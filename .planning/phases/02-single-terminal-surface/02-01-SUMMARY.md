---
phase: 02-single-terminal-surface
plan: 01
subsystem: apprt
tags: [win32, wgl, opengl, surface, input, keycodes, conpty]

# Dependency graph
requires:
  - phase: 01-foundation-rendering-bridge
    provides: WGL OpenGL context, Win32 window skeleton, COM init
provides:
  - rt_surface interface (getContentScale, getSize, getCursorPos, getTitle, close, defaultTermioEnv, clipboard stubs)
  - Core Surface.init wiring with PTY, terminal, and renderer thread
  - Win32 message loop with core_app.tick integration
  - Win32 keyboard input translation using keycodes.entries native scancodes
  - Cell-snapped resize via WM_SIZING
  - performAction dispatch for initial_size and set_title
affects: [02-02-clipboard, 02-03-dpi, 03-tabs]

# Tech tracking
tech-stack:
  added: []
  patterns: [rt_surface interface for Win32, GetMessageW-based message loop with PostMessageW wakeup, GWLP_USERDATA for wndProc App retrieval]

key-files:
  created:
    - src/apprt/windows/input.zig
  modified:
    - src/apprt/windows/Surface.zig
    - src/apprt/windows/App.zig

key-decisions:
  - "GetMessageW (blocking) instead of PeekMessageW (spinning) for message loop efficiency"
  - "WM_APP_WAKEUP (0x8000) custom message via PostMessageW to wake GetMessageW when core needs tick"
  - "Cell-snapped resize in WM_SIZING using window/client rect delta for non-client area calculation"
  - "WGL context released from main thread after init, renderer thread makes it current via threadEnter"

patterns-established:
  - "Win32 apprt pattern: GWLP_USERDATA stores App pointer, wndProc retrieves it for dispatch"
  - "Input translation: scancode from lParam bits 16-24, ToUnicode for text, GetKeyState for modifiers"

requirements-completed: [WIN-01, WIN-02, INP-02]

# Metrics
duration: 5min
completed: 2026-02-25
---

# Phase 2 Plan 1: Single Terminal Surface Summary

**Win32 rt_surface interface with core Surface.init wiring, GetMessageW message loop, keyboard input via keycodes.entries scancodes, and cell-snapped resize**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-25T18:16:18Z
- **Completed:** 2026-02-25T18:21:36Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Surface.zig implements full rt_surface interface required by core Surface.init (getContentScale, getSize, getCursorPos, getTitle, close, defaultTermioEnv, supportsClipboard, clipboardRequest, setClipboard)
- App.zig rewired from PeekMessageW spin loop to GetMessageW blocking loop with core_app.tick integration and PostMessageW wakeup
- Win32 keyboard input translation module maps scancodes to Ghostty KeyEvents using keycodes.entries native index
- Cell-snapped resize in WM_SIZING handler using window/client rect delta for non-client area

## Task Commits

Each task was committed atomically:

1. **Task 1: Core Surface wiring and rt_surface interface** - `34f546877` (feat)
2. **Task 2: Win32 input translation module** - `57d74c919` (feat)

## Files Created/Modified
- `src/apprt/windows/Surface.zig` - Full rt_surface implementation with core Surface.init wiring, WGL context management, DPI-based content scale, size/cursor callbacks
- `src/apprt/windows/App.zig` - GetMessageW message loop, GWLP_USERDATA dispatch, WM_SIZE/WM_SIZING handling, performAction for set_title/initial_size, PostMessageW wakeup
- `src/apprt/windows/input.zig` - Win32 scancode-to-KeyEvent translation, modifier detection via GetKeyState, text generation via ToUnicode

## Decisions Made
- Used GetMessageW (blocking) instead of PeekMessageW (spinning) for CPU efficiency; PostMessageW wakes the loop when core needs attention
- WGL context released from main thread after init so renderer thread can make it current -- matches the threading model where renderer owns GL context
- Cell-snapped resize uses GetWindowRect/GetClientRect delta for non-client area instead of AdjustWindowRectExForDpi, avoiding DPI-aware API complexity in Phase 2
- ToUnicode called in WM_KEYDOWN handler for text generation; WM_CHAR from TranslateMessage is suppressed (return 0)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Core surface with PTY, terminal, and renderer is wired -- ready for clipboard (02-02) implementation
- Cell-snapped resize and DPI scaling foundation in place for DPI-aware refinements
- Input translation ready for dead key and IME composition enhancements

---
*Phase: 02-single-terminal-surface*
*Completed: 2026-02-25*
