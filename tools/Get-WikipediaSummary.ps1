<#
.SYNOPSIS
Fetches a brief summary of a topic from Wikipedia.

.DESCRIPTION
This tool searches Wikipedia for a given topic and returns the introductory summary. Use this for general knowledge queries, definitions, or finding out who someone is.

.PARAMETER Topic
The topic or subject to look up on Wikipedia (e.g. "PowerShell", "Albert Einstein").
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Topic
)

try {
    $encodedTopic = [uri]::EscapeDataString($Topic)
    $url = "https://en.wikipedia.org/api/rest_v1/page/summary/$encodedTopic"
    
    $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    
    $result = @{
        Title = $response.title
        Description = $response.description
        Extract = $response.extract
        Url = $response.content_urls.desktop.page
    }
    
    return $result | ConvertTo-Json -Depth 5 -Compress
} catch {
    return @{ error = "Could not find a Wikipedia summary for '$Topic'. It may not exist or require different casing." } | ConvertTo-Json -Compress
}
