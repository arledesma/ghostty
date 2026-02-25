/// Search overlay UI for finding text in terminal scrollback.
///
/// Creates a child HWND positioned at the top-right of the surface's
/// parent HWND containing an EDIT control for text input and Up/Down
/// buttons for navigating search results.
const SearchOverlay = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Surface = @import("Surface.zig");
const CoreSurface = @import("../../Surface.zig");
const input_binding = @import("../../input/Binding.zig");

const log = std.log.scoped(.search_overlay);

// ---------------------------------------------------------------------------
// Win32 types and constants
// ---------------------------------------------------------------------------

const HWND = std.os.windows.HWND;
const HINSTANCE = std.os.windows.HINSTANCE;
const LPCWSTR = [*:0]const u16;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const LONG = i32;
const LONG_PTR = isize;
const LRESULT = isize;
const WPARAM = usize;
const LPARAM = isize;
const HDC = *anyopaque;
const HBRUSH = *anyopaque;
const HGDIOBJ = *anyopaque;
const HFONT = *anyopaque;

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_BORDER: u32 = 0x00800000;
const WS_TABSTOP: u32 = 0x00010000;
const WS_CLIPCHILDREN: u32 = 0x02000000;
const WS_EX_CLIENTEDGE: u32 = 0x00000200;

const ES_AUTOHSCROLL: u32 = 0x0080;

const WM_COMMAND: u32 = 0x0111;
const WM_KEYDOWN: u32 = 0x0100;
const WM_PAINT: u32 = 0x000F;
const WM_SETFONT: u32 = 0x0030;
const WM_GETTEXT: u32 = 0x000D;
const WM_GETTEXTLENGTH: u32 = 0x000E;
const WM_SETTEXT: u32 = 0x000C;

const EN_CHANGE: u16 = 0x0300;

const VK_RETURN: usize = 0x0D;
const VK_ESCAPE: usize = 0x1B;

const BN_CLICKED: u16 = 0;

const GWLP_USERDATA: i32 = -21;
const GWLP_WNDPROC: i32 = -4;
const GWL_STYLE: i32 = -16;

const COLOR_WINDOW: i32 = 5;

const SW_SHOW: i32 = 5;
const SW_HIDE: i32 = 0;

const TRANSPARENT: i32 = 1;
const DEFAULT_GUI_FONT: i32 = 17;
const FW_NORMAL: i32 = 400;
const DEFAULT_CHARSET: u32 = 1;
const OUT_DEFAULT_PRECIS: u32 = 0;
const CLIP_DEFAULT_PRECIS: u32 = 0;
const CLEARTYPE_QUALITY: u32 = 5;
const DEFAULT_PITCH: u32 = 0;

// Overlay dimensions
const OVERLAY_WIDTH: i32 = 300;
const OVERLAY_HEIGHT: i32 = 32;
const EDIT_WIDTH: i32 = 200;
const BTN_WIDTH: i32 = 30;
const LABEL_WIDTH: i32 = 70;
const PADDING: i32 = 4;

// Control IDs
const ID_EDIT: u16 = 101;
const ID_BTN_UP: u16 = 102;
const ID_BTN_DOWN: u16 = 103;

// ---------------------------------------------------------------------------
// Win32 function imports
// ---------------------------------------------------------------------------

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
extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
extern "user32" fn MoveWindow(hwnd: HWND, x: i32, y: i32, nWidth: i32, nHeight: i32, bRepaint: BOOL) callconv(.c) BOOL;
extern "user32" fn SetFocus(hwnd: HWND) callconv(.c) ?HWND;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) u16;
extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn SendMessageW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn InvalidateRect(hwnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.c) BOOL;
extern "user32" fn SetWindowLongPtrW(hwnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.c) LONG_PTR;
extern "user32" fn GetWindowLongPtrW(hwnd: HWND, nIndex: i32) callconv(.c) LONG_PTR;
extern "user32" fn CallWindowProcW(lpPrevWndFunc: LONG_PTR, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.c) i16;
extern "user32" fn BeginPaint(hwnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.c) ?HDC;
extern "user32" fn EndPaint(hwnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.c) BOOL;
extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.c) i32;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.c) i32;
extern "gdi32" fn SetTextColor(hdc: HDC, color: u32) callconv(.c) u32;
extern "gdi32" fn TextOutW(hdc: HDC, x: i32, y: i32, lpString: [*]const u16, c: i32) callconv(.c) BOOL;
extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.c) ?HBRUSH;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.c) BOOL;
extern "gdi32" fn GetStockObject(i: i32) callconv(.c) ?HGDIOBJ;
extern "gdi32" fn CreateFontW(
    cHeight: i32,
    cWidth: i32,
    cEscapement: i32,
    cOrientation: i32,
    cWeight: i32,
    bItalic: u32,
    bUnderline: u32,
    bStrikeOut: u32,
    iCharSet: u32,
    iOutPrecision: u32,
    iClipPrecision: u32,
    iQuality: u32,
    iPitchAndFamily: u32,
    pszFaceName: ?LPCWSTR,
) callconv(.c) ?HFONT;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

const PAINTSTRUCT = extern struct {
    hdc: ?HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

const WNDCLASSEXW = extern struct {
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
// Fields
// ---------------------------------------------------------------------------

/// The overlay container HWND.
hwnd: ?HWND = null,

/// The EDIT control HWND for search text input.
edit_hwnd: ?HWND = null,

/// The Up button HWND.
btn_up: ?HWND = null,

/// The Down button HWND.
btn_down: ?HWND = null,

/// The surface this overlay is attached to.
surface: *Surface = undefined,

/// Whether the overlay is currently visible.
visible: bool = false,

/// Search result counts for display.
search_total: ?usize = null,
search_selected: ?usize = null,

/// Original wndproc of the EDIT control (for subclassing).
original_edit_proc: LONG_PTR = 0,

/// Class registered flag.
var class_registered: bool = false;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Initialize the search overlay as a child of the given surface HWND.
pub fn init(self: *SearchOverlay, surface: *Surface) !void {
    const parent_hwnd = surface.hwnd;
    const hinstance = GetModuleHandleW(null);

    self.surface = surface;
    self.visible = false;
    self.search_total = null;
    self.search_selected = null;

    // Register class once.
    if (!class_registered) {
        const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttySearchOverlay");
        const wc = WNDCLASSEXW{
            .lpfnWndProc = overlayWndProc,
            .hInstance = hinstance,
            .lpszClassName = class_name,
        };
        _ = RegisterClassExW(&wc);
        class_registered = true;
    }

    // Get parent dimensions to position at top-right.
    var parent_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(parent_hwnd, &parent_rect);
    const parent_w = parent_rect.right - parent_rect.left;
    const x = @max(parent_w - OVERLAY_WIDTH - 4, 0);

    const overlay_class = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttySearchOverlay");
    self.hwnd = CreateWindowExW(
        0,
        overlay_class,
        null,
        WS_CHILD | WS_CLIPCHILDREN,
        x,
        4,
        OVERLAY_WIDTH,
        OVERLAY_HEIGHT,
        parent_hwnd,
        null,
        hinstance,
        null,
    ) orelse {
        log.err("Failed to create search overlay HWND", .{});
        return error.WindowCreationFailed;
    };

    const hwnd = self.hwnd.?;

    // Store self pointer.
    _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(self))));

    // Create EDIT control.
    const edit_class = comptime std.unicode.utf8ToUtf16LeStringLiteral("EDIT");
    self.edit_hwnd = CreateWindowExW(
        0,
        edit_class,
        null,
        WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | WS_TABSTOP,
        PADDING,
        PADDING,
        EDIT_WIDTH,
        OVERLAY_HEIGHT - PADDING * 2,
        hwnd,
        @ptrFromInt(ID_EDIT),
        hinstance,
        null,
    );

    // Set font on EDIT control.
    if (self.edit_hwnd) |edit| {
        if (GetStockObject(DEFAULT_GUI_FONT)) |font| {
            _ = SendMessageW(edit, WM_SETFONT, @intFromPtr(font), 1);
        }

        // Subclass the EDIT control to handle Enter/Escape/Shift+Enter.
        self.original_edit_proc = GetWindowLongPtrW(edit, GWLP_WNDPROC);
        _ = SetWindowLongPtrW(edit, GWLP_WNDPROC, @as(LONG_PTR, @intCast(@intFromPtr(&editSubclassProc))));
        _ = SetWindowLongPtrW(edit, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(self))));
    }

    // Create Up button.
    const btn_class = comptime std.unicode.utf8ToUtf16LeStringLiteral("BUTTON");
    const up_label = comptime std.unicode.utf8ToUtf16LeStringLiteral("\u{25B2}"); // Up triangle
    self.btn_up = CreateWindowExW(
        0,
        btn_class,
        up_label,
        WS_CHILD | WS_VISIBLE | WS_TABSTOP,
        EDIT_WIDTH + PADDING * 2,
        PADDING,
        BTN_WIDTH,
        OVERLAY_HEIGHT - PADDING * 2,
        hwnd,
        @ptrFromInt(ID_BTN_UP),
        hinstance,
        null,
    );

    // Create Down button.
    const down_label = comptime std.unicode.utf8ToUtf16LeStringLiteral("\u{25BC}"); // Down triangle
    self.btn_down = CreateWindowExW(
        0,
        btn_class,
        down_label,
        WS_CHILD | WS_VISIBLE | WS_TABSTOP,
        EDIT_WIDTH + PADDING * 2 + BTN_WIDTH + 2,
        PADDING,
        BTN_WIDTH,
        OVERLAY_HEIGHT - PADDING * 2,
        hwnd,
        @ptrFromInt(ID_BTN_DOWN),
        hinstance,
        null,
    );

    log.info("Search overlay initialized", .{});
}

/// Destroy the overlay and its child controls.
pub fn deinit(self: *SearchOverlay) void {
    if (self.hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.hwnd = null;
    }
    self.edit_hwnd = null;
    self.btn_up = null;
    self.btn_down = null;
    self.visible = false;
}

// ---------------------------------------------------------------------------
// Show / Hide
// ---------------------------------------------------------------------------

/// Show the overlay and set focus to the EDIT control. Optionally pre-fill needle.
pub fn show(self: *SearchOverlay, needle: []const u8) void {
    const hwnd = self.hwnd orelse return;

    // Reposition to top-right of parent.
    var parent_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(self.surface.hwnd, &parent_rect);
    const parent_w = parent_rect.right - parent_rect.left;
    const x = @max(parent_w - OVERLAY_WIDTH - 4, 0);
    _ = MoveWindow(hwnd, x, 4, OVERLAY_WIDTH, OVERLAY_HEIGHT, 1);

    _ = ShowWindow(hwnd, SW_SHOW);
    self.visible = true;

    // Pre-fill needle if provided.
    if (needle.len > 0) {
        if (self.edit_hwnd) |edit| {
            var buf: [256]u16 = undefined;
            const len = std.unicode.utf8ToUtf16Le(&buf, needle) catch 0;
            if (len < buf.len) {
                buf[len] = 0;
                _ = SendMessageW(edit, WM_SETTEXT, 0, @as(LPARAM, @intCast(@intFromPtr(&buf))));
            }
        }
    }

    // Focus the EDIT control.
    if (self.edit_hwnd) |edit| {
        _ = SetFocus(edit);
    }
}

/// Hide the overlay and notify the core surface to clear search.
pub fn hide(self: *SearchOverlay) void {
    if (self.hwnd) |hwnd| {
        _ = ShowWindow(hwnd, SW_HIDE);
    }
    self.visible = false;
    self.search_total = null;
    self.search_selected = null;

    // Tell the core to end the search.
    _ = self.surface.core_surface.performBindingAction(.end_search) catch |err| {
        log.warn("end_search binding action failed: {}", .{err});
    };

    // Return focus to the surface.
    _ = SetFocus(self.surface.hwnd);
}

/// Update the total match count display.
pub fn setTotal(self: *SearchOverlay, total: ?usize) void {
    self.search_total = total;
    // Trigger repaint of the overlay to update the label.
    if (self.hwnd) |hwnd| {
        _ = InvalidateRect(hwnd, null, 1);
    }
}

/// Update the selected match index display.
pub fn setSelected(self: *SearchOverlay, selected: ?usize) void {
    self.search_selected = selected;
    if (self.hwnd) |hwnd| {
        _ = InvalidateRect(hwnd, null, 1);
    }
}

// ---------------------------------------------------------------------------
// Internal: text change and navigation
// ---------------------------------------------------------------------------

/// Called when the EDIT control text changes.
fn onTextChange(self: *SearchOverlay) void {
    const edit = self.edit_hwnd orelse return;

    // Get the text from the EDIT control.
    const text_len_raw = SendMessageW(edit, WM_GETTEXTLENGTH, 0, 0);
    const text_len: usize = if (text_len_raw > 0) @intCast(text_len_raw) else 0;

    if (text_len == 0) {
        // Empty search: send empty needle to stop search.
        _ = self.surface.core_surface.performBindingAction(.{ .search = "" }) catch |err| {
            log.warn("search binding action failed: {}", .{err});
        };
        return;
    }

    // Read UTF-16 text.
    var wide_buf: [512]u16 = undefined;
    const max_len = @min(text_len + 1, wide_buf.len);
    const got = SendMessageW(edit, WM_GETTEXT, max_len, @as(LPARAM, @intCast(@intFromPtr(&wide_buf))));
    if (got <= 0) return;
    const wide_slice = wide_buf[0..@intCast(got)];

    // Convert to UTF-8.
    var utf8_buf: [1024]u8 = undefined;
    const utf8_len = std.unicode.utf16LeToUtf8(&utf8_buf, wide_slice) catch return;
    const needle = utf8_buf[0..utf8_len];

    // Send to core surface.
    _ = self.surface.core_surface.performBindingAction(.{ .search = needle }) catch |err| {
        log.warn("search binding action failed: {}", .{err});
    };
}

/// Navigate to the next match.
fn navigateNext(self: *SearchOverlay) void {
    _ = self.surface.core_surface.performBindingAction(.{ .navigate_search = .next }) catch |err| {
        log.warn("navigate_search next failed: {}", .{err});
    };
}

/// Navigate to the previous match.
fn navigatePrevious(self: *SearchOverlay) void {
    _ = self.surface.core_surface.performBindingAction(.{ .navigate_search = .previous }) catch |err| {
        log.warn("navigate_search previous failed: {}", .{err});
    };
}

// ---------------------------------------------------------------------------
// Window procedures
// ---------------------------------------------------------------------------

/// Overlay container wndproc.
fn overlayWndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    const self_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const self: ?*SearchOverlay = if (self_ptr != 0) @ptrFromInt(@as(usize, @intCast(self_ptr))) else null;

    switch (msg) {
        WM_COMMAND => {
            if (self) |overlay| {
                const notification: u16 = @intCast((wparam >> 16) & 0xFFFF);
                const control_id: u16 = @intCast(wparam & 0xFFFF);

                if (control_id == ID_EDIT and notification == EN_CHANGE) {
                    overlay.onTextChange();
                    return 0;
                }
                if (notification == BN_CLICKED) {
                    if (control_id == ID_BTN_UP) {
                        overlay.navigatePrevious();
                        return 0;
                    }
                    if (control_id == ID_BTN_DOWN) {
                        overlay.navigateNext();
                        return 0;
                    }
                }
            }
        },
        WM_PAINT => {
            if (self) |overlay| {
                overlay.paintOverlay(hwnd);
                return 0;
            }
        },
        else => {},
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// Paint the match count label on the overlay.
fn paintOverlay(self: *SearchOverlay, hwnd: HWND) void {
    var ps: PAINTSTRUCT = std.mem.zeroes(PAINTSTRUCT);
    const hdc = BeginPaint(hwnd, &ps) orelse return;
    defer _ = EndPaint(hwnd, &ps);

    // Background.
    var client_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(hwnd, &client_rect);
    const bg_brush = CreateSolidBrush(0x00F0F0F0) orelse return;
    _ = FillRect(hdc, &client_rect, bg_brush);
    _ = DeleteObject(@ptrCast(bg_brush));

    // Draw match count label if we have search results.
    if (self.search_total) |total| {
        _ = SetBkMode(hdc, TRANSPARENT);
        _ = SetTextColor(hdc, 0x00404040);

        var label_buf: [32]u16 = undefined;
        var label_len: usize = 0;

        if (self.search_selected) |selected| {
            // Format "N/M" as UTF-16.
            var ascii_buf: [32]u8 = undefined;
            const ascii = std.fmt.bufPrint(&ascii_buf, "{}/{}", .{ selected, total }) catch return;
            label_len = std.unicode.utf8ToUtf16Le(&label_buf, ascii) catch return;
        } else {
            var ascii_buf: [32]u8 = undefined;
            const ascii = std.fmt.bufPrint(&ascii_buf, "{} matches", .{total}) catch return;
            label_len = std.unicode.utf8ToUtf16Le(&label_buf, ascii) catch return;
        }

        if (label_len > 0) {
            // Position after the buttons.
            const label_x = EDIT_WIDTH + PADDING * 2 + BTN_WIDTH * 2 + 8;
            _ = TextOutW(hdc, label_x, 8, &label_buf, @intCast(label_len));
        }
    }
}

/// Subclassed EDIT control wndproc to handle Enter, Shift+Enter, and Escape.
fn editSubclassProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    const self_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const overlay: ?*SearchOverlay = if (self_ptr != 0) @ptrFromInt(@as(usize, @intCast(self_ptr))) else null;

    if (overlay) |self| {
        if (msg == WM_KEYDOWN) {
            if (wparam == VK_RETURN) {
                // Shift+Enter = previous, Enter = next.
                const VK_SHIFT: i32 = 0x10;
                if (GetKeyState(VK_SHIFT) < 0) {
                    self.navigatePrevious();
                } else {
                    self.navigateNext();
                }
                return 0;
            }
            if (wparam == VK_ESCAPE) {
                self.hide();
                return 0;
            }
        }

        // Forward to original EDIT wndproc.
        return CallWindowProcW(self.original_edit_proc, hwnd, msg, wparam, lparam);
    }

    return DefWindowProcW(hwnd, msg, wparam, lparam);
}
