<#
.SYNOPSIS
Finds all regex matches in text and returns match values, positions, and named capture groups.

.PARAMETER Pattern
Regular expression pattern to search for.

.PARAMETER InputText
The text to search within.

.PARAMETER Multiline
If true, enables multiline mode where ^ and $ match line boundaries. Defaults to false.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Pattern,

    [Parameter(Mandatory)]
    [string]$InputText,

    [bool]$Multiline = $false
)

try {
    $opts = [System.Text.RegularExpressions.RegexOptions]::None
    if ($Multiline) {
        $opts = [System.Text.RegularExpressions.RegexOptions]::Multiline
    }

    $regex   = [System.Text.RegularExpressions.Regex]::new($Pattern, $opts)
    $matches = $regex.Matches($InputText)

    $results = @($matches | ForEach-Object {
        $m = $_
        # Collect named groups (skip numeric-named groups which are always present)
        $groups = @{}
        foreach ($gName in $regex.GetGroupNames()) {
            if ($gName -match '^\d+$') { continue }
            $g = $m.Groups[$gName]
            if ($g.Success) {
                $groups[$gName] = $g.Value
            }
        }
        @{
            Index  = $m.Index
            Length = $m.Length
            Value  = $m.Value
            Groups = $groups
        }
    })

    return @{
        MatchCount = $results.Count
        Pattern    = $Pattern
        Matches    = $results
    } | ConvertTo-Json -Depth 4 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
