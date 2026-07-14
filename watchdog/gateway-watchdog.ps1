# OpenClaw Gateway Watchdog
# Restarts the gateway only if port is down AND no openclaw node process is already running.
# This prevents duplicate-instance storms during slow boots or restarts.

$port = 18789
$taskName = "OpenClaw Gateway"
$watchdogTask = "OpenClaw Gateway Watchdog"
$bootGraceSecs = 30  # Don't restart if a node process started within this many seconds

# Self-gating: if this task is disabled, the systray stopped us — bail out
$selfState = (Get-ScheduledTask -TaskName $watchdogTask -ErrorAction SilentlyContinue).State
if ($selfState -eq "Disabled") { exit 0 }

# Check if port is responding
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue

if (-not $up) {
    # Check if any openclaw node process is already running (may be mid-boot)
    $nodeProcs = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
        try { $_.MainModule.FileName -like "*node*" } catch { $false }
    }

    # Also check raw WMI for command line match (more reliable)
    $openclawProcs = Get-WmiObject Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*openclaw*" }

    if ($openclawProcs) {
        # Node process exists — check if it started recently (still booting)
        $recentBoot = $openclawProcs | Where-Object {
            try {
                $startTime = [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate)
                ((Get-Date) - $startTime).TotalSeconds -lt $bootGraceSecs
            } catch { $false }
        }
        if ($recentBoot) {
            # Gateway is mid-boot, leave it alone
            exit 0
        }
        # Process exists but port is still down after grace period — something is wrong, restart
    }

    # Check scheduled task state
    $taskState = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
    if ($taskState -ne "Running") {
        Start-ScheduledTask -TaskName $taskName
    }
}
