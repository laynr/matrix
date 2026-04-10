<#
.SYNOPSIS
Organize image files into date-based subfolders using EXIF data or file modification time.

.PARAMETER SourcePath
Directory containing image files to organize.

.PARAMETER DestinationPath
Root directory for the organized output. Defaults to SourcePath.

.PARAMETER Structure
Folder naming pattern: YYYY/YYYY-MM-DD (default), YYYY/YYYY-MM, or YYYY-MM-DD.

.PARAMETER Move
When true, move files instead of copying them.

.PARAMETER Recurse
When true, scan subdirectories recursively.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [string]$DestinationPath = "",

    [ValidateSet('YYYY/YYYY-MM-DD','YYYY/YYYY-MM','YYYY-MM-DD')]
    [string]$Structure = 'YYYY/YYYY-MM-DD',

    [bool]$Move    = $false,
    [bool]$Recurse = $false
)

try {
    $srcDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourcePath)
    if (-not (Test-Path -LiteralPath $srcDir)) {
        return @{ error = "Source directory not found: $srcDir" } | ConvertTo-Json -Compress
    }

    $dstRoot = if ($DestinationPath) {
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    } else { $srcDir }

    $imageExts = @('jpg','jpeg','png','heic','gif','bmp','tiff','tif','raw','cr2','nef','arw')

    $getArgs = @{ LiteralPath = $srcDir; File = $true }
    if ($Recurse) { $getArgs['Recurse'] = $true }
    $files = Get-ChildItem @getArgs | Where-Object {
        $imageExts -contains $_.Extension.TrimStart('.').ToLower()
    }

    $total = 0; $sorted = 0; $unsorted = 0; $foldersCreated = 0
    $createdFolders = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($f in $files) {
        $total++
        $date = $null

        # Try EXIF DateTaken for JPEG
        $ext = $f.Extension.TrimStart('.').ToLower()
        if ($ext -in @('jpg','jpeg')) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
                    if ($bytes[$i] -eq 0xFF -and $bytes[$i+1] -eq 0xE1) {
                        if ($i + 9 -ge $bytes.Length) { break }
                        $hdr = [System.Text.Encoding]::ASCII.GetString($bytes, $i + 4, 4)
                        if ($hdr -ne "Exif") { break }
                        $tb = $i + 10
                        $le = ($bytes[$tb] -eq 0x49 -and $bytes[$tb+1] -eq 0x49)

                        function R16s([byte[]]$b,[int]$p,[bool]$e){ if($e){[uint16]($b[$p] -bor ($b[$p+1] -shl 8))}else{[uint16](($b[$p] -shl 8) -bor $b[$p+1])} }
                        function R32s([byte[]]$b,[int]$p,[bool]$e){ if($e){[uint32]($b[$p]-bor($b[$p+1]-shl 8)-bor($b[$p+2]-shl 16)-bor($b[$p+3]-shl 24))}else{[uint32](($b[$p]-shl 24)-bor($b[$p+1]-shl 16)-bor($b[$p+2]-shl 8)-bor $b[$p+3])} }

                        $ifd0Pos = $tb + [int](R32s $bytes ($tb+4) $le)
                        if ($ifd0Pos + 2 -ge $bytes.Length) { break }
                        $ec = [int](R16s $bytes $ifd0Pos $le)
                        $pos = $ifd0Pos + 2
                        $exifPtr = 0

                        for ($e2 = 0; $e2 -lt $ec; $e2++) {
                            if ($pos + 12 -gt $bytes.Length) { break }
                            $tag = [int](R16s $bytes $pos $le)
                            if ($tag -eq 0x8769) { $exifPtr = [int](R32s $bytes ($pos+8) $le) }
                            $pos += 12
                        }

                        if ($exifPtr -gt 0) {
                            $ep = $tb + $exifPtr
                            if ($ep + 2 -lt $bytes.Length) {
                                $ec2 = [int](R16s $bytes $ep $le)
                                $pos3 = $ep + 2
                                for ($e3 = 0; $e3 -lt $ec2; $e3++) {
                                    if ($pos3 + 12 -gt $bytes.Length) { break }
                                    $tag3 = [int](R16s $bytes $pos3 $le)
                                    $cnt3 = [int](R32s $bytes ($pos3+4) $le)
                                    $dp3  = if($cnt3 -le 4){$pos3+8}else{$tb+[int](R32s $bytes ($pos3+8) $le)}
                                    if ($tag3 -eq 0x9003) {
                                        $s = @(); for($k=$dp3;$k -lt ($dp3+$cnt3-1);$k++){if($bytes[$k] -eq 0){break};$s+=[char]$bytes[$k]}
                                        $dtStr = $s -join ''
                                        try { $date = [datetime]::ParseExact($dtStr,'yyyy:MM:dd HH:mm:ss',$null) } catch {}
                                    }
                                    $pos3 += 12
                                }
                            }
                        }
                        break
                    }
                }
            } catch { }
        }

        # Fallback to file LastWriteTime
        if (-not $date) { $date = $f.LastWriteTime }

        # Compute subfolder
        $subfolder = switch ($Structure) {
            'YYYY/YYYY-MM-DD' { "$($date.ToString('yyyy'))/$($date.ToString('yyyy-MM-dd'))" }
            'YYYY/YYYY-MM'   { "$($date.ToString('yyyy'))/$($date.ToString('yyyy-MM'))" }
            'YYYY-MM-DD'     { $date.ToString('yyyy-MM-dd') }
        }

        $targetDir = Join-Path $dstRoot $subfolder
        if (-not $createdFolders.Contains($targetDir)) {
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                $foldersCreated++
            }
            $createdFolders.Add($targetDir) | Out-Null
        }

        $targetFile = Join-Path $targetDir $f.Name
        if ($Move) {
            Move-Item -LiteralPath $f.FullName -Destination $targetFile -Force
        } else {
            Copy-Item -LiteralPath $f.FullName -Destination $targetFile -Force
        }
        $sorted++
    }

    return @{
        TotalFiles     = $total
        Sorted         = $sorted
        Unsorted       = $unsorted
        FoldersCreated = $foldersCreated
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
