param(
    [string]$SettingsPath = Join-Path $PSScriptRoot 'settings.json',
    [switch]$Uninstall,
    [string]$DisplayName,
    [string]$DeviceId,
    [string]$SunshineConfigPath,
    [string]$SunshineConfigBackup,
    [string]$ServiceName,
    [string]$Version
)

if ($Uninstall) {
    if (Test-Path $SettingsPath) {
        Remove-Item $SettingsPath -Force
    }
    return
}

if (Test-Path $SettingsPath) {
    try {
        $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    } catch {
        $settings = [ordered]@{}
    }
} else {
    $settings = [ordered]@{}
}

if ($DisplayName) { $settings.displayName = $DisplayName }
if ($DeviceId) { $settings.deviceId = $DeviceId }
if ($SunshineConfigPath) { $settings.sunshineConfigPath = $SunshineConfigPath }
if ($SunshineConfigBackup) { $settings.sunshineConfigBackup = $SunshineConfigBackup }
if ($ServiceName) { $settings.serviceName = $ServiceName }
if (-not $settings.installDate) { $settings.installDate = (Get-Date).ToString('o') }
if ($Version) { $settings.version = $Version }

$settings | ConvertTo-Json -Depth 3 | Set-Content $SettingsPath -Encoding UTF8
