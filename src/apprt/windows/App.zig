/// Windows apprt backend (WinUI 3 via COM/WinRT).
///
/// This is a stub implementation that satisfies the apprt interface.
/// The actual WinUI 3 integration is built out in subsequent plans.
const App = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const com = @import("com.zig");

const log = std.log.scoped(.windows);

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = self;
    _ = core_app;
    _ = opts;

    // Initialize the COM/WinRT runtime. This validates the COM bridge
    // compiles and is callable.
    try com.roInitialize();
    log.info("Windows apprt initialized (COM/WinRT ready)", .{});
}

pub fn terminate(self: *App) void {
    _ = self;
    com.roUninitialize();
}

pub fn run(self: *App) !void {
    _ = self;
    // TODO: WinUI 3 message loop -- implemented in Plan 02
    log.info("Windows apprt run loop placeholder", .{});
}

/// Called by CoreApp to wake up the event loop.
pub fn wakeup(self: *App) void {
    _ = self;
    // TODO: PostMessage to wake up the Windows message loop
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

pub fn redrawInspector(self: *App, surface: *apprt.Surface) void {
    _ = self;
    _ = surface;
}
