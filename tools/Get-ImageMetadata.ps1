<#
.SYNOPSIS
Read EXIF metadata from a JPEG image file via pure byte parsing.

.PARAMETER Path
Path to the image file to inspect.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
    }

    $ext    = [System.IO.Path]::GetExtension($resolved).TrimStart('.').ToLower()
    $format = $ext.ToUpper()
    $bytes  = [System.IO.File]::ReadAllBytes($resolved)

    # Default result
    $result = @{
        Path         = $resolved
        Format       = $format
        Width        = $null
        Height       = $null
        Make         = $null
        Model        = $null
        DateTaken    = $null
        GPSLatitude  = $null
        GPSLongitude = $null
        GPSAltitude  = $null
        Orientation  = $null
        HasExif      = $false
    }

    # EXIF parsing only for JPEG
    if ($ext -notin @('jpg','jpeg')) {
        return $result | ConvertTo-Json -Depth 3 -Compress
    }

    # Helper: read uint16 from byte array at position with endianness
    function Read-UInt16([byte[]]$b, [int]$pos, [bool]$le) {
        if ($le) { return [uint16]($b[$pos] -bor ($b[$pos+1] -shl 8)) }
        else     { return [uint16](($b[$pos] -shl 8) -bor $b[$pos+1]) }
    }

    # Helper: read uint32
    function Read-UInt32([byte[]]$b, [int]$pos, [bool]$le) {
        if ($le) {
            return [uint32]($b[$pos] -bor ($b[$pos+1] -shl 8) -bor ($b[$pos+2] -shl 16) -bor ($b[$pos+3] -shl 24))
        } else {
            return [uint32](($b[$pos] -shl 24) -bor ($b[$pos+1] -shl 16) -bor ($b[$pos+2] -shl 8) -bor $b[$pos+3])
        }
    }

    # Helper: read null-terminated ASCII string at offset from TIFF base
    function Read-ASCII([byte[]]$b, [int]$tiffBase, [int]$offset, [int]$count) {
        $start = $tiffBase + $offset
        $end   = $start + $count - 1
        if ($end -ge $b.Length) { return '' }
        $chars = @()
        for ($k = $start; $k -lt $end; $k++) {
            if ($b[$k] -eq 0) { break }
            $chars += [char]$b[$k]
        }
        return $chars -join ''
    }

    # Helper: read rational (two uint32: numerator/denominator)
    function Read-Rational([byte[]]$b, [int]$tiffBase, [int]$offset, [bool]$le) {
        $num = Read-UInt32 $b ($tiffBase + $offset)     $le
        $den = Read-UInt32 $b ($tiffBase + $offset + 4) $le
        if ($den -eq 0) { return 0.0 }
        return [double]$num / [double]$den
    }

    # Find APP1 marker (FF E1)
    $app1Pos = -1
    for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 0xFF -and $bytes[$i+1] -eq 0xE1) {
            $app1Pos = $i
            break
        }
    }

    if ($app1Pos -lt 0) {
        return $result | ConvertTo-Json -Depth 3 -Compress
    }

    # Verify Exif\0\0 at marker+4
    if ($app1Pos + 9 -ge $bytes.Length) {
        return $result | ConvertTo-Json -Depth 3 -Compress
    }
    $exifHeader = [System.Text.Encoding]::ASCII.GetString($bytes, $app1Pos + 4, 4)
    if ($exifHeader -ne "Exif") {
        return $result | ConvertTo-Json -Depth 3 -Compress
    }

    $result.HasExif = $true
    $tiffBase = $app1Pos + 10   # position of TIFF header

    # Endianness
    $leFlag = ($bytes[$tiffBase] -eq 0x49 -and $bytes[$tiffBase+1] -eq 0x49)

    # IFD0 offset (from TIFF base)
    $ifd0Offset = [int](Read-UInt32 $bytes ($tiffBase + 4) $leFlag)
    $ifd0Pos    = $tiffBase + $ifd0Offset

    # Parse IFD entries
    function Parse-IFD([byte[]]$b, [int]$tiffBase, [int]$ifdPos, [bool]$le) {
        $tags = @{}
        if ($ifdPos + 2 -ge $b.Length) { return $tags }
        $entryCount = [int](Read-UInt16 $b $ifdPos $le)
        $pos = $ifdPos + 2
        for ($e = 0; $e -lt $entryCount; $e++) {
            if ($pos + 12 -gt $b.Length) { break }
            $tag   = [int](Read-UInt16 $b $pos $le)
            $type  = [int](Read-UInt16 $b ($pos+2) $le)
            $count = [int](Read-UInt32 $b ($pos+4) $le)
            $valOff = $pos + 8

            # Value or offset: for types that fit in 4 bytes it's inline, else it's an offset
            $byteSize = switch ($type) { 1 {1} 2 {1} 3 {2} 4 {4} 5 {8} default {1} }
            $totalSize = $byteSize * $count

            if ($totalSize -le 4) {
                $dataPos = $valOff   # inline
            } else {
                $dataPos = $tiffBase + [int](Read-UInt32 $b $valOff $le)  # pointer
            }

            $tags[$tag] = @{ Type=$type; Count=$count; DataPos=$dataPos }
            $pos += 12
        }
        return $tags
    }

    $ifd0 = Parse-IFD $bytes $tiffBase $ifd0Pos $leFlag

    # Extract IFD0 tags
    if ($ifd0.ContainsKey(0x010F)) {
        $t = $ifd0[0x010F]; $result.Make = Read-ASCII $bytes $tiffBase ($t.DataPos - $tiffBase) $t.Count
    }
    if ($ifd0.ContainsKey(0x0110)) {
        $t = $ifd0[0x0110]; $result.Model = Read-ASCII $bytes $tiffBase ($t.DataPos - $tiffBase) $t.Count
    }
    if ($ifd0.ContainsKey(0x0112)) {
        $t = $ifd0[0x0112]; $result.Orientation = [int](Read-UInt16 $bytes $t.DataPos $leFlag)
    }

    # ExifIFD
    if ($ifd0.ContainsKey(0x8769)) {
        $exifOffset = [int](Read-UInt32 $bytes $ifd0[0x8769].DataPos $leFlag)
        $exifIfd = Parse-IFD $bytes $tiffBase ($tiffBase + $exifOffset) $leFlag

        if ($exifIfd.ContainsKey(0x9003)) {
            $t = $exifIfd[0x9003]; $result.DateTaken = Read-ASCII $bytes $tiffBase ($t.DataPos - $tiffBase) $t.Count
        }
        if ($exifIfd.ContainsKey(0xA002)) {
            $t = $exifIfd[0xA002]
            $result.Width = if ($t.Type -eq 3) { [int](Read-UInt16 $bytes $t.DataPos $leFlag) } else { [int](Read-UInt32 $bytes $t.DataPos $leFlag) }
        }
        if ($exifIfd.ContainsKey(0xA003)) {
            $t = $exifIfd[0xA003]
            $result.Height = if ($t.Type -eq 3) { [int](Read-UInt16 $bytes $t.DataPos $leFlag) } else { [int](Read-UInt32 $bytes $t.DataPos $leFlag) }
        }
    }

    # GPSIFD
    if ($ifd0.ContainsKey(0x8825)) {
        $gpsOffset = [int](Read-UInt32 $bytes $ifd0[0x8825].DataPos $leFlag)
        $gpsIfd = Parse-IFD $bytes $tiffBase ($tiffBase + $gpsOffset) $leFlag

        $latRef = 'N'; $lonRef = 'E'
        if ($gpsIfd.ContainsKey(0x0001)) {
            $t = $gpsIfd[0x0001]; $latRef = Read-ASCII $bytes $tiffBase ($t.DataPos - $tiffBase) $t.Count
        }
        if ($gpsIfd.ContainsKey(0x0003)) {
            $t = $gpsIfd[0x0003]; $lonRef = Read-ASCII $bytes $tiffBase ($t.DataPos - $tiffBase) $t.Count
        }

        if ($gpsIfd.ContainsKey(0x0002)) {
            $t = $gpsIfd[0x0002]
            $dp = $t.DataPos - $tiffBase
            $deg = Read-Rational $bytes $tiffBase $dp          $leFlag
            $min = Read-Rational $bytes $tiffBase ($dp + 8)    $leFlag
            $sec = Read-Rational $bytes $tiffBase ($dp + 16)   $leFlag
            $lat = $deg + $min/60.0 + $sec/3600.0
            if ($latRef -match 'S') { $lat = -$lat }
            $result.GPSLatitude = [Math]::Round($lat, 6)
        }

        if ($gpsIfd.ContainsKey(0x0004)) {
            $t = $gpsIfd[0x0004]
            $dp = $t.DataPos - $tiffBase
            $deg = Read-Rational $bytes $tiffBase $dp         $leFlag
            $min = Read-Rational $bytes $tiffBase ($dp + 8)   $leFlag
            $sec = Read-Rational $bytes $tiffBase ($dp + 16)  $leFlag
            $lon = $deg + $min/60.0 + $sec/3600.0
            if ($lonRef -match 'W') { $lon = -$lon }
            $result.GPSLongitude = [Math]::Round($lon, 6)
        }

        if ($gpsIfd.ContainsKey(0x0006)) {
            $t = $gpsIfd[0x0006]
            $dp = $t.DataPos - $tiffBase
            $result.GPSAltitude = [Math]::Round((Read-Rational $bytes $tiffBase $dp $leFlag), 2)
        }
    }

    return $result | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
