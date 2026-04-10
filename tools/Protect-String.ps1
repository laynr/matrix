<#
.SYNOPSIS
Encrypts a string with AES-256-CBC using a password and PBKDF2 key derivation.

.PARAMETER Text
The plaintext string to encrypt.

.PARAMETER Password
The password used to derive the encryption key.

.PARAMETER Iterations
PBKDF2 iteration count. Defaults to 100000.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Text,

    [Parameter(Mandatory)]
    [string]$Password,

    [int]$Iterations = 100000
)

try {
    $enc      = [System.Text.Encoding]::UTF8
    $salt     = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
    $pbkdf2   = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $Password, $salt, $Iterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $key = $pbkdf2.GetBytes(32)   # 256-bit key
    $iv  = $pbkdf2.GetBytes(16)   # 128-bit IV
    $pbkdf2.Dispose()

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key     = $key
    $aes.IV      = $iv

    $encryptor  = $aes.CreateEncryptor()
    $plainBytes = $enc.GetBytes($Text)
    $cipher     = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    $encryptor.Dispose()
    $aes.Dispose()

    # Blob layout: [salt 16 bytes][IV 16 bytes][ciphertext]
    $blob = [byte[]]::new(16 + 16 + $cipher.Length)
    [Array]::Copy($salt,   0, $blob,  0, 16)
    [Array]::Copy($iv,     0, $blob, 16, 16)
    [Array]::Copy($cipher, 0, $blob, 32, $cipher.Length)

    return @{
        CipherText = [Convert]::ToBase64String($blob)
        Algorithm  = "AES-256-CBC"
        Iterations = $Iterations
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
