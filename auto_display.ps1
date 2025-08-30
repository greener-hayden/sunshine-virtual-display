[CmdletBinding(DefaultParameterSetName='Enable')]
param(
    [Parameter(ParameterSetName='Enable')]
    [switch]$Enable,

    [Parameter(ParameterSetName='Disable')]
    [switch]$Disable
)

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
        $info = Get-VirtualDisplay
        $result = $info.Manager.TryStartVirtualDisplay($info.Display)
        if (-not $result.Succeeded) {
            throw "Failed to enable virtual display: $($result.Error)"
        }
        $script:VirtualDisplayController = $result.Controller
        return
    }
    if ($Disable) {
        $script:VirtualDisplayController?.Close()
        $script:VirtualDisplayController = $null
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
}

# --- Parse Sunshine environment variables ---
$width = [int]($env:SUNSHINE_CLIENT_WIDTH  ?? $env:SUNSHINE_WIDTH  ?? 1920)
$height = [int]($env:SUNSHINE_CLIENT_HEIGHT ?? $env:SUNSHINE_HEIGHT ?? 1080)
$refresh = [int]($env:SUNSHINE_CLIENT_FPS ?? $env:SUNSHINE_REFRESH_RATE ?? 60)

if ($Enable) {
    Set-DisplayConfig -Enable
    Set-Resolution -Width $width -Height $height -RefreshRate $refresh
}
elseif ($Disable) {
    Set-DisplayConfig -Disable
}
