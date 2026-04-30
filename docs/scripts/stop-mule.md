# `scripts/stop-mule.ps1` — Stop the Local Mule Runtime

> **Task label**: `Mule: Stop`
> **Source**: [`../../scripts/stop-mule.ps1`](../../scripts/stop-mule.ps1)
> **Companion script**: [`run-mule.md`](./run-mule.md)

---

## What it does (one line)

Force-kills any **wrapper** processes (`wrapper-windows-x86-64`, `wrapper`) and any **java** processes whose command line mentions `mule` or `wrapper` — so the local Mule runtime started by `run-mule.ps1` (or by ACB's F5) is stopped cleanly even if `Ctrl+C` in the task panel didn't work or you closed the terminal.

---

## Why this script exists

`mule.bat console` is supposed to die when you press `Ctrl+C` in its terminal. In practice, three things break that:

1. **Closing the task panel** in Cursor doesn't propagate `Ctrl+C` — the runtime keeps running, the port stays bound, and the next `Mule: Run (Cursor)` fails with "address already in use".
2. **The wrapper survives the JVM** — `mule.bat` is actually three nested processes: `cmd.exe` → `wrapper.exe` → `java.exe`. Killing the JVM alone leaves the wrapper, which then respawns the JVM. Killing the wrapper is what actually stops the app.
3. **F5-from-ACB** spawns the same wrapper but routes its lifecycle through the debug adapter; if you close ACB without "Stop Debugging" first, the wrapper orphans.

This script is the cleanup. It targets the **wrapper** processes by name, then any **java** processes that look Mule-related — both are required because Mule on Windows uses the Tanuki wrapper to keep the JVM alive.

---

## When to use it

- **Always**, after a session in Cursor where you ran **Mule: Run (Cursor)** and want to free port 8081
- When `Mule: Run (Cursor)` fails with a port-bind error and you don't know which process is holding it
- When ACB's F5 ran the runtime but you closed ACB without stopping it first
- After a hung deploy where the runtime is alive but unresponsive
- Before changing JDK or Mule runtime versions in `~/AnypointCodeBuilder/`

It is **safe** to run when nothing is running — `Get-Process` returns nothing for the targeted names and the script silently moves on.

---

## What it does — line by line

The script is short — 23 lines total.

### Setup (lines 6–8)

```6:8:scripts/stop-mule.ps1
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "==> Stopping Mule runtime processes..." -ForegroundColor Cyan
```

- `$ErrorActionPreference = 'SilentlyContinue'` is critical — without it, `Get-Process` throws if a name isn't found, and the script exits before getting to the second cleanup step. Silencing the errors makes "no process matched" a normal outcome instead of a fatal one.

### Step 1 — Kill the Tanuki wrappers (lines 10–13)

```10:13:scripts/stop-mule.ps1
Get-Process -Name 'wrapper-windows-x86-64','wrapper' | ForEach-Object {
  Write-Host "Stopping wrapper PID $($_.Id)"
  Stop-Process -Id $_.Id -Force
}
```

- `wrapper-windows-x86-64.exe` is the Tanuki Service Wrapper binary that ships with Mule on 64-bit Windows. (Some installers name the executable `wrapper.exe` — both are checked.)
- `Stop-Process -Force` is a hard kill (`SIGKILL` equivalent on Windows). The wrapper is designed to be force-killed safely; it doesn't hold open file handles that would corrupt on abort.
- This step alone is usually enough — when the wrapper dies, it takes the JVM with it. Step 2 is for the edge case where the wrapper already died but the JVM is orphaned (rare; happens after a wrapper crash).

### Step 2 — Kill any orphaned Mule JVMs (lines 15–21)

```15:21:scripts/stop-mule.ps1
Get-Process -Name 'java' | ForEach-Object {
  $cmdline = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
  if ($cmdline -match 'mule|wrapper') {
    Write-Host "Stopping java PID $($_.Id)"
    Stop-Process -Id $_.Id -Force
  }
}
```

- Lists every `java.exe` running on the machine.
- For each one, queries WMI (`Win32_Process`) for the **full command line** — this is the only reliable way on Windows to know what a `java.exe` is actually executing.
- Filters by command line containing `mule` or `wrapper` — i.e. "this `java.exe` was launched by the Mule wrapper or has `mule` in its classpath". **Other Java apps (your IDE, Maven daemons, Elasticsearch, Gradle, etc.) are left alone.**
- Force-kills the matching ones.

> **Important**: this script does NOT kill all `java.exe` processes. It only kills the ones it can prove are Mule-related. If you ever need a nuclear option, run `Get-Process java | Stop-Process -Force` directly — but that takes down every JVM on your machine including your IDE.

### Done message (line 23)

```23:23:scripts/stop-mule.ps1
Write-Host "Done." -ForegroundColor Green
```

Always prints, regardless of how many processes were killed (including zero).

---

## How to run it

### Recommended — via the task

`Ctrl+Shift+P` → `Tasks: Run Task` → **Mule: Stop**

(There's no keybinding by default; add one in `keybindings.json` if you stop the runtime often.)

### Direct invocation

```powershell
pwsh ./scripts/stop-mule.ps1
```

### One-liner equivalent (if you don't want to invoke the script)

```powershell
Get-Process wrapper-windows-x86-64,wrapper -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process java -ErrorAction SilentlyContinue | Where-Object {
  (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'mule|wrapper'
} | Stop-Process -Force
```

---

## Reading the output

```
==> Stopping Mule runtime processes...
Stopping wrapper PID 12404
Stopping java PID 19836
Done.
```

If you see only `Done.` with no `Stopping ...` lines, nothing was running — that's fine.

If port 8081 is **still** bound after the script returns, the offender is something other than Mule (a Node dev server, another Java app, a stale Docker container). Check with:

```powershell
Get-NetTCPConnection -LocalPort 8081 | ForEach-Object {
  Get-Process -Id $_.OwningProcess
}
```

…and decide whether to kill it manually.

---

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| Script returns instantly with `Done.` but `Mule: Run (Cursor)` still fails on port 8081 | Something other than Mule is on 8081 | Use the `Get-NetTCPConnection` command above to identify the owner |
| `Access is denied` errors when killing PIDs | The wrapper was started by an elevated session (Admin terminal); your current session isn't elevated | Re-run the script in an Admin PowerShell, or close the elevated session first |
| `Get-CimInstance: Invalid namespace` | Old Windows version (pre-Win10) where WMI namespace differs | Replace `Get-CimInstance Win32_Process` with `Get-WmiObject Win32_Process` |
| Java IDE / build tool got killed | Your `java.exe` process had `mule` or `wrapper` somewhere in its command line (very rare — usually only happens if your IDE config name contains "mule") | Edit the script's regex on line 17 to be stricter, e.g. `mule.*standalone|wrapper-windows` |

---

## What this script does **not** do

- Doesn't stop a Mule runtime running inside Docker — kill the container instead (`docker stop <name>`)
- Doesn't stop Mule running on a remote machine (CloudHub, on-prem server) — those have their own lifecycle (Runtime Manager / `mule stop` on the box)
- Doesn't clean up the `apps/` folder under `~/AnypointCodeBuilder/runtime/.../apps/` — the next `run-mule.ps1` overwrites the jar with `-Force`, so this isn't usually needed. If you want to fully reset, delete the `apps/` folder manually.
- Doesn't kill stuck Maven daemons — those linger after a build crash and show up as separate `java.exe` processes that **don't** have `mule` in their command line, so step 2's filter excludes them. To kill them: `Get-Process java | Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'maven' } | Stop-Process -Force`

---

## Related

- [`run-mule.md`](./run-mule.md) — the script this one cleans up after
- [`../agent-workflow.md`](../agent-workflow.md) § 8 — why Cursor needs `run-mule.ps1` / `stop-mule.ps1` instead of F5
