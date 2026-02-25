//! Terminal surface backed by a Win32 HWND with a WGL OpenGL context.
//!
//! Each Surface owns a WGL rendering context (HGLRC) and device context (HDC)
//! for the HWND provided by App. The HWND must have CS_OWNDC set.

const Surface = @This();

const std = @import("std");
const wgl = @import("wgl.zig");

const log = std.log.scoped(.windows_surface);

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// Device context for the window (persistent due to CS_OWNDC).
hdc: wgl.HDC,

/// WGL OpenGL 4.3 core profile rendering context.
hglrc: wgl.HGLRC,

/// Surface dimensions.
width: u32,
height: u32,

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

pub const InitError = wgl.WglError;

/// Create a Surface: initialize a WGL context on the given HWND.
pub fn init(hwnd: wgl.HWND) InitError!Surface {
    const ctx = try wgl.initContext(hwnd);

    log.info("Surface initialized with WGL context", .{});

    return .{
        .hdc = ctx.hdc,
        .hglrc = ctx.hglrc,
        .width = 800,
        .height = 600,
    };
}

/// Destroy the surface: delete the WGL context.
/// The HDC is not released because CS_OWNDC ties it to the window lifetime.
pub fn deinit(self: *Surface) void {
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
