# External Integrations

**Analysis Date:** 2026-02-24

## APIs & External Services

**Crash Reporting:**
- Sentry - Error tracking and crash reporting
  - SDK: Sentry native C SDK (pkg/sentry)
  - Config files: `src/crash/sentry.zig`, `src/crash/sentry_envelope.zig`
  - Privacy: By default stores crash data locally only; user must manually send to Sentry instance
  - Enabled by default on macOS/iOS; disabled on Linux
  - Thread-local context tracking for better crash attribution

**Display Servers:**
- Wayland - Modern display protocol for Linux
  - Wayland core protocol, Wayland Protocols extensions
  - Plasma Wayland Protocols for KDE integration
  - GTK4 Layer Shell for compositing support
- X11 - Traditional Linux display system
  - Support integrated with GTK4

**Fonts & Text:**
- Google Fonts - Default fonts (JetBrains Mono, Nerd Fonts)
- System Font Registries - Font discovery via Fontconfig (Linux) or CoreText (macOS)

## Data Storage

**Databases:**
- None detected - Ghostty is a stateless terminal emulator with no persistent data layer

**File Storage:**
- Local filesystem only
  - `~/.config/ghostty/` - User configuration files
  - `XDG_CACHE_HOME/ghostty/` or macOS cache - Sentry crash reports and temporary data
  - `~/.local/share/ghostty/` - Resources (shell integration, themes) on Linux
  - `~/Library/Application Support/ghostty/` - macOS user data

**Caching:**
- In-process memory caching - Glyph atlas, font metrics
- No external cache service

## Authentication & Identity

**Auth Provider:**
- None - Ghostty is a local terminal emulator with no user authentication

**SSH Integration:**
- OpenSSH - Loaded from system PATH, not integrated
- Ghostty can cache SSH connections via `ssh-cache` module (`src/cli/ssh-cache/`)

## Monitoring & Observability

**Error Tracking:**
- Sentry (optional, local-first approach)
  - Location: `src/crash/sentry.zig`
  - Crash reports stored locally at `~/.cache/ghostty/sentry/` or macOS equivalent
  - Users must manually upload or send to own Sentry instance
  - Thread-local state tracking for crash context

**Logs:**
- stderr - Primary logging output
- macOS system log - Available via `log` command on macOS
- Zig standard logger (scoped logging per module)
- Built-in log levels: debug, info, warn, err
- Debug inspector with ImGui overlay for runtime diagnostics

**Performance Profiling:**
- Valgrind integration (optional, development only)
  - Used in CI/CD for memory leak detection
  - Suppressions: `valgrind.supp` file

## CI/CD & Deployment

**Hosting:**
- GitHub - Code repository and release hosting
- Namespace Labs - Custom CI runners for faster builds

**CI Pipeline:**
- GitHub Actions - Primary CI system
  - Test workflow: Multi-platform builds (Linux GTK, macOS, Windows, iOS)
  - Release workflows: Automated tip releases and tagged releases
  - Custom runners: namespace-profile-ghostty-xsm, namespace-profile-ghostty-sm, namespace-profile-ghostty-lg

**Release Artifacts:**
- GitHub Releases - Source tarballs, binaries
- Flatpak repository - Linux Flatpak distribution
- Snap store - Linux Snap distribution
- Nix packages - NixOS/Nixpkgs integration
- Platform-specific installers - macOS (Homebrew compatible), Linux (system packages)

**Build Caching:**
- Cachix - Nix build caching service (`secrets.CACHIX_AUTH_TOKEN`)
- GitHub Actions cache - Build artifact caching

## Environment Configuration

**Required env vars:**
- None strictly required; application works with defaults

**Optional env vars:**
- `GHOSTTY_RESOURCES_DIR` - Override built-in resources location
- `XDG_CACHE_HOME` - Override crash report storage location
- `XDG_CONFIG_HOME` - Override configuration directory (Linux)
- `IN_NIX_SHELL` - Detected for NixOS rpath patching (build-time)
- `LD_LIBRARY_PATH` - Detected for NixOS binary patching (build-time)

**Secrets location:**
- GitHub Secrets:
  - `CACHIX_AUTH_TOKEN` - Cachix cache authentication
  - `GITHUB_TOKEN` - Automatically provided by GitHub Actions

**Configuration files:**
- `~/.config/ghostty/config` - User configuration (Linux/macOS)
- `.clang-format` - C formatting rules
- `.swiftlint.yml` - Swift linting rules
- `.editorconfig` - IDE formatting rules
- `typos.toml` - Spell-check configuration
- `.shellcheckrc` - Shell script validation rules
- `.prettierignore` - Prettier formatting exclusions

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- GitHub Webhooks (configured via Actions):
  - Triggered on push, pull_request, workflow_dispatch
  - Vouch integration for issue/PR management
  - Automatic milestone/release management

**Shell Integration:**
- Shell integration scripts that hook into Bash, Zsh, Fish
  - Enable semantic prompt recognition
  - Support for key encoding and text sizing protocols
  - Notification and OSC sequence handling

## External Protocol Support

**Kitty Graphics Protocol:**
- Full Kitty graphics protocol support for inline image display
  - Located: `src/terminal/kitty/graphics.zig`

**Hyperlinks:**
- OSC 8 hyperlink protocol support
  - Clickable links in terminal output

**Text Sizing:**
- Kitty text sizing protocol support
  - Allow remote queries of rendered text dimensions

**iTerm2 Protocols:**
- Inline images support
  - OSC compatibility for iTerm2 features

**Clipboard:**
- Kitty clipboard protocol support
  - Direct clipboard access from terminal applications

**Semantic Prompts:**
- OSC-based semantic prompt recognition
  - Shell integration for better command history

## Platform-Specific Integrations

**Linux:**
- GTK4 - Full application framework integration
- D-Bus - System integration (if GTK integrated)
- Wayland - Modern compositor support
- X11 - Legacy display server support
- XDG standards - Freedesktop specifications for file locations

**macOS/iOS:**
- AppKit/UIKit - Native application frameworks
- Metal - GPU rendering
- CoreText - Font discovery and rendering
- NSCachesDirectory - Standard cache location
- App Intents - Siri/automation support
- DockTilePlugin - Dock icon updates

**WASM/Browser:**
- Canvas API - Drawing backend
- Browser fonts - Web font system integration

---

*Integration audit: 2026-02-24*
