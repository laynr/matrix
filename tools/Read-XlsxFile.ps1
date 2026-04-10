<#
.SYNOPSIS
Reads data from a .xlsx spreadsheet sheet and returns rows as structured objects.

.PARAMETER Path
Path to the .xlsx file to read.

.PARAMETER SheetIndex
Zero-based index of the sheet to read. Defaults to 0 (first sheet).

.PARAMETER SheetName
Name of the sheet to read. Overrides SheetIndex when provided.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [int]$SheetIndex    = 0,
    [string]$SheetName  = ""
)

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
    }

    function Read-ZipEntry([System.IO.Compression.ZipArchive]$zip, [string]$entryName) {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8)
        $text   = $reader.ReadToEnd()
        $reader.Dispose()
        return $text
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        # Parse workbook to get sheet list
        $wbXml = Read-ZipEntry $zip "xl/workbook.xml"
        if (-not $wbXml) { return @{ error = "Not a valid .xlsx — xl/workbook.xml not found." } | ConvertTo-Json -Compress }

        [xml]$wb  = $wbXml
        $wbNs     = [System.Xml.XmlNamespaceManager]::new($wb.NameTable)
        $wbNs.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        $wbNs.AddNamespace("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
        $sheets   = @($wb.SelectNodes("//x:sheet", $wbNs))

        if ($sheets.Count -eq 0) { return @{ error = "No sheets found in workbook." } | ConvertTo-Json -Compress }

        # Resolve target sheet
        $targetSheet = $null
        if ($SheetName) {
            $targetSheet = $sheets | Where-Object { $_.GetAttribute("name") -eq $SheetName } | Select-Object -First 1
            if (-not $targetSheet) { return @{ error = "Sheet '$SheetName' not found." } | ConvertTo-Json -Compress }
        } else {
            if ($SheetIndex -ge $sheets.Count) { return @{ error = "SheetIndex $SheetIndex out of range (0–$($sheets.Count-1))." } | ConvertTo-Json -Compress }
            $targetSheet = $sheets[$SheetIndex]
        }
        $resolvedSheetName = $targetSheet.GetAttribute("name")
        $sheetId = ($sheets.IndexOf($targetSheet)) + 1

        # Read shared strings (may not exist)
        $sharedStrings = @()
        $ssXml = Read-ZipEntry $zip "xl/sharedStrings.xml"
        if ($ssXml) {
            [xml]$ss   = $ssXml
            $ssNs      = [System.Xml.XmlNamespaceManager]::new($ss.NameTable)
            $ssNs.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
            $siNodes   = $ss.SelectNodes("//x:si", $ssNs)
            $sharedStrings = @($siNodes | ForEach-Object {
                ($_.SelectNodes(".//x:t", $ssNs) | ForEach-Object { $_.InnerText }) -join ""
            })
        }

        # Read the sheet XML
        $sheetXml = Read-ZipEntry $zip "xl/worksheets/sheet$sheetId.xml"
        if (-not $sheetXml) { return @{ error = "Could not read worksheet data for sheet index $sheetId." } | ConvertTo-Json -Compress }

        [xml]$sheet = $sheetXml
        $shNs = [System.Xml.XmlNamespaceManager]::new($sheet.NameTable)
        $shNs.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

        $rowNodes = @($sheet.SelectNodes("//x:row", $shNs))

        function Get-ColLetter([string]$ref) {
            ($ref -replace '\d+', '')
        }
        function Get-CellValue([System.Xml.XmlElement]$cell) {
            $t  = $cell.GetAttribute("t")
            $vNode = $cell.SelectSingleNode("x:v", $shNs)
            if (-not $vNode) { return "" }
            $v = $vNode.InnerText
            if ($t -eq "s" -and $sharedStrings.Count -gt 0) {
                $idx = [int]$v
                if ($idx -lt $sharedStrings.Count) { return $sharedStrings[$idx] }
                return $v
            }
            if ($t -eq "inlineStr") {
                $is = $cell.SelectSingleNode("x:is/x:t", $shNs)
                return if ($is) { $is.InnerText } else { "" }
            }
            return $v
        }

        # Parse rows into array of column→value hashtables
        $rows = @()
        foreach ($row in $rowNodes) {
            $cells = @($row.SelectNodes("x:c", $shNs))
            $rowHt = @{}
            foreach ($cell in $cells) {
                $ref = $cell.GetAttribute("r")
                $col = Get-ColLetter $ref
                $rowHt[$col] = Get-CellValue $cell
            }
            if ($rowHt.Count -gt 0) { $rows += $rowHt }
        }

        $maxCols = if ($rows.Count -gt 0) { ($rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum } else { 0 }

    } finally {
        $zip.Dispose()
    }

    return @{
        SheetName   = $resolvedSheetName
        RowCount    = $rows.Count
        ColumnCount = $maxCols
        Rows        = @($rows)
    } | ConvertTo-Json -Depth 4 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
