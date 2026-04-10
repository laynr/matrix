<#
.SYNOPSIS
Generates a cryptographically random token in Hex, Base64, Alphanumeric, or Symbols charset.

.PARAMETER Length
Number of characters in the output token. Defaults to 32.

.PARAMETER Charset
Output character set: Hex, Base64, Alphanumeric, or Symbols. Defaults to Hex.
#>
[CmdletBinding()]
param(
    [int]$Length = 32,

    [ValidateSet("Hex","Base64","Alphanumeric","Symbols")]
    [string]$Charset = "Hex"
)

try {
    if ($Length -lt 1 -or $Length -gt 4096) {
        return @{ error = "Length must be between 1 and 4096." } | ConvertTo-Json -Compress
    }

    $token = ""

    switch ($Charset) {
        "Hex" {
            # Each byte produces 2 hex chars, so we need ceil(Length/2) bytes
            $byteCount = [math]::Ceiling($Length / 2)
            $bytes     = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes($byteCount)
            $hex       = [BitConverter]::ToString($bytes) -replace '-', ''
            $token     = $hex.Substring(0, $Length).ToUpper()
        }
        "Base64" {
            # Base64 expands 3 bytes → 4 chars; request enough bytes and trim
            $byteCount = [math]::Ceiling($Length * 3 / 4) + 3
            $bytes     = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes($byteCount)
            $b64       = [Convert]::ToBase64String($bytes) -replace '[+/=]', ''
            # May be shorter than Length if we get many padding chars; pad with more
            while ($b64.Length -lt $Length) {
                $extra = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
                $b64  += [Convert]::ToBase64String($extra) -replace '[+/=]', ''
            }
            $token = $b64.Substring(0, $Length)
        }
        "Alphanumeric" {
            $alphabet  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            $bytes     = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes($Length * 2)
            $sb        = [System.Text.StringBuilder]::new($Length)
            foreach ($b in $bytes) {
                if ($sb.Length -ge $Length) { break }
                # Reject values that would introduce modulo bias (bias-free max = 255 - (255 % 62) = 247)
                if ($b -le 247) { [void]$sb.Append($alphabet[$b % 62]) }
            }
            # Top up if rejection reduced count
            while ($sb.Length -lt $Length) {
                $extra = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
                foreach ($b in $extra) {
                    if ($sb.Length -ge $Length) { break }
                    if ($b -le 247) { [void]$sb.Append($alphabet[$b % 62]) }
                }
            }
            $token = $sb.ToString()
        }
        "Symbols" {
            $alphabet  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
            $aLen      = $alphabet.Length   # 88
            $bias      = 255 - (255 % $aLen)
            $bytes     = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes($Length * 3)
            $sb        = [System.Text.StringBuilder]::new($Length)
            foreach ($b in $bytes) {
                if ($sb.Length -ge $Length) { break }
                if ($b -le $bias) { [void]$sb.Append($alphabet[$b % $aLen]) }
            }
            while ($sb.Length -lt $Length) {
                $extra = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
                foreach ($b in $extra) {
                    if ($sb.Length -ge $Length) { break }
                    if ($b -le $bias) { [void]$sb.Append($alphabet[$b % $aLen]) }
                }
            }
            $token = $sb.ToString()
        }
    }

    return @{
        Token   = $token
        Length  = $token.Length
        Charset = $Charset
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
