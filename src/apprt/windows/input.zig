//! Win32 keyboard input translation.
//!
//! Translates Win32 WM_KEYDOWN/WM_KEYUP/WM_SYSKEYDOWN/WM_SYSKEYUP messages
//! into Ghostty KeyEvent values using the keycodes.entries scancode table.

const std = @import("std");
const input = @import("../../input.zig");
const key_mod = @import("../../input/key.zig");
const keycodes = @import("../../input/keycodes.zig");

const log = std.log.scoped(.windows_input);

// ---------------------------------------------------------------------------
// Win32 types and constants
// ---------------------------------------------------------------------------

const WPARAM = usize;
const LPARAM = isize;

// Win32 message IDs
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_SYSKEYDOWN: u32 = 0x0104;
const WM_SYSKEYUP: u32 = 0x0105;

// Virtual key codes for modifier detection
const VK_SHIFT: i32 = 0x10;
const VK_SHIFT_U: u8 = 0x10;
const VK_CONTROL: i32 = 0x11;
const VK_MENU: i32 = 0x12; // Alt
const VK_LWIN: i32 = 0x5B;
const VK_RWIN: i32 = 0x5C;
const VK_CAPITAL: i32 = 0x14; // Caps Lock
const VK_NUMLOCK: i32 = 0x90;

// Win32 function imports
extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.c) i16;
extern "user32" fn GetKeyboardState(lpKeyState: *[256]u8) callconv(.c) i32;
extern "user32" fn ToUnicode(
    wVirtKey: u32,
    wScanCode: u32,
    lpKeyState: *const [256]u8,
    pwszBuff: [*]u16,
    cchBuff: i32,
    wFlags: u32,
) callconv(.c) i32;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Translate a Win32 key message into a Ghostty KeyEvent.
/// Returns null if the message cannot be translated.
pub fn translateKeyEvent(msg: u32, wparam: WPARAM, lparam: LPARAM) ?input.KeyEvent {
    // Extract scancode: bits 16-23 with extended flag in bit 24 (9-bit value).
    const scancode: u32 = @intCast(@as(u32, @bitCast(@as(u32, @intCast(lparam >> 16)))) & 0x1FF);

    // Map to Ghostty key via keycodes.entries.
    const key = keyFromScancode(scancode);

    // Determine action.
    const action: key_mod.Action = switch (msg) {
        WM_KEYDOWN, WM_SYSKEYDOWN => blk: {
            // Bit 30 of lParam: previous key state (1 = was pressed = repeat).
            const was_down = (lparam >> 30) & 1;
            break :blk if (was_down != 0) .repeat else .press;
        },
        WM_KEYUP, WM_SYSKEYUP => .release,
        else => return null,
    };

    // Build modifier state.
    const mods = getModifiers();

    // Generate text via ToUnicode (only for press/repeat, not release).
    var utf8_buf: [16]u8 = undefined;
    var utf8_len: usize = 0;
    var consumed_mods: input.Mods = .{};
    var unshifted_codepoint: u21 = 0;

    if (action != .release) {
        var keyboard_state: [256]u8 = undefined;
        if (GetKeyboardState(&keyboard_state) != 0) {
            var utf16_buf: [4]u16 = undefined;
            const result = ToUnicode(
                @intCast(wparam),
                scancode,
                &keyboard_state,
                &utf16_buf,
                4,
                0,
            );
            if (result > 0) {
                const utf16_slice = utf16_buf[0..@intCast(result)];
                utf8_len = std.unicode.utf16LeToUtf8(&utf8_buf, utf16_slice) catch 0;

                // If shift was held and produced text, shift was consumed
                // for text generation (e.g., Shift+a -> "A").
                if (mods.shift) consumed_mods.shift = true;
            }

            // Compute unshifted codepoint by calling ToUnicode with shift
            // cleared from the keyboard state. This gives us the base
            // character for the key (e.g., 'a' even when Shift is held).
            var unshifted_state = keyboard_state;
            unshifted_state[VK_SHIFT_U] = 0; // Clear shift
            var unshifted_utf16: [4]u16 = undefined;
            const unshifted_result = ToUnicode(
                @intCast(wparam),
                scancode,
                &unshifted_state,
                &unshifted_utf16,
                4,
                0,
            );
            if (unshifted_result > 0) {
                // For standard keyboard input the result is a single BMP
                // code unit, so we can directly use it as the codepoint.
                unshifted_codepoint = @intCast(unshifted_utf16[0]);
            }
        }
    }

    return .{
        .action = action,
        .key = key,
        .mods = mods,
        .consumed_mods = consumed_mods,
        .utf8 = if (utf8_len > 0) utf8_buf[0..utf8_len] else "",
        .unshifted_codepoint = unshifted_codepoint,
    };
}

/// Map a Win32 scancode to a Ghostty Key using keycodes.entries.
/// The native field (index 3 on Windows) contains Win32 scancodes.
pub fn keyFromScancode(scancode: u32) input.Key {
    for (keycodes.entries) |entry| {
        if (entry.native == scancode) {
            return entry.key;
        }
    }
    return .unidentified;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Build Ghostty modifier state from current Win32 key state.
pub fn getModifiers() input.Mods {
    var mods: input.Mods = .{};

    // GetKeyState returns negative (high bit set) if key is pressed.
    if (GetKeyState(VK_SHIFT) < 0) mods.shift = true;
    if (GetKeyState(VK_CONTROL) < 0) mods.ctrl = true;
    if (GetKeyState(VK_MENU) < 0) mods.alt = true;
    if (GetKeyState(VK_LWIN) < 0 or GetKeyState(VK_RWIN) < 0) mods.super = true;

    // Toggle keys: low bit of GetKeyState indicates toggled on.
    if (GetKeyState(VK_CAPITAL) & 1 != 0) mods.caps_lock = true;
    if (GetKeyState(VK_NUMLOCK) & 1 != 0) mods.num_lock = true;

    return mods;
}
