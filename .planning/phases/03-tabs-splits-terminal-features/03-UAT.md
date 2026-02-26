---
status: diagnosed
phase: 03-tabs-splits-terminal-features
source: 03-00-SUMMARY.md, 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md
started: 2026-02-26T12:00:00Z
updated: 2026-02-26T12:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Keyboard Input Produces Text
expected: Typing in the terminal produces characters. Ctrl+C sends interrupt. Shift produces uppercase letters.
result: issue
reported: "Ctrl+c does nothing as far as I can see"
severity: major

### 2. Mouse Text Selection
expected: Click and drag in the terminal to select text. Selected text is visually highlighted.
result: pass

### 3. Create New Tab
expected: Use the new_tab keybinding (or action). A new tab appears in the tab bar at the top of the window. The new tab is active with a fresh shell prompt.
result: issue
reported: "There are no keybindings that I can find"
severity: major

### 4. Switch Between Tabs
expected: With multiple tabs open, click a tab in the tab bar to switch to it. The terminal content changes to the selected tab's session.
result: skipped
reason: Blocked by test 3 — no keybindings to create tabs

### 5. Close Tab
expected: Close the active tab. The tab disappears from the tab bar and the next tab becomes active. If it was the last tab, the window closes.
result: skipped
reason: Blocked by test 3 — no keybindings to create tabs

### 6. Tab Drag Reorder
expected: Click and drag a tab in the tab bar to a new position. The tab order updates to reflect the new position.
result: skipped
reason: Blocked by test 3 — no keybindings to create tabs

### 7. Create Split Pane
expected: Use the new_split action. The current terminal area divides into two panes (horizontal or vertical), each with its own shell session.
result: skipped
reason: Blocked by same issue — no keybindings for actions

### 8. Navigate Between Splits
expected: With multiple splits open, use goto_split to move focus between panes. The focused pane is visually distinguishable.
result: skipped
reason: Blocked by test 7

### 9. Resize Split
expected: Use resize_split to adjust the divider between split panes. The panes resize proportionally.
result: skipped
reason: Blocked by test 7

### 10. Toggle Split Zoom
expected: Use toggle_split_zoom to maximize the focused pane to fill the tab area. Toggle again to restore the split layout.
result: skipped
reason: Blocked by test 7

### 11. Search Overlay
expected: Use the search keybinding. A search input field appears overlaying the terminal. Typing searches scrollback with match count displayed. Escape closes it.
result: issue
reported: "No keybindings"
severity: major

### 12. URL Click-to-Open
expected: With a URL visible in the terminal output, clicking it opens the URL in the default browser.
result: issue
reported: "The URL becomes underlined. The program closes when clicked."
severity: blocker

### 13. Bell Notification
expected: When the terminal bell fires (e.g., echo -e '\a'), you hear the system default sound and the taskbar icon flashes.
result: issue
reported: "With cmd.exe Ctrl+G does nothing. Starting with pwsh.exe throws an error. Starting with powershell immediately exits."
severity: blocker

### 14. Scrollbar Appears on Scrollback
expected: Generate enough output to create scrollback (e.g., run a command with lots of output). A scrollbar appears on the right edge of the terminal showing your position.
result: pass
note: "dir /s c:\\Windows crashes the application. Hitting enter 10 times leads to scrollback and shows a scrollbar."

## Summary

total: 14
passed: 2
issues: 5
pending: 0
skipped: 7

## Gaps

- truth: "Ctrl+C sends interrupt signal to the running process"
  status: failed
  reason: "User reported: Ctrl+c does nothing as far as I can see"
  severity: major
  test: 1
  root_cause: "input.zig ToUnicode returns control char 0x03 instead of 'c' when Ctrl held. ctrlSeq() expects printable chars, gets raw control byte, returns null. Also unshifted_codepoint only clears Shift not Ctrl."
  artifacts:
    - path: "src/apprt/windows/input.zig"
      issue: "No filtering of control chars from ToUnicode utf8 output; Ctrl not cleared for unshifted codepoint"
    - path: "src/input/key_encode.zig"
      issue: "ctrlSeq works correctly but receives wrong input from Windows apprt"
  missing:
    - "Filter control characters (cp < 0x20) from ToUnicode utf8 output, matching GTK behavior"
    - "Clear VK_CONTROL from keyboard state for unshifted codepoint computation"
  debug_session: ".planning/debug/ctrl-c-not-working.md"

- truth: "Keybindings exist to trigger new_tab, new_split, and other performAction actions"
  status: failed
  reason: "User reported: There are no keybindings that I can find"
  severity: major
  test: 3
  root_cause: "Two bugs in input.zig: (1) unshifted_codepoint only clears VK_SHIFT, not VK_CONTROL/VK_MENU, so ToUnicode returns control chars instead of letters — binding matcher can't match. (2) utf8 field is a dangling pointer to stack-local buffer."
  artifacts:
    - path: "src/apprt/windows/input.zig"
      issue: "Line 106: only clears Shift, not Ctrl/Alt before ToUnicode for unshifted codepoint"
    - path: "src/apprt/windows/input.zig"
      issue: "Lines 76,129: returns slice to stack-local utf8_buf (dangling pointer/UB)"
  missing:
    - "Clear VK_CONTROL and VK_MENU alongside VK_SHIFT for unshifted codepoint"
    - "Use static/threadlocal buffer for utf8 to avoid dangling pointer"
  debug_session: ".planning/debug/windows-keybindings-broken.md"

- truth: "Search overlay can be opened via keybinding"
  status: failed
  reason: "User reported: No keybindings"
  severity: major
  test: 11
  root_cause: "Same root cause as test 3 — keybinding matcher fails due to incorrect unshifted_codepoint and dangling utf8 pointer in input.zig"
  artifacts:
    - path: "src/apprt/windows/input.zig"
      issue: "Same as test 3"
  missing:
    - "Fix shared with test 3"
  debug_session: ".planning/debug/windows-keybindings-broken.md"

- truth: "Clicking a URL in terminal output opens it in the default browser"
  status: failed
  reason: "User reported: The URL becomes underlined. The program closes when clicked."
  severity: blocker
  test: 12
  root_cause: "COM threading apartment conflict. App initializes COM with RO_INIT_MULTITHREADED (MTA) but ShellExecuteW requires STA. Shell extensions crash when called from MTA thread."
  artifacts:
    - path: "src/apprt/windows/App.zig"
      issue: "Line 1578: ShellExecuteW called on MTA-initialized thread"
    - path: "src/apprt/windows/com.zig"
      issue: "Line 185: RoInitialize(RO_INIT_MULTITHREADED) sets MTA"
  missing:
    - "Either spawn STA thread for ShellExecuteW, bypass with CreateProcessW cmd /c start, or return false from performAction to use core fallback"
  debug_session: ".planning/debug/url-click-crash.md"

- truth: "Terminal bell produces system sound and taskbar flash"
  status: failed
  reason: "User reported: With cmd.exe Ctrl+G does nothing. Starting with pwsh.exe throws an error. Starting with powershell immediately exits."
  severity: blocker
  test: 13
  root_cause: "Two issues: (A) defaultTermioEnv() returns empty EnvMap instead of inheriting system env. CreateProcessW receives explicit env with only Ghostty vars, missing SYSTEMROOT/USERPROFILE/etc. PowerShell can't start without these. (B) Bell likely swallowed by ConPTY which handles BEL internally rather than passing 0x07 through."
  artifacts:
    - path: "src/apprt/windows/Surface.zig"
      issue: "Line 266-268: defaultTermioEnv returns empty map instead of system env"
    - path: "src/termio/Exec.zig"
      issue: "Line 1550-1583: unnecessary cmd.exe /C wrapping for shell commands"
    - path: "src/Command.zig"
      issue: "Line 267: createWindowsEnvBlock produces non-null env from empty map"
  missing:
    - "Change defaultTermioEnv to call internal_os.getEnvMap to inherit system environment"
    - "Investigate ConPTY BEL passthrough behavior"
  debug_session: ".planning/debug/bell-and-shell-launch.md"
