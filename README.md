# OpenClaw Tray — System Tray Gateway Monitor

A lightweight PowerShell system tray app that monitors your OpenClaw gateway in real time. No installation, no dependencies beyond Windows PowerShell.

---

## What It Does

- **Green circle** — gateway is up. Tooltip shows uptime (e.g. `OpenClaw: UP (2h 14m)`)
- **Red circle** — gateway is down
- **Yellow circle** — checking on startup
- **Left-click** — opens a live log window that tails today's gateway log and pretty-prints JSON entries
- **Right-click** — menu: Open Live Log · Open Telegram · Exit
- **Balloon notification** — pops when gateway goes down or comes back up
- Polls every 30 seconds (configurable)

---

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built into Windows — no install needed)
- OpenClaw gateway running on a known local port (default: 18789)
- Gateway log files in `%LOCALAPPDATA%\Temp\openclaw\openclaw-YYYY-MM-DD.log`

---

## Setup

### 1. Get the script

Copy `openclaw-tray.ps1` to wherever you keep your OpenClaw scripts, e.g.:
```
C:\Users\you\.openclaw\workspace\scripts\openclaw-tray.ps1
```

### 2. Edit the CONFIG block

Open the script and update the four lines at the top of the CONFIG section:

```powershell
$GATEWAY_PORT  = 18789                              # port your gateway listens on
$LOG_BASE      = "$env:LOCALAPPDATA\Temp\openclaw"  # folder containing daily log files
$TELEGRAM_URL  = "https://t.me/YourBotHere"         # your bot's Telegram link
$POLL_INTERVAL = 30000                              # check interval in milliseconds
```

### 3. Create the silent launcher (VBS)

Create a file called `run-tray-hidden.vbs` next to the script:

```vbscript
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\you\.openclaw\workspace\scripts\openclaw-tray.ps1""", 0, False
```

Replace the path with wherever you saved the script. The `, 0, False` at the end is what keeps it completely hidden — no flashing terminal window.

### 4. Register the scheduled task (runs at login)

Open PowerShell and run:

```powershell
$a = New-ScheduledTaskAction -Execute "wscript.exe" `
         -Argument '"C:\Users\you\.openclaw\workspace\scripts\run-tray-hidden.vbs"'
$t = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName "OpenClaw Tray" -Action $a -Trigger $t -Settings $s
```

### 5. Start it now (without logging off)

```powershell
Start-ScheduledTask -TaskName "OpenClaw Tray"
```

The icon should appear in your system tray within a couple of seconds.

---

## Daily Use

| Action | Result |
|--------|--------|
| Hover over icon | See status + uptime |
| Left-click | Live log window opens — tails today's log, strips ANSI colour codes, pretty-prints timestamps |
| Right-click → Open Telegram | Opens your bot chat |
| Right-click → Exit | Removes icon and exits cleanly |

The log window stays open and continues tailing even if the log rolls over at midnight — just close and re-open it the next day.

---

## Stopping / Removing

```powershell
# Stop the running instance
Get-Process powershell | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process

# Remove the scheduled task
Unregister-ScheduledTask -TaskName "OpenClaw Tray" -Confirm:$false
```

---

## Troubleshooting

**Icon doesn't appear**
Run the script directly first to see any errors:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\openclaw-tray.ps1"
```

**Log window says "Log file not found yet. Waiting..."**
The gateway hasn't written a log today yet. Start the gateway and it will appear automatically — the window polls continuously.

**Icon disappeared after a while**
The PowerShell process exited (crash or accidental kill). Restart it:
```powershell
Start-ScheduledTask -TaskName "OpenClaw Tray"
```

---

*Built with PowerShell + WinForms NotifyIcon. No third-party dependencies.*
