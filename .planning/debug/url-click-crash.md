---
status: diagnosed
trigger: "Investigate why clicking a URL in the Ghostty Windows terminal crashes the application"
created: 2026-02-26T00:00:00Z
updated: 2026-02-26T00:00:00Z
---

## Current Focus

hypothesis: COM apartment threading conflict - ShellExecuteW requires STA but app initializes COM as MTA
test: Confirmed via Microsoft documentation and known bug reports
expecting: ShellExecuteW fails/crashes when called from MTA thread
next_action: Return diagnosis

## Symptoms

expected: Clicking a detected URL opens it in the default browser
actual: Application crashes/exits when clicking a URL
errors: No error message visible (crash)
reproduction: Hover over URL (underline appears), click it -> crash
started: Since ShellExecuteW was first integrated

## Eliminated

- hypothesis: Bad UTF-8 to UTF-16 conversion
  evidence: std.unicode.utf8ToUtf16Le correctly handles ASCII URLs, buffer is 2048 u16 (more than enough), and errors are caught with `catch return false`
  timestamp: 2026-02-26

- hypothesis: Null pointer in mouse click path
  evidence: Traced full path from WM_LBUTTONUP -> forwardMouseButton -> mouseButtonCallback -> processLinks -> openUrl -> performAction; all null checks present
  timestamp: 2026-02-26

- hypothesis: Wrong extern declaration for ShellExecuteW
  evidence: Return type isize matches HINSTANCE on x64, callconv(.c) is correct on x64 (stdcall == cdecl), parameter types match Win32 API
  timestamp: 2026-02-26

- hypothesis: URL data lifetime issue (use-after-free)
  evidence: selectionString allocates, deferred free is after openUrl returns, performAction is synchronous - data is valid throughout
  timestamp: 2026-02-26

- hypothesis: Stack overflow from wide_buf[2048]u16
  evidence: 4KB on stack is well within 1MB default Windows stack limit, even with deep call chain
  timestamp: 2026-02-26

## Evidence

- timestamp: 2026-02-26
  checked: COM initialization in App.init()
  found: com.roInitialize() calls RoInitialize(RO_INIT_MULTITHREADED) at line 353 of App.zig
  implication: Main thread COM apartment is MTA (multi-threaded apartment)

- timestamp: 2026-02-26
  checked: ShellExecuteW call site in performAction
  found: ShellExecuteW called on same main thread (line 1578), within wndProc message handling
  implication: ShellExecuteW executes in MTA context

- timestamp: 2026-02-26
  checked: Microsoft documentation and known bug reports for ShellExecuteW + MTA
  found: ShellExecuteW delegates to Shell extensions activated via COM. These extensions require STA (single-threaded apartment). Microsoft docs state "COM should be initialized before ShellExecuteW is called" with COINIT_APARTMENTTHREADED for window-creating threads. Known bug reports confirm ShellExecute fails/crashes when COM is initialized as MTA.
  implication: ROOT CAUSE - MTA initialization conflicts with ShellExecuteW's STA requirement

- timestamp: 2026-02-26
  checked: Full mouse click -> open_url code path
  found: WM_LBUTTONUP (line 857) -> forwardMouseButton (line 864) -> core mouseButtonCallback -> processLinks -> openUrl -> App.performAction -> ShellExecuteW
  implication: The path is correct; the crash occurs specifically at or within ShellExecuteW

## Resolution

root_cause: COM is initialized with RO_INIT_MULTITHREADED (MTA) in App.init() via com.roInitialize(). ShellExecuteW internally uses Shell extensions that require STA (single-threaded apartment) COM. When ShellExecuteW is called from an MTA thread, the shell extensions fail to load properly, causing a crash or undefined behavior. This is a well-documented Windows API incompatibility.

fix: Not yet applied. Two possible approaches:
  1. Spawn a dedicated STA thread for ShellExecuteW calls (CoInitializeEx with COINIT_APARTMENTTHREADED on that thread)
  2. Use CreateProcessW to launch the default browser directly via "cmd /c start <url>" or use the os.open fallback (which spawns rundll32 url.dll,FileProtocolHandler)

verification: Not yet verified
files_changed: []
