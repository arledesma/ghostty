---
status: diagnosed
trigger: "bell notification doesn't work and pwsh.exe/powershell.exe fail to launch"
created: 2026-02-26T00:00:00Z
updated: 2026-02-26T00:00:00Z
---

## Current Focus

hypothesis: Two separate issues - bell path is wired correctly but untested, shell launch wraps everything in cmd.exe /C
test: trace code paths for both issues
expecting: confirm bell dispatch chain and shell wrapping behavior
next_action: report diagnosis

## Symptoms

expected: (1) Ctrl+G in cmd.exe triggers system beep + taskbar flash. (2) pwsh.exe launches as shell. (3) powershell.exe launches as shell.
actual: (1) No bell. (2) pwsh.exe throws error. (3) powershell.exe immediately exits.
errors: Unknown specific error messages for pwsh/powershell
reproduction: Set command=pwsh.exe or powershell.exe in config, or type Ctrl+G in cmd.exe
started: Likely since initial Win32 apprt implementation

## Eliminated

(none)

## Evidence

- timestamp: 2026-02-26T00:01:00Z
  checked: Bell dispatch chain from terminal stream to App.zig
  found: Chain is complete - stream.zig dispatches BEL (0x07) -> stream_handler.zig bell() -> surfaceMessageWriter(.ring_bell) -> Surface.zig ring_bell handler -> App.performAction(.ring_bell) -> MessageBeep(0xFFFFFFFF) + FlashWindow
  implication: The bell code path is fully wired. The issue is likely that Ctrl+G in cmd.exe does not produce a BEL character through ConPTY, or the bell is being rate-limited, or MessageBeep is failing silently.

- timestamp: 2026-02-26T00:02:00Z
  checked: Shell launch mechanism in Exec.zig execCommand()
  found: When config command is a "shell" type (string like "pwsh.exe"), the Windows code path wraps it as: cmd.exe /C pwsh.exe. The args become ["%WINDIR%\System32\cmd.exe", "/C", "pwsh.exe"]. This means pwsh.exe is launched as a CHILD of cmd.exe, not directly.
  implication: This is the root cause for pwsh/powershell issues. cmd.exe /C runs the command and exits when it finishes. PowerShell may have issues being launched this way through ConPTY.

- timestamp: 2026-02-26T00:03:00Z
  checked: Default shell configuration
  found: In Exec.zig line 758, default_shell_command for Windows is .{ .shell = "cmd.exe" }, which becomes cmd.exe /C cmd.exe (cmd.exe wrapping cmd.exe). This is redundant but functional because cmd.exe /C cmd.exe just launches a nested cmd.exe.
  implication: The double-cmd.exe wrapping works by accident for cmd.exe but is wrong in principle.

- timestamp: 2026-02-26T00:04:00Z
  checked: How ConPTY handles BEL character
  found: ConPTY (Windows Pseudo Console) should pass through BEL (0x07) to the terminal emulator. The read thread in Exec.zig reads raw bytes from pty.out_pipe and feeds them to termio.Termio.processOutput. The terminal parser in stream.zig correctly maps BEL to the bell handler.
  implication: BEL should work if cmd.exe actually emits it. Ctrl+G in cmd.exe normally produces BEL, but cmd.exe's own console handling may intercept it before it reaches ConPTY.

- timestamp: 2026-02-26T00:05:00Z
  checked: Environment variable passing for shell processes
  found: Surface.defaultTermioEnv() returns an EMPTY EnvMap. The Subprocess.init code builds env from config and system, but starts from the Surface's defaultTermioEnv which is empty. On Windows, CreateProcessW is called with CREATE_UNICODE_ENVIRONMENT and the explicitly-built env block. This means the child process gets ONLY the env vars explicitly set, NOT the inherited system environment.
  implication: This is likely a contributing factor for pwsh/powershell failures - they may not receive critical environment variables like SYSTEMROOT, USERPROFILE, APPDATA, etc.

## Resolution

root_cause: |
  TWO SEPARATE ROOT CAUSES:

  1. SHELL LAUNCH (pwsh.exe/powershell.exe):
     The primary issue is in src/termio/Exec.zig lines 1550-1584. When the config
     specifies a shell command (e.g., "pwsh.exe"), the Windows code path wraps it as:
       cmd.exe /C pwsh.exe
     This is problematic because:
     a) cmd.exe /C runs the command and waits for it to exit, then exits itself.
        Interactive shells like pwsh.exe may not behave correctly when launched
        this way through ConPTY.
     b) The environment may be incomplete - Surface.defaultTermioEnv() returns an
        empty EnvMap, and the env building in Subprocess.init may not include all
        necessary Windows system environment variables.

     Additionally, the "direct" command variant should be used for shells on Windows
     rather than wrapping through cmd.exe /C, since the shell IS the interactive
     program (not something that needs shell expansion).

  2. BELL (Ctrl+G):
     The bell code path is correctly wired from the terminal parser through to
     MessageBeep + FlashWindow in App.zig. The likely issue is that:
     a) cmd.exe running inside ConPTY may handle BEL internally rather than
        passing it through to the PTY output pipe, OR
     b) The BEL character IS being passed through but something in the
        processing chain is silently failing (e.g., MessageBeep returning
        failure).
     Testing is needed to confirm which case applies. A simple test: echo a
     BEL character using `echo ^G` or a script that writes 0x07 to stdout.

fix: (not yet applied)
verification: (not yet verified)
files_changed: []
