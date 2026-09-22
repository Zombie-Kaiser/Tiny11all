# Tiny11all

<p align="center">
  <img src="https://img.shields.io/badge/Windows-11-blue?style=flat-square&logo=windows" alt="Windows 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>
<img width="1334" height="968" alt="{28BD00EB-C563-49BA-8A04-CF0D3E2CA046}" src="https://github.com/user-attachments/assets/e14780a1-a722-47c7-a784-ef398d70ad21" />

**Tiny11all** is an all-in-one Windows 11 image slimming tool with a beautiful modern GUI, combining the best features from **tiny11 builder** and **nano11 builder**.

## Features

- **Modern GUI**: Beautiful dark-themed WPF interface with real-time progress tracking
- **Three Build Modes**:
  - **Tiny11** (Standard): Removes bloatware while keeping the system serviceable. You can still add languages, updates, and features.
  - **Tiny11 Core**: More aggressive trimming. Removes WinSxS, WinRE, and more. Not serviceable but smaller.
  - **Nano11** (Extreme): Maximum reduction. Removes almost everything for the smallest possible footprint. For testing/VMs only.
- **DISM-Based**: Uses only built-in Windows DISM tools - no external binaries required
- **Auto-Downloads**: Automatically downloads `oscdimg.exe` if not present
- **Comprehensive Tweaks**: Bypasses hardware requirements, disables telemetry, sponsored apps, and more
- **Logging**: Full transcript logging with real-time GUI output

## What Gets Removed

| Component | Tiny11 | Tiny11 Core | Nano11 |
|-----------|--------|-------------|--------|
| Bloatware Apps | Yes | Yes | Yes |
| Microsoft Edge | Yes | Yes | Yes |
| OneDrive | Yes | Yes | Yes |
| Internet Explorer | Yes | Yes | Yes |
| Telemetry & Diagnostics | Yes | Yes | Yes |
| Windows Defender | - | Disabled | Removed |
| Windows Update | - | Disabled | Removed |
| WinSxS (Component Store) | - | Yes | Yes |
| WinRE | - | Yes | Yes |
| Most Drivers | - | - | Yes (keeps basic) |
| IMEs / Asian Languages | - | - | Yes |
| Audio Services | - | - | Yes |

## Requirements

- Windows 10/11 64-bit
- PowerShell 5.1 or later
- Administrator privileges
- Windows 11 ISO (mounted)
- ~20GB free disk space

## Usage

1. **Download Windows 11** from [Microsoft](https://www.microsoft.com/software-download/windows11)
2. **Mount the ISO** by double-clicking it
3. **Run Tiny11all.ps1 as Administrator**
4. **Select your mode** and configure options in the GUI
5. **Click Build** and wait for completion
6. Your ISO will be saved in the same folder as the script

## GUI Preview

The application features a modern dark-themed interface with:
- **Home Screen**: Welcome and mode selection
- **Configuration Panel**: ISO drive selection, scratch disk, and options
- **Progress Panel**: Real-time build progress with animated indicators
- **Log Panel**: Live output from the build process

## Build Modes Explained

### Tiny11 (Recommended)
Best balance between size reduction and functionality. Removes:
- Clipchamp, News, Weather, Xbox, Office Hub, Solitaire, etc.
- Edge, OneDrive, Internet Explorer
- Telemetry and sponsored apps
- Keeps Windows Update, Defender, and serviceability intact

### Tiny11 Core (Advanced)
For development and VM use. Removes everything from Tiny11 plus:
- Windows Component Store (WinSxS)
- Windows Recovery Environment (WinRE)
- Disables Windows Update and Defender

**Warning**: Cannot add languages, updates, or features after creation!

### Nano11 (Extreme)
For absolute minimum footprint. Removes everything from Core plus:
- Most system services (including audio)
- Most drivers (keeps only VGA, network, storage)
- All IMEs and accessibility features

**Warning**: Only for testing/embedded use. Not suitable for daily use!

## Safety Warnings

> **Important**: This tool modifies Windows installation images. Always test the output in a VM before deploying to real hardware.

> **Tiny11 Core & Nano11**: These modes create non-serviceable images. You will NOT receive Windows Updates.

## Credits

- Based on [tiny11builder](https://github.com/ntdevlabs/tiny11builder) by ntdevlabs
- Based on [nano11](https://github.com/ntdevlabs/nano11) by ntdevlabs
- GUI and integration by Tiny11all project

## License

This project is open-source. Feel free to modify and adapt it to your needs.
