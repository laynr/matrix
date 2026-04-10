<#
.SYNOPSIS
Creates a .docx file from an array of paragraph strings using minimal OOXML.

.PARAMETER Path
Output path for the .docx file.

.PARAMETER Paragraphs
Array of paragraph text strings to write into the document.

.PARAMETER Title
Optional document title (stored as a paragraph before the body paragraphs).

.PARAMETER Overwrite
If true, overwrite an existing file. Defaults to false.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string[]]$Paragraphs,

    [string]$Title    = "",
    [bool]$Overwrite  = $false
)

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (Test-Path -LiteralPath $dst) {
        if ($Overwrite) { Remove-Item -LiteralPath $dst -Force }
        else { return @{ error = "File already exists. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress }
    }

    function Escape-Xml([string]$s) {
        $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
    }

    # Build paragraph XML elements
    $allParas = @()
    if ($Title) { $allParas += $Title }
    $allParas += $Paragraphs

    $paraXml = ($allParas | ForEach-Object {
        $t = Escape-Xml $_
        "<w:p><w:r><w:t xml:space=`"preserve`">$t</w:t></w:r></w:p>"
    }) -join ""

    $contentTypes = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
'@

    $rootRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'@

    $documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$paraXml<w:sectPr/></w:body>
</w:document>
"@

    $wordRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>
'@

    $entries = @{
        "[Content_Types].xml"          = $contentTypes
        "_rels/.rels"                  = $rootRels
        "word/document.xml"            = $documentXml
        "word/_rels/document.xml.rels" = $wordRels
    }

    $enc    = [System.Text.Encoding]::UTF8
    $stream  = [System.IO.File]::Open($dst, [System.IO.FileMode]::Create)
    $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
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
        $stream.Dispose()
    }

    $size = (Get-Item -LiteralPath $dst).Length

    return @{
        Path           = $dst
        ParagraphCount = $allParas.Count
        SizeBytes      = $size
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
