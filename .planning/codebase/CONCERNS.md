# Codebase Concerns

**Analysis Date:** 2026-02-24

## Tech Debt

**Semantic Prompt Clearing Logic:**
- Issue: Disabled code path in screen clear implementation. When at a prompt and receiving FF (0x0C), the code should mark the current row as non-prompt before clearing, but this is commented out with a TODO.
- Files: `src/termio/Termio.zig` (line 628)
- Impact: Semantic prompt state may not be correctly maintained during screen clears, affecting shell integration and prompt detection features.
- Fix approach: Re-enable and test the disabled prompt marking logic, ensure it properly integrates with terminal state management.

**Grapheme Break Edge Cases:**
- Issue: Multiple `orelse unreachable` calls in grapheme breaking implementation suggest assumptions about codepoint sequences that may fail on malformed input.
- Files: `src/unicode/grapheme.zig` (lines 146, 147, 152, 157, 162, 167, 172, 177)
- Impact: Invalid UTF-8 or malformed character sequences could cause runtime crashes instead of graceful error handling.
- Fix approach: Replace `unreachable` with proper error handling or input validation; add fuzzing tests for edge cases.

**Incomplete Command Execution with File Descriptors:**
- Issue: FD-based subprocess execution is not fully implemented; code contains a TODO indicating missing support.
- Files: `src/Command.zig` (line 280)
- Impact: File descriptor-based process spawning (alternative to PTY) is not functional, limiting flexibility in subprocess handling.
- Fix approach: Complete FD-based execution implementation or document why it's not supported.

**Windows Subprocess Path Setup Incomplete:**
- Issue: Windows-specific code for working directory changes in subprocesses is marked as incomplete.
- Files: `src/termio/Exec.zig` (line 327)
- Impact: Working directory changes may not work reliably on Windows during subprocess execution.
- Fix approach: Implement complete Windows path setup or add platform-specific workarounds and tests.

**Media Keys Not Implemented:**
- Issue: Media key handling on GTK is stubbed with TODO comment.
- Files: `src/apprt/gtk/key.zig` (line 534)
- Impact: Media keys (play, pause, volume) are not recognized on Linux/GTK platforms.
- Fix approach: Research GTK media key APIs and implement media key support.

## Platform-Specific Concerns

**GTK Window Decoration Workarounds:**
- Issue: Multiple FIXME comments indicate dependencies on GTK merge requests that haven't landed; current implementation uses temporary workarounds for window decorations.
- Files: `src/apprt/gtk/winproto/wayland.zig` (lines 30, 46), `src/build/SharedDeps.zig` (line 630)
- Impact: Window decoration handling on Wayland may break when GTK version changes; future GTK updates could require code changes.
- Fix approach: Monitor upstream GTK merge requests; plan for migration when `zxdg_decoration_v1` support lands in GTK.

**X11 Rounded Corners Rendering:**
- Issue: Rounded corners are not factored into window decoration calculations on X11 Adwaita themes.
- Files: `src/apprt/gtk/winproto/x11.zig` (line 253)
- Impact: Visual rendering discrepancies when using rounded corner themes on X11; window borders may overlap incorrectly.
- Fix approach: Investigate theme metrics API; potentially use libxcb for more precise rendering.

**X11 vs libxcb Decision:**
- Issue: Code uses Xlib but contains FIXME suggesting migration to libxcb might be needed.
- Files: `src/apprt/gtk/winproto/x11.zig` (line 372)
- Impact: Xlib has thread-safety considerations that could affect stability; potential performance issues.
- Fix approach: Benchmark Xlib vs libxcb for performance; plan migration if stability issues emerge.

**macOS Focus Workaround:**
- Issue: 500ms timer-based focus workaround for GTK on macOS instead of proper OS event integration.
- Files: `src/apprt/gtk/class/window.zig` (lines 354, 1523)
- Impact: Focus handling on macOS may have 500ms latency; race conditions possible if focus changes rapidly.
- Fix approach: Investigate GTK macOS focus event handling; potentially add runtime version checks to eliminate workaround on newer GTK.

**Nix Build Issues:**
- Issue: Multiple Nix build workarounds for issues in upstream Nix that haven't been fixed.
- Files: `.github/workflows/release-tip.yml` (lines 244, 500, 697), `.github/workflows/test.yml` (multiple lines)
- Impact: CI/CD pipeline has external dependency on Nix fixes; potential for long-term maintenance burden.
- Fix approach: Track upstream Nix issues; migrate away from workarounds as upstream fixes are released.

## Known Fragile Areas

**Large Complex Modules:**
- Issue: Several core modules exceed 10,000 lines of code, making them difficult to modify safely.
- Files:
  - `src/terminal/PageList.zig` (14,466 lines)
  - `src/terminal/Terminal.zig` (12,765 lines)
  - `src/config/Config.zig` (10,687 lines)
  - `src/terminal/Screen.zig` (10,352 lines)
- Impact: High risk of unintended side effects when modifying these modules; difficult to test all code paths; long compile times.
- Safe modification: Add comprehensive tests before any changes; consider extracting internal abstractions to reduce module size; use modular approach with clear internal interfaces.
- Test coverage: These modules have tests but complexity suggests more edge case coverage needed.

**Terminal Stream Handler:**
- Issue: Stream parsing and execution have complex state machines with multiple unreachable branches that could hide bugs.
- Files: `src/termio/stream_handler.zig` (line 447 contains TODO with no context)
- Impact: Malformed escape sequences could cause crashes or undefined behavior.
- Fix approach: Add fuzzing tests; replace `unreachable` with proper error handling; document state machine invariants.

**Unicode Property Tables:**
- Issue: Precomputed grapheme break lookup table is large (8KB) and computed at compile time; any changes to underlying tables could silently produce incorrect results.
- Files: `src/unicode/grapheme.zig` (lines 24-80)
- Impact: Silent incorrectness in grapheme cluster detection could affect text rendering and selection in complex scripts.
- Safe modification: Add comprehensive Unicode test suite covering all scripts; validate table generation with multiple Unicode versions.

**Command Palette Surface Tracking:**
- Issue: Command palette does not track which surface invoked it; multiple TODOs indicate incomplete state management.
- Files: `src/apprt/gtk/class/command_palette.zig` (line 585), `src/apprt/gtk/class/surface.zig` (line 824), `src/apprt/gtk/class/window.zig` (lines 354, 1916, 1971, 1988)
- Impact: Command palette actions may apply to wrong surface; state inconsistency in multi-window scenarios.
- Safe modification: Add surface ID tracking throughout command palette lifecycle; add tests for multi-surface operations.

## Potential Error Handling Issues

**Unsafe orelse unreachable Patterns:**
- Issue: Multiple locations use `orelse unreachable` for optional unwrapping without null-safety guarantees.
- Files:
  - `src/unicode/grapheme.zig` (multiple lines: 146, 147, 152, 157, 162, 167, 172, 177)
  - `src/cli/list_themes.zig` (line 1644)
  - `src/Surface.zig` (lines 6386, 6389, 6401, 6404, 6455, 6458)
  - `src/terminal/PageList.zig` (line 3836)
  - `src/termio/Exec.zig` (lines 646, 1019)
- Impact: If assumptions are violated, crashes occur instead of graceful degradation. Difficult to debug in production.
- Fix approach: Use Result types or error returns instead; validate preconditions explicitly; add safety guards in debug builds.

**Command Execution Error Handling:**
- Issue: Comments indicate error handling is incomplete or requires careful handling of race conditions in working directory setup.
- Files: `src/Command.zig` (line 211-213): "if due to race conditions it doesn't exist...we ignore it"
- Impact: Silent failures in subprocess initialization; working directory may not be set correctly; difficult to debug.
- Fix approach: Log ignored errors at least in debug mode; consider retrying with exponential backoff; validate working directory after subprocess start.

## Integration & Feature Gaps

**Crash Report Infrastructure:**
- Issue: Crash report viewing and sending is marked as unimplemented.
- Files: `src/cli/crash_report.zig` (lines 24-25)
- Impact: Users can only list crash reports; cannot view details or submit them for debugging.
- Fix approach: Implement crash report viewing with structured data extraction; implement secure submission to crash analysis service.

**Unicode List Sorting:**
- Issue: Theme list sorting does not use Unicode-aware string comparison.
- Files: `src/cli/list_themes.zig` (line 49)
- Impact: Themes with non-ASCII characters may be sorted incorrectly; different sort order across different locales.
- Fix approach: Use Unicode collation algorithm (ICU or equivalent) for proper locale-aware sorting.

**Incomplete Clipboard Configuration:**
- Issue: Clipboard codepoint mapping configuration cannot currently be set; marked with TODO.
- Files: `src/config/Config.zig` (line 1418)
- Impact: Users cannot customize clipboard behavior for special characters; workaround requires code modification.
- Fix approach: Implement configuration file parsing and CLI flag for clipboard codepoinot remapping.

**Application URI Opening:**
- Issue: XDG desktop portal integration for URI opening is not implemented.
- Files: `src/apprt/gtk/class/application.zig` (line 2208)
- Impact: Links opened through OSC 8 hyperlinks may not work correctly on sandboxed environments (Flatpak).
- Fix approach: Implement XDG portal integration following freedesktop.org specifications.

## Performance Concerns

**Font Atlas Preallocation:**
- Issue: Optimal preallocation size for font glyph atlas is unknown; currently using hardcoded value that may be non-optimal.
- Files: `src/font/Atlas.zig` (line 92)
- Impact: Either wasting memory (large prealloc) or frequent allocations (small prealloc); poor caching efficiency.
- Fix approach: Profile real-world usage; implement adaptive preallocation based on usage patterns.

**Graphics Codec Implementation Detail:**
- Issue: SIMD UTF validation in graphics protocol parsing notes that scalar instructions might be faster in some cases.
- Files: `src/pkg/simdutf/vendor/simdutf.cpp` (line 14842)
- Impact: Graphics protocol parsing may not be optimally performant on all CPU architectures.
- Fix approach: Implement architecture-specific code paths; add benchmark suite for different architectures.

## Security Considerations

**Error Scripting Injection:**
- Issue: Crash reports and error logs may contain user input that could be misinterpreted as code if displayed without proper escaping.
- Files: `src/cli/crash_report.zig`, `src/crash` module
- Risk: XSS-like issues if crash reports are displayed in web UI; potential injection attacks in error messages.
- Current mitigation: Basic logging infrastructure in place.
- Recommendations: Sanitize all output when generating crash reports; use safe formatting functions; audit error message generation for injection points.

**PTY/Process Handling:**
- Issue: Race conditions possible in working directory setup; commented code suggests awareness of timing issues.
- Files: `src/Command.zig` (lines 211-213), `src/termio/Exec.zig`
- Risk: Privilege escalation if working directory changes don't apply correctly; information disclosure via wrong directory context.
- Current mitigation: Code attempts to handle race conditions by ignoring failures.
- Recommendations: Add security audit for PTY operations; implement secure process spawning patterns; document threat model for subprocess execution.

## Test Coverage Gaps

**Grapheme Breaking Edge Cases:**
- What's not tested: Malformed UTF-8, incomplete sequences, control character boundaries, complex scripts at cluster boundaries
- Files: `src/unicode/grapheme.zig`
- Risk: Silent crashes on real-world text with special characters; rendering artifacts for non-Latin scripts.
- Priority: High

**Terminal Emulation Escape Sequence Handling:**
- What's not tested: Malformed sequences, truncated sequences mid-stream, very long sequences, sequences with embedded nulls
- Files: `src/terminal/stream_handler.zig`, `src/termio/stream_handler.zig`
- Risk: Crashes or incorrect terminal state from malformed input; denial of service via resource exhaustion.
- Priority: High

**Multi-Window/Multi-Surface Commands:**
- What's not tested: Command palette action application to multiple surfaces, focus transfer between surfaces with pending operations
- Files: `src/apprt/gtk/class` modules (window.zig, surface.zig, command_palette.zig)
- Risk: Commands apply to wrong surface; state corruption in multi-surface scenarios.
- Priority: Medium

**Platform-Specific Rendering:**
- What's not tested: GTK version compatibility for decoration handling, Wayland protocol compliance, X11 window manager interactions
- Files: `src/apprt/gtk/winproto/` modules
- Risk: Rendering broken on some window managers or Wayland implementations; visual glitches or crashes.
- Priority: Medium

---

*Concerns audit: 2026-02-24*
