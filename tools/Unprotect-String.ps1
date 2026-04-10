<#
.SYNOPSIS
Decrypts a ciphertext produced by Protect-String using the same password.

.PARAMETER CipherText
The Base64-encoded ciphertext from Protect-String.

.PARAMETER Password
The password used when the string was encrypted.

.PARAMETER Iterations
PBKDF2 iteration count — must match the value used during encryption. Defaults to 100000.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CipherText,

    [Parameter(Mandatory)]
    [string]$Password,

    [int]$Iterations = 100000
)

try {
    $blob = [Convert]::FromBase64String($CipherText)

    if ($blob.Length -lt 33) {
        return @{ error = "CipherText is too short to be a valid Protect-String blob." } | ConvertTo-Json -Compress
    }

    $salt   = $blob[0..15]
    $iv     = $blob[16..31]
    $cipher = $blob[32..($blob.Length - 1)]

    $pbkdf2 = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $Password, [byte[]]$salt, $Iterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $key = $pbkdf2.GetBytes(32)
    $pbkdf2.Dispose()

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key     = $key
    $aes.IV      = [byte[]]$iv

    $decryptor  = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock([byte[]]$cipher, 0, $cipher.Length)
    $decryptor.Dispose()
    $aes.Dispose()

    $text = [System.Text.Encoding]::UTF8.GetString($plainBytes)

    return @{
        Text      = $text
        Algorithm = "AES-256-CBC"
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
