[CmdletBinding(DefaultParameterSetName='Enable')]
param(
    [Parameter(ParameterSetName='Enable')]
    [switch]$Enable,

    [Parameter(ParameterSetName='Disable')]
    [switch]$Disable,
    
    [Parameter()]
    [switch]$NoLogging
)

# Initialize logging if not disabled
if (-not $NoLogging) {
    $logDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    
    $action = if ($Enable) { 'enable' } elseif ($Disable) { 'disable' } else { 'status' }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $logDir "auto_display-$action-$timestamp.log"
    Start-Transcript -Path $logPath -Append | Out-Null
    Write-Output "Logging to: $logPath"
}

try {
    function Get-VirtualDisplay {
        <#
            Acquire the DisplayManager COM object and return the first virtual display.
            This uses the Windows Runtime type Windows.System.Display.DisplayManager.
        #>
        $displayManagerType = [Windows.System.Display.DisplayManager, Windows.System.Display, ContentType=WindowsRuntime]
        $manager = $displayManagerType::GetForCurrentView()
        if (-not $manager) {
            throw "DisplayManager is not available on this system."
        }
        $virtual = $manager.GetDisplays() | Where-Object { $_.ConnectionKind -eq 'Virtual' } | Select-Object -First 1
        return @{ Manager = $manager; Display = $virtual }
    }

    function Set-DisplayConfig {
        param(
            [switch]$Enable,
            [switch]$Disable
        )
        <#
            Enable or disable the virtual display using DisplayManager.
            A global controller is kept for cleanup.
        #>
        if ($Enable) {
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Enabling virtual display..."
            $info = Get-VirtualDisplay
            $result = $info.Manager.TryStartVirtualDisplay($info.Display)
            if (-not $result.Succeeded) {
                throw "Failed to enable virtual display: $($result.Error)"
            }
            $script:VirtualDisplayController = $result.Controller
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Virtual display enabled successfully"
            return
        }
        if ($Disable) {
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Disabling virtual display..."
            $script:VirtualDisplayController?.Close()
            $script:VirtualDisplayController = $null
            Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Virtual display disabled successfully"
        }
    }

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public class DisplayUtil {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DEVMODE {
        private const int CCHDEVICENAME = 32;
        private const int CCHFORMNAME = 32;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=CCHDEVICENAME)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=CCHFORMNAME)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(
        string lpszDeviceName,
        ref DEVMODE lpDevMode,
        IntPtr hwnd,
        uint dwflags,
        IntPtr lParam);

    public const int DM_PELSWIDTH = 0x80000;
    public const int DM_PELSHEIGHT = 0x100000;
    public const int DM_DISPLAYFREQUENCY = 0x400000;
    public const int CDS_UPDATEREGISTRY = 0x00000001;
    public const int CDS_FULLSCREEN = 0x00000004;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
}
"@

    function Set-Resolution {
        param(
            [int]$Width,
            [int]$Height,
            [int]$RefreshRate,
            [string]$DeviceName = $null
        )
        <#
            Change the resolution of the supplied display using ChangeDisplaySettingsEx.
        #>
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Setting resolution to ${Width}x${Height} @ ${RefreshRate}Hz"
        $dev = New-Object DisplayUtil+DEVMODE
        $dev.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dev)
        $dev.dmFields = [DisplayUtil]::DM_PELSWIDTH -bor [DisplayUtil]::DM_PELSHEIGHT -bor [DisplayUtil]::DM_DISPLAYFREQUENCY
        $dev.dmPelsWidth = $Width
        $dev.dmPelsHeight = $Height
        $dev.dmDisplayFrequency = $RefreshRate

        $ret = [DisplayUtil]::ChangeDisplaySettingsEx($DeviceName, [ref]$dev, [IntPtr]::Zero, [DisplayUtil]::CDS_FULLSCREEN, [IntPtr]::Zero)
        if ($ret -ne [DisplayUtil]::DISP_CHANGE_SUCCESSFUL) {
            throw "ChangeDisplaySettingsEx failed with code $ret"
        }
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Resolution set successfully"
    }

    # --- Parse Sunshine environment variables ---
    $width = [int]($env:SUNSHINE_CLIENT_WIDTH  ?? $env:SUNSHINE_WIDTH  ?? 1920)
    $height = [int]($env:SUNSHINE_CLIENT_HEIGHT ?? $env:SUNSHINE_HEIGHT ?? 1080)
    $refresh = [int]($env:SUNSHINE_CLIENT_FPS ?? $env:SUNSHINE_REFRESH_RATE ?? 60)

    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Script started with parameters:"
    Write-Output "  Enable: $Enable"
    Write-Output "  Disable: $Disable"
    Write-Output "  Width: $width"
    Write-Output "  Height: $height"
    Write-Output "  Refresh Rate: $refresh"

    if ($Enable) {
        Set-DisplayConfig -Enable
        Set-Resolution -Width $width -Height $height -RefreshRate $refresh
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Virtual display setup completed successfully"
    }
    elseif ($Disable) {
        Set-DisplayConfig -Disable
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Virtual display teardown completed successfully"
    }
    else {
        Write-Host "Usage: auto_display.ps1 [-Enable | -Disable] [-NoLogging]"
        Write-Host ""
        Write-Host "  -Enable    : Enable the virtual display"
        Write-Host "  -Disable   : Disable the virtual display"
        Write-Host "  -NoLogging : Disable logging to file"
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