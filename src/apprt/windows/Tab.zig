/// Tab abstraction for the Windows apprt multi-tab architecture.
///
/// Each Tab owns a child HWND (WS_CHILD) within the main window's client area
/// and a Surface that renders into it via its own WGL context. The child HWND
/// is shown/hidden based on whether the tab is active.
const Tab = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const configpkg = @import("../../config.zig");
const CoreApp = @import("../../App.zig");
const Surface = @import("Surface.zig");

const log = std.log.scoped(.windows_tab);

// ---------------------------------------------------------------------------
// Win32 types and constants
// ---------------------------------------------------------------------------

const HWND = std.os.windows.HWND;
const HINSTANCE = std.os.windows.HINSTANCE;
const LPCWSTR = [*:0]const u16;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const LONG = i32;
const LONG_PTR = isize;
const LRESULT = isize;
const WPARAM = usize;
const LPARAM = isize;
const COLORREF = u32;

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_CLIPCHILDREN: u32 = 0x02000000;
const CS_OWNDC: u32 = 0x0020;
const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;
const SW_SHOW: i32 = 5;
const SW_HIDE: i32 = 0;
const GWLP_USERDATA: i32 = -21;

extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: LPCWSTR,
    lpWindowName: ?LPCWSTR,
    dwStyle: DWORD,
    x: i32,
    y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?*anyopaque,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.c) ?HWND;
extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.c) BOOL;
extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
extern "user32" fn MoveWindow(hwnd: HWND, x: i32, y: i32, nWidth: i32, nHeight: i32, bRepaint: BOOL) callconv(.c) BOOL;
extern "user32" fn SetFocus(hwnd: HWND) callconv(.c) ?HWND;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) u16;
extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.c) LRESULT,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: ?*anyopaque = null,
};

// ---------------------------------------------------------------------------
// Tab bar constants
// ---------------------------------------------------------------------------

/// Height of the tab bar area in pixels.
pub const TAB_BAR_HEIGHT: i32 = 30;

/// Width of each tab item in the tab bar.
pub const TAB_ITEM_WIDTH: i32 = 150;

/// Class registered flag (module-level, registered once).
var class_registered: bool = false;

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// The Surface that renders terminal content in this tab.
surface: Surface = undefined,

/// Whether the surface has been initialized.
surface_initialized: bool = false,

/// Tab title (displayed in the tab bar). Null means use surface title.
title: ?[:0]const u8 = null,

/// Optional tab color for visual differentiation (COLORREF: 0x00BBGGRR).
color: ?COLORREF = null,

/// The child HWND that the surface renders into.
child_hwnd: ?HWND = null,

/// Whether this tab is currently active/visible.
active: bool = false,

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Initialize a tab: register the child window class (once), create a child
/// HWND within the parent, and initialize the Surface with its own WGL context.
pub fn init(
    self: *Tab,
    parent_hwnd: HWND,
    alloc: Allocator,
    config: *const configpkg.Config,
    core_app: *CoreApp,
    app: *@import("App.zig"),
    client_width: i32,
    client_height: i32,
) !void {
    const hinstance = GetModuleHandleW(null);

    // Register the child window class once.
    if (!class_registered) {
        const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyTabChild");
        const wc = WNDCLASSEXW{
            .style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc = childWndProc,
            .hInstance = hinstance,
            .lpszClassName = class_name,
        };
        _ = RegisterClassExW(&wc);
        class_registered = true;
    }

    // Create a child HWND positioned below the tab bar.
    const content_y = TAB_BAR_HEIGHT;
    const content_h = @max(client_height - TAB_BAR_HEIGHT, 1);

    const child_class = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyTabChild");
    const child = CreateWindowExW(
        0,
        child_class,
        null,
        WS_CHILD | WS_CLIPCHILDREN,
        0,
        content_y,
        client_width,
        content_h,
        parent_hwnd,
        null,
        hinstance,
        null,
    ) orelse {
        log.err("CreateWindowExW failed for tab child HWND", .{});
        return error.WindowCreationFailed;
    };

    self.* = .{
        .child_hwnd = child,
        .active = false,
        .surface = undefined,
        .surface_initialized = false,
        .title = null,
        .color = null,
    };

    // Initialize the surface with its own WGL context on the child HWND.
    try self.surface.init(app, config, core_app, child);
    self.surface_initialized = true;

    log.info("Tab initialized with child HWND, content area {}x{}", .{ client_width, content_h });

    _ = alloc;
}

/// Deinitialize the tab: deinit surface, destroy child HWND.
pub fn deinit(self: *Tab) void {
    if (self.surface_initialized) {
        self.surface.deinit();
        self.surface_initialized = false;
    }
    if (self.child_hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.child_hwnd = null;
    }
}

// ---------------------------------------------------------------------------
// Visibility
// ---------------------------------------------------------------------------

/// Show this tab's child HWND and set focus to it.
pub fn show(self: *Tab) void {
    if (self.child_hwnd) |hwnd| {
        _ = ShowWindow(hwnd, SW_SHOW);
        _ = SetFocus(hwnd);
    }
    self.active = true;
}

/// Hide this tab's child HWND.
pub fn hide(self: *Tab) void {
    if (self.child_hwnd) |hwnd| {
        _ = ShowWindow(hwnd, SW_HIDE);
    }
    self.active = false;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// Resize the child HWND to fill the client area below the tab bar.
pub fn resize(self: *Tab, client_width: i32, client_height: i32) void {
    if (self.child_hwnd) |hwnd| {
        const content_y = TAB_BAR_HEIGHT;
        const content_h = @max(client_height - TAB_BAR_HEIGHT, 1);
        _ = MoveWindow(hwnd, 0, content_y, client_width, content_h, 1);
    }
}

/// Get the display title for this tab.
pub fn getTitle(self: *const Tab) []const u8 {
    if (self.title) |t| return t;
    if (self.surface_initialized) {
        if (self.surface.title) |t| return t;
    }
    return "Terminal";
}

// ---------------------------------------------------------------------------
// Child window procedure
// ---------------------------------------------------------------------------

fn childWndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    // The child HWND is a simple container. All input messages are forwarded
    // to the parent by DefWindowProcW's default child handling, or handled
    // by the parent's wndProc which routes to the active tab's surface.
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}
