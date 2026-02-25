//! COM/WinRT bridge helpers for the Windows apprt backend.
//!
//! Provides Zig-friendly wrappers around COM/WinRT primitives:
//! GUID, HRESULT helpers, IInspectable, HSTRING utilities, ComPtr,
//! and RoInitialize/RoActivateInstance wrappers.
//!
//! All WinRT interfaces inherit from IInspectable (6 base vtable methods).
//! Classic COM interfaces inherit from IUnknown (3 base vtable methods).

const std = @import("std");

// ---------------------------------------------------------------------------
// Basic types
// ---------------------------------------------------------------------------

pub const HRESULT = i32;
pub const HSTRING = *opaque {};
pub const HSTRING_HEADER = extern struct {
    reserved: extern struct {
        reserved1: *allowzero anyopaque,
        reserved2: [2]u8,
        reserved3: [7]u32,
    },
};
pub const BOOL = i32;

/// Globally Unique Identifier used by COM to identify interfaces.
pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,

    pub fn eql(self: GUID, other: GUID) bool {
        return self.data1 == other.data1 and
            self.data2 == other.data2 and
            self.data3 == other.data3 and
            std.mem.eql(u8, &self.data4, &other.data4);
    }
};

// ---------------------------------------------------------------------------
// HRESULT helpers
// ---------------------------------------------------------------------------

pub fn succeeded(hr: HRESULT) bool {
    return hr >= 0;
}

pub const HResultError = error{HResultFail};

pub fn check(hr: HRESULT) HResultError!void {
    if (hr < 0) return error.HResultFail;
}

// ---------------------------------------------------------------------------
// IUnknown — base for classic COM interfaces (3 methods)
// ---------------------------------------------------------------------------

pub const IUnknown = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const fn (*IUnknown, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IUnknown) callconv(.c) u32,
        Release: *const fn (*IUnknown) callconv(.c) u32,
    };

    pub fn release(self: *IUnknown) u32 {
        return self.vtable.Release(self);
    }
};

// ---------------------------------------------------------------------------
// IInspectable — base for all WinRT interfaces (6 methods)
// ---------------------------------------------------------------------------

pub const IInspectable = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*IInspectable, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IInspectable) callconv(.c) u32,
        Release: *const fn (*IInspectable) callconv(.c) u32,
        // IInspectable (3 methods)
        GetIids: *const fn (*IInspectable, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IInspectable, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IInspectable, *i32) callconv(.c) HRESULT,
    };

    pub fn queryInterface(self: *IInspectable, iid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, iid, out);
    }

    pub fn release(self: *IInspectable) u32 {
        return self.vtable.Release(self);
    }
};

// ---------------------------------------------------------------------------
// ComPtr — generic COM pointer wrapper with RAII release
// ---------------------------------------------------------------------------

pub fn ComPtr(comptime T: type) type {
    return struct {
        const Self = @This();

        raw: *T,

        pub fn deinit(self: Self) void {
            // All COM objects start with an IUnknown-compatible vtable.
            // Cast to IUnknown to call Release.
            const unknown: *IUnknown = @ptrCast(self.raw);
            _ = unknown.release();
        }

        /// Query for another interface on this COM object.
        pub fn queryInterface(self: Self, comptime U: type, iid: *const GUID) HResultError!ComPtr(U) {
            const unknown: *IUnknown = @ptrCast(self.raw);
            var result: ?*anyopaque = null;
            try check(unknown.vtable.QueryInterface(unknown, iid, &result));
            return .{ .raw = @ptrCast(@alignCast(result.?)) };
        }
    };
}

// ---------------------------------------------------------------------------
// HSTRING helpers
// ---------------------------------------------------------------------------

extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsCreateStringReference(
    source: [*]const u16,
    length: u32,
    header: *HSTRING_HEADER,
    result: *HSTRING,
) callconv(.c) HRESULT;

extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsDeleteString(
    string: ?HSTRING,
) callconv(.c) HRESULT;

/// Create a stack-based reference HSTRING from a comptime-known UTF-16 literal.
/// The returned HSTRING is valid for the lifetime of the `header` it writes to.
/// No deallocation is required for reference strings.
pub fn hstring(literal: [:0]const u16, header: *HSTRING_HEADER) HResultError!HSTRING {
    var result: HSTRING = undefined;
    try check(WindowsCreateStringReference(
        literal.ptr,
        @intCast(literal.len),
        header,
        &result,
    ));
    return result;
}

pub fn deleteString(string: ?HSTRING) void {
    _ = WindowsDeleteString(string);
}

// ---------------------------------------------------------------------------
// WinRT activation: RoInitialize, RoActivateInstance, RoGetActivationFactory
// ---------------------------------------------------------------------------

const RO_INIT_MULTITHREADED: u32 = 1;

extern "api-ms-win-core-winrt-l1-1-0" fn RoInitialize(
    init_type: u32,
) callconv(.c) HRESULT;

extern "api-ms-win-core-winrt-l1-1-0" fn RoUninitialize() callconv(.c) void;

extern "api-ms-win-core-winrt-l1-1-0" fn RoActivateInstance(
    class_id: HSTRING,
    instance: *?*IInspectable,
) callconv(.c) HRESULT;

extern "api-ms-win-core-winrt-l1-1-0" fn RoGetActivationFactory(
    class_id: HSTRING,
    iid: *const GUID,
    factory: *?*anyopaque,
) callconv(.c) HRESULT;

pub fn roInitialize() HResultError!void {
    const hr = RoInitialize(RO_INIT_MULTITHREADED);
    // S_OK (0) or S_FALSE (1, already initialized) are both acceptable.
    if (hr < 0) return error.HResultFail;
}

pub fn roUninitialize() void {
    RoUninitialize();
}

pub fn activateInstance(class_name: HSTRING) HResultError!*IInspectable {
    var instance: ?*IInspectable = null;
    try check(RoActivateInstance(class_name, &instance));
    return instance orelse return error.HResultFail;
}

pub fn getActivationFactory(class_name: HSTRING, iid: *const GUID) HResultError!*anyopaque {
    var factory: ?*anyopaque = null;
    try check(RoGetActivationFactory(class_name, iid, &factory));
    return factory orelse return error.HResultFail;
}

// ---------------------------------------------------------------------------
// Wide-string literal helper
// ---------------------------------------------------------------------------

/// Converts a comptime ASCII string to a UTF-16 null-terminated array.
/// Useful for WinRT class name constants.
pub fn L(comptime str: []const u8) [:0]const u16 {
    return comptime blk: {
        var result: [str.len:0]u16 = undefined;
        for (str, 0..) |c, i| {
            result[i] = c;
        }
        const final = result;
        break :blk &final;
    };
}
