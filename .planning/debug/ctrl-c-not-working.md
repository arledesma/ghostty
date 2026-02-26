---
status: diagnosed
trigger: "Ctrl+C does nothing in the Ghostty Windows terminal"
created: 2026-02-26T00:00:00Z
updated: 2026-02-26T00:00:00Z
---

## Current Focus

hypothesis: ToUnicode with Ctrl held returns control character (0x03) which breaks both ctrlSeq lookup and unshifted_codepoint
test: Trace the data flow from ToUnicode through ctrlSeq in key_encode.zig
expecting: ctrlSeq switch fails because char=0x03 not 'c'; unshifted_codepoint=3 not 99
next_action: return diagnosis

## Symptoms

expected: Ctrl+C sends 0x03 (ETX) to PTY, interrupting running process
actual: Ctrl+C does nothing (no interrupt signal sent to running process)
errors: None visible
reproduction: Press Ctrl+C while a command is running in the terminal
started: Likely always broken on Windows apprt

## Eliminated

(none needed -- root cause found on first hypothesis)

## Evidence

- timestamp: 2026-02-26
  checked: input.zig ToUnicode call with keyboard_state containing Ctrl
  found: ToUnicode returns 0x0003 (control character ETX) when Ctrl+C is pressed
  implication: utf8 field is set to "\x03" (single byte 0x03) instead of "" or "c"

- timestamp: 2026-02-26
  checked: input.zig unshifted_codepoint computation
  found: Ctrl is NOT cleared from keyboard_state before second ToUnicode call; only shift is cleared
  implication: unshifted_codepoint = 3 (U+0003) instead of 99 ('c')

- timestamp: 2026-02-26
  checked: key_encode.zig ctrlSeq function (line 663)
  found: ctrlSeq checks utf8[0] which is 0x03; switch only matches printable chars ('a'-'z', '0'-'9', etc.)
  implication: ctrlSeq returns null -- no control character is generated

- timestamp: 2026-02-26
  checked: key_encode.zig legacy function fallthrough after ctrlSeq returns null
  found: Falls to fixterms/CSIu path because event.mods.ctrl is true; encodes codepoint 3 as CSIu escape
  implication: Sends wrong encoding or misbehaves in legacy mode

- timestamp: 2026-02-26
  checked: GTK apprt surface.zig (line 1348-1353) for comparison
  found: GTK explicitly filters control characters (cp < 0x20) from IM text, sets utf8="" for them
  implication: On GTK, Ctrl+C produces utf8="" and unshifted_codepoint='c', so ctrlSeq correctly matches 'c'->3

## Resolution

root_cause: |
  The Windows input.zig translateKeyEvent function passes raw ToUnicode output to the
  KeyEvent without filtering control characters. When Ctrl+C is pressed:

  1. ToUnicode(VK_C, ..., keyboard_state_with_ctrl) returns U+0003 (control character)
  2. This 0x03 byte is stored as utf8 text in the KeyEvent
  3. The unshifted_codepoint is also wrong (3 instead of 99/'c') because Ctrl is NOT
     cleared from keyboard_state before the unshifted ToUnicode call (only Shift is cleared)
  4. In key_encode.zig, ctrlSeq() looks at utf8[0]=0x03 which doesn't match any
     printable character in its switch statement, so it returns null
  5. The legacy encoder falls through to the fixterms/CSIu path, which sends the wrong
     escape sequence instead of the raw 0x03 byte

  The GTK apprt handles this correctly by filtering out control characters (codepoint < 0x20)
  from the text buffer. The Windows apprt needs similar treatment.

  TWO fixes are needed in src/apprt/windows/input.zig:

  FIX 1: Clear Ctrl (and Alt) from keyboard_state before calling ToUnicode for text generation,
  OR filter out control characters from the utf8 result (matching GTK behavior).

  FIX 2: Clear Ctrl from keyboard_state (in addition to Shift) when computing
  unshifted_codepoint, so it returns 'c' (99) instead of 0x03 (3).

fix: (not yet applied)
verification: (not yet verified)
files_changed: []
