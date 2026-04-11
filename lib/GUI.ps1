Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms

function Show-MatrixGUI {
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Matrix" Height="650" Width="850" Background="#121212" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="6" BorderThickness="0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>
        
        <!-- Header area for Token Tracking -->
        <Grid Grid.Row="0" Margin="0,0,0,10">
            <TextBlock x:Name="TokenTracker" Text="Tokens: 0 In | 0 Out" Foreground="#888888" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" />
            <TextBlock Text="Matrix" Foreground="#E0E0E0" FontSize="16" FontWeight="SemiBold" HorizontalAlignment="Left" VerticalAlignment="Center" />
        </Grid>

        <Border Grid.Row="1" Background="#1E1E1E" CornerRadius="8" Margin="0,0,0,15" Padding="5">
            <ScrollViewer x:Name="ChatScrollViewer" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ChatPanel" Margin="5" />
            </ScrollViewer>
        </Border>
        
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            
            <Button x:Name="AttachBtn" Grid.Column="0" Width="40" Height="40" Margin="0,0,8,0" Background="#4B5563" ToolTip="Attach File">
                <Image x:Name="AttachIcon" Width="22" Height="22" />
            </Button>
            
            <Border Grid.Column="1" Background="#2D2D2D" CornerRadius="8" Padding="2">
                <TextBox x:Name="InputBox" Height="40" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Background="Transparent" Foreground="#E0E0E0" BorderThickness="0" Padding="8,10,8,10" FontSize="14" />
            </Border>
            
            <Button x:Name="SendBtn" Grid.Column="2" Content="Send" Width="70" Height="40" Margin="8,0,0,0" Background="#3B82F6" Foreground="White" FontSize="14" FontWeight="SemiBold"/>
            
            <Button x:Name="SettingsBtn" Grid.Column="3" Width="40" Height="40" Margin="8,0,0,0" Background="#4B5563" ToolTip="Settings">
                <Image x:Name="SettingsIcon" Width="22" Height="22" />
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
        TokenTracker = $window.FindName("TokenTracker")
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

    Add-UIChatMessage -Role "system" -Message "Welcome to Matrix. Ready."
    
    $window.ShowDialog() | Out-Null
}

function Add-UIChatMessage {
    param([string]$Role, [string]$Message)
    
    # Modern color palette based on Claude Code / Tailwind gray scales
    $color = if ($Role -eq "user") { "#3B82F6" } elseif ($Role -eq "system") { "#3F3F46" } else { "#10B981" }
    $alignment = if ($Role -eq "user") { "Right" } else { "Left" }
    $margin = if ($Role -eq "user") { "50,6,8,6" } else { "8,6,50,6" }
    
    $border = New-Object System.Windows.Controls.Border
    $border.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($color)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $border.Padding = New-Object System.Windows.Thickness(14, 10, 14, 10)
    $marginParts = $margin -split ','
    $border.Margin = New-Object System.Windows.Thickness([double]$marginParts[0], [double]$marginParts[1], [double]$marginParts[2], [double]$marginParts[3])
    $border.HorizontalAlignment = $alignment
    
    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = $Message
    $textBlock.TextWrapping = "Wrap"
    $textBlock.Foreground = [System.Windows.Media.Brushes]::White
    $textBlock.FontSize = 14
    $textBlock.LineHeight = 22
    $textBlock.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI, Inter, Arial")
    
    $border.Child = $textBlock
    $global:GUI.ChatPanel.Children.Add($border) | Out-Null
    $global:GUI.ChatScrollViewer.ScrollToEnd()
}

function Invoke-AttachFile {
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title  = "Attach File"
    $dialog.Filter = "Text files (*.txt;*.md;*.ps1;*.json;*.csv;*.log)|*.txt;*.md;*.ps1;*.json;*.csv;*.log|All files (*.*)|*.*"
    if ($dialog.ShowDialog($global:GUI.Window) -ne $true) { return }

    $path = $dialog.FileName
    try {
        $content = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        $filename = Split-Path $path -Leaf
        # Truncate large files to avoid flooding context
        $maxChars = 8000
        if ($content.Length -gt $maxChars) {
            $content = $content.Substring(0, $maxChars) + "`n[... file truncated after $maxChars chars ...]"
        }
        $snippet = "``````$filename`n$content`n``````"
        # Append file content to the input box
        $current = $global:GUI.InputBox.Text
        $global:GUI.InputBox.Text = if ($current) { "$current`n$snippet" } else { $snippet }
        $global:GUI.InputBox.CaretIndex = $global:GUI.InputBox.Text.Length
        $global:GUI.InputBox.Focus() | Out-Null
    } catch {
        Add-UIChatMessage -Role "system" -Message "Could not read file: $_"
    }
}

function Show-SettingsGUI {
    [xml]$settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Settings" Height="450" Width="400" Background="#1E1E1E" WindowStartupLocation="CenterOwner">
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
