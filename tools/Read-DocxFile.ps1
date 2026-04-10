<#
.SYNOPSIS
Extracts text content from a .docx file, returning paragraphs and full text.

.PARAMETER Path
Path to the .docx file to read.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -LiteralPath $resolved)) {
        return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        $docEntry = $zip.Entries | Where-Object { $_.FullName -eq "word/document.xml" } | Select-Object -First 1
        if (-not $docEntry) {
            return @{ error = "Not a valid .docx — word/document.xml not found." } | ConvertTo-Json -Compress
        }
        $reader  = [System.IO.StreamReader]::new($docEntry.Open(), [System.Text.Encoding]::UTF8)
        $xmlText = $reader.ReadToEnd()
        $reader.Dispose()
    } finally {
        $zip.Dispose()
    }

    [xml]$doc = $xmlText
    $ns  = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

    $paraNodes  = $doc.SelectNodes("//w:p", $ns)
    $paragraphs = @()

    foreach ($p in $paraNodes) {
        $tNodes = $p.SelectNodes(".//w:t", $ns)
        $text   = ($tNodes | ForEach-Object { $_.InnerText }) -join ""
        if ($text.Length -gt 0) {
            $paragraphs += $text
        }
    }

    return @{
        Path           = $resolved
        ParagraphCount = $paragraphs.Count
        Text           = $paragraphs -join "`n"
        Paragraphs     = $paragraphs
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
