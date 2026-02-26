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

// ---------------------------------------------------------------------------
// WinRT Toast Notification interfaces
// ---------------------------------------------------------------------------

/// IToastNotificationManagerStatics — factory for creating toast notifiers.
/// IID: {50ac103f-d235-4598-bbef-98fe4d1a3ad4}
pub const IToastNotificationManagerStatics = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0x50ac103f,
        .data2 = 0xd235,
        .data3 = 0x4598,
        .data4 = .{ 0xbb, 0xef, 0x98, 0xfe, 0x4d, 0x1a, 0x3a, 0xd4 },
    };

    pub const VTable = extern struct {
        // IUnknown (3)
        QueryInterface: *const fn (*IToastNotificationManagerStatics, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IToastNotificationManagerStatics) callconv(.c) u32,
        Release: *const fn (*IToastNotificationManagerStatics) callconv(.c) u32,
        // IInspectable (3)
        GetIids: *const fn (*IToastNotificationManagerStatics, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IToastNotificationManagerStatics, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IToastNotificationManagerStatics, *i32) callconv(.c) HRESULT,
        // IToastNotificationManagerStatics methods
        CreateToastNotifier: *const fn (*IToastNotificationManagerStatics, *?*IToastNotifier) callconv(.c) HRESULT,
        CreateToastNotifierWithId: *const fn (*IToastNotificationManagerStatics, HSTRING, *?*IToastNotifier) callconv(.c) HRESULT,
    };
};

/// IToastNotifier — shows toast notifications.
/// IID: {75927b93-03f3-41ec-91d3-6e5bac1b38e3}
pub const IToastNotifier = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0x75927b93,
        .data2 = 0x03f3,
        .data3 = 0x41ec,
        .data4 = .{ 0x91, 0xd3, 0x6e, 0x5b, 0xac, 0x1b, 0x38, 0xe3 },
    };

    pub const VTable = extern struct {
        // IUnknown (3)
        QueryInterface: *const fn (*IToastNotifier, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IToastNotifier) callconv(.c) u32,
        Release: *const fn (*IToastNotifier) callconv(.c) u32,
        // IInspectable (3)
        GetIids: *const fn (*IToastNotifier, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IToastNotifier, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IToastNotifier, *i32) callconv(.c) HRESULT,
        // IToastNotifier methods
        Show: *const fn (*IToastNotifier, *IToastNotification) callconv(.c) HRESULT,
    };
};

/// IToastNotification — represents a single toast notification.
/// IID: {997e2675-059e-4e60-8b06-1760917c8b80}
pub const IToastNotification = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0x997e2675,
        .data2 = 0x059e,
        .data3 = 0x4e60,
        .data4 = .{ 0x8b, 0x06, 0x17, 0x60, 0x91, 0x7c, 0x8b, 0x80 },
    };

    pub const VTable = extern struct {
        // IUnknown (3)
        QueryInterface: *const fn (*IToastNotification, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IToastNotification) callconv(.c) u32,
        Release: *const fn (*IToastNotification) callconv(.c) u32,
        // IInspectable (3)
        GetIids: *const fn (*IToastNotification, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IToastNotification, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IToastNotification, *i32) callconv(.c) HRESULT,
    };
};

/// IToastNotificationFactory — creates IToastNotification instances from XML.
/// IID: {04124b20-82c6-4229-b109-fd9ed4662b53}
pub const IToastNotificationFactory = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0x04124b20,
        .data2 = 0x82c6,
        .data3 = 0x4229,
        .data4 = .{ 0xb1, 0x09, 0xfd, 0x9e, 0xd4, 0x66, 0x2b, 0x53 },
    };

    pub const VTable = extern struct {
        // IUnknown (3)
        QueryInterface: *const fn (*IToastNotificationFactory, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IToastNotificationFactory) callconv(.c) u32,
        Release: *const fn (*IToastNotificationFactory) callconv(.c) u32,
        // IInspectable (3)
        GetIids: *const fn (*IToastNotificationFactory, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IToastNotificationFactory, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IToastNotificationFactory, *i32) callconv(.c) HRESULT,
        // IToastNotificationFactory methods
        CreateToastNotification: *const fn (*IToastNotificationFactory, *IXmlDocument, *?*IToastNotification) callconv(.c) HRESULT,
    };
};

/// IXmlDocument — represents an XML DOM document (Windows.Data.Xml.Dom.XmlDocument).
/// IID: {f7f3a506-1e87-42d6-bcfb-b8c809fa5494}
pub const IXmlDocument = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0xf7f3a506,
        .data2 = 0x1e87,
        .data3 = 0x42d6,
        .data4 = .{ 0xbc, 0xfb, 0xb8, 0xc8, 0x09, 0xfa, 0x54, 0x94 },
    };

    pub const VTable = extern struct {
        // IUnknown (3)
        QueryInterface: *const fn (*IXmlDocument, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IXmlDocument) callconv(.c) u32,
        Release: *const fn (*IXmlDocument) callconv(.c) u32,
        // IInspectable (3)
        GetIids: *const fn (*IXmlDocument, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IXmlDocument, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IXmlDocument, *i32) callconv(.c) HRESULT,
    };
};

/// IXmlDocumentIO — provides LoadXml method for loading XML from string.
/// IID: {6cd0e74e-ee65-4489-9ebf-ca43e87ba637}
pub const IXmlDocumentIO = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0x6cd0e74e,
        .data2 = 0xee65,
        .data3 = 0x4489,
        .data4 = .{ 0x9e, 0xbf, 0xca, 0x43, 0xe8, 0x7b, 0xa6, 0x37 },
    };

    pub const VTable = extern struct {
        // IUnknown (3)
        QueryInterface: *const fn (*IXmlDocumentIO, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IXmlDocumentIO) callconv(.c) u32,
        Release: *const fn (*IXmlDocumentIO) callconv(.c) u32,
        // IInspectable (3)
        GetIids: *const fn (*IXmlDocumentIO, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IXmlDocumentIO, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IXmlDocumentIO, *i32) callconv(.c) HRESULT,
        // IXmlDocumentIO methods
        LoadXml: *const fn (*IXmlDocumentIO, HSTRING) callconv(.c) HRESULT,
    };
};
