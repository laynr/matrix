Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms

function Show-MatrixGUI {
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Matrix AI Agent" Height="600" Width="800" Background="#1E1E1E" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>
        
        <ScrollViewer x:Name="ChatScrollViewer" Grid.Row="0" Margin="0,0,0,10" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="ChatPanel" />
        </ScrollViewer>
        
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            
            <Button x:Name="AttachBtn" Grid.Column="0" Width="35" Height="35" Margin="0,0,5,0" Background="#333" BorderThickness="0" ToolTip="Attach File">
                <Image x:Name="AttachIcon" Width="20" Height="20" />
            </Button>
            <TextBox x:Name="InputBox" Grid.Column="1" Height="35" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Background="#333" Foreground="White" BorderThickness="0" Padding="5" FontSize="14" />
            <Button x:Name="SendBtn" Grid.Column="2" Content="Send" Width="60" Height="35" Margin="5,0,0,0" Background="#4CAF50" Foreground="White" BorderThickness="0" FontSize="14" FontWeight="Bold"/>
            <Button x:Name="SettingsBtn" Grid.Column="3" Width="35" Height="35" Margin="5,0,0,0" Background="#333" BorderThickness="0" ToolTip="Settings">
                <Image x:Name="SettingsIcon" Width="20" Height="20" />
            </Button>
        </Grid>
    </Grid>
</Window>
"@
    
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    
    $global:GUI = @{
        Window = $window
        ChatPanel = $window.FindName("ChatPanel")
        ChatScrollViewer = $window.FindName("ChatScrollViewer")
        InputBox = $window.FindName("InputBox")
        SendBtn = $window.FindName("SendBtn")
        AttachBtn = $window.FindName("AttachBtn")
        SettingsBtn = $window.FindName("SettingsBtn")
    }
    
    $script:GUI = $global:GUI
    $global:GUI.SendBtn.add_Click({ Invoke-Send })
    $global:GUI.InputBox.add_PreviewKeyDown({
        param($src, $e)
        if ($e.Key -eq 'Return') {
            if ([System.Windows.Input.Keyboard]::IsKeyDown('LeftCtrl') -or [System.Windows.Input.Keyboard]::IsKeyDown('RightCtrl')) {
                $caretIndex = $global:GUI.InputBox.CaretIndex
                $global:GUI.InputBox.Text = $global:GUI.InputBox.Text.Insert($caretIndex, "`n")
                $global:GUI.InputBox.CaretIndex = $caretIndex + 1
                $e.Handled = $true
            } elseif (-not [System.Windows.Input.Keyboard]::IsKeyDown('LeftShift') -and -not [System.Windows.Input.Keyboard]::IsKeyDown('RightShift')) {
                $e.Handled = $true
                Invoke-Send
            }
        }
    })
    $global:GUI.AttachBtn.add_Click({ Invoke-AttachFile })
    $global:GUI.SettingsBtn.add_Click({ Show-SettingsGUI })

    $attachIconPath = Join-Path $PSScriptRoot "attach.png"
    if (Test-Path $attachIconPath) {
        $window.FindName("AttachIcon").Source = New-Object System.Windows.Media.Imaging.BitmapImage(New-Object Uri($attachIconPath))
    }
    
    $settingsIconPath = Join-Path $PSScriptRoot "settings.png"
    if (Test-Path $settingsIconPath) {
        $window.FindName("SettingsIcon").Source = New-Object System.Windows.Media.Imaging.BitmapImage(New-Object Uri($settingsIconPath))
    }

    Add-UIChatMessage -Role "system" -Message "Welcome to Matrix AI Agent. Ready."
    
    $window.ShowDialog() | Out-Null
}

function Add-UIChatMessage {
    param([string]$Role, [string]$Message)
    
    $color = if ($Role -eq "user") { "#4A90E2" } elseif ($Role -eq "system") { "#888888" } else { "#50C878" }
    $alignment = if ($Role -eq "user") { "Right" } else { "Left" }
    $margin = if ($Role -eq "user") { "50,5,5,5" } else { "5,5,50,5" }
    
    $border = New-Object System.Windows.Controls.Border
    $border.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($color)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $border.Padding = New-Object System.Windows.Thickness(10)
    $marginParts = $margin -split ','
    $border.Margin = New-Object System.Windows.Thickness([double]$marginParts[0], [double]$marginParts[1], [double]$marginParts[2], [double]$marginParts[3])
    $border.HorizontalAlignment = $alignment
    
    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = $Message
    $textBlock.TextWrapping = "Wrap"
    $textBlock.Foreground = [System.Windows.Media.Brushes]::White
    $textBlock.FontSize = 14
    
    $border.Child = $textBlock
    $global:GUI.ChatPanel.Children.Add($border) | Out-Null
    $global:GUI.ChatScrollViewer.ScrollToEnd()
}

function Show-SettingsGUI {
    [xml]$settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Settings" Height="380" Width="400" Background="#1E1E1E" WindowStartupLocation="CenterOwner">
    <StackPanel Margin="10">
        <TextBlock Text="API Provider:" Foreground="White" Margin="0,5,0,0"/>
        <TextBox x:Name="ProviderBox" Background="#333" Foreground="White" BorderThickness="0" Padding="5"/>
        
        <TextBlock Text="API Endpoint:" Foreground="White" Margin="0,5,0,0"/>
        <TextBox x:Name="EndpointBox" Background="#333" Foreground="White" BorderThickness="0" Padding="5"/>
        
        <TextBlock Text="Model:" Foreground="White" Margin="0,5,0,0"/>
        <TextBox x:Name="ModelBox" Background="#333" Foreground="White" BorderThickness="0" Padding="5"/>
        
        <TextBlock Text="API Key:" Foreground="White" Margin="0,5,0,0"/>
        <PasswordBox x:Name="ApiKeyBox" Background="#333" Foreground="White" BorderThickness="0" Padding="5"/>
        
        <TextBlock Text="System Prompt:" Foreground="White" Margin="0,5,0,0"/>
        <TextBox x:Name="SystemPromptBox" Height="80" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Background="#333" Foreground="White" BorderThickness="0" Padding="5"/>
        
        <Button x:Name="SaveBtn" Content="Save" Width="80" Height="30" Margin="0,15,0,0" Background="#4CAF50" Foreground="White" BorderThickness="0" HorizontalAlignment="Right"/>
    </StackPanel>
</Window>
"@
    
    $reader = (New-Object System.Xml.XmlNodeReader $settingsXaml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)
    $win.Owner = $global:GUI.Window
    
    $providerBox = $win.FindName("ProviderBox")
    $endpointBox = $win.FindName("EndpointBox")
    $modelBox = $win.FindName("ModelBox")
    $apiKeyBox = $win.FindName("ApiKeyBox")
    $systemBox = $win.FindName("SystemPromptBox")
    $saveBtn = $win.FindName("SaveBtn")
    
    $providerBox.Text = $global:Config.Provider
    $endpointBox.Text = $global:Config.Endpoint
    $modelBox.Text = $global:Config.Model
    $apiKeyBox.Password = $global:Config.ApiKey
    $systemBox.Text = $global:Config.SystemPrompt
    
    $saveBtn.add_Click({
        $global:Config.Provider = $providerBox.Text
        $global:Config.Endpoint = $endpointBox.Text
        $global:Config.Model = $modelBox.Text
        $global:Config.ApiKey = $apiKeyBox.Password
        $global:Config.SystemPrompt = $systemBox.Text
        Save-Config -Config $global:Config
        $win.Close()
    })
    
    $win.ShowDialog() | Out-Null
}
