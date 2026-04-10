<#
.SYNOPSIS
Retrieves recent system log entries from the Windows Event Log, Linux syslog, or macOS unified log.

.PARAMETER LogName
Event log name to query on Windows (e.g. System, Application). Ignored on Linux/macOS. Defaults to System.

.PARAMETER Newest
Maximum number of entries to return. Defaults to 50.

.PARAMETER Level
Optional severity filter: Error, Warning, or Info. Case-insensitive.
#>
[CmdletBinding()]
param(
    [string]$LogName = "System",
    [int]$Newest     = 50,
    [string]$Level   = ""
)

try {
    $entries   = @()
    $logSource = ""

    if ($IsWindows) {
        $logSource = "WinEvent:$LogName"
        $params    = @{
            LogName   = $LogName
            MaxEvents = $Newest
            ErrorAction = "SilentlyContinue"
        }
        $events = Get-WinEvent @params

        $levelMap = @{ Error = @(1,2); Warning = @(3); Info = @(4,0) }

        foreach ($e in $events) {
            if ($Level) {
                $allowed = $levelMap[$Level]
                if ($allowed -and $e.Level -notin $allowed) { continue }
            }
            $entries += @{
                TimeCreated = $e.TimeCreated.ToString("o")
                Level       = $e.LevelDisplayName
                Source      = $e.ProviderName
                Message     = ($e.Message -split "`n")[0].Trim()  # first line only
            }
        }

    } elseif ($IsLinux) {
        $candidates = @("/var/log/syslog", "/var/log/messages", "/var/log/kern.log")
        $logFile    = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($logFile) {
            $logSource = $logFile
            $lines     = Get-Content $logFile -Tail $Newest -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $lvl = if ($line -match "error"  ) { "Error"   }
                       elseif ($line -match "warn") { "Warning" }
                       else                         { "Info"    }
                if ($Level -and $lvl -ne $Level) { continue }
                $entries += @{
                    TimeCreated = $null
                    Level       = $lvl
                    Source      = "syslog"
                    Message     = $line.Trim()
                }
            }
        } else {
            if (-not (Get-Command 'journalctl' -ErrorAction SilentlyContinue)) {
                return @{ error = "No syslog file found and journalctl is not available on this system." } |
                    ConvertTo-Json -Compress
            }
            $logSource = "journalctl"
            $raw = & journalctl -n $Newest --no-pager --output short 2>/dev/null
            foreach ($line in $raw) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $entries += @{
                    TimeCreated = $null
                    Level       = "Info"
                    Source      = "journalctl"
                    Message     = $line.Trim()
                }
            }
        }

    } elseif ($IsMacOS) {
        $logSource = "log show (macOS)"
        $raw = & log show --last 1h --style syslog --info 2>/dev/null | Select-Object -Last $Newest
        foreach ($line in $raw) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $lvl = if ($line -match "Error"  ) { "Error"   }
                   elseif ($line -match "Warn") { "Warning" }
                   else                         { "Info"    }
            if ($Level -and $lvl -ne $Level) { continue }
            $entries += @{
                TimeCreated = $null
                Level       = $lvl
                Source      = "macOS-log"
                Message     = $line.Trim()
            }
        }
    } else {
        return @{ error = "Unsupported platform." } | ConvertTo-Json -Compress
    }

    return @{
        EntryCount = $entries.Count
        LogSource  = $logSource
        Entries    = @($entries)
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
