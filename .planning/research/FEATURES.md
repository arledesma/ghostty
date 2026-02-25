# Feature Research

**Domain:** Native Windows terminal emulator UI/windowing layer (apprt)
**Researched:** 2026-02-24
**Confidence:** MEDIUM-HIGH (based on competitor analysis, Ghostty macOS parity target, and Windows platform documentation)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete or unusable as a daily driver.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Tabbed interface** | Every modern Windows terminal has tabs. Windows Terminal, WezTerm, ConEmu all have them. Users will not tolerate one-window-per-shell. | MEDIUM | WinUI 3 TabView control provides native implementation. Must support reorder, close, new tab button, tab context menu. Ghostty macOS already has full tab support via AppKit. |
| **Split panes** | Windows Terminal popularized this on Windows. Power users expect horizontal/vertical splits with keyboard navigation. | HIGH | Core split tree logic exists in libghostty. The apprt must manage layout, resize handles, and focus tracking. Each split hosts an independent OpenGL surface. |
| **Per-monitor DPI scaling** | Windows has mixed-DPI setups far more commonly than macOS (laptop + external monitor). Blurry text at wrong DPI is immediately noticeable. | MEDIUM | WinUI 3 handles DPI awareness automatically for XAML elements. The OpenGL rendering surface needs manual DPI handling -- content scale already exists in apprt structs (`ContentScale`). Must handle `WM_DPICHANGED` or equivalent WinUI event for the SwapChainPanel. |
| **Native clipboard (copy/paste)** | Ctrl+C/Ctrl+V is muscle memory on Windows. Must handle rich text, plain text, and OSC 52 clipboard protocol. | LOW | Win32 clipboard API is straightforward. The core already has clipboard abstractions (`Clipboard`, `ClipboardRequest` in apprt structs). |
| **IME support (Input Method Editor)** | Required for CJK language users. Windows has a large CJK user base. Without IME, the terminal is unusable for a significant population. | HIGH | Must position the IME candidate window correctly relative to the cursor. `IMEPos` struct exists in apprt. WinUI 3 TextInputPane or TSF (Text Services Framework) integration needed. Complex because the terminal renders via OpenGL, not a standard text control. |
| **Window chrome and decorations** | Title bar, minimize/maximize/close buttons, resize handles, window snapping (Snap Layouts on Win11). Users expect native Windows window behavior. | MEDIUM | WinUI 3 provides this largely for free. Custom title bar (tabs-in-titlebar) adds complexity. Must support `window-decoration` config options (auto, none, etc.). |
| **Fullscreen mode** | Standard expectation. F11 fullscreen is universal on Windows. | LOW | `toggle_fullscreen` action already exists. WinUI 3 `AppWindow.SetPresenter(FullScreenPresenter)` handles this. |
| **Window state persistence** | Remember window size, position, and tab state across restarts. Losing your layout on restart is unacceptable. | MEDIUM | `window-save-state` config already exists. Need to serialize/deserialize window geometry, tab count, split layout, and working directories. |
| **Configuration file support** | Ghostty's `ghostty.conf` file-based config is core to the product. Users expect `open_config` to work. | LOW | Already exists in core. The apprt just needs to launch the file in the user's editor via `ShellExecute` or equivalent. |
| **Font rendering quality** | Must match or exceed Windows Terminal's DirectWrite text rendering. Subpixel rendering, font fallback, ligatures. | MEDIUM | Freetype rasterization is already working. DirectWrite font discovery is planned. The combination should produce good results but needs tuning for ClearType expectations on Windows. |
| **Scrollback buffer with scrollbar** | Users expect to scroll back through terminal output. Visible scrollbar is expected on Windows (macOS hides them by default, Windows shows them). | LOW | Scrollbar action exists. Need a native scrollbar widget or overlay that communicates with the core's scrollback. |
| **Bell notification** | Visual or audible bell when programs trigger BEL character. | LOW | `ring_bell` action exists. Use `SystemSounds.Beep` or flash the taskbar. |
| **URL detection and click-to-open** | Ctrl+click or hover-to-highlight URLs. Expected in all modern terminals. | LOW | `mouse_over_link` and `open_url` actions exist in core. Apprt needs to show a hover state and call `ShellExecute` for the URL. |
| **Search in scrollback** | Find text in terminal output. Ctrl+Shift+F is expected. | MEDIUM | `start_search`, `end_search`, `search_total`, `search_selected` actions exist. Need a search overlay UI (TextBox + match count display). |
| **Window padding and theming** | Customizable padding around terminal content, background colors, and theme (light/dark) following Windows system theme. | LOW | All config options exist (`window-padding-*`, `window-theme`). `ColorScheme` enum in apprt handles light/dark. WinUI 3 natively follows system theme. |
| **Keyboard shortcut customization** | Rebindable keybindings. Ghostty's keybind system is a core feature. | LOW | Fully handled by libghostty's keybind system. Apprt just forwards key events. |
| **Desktop notifications** | Toast notifications for long-running command completion, bell events. Windows has a robust notification system. | MEDIUM | `desktop_notification` and `command_finished` actions exist. Use Windows App SDK `AppNotificationManager` for native toast notifications. Requires MSIX identity for full notification support. |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but create real value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Quick Terminal (Quake mode)** | Global hotkey drops down a terminal from screen edge. Windows Terminal has this (`Win+backtick`). Ghostty macOS has a richer implementation with configurable position, size, animation, and per-screen state. Ghostty's implementation is already more flexible than WT's. | HIGH | `toggle_quick_terminal` action exists. Needs global hotkey registration via `RegisterHotKey` Win32 API. Window positioning, animation, and multi-monitor awareness. macOS already has `QuickTerminalPosition`, `QuickTerminalSize`, `QuickTerminalScreen`, `QuickTerminalSpaceBehavior`. |
| **Command palette** | Searchable command interface. Windows Terminal has one. Ghostty macOS has one. But Ghostty can make it better with fuzzy matching, action previews, and config access. | MEDIUM | `toggle_command_palette` action exists. Need a WinUI 3 overlay with `TextBox` + filtered `ListView`. The macOS implementation (`CommandPalette.swift`, `TerminalCommandPalette.swift`) provides the design reference. |
| **Tabs-in-titlebar** | Merging tabs into the title bar saves vertical space and looks modern. Windows Terminal does this. It's a premium feel. | HIGH | Requires custom title bar with WinUI 3 `ExtendsContentIntoTitleBar`. Must handle drag regions, window buttons, and tab rendering in the non-client area. macOS has multiple implementations (`TitlebarTabsTahoeTerminalWindow`, `TitlebarTabsVenturaTerminalWindow`). |
| **GPU rendering performance** | Ghostty's OpenGL renderer should be faster than Windows Terminal's. Casey Muratori's refterm shows 0.5-2+ GB/s is achievable. This is a core differentiator. | LOW (already exists) | The renderer already works. The apprt must not introduce latency -- XAML manages chrome only, terminal grid renders directly to SwapChainPanel. |
| **Configuration hot-reload** | Change config, see results immediately. No restart needed. Most Windows terminals require restart for many settings. | LOW (already exists) | `reload_config` and `config_change` actions exist. Core handles this. Apprt must respond to config changes for window chrome (titlebar colors, padding, decorations). |
| **Custom window styles** | Transparent backgrounds, hidden titlebar, borderless mode. These are enthusiast features but highly valued by the Ghostty community. | MEDIUM | `toggle_window_decorations`, `toggle_background_opacity`, `window-decoration` config. WinUI 3 supports `Mica`, `Acrylic`, and custom composition for transparency effects -- could even exceed macOS capabilities here. |
| **Shell integration notifications** | Automatic notifications when long-running commands complete. No manual setup needed if shell integration is installed. | LOW | `command_finished` action exists. Shell integration already works. Just wire to Windows toast notifications. |
| **Float (always-on-top) window** | Pin a terminal above other windows. Useful for monitoring logs while working. | LOW | `float_window` action exists. WinUI 3 `AppWindow.SetPresenter` with `CompactOverlayPresenter` or `SetIsAlwaysOnTop`. |
| **Inspector** | Built-in terminal state inspector for debugging. Unique to Ghostty. | MEDIUM | `inspector` action exists. Needs a UI panel (probably a split or separate window) rendering inspector data. macOS has a full implementation. |
| **Secure input indicator** | Visual indication when terminal is in secure input mode (password prompts). Helps users trust the terminal with sensitive input. | LOW | `secure_input` action exists. macOS has `SecureInputOverlay.swift`. Need a small overlay or titlebar indicator on Windows. |
| **Jump list integration** | Right-click Ghostty in taskbar to see recent directories, pinned shells, or profiles. Windows-specific feature that no other terminal does well. | MEDIUM | Win32 `ICustomDestinationList` API. Can populate from `pwd` action history and configured profiles. This is a Windows-native affordance that Ghostty could own. |
| **System tray integration** | Minimize to tray, quick access menu. Useful for quick terminal and background processes. | MEDIUM | Win32 `Shell_NotifyIcon` API or WinUI equivalent. Enables `toggle_visibility` action to show/hide all windows. Pairs with quick terminal for always-available access. |
| **Context menu shell extension ("Open Ghostty here")** | Right-click folder to open Ghostty in that directory. Windows Terminal has this built in on Windows 11. | MEDIUM | Requires registry entries or MSIX sparse package for context menu integration. Standard for Windows terminal emulators. |
| **Auto-update** | In-app update checking and installation. macOS has a full Sparkle-based update system. | HIGH | `check_for_updates` action exists. Windows Store handles updates automatically for Store distribution. For sideload, need a custom update mechanism. macOS has `UpdateController`, `UpdateDriver`, `UpdateViewModel`. |
| **Tab colors** | Visual differentiation of tabs by color. Helps navigate many tabs. | LOW | macOS has `TerminalTabColor.swift`. WinUI 3 TabView supports custom tab coloring. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems or conflict with Ghostty's philosophy.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Built-in graphical settings UI (full editor)** | Windows Terminal has a settings GUI. Users expect it. | Ghostty's philosophy is config-file-first. A full settings GUI is a massive maintenance burden, creates a second source of truth, and limits power users. Windows Terminal's settings GUI still generates JSON underneath. | `open_config` action opens the config file in an editor. Command palette provides discoverability. A focused "configuration errors" view (like macOS `ConfigurationErrorsView`) catches mistakes without a full GUI. |
| **Profiles dropdown (shell picker)** | Windows Terminal lets you pick between PowerShell, CMD, WSL, SSH from a dropdown. | Ghostty uses a single shell concept with config inheritance. A profiles dropdown adds complexity and a different mental model. | Support `new_tab` with shell override via config. The new tab menu can be customized. Quick terminal can use a different shell via config. |
| **Built-in SSH client** | Windows Terminal auto-detects SSH hosts from `~/.ssh/config`. | Ghostty is a terminal emulator, not an SSH client. Shell integration handles the SSH experience. Adding SSH management adds surface area and maintenance. | Shell integration provides working directory tracking over SSH. Users run `ssh` in the terminal naturally. |
| **Plugin/extension system** | WezTerm has Lua scripting. Users request extensibility. | Massively increases maintenance burden, security surface, and API stability requirements. Ghostty's approach is to build the right features natively. | Comprehensive keybind system, config options, and shell integration cover most customization needs. |
| **Inline rendering of images in tab bar** | Some terminals show favicons or process icons in tabs. | Performance overhead, visual clutter, inconsistent across shells. | Tab title from shell integration is sufficient. Tab colors provide visual differentiation without the complexity. |
| **Multiple settings JSON files / workspace configs** | Teams want shared configs per project. | Adds configuration resolution complexity. Which file wins? Merge semantics? | Ghostty already supports config file includes and `--config-file` CLI flag. This covers the use case without a new abstraction. |

## Feature Dependencies

```
[Native Window (WinUI 3 AppWindow)]
    +--requires--> [DPI Scaling]
    +--requires--> [Window Chrome/Decorations]
    +--enables---> [Fullscreen]
    +--enables---> [Window State Persistence]
    +--enables---> [Float Window]

[Tab Interface (WinUI 3 TabView)]
    +--requires--> [Native Window]
    +--enables---> [Tab Colors]
    +--enables---> [Move/Goto Tab actions]

[Tabs-in-Titlebar]
    +--requires--> [Tab Interface]
    +--requires--> [Custom Title Bar]
    +--conflicts--> [Hidden Titlebar mode] (must handle fallback)

[Split Panes]
    +--requires--> [Native Window]
    +--requires--> [OpenGL Surface Hosting (SwapChainPanel)]
    +--enables---> [Resize/Navigate Splits]
    +--enables---> [Toggle Split Zoom]

[OpenGL Surface Hosting]
    +--requires--> [Native Window]
    +--requires--> [DPI Scaling]
    +--enables---> [Split Panes]
    +--enables---> [Quick Terminal]

[Quick Terminal]
    +--requires--> [Native Window]
    +--requires--> [Global Hotkey Registration (RegisterHotKey)]
    +--requires--> [OpenGL Surface Hosting]
    +--enhances--> [System Tray]

[Command Palette]
    +--requires--> [Native Window]
    +--enhances--> [Keybind Discoverability]

[Desktop Notifications]
    +--requires--> [MSIX Packaging Identity]
    +--enhances--> [Shell Integration (command_finished)]

[Jump List]
    +--requires--> [MSIX Packaging Identity]
    +--enhances--> [Taskbar Integration]

[Context Menu Shell Extension]
    +--requires--> [MSIX Packaging or Registry Entries]

[System Tray]
    +--enhances--> [Quick Terminal]
    +--enables---> [Toggle Visibility]

[IME Support]
    +--requires--> [Native Window]
    +--requires--> [OpenGL Surface Hosting] (for cursor position reporting)

[Search Overlay]
    +--requires--> [Native Window]
    +--requires--> [OpenGL Surface Hosting]

[Auto-Update]
    +--requires--> [MSIX Packaging] (for Store updates)
```

### Dependency Notes

- **Native Window is the foundation:** Everything depends on getting the basic WinUI 3 AppWindow working with an OpenGL surface inside it. This must be phase 1.
- **MSIX Packaging unlocks platform integration:** Desktop notifications, jump lists, context menu integration, and Store distribution all require or benefit from MSIX app identity. This is infrastructure that should come early.
- **Tabs-in-titlebar conflicts with hidden titlebar:** When `window-decoration=none`, the tab bar must fall back to a standard position below where the title bar would be. The macOS apprt handles this with separate window style classes.
- **Quick Terminal requires global hotkey:** `RegisterHotKey` is a Win32 API that must be called even when the app is not focused. This is a Windows-specific requirement that does not exist on macOS (which uses CGEventTap).
- **IME positioning requires cursor-to-screen coordinate mapping:** The OpenGL surface does not give IME the cursor position automatically. The apprt must compute this from the core's cell position and surface geometry.

## MVP Definition

### Launch With (v1)

Minimum viable product -- what's needed for early adopters to daily-drive Ghostty on Windows.

- [ ] **Native window with OpenGL surface** -- foundation for everything else
- [ ] **Tabbed interface** -- non-negotiable for daily use
- [ ] **Split panes** -- expected by power users, core Ghostty feature
- [ ] **Per-monitor DPI scaling** -- required for multi-monitor setups
- [ ] **Native clipboard** -- copy/paste must work
- [ ] **Fullscreen** -- basic window management
- [ ] **Window chrome and decorations** -- native look and feel
- [ ] **Configuration file support** -- `open_config` works
- [ ] **Keybind system** -- all existing keybinds work
- [ ] **Search overlay** -- find in scrollback
- [ ] **Scrollbar** -- visible scrollbar for scrollback
- [ ] **Bell** -- audible/visual bell
- [ ] **URL click-to-open** -- open links from terminal
- [ ] **Window padding and theming** -- light/dark theme following system

### Add After Validation (v1.x)

Features to add once core is working and early adopters confirm stability.

- [ ] **IME support** -- add when CJK users report the need; high complexity means it should not block v1
- [ ] **Quick Terminal** -- add when window management is solid; depends on global hotkey registration
- [ ] **Command palette** -- add when the action system is fully wired up
- [ ] **Desktop notifications** -- add when MSIX packaging is ready
- [ ] **Tabs-in-titlebar** -- add when basic tabs are stable; high complexity custom title bar
- [ ] **Custom window styles (transparency, acrylic)** -- add when the rendering pipeline is stable
- [ ] **System tray** -- add alongside quick terminal
- [ ] **Jump list** -- add when MSIX packaging is ready
- [ ] **Float window** -- low complexity, add when window management is solid
- [ ] **Tab colors** -- low complexity, add when tabs are stable
- [ ] **Secure input indicator** -- low complexity, add when shell integration is validated

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Context menu shell extension** -- requires separate installer work or MSIX sparse package
- [ ] **Auto-update (non-Store)** -- Store handles this; sideload update is complex
- [ ] **Inspector UI** -- developer tool, not user-facing priority
- [ ] **Window state persistence (full layout)** -- basic position persistence first, full tab/split layout later
- [ ] **Accessibility (UIA)** -- important but extremely complex to do right with a GPU-rendered terminal; OpenGL surface is opaque to screen readers. Requires building a UIA provider that exposes terminal buffer content. Should be a dedicated effort.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Native window + OpenGL hosting | HIGH | HIGH | P1 |
| Tabbed interface | HIGH | MEDIUM | P1 |
| Split panes | HIGH | HIGH | P1 |
| DPI scaling | HIGH | MEDIUM | P1 |
| Clipboard | HIGH | LOW | P1 |
| Fullscreen | HIGH | LOW | P1 |
| Window chrome | HIGH | MEDIUM | P1 |
| Config file support | HIGH | LOW | P1 |
| Keybinds | HIGH | LOW | P1 |
| Search overlay | MEDIUM | MEDIUM | P1 |
| Scrollbar | MEDIUM | LOW | P1 |
| Bell | LOW | LOW | P1 |
| URL click-to-open | MEDIUM | LOW | P1 |
| Theming (light/dark) | MEDIUM | LOW | P1 |
| IME support | HIGH (for CJK) | HIGH | P2 |
| Quick Terminal | HIGH | HIGH | P2 |
| Command palette | MEDIUM | MEDIUM | P2 |
| Desktop notifications | MEDIUM | MEDIUM | P2 |
| Tabs-in-titlebar | MEDIUM | HIGH | P2 |
| Transparency/Acrylic | MEDIUM | MEDIUM | P2 |
| System tray | MEDIUM | MEDIUM | P2 |
| Jump list | LOW | MEDIUM | P2 |
| Float window | LOW | LOW | P2 |
| Tab colors | LOW | LOW | P2 |
| Secure input indicator | LOW | LOW | P2 |
| Context menu extension | MEDIUM | MEDIUM | P3 |
| Auto-update (sideload) | MEDIUM | HIGH | P3 |
| Inspector UI | LOW | MEDIUM | P3 |
| Full layout persistence | MEDIUM | HIGH | P3 |
| Accessibility (UIA) | HIGH (for a11y users) | VERY HIGH | P3 |

**Priority key:**
- P1: Must have for launch (daily-driver capable)
- P2: Should have, add in v1.x releases
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Windows Terminal | WezTerm | Alacritty | ConEmu | Ghostty (planned) |
|---------|----------------|---------|-----------|--------|-------------------|
| Tabs | Yes (TabView) | Yes (built-in) | No | Yes | Yes (WinUI TabView) |
| Split panes | Yes | Yes (multiplexer) | No | Yes | Yes (core split tree) |
| GPU rendering | Yes (D3D/Atlas) | Yes (OpenGL) | Yes (OpenGL) | No (GDI) | Yes (OpenGL) |
| Quake/dropdown | Yes (Win+`) | No | No | Yes | Yes (quick terminal) |
| Command palette | Yes (Ctrl+Shift+P) | No (Lua instead) | No | No | Yes |
| Settings GUI | Yes (full editor) | No (Lua config) | No (YAML) | Yes (dialog) | No (file-based, by design) |
| Tabs-in-titlebar | Yes | No | N/A | Yes | Yes (planned) |
| IME | Yes | Yes | Partial | Yes | Yes (planned) |
| DPI scaling | Yes (auto) | Yes | Yes | Yes | Yes (manual for GL surface) |
| Notifications | Limited | No | No | No | Yes (toast + command_finished) |
| Jump list | No | No | No | Yes | Yes (planned) |
| System tray | No | No | No | Yes | Yes (planned) |
| Context menu | Yes (Win11 native) | No | No | Yes | Yes (planned) |
| Transparency | Yes (Acrylic/Mica) | Yes | Yes | Yes | Yes (planned) |
| Accessibility | Yes (UIA) | Partial | No | Partial | Deferred (complex) |
| Hot-reload config | Partial | Yes (Lua) | Yes | No | Yes (core feature) |
| Shell integration | No | No | No | Partial (ANSI) | Yes (core feature) |
| Custom keybinds | Yes (JSON) | Yes (Lua) | Yes (YAML) | Yes (GUI) | Yes (config file) |
| Scrollbar | Yes (overlay) | Yes | No (by design) | Yes | Yes (planned) |

## Sources

- Ghostty macOS apprt source code (`macos/Sources/Features/`) -- analyzed for parity target
- Ghostty core apprt action system (`src/apprt/action.zig`) -- analyzed for existing action support
- Ghostty apprt structs (`src/apprt/structs.zig`) -- analyzed for existing type support
- Ghostty config (`src/config/Config.zig`) -- analyzed for existing configuration options
- [Windows Terminal overview -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/terminal/)
- [Windows Terminal Panes -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/terminal/panes)
- [Windows Terminal Command Palette -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/terminal/command-palette)
- [Windows Terminal Appearance Settings -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/appearance)
- [High DPI Desktop Application Development -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)
- [Accessibility overview for Windows apps -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview)
- [UI Automation Overview -- Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-uiautomationoverview)
- [ConEmu High DPI Awareness](https://conemu.github.io/en/DpiAware.html)
- [WezTerm DPI configuration](https://wezterm.org/config/lua/config/dpi.html)
- [Slant -- Best terminal emulators for Windows 2026](https://www.slant.co/topics/1552/~best-terminal-emulators-for-windows)
- [Terminal Compatibility Matrix](https://tmuxai.dev/terminal-compatibility/)
- [Best Terminal Emulators 2026 -- Scopir](https://scopir.com/posts/best-terminal-emulators-developers-2026/)
- [NVDA UIA console improvements](https://github.com/nvaccess/nvda/wiki/Improving-the-console-experience-with-UI-Automation)

---
*Feature research for: Native Windows terminal emulator apprt*
*Researched: 2026-02-24*
