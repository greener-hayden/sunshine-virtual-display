# Sunshine Virtual-Only Portable

A minimal, portable add-on that configures Sunshine to always capture a dedicated virtual display with automatic resolution matching for any streaming client.

## Quick Start

1. **Prerequisites**
   - Windows 10/11 with Administrator access
   - Sunshine installed (will be auto-detected)
   - Either a virtual display driver package (signed .inf) or a hardware dummy plug

2. **Installation**
   ```powershell
   # Open PowerShell as Administrator
   cd D:\GitLocal\sunshine-virtual-display\VirtualOnlyPortable
   .\portable.ps1 -Install
   # Or with a driver package:
   .\portable.ps1 -Install -DriverPackage "C:\path\to\driver.inf"
   ```
   The installer will run preflight checks and configure everything automatically.

3. **Usage**
   - Start your streaming client (Moonlight, Steam Link, etc.)
   - Select any resolution/refresh rate (e.g., 1440p@120Hz, 4K@60Hz)
   - The host automatically matches the requested mode
   - Audio streams through Steam Streaming Speakers

4. **Uninstallation**
   ```powershell
   .\portable.ps1 -Uninstall
   ```
   This removes all changes and returns your system to its previous state.

## Features

- **True Portability**: Only 4 files in the repository
- **Automatic Resolution Matching**: Host adapts to any client's requested resolution/refresh
- **Device Agnostic**: Works with iPhone/iPad (120Hz), Android, Apple TV, desktop clients
- **Clean Design**: No third-party code committed; fetched per-session and cleaned up
- **Full Reversibility**: Complete uninstall restores original system state

## How It Works

### Architecture

The add-on uses a fixed virtual display strategy:
1. Sunshine always captures from a dedicated virtual display (no runtime display swapping)
2. Client resolution/refresh requests trigger automatic mode changes on that virtual display
3. All changes are applied through Sunshine's global command hooks

### Components

- **`portable.ps1`**: Installer/uninstaller that configures the virtual display and Sunshine
- **`auto_display.ps1`**: Runtime hook that handles resolution switching on connect/disconnect
- **`settings.json`**: Configuration file storing your preferences and mappings
- **`README.md`**: This documentation

### Installation Process

1. **Virtual Display Setup**
   - Option 1: Install a signed virtual display driver via PnPUtil
   - Option 2: Validate an existing hardware dummy plug

2. **Sunshine Configuration**
   - Sets Output Name to the virtual display
   - Configures Steam Streaming Speakers for audio
   - Registers global commands for automatic resolution switching

3. **Runtime Behavior**
   - On stream connect: Downloads ResolutionAutomation, applies client's requested mode
   - On stream disconnect: Restores display settings, cleans temporary files

## Configuration

### settings.json

The installer creates a `settings.json` file with your configuration:

```json
{
  "VirtualDisplay": {
    "Mode": "Driver",              // "Driver" or "DummyPlug"
    "DriverPackage": "path/to/driver.inf",
    "VirtualDisplayName": "Virtual Display 1"
  },
  "SunshineConfig": {
    "Policy": "Apply",             // "Apply" or "Print"
    "ConfigPath": "C:\\Program Files\\Sunshine\\config\\sunshine.conf"
  },
  "Audio": {
    "VirtualSink": "Steam Streaming Speakers",
    "StreamAudio": true,
    "InstallSteamAudioDrivers": true
  },
  "ResolutionAutomation": {
    "Channel": "PinnedTag",        // "PinnedTag" or "Latest"
    "Tag": "v1.0.0"
  },
  "ModeOverrides": [
    "1280x720x60=3840x2160x60"    // Optional resolution mappings
  ]
}
```

### Mode Overrides

You can map specific resolutions to different ones. For example:
- `"1280x720x60=3840x2160x60"`: When client requests 720p60, apply 4K60 instead
- Useful for upscaling low-resolution requests to native display resolution

### Sunshine Settings Applied

- **General Tab**
  - Global Command Do: `auto_display.ps1 Action=Connect`
  - Global Command Undo: `auto_display.ps1 Action=Disconnect`

- **Audio/Video Tab**
  - Output Name: `<Your Virtual Display Name>`
  - Virtual Sink: `Steam Streaming Speakers`
  - Stream Audio: `Enabled`
  - Install Steam Audio Drivers: `Enabled`

## Troubleshooting

### Common Issues

1. **"Virtual display not found"**
   - Ensure your virtual display driver is properly installed
   - For dummy plugs, verify it's connected and detected by Windows

2. **"Resolution not applied"**
   - Check if the requested mode is supported by your virtual display
   - Review logs in `VirtualOnlyPortable\_temp\logs\`
   - System falls back to nearest supported refresh rate

3. **"Access denied" errors**
   - Ensure PowerShell is running as Administrator
   - Check Windows execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

4. **"Sunshine config not found"**
   - Verify Sunshine installation path
   - Manually specify config path during installation

### Fallback Behavior

When exact resolution/refresh isn't available:
1. Try same resolution at lower refresh (120Hz → 90Hz → 60Hz)
2. Try nearest resolution at requested refresh
3. Log the applied mode for debugging

### Log Locations

- Installation logs: `VirtualOnlyPortable\install.log`
- Runtime logs: `VirtualOnlyPortable\_temp\logs\session-*.log`
- Errors preserve logs even after cleanup

## Advanced Usage

### Manual Configuration

If you choose `"Policy": "Print"` during installation, the script will display the exact Sunshine configuration changes without applying them. You can then manually edit Sunshine's config file.

### Custom ResolutionAutomation Version

To pin a specific version of ResolutionAutomation:
1. Edit `settings.json`
2. Set `"Channel": "PinnedTag"`
3. Set `"Tag": "vX.Y.Z"` to your desired version

### Command Line Options

```powershell
# Installation with all defaults
.\portable.ps1 -Install

# Installation with custom driver package
.\portable.ps1 -Install -DriverPackage "C:\Drivers\VirtualDisplay.inf"

# Uninstall and clean everything
.\portable.ps1 -Uninstall

# Check current status
.\portable.ps1 -Status
```

## Design Principles

1. **Minimal**: Exactly 4 files in repository, no persistent third-party code
2. **Portable**: Self-contained, works from any location
3. **Clean**: Temporary files in session folders, deleted after use
4. **Reversible**: Complete uninstall returns system to original state
5. **Reliable**: Single display strategy, no runtime swapping

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Administrator privileges
- Internet connection (for ResolutionAutomation download)
- Sunshine installed and configured

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review logs in `VirtualOnlyPortable\_temp\logs\`
3. Ensure you're running the latest version

## License

This project is designed as a companion tool for Sunshine. Please ensure you comply with Sunshine's license and terms of use.

---

*Version 1.0.0 - Minimal, Clean, "Just Works"*