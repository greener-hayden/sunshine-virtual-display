#requires -version 5.1
<#
.SYNOPSIS
    Utility functions to install/uninstall the Sunshine virtual display driver.
.DESCRIPTION
    Provides commands to install or remove the Sunshine virtual display driver
    with validation for administrator rights, Sunshine presence and internet
    connectivity. Sunshine's service is stopped and started gracefully and its
    configuration is backed up before modification. Errors trigger rollback of
    configuration and driver installation.
#>

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
    param([string]$Host = '8.8.8.8')
    try { Test-Connection -ComputerName $Host -Quiet -Count 1 -ErrorAction Stop } catch { $false }
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

    $sunshine = Find-Sunshine
    $service = Get-Service -Name 'SunshineService' -ErrorAction SilentlyContinue
    $wasRunning = $false
    $infPath = $null
    $backup  = $null

    try {
        if ($service -and $service.Status -eq 'Running') {
            Stop-Service $service -Force -ErrorAction Stop
            $service.WaitForStatus('Stopped','00:00:20')
            $wasRunning = $true
        }

        $infPath = Install-VirtualDisplay
        $backup  = Update-SunshineConfig -SunshinePath $sunshine

        if ($service) { Start-Service $service -ErrorAction Stop }
        Write-Output 'Sunshine virtual display installed successfully.'
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

    $sunshine = Find-Sunshine
    $service = Get-Service -Name 'SunshineService' -ErrorAction SilentlyContinue
    $wasRunning = $false
    $configFile = Join-Path $sunshine 'config\sunshine.conf'
    $backupFile = "$configFile.bak"

    try {
        if ($service -and $service.Status -eq 'Running') {
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

        if ($service) { Start-Service $service -ErrorAction Stop }
        Write-Output 'Sunshine virtual display removed successfully.'
    }
    catch {
        Write-Error "Uninstall failed: $_"
        if ($service -and $wasRunning) { try { Start-Service $service -ErrorAction SilentlyContinue } catch {} }
        throw 'Uninstall encountered errors.'
    }
}
