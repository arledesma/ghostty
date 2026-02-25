/// Tab abstraction for the Windows apprt multi-tab architecture.
///
/// Each Tab owns a SplitTree root node (binary tree of split panes).
/// Leaf nodes in the tree are Surfaces, each with its own child HWND
/// and WGL context. The tab's child HWND is the parent for all split
/// surface HWNDs.
const Tab = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const configpkg = @import("../../config.zig");
const CoreApp = @import("../../App.zig");
const Surface = @import("Surface.zig");
const SplitTree = @import("SplitTree.zig");

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

const RECT = SplitTree.RECT;

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
extern "user32" fn SetWindowLongPtrW(hwnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.c) LONG_PTR;
extern "user32" fn GetWindowLongPtrW(hwnd: HWND, nIndex: i32) callconv(.c) LONG_PTR;
extern "user32" fn BeginPaint(hwnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.c) ?HDC;
extern "user32" fn EndPaint(hwnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.c) BOOL;
extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.c) i32;
extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.c) ?HBRUSH;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.c) BOOL;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

const HDC = *anyopaque;
const HBRUSH = *anyopaque;
const HGDIOBJ = *anyopaque;

const PAINTSTRUCT = extern struct {
    hdc: ?HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

const WM_PAINT: u32 = 0x000F;

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

/// The SplitTree root node. All surfaces live as leaves in this tree.
root: ?*SplitTree.Node = null,

/// The currently focused surface within this tab's split tree.
focused_surface: ?*Surface = null,

/// Tab title (displayed in the tab bar). Null means use surface title.
title: ?[:0]const u8 = null,

/// Optional tab color for visual differentiation (COLORREF: 0x00BBGGRR).
color: ?COLORREF = null,

/// The child HWND that contains all split surface HWNDs.
child_hwnd: ?HWND = null,

/// Whether this tab is currently active/visible.
active: bool = false,

/// Whether the focused surface is zoomed to fill the entire tab area.
zoomed: bool = false,

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Initialize a tab: register the child window class (once), create a child
/// HWND within the parent, and initialize the first Surface with its own WGL context.
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
        .root = null,
        .focused_surface = null,
        .title = null,
        .color = null,
        .zoomed = false,
    };

    // Store a back-pointer to this Tab on the child HWND so childWndProc
    // can retrieve it (e.g. for WM_PAINT scrollbar painting).
    _ = SetWindowLongPtrW(child, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(self))));

    // Create and initialize the first surface.
    const surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);

    try surface.init(app, config, core_app, child);

    // Create a leaf node wrapping the surface.
    self.root = try SplitTree.create(alloc, surface);
    self.focused_surface = surface;

    log.info("Tab initialized with child HWND and SplitTree root, content area {}x{}", .{ client_width, content_h });
}

/// Deinitialize the tab: deinit all surfaces in the tree, destroy child HWND.
pub fn deinit(self: *Tab, alloc: Allocator) void {
    if (self.root) |root| {
        SplitTree.deinitAll(root, alloc);
        alloc.destroy(root);
        self.root = null;
    }
    self.focused_surface = null;
    if (self.child_hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.child_hwnd = null;
    }
}

// ---------------------------------------------------------------------------
// Visibility
// ---------------------------------------------------------------------------

/// Show this tab's child HWND and set focus to the focused surface.
pub fn show(self: *Tab) void {
    if (self.child_hwnd) |hwnd| {
        _ = ShowWindow(hwnd, SW_SHOW);
    }
    if (self.focused_surface) |surface| {
        _ = SetFocus(surface.hwnd);
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

/// Resize the child HWND to fill the client area below the tab bar,
/// then re-layout all splits within it.
pub fn resize(self: *Tab, client_width: i32, client_height: i32) void {
    if (self.child_hwnd) |hwnd| {
        const content_y = TAB_BAR_HEIGHT;
        const content_h = @max(client_height - TAB_BAR_HEIGHT, 1);
        _ = MoveWindow(hwnd, 0, content_y, client_width, content_h, 1);
    }
    // Re-layout splits within the tab content area.
    if (self.root) |root| {
        if (!self.zoomed) {
            self.layoutSplits(root);
        } else if (self.focused_surface) |surface| {
            // When zoomed, only the focused surface fills the area.
            self.layoutZoomed(surface);
        }
    }
}

/// Layout the entire split tree within the tab's content area.
pub fn layoutSplits(self: *Tab, root: *SplitTree.Node) void {
    if (self.child_hwnd) |_| {
        // Content area is always 0,0 relative to the child HWND.
        // We need the child HWND dimensions.
        const rect = self.getContentRect();
        SplitTree.layout(root, rect);
    }
}

/// Get the content rect for split layout (relative to child HWND, so origin is 0,0).
fn getContentRect(self: *Tab) RECT {
    if (self.child_hwnd) |hwnd| {
        var rect: RECT = std.mem.zeroes(RECT);
        if (GetClientRect(hwnd, &rect) != 0) {
            return rect;
        }
    }
    return .{ .left = 0, .top = 0, .right = 800, .bottom = 570 };
}

extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(.c) BOOL;

/// Layout the zoomed surface to fill the entire tab content area.
pub fn layoutZoomed(self: *Tab, surface: *Surface) void {
    const rect = self.getContentRect();
    const w = rect.right - rect.left;
    const h = rect.bottom - rect.top;
    if (w > 0 and h > 0) {
        _ = MoveWindow(surface.hwnd, rect.left, rect.top, w, h, 1);
        surface.width = @intCast(@max(w, 1));
        surface.height = @intCast(@max(h, 1));
    }
}

/// Split the focused surface in the given direction, creating a new surface.
pub fn splitSurface(
    self: *Tab,
    alloc: Allocator,
    direction: SplitTree.Direction,
    new_first: bool,
    config: *const configpkg.Config,
    core_app: *CoreApp,
    app: *@import("App.zig"),
) !*Surface {
    const focused = self.focused_surface orelse return error.NoFocusedSurface;
    const root = self.root orelse return error.NoRoot;

    // Find the leaf node containing the focused surface.
    const leaf = SplitTree.findSurface(root, focused) orelse return error.SurfaceNotFound;

    // Create a new surface with its own child HWND.
    const child_hwnd = self.child_hwnd orelse return error.NoChildHwnd;
    const new_surface = try alloc.create(Surface);
    errdefer alloc.destroy(new_surface);
    try new_surface.init(app, config, core_app, child_hwnd);

    // Split the leaf node.
    try SplitTree.split(alloc, leaf, direction, new_surface, new_first);

    // Un-zoom if zoomed.
    if (self.zoomed) {
        self.zoomed = false;
        if (self.root) |r| {
            SplitTree.showAll(r, true);
        }
    }

    // Re-layout.
    if (self.root) |r| {
        self.layoutSplits(r);
    }

    // Focus the new surface.
    self.focused_surface = new_surface;
    _ = SetFocus(new_surface.hwnd);

    return new_surface;
}

/// Remove a surface from the split tree. Returns false if the tab is now empty.
pub fn removeSurface(self: *Tab, alloc: Allocator, surface: *Surface) bool {
    const root = self.root orelse return false;

    // If zoomed, un-zoom first.
    if (self.zoomed) {
        self.zoomed = false;
    }

    const new_root = SplitTree.remove(alloc, root, surface);

    // Deinit and free the surface.
    surface.deinit();
    alloc.destroy(surface);

    if (new_root) |nr| {
        self.root = nr;
        // If the removed surface was focused, focus another one.
        if (self.focused_surface == surface) {
            var buf: [64]*Surface = undefined;
            var count: usize = 0;
            SplitTree.collectSurfaces(nr, &buf, &count);
            self.focused_surface = if (count > 0) buf[0] else null;
            if (self.focused_surface) |fs| {
                _ = SetFocus(fs.hwnd);
            }
        }
        // Re-layout.
        self.layoutSplits(nr);
        return true;
    } else {
        self.root = null;
        self.focused_surface = null;
        return false;
    }
}

/// Get the display title for this tab.
pub fn getTitle(self: *const Tab) []const u8 {
    if (self.title) |t| return t;
    if (self.focused_surface) |surface| {
        if (surface.title) |t| return t;
    }
    return "Terminal";
}

/// Get the first initialized surface (for backwards compatibility).
pub fn getFirstSurface(self: *Tab) ?*Surface {
    const root = self.root orelse return null;
    var buf: [64]*Surface = undefined;
    var count: usize = 0;
    SplitTree.collectSurfaces(root, &buf, &count);
    return if (count > 0) buf[0] else null;
}

// ---------------------------------------------------------------------------
// Child window procedure
// ---------------------------------------------------------------------------

fn childWndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    if (msg == WM_PAINT) {
        // Retrieve Tab pointer from GWLP_USERDATA.
        const tab_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
        if (tab_ptr != 0) {
            const tab: *Tab = @ptrFromInt(@as(usize, @intCast(tab_ptr)));
            tab.paintScrollbars(hwnd);
            return 0;
        }
    }
    // The child HWND is a simple container. All input messages are forwarded
    // to the parent by DefWindowProcW's default child handling, or handled
    // by the parent's wndProc which routes to the active tab's surface.
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

// ---------------------------------------------------------------------------
// Scrollbar painting
// ---------------------------------------------------------------------------

/// Paint scrollbars for all visible surfaces that have scrollback content.
fn paintScrollbars(self: *Tab, hwnd: HWND) void {
    var ps: PAINTSTRUCT = std.mem.zeroes(PAINTSTRUCT);
    const hdc = BeginPaint(hwnd, &ps) orelse {
        return;
    };
    defer _ = EndPaint(hwnd, &ps);

    // Collect all visible surfaces and paint scrollbar for each that has scrollback.
    const root = self.root orelse return;
    var surfaces: [64]*Surface = undefined;
    var count: usize = 0;
    SplitTree.collectSurfaces(root, &surfaces, &count);

    for (surfaces[0..count]) |surface| {
        if (surface.scroll_total > surface.scroll_view_len) {
            paintSurfaceScrollbar(hdc, surface);
        }
    }
}

/// Paint a scrollbar overlay on the right edge of a surface's area.
fn paintSurfaceScrollbar(hdc: HDC, surface: *Surface) void {
    const SCROLLBAR_WIDTH: i32 = 8;

    // Get the surface's area within the child HWND.
    var rect: RECT = std.mem.zeroes(RECT);
    if (GetClientRect(surface.hwnd, &rect) == 0) return;

    const track_right = rect.right;
    const track_left = track_right - SCROLLBAR_WIDTH;
    const track_top = rect.top;
    const track_bottom = rect.bottom;
    const track_height = track_bottom - track_top;
    if (track_height <= 0) return;

    // Paint track (dark gray background).
    const track_rect = RECT{
        .left = track_left,
        .top = track_top,
        .right = track_right,
        .bottom = track_bottom,
    };
    const track_brush = CreateSolidBrush(0x00333333) orelse return;
    defer _ = DeleteObject(@ptrCast(track_brush));
    _ = FillRect(hdc, &track_rect, track_brush);

    // Calculate thumb position and size.
    const total = surface.scroll_total;
    const view_len = surface.scroll_view_len;
    const offset = surface.scroll_offset;
    if (total == 0) return;

    // Thumb size proportional to view_len / total, minimum 20px.
    const thumb_height_f: f64 = @as(f64, @floatFromInt(view_len)) / @as(f64, @floatFromInt(total)) * @as(f64, @floatFromInt(track_height));
    const thumb_height: i32 = @intFromFloat(@max(thumb_height_f, 20.0));

    // Thumb position: offset is distance from bottom.
    // When offset=0, thumb is at the bottom. When offset=total-view_len, thumb is at the top.
    const scrollable = if (total > view_len) total - view_len else 0;
    const thumb_pos_f: f64 = if (scrollable > 0)
        @as(f64, @floatFromInt(scrollable - offset)) / @as(f64, @floatFromInt(scrollable)) * @as(f64, @floatFromInt(track_height - thumb_height))
    else
        0.0;
    const thumb_top: i32 = track_top + @as(i32, @intFromFloat(thumb_pos_f));
    const thumb_bottom: i32 = @min(thumb_top + thumb_height, track_bottom);

    // Paint thumb (lighter gray).
    const thumb_rect = RECT{
        .left = track_left,
        .top = thumb_top,
        .right = track_right,
        .bottom = thumb_bottom,
    };
    const thumb_brush = CreateSolidBrush(0x00888888) orelse return;
    defer _ = DeleteObject(@ptrCast(thumb_brush));
    _ = FillRect(hdc, &thumb_rect, thumb_brush);
}
