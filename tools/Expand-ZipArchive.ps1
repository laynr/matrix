<#
.SYNOPSIS
Extracts a ZIP archive to a destination directory.

.PARAMETER SourcePath
Path to the ZIP file to extract.

.PARAMETER DestinationPath
Directory where contents will be extracted.

.PARAMETER Overwrite
If true, overwrite existing files at the destination. Defaults to false.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [Parameter(Mandatory)]
    [string]$DestinationPath,

    [bool]$Overwrite = $false
)

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $src = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourcePath)
    $dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)

    if (-not (Test-Path -LiteralPath $src)) {
        return @{ error = "Source ZIP not found: $src" } | ConvertTo-Json -Compress
    }

    $srcItem = Get-Item -LiteralPath $src
    if ($srcItem.PSIsContainer) {
        return @{ error = "SourcePath is a directory, not a ZIP file." } | ConvertTo-Json -Compress
    }

    if (-not (Test-Path -LiteralPath $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }

    # PS 7 / .NET 6+ supports overwrite parameter on ExtractToDirectory
    if ($Overwrite) {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($src, $dst, $true)
    } else {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($src, $dst)
    }

    $zipRead = [System.IO.Compression.ZipFile]::OpenRead($src)
    $files   = @($zipRead.Entries | ForEach-Object { $_.FullName })
    $count   = $zipRead.Entries.Count
    $zipRead.Dispose()

    return @{
        DestinationPath = $dst
        EntryCount      = $count
        Files           = $files
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
