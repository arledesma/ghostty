---
phase: 03-tabs-splits-terminal-features
plan: 01
subsystem: ui
tags: [win32, tabs, dwm, gdi, wgl, multi-surface]

# Dependency graph
requires:
  - phase: 02-single-terminal-surface
    provides: "Single Surface with WGL context, input handling, clipboard, fullscreen"
provides:
  - "Multi-tab architecture with ArrayList of Tab structs"
  - "Tab.zig with child HWND lifecycle and show/hide management"
  - "Custom tab bar in titlebar via DwmExtendFrameIntoClientArea"
  - "performAction handlers for new_tab, close_tab, goto_tab, move_tab"
  - "Tab drag reordering with SetCapture/ReleaseCapture"
affects: [03-tabs-splits-terminal-features, 04-platform-integration]

# Tech tracking
tech-stack:
  added: [dwmapi/DwmExtendFrameIntoClientArea, gdi32/TextOutW/FillRect]
  patterns: [child-hwnd-per-tab, tab-bar-in-titlebar]

key-files:
  created:
    - src/apprt/windows/Tab.zig
  modified:
    - src/apprt/windows/App.zig
    - src/apprt/windows/Surface.zig

key-decisions:
  - "Child HWND per tab with independent WGL context rather than shared HWND"
  - "DwmExtendFrameIntoClientArea for tab bar instead of WinUI TabView"
  - "GDI TextOutW/FillRect for tab painting rather than Direct2D"
  - "Drag state tracked via drag_active flag + SetCapture rather than timer polling"
  - "ArrayList(Tab) with Zig 0.15 unmanaged API (allocator per method call)"

patterns-established:
  - "Tab lifecycle: Tab.init creates child HWND, Tab.deinit destroys it"
  - "Tab visibility: show/hide child HWND, update active_tab index"
  - "Tab bar painting: GDI in WM_PAINT, invalidated via redrawTabBar"
  - "WM_NCHITTEST: HTCAPTION for empty tab bar, HTCLIENT for tab items"

requirements-completed: [TAB-01, TAB-02, TAB-05, TAB-06]

# Metrics
duration: 10min
completed: 2026-02-25
---

# Phase 03 Plan 01: Tab Architecture Summary

**Multi-tab terminal with custom GDI tab bar in titlebar via DwmExtendFrameIntoClientArea, supporting create/close/switch/reorder/color-code tabs**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-25T20:08:51Z
- **Completed:** 2026-02-25T20:18:27Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Refactored App.zig from single-surface model to multi-tab ArrayList architecture
- Created Tab.zig with child HWND lifecycle, WGL context per tab, show/hide/resize
- Tab bar rendered in titlebar area via DWM frame extension with GDI painting
- Full performAction coverage: new_tab, close_tab, goto_tab, move_tab
- Tab drag reordering with SetCapture/ReleaseCapture and VK_LBUTTON safety check
- Tab color support via optional COLORREF field with color indicator strip

## Task Commits

Each task was committed atomically:

1. **Task 1: Tab data structure and multi-surface App refactor** - `5b6cbe629` (feat)
2. **Task 2: Tab reordering and keyboard navigation** - `961e16c57` (feat)

## Files Created/Modified
- `src/apprt/windows/Tab.zig` - Tab struct with child HWND lifecycle, show/hide, resize, GDI constants
- `src/apprt/windows/App.zig` - Multi-tab architecture with createTab/closeTab/switchToTab, tab bar painting, DWM frame extension, drag reorder, performAction handlers
- `src/apprt/windows/Surface.zig` - Added tab_index field, child HWND parameter in init, close delegates to App.closeTab

## Decisions Made
- Child HWND per tab (WS_CHILD | WS_CLIPCHILDREN) with CS_OWNDC for independent WGL contexts -- matches existing wgl.initContext pattern
- DwmExtendFrameIntoClientArea with cyTopHeight=30px for tab bar in titlebar -- no WinUI dependency needed
- GDI (TextOutW, FillRect, CreateSolidBrush) for tab painting -- lightweight, no additional dependencies
- Zig 0.15 ArrayList uses unmanaged API (allocator passed to append/deinit) -- discovered during build
- Tab drag uses drag_active flag + SetCapture rather than GetKeyState polling in WM_MOUSEMOVE

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Zig 0.15 ArrayList API change**
- **Found during:** Task 1 (compilation)
- **Issue:** `std.ArrayList(T).init(alloc)` no longer exists in Zig 0.15; the type is now unmanaged with allocator passed per call
- **Fix:** Changed to `std.ArrayList(Tab) = .{}` initialization and pass `self.alloc` to `append()` and `deinit()`
- **Files modified:** src/apprt/windows/App.zig
- **Verification:** `zig build -Dapp-runtime=windows` succeeds
- **Committed in:** 5b6cbe629 (Task 1 commit)

**2. [Rule 1 - Bug] Anonymous extern struct type mismatch**
- **Found during:** Task 1 (compilation)
- **Issue:** Inline `extern struct { x: LONG, y: LONG }` at call site was a different type than the one in the function declaration
- **Fix:** Defined named `POINT` extern struct and used `ScreenToClient` with proper capitalization
- **Files modified:** src/apprt/windows/App.zig
- **Verification:** `zig build -Dapp-runtime=windows` succeeds
- **Committed in:** 5b6cbe629 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes necessary for compilation. No scope creep.

## Issues Encountered
None beyond the auto-fixed compilation issues.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Multi-tab architecture complete, ready for split views (03-02)
- Tab management integrated into performAction dispatch
- Each tab has independent child HWND and WGL context

---
*Phase: 03-tabs-splits-terminal-features*
*Completed: 2026-02-25*
