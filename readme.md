# Sunshine Virtual Display

Simple PowerShell scripts to enable virtual display support for Sunshine game streaming without a physical monitor.

## Quick Start

### Requirements
- Windows 10/11
- Administrator privileges  
- [Sunshine](https://github.com/LizardByte/Sunshine) installed
- Internet connection (for driver download)

### Install Virtual Display

1. Download this repository
2. Open PowerShell **as Administrator**
3. Run:
   ```powershell
   .\portable.ps1 -Install
   ```

### Uninstall

```powershell
.\portable.ps1 -Uninstall
```

## What It Does

The scripts automate:
- Downloads and installs the Sunshine virtual display driver
- Configures Sunshine to support virtual displays
- Backs up your existing configuration
- Enables/disables virtual display on demand

## Scripts

### portable.ps1
Main installation script - handles everything automatically.

```powershell
.\portable.ps1 -Install    # Install virtual display support
.\portable.ps1 -Uninstall  # Remove virtual display support
```

### auto_display.ps1  
Automatically enables/disables virtual display when clients connect/disconnect.

Add to your `sunshine.conf`:
```conf
cmd_prep_begin = powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\auto_display.ps1" -Enable
cmd_prep_end = powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\auto_display.ps1" -Disable
```

The script automatically reads client resolution from Sunshine environment variables.

## Troubleshooting

**"Administrator privileges required"**
- Right-click PowerShell → Run as administrator

**"Sunshine installation not found"**  
- Make sure Sunshine is installed in Program Files

**Virtual display not appearing**
- Check Device Manager for virtual display adapter
- Look in the `logs` folder for error details

**Black screen in Sunshine**
- Verify virtual display is enabled in Windows Display Settings
- Make sure Sunshine is capturing the correct display

## Files Created

- `settings.json` - Stores installation info (pre-filled with default `SunshineService` name)
- `logs/` - Contains debug logs (created on first run)

## Notes

- Only one virtual display supported
- Some antivirus may flag the unsigned driver
- Windows updates may require reinstallation

## Support

Check the `logs` folder for detailed error information if something goes wrong.