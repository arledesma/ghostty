# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-24)

**Core value:** A Windows user launches Ghostty and it feels like a first-class Windows application while rendering faster than any other terminal on the platform.
**Current focus:** Phase 4: Platform Integration and Distribution

## Current Position

Phase: 4 of 4 (Platform Integration and Distribution)
Plan: 4 of 4 in current phase
Status: Phase 4 Complete -- All plans executed (including gap closure)
Last activity: 2026-02-26 -- Completed 04-04-PLAN.md (Gap closure: VCLibs dependency + toast tab activation)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: 5.2min
- Total execution time: 1.18 hours

**By Phase:**

| Phase | Plans | Total  | Avg/Plan |
|-------|-------|--------|----------|
| 1     | 3     | 27min  | 9min     |
| 2     | 2     | 11min  | 5.5min   |
| 3     | 5     | 29min  | 5.8min   |
| 4     | 4     | 12min  | 3.0min   |

**Recent Trend:**

- Last 5 plans: 03-04 (2min), 04-01 (2min), 04-02 (3min), 04-03 (5min), 04-04 (2min)
- Trend: stable/accelerating

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 4-phase structure derived from dependency analysis -- COM/ANGLE derisking first, then single surface, then multi-surface, then platform integration
- [Roadmap]: INFRA requirements grouped into Phase 1 as foundation; all other phases build on validated infrastructure
- [01-01]: Used api-ms-win-core-winrt extern linking for WinRT activation APIs instead of zigwin32
- [01-01]: ISwapChainPanelNative inherits from IUnknown (3 base), all other WinUI interfaces from IInspectable (6 base)
- [01-01]: Windows apprt GObject switches use void (same as none) since Windows has no GObject dependency
- [01-02]: EGL functions declared as extern libEGL with Zig signatures instead of @cImport (no EGL headers needed)
- [01-02]: GLSL version header removed from shader files, prepended at comptime in Zig based on apprt.runtime
- [01-02]: Used #ifdef GL_ES preprocessor guards for GLES differences within same shader files (single source of truth)
- [01-02]: precision highp float/int for GLES (not mediump) to avoid precision issues in color math
- [01-03]: Manual COM vtable definitions for DirectWrite instead of zigwin32 (not in project deps)
- [01-03]: DirectWrite discovery in separate file (discovery/directwrite.zig) following face/ directory pattern
- [01-03]: hasCodepoint returns true for DW deferred faces -- charset metadata not carried, checked at load time
- [02-01]: GetMessageW (blocking) instead of PeekMessageW (spinning) for message loop efficiency
- [02-01]: WGL context released from main thread after init so renderer thread owns GL context
- [02-01]: Cell-snapped resize uses GetWindowRect/GetClientRect delta for non-client area calculation
- [02-01]: ToUnicode in WM_KEYDOWN for text generation; WM_CHAR suppressed
- [02-02]: Win32 clipboard uses CF_UNICODETEXT with synchronous completeClipboardRequest
- [02-02]: Fullscreen uses WS_POPUP|WS_VISIBLE borderless style filling monitor rect
- [02-02]: System theme via registry AppsUseLightTheme + WM_SETTINGCHANGE ImmersiveColorSet
- [02-02]: DwmSetWindowAttribute attribute 20 for dark titlebar (Windows 10 20H1+)
- [02-02]: AdjustWindowRectExForDpi for DPI-aware cell-snapped resize
- [03-00]: Shift consumed_mods set when ToUnicode produces text with shift held
- [03-00]: unshifted_codepoint via second ToUnicode call with shift cleared
- [03-00]: Mouse events update cursor position before reporting button state
- [03-00]: Config reload stores new config in owned_config to prevent use-after-free
- [03-00]: Surface registered with core_app.addSurface for proper enumeration
- [03-01]: Child HWND per tab with WS_CHILD|WS_CLIPCHILDREN for independent WGL contexts
- [03-01]: DwmExtendFrameIntoClientArea for tab bar in titlebar (no WinUI dependency)
- [03-01]: GDI TextOutW/FillRect for tab painting rather than Direct2D
- [03-01]: ArrayList(Tab) with Zig 0.15 unmanaged API (allocator per method call)
- [03-02]: Binary tree Node union (leaf/branch) for split layout rather than flat list
- [03-02]: SplitTree operations as free functions on *Node, not struct methods
- [03-02]: Tab.focused_surface tracks active split pane; Surface.close delegates to App.closeSurface
- [03-02]: Split zoom hides sibling HWNDs via ShowWindow rather than detaching from tree
- [03-03]: SearchOverlay as optional field on Surface rather than separate window class
- [03-03]: Scrollbar as state fields (scroll_total/offset/view_len) with InvalidateRect repaint
- [03-03]: ShellExecuteW for URL opening (handles protocol dispatch via OS)
- [03-03]: MessageBeep(0xFFFFFFFF) + FlashWindow for audible + visual bell
- [03-04]: GDI FillRect scrollbar painting on existing child HWND via WM_PAINT handler
- [03-04]: GWLP_USERDATA back-pointer from child HWND to Tab struct for WM_PAINT access
- [04-01]: Placeholder CLSID for toast notification activation stubs -- will be replaced in PLAT-03
- [04-01]: uap10:RuntimeBehavior=win32App and TrustLevel=mediumIL for full-trust desktop app model
- [04-01]: Self-signed cert uses CN=GhosttyDev matching Publisher identity in manifest
- [04-02]: Ctrl+` as default global hotkey with MOD_NOREPEAT for Quick Terminal
- [04-02]: WS_EX_TOOLWINDOW to exclude Quick Terminal from taskbar/Alt+Tab
- [04-02]: Linear interpolation animation (step=diff/5, min 4px) at ~60fps via SetTimer
- [04-02]: Tab module reused for Quick Terminal -- owns single Tab with persistent shell
- [04-03]: WinRT COM toast via RoGetActivationFactory + IToastNotificationManagerStatics (lazy init)
- [04-03]: Fuzzy subsequence matching (not substring) for command palette search
- [04-03]: Keyboard intercept via SendMessageW forwarding when command palette visible
- [04-03]: Toast fires only when GetForegroundWindow != main HWND (unfocused check)
- [04-03]: Comptime command.defaults list from input/command.zig for palette entries
- [04-04]: Store last_tab_index on Toast struct for warm-start activation instead of COM callback
- [04-04]: Deferred full INotificationActivationCallback COM registration (cold-start scenario)
- [04-04]: VCLibs 14.0.30704.0 MinVersion targeting VS 2022 17.x era for broad compatibility

### Pending Todos

None yet.

### Blockers/Concerns

- GLES 3.1 shader compatibility structurally validated (code compiles, guards in place) but runtime ANGLE compilation deferred due to Zig 0.15.2 build runner bug
- COM vtable alignment from Zig has no existing WinUI 3 reference -- must be validated early in Phase 1

## Session Continuity

Last session: 2026-02-26
Stopped at: Completed 04-04-PLAN.md (Gap closure: VCLibs + toast tab activation) -- All phases complete
Resume file: None
