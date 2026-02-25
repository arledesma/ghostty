# Architecture

**Analysis Date:** 2026-02-24

## Pattern Overview

**Overall:** Layered Multi-Threaded Terminal Emulator with Pluggable Rendering and Platform Runtimes

**Key Characteristics:**
- Compile-time polymorphism for renderer backends (Metal, OpenGL, WebGL) and application runtimes (GTK, macOS Cocoa, Browser)
- Multi-threaded architecture with dedicated renderer and IO threads per terminal surface
- Message-passing between layers via mailboxes and queues
- Platform-agnostic core (Zig) with platform-specific bindings (Swift for macOS, GTK for Linux)
- VT100/ANSI escape sequence parser with Kitty protocol extensions
- Shared font resources across surfaces using grid cache pooling

## Layers

**Application Layer (Platform-Specific):**
- Purpose: Platform UI framework and event handling
- Location: `src/apprt/gtk/` (Linux/GTK), `macos/Sources/` (Swift/macOS), `src/apprt/browser.zig` (Web)
- Contains: Platform window management, event dispatch, clipboard integration, OS-specific features
- Depends on: Core App and Surface types from Zig
- Used by: Users via GUI

**Core Application Layer:**
- Purpose: App state management, surface lifecycle, configuration, CLI actions
- Location: `src/App.zig`, `src/main_ghostty.zig`, `src/cli/`, `src/config/`
- Contains: App instance management, surface collection, focus handling, config loading and hot-reload
- Depends on: Terminal, Renderer, Font, Input, Termio layers
- Used by: All runtime implementations and CLI handlers

**Terminal/Emulation Layer:**
- Purpose: VT100/ANSI parsing, screen state management, cursor positioning, selection, hyperlinks
- Location: `src/terminal/` (core), `src/terminal/Parser.zig`, `src/terminal/Screen.zig`, `src/terminal/Terminal.zig`
- Contains: Parser for escape sequences, screen buffer management, color handling, pagination
- Depends on: Unicode utilities, Configuration
- Used by: Renderer, Surface for display updates

**Rendering Layer:**
- Purpose: Convert screen state to GPU/canvas output
- Location: `src/renderer/` with pluggable backends
- Contains: Generic renderer framework, Metal backend, OpenGL backend, WebGL backend, cell rendering, overlays, shader effects
- Depends on: Font, Terminal screen state, Platform graphics context
- Used by: Surface display thread, runs in dedicated thread

**Font Layer:**
- Purpose: Font discovery, loading, glyph rasterization, shaping, atlas management
- Location: `src/font/` with pluggable backends (FreeType, CoreText, Web Canvas)
- Contains: Font face management, glyph caching, text shaping, emoji handling
- Depends on: OS font APIs, OpenType parsing
- Used by: Renderer for glyph lookup and atlas generation

**Input/Event Layer:**
- Purpose: Keyboard and mouse input translation to terminal protocol
- Location: `src/input.zig`, `src/apprt/gtk/key.zig` (platform-specific key mapping)
- Contains: Key event parsing, mouse protocol encoding (SGR, X10), keyboard modifiers
- Depends on: Configuration (keybindings), Input state machines
- Used by: Surface for sending events to terminal

**Terminal IO Layer:**
- Purpose: PTY/subprocess management, read/write coordination between threads
- Location: `src/termio/`, `src/termio/Termio.zig`, `src/termio/backend.zig`
- Contains: PTY allocation/management, subprocess spawning, mailbox event dispatch, multi-threaded read/write coordination
- Depends on: OS APIs (posix), Message passing infrastructure
- Used by: Surface for terminal I/O with configurable backend

**Configuration Layer:**
- Purpose: Load, parse, and manage configuration files and state
- Location: `src/config/`, `src/config/Config.zig`, `src/config/file_load.zig`
- Contains: Config file parsing, keybinding definitions, theme data, conditional state (light/dark)
- Depends on: File I/O, String utilities
- Used by: App, Surface, Input for behavior customization

## Data Flow

**Startup Flow:**

1. `main_ghostty.zig`: main() initializes global state and CLI
2. If no action, calls `App.create()` to allocate app instance
3. App creates app runtime (`apprt.App`)
4. Runtime creates initial window/surface and calls `App.addSurface()`
5. Runtime enters event loop calling `App.tick()` on each iteration
6. Renderer and IO threads spawned by Surface detached from main thread

**Terminal Output Flow:**

1. PTY subprocess writes bytes to pty
2. IO thread reads via `termio.Termio` mailbox
3. IO thread sends `read_available` message to Surface mailbox
4. Surface processes message in `Surface.handleMessage()`:
   - Reads available bytes
   - Passes to `Terminal.Parser` for escape sequence parsing
   - Parser updates `Terminal.Screen` state
   - Renderer thread notified via mailbox
5. Renderer thread (running `Renderer.init()` loop):
   - Locks screen state
   - Iterates cells to render
   - Queries font glyph caches
   - Submits GPU commands
   - Displays frame

**Keyboard Input Flow:**

1. Platform runtime receives keyboard event
2. Translates to canonical key representation (`input.KeyEvent`)
3. Calls `Surface.handleKeyboardInput()`
4. Surface checks active key tables and keybindings via `Command.resolve()`
5. If command matches, executes via `Command.run()` (may modify state)
6. If no match, sends key as bytes to PTY via `termio.Termio.write()`
7. Subprocess receives input

**Configuration Update Flow:**

1. Config file changed on disk
2. CLI action or file watcher detects change
3. New config loaded via `Config.load()`
4. `App.updateConfig()` called with new config
5. For each surface: `Surface.handleMessage(.change_config)`
6. Surface re-derives font, updates state, notifies renderer
7. Renderer re-renders with new settings

**State Management:**
- Per-app state: Surface list, focused surface, font grid cache, config conditional state in `App.zig`
- Per-surface state: Terminal, renderer, IO handler, size, config in `Surface.zig`
- Per-terminal state: Screen buffer, parser state, cursor, selection in `Terminal.zig` and `Screen.zig`
- Thread-safe: Mailboxes for inter-thread communication, arena allocators for frame-local allocs

## Key Abstractions

**Surface:**
- Purpose: Single terminal UI element (window, tab, split, pane - framework decides)
- Files: `src/Surface.zig`, `src/apprt/surface.zig`
- Pattern: Central state machine with mailbox for message receipt and async event dispatch
- Owns: Terminal instance, renderer, IO handler, font metrics, configuration

**Terminal:**
- Purpose: Stateful VT100/ANSI parser and screen state machine
- Files: `src/terminal/Terminal.zig`, `src/terminal/Screen.zig`, `src/terminal/Parser.zig`
- Pattern: Immutable escape sequence parsing to mutable screen state updates
- State: Cursor position, screen buffer (PageList), selection, color modes, parser state

**Renderer:**
- Purpose: Abstraction over different graphics backends
- Files: `src/renderer/generic.zig` (generic impl), `src/renderer/Metal.zig`, `src/renderer/OpenGL.zig`
- Pattern: Pluggable backend via compile-time selection, frame-based rendering in dedicated thread
- Responsibility: Cell iteration, glyph atlas lookup, GPU resource management

**Termio (Terminal I/O):**
- Purpose: PTY/subprocess lifecycle and byte I/O coordination
- Files: `src/termio/Termio.zig`, `src/termio/backend.zig`
- Pattern: Mailbox-driven async I/O with optional threading
- Backend: Abstract interface for PTY creation and read/write operations

**AppRuntime:**
- Purpose: Platform-specific event loop and window lifecycle
- Files: `src/apprt/gtk.zig` (GTK impl), `macos/Sources/App/` (Swift impl)
- Pattern: Compile-time selection, implements App and Surface interfaces
- Responsibility: Event dispatch, surface creation/destruction, platform feature integration

**Config:**
- Purpose: Complete application configuration with hot-reload support
- Files: `src/config/Config.zig`, `src/config/file_load.zig`
- Pattern: Immutable config objects, conditional state for theme/OS settings
- Updates: App broadcasts config changes to all surfaces via messages

## Entry Points

**Executable Entry:**
- Location: `src/main_ghostty.zig:main()`
- Triggers: User launches `ghostty` binary or app
- Responsibilities: Initialize global state, parse CLI, create App, run event loop, cleanup

**CLI Action Entry:**
- Location: `src/cli/action.zig`, various action implementations in `src/cli/` subdirs
- Triggers: User runs `ghostty +action_name`
- Responsibilities: Execute non-GUI action (list fonts, show version, inspect config) and exit

**C API Entry:**
- Location: `src/main_c.zig` (wrapper), `include/ghostty/` (headers)
- Triggers: Third-party code links libghostty
- Responsibilities: Bridge between C callers and Zig core (used by macOS Cocoa layer)

**Library Mode Entry:**
- Location: `src/lib_vt.zig` (exported C API for VT parser)
- Triggers: Third-party code uses libghostty-vt for VT parsing
- Responsibilities: Standalone VT100 parser without GUI runtime

**Platform-Specific Entry (GTK):**
- Location: `src/apprt/gtk.zig:init()` and GTK signal callbacks
- Triggers: GTK window manager signals (key press, mouse motion, window close)
- Responsibilities: Translate GTK events to Surface messages

**Platform-Specific Entry (macOS/Swift):**
- Location: `macos/Sources/App/macOS/main.swift` and Swift event handlers
- Triggers: Cocoa event loop and app delegate callbacks
- Responsibilities: Bridge Swift runtime to Zig App via libghostty C API

## Error Handling

**Strategy:** Cascade errors to topmost handler, log at point of occurrence, continue gracefully where possible

**Patterns:**
- Allocator errors: Propagate as `error.OutOfMemory`, caught at app initialization
- Parser errors: Log, reset parser state, continue parsing next sequence
- Render errors: Log health status, fall back to previous frame, attempt recovery
- Config errors: Log diagnostics, keep previous valid config, notify user
- IO errors: Log, notify surface, may close PTY and surface
- Font errors: Fall back to fallback fonts or sprite font, continue rendering
- PTY creation: If spawn fails, surface shows error and waits for user action

## Cross-Cutting Concerns

**Logging:**
- Approach: Zig `std.log` with scoped loggers per module, platform-specific backends
- macOS: Unified logging via `macos.os.Log`, viewable with `log stream` command
- Linux/Other: stderr output, respects debug build mode
- Implementation: `src/main_ghostty.zig:logFn()` routes logs to platform backends

**Validation:**
- Approach: Early validation at boundaries (config parsing, PTY creation, command dispatch)
- Parser: Defensive coding against malformed escape sequences
- Config: Range checking on numeric values, path validation for file references
- Input: Key code validation, mouse coordinate bounds checking

**Authentication/Authorization:**
- Not applicable - local terminal emulator, no remote auth
- Platform capabilities: Request OS permissions (clipboard access, recording) via platform runtime

**Concurrency Control:**
- Mailboxes: `src/datastruct/` BlockingQueue for thread-safe async message dispatch
- Per-surface: IO thread and renderer thread, main thread for input/config
- No mutex locks on terminal state: Only renderer thread reads Screen, main thread modifies
- Arena allocators: Frame-local allocations freed after each iteration

## Module Dependencies

Core dependency structure:
```
main_ghostty.zig → App → Surface → Terminal + Renderer + Termio + Font + Input + Config
                          ↓          ↓           ↓          ↓        ↓
                        apprt      parser     backend    freetype  keybinds
                          ↓        screen     PTY ops     coretext  commands
                     gtk/cocoa    color
```

---

*Architecture analysis: 2026-02-24*
