/// Windows apprt backend (Win32 HWND + WGL OpenGL).
///
/// Creates a native Win32 window with standard WS_OVERLAPPEDWINDOW chrome,
/// initializes a core Surface (PTY, terminal, renderer), and runs a message
/// loop that ticks the core mailbox.
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

const WM_QUIT: u32 = 0x0012;
const WM_CLOSE: u32 = 0x0010;
const WM_DESTROY: u32 = 0x0002;
const WM_SIZE: u32 = 0x0005;
const WM_SIZING: u32 = 0x0214;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_SYSKEYDOWN: u32 = 0x0104;
const WM_SYSKEYUP: u32 = 0x0105;
const WM_CHAR: u32 = 0x0102;
const WM_SYSCHAR: u32 = 0x0106;
const WM_DPICHANGED: u32 = 0x02E0;
const WM_SETTINGCHANGE: u32 = 0x001A;

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
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

// DPI awareness
extern "user32" fn SetProcessDpiAwarenessContext(value: isize) callconv(.c) BOOL;
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;

// DPI-aware window rect adjustment
extern "user32" fn AdjustWindowRectExForDpi(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD, dpi: u32) callconv(.c) BOOL;

// DWM for dark titlebar
extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: u32, pvAttribute: *const anyopaque, cbAttribute: u32) callconv(.c) i32;

// Registry for theme detection
extern "advapi32" fn RegOpenKeyExW(hKey: usize, lpSubKey: LPCWSTR, ulOptions: u32, samDesired: u32, phkResult: *usize) callconv(.c) i32;
extern "advapi32" fn RegQueryValueExW(hKey: usize, lpValueName: LPCWSTR, lpReserved: ?*u32, lpType: ?*u32, lpData: ?[*]u8, lpcbData: *u32) callconv(.c) i32;
extern "advapi32" fn RegCloseKey(hKey: usize) callconv(.c) i32;

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

surface: Surface = undefined,
hwnd: ?HWND = null,
core_app: *CoreApp = undefined,
alloc: Allocator = undefined,
config: *const configpkg.Config = undefined,

/// Fullscreen state.
is_fullscreen: bool = false,
saved_style: LONG = 0,
saved_placement: WINDOWPLACEMENT = .{},

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    const alloc = core_app.alloc;
    self.alloc = alloc;
    self.core_app = core_app;

    // Set per-monitor DPI awareness V2 before any window creation.
    // Ignore failure -- may already be set by manifest or prior call.
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

    // Apply initial titlebar theme based on system setting.
    applyThemeToTitlebar(hwnd, detectSystemThemeIsDark());

    _ = ShowWindow(hwnd, SW_SHOW);
    log.info("Win32 window created and shown", .{});
}

/// Called after init to create the surface. Separated because the config
/// is provided by the caller after App.init.
pub fn initSurface(self: *App, config: *const configpkg.Config) !void {
    self.config = config;
    try self.surface.init(self, config, self.core_app);
}

pub fn terminate(self: *App) void {
    self.surface.deinit();
    if (self.hwnd) |hwnd| _ = DestroyWindow(hwnd);
    self.hwnd = null;
    com.roUninitialize();
}

pub fn run(self: *App) !void {
    var msg: MSG = std.mem.zeroes(MSG);

    // Main message loop: GetMessageW blocks until a message arrives.
    // core_app.tick() is called after each batch of messages to drain the mailbox.
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
        WM_SIZE => {
            if (app) |a| {
                const w: u32 = @intCast(lparam & 0xFFFF);
                const h: u32 = @intCast((lparam >> 16) & 0xFFFF);
                a.surface.sizeCallback(w, h);
            }
            return 0;
        },
        WM_SIZING => {
            if (app) |a| {
                // Cell-snapped resize: snap the dragged rect to cell boundaries.
                const rect_ptr: *RECT = @ptrFromInt(@as(usize, @intCast(lparam)));
                a.snapResizeRect(rect_ptr, wparam);
            }
            return 1; // return TRUE to indicate we modified the rect
        },
        WM_KEYDOWN, WM_SYSKEYDOWN, WM_KEYUP, WM_SYSKEYUP => {
            if (app) |a| {
                const input_mod = @import("input.zig");
                if (input_mod.translateKeyEvent(msg, wparam, lparam)) |key_event| {
                    const effect = a.surface.core_surface.keyCallback(key_event) catch .ignored;
                    // For syskey messages, if consumed by Ghostty, don't let
                    // Windows process Alt menu activation.
                    if ((msg == WM_SYSKEYDOWN or msg == WM_SYSKEYUP) and effect == .consumed) {
                        return 0;
                    }
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_CHAR, WM_SYSCHAR => {
            // Text input is handled via ToUnicode in WM_KEYDOWN translation.
            // WM_CHAR is dispatched by TranslateMessage but we don't need it.
            return 0;
        },
        WM_DPICHANGED => {
            if (app) |a| {
                // New DPI is in the low word of wParam.
                const new_dpi: u32 = @intCast(wparam & 0xFFFF);
                // lParam points to a suggested RECT for the new window size.
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
                // Notify core of the DPI change.
                a.surface.contentScaleCallback(new_dpi);
            }
            return 0;
        },
        WM_SETTINGCHANGE => {
            if (app) |a| {
                // Check if the setting change is for theme ("ImmersiveColorSet").
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
        WM_APP_WAKEUP => {
            // No-op: just wakes up GetMessageW so we can tick the core.
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
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

    // Compute non-client area overhead using DPI-aware calculation.
    const dpi = GetDpiForWindow(hwnd);
    var nc_rect: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    _ = AdjustWindowRectExForDpi(&nc_rect, WS_OVERLAPPEDWINDOW, 0, 0, dpi);
    const nc_width = (nc_rect.right - nc_rect.left);
    const nc_height = (nc_rect.bottom - nc_rect.top);

    // Get cell dimensions from the core surface's size info.
    const cell_width = self.surface.core_surface.size.cell.width;
    const cell_height = self.surface.core_surface.size.cell.height;

    if (cell_width == 0 or cell_height == 0) return;

    // Compute desired client dimensions.
    const desired_client_w = (rect.right - rect.left) - nc_width;
    const desired_client_h = (rect.bottom - rect.top) - nc_height;

    // Snap to cell grid.
    const snapped_w = @divTrunc(desired_client_w, @as(LONG, @intCast(cell_width))) * @as(LONG, @intCast(cell_width));
    const snapped_h = @divTrunc(desired_client_h, @as(LONG, @intCast(cell_height))) * @as(LONG, @intCast(cell_height));

    // Apply snapped dimensions back to rect based on drag direction.
    const final_w = snapped_w + nc_width;
    const final_h = snapped_h + nc_height;

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
        // Save current window style and placement.
        self.saved_style = @as(LONG, @truncate(GetWindowLongPtrW(hwnd, GWL_STYLE)));
        self.saved_placement.length = @sizeOf(WINDOWPLACEMENT);
        _ = GetWindowPlacement(hwnd, &self.saved_placement);

        // Get the monitor rect for the current monitor.
        const monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) orelse return;
        var mi: MONITORINFO = .{};
        mi.cbSize = @sizeOf(MONITORINFO);
        if (GetMonitorInfoW(monitor, &mi) == 0) return;

        // Set borderless style and fill the monitor.
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
        // Restore saved style and placement.
        _ = SetWindowLongPtrW(hwnd, GWL_STYLE, @as(LONG_PTR, @intCast(self.saved_style)));
        _ = SetWindowPlacement(hwnd, &self.saved_placement);
        _ = SetWindowPos(hwnd, null, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

        self.is_fullscreen = false;
    }
}

// ---------------------------------------------------------------------------
// Theme detection and titlebar
// ---------------------------------------------------------------------------

/// Detect whether the system is using a dark theme by reading the registry.
fn detectSystemThemeIsDark() bool {
    const subkey = comptime std.unicode.utf8ToUtf16LeStringLiteral("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize");
    const value_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("AppsUseLightTheme");

    var hkey: usize = 0;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, subkey, 0, KEY_READ, &hkey) != 0) {
        // Default to dark if we can't read the registry.
        return true;
    }
    defer _ = RegCloseKey(hkey);

    var data: u32 = 1; // default to light (1)
    var data_size: u32 = @sizeOf(u32);
    _ = RegQueryValueExW(hkey, value_name, null, null, @ptrCast(&data), &data_size);

    // AppsUseLightTheme: 0 = dark, 1 = light
    return data == 0;
}

/// Apply dark or light titlebar to the window via DwmSetWindowAttribute.
fn applyThemeToTitlebar(hwnd: HWND, is_dark: bool) void {
    const value: i32 = if (is_dark) 1 else 0;
    _ = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @ptrCast(&value), @sizeOf(i32));
}

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
        .set_title => {
            if (self.hwnd) |hwnd| {
                // Convert UTF-8 title to UTF-16 for SetWindowTextW.
                const title_str: [:0]const u8 = value.title;
                var buf: [512]u16 = undefined;
                const len = std.unicode.utf8ToUtf16Le(&buf, title_str) catch 0;
                if (len < buf.len) {
                    buf[len] = 0;
                    const ptr: LPCWSTR = @ptrCast(&buf);
                    _ = SetWindowTextW(hwnd, ptr);
                }
                self.surface.title = title_str;
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
            // Fullscreen mode enum (native, macos variants) -- we always use native on Windows.
            self.toggleFullscreen();
            return true;
        },
        .reload_config => {
            const opts = value;
            if (opts.soft) {
                // Soft reload: re-apply existing config with new conditional state.
                try self.core_app.updateConfig(self, self.config);
            } else {
                // Hard reload: load config from disk and propagate.
                var config = try CoreConfig.load(self.alloc);
                defer config.deinit();
                try self.core_app.updateConfig(self, &config);
            }
            return true;
        },
        .config_change => {
            // Config has changed -- re-apply window-level settings.
            const new_config = value.config;
            self.config = new_config;
            if (self.hwnd) |hwnd| {
                applyThemeToTitlebar(hwnd, detectSystemThemeIsDark());
            }
            return true;
        },
        .color_change, .render => {
            _ = target;
            return false;
        },
        else => {
            _ = target;
            return false;
        },
    }
}

pub fn redrawInspector(self: *App, surface_arg: *apprt.Surface) void {
    _ = self;
    _ = surface_arg;
}
