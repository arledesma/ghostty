---
status: diagnosed
trigger: "Investigate why there are no keybindings in the Ghostty Windows terminal"
created: 2026-02-26T00:00:00Z
updated: 2026-02-26T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - Two bugs in input.zig prevent keybinding matching
test: Traced full key event pipeline from WM_KEYDOWN to binding matcher
expecting: Binding matcher receives correct unicode codepoint for matching
next_action: Fix both issues in input.zig

## Symptoms

expected: Ctrl+Shift+T opens new tab, Ctrl+Shift+O opens split, etc.
actual: No keybindings trigger any performAction
errors: None (silent failure - keys just go to PTY)
reproduction: Press any default keybinding (Ctrl+Shift+T, Ctrl+Shift+O, etc.)
started: Always broken on Windows apprt

## Eliminated

(none - first hypothesis was correct)

## Evidence

- timestamp: 2026-02-26
  checked: Default keybinding definitions in Config.zig
  found: Non-Darwin bindings use unicode keys (e.g., .unicode = 't' for new_tab with ctrl+shift)
  implication: Binding matcher must receive unicode codepoint 't' (0x74) to match

- timestamp: 2026-02-26
  checked: Binding.zig getEvent() matching logic (line 2610-2648)
  found: Tries physical key match, then UTF-8 text match, then unshifted_codepoint match
  implication: For unicode bindings, either utf8 or unshifted_codepoint must contain the letter

- timestamp: 2026-02-26
  checked: input.zig translateKeyEvent - unshifted_codepoint computation (line 102-120)
  found: Only clears Shift from keyboard state before ToUnicode call; Ctrl remains set
  implication: ToUnicode with Ctrl held returns control chars (0x01-0x1A), not letters (0x61-0x7A)

- timestamp: 2026-02-26
  checked: input.zig translateKeyEvent - utf8 text generation (line 81-100)
  found: Calls ToUnicode with full modifier state (Ctrl+Shift); returns control characters
  implication: utf8 field contains control char, not matchable letter

- timestamp: 2026-02-26
  checked: GTK apprt key.zig keyvalUnicodeUnshifted (line 97-139)
  found: Uses GDK keymap lookup at level 0 (no modifiers) to get base character
  implication: GTK correctly gets 't' for the T key regardless of modifiers held

- timestamp: 2026-02-26
  checked: input.zig translateKeyEvent - utf8 field lifetime (line 76, 129)
  found: utf8_buf is stack-local; returned slice points to deallocated stack memory
  implication: Secondary bug - dangling pointer for utf8 field (UB, may cause garbled text)

## Resolution

root_cause: |
  TWO BUGS in src/apprt/windows/input.zig prevent keybinding matching:

  BUG 1 (PRIMARY): unshifted_codepoint computed incorrectly.
  Line 106 only clears VK_SHIFT from keyboard state before calling ToUnicode.
  VK_CONTROL (0x11) remains set. Win32 ToUnicode with Ctrl held returns
  control characters (e.g., Ctrl+T = 0x14) instead of the base letter ('t' = 0x74).
  Since default keybindings are defined as .unicode = 't', the binding matcher
  at Binding.zig:2634-2636 compares 0x14 != 't' and finds no match.

  BUG 2 (SECONDARY): utf8 field is a dangling pointer.
  Line 76 declares `var utf8_buf: [16]u8 = undefined;` as a stack local.
  Line 129 returns a slice `utf8_buf[0..utf8_len]` pointing to this stack memory.
  After translateKeyEvent returns, this is undefined behavior. The binding
  matcher at Binding.zig:2618 reads event.utf8 which points to freed stack memory.

fix: |
  BUG 1 FIX: Clear BOTH VK_SHIFT and VK_CONTROL from keyboard state when
  computing unshifted_codepoint. Add: unshifted_state[0x11] = 0; (VK_CONTROL index).
  Also clear VK_MENU (Alt, index 0x12) for completeness, matching GTK behavior
  of returning the base character at level 0 with no modifiers.

  BUG 2 FIX: Copy utf8 data into the KeyEvent struct or use a persistent buffer.
  The KeyEvent.utf8 field is []const u8 (a slice). Options:
  - Use a fixed-size array in the returned struct (but KeyEvent uses slice)
  - Have the caller own the buffer and pass it in
  - Use a static/threadlocal buffer in translateKeyEvent

verification: (pending fix)
files_changed: []
