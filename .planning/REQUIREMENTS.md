# Requirements: Ghostty Native Windows Apprt

**Defined:** 2026-02-24
**Core Value:** A Windows user launches Ghostty and it feels like a first-class Windows application while rendering faster than any other terminal on the platform.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Windowing Foundation

- [x] **WIN-01**: User sees a native WinUI 3 window hosting Ghostty's OpenGL renderer via ANGLE + SwapChainPanel
- [x] **WIN-02**: Window has native chrome (titlebar, min/max/close, resize handles, Win11 Snap Layouts)
- [x] **WIN-03**: Terminal content scales correctly across monitors with different DPI settings
- [x] **WIN-04**: User can toggle fullscreen with F11 or configured keybind

### Tabs & Splits

- [ ] **TAB-01**: User can open multiple tabs in a single window with new tab button and Ctrl+T
- [ ] **TAB-02**: User can reorder tabs by dragging and close tabs with middle-click or Ctrl+W
- [ ] **TAB-03**: User can split the terminal horizontally and vertically with keyboard shortcuts
- [ ] **TAB-04**: User can navigate between splits with keyboard shortcuts
- [ ] **TAB-05**: Tabs render in the title bar, saving vertical space (tabs-in-titlebar)
- [ ] **TAB-06**: User can assign colors to tabs for visual differentiation

### Input & Clipboard

- [x] **INP-01**: User can copy/paste with Ctrl+Shift+C/V and OSC 52 clipboard protocol works
- [x] **INP-02**: All existing Ghostty keybindings work correctly in the native Windows apprt

### Terminal Features

- [ ] **TERM-01**: User can search scrollback buffer with Ctrl+Shift+F overlay
- [ ] **TERM-02**: Window shows a visible scrollbar for scrollback navigation
- [ ] **TERM-03**: User can Ctrl+click URLs to open them in the default browser
- [ ] **TERM-04**: Terminal bell triggers audible/visual notification
- [x] **TERM-05**: Configuration hot-reload works — changes to ghostty.conf apply without restart
- [x] **TERM-06**: Window follows Windows system theme (light/dark) and respects padding/theme config

### Platform Integration

- [ ] **PLAT-01**: App is packaged as MSIX for Windows Store distribution and sideload
- [ ] **PLAT-02**: User can summon a dropdown terminal with a global hotkey (Quick Terminal)
- [ ] **PLAT-03**: User receives Windows toast notifications when long-running commands complete
- [ ] **PLAT-04**: User can open a searchable command palette with Ctrl+Shift+P

### Infrastructure

- [x] **INFRA-01**: COM-based Zig-to-WinRT bridge using zigwin32 + manual WinUI 3 vtable definitions
- [x] **INFRA-02**: ANGLE integration translating OpenGL to D3D11 for SwapChainPanel hosting
- [x] **INFRA-03**: DirectWrite font discovery with Freetype rasterization (directwrite_freetype backend)
- [x] **INFRA-04**: New apprt backend (`src/apprt/windows/`) coexisting with GLFW during development

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Input

- **INP-03**: IME support for CJK input methods with correctly positioned candidate window

### Platform Integration

- **PLAT-05**: System tray integration with minimize-to-tray and quick access menu
- **PLAT-06**: Jump list integration showing recent directories and profiles in taskbar
- **PLAT-07**: Context menu shell extension ("Open Ghostty here") via MSIX sparse package
- **PLAT-08**: Transparency and Acrylic/Mica material effects on window background
- **PLAT-09**: Float (always-on-top) window mode
- **PLAT-10**: Secure input indicator overlay for password prompts

### Developer Tools

- **DEV-01**: Built-in terminal state inspector UI
- **DEV-02**: Full window state persistence (tab layout, split arrangement, working directories)

### Accessibility

- **A11Y-01**: UI Automation (UIA) provider exposing terminal buffer content to screen readers

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Built-in graphical settings UI | Ghostty's philosophy is config-file-first. Command palette provides discoverability. |
| Profiles dropdown (shell picker) | Ghostty uses single shell concept with config inheritance |
| Built-in SSH client | Ghostty is a terminal emulator, not an SSH client |
| Plugin/extension system | Ghostty builds features natively rather than maintaining a plugin API |
| Direct3D renderer | Keeping OpenGL initially; renderer swap is a separate future project |
| C++/WinRT wrapper layer | Using COM directly from Zig |
| DirectWrite font rasterization | Using DirectWrite for discovery only; Freetype handles rasterization |
| Runtime bundling | Targeting Windows Store dependency model |
| Auto-update for sideload | Windows Store handles updates; sideload update deferred |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| WIN-01 | Phase 2 | Complete |
| WIN-02 | Phase 2 | Complete |
| WIN-03 | Phase 2 | Complete |
| WIN-04 | Phase 2 | Complete |
| TAB-01 | Phase 3 | Pending |
| TAB-02 | Phase 3 | Pending |
| TAB-03 | Phase 3 | Pending |
| TAB-04 | Phase 3 | Pending |
| TAB-05 | Phase 3 | Pending |
| TAB-06 | Phase 3 | Pending |
| INP-01 | Phase 2 | Complete |
| INP-02 | Phase 2 | Complete |
| TERM-01 | Phase 3 | Pending |
| TERM-02 | Phase 3 | Pending |
| TERM-03 | Phase 3 | Pending |
| TERM-04 | Phase 3 | Pending |
| TERM-05 | Phase 2 | Complete |
| TERM-06 | Phase 2 | Complete |
| PLAT-01 | Phase 4 | Pending |
| PLAT-02 | Phase 4 | Pending |
| PLAT-03 | Phase 4 | Pending |
| PLAT-04 | Phase 4 | Pending |
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0

---
*Requirements defined: 2026-02-24*
*Last updated: 2026-02-24 after roadmap creation*
