---
phase: 04-platform-integration-distribution
plan: 02
subsystem: ui
tags: [win32, quick-terminal, dropdown, hotkey, animation, WS_POPUP]

# Dependency graph
requires:
  - phase: 03-tabs-splits-terminal-features
    provides: Tab, Surface, SplitTree modules for terminal content
provides:
  - QuickTerminal.zig dropdown terminal with slide animation
  - Global hotkey (Ctrl+`) registration and WM_HOTKEY dispatch
  - toggle_quick_terminal action in performAction
affects: [04-platform-integration-distribution]

# Tech tracking
tech-stack:
  added: [RegisterHotKey, SetTimer animation, MonitorFromPoint]
  patterns: [lazy HWND creation, WS_POPUP topmost popup, WM_ACTIVATE auto-hide]

key-files:
  created:
    - src/apprt/windows/QuickTerminal.zig
  modified:
    - src/apprt/windows/App.zig

key-decisions:
  - "Ctrl+` as default global hotkey with MOD_NOREPEAT (no keybind config parsing yet)"
  - "WS_EX_TOOLWINDOW to exclude Quick Terminal from taskbar/Alt+Tab"
  - "Linear interpolation animation with step=diff/5, min 4px per tick at ~60fps"
  - "Tab reuse from existing Tab module -- Quick Terminal owns a single Tab with persistent shell"

patterns-established:
  - "Lazy HWND creation: popup window created on first toggle, not at App.init"
  - "Animation via SetTimer/KillTimer at 16ms interval with SetWindowPos repositioning"

requirements-completed: [PLAT-02]

# Metrics
duration: 3min
completed: 2026-02-25
---

# Phase 4 Plan 2: Quick Terminal Summary

**Quake-style dropdown terminal with global hotkey (Ctrl+`), slide animation, and auto-hide on focus loss**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-26T00:15:34Z
- **Completed:** 2026-02-26T00:19:02Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- QuickTerminal.zig module with full dropdown lifecycle (create, show, hide, destroy)
- Global hotkey Ctrl+` via RegisterHotKey dispatching WM_HOTKEY to toggle
- Slide-down/slide-up animation at ~60fps using SetTimer + SetWindowPos
- Auto-hide on WM_ACTIVATE with WA_INACTIVE (focus loss)
- Multi-monitor aware positioning via MonitorFromPoint (80% width, 40% height, centered)
- Persistent shell session survives hide/show cycles

## Task Commits

Each task was committed atomically:

1. **Task 1: Create QuickTerminal.zig module** - `a9fc53f65` (feat)
2. **Task 2: Integrate Quick Terminal into App.zig with global hotkey** - `ffdc61244` (feat)

## Files Created/Modified
- `src/apprt/windows/QuickTerminal.zig` - Dropdown terminal window with lazy creation, animation, auto-hide
- `src/apprt/windows/App.zig` - QuickTerminal field, RegisterHotKey, WM_HOTKEY dispatch, performAction case

## Decisions Made
- Used Ctrl+` as hardcoded default global hotkey (config-based keybind parsing deferred)
- WS_EX_TOOLWINDOW style excludes the Quick Terminal from taskbar and Alt+Tab
- Linear interpolation animation (step = diff/5, clamped to min 4px) for smooth ~200ms slide
- Tab module reused directly -- QuickTerminal owns a Tab with a single Surface for the persistent shell
- MonitorFromPoint with cursor position for multi-monitor support (follows cursor to correct monitor)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Quick Terminal feature complete and integrated into App lifecycle
- Ready for Phase 4 Plan 3 (remaining platform integration work)
- Config-based keybind for toggle_quick_terminal can be wired when keybind parsing is extended

---
*Phase: 04-platform-integration-distribution*
*Completed: 2026-02-25*
