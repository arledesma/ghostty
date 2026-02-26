---
phase: 04-platform-integration-distribution
plan: 01
subsystem: packaging
tags: [msix, windows-store, makeappx, signtool, sideloading]

# Dependency graph
requires:
  - phase: 02-single-window-rendering
    provides: compiled ghostty.exe binary for packaging
provides:
  - MSIX package manifest (AppxManifest.xml) with app identity and capabilities
  - Build script for creating distributable .msix packages
  - Placeholder icon assets for Windows Store and Start menu
affects: [04-02, 04-03]

# Tech tracking
tech-stack:
  added: [MakeAppx.exe, SignTool.exe]
  patterns: [MSIX packaging pipeline, self-signed certificate generation]

key-files:
  created:
    - pkg/windows/AppxManifest.xml
    - pkg/windows/build-msix.sh
    - pkg/windows/assets/Square44x44Logo.png
    - pkg/windows/assets/Square150x150Logo.png
    - pkg/windows/assets/StoreLogo.png

key-decisions:
  - "Placeholder CLSID for toast notification activation stubs -- will be replaced in PLAT-03"
  - "uap10:RuntimeBehavior=win32App and TrustLevel=mediumIL for full-trust desktop app model"
  - "Self-signed cert uses CN=GhosttyDev matching Publisher identity in manifest"

patterns-established:
  - "MSIX layout: binary + manifest + assets in staging directory, packed via MakeAppx"
  - "Windows SDK tool discovery: check PATH first, then default install locations"

requirements-completed: [PLAT-01]

# Metrics
duration: 2min
completed: 2026-02-25
---

# Phase 4 Plan 1: MSIX Packaging Pipeline Summary

**MSIX packaging pipeline with AppxManifest.xml, placeholder assets, and build-msix.sh for Windows Store and sideload distribution**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-26T00:15:26Z
- **Completed:** 2026-02-26T00:17:18Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- AppxManifest.xml with full identity, visual elements, toast notification stubs, and runFullTrust capability
- Placeholder PNG icon assets at all three required sizes (44x44, 150x150, 50x50)
- Build script that stages layout, invokes MakeAppx.exe, and optionally self-signs via SignTool

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AppxManifest.xml and placeholder assets** - `a5b6216d3` (feat)
2. **Task 2: Create MSIX build script** - `43643f910` (feat)

## Files Created/Modified
- `pkg/windows/AppxManifest.xml` - MSIX package manifest with identity, visual elements, and capabilities
- `pkg/windows/build-msix.sh` - Build script assembling layout and calling MakeAppx + SignTool
- `pkg/windows/assets/Square44x44Logo.png` - 44x44 placeholder icon (dark gray)
- `pkg/windows/assets/Square150x150Logo.png` - 150x150 placeholder icon (dark gray)
- `pkg/windows/assets/StoreLogo.png` - 50x50 store logo placeholder (dark gray)

## Decisions Made
- Used placeholder CLSID "00000000-0000-0000-0000-000000000001" for toast notification activation stubs to be replaced in PLAT-03
- uap10:RuntimeBehavior="win32App" and TrustLevel="mediumIL" for full desktop app access without elevation
- Self-signed certificate subject "CN=GhosttyDev" matches Publisher identity in manifest for valid sideload signing

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- MSIX manifest and build script ready for integration with CI/CD pipeline (plan 04-02)
- Toast notification CLSID stubs ready for PLAT-03 implementation
- Placeholder assets should be replaced with actual Ghostty icons before Store submission

## Self-Check: PASSED

All 5 created files verified present. Both task commits (a5b6216d3, 43643f910) verified in git log.

---
*Phase: 04-platform-integration-distribution*
*Completed: 2026-02-25*
