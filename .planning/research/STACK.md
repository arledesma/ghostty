# Stack Research

**Domain:** Native Windows terminal emulator apprt (WinUI 3 + COM from Zig + OpenGL rendering)
**Researched:** 2026-02-24
**Confidence:** MEDIUM — WinUI 3 and Win32 COM APIs are well-documented; Zig-to-WinRT interop and OpenGL-in-XAML hosting are less proven and have fewer reference implementations.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Windows App SDK | 1.8.x (stable) | WinUI 3 XAML runtime — provides native TabView, NavigationView, MenuBar, ContentDialog with Fluent Design | Industry standard for new native Windows desktop apps. Same framework Windows Terminal uses. Stable channel is production-ready. 2.0 is experimental-only; avoid until stable. **[HIGH confidence]** |
| zigwin32 | main (tracks Zig 0.14/0.15) | Auto-generated Zig bindings for Win32 and COM APIs — DirectWrite, DXGI, D3D11, shell APIs | Complete coverage of Win32 API surface auto-generated from Windows SDK metadata. Covers COM vtable layout natively. Used by marler8997 (author of Ghostty PR #1519). No WinRT projection but Win32/COM is sufficient for our needs. **[HIGH confidence]** |
| ANGLE | chromium/main | OpenGL ES 3.1 to D3D11 translation layer — lets Ghostty's existing OpenGL renderer target a DXGI swap chain | ANGLE has built-in `angle_is_winappsdk=true` support for WinUI 3 SwapChainPanel. Translates GL calls to D3D11, producing an `IDXGISwapChain1` that can be handed to `ISwapChainPanelNative::SetSwapChain`. Chromium, Electron, and Flutter all ship ANGLE on Windows. **[MEDIUM confidence — WinUI 3 SwapChainPanel path is community-proven but not officially documented by Google]** |
| DirectWrite | Windows SDK (ships with OS) | Font discovery — enumerate system fonts, match by family/weight/style/stretch | COM-based API available through zigwin32 bindings. Follows the same `coretext_freetype` pattern Ghostty uses on macOS: native discovery, FreeType rasterization. **[HIGH confidence]** |
| FreeType | existing (vendored) | Font rasterization — unchanged from current Ghostty stack | Already compiles and runs on Windows. No changes needed. **[HIGH confidence]** |
| HarfBuzz | existing (vendored) | Text shaping — unchanged from current Ghostty stack | Already compiles and runs on Windows. No changes needed. **[HIGH confidence]** |
| OpenGL (via GLAD) | 4.3+ (through ANGLE's GLES 3.1 translation) | GPU-accelerated terminal grid rendering | Ghostty's existing renderer uses OpenGL 4.3 with GLAD loader. ANGLE exposes GLES 3.1 (roughly GL 4.3 feature equivalent). Ghostty's shaders need audit for GLES compatibility but the core rendering pipeline remains unchanged. **[MEDIUM confidence — GL 4.3 to GLES 3.1 feature gap needs validation]** |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DXGI 1.2+ | Windows SDK | Swap chain creation via `IDXGIFactory2::CreateSwapChainForComposition` | Required to create the `IDXGISwapChain1` that feeds `SwapChainPanel`. ANGLE handles this internally when configured for SwapChainPanel, but you need DXGI for resize handling and present configuration. |
| D3D11 | Windows SDK | GPU device creation for ANGLE's D3D11 backend | ANGLE creates the D3D11 device internally. Exposed through ANGLE's EGL extension for sharing device handles if needed for interop. |
| ConPTY | Windows SDK | Pseudoterminal API for subprocess management | Already used by Ghostty on Windows. No changes needed. |
| Windows.UI.Xaml.Media.DxInterop | Windows App SDK | `ISwapChainPanelNative` COM interface for connecting swap chain to XAML | The critical bridge between ANGLE's swap chain and WinUI's `SwapChainPanel` control. Cast `SwapChainPanel` to `ISwapChainPanelNative` via `QueryInterface`, call `SetSwapChain`. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Zig Build System | Build orchestration | Existing build system. Add Windows App SDK header/lib paths, ANGLE build integration, and zigwin32 dependency. |
| Windows SDK 10.0.22621+ | Platform headers and libraries | Required for DirectWrite, DXGI, D3D11, ConPTY. Ship with Visual Studio or standalone installer. |
| MSIX Packaging | Distribution packaging | Required for Windows Store and sideloading. Declares App SDK runtime as framework dependency. |
| GN + Ninja (for ANGLE) | ANGLE build system | ANGLE uses Chromium's GN build. Build ANGLE as static libs (`is_component_build = false`), then link from Zig. |

## OpenGL-in-XAML Hosting Architecture

This is the critical integration point. Three approaches exist; we recommend **Option A**.

### Option A: ANGLE + SwapChainPanel (RECOMMENDED)

**How it works:**
1. WinUI 3 XAML layout contains a `SwapChainPanel` element where the terminal grid renders
2. ANGLE is built with `angle_is_winappsdk=true`, producing `libEGL.dll` and `libGLESv2.dll` that understand SwapChainPanel as an EGL native window
3. ANGLE creates a D3D11 device and `IDXGISwapChain1` via `CreateSwapChainForComposition`
4. The swap chain is connected to the `SwapChainPanel` via `ISwapChainPanelNative::SetSwapChain`
5. Ghostty's OpenGL renderer calls GLES functions through ANGLE; ANGLE translates to D3D11 commands
6. The XAML compositor composites the terminal grid under/over XAML chrome (tabs, menus, overlays)

**Integration steps from Zig:**
```
1. Create WinUI 3 Window with XAML containing SwapChainPanel
2. Get SwapChainPanel HWND/IInspectable
3. Initialize EGL display + surface targeting the SwapChainPanel
4. Create EGL/GLES context
5. Load GLES function pointers via GLAD (eglGetProcAddress)
6. Pass to Ghostty's existing OpenGL renderer
7. Renderer draws to GLES context; ANGLE translates to D3D11; SwapChainPanel displays
```

**Why this approach:**
- SwapChainPanel is how Windows Terminal hosts its D3D renderer inside XAML
- ANGLE provides the GL-to-D3D11 translation so Ghostty's existing shaders work
- XAML compositor handles tab chrome, menus, and overlays without interfering with terminal rendering
- Single DXGI swap chain per terminal surface, composited by DirectComposition

**Limitations:**
- Max 4 SwapChainPanels per window recommended (one per visible terminal pane is fine)
- SwapChainPanel does not support transparency/acrylic effects over the rendered content
- ANGLE adds a translation layer (~5-10% overhead vs native D3D11, negligible for terminal rendering)
- Ghostty's shaders need GLES 3.1 compatibility audit (GL 4.3 features like compute shaders need `GL_ES` equivalents)

### Option B: WGL + Child HWND (NOT RECOMMENDED)

Create a child Win32 HWND inside the WinUI 3 window, use WGL for native OpenGL 4.3 context.

**Why not:**
- WinUI 3 has no official API for hosting child HWNDs. `DesktopChildSiteBridge` is internal/undocumented.
- Input routing breaks — keyboard and mouse events get swallowed by XAML's input manager.
- Workarounds exist (undocumented `Microsoft.InputStateManager.dll`) but are fragile and unsupported.
- The child HWND does not participate in XAML's visual tree or composition, so it cannot be overlaid with XAML elements (e.g., search bars, tab overlays).
- This approach was effectively abandoned by the Windows Terminal team.

### Option C: Native D3D11 + SwapChainPanel (FUTURE OPTIMIZATION)

Rewrite Ghostty's renderer to emit D3D11 commands directly, bypassing ANGLE.

**Why not now:**
- Massive effort: new shader language (HLSL), new GPU abstraction, new texture/buffer management.
- Decouples renderer work from windowing/chrome work — can be done later as a performance optimization.
- ANGLE overhead is negligible for terminal rendering workloads.
- This is explicitly listed as out-of-scope in PROJECT.md.

## COM Interop from Zig

### WinRT/COM Calling Pattern

WinUI 3 is built on WinRT, which is COM under the hood. The key insight: **you do not need a WinRT projection (like C++/WinRT) to call WinRT APIs from Zig.** WinRT interfaces are COM interfaces with IIDs. You can call them via vtable dispatch.

**What zigwin32 provides:**
- Complete Win32 COM interface definitions (IUnknown, IInspectable, etc.)
- DirectWrite interfaces (IDWriteFactory, IDWriteFontCollection, etc.)
- DXGI interfaces (IDXGIFactory2, IDXGISwapChain1, etc.)
- D3D11 interfaces (ID3D11Device, etc.)
- Shell and window management APIs

**What zigwin32 does NOT provide:**
- WinRT activation and projected types (e.g., `Microsoft.UI.Xaml.Controls.TabView`)
- WinUI 3 XAML controls and their WinRT interfaces
- Windows App SDK-specific APIs

**How to bridge the gap — three strategies:**

1. **Manual vtable definitions for WinRT interfaces** (RECOMMENDED for small surface area)
   - Define the COM vtable struct in Zig matching the ABI layout
   - Use `RoActivateInstance` / `RoGetActivationFactory` to instantiate WinRT types
   - Call methods through vtable function pointers
   - Works for: SwapChainPanel, TabView, NavigationView, Window, Application
   - Effort: ~50-100 interface definitions needed for a full apprt

2. **Extend zigwin32gen to parse WinUI 3 .winmd files** (FUTURE — if surface area grows)
   - The zigwin32gen tool already parses Windows SDK metadata (.winmd)
   - Windows App SDK ships its own .winmd files
   - Could auto-generate Zig bindings for all WinUI 3 types
   - Higher upfront effort, but scales better

3. **Thin C shim for XAML bootstrapping** (FALLBACK — if manual vtables prove too painful)
   - Write a minimal C file (~200 lines) that handles XAML Application init, Window creation, and returns COM pointers
   - Zig code drives everything after bootstrap
   - Avoids C++ entirely (C can call COM via explicit vtable casts)
   - Last resort — violates the "no C++ wrapper" goal but keeps C++ out

**Recommended approach:** Start with strategy 1 (manual vtable definitions). The number of WinUI 3 interfaces needed is bounded — ~20-30 for the initial apprt. If this proves painful, fall back to strategy 3.

### DirectWrite Font Discovery from Zig

DirectWrite is a pure COM API (not WinRT), so zigwin32 provides complete bindings.

```
Calling pattern:
1. DWriteCreateFactory() -> IDWriteFactory
2. IDWriteFactory::GetSystemFontCollection() -> IDWriteFontCollection
3. IDWriteFontCollection::FindFamilyName() -> index
4. IDWriteFontCollection::GetFontFamily(index) -> IDWriteFontFamily
5. IDWriteFontFamily::GetMatchingFonts(weight, stretch, style) -> IDWriteFontList
6. IDWriteFontList::GetFont(0) -> IDWriteFont
7. IDWriteFont::CreateFontFace() -> IDWriteFontFace
8. Use FreeType to load from file path or in-memory data
```

This mirrors the `coretext_freetype` pattern: native API for discovery, FreeType for rasterization. A new font backend variant `directwrite_freetype` would be added to `src/font/backend.zig`.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| WinUI 3 (Windows App SDK 1.8) | Win32 + custom chrome | If Windows 10 1507 support is required (App SDK needs 1809+). Also if MSIX packaging is unacceptable. |
| WinUI 3 (Windows App SDK 1.8) | Windows App SDK 2.0 | When 2.0 reaches stable. Currently experimental-only; not suitable for production. |
| ANGLE (GL-to-D3D11) | Native WGL OpenGL | If you do not need XAML integration (i.e., pure Win32 window with no tabs/splits). The closed PR #1519 took this approach. |
| ANGLE (GL-to-D3D11) | Native D3D11 renderer | When performance profiling shows ANGLE overhead matters. This is a renderer rewrite, not an apprt concern. |
| zigwin32 (manual COM) | C++/WinRT wrapper | If Zig-to-COM interop proves too fragile. Adds C++ build dependency, which the project explicitly wants to avoid. |
| DirectWrite (discovery only) | Fontconfig on Windows | Fontconfig does not work well on Windows — it requires manual font.conf setup and misses system fonts. DirectWrite is the correct Windows answer. |
| MSIX packaging | MSI / EXE installer | For enterprise deployment where MSIX is blocked by policy. Would need to bundle the App SDK runtime (adds ~50MB). |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| C++/WinRT projections | Adds C++ compiler dependency, incompatible with Zig build system, violates project constraint | Manual COM vtable definitions from Zig via zigwin32 |
| GLFW on Windows (for native apprt) | Provides no native UI controls — no tabs, splits, or Fluent Design. Fine for the existing cross-platform shim, not for the native experience | WinUI 3 via Windows App SDK |
| UWP (Universal Windows Platform) | Deprecated in favor of Windows App SDK / WinUI 3. UWP sandbox restrictions prevent ConPTY usage | WinUI 3 desktop app (no sandbox) |
| WPF (Windows Presentation Foundation) | .NET dependency, no Fluent Design, poor GPU rendering integration, completely wrong technology for a Zig project | WinUI 3 |
| Electron / WebView2 for UI | Massive memory overhead, wrong architecture for a terminal emulator that needs sub-millisecond input latency | WinUI 3 native XAML |
| Windows App SDK 2.0 (experimental) | API surface still changing, not production-ready, may have breaking changes before stable release | Windows App SDK 1.8.x (stable) |
| GTK on Windows | Poor native feel, missing Windows integration (taskbar, system tray, notifications), font rendering issues. Explicitly being replaced by this project. | WinUI 3 |
| Direct2D for terminal grid rendering | Wrong tool — D2D is a 2D vector graphics API, not a tile-based GPU renderer. Would require rewriting Ghostty's rendering pipeline. | OpenGL via ANGLE (existing renderer) or future D3D11 tile renderer |

## Stack Patterns by Variant

**If targeting Windows Store distribution:**
- Use MSIX packaging with framework dependency on Windows App SDK runtime
- The Store handles App SDK runtime installation automatically
- No need to bundle the runtime (saves ~50MB in package size)

**If targeting sideload / enterprise distribution:**
- Use MSIX with App SDK framework dependency declared in manifest
- Include `WindowsAppRuntimeInstall.exe` in your installer to bootstrap the runtime
- Or use self-contained deployment (bundles App SDK runtime, larger package)

**If OpenGL 4.3 features are needed that GLES 3.1 cannot provide:**
- Audit shaders for GLES 3.1 compatibility first (most GL 4.3 features have GLES equivalents)
- If compute shaders are needed: GLES 3.1 supports compute shaders
- If geometry shaders are needed: GLES 3.2 or use a transform feedback workaround
- Last resort: switch to native D3D11 renderer (major effort, separate project)

**If the manual COM vtable approach becomes unmanageable:**
- Fall back to a thin C bootstrap shim (~200 lines)
- The shim handles XAML Application/Window creation only
- All subsequent COM calls still go through Zig via zigwin32
- This is NOT the same as a C++ wrapper — no C++ compiler needed

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| Windows App SDK 1.8.x | Windows 10 1809+ (build 17763) | Minimum OS version. Covers ~99% of Windows 10/11 installations. |
| Windows App SDK 1.8.x | Zig 0.15.x | No direct dependency, but zigwin32 bindings must match SDK headers. |
| zigwin32 (main) | Zig 0.14.x / 0.15.x | Version-conditional code in zigwin32 handles both. Track main branch. |
| ANGLE (chromium/main) | Windows 10 1809+ | D3D11 backend. Requires D3D Feature Level 11_0. |
| ANGLE (chromium/main) | Windows App SDK 1.8.x | Requires `angle_is_winappsdk=true` build flag and generated headers via `scripts/winappsdk_setup.py`. |
| DirectWrite | Windows 7+ | Available on all target Windows versions. Use IDWriteFactory3+ for variable font support (Win10+). |
| DXGI 1.2 | Windows 8+ | `CreateSwapChainForComposition` requires DXGI 1.2. Available on all target versions. |
| FreeType (vendored) | All platforms | No Windows-specific compatibility concerns. |
| HarfBuzz (vendored) | All platforms | No Windows-specific compatibility concerns. |

## Sources

- [Windows App SDK stable channel release notes](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/stable-channel) — Version 1.8.x confirmed as latest stable **[HIGH confidence]**
- [Windows App SDK downloads](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads) — Download links and version matrix **[HIGH confidence]**
- [SwapChainPanel (Windows App SDK)](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel?view=windows-app-sdk-1.8) — XAML control for DirectX swap chain hosting **[HIGH confidence]**
- [ISwapChainPanelNative::SetSwapChain](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/microsoft.ui.xaml.media.dxinterop/nf-microsoft-ui-xaml-media-dxinterop-iswapchainpanelnative-setswapchain) — COM interface for connecting swap chain to XAML panel **[HIGH confidence]**
- [IDXGIFactory2::CreateSwapChainForComposition](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcomposition) — Swap chain creation for composition targets **[HIGH confidence]**
- [ANGLE DevSetup](https://chromium.googlesource.com/angle/angle/+/HEAD/doc/DevSetup.md) — ANGLE build instructions including `angle_is_winappsdk` flag **[HIGH confidence]**
- [ANGLE SwapChainPanel WinUI 3 (Levin Li)](https://x.com/LevinLi303/status/1626091977845444608) — Community proof of ANGLE + SwapChainPanel in WinUI 3 **[MEDIUM confidence — single community source]**
- [zigwin32 repository](https://github.com/marlersoft/zigwin32) — Complete Win32 API bindings for Zig **[HIGH confidence]**
- [zigwin32gen](https://github.com/marlersoft/zigwin32gen) — Generator tool, confirms metadata-driven approach **[HIGH confidence]**
- [Ghostty PR #1519](https://github.com/ghostty-org/ghostty/pull/1519) — Previous native Win32 apprt attempt by marler8997 (zigwin32 author) **[HIGH confidence]**
- [Ghostty Discussion #2563](https://github.com/ghostty-org/ghostty/discussions/2563) — Windows support tracking discussion **[HIGH confidence]**
- [Building Windows Terminal with WinUI](https://devblogs.microsoft.com/commandline/building-windows-terminal-with-winui/) — Windows Terminal's architecture as reference **[HIGH confidence]**
- [IDWriteFactory interface](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nn-dwrite-idwritefactory) — DirectWrite COM API for font discovery **[HIGH confidence]**
- [DirectWrite font selection](https://learn.microsoft.com/en-us/windows/win32/directwrite/font-selection) — Font matching algorithm documentation **[HIGH confidence]**
- [Windows App SDK deployment for packaged apps](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-packaged-apps) — MSIX packaging and runtime dependency management **[HIGH confidence]**
- [WinUI 3 HWND hosting discussion](https://github.com/microsoft/microsoft-ui-xaml/discussions/9912) — Confirms no official child HWND hosting in WinUI 3 **[MEDIUM confidence]**
- [ANGLE WinUI 3 issue](https://github.com/microsoft/angle/issues/170) — Tracking issue for ANGLE + WinUI 3 support **[MEDIUM confidence]**

---
*Stack research for: Ghostty native Windows apprt*
*Researched: 2026-02-24*
