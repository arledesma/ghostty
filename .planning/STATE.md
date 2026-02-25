# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-24)

**Core value:** A Windows user launches Ghostty and it feels like a first-class Windows application while rendering faster than any other terminal on the platform.
**Current focus:** Phase 2: Single Surface Terminal

## Current Position

Phase: 1 of 4 (Foundation & Rendering Bridge)
Plan: 3 of 3 in current phase
Status: Phase 1 complete
Last activity: 2026-02-24 -- Completed 01-02-PLAN.md

Progress: [███░░░░░░░] 30%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 9min
- Total execution time: 0.4 hours

**By Phase:**

| Phase | Plans | Total  | Avg/Plan |
|-------|-------|--------|----------|
| 1     | 3     | 27min  | 9min     |

**Recent Trend:**

- Last 5 plans: 01-01 (7min), 01-03 (7min), 01-02 (13min)
- Trend: stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 4-phase structure derived from dependency analysis -- COM/ANGLE derisking first, then single surface, then multi-surface, then platform integration
- [Roadmap]: INFRA requirements grouped into Phase 1 as foundation; all other phases build on validated infrastructure
- [01-01]: Used api-ms-win-core-winrt extern linking for WinRT activation APIs instead of zigwin32
- [01-01]: ISwapChainPanelNative inherits from IUnknown (3 base), all other WinUI interfaces from IInspectable (6 base)
- [01-01]: Windows apprt GObject switches use void (same as none) since Windows has no GObject dependency
- [01-02]: EGL functions declared as extern libEGL with Zig signatures instead of @cImport (no EGL headers needed)
- [01-02]: GLSL version header removed from shader files, prepended at comptime in Zig based on apprt.runtime
- [01-02]: Used #ifdef GL_ES preprocessor guards for GLES differences within same shader files (single source of truth)
- [01-02]: precision highp float/int for GLES (not mediump) to avoid precision issues in color math
- [01-03]: Manual COM vtable definitions for DirectWrite instead of zigwin32 (not in project deps)
- [01-03]: DirectWrite discovery in separate file (discovery/directwrite.zig) following face/ directory pattern
- [01-03]: hasCodepoint returns true for DW deferred faces -- charset metadata not carried, checked at load time

### Pending Todos

None yet.

### Blockers/Concerns

- GLES 3.1 shader compatibility structurally validated (code compiles, guards in place) but runtime ANGLE compilation deferred due to Zig 0.15.2 build runner bug
- COM vtable alignment from Zig has no existing WinUI 3 reference -- must be validated early in Phase 1

## Session Continuity

Last session: 2026-02-24
Stopped at: Completed 01-02-PLAN.md
Resume file: None
