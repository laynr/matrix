<#
.SYNOPSIS
Reads X.509 certificate details from a file (.pem, .crt, .pfx) or a live HTTPS URL.

.PARAMETER Path
Path to a certificate file (.pem, .crt, or .pfx).

.PARAMETER Url
HTTPS URL to retrieve the server certificate from.

.PARAMETER Password
Optional password for .pfx files.
#>
[CmdletBinding()]
param(
    [string]$Path     = "",
    [string]$Url      = "",
    [string]$Password = ""
)

try {
    if ($Path -and $Url) {
        return @{ error = "Provide either Path or Url, not both." } | ConvertTo-Json -Compress
    }
    if (-not $Path -and -not $Url) {
        return @{ error = "Provide either Path or Url." } | ConvertTo-Json -Compress
    }

    $cert = $null

    if ($Path) {
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $resolved)) {
            return @{ error = "File not found: $resolved" } | ConvertTo-Json -Compress
        }
        if ($Password) {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($resolved, $Password)
        } else {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($resolved)
        }
    } elseif ($Url) {
        # Extract hostname and port from URL
        $uri      = [System.Uri]$Url
        $hostname = $uri.Host
        $port     = if ($uri.Port -gt 0) { $uri.Port } else { 443 }

        $tc  = [System.Net.Sockets.TcpClient]::new()
        $tc.ConnectAsync($hostname, $port).Wait(10000) | Out-Null
        if (-not $tc.Connected) {
            $tc.Dispose()
            return @{ error = "Could not connect to ${hostname}:${port}" } | ConvertTo-Json -Compress
        }

        $captureCert = $null
        $sslStream   = [System.Net.Security.SslStream]::new(
            $tc.GetStream(), $false,
            [System.Net.Security.RemoteCertificateValidationCallback]{
                param($sender, $certificate, $chain, $errors)
                $script:captureCert = $certificate
                $true  # always accept for inspection
            }
        )
        $sslStream.AuthenticateAsClient($hostname)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($captureCert)
        $sslStream.Dispose()
        $tc.Dispose()
    }

    if (-not $cert) {
        return @{ error = "Could not load certificate." } | ConvertTo-Json -Compress
    }

    # Extract Subject Alternative Names (OID 2.5.29.17)
    $sanList = @()
    $sanExt  = $cert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.17" }
    if ($sanExt) {
        # Parse the formatted string: "DNS Name=..., IP Address=..."
        $formatted = $sanExt.Format($false)
        $sanList   = @($formatted -split ',\s*' | Where-Object { $_ })
    }

    $notAfter    = $cert.NotAfter
    $daysLeft    = [math]::Floor(($notAfter.ToUniversalTime() - [datetime]::UtcNow).TotalDays)

    return @{
        Subject         = $cert.Subject
        Issuer          = $cert.Issuer
        NotBefore       = $cert.NotBefore.ToString("o")
        NotAfter        = $notAfter.ToString("o")
        Thumbprint      = $cert.Thumbprint
        SerialNumber    = $cert.SerialNumber
        DaysUntilExpiry = $daysLeft
        SAN             = $sanList
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
