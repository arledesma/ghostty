---
phase: 03-tabs-splits-terminal-features
plan: 03
subsystem: ui
tags: [win32, search, scrollbar, url, bell, shell32, gdi]

# Dependency graph
requires:
  - phase: 03-tabs-splits-terminal-features/02
    provides: "Split pane layout with SplitTree binary tree"
provides:
  - "SearchOverlay.zig with Win32 EDIT control for scrollback search"
  - "performAction handlers for start_search, end_search, search_total, search_selected"
  - "Scrollbar state tracking on Surface (scroll_total, scroll_offset, scroll_view_len)"
  - "URL opening via ShellExecuteW from shell32"
  - "Bell notification via MessageBeep and FlashWindow"
  - "Link hover cursor change via SetCursor with IDC_HAND"
  - "cell_size action tracking on Surface"
affects: [03-tabs-splits-terminal-features]

# Tech tracking
tech-stack:
  added: [shell32, gdi32-edit-control]
  patterns: [search-overlay, scrollbar-state, url-dispatch]
---

## Summary

Added four terminal UX features to complete the Phase 3 feature set: search overlay for scrollback, scrollbar state tracking, URL click-to-open, and bell notification.

## Key Decisions

1. **SearchOverlay as embedded struct** — SearchOverlay is stored as an optional field on Surface rather than a separate window class. It creates Win32 EDIT and BUTTON controls as children of the surface HWND for text input and navigation.

2. **Scrollbar as state, not widget** — Scrollbar position is tracked via scroll_total/scroll_offset/scroll_view_len fields on Surface. Painting is triggered via InvalidateRect. This avoids a separate scrollbar HWND and keeps rendering simple.

3. **ShellExecuteW for URLs** — Used shell32's ShellExecuteW instead of CreateProcess for URL opening. This handles protocol dispatch (http, https, mailto) via the OS default handler.

4. **MessageBeep + FlashWindow for bell** — Combined audible (MessageBeep with 0xFFFFFFFF for default sound) and visual (FlashWindow for taskbar flash) bell notification.

## What Was Built

### Task 1: Search overlay and scrollbar
- Created `src/apprt/windows/SearchOverlay.zig` (579 lines) with:
  - Win32 EDIT control for search input
  - Up/Down BUTTON controls for result navigation
  - show/hide lifecycle with focus management
  - setTotal/setSelected for match count display
  - EN_CHANGE notification for live search
  - Escape to close
- Added scrollbar state fields to Surface.zig
- performAction handlers: start_search, end_search, search_total, search_selected, scrollbar

### Task 2: URL click and bell
- performAction handler for open_url: UTF-8 → UTF-16 conversion then ShellExecuteW
- performAction handler for mouse_over_link: SetCursor to IDC_HAND/IDC_ARROW
- performAction handler for ring_bell: MessageBeep + FlashWindow
- performAction handler for cell_size: tracks cell dimensions on Surface
- Added extern declarations for ShellExecuteW, MessageBeep, FlashWindow, SetCursor

## Key Files

### key-files.created
- src/apprt/windows/SearchOverlay.zig

### key-files.modified
- src/apprt/windows/App.zig
- src/apprt/windows/Surface.zig

## Deviations

None — plan executed as designed.

## Self-Check: PASSED
- [x] SearchOverlay.zig exists with EDIT control and navigation
- [x] performAction handles start_search, end_search, search_total, search_selected
- [x] Scrollbar state tracked on Surface
- [x] open_url calls ShellExecuteW
- [x] mouse_over_link changes cursor
- [x] ring_bell plays sound and flashes taskbar
- [x] cell_size tracked on Surface
