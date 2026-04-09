$global:MatrixMessages = @()

function Get-TokenCount {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return [math]::Ceiling($Text.Length / 3.5)
}

function Add-Message {
    param(
        [string]$Role,
        $Content
    )
    $global:MatrixMessages += @{
        role = $Role
        content = $Content
    }
}

function Get-Messages {
    return $global:MatrixMessages
}

function Clear-Messages {
    $global:MatrixMessages = @()
}

function Prune-Context {
    param([int]$MaxTokens = 100000)
    
    $totalTokens = 0
    foreach ($m in $global:MatrixMessages) {
        $contentStr = $m.content | ConvertTo-Json -Depth 5 -Compress
        $totalTokens += Get-TokenCount -Text $contentStr
    }

    if ($totalTokens -gt $MaxTokens -and $global:MatrixMessages.Count -gt 2) {
        $newMessages = @()
        $tokensToDrop = $totalTokens - $MaxTokens
        $droppedTokens = 0
        $i = 0
        while ($i -lt $global:MatrixMessages.Count) {
            if ($droppedTokens -lt $tokensToDrop -and $i -lt ($global:MatrixMessages.Count - 2)) {
                $contentStr = $global:MatrixMessages[$i].content | ConvertTo-Json -Depth 5 -Compress
                $droppedTokens += Get-TokenCount -Text $contentStr
            } else {
                $newMessages += $global:MatrixMessages[$i]
            }
            $i++
        }
        $global:MatrixMessages = $newMessages
    }
}
