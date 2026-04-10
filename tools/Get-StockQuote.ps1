<#
.SYNOPSIS
Retrieve a real-time stock quote from Yahoo Finance for a given ticker symbol.

.PARAMETER Symbol
The stock ticker symbol (e.g., MSFT, AAPL, GOOG).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Symbol
)

try {
    $url      = "https://query1.finance.yahoo.com/v8/finance/chart/$($Symbol.ToUpper())?interval=1d&range=1d"
    $response = Invoke-WebRequest -Uri $url `
        -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' } `
        -TimeoutSec 15 `
        -UseBasicParsing `
        -SkipHttpErrorCheck `
        -ErrorAction Stop

    $data = $response.Content | ConvertFrom-Json

    if ($data.chart.error) {
        return @{ error = "$($data.chart.error.description)" } | ConvertTo-Json -Compress
    }

    $result = $data.chart.result
    if (-not $result -or $result.Count -eq 0) {
        return @{ error = "No data returned for symbol: $Symbol" } | ConvertTo-Json -Compress
    }

    $meta           = $result[0].meta
    $price          = $meta.regularMarketPrice
    $prevClose      = $meta.previousClose
    $change         = if ($price -and $prevClose) { [Math]::Round($price - $prevClose, 4) } else { $null }
    $changePct      = if ($price -and $prevClose -and $prevClose -ne 0) { [Math]::Round(($price - $prevClose) / $prevClose * 100, 2) } else { $null }

    return @{
        Symbol        = $Symbol.ToUpper()
        ShortName     = "$($meta.shortName)"
        Price         = $price
        PreviousClose = $prevClose
        Change        = $change
        ChangePercent = $changePct
        Currency      = "$($meta.currency)"
        Exchange      = "$($meta.exchangeName)"
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
