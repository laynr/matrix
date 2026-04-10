<#
.SYNOPSIS
Find image files matching EXIF date or GPS coordinate criteria within a directory.

.PARAMETER Path
Directory to search for images.

.PARAMETER After
Optional ISO 8601 date string; return only images taken after this date.

.PARAMETER Before
Optional ISO 8601 date string; return only images taken before this date.

.PARAMETER LatMin
Optional minimum GPS latitude (decimal degrees) for filtering.

.PARAMETER LatMax
Optional maximum GPS latitude (decimal degrees) for filtering.

.PARAMETER LonMin
Optional minimum GPS longitude (decimal degrees) for filtering.

.PARAMETER LonMax
Optional maximum GPS longitude (decimal degrees) for filtering.

.PARAMETER Extensions
Comma-separated list of file extensions to scan (default: jpg,jpeg,png,heic).

.PARAMETER Recurse
When true, scan subdirectories recursively.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$After      = "",
    [string]$Before     = "",
    [float]$LatMin      = [float]::NaN,
    [float]$LatMax      = [float]::NaN,
    [float]$LonMin      = [float]::NaN,
    [float]$LonMax      = [float]::NaN,
    [string]$Extensions = "jpg,jpeg,png,heic",
    [bool]$Recurse      = $false
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "Directory not found: $resolved" } | ConvertTo-Json -Compress
    }
    if (-not (Get-Item -LiteralPath $resolved).PSIsContainer) {
        return @{ error = "Path is not a directory: $resolved" } | ConvertTo-Json -Compress
    }

    $extList = $Extensions -split ',' | ForEach-Object { $_.Trim().TrimStart('.').ToLower() }

    $afterDt  = $null; $beforeDt = $null
    if ($After)  { $afterDt  = [datetime]::Parse($After,  [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Before) { $beforeDt = [datetime]::Parse($Before, [System.Globalization.CultureInfo]::InvariantCulture) }

    $useLatMin = -not [float]::IsNaN($LatMin)
    $useLatMax = -not [float]::IsNaN($LatMax)
    $useLonMin = -not [float]::IsNaN($LonMin)
    $useLonMax = -not [float]::IsNaN($LonMax)

    $getFilesArgs = @{ LiteralPath = $resolved; File = $true }
    if ($Recurse) { $getFilesArgs['Recurse'] = $true }
    $allFiles = Get-ChildItem @getFilesArgs | Where-Object {
        $extList -contains $_.Extension.TrimStart('.').ToLower()
    }

    $scanned = 0
    $matched = [System.Collections.Generic.List[object]]::new()

    foreach ($f in $allFiles) {
        $scanned++

        # Inline EXIF read (simplified — date only from ASCII tag)
        $dateTaken  = $null
        $gpsLat     = $null
        $gpsLon     = $null
        $ext = $f.Extension.TrimStart('.').ToLower()

        if ($ext -in @('jpg','jpeg')) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                # Find APP1
                for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
                    if ($bytes[$i] -eq 0xFF -and $bytes[$i+1] -eq 0xE1) {
                        if ($i + 9 -ge $bytes.Length) { break }
                        $hdr = [System.Text.Encoding]::ASCII.GetString($bytes, $i + 4, 4)
                        if ($hdr -ne "Exif") { break }
                        $tb  = $i + 10
                        $le  = ($bytes[$tb] -eq 0x49 -and $bytes[$tb+1] -eq 0x49)

                        function R16([byte[]]$b,[int]$p,[bool]$e){ if($e){[uint16]($b[$p] -bor ($b[$p+1] -shl 8))}else{[uint16](($b[$p] -shl 8) -bor $b[$p+1])} }
                        function R32([byte[]]$b,[int]$p,[bool]$e){ if($e){[uint32]($b[$p]-bor($b[$p+1]-shl 8)-bor($b[$p+2]-shl 16)-bor($b[$p+3]-shl 24))}else{[uint32](($b[$p]-shl 24)-bor($b[$p+1]-shl 16)-bor($b[$p+2]-shl 8)-bor $b[$p+3])} }

                        $ifd0Pos = $tb + [int](R32 $bytes ($tb+4) $le)
                        if ($ifd0Pos + 2 -ge $bytes.Length) { break }
                        $ec = [int](R16 $bytes $ifd0Pos $le)
                        $pos2 = $ifd0Pos + 2
                        $exifPtr = 0; $gpsPtr = 0

                        for ($e2 = 0; $e2 -lt $ec; $e2++) {
                            if ($pos2 + 12 -gt $bytes.Length) { break }
                            $tag   = [int](R16 $bytes $pos2 $le)
                            $type  = [int](R16 $bytes ($pos2+2) $le)
                            $cnt   = [int](R32 $bytes ($pos2+4) $le)
                            $bs    = switch($type){1{1}2{1}3{2}4{4}5{8}default{1}}
                            $dp    = if(($bs*$cnt) -le 4){$pos2+8}else{$tb+[int](R32 $bytes ($pos2+8) $le)}
                            if ($tag -eq 0x8769) { $exifPtr = [int](R32 $bytes ($pos2+8) $le) }
                            if ($tag -eq 0x8825) { $gpsPtr  = [int](R32 $bytes ($pos2+8) $le) }
                            $pos2 += 12
                        }

                        if ($exifPtr -gt 0) {
                            $ep = $tb + $exifPtr
                            if ($ep + 2 -lt $bytes.Length) {
                                $ec2 = [int](R16 $bytes $ep $le)
                                $pos3 = $ep + 2
                                for ($e3 = 0; $e3 -lt $ec2; $e3++) {
                                    if ($pos3 + 12 -gt $bytes.Length) { break }
                                    $tag3 = [int](R16 $bytes $pos3 $le)
                                    $cnt3 = [int](R32 $bytes ($pos3+4) $le)
                                    $dp3  = if($cnt3 -le 4){$pos3+8}else{$tb+[int](R32 $bytes ($pos3+8) $le)}
                                    if ($tag3 -eq 0x9003) {
                                        $s = @(); for($k=$dp3;$k -lt ($dp3+$cnt3-1);$k++){if($bytes[$k] -eq 0){break};$s+=[char]$bytes[$k]}
                                        $dtStr = $s -join ''
                                        try { $dateTaken = [datetime]::ParseExact($dtStr, 'yyyy:MM:dd HH:mm:ss', $null) } catch {}
                                    }
                                    $pos3 += 12
                                }
                            }
                        }

                        if ($gpsPtr -gt 0) {
                            $gp = $tb + $gpsPtr
                            if ($gp + 2 -lt $bytes.Length) {
                                $gc = [int](R16 $bytes $gp $le)
                                $gpos = $gp + 2; $latRef='N'; $lonRef='E'
                                $latDp=0; $lonDp=0
                                for($ge=0;$ge -lt $gc;$ge++){
                                    if($gpos+12 -gt $bytes.Length){break}
                                    $gtag=[int](R16 $bytes $gpos $le)
                                    $gcnt=[int](R32 $bytes ($gpos+4) $le)
                                    $gdp=if($gcnt*8 -le 4){$gpos+8}else{$tb+[int](R32 $bytes ($gpos+8) $le)}
                                    if($gtag -eq 0x0001){$latRef=[char]$bytes[$gdp]}
                                    if($gtag -eq 0x0003){$lonRef=[char]$bytes[$gdp]}
                                    if($gtag -eq 0x0002){$latDp=$gdp-$tb}
                                    if($gtag -eq 0x0004){$lonDp=$gdp-$tb}
                                    $gpos+=12
                                }
                                if($latDp -gt 0){
                                    function Rat([byte[]]$b,[int]$tb2,[int]$off,[bool]$le2){$n=R32 $b ($tb2+$off) $le2;$d=R32 $b ($tb2+$off+4) $le2;if($d-eq 0){0.0}else{[double]$n/[double]$d}}
                                    $lat=[double](Rat $bytes $tb $latDp $le)+(Rat $bytes $tb ($latDp+8) $le)/60+(Rat $bytes $tb ($latDp+16) $le)/3600
                                    if($latRef -eq 'S'){$lat=-$lat}
                                    $gpsLat=[Math]::Round($lat,6)
                                }
                                if($lonDp -gt 0){
                                    $lon=[double](Rat $bytes $tb $lonDp $le)+(Rat $bytes $tb ($lonDp+8) $le)/60+(Rat $bytes $tb ($lonDp+16) $le)/3600
                                    if($lonRef -eq 'W'){$lon=-$lon}
                                    $gpsLon=[Math]::Round($lon,6)
                                }
                            }
                        }
                        break
                    }
                }
            } catch { }
        }

        # Apply filters
        if ($afterDt  -and $dateTaken  -and $dateTaken  -le $afterDt)  { continue }
        if ($beforeDt -and $dateTaken  -and $dateTaken  -ge $beforeDt) { continue }
        if ($useLatMin -and $gpsLat -ne $null -and $gpsLat -lt $LatMin) { continue }
        if ($useLatMax -and $gpsLat -ne $null -and $gpsLat -gt $LatMax) { continue }
        if ($useLonMin -and $gpsLon -ne $null -and $gpsLon -lt $LonMin) { continue }
        if ($useLonMax -and $gpsLon -ne $null -and $gpsLon -gt $LonMax) { continue }

        $matched.Add(@{
            Path         = $f.FullName
            FileName     = $f.Name
            DateTaken    = if ($dateTaken) { $dateTaken.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }
            GPSLatitude  = $gpsLat
            GPSLongitude = $gpsLon
        })
    }

    # Sort by DateTaken ascending (nulls last)
    $sorted = @($matched | Sort-Object { if ($_.DateTaken) { $_.DateTaken } else { '9999' } })

    return @{
        SearchPath   = $resolved
        TotalScanned = $scanned
        MatchCount   = $sorted.Count
        Images       = $sorted
    } | ConvertTo-Json -Depth 4 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
