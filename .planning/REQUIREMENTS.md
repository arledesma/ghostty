# Requirements: Ghostty Native Windows Apprt

**Defined:** 2026-02-24
**Core Value:** A Windows user launches Ghostty and it feels like a first-class Windows application while rendering faster than any other terminal on the platform.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Windowing Foundation

- [ ] **WIN-01**: User sees a native WinUI 3 window hosting Ghostty's OpenGL renderer via ANGLE + SwapChainPanel
- [ ] **WIN-02**: Window has native chrome (titlebar, min/max/close, resize handles, Win11 Snap Layouts)
- [ ] **WIN-03**: Terminal content scales correctly across monitors with different DPI settings
- [ ] **WIN-04**: User can toggle fullscreen with F11 or configured keybind

### Tabs & Splits

- [ ] **TAB-01**: User can open multiple tabs in a single window with new tab button and Ctrl+T
- [ ] **TAB-02**: User can reorder tabs by dragging and close tabs with middle-click or Ctrl+W
- [ ] **TAB-03**: User can split the terminal horizontally and vertically with keyboard shortcuts
- [ ] **TAB-04**: User can navigate between splits with keyboard shortcuts
- [ ] **TAB-05**: Tabs render in the title bar, saving vertical space (tabs-in-titlebar)
- [ ] **TAB-06**: User can assign colors to tabs for visual differentiation

### Input & Clipboard

- [ ] **INP-01**: User can copy/paste with Ctrl+Shift+C/V and OSC 52 clipboard protocol works
- [ ] **INP-02**: All existing Ghostty keybindings work correctly in the native Windows apprt

### Terminal Features

- [ ] **TERM-01**: User can search scrollback buffer with Ctrl+Shift+F overlay
- [ ] **TERM-02**: Window shows a visible scrollbar for scrollback navigation
- [ ] **TERM-03**: User can Ctrl+click URLs to open them in the default browser
- [ ] **TERM-04**: Terminal bell triggers audible/visual notification
- [ ] **TERM-05**: Configuration hot-reload works — changes to ghostty.conf apply without restart
- [ ] **TERM-06**: Window follows Windows system theme (light/dark) and respects padding/theme config

### Platform Integration

- [ ] **PLAT-01**: App is packaged as MSIX for Windows Store distribution and sideload
- [ ] **PLAT-02**: User can summon a dropdown terminal with a global hotkey (Quick Terminal)
- [ ] **PLAT-03**: User receives Windows toast notifications when long-running commands complete
- [ ] **PLAT-04**: User can open a searchable command palette with Ctrl+Shift+P

### Infrastructure

- [ ] **INFRA-01**: COM-based Zig-to-WinRT bridge using zigwin32 + manual WinUI 3 vtable definitions
- [ ] **INFRA-02**: ANGLE integration translating OpenGL to D3D11 for SwapChainPanel hosting
- [ ] **INFRA-03**: DirectWrite font discovery with Freetype rasterization (directwrite_freetype backend)
- [ ] **INFRA-04**: New apprt backend (`src/apprt/windows/`) coexisting with GLFW during development

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
| WIN-01 | TBD | Pending |
| WIN-02 | TBD | Pending |
| WIN-03 | TBD | Pending |
| WIN-04 | TBD | Pending |
| TAB-01 | TBD | Pending |
| TAB-02 | TBD | Pending |
| TAB-03 | TBD | Pending |
| TAB-04 | TBD | Pending |
| TAB-05 | TBD | Pending |
| TAB-06 | TBD | Pending |
| INP-01 | TBD | Pending |
| INP-02 | TBD | Pending |
| TERM-01 | TBD | Pending |
| TERM-02 | TBD | Pending |
| TERM-03 | TBD | Pending |
| TERM-04 | TBD | Pending |
| TERM-05 | TBD | Pending |
| TERM-06 | TBD | Pending |
| PLAT-01 | TBD | Pending |
| PLAT-02 | TBD | Pending |
| PLAT-03 | TBD | Pending |
| PLAT-04 | TBD | Pending |
| INFRA-01 | TBD | Pending |
| INFRA-02 | TBD | Pending |
| INFRA-03 | TBD | Pending |
| INFRA-04 | TBD | Pending |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 0
- Unmapped: 26

---
*Requirements defined: 2026-02-24*
*Last updated: 2026-02-24 after initial definition*
