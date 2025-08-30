# Sunshine Virtual Display Runtime Hook
# Handles resolution switching on connect/disconnect
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Connect', 'Disconnect')]
    [string]$Action
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptPath "settings.json"
$tempRoot = Join-Path $scriptPath "_temp"
$sessionId = "session-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$sessionPath = Join-Path $tempRoot $sessionId
$logPath = Join-Path $sessionPath "runtime.log"

# Create session directory
if ($Action -eq "Connect") {
    New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
}

function Write-Log {
    param($Message, $Type = "INFO")
    if (-not (Test-Path $sessionPath)) { return }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    Add-Content -Path $logPath -Value $logMessage -Force
    
    if ($Type -eq "ERROR") {
        # Keep logs on error
        $script:keepLogs = $true
    }
}

function Get-ResolutionAutomation {
    param($Settings)
    
    $depsPath = Join-Path $sessionPath "deps"
    $raPath = Join-Path $depsPath "ResolutionAutomation"
    
    if (Test-Path "$raPath\ResolutionAutomation.exe") {
        Write-Log "ResolutionAutomation already cached"
        return "$raPath\ResolutionAutomation.exe"
    }
    
    Write-Log "Downloading ResolutionAutomation..."
    New-Item -ItemType Directory -Path $depsPath -Force | Out-Null
    
    $channel = $Settings.ResolutionAutomation.Channel
    $tag = if ($channel -eq "PinnedTag") { $Settings.ResolutionAutomation.Tag } else { "latest" }
    
    # Construct GitHub release URL
    $baseUrl = "https://github.com/YourOrg/ResolutionAutomation/releases"
    $downloadUrl = if ($tag -eq "latest") {
        "$baseUrl/latest/download/ResolutionAutomation.zip"
    } else {
        "$baseUrl/download/$tag/ResolutionAutomation.zip"
    }
    
    $zipPath = Join-Path $depsPath "ResolutionAutomation.zip"
    
    try {
        # Download with retry logic
        $retries = 3
        while ($retries -gt 0) {
            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
                break
            } catch {
                $retries--
                if ($retries -eq 0) { throw }
                Start-Sleep -Seconds 2
            }
        }
        
        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $raPath -Force
        Remove-Item $zipPath -Force
        
        Write-Log "ResolutionAutomation downloaded and extracted"
        return "$raPath\ResolutionAutomation.exe"
    } catch {
        Write-Log "Failed to download ResolutionAutomation: $_" "ERROR"
        return $null
    }
}

function Parse-ClientResolution {
    # Parse Sunshine environment variables
    $width = $env:SUNSHINE_CLIENT_WIDTH
    $height = $env:SUNSHINE_CLIENT_HEIGHT
    $fps = $env:SUNSHINE_CLIENT_FPS
    
    if (-not $width -or -not $height -or -not $fps) {
        # Fallback to parsing from command line or config
        Write-Log "Using fallback resolution detection"
        $width = 1920
        $height = 1080
        $fps = 60
    }
    
    Write-Log "Client requested: ${width}x${height}@${fps}Hz"
    
    return @{
        Width = [int]$width
        Height = [int]$height
        RefreshRate = [int]$fps
    }
}

function Apply-ModeOverrides {
    param($Resolution, $Settings)
    
    $key = "$($Resolution.Width)x$($Resolution.Height)x$($Resolution.RefreshRate)"
    
    foreach ($override in $Settings.ModeOverrides) {
        if ($override -match "^$key=(.+)$") {
            $newMode = $matches[1]
            if ($newMode -match "^(\d+)x(\d+)x(\d+)$") {
                Write-Log "Applying override: $key → $newMode"
                return @{
                    Width = [int]$matches[1]
                    Height = [int]$matches[2]
                    RefreshRate = [int]$matches[3]
                }
            }
        }
    }
    
    return $Resolution
}

function Set-DisplayResolution {
    param($Resolution, $DisplayName, $RaPath)
    
    if (-not $RaPath -or -not (Test-Path $RaPath)) {
        Write-Log "ResolutionAutomation not available" "ERROR"
        return $false
    }
    
    $args = @(
        "start",
        "--display", $DisplayName,
        "--width", $Resolution.Width,
        "--height", $Resolution.Height,
        "--refresh", $Resolution.RefreshRate
    )
    
    Write-Log "Executing: $RaPath $($args -join ' ')"
    
    try {
        $process = Start-Process -FilePath $RaPath -ArgumentList $args -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log "Resolution applied successfully"
            return $true
        } else {
            Write-Log "ResolutionAutomation returned exit code: $($process.ExitCode)" "WARNING"
            
            # Try fallback resolutions
            $fallbackRates = @(90, 60, 30)
            foreach ($rate in $fallbackRates) {
                if ($rate -ge $Resolution.RefreshRate) { continue }
                
                Write-Log "Trying fallback refresh rate: $rate Hz"
                $args[5] = $rate
                $process = Start-Process -FilePath $RaPath -ArgumentList $args -NoNewWindow -Wait -PassThru
                if ($process.ExitCode -eq 0) {
                    Write-Log "Fallback resolution applied: $($Resolution.Width)x$($Resolution.Height)@${rate}Hz"
                    return $true
                }
            }
        }
    } catch {
        Write-Log "Failed to set resolution: $_" "ERROR"
    }
    
    return $false
}

function Restore-DisplayResolution {
    param($DisplayName, $RaPath)
    
    if (-not $RaPath -or -not (Test-Path $RaPath)) {
        Write-Log "ResolutionAutomation not available for restore" "WARNING"
        return
    }
    
    $args = @("stop", "--display", $DisplayName)
    
    try {
        Start-Process -FilePath $RaPath -ArgumentList $args -NoNewWindow -Wait
        Write-Log "Display resolution restored"
    } catch {
        Write-Log "Failed to restore resolution: $_" "WARNING"
    }
}

# Main execution
try {
    if (-not (Test-Path $settingsPath)) {
        Write-Log "Settings file not found" "ERROR"
        exit 1
    }
    
    $settings = Get-Content $settingsPath | ConvertFrom-Json
    $displayName = $settings.VirtualDisplay.VirtualDisplayName
    
    if (-not $displayName) {
        Write-Log "Virtual display name not configured" "ERROR"
        exit 1
    }
    
    switch ($Action) {
        'Connect' {
            Write-Log "=== Stream Connect ==="
            
            # Get ResolutionAutomation
            $raPath = Get-ResolutionAutomation -Settings $settings
            
            # Parse client resolution
            $resolution = Parse-ClientResolution
            
            # Apply overrides
            $resolution = Apply-ModeOverrides -Resolution $resolution -Settings $settings
            
            # Set display resolution
            if ($raPath) {
                Set-DisplayResolution -Resolution $resolution -DisplayName $displayName -RaPath $raPath
            } else {
                Write-Log "Continuing without resolution change" "WARNING"
            }
            
            Write-Log "Connect completed"
        }
        
        'Disconnect' {
            Write-Log "=== Stream Disconnect ==="
            
            # Find ResolutionAutomation if it exists
            $raPath = Get-ChildItem -Path $tempRoot -Filter "ResolutionAutomation.exe" -Recurse -ErrorAction SilentlyContinue | 
                Select-Object -First 1 -ExpandProperty FullName
            
            if ($raPath) {
                Restore-DisplayResolution -DisplayName $displayName -RaPath $raPath
            }
            
            # Clean up session temp (unless there were errors)
            if (-not $script:keepLogs) {
                Remove-Item -Path $sessionPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Session cleaned up"
            } else {
                Write-Log "Logs preserved due to errors"
            }
            
            Write-Log "Disconnect completed"
        }
    }
    
    exit 0
} catch {
    Write-Log "Fatal error: $_" "ERROR"
    exit 1
}