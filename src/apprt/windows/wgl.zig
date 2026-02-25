//! WGL OpenGL context management for the Windows apprt backend.
//!
//! Uses native Windows OpenGL (WGL) to create an OpenGL 4.3 core profile
//! context. All functions come from system DLLs (opengl32.dll, gdi32.dll,
//! user32.dll) — zero external dependencies.
//!
//! The bootstrap sequence creates a temporary dummy window + legacy GL context
//! to load WGL extension functions (wglCreateContextAttribsARB), then creates
//! the real core profile context on the target HWND.

const std = @import("std");

const log = std.log.scoped(.wgl);

// ---------------------------------------------------------------------------
// Win32 types
// ---------------------------------------------------------------------------

pub const HWND = std.os.windows.HWND;
pub const HDC = *anyopaque;
pub const HGLRC = *anyopaque;
const HMODULE = std.os.windows.HMODULE;
const HINSTANCE = std.os.windows.HINSTANCE;
const LPCWSTR = [*:0]const u16;
const ATOM = u16;
const LRESULT = isize;
const WPARAM = usize;
const LPARAM = isize;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const BYTE = u8;
const WORD = u16;

// ---------------------------------------------------------------------------
// Win32 constants
// ---------------------------------------------------------------------------

const CS_OWNDC = 0x0020;
const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_HIDE = 0;
const PFD_DRAW_TO_WINDOW = 0x00000004;
const PFD_SUPPORT_OPENGL = 0x00000020;
const PFD_DOUBLEBUFFER = 0x00000001;
const PFD_TYPE_RGBA = 0;
const PFD_MAIN_PLANE = 0;

// WGL ARB constants
const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;

// ---------------------------------------------------------------------------
// Win32 structs
// ---------------------------------------------------------------------------

const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 1,
    dwFlags: DWORD = 0,
    iPixelType: BYTE = 0,
    cColorBits: BYTE = 0,
    cRedBits: BYTE = 0,
    cRedShift: BYTE = 0,
    cGreenBits: BYTE = 0,
    cGreenShift: BYTE = 0,
    cBlueBits: BYTE = 0,
    cBlueShift: BYTE = 0,
    cAlphaBits: BYTE = 0,
    cAlphaShift: BYTE = 0,
    cAccumBits: BYTE = 0,
    cAccumRedBits: BYTE = 0,
    cAccumGreenBits: BYTE = 0,
    cAccumBlueBits: BYTE = 0,
    cAccumAlphaBits: BYTE = 0,
    cDepthBits: BYTE = 0,
    cStencilBits: BYTE = 0,
    cAuxBuffers: BYTE = 0,
    iLayerType: BYTE = 0,
    bReserved: BYTE = 0,
    dwLayerMask: DWORD = 0,
    dwVisibleMask: DWORD = 0,
    dwDamageMask: DWORD = 0,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.c) LRESULT,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: ?*anyopaque = null,
};

// ---------------------------------------------------------------------------
// Win32 function imports
// ---------------------------------------------------------------------------

extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.c) ?HGLRC;
extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(.c) BOOL;
extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.c) BOOL;
extern "opengl32" fn wglGetProcAddress(lpszProc: [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void;

extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.c) i32;
extern "gdi32" fn SetPixelFormat(hdc: HDC, format: i32, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.c) BOOL;
extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.c) BOOL;

extern "user32" fn GetDC(hwnd: ?HWND) callconv(.c) ?HDC;
extern "user32" fn ReleaseDC(hwnd: ?HWND, hdc: HDC) callconv(.c) i32;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) ATOM;
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
extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.c) BOOL;
extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;

extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HMODULE;

// ---------------------------------------------------------------------------
// WGL extension function types
// ---------------------------------------------------------------------------

const WglCreateContextAttribsARB = *const fn (?HDC, ?HGLRC, ?[*]const i32) callconv(.c) ?HGLRC;

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

pub const WglError = error{WglFail};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub const Context = struct {
    hdc: HDC,
    hglrc: HGLRC,
};

/// Create an OpenGL 4.3 core profile context on the given HWND.
/// The HWND's window class must have CS_OWNDC set.
pub fn initContext(hwnd: HWND) WglError!Context {
    // Get the device context for the target window.
    const hdc = GetDC(hwnd) orelse {
        log.err("GetDC failed for target HWND", .{});
        return error.WglFail;
    };

    // Set pixel format on the target window.
    const pfd = makePixelFormatDescriptor();
    const pixel_format = ChoosePixelFormat(hdc, &pfd);
    if (pixel_format == 0) {
        log.err("ChoosePixelFormat failed", .{});
        return error.WglFail;
    }
    if (SetPixelFormat(hdc, pixel_format, &pfd) == 0) {
        log.err("SetPixelFormat failed", .{});
        return error.WglFail;
    }

    // Load wglCreateContextAttribsARB via a temporary bootstrap context.
    const create_attribs = loadCreateContextAttribs() orelse {
        log.err("failed to load wglCreateContextAttribsARB", .{});
        return error.WglFail;
    };

    // Create the real OpenGL 4.3 core profile context.
    const attribs = [_]i32{
        WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
        WGL_CONTEXT_MINOR_VERSION_ARB, 3,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        0, // terminator
    };

    const hglrc = create_attribs(hdc, null, &attribs) orelse {
        log.err("wglCreateContextAttribsARB failed", .{});
        return error.WglFail;
    };

    if (wglMakeCurrent(hdc, hglrc) == 0) {
        log.err("wglMakeCurrent failed after context creation", .{});
        _ = wglDeleteContext(hglrc);
        return error.WglFail;
    }

    log.info("WGL OpenGL 4.3 core profile context created", .{});

    return .{
        .hdc = hdc,
        .hglrc = hglrc,
    };
}

/// Make the WGL context current on the calling thread.
pub fn makeCurrent(hdc: HDC, hglrc: HGLRC) void {
    if (wglMakeCurrent(hdc, hglrc) == 0) {
        log.err("wglMakeCurrent failed", .{});
    }
}

/// Release the WGL context from the calling thread.
pub fn releaseCurrent() void {
    _ = wglMakeCurrent(null, null);
}

/// Swap the front and back buffers (present to screen).
pub fn swapBuffers(hdc: HDC) void {
    if (SwapBuffers(hdc) == 0) {
        log.err("SwapBuffers failed", .{});
    }
}

/// Delete a WGL context.
pub fn deleteContext(hglrc: HGLRC) void {
    _ = wglDeleteContext(hglrc);
}

/// Get a GL proc address loader suitable for GLAD.
/// Wraps wglGetProcAddress with a fallback to GetProcAddress on opengl32.dll
/// for core GL 1.1 functions that wglGetProcAddress doesn't resolve.
pub fn getGlProcAddress(name: [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void {
    if (wglGetProcAddress(name)) |proc| return proc;

    // Fallback: core GL 1.1 functions live in opengl32.dll itself.
    const opengl32_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("opengl32.dll");
    const module = GetModuleHandleW(opengl32_name) orelse return null;
    const kernel32 = std.os.windows.kernel32;
    return @ptrCast(kernel32.GetProcAddress(@ptrCast(module), name));
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn makePixelFormatDescriptor() PIXELFORMATDESCRIPTOR {
    return .{
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iPixelType = PFD_TYPE_RGBA,
        .cColorBits = 32,
        .cAlphaBits = 8,
        .cDepthBits = 24,
        .cStencilBits = 8,
        .iLayerType = PFD_MAIN_PLANE,
    };
}

/// Bootstrap: create a temporary window + legacy GL context to load
/// wglCreateContextAttribsARB, then tear it all down.
fn loadCreateContextAttribs() ?WglCreateContextAttribsARB {
    const hinstance: ?HINSTANCE = @ptrCast(GetModuleHandleW(null));

    const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWglBootstrap");

    const wc = WNDCLASSEXW{
        .style = CS_OWNDC,
        .lpfnWndProc = DefWindowProcW,
        .hInstance = hinstance,
        .lpszClassName = class_name,
    };
    _ = RegisterClassExW(&wc);

    const dummy_hwnd = CreateWindowExW(
        0,
        class_name,
        null,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1,
        1,
        null,
        null,
        hinstance,
        null,
    ) orelse {
        log.err("failed to create dummy window for WGL bootstrap", .{});
        return null;
    };
    defer _ = DestroyWindow(dummy_hwnd);

    const dummy_dc = GetDC(dummy_hwnd) orelse {
        log.err("GetDC failed for dummy window", .{});
        return null;
    };

    const pfd = makePixelFormatDescriptor();
    const pixel_format = ChoosePixelFormat(dummy_dc, &pfd);
    if (pixel_format == 0) {
        log.err("ChoosePixelFormat failed for dummy window", .{});
        return null;
    }
    if (SetPixelFormat(dummy_dc, pixel_format, &pfd) == 0) {
        log.err("SetPixelFormat failed for dummy window", .{});
        return null;
    }

    const dummy_ctx = wglCreateContext(dummy_dc) orelse {
        log.err("wglCreateContext failed for dummy context", .{});
        return null;
    };
    defer _ = wglDeleteContext(dummy_ctx);

    if (wglMakeCurrent(dummy_dc, dummy_ctx) == 0) {
        log.err("wglMakeCurrent failed for dummy context", .{});
        return null;
    }
    defer _ = wglMakeCurrent(null, null);

    const proc = wglGetProcAddress("wglCreateContextAttribsARB") orelse {
        log.err("wglGetProcAddress(\"wglCreateContextAttribsARB\") returned null — driver may not support OpenGL 4.3", .{});
        return null;
    };

    return @ptrCast(proc);
}
