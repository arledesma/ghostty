/// VS Code-style command palette overlay for Ghostty on Windows.
///
/// GDI-painted child window positioned at the top-center of the main window.
/// Features: fuzzy search filtering, recently-used tracking, keybinding display,
/// keyboard navigation (Up/Down/Enter/Escape), and action dispatch.
const CommandPalette = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const command = @import("../../input/command.zig");
const Command = command.Command;

const log = std.log.scoped(.command_palette);

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

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

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

const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_CLIPCHILDREN: u32 = 0x02000000;

const WM_PAINT: u32 = 0x000F;
const WM_CHAR: u32 = 0x0102;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KILLFOCUS: u32 = 0x0008;

const VK_ESCAPE: usize = 0x1B;
const VK_RETURN: usize = 0x0D;
const VK_UP: usize = 0x26;
const VK_DOWN: usize = 0x28;
const VK_BACK: usize = 0x08;

const SW_SHOW: i32 = 5;
const SW_HIDE: i32 = 0;

const GWLP_USERDATA: i32 = -21;
const TRANSPARENT: i32 = 1;
const DEFAULT_GUI_FONT: i32 = 17;

// Palette dimensions
const PALETTE_MAX_WIDTH: i32 = 600;
const PALETTE_MAX_HEIGHT: i32 = 400;
const ITEM_HEIGHT: i32 = 28;
const SEARCH_BOX_HEIGHT: i32 = 32;
const PADDING: i32 = 8;

// Colors (BGR format for GDI)
const COLOR_BG: u32 = 0x001E1E1E;
const COLOR_SEARCH_BG: u32 = 0x00262526;
const COLOR_BORDER: u32 = 0x003C3C3C;
const COLOR_TEXT: u32 = 0x00CCCCCC;
const COLOR_DIM_TEXT: u32 = 0x00888888;
const COLOR_SELECTED: u32 = 0x00714709; // 0x094771 in RGB -> BGR
const MAX_VISIBLE_ITEMS: usize = 12;

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
extern "user32" fn SetFocus(hwnd: HWND) callconv(.c) ?HWND;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) u16;
extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn InvalidateRect(hwnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.c) BOOL;
extern "user32" fn SetWindowLongPtrW(hwnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.c) LONG_PTR;
extern "user32" fn GetWindowLongPtrW(hwnd: HWND, nIndex: i32) callconv(.c) LONG_PTR;
extern "user32" fn BeginPaint(hwnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.c) ?HDC;
extern "user32" fn EndPaint(hwnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.c) BOOL;
extern "user32" fn MoveWindow(hwnd: HWND, x: i32, y: i32, nWidth: i32, nHeight: i32, bRepaint: BOOL) callconv(.c) BOOL;
extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.c) i32;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.c) i32;
extern "gdi32" fn SetTextColor(hdc: HDC, color: u32) callconv(.c) u32;
extern "gdi32" fn TextOutW(hdc: HDC, x: i32, y: i32, lpString: [*]const u16, c: i32) callconv(.c) BOOL;
extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.c) ?HBRUSH;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.c) BOOL;
extern "gdi32" fn GetStockObject(i: i32) callconv(.c) ?HGDIOBJ;
extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(.c) ?HGDIOBJ;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// The overlay child HWND (created lazily on first show).
hwnd: ?HWND = null,

/// Back-reference to the owning App.
app: *@import("App.zig") = undefined,

/// Whether the palette is currently visible.
visible: bool = false,

/// Current search input text (UTF-8).
search_text: [256]u8 = [_]u8{0} ** 256,
search_len: usize = 0,

/// Indices into command.defaults matching the current search.
filtered_commands: [128]usize = [_]usize{0} ** 128,
filtered_count: usize = 0,

/// Currently highlighted item index.
selected_index: usize = 0,

/// Ring buffer of recently used command indices.
recent_actions: [16]usize = [_]usize{0} ** 16,
recent_count: usize = 0,

/// Class registered flag (file-level static).
var class_registered: bool = false;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

const App = @import("App.zig");

pub fn init(app: *App) CommandPalette {
    return .{
        .hwnd = null,
        .app = app,
        .visible = false,
        .search_text = [_]u8{0} ** 256,
        .search_len = 0,
        .filtered_commands = [_]usize{0} ** 128,
        .filtered_count = 0,
        .selected_index = 0,
        .recent_actions = [_]usize{0} ** 16,
        .recent_count = 0,
    };
}

pub fn deinit(self: *CommandPalette) void {
    if (self.hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.hwnd = null;
    }
    self.visible = false;
}

// ---------------------------------------------------------------------------
// Toggle / Show / Hide
// ---------------------------------------------------------------------------

pub fn toggle(self: *CommandPalette) void {
    if (self.visible) {
        self.hide();
    } else {
        self.showPalette();
    }
}

pub fn showPalette(self: *CommandPalette) void {
    const parent_hwnd = self.app.hwnd orelse return;
    const hinstance = GetModuleHandleW(null);

    // Create HWND on first show.
    if (self.hwnd == null) {
        if (!class_registered) {
            const class_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyCommandPalette");
            const wc = WNDCLASSEXW{
                .lpfnWndProc = paletteWndProc,
                .hInstance = hinstance,
                .lpszClassName = class_name,
            };
            _ = RegisterClassExW(&wc);
            class_registered = true;
        }

        const palette_class = comptime std.unicode.utf8ToUtf16LeStringLiteral("GhosttyCommandPalette");
        self.hwnd = CreateWindowExW(
            0,
            palette_class,
            null,
            WS_CHILD | WS_CLIPCHILDREN,
            0,
            0,
            PALETTE_MAX_WIDTH,
            PALETTE_MAX_HEIGHT,
            parent_hwnd,
            null,
            hinstance,
            null,
        ) orelse {
            log.err("Failed to create command palette HWND", .{});
            return;
        };

        // Store self pointer.
        _ = SetWindowLongPtrW(self.hwnd.?, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(self))));
    }

    // Reset search state.
    self.search_text = [_]u8{0} ** 256;
    self.search_len = 0;
    self.selected_index = 0;

    // Build initial filtered list (all commands).
    self.filterCommands();

    // Position centered at top of parent.
    var parent_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(parent_hwnd, &parent_rect);
    const parent_w = parent_rect.right - parent_rect.left;
    const palette_w: i32 = @min(PALETTE_MAX_WIDTH, @divTrunc(parent_w * 8, 10));
    const palette_h = self.calcHeight();
    const x = @divTrunc(parent_w - palette_w, 2);

    _ = MoveWindow(self.hwnd.?, x, 0, palette_w, palette_h, 1);
    _ = ShowWindow(self.hwnd.?, SW_SHOW);
    _ = SetFocus(self.hwnd.?);

    self.visible = true;
    _ = InvalidateRect(self.hwnd, null, 1);
}

pub fn hide(self: *CommandPalette) void {
    if (self.hwnd) |hwnd| {
        _ = ShowWindow(hwnd, SW_HIDE);
    }
    self.visible = false;

    // Return focus to the active terminal surface.
    if (self.app.getActiveSurface()) |surface| {
        _ = SetFocus(surface.hwnd);
    }
}

// ---------------------------------------------------------------------------
// Fuzzy search
// ---------------------------------------------------------------------------

/// Filter command.defaults by fuzzy-matching against search_text.
/// When search is empty, show all commands (recents first via scoring).
fn filterCommands(self: *CommandPalette) void {
    self.filtered_count = 0;
    const defaults = command.defaults;
    const needle = self.search_text[0..self.search_len];

    for (defaults, 0..) |cmd, i| {
        if (needle.len == 0 or fuzzyMatch(cmd.title, needle)) {
            if (self.filtered_count < self.filtered_commands.len) {
                self.filtered_commands[self.filtered_count] = i;
                self.filtered_count += 1;
            }
        }
    }
}

/// Case-insensitive subsequence match: every character in needle
/// must appear in order within haystack.
fn fuzzyMatch(haystack: []const u8, needle: []const u8) bool {
    var hi: usize = 0;
    for (needle) |nc| {
        const lower_nc = std.ascii.toLower(nc);
        while (hi < haystack.len) {
            if (std.ascii.toLower(haystack[hi]) == lower_nc) {
                hi += 1;
                break;
            }
            hi += 1;
        } else {
            return false;
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Command execution
// ---------------------------------------------------------------------------

fn executeSelected(self: *CommandPalette) void {
    if (self.filtered_count == 0) return;
    if (self.selected_index >= self.filtered_count) return;

    const cmd_index = self.filtered_commands[self.selected_index];
    const defaults = command.defaults;
    if (cmd_index >= defaults.len) return;

    // Add to recent actions ring buffer.
    self.addRecent(cmd_index);

    // Hide first so the palette is dismissed.
    self.hide();

    // Dispatch the action through the core surface's binding action system.
    const cmd = defaults[cmd_index];
    if (self.app.getActiveSurface()) |surface| {
        _ = surface.core_surface.performBindingAction(cmd.action) catch |err| {
            log.warn("Command palette action failed: {}", .{err});
        };
    }
}

fn addRecent(self: *CommandPalette, cmd_index: usize) void {
    // Check if already in recent list.
    for (self.recent_actions[0..self.recent_count]) |r| {
        if (r == cmd_index) return;
    }
    // Add to front, shift others.
    if (self.recent_count < self.recent_actions.len) {
        var i = self.recent_count;
        while (i > 0) : (i -= 1) {
            self.recent_actions[i] = self.recent_actions[i - 1];
        }
        self.recent_actions[0] = cmd_index;
        self.recent_count += 1;
    } else {
        var i: usize = self.recent_actions.len - 1;
        while (i > 0) : (i -= 1) {
            self.recent_actions[i] = self.recent_actions[i - 1];
        }
        self.recent_actions[0] = cmd_index;
    }
}

// ---------------------------------------------------------------------------
// Height calculation
// ---------------------------------------------------------------------------

fn calcHeight(self: *CommandPalette) i32 {
    const item_count: i32 = @intCast(@min(self.filtered_count, MAX_VISIBLE_ITEMS));
    const content_h = SEARCH_BOX_HEIGHT + 1 + item_count * ITEM_HEIGHT;
    return @min(content_h, PALETTE_MAX_HEIGHT);
}

// ---------------------------------------------------------------------------
// Window procedure
// ---------------------------------------------------------------------------

fn paletteWndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    const self_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const self: ?*CommandPalette = if (self_ptr != 0) @ptrFromInt(@as(usize, @intCast(self_ptr))) else null;

    switch (msg) {
        WM_PAINT => {
            if (self) |palette| {
                palette.paint(hwnd);
                return 0;
            }
        },
        WM_KEYDOWN => {
            if (self) |palette| {
                switch (wparam) {
                    VK_ESCAPE => {
                        palette.hide();
                        return 0;
                    },
                    VK_RETURN => {
                        palette.executeSelected();
                        return 0;
                    },
                    VK_UP => {
                        if (palette.filtered_count > 0) {
                            if (palette.selected_index == 0) {
                                palette.selected_index = palette.filtered_count - 1;
                            } else {
                                palette.selected_index -= 1;
                            }
                            _ = InvalidateRect(hwnd, null, 1);
                        }
                        return 0;
                    },
                    VK_DOWN => {
                        if (palette.filtered_count > 0) {
                            palette.selected_index = (palette.selected_index + 1) % palette.filtered_count;
                            _ = InvalidateRect(hwnd, null, 1);
                        }
                        return 0;
                    },
                    VK_BACK => {
                        if (palette.search_len > 0) {
                            palette.search_len -= 1;
                            palette.search_text[palette.search_len] = 0;
                            palette.selected_index = 0;
                            palette.filterCommands();
                            palette.repositionHeight();
                            _ = InvalidateRect(hwnd, null, 1);
                        }
                        return 0;
                    },
                    else => {},
                }
            }
        },
        WM_CHAR => {
            if (self) |palette| {
                const char: u8 = @intCast(wparam & 0xFF);
                // Only accept printable ASCII, ignore control chars.
                if (char >= 0x20 and char < 0x7F) {
                    if (palette.search_len < palette.search_text.len - 1) {
                        palette.search_text[palette.search_len] = char;
                        palette.search_len += 1;
                        palette.selected_index = 0;
                        palette.filterCommands();
                        palette.repositionHeight();
                        _ = InvalidateRect(hwnd, null, 1);
                    }
                }
                return 0;
            }
        },
        WM_KILLFOCUS => {
            if (self) |palette| {
                if (palette.visible) {
                    palette.hide();
                }
                return 0;
            }
        },
        else => {},
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// Reposition the palette height after filtering changes the number of items.
fn repositionHeight(self: *CommandPalette) void {
    const parent_hwnd = self.app.hwnd orelse return;
    const hwnd = self.hwnd orelse return;

    var parent_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(parent_hwnd, &parent_rect);
    const parent_w = parent_rect.right - parent_rect.left;
    const palette_w: i32 = @min(PALETTE_MAX_WIDTH, @divTrunc(parent_w * 8, 10));
    const palette_h = self.calcHeight();
    const x = @divTrunc(parent_w - palette_w, 2);

    _ = MoveWindow(hwnd, x, 0, palette_w, palette_h, 1);
}

// ---------------------------------------------------------------------------
// GDI painting
// ---------------------------------------------------------------------------

fn paint(self: *CommandPalette, hwnd: HWND) void {
    var ps: PAINTSTRUCT = std.mem.zeroes(PAINTSTRUCT);
    const hdc = BeginPaint(hwnd, &ps) orelse return;
    defer _ = EndPaint(hwnd, &ps);

    var client_rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(hwnd, &client_rect);

    // Fill background.
    if (CreateSolidBrush(COLOR_BG)) |bg_brush| {
        _ = FillRect(hdc, &client_rect, bg_brush);
        _ = DeleteObject(@ptrCast(bg_brush));
    }

    // Select default GUI font.
    const old_font = if (GetStockObject(DEFAULT_GUI_FONT)) |font| SelectObject(hdc, font) else null;
    defer if (old_font) |f| {
        _ = SelectObject(hdc, f);
    };

    _ = SetBkMode(hdc, TRANSPARENT);

    // Draw search box background.
    const search_rect = RECT{
        .left = 0,
        .top = 0,
        .right = client_rect.right,
        .bottom = SEARCH_BOX_HEIGHT,
    };
    if (CreateSolidBrush(COLOR_SEARCH_BG)) |search_brush| {
        _ = FillRect(hdc, &search_rect, search_brush);
        _ = DeleteObject(@ptrCast(search_brush));
    }

    // Draw search box border (bottom line).
    const border_rect = RECT{
        .left = 0,
        .top = SEARCH_BOX_HEIGHT,
        .right = client_rect.right,
        .bottom = SEARCH_BOX_HEIGHT + 1,
    };
    if (CreateSolidBrush(COLOR_BORDER)) |border_brush| {
        _ = FillRect(hdc, &border_rect, border_brush);
        _ = DeleteObject(@ptrCast(border_brush));
    }

    // Draw search text or placeholder.
    if (self.search_len > 0) {
        _ = SetTextColor(hdc, COLOR_TEXT);
        var search_wide: [256]u16 = undefined;
        const search_wide_len = std.unicode.utf8ToUtf16Le(&search_wide, self.search_text[0..self.search_len]) catch 0;
        if (search_wide_len > 0) {
            _ = TextOutW(hdc, PADDING, 8, &search_wide, @intCast(search_wide_len));
        }
    } else {
        _ = SetTextColor(hdc, COLOR_DIM_TEXT);
        const placeholder = comptime std.unicode.utf8ToUtf16LeStringLiteral("Type a command...");
        _ = TextOutW(hdc, PADDING, 8, placeholder, @intCast(std.unicode.utf8ToUtf16LeStringLiteral("Type a command...").len));
    }

    // Draw command list.
    const defaults = command.defaults;
    const visible_count = @min(self.filtered_count, MAX_VISIBLE_ITEMS);
    for (0..visible_count) |i| {
        const cmd_index = self.filtered_commands[i];
        if (cmd_index >= defaults.len) continue;
        const cmd = defaults[cmd_index];

        const y_top: i32 = SEARCH_BOX_HEIGHT + 1 + @as(i32, @intCast(i)) * ITEM_HEIGHT;
        const y_bottom: i32 = y_top + ITEM_HEIGHT;

        // Highlight selected item.
        if (i == self.selected_index) {
            const sel_rect = RECT{
                .left = 0,
                .top = y_top,
                .right = client_rect.right,
                .bottom = y_bottom,
            };
            if (CreateSolidBrush(COLOR_SELECTED)) |sel_brush| {
                _ = FillRect(hdc, &sel_rect, sel_brush);
                _ = DeleteObject(@ptrCast(sel_brush));
            }
        }

        // Draw command title.
        _ = SetTextColor(hdc, COLOR_TEXT);
        var title_wide: [128]u16 = undefined;
        const title_wide_len = std.unicode.utf8ToUtf16Le(&title_wide, cmd.title) catch 0;
        if (title_wide_len > 0) {
            _ = TextOutW(hdc, PADDING, y_top + 5, &title_wide, @intCast(@min(title_wide_len, 128)));
        }

        // Draw keybinding hint on the right (action tag name as shorthand).
        _ = SetTextColor(hdc, COLOR_DIM_TEXT);
        const action_name = @tagName(cmd.action);
        var action_wide: [64]u16 = undefined;
        const action_wide_len = std.unicode.utf8ToUtf16Le(&action_wide, action_name) catch 0;
        if (action_wide_len > 0) {
            const text_x = client_rect.right - PADDING - @as(i32, @intCast(action_wide_len)) * 7;
            _ = TextOutW(hdc, text_x, y_top + 5, &action_wide, @intCast(@min(action_wide_len, 64)));
        }
    }
}

// ---------------------------------------------------------------------------
// Accessor for App
// ---------------------------------------------------------------------------

/// Returns the active surface from the parent App.
fn getActiveSurface(self: *CommandPalette) ?*@import("Surface.zig") {
    return self.app.getActiveSurface();
}
