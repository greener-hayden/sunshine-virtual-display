# Sunshine Virtual Display

Automated scripts for managing virtual display drivers with Sunshine game streaming server, enabling streaming without a physical monitor.

## Features

- **Portable Installation**: Single-script installation and uninstallation of Sunshine virtual display driver
- **Auto Display Management**: Automatic virtual display enable/disable based on Sunshine client connection
- **JSON Configuration**: Persistent settings storage for installation metadata
- **Comprehensive Logging**: Detailed logging with timestamps for debugging
- **CI/CD Integration**: GitHub Actions workflow for code quality checks

## Prerequisites

- Windows 10 or Windows 11
- Administrator privileges
- [Sunshine](https://github.com/LizardByte/Sunshine) installed and configured
- PowerShell 5.1 or newer
- Internet connection (for driver download)

## Quick Start

### Installation

1. Clone or download this repository
2. Open PowerShell **as Administrator**
3. Install the virtual display driver:
   ```powershell
   .\portable.ps1 -Install
   ```

### Uninstallation

1. Open PowerShell **as Administrator**
2. Remove the virtual display driver:
   ```powershell
   .\portable.ps1 -Uninstall
   ```

## Scripts

### portable.ps1
Main installation script that handles the complete setup process:
- Downloads and installs the virtual display driver
- Configures Sunshine for virtual display support
- Backs up existing configuration
- Supports rollback on failure
- Stores installation metadata in `settings.json`

**Usage:**
```powershell
.\portable.ps1 [-Install | -Uninstall] [-SettingsPath <path>] [-NoLogging]

Parameters:
  -Install      : Install the Sunshine virtual display driver
  -Uninstall    : Remove the Sunshine virtual display driver  
  -SettingsPath : Path to settings.json file (default: .\settings.json)
  -NoLogging    : Disable logging to file
```

### auto_display.ps1
Automatic display management script for use with Sunshine's command hooks:
- Enables virtual display on client connection
- Disables virtual display on client disconnection
- Adjusts resolution based on client parameters
- Reads Sunshine environment variables for dynamic configuration

**Usage:**
```powershell
.\auto_display.ps1 [-Enable | -Disable] [-NoLogging]

Parameters:
  -Enable    : Enable the virtual display
  -Disable   : Disable the virtual display
  -NoLogging : Disable logging to file
```

**Sunshine Integration:**
Add to your Sunshine configuration:
```conf
# In sunshine.conf
cmd_prep_begin = powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\auto_display.ps1" -Enable
cmd_prep_end = powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\auto_display.ps1" -Disable
```

### settings.json
Configuration file storing installation metadata:
```json
{
  "displayName": "Sunshine Virtual Display",
  "deviceId": "path/to/driver.inf",
  "sunshineConfigPath": "C:/Program Files/Sunshine/config/sunshine.conf",
  "sunshineConfigBackup": "C:/Program Files/Sunshine/config/sunshine.conf.bak",
  "serviceName": "SunshineService",
  "installDate": "2024-01-01T00:00:00.0000000",
  "version": "1.0.0"
}
```

## Logging

Both scripts support comprehensive logging with timestamps:
- Logs are stored in the `logs` directory
- File naming: `<script>-<action>-<timestamp>.log`
- Use `-NoLogging` parameter to disable logging

## Environment Variables

The `auto_display.ps1` script reads the following Sunshine environment variables:
- `SUNSHINE_CLIENT_WIDTH` / `SUNSHINE_WIDTH` (default: 1920)
- `SUNSHINE_CLIENT_HEIGHT` / `SUNSHINE_HEIGHT` (default: 1080)
- `SUNSHINE_CLIENT_FPS` / `SUNSHINE_REFRESH_RATE` (default: 60)

## CI/CD

The repository includes a GitHub Actions workflow (`.github/workflows/ci.yml`) that:
- Runs PowerShell Script Analyzer (PSScriptAnalyzer)
- Validates script syntax
- Checks for common issues and best practices

## Troubleshooting

### Common Issues

1. **"Administrator privileges are required"**
   - Ensure PowerShell is running as Administrator
   - Right-click PowerShell and select "Run as administrator"

2. **"Internet connection is required"**
   - Check your internet connection
   - Verify firewall/proxy settings allow GitHub access

3. **"Sunshine installation not found"**
   - Ensure Sunshine is installed in the default location
   - Check `Program Files` or `Program Files (x86)`

4. **Virtual display not appearing**
   - Check Device Manager for the virtual display adapter
   - Review logs in the `logs` directory
   - Ensure the driver installed successfully

5. **Black screen in Sunshine**
   - Verify virtual display is enabled
   - Check display settings in Windows
   - Ensure Sunshine is capturing the correct display

### Log Analysis

Check log files for detailed error information:
```powershell
Get-Content logs\portable-install-*.log | Select-Object -Last 50
Get-Content logs\auto_display-enable-*.log | Select-Object -Last 50
```

## Known Limitations

- Only one virtual display is supported at a time
- HDR and hardware cursor features may not be available
- Display resolutions are limited to driver-defined values
- Windows updates may require driver reinstallation
- Some antivirus software may flag the unsigned driver

## Security Considerations

- Scripts require administrator privileges
- Driver installation modifies system configuration
- Configuration backup is created before modifications
- Rollback mechanism available on installation failure

## Contributing

Contributions are welcome! Please ensure:
- Scripts pass PSScriptAnalyzer checks
- Logging is comprehensive and consistent
- Error handling includes rollback where appropriate
- Documentation is updated for new features

## License

See LICENSE file for details.

## Support

For issues or questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review logs in the `logs` directory
- Open an issue on GitHub with log excerpts