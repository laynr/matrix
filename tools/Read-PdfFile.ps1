<#
.SYNOPSIS
Extract text content from an unencrypted PDF file.

.PARAMETER Path
Path to the PDF file to read.
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

    $bytes  = [System.IO.File]::ReadAllBytes($resolved)
    $latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')
    $pdf    = $latin1.GetString($bytes)

    # Count pages
    $pageMatches = [regex]::Matches($pdf, '(?<=/Type\s*/Page\b)')
    $pageCount   = $pageMatches.Count

    # Extract content streams
    $streamRx  = [regex]::new('(?s)stream\r?\n(.*?)\r?\nendstream')
    $btRx      = [regex]::new('(?s)BT(.*?)ET')
    $tjRx      = [regex]::new('\(((?:[^\\()]|\\.)*)\)\s*Tj')
    $tjArrRx   = [regex]::new('\[((?:[^\[\]]|\\.)*)\]\s*TJ')
    $innerTjRx = [regex]::new('\(((?:[^\\()]|\\.)*)\)')

    function Decode-PdfString([string]$s) {
        $s = $s -replace '\\n', "`n"
        $s = $s -replace '\\r', "`r"
        $s = $s -replace '\\\(', '('
        $s = $s -replace '\\\)', ')'
        $s = $s -replace '\\\\', '\'
        return $s
    }

    $textParts = [System.Collections.Generic.List[string]]::new()

    $streamMatches = $streamRx.Matches($pdf)
    foreach ($sm in $streamMatches) {
        $streamContent = $sm.Groups[1].Value
        $btMatches = $btRx.Matches($streamContent)
        foreach ($bm in $btMatches) {
            $block = $bm.Groups[1].Value
            # Tj strings
            $tjMatches = $tjRx.Matches($block)
            foreach ($tm in $tjMatches) {
                $decoded = Decode-PdfString $tm.Groups[1].Value
                if ($decoded.Trim().Length -gt 0) { $textParts.Add($decoded) }
            }
            # TJ arrays
            $tjArrMatches = $tjArrRx.Matches($block)
            foreach ($am in $tjArrMatches) {
                $innerMatches = $innerTjRx.Matches($am.Groups[1].Value)
                $parts = @($innerMatches | ForEach-Object { Decode-PdfString $_.Groups[1].Value })
                $combined = $parts -join ''
                if ($combined.Trim().Length -gt 0) { $textParts.Add($combined) }
            }
        }
    }

    $text = $textParts -join "`n"

    if ($text.Length -eq 0) {
        return @{ error = "Could not extract text from this PDF. The file may be scanned, encrypted, or use unsupported encoding." } |
            ConvertTo-Json -Compress
    }

    return @{
        Path      = $resolved
        PageCount = $pageCount
        Text      = $text
        CharCount = $text.Length
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
