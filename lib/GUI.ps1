Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms

function Show-MatrixGUI {
    $modelName = if ($global:Config -and $global:Config.Model) { $global:Config.Model } else { "matrix" }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Matrix" Height="700" Width="900" Background="#121212" WindowStartupLocation="CenterScreen" MinHeight="480" MinWidth="600">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6" BorderThickness="0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Matrix" Foreground="#E0E0E0" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" x:Name="ModelChip" Text="" Foreground="#6B7280" FontSize="11" VerticalAlignment="Center" Margin="10,0,0,0"/>
            <TextBlock Grid.Column="2" x:Name="StatusLabel" Text="Ready" Foreground="#6B7280" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <!-- New Chat button -->
            <Button Grid.Column="3" x:Name="ClearBtn" Width="34" Height="34" Margin="0,0,6,0" Background="#374151" ToolTip="New chat (clear history)">
                <Viewbox Width="16" Height="16">
                    <Canvas Width="24" Height="24">
                        <Path Fill="White" Data="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
                    </Canvas>
                </Viewbox>
            </Button>
            <!-- Settings button -->
            <Button Grid.Column="4" x:Name="SettingsBtn" Width="34" Height="34" Background="#374151" ToolTip="Settings">
                <Viewbox Width="16" Height="16">
                    <Canvas Width="24" Height="24">
                        <Path Fill="White" Data="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
                    </Canvas>
                </Viewbox>
            </Button>
        </Grid>

        <!-- Chat area -->
        <Border Grid.Row="1" Background="#1A1A1A" CornerRadius="10" Margin="0,0,0,12" Padding="6">
            <ScrollViewer x:Name="ChatScrollViewer" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ChatPanel" Margin="4"/>
            </ScrollViewer>
        </Border>

        <!-- Attachment indicator -->
        <TextBlock x:Name="AttachLabel" Grid.Row="3" Text="" Foreground="#9CA3AF"
                   FontSize="12" Margin="50,4,0,0" Visibility="Collapsed"/>

        <!-- Input row -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="AttachBtn" Grid.Column="0" Width="42" Height="42" Margin="0,0,8,0" Background="#374151" ToolTip="Attach a file">
                <Viewbox Width="18" Height="18">
                    <Canvas Width="24" Height="24">
                        <Path Fill="White" Data="M16.5 6v11.5c0 2.21-1.79 4-4 4s-4-1.79-4-4V5a2.5 2.5 0 0 1 5 0v10.5c0 .83-.67 1.5-1.5 1.5s-1.5-.67-1.5-1.5V6h-1v9.5a2.5 2.5 0 0 0 5 0V5a3.5 3.5 0 0 0-7 0v12.5c0 2.76 2.24 5 5 5s5-2.24 5-5V6h-1z"/>
                    </Canvas>
                </Viewbox>
            </Button>

            <Border Grid.Column="1" Background="#2A2A2A" CornerRadius="8" Padding="2">
                <TextBox x:Name="InputBox" Height="42" TextWrapping="Wrap" AcceptsReturn="True"
                         VerticalScrollBarVisibility="Auto" Background="Transparent"
                         Foreground="#E0E0E0" BorderThickness="0" Padding="10,11,10,11"
                         FontSize="14" FontFamily="Segoe UI, Inter, Arial" VerticalContentAlignment="Center"/>
            </Border>

            <!-- Cancel button — hidden until a request is in flight -->
            <Button x:Name="CancelBtn" Grid.Column="2" Content="Cancel" Width="72" Height="42"
                    Margin="8,0,0,0" Background="#DC2626" Foreground="White"
                    FontSize="13" FontWeight="SemiBold" Visibility="Collapsed"/>

            <Button x:Name="SendBtn" Grid.Column="3" Content="Send" Width="72" Height="42"
                    Margin="8,0,0,0" Background="#2563EB" Foreground="White"
                    FontSize="14" FontWeight="SemiBold"/>

            <Button x:Name="SettingsInputBtn" Grid.Column="4" Width="42" Height="42"
                    Margin="8,0,0,0" Background="#374151" ToolTip="Settings" Visibility="Collapsed"/>
        </Grid>
    </Grid>
</Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $global:GUI = @{
        Window           = $window
        ChatPanel        = $window.FindName("ChatPanel")
        ChatScrollViewer = $window.FindName("ChatScrollViewer")
        InputBox         = $window.FindName("InputBox")
        SendBtn          = $window.FindName("SendBtn")
        CancelBtn        = $window.FindName("CancelBtn")
        AttachBtn        = $window.FindName("AttachBtn")
        SettingsBtn      = $window.FindName("SettingsBtn")
        ClearBtn         = $window.FindName("ClearBtn")
        StatusLabel      = $window.FindName("StatusLabel")
        ModelChip        = $window.FindName("ModelChip")
        AttachLabel      = $window.FindName("AttachLabel")
    }

    $script:GUI = $global:GUI

    # Set model name chip
    $global:GUI.ModelChip.Text = "· $modelName"

    # Wire events
    $global:GUI.SendBtn.add_Click({ Invoke-Send })
    $global:GUI.CancelBtn.add_Click({ Invoke-CancelRequest })
    $global:GUI.AttachBtn.add_Click({ Invoke-AttachFile })
    $global:GUI.SettingsBtn.add_Click({ Show-SettingsGUI })
    $global:GUI.ClearBtn.add_Click({
        Clear-Messages
        $global:GUI.ChatPanel.Children.Clear()
        Add-UIChatMessage -Role "system" -Message "Chat cleared. Ready." | Out-Null
        Update-ContextDisplay
    })

    $global:GUI.InputBox.add_PreviewKeyDown({
        param($src, $e)
        if ($e.Key -eq 'Return') {
            if ([System.Windows.Input.Keyboard]::IsKeyDown('LeftCtrl') -or
                [System.Windows.Input.Keyboard]::IsKeyDown('RightCtrl')) {
                $idx = $global:GUI.InputBox.CaretIndex
                $global:GUI.InputBox.Text = $global:GUI.InputBox.Text.Insert($idx, "`n")
                $global:GUI.InputBox.CaretIndex = $idx + 1
                $e.Handled = $true
            } elseif (-not [System.Windows.Input.Keyboard]::IsKeyDown('LeftShift') -and
                      -not [System.Windows.Input.Keyboard]::IsKeyDown('RightShift')) {
                $e.Handled = $true
                Invoke-Send
            }
        }
    })

    # Cancel any in-flight request when window closes
    $window.add_Closing({
        if ($global:CancelToken) { $global:CancelToken.Cancel = $true }
    })

    Add-UIChatMessage -Role "system" -Message "Matrix is ready  ·  Model: $modelName  ·  Type a message and press Enter" | Out-Null

    $window.ShowDialog() | Out-Null
}

# ── Message bubble helpers ─────────────────────────────────────────────────────

# Adds a static message bubble. Returns the Border so callers can remove it later.
function Add-UIChatMessage {
    param([string]$Role, [string]$Message)

    $color     = switch ($Role) {
        "user"      { "#1D4ED8" }   # blue
        "assistant" { "#065F46" }   # green
        default     { "#27272A" }   # zinc-800 for system/tool
    }
    $alignment = if ($Role -eq "user") { "Right" } else { "Left" }
    $margin    = if ($Role -eq "user") { "60,5,6,5" } else { "6,5,60,5" }

    $border              = [System.Windows.Controls.Border]::new()
    $border.Background   = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString($color)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $border.Padding      = [System.Windows.Thickness]::new(14, 9, 14, 9)
    $parts               = $margin -split ','
    $border.Margin       = [System.Windows.Thickness]::new([double]$parts[0],[double]$parts[1],[double]$parts[2],[double]$parts[3])
    $border.HorizontalAlignment = $alignment

    $tb                  = [System.Windows.Controls.TextBlock]::new()
    $tb.Text             = $Message
    $tb.TextWrapping     = "Wrap"
    $tb.Foreground       = [System.Windows.Media.Brushes]::White
    $tb.FontSize         = 14
    $tb.LineHeight       = 22
    $tb.FontFamily       = [System.Windows.Media.FontFamily]::new("Segoe UI, Inter, Arial")

    $border.Child = $tb
    $global:GUI.ChatPanel.Children.Add($border) | Out-Null
    $global:GUI.ChatScrollViewer.ScrollToEnd()
    return $border
}

# Creates an empty assistant bubble and returns its TextBlock for live token streaming.
function New-LiveMessageBubble {
    $border              = [System.Windows.Controls.Border]::new()
    $border.Background   = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#065F46")
    $border.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $border.Padding      = [System.Windows.Thickness]::new(14, 9, 14, 9)
    $border.Margin       = [System.Windows.Thickness]::new(6, 5, 60, 5)
    $border.HorizontalAlignment = "Left"

    $tb                  = [System.Windows.Controls.TextBlock]::new()
    $tb.Text             = ""
    $tb.TextWrapping     = "Wrap"
    $tb.Foreground       = [System.Windows.Media.Brushes]::White
    $tb.FontSize         = 14
    $tb.LineHeight       = 22
    $tb.FontFamily       = [System.Windows.Media.FontFamily]::new("Segoe UI, Inter, Arial")

    $border.Child = $tb
    $global:GUI.ChatPanel.Children.Add($border) | Out-Null
    $global:GUI.ChatScrollViewer.ScrollToEnd()
    return $tb
}

# Creates a tool-status row (⟳ toolname). Returns the TextBlock for in-place updates.
function Add-ToolStatusCard {
    param([string]$Name, [string]$ArgPreview = "")

    $label = if ($ArgPreview) { "  ⟳  $Name ($ArgPreview)" } else { "  ⟳  $Name" }

    $border              = [System.Windows.Controls.Border]::new()
    $border.Background   = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#1C1C1E")
    $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $border.Padding      = [System.Windows.Thickness]::new(12, 6, 12, 6)
    $border.Margin       = [System.Windows.Thickness]::new(6, 2, 60, 2)
    $border.HorizontalAlignment = "Left"

    $tb                  = [System.Windows.Controls.TextBlock]::new()
    $tb.Text             = $label
    $tb.TextWrapping     = "Wrap"
    $tb.Foreground       = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#9CA3AF")
    $tb.FontSize         = 12
    $tb.FontFamily       = [System.Windows.Media.FontFamily]::new("Cascadia Mono, Consolas, Courier New, Segoe UI")

    $border.Child = $tb
    $global:GUI.ChatPanel.Children.Add($border) | Out-Null
    $global:GUI.ChatScrollViewer.ScrollToEnd()
    return $tb
}

# Updates the status label and model chip with current context usage.
function Update-ContextDisplay {
    try {
        $tok = Get-ContextTokenCount
        $max = if ($global:Config -and $global:Config.MaxTokens) { $global:Config.MaxTokens } else { 100000 }
        if ($tok -le 0) {
            $global:GUI.StatusLabel.Text       = "Ready"
            $global:GUI.StatusLabel.Foreground = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString("#6B7280")
            return
        }
        $pct   = [math]::Round($tok / $max * 100)
        $color = if ($pct -ge 90) { "#EF4444" } elseif ($pct -ge 75) { "#F59E0B" } elseif ($pct -ge 50) { "#D97706" } else { "#6B7280" }
        $global:GUI.StatusLabel.Text       = "~$tok tok · $pct%"
        $global:GUI.StatusLabel.Foreground = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString($color)
    } catch {}
}

# ── File attachment ────────────────────────────────────────────────────────────

function Invoke-AttachFile {
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title  = "Attach File"
    $dialog.Filter = "Text files (*.txt;*.md;*.ps1;*.json;*.csv;*.log;*.yaml;*.xml)|*.txt;*.md;*.ps1;*.json;*.csv;*.log;*.yaml;*.xml|All files (*.*)|*.*"
    if ($dialog.ShowDialog($global:GUI.Window) -ne $true) { return }

    $path = $dialog.FileName
    try {
        $content   = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        $filename  = Split-Path $path -Leaf
        $maxChars  = 8000
        $truncated = $content.Length -gt $maxChars
        if ($truncated) { $content = $content.Substring(0, $maxChars) }

        $global:PendingAttachment = @{ Name = $filename; Content = $content }

        $sizeNote = if ($truncated) { "truncated to $maxChars chars" } else { "$($content.Length) chars" }
        $global:GUI.AttachLabel.Text       = "Attached: $filename  ($sizeNote)"
        $global:GUI.AttachLabel.Visibility = "Visible"
        $global:GUI.InputBox.Focus() | Out-Null
    } catch {
        Add-UIChatMessage -Role "system" -Message "Could not read file: $_" | Out-Null
    }
}

# ── Settings dialog ────────────────────────────────────────────────────────────

function Show-SettingsGUI {
    [xml]$settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Settings" Height="480" Width="420" Background="#1A1A1A" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <StackPanel Margin="16">
        <TextBlock Text="Endpoint (Ollama URL):" Foreground="#9CA3AF" FontSize="12" Margin="0,0,0,4"/>
        <TextBox x:Name="EndpointBox" Background="#2A2A2A" Foreground="White" BorderBrush="#3F3F46" BorderThickness="1" Padding="8,6" FontSize="13" CornerRadius="4"/>

        <TextBlock Text="Model:" Foreground="#9CA3AF" FontSize="12" Margin="0,12,0,4"/>
        <TextBox x:Name="ModelBox" Background="#2A2A2A" Foreground="White" BorderBrush="#3F3F46" BorderThickness="1" Padding="8,6" FontSize="13" CornerRadius="4"/>

        <TextBlock Text="API Key (if required):" Foreground="#9CA3AF" FontSize="12" Margin="0,12,0,4"/>
        <PasswordBox x:Name="ApiKeyBox" Background="#2A2A2A" Foreground="White" BorderBrush="#3F3F46" BorderThickness="1" Padding="8,6" FontSize="13"/>

        <TextBlock Text="System Prompt:" Foreground="#9CA3AF" FontSize="12" Margin="0,12,0,4"/>
        <TextBox x:Name="SystemPromptBox" Height="90" TextWrapping="Wrap" AcceptsReturn="True"
                 VerticalScrollBarVisibility="Auto" Background="#2A2A2A" Foreground="White"
                 BorderBrush="#3F3F46" BorderThickness="1" Padding="8,6" FontSize="12"/>

        <TextBlock x:Name="ErrorLabel" Text="" Foreground="#EF4444" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>

        <Grid Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="CancelSettingsBtn" Grid.Column="1" Content="Cancel" Width="80" Height="32" Margin="0,0,8,0" Background="#374151" Foreground="White" BorderThickness="0"/>
            <Button x:Name="SaveBtn" Grid.Column="2" Content="Save" Width="80" Height="32" Background="#2563EB" Foreground="White" BorderThickness="0"/>
        </Grid>
    </StackPanel>
</Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader $settingsXaml)
    $win    = [System.Windows.Markup.XamlReader]::Load($reader)
    $win.Owner = $global:GUI.Window

    $endpointBox = $win.FindName("EndpointBox")
    $modelBox    = $win.FindName("ModelBox")
    $apiKeyBox   = $win.FindName("ApiKeyBox")
    $systemBox   = $win.FindName("SystemPromptBox")
    $errorLabel  = $win.FindName("ErrorLabel")
    $saveBtn     = $win.FindName("SaveBtn")
    $cancelBtn   = $win.FindName("CancelSettingsBtn")

    $endpointBox.Text    = $global:Config.Endpoint
    $modelBox.Text       = $global:Config.Model
    $apiKeyBox.Password  = if ($global:Config.ApiKey) { $global:Config.ApiKey } else { "" }
    $systemBox.Text      = $global:Config.SystemPrompt

    $cancelBtn.add_Click({ $win.Close() })

    $saveBtn.add_Click({
        $errorLabel.Text = ""
        try {
            $global:Config.Endpoint     = $endpointBox.Text.Trim()
            $global:Config.Model        = $modelBox.Text.Trim()
            $global:Config.ApiKey       = $apiKeyBox.Password
            $global:Config.SystemPrompt = $systemBox.Text
            Save-Config -Config $global:Config
            # Update model chip in main window
            $global:GUI.ModelChip.Text = "· $($global:Config.Model)"
            $win.Close()
        } catch {
            $errorLabel.Text = "Save failed: $_"
        }
    })

    $win.ShowDialog() | Out-Null
}
