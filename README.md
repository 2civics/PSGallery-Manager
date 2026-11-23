# PSGallery-Manager

A PowerShell utility (`PSGallery-Manager.ps1`) by **waresoft** for managing PowerShell Gallery workflows—including publishing scripts, unlisting versions, installing/uninstalling scripts locally, managing API keys, and creating desktop shortcuts for locally installed scripts.

## Features

- **Publish & Unlist on PowerShell Gallery:** Push scripts and handle version unlisting using your PowerShell Gallery API key.
- **Local Script Lifecycle Management:** Install and uninstall scripts locally without getting tripped up by license prompts or multi-version uninstall edge cases.
- **Desktop Shortcuts for Installed Scripts:** Create shortcuts for locally installed scripts (via UI controls such as a button, double-click, or context menu action).
- **API Key & Scope Guidance:** Built-in reminders/shortcuts for API key management and scope requirements (including `403` permission/scope hints when publishing or unlisting).
- **Preserves Existing Metadata:** Designed to handle script metadata cleanly without clobbering existing publisher fields.

## Requirements

- **OS:** Windows 10 / Windows 11
- **PowerShell:** Windows PowerShell 5.1 or PowerShell 7.x
- **Network Access:** Outbound HTTPS access to the PowerShell Gallery (`powershellgallery.com`)
- **Permissions:** Standard user for general operations; Administrator elevation may be required depending on target installation scope or shortcut paths
- **API Key:** A valid PowerShell Gallery API key with the required scopes (`Publish` / package push and/or `Unlist` as needed)

## Installation

### Download from GitHub Releases
1. Download `PSGallery-Manager.ps1` (or the release `.zip`) from the **Releases** page.
2. Unblock the file if Windows marks it as downloaded from the web:
   ```powershell
   Unblock-File -Path .\PSGallery-Manager.ps1