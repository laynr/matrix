<#
.SYNOPSIS
Fetch and parse an RSS 2.0 or Atom 1.0 feed, returning structured feed items.

.PARAMETER Url
URL of the RSS or Atom feed.

.PARAMETER MaxItems
Maximum number of items to return (default 20).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Url,

    [int]$MaxItems = 20
)

try {
    $response = Invoke-WebRequest -Uri $Url -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop

    [xml]$feed = $response.Content

    $rootName = $feed.DocumentElement.LocalName
    $format   = 'Unknown'
    $feedTitle = ''
    $items    = @()

    if ($rootName -eq 'rss') {
        $format    = 'RSS'
        $feedTitle = $feed.rss.channel.title
        $rawItems  = $feed.rss.channel.item

        foreach ($item in $rawItems) {
            if ($items.Count -ge $MaxItems) { break }
            $summary = if ($item.description) {
                $s = $item.description -replace '<[^>]+>','' # strip HTML tags
                if ($s.Length -gt 200) { $s.Substring(0,200) } else { $s }
            } else { '' }
            $items += @{
                Title     = "$($item.title)"
                Link      = "$($item.link)"
                Published = "$($item.pubDate)"
                Summary   = $summary
                Author    = "$($item.author)"
            }
        }
    } elseif ($rootName -eq 'feed') {
        $format    = 'Atom'
        $ns        = [System.Xml.XmlNamespaceManager]::new($feed.NameTable)
        $ns.AddNamespace('a', 'http://www.w3.org/2005/Atom')

        $titleNode = $feed.DocumentElement.SelectSingleNode('a:title', $ns)
        $feedTitle = if ($titleNode) { $titleNode.InnerText } else { '' }

        $entryNodes = $feed.DocumentElement.SelectNodes('a:entry', $ns)
        foreach ($entry in $entryNodes) {
            if ($items.Count -ge $MaxItems) { break }
            $titleNode2   = $entry.SelectSingleNode('a:title', $ns)
            $linkNode     = $entry.SelectSingleNode('a:link', $ns)
            $updatedNode  = $entry.SelectSingleNode('a:updated', $ns)
            $summaryNode  = $entry.SelectSingleNode('a:summary', $ns)
            $authorNode   = $entry.SelectSingleNode('a:author/a:name', $ns)

            $link = if ($linkNode) { $linkNode.GetAttribute('href') } else { '' }
            $summary = if ($summaryNode) {
                $s = $summaryNode.InnerText -replace '<[^>]+>',''
                if ($s.Length -gt 200) { $s.Substring(0,200) } else { $s }
            } else { '' }

            $items += @{
                Title     = if ($titleNode2)  { $titleNode2.InnerText  } else { '' }
                Link      = $link
                Published = if ($updatedNode) { $updatedNode.InnerText } else { '' }
                Summary   = $summary
                Author    = if ($authorNode)  { $authorNode.InnerText  } else { '' }
            }
        }
    } else {
        return @{ error = "Unrecognized feed format: root element is '$rootName'." } | ConvertTo-Json -Compress
    }

    return @{
        FeedTitle  = $feedTitle
        FeedUrl    = $Url
        Format     = $format
        ItemCount  = $items.Count
        Items      = $items
    } | ConvertTo-Json -Depth 4 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
