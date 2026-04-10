<#
.SYNOPSIS
Create a simple text-based PDF file from an array of lines.

.PARAMETER Path
Destination path for the new PDF file.

.PARAMETER Lines
Array of text lines to write into the PDF.

.PARAMETER Title
Optional document title string embedded in the PDF info dictionary.

.PARAMETER FontSize
Font size in points (default 12).

.PARAMETER Overwrite
When true, overwrite an existing file at Path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string[]]$Lines,

    [string]$Title     = "",
    [int]$FontSize     = 12,
    [bool]$Overwrite   = $false
)

try {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (Test-Path -LiteralPath $resolved) {
        if ($Overwrite) { Remove-Item -LiteralPath $resolved -Force }
        else { return @{ error = "File already exists: $resolved. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress }
    }

    $parentDir = Split-Path $resolved -Parent
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    function Escape-Pdf([string]$s) {
        $s -replace '\\','\\' -replace '\(', '\(' -replace '\)', '\)'
    }

    $lineHeight = $FontSize + 4
    $pageHeight = 792
    $topY       = 720
    $bottomY    = 72
    $leftX      = 72

    # Chunk lines into pages
    $linesPerPage = [Math]::Floor(($topY - $bottomY) / $lineHeight)
    if ($linesPerPage -lt 1) { $linesPerPage = 1 }

    $pages = [System.Collections.Generic.List[object]]::new()
    $i = 0
    while ($i -lt $Lines.Count) {
        $pageLines = @($Lines[$i..([Math]::Min($i + $linesPerPage - 1, $Lines.Count - 1))])
        $pages.Add($pageLines)
        $i += $linesPerPage
    }
    if ($pages.Count -eq 0) { $pages.Add(@()) }

    $pageCount = $pages.Count

    # Build PDF content as a list of object strings; track byte offsets
    $sb      = [System.Text.StringBuilder]::new()
    $offsets = @{}

    function AppendLine([string]$s) { $sb.AppendLine($s) | Out-Null }
    function AppendRaw([string]$s)  { $sb.Append($s)     | Out-Null }

    # PDF header (Latin-1 safe)
    AppendLine "%PDF-1.4"
    AppendLine "% Matrix PDF Writer"

    # Object numbering:
    # 1 = Catalog
    # 2 = Pages
    # 3 = Font (Helvetica)
    # 4, 5, 6, ... = Page + ContentStream pairs (2 objects per page)
    # Info object appended at end before xref

    $firstPageObj = 4

    # Collect page kid refs and content stream lengths
    $pageKids      = @()
    $pageObjs      = @()  # list of [pageObjNum, streamObjNum, streamContent]

    $objNum = $firstPageObj
    foreach ($pg in $pages) {
        $pageObjNum   = $objNum
        $streamObjNum = $objNum + 1
        $objNum      += 2

        # Build content stream
        $streamSb = [System.Text.StringBuilder]::new()
        $streamSb.AppendLine("BT") | Out-Null
        $streamSb.AppendLine("/F1 $FontSize Tf") | Out-Null
        $streamSb.AppendLine("$leftX $topY Td")  | Out-Null
        $streamSb.AppendLine("$lineHeight TL")    | Out-Null
        foreach ($line in $pg) {
            $esc = Escape-Pdf $line
            $streamSb.AppendLine("($esc) Tj T*") | Out-Null
        }
        $streamSb.AppendLine("ET") | Out-Null
        $streamContent = $streamSb.ToString()

        $pageKids += "$pageObjNum 0 R"
        $pageObjs += @{ Page = $pageObjNum; Stream = $streamObjNum; Content = $streamContent }
    }

    $infoObjNum  = $objNum
    $xrefObjNum  = $objNum + 1   # total objects + 1 for 0-entry

    $kidsList = $pageKids -join " "

    # --- Obj 1: Catalog ---
    $offsets[1] = $sb.Length
    AppendLine "1 0 obj"
    AppendLine "<< /Type /Catalog /Pages 2 0 R >>"
    AppendLine "endobj"

    # --- Obj 2: Pages ---
    $offsets[2] = $sb.Length
    AppendLine "2 0 obj"
    AppendLine "<< /Type /Pages /Kids [$kidsList] /Count $pageCount >>"
    AppendLine "endobj"

    # --- Obj 3: Font ---
    $offsets[3] = $sb.Length
    AppendLine "3 0 obj"
    AppendLine "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    AppendLine "endobj"

    # --- Page + Stream pairs ---
    foreach ($pg in $pageObjs) {
        $streamBytes = [System.Text.Encoding]::Latin1.GetByteCount($pg.Content)

        $offsets[$pg.Page] = $sb.Length
        AppendLine "$($pg.Page) 0 obj"
        AppendLine "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 $pageHeight]"
        AppendLine "   /Contents $($pg.Stream) 0 R /Resources << /Font << /F1 3 0 R >> >> >>"
        AppendLine "endobj"

        $offsets[$pg.Stream] = $sb.Length
        AppendLine "$($pg.Stream) 0 obj"
        AppendLine "<< /Length $streamBytes >>"
        AppendLine "stream"
        AppendRaw  $pg.Content
        AppendLine "endstream"
        AppendLine "endobj"
    }

    # --- Info object ---
    $titleEsc = Escape-Pdf $Title
    $offsets[$infoObjNum] = $sb.Length
    AppendLine "$infoObjNum 0 obj"
    AppendLine "<< /Title ($titleEsc) /Creator (Matrix Agent) >>"
    AppendLine "endobj"

    # --- xref table ---
    $xrefOffset = $sb.Length
    $totalObjs  = $infoObjNum + 1   # objects 1..$infoObjNum

    AppendLine "xref"
    AppendLine "0 $totalObjs"
    AppendLine "0000000000 65535 f "   # free entry 0

    for ($n = 1; $n -lt $totalObjs; $n++) {
        $off = $offsets[$n]
        AppendLine ("{0:D10} 00000 n " -f $off)
    }

    AppendLine "trailer"
    AppendLine "<< /Size $totalObjs /Root 1 0 R /Info $infoObjNum 0 R >>"
    AppendLine "startxref"
    AppendLine "$xrefOffset"
    AppendRaw  "%%EOF"

    $pdfText = $sb.ToString()
    [System.IO.File]::WriteAllText($resolved, $pdfText, [System.Text.Encoding]::Latin1)

    $size = (Get-Item -LiteralPath $resolved).Length

    return @{
        Path      = $resolved
        PageCount = $pageCount
        LineCount = $Lines.Count
        SizeBytes = $size
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
