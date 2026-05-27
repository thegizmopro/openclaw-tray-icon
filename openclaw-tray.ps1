# openclaw-tray.ps1
# System tray status monitor for the OpenClaw gateway.
#
# Green  = gateway UP  (shows uptime)
# Red    = gateway DOWN
# Yellow = checking...
#
# Left-click        → live log window (tails today's log, JSON-pretty)
# Right-click       → menu: Live Log | Open Telegram | Exit
# Balloon tip       → fires on status change (up ↔ down)
#
# ── DEPLOYMENT ───────────────────────────────────────────────────────────────
# 1. Edit the CONFIG block below (port, log path, Telegram URL).
# 2. Create a silent VBS launcher alongside this file:
#
#       Set objShell = CreateObject("WScript.Shell")
#       objShell.Run "powershell.exe -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
#           "C:\path\to\openclaw-tray.ps1""", 0, False
#
# 3. Register a scheduled task (runs once at logon, no window):
#
#       $a = New-ScheduledTaskAction -Execute "wscript.exe" `
#                -Argument '"C:\path\to\run-tray-hidden.vbs"'
#       $t = New-ScheduledTaskTrigger -AtLogOn
#       $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -MultipleInstances IgnoreNew
#       Register-ScheduledTask -TaskName "OpenClaw Tray" -Action $a -Trigger $t -Settings $s
#
# 4. Start-ScheduledTask "OpenClaw Tray"   ← or just log off/on
# ─────────────────────────────────────────────────────────────────────────────

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── CONFIG ────────────────────────────────────────────────────────────────────
$GATEWAY_PORT  = 18789
$LOG_BASE      = "$env:LOCALAPPDATA\Temp\openclaw"   # folder holding openclaw-YYYY-MM-DD.log
$TELEGRAM_URL  = "https://t.me/YourBotHere"          # right-click → Open Telegram
$POLL_INTERVAL = 30000                               # ms between status checks
# ─────────────────────────────────────────────────────────────────────────────

# ── Helper: today's log path ──────────────────────────────────────────────────
function Get-TodayLog {
    return Join-Path $LOG_BASE ("openclaw-" + (Get-Date -Format 'yyyy-MM-dd') + ".log")
}

# ── Helper: is gateway listening? (port check, ~1 ms) ────────────────────────
function Test-Gateway {
    return ($null -ne (Get-NetTCPConnection -LocalPort $GATEWAY_PORT -State Listen -ErrorAction SilentlyContinue))
}

# ── Helper: draw a coloured circle as a 16×16 tray icon ──────────────────────
function New-CircleIcon {
    param([System.Drawing.Color]$Color)
    $bmp   = New-Object System.Drawing.Bitmap(16, 16)
    $g     = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $brush = New-Object System.Drawing.SolidBrush($Color)
    $g.FillEllipse($brush, 1, 1, 13, 13)
    $brush.Dispose(); $g.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $bmp.Dispose()
    return $icon
}

$iconGreen  = New-CircleIcon ([System.Drawing.Color]::FromArgb(34,  197,  94))
$iconRed    = New-CircleIcon ([System.Drawing.Color]::FromArgb(220,  38,  38))
$iconYellow = New-CircleIcon ([System.Drawing.Color]::FromArgb(234, 179,   8))

# ── Open a live-tailing log window ───────────────────────────────────────────
function Open-LiveLog {
    $logPath = Get-TodayLog
    $cmd = @"
`$host.UI.RawUI.WindowTitle = 'OpenClaw Live Log'
`$logPath = '$logPath'
Write-Host "OpenClaw Gateway - Live Log" -ForegroundColor Cyan
Write-Host "File: `$logPath"             -ForegroundColor DarkGray
Write-Host ("-" * 70)                    -ForegroundColor DarkGray
if (-not (Test-Path `$logPath)) {
    Write-Host "Log file not found yet. Waiting..." -ForegroundColor Yellow
}
Get-Content `$logPath -Wait -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        `$j = `$_ | ConvertFrom-Json
        `$t = `$j.time    -replace 'T',' ' -replace '\.\d+[+-].*',''
        `$m = `$j.message -replace '\x1B\[[0-9;]*m',''
        Write-Host "`$t  `$m"
    } catch {
        Write-Host `$_ -ForegroundColor DarkGray
    }
}
"@
    $bytes   = [System.Text.Encoding]::Unicode.GetBytes($cmd)
    $encoded = [Convert]::ToBase64String($bytes)
    Start-Process powershell.exe -ArgumentList "-NoExit", "-EncodedCommand", $encoded
}

# ── Tray icon ─────────────────────────────────────────────────────────────────
$notify         = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
$notify.Icon    = $iconYellow
$notify.Text    = "OpenClaw: checking..."

# ── Context menu ─────────────────────────────────────────────────────────────
$menu       = New-Object System.Windows.Forms.ContextMenuStrip
$miLog      = $menu.Items.Add("Open Live Log")
$miTelegram = $menu.Items.Add("Open Telegram")
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miExit     = $menu.Items.Add("Exit")
$notify.ContextMenuStrip = $menu

$notify.add_MouseClick({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Open-LiveLog }
})
$miLog.add_Click({      Open-LiveLog })
$miTelegram.add_Click({ Start-Process $TELEGRAM_URL })
$miExit.add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

# ── Status polling ────────────────────────────────────────────────────────────
$script:lastUp      = $null
$script:uptimeSince = $null

function Update-TrayStatus {
    $up = Test-Gateway

    if ($up) {
        if ($null -eq $script:uptimeSince) { $script:uptimeSince = Get-Date }
        $span  = (Get-Date) - $script:uptimeSince
        $upStr = if ($span.TotalHours -ge 1) { "$([int]$span.TotalHours)h $($span.Minutes)m" }
                 else                         { "$($span.Minutes)m" }
        $notify.Icon = $iconGreen
        $notify.Text = "OpenClaw: UP ($upStr)"
    } else {
        $script:uptimeSince = $null
        $notify.Icon = $iconRed
        $notify.Text = "OpenClaw: DOWN"
    }

    if ($null -ne $script:lastUp -and $script:lastUp -ne $up) {
        if ($up) { $notify.ShowBalloonTip(4000, "OpenClaw", "Gateway is back up",  [System.Windows.Forms.ToolTipIcon]::Info)    }
        else     { $notify.ShowBalloonTip(6000, "OpenClaw", "Gateway went DOWN",   [System.Windows.Forms.ToolTipIcon]::Warning) }
    }
    $script:lastUp = $up
}

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = $POLL_INTERVAL
$timer.add_Tick({ Update-TrayStatus })
$timer.Start()

Update-TrayStatus   # immediate first check

[System.Windows.Forms.Application]::Run()
