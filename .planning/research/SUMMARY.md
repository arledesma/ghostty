# Project Research Summary

**Project:** Ghostty native Windows apprt (WinUI 3 + COM from Zig + OpenGL)
**Domain:** Native Windows terminal emulator windowing layer
**Researched:** 2026-02-24
**Confidence:** MEDIUM

## Executive Summary

Building a native Windows apprt for Ghostty means implementing a windowing and platform integration layer on top of the existing Zig core (libghostty) using WinUI 3 (Windows App SDK 1.8.x), COM called directly from Zig via zigwin32, ANGLE for OpenGL-to-D3D11 translation, and DirectWrite for font discovery. This is the same architectural pattern Windows Terminal uses: XAML manages all application chrome (tabs, menus, overlays) while the terminal grid renders directly into a `SwapChainPanel` via DirectX. The critical integration is ANGLE + SwapChainPanel — ANGLE translates Ghostty's existing OpenGL renderer to D3D11 and presents via a DXGI swap chain connected to a XAML `SwapChainPanel`. This path is proven in Chrome, Electron, and Flutter, and has been demonstrated for WinUI 3 specifically, though Zig-specific precedent is thin.

The recommended approach is to build the Windows apprt as `src/apprt/win32/` mirroring the existing `src/apprt/gtk/` structure, slot it into the compile-time apprt selection system, and keep all XAML bootstrapping in Zig via manual COM vtable definitions (no C++ wrapper, no C++/WinRT). The existing core (terminal emulation, OpenGL renderer, ConPTY, font rasterization) is unchanged. Ghostty's Zig-only build system is preserved. The MVP delivers a daily-drivable Windows terminal: tabbed interface, split panes, DPI scaling, native clipboard, and the full existing keybind and config system.

The two highest-risk decisions are (1) ANGLE + SwapChainPanel integration — if Ghostty's OpenGL 4.3 shaders cannot be ported to GLES 3.1, the entire rendering strategy must change — and (2) COM from Zig without a C++ layer — vtable misalignment causes silent stack corruption, not helpful error messages. Both must be validated in a standalone proof-of-concept before any apprt code is written. Phase 1 exists specifically to derisk these two unknowns.

## Key Findings

### Recommended Stack

The Windows apprt builds on Windows App SDK 1.8.x (stable) for WinUI 3 XAML, zigwin32 (main branch) for Win32 and COM bindings, ANGLE (chromium/main with `angle_is_winappsdk=true`) for OpenGL-to-D3D11 translation, and DirectWrite (via zigwin32 COM bindings) for font discovery. FreeType and HarfBuzz are already vendored and need no changes. ConPTY is already implemented in `src/termio/`. The entire stack targets Windows 10 1809+ (build 17763), covering ~99% of active Windows 10/11 installations.

WinRT APIs are COM under the hood. Zig can call them via vtable dispatch without a C++ layer. zigwin32 covers Win32/DXGI/D3D11/DirectWrite fully; WinUI 3-specific interfaces (`ISwapChainPanelNative`, `IWindowNative`, etc.) must be hand-defined as Zig vtable structs from the Windows App SDK headers. An estimated 20-30 interface definitions are needed for the initial apprt. If this proves unmanageable, a thin C bootstrap shim (~200 lines) is the fallback — but no C++ compiler is needed in either case.

**Core technologies:**
- **Windows App SDK 1.8.x:** WinUI 3 XAML runtime (TabView, NavigationView, window chrome) — industry standard for new native Windows desktop apps; same framework as Windows Terminal. Avoid 2.0 (experimental-only).
- **zigwin32 (main):** Complete auto-generated Zig bindings for Win32 and COM — covers DXGI, D3D11, DirectWrite, ConPTY, shell APIs — no C++ dependency.
- **ANGLE (chromium/main):** OpenGL ES 3.1 to D3D11 translation — lets Ghostty's existing OpenGL renderer target a DXGI swap chain inside SwapChainPanel. Build with `angle_is_winappsdk=true`.
- **DirectWrite:** Font discovery via COM — follow the same `coretext_freetype` pattern used on macOS (native discovery, FreeType rasterization). New `directwrite_freetype` backend variant.
- **FreeType / HarfBuzz:** Unchanged from current stack — already compiles on Windows.

### Expected Features

The MVP targets feature parity sufficient to daily-drive Ghostty on Windows. Fourteen table-stakes features must ship at launch. Eleven differentiators target v1.x. Five features are deferred to v2+. See `.planning/research/FEATURES.md` for the full prioritization matrix.

**Must have (table stakes — v1):**
- Native window with OpenGL surface — foundation for everything else
- Tabbed interface (WinUI 3 TabView) — non-negotiable for daily use
- Split panes — core Ghostty feature, expected by power users
- Per-monitor DPI scaling — critical on mixed-DPI Windows setups
- Native clipboard — Ctrl+C/Ctrl+V muscle memory
- Fullscreen — basic window management
- Window chrome and decorations — native Windows look and feel
- Configuration file support, keybind system, search overlay, scrollbar, bell, URL click-to-open, light/dark theming

**Should have (differentiators — v1.x):**
- IME support — required for CJK users; defer from v1 due to high complexity
- Quick Terminal (Quake mode) — Ghostty's implementation is richer than Windows Terminal's
- Command palette — better than WT with fuzzy matching
- Desktop notifications, tabs-in-titlebar, transparency/Acrylic, system tray, jump list

**Defer (v2+):**
- Context menu shell extension, auto-update (non-Store), Inspector UI, full layout persistence, Accessibility (UIA) — important but each is a dedicated effort

Do NOT build: full settings GUI (config-file-first philosophy), profiles dropdown, built-in SSH client, plugin/extension system.

### Architecture Approach

The Windows apprt follows the Windows Terminal pattern: WinUI 3 XAML owns all application chrome while the terminal grid renders directly into a `SwapChainPanel` via ANGLE/D3D11. The apprt lives at `src/apprt/win32/` and slots into Ghostty's compile-time apprt selection (`build_config.app_runtime = .win32`). The Zig core is untouched. Each terminal surface gets its own SwapChainPanel and its own ANGLE EGL context (sharing one D3D11 device). The renderer thread can draw directly without going through the app thread (`must_draw_from_app_thread = false`) — a performance advantage over the GTK apprt.

**Major components:**
1. **XAML Shell** (`apprt/win32/xaml.zig`, `App.zig`) — WinUI 3 Window, TabView, split layout, menus; owns the HWND and XAML DesktopWindow; all UI-thread operations
2. **COM Bridge** (`apprt/win32/com.zig`) — QueryInterface helpers, IID definitions, WinRT activation, DispatcherQueue dispatch; bridges XAML events to Surface.zig calls
3. **Rendering Bridge** (`apprt/win32/Surface.zig`) — ANGLE EGL context creation per surface, ISwapChainPanelNative::SetSwapChain wiring, swap chain resize handling
4. **Input Translation** (`apprt/win32/input.zig`) — Windows virtual keys to Ghostty key codes; pointer events; IME positioning
5. **Platform Integration** (`apprt/win32/clipboard.zig`, `dwrite.zig`) — Win32 clipboard, DirectWrite font discovery

### Critical Pitfalls

1. **XAML threading model** — WinUI 3 STA model requires all XAML API calls on the UI thread. Renderer thread violations cause hard crashes (`RPC_E_WRONG_THREAD`). Set `must_draw_from_app_thread = false` but guard every XAML interaction with `DispatcherQueue.TryEnqueue`. Establish threading discipline in Phase 1 before any surface code.

2. **OpenGL inside XAML requires ANGLE** — SwapChainPanel expects a DXGI swap chain, not a WGL context. WGL needs an HWND; SwapChainPanel is a XAML composition surface. WGL + SwapChainPanel is impossible. ANGLE is the only viable path. Must be prototyped in Phase 1; if Ghostty's GL 4.3 shaders cannot target GLES 3.1, the rendering strategy must change before any apprt code is written.

3. **COM vtable misalignment from Zig** — A single wrong vtable slot causes silent stack corruption or the wrong method being called. There is no C++ compiler to catch this. Build a `ComInterface` helper with explicit HRESULT checking first; validate 5+ different COM interfaces over 1000 iterations before proceeding.

4. **SwapChainPanel DPI scaling bug** — Documented WinUI 3 issue (microsoft-ui-xaml#5888, #9794): content renders at wrong position at non-100% scaling. Always create swap chain buffers at physical pixel dimensions (`dip * scale`). Handle `SizeChanged`, `CompositionScaleChanged`, and `XamlRoot.Changed`. Validate at 100%, 125%, 150%, 175%, 200%, 250% before Phase 3.

5. **Windows App SDK runtime not installed on sideload** — Store distribution is fine (runtime declared as framework dependency). Sideload requires the bootstrapper API (`MddBootstrapInitialize2`) called before any WinUI 3 API. Must be prototyped in Phase 1 to validate the deployment model; GLFW apprt provides a safety net during transition.

## Implications for Roadmap

Based on the combined research, a four-phase structure is recommended. The ordering is driven by hard technical dependencies: COM interop and the rendering surface strategy must be validated before any apprt code is written. Everything else builds on those foundations.

### Phase 1: COM Foundation and Rendering Proof-of-Concept

**Rationale:** The two highest-risk unknowns — COM from Zig and ANGLE + SwapChainPanel — must be validated before investing in apprt infrastructure. Phase 1 is a standalone proof-of-concept, not production apprt code. If either fails, the strategy changes here with minimal sunk cost.
**Delivers:** A working WinUI 3 window with a `SwapChainPanel` rendering a solid color from Ghostty's OpenGL renderer via ANGLE. No terminal emulation, no tabs. Just proof that the rendering bridge works.
**Addresses:** Foundation for all subsequent features
**Avoids:** XAML threading violations (establish `DispatcherQueue` discipline), COM vtable misalignment (validate COM helpers), ANGLE + SwapChainPanel incompatibility (test before committing to strategy), App SDK runtime missing on sideload (prototype bootstrapper API)
**Uses:** Windows App SDK 1.8.x, ANGLE with `angle_is_winappsdk=true`, zigwin32 COM helpers, DXGI/D3D11

### Phase 2: Single Terminal Surface

**Rationale:** With the rendering bridge proven, wire Ghostty's full terminal pipeline to it. This is the core value proof — a working terminal in a native WinUI 3 window. Validates DPI scaling before multi-surface complexity is added.
**Delivers:** A fully functional single-tab Ghostty terminal in a native WinUI 3 window. Terminal emulation, keyboard/mouse input, ConPTY I/O, OpenGL rendering, DPI scaling.
**Addresses:** Native window with OpenGL surface (P1), per-monitor DPI scaling (P1), native clipboard (P1), fullscreen (P1), window chrome (P1), config file support (P1), keybind system (P1)
**Implements:** `apprt/win32/App.zig`, `apprt/win32/Surface.zig`, `apprt/win32/input.zig`, `apprt/win32/clipboard.zig`
**Avoids:** SwapChainPanel DPI bug — validate at all scaling factors before Phase 3

### Phase 3: Multi-Surface, Tabs, and Splits

**Rationale:** Tabs and splits are non-negotiable for daily use and both depend on the single-surface foundation. MSIX packaging identity unlocks desktop notifications and jump lists.
**Delivers:** Full multi-tab, split-pane Ghostty on Windows. TabView, split layout, multiple SwapChainPanel lifecycle management, MSIX packaging with App SDK runtime dependency.
**Addresses:** Tabbed interface (P1), split panes (P1), search overlay (P1), scrollbar (P1), bell (P1), URL click-to-open (P1), window theming (P1), MSIX packaging
**Implements:** XAML TabView, split layout (XAML Grid + GridSplitter), multi-surface action system (`performAction` for tab/split/window actions), `dwrite.zig` (DirectWrite font discovery)
**Avoids:** Single shared GL context anti-pattern (one ANGLE EGL context per surface); SwapChainPanel 4-instance limit (tabs recycle panels; only visible splits need live panels)

### Phase 4: Platform Integration and v1.x Differentiators

**Rationale:** With the core working and early adopters validating stability, add the features that make Ghostty better than Windows Terminal. IME and Quick Terminal are the highest-value additions.
**Delivers:** IME support (CJK users), Quick Terminal / Quake mode, command palette, desktop notifications (via MSIX identity), tabs-in-titlebar, transparency/Acrylic, system tray, jump list.
**Addresses:** IME (P2), Quick Terminal (P2), command palette (P2), desktop notifications (P2), tabs-in-titlebar (P2), custom window styles (P2), system tray (P2), jump list (P2)
**Implements:** IMM32 API for IME positioning (not full TSF — even Windows Terminal uses IMM32), `RegisterHotKey` for Quick Terminal global hotkey, `AppNotificationManager` for toast notifications, `IWindowNative::get_WindowHandle` for HWND access
**Note:** IME is complex enough to warrant its own sub-phase within Phase 4. Ship Phase 4 without IME, add IME as Phase 4b.

### Phase Ordering Rationale

- **Phase 1 before everything:** ANGLE + SwapChainPanel is the riskiest unknown. If the GL 4.3 to GLES 3.1 shader audit fails, the entire rendering strategy changes. Discovering this in Phase 1 costs days, not months.
- **Phase 2 before tabs/splits:** DPI scaling bugs in SwapChainPanel must be found and fixed on a single surface before the complexity of multi-surface management is added.
- **Phase 3 includes MSIX:** Packaging is infrastructure, not a Phase 5 afterthought. Desktop notifications and jump lists both require MSIX app identity, and catching packaging issues early avoids rework.
- **Phase 4 is additive:** All Phase 4 features build on a stable core. IME is isolated to input handling. Quick Terminal is isolated to window management. None should require architectural changes.

### Research Flags

Phases needing deeper research during planning:
- **Phase 1:** ANGLE build configuration (`angle_is_winappsdk=true`) and GLES 3.1 shader compatibility audit for Ghostty's existing shaders — need to enumerate all GL 4.3 features used and verify GLES 3.1 equivalents exist.
- **Phase 1:** Windows App SDK bootstrapper API (`MddBootstrapInitialize2`) — runtime initialization order is strict and poorly documented for Zig callers; needs prototype.
- **Phase 3:** SwapChainPanel 4-instance limit and lifecycle management under split panes — tab recycling strategy needs design work.
- **Phase 4:** IME via IMM32 in WinUI 3 — requires HWND subclassing or `InputPreview` handler to intercept `WM_IME_*` messages; WinUI 3 complicates direct Win32 message handling.

Phases with standard patterns (skip `research-phase`):
- **Phase 2, keyboard/mouse input:** Ghostty's input abstraction layer is well-defined; Win32 virtual key to Ghostty key code mapping is mechanical work.
- **Phase 2, ConPTY:** Already implemented in `src/termio/`; no new research needed.
- **Phase 3, TabView:** WinUI 3 TabView is well-documented with official samples.
- **Phase 3, MSIX packaging:** Standard packaging workflow; App SDK framework dependency declaration is documented.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | WinUI 3 + Win32/COM APIs are HIGH confidence (official docs, Windows Terminal precedent). ANGLE + SwapChainPanel for WinUI 3 is MEDIUM (community-proven, single demo source). Zig-specific COM interop is MEDIUM (zigwin32 is well-maintained, but WinUI 3 vtable definitions require manual work with no existing reference). |
| Features | MEDIUM-HIGH | Feature set derived from Ghostty macOS parity analysis + Windows Terminal competitor analysis + Ghostty's existing action system. High confidence on P1 features. P2 feature scoping is reasonable but may shift based on early adopter feedback. |
| Architecture | MEDIUM | Windows Terminal architecture pattern is HIGH confidence. ANGLE/SwapChainPanel integration specifics are MEDIUM (Levin Li demo is single source). Threading model analysis is HIGH confidence (from official WinUI 3 docs and codebase analysis). |
| Pitfalls | MEDIUM | Pitfalls sourced from tracked GitHub issues (microsoft-ui-xaml#5888, #9794), official threading docs, and Ghostty codebase analysis. ANGLE-specific pitfalls are MEDIUM because the WinUI 3 path has fewer battle-tested implementations than the UWP path. |

**Overall confidence:** MEDIUM

### Gaps to Address

- **GLES 3.1 shader compatibility:** Ghostty's OpenGL renderer requires 4.3. ANGLE exposes GLES 3.1. The gap (geometry shaders, specific GL 4.3 features) is unknown until the shader files are audited. This is the single most important validation in Phase 1. If the gap is real, options are: (a) ANGLE desktop GL emulation mode (non-standard), (b) WGL_NV_DX_interop (preserves desktop GL but adds complexity), (c) native D3D11 renderer (major effort, out of scope).
- **COM vtable generation strategy:** Starting with manual definitions is correct for Phase 1-2. By Phase 3 (~30 interfaces), a generator becomes necessary. Decision point: extend zigwin32gen to parse Windows App SDK .winmd files, or continue manual. Should be decided during Phase 2 planning.
- **SwapChainPanel instance limit:** Microsoft docs suggest ~4 instances per app. With split panes, this could be hit. The mitigation (only active tabs/visible splits get live panels) needs design work before Phase 3 implementation.
- **Distribution strategy for sideload:** MSIX + App SDK bootstrapper is the plan. Need to validate the bootstrapper on clean Windows 10 1809 VMs before committing to it as the primary non-Store distribution path.
- **ARM64 support:** Research focused on x86_64. Calling conventions differ on ARM64. Should be flagged as a Phase 3 or Phase 4 concern if ARM64 Windows (Surface Pro X, Snapdragon laptops) is a target.

## Sources

### Primary (HIGH confidence)
- [Windows App SDK stable channel release notes](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/stable-channel) — version confirmation
- [SwapChainPanel Class — Windows App SDK](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel) — XAML rendering surface API
- [ISwapChainPanelNative::SetSwapChain](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/microsoft.ui.xaml.media.dxinterop/nf-microsoft-ui-xaml-media-dxinterop-iswapchainpanelnative-setswapchain) — COM interface for swap chain connection
- [Building Windows Terminal with WinUI](https://devblogs.microsoft.com/commandline/building-windows-terminal-with-winui/) — architecture reference
- [Windows Terminal ORGANIZATION.md](https://github.com/Microsoft/Terminal/blob/main/doc/ORGANIZATION.md) — component structure reference
- [zigwin32 repository](https://github.com/marlersoft/zigwin32) — Zig Win32 bindings
- [IDWriteFactory interface](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nn-dwrite-idwritefactory) — DirectWrite COM API
- [IDXGIFactory2::CreateSwapChainForComposition](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcomposition) — swap chain for composition
- [ANGLE DevSetup](https://chromium.googlesource.com/angle/angle/+/HEAD/doc/DevSetup.md) — ANGLE build with WinAppSDK flag
- Ghostty codebase: `src/apprt.zig`, `src/apprt/gtk/`, `src/renderer/OpenGL.zig`, `src/Surface.zig`, `src/apprt/structs.zig`, `src/apprt/action.zig`, `src/config/Config.zig`
- [WinUI 3 SwapChainPanel DPI bug — microsoft-ui-xaml#5888](https://github.com/microsoft/microsoft-ui-xaml/issues/5888)
- [WinUI 3 COM threading — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/threading)
- [Ghostty PR #1519](https://github.com/ghostty-org/ghostty/pull/1519) — previous Win32 apprt attempt by zigwin32 author

### Secondary (MEDIUM confidence)
- [ANGLE WinUI 3 issue — microsoft/angle#170](https://github.com/microsoft/angle/issues/170) — tracking issue for WinUI 3 support
- [WinUI 3 HWND hosting discussion — microsoft-ui-xaml#9912](https://github.com/microsoft/microsoft-ui-xaml/discussions/9912) — confirms no official child HWND hosting
- [DirectX and XAML interop — Microsoft Learn](https://learn.microsoft.com/en-us/windows/uwp/gaming/directx-and-xaml-interop) — DX+XAML integration patterns
- [Creating DirectX 11 SwapChain in WinUI 3.0](https://www.juhakeranen.com/winui3/directx-11-2-swap-chain.html) — tutorial
- [Zig Win32 type conflicts — Ziggit](https://ziggit.dev/t/win32-apps-with-zig-conflicting-defintions-extern-struct-vs-opaque/1400)
- [Windows Terminal panes, command palette, appearance — Microsoft Learn](https://learn.microsoft.com/en-us/windows/terminal/)

### Tertiary (LOW confidence)
- [ANGLE + WinUI 3 SwapChainPanel demo — Levin Li](https://x.com/LevinLi303/status/1626091977845444608) — single community source proving ANGLE + WinUI 3 SwapChainPanel works; needs replication

---
*Research completed: 2026-02-24*
*Ready for roadmap: yes*
