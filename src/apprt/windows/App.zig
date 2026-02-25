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

const CS_OWNDC: u32 = 0x0020;
const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: i32 = 5;
const IDC_ARROW: usize = 32512;

/// Custom message to wake up GetMessageW when core needs attention.
const WM_APP_WAKEUP: u32 = 0x8000; // WM_APP range

const GWLP_USERDATA: i32 = -21;

// WM_SIZING wParam direction values
const WMSZ_LEFT: usize = 1;
const WMSZ_RIGHT: usize = 2;
const WMSZ_TOP: usize = 3;
const WMSZ_TOPLEFT: usize = 4;
const WMSZ_TOPRIGHT: usize = 5;
const WMSZ_BOTTOM: usize = 6;
const WMSZ_BOTTOMLEFT: usize = 7;
const WMSZ_BOTTOMRIGHT: usize = 8;

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
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

// SetWindowPos flags
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOZORDER: u32 = 0x0004;

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

surface: Surface = undefined,
hwnd: ?HWND = null,
core_app: *CoreApp = undefined,
alloc: Allocator = undefined,
config: *const configpkg.Config = undefined,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    const alloc = core_app.alloc;
    self.alloc = alloc;
    self.core_app = core_app;

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
        WM_APP_WAKEUP => {
            // No-op: just wakes up GetMessageW so we can tick the core.
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Snap a resize rect to cell boundaries for cell-snapped resize.
fn snapResizeRect(self: *App, rect: *RECT, direction: usize) void {
    const hwnd = self.hwnd orelse return;

    // Compute non-client area overhead (borders, titlebar).
    var window_rect: RECT = std.mem.zeroes(RECT);
    var client_rect: RECT = std.mem.zeroes(RECT);
    _ = GetWindowRect(hwnd, &window_rect);
    _ = GetClientRect(hwnd, &client_rect);

    const nc_width = (window_rect.right - window_rect.left) - (client_rect.right - client_rect.left);
    const nc_height = (window_rect.bottom - window_rect.top) - (client_rect.bottom - client_rect.top);

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
