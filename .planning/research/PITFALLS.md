# Pitfalls Research

**Domain:** Native Windows terminal emulator apprt (WinUI 3 + COM from Zig + OpenGL)
**Researched:** 2026-02-24
**Confidence:** MEDIUM — based on codebase analysis, documented WinUI 3 issues, Windows Terminal architecture post-mortems, and COM/Zig ecosystem investigation

## Critical Pitfalls

### Pitfall 1: XAML Threading Model vs Ghostty's Multi-Threaded Renderer

**What goes wrong:**
Ghostty runs a dedicated renderer thread per surface (`src/renderer/Thread.zig`) and a separate IO thread per surface (`src/Surface.zig:120`). WinUI 3 / XAML requires all UI operations on the DispatcherQueue (UI) thread. Calling any XAML API from the renderer or IO thread causes `RPC_E_WRONG_THREAD` (0x8001010E) — "The application called an interface that was marshalled for a different thread." This is not a warning; it is a hard COM error that crashes.

**Why it happens:**
WinUI 3 uses an STA (Single-Threaded Apartment) model, not the ASTA (Application Single-Threaded Apartment) model UWP used. The STA model additionally lacks reentrancy guards that UWP's ASTA provided, meaning even callbacks dispatched to the UI thread can re-enter. Developers familiar with GTK's similar constraint (Ghostty already handles this via `must_draw_from_app_thread = true`) may underestimate the strictness — GTK at least has `g_idle_add` for safe cross-thread dispatch, while WinUI 3 requires `DispatcherQueue.TryEnqueue` from COM.

**How to avoid:**
- Set `must_draw_from_app_thread = true` in the Windows apprt (same pattern as `src/apprt/gtk/App.zig:22`). This makes the renderer thread send `redraw_surface` messages to the app thread instead of calling `drawFrame` directly.
- For OpenGL context management: the OpenGL context itself can be current on a single thread at a time. If using WGL (not ANGLE), the rendering can happen on the renderer thread as long as no XAML calls are made. The `threadEnter`/`threadExit` pattern in `src/renderer/OpenGL.zig:197-235` must make the WGL context current on the renderer thread.
- Implement a thin `DispatcherQueue.TryEnqueue` wrapper callable from Zig. This is a COM method call, not a Win32 API — it requires the `IDispatcherQueue` interface pointer.
- Audit every XAML interaction point. Tab creation, title updates, focus changes, and DPI notifications all must happen on the UI thread.

**Warning signs:**
- Intermittent crashes with `RPC_E_WRONG_THREAD` HRESULT, especially during tab/window operations triggered by terminal output
- Deadlocks where the renderer thread blocks waiting for the UI thread, which is blocked waiting for something the renderer thread holds
- "Works fine with one tab, crashes with two" — classic sign of thread-unsafe XAML access

**Phase to address:**
Phase 1 (Foundation) — the apprt skeleton must establish threading discipline before any XAML surface hosting is added. Get the `must_draw_from_app_thread` and DispatcherQueue dispatch working before building out tabs/splits.

---

### Pitfall 2: SwapChainPanel DPI Scaling Renders at Wrong Position

**What goes wrong:**
SwapChainPanel renders content at the wrong screen position when display scaling is not 100%. This is a documented WinUI 3 bug (microsoft/microsoft-ui-xaml#5888). The rendering surface shifts off-position during resize operations. Additionally, `CompositionScaleChanged` can return incorrect scale values after DPI changes (microsoft/microsoft-ui-xaml#9794).

**Why it happens:**
SwapChainPanel internally transforms coordinates for DPI but the composition scale it reports and the actual rasterization coordinates can disagree, particularly during or immediately after resize. The swap chain's buffer dimensions must match the physical pixel dimensions, but XAML layout works in logical (DIP) coordinates. If you create the swap chain at DIP size instead of physical pixel size, or if you trust `CompositionScaleX/Y` without validation, the content renders at the wrong scale or position.

**How to avoid:**
- Always create swap chain buffers at physical pixel dimensions: `width_dip * scale_factor`, `height_dip * scale_factor`.
- Do not rely solely on `CompositionScaleChanged`. Cross-check with `XamlRoot.RasterizationScale` and the window's actual DPI (via `GetDpiForWindow` Win32 API).
- Apply `SwapChainPanel.CompositionScaleX/Y` as an inverse transform on the swap chain's matrix transform to counter XAML's automatic scaling.
- Handle `SizeChanged`, `CompositionScaleChanged`, and `XamlRoot.Changed` events — all three can indicate a need to resize buffers.
- Test on 100%, 125%, 150%, 175%, 200%, and 250% scaling. Multi-monitor setups with mixed scaling are the hardest case.
- Ghostty already has DPI/scale handling in `src/apprt/structs.zig` (`ContentScale`) and surfaces track `content_scale` — wire this to the WinUI scale events correctly.

**Warning signs:**
- Content appears correct at 100% scaling but shifts or is clipped at 150%
- Resize causes content to jump before settling
- Text appears blurry (rendering at wrong resolution then being scaled by compositor)
- Different behavior on laptop screen vs external monitor

**Phase to address:**
Phase 2 (Surface Hosting) — when SwapChainPanel is first integrated. Must be validated before Phase 3 (Tabs/Splits) since multi-monitor DPI changes happen when dragging windows between monitors.

---

### Pitfall 3: OpenGL Inside XAML — No Native WGL with SwapChainPanel

**What goes wrong:**
SwapChainPanel expects a DXGI swap chain (`IDXGISwapChain1`). It does not accept an OpenGL rendering context directly. There is no way to create a WGL context targeting a SwapChainPanel because WGL requires an HWND with a device context (HDC), and SwapChainPanel is a XAML composition surface, not an HWND. Developers who assume "OpenGL works on Windows therefore it works in XAML" will hit a wall.

**Why it happens:**
XAML's visual tree is composed through DirectComposition/DComp. SwapChainPanel provides a slot in this composition tree for a DXGI swap chain. OpenGL on Windows traditionally goes through WGL which operates on HWNDs. These are fundamentally different surface models.

**How to avoid:**
There are three viable strategies, in order of recommendation:

1. **ANGLE (recommended):** Build ANGLE with `angle_is_winappsdk=true` to get EGL support for SwapChainPanel. ANGLE translates OpenGL ES calls to D3D11. Ghostty's renderer requires OpenGL 4.3 (`src/renderer/OpenGL.zig:37-38`), but ANGLE only supports OpenGL ES 3.1. The renderer's GLSL shaders and GL calls must be audited for ES compatibility or an ES-compatible path must be added.

2. **WGL_NV_DX_interop:** Create a hidden HWND for WGL context, render to an OpenGL texture, then use `wglDXRegisterObjectNV` / `wglDXLockObjectsNV` to share that texture with a D3D11 texture that backs the swap chain. Requires NVIDIA extension support (also available on AMD/Intel for years). Adds complexity but preserves desktop OpenGL 4.3.

3. **Offscreen render + copy:** Render to an OpenGL FBO, read pixels back to CPU, copy to D3D11 texture. Unacceptable for performance — would fail the "outperform Windows Terminal" requirement.

**Warning signs:**
- `eglCreateWindowSurface` returns `EGL_BAD_NATIVE_WINDOW` when passed a SwapChainPanel
- Ghostty's OpenGL 4.3 shaders fail to compile under ANGLE's ES 3.1 translation
- Frame presentation works in a test harness but shows a black surface inside XAML

**Phase to address:**
Phase 1 (Foundation) — the rendering surface strategy must be validated in a standalone proof-of-concept before any apprt code is written. This is the highest-risk technical decision. If ANGLE cannot meet the OpenGL feature requirements, the entire rendering strategy must change.

---

### Pitfall 4: COM Calling Convention and Vtable Layout from Zig

**What goes wrong:**
WinRT APIs are COM interfaces under the hood. Calling COM from Zig requires manually defining vtable structs with the correct calling convention (`callconv(std.os.windows.WINAPI)` = `__stdcall` on x86, `__fastcall` on x86_64), correct vtable slot ordering (IUnknown methods first, then interface-specific methods in declaration order), and correct parameter passing (first parameter is always the interface pointer itself — the `this` pointer). A single vtable slot misalignment corrupts the stack or calls the wrong method.

**Why it happens:**
C++ COM development hides vtable details behind compiler-generated code. Zig has no COM support in the language — everything must be manually defined or generated. The `zigwin32` project generates bindings for Win32 COM interfaces but does not cover WinUI 3 / Windows App SDK interfaces (which are WinRT/MIDL3-based, not classic Win32 IDL). Type conflicts also arise between `std.os.windows.HWND` and any imported C header's `HWND` (different Zig types for the same thing — see Ziggit thread on extern struct vs `*opaque{}`).

**How to avoid:**
- Start with a minimal COM proof-of-concept: `IUnknown.QueryInterface` / `AddRef` / `Release` on a known WinRT object (e.g., `DispatcherQueueController`). Verify reference counting works before building anything complex.
- Use `zigwin32` for standard Win32 COM interfaces (e.g., `IDXGISwapChain1`, `ID3D11Device`). For WinUI 3 interfaces (`ISwapChainPanelNative`, `IDesktopWindowXamlSource`), hand-write vtable definitions from the WinRT metadata (winmd) or the C-style headers in the Windows App SDK.
- Define a `ComInterface` helper in Zig that encapsulates: vtable pointer type, `QueryInterface` / `AddRef` / `Release` wrappers, `as(T)` for QI-based casting, and nullable/optional handling. This prevents per-interface boilerplate errors.
- Be explicit about HRESULT checking — every COM call returns HRESULT. Do not ignore return values. `S_OK = 0`, anything else is an error. Use Zig's error handling: `if (hr < 0) return error.ComError`.
- Test on both x86_64 (primary target) and ARM64 if supporting Windows on ARM. Calling conventions differ.

**Warning signs:**
- Access violations (0xC0000005) when calling COM methods — likely vtable misalignment
- HRESULT `E_NOINTERFACE` (0x80004002) on QueryInterface — wrong IID or wrong vtable base
- Reference count leaks causing objects to never be freed (memory grows over session lifetime)
- Stack corruption symptoms: wrong method called, garbled parameters

**Phase to address:**
Phase 1 (Foundation) — COM infrastructure is the lowest layer. Every WinUI 3 interaction depends on it. Build and test the COM helper types first, before any XAML or rendering code.

---

### Pitfall 5: Windows App SDK Runtime Not Installed — Silent Failure on Launch

**What goes wrong:**
WinUI 3 applications require the Windows App SDK runtime. If a user installs Ghostty via sideload (not Microsoft Store) or runs a portable build, the runtime may not be present. The application either fails to launch with a cryptic error ("The application failed to start because its side-by-side configuration is incorrect") or crashes during `XamlSourceInitialize`.

**Why it happens:**
The Windows App SDK uses a framework package deployment model. MSIX-packaged apps declare a dependency and the Store handles installation. Non-Store distribution (sideload, portable zip) requires either: (a) bundling the runtime (increases package size ~50MB), (b) requiring users to install the runtime separately, or (c) using the bootstrapper API to dynamically install it. PROJECT.md states "Store handles App SDK runtime dependency — no bundling needed" but sideload is also listed as a distribution target.

**How to avoid:**
- For Store distribution: declare the framework dependency in the MSIX manifest. The Store handles the rest.
- For sideload: use the Windows App SDK bootstrapper API (`MddBootstrapInitialize2`) at application startup. This API checks for the runtime and can download/install it automatically. It must be called before any WinUI 3 APIs.
- Provide a clear error message if the runtime is missing, with a download link. Do not let the OS show its generic side-by-side error.
- Pin a specific Windows App SDK version (e.g., 1.7.x) and test against it. Do not target "latest" — breaking changes happen between major versions, and minor version mismatches can cause subtle issues.
- The GLFW fallback apprt should remain available during the transition period so users can still launch Ghostty even if the WinUI 3 runtime is unavailable.

**Warning signs:**
- Works on developer machine (SDK installed) but fails on clean Windows install
- Works on Windows 11 but fails on Windows 10 (different default runtime availability)
- CI builds pass but users report "failed to start" errors

**Phase to address:**
Phase 5 (Packaging/Distribution) — but the bootstrapper API integration should be prototyped in Phase 1 to validate the deployment model early. The GLFW coexistence strategy from PROJECT.md provides a safety net.

---

### Pitfall 6: IME (Input Method Editor) Does Not Work in Custom Rendering Surfaces

**What goes wrong:**
IME composition windows (used for CJK input, dead keys, and complex scripts) do not appear or appear at the wrong position when the terminal content is rendered via OpenGL/D3D inside a SwapChainPanel. Standard XAML TextBox controls get IME support automatically, but custom rendering surfaces do not. Users typing in Chinese, Japanese, or Korean see no composition candidates, or candidates appear at screen origin (0,0) instead of at the cursor.

**Why it happens:**
XAML's IME support is built into its text controls via the Text Services Framework (TSF). SwapChainPanel is not a text control — it's a raw rendering surface. TSF requires an `ITfThreadMgr` and `ITfDocumentMgr` to be set up, with an `ITfContext` that reports the text position for the composition window. None of this exists by default for a custom rendering surface. Additionally, TSF's COM interfaces are complex (dozens of methods across multiple interfaces).

**How to avoid:**
- Do NOT attempt full TSF integration initially. Instead, use the simpler IMM32 API (`ImmGetContext`, `ImmSetCompositionWindow`, `ImmSetCandidateWindow`) which is still supported and sufficient for basic IME functionality. Ghostty already has `IMEPos` in `src/apprt/structs.zig` for reporting cursor position to the IME.
- Position the IME composition window by calling `ImmSetCompositionWindow` with `CFS_POINT` and the pixel coordinates of the terminal cursor. This requires knowing the HWND — for WinUI 3, get it via `IWindowNative::get_WindowHandle`.
- Handle `WM_IME_COMPOSITION`, `WM_IME_STARTCOMPOSITION`, `WM_IME_ENDCOMPOSITION` messages. In WinUI 3, this requires subclassing the HWND or using an `InputPreview` handler.
- Test with: Microsoft IME (Japanese), Microsoft Pinyin (Chinese), Korean IME, and at least one third-party IME (e.g., Google Japanese Input, Sogou Pinyin). Each behaves differently.
- Dead key support (for European languages) is separate from IME — it uses `WM_DEADCHAR` / `WM_CHAR` sequences and should work through standard keyboard input handling.

**Warning signs:**
- IME candidate window appears at (0,0) or off-screen
- Typing in CJK languages produces nothing or produces committed characters without composition preview
- Dead keys produce double characters (e.g., typing `^` then `e` produces `^e` instead of `ê`)
- Works with Microsoft IME but not with third-party IMEs

**Phase to address:**
Phase 3 (Input Handling) — after basic keyboard input works. IME is complex enough to warrant its own sub-phase. Ship without full IME first, but do not mark input handling as complete without it.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoding vtable definitions instead of generating from winmd | Faster to prototype, no tooling dependency | Every Windows App SDK update requires manual vtable re-verification; easy to introduce slot misalignment | Phase 1 only — build a generator before Phase 3 |
| Using IMM32 instead of TSF for IME | Much simpler (5 API calls vs 50+ COM methods) | Some advanced IME features (text suggestions, handwriting) won't work; some modern IMEs may behave suboptimally | Acceptable long-term — even Windows Terminal uses IMM32 for its custom renderer |
| Rendering to offscreen FBO then blitting to DXGI | Avoids ANGLE dependency, keeps desktop GL | Adds one full frame of latency plus GPU-to-CPU-to-GPU copy; halves throughput | Never — fails the performance requirement |
| Skipping `must_draw_from_app_thread` by "just being careful" | Avoids DispatcherQueue dispatch overhead | Random crashes under load, impossible to debug | Never |
| Bundling Windows App SDK runtime in the installer | Eliminates runtime dependency problem | 50+ MB size increase, must update bundled runtime for security patches | Acceptable as fallback if bootstrapper API proves unreliable |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| DXGI SwapChain + SwapChainPanel | Creating swap chain with `CreateSwapChainForHwnd` | Must use `CreateSwapChainForComposition` — SwapChainPanel is not an HWND. Then call `ISwapChainPanelNative::SetSwapChain` |
| WinUI 3 HWND access | Using `FindWindow` or `GetActiveWindow` | Use `IWindowNative::get_WindowHandle` COM interface on the WinUI Window object |
| DispatcherQueue from background thread | Calling `DispatcherQueue.GetForCurrentThread()` from renderer thread | Capture the UI thread's DispatcherQueue during init and pass it to background threads. `GetForCurrentThread` returns null on non-UI threads |
| Windows App SDK bootstrapper | Calling WinUI 3 APIs before `MddBootstrapInitialize2` | Bootstrap must be the very first call. Even `RoInitialize` must wait. Order: `MddBootstrapInitialize2` -> `RoInitialize` -> XAML init |
| ConPTY resize | Calling `ResizePseudoConsole` from the UI thread during `SizeChanged` | Resize should be debounced and performed from the IO thread to avoid blocking the UI thread and causing resize feedback loops |
| OpenGL context sharing | Creating one GL context and using it from multiple threads | One GL context per thread, or explicit `wglMakeCurrent(NULL, NULL)` before transferring. Ghostty's `threadEnter`/`threadExit` pattern handles this correctly |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| XAML layout in the rendering path | Frame time spikes during tab switches or split resizes | Terminal grid rendering must go directly to SwapChainPanel, never through XAML layout/measure/arrange. XAML manages chrome only (tab bar, title bar) | Immediately — any XAML in the hot path adds 2-5ms per frame |
| `SwapChain.Present(1, 0)` with vsync in a timer-driven renderer | Renderer thread blocks on Present() while the xev timer fires again, queueing frames | Use `Present(0, DXGI_PRESENT_ALLOW_TEARING)` for immediate presentation, or use `DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT` to sync with compositor | At 120 FPS target (`DRAW_INTERVAL = 8` in `src/renderer/Thread.zig:19`) |
| GPU-CPU readback for cursor position reporting | `glReadPixels` or equivalent stalls the GPU pipeline | Track cursor position analytically from terminal state, not by reading back rendered pixels | Immediately — any readback adds 1-10ms |
| Allocating COM objects per frame | GC pressure (if using a GC language) or allocation overhead | Pre-allocate command lists, reuse swap chain buffers. In Zig this is less of a concern but COM `AddRef`/`Release` overhead accumulates | At high scroll rates (thousands of lines/second) |
| Unbounded `DispatcherQueue.TryEnqueue` from renderer thread | UI thread falls behind, enqueued callbacks pile up, memory grows | Coalesce redraw requests: set a dirty flag and only enqueue if no pending redraw. The `redraw_surface` pattern in Ghostty already does this | When holding PageDown in a large file |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Not validating HRESULT from COM calls | Unchecked error leads to null pointer dereference on the returned interface pointer | Wrap every COM call in HRESULT check. Zig's error handling makes this natural: `if (hr < 0) return error.ComCallFailed` |
| Running with elevated privileges for ConPTY | Terminal inherits admin rights, child processes run as admin | Never request elevation. ConPTY works fine at normal user privilege. Use `CreateProcessAsUser` if de-elevation is needed |
| Exposing COM interfaces across process boundaries without marshaling | Malicious process could QI for internal interfaces | Not a concern for Ghostty's in-process COM usage — only relevant if exposing automation interfaces |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Tab bar visual mismatch between XAML TabView and terminal content | Jarring transition between Fluent Design tabs and OpenGL-rendered content at different DPI scales | Use `SwapChainPanel` background matching the XAML theme. Ensure the terminal background color alpha-blends correctly with the XAML visual tree |
| Window resize causes visible black gutters | During resize, the swap chain buffer is the old size while the window is the new size, creating black bars | Handle `SizeChanged` synchronously: resize the swap chain before returning from the event handler, or use `DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH` for smoother transitions |
| Title bar integration missing | WinUI 3 has a default title bar, but Windows Terminal users expect a custom title bar with tabs integrated | Use `AppWindow.TitleBar.ExtendsContentIntoTitleBar = true` and host the TabView in the title bar area. This is a WinUI 3 API, not a Win32 hack |
| System theme changes not reflected | User switches from Light to Dark mode, terminal keeps old theme | Subscribe to `UISettings.ColorValuesChanged` and `XamlRoot.ActualThemeChanged`. Propagate to Ghostty's `ColorScheme` (already defined in `src/apprt/structs.zig`) |

## "Looks Done But Isn't" Checklist

- [ ] **OpenGL rendering in XAML:** Surface shows content at 100% DPI — verify it also works at 125%, 150%, 200%, and on multi-monitor setups with mixed DPI
- [ ] **Keyboard input:** ASCII keys work — verify dead keys (European), IME composition (CJK), and AltGr (German/French keyboards) all produce correct output
- [ ] **Tab management:** Tabs open and close — verify drag-reorder, middle-click-to-close, Ctrl+Tab cycling, and tab overflow scrolling all work
- [ ] **Clipboard:** Copy/paste works with plain text — verify it handles RTF, HTML fragments, large pastes (>1MB), and clipboard history (Win+V)
- [ ] **Window management:** Single window works — verify multi-window, snap layouts (Win+Z), virtual desktop switching, and minimize-to-tray all work
- [ ] **Performance:** Renders fast in benchmarks — verify no frame drops during resize, tab switch, or when system goes to sleep and wakes up
- [ ] **ConPTY lifecycle:** Shell starts and runs — verify graceful handling of shell crash, `exit` command, window close during long-running process, and the "Close anyway?" dialog
- [ ] **Accessibility:** Screen readers can read terminal content — verify UIA provider is implemented for the custom rendering surface (Windows Terminal spent significant effort here)

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong OpenGL surface strategy (e.g., chose WGL when ANGLE was needed) | HIGH | Requires rewriting the GL context creation and possibly shader pipeline. Mitigate by prototyping both approaches in Phase 1 |
| COM vtable misalignment causing crashes | MEDIUM | Identify the wrong offset by comparing against the IDL/winmd definition. Fix the vtable struct. If many interfaces are affected, build a code generator |
| DPI scaling bugs | LOW-MEDIUM | Usually fixable by correcting the coordinate transform math. Test matrix is the expensive part |
| Threading violations (cross-thread XAML access) | MEDIUM | Add DispatcherQueue dispatch at the call site. Hard part is finding all violations — they may only manifest under load |
| Windows App SDK version incompatibility | LOW | Pin the version in the build system and MSIX manifest. Test against the pinned version in CI |
| IME not working | MEDIUM | IME fixes are typically isolated to the input handling module. The difficulty is testing — requires IME-capable keyboard layouts and native speaker verification |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| XAML threading model violations | Phase 1: Foundation | Stress test with rapid tab creation/destruction from terminal commands; no `RPC_E_WRONG_THREAD` errors in debug output |
| SwapChainPanel DPI scaling | Phase 2: Surface Hosting | Visual inspection at 100%, 150%, 200% scaling; drag window between monitors with different DPI |
| OpenGL inside XAML (ANGLE vs WGL interop) | Phase 1: Foundation (POC) | `cat large_file.txt` renders correctly inside a WinUI 3 window; measure throughput matches GLFW baseline |
| COM vtable layout from Zig | Phase 1: Foundation | Successfully create and interact with at least 5 different COM interfaces without crashes over 1000 iterations |
| Windows App SDK runtime missing | Phase 5: Packaging | Test on clean Windows 10 1809 VM with no SDK; application either launches or shows actionable error |
| IME in custom rendering surface | Phase 3: Input Handling | Type CJK characters with Microsoft IME and Google Japanese Input; composition window appears at cursor position |

## Sources

- [WinUI 3 SwapChainPanel DPI scaling bug — microsoft/microsoft-ui-xaml#5888](https://github.com/microsoft/microsoft-ui-xaml/issues/5888)
- [SwapChainPanel image quality at non-100% DPI — microsoft/microsoft-ui-xaml#9794](https://github.com/microsoft/microsoft-ui-xaml/issues/9794)
- [WinUI 3 custom GPU rendering options — microsoft/microsoft-ui-xaml#5193](https://github.com/microsoft/microsoft-ui-xaml/issues/5193)
- [Building Windows Terminal with WinUI — Windows Developer Blog](https://devblogs.microsoft.com/commandline/building-windows-terminal-with-winui/)
- [ANGLE SwapChainPanel support for WinUI 3 — microsoft/angle#170](https://github.com/microsoft/angle/issues/170)
- [WinUI 3 COM apartment threading — Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/1184556/winui3-understating-com-apartments-and-objects-in)
- [WinUI 3 cross-thread COMException — microsoft/microsoft-ui-xaml Discussion#8410](https://github.com/microsoft/microsoft-ui-xaml/discussions/8410)
- [Threading migration for Windows App SDK — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/threading)
- [DispatcherQueue spec — microsoft/microsoft-ui-xaml-specs](https://github.com/microsoft/microsoft-ui-xaml-specs/blob/master/winui3/DispatcherQueueUpdates.md)
- [ConPTY race conditions — microsoft/terminal#394, #1156](https://github.com/microsoft/terminal/issues/394)
- [ConPTY close race condition fix — lldb PR#182302](http://www.mail-archive.com/lldb-commits@lists.llvm.org/msg139057.html)
- [zigwin32 generator — marlersoft/zigwin32gen](https://github.com/marlersoft/zigwin32gen)
- [Zig Win32 type conflicts — Ziggit](https://ziggit.dev/t/win32-apps-with-zig-conflicting-defintions-extern-struct-vs-opaque/1400)
- [Windows App SDK deployment architecture — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deployment-architecture)
- [Windows App SDK stable channel releases — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/stable-channel)
- [TSF documentation — Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework)
- [ANGLE + SwapChainPanel WinUI 3 sample — Levin Li](https://x.com/LevinLi303/status/1626091977845444608)
- Ghostty codebase analysis: `src/apprt.zig`, `src/apprt/gtk/App.zig`, `src/renderer/OpenGL.zig`, `src/renderer/Thread.zig`, `src/Surface.zig`, `src/os/windows.zig`

---
*Pitfalls research for: Native Windows terminal emulator apprt (WinUI 3 + COM from Zig + OpenGL)*
*Researched: 2026-02-24*
