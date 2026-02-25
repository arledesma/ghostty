//! Terminal surface backed by a Win32 HWND with a WGL OpenGL context.
//!
//! Each Surface owns a WGL rendering context (HGLRC) and device context (HDC)
//! for the HWND provided by App. The HWND must have CS_OWNDC set.
//!
//! Implements the rt_surface interface required by src/Surface.zig (core).

const Surface = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const CoreSurface = @import("../../Surface.zig");
const CoreApp = @import("../../App.zig");
const App = @import("App.zig");
const wgl = @import("wgl.zig");

const log = std.log.scoped(.windows_surface);

// ---------------------------------------------------------------------------
// Win32 types
// ---------------------------------------------------------------------------

const HWND = wgl.HWND;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const LONG = i32;

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

const POINT = extern struct {
    x: LONG,
    y: LONG,
};

// ---------------------------------------------------------------------------
// Win32 function imports
// ---------------------------------------------------------------------------

extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(.c) u32;
extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.c) BOOL;
extern "user32" fn ScreenToClient(hwnd: HWND, lpPoint: *POINT) callconv(.c) BOOL;
extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.c) BOOL;

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// The core surface that manages PTY, terminal state, renderer, etc.
core_surface: CoreSurface,

/// Back-reference to the App that owns this surface.
app: *App,

/// The Win32 window handle.
hwnd: HWND,

/// Device context for the window (persistent due to CS_OWNDC).
hdc: wgl.HDC,

/// WGL OpenGL 4.3 core profile rendering context.
hglrc: wgl.HGLRC,

/// Client area dimensions in pixels.
width: u32,
height: u32,

/// Current window title set by the terminal via set_title.
title: ?[:0]const u8,

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Initialize a surface: create WGL context on the HWND, then init the core surface.
pub fn init(self: *Surface, app: *App, config: *const configpkg.Config, core_app: *CoreApp) !void {
    const hwnd = app.hwnd orelse return error.WinApiError;

    // Initialize WGL context on the HWND.
    const ctx = try wgl.initContext(hwnd);

    // Release the WGL context from this thread -- the renderer thread will
    // make it current when it starts.
    wgl.releaseCurrent();

    // Get initial client area dimensions.
    var rect: RECT = std.mem.zeroes(RECT);
    if (GetClientRect(hwnd, &rect) == 0) {
        return error.WinApiError;
    }
    const w: u32 = @intCast(rect.right - rect.left);
    const h: u32 = @intCast(rect.bottom - rect.top);

    self.* = .{
        .core_surface = undefined,
        .app = app,
        .hwnd = hwnd,
        .hdc = ctx.hdc,
        .hglrc = ctx.hglrc,
        .width = w,
        .height = h,
        .title = null,
    };

    // Initialize the core surface (PTY, terminal, renderer thread, etc.).
    try self.core_surface.init(
        app.alloc,
        config,
        core_app,
        app,
        self,
    );

    log.info("Surface initialized with WGL context, size={}x{}", .{ w, h });
}

/// Destroy the surface: deinit core surface, release WGL context.
pub fn deinit(self: *Surface) void {
    self.core_surface.deinit();
    wgl.releaseCurrent();
    wgl.deleteContext(self.hglrc);
    log.info("Surface deinitialized", .{});
}

// ---------------------------------------------------------------------------
// Thread context management (called by OpenGL renderer)
// ---------------------------------------------------------------------------

/// Make the WGL context current on the calling thread.
pub fn threadEnter(self: *Surface) void {
    wgl.makeCurrent(self.hdc, self.hglrc);
}

/// Release the WGL context from the calling thread.
pub fn threadExit(self: *Surface) void {
    _ = self;
    wgl.releaseCurrent();
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

/// Swap buffers to present the rendered frame.
pub fn swapBuffers(self: *Surface) void {
    wgl.swapBuffers(self.hdc);
}

// ---------------------------------------------------------------------------
// rt_surface interface methods (called by core Surface)
// ---------------------------------------------------------------------------

/// Return the DPI-based content scale. Windows default DPI is 96.
pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    const dpi = GetDpiForWindow(self.hwnd);
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    return .{ .x = scale, .y = scale };
}

/// Return the current client area size in pixels.
pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    return .{ .width = self.width, .height = self.height };
}

/// Return the current cursor position relative to the client area.
pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    var pt: POINT = .{ .x = 0, .y = 0 };
    _ = GetCursorPos(&pt);
    _ = ScreenToClient(self.hwnd, &pt);
    return .{
        .x = @floatFromInt(pt.x),
        .y = @floatFromInt(pt.y),
    };
}

/// Return the current window title.
pub fn getTitle(self: *Surface) ?[:0]const u8 {
    return self.title;
}

/// Close the surface. For Phase 2, no confirmation dialog.
pub fn close(self: *Surface, process_active: bool) void {
    _ = process_active;
    _ = DestroyWindow(self.hwnd);
}

/// Return the default termio environment. ConPTY inherits
/// the process environment, so return an empty map.
pub fn defaultTermioEnv(self: *Surface) !std.process.EnvMap {
    return std.process.EnvMap.init(self.app.alloc);
}

/// Windows has a single clipboard (no selection/primary).
pub fn supportsClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
) bool {
    _ = self;
    return clipboard_type == .standard;
}

/// Clipboard read request -- stub for Phase 2.
pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = self;
    _ = clipboard_type;
    _ = state;
    return false;
}

/// Clipboard write -- stub for Phase 2.
pub fn setClipboard(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = self;
    _ = clipboard_type;
    _ = contents;
    _ = confirm;
}

// ---------------------------------------------------------------------------
// Window event callbacks (called from App.zig wndProc)
// ---------------------------------------------------------------------------

/// Called on WM_SIZE to update dimensions and notify core.
pub fn sizeCallback(self: *Surface, width: u32, height: u32) void {
    self.width = width;
    self.height = height;
    self.core_surface.sizeCallback(.{ .width = width, .height = height }) catch |err| {
        log.err("sizeCallback error: {}", .{err});
    };
}
