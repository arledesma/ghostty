# Roadmap: Ghostty Native Windows Apprt

## Overview

This roadmap delivers a native WinUI 3 Windows application runtime for Ghostty in four phases. Phase 1 derisks the two highest-risk unknowns (COM from Zig and ANGLE rendering inside SwapChainPanel). Phase 2 delivers a working single-terminal window with full input, clipboard, DPI, and config support. Phase 3 adds tabs, splits, and the remaining terminal features (search, scrollbar, URLs, bell). Phase 4 adds platform integration: MSIX packaging, Quick Terminal, notifications, and command palette.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation & Rendering Bridge** - COM bridge, ANGLE+SwapChainPanel proof-of-concept, DirectWrite font discovery, apprt scaffold (completed 2026-02-25)
- [x] **Phase 2: Single Terminal Surface** - Working terminal in native WinUI 3 window with input, clipboard, DPI, fullscreen, config (completed 2026-02-25)
- [x] **Phase 3: Tabs, Splits & Terminal Features** - Multi-tab, split-pane interface with search, scrollbar, URL handling, bell (completed 2026-02-25)
- [ ] **Phase 4: Platform Integration & Distribution** - MSIX packaging, Quick Terminal, notifications, command palette

## Phase Details

### Phase 1: Foundation & Rendering Bridge
**Goal**: Validate that Ghostty's OpenGL renderer can draw into a WinUI 3 SwapChainPanel via ANGLE, driven from Zig through COM -- the two riskiest unknowns in the project
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. A WinUI 3 window opens from Zig code using COM-based WinRT activation with no C++ dependency
  2. Ghostty's OpenGL renderer draws a visible frame into a SwapChainPanel via ANGLE (GLES 3.1 path validated)
  3. DirectWrite font discovery returns system fonts that Freetype can rasterize
  4. The new apprt backend compiles alongside GLFW without conflicts via compile-time apprt selection
**Plans**: 3 plans

Plans:
- [ ] 01-01-PLAN.md — COM/WinRT bridge helpers, WinUI 3 vtable definitions, and apprt backend scaffold
- [ ] 01-02-PLAN.md — ANGLE EGL integration, SwapChainPanel rendering, and GLES 3.1 shader porting
- [x] 01-03-PLAN.md — DirectWrite font discovery backend with Freetype rasterization

### Phase 2: Single Terminal Surface
**Goal**: A user can launch Ghostty on Windows and use it as a fully functional single-tab terminal with native look and feel
**Depends on**: Phase 1
**Requirements**: WIN-01, WIN-02, WIN-03, WIN-04, INP-01, INP-02, TERM-05, TERM-06
**Success Criteria** (what must be TRUE):
  1. User sees a native Windows window with standard chrome (titlebar, min/max/close, resize handles, Snap Layouts) hosting a working terminal
  2. User can type commands, see output, and interact with shell programs using all existing Ghostty keybindings
  3. User can copy/paste text with Ctrl+Shift+C/V and OSC 52 clipboard protocol works
  4. Terminal content renders correctly when dragged between monitors with different DPI settings (100%-250%)
  5. User can toggle fullscreen, and config changes in ghostty.conf apply without restart including light/dark theme following system setting
**Plans**: 2 plans

Plans:
- [ ] 02-01-PLAN.md — Window chrome, core Surface wiring, and Win32 input translation
- [ ] 02-02-PLAN.md — Clipboard, DPI scaling, fullscreen, config hot-reload, and theme following

### Phase 3: Tabs, Splits & Terminal Features
**Goal**: Users can work with multiple terminals in tabs and splits with full search, scrollback, URL handling, and bell support
**Depends on**: Phase 2
**Requirements**: TAB-01, TAB-02, TAB-03, TAB-04, TAB-05, TAB-06, TERM-01, TERM-02, TERM-03, TERM-04
**Success Criteria** (what must be TRUE):
  1. User can open, close, reorder, and color-code tabs, with tabs rendered in the titlebar to save vertical space
  2. User can split the terminal horizontally and vertically and navigate between splits with keyboard shortcuts
  3. User can search scrollback with Ctrl+Shift+F and navigate results in an overlay
  4. User can scroll through terminal history using a visible scrollbar and Ctrl+click URLs to open them in the browser
  5. Terminal bell triggers an audible or visual notification
**Plans**: 5 plans

Plans:
- [x] 03-00-PLAN.md — Phase 2 UAT gap closure (keyboard input, clipboard, config reload)
- [x] 03-01-PLAN.md — Tab infrastructure, multi-surface lifecycle, and custom tab bar in titlebar
- [x] 03-02-PLAN.md — Split panes with binary tree layout and directional navigation
- [x] 03-03-PLAN.md — Search overlay, scrollbar, URL click handling, and bell notification
- [ ] 03-04-PLAN.md — Gap closure: scrollbar GDI painting in child HWND (TERM-02)

### Phase 4: Platform Integration & Distribution
**Goal**: Ghostty is distributable through the Windows Store and offers platform-level integration features that differentiate it from other terminals
**Depends on**: Phase 3
**Requirements**: PLAT-01, PLAT-02, PLAT-03, PLAT-04
**Success Criteria** (what must be TRUE):
  1. User can install Ghostty from the Windows Store or sideload via MSIX with App SDK runtime resolved automatically
  2. User can summon a dropdown terminal from any context using a global hotkey
  3. User receives a Windows toast notification when a long-running command completes
  4. User can open a searchable command palette with Ctrl+Shift+P to discover and execute actions
**Plans**: 3 plans

Plans:
- [ ] 04-01-PLAN.md — MSIX packaging pipeline (AppxManifest.xml, assets, build script)
- [ ] 04-02-PLAN.md — Quick Terminal dropdown with global hotkey and slide animation
- [ ] 04-03-PLAN.md — Toast notifications for command completion and searchable command palette

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Rendering Bridge | 1/3 | Complete    | 2026-02-25 |
| 2. Single Terminal Surface | 0/2 | Complete    | 2026-02-25 |
| 3. Tabs, Splits & Terminal Features | 5/5 | Complete   | 2026-02-25 |
| 4. Platform Integration & Distribution | 0/3 | Not started | - |
