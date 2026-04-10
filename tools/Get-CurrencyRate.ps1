<#
.SYNOPSIS
Retrieve live currency exchange rates using the open.er-api.com API.

.PARAMETER BaseCurrency
The base currency code (e.g., USD, EUR, GBP). Defaults to USD.

.PARAMETER TargetCurrency
Optional target currency code. When provided, returns only the rate for that currency.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaseCurrency = "USD",

    [string]$TargetCurrency = ""
)

try {
    $url  = "https://open.er-api.com/v6/latest/$BaseCurrency"
    $data = Invoke-RestMethod -Uri $url -TimeoutSec 15 -ErrorAction Stop

    if ($data.result -ne 'success') {
        $msg = if ($data.'error-type') { $data.'error-type' } else { 'API returned non-success result' }
        return @{ error = $msg } | ConvertTo-Json -Compress
    }

    if ($TargetCurrency) {
        $target = $TargetCurrency.ToUpper()
        $rate   = $data.rates.$target
        if ($null -eq $rate) {
            return @{ error = "Currency not found: $target" } | ConvertTo-Json -Compress
        }
        return @{
            Base        = $data.base_code
            LastUpdated = $data.time_last_update_utc
            Rate        = $rate
        } | ConvertTo-Json -Depth 3 -Compress
    }

    $ratesCount = ($data.rates | Get-Member -MemberType NoteProperty).Count

    return @{
        Base          = $data.base_code
        LastUpdated   = $data.time_last_update_utc
        Rates         = $data.rates
        CurrencyCount = $ratesCount
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
