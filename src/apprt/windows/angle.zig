//! ANGLE EGL lifecycle management for the Windows apprt backend.
//!
//! ANGLE provides an OpenGL ES implementation on top of Direct3D 11.
//! This module wraps the EGL API for display, surface, and context creation
//! targeting a WinUI 3 SwapChainPanel via ANGLE's D3D11 backend.
//!
//! ANGLE DLLs required: libEGL.dll, libGLESv2.dll
//! Build from ANGLE source with `angle_is_winappsdk=true` or obtain
//! prebuilt binaries from the chromium/angle project.

const std = @import("std");

const log = std.log.scoped(.angle);

// ---------------------------------------------------------------------------
// EGL types
// ---------------------------------------------------------------------------

pub const EGLDisplay = *anyopaque;
pub const EGLSurface = *anyopaque;
pub const EGLContext = *anyopaque;
pub const EGLConfig = *anyopaque;
pub const EGLNativeWindowType = ?*anyopaque;
pub const EGLint = i32;
pub const EGLBoolean = c_uint;

// ---------------------------------------------------------------------------
// EGL constants
// ---------------------------------------------------------------------------

pub const EGL_NONE: EGLint = 0x3038;
pub const EGL_TRUE: EGLint = 1;
pub const EGL_FALSE: EGLint = 0;

// Display attributes
pub const EGL_PLATFORM_ANGLE_ANGLE: EGLint = 0x3202;
pub const EGL_PLATFORM_ANGLE_TYPE_ANGLE: EGLint = 0x3203;
pub const EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE: EGLint = 0x3208;

// Config attributes
pub const EGL_RED_SIZE: EGLint = 0x3024;
pub const EGL_GREEN_SIZE: EGLint = 0x3023;
pub const EGL_BLUE_SIZE: EGLint = 0x3022;
pub const EGL_ALPHA_SIZE: EGLint = 0x3021;
pub const EGL_DEPTH_SIZE: EGLint = 0x3025;
pub const EGL_STENCIL_SIZE: EGLint = 0x3026;
pub const EGL_RENDERABLE_TYPE: EGLint = 0x3040;
pub const EGL_OPENGL_ES3_BIT: EGLint = 0x0040;
pub const EGL_SURFACE_TYPE: EGLint = 0x3033;
pub const EGL_WINDOW_BIT: EGLint = 0x0004;

// Context attributes
pub const EGL_CONTEXT_CLIENT_VERSION: EGLint = 0x3098;

// Surface attributes
pub const EGL_ANGLE_SURFACE_RENDER_TO_BACK_BUFFER: EGLint = 0x320C;

// Sentinel values for makeCurrent unbind
pub const EGL_NO_DISPLAY: EGLDisplay = @ptrFromInt(0);
pub const EGL_NO_SURFACE: ?*anyopaque = null;
pub const EGL_NO_CONTEXT: ?*anyopaque = null;

// Default display sentinel for eglGetPlatformDisplayEXT
pub const EGL_DEFAULT_DISPLAY: EGLNativeWindowType = null;

// ---------------------------------------------------------------------------
// EGL function imports (linked against libEGL.dll)
// ---------------------------------------------------------------------------

extern "libEGL" fn eglGetPlatformDisplayEXT(
    platform: EGLint,
    native_display: EGLNativeWindowType,
    attrib_list: [*]const EGLint,
) callconv(.c) ?EGLDisplay;

extern "libEGL" fn eglInitialize(
    display: EGLDisplay,
    major: ?*EGLint,
    minor: ?*EGLint,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglChooseConfig(
    display: EGLDisplay,
    attrib_list: [*]const EGLint,
    configs: ?*EGLConfig,
    config_size: EGLint,
    num_config: *EGLint,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglCreateWindowSurface(
    display: EGLDisplay,
    config: EGLConfig,
    native_window: EGLNativeWindowType,
    attrib_list: ?[*]const EGLint,
) callconv(.c) ?EGLSurface;

extern "libEGL" fn eglCreateContext(
    display: EGLDisplay,
    config: EGLConfig,
    share_context: ?EGLContext,
    attrib_list: [*]const EGLint,
) callconv(.c) ?EGLContext;

extern "libEGL" fn eglMakeCurrent(
    display: EGLDisplay,
    draw: ?EGLSurface,
    read: ?EGLSurface,
    context: ?EGLContext,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglSwapBuffers(
    display: EGLDisplay,
    surface: EGLSurface,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglDestroyContext(
    display: EGLDisplay,
    context: EGLContext,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglDestroySurface(
    display: EGLDisplay,
    surface: EGLSurface,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglTerminate(
    display: EGLDisplay,
) callconv(.c) EGLBoolean;

extern "libEGL" fn eglGetError() callconv(.c) EGLint;

pub extern "libEGL" fn eglGetProcAddress(
    name: [*:0]const u8,
) callconv(.c) ?*const fn () callconv(.c) void;

// ---------------------------------------------------------------------------
// Error handling
// ---------------------------------------------------------------------------

pub const EglError = error{EglFail};

fn checkBool(result: EGLBoolean) EglError!void {
    if (result == 0) {
        const err = eglGetError();
        log.err("EGL error: 0x{X:0>4}", .{@as(u32, @bitCast(err))});
        return error.EglFail;
    }
}

// ---------------------------------------------------------------------------
// Public API: EGL lifecycle
// ---------------------------------------------------------------------------

/// Initialize an EGL display using ANGLE's D3D11 backend.
pub fn initDisplay() EglError!EGLDisplay {
    const attribs = [_]EGLint{
        EGL_PLATFORM_ANGLE_TYPE_ANGLE,
        EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
        EGL_NONE,
    };

    const display = eglGetPlatformDisplayEXT(
        EGL_PLATFORM_ANGLE_ANGLE,
        EGL_DEFAULT_DISPLAY,
        &attribs,
    ) orelse {
        log.err("eglGetPlatformDisplayEXT failed", .{});
        return error.EglFail;
    };

    var major: EGLint = 0;
    var minor: EGLint = 0;
    try checkBool(eglInitialize(display, &major, &minor));
    log.info("EGL initialized: version {}.{}", .{ major, minor });

    return display;
}

/// Choose an EGL config for RGBA8888, depth 24, stencil 8, GLES 3.x.
pub fn chooseConfig(display: EGLDisplay) EglError!EGLConfig {
    const attribs = [_]EGLint{
        EGL_RED_SIZE,       8,
        EGL_GREEN_SIZE,     8,
        EGL_BLUE_SIZE,      8,
        EGL_ALPHA_SIZE,     8,
        EGL_DEPTH_SIZE,     24,
        EGL_STENCIL_SIZE,   8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE,   EGL_WINDOW_BIT,
        EGL_NONE,
    };

    var config: EGLConfig = undefined;
    var num_configs: EGLint = 0;
    try checkBool(eglChooseConfig(display, &attribs, &config, 1, &num_configs));

    if (num_configs == 0) {
        log.err("eglChooseConfig: no matching configs found", .{});
        return error.EglFail;
    }

    return config;
}

/// Create an EGL window surface for a SwapChainPanel native window handle.
///
/// The `native_window` parameter should be a PropertySet IInspectable* containing
/// the SwapChainPanel reference, per ANGLE's WinUI 3 integration pattern.
pub fn createSurface(
    display: EGLDisplay,
    config: EGLConfig,
    native_window: EGLNativeWindowType,
) EglError!EGLSurface {
    const attribs = [_]EGLint{
        EGL_ANGLE_SURFACE_RENDER_TO_BACK_BUFFER,
        EGL_TRUE,
        EGL_NONE,
    };

    const surface = eglCreateWindowSurface(
        display,
        config,
        native_window,
        &attribs,
    ) orelse {
        log.err("eglCreateWindowSurface failed", .{});
        return error.EglFail;
    };

    return surface;
}

/// Create an EGL context for GLES 3.1.
pub fn createContext(display: EGLDisplay, config: EGLConfig) EglError!EGLContext {
    const attribs = [_]EGLint{
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE,
    };

    const context = eglCreateContext(display, config, null, &attribs) orelse {
        log.err("eglCreateContext failed", .{});
        return error.EglFail;
    };

    return context;
}

/// Make the given EGL context current on this thread.
pub fn makeCurrent(display: EGLDisplay, surface: EGLSurface, context: EGLContext) EglError!void {
    try checkBool(eglMakeCurrent(display, surface, surface, context));
}

/// Release the current EGL context from this thread.
pub fn releaseContext(display: EGLDisplay) EglError!void {
    try checkBool(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT));
}

/// Swap the EGL surface buffers (present to screen).
pub fn swapBuffers(display: EGLDisplay, surface: EGLSurface) EglError!void {
    try checkBool(eglSwapBuffers(display, surface));
}

/// Destroy an EGL context.
pub fn destroyContext(display: EGLDisplay, context: EGLContext) void {
    _ = eglDestroyContext(display, context);
}

/// Destroy an EGL surface.
pub fn destroySurface(display: EGLDisplay, surface: EGLSurface) void {
    _ = eglDestroySurface(display, surface);
}

/// Terminate an EGL display.
pub fn terminate(display: EGLDisplay) void {
    _ = eglTerminate(display);
}
