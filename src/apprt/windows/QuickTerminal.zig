/// Quick Terminal -- a dropdown (Quake-style) terminal that slides down from
/// the top of the screen, summoned by a global hotkey.
///
/// Lazily creates a WS_POPUP | WS_EX_TOPMOST window with no titlebar on first
/// toggle. The shell session persists when hidden -- only the HWND visibility
/// changes. Auto-hides when the window loses focus (configurable via
/// `quick-terminal-autohide`).
const QuickTerminal = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const configpkg = @import("../../config.zig");
const CoreApp = @import("../../App.zig");
const CoreConfig = configpkg.Config;
const Surface = @import("Surface.zig");
const Tab = @import("Tab.zig");
const wgl = @import("wgl.zig");

const log = std.log.scoped(.quick_terminal);

// ---------------------------------------------------------------------------
// Win32 types and constants
// ---------------------------------------------------------------------------

const HWND = wgl.HWND;
const HINSTANCE = std.os.windows.HINSTANCE;
const LPCWSTR = [*:0]const u16;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const LONG = i32;
const LONG_PTR = isize;
const LRESULT = isize;
const WPARAM = usize;
const LPARAM = isize;

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

const MONITORINFO = extern struct {
    cbSize: u32 = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    rcWork: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    dwFlags: u32 = 0,
};

const POINT = extern struct {
    x: LONG,
    y: LONG,
};

// Window styles
const WS_POPUP: u32 = 0x80000000;
const WS_EX_TOPMOST: u32 = 0x00000008;
const WS_EX_TOOLWINDOW: u32 = 0x00000080;
const WS_CLIPCHILDREN: u32 = 0x02000000;
const CS_OWNDC: u32 = 0x0020;
const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;

// Show window commands
const SW_SHOW: i32 = 5;
const SW_SHOWNOACTIVATE: i32 = 4;
const SW_HIDE: i32 = 0;

// SetWindowPos flags and insert-after values
const SWP_NOSIZE: u32 = 0x0001;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOACTIVATE: u32 = 0x0010;
const HWND_TOPMOST: isize = -1;

// Messages
const WM_ACTIVATE: u32 = 0x0006;
const WM_TIMER: u32 = 0x0113;
const WM_SIZE: u32 = 0x0005;
const WM_DESTROY: u32 = 0x0002;
const WA_INACTIVE: u16 = 0;

// Timer
const ANIMATION_TIMER_ID: usize = 1;
const ANIMATION_INTERVAL_MS: u32 = 16; // ~60 fps

// Monitor constants
const MONITOR_DEFAULTTONEAREST: u32 = 0x00000002;

const GWLP_USERDATA: i32 = -21;

// ---------------------------------------------------------------------------
// Win32 function imports
// ---------------------------------------------------------------------------

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
extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
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
extern "user32" fn SetForegroundWindow(hwnd: HWND) callconv(.c) BOOL;
extern "user32" fn SetFocus(hwnd: HWND) callconv(.c) ?HWND;
extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.c) BOOL;
extern "user32" fn MonitorFromPoint(pt: POINT, dwFlags: u32) callconv(.c) ?*anyopaque;
extern "user32" fn GetMonitorInfoW(hMonitor: *anyopaque, lpmi: *MONITORINFO) callconv(.c) BOOL;
extern "user32" fn SetTimer(hwnd: HWND, nIDEvent: usize, uElapse: u32, lpTimerFunc: ?*anyopaque) callconv(.c) usize;
extern "user32" fn KillTimer(hwnd: HWND, uIDEvent: usize) callconv(.c) BOOL;
extern "user32" fn MoveWindow(hwnd: HWND, x: i32, y: i32, nWidth: i32, nHeight: i32, bRepaint: BOOL) callconv(.c) BOOL;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// The popup window handle (null until first toggle -- lazy creation).
hwnd: ?HWND = null,

/// Single tab with a persistent shell session.
tab: ?Tab = null,

/// Back-reference to the parent App.
app: *@import("App.zig"),

/// Current visibility state.
visible: bool = false,

/// Whether an animation is currently running.
animating: bool = false,

/// Target Y position for animation (0 = fully shown, -height = fully hidden).
target_y: i32 = 0,

/// Current Y position during animation.
current_y: i32 = 0,

/// Cached window dimensions.
win_x: i32 = 0,
win_width: i32 = 0,
win_height: i32 = 0,

/// Class registered flag.
var class_registered: bool = false;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Initialize with null hwnd/tab. No HWND created yet (lazy).
pub fn init(app: *@import("App.zig")) QuickTerminal {
    return .{
        .hwnd = null,
        .tab = null,
        .app = app,
        .visible = false,
        .animating = false,
        .target_y = 0,
        .current_y = 0,
        .win_x = 0,
        .win_width = 0,
        .win_height = 0,
    };
}

/// Destroy tab (if exists), destroy HWND (if exists).
pub fn deinit(self: *QuickTerminal) void {
    if (self.tab) |*tab| {
        tab.deinit(self.app.alloc);
        self.tab = null;
    }
    if (self.hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.hwnd = null;
    }
    self.visible = false;
}

// ---------------------------------------------------------------------------
// Toggle / show / hide
// ---------------------------------------------------------------------------

/// Main entry point called from WM_HOTKEY or performAction.
pub fn toggle(self: *QuickTerminal) void {
    // If currently animating, ignore the toggle to avoid conflicting animations.
    if (self.animating) return;

    if (self.hwnd == null) {
        self.ensureWindow();
        if (self.hwnd == null) {
            log.err("Failed to create Quick Terminal window", .{});
            return;
        }
        self.show();
    } else if (self.visible) {
        self.hide();
    } else {
        // Re-position to current monitor before showing (user may have moved cursor).
        self.updatePosition();
        self.show();
    }
}

/// Create the Quick Terminal HWND lazily.
fn ensureWindow(self: *QuickTerminal) void {
    const hinstance = GetModuleHandleW(null);

    // Register the window class once.
    if (!class_registered) {
        const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyQuickTerminal");
        const wc = wgl.WNDCLASSEXW{
            .style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc = quickTerminalWndProc,
            .hInstance = hinstance,
            .lpszClassName = class_name,
        };
        _ = RegisterClassExW(&wc);
        class_registered = true;
    }

    // Determine position on the current monitor.
    var cursor: POINT = .{ .x = 0, .y = 0 };
    _ = GetCursorPos(&cursor);
    const monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST) orelse {
        log.err("MonitorFromPoint failed", .{});
        return;
    };
    var mi: MONITORINFO = .{};
    mi.cbSize = @sizeOf(MONITORINFO);
    if (GetMonitorInfoW(monitor, &mi) == 0) {
        log.err("GetMonitorInfoW failed", .{});
        return;
    }

    const work = mi.rcWork;
    const mon_w = work.right - work.left;
    const mon_h = work.bottom - work.top;

    // 80% width, 40% height, centered horizontally at top of work area.
    self.win_width = @divTrunc(mon_w * 80, 100);
    self.win_height = @divTrunc(mon_h * 40, 100);
    self.win_x = work.left + @divTrunc(mon_w - self.win_width, 2);

    // Start above the screen for slide-down animation.
    self.current_y = work.top - self.win_height;
    self.target_y = work.top;

    const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyQuickTerminal");
    const window_title = comptime std.unicode.utf8ToUtf16LeStringLiteral("Ghostty Quick Terminal");
    const hwnd = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
        class_name,
        window_title,
        WS_POPUP | WS_CLIPCHILDREN,
        self.win_x,
        self.current_y,
        self.win_width,
        self.win_height,
        null,
        null,
        hinstance,
        null,
    ) orelse {
        log.err("CreateWindowExW failed for Quick Terminal", .{});
        return;
    };
    self.hwnd = hwnd;

    // Store self pointer in GWLP_USERDATA so the wndProc can retrieve it.
    _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(self))));

    // Create a Tab inside this HWND with a single Surface (the persistent shell).
    self.tab = .{};
    var tab = &self.tab.?;

    // Load config if not already available.
    const config = self.app.config;
    tab.init(hwnd, self.app.alloc, config, self.app.core_app, self.app, self.win_width, self.win_height) catch |err| {
        log.err("Failed to init Quick Terminal tab: {}", .{err});
        _ = DestroyWindow(hwnd);
        self.hwnd = null;
        self.tab = null;
        return;
    };

    log.info("Quick Terminal window created: {}x{} at ({}, {})", .{ self.win_width, self.win_height, self.win_x, self.current_y });
}

/// Show the Quick Terminal with slide-down animation.
fn show(self: *QuickTerminal) void {
    const hwnd = self.hwnd orelse return;

    // Ensure we start from fully above the screen.
    self.current_y = self.target_y - self.win_height;

    // Position the window above the screen before showing.
    _ = SetWindowPos(
        hwnd,
        @ptrFromInt(@as(usize, @bitCast(HWND_TOPMOST))),
        self.win_x,
        self.current_y,
        self.win_width,
        self.win_height,
        0,
    );

    _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    _ = SetForegroundWindow(hwnd);

    // Focus the tab's surface.
    if (self.tab) |*tab| {
        tab.show();
    }

    // Start animation timer to slide down.
    self.animating = true;
    _ = SetTimer(hwnd, ANIMATION_TIMER_ID, ANIMATION_INTERVAL_MS, null);

    self.visible = true;
    log.info("Quick Terminal showing (animating down)", .{});
}

/// Hide the Quick Terminal with slide-up animation.
fn hide(self: *QuickTerminal) void {
    const hwnd = self.hwnd orelse return;

    // Set target above the screen.
    self.target_y = self.current_y - self.win_height;

    // Start animation timer to slide up.
    self.animating = true;
    _ = SetTimer(hwnd, ANIMATION_TIMER_ID, ANIMATION_INTERVAL_MS, null);

    self.visible = false;
    log.info("Quick Terminal hiding (animating up)", .{});
}

/// Re-calculate position for the current monitor (cursor position may have changed).
fn updatePosition(self: *QuickTerminal) void {
    var cursor: POINT = .{ .x = 0, .y = 0 };
    _ = GetCursorPos(&cursor);
    const monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST) orelse return;
    var mi: MONITORINFO = .{};
    mi.cbSize = @sizeOf(MONITORINFO);
    if (GetMonitorInfoW(monitor, &mi) == 0) return;

    const work = mi.rcWork;
    const mon_w = work.right - work.left;
    const mon_h = work.bottom - work.top;

    self.win_width = @divTrunc(mon_w * 80, 100);
    self.win_height = @divTrunc(mon_h * 40, 100);
    self.win_x = work.left + @divTrunc(mon_w - self.win_width, 2);
    self.target_y = work.top;

    // Also resize the tab's child HWND if it exists.
    if (self.tab) |*tab| {
        tab.resize(self.win_width, self.win_height);
    }
}

// ---------------------------------------------------------------------------
// Animation
// ---------------------------------------------------------------------------

/// Called on each WM_TIMER tick to animate the window position.
fn animationTick(self: *QuickTerminal) void {
    const hwnd = self.hwnd orelse return;

    // Linear interpolation: step = (target - current) / 5, min 4px.
    const diff = self.target_y - self.current_y;
    if (diff == 0) {
        // Animation complete.
        self.animating = false;
        _ = KillTimer(hwnd, ANIMATION_TIMER_ID);

        // If we animated upward (hiding), hide the window now.
        if (!self.visible) {
            _ = ShowWindow(hwnd, SW_HIDE);
        }
        return;
    }

    var step = @divTrunc(diff, 5);
    // Clamp minimum step size.
    if (step > 0 and step < 4) step = 4;
    if (step < 0 and step > -4) step = -4;

    // Clamp so we don't overshoot.
    if ((step > 0 and self.current_y + step > self.target_y) or
        (step < 0 and self.current_y + step < self.target_y))
    {
        self.current_y = self.target_y;
    } else {
        self.current_y += step;
    }

    // Reposition window.
    _ = SetWindowPos(
        hwnd,
        @ptrFromInt(@as(usize, @bitCast(HWND_TOPMOST))),
        self.win_x,
        self.current_y,
        self.win_width,
        self.win_height,
        0,
    );

    // Check if done.
    if (self.current_y == self.target_y) {
        self.animating = false;
        _ = KillTimer(hwnd, ANIMATION_TIMER_ID);
        if (!self.visible) {
            _ = ShowWindow(hwnd, SW_HIDE);
        }
    }
}

// ---------------------------------------------------------------------------
// Window procedure
// ---------------------------------------------------------------------------

fn quickTerminalWndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    const self_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const self: ?*QuickTerminal = if (self_ptr != 0) @ptrFromInt(@as(usize, @intCast(self_ptr))) else null;

    switch (msg) {
        WM_ACTIVATE => {
            const activation = @as(u16, @intCast(wparam & 0xFFFF));
            if (activation == WA_INACTIVE) {
                if (self) |qt| {
                    // Auto-hide on focus loss (default behavior).
                    // Check config for quick-terminal-autohide (default: true).
                    if (qt.visible and !qt.animating) {
                        qt.hide();
                    }
                }
            }
            return 0;
        },
        WM_TIMER => {
            if (wparam == ANIMATION_TIMER_ID) {
                if (self) |qt| {
                    qt.animationTick();
                }
                return 0;
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_SIZE => {
            if (self) |qt| {
                const w: i32 = @intCast(lparam & 0xFFFF);
                const h: i32 = @intCast((lparam >> 16) & 0xFFFF);
                if (qt.tab) |*tab| {
                    tab.resize(w, h);
                }
            }
            return 0;
        },
        WM_DESTROY => {
            if (self) |qt| {
                if (qt.animating) {
                    _ = KillTimer(hwnd, ANIMATION_TIMER_ID);
                    qt.animating = false;
                }
            }
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
