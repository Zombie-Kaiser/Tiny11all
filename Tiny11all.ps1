#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Tiny11all - All-in-one Windows 11 Image Slimming Tool with Modern GUI

.DESCRIPTION
    Combines tiny11 builder and nano11 builder into a single elegant GUI application.
    Supports three build modes: Tiny11 (Standard), Tiny11 Core, and Nano11 (Extreme).

.PARAMETER Mode
    Pre-select build mode: 'Standard', 'Core', or 'Nano'

.EXAMPLE
    .\Tiny11all.ps1
    .\Tiny11all.ps1 -Mode Standard
#>

[CmdletBinding()]
param (
    [ValidateSet('Standard', 'Core', 'Nano')]
    [string]$Mode
)

#region === Initialization ===
$ErrorActionPreference = 'Stop'
$script:BaseDir = $PSScriptRoot
$script:LogFile = Join-Path $script:BaseDir "Tiny11all_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:BuildMode = if ($Mode) { $Mode } else { 'Standard' }
$script:IsBuilding = $false
$script:BuildCancelled = $false
$script:ScratchDisk = $env:SystemDrive
$script:OutputName = 'Tiny11all'

# Admin check (redundant with #requires but ensures elevation)
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    $psi.Verb = 'runas'
    $psi.WorkingDirectory = $script:BaseDir
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit
}

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# Helper: Admin group
$adminSID = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$script:AdminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$script:HostArchitecture = $Env:PROCESSOR_ARCHITECTURE

# Logging
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
}

function Add-GuiLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-Log -Message $Message -Level $Level
    if ($script:txtLog) {
        $script:txtLog.Dispatcher.Invoke([action]{
            $script:txtLog.AppendText("[$Level] $Message`r`n")
            $script:txtLog.ScrollToEnd()
        })
    }
}

Write-Log "Tiny11all started. Mode: $($script:BuildMode)"
#endregion

#region === GUI XAML ===
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tiny11all" Height="780" Width="1080"
        WindowStartupLocation="CenterScreen"
        Background="#0d1117"
        Foreground="#c9d1d9"
        FontFamily="Segoe UI, Microsoft YaHei UI"
        FontSize="13"
        ResizeMode="CanResize"
        MinWidth="900" MinHeight="650">
    <Window.Resources>
        <!-- Colors -->
        <SolidColorBrush x:Key="BgPrimary" Color="#0d1117"/>
        <SolidColorBrush x:Key="BgCard" Color="#161b22"/>
        <SolidColorBrush x:Key="BgCardHover" Color="#1c2128"/>
        <SolidColorBrush x:Key="BorderColor" Color="#30363d"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#c9d1d9"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#8b949e"/>
        <SolidColorBrush x:Key="AccentBlue" Color="#58a6ff"/>
        <SolidColorBrush x:Key="AccentGreen" Color="#238636"/>
        <SolidColorBrush x:Key="AccentOrange" Color="#d29922"/>
        <SolidColorBrush x:Key="AccentRed" Color="#da3633"/>
        <SolidColorBrush x:Key="NavBg" Color="#010409"/>
        <SolidColorBrush x:Key="NavHover" Color="#161b22"/>
        <SolidColorBrush x:Key="NavSelected" Color="#1f6feb"/>

        <!-- Card Style -->
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource BgCard}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="0,0,0,16"/>
        </Style>

        <!-- Mode Card Style -->
        <Style x:Key="ModeCardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource BgCard}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="2"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="24"/>
            <Setter Property="Margin" Value="8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource BgCardHover}"/>
                    <Setter Property="BorderBrush" Value="{StaticResource AccentBlue}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Nav Button Style -->
        <Style x:Key="NavButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondary}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,12"/>
            <Setter Property="Margin" Value="8,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource NavHover}"/>
                    <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Primary Button Style -->
        <Style x:Key="PrimaryButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentGreen}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="24,12"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2ea043"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#30363d"/>
                    <Setter Property="Foreground" Value="#8b949e"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Danger Button Style -->
        <Style x:Key="DangerButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
            <Setter Property="Background" Value="{StaticResource AccentRed}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#f85149"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="DarkTextBoxStyle" TargetType="TextBox">
            <Setter Property="Background" Value="#0d1117"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <!-- ComboBox Style -->
        <Style x:Key="DarkComboBoxStyle" TargetType="ComboBox">
            <Setter Property="Background" Value="#0d1117"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColor}"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <!-- ScrollViewer Style -->
        <Style x:Key="DarkScrollViewer" TargetType="ScrollViewer">
            <Setter Property="Background" Value="Transparent"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="240"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="{StaticResource NavBg}" BorderBrush="{StaticResource BorderColor}" BorderThickness="0,0,1,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Logo -->
                <Border Grid.Row="0" Padding="20,24,20,16">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE770;" FontFamily="Segoe MDL2 Assets" FontSize="28"
                                   Foreground="{StaticResource AccentBlue}" Margin="0,0,12,0"
                                   VerticalAlignment="Center"/>
                        <StackPanel>
                            <TextBlock Text="Tiny11all" FontSize="20" FontWeight="Bold"
                                       Foreground="{StaticResource TextPrimary}"/>
                            <TextBlock Text="v1.0.0" FontSize="11"
                                       Foreground="{StaticResource TextSecondary}"/>
                        </StackPanel>
                    </StackPanel>
                </Border>

                <!-- Divider -->
                <Border Grid.Row="1" Height="1" Background="{StaticResource BorderColor}" Margin="16,0"/>

                <!-- Nav Buttons -->
                <StackPanel Grid.Row="2" Margin="0,16,0,0">
                    <Button x:Name="btnNavHome" Style="{StaticResource NavButtonStyle}"
                            Foreground="{StaticResource AccentBlue}">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE80F;" FontFamily="Segoe MDL2 Assets" FontSize="18"
                                       Margin="0,0,12,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Home" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="btnNavConfig" Style="{StaticResource NavButtonStyle}">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="18"
                                       Margin="0,0,12,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Configure" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="btnNavProgress" Style="{StaticResource NavButtonStyle}">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="18"
                                       Margin="0,0,12,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Progress" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="btnNavAbout" Style="{StaticResource NavButtonStyle}">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="18"
                                       Margin="0,0,12,0" VerticalAlignment="Center"/>
                            <TextBlock Text="About" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                </StackPanel>

                <!-- Bottom Info -->
                <Border Grid.Row="3" Padding="20,16" BorderBrush="{StaticResource BorderColor}" BorderThickness="0,1,0,0">
                    <StackPanel>
                        <TextBlock Text="Build Mode" FontSize="10" Foreground="{StaticResource TextSecondary}"/>
                        <TextBlock x:Name="txtSidebarMode" Text="Standard" FontSize="13"
                                   Foreground="{StaticResource AccentBlue}" FontWeight="SemiBold"
                                   Margin="0,2,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <!-- Main Content -->
        <Border Grid.Column="1" Background="{StaticResource BgPrimary}">
            <Grid x:Name="mainGrid">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Header -->
                <Border Grid.Row="0" Background="{StaticResource BgCard}" BorderBrush="{StaticResource BorderColor}"
                        BorderThickness="0,0,0,1" Padding="24,16">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock x:Name="txtPageTitle" Text="Welcome" FontSize="22" FontWeight="SemiBold"
                                       Foreground="{StaticResource TextPrimary}"/>
                            <TextBlock x:Name="txtPageSubtitle" Text="Select your build mode to get started"
                                       FontSize="13" Foreground="{StaticResource TextSecondary}" Margin="0,4,0,0"/>
                        </StackPanel>
                        <Border Grid.Column="1" Background="{StaticResource NavBg}" CornerRadius="6"
                                Padding="12,6" BorderBrush="{StaticResource BorderColor}" BorderThickness="1"
                                VerticalAlignment="Center">
                            <StackPanel Orientation="Horizontal">
                                <Ellipse Width="8" Height="8" Fill="{StaticResource AccentGreen}" Margin="0,0,8,0"
                                         VerticalAlignment="Center"/>
                                <TextBlock x:Name="txtStatus" Text="Ready" Foreground="{StaticResource TextSecondary}"
                                           FontSize="12"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Border>

                <!-- Pages -->
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="24">
                    <StackPanel>

                        <!-- HOME PAGE -->
                        <StackPanel x:Name="pageHome">
                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel>
                                    <TextBlock Text="Choose Your Build Mode" FontSize="18" FontWeight="SemiBold"
                                               Foreground="{StaticResource TextPrimary}" Margin="0,0,0,8"/>
                                    <TextBlock Text="Each mode offers a different balance between size reduction and functionality."
                                               Foreground="{StaticResource TextSecondary}" TextWrapping="Wrap"
                                               Margin="0,0,0,20"/>

                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <!-- Standard Card -->
                                        <Border x:Name="cardStandard" Grid.Column="0" Style="{StaticResource ModeCardStyle}"
                                                BorderBrush="{StaticResource AccentGreen}">
                                            <StackPanel>
                                                <TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="36"
                                                           Foreground="{StaticResource AccentGreen}" HorizontalAlignment="Center"
                                                           Margin="0,0,0,12"/>
                                                <TextBlock Text="Tiny11" FontSize="16" FontWeight="Bold"
                                                           Foreground="{StaticResource TextPrimary}" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Standard" FontSize="11"
                                                           Foreground="{StaticResource AccentGreen}" FontWeight="SemiBold"
                                                           HorizontalAlignment="Center" Margin="0,2,0,10"/>
                                                <TextBlock Text="Removes bloatware while keeping the system fully serviceable. You can still install updates, languages, and features."
                                                           Foreground="{StaticResource TextSecondary}" FontSize="12"
                                                           TextWrapping="Wrap" TextAlignment="Center" LineHeight="18"/>
                                                <Border Background="{StaticResource NavBg}" CornerRadius="4"
                                                        Padding="8,4" Margin="0,12,0,0">
                                                    <TextBlock Text="Recommended for daily use" FontSize="11"
                                                               Foreground="{StaticResource AccentGreen}"
                                                               HorizontalAlignment="Center" FontWeight="SemiBold"/>
                                                </Border>
                                            </StackPanel>
                                        </Border>

                                        <!-- Core Card -->
                                        <Border x:Name="cardCore" Grid.Column="1" Style="{StaticResource ModeCardStyle}">
                                            <StackPanel>
                                                <TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" FontSize="36"
                                                           Foreground="{StaticResource AccentOrange}" HorizontalAlignment="Center"
                                                           Margin="0,0,0,12"/>
                                                <TextBlock Text="Tiny11 Core" FontSize="16" FontWeight="Bold"
                                                           Foreground="{StaticResource TextPrimary}" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Advanced" FontSize="11"
                                                           Foreground="{StaticResource AccentOrange}" FontWeight="SemiBold"
                                                           HorizontalAlignment="Center" Margin="0,2,0,10"/>
                                                <TextBlock Text="More aggressive trimming. Removes WinSxS and WinRE. Disables Windows Update. Not serviceable after creation."
                                                           Foreground="{StaticResource TextSecondary}" FontSize="12"
                                                           TextWrapping="Wrap" TextAlignment="Center" LineHeight="18"/>
                                                <Border Background="{StaticResource NavBg}" CornerRadius="4"
                                                        Padding="8,4" Margin="0,12,0,0">
                                                    <TextBlock Text="For VMs and testing" FontSize="11"
                                                               Foreground="{StaticResource AccentOrange}"
                                                               HorizontalAlignment="Center" FontWeight="SemiBold"/>
                                                </Border>
                                            </StackPanel>
                                        </Border>

                                        <!-- Nano Card -->
                                        <Border x:Name="cardNano" Grid.Column="2" Style="{StaticResource ModeCardStyle}">
                                            <StackPanel>
                                                <TextBlock Text="&#xE83F;" FontFamily="Segoe MDL2 Assets" FontSize="36"
                                                           Foreground="{StaticResource AccentRed}" HorizontalAlignment="Center"
                                                           Margin="0,0,0,12"/>
                                                <TextBlock Text="Nano11" FontSize="16" FontWeight="Bold"
                                                           Foreground="{StaticResource TextPrimary}" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Extreme" FontSize="11"
                                                           Foreground="{StaticResource AccentRed}" FontWeight="SemiBold"
                                                           HorizontalAlignment="Center" Margin="0,2,0,10"/>
                                                <TextBlock Text="Maximum reduction. Removes almost everything including audio, most drivers, and IMEs. Smallest possible footprint."
                                                           Foreground="{StaticResource TextSecondary}" FontSize="12"
                                                           TextWrapping="Wrap" TextAlignment="Center" LineHeight="18"/>
                                                <Border Background="{StaticResource NavBg}" CornerRadius="4"
                                                        Padding="8,4" Margin="0,12,0,0">
                                                    <TextBlock Text="Testing / embedded only" FontSize="11"
                                                               Foreground="{StaticResource AccentRed}"
                                                               HorizontalAlignment="Center" FontWeight="SemiBold"/>
                                                </Border>
                                            </StackPanel>
                                        </Border>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel>
                                    <TextBlock Text="Quick Start" FontSize="16" FontWeight="SemiBold"
                                               Foreground="{StaticResource TextPrimary}" Margin="0,0,0,12"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <Ellipse Grid.Row="0" Grid.Column="0" Width="28" Height="28"
                                                 Fill="{StaticResource AccentBlue}" Margin="0,0,16,12"/>
                                        <TextBlock Grid.Row="0" Grid.Column="0" Text="1" Foreground="White"
                                                   FontWeight="Bold" HorizontalAlignment="Center"
                                                   VerticalAlignment="Center" Margin="0,0,16,12"/>
                                        <TextBlock Grid.Row="0" Grid.Column="1" Text="Download a Windows 11 ISO from Microsoft and mount it (double-click the ISO file)"
                                                   Foreground="{StaticResource TextSecondary}" TextWrapping="Wrap"
                                                   VerticalAlignment="Center" Margin="0,0,0,12"/>

                                        <Ellipse Grid.Row="1" Grid.Column="0" Width="28" Height="28"
                                                 Fill="{StaticResource AccentBlue}" Margin="0,0,16,12"/>
                                        <TextBlock Grid.Row="1" Grid.Column="0" Text="2" Foreground="White"
                                                   FontWeight="Bold" HorizontalAlignment="Center"
                                                   VerticalAlignment="Center" Margin="0,0,16,12"/>
                                        <TextBlock Grid.Row="1" Grid.Column="1" Text="Select your preferred build mode above (Standard, Core, or Nano)"
                                                   Foreground="{StaticResource TextSecondary}" TextWrapping="Wrap"
                                                   VerticalAlignment="Center" Margin="0,0,0,12"/>

                                        <Ellipse Grid.Row="2" Grid.Column="0" Width="28" Height="28"
                                                 Fill="{StaticResource AccentBlue}" Margin="0,0,16,12"/>
                                        <TextBlock Grid.Row="2" Grid.Column="0" Text="3" Foreground="White"
                                                   FontWeight="Bold" HorizontalAlignment="Center"
                                                   VerticalAlignment="Center" Margin="0,0,16,12"/>
                                        <TextBlock Grid.Row="2" Grid.Column="1" Text="Go to Configure page, select your mounted ISO drive and options"
                                                   Foreground="{StaticResource TextSecondary}" TextWrapping="Wrap"
                                                   VerticalAlignment="Center" Margin="0,0,0,12"/>

                                        <Ellipse Grid.Row="3" Grid.Column="0" Width="28" Height="28"
                                                 Fill="{StaticResource AccentBlue}" Margin="0,0,16,0"/>
                                        <TextBlock Grid.Row="3" Grid.Column="0" Text="4" Foreground="White"
                                                   FontWeight="Bold" HorizontalAlignment="Center"
                                                   VerticalAlignment="Center" Margin="0,0,16,0"/>
                                        <TextBlock Grid.Row="3" Grid.Column="1" Text="Click Build and wait. Your trimmed ISO will be saved in this folder."
                                                   Foreground="{StaticResource TextSecondary}" TextWrapping="Wrap"
                                                   VerticalAlignment="Center"/>
                                    </Grid>
                                </StackPanel>
                            </Border>
                        </StackPanel>

                        <!-- CONFIG PAGE -->
                        <StackPanel x:Name="pageConfig" Visibility="Collapsed">
                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel>
                                    <TextBlock Text="ISO Configuration" FontSize="16" FontWeight="SemiBold"
                                               Foreground="{StaticResource TextPrimary}" Margin="0,0,0,16"/>

                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="140"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Grid.Column="0" Text="ISO Drive"
                                                   Foreground="{StaticResource TextSecondary}"
                                                   VerticalAlignment="Center" Margin="0,0,16,12"/>
                                        <ComboBox x:Name="cmbDrive" Grid.Row="0" Grid.Column="1"
                                                  Style="{StaticResource DarkComboBoxStyle}"
                                                  Margin="0,0,8,12" VerticalContentAlignment="Center"/>
                                        <Button x:Name="btnRefreshDrives" Grid.Row="0" Grid.Column="2"
                                                Content="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="14"
                                                Background="Transparent" Foreground="{StaticResource TextSecondary}"
                                                BorderThickness="0" Padding="10,8" Margin="0,0,0,12"
                                                Cursor="Hand" ToolTip="Refresh drives"/>

                                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Scratch Disk"
                                                   Foreground="{StaticResource TextSecondary}"
                                                   VerticalAlignment="Center" Margin="0,0,16,12"/>
                                        <ComboBox x:Name="cmbScratch" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2"
                                                  Style="{StaticResource DarkComboBoxStyle}"
                                                  Margin="0,0,0,12" VerticalContentAlignment="Center"/>

                                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Image Index"
                                                   Foreground="{StaticResource TextSecondary}"
                                                   VerticalAlignment="Center" Margin="0,0,16,12"/>
                                        <ComboBox x:Name="cmbIndex" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2"
                                                  Style="{StaticResource DarkComboBoxStyle}"
                                                  Margin="0,0,0,12" VerticalContentAlignment="Center"/>

                                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Output Name"
                                                   Foreground="{StaticResource TextSecondary}"
                                                   VerticalAlignment="Center" Margin="0,0,16,0"/>
                                        <TextBox x:Name="txtOutputName" Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2"
                                                 Style="{StaticResource DarkTextBoxStyle}"
                                                 Text="Tiny11all" VerticalContentAlignment="Center"/>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel>
                                    <TextBlock Text="Build Options" FontSize="16" FontWeight="SemiBold"
                                               Foreground="{StaticResource TextPrimary}" Margin="0,0,0,16"/>

                                    <CheckBox x:Name="chkBypassHW" Content="Bypass hardware requirements (TPM, CPU, RAM checks)"
                                              Foreground="{StaticResource TextSecondary}" IsChecked="True"
                                              Margin="0,0,0,10"/>
                                    <CheckBox x:Name="chkDisableTelemetry" Content="Disable telemetry and diagnostic data collection"
                                              Foreground="{StaticResource TextSecondary}" IsChecked="True"
                                              Margin="0,0,0,10"/>
                                    <CheckBox x:Name="chkDisableSponsored" Content="Disable sponsored apps and suggestions"
                                              Foreground="{StaticResource TextSecondary}" IsChecked="True"
                                              Margin="0,0,0,10"/>
                                    <CheckBox x:Name="chkDisableBitLocker" Content="Disable BitLocker device encryption"
                                              Foreground="{StaticResource TextSecondary}" IsChecked="True"
                                              Margin="0,0,0,10"/>
                                    <CheckBox x:Name="chkCompact" Content="Enable Compact OS installation (smaller on-disk footprint)"
                                              Foreground="{StaticResource TextSecondary}" IsChecked="True"
                                              Margin="0,0,0,10"/>
                                    <CheckBox x:Name="chkNet35" Content="Enable .NET Framework 3.5 support"
                                              Foreground="{StaticResource TextSecondary}" IsChecked="False"
                                              Margin="0,0,0,0"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource CardStyle}" Background="#da363322"
                                    BorderBrush="#da3633" Visibility="Collapsed" x:Name="warnBorder">
                                <StackPanel>
                                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                        <TextBlock Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="18"
                                                   Foreground="{StaticResource AccentRed}" Margin="0,0,8,0"
                                                   VerticalAlignment="Center"/>
                                        <TextBlock Text="Warning" FontSize="14" FontWeight="Bold"
                                                   Foreground="{StaticResource AccentRed}" VerticalAlignment="Center"/>
                                    </StackPanel>
                                    <TextBlock x:Name="txtWarning" Text=""
                                               Foreground="#f85149" TextWrapping="Wrap" FontSize="12"/>
                                </StackPanel>
                            </Border>

                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                                <Button x:Name="btnBuild" Content="Start Build" Style="{StaticResource PrimaryButtonStyle}"/>
                            </StackPanel>
                        </StackPanel>

                        <!-- PROGRESS PAGE -->
                        <StackPanel x:Name="pageProgress" Visibility="Collapsed">
                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel>
                                    <TextBlock Text="Build Progress" FontSize="16" FontWeight="SemiBold"
                                               Foreground="{StaticResource TextPrimary}" Margin="0,0,0,16"/>

                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <ProgressBar x:Name="progressBar" Grid.Column="0" Height="24"
                                                     Background="#0d1117" Foreground="{StaticResource AccentGreen}"
                                                     BorderBrush="{StaticResource BorderColor}" BorderThickness="1"
                                                     Value="0" Maximum="100"/>
                                        <TextBlock x:Name="txtProgressPercent" Grid.Column="1" Text="0%"
                                                   Foreground="{StaticResource TextPrimary}" FontWeight="Bold"
                                                   FontSize="14" Margin="12,0,0,0" VerticalAlignment="Center"/>
                                    </Grid>

                                    <TextBlock x:Name="txtCurrentStep" Text="Waiting to start..."
                                               Foreground="{StaticResource TextSecondary}" Margin="0,12,0,0"
                                               FontSize="13"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel>
                                    <Grid Margin="0,0,0,12">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Text="Build Log" FontSize="14" FontWeight="SemiBold"
                                                   Foreground="{StaticResource TextPrimary}" VerticalAlignment="Center"/>
                                        <Button x:Name="btnClearLog" Grid.Column="1" Content="Clear"
                                                Background="Transparent" Foreground="{StaticResource AccentBlue}"
                                                BorderThickness="0" FontSize="12" Cursor="Hand"/>
                                    </Grid>
                                    <Border Background="#0d1117" BorderBrush="{StaticResource BorderColor}"
                                            BorderThickness="1" CornerRadius="4">
                                        <TextBox x:Name="txtLog" Background="Transparent"
                                                 Foreground="{StaticResource TextSecondary}"
                                                 BorderThickness="0" Padding="12"
                                                 IsReadOnly="True" TextWrapping="Wrap"
                                                 VerticalScrollBarVisibility="Auto"
                                                 Height="320" FontFamily="Consolas"
                                                 FontSize="11" AcceptsReturn="True"/>
                                    </Border>
                                </StackPanel>
                            </Border>

                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                                <Button x:Name="btnCancel" Content="Cancel Build" Style="{StaticResource DangerButtonStyle}"
                                        IsEnabled="False" Margin="0,0,8,0"/>
                            </StackPanel>
                        </StackPanel>

                        <!-- ABOUT PAGE -->
                        <StackPanel x:Name="pageAbout" Visibility="Collapsed">
                            <Border Style="{StaticResource CardStyle}">
                                <StackPanel HorizontalAlignment="Center">
                                    <TextBlock Text="&#xE770;" FontFamily="Segoe MDL2 Assets" FontSize="64"
                                               Foreground="{StaticResource AccentBlue}" HorizontalAlignment="Center"
                                               Margin="0,0,0,16"/>
                                    <TextBlock Text="Tiny11all" FontSize="28" FontWeight="Bold"
                                               Foreground="{StaticResource TextPrimary}" HorizontalAlignment="Center"/>
                                    <TextBlock Text="Version 1.0.0" FontSize="13"
                                               Foreground="{StaticResource TextSecondary}" HorizontalAlignment="Center"
                                               Margin="0,4,0,20"/>
                                    <TextBlock Text="All-in-one Windows 11 image slimming tool with modern GUI"
                                               Foreground="{StaticResource TextSecondary}" FontSize="13"
                                               TextAlignment="Center" TextWrapping="Wrap" Margin="0,0,0,20"/>

                                    <Border Background="{StaticResource NavBg}" CornerRadius="8" Padding="20"
                                            BorderBrush="{StaticResource BorderColor}" BorderThickness="1"
                                            MaxWidth="500">
                                        <StackPanel>
                                            <TextBlock Text="Credits" FontSize="14" FontWeight="SemiBold"
                                                       Foreground="{StaticResource TextPrimary}" Margin="0,0,0,12"/>
                                            <TextBlock Text="Based on tiny11 builder and nano11 builder by ntdevlabs"
                                                       Foreground="{StaticResource TextSecondary}" FontSize="12"
                                                       TextWrapping="Wrap" TextAlignment="Center"/>
                                            <TextBlock Text="GUI and integration by Tiny11all project"
                                                       Foreground="{StaticResource TextSecondary}" FontSize="12"
                                                       TextWrapping="Wrap" TextAlignment="Center" Margin="0,4,0,0"/>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </Border>
                        </StackPanel>

                    </StackPanel>
                </ScrollViewer>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# Parse XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:Window = [Windows.Markup.XamlReader]::Load($reader)

# Get UI elements
$script:btnNavHome = $script:Window.FindName('btnNavHome')
$script:btnNavConfig = $script:Window.FindName('btnNavConfig')
$script:btnNavProgress = $script:Window.FindName('btnNavProgress')
$script:btnNavAbout = $script:Window.FindName('btnNavAbout')
$script:txtPageTitle = $script:Window.FindName('txtPageTitle')
$script:txtPageSubtitle = $script:Window.FindName('txtPageSubtitle')
$script:txtStatus = $script:Window.FindName('txtStatus')
$script:txtSidebarMode = $script:Window.FindName('txtSidebarMode')
$script:pageHome = $script:Window.FindName('pageHome')
$script:pageConfig = $script:Window.FindName('pageConfig')
$script:pageProgress = $script:Window.FindName('pageProgress')
$script:pageAbout = $script:Window.FindName('pageAbout')
$script:cardStandard = $script:Window.FindName('cardStandard')
$script:cardCore = $script:Window.FindName('cardCore')
$script:cardNano = $script:Window.FindName('cardNano')
$script:cmbDrive = $script:Window.FindName('cmbDrive')
$script:cmbScratch = $script:Window.FindName('cmbScratch')
$script:cmbIndex = $script:Window.FindName('cmbIndex')
$script:txtOutputName = $script:Window.FindName('txtOutputName')
$script:btnRefreshDrives = $script:Window.FindName('btnRefreshDrives')
$script:btnBuild = $script:Window.FindName('btnBuild')
$script:btnCancel = $script:Window.FindName('btnCancel')
$script:btnClearLog = $script:Window.FindName('btnClearLog')
$script:progressBar = $script:Window.FindName('progressBar')
$script:txtProgressPercent = $script:Window.FindName('txtProgressPercent')
$script:txtCurrentStep = $script:Window.FindName('txtCurrentStep')
$script:txtLog = $script:Window.FindName('txtLog')
$script:warnBorder = $script:Window.FindName('warnBorder')
$script:txtWarning = $script:Window.FindName('txtWarning')
$script:chkBypassHW = $script:Window.FindName('chkBypassHW')
$script:chkDisableTelemetry = $script:Window.FindName('chkDisableTelemetry')
$script:chkDisableSponsored = $script:Window.FindName('chkDisableSponsored')
$script:chkDisableBitLocker = $script:Window.FindName('chkDisableBitLocker')
$script:chkCompact = $script:Window.FindName('chkCompact')
$script:chkNet35 = $script:Window.FindName('chkNet35')
#endregion

#region === Navigation ===
$script:CurrentPage = 'Home'

function Show-Page {
    param([string]$Page)
    $script:CurrentPage = $Page
    $script:pageHome.Visibility = 'Collapsed'
    $script:pageConfig.Visibility = 'Collapsed'
    $script:pageProgress.Visibility = 'Collapsed'
    $script:pageAbout.Visibility = 'Collapsed'

    # Reset nav colors
    $script:btnNavHome.Foreground = '#8b949e'
    $script:btnNavConfig.Foreground = '#8b949e'
    $script:btnNavProgress.Foreground = '#8b949e'
    $script:btnNavAbout.Foreground = '#8b949e'

    switch ($Page) {
        'Home' {
            $script:pageHome.Visibility = 'Visible'
            $script:txtPageTitle.Text = 'Welcome'
            $script:txtPageSubtitle.Text = 'Select your build mode to get started'
            $script:btnNavHome.Foreground = '#58a6ff'
        }
        'Config' {
            $script:pageConfig.Visibility = 'Visible'
            $script:txtPageTitle.Text = 'Configuration'
            $script:txtPageSubtitle.Text = 'Set your build options and ISO source'
            $script:btnNavConfig.Foreground = '#58a6ff'
        }
        'Progress' {
            $script:pageProgress.Visibility = 'Visible'
            $script:txtPageTitle.Text = 'Build Progress'
            $script:txtPageSubtitle.Text = 'Monitor your build in real-time'
            $script:btnNavProgress.Foreground = '#58a6ff'
        }
        'About' {
            $script:pageAbout.Visibility = 'Visible'
            $script:txtPageTitle.Text = 'About'
            $script:txtPageSubtitle.Text = 'Tiny11all project information'
            $script:btnNavAbout.Foreground = '#58a6ff'
        }
    }
}
#endregion

#region === Helper Functions ===
function Set-Mode {
    param([string]$NewMode)
    $script:BuildMode = $NewMode
    $script:txtSidebarMode.Text = $NewMode
    Add-GuiLog "Build mode changed to: $NewMode" 'INFO'

    # Update card borders
    $blueBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0x58, 0xa6, 0xff))
    $greenBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0x23, 0x86, 0x36))
    $orangeBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xd2, 0x99, 0x22))
    $redBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xda, 0x36, 0x33))
    $defaultBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0x30, 0x36, 0x3d))

    $script:cardStandard.BorderBrush = $defaultBrush
    $script:cardCore.BorderBrush = $defaultBrush
    $script:cardNano.BorderBrush = $defaultBrush

    switch ($NewMode) {
        'Standard' { $script:cardStandard.BorderBrush = $greenBrush }
        'Core' { $script:cardCore.BorderBrush = $orangeBrush }
        'Nano' { $script:cardNano.BorderBrush = $redBrush }
    }

    # Show/hide warnings
    if ($NewMode -eq 'Core') {
        $script:warnBorder.Visibility = 'Visible'
        $script:txtWarning.Text = "Tiny11 Core creates a non-serviceable image. You will NOT be able to install Windows Updates, add languages, or install features after creation. This mode is intended for VMs and testing only."
    } elseif ($NewMode -eq 'Nano') {
        $script:warnBorder.Visibility = 'Visible'
        $script:txtWarning.Text = "Nano11 is an EXTREME experimental mode. It removes the Windows Component Store, most drivers, audio services, IMEs, and much more. The resulting OS is NOT serviceable and may have limited functionality. Use only for testing or embedded scenarios in VMs."
    } else {
        $script:warnBorder.Visibility = 'Collapsed'
    }
}

function Update-Progress {
    param([int]$Percent, [string]$Step)
    $script:Window.Dispatcher.Invoke([action]{
        $script:progressBar.Value = $Percent
        $script:txtProgressPercent.Text = "$Percent%"
        if ($Step) { $script:txtCurrentStep.Text = $Step }
    })
}

function Get-AvailableDrives {
    $drives = @()
    Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'CD-ROM' } | ForEach-Object {
        $letter = $_.DriveLetter
        $label = if ($_.FileSystemLabel) { $_.FileSystemLabel } else { 'No Label' }
        $drives += "$letter`: - $label"
    }
    # Also check mounted ISOs that might not be CD-ROM type
    Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter)`:\sources\boot.wim") } | ForEach-Object {
        $letter = $_.DriveLetter
        $label = if ($_.FileSystemLabel) { $_.FileSystemLabel } else { 'Windows ISO' }
        $item = "$letter`: - $label"
        if ($drives -notcontains $item) { $drives += $item }
    }
    return $drives
}

function Get-ScratchDrives {
    $drives = @()
    Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
        $letter = $_.DriveLetter
        $size = [math]::Round($_.Size / 1GB, 1)
        $free = [math]::Round($_.SizeRemaining / 1GB, 1)
        $drives += "$letter`: ($free GB free / $size GB total)"
    }
    return $drives
}

function Refresh-DriveList {
    $script:cmbDrive.Items.Clear()
    $drives = Get-AvailableDrives
    if ($drives.Count -eq 0) {
        $script:cmbDrive.Items.Add('No mounted ISO found')
        $script:cmbDrive.IsEnabled = $false
    } else {
        foreach ($d in $drives) { $script:cmbDrive.Items.Add($d) }
        $script:cmbDrive.SelectedIndex = 0
        $script:cmbDrive.IsEnabled = $true
    }

    $script:cmbScratch.Items.Clear()
    $scratches = Get-ScratchDrives
    foreach ($s in $scratches) { $script:cmbScratch.Items.Add($s) }
    if ($scratches.Count -gt 0) { $script:cmbScratch.SelectedIndex = 0 }
}

function Get-SelectedDriveLetter {
    $sel = $script:cmbDrive.SelectedItem
    if ($sel -and $sel -match '^([A-Z]):') { return $matches[1] }
    return $null
}

function Get-SelectedScratchLetter {
    $sel = $script:cmbScratch.SelectedItem
    if ($sel -and $sel -match '^([A-Z]):') { return $matches[1] }
    return $env:SystemDrive.TrimEnd(':')
}

function Test-Prerequisites {
    $drive = Get-SelectedDriveLetter
    if (-not $drive) { return 'Please select a valid mounted ISO drive.' }
    if (-not (Test-Path "$drive`:\sources\boot.wim")) {
        return "Selected drive does not contain a valid Windows installation image.`nPlease mount a Windows 11 ISO first."
    }
    $scratch = Get-SelectedScratchLetter
    $vol = Get-Volume -DriveLetter $scratch -ErrorAction SilentlyContinue
    if (-not $vol -or $vol.SizeRemaining -lt 20GB) {
        return "Scratch disk $scratch`: does not have enough free space.`nAt least 20 GB is recommended."
    }
    return $null
}

function Set-RegistryValue {
    param([string]$Path, [string]$Name, [string]$Type, [string]$Value)
    try {
        & 'reg' 'add' $Path '/v' $Name '/t' $Type '/d' $Value '/f' | Out-Null
    } catch { Add-GuiLog "Failed to set registry: $Path\$Name" 'WARN' }
}

function Remove-RegistryValue {
    param([string]$Path)
    try { & 'reg' 'delete' $Path '/f' | Out-Null } catch {}
}

function Invoke-DISM {
    param([string[]]$Arguments)
    $proc = Start-Process -FilePath 'dism.exe' -ArgumentList $Arguments -NoNewWindow -PassThru
    while (-not $proc.HasExited) {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 200
    }
    return $proc.ExitCode
}

function Process-DispatcherEvents {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Download-Oscdimg {
    $localPath = Join-Path $script:BaseDir 'oscdimg.exe'
    $adkPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$script:HostArchitecture\Oscdimg"

    if (Test-Path (Join-Path $adkPath 'oscdimg.exe')) {
        Add-GuiLog 'Using oscdimg.exe from system ADK' 'INFO'
        return Join-Path $adkPath 'oscdimg.exe'
    }

    if (-not (Test-Path $localPath)) {
        Add-GuiLog 'Downloading oscdimg.exe...' 'INFO'
        try {
            Invoke-WebRequest -Uri 'https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe' -OutFile $localPath -UseBasicParsing
            Add-GuiLog 'oscdimg.exe downloaded successfully' 'INFO'
        } catch {
            Add-GuiLog "Failed to download oscdimg.exe: $_" 'ERROR'
            return $null
        }
    } else {
        Add-GuiLog 'Using local oscdimg.exe' 'INFO'
    }
    return $localPath
}

function Remove-AppxBloat {
    param([string]$ScratchDir, [string[]]$ExtraPatterns)
    Add-GuiLog 'Removing provisioned AppX packages...' 'INFO'

    $basePatterns = @(
        'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather',
        'Microsoft.Copilot', 'Microsoft.Windows.CrossDevice', 'Microsoft.GamingApp', 'Microsoft.GetHelp',
        'Microsoft.Getstarted', 'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes', 'Microsoft.MixedReality.Portal',
        'Microsoft.MSPaint', 'Microsoft.Office.OneNote', 'Microsoft.OfficePushNotificationUtility',
        'Microsoft.OutlookForWindows', 'Microsoft.Paint', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop',
        'Microsoft.SkypeApp', 'Microsoft.StartExperiencesApp', 'Microsoft.Todos', 'Microsoft.Wallet',
        'Microsoft.Windows.DevHome', 'Microsoft.Windows.Copilot', 'Microsoft.Windows.Teams',
        'Microsoft.WindowsAlarms', 'Microsoft.WindowsCamera', 'microsoft.windowscommunicationsapps',
        'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder',
        'Microsoft.WindowsTerminal', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay',
        'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'MicrosoftCorporationII.MicrosoftFamily',
        'MicrosoftCorporationII.QuickAssist', 'MSTeams', 'MicrosoftTeams', 'Microsoft.549981C3F5F10'
    )

    $allPatterns = $basePatterns + $ExtraPatterns | Select-Object -Unique

    $packages = & 'dism' '/English' "/image:$ScratchDir" '/Get-ProvisionedAppxPackages' | ForEach-Object {
        if ($_ -match 'PackageName : (.*)') { $matches[1] }
    }

    $packagesToRemove = $packages | Where-Object {
        $pkg = $_
        $allPatterns | Where-Object { $pkg -like "*$_*" }
    }

    foreach ($package in $packagesToRemove) {
        Add-GuiLog "Removing AppX: $package" 'INFO'
        & 'dism' '/English' "/image:$ScratchDir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package" | Out-Null
    }
    Add-GuiLog "Removed $($packagesToRemove.Count) AppX packages" 'INFO'
}

function Remove-EdgeAndOneDrive {
    param([string]$ScratchDir, [string]$Architecture)
    Add-GuiLog 'Removing Microsoft Edge...' 'INFO'
    Remove-Item -Path "$ScratchDir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue

    & 'takeown' '/f' "$ScratchDir\Windows\System32\Microsoft-Edge-Webview" '/r' | Out-Null
    & 'icacls' "$ScratchDir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($script:AdminGroup.Value):(F)" '/T' '/C' | Out-Null
    Remove-Item -Path "$ScratchDir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction SilentlyContinue

    if ($Architecture -eq 'amd64') {
        $edgeFolder = Get-ChildItem -Path "$ScratchDir\Windows\WinSxS" -Filter 'amd64_microsoft-edge-webview_31bf3856ad364e35*' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($edgeFolder) {
            & 'takeown' '/f' $edgeFolder '/r' | Out-Null
            & 'icacls' $edgeFolder '/grant' "$($script:AdminGroup.Value):(F)" '/T' '/C' | Out-Null
            Remove-Item -Path $edgeFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Add-GuiLog 'Removing OneDrive...' 'INFO'
    & 'takeown' '/f' "$ScratchDir\Windows\System32\OneDriveSetup.exe" | Out-Null
    & 'icacls' "$ScratchDir\Windows\System32\OneDriveSetup.exe" '/grant' "$($script:AdminGroup.Value):(F)" '/T' '/C' | Out-Null
    Remove-Item -Path "$ScratchDir\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue
}

function Apply-RegistryTweaks {
    param([string]$ScratchDir, [string]$Mode)
    Add-GuiLog 'Applying registry tweaks...' 'INFO'

    reg load HKLM\zCOMPONENTS "$ScratchDir\Windows\System32\config\COMPONENTS" | Out-Null
    reg load HKLM\zDEFAULT "$ScratchDir\Windows\System32\config\default" | Out-Null
    reg load HKLM\zNTUSER "$ScratchDir\Users\Default\ntuser.dat" | Out-Null
    reg load HKLM\zSOFTWARE "$ScratchDir\Windows\System32\config\SOFTWARE" | Out-Null
    reg load HKLM\zSYSTEM "$ScratchDir\Windows\System32\config\SYSTEM" | Out-Null

    # Bypass hardware requirements
    if ($script:chkBypassHW.IsChecked) {
        Add-GuiLog 'Bypassing hardware requirements...' 'INFO'
        Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
    }

    # Disable sponsored apps
    if ($script:chkDisableSponsored.IsChecked) {
        Add-GuiLog 'Disabling sponsored apps...' 'INFO'
        Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
        Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
        Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'
    }

    # Enable local accounts on OOBE
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'

    # Copy autounattend.xml
    $autoPath = Join-Path $script:BaseDir 'autounattend.xml'
    if (Test-Path $autoPath) {
        Copy-Item -Path $autoPath -Destination "$ScratchDir\Windows\System32\Sysprep\autounattend.xml" -Force | Out-Null
    }

    # Disable reserved storage
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'

    # Disable BitLocker
    if ($script:chkDisableBitLocker.IsChecked) {
        Add-GuiLog 'Disabling BitLocker device encryption...' 'INFO'
        Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'
    }

    # Disable chat icon
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'

    # Remove Edge registries
    Remove-RegistryValue 'HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    Remove-RegistryValue 'HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update'

    # Disable OneDrive folder backup
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 'REG_DWORD' '1'

    # Disable telemetry
    if ($script:chkDisableTelemetry.IsChecked) {
        Add-GuiLog 'Disabling telemetry...' 'INFO'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
    }

    # Prevent DevHome and Outlook installation
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
    Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
    Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'

    # Disable Copilot
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'

    # Prevent Teams installation
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'

    # Core/Nano specific: Disable Windows Update
    if ($Mode -in @('Core', 'Nano')) {
        Add-GuiLog 'Disabling Windows Update...' 'INFO'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'StopWUPostOOBE1' 'REG_SZ' 'net stop wuauserv'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'StopWUPostOOBE2' 'REG_SZ' 'sc stop wuauserv'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'StopWUPostOOBE3' 'REG_SZ' 'sc config wuauserv start= disabled'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'DisbaleWUPostOOBE1' 'REG_SZ' 'reg add HKLM\SYSTEM\CurrentControlSet\Services\wuauserv /v Start /t REG_DWORD /d 4 /f'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'DisbaleWUPostOOBE2' 'REG_SZ' 'reg add HKLM\SYSTEM\ControlSet001\Services\wuauserv /v Start /t REG_DWORD /d 4 /f'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DoNotConnectToWindowsUpdateInternetLocations' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DisableWindowsUpdateAccess' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUServer' 'REG_SZ' 'localhost'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUStatusServer' 'REG_SZ' 'localhost'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'UpdateServiceUrlAlternate' 'REG_SZ' 'localhost'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'DisableOnline' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\wuauserv' 'Start' 'REG_DWORD' '4'
        Remove-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\WaaSMedicSVC'
        Remove-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\UsoSvc'
        Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 'REG_DWORD' '1'
    }

    # Core/Nano specific: Disable Windows Defender
    if ($Mode -in @('Core', 'Nano')) {
        Add-GuiLog 'Disabling Windows Defender...' 'INFO'
        $svcPaths = @('WinDefend', 'WdNisSvc', 'WdNisDrv', 'WdFilter', 'Sense')
        foreach ($p in $svcPaths) {
            try { Set-ItemProperty -Path "HKLM:\zSYSTEM\ControlSet001\Services\$p" -Name 'Start' -Value 4 } catch {}
        }
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'REG_SZ' 'hide:virus;windowsupdate'
    }

    # Delete scheduled tasks
    $tasksPath = "$ScratchDir\Windows\System32\Tasks"
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue

    # Unload registry hives
    reg unload HKLM\zCOMPONENTS 2>$null
    reg unload HKLM\zDEFAULT 2>$null
    reg unload HKLM\zNTUSER 2>$null
    reg unload HKLM\zSOFTWARE 2>$null
    reg unload HKLM\zSYSTEM 2>$null
}

function Remove-SystemPackages {
    param([string]$ScratchDir, [string]$LanguageCode, [string[]]$ExtraPatterns)
    Add-GuiLog 'Removing system packages...' 'INFO'

    $patterns = @(
        'Microsoft-Windows-InternetExplorer-Optional-Package~',
        'Microsoft-Windows-MediaPlayer-Package~',
        'Microsoft-Windows-TabletPCMath-Package~',
        'Microsoft-Windows-StepsRecorder-Package~',
        'Microsoft-Windows-WordPad-FoD-Package~',
        'Microsoft-Windows-Kernel-LA57-FoD-Package~',
        'Microsoft-Windows-Hello-Face-Package~',
        'Microsoft-Windows-Hello-BioEnrollment-Package~',
        'Microsoft-Windows-BitLocker-DriveEncryption-FVE-Package~',
        "Microsoft-Windows-LanguageFeatures-Handwriting-$LanguageCode-Package~",
        "Microsoft-Windows-LanguageFeatures-OCR-$LanguageCode-Package~",
        "Microsoft-Windows-LanguageFeatures-Speech-$LanguageCode-Package~",
        "Microsoft-Windows-LanguageFeatures-TextToSpeech-$LanguageCode-Package~",
        '*IME-ja-jp*', '*IME-ko-kr*', '*IME-zh-cn*', '*IME-zh-tw*'
    ) + $ExtraPatterns | Select-Object -Unique

    $allPackages = & dism /image:$ScratchDir /Get-Packages /Format:Table
    $allPackages = $allPackages -split "`n" | Select-Object -Skip 1

    foreach ($pattern in $patterns) {
        $pkgs = $allPackages | Where-Object { $_ -like "$pattern*" }
        foreach ($pkg in $pkgs) {
            $pkgIdentity = ($pkg -split '\s+')[0]
            Add-GuiLog "Removing package: $pkgIdentity" 'INFO'
            & dism /image:$ScratchDir /Remove-Package /PackageName:$pkgIdentity | Out-Null
        }
    }
}

function Remove-NanoSpecific {
    param([string]$ScratchDir, [string]$Architecture)
    Add-GuiLog 'Performing Nano11-specific removals...' 'INFO'

    # Take ownership of key folders
    $folders = @(
        "$ScratchDir\Windows\System32\DriverStore\FileRepository",
        "$ScratchDir\Windows\Fonts", "$ScratchDir\Windows\Web",
        "$ScratchDir\Windows\Help", "$ScratchDir\Windows\Cursors",
        "$ScratchDir\Program Files (x86)\Microsoft",
        "$ScratchDir\Program Files\WindowsApps",
        "$ScratchDir\Windows\System32\Microsoft-Edge-Webview",
        "$ScratchDir\Windows\System32\Recovery",
        "$ScratchDir\Windows\WinSxS", "$ScratchDir\Windows\assembly",
        "$ScratchDir\ProgramData\Microsoft\Windows Defender",
        "$ScratchDir\Windows\System32\InputMethod",
        "$ScratchDir\Windows\Speech", "$ScratchDir\Windows\Temp"
    )
    foreach ($f in $folders) {
        if (Test-Path $f) {
            & takeown.exe /F $f /R /D Y | Out-Null
            & icacls.exe $f /grant "$($script:AdminGroup.Value):(F)" /T /C | Out-Null
        }
    }

    # Slim driver store
    $driverRepo = "$ScratchDir\Windows\System32\DriverStore\FileRepository"
    if (Test-Path $driverRepo) {
        $driverPatterns = @('prn*', 'scan*', 'mfd*', 'wscsmd.inf*', 'tapdrv*', 'rdpbus.inf*', 'tdibth.inf*')
        Get-ChildItem -Path $driverRepo -Directory | ForEach-Object {
            foreach ($pat in $driverPatterns) {
                if ($_.Name -like $pat) {
                    Remove-Item -Path $_.FullName -Recurse -Force
                    break
                }
            }
        }
    }

    # Slim fonts
    $fontsPath = "$ScratchDir\Windows\Fonts"
    if (Test-Path $fontsPath) {
        Get-ChildItem -Path $fontsPath -Exclude 'segoe*.*', 'tahoma*.*', 'marlett.ttf', '8541oem.fon', 'segui*.*', 'consol*.*', 'lucon*.*', 'calibri*.*', 'arial*.*', 'times*.*', 'cou*.*', '8*.*' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $fontsPath -Include 'mingli*', 'msjh*', 'msyh*', 'malgun*', 'meiryo*', 'yugoth*', 'segoeuihistoric.ttf' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove additional items
    Remove-Item -Path "$ScratchDir\Windows\Speech\Engines\TTS" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\ProgramData\Microsoft\Windows Defender\Definition Updates" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\System32\InputMethod\CHS" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\System32\InputMethod\CHT" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\System32\InputMethod\JPN" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\System32\InputMethod\KOR" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\Web" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\Help" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\Cursors" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDir\Windows\assembly\NativeImages_*" -Recurse -Force -ErrorAction SilentlyContinue
}

function Optimize-WinSxS {
    param([string]$ScratchDir, [string]$Architecture)
    Add-GuiLog 'Optimizing WinSxS (Nano11 mode)...' 'INFO'

    & 'takeown' '/f' "$ScratchDir\Windows\WinSxS" '/r' | Out-Null
    & 'icacls' "$ScratchDir\Windows\WinSxS" '/grant' "$($script:AdminGroup.Value):(F)" '/T' '/C' | Out-Null

    $folderPath = "$ScratchDir\Windows\WinSxS_edit"
    $sourceDirectory = "$ScratchDir\Windows\WinSxS"
    $destinationDirectory = "$ScratchDir\Windows\WinSxS_edit"
    New-Item -Path $folderPath -ItemType Directory -Force | Out-Null

    if ($Architecture -eq 'amd64') {
        $dirsToCopy = @(
            'x86_microsoft.windows.common-controls_6595b64144ccf1df_*',
            'x86_microsoft.windows.gdiplus_6595b64144ccf1df_*',
            'x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*',
            'x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*',
            'x86_microsoft-windows-s..ngstack-onecorebase_31bf3856ad364e35_*',
            'x86_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*',
            'x86_microsoft-windows-servicingstack_31bf3856ad364e35_*',
            'x86_microsoft-windows-servicingstack-inetsrv_*',
            'x86_microsoft-windows-servicingstack-onecore_*',
            'amd64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*',
            'amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*',
            'amd64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*',
            'amd64_microsoft.windows.common-controls_6595b64144ccf1df_*',
            'amd64_microsoft.windows.gdiplus_6595b64144ccf1df_*',
            'amd64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*',
            'amd64_microsoft.windows.isolationautomation_6595b64144ccf1df_*',
            'amd64_microsoft-windows-s..stack-inetsrv-extra_31bf3856ad364e35_*',
            'amd64_microsoft-windows-s..stack-msg.resources_31bf3856ad364e35_*',
            'amd64_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*',
            'amd64_microsoft-windows-servicingstack_31bf3856ad364e35_*',
            'amd64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*',
            'amd64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*',
            'amd64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*',
            'Catalogs', 'FileMaps', 'Fusion', 'InstallTemp', 'Manifests',
            'x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*',
            'x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*',
            'x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*'
        )
    } else {
        $dirsToCopy = @('Catalogs', 'FileMaps', 'Fusion', 'InstallTemp', 'Manifests')
    }

    foreach ($dir in $dirsToCopy) {
        $sourceDirs = Get-ChildItem -Path $sourceDirectory -Filter $dir -Directory -ErrorAction SilentlyContinue
        foreach ($sourceDir in $sourceDirs) {
            $destDir = Join-Path $destinationDirectory $sourceDir.Name
            Copy-Item -Path $sourceDir.FullName -Destination $destDir -Recurse -Force
        }
    }

    Remove-Item -Path $sourceDirectory -Recurse -Force
    Rename-Item -Path $destinationDirectory -NewName 'WinSxS'
    Add-GuiLog 'WinSxS optimized' 'INFO'
}

function Remove-Services {
    param([string]$ScratchDir)
    Add-GuiLog 'Removing unnecessary services...' 'INFO'
    reg load HKLM\zSYSTEM "$ScratchDir\Windows\System32\config\SYSTEM" | Out-Null
    $services = @('Spooler', 'PrintNotify', 'Fax', 'RemoteRegistry', 'diagsvc', 'WerSvc', 'PcaSvc', 'MapsBroker',
                  'WalletService', 'BthAvctpSvc', 'BluetoothUserService', 'wuauserv', 'UsoSvc', 'WaaSMedicSvc')
    foreach ($svc in $services) {
        & 'reg' 'delete' "HKLM\zSYSTEM\ControlSet001\Services\$svc" /f | Out-Null
    }
    reg unload HKLM\zSYSTEM 2>$null
}

function Build-BootWim {
    param([string]$WorkDir, [string]$ScratchDir)
    Add-GuiLog 'Processing boot.wim...' 'INFO'
    $bootWim = "$WorkDir\sources\boot.wim"
    & takeown '/F' $bootWim | Out-Null
    & icacls $bootWim '/grant' "$($script:AdminGroup.Value):(F)" | Out-Null
    Set-ItemProperty -Path $bootWim -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

    $newBoot = "$WorkDir\sources\boot_new.wim"
    $finalBoot = "$WorkDir\sources\boot_final.wim"

    & 'dism' '/English' '/Export-Image' "/SourceImageFile:$bootWim" '/SourceIndex:2' "/DestinationImageFile:$newBoot" | Out-Null
    & 'dism' '/English' '/mount-image' "/imagefile:$newBoot" '/index:1' "/mountdir:$ScratchDir" | Out-Null

    reg load HKLM\zDEFAULT "$ScratchDir\Windows\System32\config\default" | Out-Null
    reg load HKLM\zNTUSER "$ScratchDir\Users\Default\ntuser.dat" | Out-Null
    reg load HKLM\zSOFTWARE "$ScratchDir\Windows\System32\config\SOFTWARE" | Out-Null
    reg load HKLM\zSYSTEM "$ScratchDir\Windows\System32\config\SYSTEM" | Out-Null

    Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'

    reg unload HKLM\zDEFAULT 2>$null
    reg unload HKLM\zNTUSER 2>$null
    reg unload HKLM\zSOFTWARE 2>$null
    reg unload HKLM\zSYSTEM 2>$null

    & 'dism' '/English' '/unmount-image' "/mountdir:$ScratchDir" '/commit' | Out-Null
    Remove-Item -Path $bootWim -Force -ErrorAction SilentlyContinue
    & 'dism' '/English' '/Export-Image' "/SourceImageFile:$newBoot" '/SourceIndex:1' "/DestinationImageFile:$finalBoot" '/compress:max' | Out-Null
    Remove-Item -Path $newBoot -Force -ErrorAction SilentlyContinue
    Rename-Item -Path $finalBoot -NewName 'boot.wim' -ErrorAction SilentlyContinue
}

function Export-InstallImage {
    param([string]$WorkDir, [string]$Mode, [int]$Index)
    Add-GuiLog 'Exporting final install image...' 'INFO'
    if ($Mode -eq 'Nano') {
        & dism /Export-Image /SourceImageFile:"$WorkDir\sources\install.wim" /SourceIndex:$Index /DestinationImageFile:"$WorkDir\sources\install.esd" /Compress:recovery | Out-Null
        Remove-Item "$WorkDir\sources\install.wim" -Force -ErrorAction SilentlyContinue
    } else {
        & 'dism' '/English' '/Export-Image' "/SourceImageFile:$WorkDir\sources\install.wim" "/SourceIndex:$Index" "/DestinationImageFile:$WorkDir\sources\install2.wim" '/compress:recovery' | Out-Null
        Remove-Item -Path "$WorkDir\sources\install.wim" -Force -ErrorAction SilentlyContinue
        Rename-Item -Path "$WorkDir\sources\install2.wim" -NewName 'install.wim' -ErrorAction SilentlyContinue
    }
}

function New-IsoImage {
    param([string]$WorkDir, [string]$OutputPath, [string]$OscdimgPath)
    Add-GuiLog 'Creating bootable ISO...' 'INFO'
    $letter = $WorkDir.TrimEnd('\').Substring(0, 2)
    & "$OscdimgPath" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$WorkDir\boot\etfsboot.com#pEF,e,b$WorkDir\efi\microsoft\boot\efisys.bin" "$WorkDir" "$OutputPath" | Out-Null
    Add-GuiLog "ISO created: $OutputPath" 'INFO'
}
#endregion

#region === BUILD ENGINE ===
function Start-BuildEngine {
    param([string]$SelectedMode)

    $script:IsBuilding = $true
    $script:BuildCancelled = $false
    $script:Window.Dispatcher.Invoke([action]{
        $script:txtStatus.Text = 'Building...'
        $script:txtStatus.Foreground = '#d29922'
        $script:btnBuild.IsEnabled = $false
        $script:btnCancel.IsEnabled = $true
    })

    Show-Page 'Progress'
    $driveLetter = Get-SelectedDriveLetter
    $scratchLetter = Get-SelectedScratchLetter
    $scratchDisk = "$scratchLetter`:"
    $workDir = "$scratchDisk\$($script:OutputName)"
    $scratchDir = "$scratchDisk\scratchdir"
    $outputIso = Join-Path $script:BaseDir "$($script:OutputName).iso"

    try {
        # Phase 1: Setup
        Update-Progress -Percent 5 -Step 'Setting up working directories...'
        Add-GuiLog "Starting $SelectedMode build..." 'INFO'
        Add-GuiLog "Source drive: $driveLetter`:" 'INFO'
        Add-GuiLog "Scratch disk: $scratchDisk" 'INFO'
        Process-DispatcherEvents

        if (Test-Path $workDir) { Remove-Item -Path $workDir -Recurse -Force }
        if (Test-Path $scratchDir) { Remove-Item -Path $scratchDir -Recurse -Force }
        New-Item -ItemType Directory -Path "$workDir\sources" -Force | Out-Null
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null

        # Copy ISO contents
        Update-Progress -Percent 10 -Step 'Copying Windows image...'
        Add-GuiLog 'Copying ISO contents...' 'INFO'
        Copy-Item -Path "$driveLetter`:\*" -Destination $workDir -Recurse -Force | Out-Null
        Remove-Item "$workDir\sources\install.esd" -Force -ErrorAction SilentlyContinue
        Process-DispatcherEvents

        # Handle ESD if present
        if (-not (Test-Path "$workDir\sources\install.wim")) {
            if (Test-Path "$driveLetter`:\sources\install.esd") {
                Add-GuiLog 'Converting install.esd to install.wim...' 'INFO'
                & 'dism' '/English' '/Get-WimInfo' "/wimfile:$driveLetter`:\sources\install.esd" | Out-Null
                $script:Window.Dispatcher.Invoke([action]{
                    [System.Windows.MessageBox]::Show('The source uses install.esd format. Using index 1 by default.', 'ESD Detected', 'OK', 'Information')
                })
                $index = 1
                & 'DISM' /Export-Image /SourceImageFile:"$driveLetter`:\sources\install.esd" /SourceIndex:$index /DestinationImageFile:"$workDir\sources\install.wim" /Compress:max /CheckIntegrity | Out-Null
            } else {
                throw 'No install.wim or install.esd found in source drive!'
            }
        }

        # Get image info
        Update-Progress -Percent 15 -Step 'Getting image information...'
        Process-DispatcherEvents
        $imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$workDir\sources\install.wim"
        $lines = $imageInfo -split '\r?\n'
        $architecture = $null
        foreach ($line in $lines) {
            if ($line -like '*Architecture : *') {
                $architecture = $line -replace 'Architecture : ',''
                if ($architecture -eq 'x64') { $architecture = 'amd64' }
                break
            }
        }
        Add-GuiLog "Architecture: $architecture" 'INFO'

        # Get language code
        $imageIntl = & dism /English /Get-Intl "/Image:$scratchDir"
        $languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }
        $languageCode = if ($languageLine) { $matches[1] } else { 'en-us' }
        Add-GuiLog "Language code: $languageCode" 'INFO'

        # Determine index
        $index = 1
        if ($script:cmbIndex.SelectedItem -and $script:cmbIndex.SelectedItem -match '(\d+)') {
            $index = [int]$matches[1]
        }

        # Mount install.wim
        Update-Progress -Percent 20 -Step 'Mounting install.wim...'
        Process-DispatcherEvents
        $wimFile = "$workDir\sources\install.wim"
        & takeown '/F' $wimFile | Out-Null
        & icacls $wimFile '/grant' "$($script:AdminGroup.Value):(F)" | Out-Null
        Set-ItemProperty -Path $wimFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        & dism /English '/mount-image' "/imagefile:$wimFile" "/index:$index" "/mountdir:$scratchDir" | Out-Null

        # === MODE-SPECIFIC PROCESSING ===
        if ($SelectedMode -eq 'Standard') {
            # Standard Tiny11 mode
            Update-Progress -Percent 30 -Step 'Removing AppX packages...'
            Process-DispatcherEvents
            Remove-AppxBloat -ScratchDir $scratchDir -ExtraPatterns @()

            Update-Progress -Percent 40 -Step 'Removing Edge and OneDrive...'
            Process-DispatcherEvents
            Remove-EdgeAndOneDrive -ScratchDir $scratchDir -Architecture $architecture

            Update-Progress -Percent 50 -Step 'Applying registry tweaks...'
            Process-DispatcherEvents
            Apply-RegistryTweaks -ScratchDir $scratchDir -Mode 'Standard'

            Update-Progress -Percent 60 -Step 'Cleaning up image...'
            Process-DispatcherEvents
            & dism /English "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' | Out-Null

        } elseif ($SelectedMode -eq 'Core') {
            # Tiny11 Core mode
            Update-Progress -Percent 25 -Step 'Removing AppX packages...'
            Process-DispatcherEvents
            Remove-AppxBloat -ScratchDir $scratchDir -ExtraPatterns @()

            Update-Progress -Percent 35 -Step 'Removing Edge and OneDrive...'
            Process-DispatcherEvents
            Remove-EdgeAndOneDrive -ScratchDir $scratchDir -Architecture $architecture

            Update-Progress -Percent 45 -Step 'Removing system packages...'
            Process-DispatcherEvents
            Remove-SystemPackages -ScratchDir $scratchDir -LanguageCode $languageCode -ExtraPatterns @(
                'Windows-Defender-Client-Package~',
                'Microsoft-Windows-Search-Engine-Client-Package~'
            )

            Update-Progress -Percent 55 -Step 'Removing WinRE...'
            Process-DispatcherEvents
            Remove-Item -Path "$scratchDir\Windows\System32\Recovery\winre.wim" -Force -ErrorAction SilentlyContinue
            New-Item -Path "$scratchDir\Windows\System32\Recovery\winre.wim" -ItemType File -Force | Out-Null

            # Enable .NET 3.5 if checked
            if ($script:chkNet35.IsChecked) {
                Update-Progress -Percent 58 -Step 'Enabling .NET 3.5...'
                Add-GuiLog 'Enabling .NET Framework 3.5...' 'INFO'
                & 'dism' "/image:$scratchDir" '/enable-feature' '/featurename:NetFX3' '/All' "/source:$workDir\sources\sxs" | Out-Null
            }

            Update-Progress -Percent 60 -Step 'Applying registry tweaks...'
            Process-DispatcherEvents
            Apply-RegistryTweaks -ScratchDir $scratchDir -Mode 'Core'

            Update-Progress -Percent 70 -Step 'Cleaning up image...'
            Process-DispatcherEvents
            & dism /English "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' | Out-Null

        } else {
            # Nano11 mode
            Update-Progress -Percent 25 -Step 'Removing AppX packages (aggressive)...'
            Process-DispatcherEvents
            Remove-AppxBloat -ScratchDir $scratchDir -ExtraPatterns @('*SecHealthUI*', '*Photos*', '*Camera*', '*Paint*', '*Notepad*')

            Update-Progress -Percent 30 -Step 'Removing Edge and OneDrive...'
            Process-DispatcherEvents
            Remove-EdgeAndOneDrive -ScratchDir $scratchDir -Architecture $architecture

            Update-Progress -Percent 35 -Step 'Removing system packages...'
            Process-DispatcherEvents
            Remove-SystemPackages -ScratchDir $scratchDir -LanguageCode $languageCode -ExtraPatterns @(
                'Windows-Defender-Client-Package~',
                'Microsoft-Windows-Search-Engine-Client-Package~',
                'Microsoft-Windows-Kernel-LA57-FoD-Package~',
                'Microsoft-Windows-Hello-Face-Package~',
                'Microsoft-Windows-Hello-BioEnrollment-Package~',
                'Microsoft-Windows-BitLocker-DriveEncryption-FVE-Package~',
                'Microsoft-Windows-TPM-WMI-Provider-Package~',
                'Microsoft-Windows-Narrator-App-Package~',
                'Microsoft-Windows-Magnifier-App-Package~',
                'Microsoft-Windows-Printing-PMCPPC-FoD-Package~',
                'Microsoft-Windows-WebcamExperience-Package~',
                'Microsoft-Media-MPEG2-Decoder-Package~',
                'Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package~',
                'Microsoft-Windows-MSPaint-FoD-Package~',
                'Microsoft-Windows-SnippingTool-FoD-Package~',
                'Microsoft-Windows-PowerShell-ISE-FOD-Package~',
                'OpenSSH-Client-Package~',
                'Microsoft-Windows-Xps-Xps-Viewer-Opt-Package~'
            )

            Update-Progress -Percent 45 -Step 'Performing Nano11-specific removals...'
            Process-DispatcherEvents
            Remove-NanoSpecific -ScratchDir $scratchDir -Architecture $architecture

            Update-Progress -Percent 55 -Step 'Optimizing WinSxS...'
            Process-DispatcherEvents
            Optimize-WinSxS -ScratchDir $scratchDir -Architecture $architecture

            Update-Progress -Percent 60 -Step 'Removing services...'
            Process-DispatcherEvents
            Remove-Services -ScratchDir $scratchDir

            Update-Progress -Percent 65 -Step 'Applying registry tweaks...'
            Process-DispatcherEvents
            Apply-RegistryTweaks -ScratchDir $scratchDir -Mode 'Nano'

            Update-Progress -Percent 75 -Step 'Final cleanup...'
            Process-DispatcherEvents
            & dism /English "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' | Out-Null
        }

        # Unmount install.wim
        Update-Progress -Percent 80 -Step 'Unmounting install.wim...'
        Process-DispatcherEvents
        & dism /English '/unmount-image' "/mountdir:$scratchDir" '/commit' | Out-Null

        # Export install image
        Update-Progress -Percent 85 -Step 'Exporting install image...'
        Process-DispatcherEvents
        Export-InstallImage -WorkDir $workDir -Mode $SelectedMode -Index $index

        # Process boot.wim
        Update-Progress -Percent 90 -Step 'Processing boot.wim...'
        Process-DispatcherEvents
        Build-BootWim -WorkDir $workDir -ScratchDir $scratchDir

        # Copy autounattend to root
        $autoPath = Join-Path $script:BaseDir 'autounattend.xml'
        if (Test-Path $autoPath) {
            Copy-Item -Path $autoPath -Destination "$workDir\autounattend.xml" -Force | Out-Null
        }

        # Create ISO
        Update-Progress -Percent 95 -Step 'Creating ISO...'
        Process-DispatcherEvents
        $oscdimg = Download-Oscdimg
        if ($oscdimg) {
            New-IsoImage -WorkDir $workDir -OutputPath $outputIso -OscdimgPath $oscdimg
        }

        # Cleanup
        Update-Progress -Percent 100 -Step 'Build complete!'
        Add-GuiLog "Build completed successfully!" 'INFO'
        Add-GuiLog "Output: $outputIso" 'INFO'

        # Eject ISO
        try { Get-Volume -DriveLetter $driveLetter | Get-DiskImage | Dismount-DiskImage | Out-Null } catch {}

        $script:Window.Dispatcher.Invoke([action]{
            [System.Windows.MessageBox]::Show("Build completed successfully!`n`nOutput: $outputIso", 'Success', 'OK', 'Information')
        })

    } catch {
        Add-GuiLog "ERROR: $_" 'ERROR'
        $script:Window.Dispatcher.Invoke([action]{
            [System.Windows.MessageBox]::Show("Build failed:`n$_", 'Error', 'OK', 'Error')
        })
        # Try cleanup
        & dism /English '/unmount-image' "/mountdir:$scratchDir" '/discard' 2>$null
    } finally {
        # Final cleanup
        Add-GuiLog 'Performing cleanup...' 'INFO'
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $script:BaseDir 'oscdimg.exe') -Force -ErrorAction SilentlyContinue

        $script:IsBuilding = $false
        $script:Window.Dispatcher.Invoke([action]{
            $script:txtStatus.Text = 'Ready'
            $script:txtStatus.Foreground = '#8b949e'
            $script:btnBuild.IsEnabled = $true
            $script:btnCancel.IsEnabled = $false
        })
    }
}
#endregion

#region === Event Handlers ===
# Navigation
$script:btnNavHome.Add_Click({ Show-Page 'Home' })
$script:btnNavConfig.Add_Click({ Show-Page 'Config' })
$script:btnNavProgress.Add_Click({ Show-Page 'Progress' })
$script:btnNavAbout.Add_Click({ Show-Page 'About' })

# Mode selection
$script:cardStandard.Add_MouseLeftButtonUp({ Set-Mode 'Standard'; Show-Page 'Config' })
$script:cardCore.Add_MouseLeftButtonUp({ Set-Mode 'Core'; Show-Page 'Config' })
$script:cardNano.Add_MouseLeftButtonUp({ Set-Mode 'Nano'; Show-Page 'Config' })

# Refresh drives
$script:btnRefreshDrives.Add_Click({
    Add-GuiLog 'Refreshing drive list...' 'INFO'
    Refresh-DriveList
})

# Build button
$script:btnBuild.Add_Click({
    $err = Test-Prerequisites
    if ($err) {
        [System.Windows.MessageBox]::Show($err, 'Prerequisites Not Met', 'OK', 'Warning')
        return
    }

    $script:OutputName = $script:txtOutputName.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($script:OutputName)) { $script:OutputName = 'Tiny11all' }

    $result = [System.Windows.MessageBox]::Show(
        "Ready to build with mode: $($script:BuildMode)`n`nSource: $(Get-SelectedDriveLetter)`:`nScratch: $(Get-SelectedScratchLetter)`:`nOutput: $($script:OutputName).iso`n`nThis process may take 30-60 minutes. Continue?",
        'Confirm Build',
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        $script:txtLog.Clear()
        # Run build - UI will be busy but window stays responsive via Dispatcher hooks
        Start-BuildEngine -SelectedMode $script:BuildMode
    }
})

# Cancel button
$script:btnCancel.Add_Click({
    $script:BuildCancelled = $true
    Add-GuiLog 'Build cancellation requested...' 'WARN'
    $script:btnCancel.IsEnabled = $false
})

# Clear log
$script:btnClearLog.Add_Click({ $script:txtLog.Clear() })
#endregion

#region === Main ===
# Initialize
Set-Mode $script:BuildMode
Refresh-DriveList

# Populate image index combo
$script:cmbIndex.Items.Add('1 - Auto detect')
$script:cmbIndex.Items.Add('1')
$script:cmbIndex.Items.Add('2')
$script:cmbIndex.Items.Add('3')
$script:cmbIndex.Items.Add('4')
$script:cmbIndex.Items.Add('5')
$script:cmbIndex.Items.Add('6')
$script:cmbIndex.SelectedIndex = 0

# Show window
Add-GuiLog 'Tiny11all ready. Select a build mode to begin.' 'INFO'
$script:Window.ShowDialog() | Out-Null
#endregion
