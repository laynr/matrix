<#
.SYNOPSIS
Writes or appends text content to a file. Creates the file and any missing parent directories if they do not exist.

.PARAMETER Path
The path of the file to write.

.PARAMETER Content
The text content to write.

.PARAMETER Append
If true, appends to the file instead of overwriting. Defaults to false.

.PARAMETER Overwrite
If true, allows overwriting an existing file. Defaults to false (returns an error if the file exists and Append is false).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [Parameter(Mandatory=$true)]
    [string]$Content,

    [bool]$Append    = $false,
    [bool]$Overwrite = $false
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $parent   = Split-Path $resolved -Parent

    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ((Test-Path $resolved) -and -not $Append -and -not $Overwrite) {
        return @{ error = "'$resolved' already exists. Set Overwrite=true to replace it or Append=true to add to it." } | ConvertTo-Json -Compress
    }

    if ($Append) {
        Add-Content -Path $resolved -Value $Content -Encoding UTF8
        $action = "appended"
    } else {
        Set-Content -Path $resolved -Value $Content -Encoding UTF8
        $action = "written"
    }

    $size = (Get-Item $resolved).Length

    return @{
        Path   = $resolved
        Action = $action
        Bytes  = $size
    } | ConvertTo-Json -Compress
} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
