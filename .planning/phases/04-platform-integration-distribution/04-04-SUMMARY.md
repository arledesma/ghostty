---
phase: 04-platform-integration-distribution
plan: 04
subsystem: packaging, notifications
tags: [msix, vclibs, toast, win32, winrt]

# Dependency graph
requires:
  - phase: 04-platform-integration-distribution/01
    provides: AppxManifest.xml MSIX packaging foundation
  - phase: 04-platform-integration-distribution/03
    provides: Toast notification COM vtables and Toast.zig
provides:
  - VCLibs framework PackageDependency in AppxManifest.xml for automatic runtime resolution
  - Toast click-to-tab activation with launch attribute encoding
affects: [msix-packaging, installer, notification-ux]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Toast launch attribute encoding (tab:N) for notification activation context
    - Store-and-activate pattern for warm-start toast click handling

key-files:
  created: []
  modified:
    - pkg/windows/AppxManifest.xml
    - src/apprt/windows/Toast.zig
    - src/apprt/windows/App.zig

key-decisions:
  - "Store last_tab_index on Toast struct for warm-start activation instead of COM callback"
  - "Defer full INotificationActivationCallback COM registration to future work (cold-start scenario)"
  - "VCLibs 14.0.30704.0 MinVersion targeting VS 2022 17.x era for broad compatibility"

patterns-established:
  - "Toast launch attribute encoding: launch=\"tab:N\" for tab context"

requirements-completed: [PLAT-01, PLAT-03]

# Metrics
duration: 2min
completed: 2026-02-26
---

# Phase 4 Plan 4: Gap Closure Summary

**VCLibs framework dependency in AppxManifest.xml for auto-resolving C runtime, plus toast click-to-tab activation via launch attribute encoding**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-26T00:45:10Z
- **Completed:** 2026-02-26T00:47:17Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- AppxManifest.xml declares Microsoft.VCLibs.140.00 as PackageDependency so MSIX installer auto-resolves C runtime
- Toast notifications encode originating tab index in launch attribute (launch="tab:N")
- Toast.handleActivation() brings window to foreground and switches to correct tab on click
- App.activateFromToast() provides public API for toast-driven tab activation

## Task Commits

Each task was committed atomically:

1. **Task 1: Add VCLibs framework package dependency** - `e1c6a1411` (feat)
2. **Task 2: Implement toast click tab activation** - `062523f75` (feat)

## Files Created/Modified
- `pkg/windows/AppxManifest.xml` - Added PackageDependency for Microsoft.VCLibs.140.00
- `src/apprt/windows/Toast.zig` - Pass tab_index through, add launch attribute to XML, store last_tab_index, add handleActivation()
- `src/apprt/windows/App.zig` - Add activateFromToast() method, add SetForegroundWindow extern

## Decisions Made
- Used simple store-last_tab_index approach for toast activation rather than full COM INotificationActivationCallback (deferred for cold-start)
- VCLibs MinVersion 14.0.30704.0 chosen for VS 2022 17.x compatibility coverage
- No Windows App SDK dependency added -- project uses raw Win32/WinRT COM directly

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All Phase 4 gaps closed; MSIX packaging has runtime dependency auto-resolution
- Toast notification UX complete with tab-aware click handling
- Phase 4 complete, ready for milestone completion

---
*Phase: 04-platform-integration-distribution*
*Completed: 2026-02-26*
