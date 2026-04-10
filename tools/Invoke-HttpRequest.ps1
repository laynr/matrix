<#
.SYNOPSIS
Performs an HTTP request and returns the status code, headers, and body.

.PARAMETER Uri
The URL to request.

.PARAMETER Method
HTTP method: GET, POST, PUT, PATCH, DELETE, HEAD. Defaults to GET.

.PARAMETER Headers
Optional hashtable of additional request headers.

.PARAMETER Body
Optional request body string.

.PARAMETER ContentType
Content-Type header for requests with a body. Defaults to application/json.

.PARAMETER AuthType
Authentication type: Bearer, Basic, or None. Defaults to None.

.PARAMETER Token
Bearer token — used when AuthType is Bearer.

.PARAMETER Username
Username — used when AuthType is Basic.

.PARAMETER Password
Password — used when AuthType is Basic.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Uri,

    [string]$Method      = "GET",
    [hashtable]$Headers  = @{},
    [string]$Body        = "",
    [string]$ContentType = "application/json",
    [string]$AuthType    = "None",
    [string]$Token       = "",
    [string]$Username    = "",
    [string]$Password    = ""
)

try {
    $hdrs = @{}
    foreach ($k in $Headers.Keys) { $hdrs[$k] = $Headers[$k] }

    switch ($AuthType) {
        "Bearer" {
            if ([string]::IsNullOrWhiteSpace($Token)) {
                return @{ error = "AuthType Bearer requires Token parameter." } | ConvertTo-Json -Compress
            }
            $hdrs["Authorization"] = "Bearer $Token"
        }
        "Basic" {
            if ([string]::IsNullOrWhiteSpace($Username)) {
                return @{ error = "AuthType Basic requires Username and Password parameters." } | ConvertTo-Json -Compress
            }
            $pair   = [System.Text.Encoding]::UTF8.GetBytes("${Username}:${Password}")
            $b64    = [Convert]::ToBase64String($pair)
            $hdrs["Authorization"] = "Basic $b64"
        }
    }

    $params = @{
        Uri             = $Uri
        Method          = $Method
        Headers         = $hdrs
        TimeoutSec      = 15
        UseBasicParsing = $true
        ErrorAction     = "Stop"
    }

    if ($Body -and $Method -notin @("GET","HEAD","DELETE")) {
        $params["Body"]        = $Body
        $params["ContentType"] = $ContentType
    }

    # PS 7+: skip throwing on 4xx/5xx so we can return the status
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $params["SkipHttpErrorCheck"] = $true
    }

    $resp = Invoke-WebRequest @params

    $respHeaders = @{}
    foreach ($k in $resp.Headers.Keys) {
        $v = $resp.Headers[$k]
        $respHeaders[$k] = if ($v -is [System.Collections.Generic.List[string]]) { $v -join ", " } else { "$v" }
    }

    $ct = if ($resp.Headers["Content-Type"]) { ($resp.Headers["Content-Type"] | Select-Object -First 1) } else { "" }

    return @{
        StatusCode   = [int]$resp.StatusCode
        ContentType  = "$ct"
        Content      = $resp.Content
        Headers      = $respHeaders
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    $sc = $null
    if ($_.Exception.Response) { $sc = [int]$_.Exception.Response.StatusCode }
    return @{
        error      = $_.Exception.Message
        StatusCode = $sc
    } | ConvertTo-Json -Depth 3 -Compress
}
