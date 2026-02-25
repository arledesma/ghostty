/// Windows apprt backend (Win32 HWND + WGL OpenGL).
///
/// Creates a native Win32 window, initializes a WGL OpenGL 4.3 core profile
/// context via Surface, and runs a message loop that presents frames.
const App = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
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

const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    w_param: WPARAM,
    l_param: LPARAM,
    time: u32,
    pt: extern struct { x: i32, y: i32 },
};

const PM_REMOVE: u32 = 0x0001;
const WM_QUIT: u32 = 0x0012;
const WM_CLOSE: u32 = 0x0010;
const WM_DESTROY: u32 = 0x0002;
const CS_OWNDC: u32 = 0x0020;
const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: i32 = 5;
const IDC_ARROW: usize = 32512;

// ---------------------------------------------------------------------------
// Win32 function imports
// ---------------------------------------------------------------------------

extern "user32" fn PeekMessageW(msg: *MSG, hwnd: ?HWND, filter_min: u32, filter_max: u32, remove_msg: u32) callconv(.c) BOOL;
extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.c) BOOL;
extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.c) LRESULT;
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
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

surface: ?Surface = null,
hwnd: ?HWND = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = core_app;
    _ = opts;

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

    // Create the rendering surface (WGL context on the HWND).
    self.surface = Surface.init(hwnd) catch |err| {
        log.err("Failed to create rendering surface: {}", .{err});
        return err;
    };

    _ = ShowWindow(hwnd, SW_SHOW);
    log.info("Win32 window created and shown", .{});
}

pub fn terminate(self: *App) void {
    if (self.surface) |*s| s.deinit();
    self.surface = null;
    if (self.hwnd) |hwnd| _ = DestroyWindow(hwnd);
    self.hwnd = null;
    com.roUninitialize();
}

pub fn run(self: *App) !void {
    var surface = &(self.surface orelse return);

    // Make WGL context current for initial rendering.
    surface.threadEnter();

    var msg: MSG = std.mem.zeroes(MSG);
    var running = true;

    while (running) {
        while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == WM_QUIT) {
                running = false;
                break;
            }
            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
        }

        if (running) {
            surface.swapBuffers();
        }
    }

    surface.threadExit();
}

fn wndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    switch (msg) {
        WM_CLOSE => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Called by CoreApp to wake up the event loop.
pub fn wakeup(self: *App) void {
    _ = self;
    // TODO: PostMessage to wake up the Windows message loop
}

pub fn performIpc(
    _: std.mem.Allocator,
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
    _ = self;
    _ = target;
    _ = value;
    return false;
}

pub fn redrawInspector(self: *App, surface_arg: *apprt.Surface) void {
    _ = self;
    _ = surface_arg;
}
