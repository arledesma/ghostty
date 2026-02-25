# Ghostty Native Windows Apprt

## What This Is

A 100% native Microsoft Windows application runtime for Ghostty that replaces the current GLFW cross-platform shim with a WinUI 3 (XAML) shell around Ghostty's existing rendering engine. The goal is a terminal emulator that feels built for Windows and outperforms Windows Terminal in rendering throughput and input latency.

## Core Value

A Windows user launches Ghostty and it feels like a first-class Windows application — native tabs, splits, settings, system integration — while rendering faster than any other terminal on the platform.

## Requirements

### Validated

<!-- Shipped and confirmed valuable — existing Ghostty capabilities. -->

- ✓ VT100/ANSI terminal emulation with Kitty protocol extensions — existing
- ✓ OpenGL GPU-accelerated rendering pipeline — existing
- ✓ Freetype font rasterization — existing
- ✓ HarfBuzz text shaping (ligatures, complex scripts) — existing
- ✓ Configuration file loading with hot-reload — existing
- ✓ Keybinding system with customizable mappings — existing
- ✓ Multi-threaded architecture (IO thread + renderer thread per surface) — existing
- ✓ Shell integration (Bash, Zsh, Fish) — existing
- ✓ Kitty graphics protocol support — existing
- ✓ Theme system (iTerm2 compatible) — existing
- ✓ CLI actions (list-fonts, show-config, etc.) — existing
- ✓ PTY/subprocess management on Windows (ConPTY) — existing
- ✓ Compile-time apprt abstraction (`src/apprt.zig`) — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] Native WinUI 3 / XAML window shell with tabs, splits, and chrome
- [ ] COM-based Zig-to-WinRT bridge (no C++ wrapper layer)
- [ ] DirectWrite font discovery (Freetype continues rasterization)
- [ ] Windows Store distribution with App SDK runtime dependency
- [ ] Full feature parity with macOS Ghostty (tabs, splits, config UI, notifications, system tray)
- [ ] Performance exceeding Windows Terminal in rendering throughput and input latency
- [ ] Native Windows input handling (IME, dead keys, keyboard layouts)
- [ ] Windows-native clipboard integration
- [ ] Native Windows notifications
- [ ] System tray integration
- [ ] Multi-monitor / DPI-aware scaling
- [ ] MSIX packaging for Store and sideload distribution

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Direct3D renderer swap — Keep OpenGL initially; renderer change is a separate future project
- C++/WinRT wrapper layer — Using COM directly from Zig instead
- GTK on Windows — Explicitly replacing this approach with native UI
- Windows Terminal feature cloning — Building Ghostty's feature set, not replicating WT's
- DirectWrite font rasterization — Using DirectWrite for discovery only; Freetype handles rasterization
- Runtime bundling — Targeting Windows Store dependency model instead

## Context

**Background:** Ghostty discussion #2563 tracks the roadmap for Windows support. The current state is a working GLFW + OpenGL + Freetype cross-platform MVP. The remaining major work item is "New apprt implementation for dedicated Windows GUI, native widgets."

**Architecture insight:** The macOS apprt (Swift/AppKit via libghostty C API) provides the pattern to follow — platform-native UI framework wrapping the core Zig engine. On Windows, the equivalent is WinUI 3 / XAML calling into libghostty via COM interfaces rather than C API.

**Performance reference:** Casey Muratori's refterm demonstrates that a simple D3D11 tile renderer achieves 0.5-2+ GB/s throughput. Ghostty's existing OpenGL renderer should be competitive. The XAML shell must not introduce latency in the rendering path — it manages chrome only, not the terminal grid.

**WinUI 3 / Windows App SDK:** Provides native Windows 10/11 controls (TabView, NavigationView, ContentDialog) with modern Fluent Design. The runtime can be declared as a Store dependency, avoiding bundling. COM interop from Zig is feasible since WinRT is COM-based under the hood.

**Existing apprt pattern:** `src/apprt.zig` uses compile-time switching. The new Windows apprt will coexist with GLFW during development for A/B comparison, then become the default Windows backend.

## Constraints

- **Language bridge**: Zig-to-WinRT via COM — must handle ABI boundaries carefully, no C++ dependency
- **Runtime dependency**: Windows App SDK must be available — Store handles this, sideload needs MSIX
- **Platform minimum**: Windows 10 1809+ (Windows App SDK minimum)
- **Rendering**: OpenGL via WGL or ANGLE — must integrate with XAML's composition tree without double-buffering overhead
- **Performance**: Terminal grid rendering must not go through XAML layout — direct GPU rendering to a SwapChainPanel or similar hosting surface

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| WinUI 3 / XAML for window chrome | Provides native Windows controls (tabs, splits, menus) with Fluent Design — same architecture as Windows Terminal | — Pending |
| COM from Zig (no C++ wrapper) | Zig can call COM interfaces directly, avoiding a C++ build dependency and keeping the build system pure Zig | — Pending |
| DirectWrite discovery + Freetype rasterization | Follows the established coretext_freetype pattern on macOS — native discovery, consistent rasterization | — Pending |
| OpenGL renderer initially | Decouples windowing work from renderer work — swap to D3D later if needed for performance | — Pending |
| Coexist with GLFW during development | Enables A/B comparison and fallback during development | — Pending |
| Windows Store distribution model | Store handles App SDK runtime dependency — no bundling needed | — Pending |

---
*Last updated: 2026-02-24 after initialization*
