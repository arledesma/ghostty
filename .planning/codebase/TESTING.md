# Testing Patterns

**Analysis Date:** 2026-02-24

## Test Framework

### Runner

**Framework:** Zig's built-in test runner

**Version:** Uses Zig's standard library test infrastructure (version specified in `build.zig.zon` minimum_zig_version)

**Build Command:**
```bash
zig build test
```

**Advanced Options:**
```bash
zig build test -Dtest-filter=<filter>
```

Filter supports substring matching on test names. Example: `-Dtest-filter=SplitTree` runs only tests containing "SplitTree".

### Assertion Library

**Standard:** `std.testing` from Zig standard library

**Assertion Functions:**
- `try testing.expect(condition)` - basic truthy assertion
- `try testing.expectEqual(expected, actual)` - equality check with type coercion
- `try testing.expectEqualStrings(expected, actual)` - string comparison
- `try testing.expectError(expected_error, expression)` - error expectation

**Example from `src/datastruct/split_tree.zig` line 1389:**
```zig
try testing.expect(!empty.isSplit());
```

**Example from `src/datastruct/split_tree.zig` line 1420:**
```zig
try testing.expectEqualStrings(str, \\empty);
```

**Example from `src/tripwire.zig` line 272:**
```zig
try testing.expectError(error.OutOfMemory, io.check(.read));
```

## Test File Organization

### Location: Inline in Source Files

**Pattern:** Tests are NOT in separate `*_test.zig` files. Instead, they are embedded inline in the same source file using `test "description"` blocks.

**Why:** This keeps tests close to implementation and allows them to access private functions and implementation details for thorough testing.

**Search command to find tests:**
```bash
find /z/github.com/ghostty-org/ghostty/src -name "*.zig" -type f -exec grep -l 'test "' {} \;
```

### Naming Conventions

**Test names use descriptive strings with colons for hierarchy:**
- `test "SplitTree: isSplit"`
- `test "SplitTree: empty tree"`
- `test "SplitTree: split horizontal"`
- `test "grapheme break: emoji modifier"`
- `test "ghostty_string_s empty string"`

**Pattern:** `ModuleName: feature or scenario`

**Examples from codebase:**
- `src/datastruct/split_tree.zig`: 25+ SplitTree tests
- `src/unicode/grapheme.zig`: grapheme break tests
- `src/simd/vt.zig`: VT decode tests
- `src/main_c.zig`: C API tests for ghostty_string_s
- `src/tripwire.zig`: error handling framework tests

## Test Structure

### Suite Organization

**Pattern: Minimal suite structure**

Zig tests don't have nested suites or describe blocks. Each `test "..."` is a top-level declaration equivalent to a test case. Organize related tests by:
1. Grouping in the same file
2. Using hierarchical test names with colons

**Example from `src/datastruct/split_tree.zig` lines 1382-1410:**
```zig
test "SplitTree: isSplit" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Empty tree should not be split
    var empty: TestTree = .empty;
    defer empty.deinit();
    try testing.expect(!empty.isSplit());

    // Single node tree should not be split
    var v1: TestView = .{ .label = "A" };
    var single: TestTree = try TestTree.init(alloc, &v1);
    defer single.deinit();
    try testing.expect(!single.isSplit());

    // Split tree should be split
    var v2: TestView = .{ .label = "B" };
    var tree2: TestTree = try TestTree.init(alloc, &v2);
    defer tree2.deinit();
    var split = try single.split(alloc, .root, .right, 0.5, &tree2);
    defer split.deinit();
    try testing.expect(split.isSplit());
}
```

### Setup and Teardown

**Setup Pattern:**
```zig
const testing = std.testing;
const alloc = testing.allocator;  // Get test allocator
```

**Teardown Pattern: Using `defer`**

All resources are cleaned up with `defer` statements. Example:
```zig
var v: TestView = .{ .label = "A" };
var t: TestTree = try .init(alloc, &v);
defer t.deinit();  // Deferred cleanup
```

This ensures cleanup happens even if test fails midway.

**No Explicit Setup/Teardown Functions:** Zig tests don't have `setUp()` / `tearDown()` callbacks; instead use `defer` for resource management.

### Assertions and Testing Patterns

**Pattern: Multiple assertions per test**

Tests often check multiple conditions. Example from `src/datastruct/split_tree.zig` line 1412-1423:
```zig
test "SplitTree: empty tree" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t: TestTree = .empty;
    defer t.deinit();

    const str = try std.fmt.allocPrint(alloc, "{f}", .{t});
    defer alloc.free(str);
    try testing.expectEqualStrings(str,
        \\empty
    );
}
```

**Pattern: Scoped comments for readability**

Large tests use inline comments to describe sections:
```zig
// Empty tree should not be split
var empty: TestTree = .empty;
defer empty.deinit();
try testing.expect(!empty.isSplit());

// Single node tree should not be split
var v1: TestView = .{ .label = "A" };
// ...
```

## Mocking

### Framework

**Tool:** Custom error/mock injection via `tripwire` pattern

Ghostty doesn't use traditional mocking libraries. Instead, it uses a **tripwire pattern** for error injection during testing.

**Located:** `src/tripwire.zig`

**Purpose:** Inject errors at specific call counts to test error handling paths

**Example from `src/tripwire.zig` lines 262-276:**
```zig
test "errorAfter" {
    const io = module(enum { read, write }, anyerror);
    // Trip after 2 calls (on the 3rd call)
    io.errorAfter(.read, error.OutOfMemory, 2);

    // First two calls succeed
    try io.check(.read);
    try io.check(.read);

    // Third call and on trips
    try testing.expectError(error.OutOfMemory, io.check(.read));
    try testing.expectError(error.OutOfMemory, io.check(.read));

    try io.end(.reset);
}
```

### Patterns: What to Mock vs. What Not to Mock

**DO Mock (via tripwire):**
- Memory allocation failures: `error.OutOfMemory`
- I/O failures: simulated read/write errors
- Specific error conditions for error path validation

**DO NOT Mock:**
- Core data structures (build real ones)
- Terminal state logic (test with real state machines)
- Font/rendering subsystems (use real font loading when possible)

**Reasoning:** Ghostty's focus is on terminal correctness. Unit tests verify data structure invariants with real structures; integration tests (separate) verify rendering.

## Fixtures and Factories

### Test Data Patterns

**Test Helper Structs:**
- Small inline structs for test configuration
- Example from `src/datastruct/split_tree.zig` line 1392:
  ```zig
  var v1: TestView = .{ .label = "A" };
  ```

**Test Builders:**
Zig tests often use initialization syntax directly:
```zig
var t: TestTree = try TestTree.init(alloc, &v1);
```

No separate factory functions; Zig's `try` and error unions handle test setup naturally.

### Test Allocator

**Location:** `std.testing.allocator`

**Usage:**
```zig
const alloc = testing.allocator;
```

**Behavior:** Test allocator tracks all allocations and fails the test if any are leaked. This is built into Zig's testing infrastructure.

**Example from `src/datastruct/split_tree.zig` line 1384:**
```zig
const testing = std.testing;
const alloc = testing.allocator;
```

## Coverage

### Requirements

**No enforced coverage target** documented. Coverage is not a CI gate but monitoring tool.

**View Coverage:**

Not configured in standard Zig test runner. Ghostty likely uses external tools if coverage is measured.

## Test Types

### Unit Tests

**Scope:** Individual functions and data structures

**Approach:**
- Test pure functions and logic in isolation
- Example: `SplitTree` tests verify tree operations (split, remove, navigate)
- Example: Unicode grapheme tests verify break detection logic

**Example from `src/unicode/grapheme.zig` line 126:**
```zig
test "grapheme break: emoji modifier" {
    // ... setup ...
    // Test that emoji modifier is correctly identified as single grapheme
}
```

### Integration Tests

**Scope:** Multiple components working together

**Approach:**
- Font system integration: test font loading with configuration
- Terminal I/O: test how input events flow through keyboard → terminal
- Not as heavily tested as unit tests in Zig source

**Example:** `src/main_c.zig` has C API integration tests verifying Zig/C interop

**Noted in HACKING.md:**
Tests for specific behaviors like Input Method Editors (IME) are **manual integration tests** requiring live environment setup, not automated tests.

### E2E Tests

**Framework:** Custom acceptance test suite (not Zig-based)

**Location:** `/test/` directory

**Type:** Screenshot-based visual regression testing

**Details from `test/README.md`:**
- Runs terminal emulator in windowing environment
- Captures screenshots
- Compares output against baseline (visual regression)
- Can test alternative terminal emulators (xterm, etc.) for comparison

**Commands:**
```bash
./run-host.sh --exec ghostty --case /src/cases/vttest/launch.sh  # Single test
./run-all.sh                                                      # Full suite
./run-host.sh --update                                            # Update baseline
```

**Requires:** Docker, ghostty binary in test directory

## Async Testing

**Not applicable** - Ghostty is primarily synchronous. Event handling is single-threaded with message passing via mailboxes.

**Exception:** Renderer runs in separate thread (`src/Surface.zig` line 87):
```zig
renderer_thr: std.Thread,
```

But thread synchronization is tested via functional tests, not async/await patterns.

## Error Testing

### Pattern: `expectError`

**Basic error assertion:**
```zig
try testing.expectError(error.OutOfMemory, io.check(.read));
```

**With tripwire for controlled errors:**
```zig
const io = module(enum { read }, anyerror);
io.errorAfter(.read, error.OutOfMemory, 2);

// First two calls succeed
try io.check(.read);
try io.check(.read);

// Third and subsequent calls error
try testing.expectError(error.OutOfMemory, io.check(.read));
```

**Compound error sets:**
Test functions that return various error types:
```zig
pub const CreateError = Allocator.Error || font.SharedGridSet.InitError;

test "create fails on allocation" {
    // Would need to mock allocator to fail, then:
    try testing.expectError(error.OutOfMemory, App.create(mock_alloc));
}
```

### Error Path Validation

**Using `errdefer`:**
Verify cleanup happens on error:
```zig
var app = try alloc.create(App);
errdefer alloc.destroy(app);  // Cleanup on error
try app.init(alloc);           // If init fails, errdefer runs
```

Tests verify that partial initialization doesn't leak resources.

## Running Tests

### Test Execution

**Run all tests:**
```bash
cd /z/github.com/ghostty-org/ghostty
zig build test
```

**Run filtered tests:**
```bash
zig build test -Dtest-filter=SplitTree
```

**Run under Valgrind (Linux):**
```bash
zig build test-valgrind
```

**Run libghostty-vt tests (library variant):**
```bash
zig build test-lib-vt
```

### CI Integration

**Automated:** GitHub Actions (referenced in `.github/` but not detailed in explored files)

**Manual validation:** Input stack testing documented in `HACKING.md` requires manual verification for:
- Linux IME (ibus, fcitx, none)
- Dead key input
- CJK input
- Preedit state handling

## Test-Related Build Configuration

**Build file:** `build.zig`

**Test filter option:**
```zig
const test_filters = b.option(
    [][]const u8,
    "test-filter",
    "Filter for test. Only applies to Zig tests.",
) orelse &[0][]const u8{};
```

**Test steps defined:**
- `test` - Run all Zig unit tests
- `test-lib-vt` - Run libghostty-vt tests
- `test-valgrind` - Run tests under Valgrind for memory leak detection
- `run-valgrind` - Run app under Valgrind for development memory checking

---

*Testing analysis: 2026-02-24*
