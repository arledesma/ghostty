# Architecture Research

**Domain:** Native Windows terminal emulator apprt for Ghostty
**Researched:** 2026-02-24
**Confidence:** MEDIUM (architecture patterns verified against codebase and official docs; ANGLE/SwapChainPanel integration details are LOW confidence due to limited Zig-specific precedent)

## Standard Architecture

### System Overview

```
+--------------------------------------------------------------------+
|                    XAML Shell (WinUI 3)                             |
|  +------------+  +-----------+  +----------+  +----------------+   |
|  | TabView    |  | Splits    |  | Menus/   |  | Settings/      |   |
|  | (chrome)   |  | (layout)  |  | Command  |  | Config UI      |   |
|  |            |  |           |  | Palette  |  |                |   |
|  +-----+------+  +-----+-----+  +----------+  +----------------+   |
|        |              |                                            |
|  +-----+--------------+-------------------------------------------+
|  |              SwapChainPanel (per terminal surface)              |
|  |  (DXGI SwapChain hosted inside XAML visual tree)               |
|  +----------------------------------------------------------------+
|        |                                                           |
+--------+-----------------------------------------------------------+
         | ISwapChainPanelNative::SetSwapChain()
         |
+--------+-----------------------------------------------------------+
|                    Rendering Bridge                                 |
|  +---------------------+  +------------------------------------+   |
|  | ANGLE (EGL/GLES->   |  | DXGI SwapChain                    |   |
|  | D3D11 translation)  |  | (created by ANGLE or directly)    |   |
|  +----------+----------+  +---+--------------------------------+   |
|             |                  |                                    |
+-------------+------------------+-----------------------------------+
              |
+-------------+------------------------------------------------------+
|                    Zig Core (libghostty)                            |
|  +------------------+  +----------------+  +-------------------+   |
|  | OpenGL Renderer  |  | Surface.zig    |  | App.zig           |   |
|  | (existing)       |  | (terminal      |  | (app state,       |   |
|  |                  |  |  state machine) |  |  surface mgmt)    |   |
|  +--------+---------+  +-------+--------+  +---------+---------+   |
|           |                    |                      |            |
|  +--------+---------+  +------+--------+  +-----------+---------+  |
|  | Font Layer       |  | Terminal      |  | Config              |  |
|  | (DWrite discover |  | (VT parser,   |  | (file load,         |  |
|  |  + FreeType rast) |  |  screen state)|  |  hot-reload)        |  |
|  +------------------+  +------+--------+  +---------------------+  |
|                               |                                    |
|                        +------+--------+                           |
|                        | Termio        |                           |
|                        | (ConPTY I/O)  |                           |
|                        +---------------+                           |
+--------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| **XAML Shell** | Window chrome, tabs, splits, menus, settings UI, DPI awareness, system tray, notifications. Owns the HWND and XAML DesktopWindow. | SwapChainPanel (contains), COM bridge (creates surfaces), Win32 APIs |
| **SwapChainPanel** | XAML element hosting a DXGI swap chain. Receives composition scale changes and pointer/keyboard input from XAML. One per terminal surface. | XAML Shell (parent), Rendering Bridge (provides swap chain target) |
| **Rendering Bridge** | Translates between Ghostty's OpenGL renderer and the DXGI swap chain inside SwapChainPanel. Uses ANGLE to provide an EGL/GLES context backed by D3D11. | SwapChainPanel (via ISwapChainPanelNative), OpenGL Renderer (provides GL context) |
| **COM Bridge (apprt)** | The `src/apprt/win32/` module. Implements the apprt interface. Creates/destroys WinRT objects via COM. Translates XAML events to `Surface.zig` calls. Calls `performAction` on `App.zig`. | XAML Shell (receives events), Zig Core (calls into Surface/App) |
| **Zig Core** | Terminal emulation, rendering, font, config, I/O. Unchanged from current architecture. | COM Bridge (via apprt interface), ConPTY (via termio) |

## Recommended Project Structure

```
src/
├── apprt/
│   ├── win32/              # New Windows apprt (parallel to gtk/)
│   │   ├── App.zig         # apprt.App implementation
│   │   ├── Surface.zig     # apprt.Surface implementation
│   │   ├── com.zig         # COM/WinRT helpers and IID definitions
│   │   ├── xaml.zig        # XAML bootstrap and Window creation
│   │   ├── input.zig       # Windows key/mouse event translation
│   │   ├── clipboard.zig   # Windows clipboard integration
│   │   └── dwrite.zig      # DirectWrite font discovery bridge
│   ├── gtk/                # Existing Linux/GTK apprt
│   ├── embedded.zig        # Existing macOS libghostty apprt
│   └── runtime.zig         # Add `win32` variant to Runtime enum
├── renderer/
│   ├── OpenGL.zig          # Existing (unchanged)
│   └── opengl/
│       └── Target.zig      # May need SwapChain-backed target variant
├── build/
│   └── Config.zig          # Add `win32` to ApprtRuntime enum
└── ...                     # Everything else unchanged
```

### Structure Rationale

- **`apprt/win32/`:** Mirrors the `apprt/gtk/` structure. A directory rather than a single file because Windows apprt will have significant platform-specific code (COM helpers, XAML bootstrap, input translation, clipboard).
- **Keep XAML definition in Zig, not separate XAML files:** Unlike GTK which uses blueprint/XML UI files, WinUI 3 XAML can be created programmatically via COM. This avoids a XAML compiler dependency and keeps everything in Zig. Windows Terminal itself creates some UI programmatically.
- **`com.zig`:** Centralizes COM IID definitions, `QueryInterface` helpers, reference counting wrappers, and WinRT activation helpers. This is the critical bridge layer.

## Architectural Patterns

### Pattern 1: Compile-Time Apprt Selection (Existing)

**What:** Ghostty uses `build_config.app_runtime` to select the apprt at compile time. Each apprt implements the same interface (`App.init`, `App.run`, `App.terminate`, `App.wakeup`, `App.performAction`, plus `Surface` methods).
**When to use:** Always. The Windows apprt slots into the existing pattern.
**Trade-offs:** Zero runtime overhead. Each platform build only compiles one apprt. Cannot switch at runtime, which is acceptable.

The key change is in `src/apprt/runtime.zig`:
```zig
pub const Runtime = enum {
    none,
    gtk,
    win32,  // NEW

    pub fn default(target: std.Target) Runtime {
        return switch (target.os.tag) {
            .linux, .freebsd => .gtk,
            .windows => .win32,  // NEW
            else => .none,
        };
    }
};
```

And in `src/apprt.zig`:
```zig
pub const win32 = @import("apprt/win32.zig");

pub const runtime = switch (build_config.artifact) {
    .exe => switch (build_config.app_runtime) {
        .none => none,
        .gtk => gtk,
        .win32 => win32,  // NEW
    },
    .lib => embedded,
    .wasm_module => browser,
};
```

### Pattern 2: XAML Chrome + DirectX Rendering Surface (Windows Terminal Pattern)

**What:** Windows Terminal's architecture uses XAML for all application chrome (TabView, menus, settings) while rendering the terminal grid to a SwapChainPanel via DirectX. The XAML framework handles layout, DPI scaling, input routing, and accessibility for chrome. The terminal content bypasses XAML rendering entirely.
**When to use:** This is the pattern Ghostty's Windows apprt must follow. XAML manages chrome; OpenGL (via ANGLE->D3D11) renders the terminal grid into a SwapChainPanel.
**Trade-offs:** Requires bridging two rendering worlds. SwapChainPanel has a limit of ~4 instances per app (MEDIUM confidence -- from Microsoft docs). Swap chain must be associated on the UI thread.

### Pattern 3: COM from Zig (No C++ Layer)

**What:** WinRT APIs are COM-based. Zig can call COM vtable methods directly since COM uses a well-defined ABI (virtual function tables with `stdcall` calling convention on Windows). The `zigwin32` project provides auto-generated bindings for Win32 APIs. For WinRT activation, use `RoActivateInstance` / `RoGetActivationFactory` from `combase.dll`.
**When to use:** All WinRT/WinUI 3 API calls from the Windows apprt.
**Trade-offs:** More verbose than C++/WinRT projections. Must manually manage `IUnknown::AddRef`/`Release`. Must define interface vtables and IIDs. But avoids a C++ build dependency entirely, which is a significant advantage for Ghostty's Zig-only build system.

**Example (conceptual):**
```zig
const ISwapChainPanelNative = extern struct {
    vtable: *const VTable,

    const IID = win32.GUID{ ... }; // 63aad0b8-7c24-40ff-85a8-640d944cc325

    const VTable = extern struct {
        // IUnknown
        query_interface: *const fn(...) callconv(.stdcall) HRESULT,
        add_ref: *const fn(...) callconv(.stdcall) u32,
        release: *const fn(...) callconv(.stdcall) u32,
        // ISwapChainPanelNative
        set_swap_chain: *const fn(*ISwapChainPanelNative, *IDXGISwapChain) callconv(.stdcall) HRESULT,
    };
};
```

## Data Flow

### Input Flow (XAML to Terminal)

```
XAML KeyDown/PointerPressed event
    |
    v
Win32 apprt event handler (registered on SwapChainPanel or parent)
    |
    v
Translate to input.KeyEvent / mouse event
    (apprt/win32/input.zig -- maps Windows virtual keys to Ghostty key codes)
    |
    v
CoreSurface.keyCallback() / CoreSurface.mouseButtonCallback()
    |
    v
[Existing Ghostty input pipeline: keybind check -> termio write -> PTY]
```

### Rendering Flow (Terminal State to Screen)

```
Terminal state changes (from PTY output parsing)
    |
    v
Renderer thread wakeup (via mailbox)
    |
    v
OpenGL renderer draws frame
    (into ANGLE-provided EGL surface backed by D3D11 texture)
    |
    v
eglSwapBuffers() -> DXGI Present()
    (ANGLE translates GL swap to DXGI swap chain present)
    |
    v
SwapChainPanel composites into XAML visual tree
    (Windows DWM presents the final frame)
```

**Critical threading note:** Unlike GTK (which requires `must_draw_from_app_thread = true` because GTK's GLArea does not support drawing from a different thread), the Windows apprt can likely draw from the renderer thread directly. ANGLE's D3D11 backend manages its own device context, and `ISwapChainPanelNative::SetSwapChain` only needs to be called once on the UI thread. Subsequent `Present()` calls can happen from any thread. This means the Windows apprt should set `must_draw_from_app_thread = false`, allowing the renderer thread to draw directly without round-tripping through the app thread. This is a significant performance advantage.

### Surface Lifecycle Flow

```
User action: new tab / new window / new split
    |
    v
XAML Shell creates new tab/split container
    |
    v
apprt/win32/App.zig creates new SwapChainPanel
    |
    v
Initialize ANGLE EGL context for this SwapChainPanel:
    1. Create D3D11 device (shared across surfaces)
    2. Create DXGI swap chain for this panel's size
    3. Call ISwapChainPanelNative::SetSwapChain() [UI thread]
    4. Create EGL surface wrapping the swap chain
    |
    v
Call App.addSurface() -> CoreSurface.init()
    |
    v
CoreSurface spawns renderer thread + IO thread
    (renderer thread uses the ANGLE EGL context)
    |
    v
Surface is live, rendering frames, processing PTY I/O
```

### Action Flow (Zig Core to XAML)

```
CoreSurface or App needs platform action
    (e.g., set_title, new_tab, toggle_fullscreen)
    |
    v
App.performAction(target, action, value)
    |
    v
apprt/win32/App.zig handles action:
    - set_title -> Update XAML TabViewItem.Header via COM
    - new_tab -> Create new XAML tab + SwapChainPanel
    - toggle_fullscreen -> Win32 SetWindowPos / XAML FullScreenMode
    - etc.
```

## How Windows Terminal's Architecture Maps to Ghostty

| Windows Terminal Layer | Ghostty Equivalent | Notes |
|------------------------|--------------------|-------|
| **CascadiaPackage** (MSIX) | MSIX packaging | Handles Store deployment, declares App SDK dependency |
| **TerminalApp** (DLL) | `src/apprt/win32/` (XAML shell) | Tabs, splits, settings UI, command palette |
| **TerminalControl** (DLL + SwapChainPanel) | `apprt/win32/Surface.zig` + SwapChainPanel + ANGLE | Hosts rendering surface, translates input |
| **TerminalCore** (LIB) | `src/terminal/`, `src/Surface.zig` | VT parsing, screen state -- already exists |
| **TerminalConnection** | `src/termio/` (ConPTY backend) | PTY I/O -- already exists |
| **DX Renderer** | `src/renderer/OpenGL.zig` via ANGLE | WT uses D3D11 directly; Ghostty uses OpenGL->ANGLE->D3D11 |

Key difference: Windows Terminal has 4 separate C++ projects with WinRT interfaces between them. Ghostty keeps everything in Zig with compile-time interfaces, which is simpler. The XAML shell and the rendering bridge are both inside `apprt/win32/`.

## Rendering Surface: SwapChainPanel via ANGLE

### Why ANGLE (HIGH confidence)

Ghostty's renderer is OpenGL 4.3. Windows has no native OpenGL driver guarantee (only OpenGL 1.1 from Microsoft's software renderer). The options are:

1. **ANGLE (OpenGL ES -> D3D11):** Translates GL calls to D3D11. Proven in Chrome, Firefox, Electron. Can target a DXGI swap chain that SwapChainPanel hosts. Ghostty would need to target OpenGL ES 3.1 (subset of GL 4.3) or ANGLE's desktop GL emulation.
2. **Mesa/Dozen (OpenGL -> D3D12):** Newer, less battle-tested on Windows desktop. More complex setup.
3. **Native WGL (vendor driver):** Works on NVIDIA/AMD/Intel but not guaranteed. Cannot integrate with SwapChainPanel (WGL needs an HWND, not a swap chain panel).
4. **Child HWND overlay:** Create a Win32 child window over the XAML area, use WGL on it. Hacky, breaks XAML composition, DPI, and input routing.

**Recommendation: ANGLE.** It is the proven path for hosting OpenGL content inside a DXGI swap chain. Microsoft maintains a fork specifically for Windows Store/UWP scenarios. Someone has already demonstrated ANGLE working with WinUI 3 SwapChainPanel (MEDIUM confidence -- single source: Levin Li's tweet/sample project).

### SwapChainPanel Setup Sequence

1. XAML Shell creates a `Microsoft.UI.Xaml.Controls.SwapChainPanel` element inside each tab/split
2. `QueryInterface` the SwapChainPanel for `ISwapChainPanelNative` (COM interface, IID `63aad0b8-7c24-40ff-85a8-640d944cc325`)
3. Create a D3D11 device and DXGI swap chain sized to the panel
4. Call `ISwapChainPanelNative::SetSwapChain(swap_chain)` on the UI thread
5. Initialize ANGLE's EGL display using `EGL_D3D11_DEVICE_ANGLE` extension, pointing at the shared D3D11 device
6. Create an EGL surface wrapping the DXGI swap chain (or let ANGLE create its own and connect them)
7. Ghostty's OpenGL renderer draws into this EGL context via ANGLE

### SwapChainPanel Limitations

- Maximum ~4 SwapChainPanel instances per app (Microsoft docs). This limits the number of simultaneously visible terminal surfaces. For tabs, only the active tab's panel needs to be live. For splits, each visible split pane needs its own panel. With 4 panels, you can show up to 4 splits, which covers the vast majority of use cases.
- No transparency support on SwapChainPanel. Terminal background blur/acrylic effects would require a different approach (e.g., composing behind the panel).
- `CompositionScaleChanged` event must be monitored for DPI changes.

## Anti-Patterns

### Anti-Pattern 1: C++ Wrapper Layer

**What people do:** Create a C++ DLL that wraps WinRT calls and exposes a C API to Zig.
**Why it's wrong:** Adds a build dependency on MSVC or Clang C++ toolchain. Increases build complexity. The C++ layer becomes a maintenance burden that drifts from the Zig code.
**Do this instead:** Call COM interfaces directly from Zig. WinRT is COM under the hood. Define vtable structs in Zig matching the COM interface layout. Use `zigwin32` bindings for Win32/DXGI/D3D11 APIs.

### Anti-Pattern 2: Rendering Through XAML

**What people do:** Use XAML text elements or Canvas to render terminal content.
**Why it's wrong:** XAML layout is far too slow for terminal rendering. Even simple text updates would go through XAML's measure/arrange/render pipeline, destroying performance.
**Do this instead:** Use SwapChainPanel as a rendering surface. XAML only manages chrome (tabs, menus, overlays). The terminal grid is rendered directly via OpenGL/ANGLE->D3D11.

### Anti-Pattern 3: Single Shared GL Context Across Surfaces

**What people do:** Share one OpenGL context across all terminal surfaces and switch targets per frame.
**Why it's wrong:** GL context switches are expensive. Ghostty's architecture creates one renderer thread per surface, which would contend on a shared context.
**Do this instead:** Each surface gets its own ANGLE EGL context (sharing a D3D11 device for resource efficiency). Each renderer thread owns its context exclusively.

### Anti-Pattern 4: Spawning XAML from a Console Subsystem Executable

**What people do:** Build as a console app and try to initialize XAML Islands.
**Why it's wrong:** XAML initialization requires a proper Windows App SDK bootstrap. Console subsystem executables show a console window flash.
**Do this instead:** Build as a Windows subsystem executable. Use `WindowsApp.lib` bootstrap for Windows App SDK initialization. Handle console attachment separately for CLI actions.

## Build Order (Suggested Phases)

The following build order is driven by dependency analysis and the need for early validation of the riskiest integration points.

### Phase 1: COM Foundation + Minimal Window

**Must come first** because every subsequent phase depends on COM interop working correctly.

- Zig COM helpers (`QueryInterface`, `AddRef`/`Release` wrappers, IID definitions)
- Windows App SDK bootstrap (initialize WinRT, create `DispatcherQueue`)
- Create a minimal XAML `Window` with a single `SwapChainPanel`
- Wire up ANGLE: create EGL display -> EGL context -> render a solid color
- **Validates:** COM from Zig works, ANGLE + SwapChainPanel integration works, build system produces a working Windows GUI exe

### Phase 2: Single Terminal Surface

**Depends on Phase 1.** The core value proof -- a working terminal in the window.

- Implement `apprt/win32/App.zig` and `apprt/win32/Surface.zig` (minimal)
- Connect Ghostty's OpenGL renderer to the ANGLE EGL context
- Wire ConPTY (already exists in `src/termio/`) to the surface
- Implement keyboard input translation (Win32 virtual keys -> Ghostty key codes)
- Implement mouse input from XAML pointer events
- **Validates:** Full rendering pipeline, input pipeline, terminal emulation in native window

### Phase 3: Multi-Surface + Tabs + Splits

**Depends on Phase 2.** Adds the XAML chrome that makes it a real application.

- XAML `TabView` for tabs (create/close/switch tabs)
- Split layout (either custom XAML panel or `Grid` with `GridSplitter`)
- Multiple SwapChainPanel lifecycle management
- `performAction` implementation for tab/split/window actions
- Clipboard integration (Win32 clipboard APIs)
- **Validates:** Multi-surface management, SwapChainPanel limit handling, action system

### Phase 4: Platform Integration + Polish

**Depends on Phase 3.** Everything needed for a shippable product.

- IME support (Windows Text Services Framework or `ImmGetCompositionString`)
- DirectWrite font discovery (bridge to existing freetype rasterization)
- DPI awareness and multi-monitor scaling (`CompositionScaleChanged`)
- System tray integration
- Native Windows notifications
- Settings/config UI
- MSIX packaging
- **Validates:** Full feature parity target, distribution readiness

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Windows App SDK / WinUI 3 | COM activation via `RoActivateInstance` | Must bootstrap via `WindowsApp.lib` or dynamic loading |
| ANGLE | EGL/GLES dynamic library | Build ANGLE as DLL, ship alongside exe, or statically link |
| DXGI / D3D11 | COM interfaces via `zigwin32` bindings | For swap chain creation; ANGLE may handle this internally |
| DirectWrite | COM interfaces for font enumeration | `IDWriteFactory` -> `GetSystemFontCollection` -> enumerate |
| ConPTY | Win32 API (already implemented in Ghostty) | `src/termio/` already has Windows PTY support |
| Windows Clipboard | Win32 `OpenClipboard`/`GetClipboardData`/`SetClipboardData` | Or WinRT `DataTransferManager` for richer clipboard |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| XAML Shell <-> COM Bridge | COM method calls (same thread, UI thread) | XAML events fire callbacks in apprt |
| COM Bridge <-> Zig Core | Direct Zig function calls via apprt interface | Same process, no marshaling |
| Renderer Thread <-> SwapChainPanel | ANGLE EGL context (renderer thread owns it) | `SetSwapChain` called once on UI thread; subsequent rendering is on renderer thread |
| App Thread <-> Renderer Thread | Mailbox (existing pattern) | `must_draw_from_app_thread = false` -- renderer draws directly |

## Sources

- [SwapChainPanel Class - Windows App SDK](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel?view=windows-app-sdk-1.8) -- Official Microsoft documentation (HIGH confidence)
- [Building Windows Terminal with WinUI](https://devblogs.microsoft.com/commandline/building-windows-terminal-with-winui/) -- Microsoft DevBlog on WT architecture (HIGH confidence)
- [Windows Terminal ORGANIZATION.md](https://github.com/Microsoft/Terminal/blob/main/doc/ORGANIZATION.md) -- Source code organization (HIGH confidence)
- [ISwapChainPanelNative interface](https://learn.microsoft.com/en-us/windows/win32/api/windows.ui.xaml.media.dxinterop/nn-windows-ui-xaml-media-dxinterop-iswapchainpanelnative) -- COM interface for SwapChainPanel (HIGH confidence)
- [DirectX and XAML interop](https://learn.microsoft.com/en-us/windows/uwp/gaming/directx-and-xaml-interop) -- Microsoft docs on XAML+DX integration (HIGH confidence)
- [zigwin32 - Win32 API bindings for Zig](https://github.com/marlersoft/zigwin32) -- Community project for Zig Win32 bindings (MEDIUM confidence)
- [ANGLE - OpenGL ES to DirectX translation](https://github.com/google/angle) -- Google's ANGLE project (HIGH confidence)
- [Microsoft ANGLE fork](https://github.com/microsoft/angle) -- Microsoft's ANGLE fork with SwapChainPanel support (MEDIUM confidence)
- [ANGLE + WinUI 3 SwapChainPanel demo](https://x.com/LevinLi303/status/1626091977845444608) -- Community demonstration (LOW confidence -- single source)
- [Creating DirectX 11 SwapChain in WinUI 3.0](https://www.juhakeranen.com/winui3/directx-11-2-swap-chain.html) -- Tutorial (MEDIUM confidence)
- Ghostty codebase: `src/apprt.zig`, `src/apprt/runtime.zig`, `src/apprt/embedded.zig`, `src/apprt/gtk/`, `src/renderer/OpenGL.zig`, `src/Surface.zig`, `src/build/Config.zig` (HIGH confidence -- primary source)

---
*Architecture research for: Native Windows apprt for Ghostty*
*Researched: 2026-02-24*
