# Sunshine Virtual Display

Scripts for managing a virtual display driver so Sunshine can stream even without a physical monitor connected.

## Prerequisites

- Windows 10 or Windows 11
- Administrator rights
- [Sunshine](https://github.com/LizardByte/Sunshine) installed and configured
- PowerShell 5.1 or newer (Windows PowerShell or PowerShell Core)

## Installation

1. Clone or download this repository.
2. Open PowerShell **as Administrator**.
3. Run the driver installer script:
   ```powershell
   .\scripts\install.ps1
   ```
   This script installs the Indirect Display Driver and registers required certificates.
4. Reboot if prompted.

## Uninstallation

1. Open PowerShell **as Administrator**.
2. Remove the driver:
   ```powershell
   .\scripts\uninstall.ps1
   ```
3. Reboot to fully unload the virtual display driver.

## Virtual Display Workflow

1. After installation, start a virtual monitor before launching Sunshine:
   ```powershell
   .\scripts\create-display.ps1
   ```
2. Launch Sunshine – it will capture the newly created display.
3. When finished streaming, remove the virtual monitor:
   ```powershell
   .\scripts\remove-display.ps1
   ```

## Known Limitations

- Only a single virtual display is supported.
- HDR and hardware cursor may not be available.
- Display resolutions are limited to those defined in the driver.
- Windows updates or driver changes may break the virtual display until reinstalled.

## Troubleshooting

- **Driver fails to install** – ensure PowerShell was run with administrator privileges and that Secure Boot is disabled or certificates are trusted.
- **No virtual display appears** – verify that `create-display.ps1` ran without errors and check Device Manager for the virtual monitor.
- **Sunshine shows a black screen** – confirm Sunshine captures the correct display and that the virtual monitor is set as primary.
- Logs from `install.ps1` and `create-display.ps1` are stored in the `logs` folder for further analysis.

## Scripts

- `scripts/install.ps1` – installs the virtual display driver.
- `scripts/uninstall.ps1` – removes the driver.
- `scripts/create-display.ps1` – enables the virtual monitor.
- `scripts/remove-display.ps1` – disables the virtual monitor.
