<#
.SYNOPSIS
Lists system services with their name, status, and start type, with optional wildcard filtering.

.PARAMETER Name
Wildcard pattern to filter service names. Defaults to * (all services).
#>
[CmdletBinding()]
param(
    [string]$Name = "*"
)

try {
    $result = @()

    if ($IsWindows) {
        $services = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $result = @($services | ForEach-Object {
            $startType = $null
            try { $startType = $_.StartType.ToString() } catch { }
            @{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                Status      = $_.Status.ToString()
                StartType   = $startType
            }
        })
    } elseif ($IsMacOS) {
        # launchctl list returns: PID  Status  Label
        $lines = & launchctl list 2>/dev/null | Select-Object -Skip 1
        foreach ($line in $lines) {
            $parts = $line -split '\s+', 3
            if ($parts.Count -lt 3) { continue }
            $label = $parts[2].Trim()
            if ($Name -ne "*" -and $label -notlike $Name) { continue }
            $status = if ($parts[0] -ne "-") { "Running" } else { "Stopped" }
            $result += @{
                Name        = $label
                DisplayName = $label
                Status      = $status
                StartType   = $null
            }
        }
    } elseif ($IsLinux) {
        # systemctl --no-pager --plain -a list-units --type=service
        $lines = & systemctl list-units --type=service --no-pager --plain --all 2>/dev/null | Select-Object -Skip 1
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Trim() -split '\s+', 5
            if ($parts.Count -lt 3) { continue }
            $svcName = $parts[0] -replace '\.service$', ''
            if ($Name -ne "*" -and $svcName -notlike $Name) { continue }
            $result += @{
                Name        = $svcName
                DisplayName = if ($parts.Count -ge 5) { $parts[4] } else { $svcName }
                Status      = $parts[2]
                StartType   = $null
            }
        }
    } else {
        return @{ error = "Unsupported platform." } | ConvertTo-Json -Compress
    }

    return @{
        ServiceCount = $result.Count
        Services     = $result
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
