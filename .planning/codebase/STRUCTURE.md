# Codebase Structure

**Analysis Date:** 2026-02-24

## Directory Layout

```
ghostty/
├── src/                          # Core Zig source code (cross-platform)
│   ├── main.zig                 # Entry point selector
│   ├── main_ghostty.zig         # GUI app entry point
│   ├── App.zig                  # Main app state and lifecycle
│   ├── Surface.zig              # Single terminal surface (window/tab)
│   ├── apprt.zig                # Application runtime abstraction
│   ├── apprt/                   # Platform-specific runtimes
│   │   ├── gtk/                # Linux/GTK implementation
│   │   ├── none.zig            # Library-only mode
│   │   ├── browser.zig         # Browser/WASM implementation
│   │   ├── embedded.zig        # Embedded library implementation
│   │   └── structs.zig         # Shared types across runtimes
│   ├── terminal/               # VT100/ANSI terminal emulation
│   │   ├── Terminal.zig        # Main terminal state machine
│   │   ├── Screen.zig          # Screen buffer and cell management
│   │   ├── Parser.zig          # Escape sequence parser
│   │   ├── PageList.zig        # Scrollback buffer pages
│   │   ├── color.zig           # Color handling and palettes
│   │   ├── kitty/              # Kitty protocol extensions
│   │   ├── osc/                # Operating System Command handlers
│   │   ├── tmux/               # Tmux control sequence support
│   │   └── Selection.zig       # Text selection state
│   ├── renderer/               # Graphics rendering layer
│   │   ├── generic.zig         # Backend-agnostic renderer
│   │   ├── Metal.zig           # Metal backend (macOS)
│   │   ├── OpenGL.zig          # OpenGL backend (Linux)
│   │   ├── WebGL.zig           # WebGL backend (browser)
│   │   ├── Thread.zig          # Renderer thread manager
│   │   ├── State.zig           # Renderer state
│   │   ├── cell.zig            # Cell rendering logic
│   │   ├── image.zig           # Image protocol support
│   │   ├── shaders/            # GLSL/Metal shader files
│   │   └── Overlay.zig         # UI overlays (search, inspector)
│   ├── font/                   # Font loading and rendering
│   │   ├── main.zig            # Font module exports
│   │   ├── Collection.zig      # Font family collection
│   │   ├── face/               # Font face implementations
│   │   │   ├── freetype.zig   # FreeType backend (Linux)
│   │   │   ├── coretext.zig   # CoreText backend (macOS)
│   │   │   └── web_canvas.zig # Canvas backend (browser)
│   │   ├── Atlas.zig           # Glyph atlas texture management
│   │   ├── SharedGrid.zig      # Shared font cache across surfaces
│   │   ├── Glyph.zig           # Glyph representation
│   │   ├── opentype.zig        # OpenType parsing
│   │   └── shaper.zig          # Text shaping (HarfBuzz)
│   ├── termio/                 # Terminal I/O and PTY
│   │   ├── Termio.zig          # Main termio state
│   │   ├── Thread.zig          # Multi-threaded I/O coordinator
│   │   ├── backend.zig         # PTY backend abstraction
│   │   ├── mailbox.zig         # Async message queue
│   │   └── Exec.zig            # Subprocess execution
│   ├── config/                 # Configuration system
│   │   ├── Config.zig          # Complete config structure
│   │   ├── file_load.zig       # Config file parsing
│   │   ├── conditional.zig     # Conditional state (light/dark)
│   │   ├── io.zig              # Config I/O operations
│   │   ├── command.zig         # Command definitions
│   │   └── edit.zig            # Config editing operations
│   ├── input/                  # Keyboard and mouse input
│   │   ├── input.zig           # Input event types
│   │   └── event processing    # Event translation and dispatch
│   ├── cli/                    # Command-line interface
│   │   ├── action.zig          # CLI action definitions
│   │   ├── args.zig            # Argument parsing
│   │   └── [action_name]/      # Individual action implementations
│   ├── lib/                    # Library utilities
│   │   ├── allocator/          # Custom allocator implementations
│   │   └── [other utilities]   # Shared library code
│   ├── os/                     # Operating system abstractions
│   │   ├── wasm/               # WASM-specific OS code
│   │   └── [OS utilities]      # OS-specific helpers
│   ├── datastructs/            # Core data structures
│   │   ├── main.zig            # Data structures exports
│   │   ├── circ_buf.zig        # Circular buffer
│   │   └── BlockingQueue       # Thread-safe queue
│   ├── unicode/                # Unicode utilities
│   ├── math.zig                # Mathematical utilities
│   ├── global.zig              # Global state (process-level)
│   ├── build/                  # Build-time code generation
│   │   ├── main.zig            # Build system entry
│   │   ├── Config.zig          # Build configuration
│   │   ├── mdgen/              # Man page generator
│   │   ├── webgen/             # Web documentation generator
│   │   └── framegen/           # Frame data generator
│   └── [other modules]         # Various utility modules
├── macos/                      # macOS-specific code (Swift)
│   ├── Sources/
│   │   ├── App/                # Main app implementation
│   │   │   ├── macOS/          # macOS-specific (Cocoa)
│   │   │   └── iOS/            # iOS app (if applicable)
│   │   ├── Features/           # Feature implementations
│   │   │   ├── About/
│   │   │   ├── App Intents/    # Siri shortcuts
│   │   │   ├── Command Palette/
│   │   │   ├── Settings/
│   │   │   └── Terminal/
│   │   └── [Other features]
│   ├── Tests/                  # Swift unit tests
│   ├── Ghostty.xcodeproj/      # Xcode project
│   └── Assets.xcassets/        # Image assets
├── include/                    # Public C/API headers
│   └── ghostty/
│       ├── vt/                 # VT parser C API
│       └── [other APIs]
├── dist/                       # Distribution artifacts
│   ├── linux/                  # Linux packaging
│   ├── macos/                  # macOS app resources
│   ├── windows/                # Windows resources
│   └── doxygen/                # Doxygen config
├── test/                       # Integration/system tests
│   ├── cases/                  # Test case files
│   └── run.sh                  # Test runner
├── example/                    # Example programs using libghostty
│   ├── c-vt/                   # C VT parser example
│   ├── zig-vt/                 # Zig VT parser example
│   └── [other examples]
├── po/                         # Translation/localization files
├── nix/                        # Nix package definitions
├── flatpak/                    # Flatpak manifest
├── snap/                       # Snap package definition
├── pkg/                        # Package build configs
├── images/                     # Icon and image assets
├── build.zig                   # Main build file
├── build.zig.zon               # Build dependencies manifest
├── Makefile                    # Convenience build targets
└── [config files]              # Various config files
```

## Directory Purposes

**`src/`:**
- Purpose: All cross-platform Zig source code
- Contains: Core emulator logic, terminal, renderer, font, I/O, config
- Key files: Main entry points (`main.zig`, `main_ghostty.zig`, `App.zig`, `Surface.zig`)

**`src/apprt/`:**
- Purpose: Application runtime abstraction layer
- Contains: Platform-specific window/event handling implementations
- Key files: `gtk/` for Linux, abstract interfaces in `runtime.zig`

**`src/terminal/`:**
- Purpose: VT100/ANSI terminal emulation engine
- Contains: Parser, screen buffer, cursor, selection, color modes, extended protocols
- Key files: `Terminal.zig` (state machine), `Screen.zig` (display buffer), `Parser.zig` (sequence parsing)

**`src/renderer/`:**
- Purpose: Graphics rendering abstraction and implementations
- Contains: Backend-agnostic generic renderer, pluggable Metal/OpenGL/WebGL backends
- Key files: `generic.zig` (main logic), `Metal.zig`, `OpenGL.zig` (platform backends)

**`src/font/`:**
- Purpose: Font discovery, loading, and glyph management
- Contains: Font face wrappers, glyph atlases, text shaping
- Key files: `Collection.zig` (font family management), `Atlas.zig` (glyph caching)

**`src/termio/`:**
- Purpose: PTY/subprocess I/O management
- Contains: PTY allocation, subprocess spawning, read/write coordination
- Key files: `Termio.zig` (main state), `Thread.zig` (threading coordinator)

**`src/config/`:**
- Purpose: Configuration file loading and runtime management
- Contains: Config file parsing, keybinding resolution, conditional state
- Key files: `Config.zig` (complete config), `file_load.zig` (parser)

**`src/cli/`:**
- Purpose: Command-line interface actions
- Contains: Individual action implementations (version, list fonts, inspect config, etc.)
- Key files: `action.zig` (action dispatcher)

**`macos/`:**
- Purpose: macOS-specific Swift implementation
- Contains: Cocoa window management, native UI features, App Intents, menu system
- Key files: `Sources/App/macOS/main.swift`, `AppDelegate.swift`

**`test/`:**
- Purpose: Integration and system tests
- Contains: Test cases for VT100 compliance, terminal features, platform-specific behavior
- Key files: `run.sh` (test runner), `cases/` (test definitions)

**`example/`:**
- Purpose: Example programs demonstrating libghostty usage
- Contains: C and Zig examples for using the VT parser as a library
- Key files: Individual example directories with `src/` subdirectories

## Key File Locations

**Entry Points:**
- `src/main.zig`: Selector for different executable types (GUI, CLI, helpers)
- `src/main_ghostty.zig`: GUI app entry point, initializes App, runs event loop
- `macos/Sources/App/macOS/main.swift`: macOS app entry point (Cocoa)

**Configuration:**
- `src/config/Config.zig`: Complete configuration structure with ~100+ fields
- `src/config/file_load.zig`: Config file parsing and resolution
- `~/.config/ghostty/config`: User config file location (standard XDG)

**Core Logic:**
- `src/App.zig`: Main application state, surface lifecycle, mailbox drainage
- `src/Surface.zig`: Single terminal surface, owns renderer/terminal/IO
- `src/terminal/Terminal.zig`: Terminal state machine, escape sequence routing
- `src/terminal/Screen.zig`: Display buffer (cells), cursor, selection
- `src/terminal/Parser.zig`: VT100/ANSI escape sequence parser

**Rendering:**
- `src/renderer/generic.zig`: Backend-agnostic rendering logic (~1400+ lines)
- `src/renderer/Metal.zig`: Metal GPU backend (macOS)
- `src/renderer/OpenGL.zig`: OpenGL backend (Linux/cross-platform)
- `src/renderer/Thread.zig`: Renderer thread coordination

**Font:**
- `src/font/Collection.zig`: Font family discovery and selection
- `src/font/face.zig`: Platform-specific font loading
- `src/font/Atlas.zig`: Glyph texture atlas management

**Testing:**
- `test/run.sh`: Main test execution script
- `test/cases/`: Test case files (VT100 sequences, expected outputs)

## Naming Conventions

**Files:**
- PascalCase: Primary type/concept files (`App.zig`, `Surface.zig`, `Terminal.zig`, `Parser.zig`)
- snake_case: Utility and implementation files (`file_load.zig`, `stream_handler.zig`, `post_fork.zig`)
- Directory: lowercase with hyphens for multi-word names (`src/shell-integration/`, `src/App Intents/`)

**Directories:**
- lowercase: Most directories
- PascalCase inside feature folders: `macos/Sources/Features/About/`, `macos/Sources/Features/App Intents/`

**Zig Modules:**
- PascalCase struct/type names: `Terminal`, `Screen`, `Parser`, `Renderer`
- UPPER_CASE for constants and error set names
- camelCase for functions and variables
- `_` prefix for private implementation details within modules

## Where to Add New Code

**New Terminal Feature (e.g., new escape sequence):**
- Primary implementation: `src/terminal/Terminal.zig` or `src/terminal/Screen.zig` (state update)
- Parser routing: `src/terminal/Parser.zig` (add new sequence handler)
- Tests: Add test block within same file or in existing test section
- Config: `src/config/Config.zig` if user-configurable

**New Renderer Effect (e.g., blur, shadow):**
- Generic logic: `src/renderer/generic.zig` (call backend)
- Backend implementation: `src/renderer/Metal.zig`, `src/renderer/OpenGL.zig`
- Shader code: `src/renderer/shaders/` (new `.glsl` or `.metal` files)
- State management: `src/renderer/State.zig` if storing per-frame data

**New Configuration Option:**
- Definition: `src/config/Config.zig` (add field to struct)
- Parsing: `src/config/file_load.zig` (add parser for key)
- Validation: Inline in config struct or separate validation function
- Usage: Access as `config.field_name` throughout codebase

**New CLI Action:**
- Definition: `src/cli/action.zig` (add to Action enum and match statement)
- Implementation: New file in `src/cli/actions/` subdirectory (e.g., `src/cli/actions/my_action.zig`)
- Invocation: `ghostty +my_action [flags]`

**New Component/Widget (macOS):**
- Location: `macos/Sources/Features/[ComponentName]/`
- Files: `[Component]View.swift`, `[Component]ViewModel.swift`, `[Component]Controller.swift`
- Integration: Add to main app coordinator/window controller

**Utilities and Helpers:**
- Shared helpers: `src/lib/` directory or module-specific `utils.zig`
- Data structures: `src/datastruct/`
- OS-specific: `src/os/` with platform subdirectories

## Special Directories

**`src/build/`:**
- Purpose: Build-time code generation
- Generated: No, committed to repo
- Committed: Yes
- Contents: Zig code that generates man pages, web docs, help strings at compile-time

**`zig-cache/` and `.build/`:**
- Purpose: Build artifacts and cache (git-ignored)
- Generated: Yes
- Committed: No
- Created: Automatically by `zig build`

**`src/terminal/res/`, `src/font/res/`:**
- Purpose: Embedded resources (terminfo files, sprite font data)
- Generated: Some (terminfo compiled to C)
- Committed: Yes

**`include/ghostty/`:**
- Purpose: Public C API headers for libghostty
- Generated: No, manually maintained
- Committed: Yes
- Consumed: External C programs linking libghostty

**`vendor/`:**
- Purpose: Vendored third-party dependencies
- Generated: No, committed to repo
- Committed: Yes
- Contents: External libraries included directly (some C libraries)

---

*Structure analysis: 2026-02-24*
