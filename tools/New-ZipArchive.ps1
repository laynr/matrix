<#
.SYNOPSIS
Creates a ZIP archive from a file or directory.

.PARAMETER SourcePath
Path to the file or directory to compress.

.PARAMETER DestinationPath
Path where the ZIP archive will be written.

.PARAMETER Overwrite
If true, overwrite an existing archive at DestinationPath. Defaults to false.
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
        return @{ error = "Source not found: $src" } | ConvertTo-Json -Compress
    }

    if (Test-Path -LiteralPath $dst) {
        if ($Overwrite) {
            Remove-Item -LiteralPath $dst -Force
        } else {
            return @{ error = "Destination already exists. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress
        }
    }

    $srcItem = Get-Item -LiteralPath $src

    if ($srcItem.PSIsContainer) {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $dst)
    } else {
        # Single file — open archive and add one entry
        $stream  = [System.IO.File]::Open($dst, [System.IO.FileMode]::Create)
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry   = $archive.CreateEntry($srcItem.Name)
            $entryStream = $entry.Open()
            $fileStream  = [System.IO.File]::OpenRead($src)
            $fileStream.CopyTo($entryStream)
            $fileStream.Dispose()
            $entryStream.Dispose()
        } finally {
            $archive.Dispose()
            $stream.Dispose()
        }
    }

    $dstItem     = Get-Item -LiteralPath $dst
    $zipRead     = [System.IO.Compression.ZipFile]::OpenRead($dst)
    $entryCount  = $zipRead.Entries.Count
    $zipRead.Dispose()

    return @{
        DestinationPath = $dst
        SizeBytes       = $dstItem.Length
        EntryCount      = $entryCount
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
