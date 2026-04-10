<#
.SYNOPSIS
Extract slide text and titles from a PowerPoint .pptx file.

.PARAMETER Path
Path to the .pptx file to read.
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
        # Read presentation.xml.rels to build r:Id → slide path map
        $relsEntry = $zip.Entries | Where-Object { $_.FullName -eq 'ppt/_rels/presentation.xml.rels' } | Select-Object -First 1
        if (-not $relsEntry) {
            return @{ error = "Not a valid .pptx — ppt/_rels/presentation.xml.rels not found." } | ConvertTo-Json -Compress
        }

        $relsReader = [System.IO.StreamReader]::new($relsEntry.Open(), [System.Text.Encoding]::UTF8)
        $relsXmlText = $relsReader.ReadToEnd()
        $relsReader.Dispose()

        [xml]$relsDoc = $relsXmlText
        $idToPath = @{}
        foreach ($rel in $relsDoc.Relationships.Relationship) {
            if ($rel.Target -match 'slides/slide') {
                # Target is relative to ppt/, normalize
                $slidePath = 'ppt/' + $rel.Target.TrimStart('/')
                $idToPath[$rel.Id] = $slidePath
            }
        }

        # Read presentation.xml to get slide order
        $presEntry = $zip.Entries | Where-Object { $_.FullName -eq 'ppt/presentation.xml' } | Select-Object -First 1
        if (-not $presEntry) {
            return @{ error = "Not a valid .pptx — ppt/presentation.xml not found." } | ConvertTo-Json -Compress
        }

        $presReader = [System.IO.StreamReader]::new($presEntry.Open(), [System.Text.Encoding]::UTF8)
        $presXmlText = $presReader.ReadToEnd()
        $presReader.Dispose()

        [xml]$presDoc = $presXmlText
        $ns = [System.Xml.XmlNamespaceManager]::new($presDoc.NameTable)
        $ns.AddNamespace('p',  'http://schemas.openxmlformats.org/presentationml/2006/main')
        $ns.AddNamespace('r',  'http://schemas.openxmlformats.org/officeDocument/2006/relationships')

        $sldIdNodes = $presDoc.SelectNodes('//p:sldId', $ns)
        $orderedIds = @($sldIdNodes | ForEach-Object { $_.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships') })

        # Parse each slide
        $slides = @()
        $slideNum = 0
        foreach ($rId in $orderedIds) {
            $slideNum++
            $slidePath = $idToPath[$rId]
            if (-not $slidePath) { continue }

            $slideEntry = $zip.Entries | Where-Object { $_.FullName -eq $slidePath } | Select-Object -First 1
            if (-not $slideEntry) { continue }

            $slideReader = [System.IO.StreamReader]::new($slideEntry.Open(), [System.Text.Encoding]::UTF8)
            $slideXmlText = $slideReader.ReadToEnd()
            $slideReader.Dispose()

            [xml]$slideDoc = $slideXmlText
            $sns = [System.Xml.XmlNamespaceManager]::new($slideDoc.NameTable)
            $sns.AddNamespace('a', 'http://schemas.openxmlformats.org/drawingml/2006/main')
            $sns.AddNamespace('p', 'http://schemas.openxmlformats.org/presentationml/2006/main')

            # Title: p:sp containing p:ph with type="title"
            $title = ''
            $spNodes = $slideDoc.SelectNodes('//p:sp', $sns)
            $bodyParts = [System.Collections.Generic.List[string]]::new()

            foreach ($sp in $spNodes) {
                $ph = $sp.SelectSingleNode('.//p:ph', $sns)
                $isTitle = ($ph -ne $null -and ($ph.GetAttribute('type') -eq 'title' -or $ph.GetAttribute('type') -eq 'ctrTitle'))
                $tNodes = $sp.SelectNodes('.//a:t', $sns)
                $text = ($tNodes | ForEach-Object { $_.InnerText }) -join ''
                if ($isTitle) {
                    $title = $text
                } else {
                    if ($text.Length -gt 0) { $bodyParts.Add($text) }
                }
            }

            $slides += @{
                SlideNumber = $slideNum
                Title       = $title
                Text        = $bodyParts -join "`n"
            }
        }

        return @{
            Path       = $resolved
            SlideCount = $slides.Count
            Slides     = $slides
        } | ConvertTo-Json -Depth 5 -Compress

    } finally {
        $zip.Dispose()
    }

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
