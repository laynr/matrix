<#
.SYNOPSIS
Create a PowerPoint .pptx file with one or more text slides.

.PARAMETER Path
Destination path for the new .pptx file.

.PARAMETER Slides
Array of slides to create. Each item may be a string (used as body text) or a hashtable with Title and Content keys.

.PARAMETER Overwrite
When true, overwrite an existing file at Path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    $Slides,

    [bool]$Overwrite = $false
)

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (Test-Path -LiteralPath $resolved) {
        if ($Overwrite) { Remove-Item -LiteralPath $resolved -Force }
        else { return @{ error = "File already exists: $resolved. Set Overwrite=true to replace it." } | ConvertTo-Json -Compress }
    }

    $parentDir = Split-Path $resolved -Parent
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Normalize slides to hashtable array
    $slideList = @()
    foreach ($s in $Slides) {
        if ($s -is [string]) {
            $slideList += @{ Title = ''; Content = $s }
        } elseif ($s -is [hashtable] -or $s -is [System.Collections.IDictionary]) {
            $slideList += @{
                Title   = if ($s.ContainsKey('Title'))   { "$($s['Title'])" }   else { '' }
                Content = if ($s.ContainsKey('Content')) { "$($s['Content'])" } else { '' }
            }
        } else {
            $slideList += @{ Title = ''; Content = "$s" }
        }
    }

    $slideCount = $slideList.Count

    # ── Namespace URIs ────────────────────────────────────────────────────────
    $pkg  = 'http://schemas.openxmlformats.org/package/2006/relationships'
    $odoc = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $pml  = 'http://schemas.openxmlformats.org/presentationml/2006/main'
    $dml  = 'http://schemas.openxmlformats.org/drawingml/2006/main'

    function Xml-Escape([string]$s) {
        $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&apos;"
    }

    # ── [Content_Types].xml ───────────────────────────────────────────────────
    $slideOverrides = ($slideList | ForEach-Object -Begin { $i = 0 } -Process {
        $i++
        "  <Override PartName=""/ppt/slides/slide$i.xml"" ContentType=""application/vnd.openxmlformats-officedocument.presentationml.slide+xml""/>"
    }) -join "`n"

    $contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
$slideOverrides
</Types>
"@

    # ── _rels/.rels ───────────────────────────────────────────────────────────
    $rootRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="$pkg">
  <Relationship Id="rId1" Type="$odoc/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>
"@

    # ── ppt/_rels/presentation.xml.rels ──────────────────────────────────────
    $presRelItems = ($slideList | ForEach-Object -Begin { $i = 0 } -Process {
        $i++
        "  <Relationship Id=""rId$i"" Type=""$odoc/slide"" Target=""slides/slide$i.xml""/>"
    }) -join "`n"
    $smId = $slideCount + 1

    $presRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="$pkg">
$presRelItems
  <Relationship Id="rId$smId" Type="$odoc/slideMaster" Target="slideMasters/slideMaster1.xml"/>
</Relationships>
"@

    # ── ppt/presentation.xml ──────────────────────────────────────────────────
    $sldIdItems = ($slideList | ForEach-Object -Begin { $i = 0 } -Process {
        $i++
        $id = 255 + $i
        "    <p:sldId id=""$id"" r:id=""rId$i""/>"
    }) -join "`n"

    $presXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="$pml" xmlns:r="$odoc" xmlns:a="$dml" saveSubsetFonts="1">
  <p:sldMasterIdLst>
    <p:sldMasterId id="2147483648" r:id="rId$smId"/>
  </p:sldMasterIdLst>
  <p:sldIdLst>
$sldIdItems
  </p:sldIdLst>
  <p:sldSz cx="9144000" cy="6858000"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>
"@

    # ── ppt/slideMasters/slideMaster1.xml ────────────────────────────────────
    $slideMasterXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:p="$pml" xmlns:a="$dml" xmlns:r="$odoc">
  <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
</p:sldMaster>
"@

    # ── ppt/slideMasters/_rels/slideMaster1.xml.rels ─────────────────────────
    $slideMasterRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="$pkg">
  <Relationship Id="rId1" Type="$odoc/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>
"@

    # ── ppt/slideLayouts/slideLayout1.xml ────────────────────────────────────
    $slideLayoutXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:p="$pml" xmlns:a="$dml" xmlns:r="$odoc" type="blank">
  <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
</p:sldLayout>
"@

    # ── ppt/slideLayouts/_rels/slideLayout1.xml.rels ──────────────────────────
    $slideLayoutRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="$pkg">
  <Relationship Id="rId1" Type="$odoc/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>
"@

    # ── Build slides ──────────────────────────────────────────────────────────
    $slideXmls = @{}
    $slideRelXmls = @{}

    for ($i = 0; $i -lt $slideCount; $i++) {
        $n = $i + 1
        $sl = $slideList[$i]
        $titleEsc   = Xml-Escape $sl.Title
        $contentEsc = Xml-Escape $sl.Content

        $slideXmls["ppt/slides/slide$n.xml"] = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="$pml" xmlns:a="$dml" xmlns:r="$odoc">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="457200" y="274638"/><a:ext cx="8229600" cy="1143000"/></a:xfrm></p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$titleEsc</a:t></a:r></a:p></p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="3" name="Content"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="457200" y="1600200"/><a:ext cx="8229600" cy="4525963"/></a:xfrm></p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$contentEsc</a:t></a:r></a:p></p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>
"@

        $slideRelXmls["ppt/slides/_rels/slide$n.xml.rels"] = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="$pkg">
  <Relationship Id="rId1" Type="$odoc/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>
"@
    }

    # ── Write ZIP ─────────────────────────────────────────────────────────────
    $entries = [ordered]@{
        '[Content_Types].xml'                               = $contentTypes
        '_rels/.rels'                                       = $rootRels
        'ppt/presentation.xml'                              = $presXml
        'ppt/_rels/presentation.xml.rels'                   = $presRels
        'ppt/slideMasters/slideMaster1.xml'                 = $slideMasterXml
        'ppt/slideMasters/_rels/slideMaster1.xml.rels'      = $slideMasterRels
        'ppt/slideLayouts/slideLayout1.xml'                 = $slideLayoutXml
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels'      = $slideLayoutRels
    }
    foreach ($key in $slideXmls.Keys)    { $entries[$key] = $slideXmls[$key] }
    foreach ($key in $slideRelXmls.Keys) { $entries[$key] = $slideRelXmls[$key] }

    $enc     = [System.Text.Encoding]::UTF8
    $fstream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::Create)
    $archive = [System.IO.Compression.ZipArchive]::new($fstream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $entries.Keys) {
            $entry = $archive.CreateEntry($name)
            $es    = $entry.Open()
            $bytes = $enc.GetBytes($entries[$name])
            $es.Write($bytes, 0, $bytes.Length)
            $es.Dispose()
        }
    } finally {
        $archive.Dispose()
        $fstream.Dispose()
    }

    $size = (Get-Item -LiteralPath $resolved).Length

    return @{
        Path       = $resolved
        SlideCount = $slideCount
        SizeBytes  = $size
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
