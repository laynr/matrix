<#
.SYNOPSIS
Organize files in a directory into subdirectories grouped by extension, date, size, or type.

.PARAMETER Path
The source directory containing files to organize.

.PARAMETER GroupBy
How to group files: Extension, Date, Size, or Type.

.PARAMETER DestinationPath
Root directory for organized subdirectories. Defaults to Path.

.PARAMETER Move
When true, move files instead of copying them.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidateSet('Extension','Date','Size','Type')]
    [string]$GroupBy,

    [string]$DestinationPath = "",
    [bool]$Move = $false
)

try {
    $srcDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $srcDir)) {
        return @{ error = "Directory not found: $srcDir" } | ConvertTo-Json -Compress
    }
    if (-not (Get-Item -LiteralPath $srcDir).PSIsContainer) {
        return @{ error = "Path is not a directory: $srcDir" } | ConvertTo-Json -Compress
    }

    $dstRoot = if ($DestinationPath) {
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    } else {
        $srcDir
    }

    $typeMap = @{
        Images    = 'jpg,jpeg,png,gif,bmp,tiff,tif,heic,raw,cr2,nef,arw,svg,webp' -split ','
        Documents = 'pdf,doc,docx,xls,xlsx,ppt,pptx,txt,rtf,odt,ods,odp,md,csv'  -split ','
        Audio     = 'mp3,wav,flac,aac,ogg,wma,m4a,opus'                           -split ','
        Video     = 'mp4,avi,mkv,mov,wmv,flv,m4v,webm,mpeg,mpg'                   -split ','
        Code      = 'ps1,py,js,ts,html,css,go,rs,rb,java,cpp,c,h,sh,yaml,yml,json,xml,toml' -split ','
        Archives  = 'zip,tar,gz,7z,rar,bz2,xz'                                    -split ','
    }

    $files = Get-ChildItem -LiteralPath $srcDir -File

    $groupCounts = @{}
    $processed   = 0
    $dirsCreated = 0

    foreach ($f in $files) {
        $groupName = switch ($GroupBy) {
            'Extension' {
                $ext = $f.Extension.TrimStart('.')
                if ($ext) { $ext } else { 'no-extension' }
            }
            'Date' {
                "$($f.LastWriteTime.ToString('yyyy'))/$($f.LastWriteTime.ToString('yyyy-MM'))"
            }
            'Size' {
                $len = $f.Length
                if     ($len -lt 1KB)   { 'Tiny' }
                elseif ($len -lt 1MB)   { 'Small' }
                elseif ($len -lt 100MB) { 'Medium' }
                else                    { 'Large' }
            }
            'Type' {
                $ext = $f.Extension.TrimStart('.').ToLower()
                $found = $typeMap.Keys | Where-Object { $typeMap[$_] -contains $ext } | Select-Object -First 1
                if ($found) { $found } else { 'Other' }
            }
        }

        $targetDir = Join-Path $dstRoot $groupName

        # Skip if already in destination folder
        $normalSrc = $f.DirectoryName.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        $normalDst = $targetDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        if ($normalSrc -eq $normalDst) {
            continue
        }

        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            $dirsCreated++
        }

        $targetFile = Join-Path $targetDir $f.Name
        if ($Move) {
            Move-Item -LiteralPath $f.FullName -Destination $targetFile -Force
        } else {
            Copy-Item -LiteralPath $f.FullName -Destination $targetFile -Force
        }

        $processed++
        if ($groupCounts.ContainsKey($groupName)) {
            $groupCounts[$groupName]++
        } else {
            $groupCounts[$groupName] = 1
        }
    }

    $groups = @($groupCounts.Keys | ForEach-Object {
        @{
            GroupName       = $_
            FileCount       = $groupCounts[$_]
            DestinationPath = (Join-Path $dstRoot $_)
        }
    })

    return @{
        FilesProcessed = $processed
        GroupsCreated  = $dirsCreated
        Groups         = $groups
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
