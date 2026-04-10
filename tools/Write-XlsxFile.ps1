<#
.SYNOPSIS
Writes an array of objects to a .xlsx spreadsheet using minimal OOXML.

.PARAMETER Path
Output path for the .xlsx file.

.PARAMETER Data
Array of objects or hashtables to write. Column headers are derived from property names.

.PARAMETER SheetName
Name for the worksheet. Defaults to Sheet1.

.PARAMETER Overwrite
If true, overwrite an existing file. Defaults to false.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [object[]]$Data,

    [string]$SheetName = "Sheet1",
    [bool]$Overwrite   = $false
)

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (Test-Path -LiteralPath $dst) {
        if ($Overwrite) { Remove-Item -LiteralPath $dst -Force }
        else { return @{ error = "File already exists. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress }
    }

    if ($Data.Count -eq 0) {
        return @{ error = "Data array is empty." } | ConvertTo-Json -Compress
    }

    function Escape-Xml([string]$s) {
        $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
    }

    function Col-Letter([int]$n) {
        # 1-based column index to Excel letter (A=1, Z=26, AA=27, ...)
        $result = ""
        while ($n -gt 0) {
            $n--
            $result = [char](65 + ($n % 26)) + $result
            $n = [math]::Floor($n / 26)
        }
        return $result
    }

    # Extract headers from first item
    $first = $Data[0]
    $headers = if ($first -is [hashtable] -or $first -is [System.Collections.IDictionary]) {
        @($first.Keys)
    } else {
        @($first.PSObject.Properties.Name)
    }

    # Build shared strings table
    $ssIndex  = @{}
    $ssList   = [System.Collections.Generic.List[string]]::new()

    function Add-SS([string]$s) {
        if (-not $ssIndex.ContainsKey($s)) {
            $ssIndex[$s] = $ssList.Count
            $ssList.Add($s)
        }
        return $ssIndex[$s]
    }

    # Pre-populate headers into shared strings
    foreach ($h in $headers) { Add-SS $h | Out-Null }

    # Build cell rows: header row + data rows
    $rowsXml = ""
    $rowNum  = 1

    # Header row
    $cells = ""
    $colIdx = 1
    foreach ($h in $headers) {
        $si  = Add-SS $h
        $ref = "$(Col-Letter $colIdx)$rowNum"
        $cells += "<c r=`"$ref`" t=`"s`"><v>$si</v></c>"
        $colIdx++
    }
    $rowsXml += "<row r=`"$rowNum`">$cells</row>"
    $rowNum++

    # Data rows
    foreach ($item in $Data) {
        $cells  = ""
        $colIdx = 1
        foreach ($h in $headers) {
            $val = if ($item -is [hashtable] -or $item -is [System.Collections.IDictionary]) {
                "$($item[$h])"
            } else {
                "$($item.$h)"
            }
            $ref = "$(Col-Letter $colIdx)$rowNum"
            # Try numeric
            $numVal = $null
            if ([double]::TryParse($val, [System.Globalization.NumberStyles]::Any,
                                   [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numVal)) {
                $cells += "<c r=`"$ref`"><v>$numVal</v></c>"
            } else {
                $si     = Add-SS $val
                $cells += "<c r=`"$ref`" t=`"s`"><v>$si</v></c>"
            }
            $colIdx++
        }
        $rowsXml += "<row r=`"$rowNum`">$cells</row>"
        $rowNum++
    }

    $totalRows = $Data.Count
    $totalCols = $headers.Count
    $lastRef   = "$(Col-Letter $totalCols)$($totalRows + 1)"

    # Shared strings XML
    $ssXmlItems = ($ssList | ForEach-Object { "<si><t>$(Escape-Xml $_)</t></si>" }) -join ""
    $ssCount    = $ssList.Count
    $sharedStringsXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="$ssCount" uniqueCount="$ssCount">$ssXmlItems</sst>
"@

    $sheetNameSafe = Escape-Xml $SheetName

    $contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
"@

    $rootRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@

    $workbookXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="$sheetNameSafe" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"@

    $workbookRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
'@

    $stylesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
  <borders><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>
'@

    $sheetXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>$rowsXml</sheetData>
</worksheet>
"@

    $entries = @{
        "[Content_Types].xml"              = $contentTypes
        "_rels/.rels"                      = $rootRels
        "xl/workbook.xml"                  = $workbookXml
        "xl/_rels/workbook.xml.rels"       = $workbookRels
        "xl/worksheets/sheet1.xml"         = $sheetXml
        "xl/sharedStrings.xml"             = $sharedStringsXml
        "xl/styles.xml"                    = $stylesXml
    }

    $enc     = [System.Text.Encoding]::UTF8
    $fstream = [System.IO.File]::Open($dst, [System.IO.FileMode]::Create)
    $archive = [System.IO.Compression.ZipArchive]::new($fstream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $entries.Keys) {
            $entry  = $archive.CreateEntry($name)
            $es     = $entry.Open()
            $bytes  = $enc.GetBytes($entries[$name])
            $es.Write($bytes, 0, $bytes.Length)
            $es.Dispose()
        }
    } finally {
        $archive.Dispose()
        $fstream.Dispose()
    }

    $size = (Get-Item -LiteralPath $dst).Length

    return @{
        Path        = $dst
        SheetName   = $SheetName
        RowCount    = $totalRows
        ColumnCount = $totalCols
        SizeBytes   = $size
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
