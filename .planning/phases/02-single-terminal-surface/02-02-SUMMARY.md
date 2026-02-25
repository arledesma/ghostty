---
phase: 02-single-terminal-surface
plan: 02
subsystem: apprt
tags: [win32, clipboard, dpi, fullscreen, theme, dwm, registry]

# Dependency graph
requires:
  - phase: 02-single-terminal-surface
    plan: 01
    provides: rt_surface interface, core Surface wiring, message loop, performAction dispatch
provides:
  - Win32 clipboard read/write via OpenClipboard/SetClipboardData with CF_UNICODETEXT and UTF-16 conversion
  - Per-monitor DPI V2 awareness with WM_DPICHANGED handling
  - DPI-aware cell-snapped resize via AdjustWindowRectExForDpi
  - Fullscreen toggle saving/restoring window style and placement
  - Config hot-reload (soft and hard) via performAction dispatch
  - System dark/light theme detection via registry and WM_SETTINGCHANGE
  - Dark titlebar via DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE)
affects: [03-multi-surface, 04-platform-integration]

# Tech tracking
tech-stack:
  added: [dwmapi.dll, advapi32.dll]
  patterns: [Win32 clipboard with CF_UNICODETEXT UTF-16 conversion, registry theme detection, DwmSetWindowAttribute for titlebar theming]

key-files:
  created: []
  modified:
    - src/apprt/windows/Surface.zig
    - src/apprt/windows/App.zig

key-decisions:
  - "Win32 clipboard uses CF_UNICODETEXT with UTF-8/UTF-16 bidirectional conversion via std.unicode"
  - "completeClipboardRequest called synchronously after clipboard read (no async needed on Win32)"
  - "Fullscreen uses WS_POPUP|WS_VISIBLE borderless style filling monitor rect via MonitorFromWindow"
  - "System theme detected via HKCU registry AppsUseLightTheme DWORD (0=dark, 1=light)"
  - "DwmSetWindowAttribute with attribute 20 (DWMWA_USE_IMMERSIVE_DARK_MODE) for dark titlebar"
  - "DPI-aware cell-snapped resize uses AdjustWindowRectExForDpi instead of GetWindowRect/GetClientRect delta"

patterns-established:
  - "Clipboard pattern: OpenClipboard -> GetClipboardData/SetClipboardData -> CloseClipboard with GlobalAlloc for data"
  - "Theme pattern: registry read at init + WM_SETTINGCHANGE ImmersiveColorSet for runtime changes -> colorSchemeEvent"
  - "performAction pattern: comptime switch dispatching toggle_fullscreen, reload_config, config_change"

requirements-completed: [WIN-03, WIN-04, INP-01, TERM-05, TERM-06]

# Metrics
duration: 6min
completed: 2026-02-25
---

# Phase 2 Plan 2: Clipboard, DPI, Fullscreen, Config Reload, Theme Summary

**Win32 clipboard via CF_UNICODETEXT with UTF-16 conversion, per-monitor DPI V2 with WM_DPICHANGED, fullscreen toggle, config hot-reload, and dark/light theme following via DWM and registry**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-25T18:24:00Z
- **Completed:** 2026-02-25T18:30:08Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Surface.zig clipboard read (clipboardRequest) and write (setClipboard) using Win32 OpenClipboard/GetClipboardData/SetClipboardData with CF_UNICODETEXT and UTF-8/UTF-16 bidirectional conversion
- Per-monitor DPI V2 awareness via SetProcessDpiAwarenessContext at startup, WM_DPICHANGED handler resizing window with suggested rect and notifying core via contentScaleCallback
- Cell-snapped resize updated to use AdjustWindowRectExForDpi for DPI-aware non-client area calculation
- Fullscreen toggle saving/restoring window style and placement via GetWindowPlacement/SetWindowPlacement/MonitorFromWindow
- Config hot-reload via performAction dispatch: soft reload re-applies existing config, hard reload loads from disk
- System theme detection via registry AppsUseLightTheme and WM_SETTINGCHANGE ImmersiveColorSet, applying dark titlebar via DwmSetWindowAttribute

## Task Commits

Each task was committed atomically:

1. **Task 1: Clipboard support and DPI scaling** - `d4b681e84` (feat)
2. **Task 2: Fullscreen toggle, config hot-reload, and theme following** - `d8bdc4673` (feat)

## Files Created/Modified
- `src/apprt/windows/Surface.zig` - Clipboard read/write with Win32 APIs, contentScaleCallback for DPI changes
- `src/apprt/windows/App.zig` - DPI awareness setup, WM_DPICHANGED/WM_SETTINGCHANGE handlers, fullscreen toggle, config reload, theme detection via registry, dark titlebar via DWM

## Decisions Made
- Clipboard read uses synchronous completeClipboardRequest (Win32 clipboard access is inherently synchronous, no async callback needed unlike GTK)
- Fullscreen uses WS_POPUP|WS_VISIBLE borderless style rather than exclusive fullscreen (matches other terminal emulators, avoids display mode switch)
- Theme detection reads AppsUseLightTheme DWORD from registry; defaults to dark if registry read fails
- DwmSetWindowAttribute attribute 20 used (Windows 10 20H1+ / Windows 11); no fallback to attribute 19 for older builds
- AdjustWindowRectExForDpi replaces GetWindowRect/GetClientRect delta for more accurate DPI-aware non-client area sizing

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Zig ast-check flagged "pointless discard of function parameter" for `_ = value` in toggle_fullscreen arm of performAction comptime switch; resolved by removing the discard since value is used in other arms

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full single-terminal surface feature set complete: rendering, input, clipboard, DPI, fullscreen, config reload, theme
- Ready for Phase 3 multi-surface work (tabs, splits) which will refactor App to manage multiple Surface instances
- performAction pattern established for adding future action dispatches

## Self-Check: PASSED

All files exist, all commit hashes verified.

---
*Phase: 02-single-terminal-surface*
*Completed: 2026-02-25*
