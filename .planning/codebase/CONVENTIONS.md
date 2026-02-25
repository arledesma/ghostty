# Coding Conventions

**Analysis Date:** 2026-02-24

## Overview

Ghostty is primarily written in **Zig**, with platform-specific code in **Swift** (macOS), **C** (wrappers), and shell scripts. Each language has distinct conventions enforced through linters and formatters.

## Naming Patterns

### Files

**Zig Files:**
- **PascalCase for struct/struct-like modules:** `App.zig`, `Surface.zig`, `Terminal.zig` - typically represent primary types defined in that file
- **snake_case for utility/function modules:** `terminal/main.zig`, `renderer.zig`, `config.zig`
- **Subdirectory organization:** Functional groupings use lowercase directories: `apprt/`, `terminal/`, `renderer/`, `font/`, `unicode/`
- **Test files:** Embedded inline with source using `test "..."` blocks in the same file, no separate test files
- **Build files:** `build.zig`, `build.zig.zon` for dependency management

**Swift Files:**
- **PascalCase:** `DockTilePlugin.swift`, `Animation.swift`
- Located in `macos/` directory

**Shell Scripts:**
- **lowercase with hyphens:** `run-host.sh`, `run-all.sh`

### Functions

**Pattern:** `snake_case` across all Zig code

Examples from `src/`:
- `pub fn create(alloc: Allocator) CreateError!*App` - constructors use `create`
- `pub fn deinit(self: *App) void` - destructors use `deinit`
- `pub fn tick(self: *App, rt_app: *apprt.App) !void`
- `pub fn updateConfig(...) !void`
- `pub fn focusedSurface(self: *const App) ?*Surface`
- `fn writeTriggerKey(writer: *std.Io.Writer, trigger: input.Binding.Trigger) error{WriteFailed}!bool`

**Conventions:**
- Methods taking `self` as first parameter
- Error-returning functions use `!ReturnType` syntax
- Getter functions omit `get` prefix: `focusedSurface()` not `getFocusedSurface()`

### Variables

**Pattern:** `snake_case` throughout

Examples:
- `alloc: Allocator` - allocators
- `focused_surface: ?*Surface` - pointers to optional types
- `font_grid_set: font.SharedGridSet` - complex types
- `renderer_thread: rendererpkg.Thread` - component references
- `config_conditional_state: configpkg.ConditionalState` - state fields
- `last_notification_time: ?std.time.Instant`

**Pointer naming:**
- Prefix `rt_` for runtime/apprt pointers: `rt_app`, `rt_surface`
- Plain `*T` for ownership-holding pointers

### Types

**Struct Definition Pattern:**
- Use `const TypeName = @This();` at the top of `.zig` files where the struct is primary
- Example from `Surface.zig` line 12: `const Surface = @This();`
- Example from `App.zig` line 4: `const App = @This();`

**Enum and Union Patterns:**
- `PascalCase` for enum names: `Key`, `Target`, `Action`
- Discriminated unions often have `Key` enum variants: `pub const Action = union(Key) { ... }`
- Nested types use PascalCase: `pub const CreateError`, `pub const Mouse`

**Error Types:**
- `pub const CreateError = Allocator.Error || font.SharedGridSet.InitError;`
- Composed from standard library error sets and custom error sets

### Constants and Comptime

**Pattern:** `SCREAMING_SNAKE_CASE` or `snake_case` depending on context

Examples:
- `min_window_width_cells: u32 = 10` - configuration constants use snake_case
- Error sets and compile-time values follow error/type naming
- Build-time config: `appVersion`, `minimumZigVersion` - camelCase in build config

## Code Style

### Formatting

**Zig Code:**
- **Tool:** Zig's built-in formatter (no external formatter configured)
- **Indentation:** 2 spaces (see `.clang-format` IndentWidth: 2)
- **Line length:** 80 columns maximum (see `.clang-format` ColumnLimit: 80)
- **Braces:** Allman style avoided, K&R style used (opening brace on same line)
- **Spaces:** Around operators, controlled by Zig formatter

**Resource Files (Docs, YAML, JSON):**
- **Tool:** Prettier with default configuration
- **Run command:** `prettier --write .`
- **Nix users:** `nix develop -c prettier --write .`
- Ignored paths: vendor/, **/*.html, zig-cache/, zig-out/, macos/, *.frag

**C/C++ Code:**
- **Tool:** `clang-format` using Chromium-based style
- **Config file:** `.clang-format`
- **Key settings:** 2-space indentation, 80-column limit, K&R brace style

**Swift Code:**
- **Tool:** SwiftLint
- **Config file:** `.swiftlint.yml` + `macos/.swiftlint.yml`
- **Run command:** `swiftlint lint --fix`
- **Nix users:** `nix develop -c swiftlint lint --fix`

**Shell Scripts:**
- **Tool:** ShellCheck
- **Run command:** `shellcheck --check-sourced --severity=warning $(find . ...)`
- **Nix config:** `nix/devShell.nix` specifies version

**Nix Files:**
- **Tool:** Alejandra
- **Run command:** `alejandra .`
- **Nix users:** `nix develop -c alejandra .`

### Linting

**Zig:**
- No explicit linter configuration found; relies on compiler warnings and Zig formatter

**Bash/Shell:**
- ShellCheck is CI-enforced
- Settings: `--check-sourced --severity=warning`
- Config file: `.shellcheckrc`

**Swift:**
- SwiftLint is CI-enforced
- Config hierarchy: root `.swiftlint.yml` (includes macos) → `macos/.swiftlint.yml`
- Check violations without fixing: `swiftlint lint --strict`

## Import Organization

### Zig Imports

**Pattern:**
1. Standard library imports (`std.X`)
2. Internal module imports (project-relative with `@import("path.zig")`)
3. Platform/runtime-specific imports

**Example from `App.zig`:**
```zig
const std = @import("std");
const builtin = @import("builtin");
const assert = @import("quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const apprt = @import("apprt.zig");
const Surface = @import("Surface.zig");
const input = @import("input.zig");
const configpkg = @import("config.zig");
const Config = configpkg.Config;
const BlockingQueue = @import("datastruct/main.zig").BlockingQueue;
const renderer = @import("renderer.zig");
const font = @import("font/main.zig");

const log = std.log.scoped(.app);
```

**Aliasing Pattern:**
- Full module import and alias for re-exports: `const Config = configpkg.Config;`
- Scoped logger per module: `const log = std.log.scoped(.module_name);`
- Extract frequently-used types: `const Allocator = std.mem.Allocator;`

### No Path Aliases

Ghostty does not use TypeScript-style path aliases or Zig's built-in path resolution beyond relative imports. All imports are relative: `@import("../path/to/file.zig")` or `@import("sibling.zig")`.

## Error Handling

### Pattern: Error Sets and Try-Catch

**Explicit Error Sets:**
- Functions define return types with error sets: `CreateError!*App`, `!void`
- Error sets are composed from library errors and custom errors:
  ```zig
  pub const CreateError = Allocator.Error || font.SharedGridSet.InitError;
  ```

**Try Operator:**
- `try` propagates errors up the call stack
- Example from `apprt/action.zig`:
  ```zig
  var app = try alloc.create(App);
  errdefer alloc.destroy(app);
  try app.init(alloc);
  ```

**Errdefer:**
- Cleanup deferred on error: `errdefer alloc.destroy(app);`
- Ensures resources are freed if initialization fails partway through
- Pattern: allocate/create with `try`, immediately follow with `errdefer`

**Error Handling in Callbacks:**
- Errors in callbacks are logged (not propagated to caller)
- Example from `embedded.zig` line 315:
  ```zig
  else => log.err("error updating app config err={}", .{err})
  ```

**Catch with Special Cases:**
- `catch unreachable` for compile-time guaranteed success
- Example from `build/zig.zig` line 8:
  ```zig
  const required_vsn = std.SemanticVersion.parse(required_zig) catch unreachable;
  ```
- `catch @panic("OOM")` for out-of-memory at build time (acceptable failure)

## Logging

### Framework

**Tool:** `std.log` (Zig standard library)

**Pattern: Scoped Loggers**
- Each module declares a scoped logger at module level:
  ```zig
  const log = std.log.scoped(.module_name);
  ```
- Examples:
  - `App.zig` line 19: `const log = std.log.scoped(.app);`
  - `Surface.zig` line 40: `const log = std.log.scoped(.surface);`
  - `embedded.zig` line 24: `const log = std.log.scoped(.embedded_window);`

### When to Log

**Debug Level:** `log.debug(...)`
- Detailed diagnostic information
- Example: `log.debug("focus event focused={}", .{focused});`
- Only output in debug builds

**Info Level:** `log.info(...)`
- General informational messages
- Example: `log.info("quit message received, short circuiting mailbox drain", .{});`
- Output in debug; controllable in release via `GHOSTTY_LOG` env var

**Error Level:** `log.err(...)`
- Error conditions that don't cause panic
- Example: `log.err("error updating app config err={}", .{err});`
- Always output (unless disabled via `GHOSTTY_LOG`)

### Configuration

**Build-time control:**
- Debug builds automatically output debug logs to `stderr`
- Release builds suppress debug logs by default

**Runtime control:**
- Environment variable: `GHOSTTY_LOG`
- Values: `stderr`, `macos`, or comma-separated combination
- Prefix with `no-` to disable: `GHOSTTY_LOG=no-stderr,macos`
- Special: `GHOSTTY_LOG=true` (all destinations), `false` (no destinations)

**Platform-specific:**
- **macOS:** Logging to unified log via `macos` destination (set by default)
- **Linux:** Logging to `systemd` journald via `journalctl --user --unit app-com.mitchellh.ghostty.service`

## Comments

### When to Comment

**Module-level Documentation:** `//!` at the top of `.zig` files

Example from `Surface.zig` lines 1-11:
```zig
//! Surface represents a single terminal "surface". A terminal surface is
//! a minimal "widget" where the terminal is drawn and responds to events
//! such as keyboard and mouse. Each surface also creates and owns its pty
//! session.
//!
//! The word "surface" is used because it is left to the higher level
//! application runtime to determine if the surface is a window, a tab,
//! a split, a preview pane in a larger window, etc. This struct doesn't care:
//! it just draws and responds to events. The events come from the application
//! runtime so the runtime can determine when and how those are delivered
//! (i.e. with focus, without focus, and so on).
```

**Struct Field Comments:** `///` above struct members

Example from `App.zig` lines 29-41:
```zig
/// This is true if the app that Ghostty is in is focused. This may
/// mean that no surfaces (terminals) are focused but the app is still
/// focused, i.e. may an about window. On macOS, this concept is known
/// as the "active" app while focused windows are known as the
/// "main" window.
///
/// This is used to determine if keyboard shortcuts that are non-global
/// should be processed. If the app is not focused, then we don't want
/// to process keyboard shortcuts that are not global.
///
/// This defaults to true since we assume that the app is focused when
/// Ghostty is initialized but a well behaved apprt should call
/// focusEvent to set this to the correct value right away.
focused: bool = true,
```

**Inline Comments:** `//` for implementation details needing explanation

Example from `apprt/action.zig` lines 58-72:
```zig
pub const Action = union(Key) {
    // A GUIDE TO ADDING NEW ACTIONS:
    //
    // 1. Add the action to the `Key` enum. The order of the enum matters
    //    because it maps directly to the libghostty C enum. For ABI
    //    compatibility, new actions should be added to the end of the enum.
    // ...
```

**Sync Comments:** `// Sync with: <location>` to mark C API correspondences

Example from `apprt/action.zig` line 18:
```zig
// Sync with: ghostty_target_tag_e
pub const Key = enum(c_int) {
```

### JSDoc/TSDoc

**Not used in Zig.** Use `///` for public type/function documentation. For Zig, this is the standard approach; there's no formal "doc comment" standard like JSDoc, but `///` is recognized by documentation generators.

Example from code:
```zig
/// Create a new app instance. This returns a stable pointer to the app
/// instance which is required for callbacks.
pub fn create(alloc: Allocator) CreateError!*App {
    ...
}
```

## Function Design

### Size

**No explicit guidelines documented**, but code review patterns suggest:
- Keep functions focused on a single responsibility
- Methods typically 10-50 lines
- Complex operations split into private helper functions

**Example:** `writeTriggerKey` (25 lines) in `apprt/gtk/key.zig` is a private helper for translating key bindings.

### Parameters

**Pattern:**
- `self` or `self: *T` as first parameter for methods
- Const receiver for read-only operations: `self: *const App`
- Mutable receiver for modifications: `self: *Surface`
- Allocators typically early: `pub fn create(alloc: Allocator)`
- Configuration/options at the end: `opts: Options`

Example from `App.zig`:
```zig
pub fn tick(self: *App, rt_app: *apprt.App) !void
pub fn focusedSurface(self: *const App) ?*Surface
pub fn newWindow(self: *App, rt_app: *apprt.App, msg: Message.NewWindow) !void
```

### Return Values

**Patterns:**
- Error-returning functions: `!ReturnType` or `SomeError!ReturnType`
- Optional pointers for "may not exist": `?*Surface`
- Plain types for guaranteed values
- Error set composition: `pub const CreateError = Allocator.Error || OtherError;`

Example returns:
```zig
pub fn create(alloc: Allocator) CreateError!*App  // error union with pointer
pub fn focusedSurface(self: *const App) ?*Surface  // optional pointer
pub fn needsConfirmQuit(self: *const App) bool     // plain boolean
```

## Module Design

### Exports

**Public APIs:**
- Use `pub` for functions/types intended as part of public API
- Named types: `pub const CreateError = ...;`
- Functions: `pub fn functionName(...) !void`
- Structs/unions: `pub const TypeName = union(Key) { ... }`

**Private Implementation:**
- Omit `pub` for internal helpers
- Example: `fn writeTriggerKey(...)` is private in `key.zig`

### Barrel Files

**Pattern: `main.zig` for module re-exports**

Directories like `font/`, `terminal/`, `renderer/` use `main.zig` to aggregate and re-export:
```zig
// src/font/main.zig
pub const SharedGridSet = @import("shared_grid_set.zig").SharedGridSet;
pub const Metrics = @import("metrics.zig").Metrics;
// ... other re-exports
```

**Usage:**
```zig
const font = @import("font/main.zig");
// Access as font.SharedGridSet, font.Metrics, etc.
```

**Benefits:**
- Centralizes public API
- Allows internal reorganization without breaking imports
- Single entry point for modules

## C API Interop

**Cross-language binding pattern:**
- Native Zig types defined in one module
- C-compatible extern types in parallel: `pub const C = extern struct { ... }`
- Conversion functions: `pub fn cval(self: Target) C { ... }`
- Sync comments mark C/Zig correspondence

Example from `apprt/action.zig` lines 14-45:
```zig
pub const Target = union(Key) {
    app,
    surface: *CoreSurface,

    // Sync with: ghostty_target_tag_e
    pub const Key = enum(c_int) { app, surface };

    // Sync with: ghostty_target_u
    pub const CValue = extern union { app: void, surface: *apprt.Surface };

    // Sync with: ghostty_target_s
    pub const C = extern struct { key: Key, value: CValue };

    pub fn cval(self: Target) C {
        return .{ .key = @as(Key, self), .value = switch (self) {...} };
    }
};
```

---

*Convention analysis: 2026-02-24*
