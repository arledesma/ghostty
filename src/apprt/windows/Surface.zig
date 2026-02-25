//! Terminal surface hosting a WinUI 3 SwapChainPanel with EGL rendering context.
//!
//! Each Surface owns an EGL display, surface, and context managed via the
//! angle module. The SwapChainPanel is created via COM activation and provides
//! the native window handle that ANGLE renders into via its D3D11 backend.

const Surface = @This();

const std = @import("std");
const com = @import("com.zig");
const winui = @import("winui.zig");
const angle = @import("angle.zig");

const log = std.log.scoped(.windows_surface);

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// EGL display connection (ANGLE D3D11 backend).
egl_display: angle.EGLDisplay,

/// EGL rendering surface bound to the SwapChainPanel.
egl_surface: angle.EGLSurface,

/// EGL rendering context (GLES 3.1).
egl_context: angle.EGLContext,

/// EGL config used to create surface and context.
egl_config: angle.EGLConfig,

/// The SwapChainPanel native interface for setting the swap chain.
swap_chain_panel: com.ComPtr(winui.ISwapChainPanelNative),

/// The SwapChainPanel as an IInspectable (for setting as window content).
panel_inspectable: *com.IInspectable,

/// Surface dimensions.
width: u32,
height: u32,

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

pub const InitError = angle.EglError || com.HResultError;

/// Create a Surface: activate a SwapChainPanel via COM, initialize EGL.
pub fn init() InitError!Surface {
    // Create SwapChainPanel via WinRT activation
    const class_name = com.L("Microsoft.UI.Xaml.Controls.SwapChainPanel");
    var header: com.HSTRING_HEADER = undefined;
    const hstr = try com.hstring(class_name, &header);
    const inspectable = try com.activateInstance(hstr);

    // Query ISwapChainPanelNative (classic COM interface)
    const panel_native = try (com.ComPtr(com.IInspectable){ .raw = inspectable })
        .queryInterface(winui.ISwapChainPanelNative, &winui.ISwapChainPanelNative.IID);

    // Initialize EGL via ANGLE
    const egl_display = try angle.initDisplay();
    errdefer angle.terminate(egl_display);

    const egl_config = try angle.chooseConfig(egl_display);

    // Create EGL surface using the SwapChainPanel's IInspectable as the native window.
    // ANGLE's WinUI 3 integration expects the SwapChainPanel IInspectable pointer.
    const egl_surface = try angle.createSurface(egl_display, egl_config, @ptrCast(inspectable));
    errdefer angle.destroySurface(egl_display, egl_surface);

    const egl_context = try angle.createContext(egl_display, egl_config);
    errdefer angle.destroyContext(egl_display, egl_context);

    log.info("Surface initialized with EGL context on SwapChainPanel", .{});

    return .{
        .egl_display = egl_display,
        .egl_surface = egl_surface,
        .egl_context = egl_context,
        .egl_config = egl_config,
        .swap_chain_panel = panel_native,
        .panel_inspectable = inspectable,
        .width = 800,
        .height = 600,
    };
}

/// Destroy the surface: release EGL resources and COM references.
pub fn deinit(self: *Surface) void {
    angle.destroyContext(self.egl_display, self.egl_context);
    angle.destroySurface(self.egl_display, self.egl_surface);
    angle.terminate(self.egl_display);
    self.swap_chain_panel.deinit();
    _ = self.panel_inspectable.release();
    log.info("Surface deinitialized", .{});
}

// ---------------------------------------------------------------------------
// Thread context management (called by OpenGL renderer)
// ---------------------------------------------------------------------------

/// Make the EGL context current on the calling thread.
/// Called by the renderer thread before drawing.
pub fn threadEnter(self: *Surface) void {
    angle.makeCurrent(self.egl_display, self.egl_surface, self.egl_context) catch |err| {
        log.err("threadEnter: EGL makeCurrent failed: {}", .{err});
    };
}

/// Release the EGL context from the calling thread.
/// Called by the renderer thread after drawing is complete.
pub fn threadExit(self: *Surface) void {
    angle.releaseContext(self.egl_display) catch |err| {
        log.err("threadExit: EGL releaseContext failed: {}", .{err});
    };
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

/// Swap EGL buffers to present the rendered frame.
pub fn swapBuffers(self: *Surface) void {
    angle.swapBuffers(self.egl_display, self.egl_surface) catch |err| {
        log.err("swapBuffers failed: {}", .{err});
    };
}
