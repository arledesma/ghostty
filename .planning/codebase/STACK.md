# Technology Stack

**Analysis Date:** 2026-02-24

## Languages

**Primary:**
- Zig 0.15.2+ - Core terminal emulator, event handling, rendering pipeline, and cross-platform abstraction layer
- Swift - macOS and iOS app frontend, UI framework integration
- Objective-C - macOS/iOS bridging and native API integration
- C - Low-level utilities, font rendering, text shaping, and GPU drivers

**Secondary:**
- GLSL - Vertex and fragment shaders for OpenGL rendering
- Blueprint (GTK UI) - Linux GTK4 UI markup
- Nu Shell - Build automation and release scripts

## Runtime

**Environment:**
- Zig Build System (0.15.2+) - Primary build orchestrator
- Xcode 26+ - macOS/iOS application builds
- GTK 4.x - Linux runtime platform
- Metal API - macOS GPU rendering
- OpenGL 4.x+ - Linux/cross-platform GPU rendering
- WebGL 2.0 - Browser/WASM rendering

**Package Manager:**
- Zig package manager (build.zig.zon) - Manages Zig dependencies
- System package managers - For platform-specific C libraries (pkg-config on Linux, Xcode on macOS)

## Frameworks

**Core Terminal:**
- libghostty - Core terminal emulation library (Zig), exposed via C and Zig APIs
- libghostty-vt - Virtual terminal library for Zig consumers, supports WebAssembly

**Platform Runtimes:**
- GTK 4.x - Linux GUI framework
- AppKit/UIKit - macOS/iOS native frameworks
- libxev - Cross-platform event multiplexing (async I/O)

**Text & Font:**
- FreeType - Font rasterization engine (Linux/fallback on macOS)
- CoreText - macOS native font discovery and rendering
- HarfBuzz - Text shaping and layout
- Fontconfig - Font discovery on Linux
- Oniguruma - Regular expression engine for text processing
- UTF-CPP, SIMDUTF - UTF-8/Unicode handling with SIMD acceleration

**Graphics:**
- OpenGL (via GLAD loader) - Cross-platform GPU rendering
- Metal - macOS GPU rendering
- ImGui (dcimgui) - Debug inspector UI
- z2d - 2D graphics/drawing abstractions

**Media & Format Handling:**
- libpng - PNG image decoding
- Wuffs - Image format library
- Highway - SIMD library for performance-critical code
- glslang - GLSL shader compilation
- SPIRV-Cross - Shader translation between formats

**Terminal Features:**
- Wayland Protocols - Wayland display server support
- Plasma Wayland Protocols - KDE Plasma extensions
- GTK4 Layer Shell - Compositing support for GTK4

**Internationalization:**
- gettext (libintl) - Message translation framework

## Key Dependencies

**Critical:**
- libxev - Event loop and async I/O; essential for responsive terminal
- FreeType/CoreText - Font rendering; core to text display pipeline
- OpenGL/Metal - GPU rendering; critical path for performance
- GTK 4.x (Linux) - Application framework on Linux
- Sentry SDK - Crash reporting and diagnostics collection

**Infrastructure:**
- libpng - Image support (icons, graphics)
- Oniguruma - Regex support for terminal sequences and configuration
- HarfBuzz - Complex text shaping (ligatures, RTL text)
- Fontconfig - Font discovery optimization on Linux
- SIMDUTF - High-speed UTF-8 validation and conversion
- Wayland - Display server protocol for modern Linux

## Build Artifacts

**Executable:**
- `ghostty` - Linux GTK4 terminal emulator application
- `Ghostty.app` - macOS application bundle (built with Xcode)
- `libghostty.so` / `libghostty.a` - Shared/static library on Linux
- `GhosttyKit.xcframework` - Reusable framework for macOS/iOS

**Resources:**
- Terminfo database - Terminal capability database
- Shell integration scripts - Bash/Zsh/Fish shell extensions
- Themes - Default color schemes (iTerm2 format compatible)
- Embedded fonts - JetBrains Mono, Nerd Fonts Symbols Only

**WASM:**
- `libghostty-vt.js` - WebAssembly terminal library for browser use

## Configuration

**Build Options:**
- `zig build` - Default debug build
- `zig build -Doptimize=ReleaseFast` - Production build with optimizations
- `-Dtarget=<triple>` - Cross-compilation target
- `-Dapp-runtime=gtk` - Select application runtime (gtk, none)
- `-Drenderer=opengl|metal|webgl` - Select GPU backend
- `-Dfont-backend=freetype|fontconfig_freetype|coretext|coretext_freetype|coretext_harfbuzz|web_canvas` - Font engine
- `-Dgtk-x11=true` - Enable X11 support on Linux
- `-Dgtk-wayland=true` - Enable Wayland support on Linux
- `-Dsentry=true|false` - Enable/disable Sentry crash reporting
- `-Dflatpak=true` - Flatpak-specific integrations
- `-Dsnap=true` - Snap package integrations

**Environment Variables:**
- `GHOSTTY_RESOURCES_DIR` - Override built-in resources (fonts, themes, shell integration)
- `XDG_CACHE_HOME` / macOS cache directories - Sentry crash report storage

**Compression & Packaging:**
- zlib - Compression for distribution archives
- tar/gzip - Source distribution format

## Platform Support

**Developed & Tested:**
- Linux (x86_64, aarch64) with X11 and Wayland
- macOS (x86_64, aarch64/Apple Silicon)
- iOS (aarch64)
- WebAssembly (wasm32 browser target)

**Experimental/Planned:**
- Windows (not yet supported)
- Android (infrastructure present, not maintained)

## Development & Testing

**Build Validation:**
- Valgrind - Memory leak detection and profiling
- LLVM/clang - C/C++ compilation for graphics libraries
- Zig test framework - Built-in unit testing
- GitHub Actions - CI/CD pipeline
- Namespace Labs infrastructure - Custom GitHub Actions runners (namespace-profile-ghostty-*)

**Code Quality:**
- clang-format - C code formatting (`.clang-format` configuration)
- swiftlint - Swift linting (`.swiftlint.yml` configuration)
- shellcheck - Shell script validation
- prettier - Code formatting configuration (`.prettierignore` file)

**Documentation:**
- Doxygen - API documentation generation
- Man pages - Command-line documentation
- Markdown - User-facing documentation

---

*Stack analysis: 2026-02-24*
