<#
.SYNOPSIS
Reads one or all environment variables from the current session.

.PARAMETER Name
The name of the environment variable to read. Leave blank to list all variables.

.PARAMETER Filter
Wildcard filter applied when listing all variables (e.g. "PATH*", "*HOME*").
#>
[CmdletBinding()]
param(
    [string]$Name   = "",
    [string]$Filter = "*"
)

try {
    if ($Name) {
        $val = [System.Environment]::GetEnvironmentVariable($Name)
        if ($null -eq $val) {
            return @{ error = "Environment variable '$Name' is not set." } | ConvertTo-Json -Compress
        }
        return @{ Name = $Name; Value = $val } | ConvertTo-Json -Compress
    }

    $all = Get-ChildItem Env: |
        Where-Object { $_.Name -like $Filter } |
        Sort-Object Name |
        ForEach-Object { @{ Name = $_.Name; Value = $_.Value } }

    return @{
        Filter = $Filter
        Count  = @($all).Count
        Variables = @($all)
    } | ConvertTo-Json -Depth 4 -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
