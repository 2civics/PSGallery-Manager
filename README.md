# PSGallery Manager

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSGallery-Manager?logo=powershell&label=PSGallery)](https://www.powershellgallery.com/packages/PSGallery-Manager)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/PSGallery-Manager?logo=powershell&label=Downloads)](https://www.powershellgallery.com/packages/PSGallery-Manager)
[![GitHub Release](https://img.shields.io/github/v/release/2civics/PSGallery-Manager?logo=github&label=GitHub)](https://github.com/2civics/PSGallery-Manager/releases)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20PowerShell%205.1%2B%20%2F%207%2B-0078D4?logo=windows)

A standalone Windows desktop GUI for browsing, installing, updating, translating, and publishing PowerShell Gallery scripts and modules—without memorizing cmdlets or manually editing metadata headers.

View the official package listing on **[PowerShell Gallery](https://www.powershellgallery.com/packages/PSGallery-Manager)**.

---

## Key Features

### Discover & Install
* **Search & Filter:** Browse the PowerShell Gallery by keyword, category, package type (Scripts or Modules), and sort order (**Most Downloaded**, **Recently Updated**, or **Name A-Z**).
* **Exact Download Counts:** Fetches and caches cumulative multi-version download totals to populate search results, keeping download counts accurate and consistent regardless of how results are sorted.
* **Inspect Source Code:** Preview a script's full source code before downloading or installing anything to your system.
* **On-Demand Translation:** Translate package descriptions and release notes into 12 languages with automatic source-language detection and instant in-memory caching.
* **One-Click Install or Direct Download:** Install packages for `CurrentUser` or `AllUsers`, or save copies directly to your configured `DefaultSavePath`.

### My Gallery & Local Packages
* **Published Package Tracking:** View all scripts and modules published under your PowerShell Gallery username alongside live download counts.
* **Local Package Scanner:** Automatically detects scripts and modules installed on your PC, checks for newer versions on PowerShell Gallery, and lets you update or uninstall in one click.
* **Right-Click Context Menu:** Right-click any installed module or script in the list for instant actions—create a desktop `.lnk` shortcut, inspect source code, update to the latest version, uninstall, open its install folder in File Explorer, or open it in an editor.

### Publish to PowerShell Gallery
* **Scripts & Modules:** Publish standalone `.ps1` scripts or module folders (`.psd1` / `.psm1`) with pre-publish validation and live Gallery version checks.
* **Version Bumping & Metadata Injection:** Bump **Major**, **Minor**, or **Patch** versions in one click and automatically inject `<#PSScriptInfo>` or `.psd1` fields (including saved default Company Name and Copyright values).

### Security, Shortcuts & Interface
* **Windows DPAPI API Key Vault:** Encrypts your PowerShell Gallery API key locally under your Windows user profile (`CurrentUser`) so you never have to re-enter it.
* **Desktop Shortcut Creator:** Built-in `.lnk` generator for any `.ps1` script with custom icons, hidden or normal window styles, execution policy bypass, and optional Administrator elevation.
* **Adaptive Dark / Light Theme:** Automatically matches your Windows theme (with manual override) and runs in both Administrator and Standard user modes.

---

## Requirements

* **OS:** Windows 10 or Windows 11
* **PowerShell:** Windows PowerShell 5.1 or PowerShell 7+
* **Modules:** `PowerShellGet` and `PackageManagement` (included with Windows 10/11)

---

## Installation & Quick Start

### Option 1: Install from PowerShell Gallery
Install directly from your **[PowerShell Gallery listing](https://www.powershellgallery.com/packages/PSGallery-Manager)**:

```powershell
Install-Script -Name PSGallery-Manager -Scope CurrentUser
PSGallery-Manager.ps1
```

### Option 2: Download from GitHub Releases
1. Download `PSGallery-Manager.ps1` (or `PSGallery-Manager-v2.4.2.zip`) from the **[Releases page](https://github.com/2civics/PSGallery-Manager/releases)**.
2. Run the script in PowerShell:

```powershell
.\PSGallery-Manager.ps1
```

To launch without prompting for Administrator elevation via UAC:

```powershell
.\PSGallery-Manager.ps1 -NoElevate
```

---

## Tips & Keyboard / Mouse Shortcuts

* **Right-Click Installed Packages:** In **My Gallery & Local Packages**, right-click any locally installed script or module to **Create Desktop Shortcut (.lnk)**, **Inspect Code**, **Update**, **Uninstall**, or **Open Install Folder**.
* **Choose a Custom Download Folder on Demand:** Clicking **Download / Save** saves directly to your configured `DefaultSavePath`. Hold **Shift** while clicking **Download / Save** (or **Download Copy**) to pick a one-off destination folder.
* **Toggle Translated Descriptions:** After clicking **Translate** in the Discover details pane, click **Show Original** at any time to switch back, or pick another target language from the dropdown to translate immediately.

---

## Troubleshooting

* **PowerShell Gallery Slowness or Timeouts:** If searches, downloads, or publishes fail unexpectedly, check the official **[PowerShell Gallery Service Status](https://github.com/PowerShell/PowerShellGallery/blob/master/psgallery_status.md)** log for ongoing incidents or maintenance.
* **TLS / NuGet Provider Errors on Older Systems:** Use the **Repair TLS / NuGet** button in the Publish tab to enforce TLS 1.2 and install/update the required NuGet provider for `CurrentUser`.

---

## Release History

## What's New is 2.5.0

### Fixed Cross-Edition Local Package Management

-Cross-Edition Local Package Management: Fixed updating and uninstalling installed scripts across Windows PowerShell 5.1 and PowerShell 7.x. Operations now automatically execute in the matching host (powershell.exe or pwsh.exe) regardless of which edition launched the GUI, with safe cleanup fallback for orphaned PS 7.x scripts if pwsh.exe is not installed.
-PS Ver Column & Scan Fix: Added a "PS Ver" column (PS 5.1 / PS 7.x) to the Installed on This PC grid and fixed a deduplication bug where installing the same script in both 5.1 and 7.x caused one entry to hide the other.
-Fixed PS 7.x Grid Header Highlight Bug: Explicitly set ColumnHeadersDefaultCellStyle SelectionBackColor and SelectionForeColor in Apply-Theme so the first column header ("Package Name" / "Name") no longer turns blue in PowerShell 7.x.
-Title Bar Version Display: Added the app version beside the title in the main window title bar, backed by an editable $script:AppVersion variable at the top of the script.

## What's New in v2.4.4

### Fixed PowerShell 5.1 Parser Error
-Fixed PowerShell 5.1 Parser Error: Replaced a UTF-8 em-dash (—) in an API key error message on line 4435 with an ASCII hyphen to prevent Windows PowerShell 5.1 from misreading the character as a closing quote (”) and breaking script parsing.

## What's New in v2.4.3

### Dual PowerShell 5.1 & 7.x Runtime Support
* **Full PowerShell 7 (`pwsh.exe`) Compatibility:** Dynamically resolves loaded .NET 8+ assemblies when compiling Win32/DWM helpers (`PSGalWin32`) and applies `-STA` only on Windows PowerShell 5.1.
* **Runtime-Preserving UAC Elevation:** Both startup auto-elevation and the top-bar **Elevate** button detect the active host binary (`pwsh.exe` or `powershell.exe`) so relaunching as Administrator stays on the same PowerShell runtime.

### Runtime-Aware Desktop Shortcut Creator
* **PowerShell 5.1 / 7.x Mode Selector:** Choose whether generated `.lnk` shortcuts target `powershell.exe` or `pwsh.exe`, with live installation status (`Built-in`, `Installed`, or `Not installed`), automatic icon switching, and saved mode preference.
* **Automatic PowerShell 7 Setup:** Offers one-click background installation of PowerShell 7 (using `winget` with an official GitHub MSI fallback) when creating a PowerShell 7.x shortcut on a PC without `pwsh.exe`.
* **Built-In Windows Icon Browser:** Added a dedicated **Windows Icons...** button (`shell32.dll`) alongside **Choose Icon...** for one-click access to standard Windows system icons.

### v2.4.2
* Added on-demand translation in the Discover Gallery details pane with a **Translate / Show Original** toggle button and a 12-language target selector (auto-detecting source language for descriptions and release notes).
* Added in-memory translation caching per package version and target language so switching languages or revisiting packages loads instantly without redundant requests.
* Enabled automatic height sizing on the Discover details action bar so wrapped button rows never clip at any window width or Windows DPI scaling level.

### v2.4.1
* Updated package downloads to save directly to `DefaultSavePath` by default instead of always prompting for a folder (`Shift+Click` still lets you choose a folder on demand).
* Fixed `Import-PubTargetMetadata` so saved default Company Name and Copyright values pre-fill empty fields even when loading existing `.ps1` or `.psd1` files that already contain metadata blocks.
* Fixed Discover Gallery details pane layout by dynamically sizing header labels for wrapped titles and moving Tags into the scrollable details box so the description area is never clipped or crowded out.
* Fixed inconsistent download counts when switching Discover Gallery sort modes (**Most Downloaded**, **Recently Updated**, **Name A-Z**) by caching and hydrating exact `FindPackagesById()` totals across search pages.

---

## License

Copyright (c) Danny Wareham (`waresoft` / `2civics`). All rights reserved.