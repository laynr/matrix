<#
.SYNOPSIS
Send an email message via SMTP using .NET System.Net.Mail.

.PARAMETER SmtpServer
Hostname or IP address of the SMTP server.

.PARAMETER From
Sender email address.

.PARAMETER To
Recipient email address.

.PARAMETER Subject
Email subject line.

.PARAMETER Body
Email body text.

.PARAMETER Port
SMTP port number (default 587).

.PARAMETER UseSsl
When true, enables SSL/TLS for the SMTP connection (default true).

.PARAMETER Username
Optional SMTP authentication username.

.PARAMETER Password
Optional SMTP authentication password.

.PARAMETER Cc
Optional array of Cc recipient email addresses.

.PARAMETER IsHtml
When true, the body is treated as HTML content.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SmtpServer,

    [Parameter(Mandatory)]
    [string]$From,

    [Parameter(Mandatory)]
    [string]$To,

    [Parameter(Mandatory)]
    [string]$Subject,

    [Parameter(Mandatory)]
    [string]$Body,

    [int]$Port          = 587,
    [bool]$UseSsl       = $true,
    [string]$Username   = "",
    [string]$Password   = "",
    [string[]]$Cc       = @(),
    [bool]$IsHtml       = $false
)

try {
    $msg           = [System.Net.Mail.MailMessage]::new($From, $To, $Subject, $Body)
    $msg.IsBodyHtml = $IsHtml

    foreach ($cc in $Cc) {
        if ($cc.Trim()) { $msg.CC.Add($cc.Trim()) }
    }

    $client           = [System.Net.Mail.SmtpClient]::new($SmtpServer, $Port)
    $client.EnableSsl = $UseSsl

    if ($Username) {
        $client.Credentials = [System.Net.NetworkCredential]::new($Username, $Password)
    }

    $client.Send($msg)
    $msg.Dispose()
    $client.Dispose()

    return @{
        Success    = $true
        From       = $From
        To         = $To
        Subject    = $Subject
        SmtpServer = $SmtpServer
    } | ConvertTo-Json -Depth 3 -Compress

} catch {
    return @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
}
