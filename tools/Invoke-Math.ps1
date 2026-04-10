<#
.SYNOPSIS
Evaluates a mathematical expression and returns the result.

.DESCRIPTION
This tool safely evaluates standardized mathematical expressions (e.g. "250 * 14", "100 / 4 + 7") and returns the numerical result. Use this whenever calculations are required.

.PARAMETER Expression
The mathematical expression to evaluate (e.g. "2 + 2", "10 * (3 + 2)", "sqrt(144)").
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Expression
)

try {
    # Basic sanitization
    $cleanExp = $Expression -replace '[^0-9\+\-\*\/\(\)\.]', ''
    if ([string]::IsNullOrWhiteSpace($cleanExp)) { throw "Invalid expression" }
    
    $dt = New-Object System.Data.DataTable
    $resultValue = $dt.Compute($cleanExp, "")
    
    $result = @{
        Expression = $Expression
        Result = $resultValue
    }
    return $result | ConvertTo-Json -Depth 3 -Compress
} catch {
    return @{ error = "Failed to evaluate math expression: $($_.Exception.Message)" } | ConvertTo-Json -Compress
}
