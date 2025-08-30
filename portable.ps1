#requires -version 5.1
<#
.SYNOPSIS
    Utility functions to install/uninstall the Sunshine virtual display driver.
.DESCRIPTION
    Provides commands to install or remove the Sunshine virtual display driver
    with validation for administrator rights, Sunshine presence and internet
    connectivity. Sunshine's service is stopped and started gracefully and its
    configuration is backed up before modification. Errors trigger rollback of
    configuration and driver installation. Settings are persisted in JSON format.
#>

param(
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$NoLogging
)

# Initialize logging if not disabled
if (-not $NoLogging) {
    $logDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    
    $action = if ($Install) { 'install' } elseif ($Uninstall) { 'uninstall' } else { 'status' }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $logDir "portable-$action-$timestamp.log"
    Start-Transcript -Path $logPath -Append | Out-Null
    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Logging to: $logPath"
}

#region Helper Functions
function Test-IsAdmin {
    <# Tests whether the current session has administrator privileges. #>
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

function Test-Internet {
    <# Returns $true if the machine can reach a public host. #>
    param([string]$TargetHost = '8.8.8.8')
    try { Test-Connection -ComputerName $TargetHost -Quiet -Count 1 -ErrorAction Stop } catch { $false }
}

function Get-Settings {
    <# Loads settings from JSON file or returns default settings. #>
    param([string]$Path = $SettingsPath)
    
    if (Test-Path $Path) {
        try {
            $settings = Get-Content $Path -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($settings.serviceName)) {
                $settings.serviceName = 'SunshineService'
            }
            return $settings
        } catch {
            Write-Warning "Failed to load settings from $Path"
        }
    }
    
    return [PSCustomObject]@{
        displayName = ""
        deviceId = ""
        sunshineConfigPath = ""
        sunshineConfigBackup = ""
        serviceName = "SunshineService"
        installDate = ""
        version = "1.0.0"
    }
}

function Save-Settings {
    <# Saves settings to JSON file. #>
    param(
        [Parameter(Mandatory)]$Settings,
        [string]$Path = $SettingsPath
    )
    
    try {
        $Settings | ConvertTo-Json -Depth 3 | Set-Content $Path -Encoding UTF8
        Write-Verbose "Settings saved to $Path"
    } catch {
        Write-Warning "Failed to save settings to $Path"
    }
}
#endregion Helper Functions

function Find-Sunshine {
    <# Locates the Sunshine installation directory. #>
    [CmdletBinding()]
    param()

    if (-not (Test-IsAdmin)) { throw 'Administrator privileges are required.' }

    $candidates = @(
        Join-Path $env:ProgramFiles     'Sunshine',
        Join-Path $env:ProgramFilesx86  'Sunshine'
    )

    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir 'sunshine.exe')) { return $dir }
    }
    throw 'Sunshine installation not found.'
}

function Install-VirtualDisplay {
    <# Downloads and installs the virtual display driver. #>
    [CmdletBinding()]
    param(
        [string]$DriverUrl = 'https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-virtual-display.zip'
    )

    if (-not (Test-IsAdmin))   { throw 'Administrator privileges are required.' }
    if (-not (Test-Internet)) { throw 'Internet connection is required.' }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $zip = Join-Path $tempDir 'driver.zip'

    try {
        Invoke-WebRequest -Uri $DriverUrl -OutFile $zip -ErrorAction Stop
        Expand-Archive -Path $zip -DestinationPath $tempDir -Force
        $inf = Get-ChildItem -Path $tempDir -Filter '*.inf' -Recurse | Select-Object -First 1
        if (-not $inf) { throw 'INF file not found in driver package.' }

        $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
        if (-not (Test-Path $pnputil)) { throw 'pnputil.exe not found.' }
        $args = "/add-driver `"$($inf.FullName)`" /install"
        $proc = Start-Process -FilePath $pnputil -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) { throw "pnputil exited with code $($proc.ExitCode)" }

        return $inf.FullName
    }
    catch {
        throw "Virtual display installation failed: $_"
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Update-SunshineConfig {
    <# Enables virtual display support in Sunshine's configuration. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SunshinePath)

    if (-not (Test-IsAdmin)) { throw 'Administrator privileges are required.' }

    $configDir  = Join-Path $SunshinePath 'config'
    $configFile = Join-Path $configDir 'sunshine.conf'
    if (-not (Test-Path $configFile)) { throw 'Sunshine configuration not found.' }

    $backup = "$configFile.bak"
    try {
        Copy-Item $configFile $backup -Force -ErrorAction Stop
        $content = Get-Content $configFile -ErrorAction Stop
        if ($content -notmatch 'virtual_display\s*=\s*true') {
            $content += 'virtual_display = true'
            Set-Content $configFile $content -ErrorAction Stop
        }
        return $backup
    }
    catch {
        if (Test-Path $backup) { Move-Item $backup $configFile -Force -ErrorAction SilentlyContinue }
        throw "Failed to update Sunshine configuration: $_"
    }
}

function Install-Portable {
    <# Installs the driver and updates Sunshine with rollback on failure. #>
    [CmdletBinding()]
    param()

    if (-not (Test-IsAdmin))   { throw 'Administrator privileges are required.' }
    if (-not (Test-Internet)) { throw 'Internet connection is required.' }

    $settings = Get-Settings
    $sunshine = Find-Sunshine
    $service = Get-Service -Name $settings.serviceName -ErrorAction SilentlyContinue
    $wasRunning = $false
    $infPath = $null
    $backup  = $null

    try {
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting installation process"
        if ($service -and $service.Status -eq 'Running') {
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Stopping Sunshine service"
            Stop-Service $service -Force -ErrorAction Stop
            $service.WaitForStatus('Stopped','00:00:20')
            $wasRunning = $true
        }

        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installing virtual display driver"
        $infPath = Install-VirtualDisplay
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Updating Sunshine configuration"
        $backup  = Update-SunshineConfig -SunshinePath $sunshine

        # Update settings with installation details
        $settings.sunshineConfigPath = Join-Path $sunshine 'config\sunshine.conf'
        $settings.sunshineConfigBackup = $backup
        $settings.installDate = (Get-Date).ToString('o')
        $settings.displayName = "Sunshine Virtual Display"
        $settings.deviceId = $infPath
        Save-Settings -Settings $settings

        if ($service) { 
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting Sunshine service"
            Start-Service $service -ErrorAction Stop 
        }
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Sunshine virtual display installed successfully."
    }
    catch {
        Write-Error $_
        if ($backup -and (Test-Path $backup)) {
            Move-Item $backup (Join-Path $sunshine 'config\sunshine.conf') -Force -ErrorAction SilentlyContinue
        }
        if ($infPath) {
            try { pnputil /delete-driver "$infPath" /uninstall /force | Out-Null } catch { Write-Warning $_ }
        }
        if ($service -and $wasRunning) {
            try { Start-Service $service -ErrorAction SilentlyContinue } catch {}
        }
        throw 'Installation failed; changes were rolled back.'
    }
}

function Uninstall-Portable {
    <# Removes the driver and restores Sunshine configuration. #>
    [CmdletBinding()]
    param()

    if (-not (Test-IsAdmin)) { throw 'Administrator privileges are required.' }

    $settings = Get-Settings
    $sunshine = Find-Sunshine
    $service = Get-Service -Name $settings.serviceName -ErrorAction SilentlyContinue
    $wasRunning = $false
    $configFile = Join-Path $sunshine 'config\sunshine.conf'
    $backupFile = "$configFile.bak"

    try {
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting uninstallation process"
        if ($service -and $service.Status -eq 'Running') {
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Stopping Sunshine service"
            Stop-Service $service -Force -ErrorAction Stop
            $service.WaitForStatus('Stopped','00:00:20')
            $wasRunning = $true
        }

        if (Test-Path $backupFile) {
            Move-Item $backupFile $configFile -Force -ErrorAction Stop
        } else {
            $content = Get-Content $configFile -ErrorAction SilentlyContinue
            $content = $content | Where-Object { $_ -notmatch 'virtual_display\s*=\s*true' }
            Set-Content $configFile $content -ErrorAction SilentlyContinue
        }

        try { pnputil /delete-driver 'sunshine-virtual-display.inf' /uninstall /force | Out-Null } catch { Write-Warning $_ }

        # Remove settings file
        if (Test-Path $SettingsPath) {
            Remove-Item $SettingsPath -Force
        }

        if ($service) { 
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting Sunshine service"
            Start-Service $service -ErrorAction Stop 
        }
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Sunshine virtual display removed successfully."
    }
    catch {
        Write-Error "Uninstall failed: $_"
        if ($service -and $wasRunning) { try { Start-Service $service -ErrorAction SilentlyContinue } catch {} }
        throw 'Uninstall encountered errors.'
    }
}

# Main execution
try {
    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Script started with parameters:"
    Write-Output "  Install: $Install"
    Write-Output "  Uninstall: $Uninstall"
    Write-Output "  SettingsPath: $SettingsPath"
    
    if ($Install) {
        Install-Portable
    } elseif ($Uninstall) {
        Uninstall-Portable
    } else {
        Write-Host "Usage: portable.ps1 [-Install | -Uninstall] [-SettingsPath <path>] [-NoLogging]"
        Write-Host ""
        Write-Host "  -Install      : Install the Sunshine virtual display driver"
        Write-Host "  -Uninstall    : Remove the Sunshine virtual display driver"
        Write-Host "  -SettingsPath : Path to settings.json file (default: .\settings.json)"
        Write-Host "  -NoLogging    : Disable logging to file"
    }
}
catch {
    $errorMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Error occurred: $_"
    Write-Error $errorMessage
    throw
}
finally {
    if (-not $NoLogging) {
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Script execution completed"
        Stop-Transcript | Out-Null
    }
}