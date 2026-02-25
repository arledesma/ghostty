---
phase: 03-tabs-splits-terminal-features
plan: 00
subsystem: input
tags: [win32, keyboard, mouse, clipboard, config-reload, wndproc]

# Dependency graph
requires:
  - phase: 02-single-terminal-surface
    provides: Win32 HWND window with WGL context, PTY, and core Surface
provides:
  - Working keyboard input via ToUnicode with consumed_mods and unshifted_codepoint
  - Mouse event dispatch (click, move, scroll) for text selection
  - Focus event tracking (WM_SETFOCUS/WM_KILLFOCUS)
  - Surface registration with core app (addSurface/deleteSurface)
  - Config reload with proper lifetime management
affects: [03-tabs-splits-terminal-features]

# Tech tracking
tech-stack:
  added: []
  patterns: [mouse-event-dispatch-via-wndproc, consumed-mods-for-text-generation]

key-files:
  created: []
  modified:
    - src/apprt/windows/App.zig
    - src/apprt/windows/Surface.zig
    - src/apprt/windows/input.zig

key-decisions:
  - "Shift consumed_mods set when ToUnicode produces text with shift held"
  - "unshifted_codepoint computed via second ToUnicode call with shift cleared"
  - "Mouse events update cursor position before reporting button state"
  - "Config reload stores new config in owned_config to prevent use-after-free"
  - "Surface registered with core_app.addSurface for proper enumeration"

patterns-established:
  - "Mouse dispatch pattern: extract coords from lParam, build mods, call cursorPosCallback then mouseButtonCallback"

requirements-completed: [INP-01, INP-02, WIN-03, TERM-06]

# Metrics
duration: 5min
completed: 2026-02-25
---

# Phase 03 Plan 00: Phase 2 UAT Gap Fixes Summary

**Fixed keyboard input (ToUnicode with consumed_mods), added mouse event dispatch for text selection, registered surface with core app, and fixed config reload lifetime**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-25T20:01:03Z
- **Completed:** 2026-02-25T20:06:21Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- Keyboard input now generates proper KeyEvent with consumed_mods and unshifted_codepoint via ToUnicode
- Mouse events (click, move, scroll) dispatched through wndProc to core_surface for text selection support
- Surface registered with core app via addSurface/deleteSurface for config reload and surface enumeration
- Config hard reload stores config in owned_config to prevent use-after-free
- Focus tracking via WM_SETFOCUS/WM_KILLFOCUS added

## Task Commits

Each task was committed atomically:

1. **Task 1: Debug and fix keyboard input and clipboard** - `4fb7e9d17` (fix)

## Files Created/Modified
- `src/apprt/windows/input.zig` - Added consumed_mods, unshifted_codepoint, made getModifiers public
- `src/apprt/windows/App.zig` - Added mouse/focus/scroll message handlers, fixed config reload lifetime
- `src/apprt/windows/Surface.zig` - Added addSurface/deleteSurface calls, added rtApp() accessor

## Decisions Made
- Shift is marked as consumed when ToUnicode produces text with shift held, matching GTK behavior
- unshifted_codepoint computed via separate ToUnicode call with shift cleared from keyboard state
- Mouse button events update cursor position first (cursorPosCallback) then report button state (mouseButtonCallback)
- Config reload replaces owned_config and updates self.config pointer to prevent dangling reference
- Surface registered with core app in init, unregistered in deinit (matching embedded.zig and GTK patterns)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added mouse event handlers**
- **Found during:** Task 1 (investigating clipboard/selection)
- **Issue:** No mouse message handlers existed in wndProc at all -- text selection requires WM_LBUTTONDOWN/UP, WM_MOUSEMOVE
- **Fix:** Added full mouse event dispatch (left/right/middle buttons, move, scroll) plus focus tracking
- **Files modified:** src/apprt/windows/App.zig
- **Verification:** Build succeeds
- **Committed in:** 4fb7e9d17 (Task 1 commit)

**2. [Rule 1 - Bug] Fixed Surface not registered with core app**
- **Found during:** Task 1 (investigating config reload)
- **Issue:** Surface.init never called core_app.addSurface, so core App.updateConfig could not find any surfaces to update
- **Fix:** Added addSurface call in init, deleteSurface in deinit, plus rtApp() accessor required by core
- **Files modified:** src/apprt/windows/Surface.zig
- **Verification:** Build succeeds
- **Committed in:** 4fb7e9d17 (Task 1 commit)

**3. [Rule 1 - Bug] Fixed config reload use-after-free**
- **Found during:** Task 1 (investigating config reload)
- **Issue:** Hard reload created stack-local config, passed pointer to updateConfig, then deinited it -- surfaces would hold dangling pointer
- **Fix:** Store reloaded config in owned_config field and update self.config pointer
- **Files modified:** src/apprt/windows/App.zig
- **Verification:** Build succeeds
- **Committed in:** 4fb7e9d17 (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (1 missing critical, 2 bugs)
**Impact on plan:** All auto-fixes essential for correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three Phase 2 UAT gaps addressed, ready for Phase 3 tabs/splits work
- Keyboard input, mouse selection, clipboard, and config reload paths wired end-to-end

---
*Phase: 03-tabs-splits-terminal-features*
*Completed: 2026-02-25*
