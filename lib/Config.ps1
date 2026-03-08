function Load-Config {
    $configPath = Join-Path $PSScriptRoot "..\config.json"
    if (Test-Path $configPath) {
        try {
            $jsonItems = @(Get-Content $configPath -Raw | ConvertFrom-Json)
            $json = $jsonItems[0]
            return @{
                Provider     = $json.Provider
                Model        = $json.Model
                ApiKey       = $json.ApiKey
                SystemPrompt = $json.SystemPrompt
                Endpoint     = $json.Endpoint
            }
        } catch {
            Write-Warning "Failed to parse config.json. Using defaults. $_"
        }
    }
    
    return @{
        Provider     = "Anthropic"
        Model        = "claude-3-5-sonnet-20241022"
        ApiKey       = ""
        SystemPrompt = "You are Matrix, an intelligent AI assistant. Use your tools and skills natively for maximum effectiveness. You are compatible with Claude Code plugins."
        Endpoint     = "https://api.anthropic.com/v1/messages"
    }
}

function Save-Config {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )
    $configPath = Join-Path $PSScriptRoot "..\config.json"
    $Config | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
}
