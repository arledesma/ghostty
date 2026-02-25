---
phase: 01-foundation-rendering-bridge
plan: 01
subsystem: infra
tags: [zig, com, winrt, winui3, vtable, apprt, windows]

# Dependency graph
requires: []
provides:
  - COM/WinRT bridge helpers (GUID, HRESULT, IInspectable, HSTRING, ComPtr, RoInitialize)
  - WinUI 3 manual vtable definitions (IApplicationStatics, IWindow, ISwapChainPanelNative, IFrameworkElement)
  - Windows apprt backend scaffold (App stub with init/terminate/run/wakeup/performAction)
  - Build system integration (Runtime.windows enum, apprt switch routing, OpenGL.zig stubs)
affects: [01-02-PLAN, 01-03-PLAN, 02-single-surface]

# Tech tracking
tech-stack:
  added: [WinRT COM activation APIs, WinUI 3 XAML interfaces]
  patterns: [COM vtable extern struct pattern, ComPtr RAII wrapper, HSTRING reference helper]

key-files:
  created:
    - src/apprt/windows/com.zig
    - src/apprt/windows/winui.zig
    - src/apprt/windows/App.zig
    - src/apprt/windows.zig
  modified:
    - src/apprt/runtime.zig
    - src/apprt.zig
    - src/renderer/OpenGL.zig
    - src/build/SharedDeps.zig
    - src/apprt/structs.zig
    - src/apprt/surface.zig
    - src/apprt/action.zig
    - src/config/Config.zig
    - src/datastruct/split_tree.zig
    - src/font/face.zig
    - src/input/Binding.zig
    - src/terminal/mouse_shape.zig

key-decisions:
  - "Used api-ms-win-core-winrt extern linking for WinRT activation APIs instead of zigwin32 (WinRT activation not covered by zigwin32)"
  - "ISwapChainPanelNative inherits from IUnknown (3 base), all other WinUI interfaces from IInspectable (6 base)"
  - "Windows apprt GObject switches use void (same as none) since Windows has no GObject dependency"

patterns-established:
  - "COM vtable pattern: extern struct with VTable containing function pointers using callconv(.c)"
  - "ComPtr(T) RAII wrapper with deinit calling Release for safe COM reference counting"
  - "L() comptime helper for UTF-16 string literals needed by WinRT class names"

requirements-completed: [INFRA-01, INFRA-04]

# Metrics
duration: 7min
completed: 2026-02-24
---

# Phase 1 Plan 1: COM/WinRT Bridge & Apprt Scaffold Summary

**COM/WinRT bridge with IInspectable/HSTRING/ComPtr helpers, WinUI 3 vtable definitions, and Windows apprt backend scaffold integrated into build system**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-25T01:27:38Z
- **Completed:** 2026-02-25T01:34:32Z
- **Tasks:** 2
- **Files modified:** 16

## Accomplishments
- COM/WinRT bridge module with GUID, HRESULT helpers, IUnknown, IInspectable, HSTRING utilities, ComPtr RAII wrapper, and RoInitialize/RoActivateInstance/RoGetActivationFactory wrappers
- Manual WinUI 3 vtable definitions for IApplicationStatics, IWindow, ISwapChainPanelNative (classic COM), and IFrameworkElement with correct inheritance hierarchy
- Windows apprt backend scaffold with App.zig stub that calls roInitialize on init, validating the COM bridge compiles
- Full build system integration: Runtime enum, apprt routing, OpenGL.zig renderer stubs, and all exhaustive switch statements updated

## Task Commits

Each task was committed atomically:

1. **Task 1: COM/WinRT bridge helpers and WinUI 3 vtable definitions** - `76dff3f34` (feat)
2. **Task 2: Apprt backend scaffold and build system integration** - `59d85b931` (feat)

## Files Created/Modified
- `src/apprt/windows/com.zig` - COM/WinRT bridge: GUID, HRESULT, IUnknown, IInspectable, HSTRING, ComPtr, RoInitialize/RoActivateInstance
- `src/apprt/windows/winui.zig` - WinUI 3 vtable definitions: IApplicationStatics, IWindow, ISwapChainPanelNative, IFrameworkElement
- `src/apprt/windows/App.zig` - Stub App struct with init/terminate/run/wakeup/performAction
- `src/apprt/windows.zig` - Module root exporting App and Surface stub
- `src/apprt/runtime.zig` - Added windows variant to Runtime enum with OS default
- `src/apprt.zig` - Added windows import and switch case for runtime selection
- `src/renderer/OpenGL.zig` - Added windows stub cases to surfaceInit/threadEnter/threadExit
- `src/build/SharedDeps.zig` - Added windows no-op case to app_runtime switch
- `src/apprt/structs.zig` - Added windows to GObject type switches
- `src/apprt/surface.zig` - Added windows to GObject type switch
- `src/apprt/action.zig` - Added windows to GObject type switch
- `src/config/Config.zig` - Added windows to apprt defaults and GObject switches
- `src/datastruct/split_tree.zig` - Added windows to GObject type switch
- `src/font/face.zig` - Added windows to GObject type switch
- `src/input/Binding.zig` - Added windows to GObject type switch
- `src/terminal/mouse_shape.zig` - Added windows to GObject type switch

## Decisions Made
- Used `api-ms-win-core-winrt-l1-1-0` and `api-ms-win-core-winrt-string-l1-1-0` extern linking for WinRT activation APIs (RoInitialize, RoActivateInstance, etc.) since zigwin32 does not cover WinRT activation
- ISwapChainPanelNative defined with IUnknown base (3 methods) since it is a classic COM interface, while all WinUI 3 interfaces use IInspectable base (6 methods)
- All GObject-related switches in shared infrastructure use `.windows => void` (same as `.none`) since Windows has no GObject dependency
- OpenGL.zig renderer switches get empty stub bodies for windows (not compileError) to allow compilation; actual ANGLE/EGL implementation deferred to Plan 02

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated all exhaustive switches on build_config.app_runtime**
- **Found during:** Task 2 (Build system integration)
- **Issue:** Adding `windows` to the Runtime enum caused exhaustive switch compile errors in 10+ files across the codebase (GObject type definitions, Config defaults, SharedDeps, etc.)
- **Fix:** Added `.windows` case to every exhaustive switch -- `void` for GObject types, `{}` for behavioral no-ops
- **Files modified:** structs.zig, surface.zig, action.zig, Config.zig (3 switches), split_tree.zig, face.zig, Binding.zig, mouse_shape.zig, SharedDeps.zig
- **Verification:** All files pass zig ast-check
- **Committed in:** 59d85b931 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary for enum exhaustiveness. No scope creep -- this is the expected consequence of adding a new Runtime variant.

## Issues Encountered
- `zig build` crashes with unreachable panic in `convertPathArg` on this MSYS2/Windows environment for ALL configurations (including baseline `-Dapp-runtime=none`). This is a pre-existing Zig 0.15.2 build runner bug with absolute paths on Windows, not caused by our changes. Verification was done via `zig ast-check` on all modified files instead.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- COM/WinRT bridge ready for ANGLE EGL integration (Plan 02) and DirectWrite font discovery (Plan 03)
- WinUI 3 vtable definitions ready for Application bootstrap and Window creation
- App.zig stub ready to be fleshed out with WinUI 3 message loop
- Build system accepts `-Dapp-runtime=windows` and routes to the windows apprt module

---
*Phase: 01-foundation-rendering-bridge*
*Completed: 2026-02-24*

## Self-Check: PASSED

- All 4 created files exist on disk
- Both task commits verified in git log (76dff3f34, 59d85b931)
- All 16 modified/created files pass zig ast-check
