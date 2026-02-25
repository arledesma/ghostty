---
phase: 03-tabs-splits-terminal-features
plan: 04
subsystem: ui
tags: [win32, gdi, scrollbar, wm_paint, hwnd]

# Dependency graph
requires:
  - phase: 03-tabs-splits-terminal-features
    provides: "scroll state fields on Surface (scroll_total/offset/view_len) and InvalidateRect trigger from App.zig scrollbar action"
provides:
  - "Visible GDI-painted scrollbar overlay on terminal surfaces with scrollback"
  - "Tab pointer stored in child HWND GWLP_USERDATA for WM_PAINT access"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GDI FillRect scrollbar painting in Tab childWndProc WM_PAINT handler"
    - "GWLP_USERDATA back-pointer from child HWND to Tab struct"

key-files:
  created: []
  modified:
    - "src/apprt/windows/Tab.zig"

key-decisions:
  - "GDI FillRect painting on existing child HWND rather than separate scrollbar HWND"
  - "Dark gray track (0x333333) with light gray thumb (0x888888) for visibility"
  - "Minimum thumb height of 20px to remain clickable/visible"

patterns-established:
  - "WM_PAINT handler in childWndProc with GWLP_USERDATA Tab pointer retrieval"

requirements-completed: [TERM-02]

# Metrics
duration: 2min
completed: 2026-02-25
---

# Phase 3 Plan 4: Scrollbar Painting Summary

**GDI-painted scrollbar overlay in Tab childWndProc via WM_PAINT with track and proportional thumb reflecting scroll position**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-25T21:25:30Z
- **Completed:** 2026-02-25T21:27:59Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Scrollbar track and thumb painted on right edge of terminal surface when scrollback exists
- Thumb size proportional to visible viewport relative to total scrollback
- Thumb position accurately reflects scroll offset (bottom when at latest output, top when scrolled to beginning)
- Scrollbar hidden when no scrollback content (scroll_total <= scroll_view_len)

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire Tab pointer into child HWND and paint scrollbar on WM_PAINT** - `79efa5acb` (feat)

## Files Created/Modified
- `src/apprt/windows/Tab.zig` - Added GDI externs (BeginPaint, EndPaint, FillRect, CreateSolidBrush, DeleteObject), PAINTSTRUCT type, WM_PAINT handler in childWndProc, paintScrollbars and paintSurfaceScrollbar methods, GWLP_USERDATA Tab pointer storage in init

## Decisions Made
- Used GDI FillRect on existing child HWND rather than creating a separate scrollbar HWND (consistent with tab bar painting approach in App.zig)
- Dark gray (0x333333) track with light gray (0x888888) thumb for visibility on dark terminal backgrounds
- Minimum 20px thumb height to remain visible even with very large scrollback

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TERM-02 verification gap is now closed
- All Phase 3 plans (01-04) complete
- Phase complete, ready for transition to Phase 4

## Self-Check: PASSED

- FOUND: src/apprt/windows/Tab.zig
- FOUND: 79efa5acb (task 1 commit)

---
*Phase: 03-tabs-splits-terminal-features*
*Completed: 2026-02-25*
