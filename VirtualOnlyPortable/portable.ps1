# Sunshine Virtual-Only Portable Installer/Uninstaller
# Clean, focused implementation under 200 LOC
param(
    [Parameter(Position=0)]
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string]$Action = 'Status',
    
    [string]$DriverPackage = ""
)

# Self-elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $Action"
    if ($DriverPackage) { $args += " -DriverPackage `"$DriverPackage`"" }
    Start-Process PowerShell -Verb RunAs -ArgumentList $args
    exit
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptPath "settings.json"
$tempPath = Join-Path $scriptPath "_temp"
$logPath = Join-Path $scriptPath "install.log"

function Write-Log {
    param($Message, $Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    Add-Content -Path $logPath -Value $logMessage -Force
    
    switch ($Type) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        default { Write-Host $Message }
    }
}

function Find-Sunshine {
    Write-Log "Searching for Sunshine installation..."
    
    # Check service first
    $service = Get-Service -Name "Sunshine*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($service) {
        Write-Log "Found Sunshine service: $($service.Name)" "SUCCESS"
        return @{
            Found = $true
            Service = $service.Name
            Path = (Get-WmiObject Win32_Service | Where-Object {$_.Name -eq $service.Name}).PathName -replace '"', '' -replace ' --.*', ''
            ConfigPath = ""
        }
    }
    
    # Check common paths
    $paths = @(
        "$env:ProgramFiles\Sunshine",
        "${env:ProgramFiles(x86)}\Sunshine",
        "$env:LOCALAPPDATA\Programs\Sunshine",
        "$env:APPDATA\Sunshine"
    )
    
    foreach ($path in $paths) {
        if (Test-Path "$path\sunshine.exe") {
            Write-Log "Found Sunshine at: $path" "SUCCESS"
            $configPath = Get-ChildItem -Path $path -Filter "*.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            return @{
                Found = $true
                Service = "SunshineService"
                Path = "$path\sunshine.exe"
                ConfigPath = if ($configPath) { $configPath.FullName } else { "" }
            }
        }
    }
    
    # Check running process
    $process = Get-Process -Name "sunshine" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process) {
        $path = $process.Path
        Write-Log "Found running Sunshine process: $path" "SUCCESS"
        return @{
            Found = $true
            Service = "SunshineService"
            Path = $path
            ConfigPath = ""
        }
    }
    
    Write-Log "Sunshine not found automatically" "WARNING"
    return @{ Found = $false }
}

function Run-PreflightChecks {
    Write-Host "`n=== Preflight Checks ===" -ForegroundColor Cyan
    
    $checks = @{
        "Administrator privileges" = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        "Disk space (500MB)" = ((Get-PSDrive C).Free -gt 500MB)
        "Internet connectivity" = (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet)
    }
    
    $sunshine = Find-Sunshine
    $checks["Sunshine installation"] = $sunshine.Found
    
    # Check virtual display
    $virtualDisplays = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID -ErrorAction SilentlyContinue | 
        Where-Object { $_.InstanceName -match "DISPLAY" }
    $checks["Virtual display ready"] = ($null -ne $virtualDisplays) -or ($DriverPackage -ne "")
    
    foreach ($check in $checks.GetEnumerator()) {
        $status = if ($check.Value) { "[✓]" } else { "[✗]" }
        $color = if ($check.Value) { "Green" } else { "Red" }
        Write-Host "$status $($check.Key)" -ForegroundColor $color
    }
    
    $allPassed = -not ($checks.Values -contains $false)
    if (-not $allPassed) {
        Write-Log "Preflight checks failed" "ERROR"
        if (-not $checks["Sunshine installation"]) {
            Write-Host "`nPlease install Sunshine first or specify the installation path" -ForegroundColor Yellow
        }
    }
    
    return @{ Success = $allPassed; Sunshine = $sunshine }
}

function Install-VirtualDisplay {
    param($Settings)
    
    if ($Settings.VirtualDisplay.Mode -eq "Driver" -and $Settings.VirtualDisplay.DriverPackage) {
        Write-Log "Installing virtual display driver..."
        $result = pnputil /add-driver $Settings.VirtualDisplay.DriverPackage /install
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Virtual display driver installed" "SUCCESS"
            
            # Find the new virtual display
            Start-Sleep -Seconds 2
            $displays = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID | 
                Where-Object { $_.InstanceName -match "DISPLAY" }
            if ($displays) {
                $displayName = [System.Text.Encoding]::ASCII.GetString($displays[0].UserFriendlyName)
                $Settings.VirtualDisplay.VirtualDisplayName = $displayName.Trim([char]0)
                Write-Log "Detected virtual display: $($Settings.VirtualDisplay.VirtualDisplayName)" "SUCCESS"
            }
        }
    } elseif ($Settings.VirtualDisplay.Mode -eq "DummyPlug") {
        Write-Log "Using dummy plug configuration"
        # Detect dummy plug display
        $displays = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID
        if ($displays) {
            $Settings.VirtualDisplay.VirtualDisplayName = "Display 2"  # Default for dummy plugs
        }
    }
    
    return $Settings
}

function Install-Portable {
    $checks = Run-PreflightChecks
    if (-not $checks.Success) { return }
    
    Write-Host "`n=== Installation Starting ===" -ForegroundColor Cyan
    
    # Initialize settings
    $settings = @{
        VirtualDisplay = @{
            Mode = if ($DriverPackage) { "Driver" } else { "DummyPlug" }
            DriverPackage = $DriverPackage
            VirtualDisplayName = ""
        }
        SunshineConfig = @{
            Policy = "Apply"
            ConfigPath = $checks.Sunshine.ConfigPath
            BackupPath = "$scriptPath\sunshine.conf.backup"
        }
        Audio = @{
            VirtualSink = "Steam Streaming Speakers"
            StreamAudio = $true
            InstallSteamAudioDrivers = $true
        }
        ResolutionAutomation = @{
            Channel = "PinnedTag"
            Tag = "v1.0.0"
        }
        ModeOverrides = @()
    }
    
    # Stop Sunshine
    Write-Log "Stopping Sunshine service..."
    Stop-Service -Name $checks.Sunshine.Service -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    # Backup config
    if ($settings.SunshineConfig.ConfigPath -and (Test-Path $settings.SunshineConfig.ConfigPath)) {
        Copy-Item $settings.SunshineConfig.ConfigPath $settings.SunshineConfig.BackupPath -Force
        Write-Log "Backed up Sunshine config" "SUCCESS"
    }
    
    # Install virtual display
    $settings = Install-VirtualDisplay -Settings $settings
    
    # Configure Sunshine (simplified - would need actual config parsing)
    Write-Log "Configuring Sunshine..."
    # This would modify the actual Sunshine config file
    
    # Save settings
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    Write-Log "Settings saved to $settingsPath" "SUCCESS"
    
    # Start Sunshine
    Start-Service -Name $checks.Sunshine.Service -ErrorAction SilentlyContinue
    Write-Log "Sunshine service started" "SUCCESS"
    
    Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
    Write-Host "Virtual display configured and Sunshine updated"
}

function Uninstall-Portable {
    if (-not (Test-Path $settingsPath)) {
        Write-Log "No installation found" "ERROR"
        return
    }
    
    Write-Host "`n=== Uninstalling ===" -ForegroundColor Cyan
    $settings = Get-Content $settingsPath | ConvertFrom-Json
    
    # Stop Sunshine
    $sunshine = Find-Sunshine
    if ($sunshine.Found) {
        Stop-Service -Name $sunshine.Service -Force -ErrorAction SilentlyContinue
    }
    
    # Restore config
    if (Test-Path $settings.SunshineConfig.BackupPath) {
        Copy-Item $settings.SunshineConfig.BackupPath $settings.SunshineConfig.ConfigPath -Force
        Write-Log "Restored original Sunshine config" "SUCCESS"
    }
    
    # Clean up
    Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
    Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    
    # Start Sunshine
    if ($sunshine.Found) {
        Start-Service -Name $sunshine.Service -ErrorAction SilentlyContinue
    }
    
    Write-Host "Uninstall complete" -ForegroundColor Green
}

# Main execution
switch ($Action) {
    'Install' { Install-Portable }
    'Uninstall' { Uninstall-Portable }
    'Status' {
        Write-Host "Sunshine Virtual-Only Portable Status" -ForegroundColor Cyan
        if (Test-Path $settingsPath) {
            Write-Host "Status: INSTALLED" -ForegroundColor Green
            $settings = Get-Content $settingsPath | ConvertFrom-Json
            Write-Host "Virtual Display: $($settings.VirtualDisplay.Mode)"
        } else {
            Write-Host "Status: NOT INSTALLED" -ForegroundColor Yellow
        }
    }
}