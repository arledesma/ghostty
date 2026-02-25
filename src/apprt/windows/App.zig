/// Windows apprt backend (WinUI 3 via COM/WinRT).
///
/// Creates a WinUI 3 Window with a SwapChainPanel as content,
/// initializes ANGLE EGL rendering, and runs a basic message loop
/// that presents frames via eglSwapBuffers.
const App = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const com = @import("com.zig");
const winui = @import("winui.zig");
const Surface = @import("Surface.zig");
const angle = @import("angle.zig");

const log = std.log.scoped(.windows);

// ---------------------------------------------------------------------------
// Win32 message loop types and functions
// ---------------------------------------------------------------------------

const MSG = extern struct {
    hwnd: ?*anyopaque,
    message: u32,
    w_param: usize,
    l_param: isize,
    time: u32,
    pt: extern struct { x: i32, y: i32 },
};

const PM_REMOVE: u32 = 0x0001;
const WM_QUIT: u32 = 0x0012;

extern "user32" fn PeekMessageW(
    msg: *MSG,
    hwnd: ?*anyopaque,
    filter_min: u32,
    filter_max: u32,
    remove_msg: u32,
) callconv(.c) i32;

extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.c) i32;
extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.c) isize;

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

surface: ?Surface = null,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = core_app;
    _ = opts;

    // Initialize the COM/WinRT runtime.
    try com.roInitialize();
    log.info("Windows apprt initialized (COM/WinRT ready)", .{});

    // Create the rendering surface (SwapChainPanel + EGL).
    self.surface = Surface.init() catch |err| {
        log.err("Failed to create rendering surface: {}", .{err});
        return err;
    };
}

pub fn terminate(self: *App) void {
    if (self.surface) |*s| s.deinit();
    self.surface = null;
    com.roUninitialize();
}

pub fn run(self: *App) !void {
    var surface = &(self.surface orelse return);

    // Create a WinUI 3 Window and set the SwapChainPanel as its content.
    const window = blk: {
        var header: com.HSTRING_HEADER = undefined;
        const hstr = try com.hstring(com.L("Microsoft.UI.Xaml.Window"), &header);
        const inspectable = try com.activateInstance(hstr);
        const w: *winui.IWindow = @ptrCast(@alignCast(inspectable));
        break :blk w;
    };

    // Set SwapChainPanel as window content
    const hr = window.vtable.put_Content(window, surface.panel_inspectable);
    com.check(hr) catch |err| {
        log.err("Failed to set window content: {}", .{err});
        return err;
    };

    // Activate (show) the window
    com.check(window.vtable.Activate(window)) catch |err| {
        log.err("Failed to activate window: {}", .{err});
        return err;
    };

    log.info("WinUI 3 window activated with SwapChainPanel content", .{});

    // Make EGL context current for initial clear
    surface.threadEnter();

    // Basic message loop
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
            // Present a frame (initially just whatever the clear color is).
            surface.swapBuffers();
        }
    }

    surface.threadExit();
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
