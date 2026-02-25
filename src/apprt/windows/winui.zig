//! Manual vtable definitions for WinUI 3 interfaces not covered by zigwin32.
//!
//! CRITICAL: WinRT interfaces inherit from IInspectable (6 base methods),
//! not IUnknown (3 methods). Only ISwapChainPanelNative inherits from
//! IUnknown (it is a classic COM interface, not WinRT).
//! Getting this wrong shifts all vtable offsets and causes silent corruption.

const com = @import("com.zig");
const GUID = com.GUID;
const HRESULT = com.HRESULT;
const HSTRING = com.HSTRING;
const HSTRING_HEADER = com.HSTRING_HEADER;
const IInspectable = com.IInspectable;
const IUnknown = com.IUnknown;

// ---------------------------------------------------------------------------
// IApplicationStatics — activation factory for Microsoft.UI.Xaml.Application
// ---------------------------------------------------------------------------

pub const IApplicationStatics = extern struct {
    vtable: *const VTable,

    pub const class_name = com.L("Microsoft.UI.Xaml.Application");

    pub const IID = GUID{
        .data1 = 0x06499997,
        .data2 = 0xf7b4,
        .data3 = 0x45fe,
        .data4 = .{ 0xb7, 0x63, 0x75, 0x77, 0xd1, 0xd3, 0xcb, 0x4a },
    };

    pub const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*IApplicationStatics, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IApplicationStatics) callconv(.c) u32,
        Release: *const fn (*IApplicationStatics) callconv(.c) u32,
        // IInspectable (3 methods)
        GetIids: *const fn (*IApplicationStatics, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IApplicationStatics, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IApplicationStatics, *i32) callconv(.c) HRESULT,
        // IApplicationStatics methods
        Start: *const fn (*IApplicationStatics, *anyopaque) callconv(.c) HRESULT,
    };
};

// ---------------------------------------------------------------------------
// IWindow — WinUI 3 Window interface
// ---------------------------------------------------------------------------

pub const IWindow = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*IWindow, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IWindow) callconv(.c) u32,
        Release: *const fn (*IWindow) callconv(.c) u32,
        // IInspectable (3 methods)
        GetIids: *const fn (*IWindow, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IWindow, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IWindow, *i32) callconv(.c) HRESULT,
        // IWindow methods
        get_Content: *const fn (*IWindow, *?*IInspectable) callconv(.c) HRESULT,
        put_Content: *const fn (*IWindow, ?*IInspectable) callconv(.c) HRESULT,
        Activate: *const fn (*IWindow) callconv(.c) HRESULT,
        Close: *const fn (*IWindow) callconv(.c) HRESULT,
    };
};

// ---------------------------------------------------------------------------
// ISwapChainPanelNative — classic COM (inherits IUnknown, NOT IInspectable)
// ---------------------------------------------------------------------------

pub const ISwapChainPanelNative = extern struct {
    vtable: *const VTable,

    pub const IID = GUID{
        .data1 = 0x63aad0b8,
        .data2 = 0x7c24,
        .data3 = 0x40ff,
        .data4 = .{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 },
    };

    pub const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*ISwapChainPanelNative, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*ISwapChainPanelNative) callconv(.c) u32,
        Release: *const fn (*ISwapChainPanelNative) callconv(.c) u32,
        // ISwapChainPanelNative methods
        SetSwapChain: *const fn (*ISwapChainPanelNative, ?*anyopaque) callconv(.c) HRESULT,
    };
};

// ---------------------------------------------------------------------------
// IFrameworkElement — WinUI 3 FrameworkElement interface
// ---------------------------------------------------------------------------

pub const IFrameworkElement = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*IFrameworkElement, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*IFrameworkElement) callconv(.c) u32,
        Release: *const fn (*IFrameworkElement) callconv(.c) u32,
        // IInspectable (3 methods)
        GetIids: *const fn (*IFrameworkElement, *u32, *?[*]GUID) callconv(.c) HRESULT,
        GetRuntimeClassName: *const fn (*IFrameworkElement, *?HSTRING) callconv(.c) HRESULT,
        GetTrustLevel: *const fn (*IFrameworkElement, *i32) callconv(.c) HRESULT,
        // IFrameworkElement methods
        get_Width: *const fn (*IFrameworkElement, *f64) callconv(.c) HRESULT,
        put_Width: *const fn (*IFrameworkElement, f64) callconv(.c) HRESULT,
        get_Height: *const fn (*IFrameworkElement, *f64) callconv(.c) HRESULT,
        put_Height: *const fn (*IFrameworkElement, f64) callconv(.c) HRESULT,
        get_ActualWidth: *const fn (*IFrameworkElement, *f64) callconv(.c) HRESULT,
        get_ActualHeight: *const fn (*IFrameworkElement, *f64) callconv(.c) HRESULT,
    };
};
