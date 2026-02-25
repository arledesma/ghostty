---
phase: 03-tabs-splits-terminal-features
plan: 02
subsystem: ui
tags: [win32, splits, binary-tree, wgl, multi-surface, hwnd]

# Dependency graph
requires:
  - phase: 03-tabs-splits-terminal-features/01
    provides: "Multi-tab architecture with ArrayList of Tab structs, child HWND per tab"
provides:
  - "SplitTree.zig binary tree for split pane layout"
  - "Split creation, removal, layout, navigation, and resize operations"
  - "performAction handlers for new_split, goto_split, resize_split, equalize_splits, toggle_split_zoom"
  - "Tab.zig refactored to own a SplitTree root instead of single Surface"
  - "Surface close via split tree removal instead of tab_index"
affects: [03-tabs-splits-terminal-features, 04-platform-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [binary-tree-split-layout, focused-surface-tracking, split-zoom-toggle]

key-files:
  created:
    - src/apprt/windows/SplitTree.zig
  modified:
    - src/apprt/windows/App.zig
    - src/apprt/windows/Tab.zig
    - src/apprt/windows/Surface.zig

key-decisions:
  - "Binary tree Node union (leaf/branch) for split layout rather than flat list"
  - "SplitTree operations are free functions taking *Node, not methods on a struct"
  - "Tab owns focused_surface pointer for tracking active split pane"
  - "Surface.close delegates to App.closeSurface for split-aware removal"
  - "Split zoom hides sibling HWNDs via ShowWindow rather than detaching from tree"

patterns-established:
  - "SplitTree.layout recursively positions all leaf HWNDs via MoveWindow"
  - "focusDirection uses in-order traversal for prev/next and directional navigation"
  - "resize propagates up tree to find matching branch direction"
  - "Tab.splitSurface creates new child HWND + Surface and splits the focused leaf"

requirements-completed: [TAB-03, TAB-04]

# Metrics
duration: 7min
completed: 2026-02-25
---

# Phase 03 Plan 02: Split Pane Support Summary

**Binary tree split layout with create/navigate/resize/zoom via performAction dispatch, each split a child HWND with independent WGL context**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-25T20:21:54Z
- **Completed:** 2026-02-25T20:29:03Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created SplitTree.zig with binary tree (Node union: leaf/branch) for split pane layout
- Refactored Tab.zig from single Surface to SplitTree root with focused_surface tracking
- Added performAction handlers: new_split, goto_split, resize_split, equalize_splits, toggle_split_zoom
- Split zoom toggles between focused-only and full-tree layout via ShowWindow hide/show

## Task Commits

Each task was committed atomically:

1. **Task 1: SplitTree data structure and Tab integration** - `9197639a2` (feat)
2. **Task 2: performAction handlers for splits** - `76644d5d9` (feat)

## Files Created/Modified
- `src/apprt/windows/SplitTree.zig` - Binary tree with Node union, split/remove/layout/navigate/resize/equalize/zoom operations
- `src/apprt/windows/Tab.zig` - Refactored to own SplitTree root, focused_surface, splitSurface/removeSurface methods
- `src/apprt/windows/App.zig` - Split performAction handlers, closeSurface, getActiveTab, notifyActiveSurfaceSizes
- `src/apprt/windows/Surface.zig` - Removed tab_index, close delegates to App.closeSurface

## Decisions Made
- Binary tree Node union (leaf Surface pointer, branch with direction/ratio/first/second) -- natural recursive structure for split layout
- SplitTree operations as free functions on *Node rather than struct methods -- matches Zig idiom for tree operations
- Tab.focused_surface tracks which split pane has focus -- avoids searching tree on every input event
- Surface.close calls App.closeSurface which searches all tabs for the surface -- decouples surface from tab index
- Split zoom hides siblings via ShowWindow(SW_HIDE) rather than restructuring tree -- simpler toggle, preserves tree state

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Unused return value in SplitTree.resize**
- **Found during:** Task 2 (compilation)
- **Issue:** `resizeInner` returns bool but `resize` wrapper ignored it; Zig 0.15 treats ignored non-void returns as errors
- **Fix:** Added `_ = resizeInner(...)` to explicitly discard the propagation flag
- **Files modified:** src/apprt/windows/SplitTree.zig
- **Verification:** `zig build -Dapp-runtime=windows` succeeds
- **Committed in:** 76644d5d9 (Task 2 commit)

**2. [Rule 3 - Blocking] Missing SetFocus extern in App.zig**
- **Found during:** Task 2 (compilation)
- **Issue:** goto_split handler calls SetFocus which was only declared in Tab.zig, not App.zig
- **Fix:** Added `extern "user32" fn SetFocus` declaration to App.zig
- **Files modified:** src/apprt/windows/App.zig
- **Verification:** `zig build -Dapp-runtime=windows` succeeds
- **Committed in:** 76644d5d9 (Task 2 commit)

**3. [Rule 3 - Blocking] Tab.layoutZoomed not public**
- **Found during:** Task 2 (compilation)
- **Issue:** toggle_split_zoom handler in App.zig calls tab.layoutZoomed which was private
- **Fix:** Changed `fn layoutZoomed` to `pub fn layoutZoomed` in Tab.zig
- **Files modified:** src/apprt/windows/Tab.zig
- **Verification:** `zig build -Dapp-runtime=windows` succeeds
- **Committed in:** 76644d5d9 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All fixes necessary for compilation. No scope creep.

## Issues Encountered
None beyond the auto-fixed compilation issues.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Split pane support complete, ready for terminal features (03-03)
- All split operations dispatch through performAction
- Tab/SplitTree architecture supports arbitrary nesting depth

---
*Phase: 03-tabs-splits-terminal-features*
*Completed: 2026-02-25*
