/// Windows apprt backend (Win32 HWND + WGL OpenGL) with multi-tab support.
///
/// Creates a native Win32 window with a custom tab bar rendered in the
/// titlebar area via DwmExtendFrameIntoClientArea. Manages an ArrayList
/// of Tabs, each with its own child HWND and WGL context.
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const CoreApp = @import("../../App.zig");
const CoreConfig = configpkg.Config;
const com = @import("com.zig");
const wgl = @import("wgl.zig");
const Surface = @import("Surface.zig");
const SearchOverlay = @import("SearchOverlay.zig");
const Tab = @import("Tab.zig");

const log = std.log.scoped(.windows);

// ---------------------------------------------------------------------------
// Win32 types and constants
// ---------------------------------------------------------------------------

const HWND = wgl.HWND;
const LRESULT = isize;
const WPARAM = usize;
const LPARAM = isize;
const HINSTANCE = std.os.windows.HINSTANCE;
const LPCWSTR = [*:0]const u16;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const LONG = i32;
const LONG_PTR = isize;

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    w_param: WPARAM,
    l_param: LPARAM,
    time: u32,
    pt: extern struct { x: i32, y: i32 },
};

const WINDOWPLACEMENT = extern struct {
    length: u32 = @sizeOf(WINDOWPLACEMENT),
    flags: u32 = 0,
    showCmd: u32 = 0,
    ptMinPosition: extern struct { x: LONG, y: LONG } = .{ .x = 0, .y = 0 },
    ptMaxPosition: extern struct { x: LONG, y: LONG } = .{ .x = 0, .y = 0 },
    rcNormalPosition: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

const MONITORINFO = extern struct {
    cbSize: u32 = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    rcWork: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    dwFlags: u32 = 0,
};

const PAINTSTRUCT = extern struct {
    hdc: ?HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

const HDC = *anyopaque;
const HBRUSH = *anyopaque;
const HFONT = *anyopaque;
const HGDIOBJ = *anyopaque;

const MARGINS = extern struct {
    cxLeftWidth: i32,
    cxRightWidth: i32,
    cyTopHeight: i32,
    cyBottomHeight: i32,
};

const WM_QUIT: u32 = 0x0012;
const WM_CLOSE: u32 = 0x0010;
const WM_DESTROY: u32 = 0x0002;
const WM_SIZE: u32 = 0x0005;
const WM_SIZING: u32 = 0x0214;
const WM_PAINT: u32 = 0x000F;
const WM_NCHITTEST: u32 = 0x0084;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_SYSKEYDOWN: u32 = 0x0104;
const WM_SYSKEYUP: u32 = 0x0105;
const WM_CHAR: u32 = 0x0102;
const WM_SYSCHAR: u32 = 0x0106;
const WM_DPICHANGED: u32 = 0x02E0;
const WM_SETTINGCHANGE: u32 = 0x001A;

// Mouse messages
const WM_LBUTTONDOWN: u32 = 0x0201;
const WM_LBUTTONUP: u32 = 0x0202;
const WM_RBUTTONDOWN: u32 = 0x0204;
const WM_RBUTTONUP: u32 = 0x0205;
const WM_MBUTTONDOWN: u32 = 0x0207;
const WM_MBUTTONUP: u32 = 0x0208;
const WM_MOUSEMOVE: u32 = 0x0200;
const WM_MOUSEWHEEL: u32 = 0x020A;
const WM_SETFOCUS: u32 = 0x0007;
const WM_KILLFOCUS: u32 = 0x0008;

const CS_OWNDC: u32 = 0x0020;
const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const WS_POPUP: u32 = 0x80000000;
const WS_VISIBLE: u32 = 0x10000000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: i32 = 5;
const IDC_ARROW: usize = 32512;

/// Custom message to wake up GetMessageW when core needs attention.
const WM_APP_WAKEUP: u32 = 0x8000; // WM_APP range

const GWLP_USERDATA: i32 = -21;
const GWL_STYLE: i32 = -16;

// WM_SIZING wParam direction values
const WMSZ_LEFT: usize = 1;
const WMSZ_RIGHT: usize = 2;
const WMSZ_TOP: usize = 3;
const WMSZ_TOPLEFT: usize = 4;
const WMSZ_TOPRIGHT: usize = 5;
const WMSZ_BOTTOM: usize = 6;
const WMSZ_BOTTOMLEFT: usize = 7;
const WMSZ_BOTTOMRIGHT: usize = 8;

// SetWindowPos flags
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOSIZE: u32 = 0x0001;
const SWP_FRAMECHANGED: u32 = 0x0020;

// DwmSetWindowAttribute constants
const DWMWA_USE_IMMERSIVE_DARK_MODE: u32 = 20;

// Registry constants
const HKEY_CURRENT_USER: usize = 0x80000001;
const KEY_READ: u32 = 0x20019;

// Monitor constants
const MONITOR_DEFAULTTONEAREST: u32 = 0x00000002;

// HWND_TOP for SetWindowPos
const HWND_TOP: ?HWND = null;

// WM_NCHITTEST return values
const HTCAPTION: LRESULT = 2;
const HTCLIENT: LRESULT = 1;

// GDI constants
const TRANSPARENT: i32 = 1;
const NULL_BRUSH: i32 = 5;

// ---------------------------------------------------------------------------
// Win32 function imports
// ---------------------------------------------------------------------------

extern "user32" fn GetMessageW(msg: *MSG, hwnd: ?HWND, filter_min: u32, filter_max: u32) callconv(.c) BOOL;
extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.c) BOOL;
extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.c) LRESULT;
extern "user32" fn PostMessageW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) BOOL;
extern "user32" fn RegisterClassExW(lpWndClass: *const wgl.WNDCLASSEXW) callconv(.c) u16;
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
extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.c) BOOL;
extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.c) void;
extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: usize) callconv(.c) ?*anyopaque;
extern "user32" fn SetWindowLongPtrW(hwnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.c) LONG_PTR;
extern "user32" fn GetWindowLongPtrW(hwnd: HWND, nIndex: i32) callconv(.c) LONG_PTR;
extern "user32" fn SetWindowPos(
    hwnd: HWND,
    hWndInsertAfter: ?HWND,
    x: i32,
    y: i32,
    cx: i32,
    cy: i32,
    uFlags: u32,
) callconv(.c) BOOL;
extern "user32" fn SetWindowTextW(hwnd: HWND, lpString: LPCWSTR) callconv(.c) BOOL;
extern "user32" fn GetWindowRect(hwnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(.c) u32;
extern "user32" fn GetWindowPlacement(hwnd: HWND, lpwndpl: *WINDOWPLACEMENT) callconv(.c) BOOL;
extern "user32" fn SetWindowPlacement(hwnd: HWND, lpwndpl: *const WINDOWPLACEMENT) callconv(.c) BOOL;
extern "user32" fn MonitorFromWindow(hwnd: HWND, dwFlags: u32) callconv(.c) ?*anyopaque;
extern "user32" fn GetMonitorInfoW(hMonitor: *anyopaque, lpmi: *MONITORINFO) callconv(.c) BOOL;
extern "user32" fn InvalidateRect(hwnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.c) BOOL;
extern "user32" fn BeginPaint(hwnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.c) ?HDC;
extern "user32" fn EndPaint(hwnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.c) BOOL;
extern "user32" fn SetFocus(hwnd: HWND) callconv(.c) ?HWND;
extern "user32" fn SetCapture(hwnd: HWND) callconv(.c) ?HWND;
extern "user32" fn ReleaseCapture() callconv(.c) BOOL;
extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.c) i16;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

// DPI awareness
extern "user32" fn SetProcessDpiAwarenessContext(value: isize) callconv(.c) BOOL;
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;

// DPI-aware window rect adjustment
extern "user32" fn AdjustWindowRectExForDpi(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD, dpi: u32) callconv(.c) BOOL;

// DWM
extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: u32, pvAttribute: *const anyopaque, cbAttribute: u32) callconv(.c) i32;
extern "dwmapi" fn DwmExtendFrameIntoClientArea(hwnd: HWND, pMarInset: *const MARGINS) callconv(.c) i32;

// GDI
extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.c) i32;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.c) i32;
extern "gdi32" fn SetTextColor(hdc: HDC, color: u32) callconv(.c) u32;
extern "gdi32" fn TextOutW(hdc: HDC, x: i32, y: i32, lpString: [*]const u16, c: i32) callconv(.c) BOOL;
extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.c) ?HBRUSH;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.c) BOOL;
extern "gdi32" fn GetStockObject(i: i32) callconv(.c) ?HGDIOBJ;

// Registry for theme detection
extern "advapi32" fn RegOpenKeyExW(hKey: usize, lpSubKey: LPCWSTR, ulOptions: u32, samDesired: u32, phkResult: *usize) callconv(.c) i32;
extern "advapi32" fn RegQueryValueExW(hKey: usize, lpValueName: LPCWSTR, lpReserved: ?*u32, lpType: ?*u32, lpData: ?[*]u8, lpcbData: *u32) callconv(.c) i32;
extern "advapi32" fn RegCloseKey(hKey: usize) callconv(.c) i32;

// Shell
extern "shell32" fn ShellExecuteW(hwnd: ?HWND, lpOperation: ?LPCWSTR, lpFile: LPCWSTR, lpParameters: ?LPCWSTR, lpDirectory: ?LPCWSTR, nShowCmd: i32) callconv(.c) isize;

// Bell and flash
extern "user32" fn MessageBeep(uType: u32) callconv(.c) BOOL;
extern "user32" fn FlashWindow(hwnd: HWND, bInvert: BOOL) callconv(.c) BOOL;

// Cursor
extern "user32" fn SetCursor(hCursor: ?*anyopaque) callconv(.c) ?*anyopaque;
const IDC_HAND: usize = 32649;

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

/// All open tabs.
tabs: std.ArrayList(Tab) = .{},

/// Index of the currently active/visible tab.
active_tab: usize = 0,

hwnd: ?HWND = null,
core_app: *CoreApp = undefined,
alloc: Allocator = undefined,
config: *const configpkg.Config = undefined,

/// Owned config loaded at startup for the initial surface.
owned_config: ?configpkg.Config = null,

/// Fullscreen state.
is_fullscreen: bool = false,
saved_style: LONG = 0,
saved_placement: WINDOWPLACEMENT = .{},

/// Tab drag state for reordering.
drag_active: bool = false,
drag_source_index: usize = 0,
drag_start_x: i32 = 0,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    const alloc = core_app.alloc;
    self.alloc = alloc;
    self.core_app = core_app;
    self.tabs = .{};
    self.active_tab = 0;
    self.drag_active = false;

    // Set per-monitor DPI awareness V2 before any window creation.
    _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    // Initialize COM runtime (needed for DirectWrite font discovery).
    try com.roInitialize();
    log.info("Windows apprt initialized (COM ready)", .{});

    const hinstance = GetModuleHandleW(null);

    // Register window class with CS_OWNDC for persistent DC.
    const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindow");
    const wc = wgl.WNDCLASSEXW{
        .style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW,
        .lpfnWndProc = wndProc,
        .hInstance = hinstance,
        .hCursor = LoadCursorW(null, IDC_ARROW),
        .lpszClassName = class_name,
    };
    _ = RegisterClassExW(&wc);

    const window_title = comptime std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");
    const hwnd = CreateWindowExW(
        0,
        class_name,
        window_title,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        800,
        600,
        null,
        null,
        hinstance,
        null,
    ) orelse {
        log.err("CreateWindowExW failed", .{});
        return error.WindowCreationFailed;
    };
    self.hwnd = hwnd;

    // Store self pointer in HWND user data so wndProc can retrieve it.
    _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(self))));

    // Extend the frame into the client area for the tab bar.
    const margins = MARGINS{
        .cxLeftWidth = 0,
        .cxRightWidth = 0,
        .cyTopHeight = Tab.TAB_BAR_HEIGHT,
        .cyBottomHeight = 0,
    };
    _ = DwmExtendFrameIntoClientArea(hwnd, &margins);

    // Apply initial titlebar theme based on system setting.
    applyThemeToTitlebar(hwnd, detectSystemThemeIsDark());

    _ = ShowWindow(hwnd, SW_SHOW);
    log.info("Win32 window created and shown with tab bar", .{});
}

pub fn terminate(self: *App) void {
    // Deinit all tabs.
    for (self.tabs.items) |*tab| {
        tab.deinit(self.alloc);
    }
    self.tabs.deinit(self.alloc);
    if (self.owned_config) |*c| c.deinit();
    if (self.hwnd) |hwnd| _ = DestroyWindow(hwnd);
    self.hwnd = null;
    com.roUninitialize();
}

pub fn run(self: *App) !void {
    var msg: MSG = std.mem.zeroes(MSG);

    // Queue the initial window creation, mirroring GTK's activate signal.
    _ = self.core_app.mailbox.push(.{
        .new_window = .{},
    }, .{ .forever = {} });

    // Perform an initial tick to process the new_window message before
    // entering the blocking GetMessageW loop.
    try self.core_app.tick(self);

    // Main message loop: GetMessageW blocks until a message arrives.
    while (true) {
        const ret = GetMessageW(&msg, null, 0, 0);
        if (ret == 0) break; // WM_QUIT
        if (ret < 0) break; // error

        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);

        // Tick the core mailbox after processing messages.
        self.core_app.tick(self) catch |err| {
            log.err("core_app.tick error: {}", .{err});
        };
    }
}

// ---------------------------------------------------------------------------
// Tab management
// ---------------------------------------------------------------------------

/// Create a new tab, initialize its surface, and make it active.
pub fn createTab(self: *App) !void {
    const hwnd = self.hwnd orelse return error.WindowCreationFailed;

    // Get client area dimensions.
    var client_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(hwnd, &client_rect);
    const client_w: i32 = client_rect.right - client_rect.left;
    const client_h: i32 = client_rect.bottom - client_rect.top;

    // Load config if not already loaded.
    if (self.owned_config == null) {
        self.owned_config = try CoreConfig.load(self.alloc);
        self.config = &self.owned_config.?;
    }

    // Hide the current active tab if any.
    if (self.tabs.items.len > 0 and self.active_tab < self.tabs.items.len) {
        self.tabs.items[self.active_tab].hide();
    }

    // Add new tab.
    const new_index = self.tabs.items.len;
    try self.tabs.append(self.alloc, .{});
    errdefer _ = self.tabs.pop();

    var tab = &self.tabs.items[new_index];
    try tab.init(hwnd, self.alloc, self.config, self.core_app, self, client_w, client_h);

    // Make the new tab active.
    self.active_tab = new_index;
    tab.show();

    // Redraw the tab bar.
    self.redrawTabBar();

    log.info("Created tab {}, total tabs: {}", .{ new_index, self.tabs.items.len });
}

/// Close the tab at the given index.
pub fn closeTab(self: *App, index: usize) !void {
    if (index >= self.tabs.items.len) return;

    // Deinit the tab (frees all surfaces in its split tree).
    self.tabs.items[index].deinit(self.alloc);
    _ = self.tabs.orderedRemove(index);

    // If no tabs remain, quit.
    if (self.tabs.items.len == 0) {
        PostQuitMessage(0);
        return;
    }

    // Adjust active_tab.
    if (self.active_tab >= self.tabs.items.len) {
        self.active_tab = self.tabs.items.len - 1;
    } else if (self.active_tab > index) {
        self.active_tab -= 1;
    }

    // Show the new active tab.
    self.tabs.items[self.active_tab].show();
    self.redrawTabBar();
}

/// Close a specific surface. If it's the last surface in a tab, close the tab.
pub fn closeSurface(self: *App, surface: *Surface) !void {
    // Find which tab contains this surface.
    for (self.tabs.items, 0..) |*tab, i| {
        if (tab.root) |root| {
            const SplitTree = @import("SplitTree.zig");
            if (SplitTree.findSurface(root, surface) != null) {
                const tab_alive = tab.removeSurface(self.alloc, surface);
                if (!tab_alive) {
                    // Tab is empty, close it.
                    _ = self.tabs.orderedRemove(i);
                    if (self.tabs.items.len == 0) {
                        PostQuitMessage(0);
                        return;
                    }
                    if (self.active_tab >= self.tabs.items.len) {
                        self.active_tab = self.tabs.items.len - 1;
                    } else if (self.active_tab > i) {
                        self.active_tab -= 1;
                    }
                    self.tabs.items[self.active_tab].show();
                    self.redrawTabBar();
                } else {
                    // Notify size change after relayout.
                    if (tab.focused_surface) |fs| {
                        fs.sizeCallback(fs.width, fs.height);
                    }
                }
                return;
            }
        }
    }
}

/// Switch to the tab at the given index.
pub fn switchToTab(self: *App, index: usize) void {
    if (index >= self.tabs.items.len) return;
    if (index == self.active_tab) return;

    // Hide current tab.
    self.tabs.items[self.active_tab].hide();

    // Show target tab.
    self.active_tab = index;
    self.tabs.items[index].show();

    // Update window title to match the active tab.
    if (self.hwnd) |hwnd| {
        const title_str = self.tabs.items[index].getTitle();
        var buf: [512]u16 = undefined;
        const len = std.unicode.utf8ToUtf16Le(&buf, title_str) catch 0;
        if (len < buf.len) {
            buf[len] = 0;
            const ptr: LPCWSTR = @ptrCast(&buf);
            _ = SetWindowTextW(hwnd, ptr);
        }
    }

    self.redrawTabBar();
}

/// Get the active tab's focused surface, if any.
fn getActiveSurface(self: *App) ?*Surface {
    if (self.tabs.items.len == 0) return null;
    if (self.active_tab >= self.tabs.items.len) return null;
    return self.tabs.items[self.active_tab].focused_surface;
}

/// Resolve an action target to a Surface. If the target is a specific surface,
/// use it directly; otherwise fall back to the active tab's focused surface.
fn getTargetSurface(self: *App, target: apprt.Target) ?*Surface {
    return switch (target) {
        .surface => |cs| cs.rt_surface,
        .app => self.getActiveSurface(),
    };
}

/// Get the active tab, if any.
fn getActiveTab(self: *App) ?*Tab {
    if (self.tabs.items.len == 0) return null;
    if (self.active_tab >= self.tabs.items.len) return null;
    return &self.tabs.items[self.active_tab];
}

/// Notify all surfaces in the active tab about their current size.
/// Called after layout so each surface can inform its core about dimension changes.
fn notifyActiveSurfaceSizes(self: *App) void {
    const tab = self.getActiveTab() orelse return;
    const root = tab.root orelse return;
    const SplitTree = @import("SplitTree.zig");
    var buf: [64]*Surface = undefined;
    var count: usize = 0;
    SplitTree.collectSurfaces(root, &buf, &count);
    for (buf[0..count]) |surface| {
        surface.sizeCallback(surface.width, surface.height);
    }
}

/// Trigger a repaint of the tab bar area.
pub fn redrawTabBar(self: *App) void {
    if (self.hwnd) |hwnd| {
        const tab_bar_rect = RECT{
            .left = 0,
            .top = 0,
            .right = 2000, // wide enough to cover any window width
            .bottom = Tab.TAB_BAR_HEIGHT,
        };
        _ = InvalidateRect(hwnd, &tab_bar_rect, 1);
    }
}

// ---------------------------------------------------------------------------
// WndProc
// ---------------------------------------------------------------------------

fn wndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    // Retrieve App pointer from GWLP_USERDATA.
    const app_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const app: ?*App = if (app_ptr != 0) @ptrFromInt(@as(usize, @intCast(app_ptr))) else null;

    switch (msg) {
        WM_CLOSE => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        WM_PAINT => {
            if (app) |a| {
                a.paintTabBar(hwnd);
            }
            return 0;
        },
        WM_NCHITTEST => {
            if (app) |a| {
                // Get cursor position in client coords.
                const x: i16 = @bitCast(@as(u16, @intCast(lparam & 0xFFFF)));
                const y: i16 = @bitCast(@as(u16, @intCast((lparam >> 16) & 0xFFFF)));

                // Convert screen coords to client coords.
                var pt = POINT{ .x = x, .y = y };
                _ = ScreenToClient(hwnd, &pt);

                // If in the tab bar area...
                if (pt.y >= 0 and pt.y < Tab.TAB_BAR_HEIGHT) {
                    // Check if over a tab item.
                    const tab_count: i32 = @intCast(a.tabs.items.len);
                    if (tab_count > 0 and pt.x >= 0 and pt.x < tab_count * Tab.TAB_ITEM_WIDTH) {
                        return HTCLIENT; // clickable tab area
                    }
                    // Empty tab bar area = draggable caption
                    return HTCAPTION;
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_SIZE => {
            if (app) |a| {
                const w: i32 = @intCast(lparam & 0xFFFF);
                const h: i32 = @intCast((lparam >> 16) & 0xFFFF);

                // Resize the active tab's child HWND and re-layout splits.
                if (a.tabs.items.len > 0 and a.active_tab < a.tabs.items.len) {
                    a.tabs.items[a.active_tab].resize(w, h);
                    // Notify all surfaces in the active tab of their new size.
                    a.notifyActiveSurfaceSizes();
                }
                a.redrawTabBar();
            }
            return 0;
        },
        WM_SIZING => {
            if (app) |a| {
                if (a.getActiveSurface()) |_| {
                    const rect_ptr: *RECT = @ptrFromInt(@as(usize, @intCast(lparam)));
                    a.snapResizeRect(rect_ptr, wparam);
                }
            }
            return 1;
        },
        WM_KEYDOWN, WM_SYSKEYDOWN, WM_KEYUP, WM_SYSKEYUP => {
            if (app) |a| {
                if (a.getActiveSurface()) |surface| {
                    const input_mod = @import("input.zig");
                    if (input_mod.translateKeyEvent(msg, wparam, lparam)) |key_event| {
                        const effect = surface.core_surface.keyCallback(key_event) catch .ignored;
                        if ((msg == WM_SYSKEYDOWN or msg == WM_SYSKEYUP) and effect == .consumed) {
                            return 0;
                        }
                    }
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_CHAR, WM_SYSCHAR => {
            return 0;
        },
        WM_DPICHANGED => {
            if (app) |a| {
                const new_dpi: u32 = @intCast(wparam & 0xFFFF);
                const suggested: *const RECT = @ptrFromInt(@as(usize, @intCast(lparam)));
                _ = SetWindowPos(
                    hwnd,
                    null,
                    suggested.left,
                    suggested.top,
                    suggested.right - suggested.left,
                    suggested.bottom - suggested.top,
                    SWP_NOZORDER | SWP_FRAMECHANGED,
                );
                // Notify all surfaces of the DPI change.
                const SplitTree = @import("SplitTree.zig");
                for (a.tabs.items) |*tab| {
                    if (tab.root) |root| {
                        var buf: [64]*Surface = undefined;
                        var count: usize = 0;
                        SplitTree.collectSurfaces(root, &buf, &count);
                        for (buf[0..count]) |surface| {
                            surface.contentScaleCallback(new_dpi);
                        }
                    }
                }
            }
            return 0;
        },
        WM_SETTINGCHANGE => {
            if (app) |a| {
                const lparam_ptr: ?[*:0]const u16 = if (lparam != 0)
                    @ptrFromInt(@as(usize, @intCast(lparam)))
                else
                    null;
                if (lparam_ptr) |setting_str| {
                    const immersive = comptime std.unicode.utf8ToUtf16LeStringLiteral("ImmersiveColorSet");
                    if (strEqlW(setting_str, immersive)) {
                        const is_dark = detectSystemThemeIsDark();
                        applyThemeToTitlebar(hwnd, is_dark);
                        const scheme: apprt.ColorScheme = if (is_dark) .dark else .light;
                        a.core_app.colorSchemeEvent(a, scheme) catch |err| {
                            log.warn("colorSchemeEvent error: {}", .{err});
                        };
                    }
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_LBUTTONDOWN => {
            if (app) |a| {
                const x: i16 = @bitCast(@as(u16, @intCast(lparam & 0xFFFF)));
                const y: i16 = @bitCast(@as(u16, @intCast((lparam >> 16) & 0xFFFF)));

                // Check if click is in the tab bar area.
                if (y >= 0 and y < Tab.TAB_BAR_HEIGHT and a.tabs.items.len > 0) {
                    const tab_index = @divTrunc(@as(usize, @intCast(@max(x, 0))), @as(usize, @intCast(Tab.TAB_ITEM_WIDTH)));
                    if (tab_index < a.tabs.items.len) {
                        a.switchToTab(tab_index);

                        // Start drag tracking.
                        a.drag_active = true;
                        a.drag_source_index = tab_index;
                        a.drag_start_x = x;
                        _ = SetCapture(hwnd);
                    }
                    return 0;
                }

                // Not in tab bar -- forward to active surface.
                a.forwardMouseButton(msg, wparam, lparam);
            }
            return 0;
        },
        WM_LBUTTONUP => {
            if (app) |a| {
                if (a.drag_active) {
                    a.drag_active = false;
                    _ = ReleaseCapture();
                    return 0;
                }
                a.forwardMouseButton(msg, wparam, lparam);
            }
            return 0;
        },
        WM_MBUTTONDOWN => {
            if (app) |a| {
                const x: i16 = @bitCast(@as(u16, @intCast(lparam & 0xFFFF)));
                const y: i16 = @bitCast(@as(u16, @intCast((lparam >> 16) & 0xFFFF)));

                // Middle-click in tab bar closes the tab.
                if (y >= 0 and y < Tab.TAB_BAR_HEIGHT and a.tabs.items.len > 0) {
                    const tab_index = @divTrunc(@as(usize, @intCast(@max(x, 0))), @as(usize, @intCast(Tab.TAB_ITEM_WIDTH)));
                    if (tab_index < a.tabs.items.len) {
                        a.closeTab(tab_index) catch |err| {
                            log.err("closeTab error from middle-click: {}", .{err});
                        };
                    }
                    return 0;
                }

                // Not in tab bar -- forward to active surface.
                a.forwardMouseButton(msg, wparam, lparam);
            }
            return 0;
        },
        WM_RBUTTONDOWN, WM_RBUTTONUP, WM_MBUTTONUP => {
            if (app) |a| {
                a.forwardMouseButton(msg, wparam, lparam);
            }
            return 0;
        },
        WM_MOUSEMOVE => {
            if (app) |a| {
                // Handle tab drag reordering. Check VK_LBUTTON state
                // defensively in case we missed a button-up event.
                if (a.drag_active) {
                    const VK_LBUTTON: i32 = 0x01;
                    if (GetKeyState(VK_LBUTTON) >= 0) {
                        // Left button no longer held -- cancel drag.
                        a.drag_active = false;
                        _ = ReleaseCapture();
                        return 0;
                    }
                    const x: i16 = @bitCast(@as(u16, @intCast(lparam & 0xFFFF)));
                    const delta = @as(i32, x) - a.drag_start_x;
                    if (@abs(delta) > 5) {
                        const target_index = @divTrunc(@as(usize, @intCast(@max(x, 0))), @as(usize, @intCast(Tab.TAB_ITEM_WIDTH)));
                        if (target_index < a.tabs.items.len and target_index != a.drag_source_index) {
                            // Swap tabs.
                            const tmp = a.tabs.items[a.drag_source_index];
                            a.tabs.items[a.drag_source_index] = a.tabs.items[target_index];
                            a.tabs.items[target_index] = tmp;

                            // Update active tab and drag source.
                            if (a.active_tab == a.drag_source_index) {
                                a.active_tab = target_index;
                            } else if (a.active_tab == target_index) {
                                a.active_tab = a.drag_source_index;
                            }
                            a.drag_source_index = target_index;
                            a.drag_start_x = x;
                            a.redrawTabBar();
                        }
                    }
                    return 0;
                }

                // Forward to active surface.
                if (a.getActiveSurface()) |surface| {
                    const input_mod = @import("input.zig");
                    const x: i16 = @bitCast(@as(u16, @intCast(lparam & 0xFFFF)));
                    const y_raw: i16 = @bitCast(@as(u16, @intCast((lparam >> 16) & 0xFFFF)));
                    // Adjust Y for tab bar offset.
                    const y = y_raw - @as(i16, @intCast(Tab.TAB_BAR_HEIGHT));
                    const pos = apprt.CursorPos{
                        .x = @floatFromInt(x),
                        .y = @floatFromInt(y),
                    };
                    const mods = input_mod.getModifiers();
                    surface.core_surface.cursorPosCallback(pos, mods) catch |err| {
                        log.warn("cursorPosCallback error: {}", .{err});
                    };
                }
            }
            return 0;
        },
        WM_MOUSEWHEEL => {
            if (app) |a| {
                if (a.getActiveSurface()) |surface| {
                    const raw_delta: i16 = @bitCast(@as(u16, @intCast((wparam >> 16) & 0xFFFF)));
                    const delta: f64 = @as(f64, @floatFromInt(raw_delta)) / 120.0;
                    surface.core_surface.scrollCallback(0, delta, .{}) catch |err| {
                        log.warn("scrollCallback error: {}", .{err});
                    };
                }
            }
            return 0;
        },
        WM_SETFOCUS => {
            if (app) |a| {
                if (a.getActiveSurface()) |surface| {
                    surface.core_surface.focusCallback(true) catch |err| {
                        log.warn("focusCallback error: {}", .{err});
                    };
                }
            }
            return 0;
        },
        WM_KILLFOCUS => {
            if (app) |a| {
                if (a.getActiveSurface()) |surface| {
                    surface.core_surface.focusCallback(false) catch |err| {
                        log.warn("focusCallback error: {}", .{err});
                    };
                }
            }
            return 0;
        },
        WM_APP_WAKEUP => {
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Forward a mouse button message to the active surface.
fn forwardMouseButton(self: *App, msg: u32, wparam: WPARAM, lparam: LPARAM) void {
    _ = wparam;
    if (self.getActiveSurface()) |surface| {
        const input_mod = @import("input.zig");
        const input_types = @import("../../input.zig");
        const button: input_types.MouseButton = switch (msg) {
            WM_LBUTTONDOWN, WM_LBUTTONUP => .left,
            WM_RBUTTONDOWN, WM_RBUTTONUP => .right,
            WM_MBUTTONDOWN, WM_MBUTTONUP => .middle,
            else => return,
        };
        const action: input_types.MouseButtonState = switch (msg) {
            WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN => .press,
            WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP => .release,
            else => return,
        };
        const mods = input_mod.getModifiers();

        const x: i16 = @bitCast(@as(u16, @intCast(lparam & 0xFFFF)));
        const y_raw: i16 = @bitCast(@as(u16, @intCast((lparam >> 16) & 0xFFFF)));
        // Adjust Y for tab bar offset.
        const y = y_raw - @as(i16, @intCast(Tab.TAB_BAR_HEIGHT));
        const pos = apprt.CursorPos{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
        };
        surface.core_surface.cursorPosCallback(pos, null) catch |err| {
            log.warn("cursorPosCallback error in mouse button: {}", .{err});
        };
        _ = surface.core_surface.mouseButtonCallback(action, button, mods) catch |err| {
            log.warn("mouseButtonCallback error: {}", .{err});
        };
    }
}

// ---------------------------------------------------------------------------
// Tab bar painting
// ---------------------------------------------------------------------------

fn paintTabBar(self: *App, hwnd: HWND) void {
    var ps: PAINTSTRUCT = std.mem.zeroes(PAINTSTRUCT);
    const hdc = BeginPaint(hwnd, &ps) orelse return;
    defer _ = EndPaint(hwnd, &ps);

    // Only paint if the paint rect intersects the tab bar.
    if (ps.rcPaint.bottom <= 0) return;

    // Background for the tab bar area.
    const is_dark = detectSystemThemeIsDark();
    const bg_color: u32 = if (is_dark) 0x00302020 else 0x00F0F0F0;
    const active_color: u32 = if (is_dark) 0x00504040 else 0x00FFFFFF;
    const text_color: u32 = if (is_dark) 0x00FFFFFF else 0x00000000;

    var client_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(hwnd, &client_rect);

    // Fill tab bar background.
    const bar_rect = RECT{
        .left = 0,
        .top = 0,
        .right = client_rect.right,
        .bottom = Tab.TAB_BAR_HEIGHT,
    };
    if (CreateSolidBrush(bg_color)) |bg_brush| {
        _ = FillRect(hdc, &bar_rect, bg_brush);
        _ = DeleteObject(@ptrCast(bg_brush));
    }

    _ = SetBkMode(hdc, TRANSPARENT);
    _ = SetTextColor(hdc, text_color);

    // Draw each tab item.
    for (self.tabs.items, 0..) |*tab, i| {
        const tab_left: i32 = @intCast(i * @as(usize, @intCast(Tab.TAB_ITEM_WIDTH)));
        const tab_right: i32 = tab_left + Tab.TAB_ITEM_WIDTH;

        const tab_rect = RECT{
            .left = tab_left,
            .top = 0,
            .right = tab_right,
            .bottom = Tab.TAB_BAR_HEIGHT,
        };

        // Draw tab background.
        if (i == self.active_tab) {
            if (CreateSolidBrush(active_color)) |active_brush| {
                _ = FillRect(hdc, &tab_rect, active_brush);
                _ = DeleteObject(@ptrCast(active_brush));
            }
        }

        // Draw tab color indicator if set.
        if (tab.color) |color| {
            const color_rect = RECT{
                .left = tab_left,
                .top = Tab.TAB_BAR_HEIGHT - 3,
                .right = tab_right,
                .bottom = Tab.TAB_BAR_HEIGHT,
            };
            if (CreateSolidBrush(color)) |color_brush| {
                _ = FillRect(hdc, &color_rect, color_brush);
                _ = DeleteObject(@ptrCast(color_brush));
            }
        }

        // Draw tab title.
        const title = tab.getTitle();
        var title_buf: [64]u16 = undefined;
        const title_len = std.unicode.utf8ToUtf16Le(&title_buf, title) catch 0;
        if (title_len > 0) {
            _ = TextOutW(hdc, tab_left + 8, 6, &title_buf, @intCast(@min(title_len, 64)));
        }
    }
}

/// Compare two null-terminated UTF-16 strings.
fn strEqlW(a: [*:0]const u16, b: [*:0]const u16) bool {
    var i: usize = 0;
    while (a[i] != 0 and b[i] != 0) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == b[i];
}

/// Snap a resize rect to cell boundaries for cell-snapped resize.
fn snapResizeRect(self: *App, rect: *RECT, direction: usize) void {
    const hwnd = self.hwnd orelse return;
    const surface = self.getActiveSurface() orelse return;

    // Compute non-client area overhead using DPI-aware calculation.
    const dpi = GetDpiForWindow(hwnd);
    var nc_rect: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    _ = AdjustWindowRectExForDpi(&nc_rect, WS_OVERLAPPEDWINDOW, 0, 0, dpi);
    const nc_width = (nc_rect.right - nc_rect.left);
    const nc_height = (nc_rect.bottom - nc_rect.top);

    // Get cell dimensions from the core surface's size info.
    const cell_width = surface.core_surface.size.cell.width;
    const cell_height = surface.core_surface.size.cell.height;

    if (cell_width == 0 or cell_height == 0) return;

    // Compute desired client dimensions (account for tab bar height).
    const desired_client_w = (rect.right - rect.left) - nc_width;
    const desired_client_h = (rect.bottom - rect.top) - nc_height - Tab.TAB_BAR_HEIGHT;

    // Snap to cell grid.
    const snapped_w = @divTrunc(desired_client_w, @as(LONG, @intCast(cell_width))) * @as(LONG, @intCast(cell_width));
    const snapped_h = @divTrunc(desired_client_h, @as(LONG, @intCast(cell_height))) * @as(LONG, @intCast(cell_height));

    // Apply snapped dimensions back to rect based on drag direction.
    const final_w = snapped_w + nc_width;
    const final_h = snapped_h + nc_height + Tab.TAB_BAR_HEIGHT;

    switch (direction) {
        WMSZ_LEFT, WMSZ_TOPLEFT, WMSZ_BOTTOMLEFT => {
            rect.left = rect.right - final_w;
        },
        WMSZ_RIGHT, WMSZ_TOPRIGHT, WMSZ_BOTTOMRIGHT => {
            rect.right = rect.left + final_w;
        },
        else => {
            rect.right = rect.left + final_w;
        },
    }

    switch (direction) {
        WMSZ_TOP, WMSZ_TOPLEFT, WMSZ_TOPRIGHT => {
            rect.top = rect.bottom - final_h;
        },
        WMSZ_BOTTOM, WMSZ_BOTTOMLEFT, WMSZ_BOTTOMRIGHT => {
            rect.bottom = rect.top + final_h;
        },
        else => {
            rect.bottom = rect.top + final_h;
        },
    }
}

// ---------------------------------------------------------------------------
// Fullscreen toggle
// ---------------------------------------------------------------------------

fn toggleFullscreen(self: *App) void {
    const hwnd = self.hwnd orelse return;

    if (!self.is_fullscreen) {
        self.saved_style = @as(LONG, @truncate(GetWindowLongPtrW(hwnd, GWL_STYLE)));
        self.saved_placement.length = @sizeOf(WINDOWPLACEMENT);
        _ = GetWindowPlacement(hwnd, &self.saved_placement);

        const monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) orelse return;
        var mi: MONITORINFO = .{};
        mi.cbSize = @sizeOf(MONITORINFO);
        if (GetMonitorInfoW(monitor, &mi) == 0) return;

        _ = SetWindowLongPtrW(hwnd, GWL_STYLE, @as(LONG_PTR, @intCast(WS_POPUP | WS_VISIBLE)));
        _ = SetWindowPos(
            hwnd,
            HWND_TOP,
            mi.rcMonitor.left,
            mi.rcMonitor.top,
            mi.rcMonitor.right - mi.rcMonitor.left,
            mi.rcMonitor.bottom - mi.rcMonitor.top,
            SWP_FRAMECHANGED,
        );

        self.is_fullscreen = true;
    } else {
        _ = SetWindowLongPtrW(hwnd, GWL_STYLE, @as(LONG_PTR, @intCast(self.saved_style)));
        _ = SetWindowPlacement(hwnd, &self.saved_placement);
        _ = SetWindowPos(hwnd, null, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

        self.is_fullscreen = false;
    }
}

// ---------------------------------------------------------------------------
// Theme detection and titlebar
// ---------------------------------------------------------------------------

fn detectSystemThemeIsDark() bool {
    const subkey = comptime std.unicode.utf8ToUtf16LeStringLiteral("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize");
    const value_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("AppsUseLightTheme");

    var hkey: usize = 0;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, subkey, 0, KEY_READ, &hkey) != 0) {
        return true;
    }
    defer _ = RegCloseKey(hkey);

    var data: u32 = 1;
    var data_size: u32 = @sizeOf(u32);
    _ = RegQueryValueExW(hkey, value_name, null, null, @ptrCast(&data), &data_size);

    return data == 0;
}

fn applyThemeToTitlebar(hwnd: HWND, is_dark: bool) void {
    const value: i32 = if (is_dark) 1 else 0;
    _ = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @ptrCast(&value), @sizeOf(i32));
}

// ---------------------------------------------------------------------------
// Win32 helper (ScreenToClient)
// ---------------------------------------------------------------------------

const POINT = extern struct {
    x: LONG,
    y: LONG,
};

extern "user32" fn ScreenToClient(hwnd: HWND, lpPoint: *POINT) callconv(.c) BOOL;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Called by CoreApp to wake up the event loop.
pub fn wakeup(self: *App) void {
    if (self.hwnd) |hwnd| {
        _ = PostMessageW(hwnd, WM_APP_WAKEUP, 0, 0);
    }
}

pub fn performIpc(
    _: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    switch (action) {
        .new_tab => {

            try self.createTab();
            return true;
        },
        .close_tab => {

            switch (value) {
                .this => {
                    try self.closeTab(self.active_tab);
                },
                .other => {
                    // Close all tabs except the active one.
                    var i: usize = self.tabs.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (i != self.active_tab) {
                            try self.closeTab(i);
                        }
                    }
                },
                .right => {
                    // Close all tabs to the right.
                    var i: usize = self.tabs.items.len;
                    while (i > self.active_tab + 1) {
                        i -= 1;
                        try self.closeTab(i);
                    }
                },
            }
            return true;
        },
        .goto_tab => {

            const tab_count = self.tabs.items.len;
            if (tab_count == 0) return true;
            const idx: usize = switch (value) {
                .previous => if (self.active_tab == 0) tab_count - 1 else self.active_tab - 1,
                .next => if (self.active_tab >= tab_count - 1) 0 else self.active_tab + 1,
                .last => tab_count - 1,
                _ => b: {
                    const raw: c_int = @intFromEnum(value);
                    if (raw < 0) break :b self.active_tab;
                    const u: usize = @intCast(raw);
                    break :b if (u < tab_count) u else self.active_tab;
                },
            };
            self.switchToTab(idx);
            return true;
        },
        .move_tab => {

            const tab_count = self.tabs.items.len;
            if (tab_count <= 1) return true;
            const amount = value.amount;
            const current: isize = @intCast(self.active_tab);
            const count: isize = @intCast(tab_count);
            const new_idx: usize = @intCast(@mod(current + amount, count));
            if (new_idx != self.active_tab) {
                // Swap tabs.
                const tmp = self.tabs.items[self.active_tab];
                self.tabs.items[self.active_tab] = self.tabs.items[new_idx];
                self.tabs.items[new_idx] = tmp;
                self.active_tab = new_idx;
                self.redrawTabBar();
            }
            return true;
        },
        .set_title => {
            if (self.tabs.items.len > 0 and self.active_tab < self.tabs.items.len) {
                const tab = &self.tabs.items[self.active_tab];
                if (tab.focused_surface) |surface| {
                    surface.title = value.title;
                }
                // Update window title.
                if (self.hwnd) |hwnd| {
                    const title_str: [:0]const u8 = value.title;
                    var buf: [512]u16 = undefined;
                    const len = std.unicode.utf8ToUtf16Le(&buf, title_str) catch 0;
                    if (len < buf.len) {
                        buf[len] = 0;
                        const ptr: LPCWSTR = @ptrCast(&buf);
                        _ = SetWindowTextW(hwnd, ptr);
                    }
                }
                self.redrawTabBar();
            }
            return true;
        },
        .initial_size => {
            if (self.hwnd) |hwnd| {
                _ = SetWindowPos(
                    hwnd,
                    null,
                    0,
                    0,
                    @intCast(value.width),
                    @intCast(value.height),
                    SWP_NOMOVE | SWP_NOZORDER,
                );
            }
            return true;
        },
        .toggle_fullscreen => {
            self.toggleFullscreen();
            return true;
        },
        .reload_config => {
            const opts = value;
            if (opts.soft) {
                try self.core_app.updateConfig(self, self.config);
            } else {
                var new_config = try CoreConfig.load(self.alloc);
                errdefer new_config.deinit();
                try self.core_app.updateConfig(self, &new_config);
                if (self.owned_config) |*old| old.deinit();
                self.owned_config = new_config;
                self.config = &self.owned_config.?;
            }
            return true;
        },
        .config_change => {
            const new_config = value.config;
            self.config = new_config;
            if (self.hwnd) |hwnd| {
                applyThemeToTitlebar(hwnd, detectSystemThemeIsDark());
            }
            return true;
        },
        .new_window => {

            // new_window creates the first tab.
            if (self.tabs.items.len == 0) {
                try self.createTab();
            }
            return true;
        },
        .new_split => {

            const tab = self.getActiveTab() orelse return false;
            const SplitTree = @import("SplitTree.zig");

            // Map SplitDirection to SplitTree.Direction and whether new surface is first.
            const direction: SplitTree.Direction = switch (value) {
                .right, .left => .horizontal,
                .down, .up => .vertical,
            };
            const new_first = switch (value) {
                .left, .up => true,
                .right, .down => false,
            };

            _ = try tab.splitSurface(self.alloc, direction, new_first, self.config, self.core_app, self);
            return true;
        },
        .goto_split => {

            const tab = self.getActiveTab() orelse return false;
            const root = tab.root orelse return false;
            const current = tab.focused_surface orelse return false;
            const SplitTree = @import("SplitTree.zig");

            if (SplitTree.focusDirection(root, current, value)) |next_surface| {
                tab.focused_surface = next_surface;
                _ = SetFocus(next_surface.hwnd);
            }
            return true;
        },
        .resize_split => {

            const tab = self.getActiveTab() orelse return false;
            const root = tab.root orelse return false;
            const current = tab.focused_surface orelse return false;
            const SplitTree = @import("SplitTree.zig");

            SplitTree.resize(root, current, value.direction, value.amount);
            tab.layoutSplits(root);
            self.notifyActiveSurfaceSizes();
            return true;
        },
        .equalize_splits => {
            const tab = self.getActiveTab() orelse return false;
            const root = tab.root orelse return false;
            const SplitTree = @import("SplitTree.zig");

            SplitTree.equalize(root);
            tab.layoutSplits(root);
            self.notifyActiveSurfaceSizes();
            return true;
        },
        .toggle_split_zoom => {
            const tab = self.getActiveTab() orelse return false;
            const root = tab.root orelse return false;
            const focused = tab.focused_surface orelse return false;
            const SplitTree = @import("SplitTree.zig");

            if (!tab.zoomed) {
                // Zoom: hide all surfaces except the focused one, resize it to fill.
                SplitTree.showAll(root, false);
                _ = ShowWindow(focused.hwnd, SW_SHOW);
                tab.layoutZoomed(focused);
                tab.zoomed = true;
            } else {
                // Unzoom: show all surfaces and restore layout.
                SplitTree.showAll(root, true);
                tab.layoutSplits(root);
                tab.zoomed = false;
            }
            self.notifyActiveSurfaceSizes();
            return true;
        },
        .start_search => {
            const surface = self.getTargetSurface(target) orelse return false;
            // Create search overlay if it doesn't exist on this surface.
            if (surface.search_overlay == null) {
                surface.search_overlay = .{};
                surface.search_overlay.?.init(surface) catch |err| {
                    log.err("Failed to create search overlay: {}", .{err});
                    surface.search_overlay = null;
                    return false;
                };
            }
            surface.search_overlay.?.show(value.needle);
            return true;
        },
        .end_search => {
            const surface = self.getTargetSurface(target) orelse return false;
            if (surface.search_overlay) |*overlay| {
                if (overlay.visible) {
                    overlay.hide();
                }
            }
            return true;
        },
        .search_total => {
            const surface = self.getTargetSurface(target) orelse return false;
            if (surface.search_overlay) |*overlay| {
                overlay.setTotal(value.total);
            }
            return true;
        },
        .search_selected => {
            const surface = self.getTargetSurface(target) orelse return false;
            if (surface.search_overlay) |*overlay| {
                overlay.setSelected(value.selected);
            }
            return true;
        },
        .scrollbar => {
            const surface = self.getTargetSurface(target) orelse return false;
            surface.scroll_total = value.total;
            surface.scroll_offset = value.offset;
            surface.scroll_view_len = value.len;
            // Trigger a repaint on the surface's HWND for scrollbar painting.
            _ = InvalidateRect(surface.hwnd, null, 0);
            return true;
        },
        .open_url => {
            const url = value.url;
            if (url.len == 0) return true;

            // Convert UTF-8 URL to null-terminated UTF-16.
            var wide_buf: [2048]u16 = undefined;
            const wide_len = std.unicode.utf8ToUtf16Le(&wide_buf, url) catch return false;
            if (wide_len >= wide_buf.len) return false;
            wide_buf[wide_len] = 0;
            const url_wide: LPCWSTR = @ptrCast(&wide_buf);

            _ = ShellExecuteW(null, null, url_wide, null, null, SW_SHOW);
            return true;
        },
        .mouse_over_link => {
            const surface = self.getTargetSurface(target) orelse return false;
            if (value.url.len > 0) {
                surface.hovering_link = true;
                _ = SetCursor(LoadCursorW(null, IDC_HAND));
            } else {
                surface.hovering_link = false;
                _ = SetCursor(LoadCursorW(null, IDC_ARROW));
            }
            return true;
        },
        .ring_bell => {
            // Play system default beep.
            _ = MessageBeep(0xFFFFFFFF);
            // Optionally flash the taskbar icon for visual bell.
            if (self.hwnd) |hwnd| {
                _ = FlashWindow(hwnd, 1);
            }
            return true;
        },
        .cell_size => {
            const surface = self.getTargetSurface(target) orelse return false;
            surface.cell_width = value.width;
            surface.cell_height = value.height;
            return true;
        },
        .color_change, .render => {
            return false;
        },
        else => {
            return false;
        },
    }
}

pub fn redrawInspector(self: *App, surface_arg: *apprt.Surface) void {
    _ = self;
    _ = surface_arg;
}
