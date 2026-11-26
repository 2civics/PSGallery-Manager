<#PSScriptInfo

.VERSION 2.4.4

.GUID 8f4e2b91-6c3a-4d7e-9b12-5a8f0c3d7e91

.AUTHOR waresoft

.COMPANYNAME waresoft

.COPYRIGHT (c) 2026 waresoft. All rights reserved.

.TAGS PowerShellGallery PSGallery PowerShellGet PackageManagement GUI WinForms Windows Desktop Utility Automation DevOps Security Publish Publisher Scripts Modules ShortcutCreator DPAPI DarkMode

.LICENSEURI https://opensource.org/licenses/MIT

.PROJECTURI https://www.powershellgallery.com/packages/PSGallery-Manager/

.RELEASENOTES
v2.4.4:
Fixed PowerShell 5.1 Parser Error: Replaced a UTF-8 em-dash (—) in an API key error message on line 4435 with an ASCII hyphen to prevent Windows PowerShell 5.1 from misreading the character as a closing quote (”) and breaking script parsing.

#>

<#
.SYNOPSIS
    PSGallery Manager gives you a single desktop window to find, manage, and publish PowerShell Gallery packages without memorizing cmdlets or editing metadata headers by hand.

.DESCRIPTION
    PSGallery Manager gives you a single desktop window to find, manage, and publish PowerShell Gallery packages without memorizing cmdlets or editing metadata headers by hand.

        Key Features:
        - Discover & Install: Search the PowerShell Gallery by keyword, category, or package type, inspect script source code before running anything, download copies straight to your save folder, or install packages for your account or the whole PC.
        - My Gallery & Local Packages: View your published PowerShell Gallery packages with live download totals, scan scripts and modules installed on your PC, check for newer versions, and update or uninstall them in one click.
        - Publish to PowerShell Gallery: Publish standalone .ps1 scripts or module folders (.psd1/.psm1) with one-click Major, Minor, or Patch version bumps, automatic metadata injection, and pre-publish validation.
        - Encrypted API Key Storage: Protect your PowerShell Gallery API key locally with Windows DPAPI encryption so you never have to paste it repeatedly.
        - Desktop Shortcut Creator: Create Windows .lnk shortcuts for any .ps1 script with custom icons, hidden or normal window modes, execution policy bypass, and optional Administrator elevation.














.PARAMETER NoElevate Prevents the application from requesting Administrator elevation via UAC on startup.
#>

[CmdletBinding()]
param(
    [switch]$NoElevate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Web

# ==============================================================================
# 1. WIN32 HELPERS (CONSOLE HIDE, DWM TITLEBAR, UXTHEME, SHELL ICON PICKER)
# ==============================================================================
if (-not ([System.Management.Automation.PSTypeName]'PSGalWin32').Type) {
Add-Type -AssemblyName System.Drawing
$addTypeParams = @{}
if ($PSVersionTable.PSEdition -eq 'Core') {
    $seenAssemblies = @{}
    $coreRefs = New-Object System.Collections.Generic.List[string]
    foreach ($asm in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        if (-not $asm.IsDynamic -and -not [string]::IsNullOrWhiteSpace($asm.Location)) {
            $shortName = $asm.GetName().Name
            if (-not $seenAssemblies.ContainsKey($shortName)) {
                $seenAssemblies[$shortName] = $true
                $coreRefs.Add($asm.Location)
            }
        }
    }
    $addTypeParams['ReferencedAssemblies'] = $coreRefs.ToArray()
}
else {
    $addTypeParams['ReferencedAssemblies'] = 'System.Drawing'
}
Add-Type @addTypeParams -TypeDefinition @'

using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class PSGalWin32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

    public static void HideConsole() {
        IntPtr hwnd = GetConsoleWindow();
        if (hwnd != IntPtr.Zero) {
            ShowWindow(hwnd, 0);
            IntPtr root = GetAncestor(hwnd, 3);
            if (root != IntPtr.Zero && root != hwnd) {
                ShowWindow(root, 0);
            }
        }
    }

    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public static void SetDarkTitleBar(IntPtr hwnd, bool dark) {
        if (hwnd == IntPtr.Zero) return;
        int val = dark ? 1 : 0;
        if (DwmSetWindowAttribute(hwnd, 20, ref val, sizeof(int)) != 0) {
            DwmSetWindowAttribute(hwnd, 19, ref val, sizeof(int));
        }
    }

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int PickIconDlg(IntPtr hwndOwner, StringBuilder lpstrFile, int nMaxFile, ref int lpdwIconIndex);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint ExtractIconEx(string lpszFile, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    public static Bitmap GetIconBitmap(string filePath, int index) {
        if (string.IsNullOrWhiteSpace(filePath)) return null;
        string expanded = Environment.ExpandEnvironmentVariables(filePath.Trim().Trim('"'));
        if (!File.Exists(expanded)) return null;

        IntPtr[] large = new IntPtr[1];
        IntPtr[] small = new IntPtr[1];
        uint count = ExtractIconEx(expanded, index, large, small, 1);

        if (count > 0 && large[0] != IntPtr.Zero) {
            try {
                using (Icon ico = Icon.FromHandle(large[0])) {
                    return ico.ToBitmap();
                }
            } finally {
                DestroyIcon(large[0]);
                if (small[0] != IntPtr.Zero) DestroyIcon(small[0]);
            }
        }
        if (small[0] != IntPtr.Zero) DestroyIcon(small[0]);

        if (expanded.EndsWith(".ico", StringComparison.OrdinalIgnoreCase)) {
            try {
                using (Icon ico = new Icon(expanded, 32, 32)) {
                    return ico.ToBitmap();
                }
            } catch { }
        }
        return null;
    }
}
'@ -ErrorAction SilentlyContinue
}

$script:HasWin32 = [bool]([System.Management.Automation.PSTypeName]'PSGalWin32').Type
if ($script:HasWin32) {
    try { [PSGalWin32]::HideConsole() } catch { }
}

try {

# ==============================================================================
# 2. SAFE PROPERTY ACCESSOR & CONFIGURATION / DPAPI VAULT PATHS
# ==============================================================================
function Get-SafeProp {
    param(
        $Obj,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Obj) { return $Default }

    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) {
            return $Obj[$Name]
        }
        return $Default
    }

    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) {
        return $prop.Value
    }
    return $Default
}

$script:MaxRecentItems     = 15
$script:AppDataDir         = Join-Path $env:LOCALAPPDATA 'PSGalleryManager'
$script:ConfigPath         = Join-Path $script:AppDataDir 'config.json'
$script:ApiKeyPath         = Join-Path $script:AppDataDir 'apikey.dat'
$script:IsInitializing     = $true
$script:SuppressEvents     = $false
$script:ConfigNeedsUpgrade = $false

if (-not (Test-Path -LiteralPath $script:AppDataDir)) {
    New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
}

function Get-AppConfig {
    $defaults = [ordered]@{
        Username            = ''
        DefaultSavePath     = (Join-Path $HOME 'Downloads\PSGallery')
        ThemeMode           = 'Auto'
        PreferredScope      = 'Auto'
        AutoElevate         = $true
        PageSize            = 40
        PubPackageType      = 'Script'
        PubLastScriptPath   = ''
        PubLastModulePath   = ''
        PubRecentPackages   = @()
        PubRepository       = 'PSGallery'
        PubAutoInjectMeta   = $true
        PubDefaultCompany   = ''
        PubDefaultCopyright = ''
        PubDefaultTags      = 'PowerShell, Automation'
        PubDefaultProjUri   = ''
        PubDefaultLicUri    = ''
    }

    if (Test-Path -LiteralPath $script:ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in @($defaults.Keys)) {
                $val = Get-SafeProp -Obj $raw -Name $key -Default $null
                if ($null -ne $val) {
                    if ($key -eq 'PubRecentPackages') {
                        $norm = @()
                        foreach ($entry in @($val)) {
                            $ePath = [string](Get-SafeProp -Obj $entry -Name 'Path' -Default '')
                            if (-not [string]::IsNullOrWhiteSpace($ePath)) {
                                $eType = [string](Get-SafeProp -Obj $entry -Name 'Type' -Default 'Script')
                                $pType = if ($eType -eq 'Module') { 'Module' } else { 'Script' }
                                $eName = [string](Get-SafeProp -Obj $entry -Name 'Name' -Default '')
                                $pName = if (-not [string]::IsNullOrWhiteSpace($eName)) { $eName } else { Split-Path $ePath -Leaf }
                                $norm += [PSCustomObject]@{ Name = $pName; Type = $pType; Path = $ePath.Trim() }
                            }
                        }
                        $defaults[$key] = $norm
                    }
                    else {
                        $defaults[$key] = $val
                    }
                }
                else {
                    $script:ConfigNeedsUpgrade = $true
                }
            }
        }
        catch {
            try {
                Copy-Item -LiteralPath $script:ConfigPath -Destination "$($script:ConfigPath).bak" -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }
    }
    else {
        $script:ConfigNeedsUpgrade = $true
    }

    return [PSCustomObject]$defaults
}

function Save-AppConfig {
    if ($script:IsInitializing) { return }
    try {
        $script:Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8 -Force
    }
    catch { }
}

$script:Config = Get-AppConfig

# ==============================================================================
# 3. AUTO-ELEVATION & STA THREAD ENFORCEMENT WITH GRACEFUL FALLBACK
# ==============================================================================
function Test-IsAdministrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PowerShellHostPath {
    try {
        $procPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($procPath) -and ($procPath -match '\\(pwsh|powershell)\.exe$') -and (Test-Path -LiteralPath $procPath -PathType Leaf)) {
            return $procPath
        }
    }
    catch { }

    if ($PSVersionTable.PSEdition -eq 'Core') {
        return (Join-Path -Path $PSHOME -ChildPath 'pwsh.exe')
    }
    return (Join-Path -Path $PSHOME -ChildPath 'powershell.exe')
}

function New-PowerShellRelaunchArgs {
    param([Parameter(Mandatory)][string]$ScriptFile)

    $argsList = New-Object System.Collections.Generic.List[string]
    $argsList.Add('-NoProfile')
    $argsList.Add('-ExecutionPolicy')
    $argsList.Add('Bypass')
    if ($PSVersionTable.PSEdition -ne 'Core') {
        $argsList.Add('-STA')
    }
    $argsList.Add('-WindowStyle')
    $argsList.Add('Hidden')
    $argsList.Add('-File')
    $argsList.Add("`"$ScriptFile`"")
    $argsList.Add('-NoElevate')
    return $argsList.ToArray()
}

$script:IsAdmin = Test-IsAdministrator
$script:IsSTA   = ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')

if ((-not $script:IsAdmin) -and (-not $NoElevate) -and $script:Config.AutoElevate) {
    $hostExe    = Get-PowerShellHostPath
    $scriptFile = $PSCommandPath

    if ($scriptFile -and (Test-Path -LiteralPath $scriptFile)) {
        $argList = New-PowerShellRelaunchArgs -ScriptFile $scriptFile
        try {
            Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
            exit 0
        }
        catch {
            if ($script:HasWin32) {
                try { [PSGalWin32]::HideConsole() } catch { }
            }
        }
    }
}

if (-not $script:IsSTA) {
    $hostExe    = Get-PowerShellHostPath
    $scriptFile = $PSCommandPath
    if ($scriptFile -and (Test-Path -LiteralPath $scriptFile)) {
        $argList = New-PowerShellRelaunchArgs -ScriptFile $scriptFile
        Start-Process -FilePath $hostExe -ArgumentList $argList -WindowStyle Hidden
        exit 0
    }
}

$script:IsAdmin = Test-IsAdministrator
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
}
catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# ==============================================================================
# 4. VISUAL STYLES & SHARED DPAPI CREDENTIAL HELPERS
# ==============================================================================
[System.Windows.Forms.Application]::EnableVisualStyles()

function Save-ProtectedApiKey {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$PlainApiKey)

    if ([string]::IsNullOrWhiteSpace($PlainApiKey)) {
        if (Test-Path -LiteralPath $script:ApiKeyPath) {
            Remove-Item -LiteralPath $script:ApiKeyPath -Force
        }
        return
    }

    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($PlainApiKey.Trim())
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [System.IO.File]::WriteAllBytes($script:ApiKeyPath, $encrypted)
}

function Get-ProtectedApiKey {
    if (-not (Test-Path -LiteralPath $script:ApiKeyPath)) {
        return ''
    }
    try {
        $encrypted = [System.IO.File]::ReadAllBytes($script:ApiKeyPath)
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    }
    catch {
        return ''
    }
}

function Get-EffectiveScope {
    switch ($script:Config.PreferredScope) {
        'AllUsers'    { if ($script:IsAdmin) { return 'AllUsers' } else { return 'CurrentUser' } }
        'CurrentUser' { return 'CurrentUser' }
        default       { if ($script:IsAdmin) { return 'AllUsers' } else { return 'CurrentUser' } }
    }
}

# ==============================================================================
# 5. UNIFIED THEME SYSTEM (AUTO WINDOWS DETECTION + MANUAL DARK / LIGHT)
# ==============================================================================
function Get-WindowsSystemTheme {
    try {
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $val = Get-ItemPropertyValue -Path $regPath -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ($val -eq 0) { return 'Dark' } else { return 'Light' }
    }
    catch {
        return 'Dark'
    }
}

function Get-ResolvedThemeName {
    if ($script:Config.ThemeMode -in @('Dark', 'Light')) {
        return $script:Config.ThemeMode
    }
    return (Get-WindowsSystemTheme)
}

function Get-ThemePalette {
    $theme = Get-ResolvedThemeName
    if ($theme -eq 'Dark') {
        return @{
            Name         = 'Dark'
            IsDark       = $true
            BgMain       = [Drawing.Color]::FromArgb(24, 26, 31)
            BgHeader     = [Drawing.Color]::FromArgb(31, 34, 41)
            BgPanel      = [Drawing.Color]::FromArgb(34, 38, 46)
            BgInput      = [Drawing.Color]::FromArgb(43, 48, 59)
            BgLog        = [Drawing.Color]::FromArgb(18, 20, 24)
            BgGrid       = [Drawing.Color]::FromArgb(29, 32, 39)
            BgGridAlt    = [Drawing.Color]::FromArgb(35, 39, 47)
            BgGridHeader = [Drawing.Color]::FromArgb(42, 47, 57)
            BgSelection  = [Drawing.Color]::FromArgb(45, 92, 168)
            FgPrimary    = [Drawing.Color]::FromArgb(236, 240, 246)
            FgSecondary  = [Drawing.Color]::FromArgb(164, 174, 190)
            Accent       = [Drawing.Color]::FromArgb(56, 132, 244)
            AccentHover  = [Drawing.Color]::FromArgb(76, 148, 255)
            Success      = [Drawing.Color]::FromArgb(46, 160, 67)
            Warning      = [Drawing.Color]::FromArgb(210, 153, 34)
            Danger       = [Drawing.Color]::FromArgb(218, 54, 51)
            Border       = [Drawing.Color]::FromArgb(64, 71, 86)
            BtnSecondary = [Drawing.Color]::FromArgb(48, 54, 66)
            BtnSecHover  = [Drawing.Color]::FromArgb(62, 70, 85)
        }
    }
    else {
        return @{
            Name         = 'Light'
            IsDark       = $false
            BgMain       = [Drawing.Color]::FromArgb(244, 246, 250)
            BgHeader     = [Drawing.Color]::FromArgb(255, 255, 255)
            BgPanel      = [Drawing.Color]::FromArgb(255, 255, 255)
            BgInput      = [Drawing.Color]::FromArgb(250, 251, 253)
            BgLog        = [Drawing.Color]::FromArgb(248, 250, 252)
            BgGrid       = [Drawing.Color]::FromArgb(255, 255, 255)
            BgGridAlt    = [Drawing.Color]::FromArgb(247, 249, 252)
            BgGridHeader = [Drawing.Color]::FromArgb(235, 239, 245)
            BgSelection  = [Drawing.Color]::FromArgb(212, 230, 255)
            FgPrimary    = [Drawing.Color]::FromArgb(24, 29, 38)
            FgSecondary  = [Drawing.Color]::FromArgb(78, 88, 104)
            Accent       = [Drawing.Color]::FromArgb(0, 103, 192)
            AccentHover  = [Drawing.Color]::FromArgb(16, 118, 208)
            Success      = [Drawing.Color]::FromArgb(26, 127, 55)
            Warning      = [Drawing.Color]::FromArgb(176, 118, 12)
            Danger       = [Drawing.Color]::FromArgb(196, 43, 43)
            Border       = [Drawing.Color]::FromArgb(204, 211, 222)
            BtnSecondary = [Drawing.Color]::FromArgb(234, 238, 245)
            BtnSecHover  = [Drawing.Color]::FromArgb(220, 226, 236)
        }
    }
}

function Initialize-ThemedComboBox {
    param([Parameter(Mandatory)][System.Windows.Forms.ComboBox]$ComboBox)

    $ComboBox.FlatStyle  = 'Flat'
    $ComboBox.DrawMode   = 'OwnerDrawFixed'
    $ComboBox.ItemHeight = 20

    $ComboBox.Add_HandleCreated({
        param($sender, $e)
        if ($script:HasWin32) {
            $p = Get-ThemePalette
            try {
                $subApp = if ($p.IsDark) { 'DarkMode_CFD' } else { 'Explorer' }
                [void][PSGalWin32]::SetWindowTheme($sender.Handle, $subApp, $null)
            }
            catch { }
        }
    })

    $ComboBox.Add_DrawItem({
        param($sender, $e)
        $p = Get-ThemePalette

        if ($e.Index -lt 0 -or $e.Index -ge $sender.Items.Count) {
            $bgBrush = New-Object System.Drawing.SolidBrush($p.BgInput)
            $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
            $bgBrush.Dispose()
            return
        }

        $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected) -and
                      (($e.State -band [System.Windows.Forms.DrawItemState]::ComboBoxEdit) -ne [System.Windows.Forms.DrawItemState]::ComboBoxEdit)

        $bgColor = if ($isSelected) { $p.Accent } else { $p.BgInput }
        $fgColor = if (-not $sender.Enabled) {
            $p.FgSecondary
        }
        elseif ($isSelected) {
            [System.Drawing.Color]::White
        }
        else {
            $p.FgPrimary
        }

        $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
        $fgBrush = New-Object System.Drawing.SolidBrush($fgColor)
        $e.Graphics.FillRectangle($bgBrush, $e.Bounds)

        $itemText = $sender.GetItemText($sender.Items[$e.Index])
        $textRect = New-Object System.Drawing.RectangleF(($e.Bounds.X + 4), ($e.Bounds.Y + 2), ($e.Bounds.Width - 6), $e.Bounds.Height)
        $e.Graphics.DrawString($itemText, $sender.Font, $fgBrush, $textRect)

        $bgBrush.Dispose()
        $fgBrush.Dispose()
    })
}

function Initialize-ThemedGroupBox {
    param([Parameter(Mandatory)][System.Windows.Forms.GroupBox]$GroupBox)

    $GroupBox.Add_Paint({
        param($sender, $e)
        $p = Get-ThemePalette
        $e.Graphics.Clear($sender.BackColor)

        $displayTitle = ($sender.Text -replace '&&', '&')
        $textSize     = $e.Graphics.MeasureString($displayTitle, $sender.Font)
        $topOffset    = [int]($textSize.Height / 2)
        $borderRect   = New-Object System.Drawing.Rectangle(0, $topOffset, ($sender.Width - 1), ($sender.Height - $topOffset - 1))

        $pen = New-Object System.Drawing.Pen($p.Border)
        $e.Graphics.DrawRectangle($pen, $borderRect)
        $pen.Dispose()

        $textRect = New-Object System.Drawing.Rectangle(10, 0, ([int]$textSize.Width + 8), ([int]$textSize.Height + 2))
        $bgBrush  = New-Object System.Drawing.SolidBrush($sender.BackColor)
        $e.Graphics.FillRectangle($bgBrush, $textRect)
        $bgBrush.Dispose()

        $fgBrush = New-Object System.Drawing.SolidBrush($p.Accent)
        $e.Graphics.DrawString($displayTitle, $sender.Font, $fgBrush, 12, 0)
        $fgBrush.Dispose()
    })
}

# ==============================================================================
# 6. NON-BLOCKING BACKGROUND TASK RUNNER (THREAD-SAFE WITH STATE PASSING)
# ==============================================================================
$script:ActiveTasks = New-Object System.Collections.ArrayList

function Invoke-AsyncTask {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [object[]]$ArgumentList = @(),
        [object]$State = $null,
        [Parameter(Mandatory)][scriptblock]$OnComplete
    )

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($Work)
    foreach ($arg in $ArgumentList) {
        [void]$ps.AddArgument($arg)
    }

    $asyncResult = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 90

    $taskState = [PSCustomObject]@{
        PowerShell  = $ps
        AsyncResult = $asyncResult
        Timer       = $timer
        State       = $State
        OnComplete  = $OnComplete
    }
    [void]$script:ActiveTasks.Add($taskState)

    $timer.Add_Tick({
        param($sender, $e)
        $currentTask = $null
        foreach ($t in @($script:ActiveTasks)) {
            if ($t.Timer -eq $sender) {
                $currentTask = $t
                break
            }
        }
        if ($null -eq $currentTask) { return }

        if ($currentTask.AsyncResult.IsCompleted) {
            $currentTask.Timer.Stop()
            $currentTask.Timer.Dispose()
            [void]$script:ActiveTasks.Remove($currentTask)

            $output = $null
            $errMsg = $null
            try {
                $output = $currentTask.PowerShell.EndInvoke($currentTask.AsyncResult)
                if ($currentTask.PowerShell.Streams.Error.Count -gt 0) {
                    $errMsg = ($currentTask.PowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
                }
            }
            catch {
                $errMsg = $_.Exception.Message
                if ($_.Exception.InnerException) {
                    $errMsg = $_.Exception.InnerException.Message
                }
            }
            finally {
                $currentTask.PowerShell.Dispose()
            }

            & $currentTask.OnComplete $output $errMsg $currentTask.State
        }
    })

    $timer.Start()
}

# ==============================================================================
# 7. POWERSHELL GALLERY ODATA PARSER HELPERS
# ==============================================================================
$script:GalleryCategories = @(
    'All Categories', 'Automation', 'Security', 'Networking', 'ActiveDirectory',
    'Azure', 'FileSystem', 'Windows', 'Utility', 'Reporting', 'Monitoring',
    'DevOps', 'GUI', 'Backup', 'Registry', 'DSC'
)

$script:ODataParserBlock = {
    function Get-ODataVal {
        param($Obj, [string]$PropName, $Default = '')
        if ($null -eq $Obj) { return $Default }
        $prop = $Obj.PSObject.Properties[$PropName]
        if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
        $val = $prop.Value
        if ($val -is [System.Xml.XmlElement]) {
            if ($val.HasAttribute('null', 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')) {
                return $Default
            }
            return $val.InnerText
        }
        return [string]$val
    }

    function ConvertFrom-GalleryFeed {
        param($RawResponse)
        $entries = @()
        if ($null -eq $RawResponse) { return $entries }

        if ($RawResponse -is [array]) {
            $entries = $RawResponse
        }
        elseif ($null -ne $RawResponse.PSObject.Properties['d']) {
            if ($null -ne $RawResponse.d.PSObject.Properties['results']) {
                $entries = @($RawResponse.d.results)
            }
            else {
                $entries = @($RawResponse.d)
            }
        }
        elseif ($null -ne $RawResponse.PSObject.Properties['value']) {
            $entries = @($RawResponse.value)
        }
        elseif ($null -ne $RawResponse.PSObject.Properties['properties']) {
            $entries = @($RawResponse)
        }

        $parsed = foreach ($entry in $entries) {
            if ($null -eq $entry) { continue }
            $src = if ($null -ne $entry.PSObject.Properties['properties']) { $entry.properties } else { $entry }
            $id  = [string](Get-ODataVal $src 'Id' '')
            if ([string]::IsNullOrWhiteSpace($id)) { continue }

            $tagsRaw  = [string](Get-ODataVal $src 'Tags' '')
            $isScript = ($tagsRaw -match '(^|\s)PSScript(\s|$)')

            $dlRaw = Get-ODataVal $src 'DownloadCount' '0'
            $dlNum = [long]0
            [void][long]::TryParse([string]$dlRaw, [ref]$dlNum)

            $verDlRaw = Get-ODataVal $src 'VersionDownloadCount' '0'
            $verDlNum = [long]0
            [void][long]::TryParse([string]$verDlRaw, [ref]$verDlNum)

            $pubRaw     = [string](Get-ODataVal $src 'Published' '')
            $pubDisplay = $pubRaw
            $dt         = [datetime]::MinValue
            if ([datetime]::TryParse($pubRaw, [ref]$dt)) {
                $pubDisplay = $dt.ToString('yyyy-MM-dd')
            }

            [PSCustomObject]@{
                Id                = $id
                Version           = [string](Get-ODataVal $src 'NormalizedVersion' (Get-ODataVal $src 'Version' ''))
                Type              = if ($isScript) { 'Script' } else { 'Module' }
                Authors           = [string](Get-ODataVal $src 'Authors' '')
                Owners            = [string](Get-ODataVal $src 'Owners' '')
                Downloads         = [Math]::Max($dlNum, $verDlNum)
                VersionDownloads  = $verDlNum
                Published         = $pubDisplay
                Tags              = $tagsRaw.Trim()
                Description       = [string](Get-ODataVal $src 'Description' (Get-ODataVal $src 'Summary' ''))
                ReleaseNotes      = [string](Get-ODataVal $src 'ReleaseNotes' '')
                ProjectUrl        = [string](Get-ODataVal $src 'ProjectUrl' '')
                LicenseUrl        = [string](Get-ODataVal $src 'LicenseUrl' '')
                GalleryDetailsUrl = [string](Get-ODataVal $src 'GalleryDetailsUrl' "https://www.powershellgallery.com/packages/$id")
            }
        }
        return @($parsed)
    }

    function Get-AccuratePackageDownloads {
        param([Parameter(Mandatory)][string]$PackageId)
        try {
            $escapedId = $PackageId.Replace("'", "''")
            $uri       = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='$([uri]::EscapeDataString($escapedId))'"
            $headers   = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
            $feed      = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 15 -ErrorAction Stop

            $entries = @()
            if ($feed -is [array]) { $entries = $feed }
            elseif ($null -ne $feed.PSObject.Properties['d']) {
                $entries = if ($null -ne $feed.d.PSObject.Properties['results']) { @($feed.d.results) } else { @($feed.d) }
            }
            elseif ($null -ne $feed.PSObject.Properties['value']) { $entries = @($feed.value) }
            elseif ($null -ne $feed) { $entries = @($feed) }

            $sumVersionDownloads = [long]0
            $maxAggregateCount   = [long]0
            $latestVerDownloads  = [long]0
            $highestVer          = [version]'0.0.0'

            foreach ($entry in $entries) {
                if ($null -eq $entry) { continue }
                $src = if ($null -ne $entry.PSObject.Properties['properties']) { $entry.properties } else { $entry }

                $vDl = [long]0
                [void][long]::TryParse([string](Get-ODataVal $src 'VersionDownloadCount' '0'), [ref]$vDl)
                $sumVersionDownloads += $vDl

                $aggDl = [long]0
                [void][long]::TryParse([string](Get-ODataVal $src 'DownloadCount' '0'), [ref]$aggDl)
                if ($aggDl -gt $maxAggregateCount) { $maxAggregateCount = $aggDl }

                $isLatest = ((Get-ODataVal $src 'IsLatestVersion' '') -ieq 'true')
                $verStr   = [string](Get-ODataVal $src 'NormalizedVersion' (Get-ODataVal $src 'Version' ''))
                if ($isLatest) {
                    $latestVerDownloads = $vDl
                }
                elseif ($verStr -match '^(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') {
                    $parsedVer = [version]$Matches[1]
                    if ($parsedVer -gt $highestVer -and $latestVerDownloads -eq 0) {
                        $highestVer         = $parsedVer
                        $latestVerDownloads = $vDl
                    }
                }
            }

            return [PSCustomObject]@{
                TotalDownloads         = [Math]::Max($sumVersionDownloads, $maxAggregateCount)
                LatestVersionDownloads = $latestVerDownloads
            }
        }
        catch {
            return $null
        }
    }
}

# ==============================================================================
# 8. BUILD MAIN FORM & TOP NAVIGATION
# ==============================================================================
$fontUi        = New-Object Drawing.Font('Segoe UI', 9.5)
$fontUiBold    = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
$fontTitle     = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
$fontSubHeader = New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold)
$fontBadge     = New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Bold)
$fontSmall     = New-Object Drawing.Font('Segoe UI', 8.5)
$fontMono      = New-Object Drawing.Font('Consolas', 9.25)

$toolTip = New-Object System.Windows.Forms.ToolTip

$form = New-Object Windows.Forms.Form
$form.Text = 'PowerShell Gallery Manager & Publisher'
$form.Size = New-Object Drawing.Size(1280, 860)
$form.MinimumSize = New-Object Drawing.Size(1120, 760)
$form.StartPosition = 'CenterScreen'
$form.WindowState = 'Normal'
$form.ShowInTaskbar = $true
$form.Font = $fontUi

# --- Top Header Bar ---
$pnlHeader = New-Object Windows.Forms.Panel
$pnlHeader.Dock = 'Top'
$pnlHeader.Height = 58
$pnlHeader.Padding = New-Object Windows.Forms.Padding(16, 10, 16, 10)
$form.Controls.Add($pnlHeader)

$lblAppTitle = New-Object Windows.Forms.Label
$lblAppTitle.Text = 'PSGallery Suite'
$lblAppTitle.Font = $fontTitle
$lblAppTitle.AutoSize = $true
$lblAppTitle.Location = New-Object Drawing.Point(16, 15)
$pnlHeader.Controls.Add($lblAppTitle)

$btnNavDiscover = New-Object Windows.Forms.Button
$btnNavDiscover.Text = 'Discover Gallery'
$btnNavDiscover.Font = $fontUiBold
$btnNavDiscover.Size = New-Object Drawing.Size(135, 34)
$btnNavDiscover.Location = New-Object Drawing.Point(175, 12)
$btnNavDiscover.FlatStyle = 'Flat'
$btnNavDiscover.Cursor = 'Hand'
$pnlHeader.Controls.Add($btnNavDiscover)

$btnNavMyScripts = New-Object Windows.Forms.Button
$btnNavMyScripts.Text = 'My Gallery && Local'
$btnNavMyScripts.Font = $fontUiBold
$btnNavMyScripts.Size = New-Object Drawing.Size(145, 34)
$btnNavMyScripts.Location = New-Object Drawing.Point(316, 12)
$btnNavMyScripts.FlatStyle = 'Flat'
$btnNavMyScripts.Cursor = 'Hand'
$pnlHeader.Controls.Add($btnNavMyScripts)

$btnNavPublish = New-Object Windows.Forms.Button
$btnNavPublish.Text = 'Publish to Gallery'
$btnNavPublish.Font = $fontUiBold
$btnNavPublish.Size = New-Object Drawing.Size(140, 34)
$btnNavPublish.Location = New-Object Drawing.Point(467, 12)
$btnNavPublish.FlatStyle = 'Flat'
$btnNavPublish.Cursor = 'Hand'
$pnlHeader.Controls.Add($btnNavPublish)

$btnNavSettings = New-Object Windows.Forms.Button
$btnNavSettings.Text = 'Settings && Keys'
$btnNavSettings.Font = $fontUiBold
$btnNavSettings.Size = New-Object Drawing.Size(125, 34)
$btnNavSettings.Location = New-Object Drawing.Point(613, 12)
$btnNavSettings.FlatStyle = 'Flat'
$btnNavSettings.Cursor = 'Hand'
$pnlHeader.Controls.Add($btnNavSettings)

$pnlHeaderRight = New-Object Windows.Forms.FlowLayoutPanel
$pnlHeaderRight.Dock = 'Right'
$pnlHeaderRight.FlowDirection = 'RightToLeft'
$pnlHeaderRight.WrapContents = $false
$pnlHeaderRight.AutoSize = $true
$pnlHeaderRight.Padding = New-Object Windows.Forms.Padding(0, 3, 0, 0)
$pnlHeader.Controls.Add($pnlHeaderRight)

$cmbTheme = New-Object Windows.Forms.ComboBox
$cmbTheme.DropDownStyle = 'DropDownList'
$cmbTheme.Width = 96
$cmbTheme.Font = $fontUi
[void]$cmbTheme.Items.AddRange(@('Auto', 'Dark', 'Light'))
$cmbTheme.SelectedItem = if ($script:Config.ThemeMode -in @('Auto', 'Dark', 'Light')) { $script:Config.ThemeMode } else { 'Auto' }
$cmbTheme.Margin = New-Object Windows.Forms.Padding(6, 4, 0, 0)
$pnlHeaderRight.Controls.Add($cmbTheme)

$lblThemeTitle = New-Object Windows.Forms.Label
$lblThemeTitle.Text = 'Theme:'
$lblThemeTitle.AutoSize = $true
$lblThemeTitle.Margin = New-Object Windows.Forms.Padding(10, 8, 2, 0)
$pnlHeaderRight.Controls.Add($lblThemeTitle)

$btnShortcutDlgTop = New-Object Windows.Forms.Button
$btnShortcutDlgTop.Text = 'Desktop Shortcut...'
$btnShortcutDlgTop.Font = $fontBadge
$btnShortcutDlgTop.Size = New-Object Drawing.Size(130, 28)
$btnShortcutDlgTop.FlatStyle = 'Flat'
$btnShortcutDlgTop.Cursor = 'Hand'
$btnShortcutDlgTop.Margin = New-Object Windows.Forms.Padding(8, 3, 0, 0)
$pnlHeaderRight.Controls.Add($btnShortcutDlgTop)

$btnElevateNow = New-Object Windows.Forms.Button
$btnElevateNow.Text = 'Elevate'
$btnElevateNow.Font = $fontBadge
$btnElevateNow.Size = New-Object Drawing.Size(74, 28)
$btnElevateNow.FlatStyle = 'Flat'
$btnElevateNow.Cursor = 'Hand'
$btnElevateNow.Visible = (-not $script:IsAdmin)
$btnElevateNow.Margin = New-Object Windows.Forms.Padding(6, 3, 0, 0)
$pnlHeaderRight.Controls.Add($btnElevateNow)

$lblModeBadge = New-Object Windows.Forms.Label
$lblModeBadge.Text = if ($script:IsAdmin) { ' ADMIN ' } else { ' STANDARD ' }
$lblModeBadge.Font = $fontBadge
$lblModeBadge.AutoSize = $true
$lblModeBadge.Padding = New-Object Windows.Forms.Padding(6, 5, 6, 5)
$lblModeBadge.Margin = New-Object Windows.Forms.Padding(6, 4, 0, 0)
$pnlHeaderRight.Controls.Add($lblModeBadge)

# --- Status Bar at Bottom ---
$pnlStatus = New-Object Windows.Forms.Panel
$pnlStatus.Dock = 'Bottom'
$pnlStatus.Height = 32
$pnlStatus.Padding = New-Object Windows.Forms.Padding(14, 6, 14, 6)
$form.Controls.Add($pnlStatus)

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Dock = 'Fill'
$lblStatus.TextAlign = 'MiddleLeft'
$pnlStatus.Controls.Add($lblStatus)

$lblUserBadge = New-Object Windows.Forms.Label
$lblUserBadge.Dock = 'Right'
$lblUserBadge.Width = 280
$lblUserBadge.TextAlign = 'MiddleRight'
$pnlStatus.Controls.Add($lblUserBadge)

# --- Main Content Container ---
$pnlMain = New-Object Windows.Forms.Panel
$pnlMain.Dock = 'Fill'
$pnlMain.Padding = New-Object Windows.Forms.Padding(14, 10, 14, 10)
$form.Controls.Add($pnlMain)
$pnlMain.BringToFront()

# ==============================================================================
# VIEW 1: DISCOVER GALLERY
# ==============================================================================
$viewDiscover = New-Object Windows.Forms.Panel
$viewDiscover.Dock = 'Fill'
$pnlMain.Controls.Add($viewDiscover)

$pnlFilter = New-Object Windows.Forms.Panel
$pnlFilter.Dock = 'Top'
$pnlFilter.Height = 52
$pnlFilter.Padding = New-Object Windows.Forms.Padding(10, 9, 10, 9)
$viewDiscover.Controls.Add($pnlFilter)

$lblCat = New-Object Windows.Forms.Label
$lblCat.Text = 'Category:'
$lblCat.AutoSize = $true
$lblCat.Location = New-Object Drawing.Point(12, 15)
$pnlFilter.Controls.Add($lblCat)

$cmbCategory = New-Object Windows.Forms.ComboBox
$cmbCategory.DropDownStyle = 'DropDownList'
$cmbCategory.Location = New-Object Drawing.Point(78, 12)
$cmbCategory.Size = New-Object Drawing.Size(155, 26)
[void]$cmbCategory.Items.AddRange($script:GalleryCategories)
$cmbCategory.SelectedIndex = 0
$pnlFilter.Controls.Add($cmbCategory)

$lblType = New-Object Windows.Forms.Label
$lblType.Text = 'Type:'
$lblType.AutoSize = $true
$lblType.Location = New-Object Drawing.Point(246, 15)
$pnlFilter.Controls.Add($lblType)

$cmbItemType = New-Object Windows.Forms.ComboBox
$cmbItemType.DropDownStyle = 'DropDownList'
$cmbItemType.Location = New-Object Drawing.Point(288, 12)
$cmbItemType.Size = New-Object Drawing.Size(105, 26)
[void]$cmbItemType.Items.AddRange(@('Scripts', 'All', 'Modules'))
$cmbItemType.SelectedIndex = 0
$pnlFilter.Controls.Add($cmbItemType)

$lblSort = New-Object Windows.Forms.Label
$lblSort.Text = 'Sort:'
$lblSort.AutoSize = $true
$lblSort.Location = New-Object Drawing.Point(406, 15)
$pnlFilter.Controls.Add($lblSort)

$cmbSort = New-Object Windows.Forms.ComboBox
$cmbSort.DropDownStyle = 'DropDownList'
$cmbSort.Location = New-Object Drawing.Point(444, 12)
$cmbSort.Size = New-Object Drawing.Size(150, 26)
[void]$cmbSort.Items.AddRange(@('Most Downloaded', 'Recently Updated', 'Name (A-Z)'))
$cmbSort.SelectedIndex = 0
$pnlFilter.Controls.Add($cmbSort)

$txtSearch = New-Object Windows.Forms.TextBox
$txtSearch.Location = New-Object Drawing.Point(608, 12)
$txtSearch.Size = New-Object Drawing.Size(260, 26)
$txtSearch.BorderStyle = 'FixedSingle'
$pnlFilter.Controls.Add($txtSearch)

$btnSearch = New-Object Windows.Forms.Button
$btnSearch.Text = 'Search'
$btnSearch.Font = $fontUiBold
$btnSearch.Location = New-Object Drawing.Point(878, 10)
$btnSearch.Size = New-Object Drawing.Size(95, 30)
$btnSearch.FlatStyle = 'Flat'
$btnSearch.Cursor = 'Hand'
$pnlFilter.Controls.Add($btnSearch)

$btnPrevPage = New-Object Windows.Forms.Button
$btnPrevPage.Text = '< Prev'
$btnPrevPage.Location = New-Object Drawing.Point(985, 10)
$btnPrevPage.Size = New-Object Drawing.Size(68, 30)
$btnPrevPage.FlatStyle = 'Flat'
$btnPrevPage.Cursor = 'Hand'
$btnPrevPage.Enabled = $false
$pnlFilter.Controls.Add($btnPrevPage)

$lblPage = New-Object Windows.Forms.Label
$lblPage.Text = 'Page 1'
$lblPage.Location = New-Object Drawing.Point(1058, 15)
$lblPage.Size = New-Object Drawing.Size(54, 22)
$lblPage.TextAlign = 'MiddleCenter'
$pnlFilter.Controls.Add($lblPage)

$btnNextPage = New-Object Windows.Forms.Button
$btnNextPage.Text = 'Next >'
$btnNextPage.Location = New-Object Drawing.Point(1116, 10)
$btnNextPage.Size = New-Object Drawing.Size(68, 30)
$btnNextPage.FlatStyle = 'Flat'
$btnNextPage.Cursor = 'Hand'
$pnlFilter.Controls.Add($btnNextPage)

$splitDiscover = New-Object Windows.Forms.SplitContainer
$splitDiscover.Dock = 'Fill'
$splitDiscover.Orientation = 'Vertical'
$splitDiscover.SplitterDistance = 780
$splitDiscover.SplitterWidth = 6
$viewDiscover.Controls.Add($splitDiscover)
$splitDiscover.BringToFront()

$dgvGallery = New-Object Windows.Forms.DataGridView
$dgvGallery.Dock = 'Fill'
$dgvGallery.ReadOnly = $true
$dgvGallery.AllowUserToAddRows = $false
$dgvGallery.AllowUserToDeleteRows = $false
$dgvGallery.AllowUserToResizeRows = $false
$dgvGallery.RowHeadersVisible = $false
$dgvGallery.SelectionMode = 'FullRowSelect'
$dgvGallery.MultiSelect = $false
$dgvGallery.AutoSizeColumnsMode = 'Fill'
$dgvGallery.BorderStyle = 'None'
$dgvGallery.CellBorderStyle = 'SingleHorizontal'
$dgvGallery.EnableHeadersVisualStyles = $false
$dgvGallery.ColumnHeadersHeight = 34
$dgvGallery.RowTemplate.Height = 30
$splitDiscover.Panel1.Controls.Add($dgvGallery)

$pnlDetails = New-Object Windows.Forms.Panel
$pnlDetails.Dock = 'Fill'
$pnlDetails.Padding = New-Object Windows.Forms.Padding(14)
$splitDiscover.Panel2.Controls.Add($pnlDetails)

$lblDetTitle = New-Object Windows.Forms.Label
$lblDetTitle.Text = 'Select a package to view details'
$lblDetTitle.Font = $fontSubHeader
$lblDetTitle.Dock = 'Top'
$lblDetTitle.Height = 30
$lblDetTitle.Padding = New-Object Windows.Forms.Padding(0, 0, 0, 6)
$pnlDetails.Controls.Add($lblDetTitle)

$lblDetMeta = New-Object Windows.Forms.Label
$lblDetMeta.Text = ''
$lblDetMeta.Dock = 'Top'
$lblDetMeta.Height = 72
$lblDetMeta.Padding = New-Object Windows.Forms.Padding(0, 0, 0, 10)
$pnlDetails.Controls.Add($lblDetMeta)
$lblDetMeta.BringToFront()

function Update-GalleryDetailsLayout {
    if ($null -eq $pnlDetails -or $pnlDetails.IsDisposed) { return }
    $panelW = if ($pnlDetails.ClientSize.Width -gt 40) { $pnlDetails.ClientSize.Width } else { 440 }
    $availW = [Math]::Max(140, $panelW - $pnlDetails.Padding.Horizontal - 4)
    $flags  = [System.Windows.Forms.TextFormatFlags]::WordBreak

    $titleText = if ([string]::IsNullOrEmpty($lblDetTitle.Text)) { ' ' } else { $lblDetTitle.Text }
    $titleSize = [System.Windows.Forms.TextRenderer]::MeasureText($titleText, $lblDetTitle.Font, (New-Object Drawing.Size($availW, 0)), $flags)
    $lblDetTitle.Height = [Math]::Min(72, [Math]::Max(30, $titleSize.Height + 10))

    $metaText = if ([string]::IsNullOrEmpty($lblDetMeta.Text)) { ' ' } else { $lblDetMeta.Text }
    $metaSize = [System.Windows.Forms.TextRenderer]::MeasureText($metaText, $lblDetMeta.Font, (New-Object Drawing.Size($availW, 0)), $flags)
    $lblDetMeta.Height = [Math]::Min(80, [Math]::Max(46, $metaSize.Height + 14))
}

$pnlDetails.Add_SizeChanged({ Update-GalleryDetailsLayout })

$pnlDetActions = New-Object Windows.Forms.FlowLayoutPanel
$pnlDetActions.Dock = 'Bottom'
$pnlDetActions.AutoSize = $true
$pnlDetActions.AutoSizeMode = 'GrowAndShrink'
$pnlDetActions.FlowDirection = 'LeftToRight'
$pnlDetActions.WrapContents = $true
$pnlDetActions.Padding = New-Object Windows.Forms.Padding(0, 8, 0, 4)
$pnlDetails.Controls.Add($pnlDetActions)

$btnInstallPkg = New-Object Windows.Forms.Button
$btnInstallPkg.Text = 'Install to PC'
$btnInstallPkg.Font = $fontUiBold
$btnInstallPkg.Size = New-Object Drawing.Size(124, 34)
$btnInstallPkg.FlatStyle = 'Flat'
$btnInstallPkg.Cursor = 'Hand'
$btnInstallPkg.Enabled = $false
$pnlDetActions.Controls.Add($btnInstallPkg)

$btnDownloadPkg = New-Object Windows.Forms.Button
$btnDownloadPkg.Text = 'Download / Save'
$btnDownloadPkg.Font = $fontUiBold
$btnDownloadPkg.Size = New-Object Drawing.Size(134, 34)
$btnDownloadPkg.FlatStyle = 'Flat'
$btnDownloadPkg.Cursor = 'Hand'
$btnDownloadPkg.Enabled = $false
$pnlDetActions.Controls.Add($btnDownloadPkg)

$btnViewCode = New-Object Windows.Forms.Button
$btnViewCode.Text = 'Inspect Code'
$btnViewCode.Size = New-Object Drawing.Size(112, 34)
$btnViewCode.FlatStyle = 'Flat'
$btnViewCode.Cursor = 'Hand'
$btnViewCode.Enabled = $false
$pnlDetActions.Controls.Add($btnViewCode)

$btnTranslate = New-Object Windows.Forms.Button
$btnTranslate.Text = 'Translate'
$btnTranslate.Size = New-Object Drawing.Size(105, 34)
$btnTranslate.FlatStyle = 'Flat'
$btnTranslate.Cursor = 'Hand'
$btnTranslate.Enabled = $false
$toolTip.SetToolTip($btnTranslate, 'Translate package description and release notes (auto-detects source language)')
$pnlDetActions.Controls.Add($btnTranslate)

$cmbTargetLang = New-Object Windows.Forms.ComboBox
$cmbTargetLang.DropDownStyle = 'DropDownList'
$cmbTargetLang.Width = 118
$cmbTargetLang.Font = $fontUi
$cmbTargetLang.Margin = New-Object Windows.Forms.Padding(4, 6, 3, 3)
$cmbTargetLang.Enabled = $false
[void]$cmbTargetLang.Items.AddRange(@(
    'English (en)',
    'Spanish (es)',
    'German (de)',
    'French (fr)',
    'Portuguese (pt)',
    'Italian (it)',
    'Dutch (nl)',
    'Polish (pl)',
    'Russian (ru)',
    'Japanese (ja)',
    'Korean (ko)',
    'Chinese (zh-CN)'
))
$cmbTargetLang.SelectedIndex = 0
$toolTip.SetToolTip($cmbTargetLang, 'Target language for package description translation')
$pnlDetActions.Controls.Add($cmbTargetLang)


$txtDetBody = New-Object Windows.Forms.TextBox
$txtDetBody.Multiline = $true
$txtDetBody.ReadOnly = $true
$txtDetBody.ScrollBars = 'Vertical'
$txtDetBody.Dock = 'Fill'
$txtDetBody.BorderStyle = 'FixedSingle'
$pnlDetails.Controls.Add($txtDetBody)
$txtDetBody.BringToFront()

# ==============================================================================
# VIEW 2: MY GALLERY & LOCAL SCRIPTS/MODULES
# ==============================================================================
$viewMyScripts = New-Object Windows.Forms.Panel
$viewMyScripts.Dock = 'Fill'
$viewMyScripts.Visible = $false
$pnlMain.Controls.Add($viewMyScripts)

$pnlMySubNav = New-Object Windows.Forms.Panel
$pnlMySubNav.Dock = 'Top'
$pnlMySubNav.Height = 46
$pnlMySubNav.Padding = New-Object Windows.Forms.Padding(10, 7, 10, 7)
$viewMyScripts.Controls.Add($pnlMySubNav)

$btnSubPublished = New-Object Windows.Forms.Button
$btnSubPublished.Text = 'My Published Gallery Packages'
$btnSubPublished.Font = $fontUiBold
$btnSubPublished.Location = New-Object Drawing.Point(10, 7)
$btnSubPublished.Size = New-Object Drawing.Size(230, 32)
$btnSubPublished.FlatStyle = 'Flat'
$btnSubPublished.Cursor = 'Hand'
$pnlMySubNav.Controls.Add($btnSubPublished)

$btnSubLocal = New-Object Windows.Forms.Button
$btnSubLocal.Text = 'Installed on This PC (Scripts && Modules)'
$btnSubLocal.Font = $fontUiBold
$btnSubLocal.Location = New-Object Drawing.Point(248, 7)
$btnSubLocal.Size = New-Object Drawing.Size(275, 32)
$btnSubLocal.FlatStyle = 'Flat'
$btnSubLocal.Cursor = 'Hand'
$pnlMySubNav.Controls.Add($btnSubLocal)

# --- Sub-view A: My Published PSGallery Items ---
$subViewPublished = New-Object Windows.Forms.Panel
$subViewPublished.Dock = 'Fill'
$viewMyScripts.Controls.Add($subViewPublished)
$subViewPublished.BringToFront()

$pnlPubBar = New-Object Windows.Forms.Panel
$pnlPubBar.Dock = 'Top'
$pnlPubBar.Height = 48
$pnlPubBar.Padding = New-Object Windows.Forms.Padding(10, 8, 10, 8)
$subViewPublished.Controls.Add($pnlPubBar)

$lblPubAccount = New-Object Windows.Forms.Label
$lblPubAccount.Text = 'Publisher Username:'
$lblPubAccount.AutoSize = $true
$lblPubAccount.Location = New-Object Drawing.Point(10, 14)
$pnlPubBar.Controls.Add($lblPubAccount)

$txtPubUser = New-Object Windows.Forms.TextBox
$txtPubUser.Location = New-Object Drawing.Point(145, 11)
$txtPubUser.Size = New-Object Drawing.Size(185, 26)
$txtPubUser.BorderStyle = 'FixedSingle'
$txtPubUser.Text = $script:Config.Username
$pnlPubBar.Controls.Add($txtPubUser)

$btnRefreshPub = New-Object Windows.Forms.Button
$btnRefreshPub.Text = 'Load My Packages'
$btnRefreshPub.Font = $fontUiBold
$btnRefreshPub.Location = New-Object Drawing.Point(338, 9)
$btnRefreshPub.Size = New-Object Drawing.Size(140, 30)
$btnRefreshPub.FlatStyle = 'Flat'
$btnRefreshPub.Cursor = 'Hand'
$pnlPubBar.Controls.Add($btnRefreshPub)

$btnPubDownload = New-Object Windows.Forms.Button
$btnPubDownload.Text = 'Download Copy'
$btnPubDownload.Location = New-Object Drawing.Point(486, 9)
$btnPubDownload.Size = New-Object Drawing.Size(120, 30)
$btnPubDownload.FlatStyle = 'Flat'
$btnPubDownload.Cursor = 'Hand'
$pnlPubBar.Controls.Add($btnPubDownload)

$btnPubInspect = New-Object Windows.Forms.Button
$btnPubInspect.Text = 'Inspect Code'
$btnPubInspect.Location = New-Object Drawing.Point(614, 9)
$btnPubInspect.Size = New-Object Drawing.Size(110, 30)
$btnPubInspect.FlatStyle = 'Flat'
$btnPubInspect.Cursor = 'Hand'
$pnlPubBar.Controls.Add($btnPubInspect)

$btnPubOpenWeb = New-Object Windows.Forms.Button
$btnPubOpenWeb.Text = 'Manage on Web'
$btnPubOpenWeb.Location = New-Object Drawing.Point(732, 9)
$btnPubOpenWeb.Size = New-Object Drawing.Size(120, 30)
$btnPubOpenWeb.FlatStyle = 'Flat'
$btnPubOpenWeb.Cursor = 'Hand'
$pnlPubBar.Controls.Add($btnPubOpenWeb)

$btnPubUnlist = New-Object Windows.Forms.Button
$btnPubUnlist.Text = 'Unlist Version (API Key)'
$btnPubUnlist.Location = New-Object Drawing.Point(860, 9)
$btnPubUnlist.Size = New-Object Drawing.Size(165, 30)
$btnPubUnlist.FlatStyle = 'Flat'
$btnPubUnlist.Cursor = 'Hand'
$pnlPubBar.Controls.Add($btnPubUnlist)

$dgvPublished = New-Object Windows.Forms.DataGridView
$dgvPublished.Dock = 'Fill'
$dgvPublished.ReadOnly = $true
$dgvPublished.AllowUserToAddRows = $false
$dgvPublished.AllowUserToDeleteRows = $false
$dgvPublished.AllowUserToResizeRows = $false
$dgvPublished.RowHeadersVisible = $false
$dgvPublished.SelectionMode = 'FullRowSelect'
$dgvPublished.MultiSelect = $false
$dgvPublished.AutoSizeColumnsMode = 'Fill'
$dgvPublished.BorderStyle = 'None'
$dgvPublished.CellBorderStyle = 'SingleHorizontal'
$dgvPublished.EnableHeadersVisualStyles = $false
$dgvPublished.ColumnHeadersHeight = 34
$dgvPublished.RowTemplate.Height = 30
$subViewPublished.Controls.Add($dgvPublished)
$dgvPublished.BringToFront()

# --- Sub-view B: Local Installed Scripts & Modules ---
$subViewLocal = New-Object Windows.Forms.Panel
$subViewLocal.Dock = 'Fill'
$subViewLocal.Visible = $false
$viewMyScripts.Controls.Add($subViewLocal)

$pnlLocalBar = New-Object Windows.Forms.Panel
$pnlLocalBar.Dock = 'Top'
$pnlLocalBar.Height = 48
$pnlLocalBar.Padding = New-Object Windows.Forms.Padding(10, 8, 10, 8)
$subViewLocal.Controls.Add($pnlLocalBar)

$btnScanLocal = New-Object Windows.Forms.Button
$btnScanLocal.Text = 'Refresh Installed'
$btnScanLocal.Font = $fontUiBold
$btnScanLocal.Location = New-Object Drawing.Point(10, 9)
$btnScanLocal.Size = New-Object Drawing.Size(140, 30)
$btnScanLocal.FlatStyle = 'Flat'
$btnScanLocal.Cursor = 'Hand'
$pnlLocalBar.Controls.Add($btnScanLocal)

$btnCheckUpdates = New-Object Windows.Forms.Button
$btnCheckUpdates.Text = 'Check Gallery Updates'
$btnCheckUpdates.Font = $fontUiBold
$btnCheckUpdates.Location = New-Object Drawing.Point(158, 9)
$btnCheckUpdates.Size = New-Object Drawing.Size(175, 30)
$btnCheckUpdates.FlatStyle = 'Flat'
$btnCheckUpdates.Cursor = 'Hand'
$pnlLocalBar.Controls.Add($btnCheckUpdates)

$btnUpdateLocal = New-Object Windows.Forms.Button
$btnUpdateLocal.Text = 'Update Selected'
$btnUpdateLocal.Location = New-Object Drawing.Point(341, 9)
$btnUpdateLocal.Size = New-Object Drawing.Size(130, 30)
$btnUpdateLocal.FlatStyle = 'Flat'
$btnUpdateLocal.Cursor = 'Hand'
$pnlLocalBar.Controls.Add($btnUpdateLocal)

$btnUninstallLocal = New-Object Windows.Forms.Button
$btnUninstallLocal.Text = 'Uninstall Selected'
$btnUninstallLocal.Location = New-Object Drawing.Point(479, 9)
$btnUninstallLocal.Size = New-Object Drawing.Size(135, 30)
$btnUninstallLocal.FlatStyle = 'Flat'
$btnUninstallLocal.Cursor = 'Hand'
$pnlLocalBar.Controls.Add($btnUninstallLocal)

$btnOpenLocalFolder = New-Object Windows.Forms.Button
$btnOpenLocalFolder.Text = 'Open Folder'
$btnOpenLocalFolder.Location = New-Object Drawing.Point(622, 9)
$btnOpenLocalFolder.Size = New-Object Drawing.Size(110, 30)
$btnOpenLocalFolder.FlatStyle = 'Flat'
$btnOpenLocalFolder.Cursor = 'Hand'
$pnlLocalBar.Controls.Add($btnOpenLocalFolder)

$btnEditLocal = New-Object Windows.Forms.Button
$btnEditLocal.Text = 'Open in Editor'
$btnEditLocal.Location = New-Object Drawing.Point(740, 9)
$btnEditLocal.Size = New-Object Drawing.Size(120, 30)
$btnEditLocal.FlatStyle = 'Flat'
$btnEditLocal.Cursor = 'Hand'
$pnlLocalBar.Controls.Add($btnEditLocal)

$btnLocalShortcut = New-Object Windows.Forms.Button
$btnLocalShortcut.Text = 'Desktop Shortcut...'
$btnLocalShortcut.Location = New-Object Drawing.Point(868, 9)
$btnLocalShortcut.Size = New-Object Drawing.Size(145, 30)
$btnLocalShortcut.FlatStyle = 'Flat'
$btnLocalShortcut.Cursor = 'Hand'
$toolTip.SetToolTip($btnLocalShortcut, 'Create a Desktop shortcut (.lnk) for the selected local script (or double-click / right-click a row)')
$pnlLocalBar.Controls.Add($btnLocalShortcut)

$ctxLocalMenu = New-Object System.Windows.Forms.ContextMenuStrip
$mnuLocalShortcut = New-Object System.Windows.Forms.ToolStripMenuItem('Create Desktop Shortcut (.lnk)...')
$mnuLocalShortcut.Font = $fontUiBold
$mnuLocalEdit = New-Object System.Windows.Forms.ToolStripMenuItem('Open in Editor')
$mnuLocalFolder = New-Object System.Windows.Forms.ToolStripMenuItem('Open Folder')
$mnuLocalUpdate = New-Object System.Windows.Forms.ToolStripMenuItem('Update Selected')
$mnuLocalUninstall = New-Object System.Windows.Forms.ToolStripMenuItem('Uninstall Selected')
[void]$ctxLocalMenu.Items.AddRange(@(
    $mnuLocalShortcut,
    (New-Object System.Windows.Forms.ToolStripSeparator),
    $mnuLocalEdit,
    $mnuLocalFolder,
    $mnuLocalUpdate,
    $mnuLocalUninstall
))

$dgvLocal = New-Object Windows.Forms.DataGridView
$dgvLocal.Dock = 'Fill'
$dgvLocal.ReadOnly = $true
$dgvLocal.AllowUserToAddRows = $false
$dgvLocal.AllowUserToDeleteRows = $false
$dgvLocal.AllowUserToResizeRows = $false
$dgvLocal.RowHeadersVisible = $false
$dgvLocal.SelectionMode = 'FullRowSelect'
$dgvLocal.MultiSelect = $false
$dgvLocal.AutoSizeColumnsMode = 'Fill'
$dgvLocal.BorderStyle = 'None'
$dgvLocal.CellBorderStyle = 'SingleHorizontal'
$dgvLocal.EnableHeadersVisualStyles = $false
$dgvLocal.ColumnHeadersHeight = 34
$dgvLocal.RowTemplate.Height = 30
$dgvLocal.ContextMenuStrip = $ctxLocalMenu
$subViewLocal.Controls.Add($dgvLocal)
$dgvLocal.BringToFront()

# ==============================================================================
# VIEW 3: PUBLISH TO POWERSHELL GALLERY (UNIFIED MODERN FLAT UI)
# ==============================================================================
$viewPublish = New-Object Windows.Forms.Panel
$viewPublish.Dock = 'Fill'
$viewPublish.Visible = $false
$pnlMain.Controls.Add($viewPublish)

$pnlPubLeft = New-Object Windows.Forms.Panel
$pnlPubLeft.Dock = 'Left'
$pnlPubLeft.Width = 680
$pnlPubLeft.Padding = New-Object Windows.Forms.Padding(12)
$viewPublish.Controls.Add($pnlPubLeft)

$pnlPubSpacer = New-Object Windows.Forms.Panel
$pnlPubSpacer.Dock = 'Left'
$pnlPubSpacer.Width = 10
$viewPublish.Controls.Add($pnlPubSpacer)
$pnlPubSpacer.BringToFront()

$pnlPubRight = New-Object Windows.Forms.Panel
$pnlPubRight.Dock = 'Fill'
$pnlPubRight.Padding = New-Object Windows.Forms.Padding(14)
$viewPublish.Controls.Add($pnlPubRight)
$pnlPubRight.BringToFront()

$grpPubTarget = New-Object Windows.Forms.GroupBox
$grpPubTarget.Text = 'Package Type, Recent History && Repository'
$grpPubTarget.Location = New-Object Drawing.Point(12, 10)
$grpPubTarget.Size = New-Object Drawing.Size(656, 162)
$pnlPubLeft.Controls.Add($grpPubTarget)

$lblPubMode = New-Object Windows.Forms.Label
$lblPubMode.Text = 'Package Type:'
$lblPubMode.Location = New-Object Drawing.Point(16, 26)
$lblPubMode.Size = New-Object Drawing.Size(98, 23)
$grpPubTarget.Controls.Add($lblPubMode)

$rbPubScript = New-Object Windows.Forms.RadioButton
$rbPubScript.Text = 'Standalone Script (.ps1)'
$rbPubScript.Checked = $true
$rbPubScript.Location = New-Object Drawing.Point(120, 24)
$rbPubScript.Size = New-Object Drawing.Size(190, 24)
$grpPubTarget.Controls.Add($rbPubScript)

$rbPubModule = New-Object Windows.Forms.RadioButton
$rbPubModule.Text = 'Module Folder (.psd1 / .psm1)'
$rbPubModule.Location = New-Object Drawing.Point(320, 24)
$rbPubModule.Size = New-Object Drawing.Size(230, 24)
$grpPubTarget.Controls.Add($rbPubModule)

$lblPubRecent = New-Object Windows.Forms.Label
$lblPubRecent.Text = 'Recent:'
$lblPubRecent.Location = New-Object Drawing.Point(16, 58)
$lblPubRecent.Size = New-Object Drawing.Size(98, 23)
$grpPubTarget.Controls.Add($lblPubRecent)

$cmbPubRecent = New-Object Windows.Forms.ComboBox
$cmbPubRecent.DropDownStyle = 'DropDownList'
$cmbPubRecent.DropDownWidth = 560
$cmbPubRecent.Location = New-Object Drawing.Point(120, 55)
$cmbPubRecent.Size = New-Object Drawing.Size(448, 25)
$toolTip.SetToolTip($cmbPubRecent, 'Quickly switch between recently selected scripts and module folders')
$grpPubTarget.Controls.Add($cmbPubRecent)

$btnPubClearRecent = New-Object Windows.Forms.Button
$btnPubClearRecent.Text = 'Clear'
$btnPubClearRecent.Location = New-Object Drawing.Point(574, 54)
$btnPubClearRecent.Size = New-Object Drawing.Size(66, 27)
$btnPubClearRecent.FlatStyle = 'Flat'
$btnPubClearRecent.Cursor = 'Hand'
$grpPubTarget.Controls.Add($btnPubClearRecent)

$lblPubPath = New-Object Windows.Forms.Label
$lblPubPath.Text = 'Script (.ps1):'
$lblPubPath.Location = New-Object Drawing.Point(16, 92)
$lblPubPath.Size = New-Object Drawing.Size(98, 23)
$grpPubTarget.Controls.Add($lblPubPath)

$txtPubPath = New-Object Windows.Forms.TextBox
$txtPubPath.Location = New-Object Drawing.Point(120, 89)
$txtPubPath.Size = New-Object Drawing.Size(428, 25)
$txtPubPath.BorderStyle = 'FixedSingle'
$grpPubTarget.Controls.Add($txtPubPath)

$btnPubBrowse = New-Object Windows.Forms.Button
$btnPubBrowse.Text = 'Browse...'
$btnPubBrowse.Location = New-Object Drawing.Point(554, 88)
$btnPubBrowse.Size = New-Object Drawing.Size(86, 27)
$btnPubBrowse.FlatStyle = 'Flat'
$btnPubBrowse.Cursor = 'Hand'
$grpPubTarget.Controls.Add($btnPubBrowse)

$lblPubRepo = New-Object Windows.Forms.Label
$lblPubRepo.Text = 'Repository:'
$lblPubRepo.Location = New-Object Drawing.Point(16, 126)
$lblPubRepo.Size = New-Object Drawing.Size(98, 23)
$grpPubTarget.Controls.Add($lblPubRepo)

$txtPubRepo = New-Object Windows.Forms.TextBox
$txtPubRepo.Text = 'PSGallery'
$txtPubRepo.Location = New-Object Drawing.Point(120, 123)
$txtPubRepo.Size = New-Object Drawing.Size(165, 25)
$txtPubRepo.BorderStyle = 'FixedSingle'
$grpPubTarget.Controls.Add($txtPubRepo)

$lblPubVaultBadge = New-Object Windows.Forms.Label
$lblPubVaultBadge.TextAlign = 'MiddleRight'
$lblPubVaultBadge.Font = $fontBadge
$lblPubVaultBadge.Location = New-Object Drawing.Point(292, 126)
$lblPubVaultBadge.Size = New-Object Drawing.Size(348, 22)
$grpPubTarget.Controls.Add($lblPubVaultBadge)

$grpPubMeta = New-Object Windows.Forms.GroupBox
$grpPubMeta.Text = 'Package Metadata (PSScriptInfo for .ps1 / Manifest .psd1 for Modules)'
$grpPubMeta.Location = New-Object Drawing.Point(12, 180)
$grpPubMeta.Size = New-Object Drawing.Size(656, 344)
$pnlPubLeft.Controls.Add($grpPubMeta)

$lblPubVer = New-Object Windows.Forms.Label
$lblPubVer.Text = 'Version *:'
$lblPubVer.Location = New-Object Drawing.Point(16, 28)
$lblPubVer.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubVer)

$txtPubVersion = New-Object Windows.Forms.TextBox
$txtPubVersion.Text = '1.0.0'
$txtPubVersion.Location = New-Object Drawing.Point(120, 25)
$txtPubVersion.Size = New-Object Drawing.Size(74, 25)
$txtPubVersion.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubVersion)

$btnPubBumpMajor = New-Object Windows.Forms.Button
$btnPubBumpMajor.Text = 'Major'
$btnPubBumpMajor.Font = $fontSmall
$btnPubBumpMajor.Location = New-Object Drawing.Point(198, 24)
$btnPubBumpMajor.Size = New-Object Drawing.Size(48, 26)
$btnPubBumpMajor.FlatStyle = 'Flat'
$btnPubBumpMajor.Cursor = 'Hand'
$toolTip.SetToolTip($btnPubBumpMajor, 'Increment Major version (X.0.0)')
$grpPubMeta.Controls.Add($btnPubBumpMajor)

$btnPubBumpMinor = New-Object Windows.Forms.Button
$btnPubBumpMinor.Text = 'Minor'
$btnPubBumpMinor.Font = $fontSmall
$btnPubBumpMinor.Location = New-Object Drawing.Point(248, 24)
$btnPubBumpMinor.Size = New-Object Drawing.Size(48, 26)
$btnPubBumpMinor.FlatStyle = 'Flat'
$btnPubBumpMinor.Cursor = 'Hand'
$toolTip.SetToolTip($btnPubBumpMinor, 'Increment Minor version (x.Y.0)')
$grpPubMeta.Controls.Add($btnPubBumpMinor)

$btnPubBumpPatch = New-Object Windows.Forms.Button
$btnPubBumpPatch.Text = 'Patch'
$btnPubBumpPatch.Font = $fontSmall
$btnPubBumpPatch.Location = New-Object Drawing.Point(298, 24)
$btnPubBumpPatch.Size = New-Object Drawing.Size(48, 26)
$btnPubBumpPatch.FlatStyle = 'Flat'
$btnPubBumpPatch.Cursor = 'Hand'
$toolTip.SetToolTip($btnPubBumpPatch, 'Increment Patch version (x.y.Z)')
$grpPubMeta.Controls.Add($btnPubBumpPatch)

$lblPubAuthor = New-Object Windows.Forms.Label
$lblPubAuthor.Text = 'Author *:'
$lblPubAuthor.Location = New-Object Drawing.Point(356, 28)
$lblPubAuthor.Size = New-Object Drawing.Size(68, 23)
$grpPubMeta.Controls.Add($lblPubAuthor)

$txtPubAuthor = New-Object Windows.Forms.TextBox
$txtPubAuthor.Location = New-Object Drawing.Point(426, 25)
$txtPubAuthor.Size = New-Object Drawing.Size(152, 25)
$txtPubAuthor.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubAuthor)

$btnPubSaveAuthor = New-Object Windows.Forms.Button
$btnPubSaveAuthor.Text = 'Save'
$btnPubSaveAuthor.Font = $fontSmall
$btnPubSaveAuthor.Location = New-Object Drawing.Point(582, 24)
$btnPubSaveAuthor.Size = New-Object Drawing.Size(58, 26)
$btnPubSaveAuthor.FlatStyle = 'Flat'
$btnPubSaveAuthor.Cursor = 'Hand'
$toolTip.SetToolTip($btnPubSaveAuthor, 'Save username to shared config.json')
$grpPubMeta.Controls.Add($btnPubSaveAuthor)

$lblPubCompany = New-Object Windows.Forms.Label
$lblPubCompany.Text = 'Company:'
$lblPubCompany.Location = New-Object Drawing.Point(16, 62)
$lblPubCompany.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubCompany)

$txtPubCompany = New-Object Windows.Forms.TextBox
$txtPubCompany.Location = New-Object Drawing.Point(120, 59)
$txtPubCompany.Size = New-Object Drawing.Size(226, 25)
$txtPubCompany.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubCompany)

$lblPubCopyright = New-Object Windows.Forms.Label
$lblPubCopyright.Text = 'Copyright:'
$lblPubCopyright.Location = New-Object Drawing.Point(356, 62)
$lblPubCopyright.Size = New-Object Drawing.Size(68, 23)
$grpPubMeta.Controls.Add($lblPubCopyright)

$txtPubCopyright = New-Object Windows.Forms.TextBox
$txtPubCopyright.Location = New-Object Drawing.Point(426, 59)
$txtPubCopyright.Size = New-Object Drawing.Size(214, 25)
$txtPubCopyright.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubCopyright)

$lblPubDesc = New-Object Windows.Forms.Label
$lblPubDesc.Text = 'Description *:'
$lblPubDesc.Location = New-Object Drawing.Point(16, 96)
$lblPubDesc.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubDesc)

$txtPubDesc = New-Object Windows.Forms.TextBox
$txtPubDesc.Location = New-Object Drawing.Point(120, 93)
$txtPubDesc.Size = New-Object Drawing.Size(520, 54)
$txtPubDesc.Multiline = $true
$txtPubDesc.ScrollBars = 'Vertical'
$txtPubDesc.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubDesc)

$lblPubTags = New-Object Windows.Forms.Label
$lblPubTags.Text = 'Tags:'
$lblPubTags.Location = New-Object Drawing.Point(16, 158)
$lblPubTags.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubTags)

$txtPubTags = New-Object Windows.Forms.TextBox
$txtPubTags.Text = 'PowerShell, Automation'
$txtPubTags.Location = New-Object Drawing.Point(120, 155)
$txtPubTags.Size = New-Object Drawing.Size(520, 25)
$txtPubTags.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubTags)

$lblPubProjUri = New-Object Windows.Forms.Label
$lblPubProjUri.Text = 'Project URI:'
$lblPubProjUri.Location = New-Object Drawing.Point(16, 192)
$lblPubProjUri.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubProjUri)

$txtPubProjUri = New-Object Windows.Forms.TextBox
$txtPubProjUri.Location = New-Object Drawing.Point(120, 190)
$txtPubProjUri.Size = New-Object Drawing.Size(520, 25)
$txtPubProjUri.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubProjUri)

$lblPubLicUri = New-Object Windows.Forms.Label
$lblPubLicUri.Text = 'License URI:'
$lblPubLicUri.Location = New-Object Drawing.Point(16, 226)
$lblPubLicUri.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubLicUri)

$txtPubLicUri = New-Object Windows.Forms.TextBox
$txtPubLicUri.Location = New-Object Drawing.Point(120, 224)
$txtPubLicUri.Size = New-Object Drawing.Size(520, 25)
$txtPubLicUri.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubLicUri)

$lblPubNotes = New-Object Windows.Forms.Label
$lblPubNotes.Text = 'Release Notes:'
$lblPubNotes.Location = New-Object Drawing.Point(16, 260)
$lblPubNotes.Size = New-Object Drawing.Size(98, 23)
$grpPubMeta.Controls.Add($lblPubNotes)

$txtPubNotes = New-Object Windows.Forms.TextBox
$txtPubNotes.Location = New-Object Drawing.Point(120, 258)
$txtPubNotes.Size = New-Object Drawing.Size(520, 44)
$txtPubNotes.Multiline = $true
$txtPubNotes.ScrollBars = 'Vertical'
$txtPubNotes.BorderStyle = 'FixedSingle'
$grpPubMeta.Controls.Add($txtPubNotes)

$chkPubAutoMeta = New-Object Windows.Forms.CheckBox
$chkPubAutoMeta.Text = 'Auto-inject or update metadata (.ps1 / .psd1) before Validate or Publish'
$chkPubAutoMeta.Checked = $true
$chkPubAutoMeta.Location = New-Object Drawing.Point(16, 311)
$chkPubAutoMeta.Size = New-Object Drawing.Size(496, 22)
$grpPubMeta.Controls.Add($chkPubAutoMeta)

$btnPubSaveMeta = New-Object Windows.Forms.Button
$btnPubSaveMeta.Text = 'Save Metadata'
$btnPubSaveMeta.Font = $fontSmall
$btnPubSaveMeta.Location = New-Object Drawing.Point(520, 308)
$btnPubSaveMeta.Size = New-Object Drawing.Size(120, 26)
$btnPubSaveMeta.FlatStyle = 'Flat'
$btnPubSaveMeta.Cursor = 'Hand'
$grpPubMeta.Controls.Add($btnPubSaveMeta)

$btnPubCheckLive = New-Object Windows.Forms.Button
$btnPubCheckLive.Text = 'Check Live Ver'
$btnPubCheckLive.Location = New-Object Drawing.Point(12, 534)
$btnPubCheckLive.Size = New-Object Drawing.Size(122, 36)
$btnPubCheckLive.FlatStyle = 'Flat'
$btnPubCheckLive.Cursor = 'Hand'
$pnlPubLeft.Controls.Add($btnPubCheckLive)

$btnPubValidate = New-Object Windows.Forms.Button
$btnPubValidate.Text = 'Validate'
$btnPubValidate.Location = New-Object Drawing.Point(140, 534)
$btnPubValidate.Size = New-Object Drawing.Size(96, 36)
$btnPubValidate.FlatStyle = 'Flat'
$btnPubValidate.Cursor = 'Hand'
$pnlPubLeft.Controls.Add($btnPubValidate)

$btnPubRepairTls = New-Object Windows.Forms.Button
$btnPubRepairTls.Text = 'Repair TLS / Tools'
$btnPubRepairTls.Location = New-Object Drawing.Point(242, 534)
$btnPubRepairTls.Size = New-Object Drawing.Size(136, 36)
$btnPubRepairTls.FlatStyle = 'Flat'
$btnPubRepairTls.Cursor = 'Hand'
$pnlPubLeft.Controls.Add($btnPubRepairTls)

$btnPubCancel = New-Object Windows.Forms.Button
$btnPubCancel.Text = 'Cancel'
$btnPubCancel.Enabled = $false
$btnPubCancel.Location = New-Object Drawing.Point(384, 534)
$btnPubCancel.Size = New-Object Drawing.Size(72, 36)
$btnPubCancel.FlatStyle = 'Flat'
$btnPubCancel.Cursor = 'Hand'
$pnlPubLeft.Controls.Add($btnPubCancel)

$btnPubPublish = New-Object Windows.Forms.Button
$btnPubPublish.Text = 'Publish to PSGallery'
$btnPubPublish.Font = $fontUiBold
$btnPubPublish.Location = New-Object Drawing.Point(462, 534)
$btnPubPublish.Size = New-Object Drawing.Size(206, 36)
$btnPubPublish.FlatStyle = 'Flat'
$btnPubPublish.Cursor = 'Hand'
$pnlPubLeft.Controls.Add($btnPubPublish)

$pnlPubStatusCard = New-Object Windows.Forms.Panel
$pnlPubStatusCard.Location = New-Object Drawing.Point(12, 580)
$pnlPubStatusCard.Size = New-Object Drawing.Size(656, 38)
$pnlPubStatusCard.BorderStyle = 'FixedSingle'
$pnlPubStatusCard.Padding = New-Object Windows.Forms.Padding(12, 7, 12, 7)
$pnlPubLeft.Controls.Add($pnlPubStatusCard)

$lblPubLiveVer = New-Object Windows.Forms.Label
$lblPubLiveVer.Text = 'Live Gallery Version: Not checked'
$lblPubLiveVer.Font = $fontBadge
$lblPubLiveVer.Dock = 'Left'
$lblPubLiveVer.Width = 340
$lblPubLiveVer.TextAlign = 'MiddleLeft'
$pnlPubStatusCard.Controls.Add($lblPubLiveVer)

$lblPubUploadState = New-Object Windows.Forms.Label
$lblPubUploadState.Text = 'Status: Idle'
$lblPubUploadState.Font = $fontBadge
$lblPubUploadState.Dock = 'Right'
$lblPubUploadState.Width = 280
$lblPubUploadState.TextAlign = 'MiddleRight'
$pnlPubStatusCard.Controls.Add($lblPubUploadState)

$pnlPubLogTop = New-Object Windows.Forms.Panel
$pnlPubLogTop.Dock = 'Top'
$pnlPubLogTop.Height = 36
$pnlPubRight.Controls.Add($pnlPubLogTop)

$lblPubLogTitle = New-Object Windows.Forms.Label
$lblPubLogTitle.Text = 'Publisher Output Log'
$lblPubLogTitle.Font = $fontSubHeader
$lblPubLogTitle.Location = New-Object Drawing.Point(0, 5)
$lblPubLogTitle.AutoSize = $true
$pnlPubLogTop.Controls.Add($lblPubLogTitle)

$btnPubClearLog = New-Object Windows.Forms.Button
$btnPubClearLog.Text = 'Clear Log'
$btnPubClearLog.Font = $fontSmall
$btnPubClearLog.Dock = 'Right'
$btnPubClearLog.Width = 84
$btnPubClearLog.FlatStyle = 'Flat'
$btnPubClearLog.Cursor = 'Hand'
$pnlPubLogTop.Controls.Add($btnPubClearLog)

$txtPubLog = New-Object Windows.Forms.TextBox
$txtPubLog.Multiline = $true
$txtPubLog.ReadOnly = $true
$txtPubLog.ScrollBars = 'Both'
$txtPubLog.WordWrap = $true
$txtPubLog.Dock = 'Fill'
$txtPubLog.Font = $fontMono
$txtPubLog.BorderStyle = 'FixedSingle'
$pnlPubRight.Controls.Add($txtPubLog)
$txtPubLog.BringToFront()

# ==============================================================================
# VIEW 4: SETTINGS, DPAPI KEYS & DESKTOP SHORTCUT LAUNCHER
# ==============================================================================
$viewSettings = New-Object Windows.Forms.Panel
$viewSettings.Dock = 'Fill'
$viewSettings.Visible = $false
$viewSettings.AutoScroll = $true
$pnlMain.Controls.Add($viewSettings)

$pnlSettingsCard = New-Object Windows.Forms.Panel
$pnlSettingsCard.Location = New-Object Drawing.Point(20, 16)
$pnlSettingsCard.Size = New-Object Drawing.Size(780, 635)
$pnlSettingsCard.Padding = New-Object Windows.Forms.Padding(24)
$viewSettings.Controls.Add($pnlSettingsCard)

$lblSetHeader = New-Object Windows.Forms.Label
$lblSetHeader.Text = 'Application Configuration, DPAPI Credentials && Shortcuts'
$lblSetHeader.Font = $fontTitle
$lblSetHeader.AutoSize = $true
$lblSetHeader.Location = New-Object Drawing.Point(24, 20)
$pnlSettingsCard.Controls.Add($lblSetHeader)

$lblSetUser = New-Object Windows.Forms.Label
$lblSetUser.Text = 'PowerShell Gallery Username (shared across My Gallery & Publisher):'
$lblSetUser.Font = $fontUiBold
$lblSetUser.AutoSize = $true
$lblSetUser.Location = New-Object Drawing.Point(24, 70)
$pnlSettingsCard.Controls.Add($lblSetUser)

$txtSetUser = New-Object Windows.Forms.TextBox
$txtSetUser.Location = New-Object Drawing.Point(24, 94)
$txtSetUser.Size = New-Object Drawing.Size(340, 28)
$txtSetUser.BorderStyle = 'FixedSingle'
$txtSetUser.Text = $script:Config.Username
$pnlSettingsCard.Controls.Add($txtSetUser)

$lblSetApi = New-Object Windows.Forms.Label
$lblSetApi.Text = 'PowerShell Gallery API Key (encrypted via Windows DPAPI CurrentUser):'
$lblSetApi.Font = $fontUiBold
$lblSetApi.AutoSize = $true
$lblSetApi.Location = New-Object Drawing.Point(24, 142)
$pnlSettingsCard.Controls.Add($lblSetApi)

$txtSetApiKey = New-Object Windows.Forms.TextBox
$txtSetApiKey.Location = New-Object Drawing.Point(24, 166)
$txtSetApiKey.Size = New-Object Drawing.Size(380, 28)
$txtSetApiKey.BorderStyle = 'FixedSingle'
$txtSetApiKey.UseSystemPasswordChar = $true
$txtSetApiKey.Text = (Get-ProtectedApiKey)
$pnlSettingsCard.Controls.Add($txtSetApiKey)

$btnToggleApi = New-Object Windows.Forms.Button
$btnToggleApi.Text = 'Show'
$btnToggleApi.Location = New-Object Drawing.Point(412, 165)
$btnToggleApi.Size = New-Object Drawing.Size(62, 28)
$btnToggleApi.FlatStyle = 'Flat'
$btnToggleApi.Cursor = 'Hand'
$pnlSettingsCard.Controls.Add($btnToggleApi)

$btnClearApi = New-Object Windows.Forms.Button
$btnClearApi.Text = 'Delete Key'
$btnClearApi.Location = New-Object Drawing.Point(482, 165)
$btnClearApi.Size = New-Object Drawing.Size(86, 28)
$btnClearApi.FlatStyle = 'Flat'
$btnClearApi.Cursor = 'Hand'
$pnlSettingsCard.Controls.Add($btnClearApi)

$btnOpenApiKeysPage = New-Object Windows.Forms.Button
$btnOpenApiKeysPage.Text = 'PSGallery API Keys...'
$btnOpenApiKeysPage.Location = New-Object Drawing.Point(576, 165)
$btnOpenApiKeysPage.Size = New-Object Drawing.Size(155, 28)
$btnOpenApiKeysPage.FlatStyle = 'Flat'
$btnOpenApiKeysPage.Cursor = 'Hand'
$toolTip.SetToolTip($btnOpenApiKeysPage, 'Open PowerShellGallery.com API Keys page to create a key with Push and Unlist permissions')
$pnlSettingsCard.Controls.Add($btnOpenApiKeysPage)

$lblApiStatus = New-Object Windows.Forms.Label
$lblApiStatus.AutoSize = $true
$lblApiStatus.Location = New-Object Drawing.Point(24, 200)
$pnlSettingsCard.Controls.Add($lblApiStatus)

$lblSetSavePath = New-Object Windows.Forms.Label
$lblSetSavePath.Text = 'Default Download / Save Folder:'
$lblSetSavePath.Font = $fontUiBold
$lblSetSavePath.AutoSize = $true
$lblSetSavePath.Location = New-Object Drawing.Point(24, 238)
$pnlSettingsCard.Controls.Add($lblSetSavePath)

$txtSetSavePath = New-Object Windows.Forms.TextBox
$txtSetSavePath.Location = New-Object Drawing.Point(24, 262)
$txtSetSavePath.Size = New-Object Drawing.Size(520, 28)
$txtSetSavePath.BorderStyle = 'FixedSingle'
$txtSetSavePath.Text = $script:Config.DefaultSavePath
$pnlSettingsCard.Controls.Add($txtSetSavePath)

$btnBrowseSave = New-Object Windows.Forms.Button
$btnBrowseSave.Text = 'Browse...'
$btnBrowseSave.Location = New-Object Drawing.Point(552, 261)
$btnBrowseSave.Size = New-Object Drawing.Size(95, 28)
$btnBrowseSave.FlatStyle = 'Flat'
$btnBrowseSave.Cursor = 'Hand'
$pnlSettingsCard.Controls.Add($btnBrowseSave)

$lblSetScope = New-Object Windows.Forms.Label
$lblSetScope.Text = 'Preferred Install Scope:'
$lblSetScope.Font = $fontUiBold
$lblSetScope.AutoSize = $true
$lblSetScope.Location = New-Object Drawing.Point(24, 310)
$pnlSettingsCard.Controls.Add($lblSetScope)

$cmbSetScope = New-Object Windows.Forms.ComboBox
$cmbSetScope.DropDownStyle = 'DropDownList'
$cmbSetScope.Location = New-Object Drawing.Point(24, 334)
$cmbSetScope.Size = New-Object Drawing.Size(340, 28)
[void]$cmbSetScope.Items.AddRange(@('Auto', 'AllUsers', 'CurrentUser'))
$cmbSetScope.SelectedItem = if ($script:Config.PreferredScope -in @('Auto', 'AllUsers', 'CurrentUser')) { $script:Config.PreferredScope } else { 'Auto' }
$pnlSettingsCard.Controls.Add($cmbSetScope)

$lblSetDefaultCompany = New-Object Windows.Forms.Label
$lblSetDefaultCompany.Text = 'Default Company Name (for new packages):'
$lblSetDefaultCompany.Font = $fontUiBold
$lblSetDefaultCompany.AutoSize = $true
$lblSetDefaultCompany.Location = New-Object Drawing.Point(24, 378)
$pnlSettingsCard.Controls.Add($lblSetDefaultCompany)

$txtSetDefaultCompany = New-Object Windows.Forms.TextBox
$txtSetDefaultCompany.Location = New-Object Drawing.Point(24, 402)
$txtSetDefaultCompany.Size = New-Object Drawing.Size(295, 28)
$txtSetDefaultCompany.BorderStyle = 'FixedSingle'
$txtSetDefaultCompany.Text = $script:Config.PubDefaultCompany
$pnlSettingsCard.Controls.Add($txtSetDefaultCompany)

$lblSetDefaultCopyright = New-Object Windows.Forms.Label
$lblSetDefaultCopyright.Text = 'Default Copyright (for new packages):'
$lblSetDefaultCopyright.Font = $fontUiBold
$lblSetDefaultCopyright.AutoSize = $true
$lblSetDefaultCopyright.Location = New-Object Drawing.Point(335, 378)
$pnlSettingsCard.Controls.Add($lblSetDefaultCopyright)

$txtSetDefaultCopyright = New-Object Windows.Forms.TextBox
$txtSetDefaultCopyright.Location = New-Object Drawing.Point(335, 402)
$txtSetDefaultCopyright.Size = New-Object Drawing.Size(312, 28)
$txtSetDefaultCopyright.BorderStyle = 'FixedSingle'
$txtSetDefaultCopyright.Text = $script:Config.PubDefaultCopyright
$pnlSettingsCard.Controls.Add($txtSetDefaultCopyright)

$chkAutoElevate = New-Object Windows.Forms.CheckBox
$chkAutoElevate.Text = 'Auto-elevate via UAC on startup (fall back to Standard mode if UAC is declined)'
$chkAutoElevate.AutoSize = $true
$chkAutoElevate.Location = New-Object Drawing.Point(24, 448)
$chkAutoElevate.Checked = [bool]$script:Config.AutoElevate
$pnlSettingsCard.Controls.Add($chkAutoElevate)

$lblPathsInfo = New-Object Windows.Forms.Label
$lblPathsInfo.Text = "Config File: $script:ConfigPath`nDPAPI Key File: $script:ApiKeyPath"
$lblPathsInfo.AutoSize = $true
$lblPathsInfo.Location = New-Object Drawing.Point(24, 486)
$pnlSettingsCard.Controls.Add($lblPathsInfo)

$btnSaveSettings = New-Object Windows.Forms.Button
$btnSaveSettings.Text = 'Save Configuration && Encrypt API Key'
$btnSaveSettings.Font = $fontUiBold
$btnSaveSettings.Location = New-Object Drawing.Point(24, 546)
$btnSaveSettings.Size = New-Object Drawing.Size(280, 38)
$btnSaveSettings.FlatStyle = 'Flat'
$btnSaveSettings.Cursor = 'Hand'
$pnlSettingsCard.Controls.Add($btnSaveSettings)

$btnOpenShortcutTool = New-Object Windows.Forms.Button
$btnOpenShortcutTool.Text = 'Create Desktop Shortcut (.lnk)...'
$btnOpenShortcutTool.Font = $fontUiBold
$btnOpenShortcutTool.Location = New-Object Drawing.Point(318, 546)
$btnOpenShortcutTool.Size = New-Object Drawing.Size(250, 38)
$btnOpenShortcutTool.FlatStyle = 'Flat'
$btnOpenShortcutTool.Cursor = 'Hand'
$pnlSettingsCard.Controls.Add($btnOpenShortcutTool)

# ==============================================================================
# 9. DESKTOP SHORTCUT CREATOR MODAL DIALOG
# ==============================================================================
function Get-Pwsh7Info {
    $exePath  = $null
    $iconPath = $null

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(
        (Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'),
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'PowerShell\7\pwsh.exe'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\PowerShell\pwsh.exe'),
        (Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7-preview\pwsh.exe'),
        (Join-Path -Path $env:USERPROFILE -ChildPath '.dotnet\tools\pwsh.exe'),
        (Join-Path -Path $env:USERPROFILE -ChildPath 'scoop\apps\powershell\current\pwsh.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { $candidates.Add($p) }
    }

    # Check Windows Registry App Paths and PowerShellCore InstalledVersions
    foreach ($regKey in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe'
    )) {
        try {
            $regVal = (Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue).'(default)'
            if (-not [string]::IsNullOrWhiteSpace($regVal)) { $candidates.Add($regVal.Trim('"')) }
        } catch { }
    }

    try {
        Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions\*' -ErrorAction SilentlyContinue | ForEach-Object {
            $dir = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).InstallLocation
            if (-not [string]::IsNullOrWhiteSpace($dir)) {
                $candidates.Add((Join-Path -Path $dir -ChildPath 'pwsh.exe'))
            }
        }
    } catch { }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $exePath  = $candidate
            $iconPath = $candidate
            break
        }
    }

    # Fallback: PATH / Microsoft Store (WindowsApps) installation
    if ([string]::IsNullOrWhiteSpace($exePath)) {
        $cmd = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue
        if ($null -eq $cmd) {
            $cmd = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue
        }
        if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
            if ($cmd.Source -like '*\WindowsApps\*') {
                $appx = Get-AppxPackage -Name 'Microsoft.PowerShell*' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $appx -and -not [string]::IsNullOrWhiteSpace($appx.InstallLocation)) {
                    $exePath = $cmd.Source
                    $realBin = Join-Path -Path $appx.InstallLocation -ChildPath 'pwsh.exe'
                    $iconPath = if (Test-Path -LiteralPath $realBin -PathType Leaf) { $realBin } else { $cmd.Source }
                }
            }
            elseif (Test-Path -LiteralPath $cmd.Source -PathType Leaf) {
                $exePath  = $cmd.Source
                $iconPath = $cmd.Source
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($exePath)) { return $null }

    return [PSCustomObject]@{
        ExePath  = $exePath
        IconPath = $iconPath
    }
}

function Show-DesktopShortcutDialog {
    param([string]$DefaultScriptPath = $PSCommandPath)

    $p = Get-ThemePalette
    $ps5ExePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ps5IconSpec = "$ps5ExePath,0"
    $winShellDll = Join-Path -Path $env:SystemRoot -ChildPath 'System32\shell32.dll'
    $desktopPath = [Environment]::GetFolderPath('Desktop')

    $scForm = New-Object System.Windows.Forms.Form -Property @{
        Text            = 'PowerShell Desktop Shortcut Creator'
        Size            = New-Object System.Drawing.Size(580, 552)
        MinimumSize     = New-Object System.Drawing.Size(580, 552)
        MaximumSize     = New-Object System.Drawing.Size(580, 552)
        StartPosition   = 'CenterParent'
        FormBorderStyle = 'FixedDialog'
        MaximizeBox     = $false
        MinimizeBox     = $false
        Font            = $fontUi
        BackColor       = $p.BgMain
        ForeColor       = $p.FgPrimary
    }

    $scForm.Add_Shown({
        if ($script:HasWin32) {
            try { [PSGalWin32]::SetDarkTitleBar($scForm.Handle, $p.IsDark) } catch { }
        }
    })

    $scLblScript = New-Object System.Windows.Forms.Label -Property @{
        Text = 'PowerShell Script (.ps1):'; Location = New-Object System.Drawing.Point(20, 16); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scTxtScript = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(20, 38); Size = New-Object System.Drawing.Size(435, 25); BorderStyle = 'FixedSingle'
        BackColor = $p.BgInput; ForeColor = $p.FgPrimary
    }
    $scBtnBrowse = New-Object System.Windows.Forms.Button -Property @{
        Text = 'Browse...'; Location = New-Object System.Drawing.Point(463, 37); Size = New-Object System.Drawing.Size(83, 26); FlatStyle = 'Flat'; Cursor = 'Hand'
        BackColor = $p.BtnSecondary; ForeColor = $p.FgPrimary
    }
    $scBtnBrowse.FlatAppearance.BorderColor = $p.Border

    $scLblName = New-Object System.Windows.Forms.Label -Property @{
        Text = 'Desktop Shortcut Name:'; Location = New-Object System.Drawing.Point(20, 74); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scTxtName = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(20, 96); Size = New-Object System.Drawing.Size(526, 25); BorderStyle = 'FixedSingle'
        BackColor = $p.BgInput; ForeColor = $p.FgPrimary
    }

    $scLblIcon = New-Object System.Windows.Forms.Label -Property @{
        Text = 'Shortcut Icon (.ico, .exe, .dll):'; Location = New-Object System.Drawing.Point(20, 132); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scPnlIcon = New-Object System.Windows.Forms.Panel -Property @{
        Location = New-Object System.Drawing.Point(20, 154); Size = New-Object System.Drawing.Size(42, 42); BorderStyle = 'FixedSingle'; BackColor = $p.BgInput
    }
    $scPicIcon = New-Object System.Windows.Forms.PictureBox -Property @{
        Location = New-Object System.Drawing.Point(4, 4); Size = New-Object System.Drawing.Size(32, 32); SizeMode = 'Zoom'
    }
    $scPnlIcon.Controls.Add($scPicIcon)

    $scTxtIcon = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(70, 162); Size = New-Object System.Drawing.Size(228, 25); Text = $ps5IconSpec; BorderStyle = 'FixedSingle'
        BackColor = $p.BgInput; ForeColor = $p.FgPrimary
    }
    $scBtnIcon = New-Object System.Windows.Forms.Button -Property @{
        Text = 'Choose Icon...'; Location = New-Object System.Drawing.Point(304, 161); Size = New-Object System.Drawing.Size(88, 26); FlatStyle = 'Flat'; Cursor = 'Hand'
        BackColor = $p.BtnSecondary; ForeColor = $p.FgPrimary
    }
    $scBtnIcon.FlatAppearance.BorderColor = $p.Border

    $scBtnWinIcon = New-Object System.Windows.Forms.Button -Property @{
        Text = 'Windows Icons...'; Location = New-Object System.Drawing.Point(396, 161); Size = New-Object System.Drawing.Size(94, 26); FlatStyle = 'Flat'; Cursor = 'Hand'
        BackColor = $p.BtnSecondary; ForeColor = $p.FgPrimary
    }
    $scBtnWinIcon.FlatAppearance.BorderColor = $p.Border

    $scBtnResetIcon = New-Object System.Windows.Forms.Button -Property @{
        Text = 'Reset'; Location = New-Object System.Drawing.Point(494, 161); Size = New-Object System.Drawing.Size(52, 26); FlatStyle = 'Flat'; Cursor = 'Hand'
        BackColor = $p.BtnSecondary; ForeColor = $p.FgPrimary
    }
    $scBtnResetIcon.FlatAppearance.BorderColor = $p.Border

    $scGrpOpts = New-Object System.Windows.Forms.GroupBox -Property @{
        Text = 'PowerShell Launch Options'; Location = New-Object System.Drawing.Point(20, 210); Size = New-Object System.Drawing.Size(526, 166)
        BackColor = $p.BgPanel; ForeColor = $p.FgPrimary
    }
    Initialize-ThemedGroupBox -GroupBox $scGrpOpts

    $scLblMode = New-Object System.Windows.Forms.Label -Property @{
        Text = 'PowerShell Mode:'; Location = New-Object System.Drawing.Point(16, 29); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scCmbMode = New-Object System.Windows.Forms.ComboBox -Property @{
        Location = New-Object System.Drawing.Point(132, 25); Size = New-Object System.Drawing.Size(204, 25); DropDownStyle = 'DropDownList'
        BackColor = $p.BgInput; ForeColor = $p.FgPrimary
    }
    [void]$scCmbMode.Items.AddRange(@('PowerShell 5.1 (powershell.exe)', 'PowerShell 7.x (pwsh.exe)'))
    $savedMode = if ($null -ne $script:Config -and ($script:Config.PSObject.Properties.Name -contains 'DefaultShortcutPsMode')) {
        [string]$script:Config.DefaultShortcutPsMode
    } else { '5.1' }
    $scCmbMode.SelectedIndex = if ($savedMode -eq '7.x') { 1 } else { 0 }
    Initialize-ThemedComboBox -ComboBox $scCmbMode

    $scLblModeStatus = New-Object System.Windows.Forms.Label -Property @{
        Text = ''; Location = New-Object System.Drawing.Point(344, 29); Size = New-Object System.Drawing.Size(172, 20); ForeColor = $p.FgSecondary
    }

    $scChkRunAs = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = 'Run as Administrator (UAC prompt on launch)'; Location = New-Object System.Drawing.Point(16, 60); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scChkNoExit = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = 'Keep PowerShell window open after script finishes (-NoExit)'; Location = New-Object System.Drawing.Point(16, 86); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scChkBypass = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = 'Bypass Execution Policy (-ExecutionPolicy Bypass)'; Location = New-Object System.Drawing.Point(16, 112); Checked = $true; AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scLblWin = New-Object System.Windows.Forms.Label -Property @{
        Text = 'Window:'; Location = New-Object System.Drawing.Point(346, 62); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scCmbWin = New-Object System.Windows.Forms.ComboBox -Property @{
        Location = New-Object System.Drawing.Point(404, 58); Size = New-Object System.Drawing.Size(106, 25); DropDownStyle = 'DropDownList'
        BackColor = $p.BgInput; ForeColor = $p.FgPrimary
    }
    [void]$scCmbWin.Items.AddRange(@('Normal', 'Minimized', 'Maximized', 'Hidden'))
    $scCmbWin.SelectedIndex = 3
    Initialize-ThemedComboBox -ComboBox $scCmbWin

    $scLblArgs = New-Object System.Windows.Forms.Label -Property @{
        Text = 'Script Arguments (optional):'; Location = New-Object System.Drawing.Point(16, 138); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scTxtArgs = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(180, 135); Size = New-Object System.Drawing.Size(330, 23); BorderStyle = 'FixedSingle'
        BackColor = $p.BgInput; ForeColor = $p.FgPrimary
    }
    $scGrpOpts.Controls.AddRange(@(
        $scLblMode, $scCmbMode, $scLblModeStatus,
        $scChkRunAs, $scChkNoExit, $scChkBypass, $scLblWin, $scCmbWin, $scLblArgs, $scTxtArgs
    ))

    $scLblPreview = New-Object System.Windows.Forms.Label -Property @{
        Text = 'Shortcut Target Command Preview:'; Location = New-Object System.Drawing.Point(20, 386); AutoSize = $true; ForeColor = $p.FgPrimary
    }
    $scTxtPreview = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(20, 408); Size = New-Object System.Drawing.Size(526, 42); Multiline = $true; ReadOnly = $true
        BorderStyle = 'FixedSingle'; Font = $fontMono; BackColor = $p.BgLog; ForeColor = $p.FgSecondary
    }
    $scLblStatus = New-Object System.Windows.Forms.Label -Property @{
        Text = 'Ready to create Desktop shortcut.'; Location = New-Object System.Drawing.Point(20, 464); Size = New-Object System.Drawing.Size(330, 34); ForeColor = $p.FgSecondary
    }
    $scBtnCreate = New-Object System.Windows.Forms.Button -Property @{
        Text = 'Create Shortcut'; Location = New-Object System.Drawing.Point(358, 460); Size = New-Object System.Drawing.Size(112, 32); FlatStyle = 'Flat'; Cursor = 'Hand'
        BackColor = $p.Accent; ForeColor = [System.Drawing.Color]::White; Font = $fontUiBold
    }
    $scBtnCreate.FlatAppearance.BorderSize = 0

    $scBtnClose = New-Object System.Windows.Forms.Button -Property @{
        Text = 'Close'; Location = New-Object System.Drawing.Point(476, 460); Size = New-Object System.Drawing.Size(70, 32); FlatStyle = 'Flat'; Cursor = 'Hand'
        BackColor = $p.BtnSecondary; ForeColor = $p.FgPrimary
    }
    $scBtnClose.FlatAppearance.BorderColor = $p.Border

    $scForm.Controls.AddRange(@(
        $scLblScript, $scTxtScript, $scBtnBrowse,
        $scLblName, $scTxtName,
        $scLblIcon, $scPnlIcon, $scTxtIcon, $scBtnIcon, $scBtnWinIcon, $scBtnResetIcon,
        $scGrpOpts, $scLblPreview, $scTxtPreview, $scLblStatus, $scBtnCreate, $scBtnClose
    ))

    $getDefaultIconForMode = {
        if ($scCmbMode.SelectedIndex -eq 1) {
            $info = Get-Pwsh7Info
            if ($null -ne $info -and -not [string]::IsNullOrWhiteSpace($info.IconPath)) {
                return "$($info.IconPath),0"
            }
        }
        return $ps5IconSpec
    }

    $resolveIcon = {
        param([string]$Spec)
        $fallback = & $getDefaultIconForMode
        $raw   = if ([string]::IsNullOrWhiteSpace($Spec)) { $fallback } else { $Spec.Trim() }
        $file  = $raw
        $index = 0
        if ($raw -match '^(.*),\s*(-?\d+)$') {
            $file  = $Matches[1].Trim().Trim('"')
            $index = [int]$Matches[2]
        }
        else {
            $file = $raw.Trim('"')
        }
        $expanded = [Environment]::ExpandEnvironmentVariables($file)
        [PSCustomObject]@{ File = $expanded; Index = $index; Spec = "$expanded,$index" }
    }

    $refreshIcon = {
        if (-not $script:HasWin32) { return }
        $parsed = & $resolveIcon $scTxtIcon.Text
        $bmp = [PSGalWin32]::GetIconBitmap($parsed.File, $parsed.Index)
        $old = $scPicIcon.Image
        $scPicIcon.Image = $bmp
        if ($null -ne $old) { $old.Dispose() }
    }

    $buildArgs = {
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add('-NoProfile')
        $parts.Add('-STA')
        if ($scChkBypass.Checked) { $parts.Add('-ExecutionPolicy Bypass') }
        if ($scCmbWin.SelectedItem -eq 'Hidden') { $parts.Add('-WindowStyle Hidden') }
        if ($scChkNoExit.Checked) { $parts.Add('-NoExit') }
        $target = $scTxtScript.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($target)) { $parts.Add("-File `"$target`"") }
        if (-not [string]::IsNullOrWhiteSpace($scTxtArgs.Text)) { $parts.Add($scTxtArgs.Text.Trim()) }
        return ($parts -join ' ')
    }

    $refreshModeStatus = {
        if ($scCmbMode.SelectedIndex -eq 0) {
            $scLblModeStatus.ForeColor = $p.FgSecondary
            $scLblModeStatus.Text      = 'Built-in (Windows)'
        }
        else {
            $info = Get-Pwsh7Info
            if ($null -ne $info) {
                $scLblModeStatus.ForeColor = $p.Success
                $scLblModeStatus.Text      = 'Installed (Ready)'
            }
            else {
                $scLblModeStatus.ForeColor = [System.Drawing.Color]::FromArgb(210, 153, 34)
                $scLblModeStatus.Text      = 'Not installed'
            }
        }
    }

    $refreshState = {
        $path = $scTxtScript.Text.Trim()
        $valid = (-not [string]::IsNullOrWhiteSpace($path)) -and (Test-Path -LiteralPath $path -PathType Leaf)
        $scBtnCreate.Enabled = $valid

        $previewExe = if ($scCmbMode.SelectedIndex -eq 1) {
            $info = Get-Pwsh7Info
            if ($null -ne $info) { $info.ExePath } else { 'pwsh.exe' }
        }
        else {
            $ps5ExePath
        }
        $scTxtPreview.Text = if ($valid) { "`"$previewExe`" $(& $buildArgs)" } else { '' }
    }

    $writeShortcutFile = {
        param(
            [string]$TargetExePath,
            [string]$ShortcutFilePath,
            [string]$ScriptFilePath,
            [string]$IconSpec,
            [string]$ModeLabel
        )

        $wsh = New-Object -ComObject WScript.Shell
        try {
            $lnk = $wsh.CreateShortcut($ShortcutFilePath)
            $lnk.TargetPath       = $TargetExePath
            $lnk.Arguments        = (& $buildArgs)
            $lnk.WorkingDirectory = Split-Path -Path $ScriptFilePath -Parent
            $lnk.IconLocation     = $IconSpec
            $lnk.WindowStyle      = switch ($scCmbWin.SelectedItem) {
                'Normal'    { 1 }
                'Minimized' { 7 }
                'Maximized' { 3 }
                'Hidden'    { 7 }
                default     { 1 }
            }
            $lnk.Description = "Run $(Split-Path -Path $ScriptFilePath -Leaf) via $ModeLabel"
            $lnk.Save()
        }
        finally {
            if ($null -ne $wsh) {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)
            }
        }

        if ($scChkRunAs.Checked) {
            $bytes = [System.IO.File]::ReadAllBytes($ShortcutFilePath)
            $bytes[21] = $bytes[21] -bor 0x20
            [System.IO.File]::WriteAllBytes($ShortcutFilePath, $bytes)
        }
    }

    $startPwsh7Install = {
        param(
            [bool]$CreateAfterInstall,
            [string]$ShortcutPath,
            [string]$ScriptPath,
            [string]$CleanName,
            [string]$IconSpec
        )

        $scBtnCreate.Enabled  = $false
        $scBtnClose.Enabled   = $false
        $scBtnBrowse.Enabled  = $false
        $scCmbMode.Enabled    = $false
        $scLblStatus.ForeColor = $p.Accent
        $scLblStatus.Text      = 'Installing PowerShell 7.x... Please wait.'

        $installWork = {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            # 1. Try winget first when available
            $wingetCmd = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
            if ($null -ne $wingetCmd) {
                $wgArgs = 'install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent'
                $proc = Start-Process -FilePath $wingetCmd.Source -ArgumentList $wgArgs -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -eq 0) {
                    return 'winget'
                }
            }

            # 2. Fallback: Download latest official PowerShell 7 MSI from GitHub and install
            $arch    = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64.msi' } else { 'win-x64.msi' }
            $headers = @{ 'User-Agent' = 'PSGallery-Manager' }
            $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers $headers -TimeoutSec 25 -ErrorAction Stop
            $asset   = $release.assets | Where-Object { $_.name -like "*$arch" } | Select-Object -First 1
            if ($null -eq $asset) {
                throw "No matching PowerShell 7 installer ($arch) was found on GitHub."
            }

            $msiPath = Join-Path -Path $env:TEMP -ChildPath $asset.name
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop

            $msiArgs = "/i `"$msiPath`" /passive ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 USE_MU=1 ENABLE_MU=1"
            $msiProc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue

            if ($msiProc.ExitCode -ne 0 -and $msiProc.ExitCode -ne 3010) {
                throw "PowerShell 7 installer exited with code $($msiProc.ExitCode)."
            }
            return 'msi'
        }

        $state = @{
            CreateAfterInstall = $CreateAfterInstall
            ShortcutPath       = $ShortcutPath
            ScriptPath         = $ScriptPath
            CleanName          = $CleanName
            IconSpec           = $IconSpec
        }

        Invoke-AsyncTask -Work $installWork -State $state -OnComplete {
            param($res, $err, $st)
            if ($scForm.IsDisposed) { return }

            $scBtnClose.Enabled  = $true
            $scBtnBrowse.Enabled = $true
            $scCmbMode.Enabled   = $true
            & $refreshState

            if ($err) {
                & $refreshModeStatus
                $scLblStatus.ForeColor = $p.Danger
                $scLblStatus.Text = "Install failed: $err"
                [System.Windows.Forms.MessageBox]::Show($scForm, "PowerShell 7 installation failed:`n$err", 'Installation Error', 'OK', 'Error') | Out-Null
                return
            }

            $installedInfo = Get-Pwsh7Info
            if ($null -eq $installedInfo) {
                & $refreshModeStatus
                $scLblStatus.ForeColor = $p.Danger
                $scLblStatus.Text = 'PowerShell 7 installed, but pwsh.exe was not found.'
                [System.Windows.Forms.MessageBox]::Show($scForm, 'PowerShell 7 finished installing, but pwsh.exe could not be located automatically. Click Create Shortcut again to retry.', 'Detection Needed', 'OK', 'Warning') | Out-Null
                return
            }

            # Upgrade default PS 5.1 icon to the new PS 7 icon if user hadn't chosen a custom icon
            $finalIconSpec = $st.IconSpec
            if ([string]::IsNullOrWhiteSpace($finalIconSpec) -or ($finalIconSpec -ieq $ps5IconSpec)) {
                $finalIconSpec = "$($installedInfo.IconPath),0"
                $scTxtIcon.Text = $finalIconSpec
            }

            & $refreshModeStatus
            & $refreshState

            if ($st.CreateAfterInstall) {
                try {
                    & $writeShortcutFile $installedInfo.ExePath $st.ShortcutPath $st.ScriptPath $finalIconSpec 'PowerShell 7.x'
                    $scLblStatus.ForeColor = $p.Success
                    $scLblStatus.Text = "Installed PowerShell 7.x and created '$($st.CleanName).lnk'."
                }
                catch {
                    $scLblStatus.ForeColor = $p.Danger
                    $scLblStatus.Text = "Installed PS 7, but shortcut failed: $($_.Exception.Message)"
                }
            }
            else {
                $scLblStatus.ForeColor = $p.Success
                $scLblStatus.Text = 'PowerShell 7.x installed. Ready to create shortcut.'
            }
        }
    }

    $scCmbMode.Add_SelectedIndexChanged({
        $isPs7 = ($scCmbMode.SelectedIndex -eq 1)
        if ($null -ne $script:Config) {
            $modeVal = if ($isPs7) { '7.x' } else { '5.1' }
            if ($script:Config.PSObject.Properties.Name -contains 'DefaultShortcutPsMode') {
                $script:Config.DefaultShortcutPsMode = $modeVal
            }
            else {
                $script:Config | Add-Member -NotePropertyName 'DefaultShortcutPsMode' -NotePropertyValue $modeVal -Force
            }
            if (Get-Command Save-AppConfig -ErrorAction SilentlyContinue) { Save-AppConfig }
        }

        $curIcon = $scTxtIcon.Text.Trim()
        if ($isPs7) {
            $info = Get-Pwsh7Info
            if ($null -ne $info) {
                if ([string]::IsNullOrWhiteSpace($curIcon) -or ($curIcon -ieq $ps5IconSpec)) {
                    $scTxtIcon.Text = "$($info.IconPath),0"
                }
            }
            else {
                & $refreshModeStatus
                & $refreshState
                $askNow = [System.Windows.Forms.MessageBox]::Show(
                    $scForm,
                    "PowerShell 7.x (pwsh.exe) is not currently installed on this PC.`n`nWould you like to download and install PowerShell 7 now?",
                    'PowerShell 7.x Not Installed',
                    'YesNo',
                    'Question'
                )
                if ($askNow -eq 'Yes') {
                    & $startPwsh7Install $false '' '' '' $scTxtIcon.Text
                }
                return
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($curIcon) -or ($curIcon -match '\\pwsh\.exe,0$')) {
                $scTxtIcon.Text = $ps5IconSpec
            }
        }

        & $refreshModeStatus
        & $refreshState
    })

    $scBtnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog -Property @{
            Title = 'Select a PowerShell Script (.ps1)'; Filter = 'PowerShell Scripts (*.ps1)|*.ps1|All Files (*.*)|*.*'; CheckFileExists = $true
        }
        if ($dlg.ShowDialog($scForm) -eq 'OK') {
            $scTxtScript.Text = $dlg.FileName
            $scTxtName.Text   = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
            & $refreshState
        }
        $dlg.Dispose()
    })

    $openIconPickerForFile = {
        param([string]$SeedPath, [int]$SeedIndex)
        if (-not $script:HasWin32) { return }
        $sb = New-Object System.Text.StringBuilder(260)
        [void]$sb.Append($SeedPath)
        $idx = [int]$SeedIndex
        if ([PSGalWin32]::PickIconDlg($scForm.Handle, $sb, $sb.Capacity, [ref]$idx) -ne 0) {
            $scTxtIcon.Text = "$([Environment]::ExpandEnvironmentVariables($sb.ToString())),$idx"
        }
    }

    # Opens the icon picker on the active PowerShell .exe (PS 7 or PS 5.1) or current custom icon file
    $scBtnIcon.Add_Click({
        $parsed   = & $resolveIcon $scTxtIcon.Text
        $fallback = if ($scCmbMode.SelectedIndex -eq 1 -and (Get-Pwsh7Info)) { (Get-Pwsh7Info).IconPath } else { $ps5ExePath }
        $seedFile = if (Test-Path -LiteralPath $parsed.File -PathType Leaf) { $parsed.File } else { $fallback }
        $seedIdx  = if (Test-Path -LiteralPath $parsed.File -PathType Leaf) { $parsed.Index } else { 0 }
        & $openIconPickerForFile $seedFile $seedIdx
    })

    # Opens the standard built-in Windows shell32.dll icon gallery directly
    $scBtnWinIcon.Add_Click({
        & $openIconPickerForFile $winShellDll 0
    })

    $scBtnResetIcon.Add_Click({ $scTxtIcon.Text = (& $getDefaultIconForMode) })
    $scTxtIcon.Add_TextChanged({ & $refreshIcon })
    $scTxtScript.Add_TextChanged({ & $refreshState })
    $scChkBypass.Add_CheckedChanged({ & $refreshState })
    $scChkNoExit.Add_CheckedChanged({ & $refreshState })
    $scTxtArgs.Add_TextChanged({ & $refreshState })

    $scCmbWin.Add_SelectedIndexChanged({
        if ($scCmbWin.SelectedItem -eq 'Hidden') {
            $scChkNoExit.Checked = $false
            $scChkNoExit.Enabled = $false
        }
        else {
            $scChkNoExit.Enabled = $true
        }
        & $refreshState
    })

    $scBtnCreate.Add_Click({
        try {
            $scriptPath = $scTxtScript.Text.Trim()
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                $scLblStatus.ForeColor = $p.Danger
                $scLblStatus.Text = 'Error: The selected script file does not exist.'
                return
            }
            $iconInfo = & $resolveIcon $scTxtIcon.Text
            if (-not (Test-Path -LiteralPath $iconInfo.File -PathType Leaf)) {
                $scLblStatus.ForeColor = $p.Danger
                $scLblStatus.Text = 'Error: The selected icon file does not exist.'
                return
            }

            $rawName = if ([string]::IsNullOrWhiteSpace($scTxtName.Text)) { [System.IO.Path]::GetFileNameWithoutExtension($scriptPath) } else { $scTxtName.Text.Trim() }
            $invalidRegex = [Regex]::Escape(([System.IO.Path]::GetInvalidFileNameChars() -join ''))
            $cleanName = ($rawName -replace "[$invalidRegex]", '').Trim()
            if ([string]::IsNullOrWhiteSpace($cleanName)) { $cleanName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath) }
            $scTxtName.Text = $cleanName

            $shortcutPath = Join-Path -Path $desktopPath -ChildPath "$cleanName.lnk"
            if (Test-Path -LiteralPath $shortcutPath) {
                $ow = [System.Windows.Forms.MessageBox]::Show($scForm, "Overwrite existing '$cleanName.lnk' on Desktop?", 'Confirm Overwrite', 'YesNo', 'Question')
                if ($ow -ne 'Yes') { return }
            }

            # PowerShell 5.1 Mode
            if ($scCmbMode.SelectedIndex -eq 0) {
                & $writeShortcutFile $ps5ExePath $shortcutPath $scriptPath $iconInfo.Spec 'PowerShell 5.1'
                $scLblStatus.ForeColor = $p.Success
                $scLblStatus.Text = "Created '$cleanName.lnk' (PowerShell 5.1) on your Desktop."
                return
            }

            # PowerShell 7.x Mode
            $pwsh7Info = Get-Pwsh7Info
            if ($null -ne $pwsh7Info) {
                & $writeShortcutFile $pwsh7Info.ExePath $shortcutPath $scriptPath $iconInfo.Spec 'PowerShell 7.x'
                $scLblStatus.ForeColor = $p.Success
                $scLblStatus.Text = "Created '$cleanName.lnk' (PowerShell 7.x) on your Desktop."
                return
            }

            # PowerShell 7.x is not installed -> Ask user before installing, then create shortcut
            $ask = [System.Windows.Forms.MessageBox]::Show(
                $scForm,
                "PowerShell 7.x (pwsh.exe) is not currently installed on this PC.`n`nWould you like to download and install PowerShell 7 now, and then create '$cleanName.lnk'?",
                'PowerShell 7.x Not Installed',
                'YesNo',
                'Question'
            )
            if ($ask -ne 'Yes') {
                $scLblStatus.ForeColor = $p.FgSecondary
                $scLblStatus.Text = 'Canceled: PowerShell 7.x is not installed.'
                return
            }

            & $startPwsh7Install $true $shortcutPath $scriptPath $cleanName $iconInfo.Spec
        }
        catch {
            $scLblStatus.ForeColor = $p.Danger
            $scLblStatus.Text = "Failed: $($_.Exception.Message)"
        }
    })

    $scBtnClose.Add_Click({ $scForm.Close() })

    if (-not [string]::IsNullOrWhiteSpace($DefaultScriptPath) -and (Test-Path -LiteralPath $DefaultScriptPath -PathType Leaf)) {
        $scTxtScript.Text = $DefaultScriptPath
        $scTxtName.Text   = [System.IO.Path]::GetFileNameWithoutExtension($DefaultScriptPath)
    }
    if ($scCmbMode.SelectedIndex -eq 1) {
        $initialInfo = Get-Pwsh7Info
        if ($null -ne $initialInfo) {
            $scTxtIcon.Text = "$($initialInfo.IconPath),0"
        }
    }

    $scChkNoExit.Checked = $false
    $scChkNoExit.Enabled = $false
    & $refreshModeStatus
    & $refreshIcon
    & $refreshState

    [void]$scForm.ShowDialog($form)
    if ($null -ne $scPicIcon.Image) { $scPicIcon.Image.Dispose() }
    $scForm.Dispose()
}

# ==============================================================================
# 10. PUBLISHER LOGIC (AST PARSER HEADER TOKENIZER & LOSSLESS WRITER)
# ==============================================================================
function Write-PubLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('HH:mm:ss')
    $txtPubLog.AppendText("[$ts] [$Level] $Message`r`n")
    $txtPubLog.SelectionStart = $txtPubLog.Text.Length
    $txtPubLog.ScrollToCaret()
}

function Enable-DotNetStrongCrypto {
    param([switch]$VerboseOutput)
    if (-not $script:IsAdmin) {
        if ($VerboseOutput) {
            Write-PubLog 'Not running as Administrator; cannot update system .NET TLS registry keys.' 'WARN'
        }
        return $false
    }

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    )
    $updated = $false
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        $props  = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        $strong = Get-SafeProp -Obj $props -Name 'SchUseStrongCrypto' -Default 0
        $sysTls = Get-SafeProp -Obj $props -Name 'SystemDefaultTlsVersions' -Default 0
        if ($strong -ne 1) { Set-ItemProperty -Path $path -Name 'SchUseStrongCrypto' -Value 1 -Type DWord -Force; $updated = $true }
        if ($sysTls -ne 1) { Set-ItemProperty -Path $path -Name 'SystemDefaultTlsVersions' -Value 1 -Type DWord -Force; $updated = $true }
    }
    if ($updated) { Write-PubLog 'Enabled .NET Framework Strong Cryptography (TLS 1.2+) in Registry.' 'SUCCESS' }
    elseif ($VerboseOutput) { Write-PubLog '.NET Framework Strong Cryptography (SchUseStrongCrypto) is already enabled.' 'INFO' }
    return $true
}

function Refresh-PubRecentDropdown {
    param([string]$SelectPath = '')
    $prev = $script:SuppressEvents
    $script:SuppressEvents = $true
    try {
        $cmbPubRecent.Items.Clear()
        $items = @($script:Config.PubRecentPackages)
        if ($items.Count -eq 0) {
            [void]$cmbPubRecent.Items.Add('(No recent packages yet)')
            $cmbPubRecent.SelectedIndex = 0
            $cmbPubRecent.Enabled = $false
            $btnPubClearRecent.Enabled = $false
            $cmbPubRecent.Invalidate()
            return
        }
        $cmbPubRecent.Enabled = $true
        $btnPubClearRecent.Enabled = $true
        $matchIdx = -1
        for ($i = 0; $i -lt $items.Count; $i++) {
            $e = $items[$i]
            [void]$cmbPubRecent.Items.Add("[$($e.Type)] $($e.Name)  -  $($e.Path)")
            if (-not [string]::IsNullOrWhiteSpace($SelectPath) -and ($e.Path -ieq $SelectPath)) { $matchIdx = $i }
        }
        $cmbPubRecent.SelectedIndex = $matchIdx
        $cmbPubRecent.Invalidate()
    }
    finally {
        $script:SuppressEvents = $prev
    }
}

function Save-PubStateToConfig {
    if ($script:IsInitializing) { return }
    $isScript = $rbPubScript.Checked
    $curPath  = $txtPubPath.Text.Trim()
    $script:Config.PubPackageType = if ($isScript) { 'Script' } else { 'Module' }
    if ($isScript) { $script:Config.PubLastScriptPath = $curPath } else { $script:Config.PubLastModulePath = $curPath }
    $script:Config.PubRepository     = if ([string]::IsNullOrWhiteSpace($txtPubRepo.Text)) { 'PSGallery' } else { $txtPubRepo.Text.Trim() }
    $script:Config.PubAutoInjectMeta = [bool]$chkPubAutoMeta.Checked
    Save-AppConfig
}

function Add-PubRecentPackage {
    param([string]$Path, [ValidateSet('Script', 'Module')][string]$Type)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $cleanPath = $Path.Trim()
    $newEntry  = [PSCustomObject]@{ Name = (Split-Path $cleanPath -Leaf); Type = $Type; Path = $cleanPath }
    $updated   = @($newEntry)
    foreach ($ex in @($script:Config.PubRecentPackages)) {
        if ($ex.Path -ine $cleanPath) { $updated += $ex }
        if ($updated.Count -ge $script:MaxRecentItems) { break }
    }
    $script:Config.PubRecentPackages = $updated
    Refresh-PubRecentDropdown -SelectPath $cleanPath
    Save-PubStateToConfig
}

function Get-LeadingHeaderTokens {
    param([string]$SourceText)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($SourceText, [ref]$tokens, [ref]$errors)

    $headerComments  = New-Object System.Collections.Generic.List[System.Management.Automation.Language.Token]
    $headerEndOffset = 0

    if ($null -ne $tokens) {
        foreach ($tok in $tokens) {
            if ($tok.Kind -eq [System.Management.Automation.Language.TokenKind]::EndOfInput) {
                break
            }
            if ($tok.Kind -eq [System.Management.Automation.Language.TokenKind]::NewLine) {
                $headerEndOffset = $tok.Extent.EndOffset
                continue
            }
            if ($tok.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) {
                [void]$headerComments.Add($tok)
                $headerEndOffset = $tok.Extent.EndOffset
                continue
            }
            break
        }
    }

    return [PSCustomObject]@{
        Comments        = @($headerComments)
        HeaderEndOffset = $headerEndOffset
    }
}

function Get-ParsedScriptMetadata {
    param([string]$FilePath)

    $rawContent = (Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop) -replace "`r`n", "`n" -replace "`n", "`r`n"
    $rawTags    = [ordered]@{}
    $meta = @{
        HasScriptInfo     = $false
        HasHelpBlock      = $false
        Version           = ''
        Guid              = ''
        Author            = ''
        CompanyName       = ''
        Copyright         = ''
        Tags              = @()
        LicenseUri        = ''
        ProjectUri        = ''
        ReleaseNotes      = ''
        Description       = ''
        RawScriptInfoTags = $rawTags
    }

    $header   = Get-LeadingHeaderTokens -SourceText $rawContent
    $openTag  = '<#' + 'PSScriptInfo'
    $closeTag = '#' + '>'

    foreach ($tok in $header.Comments) {
        $text = $tok.Text
        if ($text.StartsWith($openTag, [System.StringComparison]::OrdinalIgnoreCase) -and $text.EndsWith($closeTag)) {
            $meta.HasScriptInfo = $true
            $infoBody = $text.Substring($openTag.Length, $text.Length - $openTag.Length - $closeTag.Length)

            $tagMatches = [regex]::Matches($infoBody, '(?ms)^\s*\.([A-Z]+)\b([^\r\n]*)(.*?)(?=(?:^\s*\.[A-Z]+\b|\z))')
            foreach ($m in $tagMatches) {
                $key       = $m.Groups[1].Value.ToUpperInvariant()
                $inlineVal = $m.Groups[2].Value.Trim()
                $blockVal  = ($m.Groups[3].Value -replace '^(?:\s*\r?\n)+', '').TrimEnd()
                $combined  = if ($inlineVal -and $blockVal) {
                    "$inlineVal`r`n$blockVal"
                } elseif ($inlineVal) {
                    $inlineVal
                } else {
                    $blockVal
                }

                $trimmedVal    = $combined.Trim()
                $rawTags[$key] = $trimmedVal

                switch ($key) {
                    'VERSION'      { $meta.Version      = $trimmedVal }
                    'GUID'         { $meta.Guid         = $trimmedVal }
                    'AUTHOR'       { $meta.Author       = $trimmedVal }
                    'COMPANYNAME'  { $meta.CompanyName  = $trimmedVal }
                    'COPYRIGHT'    { $meta.Copyright    = $trimmedVal }
                    'TAGS'         {
                        if (-not [string]::IsNullOrWhiteSpace($trimmedVal)) {
                            $meta.Tags = @($trimmedVal -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                        }
                    }
                    'LICENSEURI'   { $meta.LicenseUri   = $trimmedVal }
                    'PROJECTURI'   { $meta.ProjectUri   = $trimmedVal }
                    'RELEASENOTES' { $meta.ReleaseNotes = $trimmedVal }
                    'DESCRIPTION'  {
                        if ([string]::IsNullOrWhiteSpace($meta.Description)) {
                            $meta.Description = $trimmedVal
                        }
                    }
                }
            }
            break
        }
    }

    foreach ($tok in $header.Comments) {
        $text = $tok.Text
        if ($text.StartsWith('<#') -and (-not $text.StartsWith($openTag, [System.StringComparison]::OrdinalIgnoreCase)) -and $text.EndsWith($closeTag)) {
            $meta.HasHelpBlock = $true
            $helpBody = $text.Substring(2, $text.Length - 4)
            if ($helpBody -match '(?ms)^\s*\.DESCRIPTION\b[^\r\n]*\r?\n(.*?)(?=(?:^\s*\.[A-Z]+\b|\z))') {
                $descRaw = ($Matches[1] -replace '^(?:\s*\r?\n)+', '').TrimEnd()
                if (-not [string]::IsNullOrWhiteSpace($descRaw)) {
                    $lines = $descRaw -split '\r?\n'
                    $nonEmptyLines = @($lines | Where-Object { $_.Trim() -ne '' })
                    $minIndent = 0
                    if ($nonEmptyLines.Count -gt 0) {
                        $minIndent = ($nonEmptyLines | ForEach-Object {
                            if ($_ -match '^(\s+)') { $Matches[1].Length } else { 0 }
                        } | Measure-Object -Minimum).Minimum
                    }
                    if ($minIndent -gt 0) {
                        $lines = $lines | ForEach-Object {
                            if ($_.Length -ge $minIndent) { $_.Substring($minIndent) } else { $_.TrimStart() }
                        }
                    }
                    $meta.Description = ($lines -join "`r`n").Trim()
                    break
                }
            }
        }
    }

    return $meta
}

function Clear-PubMetadataFields {
    param([bool]$ApplyShareableDefaults = $false)

    $txtPubVersion.Text   = '1.0.0'
    $txtPubAuthor.Text    = if (-not [string]::IsNullOrWhiteSpace($script:Config.Username)) {
        $script:Config.Username
    } else {
        ''
    }
    $txtPubCompany.Text   = if ($ApplyShareableDefaults) { $script:Config.PubDefaultCompany } else { '' }
    $txtPubCopyright.Text = if ($ApplyShareableDefaults) { $script:Config.PubDefaultCopyright } else { '' }
    $txtPubDesc.Text      = ''
    $txtPubTags.Text      = if ($ApplyShareableDefaults) { $script:Config.PubDefaultTags } else { '' }
    $txtPubProjUri.Text   = if ($ApplyShareableDefaults) { $script:Config.PubDefaultProjUri } else { '' }
    $txtPubLicUri.Text    = if ($ApplyShareableDefaults) { $script:Config.PubDefaultLicUri } else { '' }
    $txtPubNotes.Text     = ''
}

function Import-PubTargetMetadata {
    param(
        [string]$TargetPath,
        [bool]$IsScript,
        [switch]$QuietMissing
    )

    $lblPubLiveVer.Text = 'Live Gallery Version: Not checked'
    Clear-PubMetadataFields -ApplyShareableDefaults $false

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        Clear-PubMetadataFields -ApplyShareableDefaults $true
        return
    }

    if ($IsScript) {
        if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
            if (-not $QuietMissing) {
                Write-PubLog "Path no longer exists on disk: $TargetPath" 'WARN'
            }
            return
        }

        try {
            $parsedMeta = Get-ParsedScriptMetadata -FilePath $TargetPath
            $foundAny   = $parsedMeta.HasScriptInfo -or $parsedMeta.HasHelpBlock -or (-not [string]::IsNullOrWhiteSpace($parsedMeta.Description))

            $cmdletInfo = $null
            try {
                $cmdletInfo = if (Get-Command Test-PSScriptFileInfo -ErrorAction SilentlyContinue) {
                    Test-PSScriptFileInfo -Path $TargetPath -ErrorAction Stop
                } elseif (Get-Command Test-ScriptFileInfo -ErrorAction SilentlyContinue) {
                    Test-ScriptFileInfo -Path $TargetPath -ErrorAction Stop
                } else {
                    $null
                }
            } catch {
                $cmdletInfo = $null
            }

            if ($foundAny -or ($null -ne $cmdletInfo)) {
                $cmdVer   = [string](Get-SafeProp -Obj $cmdletInfo -Name 'Version' -Default '')
                $cmdAuth  = [string](Get-SafeProp -Obj $cmdletInfo -Name 'Author' -Default '')
                $cmdComp  = [string](Get-SafeProp -Obj $cmdletInfo -Name 'CompanyName' -Default '')
                $cmdCopy  = [string](Get-SafeProp -Obj $cmdletInfo -Name 'Copyright' -Default '')
                $cmdDesc  = [string](Get-SafeProp -Obj $cmdletInfo -Name 'Description' -Default '')
                $cmdTags  = @(Get-SafeProp -Obj $cmdletInfo -Name 'Tags' -Default @())
                $cmdProj  = [string](Get-SafeProp -Obj $cmdletInfo -Name 'ProjectUri' -Default '')
                $cmdLic   = [string](Get-SafeProp -Obj $cmdletInfo -Name 'LicenseUri' -Default '')
                $cmdNotes = @(Get-SafeProp -Obj $cmdletInfo -Name 'ReleaseNotes' -Default @())

                $verVal  = if ($parsedMeta.Version) { $parsedMeta.Version } elseif ($cmdVer) { $cmdVer } else { '1.0.0' }
                $authVal = if ($parsedMeta.Author) { $parsedMeta.Author } elseif ($cmdAuth) { $cmdAuth } else { $script:Config.Username }
                $compVal = if (-not [string]::IsNullOrWhiteSpace($parsedMeta.CompanyName)) {
                    $parsedMeta.CompanyName
                } elseif (-not [string]::IsNullOrWhiteSpace($cmdComp)) {
                    $cmdComp
                } else {
                    $script:Config.PubDefaultCompany
                }
                $copyVal = if (-not [string]::IsNullOrWhiteSpace($parsedMeta.Copyright)) {
                    $parsedMeta.Copyright
                } elseif (-not [string]::IsNullOrWhiteSpace($cmdCopy)) {
                    $cmdCopy
                } else {
                    $script:Config.PubDefaultCopyright
                }
                $descVal = if ($parsedMeta.Description) { $parsedMeta.Description } elseif ($cmdDesc) { ($cmdDesc -replace '\r?\n', "`r`n").Trim() } else { '' }
                $tagsArr = if (@($parsedMeta.Tags).Count -gt 0) { @($parsedMeta.Tags) } elseif ($cmdTags.Count -gt 0) { $cmdTags } else { @() }
                $projVal = if ($parsedMeta.ProjectUri) { $parsedMeta.ProjectUri } elseif ($cmdProj) { $cmdProj } else { '' }
                $licVal  = if ($parsedMeta.LicenseUri) { $parsedMeta.LicenseUri } elseif ($cmdLic) { $cmdLic } else { '' }
                $noteVal = if ($parsedMeta.ReleaseNotes) { $parsedMeta.ReleaseNotes } elseif ($cmdNotes.Count -gt 0) { ($cmdNotes -join "`r`n").Trim() } else { '' }

                $txtPubVersion.Text   = $verVal
                $txtPubAuthor.Text    = $authVal
                $txtPubCompany.Text   = $compVal
                $txtPubCopyright.Text = $copyVal
                $txtPubDesc.Text      = $descVal
                $txtPubTags.Text      = ($tagsArr -join ', ')
                $txtPubProjUri.Text   = $projVal
                $txtPubLicUri.Text    = $licVal
                $txtPubNotes.Text     = $noteVal

                Write-PubLog "Loaded metadata from '$(Split-Path $TargetPath -Leaf)'."
            } else {
                Clear-PubMetadataFields -ApplyShareableDefaults $true
                Write-PubLog "No PSScriptInfo detected yet in '$(Split-Path $TargetPath -Leaf)'. Fill in required (*) fields to generate it." 'WARN'
            }
        } catch {
            Clear-PubMetadataFields -ApplyShareableDefaults $true
            Write-PubLog "Could not read metadata from '$(Split-Path $TargetPath -Leaf)': $($_.Exception.Message)" 'WARN'
        }
    } else {
        if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
            if (-not $QuietMissing) {
                Write-PubLog "Folder no longer exists on disk: $TargetPath" 'WARN'
            }
            return
        }

        $moduleName   = Split-Path $TargetPath -Leaf
        $manifestPath = Join-Path $TargetPath "$moduleName.psd1"

        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try {
                $modData = $null
                try {
                    $modData = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
                } catch {
                    $modData = $null
                }

                $modInfo = $null
                try {
                    $modInfo = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
                } catch {
                    $modInfo = $null
                }

                if (($null -ne $modData) -or ($null -ne $modInfo)) {
                    $dVer  = [string](Get-SafeProp -Obj $modData -Name 'ModuleVersion' -Default '')
                    $iVer  = [string](Get-SafeProp -Obj $modInfo -Name 'Version' -Default '')
                    $dAuth = [string](Get-SafeProp -Obj $modData -Name 'Author' -Default '')
                    $iAuth = [string](Get-SafeProp -Obj $modInfo -Name 'Author' -Default '')
                    $dComp = [string](Get-SafeProp -Obj $modData -Name 'CompanyName' -Default '')
                    $iComp = [string](Get-SafeProp -Obj $modInfo -Name 'CompanyName' -Default '')
                    $dCopy = [string](Get-SafeProp -Obj $modData -Name 'Copyright' -Default '')
                    $iCopy = [string](Get-SafeProp -Obj $modInfo -Name 'Copyright' -Default '')
                    $dDesc = [string](Get-SafeProp -Obj $modData -Name 'Description' -Default '')
                    $iDesc = [string](Get-SafeProp -Obj $modInfo -Name 'Description' -Default '')

                    $verVal  = if ($dVer) { $dVer } elseif ($iVer) { $iVer } else { '1.0.0' }
                    $authVal = if ($dAuth) { $dAuth } elseif ($iAuth) { $iAuth } else { $script:Config.Username }
                    $compVal = if (-not [string]::IsNullOrWhiteSpace($dComp)) {
                        $dComp
                    } elseif (-not [string]::IsNullOrWhiteSpace($iComp) -and $iComp -ne 'Unknown') {
                        $iComp
                    } else {
                        $script:Config.PubDefaultCompany
                    }
                    $copyVal = if (-not [string]::IsNullOrWhiteSpace($dCopy)) {
                        $dCopy
                    } elseif (-not [string]::IsNullOrWhiteSpace($iCopy)) {
                        $iCopy
                    } else {
                        $script:Config.PubDefaultCopyright
                    }
                    $descVal = if ($dDesc) { ($dDesc -replace '\r?\n', "`r`n").Trim() } elseif ($iDesc) { ($iDesc -replace '\r?\n', "`r`n").Trim() } else { '' }

                    $dPriv  = Get-SafeProp -Obj $modData -Name 'PrivateData' -Default $null
                    $iPriv  = Get-SafeProp -Obj $modInfo -Name 'PrivateData' -Default $null
                    $psData = Get-SafeProp -Obj $dPriv -Name 'PSData' -Default (Get-SafeProp -Obj $iPriv -Name 'PSData' -Default $null)

                    $psTags  = @(Get-SafeProp -Obj $psData -Name 'Tags' -Default @())
                    $psProj  = [string](Get-SafeProp -Obj $psData -Name 'ProjectUri' -Default '')
                    $psLic   = [string](Get-SafeProp -Obj $psData -Name 'LicenseUri' -Default '')
                    $psNotes = @(Get-SafeProp -Obj $psData -Name 'ReleaseNotes' -Default @())

                    $txtPubVersion.Text   = $verVal
                    $txtPubAuthor.Text    = $authVal
                    $txtPubCompany.Text   = $compVal
                    $txtPubCopyright.Text = $copyVal
                    $txtPubDesc.Text      = $descVal
                    $txtPubTags.Text      = if ($psTags.Count -gt 0) { ($psTags -join ', ') } else { '' }
                    $txtPubProjUri.Text   = $psProj
                    $txtPubLicUri.Text    = $psLic
                    $txtPubNotes.Text     = if ($psNotes.Count -gt 0) { ($psNotes -join "`r`n").Trim() } else { '' }

                    Write-PubLog "Loaded metadata from '$moduleName.psd1'."
                } else {
                    Clear-PubMetadataFields -ApplyShareableDefaults $true
                    Write-PubLog "Found '$moduleName.psd1' but could not parse its fields." 'WARN'
                }
            } catch {
                Clear-PubMetadataFields -ApplyShareableDefaults $true
                Write-PubLog "Error reading '$moduleName.psd1': $($_.Exception.Message)" 'WARN'
            }
        } else {
            Clear-PubMetadataFields -ApplyShareableDefaults $true
            Write-PubLog "No '$moduleName.psd1' found in folder. Fill in required (*) fields to generate one automatically." 'WARN'
        }
    }
}

function Get-PubParsedTags {
    if ([string]::IsNullOrWhiteSpace($txtPubTags.Text)) { return @() }
    return @($txtPubTags.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Build-TopScriptInfoBlock {
    param(
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$OrderedTags
    )

    $openTag  = '<#' + 'PSScriptInfo'
    $closeTag = '#' + '>'

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add($openTag)

    foreach ($key in $OrderedTags.Keys) {
        $val = [string]$OrderedTags[$key]
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        [void]$lines.Add('')
        if ($val -match "`r?`n") {
            [void]$lines.Add(".$key`r`n$($val.Trim())")
        }
        else {
            [void]$lines.Add(".$key $($val.Trim())")
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add($closeTag)
    return ($lines -join "`r`n")
}

function Update-CommentHelpBlockText {
    param(
        [string]$ExistingBlockText,
        [string]$IndentedDescription
    )

    $closeTag = '#' + '>'
    if ([string]::IsNullOrWhiteSpace($ExistingBlockText)) {
        return "<#`r`n.DESCRIPTION`r`n$IndentedDescription`r`n$closeTag"
    }

    $body = $ExistingBlockText.Substring(2, $ExistingBlockText.Length - 4)
    if ($body -match '(?ms)^\s*\.DESCRIPTION\b') {
        $updatedBody = [regex]::Replace(
            $body,
            '(?ms)(^\s*\.DESCRIPTION\b[^\r\n]*\r?\n)(.*?)(?=(?:^\s*\.[A-Z]+\b|\z))',
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($dm)
                $dm.Groups[1].Value + $IndentedDescription + "`r`n`r`n"
            },
            1
        )
        return "<#$($updatedBody.TrimEnd())`r`n$closeTag"
    }

    return "<#$($body.TrimEnd())`r`n`r`n.DESCRIPTION`r`n$IndentedDescription`r`n$closeTag"
}

function Sync-PubScriptMetadata {
    param([string]$FilePath)

    if ([string]::IsNullOrWhiteSpace($txtPubDesc.Text)) {
        throw 'Description cannot be empty.'
    }

    $rawContent = (Get-Content -Path $FilePath -Raw -Encoding UTF8) -replace "`r`n", "`n" -replace "`n", "`r`n"
    $existing   = Get-ParsedScriptMetadata -FilePath $FilePath
    $header     = Get-LeadingHeaderTokens -SourceText $rawContent

    $verText     = if ([string]::IsNullOrWhiteSpace($txtPubVersion.Text)) { '1.0.0' } else { $txtPubVersion.Text.Trim() }
    $authorText  = $txtPubAuthor.Text.Trim()
    $companyText = $txtPubCompany.Text.Trim()
    $copyText    = $txtPubCopyright.Text.Trim()
    $descText    = ($txtPubDesc.Text.Trim() -replace '\r?\n', "`r`n")
    $tagArray    = Get-PubParsedTags
    $tagsText    = ($tagArray -join ' ')
    $projUriText = $txtPubProjUri.Text.Trim()
    $licUriText  = $txtPubLicUri.Text.Trim()
    $notesText   = ($txtPubNotes.Text.Trim() -replace '\r?\n', "`r`n")
    $guidText    = if (-not [string]::IsNullOrWhiteSpace($existing.Guid)) { $existing.Guid } else { [Guid]::NewGuid().ToString() }

    $mergedTags = [ordered]@{}
    $mergedTags['VERSION'] = $verText
    $mergedTags['GUID']    = $guidText
    $mergedTags['AUTHOR']  = $authorText

    foreach ($oldKey in $existing.RawScriptInfoTags.Keys) {
        if ($oldKey -notin @('VERSION', 'GUID', 'AUTHOR', 'COMPANYNAME', 'COPYRIGHT', 'TAGS', 'LICENSEURI', 'PROJECTURI', 'RELEASENOTES', 'DESCRIPTION')) {
            $mergedTags[$oldKey] = $existing.RawScriptInfoTags[$oldKey]
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($companyText)) { $mergedTags['COMPANYNAME']  = $companyText }
    if (-not [string]::IsNullOrWhiteSpace($copyText))    { $mergedTags['COPYRIGHT']    = $copyText }
    if (-not [string]::IsNullOrWhiteSpace($tagsText))    { $mergedTags['TAGS']         = $tagsText }
    if (-not [string]::IsNullOrWhiteSpace($licUriText))  { $mergedTags['LICENSEURI']   = $licUriText }
    if (-not [string]::IsNullOrWhiteSpace($projUriText)) { $mergedTags['PROJECTURI']   = $projUriText }
    if (-not [string]::IsNullOrWhiteSpace($notesText))   { $mergedTags['RELEASENOTES'] = $notesText }

    $topBlock = Build-TopScriptInfoBlock -OrderedTags $mergedTags

    $indentedDesc = ((($descText -split '\r?\n') | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { '' } else { "    $_" }
    }) -join "`r`n").TrimEnd()

    $openTag           = '<#' + 'PSScriptInfo'
    $closeTag          = '#' + '>'
    $existingHelpBlock = ''

    foreach ($tok in $header.Comments) {
        $t = $tok.Text
        if ($t.StartsWith('<#') -and (-not $t.StartsWith($openTag, [System.StringComparison]::OrdinalIgnoreCase)) -and $t.EndsWith($closeTag)) {
            if ($t -match '(?m)^\s*\.(SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK)\b') {
                $existingHelpBlock = $t
                break
            }
        }
    }
    if ([string]::IsNullOrEmpty($existingHelpBlock)) {
        foreach ($tok in $header.Comments) {
            $t = $tok.Text
            if ($t.StartsWith('<#') -and (-not $t.StartsWith($openTag, [System.StringComparison]::OrdinalIgnoreCase)) -and $t.EndsWith($closeTag)) {
                $existingHelpBlock = $t
                break
            }
        }
    }

    $otherHeaderComments = New-Object System.Collections.Generic.List[string]
    foreach ($tok in $header.Comments) {
        $t = $tok.Text
        if ($t.StartsWith($openTag, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($t -eq $existingHelpBlock) {
            continue
        }
        [void]$otherHeaderComments.Add($t.TrimEnd())
    }

    $helpBlock = Update-CommentHelpBlockText -ExistingBlockText $existingHelpBlock -IndentedDescription $indentedDesc
    $bodyCode  = $rawContent.Substring($header.HeaderEndOffset).TrimStart("`r", "`n")

    $headerParts = New-Object System.Collections.Generic.List[string]
    [void]$headerParts.Add($topBlock)
    if ($otherHeaderComments.Count -gt 0) {
        [void]$headerParts.Add(($otherHeaderComments -join "`r`n`r`n"))
    }
    [void]$headerParts.Add($helpBlock)

    $final = ($headerParts -join "`r`n`r`n") + "`r`n`r`n" + $bodyCode
    Set-Content -LiteralPath $FilePath -Value ($final.TrimEnd() + "`r`n") -Encoding UTF8
}

function Sync-PubModuleMetadata {
    param([string]$FolderPath)

    if ([string]::IsNullOrWhiteSpace($txtPubDesc.Text)) {
        throw 'Description cannot be empty.'
    }

    $moduleName   = Split-Path $FolderPath -Leaf
    $manifestPath = Join-Path $FolderPath "$moduleName.psd1"
    $psm1Path     = Join-Path $FolderPath "$moduleName.psm1"

    $manifestParams = @{
        Path          = $manifestPath
        ModuleVersion = $txtPubVersion.Text.Trim()
        Author        = $txtPubAuthor.Text.Trim()
        Description   = $txtPubDesc.Text.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($txtPubCompany.Text))   { $manifestParams['CompanyName']  = $txtPubCompany.Text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($txtPubCopyright.Text)) { $manifestParams['Copyright']    = $txtPubCopyright.Text.Trim() }

    $tagArray = Get-PubParsedTags
    if ($tagArray.Count -gt 0) { $manifestParams['Tags'] = [string[]]$tagArray }
    if (-not [string]::IsNullOrWhiteSpace($txtPubProjUri.Text)) { $manifestParams['ProjectUri']   = $txtPubProjUri.Text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($txtPubLicUri.Text))  { $manifestParams['LicenseUri']   = $txtPubLicUri.Text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($txtPubNotes.Text))   { $manifestParams['ReleaseNotes'] = $txtPubNotes.Text.Trim() }

    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Write-PubLog "Updating existing module manifest '$moduleName.psd1'..."
        try {
            $existingData = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
            foreach ($expKey in @('FunctionsToExport', 'CmdletsToExport', 'AliasesToExport', 'VariablesToExport')) {
                if ($existingData.ContainsKey($expKey) -and $null -ne $existingData[$expKey]) {
                    $manifestParams[$expKey] = @($existingData[$expKey])
                }
            }
        }
        catch { }

        Update-ModuleManifest @manifestParams -ErrorAction Stop
    } else {
        Write-PubLog "No '$moduleName.psd1' found. Creating new module manifest..."
        if (Test-Path -LiteralPath $psm1Path -PathType Leaf) {
            $manifestParams['RootModule'] = "$moduleName.psm1"
        } else {
            Write-PubLog "Warning: '$moduleName.psm1' not found in folder. Ensure RootModule is configured if needed." 'WARN'
        }
        New-ModuleManifest @manifestParams -ErrorAction Stop
    }
}

function Set-PubUiBusyState {
    param([bool]$IsBusy, [bool]$AllowCancel = $false)
    foreach ($ctrl in @($btnPubPublish, $btnPubValidate, $btnPubRepairTls, $btnPubCheckLive, $btnPubBrowse, $btnPubSaveAuthor, $btnPubSaveMeta, $btnPubBumpMajor, $btnPubBumpMinor, $btnPubBumpPatch, $rbPubScript, $rbPubModule)) {
        $ctrl.Enabled = -not $IsBusy
    }
    $cmbPubRecent.Enabled      = (-not $IsBusy) -and (@($script:Config.PubRecentPackages).Count -gt 0)
    $btnPubClearRecent.Enabled = (-not $IsBusy) -and (@($script:Config.PubRecentPackages).Count -gt 0)
    $btnPubCancel.Enabled      = $IsBusy -and $AllowCancel
}

# ==============================================================================
# 11. THEME APPLICATION & UI REFRESH HELPERS
# ==============================================================================
$script:CurrentPage             = 0
$script:CurrentGalleryResults   = @()
$script:CurrentPublishedResults = @()
$script:CurrentLocalResults     = @()
$script:ActiveMainTab           = 'Discover'
$script:ActiveMySubTab          = 'Published'
$script:PublishJob              = $null

function Update-HeaderStatusBadges {
    $userDisplay = if ([string]::IsNullOrWhiteSpace($script:Config.Username)) { 'User: (Not Set)' } else { "User: $($script:Config.Username)" }
    $hasKey      = (Test-Path -LiteralPath $script:ApiKeyPath)
    $keyDisplay  = if ($hasKey) { 'DPAPI Key: Saved' } else { 'DPAPI Key: None' }
    $lblUserBadge.Text = "$userDisplay  |  $keyDisplay"

    if ($hasKey) {
        $lblApiStatus.Text = 'Status: Encrypted API key is saved on disk via Windows DPAPI.'
        $lblPubVaultBadge.Text = 'DPAPI Vault: Encrypted key active'
    }
    else {
        $lblApiStatus.Text = 'Status: No API key stored on disk.'
        $lblPubVaultBadge.Text = 'DPAPI Vault: No saved key (set in Settings)'
    }
}

foreach ($cb in @($cmbTheme, $cmbCategory, $cmbItemType, $cmbSort, $cmbSetScope, $cmbPubRecent)) {
    Initialize-ThemedComboBox -ComboBox $cb
}
foreach ($grp in @($grpPubTarget, $grpPubMeta)) {
    Initialize-ThemedGroupBox -GroupBox $grp
}

function Apply-Theme {
    $p = Get-ThemePalette

    if ($script:HasWin32 -and $form.IsHandleCreated) {
        try { [PSGalWin32]::SetDarkTitleBar($form.Handle, $p.IsDark) } catch { }
    }

    $form.BackColor = $p.BgMain
    $form.ForeColor = $p.FgPrimary

    $pnlHeader.BackColor = $p.BgHeader
    $lblAppTitle.ForeColor = $p.FgPrimary
    $lblThemeTitle.ForeColor = $p.FgSecondary

    $lblModeBadge.BackColor = if ($script:IsAdmin) { $p.Success } else { $p.Warning }
    $lblModeBadge.ForeColor = [Drawing.Color]::White

    $pnlStatus.BackColor = $p.BgHeader
    $lblStatus.ForeColor = $p.FgSecondary
    $lblUserBadge.ForeColor = $p.FgSecondary

    foreach ($pnl in @($pnlMain, $splitDiscover, $pnlPubSpacer)) { $pnl.BackColor = $p.BgMain }
    foreach ($pnl in @($pnlFilter, $pnlDetails, $pnlMySubNav, $pnlPubBar, $pnlLocalBar, $pnlSettingsCard, $pnlPubLeft, $pnlPubRight, $pnlPubLogTop, $splitDiscover.Panel1, $splitDiscover.Panel2)) {
        $pnl.BackColor = $p.BgPanel
    }
    $pnlPubStatusCard.BackColor = $p.BgInput

    foreach ($grp in @($grpPubTarget, $grpPubMeta)) {
        $grp.BackColor = $p.BgPanel
        $grp.ForeColor = $p.FgPrimary
        $grp.Invalidate()
    }

    foreach ($lbl in @($lblCat, $lblType, $lblSort, $lblPage, $lblDetTitle, $lblPubAccount, $lblSetHeader, $lblSetUser, $lblSetApi, $lblSetSavePath, $lblSetScope, $lblSetDefaultCompany, $lblSetDefaultCopyright, $chkAutoElevate, $lblPubMode, $rbPubScript, $rbPubModule, $lblPubRecent, $lblPubPath, $lblPubRepo, $lblPubVer, $lblPubAuthor, $lblPubCompany, $lblPubCopyright, $lblPubDesc, $lblPubTags, $lblPubProjUri, $lblPubLicUri, $lblPubNotes, $chkPubAutoMeta, $lblPubLogTitle)) {
        $lbl.ForeColor = $p.FgPrimary
    }
    foreach ($lbl in @($lblDetMeta, $lblApiStatus, $lblPathsInfo, $lblPubUploadState, $lblPubVaultBadge, $lblPubLiveVer)) {
        $lbl.ForeColor = $p.FgSecondary
    }

    foreach ($tb in @($txtSearch, $txtDetBody, $txtPubUser, $txtSetUser, $txtSetApiKey, $txtSetSavePath, $txtSetDefaultCompany, $txtSetDefaultCopyright, $txtPubPath, $txtPubRepo, $txtPubVersion, $txtPubAuthor, $txtPubCompany, $txtPubCopyright, $txtPubDesc, $txtPubTags, $txtPubProjUri, $txtPubLicUri, $txtPubNotes)) {
        $tb.BackColor = $p.BgInput
        $tb.ForeColor = $p.FgPrimary
    }
    $txtPubLog.BackColor = $p.BgLog
    $txtPubLog.ForeColor = $p.FgPrimary

    foreach ($cb in @($cmbTheme, $cmbCategory, $cmbItemType, $cmbSort, $cmbSetScope, $cmbPubRecent)) {
        $cb.BackColor = $p.BgInput
        $cb.ForeColor = $p.FgPrimary
        if ($script:HasWin32 -and $cb.IsHandleCreated) {
            try {
                $subApp = if ($p.IsDark) { 'DarkMode_CFD' } else { 'Explorer' }
                [void][PSGalWin32]::SetWindowTheme($cb.Handle, $subApp, $null)
            }
            catch { }
        }
        $cb.Invalidate()
    }

    foreach ($btn in @($btnSearch, $btnInstallPkg, $btnRefreshPub, $btnScanLocal, $btnSaveSettings, $btnPubPublish)) {
        $btn.FlatStyle = 'Flat'
        $btn.BackColor = $p.Accent
        $btn.ForeColor = [Drawing.Color]::White
        $btn.FlatAppearance.BorderSize = 0
        $btn.FlatAppearance.MouseOverBackColor = $p.AccentHover
    }

    foreach ($btn in @($btnPrevPage, $btnNextPage, $btnDownloadPkg, $btnViewCode, $btnPubDownload, $btnPubInspect, $btnPubOpenWeb, $btnCheckUpdates, $btnUpdateLocal, $btnOpenLocalFolder, $btnEditLocal, $btnLocalShortcut, $btnToggleApi, $btnOpenApiKeysPage, $btnBrowseSave, $btnElevateNow, $btnShortcutDlgTop, $btnOpenShortcutTool, $btnPubClearRecent, $btnPubBrowse, $btnPubBumpMajor, $btnPubBumpMinor, $btnPubBumpPatch, $btnPubSaveAuthor, $btnPubSaveMeta, $btnPubCheckLive, $btnPubValidate, $btnPubRepairTls, $btnPubCancel, $btnPubClearLog)) {
        $btn.FlatStyle = 'Flat'
        $btn.BackColor = $p.BtnSecondary
        $btn.ForeColor = $p.FgPrimary
        $btn.FlatAppearance.BorderColor = $p.Border
        $btn.FlatAppearance.BorderSize = 1
        $btn.FlatAppearance.MouseOverBackColor = $p.BtnSecHover
    }

    foreach ($btn in @($btnPubUnlist, $btnUninstallLocal, $btnClearApi)) {
        $btn.FlatStyle = 'Flat'
        $btn.BackColor = $p.BtnSecondary
        $btn.ForeColor = $p.Danger
        $btn.FlatAppearance.BorderColor = $p.Danger
        $btn.FlatAppearance.BorderSize = 1
        $btn.FlatAppearance.MouseOverBackColor = $p.BtnSecHover
    }

    foreach ($btn in @($btnPrevPage, $btnNextPage, $btnViewCode, $btnTranslate, $btnPubDownload, $btnPubInspect, $btnPubOpenWeb, $btnUpdateLocal, $btnOpenLocalFolder, $btnEditLocal, $btnLocalShortcut, $btnToggleApi, $btnOpenApiKeysPage, $btnBrowseSave, $btnOpenShortcutTool, $btnShortcutDlgTop, $btnPubClearRecent, $btnPubBrowse, $btnPubSaveAuthor, $btnPubSaveMeta, $btnPubCheckLive, $btnPubValidate, $btnPubRepairTls, $btnPubCancel, $btnPubClearLog)) {
    $btn.BackColor = $p.BtnSecondary
    $btn.ForeColor = $p.FgPrimary
    $btn.FlatAppearance.BorderColor = $p.Border
}

    foreach ($cmb in @($cmbTheme, $cmbCategory, $cmbItemType, $cmbSort, $cmbSetScope, $cmbPubRecent, $cmbTargetLang)) {
        $cmb.BackColor = $p.BgInput
        $cmb.ForeColor = $p.FgPrimary
        Initialize-ThemedComboBox -ComboBox $cmb
    }

    $ctxLocalMenu.BackColor = $p.BgPanel
    $ctxLocalMenu.ForeColor = $p.FgPrimary
    foreach ($mi in $ctxLocalMenu.Items) {
        $mi.BackColor = $p.BgPanel
        $mi.ForeColor = if ($mi -eq $mnuLocalUninstall) { $p.Danger } else { $p.FgPrimary }
    }

    $navMap = @{ 'Discover' = $btnNavDiscover; 'MyScripts' = $btnNavMyScripts; 'Publish' = $btnNavPublish; 'Settings' = $btnNavSettings }
    foreach ($key in $navMap.Keys) {
        $b = $navMap[$key]
        $b.FlatStyle = 'Flat'
        if ($script:ActiveMainTab -eq $key) {
            $b.BackColor = $p.Accent; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0
        }
        else {
            $b.BackColor = $p.BtnSecondary; $b.ForeColor = $p.FgPrimary; $b.FlatAppearance.BorderColor = $p.Border; $b.FlatAppearance.BorderSize = 1
        }
    }

    $subMap = @{ 'Published' = $btnSubPublished; 'Local' = $btnSubLocal }
    foreach ($key in $subMap.Keys) {
        $b = $subMap[$key]
        $b.FlatStyle = 'Flat'
        if ($script:ActiveMySubTab -eq $key) {
            $b.BackColor = $p.Accent; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0
        }
        else {
            $b.BackColor = $p.BtnSecondary; $b.ForeColor = $p.FgPrimary; $b.FlatAppearance.BorderColor = $p.Border; $b.FlatAppearance.BorderSize = 1
        }
    }

    foreach ($dgv in @($dgvGallery, $dgvPublished, $dgvLocal)) {
        $dgv.BackgroundColor = $p.BgGrid
        $dgv.GridColor = $p.Border
        $dgv.DefaultCellStyle.BackColor = $p.BgGrid
        $dgv.DefaultCellStyle.ForeColor = $p.FgPrimary
        $dgv.DefaultCellStyle.SelectionBackColor = $p.BgSelection
        $dgv.DefaultCellStyle.SelectionForeColor = $p.FgPrimary
        $dgv.AlternatingRowsDefaultCellStyle.BackColor = $p.BgGridAlt
        $dgv.AlternatingRowsDefaultCellStyle.ForeColor = $p.FgPrimary
        $dgv.ColumnHeadersDefaultCellStyle.BackColor = $p.BgGridHeader
        $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $p.FgPrimary
        $dgv.ColumnHeadersDefaultCellStyle.Font = $fontUiBold
    }

    Update-HeaderStatusBadges
}

function Switch-MainTab {
    param([ValidateSet('Discover', 'MyScripts', 'Publish', 'Settings')][string]$TabName)
    $script:ActiveMainTab = $TabName
    $viewDiscover.Visible  = ($TabName -eq 'Discover')
    $viewMyScripts.Visible = ($TabName -eq 'MyScripts')
    $viewPublish.Visible   = ($TabName -eq 'Publish')
    $viewSettings.Visible  = ($TabName -eq 'Settings')
    Apply-Theme
}

function Switch-MySubTab {
    param([ValidateSet('Published', 'Local')][string]$SubName)
    $script:ActiveMySubTab = $SubName
    $subViewPublished.Visible = ($SubName -eq 'Published')
    $subViewLocal.Visible     = ($SubName -eq 'Local')
    Apply-Theme
}

# ==============================================================================
# 12. GALLERY DISCOVERY, INSPECT, INSTALL, DOWNLOAD & LOCAL OPERATIONS
# ==============================================================================
function Show-CodeInspectorDialog {
    param([string]$PackageId, [string]$Version, [string]$CodeText)
    $p = Get-ThemePalette

    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = "Code Inspector - $PackageId v$Version"
    $dlg.Size = New-Object Drawing.Size(920, 680)
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $p.BgMain
    $dlg.ForeColor = $p.FgPrimary
    $dlg.Add_Shown({
        if ($script:HasWin32) {
            try { [PSGalWin32]::SetDarkTitleBar($dlg.Handle, $p.IsDark) } catch { }
        }
    })

    $topBar = New-Object Windows.Forms.Panel
    $topBar.Dock = 'Top'; $topBar.Height = 46; $topBar.BackColor = $p.BgHeader; $topBar.Padding = New-Object Windows.Forms.Padding(12, 8, 12, 8)
    $dlg.Controls.Add($topBar)

    $txtCode = New-Object Windows.Forms.TextBox
    $txtCode.Multiline = $true; $txtCode.ReadOnly = $true; $txtCode.ScrollBars = 'Both'; $txtCode.WordWrap = $false
    $txtCode.Dock = 'Fill'; $txtCode.Font = $fontMono; $txtCode.BackColor = $p.BgInput; $txtCode.ForeColor = $p.FgPrimary; $txtCode.Text = $CodeText
    $dlg.Controls.Add($txtCode)

    $btnCopyCode = New-Object Windows.Forms.Button
    $btnCopyCode.Text = 'Copy All Code'; $btnCopyCode.Font = $fontUiBold; $btnCopyCode.Size = New-Object Drawing.Size(130, 30); $btnCopyCode.Location = New-Object Drawing.Point(12, 8)
    $btnCopyCode.FlatStyle = 'Flat'; $btnCopyCode.BackColor = $p.Accent; $btnCopyCode.ForeColor = [Drawing.Color]::White; $btnCopyCode.FlatAppearance.BorderSize = 0
    $btnCopyCode.Tag = $txtCode
    $btnCopyCode.Add_Click({ param($s, $e) [Windows.Forms.Clipboard]::SetText($s.Tag.Text); [Windows.Forms.MessageBox]::Show('Code copied to clipboard.', 'Copied', 'OK', 'Information') | Out-Null })
    $topBar.Controls.Add($btnCopyCode)

    $btnSaveCodeAs = New-Object Windows.Forms.Button
    $btnSaveCodeAs.Text = 'Save As .ps1...'; $btnSaveCodeAs.Size = New-Object Drawing.Size(125, 30); $btnSaveCodeAs.Location = New-Object Drawing.Point(152, 8)
    $btnSaveCodeAs.FlatStyle = 'Flat'; $btnSaveCodeAs.BackColor = $p.BtnSecondary; $btnSaveCodeAs.ForeColor = $p.FgPrimary; $btnSaveCodeAs.FlatAppearance.BorderColor = $p.Border
    $btnSaveCodeAs.Tag = @{ Box = $txtCode; Id = $PackageId }
    $btnSaveCodeAs.Add_Click({
        param($s, $e)
        $sfd = New-Object Windows.Forms.SaveFileDialog
        $sfd.Filter = 'PowerShell Script (*.ps1)|*.ps1|All Files (*.*)|*.*'
        $sfd.FileName = "$($s.Tag.Id).ps1"
        if ($sfd.ShowDialog() -eq 'OK') {
            Set-Content -LiteralPath $sfd.FileName -Value $s.Tag.Box.Text -Encoding UTF8
            [Windows.Forms.MessageBox]::Show("Saved to $($sfd.FileName)", 'Saved', 'OK', 'Information') | Out-Null
        }
    })
    $topBar.Controls.Add($btnSaveCodeAs)

    $txtCode.BringToFront()
    [void]$dlg.ShowDialog($form)
}

function Invoke-InspectPackageCode {
    param([PSCustomObject]$Pkg)
    if ($null -eq $Pkg) { return }

    $lblStatus.Text = "Downloading package archive to inspect $($Pkg.Id) v$($Pkg.Version)..."
    $work = {
        param($id, $ver)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("PSGalInspect_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $nupkgFile = Join-Path $tmpDir "$id.zip"
        try {
            Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/package/$id/$ver" -OutFile $nupkgFile -UseBasicParsing -ErrorAction Stop
            $extractDir = Join-Path $tmpDir 'extracted'
            [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkgFile, $extractDir)
            $psFiles = @(Get-ChildItem -LiteralPath $extractDir -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File)
            if ($psFiles.Count -eq 0) { return 'No .ps1, .psm1, or .psd1 files were found inside this package.' }
            $sb = New-Object System.Text.StringBuilder
            foreach ($f in $psFiles) {
                if ($psFiles.Count -gt 1) { [void]$sb.AppendLine("# === FILE: $($f.Name) ===") }
                [void]$sb.AppendLine((Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8))
                [void]$sb.AppendLine('')
            }
            return $sb.ToString()
        }
        finally {
            if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($Pkg.Id, $Pkg.Version) -State @{ Pkg = $Pkg } -OnComplete {
        param($res, $err, $state)
        if ($err) {
            $lblStatus.Text = "Inspection failed: $err"
            [Windows.Forms.MessageBox]::Show("Could not inspect package code:`n$err", 'Error', 'OK', 'Error') | Out-Null
            return
        }
        $lblStatus.Text = "Loaded source code for $($state.Pkg.Id) v$($state.Pkg.Version)."
        Show-CodeInspectorDialog -PackageId $state.Pkg.Id -Version $state.Pkg.Version -CodeText ($res | Out-String)
    }
}

$script:SelectedGalleryPkgId = ''

function Invoke-InstallPackage {
    param([PSCustomObject]$Pkg)
    if ($null -eq $Pkg) { return }
    $scope = Get-EffectiveScope
    if ([Windows.Forms.MessageBox]::Show("Install $($Pkg.Type) '$($Pkg.Id)' (v$($Pkg.Version)) to your computer?`n`nTarget Scope: $scope", 'Confirm Installation', 'YesNo', 'Question') -ne 'Yes') { return }

    $lblStatus.Text = "Installing $($Pkg.Type) '$($Pkg.Id)' ($scope)..."
    $btnInstallPkg.Enabled = $false

    $work = {
        param($id, $type, $targetScope)
        $ConfirmPreference = 'None'; $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }
        if ($type -eq 'Script') {
            $installParams = @{ Name = $id; Scope = $targetScope; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Install-Script -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AcceptLicense')) {
                $installParams['AcceptLicense'] = $true
            }
            Install-Script @installParams
        }
        else {
            $installParams = @{ Name = $id; Scope = $targetScope; Force = $true; AllowClobber = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Install-Module -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AcceptLicense')) {
                $installParams['AcceptLicense'] = $true
            }
            Install-Module @installParams
        }
        return "Successfully installed $type '$id' ($targetScope)."
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($Pkg.Id, $Pkg.Type, $scope) -OnComplete {
        param($res, $err, $state)
        $btnInstallPkg.Enabled = $true
        if ($err) {
            $lblStatus.Text = "Install failed: $err"
            [Windows.Forms.MessageBox]::Show("Installation failed:`n$err", 'Install Error', 'OK', 'Error') | Out-Null
        }
        else {
            $msg = ($res | Out-String).Trim()
            $lblStatus.Text = $msg
            $script:CurrentLocalResults = @()
            if ($script:ActiveMainTab -eq 'MyScripts' -and $script:ActiveMySubTab -eq 'Local') {
                Invoke-ScanLocalPackages
            }
            [Windows.Forms.MessageBox]::Show($msg, 'Installation Complete', 'OK', 'Information') | Out-Null
        }
    }
}

function Invoke-DownloadPackage {
    param(
        [PSCustomObject]$Pkg,
        [switch]$ChooseFolder
    )
    if ($null -eq $Pkg) { return }

    $rawDefault = if ([string]::IsNullOrWhiteSpace($script:Config.DefaultSavePath)) {
        Join-Path $HOME 'Downloads\PSGallery'
    }
    else {
        [Environment]::ExpandEnvironmentVariables($script:Config.DefaultSavePath.Trim())
    }

    $dest      = $rawDefault
    $askFolder = $ChooseFolder -or (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Shift) -eq [System.Windows.Forms.Keys]::Shift)

    if ($askFolder -or [string]::IsNullOrWhiteSpace($dest)) {
        $fbd = New-Object Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Choose destination folder to download $($Pkg.Id)"
        if (-not [string]::IsNullOrWhiteSpace($dest) -and (Test-Path -LiteralPath $dest)) {
            $fbd.SelectedPath = $dest
        }
        if ($fbd.ShowDialog() -ne 'OK') { return }
        $dest = $fbd.SelectedPath
    }

    $lblStatus.Text = "Downloading $($Pkg.Type) '$($Pkg.Id)' to $dest..."
    $btnDownloadPkg.Enabled = $false
    $btnPubDownload.Enabled = $false

    $work = {
        param($id, $type, $saveDir)
        $ConfirmPreference = 'None'; $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Test-Path -LiteralPath $saveDir)) { New-Item -ItemType Directory -Path $saveDir -Force | Out-Null }
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }
        if ($type -eq 'Script') {
            $saveParams = @{ Name = $id; Path = $saveDir; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Save-Script -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AcceptLicense')) {
                $saveParams['AcceptLicense'] = $true
            }
            Save-Script @saveParams
            return (Join-Path $saveDir "$id.ps1")
        }
        else {
            $saveParams = @{ Name = $id; Path = $saveDir; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Save-Module -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AcceptLicense')) {
                $saveParams['AcceptLicense'] = $true
            }
            Save-Module @saveParams
            return (Join-Path $saveDir $id)
        }
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($Pkg.Id, $Pkg.Type, $dest) -State @{ Pkg = $Pkg; Dest = $dest } -OnComplete {
        param($res, $err, $state)
        $btnDownloadPkg.Enabled = ($dgvGallery.SelectedRows.Count -gt 0)
        $btnPubDownload.Enabled = $true
        if ($err) {
            $lblStatus.Text = "Download failed: $err"
            [Windows.Forms.MessageBox]::Show("Download failed:`n$err", 'Download Error', 'OK', 'Error') | Out-Null
        }
        else {
            $savedLocation = ($res | Out-String).Trim()
            $lblStatus.Text = "Downloaded to $savedLocation"
            if ([Windows.Forms.MessageBox]::Show("Downloaded '$($state.Pkg.Id)' to:`n$savedLocation`n`nOpen folder in File Explorer?", 'Download Complete', 'YesNo', 'Information') -eq 'Yes') {
                Start-Process explorer.exe -ArgumentList "`"$($state.Dest)`""
            }
        }
    }
}

$script:SelectedGalleryPkgId = ''
$script:DownloadCountCache   = @{}
$script:SearchGeneration     = 0

function Invoke-GallerySearch {
    param([int]$PageIndex = 0)
    $script:CurrentPage = [Math]::Max(0, $PageIndex)
    $script:SearchGeneration++
    $currentGen = $script:SearchGeneration

    $category = [string]$cmbCategory.SelectedItem
    $itemType = [string]$cmbItemType.SelectedItem
    $sortMode = [string]$cmbSort.SelectedItem
    $queryTxt = $txtSearch.Text.Trim()
    $pageSize = [int]$script:Config.PageSize
    $skip     = $script:CurrentPage * $pageSize

    $lblStatus.Text = "Searching PowerShell Gallery ($category | $itemType | Page $($script:CurrentPage + 1))..."
    $btnSearch.Enabled = $false; $btnPrevPage.Enabled = $false; $btnNextPage.Enabled = $false
    $parserCode = $script:ODataParserBlock.ToString()

    $work = {
        param($cat, $type, $sort, $search, $top, $skipCount, $parserScript)
        . ([scriptblock]::Create($parserScript))
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $filters = New-Object System.Collections.Generic.List[string]
        $filters.Add('IsLatestVersion eq true')
        if ($type -eq 'Scripts') { $filters.Add("substringof('PSScript', Tags)") }
        elseif ($type -eq 'Modules') { $filters.Add("not substringof('PSScript', Tags)") }
        if ($cat -and $cat -ne 'All Categories') {
            $safeCat = $cat.ToLowerInvariant().Replace("'", "''")
            $filters.Add("substringof('$safeCat', tolower(Tags))")
        }
        if (-not [string]::IsNullOrWhiteSpace($search)) {
            $safeQ = $search.ToLowerInvariant().Replace("'", "''")
            $filters.Add("(substringof('$safeQ', tolower(Id)) or substringof('$safeQ', tolower(Description)) or substringof('$safeQ', tolower(Tags)))")
        }
        $orderBy = switch ($sort) { 'Recently Updated' { 'Published desc' } 'Name (A-Z)' { 'Id asc' } default { 'DownloadCount desc' } }
        $uri     = "https://www.powershellgallery.com/api/v2/Packages()?`$filter=$([uri]::EscapeDataString($filters -join ' and '))&`$orderby=$([uri]::EscapeDataString($orderBy))&`$top=$top&`$skip=$skipCount"
        $headers = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
        $resp    = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 25 -ErrorAction Stop
        return @(ConvertFrom-GalleryFeed -RawResponse $resp)
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($category, $itemType, $sortMode, $queryTxt, $pageSize, $skip, $parserCode) -State @{ PageSize = $pageSize; Gen = $currentGen; ParserCode = $parserCode } -OnComplete {
        param($res, $err, $state)
        if ($state.Gen -ne $script:SearchGeneration) { return }

        $btnSearch.Enabled = $true
        $lblPage.Text = "Page $($script:CurrentPage + 1)"
        $btnPrevPage.Enabled = ($script:CurrentPage -gt 0)

        if ($err) {
            $lblStatus.Text = "Search error: $err"
            [Windows.Forms.MessageBox]::Show("Failed to query PowerShell Gallery:`n$err", 'Gallery Error', 'OK', 'Error') | Out-Null
            return
        }

        $items = @($res | Where-Object { $null -ne $_ })
        $uncachedIds = New-Object System.Collections.Generic.List[string]

        foreach ($item in $items) {
            if ($script:DownloadCountCache.ContainsKey($item.Id)) {
                $cached = $script:DownloadCountCache[$item.Id]
                $item.Downloads        = [long]$cached.TotalDownloads
                $item.VersionDownloads = [long]$cached.LatestVersionDownloads
            }
            else {
                [void]$uncachedIds.Add($item.Id)
            }
        }

        $script:CurrentGalleryResults = $items
        $btnNextPage.Enabled = ($items.Count -ge $state.PageSize)

        $dgvGallery.Columns.Clear(); $dgvGallery.Rows.Clear()
        [void]$dgvGallery.Columns.Add('Id', 'Package Name')
        [void]$dgvGallery.Columns.Add('Type', 'Type')
        [void]$dgvGallery.Columns.Add('Version', 'Version')
        [void]$dgvGallery.Columns.Add('Authors', 'Author')
        [void]$dgvGallery.Columns.Add('Downloads', 'Downloads')
        [void]$dgvGallery.Columns.Add('Published', 'Published')

        $dgvGallery.Columns['Id'].FillWeight = 32; $dgvGallery.Columns['Type'].FillWeight = 11; $dgvGallery.Columns['Version'].FillWeight = 13
        $dgvGallery.Columns['Authors'].FillWeight = 18; $dgvGallery.Columns['Downloads'].FillWeight = 13; $dgvGallery.Columns['Published'].FillWeight = 13

        foreach ($item in $items) {
            [void]$dgvGallery.Rows.Add($item.Id, $item.Type, $item.Version, $item.Authors, $item.Downloads.ToString('N0'), $item.Published)
        }

        $lblStatus.Text = "Found $($items.Count) package(s) on Page $($script:CurrentPage + 1)."
        if ($items.Count -gt 0) { $dgvGallery.Rows[0].Selected = $true; Update-GalleryDetailsPane -Pkg $items[0] }
        else { Update-GalleryDetailsPane -Pkg $null }

        # Sync exact FindPackagesById() counts for all uncached rows on this page so every sort order matches
        if ($uncachedIds.Count -gt 0) {
            $idBatch = @($uncachedIds)
            $hydrateWork = {
                param($ids, $parserScript)
                . ([scriptblock]::Create($parserScript))
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $out = New-Object System.Collections.Generic.List[object]
                $i = 0
                foreach ($pkgId in $ids) {
                    $stats = Get-AccuratePackageDownloads -PackageId $pkgId
                    if ($null -ne $stats) {
                        $out.Add([PSCustomObject]@{ Id = $pkgId; Stats = $stats })
                    }
                    $i++
                    if (($i % 5) -eq 0) { Start-Sleep -Milliseconds 60 }
                }
                return @($out)
            }

            Invoke-AsyncTask -Work $hydrateWork -ArgumentList @(, $idBatch, $state.ParserCode) -State @{ Gen = $state.Gen } -OnComplete {
                param($hRes, $hErr, $hState)
                if ($hErr -or $null -eq $hRes -or ($hState.Gen -ne $script:SearchGeneration)) { return }

                $byId = @{}
                foreach ($entry in @($hRes | Where-Object { $null -ne $_ })) {
                    if ($null -ne $entry.Stats) {
                        $script:DownloadCountCache[$entry.Id] = $entry.Stats
                        $byId[$entry.Id] = $entry.Stats
                    }
                }

                foreach ($pkgObj in @($script:CurrentGalleryResults)) {
                    if ($byId.ContainsKey($pkgObj.Id)) {
                        $pkgObj.Downloads        = [long]$byId[$pkgObj.Id].TotalDownloads
                        $pkgObj.VersionDownloads = [long]$byId[$pkgObj.Id].LatestVersionDownloads
                    }
                }

                for ($r = 0; $r -lt $dgvGallery.Rows.Count; $r++) {
                    $rowId = [string]$dgvGallery.Rows[$r].Cells['Id'].Value
                    if ($byId.ContainsKey($rowId)) {
                        $dgvGallery.Rows[$r].Cells['Downloads'].Value = ([long]$byId[$rowId].TotalDownloads).ToString('N0')
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($script:SelectedGalleryPkgId) -and $byId.ContainsKey($script:SelectedGalleryPkgId)) {
                    $selPkg = $script:CurrentGalleryResults | Where-Object { $_.Id -eq $script:SelectedGalleryPkgId } | Select-Object -First 1
                    if ($null -ne $selPkg) {
                        $verPart = if ($selPkg.VersionDownloads -gt 0) { " (v$($selPkg.Version): $($selPkg.VersionDownloads.ToString('N0')))" } else { '' }
                        $lblDetMeta.Text = "Type: $($selPkg.Type)   |   Author: $($selPkg.Authors)`r`nDownloads: $($selPkg.Downloads.ToString('N0'))$verPart   |   Published: $($selPkg.Published)"
                        if (Get-Command Update-GalleryDetailsLayout -ErrorAction SilentlyContinue) { Update-GalleryDetailsLayout }
                    }
                }
            }
        }
    }
}

$script:TranslationCache      = @{}
$script:IsShowingTranslation  = $false
$script:CurrentDetailsPkg     = $null

function Format-PackageDetailsBody {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Pkg,
        [string]$DescriptionText = $Pkg.Description,
        [string]$ReleaseNotesText = $Pkg.ReleaseNotes,
        [string]$TranslatedBanner = ''
    )

    $body = New-Object System.Text.StringBuilder
    if (-not [string]::IsNullOrWhiteSpace($TranslatedBanner)) {
        [void]$body.AppendLine("[$TranslatedBanner]`r`n")
    }
    [void]$body.AppendLine("DESCRIPTION:`r`n$DescriptionText")
    if (-not [string]::IsNullOrWhiteSpace($ReleaseNotesText)) {
        [void]$body.AppendLine("`r`nRELEASE NOTES:`r`n$ReleaseNotesText")
    }
    if (-not [string]::IsNullOrWhiteSpace($Pkg.ProjectUrl)) {
        [void]$body.AppendLine("`r`nPROJECT URL: $($Pkg.ProjectUrl)")
    }
    if (-not [string]::IsNullOrWhiteSpace($Pkg.Tags)) {
        [void]$body.AppendLine("`r`nTAGS:`r`n$($Pkg.Tags)")
    }
    return $body.ToString()
}

function Get-SelectedTargetLangCode {
    $sel = [string]$cmbTargetLang.SelectedItem
    if ($sel -match '\(([a-zA-Z\-]+)\)$') {
        return $Matches[1]
    }
    return 'en'
}

function Update-GalleryDetailsPane {
    param([PSCustomObject]$Pkg)
    $script:CurrentDetailsPkg    = $Pkg
    $script:IsShowingTranslation = $false
    $btnTranslate.Text           = 'Translate'

    if ($null -eq $Pkg) {
        $script:SelectedGalleryPkgId = ''
        $lblDetTitle.Text = 'No package selected'; $lblDetMeta.Text = ''; $txtDetBody.Text = ''
        if (Get-Command Update-GalleryDetailsLayout -ErrorAction SilentlyContinue) { Update-GalleryDetailsLayout }
        foreach ($b in @($btnInstallPkg, $btnDownloadPkg, $btnViewCode, $btnTranslate, $cmbTargetLang)) { $b.Enabled = $false }
        return
    }

    $script:SelectedGalleryPkgId = $Pkg.Id
    $isCached = $script:DownloadCountCache.ContainsKey($Pkg.Id)
    if ($isCached) {
        $cached = $script:DownloadCountCache[$Pkg.Id]
        $Pkg.Downloads        = [long]$cached.TotalDownloads
        $Pkg.VersionDownloads = [long]$cached.LatestVersionDownloads
    }

    $lblDetTitle.Text = "$($Pkg.Id)  (v$($Pkg.Version))"
    if ($isCached) {
        $verPart = if ($Pkg.VersionDownloads -gt 0) { " (v$($Pkg.Version): $($Pkg.VersionDownloads.ToString('N0')))" } else { '' }
        $lblDetMeta.Text = "Type: $($Pkg.Type)   |   Author: $($Pkg.Authors)`r`nDownloads: $($Pkg.Downloads.ToString('N0'))$verPart   |   Published: $($Pkg.Published)"
    }
    else {
        $lblDetMeta.Text = "Type: $($Pkg.Type)   |   Author: $($Pkg.Authors)`r`nDownloads: $($Pkg.Downloads.ToString('N0')) (loading exact...)   |   Published: $($Pkg.Published)"
    }
    if (Get-Command Update-GalleryDetailsLayout -ErrorAction SilentlyContinue) { Update-GalleryDetailsLayout }

    $txtDetBody.Text = Format-PackageDetailsBody -Pkg $Pkg
    foreach ($b in @($btnInstallPkg, $btnDownloadPkg, $btnViewCode, $btnTranslate, $cmbTargetLang)) { $b.Enabled = $true }

    if ($isCached) { return }

    $parserCode = $script:ODataParserBlock.ToString()
    $work = {
        param($pkgId, $parserScript)
        . ([scriptblock]::Create($parserScript))
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        return (Get-AccuratePackageDownloads -PackageId $pkgId)
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($Pkg.Id, $parserCode) -State @{ Pkg = $Pkg } -OnComplete {
        param($res, $err, $state)
        if ($err -or $null -eq $res) { return }
        $stats = $res | Select-Object -First 1
        if ($null -eq $stats) { return }

        $script:DownloadCountCache[$state.Pkg.Id] = $stats
        $state.Pkg.Downloads        = [long]$stats.TotalDownloads
        $state.Pkg.VersionDownloads = [long]$stats.LatestVersionDownloads

        for ($r = 0; $r -lt $dgvGallery.Rows.Count; $r++) {
            if ([string]$dgvGallery.Rows[$r].Cells['Id'].Value -eq $state.Pkg.Id) {
                $dgvGallery.Rows[$r].Cells['Downloads'].Value = $state.Pkg.Downloads.ToString('N0')
                break
            }
        }

        if ($script:SelectedGalleryPkgId -eq $state.Pkg.Id) {
            $verPart = if ($state.Pkg.VersionDownloads -gt 0) { " (v$($state.Pkg.Version): $($state.Pkg.VersionDownloads.ToString('N0')))" } else { '' }
            $lblDetMeta.Text = "Type: $($state.Pkg.Type)   |   Author: $($state.Pkg.Authors)`r`nDownloads: $($state.Pkg.Downloads.ToString('N0'))$verPart   |   Published: $($state.Pkg.Published)"
            if (Get-Command Update-GalleryDetailsLayout -ErrorAction SilentlyContinue) { Update-GalleryDetailsLayout }
        }
    }
}

function Invoke-TranslatePackageDetails {
    param([switch]$ForceTranslate)

    $pkg = $script:CurrentDetailsPkg
    if ($null -eq $pkg) { return }

    if ($script:IsShowingTranslation -and (-not $ForceTranslate)) {
        $script:IsShowingTranslation = $false
        $btnTranslate.Text           = 'Translate'
        $txtDetBody.Text             = Format-PackageDetailsBody -Pkg $pkg
        $lblStatus.Text              = "Showing original description for '$($pkg.Id)'."
        return
    }

    $langCode  = Get-SelectedTargetLangCode
    $langLabel = [string]$cmbTargetLang.SelectedItem
    $cacheKey  = "$($pkg.Id)|$($pkg.Version)|$langCode"

    if ($script:TranslationCache.ContainsKey($cacheKey)) {
        $entry = $script:TranslationCache[$cacheKey]
        $script:IsShowingTranslation = $true
        $btnTranslate.Text           = 'Show Original'
        $txtDetBody.Text             = Format-PackageDetailsBody -Pkg $pkg -DescriptionText $entry.Description -ReleaseNotesText $entry.ReleaseNotes -TranslatedBanner "Translated to $langLabel"
        $lblStatus.Text              = "Translated '$($pkg.Id)' to $langLabel (cached)."
        return
    }

    $lblStatus.Text       = "Translating '$($pkg.Id)' to $langLabel..."
    $btnTranslate.Enabled = $false

    $work = {
        param($descText, $notesText, $targetLang)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        function ConvertTo-TranslatedBlock {
            param([string]$InputText, [string]$Lang)
            if ([string]::IsNullOrWhiteSpace($InputText)) { return '' }

            $outLines = New-Object System.Collections.Generic.List[string]
            foreach ($line in ($InputText -split "`r?`n")) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    $outLines.Add('')
                    continue
                }

                # Split very long single lines into <= 1200-char chunks so GET URLs stay safe
                $chunks = New-Object System.Collections.Generic.List[string]
                $remaining = $line
                while ($remaining.Length -gt 1200) {
                    $splitAt = $remaining.LastIndexOf(' ', 1200)
                    if ($splitAt -lt 200) { $splitAt = 1200 }
                    $chunks.Add($remaining.Substring(0, $splitAt))
                    $remaining = $remaining.Substring($splitAt).TrimStart()
                }
                if ($remaining.Length -gt 0) { $chunks.Add($remaining) }

                $lineBuilder = New-Object System.Text.StringBuilder
                foreach ($chunk in $chunks) {
                    $encoded = [uri]::EscapeDataString($chunk)
                    $uri     = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$Lang&dt=t&q=$encoded"
                    $resp    = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 15 -ErrorAction Stop

                    if ($null -ne $resp -and $resp.Count -gt 0 -and $null -ne $resp[0]) {
                        foreach ($seg in $resp[0]) {
                            if ($null -ne $seg -and $seg.Count -gt 0 -and $null -ne $seg[0]) {
                                [void]$lineBuilder.Append([string]$seg[0])
                            }
                        }
                    }
                }
                $outLines.Add($lineBuilder.ToString())
            }
            return ($outLines -join "`r`n")
        }

        $tDesc  = ConvertTo-TranslatedBlock -InputText $descText  -Lang $targetLang
        $tNotes = ConvertTo-TranslatedBlock -InputText $notesText -Lang $targetLang

        return [PSCustomObject]@{
            Description  = $tDesc
            ReleaseNotes = $tNotes
        }
    }

    $state = @{
        Pkg       = $pkg
        CacheKey  = $cacheKey
        LangLabel = $langLabel
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($pkg.Description, $pkg.ReleaseNotes, $langCode) -State $state -OnComplete {
        param($res, $err, $st)
        $btnTranslate.Enabled = ($null -ne $script:CurrentDetailsPkg)

        if ($err -or $null -eq $res) {
            $lblStatus.Text = "Translation failed: $err"
            [Windows.Forms.MessageBox]::Show("Could not translate package details:`n$err", 'Translation Error', 'OK', 'Warning') | Out-Null
            return
        }

        $translated = $res | Select-Object -First 1
        if ($null -eq $translated) { return }

        $script:TranslationCache[$st.CacheKey] = $translated

        if ($script:SelectedGalleryPkgId -eq $st.Pkg.Id) {
            $script:IsShowingTranslation = $true
            $btnTranslate.Text           = 'Show Original'
            $txtDetBody.Text             = Format-PackageDetailsBody -Pkg $st.Pkg -DescriptionText $translated.Description -ReleaseNotesText $translated.ReleaseNotes -TranslatedBanner "Translated to $($st.LangLabel)"
            $lblStatus.Text              = "Translated '$($st.Pkg.Id)' to $($st.LangLabel)."
        }
    }
}

function Invoke-LoadPublishedPackages {
    $user = $txtPubUser.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($user)) {
        [Windows.Forms.MessageBox]::Show('Enter your PowerShell Gallery username first (or save it in Settings).', 'Username Required', 'OK', 'Information') | Out-Null
        return
    }
    $lblStatus.Text = "Loading published PowerShell Gallery packages and live download counts for '$user'..."
    $btnRefreshPub.Enabled = $false
    $parserCode = $script:ODataParserBlock.ToString()

    $work = {
        param($ownerName, $parserScript)
        . ([scriptblock]::Create($parserScript))
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $safeUser = $ownerName.ToLowerInvariant().Replace("'", "''")
        $pattern  = [regex]::Escape($ownerName)
        $byId     = @{}

        $filter = [uri]::EscapeDataString("IsLatestVersion eq true and substringof('$safeUser', tolower(Authors))")
        $order  = [uri]::EscapeDataString('DownloadCount desc')
        $uri    = "https://www.powershellgallery.com/api/v2/Packages()?`$filter=$filter&`$orderby=$order&`$top=100"
        $resp   = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 25 -ErrorAction Stop
        foreach ($pkg in @(ConvertFrom-GalleryFeed -RawResponse $resp)) {
            if ($null -ne $pkg -and -not [string]::IsNullOrWhiteSpace($pkg.Id)) { $byId[$pkg.Id] = $pkg }
        }

        try {
            $searchUri  = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=$([uri]::EscapeDataString("'$safeUser'"))&targetFramework=''&includePrerelease=false&`$top=100"
            $searchResp = Invoke-RestMethod -Uri $searchUri -Method Get -TimeoutSec 25 -ErrorAction Stop
            foreach ($pkg in @(ConvertFrom-GalleryFeed -RawResponse $searchResp)) {
                if ($null -ne $pkg -and -not $byId.ContainsKey($pkg.Id) -and (($pkg.Owners -match $pattern) -or ($pkg.Authors -match $pattern))) {
                    $byId[$pkg.Id] = $pkg
                }
            }
        }
        catch { }

        foreach ($pkg in @($byId.Values)) {
            $exactStats = Get-AccuratePackageDownloads -PackageId $pkg.Id
            if ($null -ne $exactStats -and $exactStats.TotalDownloads -gt 0) {
                $pkg.Downloads        = [long]$exactStats.TotalDownloads
                $pkg.VersionDownloads = [long]$exactStats.LatestVersionDownloads
            }
        }

        return @($byId.Values | Sort-Object Downloads -Descending)
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($user, $parserCode) -State @{ User = $user } -OnComplete {
        param($res, $err, $state)
        $btnRefreshPub.Enabled = $true
        if ($err) {
            $lblStatus.Text = "Failed to load published packages: $err"
            [Windows.Forms.MessageBox]::Show("Could not retrieve published packages:`n$err", 'Error', 'OK', 'Error') | Out-Null
            return
        }
        $items = @($res | Where-Object { $null -ne $_ })
        $script:CurrentPublishedResults = $items

        $dgvPublished.Columns.Clear(); $dgvPublished.Rows.Clear()
        [void]$dgvPublished.Columns.Add('Id', 'Package Name')
        [void]$dgvPublished.Columns.Add('Type', 'Type')
        [void]$dgvPublished.Columns.Add('Version', 'Latest Version')
        [void]$dgvPublished.Columns.Add('Downloads', 'Total Downloads')
        [void]$dgvPublished.Columns.Add('Published', 'Last Published')
        [void]$dgvPublished.Columns.Add('Tags', 'Tags')

        $dgvPublished.Columns['Id'].FillWeight = 26; $dgvPublished.Columns['Type'].FillWeight = 10; $dgvPublished.Columns['Version'].FillWeight = 13
        $dgvPublished.Columns['Downloads'].FillWeight = 14; $dgvPublished.Columns['Published'].FillWeight = 13; $dgvPublished.Columns['Tags'].FillWeight = 24

        $totalDl = [long]0
        foreach ($item in $items) {
            $totalDl += [long]$item.Downloads
            [void]$dgvPublished.Rows.Add($item.Id, $item.Type, $item.Version, $item.Downloads.ToString('N0'), $item.Published, $item.Tags)
        }
        $lblStatus.Text = "Loaded $($items.Count) published package(s) for '$($state.User)' (Total Downloads: $($totalDl.ToString('N0')))."
    }
}

function Invoke-ScanLocalPackages {
    $lblStatus.Text = 'Scanning locally installed PowerShell scripts and modules...'
    $btnScanLocal.Enabled = $false

    $work = {
        $ErrorActionPreference = 'SilentlyContinue'
        Import-Module PowerShellGet -Force -ErrorAction SilentlyContinue

        $results = New-Object System.Collections.Generic.List[object]
        $seen    = @{}

        if (Get-Command Get-InstalledScript -ErrorAction SilentlyContinue) {
            foreach ($s in @(Get-InstalledScript -ErrorAction SilentlyContinue)) {
                if ($null -eq $s -or [string]::IsNullOrWhiteSpace($s.Name)) { continue }
                $scope = if ($s.InstalledLocation -like "$env:ProgramFiles*") { 'AllUsers' } else { 'CurrentUser' }
                $key   = "Script|$($s.Name.ToLowerInvariant())|$scope"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $results.Add([PSCustomObject]@{
                        Name             = $s.Name
                        Type             = 'Script'
                        InstalledVersion = [string]$s.Version
                        LatestVersion    = ''
                        Status           = 'Installed'
                        Scope            = $scope
                        Location         = $s.InstalledLocation
                    })
                }
            }
        }

        # Fallback XML scan to catch newly installed scripts when PowerShellGet caches session state
        $scriptRoots = @(
            @{ Path = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Scripts'); Scope = 'CurrentUser' },
            @{ Path = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Scripts');        Scope = 'CurrentUser' },
            @{ Path = (Join-Path $env:ProgramFiles 'WindowsPowerShell\Scripts');                             Scope = 'AllUsers' },
            @{ Path = (Join-Path $env:ProgramFiles 'PowerShell\Scripts');                                    Scope = 'AllUsers' }
        )
        foreach ($root in $scriptRoots) {
            $infoDir = Join-Path $root.Path 'InstalledScriptInfos'
            if (Test-Path -LiteralPath $infoDir -PathType Container) {
                foreach ($xmlFile in @(Get-ChildItem -LiteralPath $infoDir -Filter '*_InstalledScriptInfo.xml' -File -ErrorAction SilentlyContinue)) {
                    try {
                        $infoObj = Import-Clixml -LiteralPath $xmlFile.FullName -ErrorAction Stop
                        $sName   = [string]$infoObj.Name
                        $sVer    = [string]$infoObj.Version
                        $sLoc    = if ($infoObj.InstalledLocation) { [string]$infoObj.InstalledLocation } else { $root.Path }
                        if ([string]::IsNullOrWhiteSpace($sName)) { continue }
                        $key = "Script|$($sName.ToLowerInvariant())|$($root.Scope)"
                        if (-not $seen.ContainsKey($key) -and (Test-Path -LiteralPath (Join-Path $sLoc "$sName.ps1") -PathType Leaf)) {
                            $seen[$key] = $true
                            $results.Add([PSCustomObject]@{
                                Name             = $sName
                                Type             = 'Script'
                                InstalledVersion = $sVer
                                LatestVersion    = ''
                                Status           = 'Installed'
                                Scope            = $root.Scope
                                Location         = $sLoc
                            })
                        }
                    }
                    catch { }
                }
            }
        }

        if (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue) {
            foreach ($m in @(Get-InstalledModule -ErrorAction SilentlyContinue)) {
                if ($null -eq $m -or [string]::IsNullOrWhiteSpace($m.Name)) { continue }
                $scope = if ($m.InstalledLocation -like "$env:ProgramFiles*") { 'AllUsers' } else { 'CurrentUser' }
                $key   = "Module|$($m.Name.ToLowerInvariant())|$scope"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $results.Add([PSCustomObject]@{
                        Name             = $m.Name
                        Type             = 'Module'
                        InstalledVersion = [string]$m.Version
                        LatestVersion    = ''
                        Status           = 'Installed'
                        Scope            = $scope
                        Location         = $m.InstalledLocation
                    })
                }
            }
        }

        return @($results | Sort-Object Type, Name)
    }

    Invoke-AsyncTask -Work $work -OnComplete {
        param($res, $err, $state)
        $btnScanLocal.Enabled = $true
        $items = @($res | Where-Object { $null -ne $_ })
        $script:CurrentLocalResults = $items
        Render-LocalGrid -Items $items
        $lblStatus.Text = "Found $($items.Count) installed PowerShellGet script(s)/module(s) on this PC."
    }
}

function Render-LocalGrid {
    param([object[]]$Items)
    $dgvLocal.Columns.Clear(); $dgvLocal.Rows.Clear()
    [void]$dgvLocal.Columns.Add('Name', 'Name'); [void]$dgvLocal.Columns.Add('Type', 'Type'); [void]$dgvLocal.Columns.Add('InstalledVersion', 'Installed')
    [void]$dgvLocal.Columns.Add('LatestVersion', 'Gallery Latest'); [void]$dgvLocal.Columns.Add('Status', 'Status'); [void]$dgvLocal.Columns.Add('Scope', 'Scope'); [void]$dgvLocal.Columns.Add('Location', 'Install Path')
    $dgvLocal.Columns['Name'].FillWeight = 22; $dgvLocal.Columns['Type'].FillWeight = 9; $dgvLocal.Columns['InstalledVersion'].FillWeight = 11
    $dgvLocal.Columns['LatestVersion'].FillWeight = 11; $dgvLocal.Columns['Status'].FillWeight = 14; $dgvLocal.Columns['Scope'].FillWeight = 10; $dgvLocal.Columns['Location'].FillWeight = 23
    foreach ($item in $Items) { [void]$dgvLocal.Rows.Add($item.Name, $item.Type, $item.InstalledVersion, $item.LatestVersion, $item.Status, $item.Scope, $item.Location) }
}

function Invoke-LocalCreateShortcut {
    if ($dgvLocal.SelectedRows.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show('Select an installed script from the list first.', 'No Item Selected', 'OK', 'Information') | Out-Null
        return
    }
    $idx = $dgvLocal.SelectedRows[0].Index
    if ($idx -lt 0 -or $idx -ge $script:CurrentLocalResults.Count) { return }
    $item = $script:CurrentLocalResults[$idx]

    if ($item.Type -eq 'Script') {
        $targetFile = Join-Path $item.Location "$($item.Name).ps1"
        if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
            Show-DesktopShortcutDialog -DefaultScriptPath $targetFile
        }
        else {
            [Windows.Forms.MessageBox]::Show("Could not locate the installed script file at:`n$targetFile", 'Script File Not Found', 'OK', 'Warning') | Out-Null
        }
    }
    else {
        if ([Windows.Forms.MessageBox]::Show("'$($item.Name)' is an installed Module rather than a standalone .ps1 script.`n`nOpen the Desktop Shortcut Creator anyway to browse for a .ps1 script?", 'Module Selected', 'YesNo', 'Information') -eq 'Yes') {
            Show-DesktopShortcutDialog -DefaultScriptPath ''
        }
    }
}

# ==============================================================================
# 13. WIRE UP ALL EVENT HANDLERS (NAVIGATION, GALLERY, PUBLISHER, SETTINGS)
# ==============================================================================
$btnNavDiscover.Add_Click({ Switch-MainTab 'Discover' })
$btnNavMyScripts.Add_Click({
    Switch-MainTab 'MyScripts'
    if ($script:ActiveMySubTab -eq 'Published' -and $script:CurrentPublishedResults.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($txtPubUser.Text)) {
        Invoke-LoadPublishedPackages
    }
    elseif ($script:ActiveMySubTab -eq 'Local') {
        Invoke-ScanLocalPackages
    }
})
$btnNavPublish.Add_Click({ Switch-MainTab 'Publish' })
$btnNavSettings.Add_Click({ Switch-MainTab 'Settings' })

$btnSubPublished.Add_Click({
    Switch-MySubTab 'Published'
    if ($script:CurrentPublishedResults.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($txtPubUser.Text)) {
        Invoke-LoadPublishedPackages
    }
})
$btnSubLocal.Add_Click({
    Switch-MySubTab 'Local'
    Invoke-ScanLocalPackages
})

$cmbTheme.Add_SelectedIndexChanged({
    $script:Config.ThemeMode = [string]$cmbTheme.SelectedItem
    Save-AppConfig
    Apply-Theme
})

$btnShortcutDlgTop.Add_Click({ Show-DesktopShortcutDialog -DefaultScriptPath $PSCommandPath })
$btnOpenShortcutTool.Add_Click({ Show-DesktopShortcutDialog -DefaultScriptPath $PSCommandPath })
$btnOpenApiKeysPage.Add_Click({ Start-Process 'https://www.powershellgallery.com/account/apikeys' })

$btnElevateNow.Add_Click({
    $hostExe    = Get-PowerShellHostPath
    $scriptFile = $PSCommandPath
    if ($scriptFile -and (Test-Path -LiteralPath $scriptFile -PathType Leaf)) {
        try {
            $argList = New-PowerShellRelaunchArgs -ScriptFile $scriptFile
            Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
            $form.Close()
        }
        catch {
            $lblStatus.Text = 'UAC elevation cancelled; remaining in Standard mode.'
        }
    }
})

# Discover Events
$btnSearch.Add_Click({ Invoke-GallerySearch -PageIndex 0 })
$cmbCategory.Add_SelectedIndexChanged({ if ($form.Visible) { Invoke-GallerySearch -PageIndex 0 } })
$cmbItemType.Add_SelectedIndexChanged({ if ($form.Visible) { Invoke-GallerySearch -PageIndex 0 } })
$cmbSort.Add_SelectedIndexChanged({ if ($form.Visible) { Invoke-GallerySearch -PageIndex 0 } })
$txtSearch.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; Invoke-GallerySearch -PageIndex 0 } })
$btnPrevPage.Add_Click({ Invoke-GallerySearch -PageIndex ($script:CurrentPage - 1) })
$btnNextPage.Add_Click({ Invoke-GallerySearch -PageIndex ($script:CurrentPage + 1) })

$dgvGallery.Add_SelectionChanged({
    if ($dgvGallery.SelectedRows.Count -gt 0) {
        $idx = $dgvGallery.SelectedRows[0].Index
        if ($idx -ge 0 -and $idx -lt $script:CurrentGalleryResults.Count) { Update-GalleryDetailsPane -Pkg $script:CurrentGalleryResults[$idx] }
    }
})
$btnInstallPkg.Add_Click({ if ($dgvGallery.SelectedRows.Count -gt 0) { Invoke-InstallPackage -Pkg $script:CurrentGalleryResults[$dgvGallery.SelectedRows[0].Index] } })
$btnDownloadPkg.Add_Click({ if ($dgvGallery.SelectedRows.Count -gt 0) { Invoke-DownloadPackage -Pkg $script:CurrentGalleryResults[$dgvGallery.SelectedRows[0].Index] } })
$btnViewCode.Add_Click({ if ($dgvGallery.SelectedRows.Count -gt 0) { Invoke-InspectPackageCode -Pkg $script:CurrentGalleryResults[$dgvGallery.SelectedRows[0].Index] } })

$btnTranslate.Add_Click({ Invoke-TranslatePackageDetails })

$cmbTargetLang.Add_SelectedIndexChanged({
    if ($script:IsShowingTranslation -and ($null -ne $script:CurrentDetailsPkg)) {
        Invoke-TranslatePackageDetails -ForceTranslate
    }
})

# My Gallery & Local Events
$btnRefreshPub.Add_Click({ Invoke-LoadPublishedPackages })
$txtPubUser.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; Invoke-LoadPublishedPackages } })
$btnPubDownload.Add_Click({ if ($dgvPublished.SelectedRows.Count -gt 0) { Invoke-DownloadPackage -Pkg $script:CurrentPublishedResults[$dgvPublished.SelectedRows[0].Index] } })
$btnPubInspect.Add_Click({ if ($dgvPublished.SelectedRows.Count -gt 0) { Invoke-InspectPackageCode -Pkg $script:CurrentPublishedResults[$dgvPublished.SelectedRows[0].Index] } })
$btnPubOpenWeb.Add_Click({ if ($dgvPublished.SelectedRows.Count -gt 0) { Start-Process $script:CurrentPublishedResults[$dgvPublished.SelectedRows[0].Index].GalleryDetailsUrl } })

$btnPubUnlist.Add_Click({
    if ($dgvPublished.SelectedRows.Count -eq 0) { return }
    $pkg = $script:CurrentPublishedResults[$dgvPublished.SelectedRows[0].Index]
    $apiKey = Get-ProtectedApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        [Windows.Forms.MessageBox]::Show('No DPAPI-encrypted API key found. Please add and save your API key in Settings first.', 'API Key Missing', 'OK', 'Warning') | Out-Null
        Switch-MainTab 'Settings'; return
    }
    if ([Windows.Forms.MessageBox]::Show("Unlist $($pkg.Type) '$($pkg.Id)' v$($pkg.Version) on PowerShell Gallery?", 'Confirm Unlist', 'YesNo', 'Warning') -ne 'Yes') { return }

    $lblStatus.Text = "Unlisting $($pkg.Id) v$($pkg.Version)..."
    $work = {
        param($id, $ver, $key)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri "https://www.powershellgallery.com/api/v2/package/$id/$ver" -Method Delete -Headers @{ 'X-NuGet-ApiKey' = $key } -TimeoutSec 25 -ErrorAction Stop
        return "Successfully unlisted $id v$ver."
    }
    Invoke-AsyncTask -Work $work -ArgumentList @($pkg.Id, $pkg.Version, $apiKey) -State @{ PkgId = $pkg.Id; Ver = $pkg.Version } -OnComplete {
        param($res, $err, $state)
        if ($err) {
            $lblStatus.Text = "Unlist failed: $err"
            if ($err -match '403|Forbidden|invalid, has expire|does not have permission|not authorized') {
                $detailMsg = "Failed to unlist '$($state.PkgId)' v$($state.Ver):`n$err`n`n" +
                             "Common Causes on PowerShell Gallery:`n" +
                             "1. Missing Scope: Your API key was created with 'Push' permission only and does not have 'Unlist packages' enabled.`n" +
                             "2. Package Restriction / Expiration: The key's Glob Pattern does not include '*' (all packages), or the key has expired.`n`n" +
                             "Note: PowerShell Gallery does not allow editing scopes on existing keys - you must create a new key with 'Unlist packages' checked.`n`n" +
                             "Open PowerShellGallery.com API Keys page in your browser now?"
                if ([Windows.Forms.MessageBox]::Show($detailMsg, 'API Key Permission Error (403)', 'YesNo', 'Warning') -eq 'Yes') {
                    Start-Process 'https://www.powershellgallery.com/account/apikeys'
                }
            }
            else {
                [Windows.Forms.MessageBox]::Show("Failed to unlist:`n$err", 'API Error', 'OK', 'Error') | Out-Null
            }
        }
        else {
            $lblStatus.Text = ($res | Out-String).Trim()
            Invoke-LoadPublishedPackages
        }
    }
})

$btnScanLocal.Add_Click({ Invoke-ScanLocalPackages })
$btnCheckUpdates.Add_Click({
    if ($script:CurrentLocalResults.Count -eq 0) { return }
    $lblStatus.Text = 'Checking PowerShell Gallery for updates...'
    $btnCheckUpdates.Enabled = $false
    $parserCode = $script:ODataParserBlock.ToString()
    $snapshot = @($script:CurrentLocalResults)

    $work = {
        param($localItems, $parserScript)
        . ([scriptblock]::Create($parserScript))
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $updated = foreach ($item in $localItems) {
            $safeId = $item.Name.ToLowerInvariant().Replace("'", "''")
            $uri = "https://www.powershellgallery.com/api/v2/Packages()?`$filter=$([uri]::EscapeDataString("IsLatestVersion eq true and tolower(Id) eq '$safeId'"))&`$top=1"
            $latest = ''; $status = 'Up to Date'
            try {
                $found = @(ConvertFrom-GalleryFeed -RawResponse (Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 15 -ErrorAction Stop) | Where-Object { $null -ne $_ })
                if ($found.Count -gt 0) { $latest = $found[0].Version; if ($latest -ne $item.InstalledVersion) { $status = 'Update Available' } }
                else { $status = 'Not on Gallery' }
            }
            catch { $status = 'Check Failed' }
            [PSCustomObject]@{ Name = $item.Name; Type = $item.Type; InstalledVersion = $item.InstalledVersion; LatestVersion = $latest; Status = $status; Scope = $item.Scope; Location = $item.Location }
        }
        return @($updated)
    }

    Invoke-AsyncTask -Work $work -ArgumentList @(, $snapshot, $parserCode) -OnComplete {
        param($res, $err, $state)
        $btnCheckUpdates.Enabled = $true
        $items = @($res | Where-Object { $null -ne $_ })
        $script:CurrentLocalResults = $items
        Render-LocalGrid -Items $items
        $lblStatus.Text = "Update check complete: $(@($items | Where-Object { $_.Status -eq 'Update Available' }).Count) update(s) available."
    }
})

$btnUpdateLocal.Add_Click({
    if ($dgvLocal.SelectedRows.Count -eq 0) { return }
    $item = $script:CurrentLocalResults[$dgvLocal.SelectedRows[0].Index]
    if ($item.Scope -eq 'AllUsers' -and (-not $script:IsAdmin)) {
        [Windows.Forms.MessageBox]::Show("'$($item.Name)' is installed in AllUsers scope. Click 'Elevate' in the top bar first.", 'Admin Required', 'OK', 'Warning') | Out-Null; return
    }
    $lblStatus.Text = "Updating $($item.Type) '$($item.Name)'..."
    $work = {
        param($name, $type)
        $ConfirmPreference = 'None'; $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if ($type -eq 'Script') {
            $updParams = @{ Name = $name; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Update-Script -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AcceptLicense')) {
                $updParams['AcceptLicense'] = $true
            }
            Update-Script @updParams
        }
        else {
            $updParams = @{ Name = $name; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Update-Module -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AcceptLicense')) {
                $updParams['AcceptLicense'] = $true
            }
            Update-Module @updParams
        }
        return "Updated $type '$name'."
    }
    Invoke-AsyncTask -Work $work -ArgumentList @($item.Name, $item.Type) -OnComplete {
        param($res, $err, $state)
        if ($err) { $lblStatus.Text = "Update failed: $err"; [Windows.Forms.MessageBox]::Show("Update failed:`n$err", 'Error', 'OK', 'Error') | Out-Null }
        else { $lblStatus.Text = ($res | Out-String).Trim(); Invoke-ScanLocalPackages }
    }
})

$btnUninstallLocal.Add_Click({
    if ($dgvLocal.SelectedRows.Count -eq 0) { return }
    $item = $script:CurrentLocalResults[$dgvLocal.SelectedRows[0].Index]
    if ($item.Scope -eq 'AllUsers' -and (-not $script:IsAdmin)) {
        [Windows.Forms.MessageBox]::Show("'$($item.Name)' is installed in AllUsers scope. Click 'Elevate' in the top bar first.", 'Admin Required', 'OK', 'Warning') | Out-Null; return
    }
    if ([Windows.Forms.MessageBox]::Show("Uninstall $($item.Type) '$($item.Name)' (v$($item.InstalledVersion))?", 'Confirm Uninstall', 'YesNo', 'Warning') -ne 'Yes') { return }
    $lblStatus.Text = "Uninstalling $($item.Type) '$($item.Name)'..."
    $work = {
        param($name, $type)
        $ConfirmPreference = 'None'
        if ($type -eq 'Script') {
            $uninstParams = @{ Name = $name; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Uninstall-Script -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AllVersions')) {
                $uninstParams['AllVersions'] = $true
            }
            Uninstall-Script @uninstParams
        }
        else {
            $uninstParams = @{ Name = $name; Force = $true; ErrorAction = 'Stop' }
            $cmdMeta = Get-Command Uninstall-Module -ErrorAction SilentlyContinue
            if ($null -ne $cmdMeta -and $cmdMeta.Parameters.ContainsKey('AllVersions')) {
                $uninstParams['AllVersions'] = $true
            }
            Uninstall-Module @uninstParams
        }
        return "Uninstalled $type '$name'."
    }
    Invoke-AsyncTask -Work $work -ArgumentList @($item.Name, $item.Type) -OnComplete {
        param($res, $err, $state)
        if ($err) { $lblStatus.Text = "Uninstall failed: $err"; [Windows.Forms.MessageBox]::Show("Uninstall failed:`n$err", 'Error', 'OK', 'Error') | Out-Null }
        else { $lblStatus.Text = ($res | Out-String).Trim(); Invoke-ScanLocalPackages }
    }
})

$btnOpenLocalFolder.Add_Click({
    if ($dgvLocal.SelectedRows.Count -gt 0) {
        $loc = $script:CurrentLocalResults[$dgvLocal.SelectedRows[0].Index].Location
        if (Test-Path -LiteralPath $loc) { Start-Process explorer.exe -ArgumentList "`"$loc`"" }
    }
})

$btnEditLocal.Add_Click({
    if ($dgvLocal.SelectedRows.Count -gt 0) {
        $item = $script:CurrentLocalResults[$dgvLocal.SelectedRows[0].Index]
        $targetFile = if ($item.Type -eq 'Script') { Join-Path $item.Location "$($item.Name).ps1" }
        else {
            $psm = Get-ChildItem -LiteralPath $item.Location -Recurse -Include '*.psm1', '*.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($psm) { $psm.FullName } else { '' }
        }
        if ($targetFile -and (Test-Path -LiteralPath $targetFile)) {
            if (Get-Command code.cmd -ErrorAction SilentlyContinue) { Start-Process 'code.cmd' -ArgumentList "`"$targetFile`"" -WindowStyle Hidden }
            else { Start-Process 'notepad.exe' -ArgumentList "`"$targetFile`"" }
        }
    }
})

$btnLocalShortcut.Add_Click({ Invoke-LocalCreateShortcut })
$mnuLocalShortcut.Add_Click({ Invoke-LocalCreateShortcut })
$mnuLocalEdit.Add_Click({ $btnEditLocal.PerformClick() })
$mnuLocalFolder.Add_Click({ $btnOpenLocalFolder.PerformClick() })
$mnuLocalUpdate.Add_Click({ $btnUpdateLocal.PerformClick() })
$mnuLocalUninstall.Add_Click({ $btnUninstallLocal.PerformClick() })

$dgvLocal.Add_CellMouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right -and $e.RowIndex -ge 0 -and $e.RowIndex -lt $dgvLocal.Rows.Count) {
        $dgvLocal.ClearSelection()
        $dgvLocal.Rows[$e.RowIndex].Selected = $true
        if ($e.ColumnIndex -ge 0) {
            $dgvLocal.CurrentCell = $dgvLocal.Rows[$e.RowIndex].Cells[$e.ColumnIndex]
        }
    }
})

$dgvLocal.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) {
        Invoke-LocalCreateShortcut
    }
})

# ==============================================================================
# 14. PUBLISHER EVENT HANDLERS
# ==============================================================================
$btnPubClearLog.Add_Click({ $txtPubLog.Clear() })

$cmbPubRecent.Add_SelectedIndexChanged({
    if ($script:IsInitializing -or $script:SuppressEvents) { return }
    $idx = $cmbPubRecent.SelectedIndex
    $items = @($script:Config.PubRecentPackages)
    if ($idx -lt 0 -or $idx -ge $items.Count) { return }
    $chosen = $items[$idx]
    $isScript = ($chosen.Type -eq 'Script')

    $script:SuppressEvents = $true
    try {
        if ($isScript) { $rbPubScript.Checked = $true; $lblPubPath.Text = 'Script (.ps1):' }
        else { $rbPubModule.Checked = $true; $lblPubPath.Text = 'Module Folder:' }
        $txtPubPath.Text = $chosen.Path
    }
    finally { $script:SuppressEvents = $false }

    Write-PubLog "Switched to recent $($chosen.Type.ToLower()): $($chosen.Path)"
    Add-PubRecentPackage -Path $chosen.Path -Type $chosen.Type
    Import-PubTargetMetadata -TargetPath $chosen.Path -IsScript $isScript
})

$btnPubClearRecent.Add_Click({
    $script:Config.PubRecentPackages = @()
    Refresh-PubRecentDropdown
    Save-PubStateToConfig
    Write-PubLog 'Cleared Recent Packages history.' 'INFO'
})

$rbPubScript.Add_CheckedChanged({
    if ($rbPubScript.Checked) {
        $lblPubPath.Text = 'Script (.ps1):'
        if (-not $script:IsInitializing -and -not $script:SuppressEvents) {
            $script:Config.PubLastModulePath = $txtPubPath.Text.Trim()
            $txtPubPath.Text = $script:Config.PubLastScriptPath
            Refresh-PubRecentDropdown -SelectPath $txtPubPath.Text
            Save-PubStateToConfig
            if (-not [string]::IsNullOrWhiteSpace($txtPubPath.Text)) { Import-PubTargetMetadata -TargetPath $txtPubPath.Text -IsScript $true -QuietMissing }
            else { $lblPubLiveVer.Text = 'Live Gallery Version: Not checked'; Clear-PubMetadataFields -ApplyShareableDefaults $true }
        }
    }
})

$rbPubModule.Add_CheckedChanged({
    if ($rbPubModule.Checked) {
        $lblPubPath.Text = 'Module Folder:'
        if (-not $script:IsInitializing -and -not $script:SuppressEvents) {
            $script:Config.PubLastScriptPath = $txtPubPath.Text.Trim()
            $txtPubPath.Text = $script:Config.PubLastModulePath
            Refresh-PubRecentDropdown -SelectPath $txtPubPath.Text
            Save-PubStateToConfig
            if (-not [string]::IsNullOrWhiteSpace($txtPubPath.Text)) { Import-PubTargetMetadata -TargetPath $txtPubPath.Text -IsScript $false -QuietMissing }
            else { $lblPubLiveVer.Text = 'Live Gallery Version: Not checked'; Clear-PubMetadataFields -ApplyShareableDefaults $true }
        }
    }
})

$txtPubPath.Add_Leave({
    $typedPath = $txtPubPath.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($typedPath)) {
        $isScript = $rbPubScript.Checked
        $exists = if ($isScript) { Test-Path -LiteralPath $typedPath -PathType Leaf } else { Test-Path -LiteralPath $typedPath -PathType Container }
        if ($exists) {
            Add-PubRecentPackage -Path $typedPath -Type $(if ($isScript) { 'Script' } else { 'Module' })
            Import-PubTargetMetadata -TargetPath $typedPath -IsScript $isScript -QuietMissing
            return
        }
    }
    Save-PubStateToConfig
})

$btnPubBrowse.Add_Click({
    if ($rbPubScript.Checked) {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'PowerShell Scripts (*.ps1)|*.ps1|All Files (*.*)|*.*'
        $dlg.Title = 'Select a PowerShell Script to Publish'
        $cur = $txtPubPath.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($cur)) {
            $pDir = Split-Path $cur -Parent
            if (-not [string]::IsNullOrWhiteSpace($pDir) -and (Test-Path -LiteralPath $pDir -PathType Container)) { $dlg.InitialDirectory = $pDir }
        }
        if ($dlg.ShowDialog() -eq 'OK') {
            $txtPubPath.Text = $dlg.FileName
            Add-PubRecentPackage -Path $dlg.FileName -Type 'Script'
            Write-PubLog "Selected script: $($dlg.FileName)"
            Import-PubTargetMetadata -TargetPath $dlg.FileName -IsScript $true
        }
    }
    else {
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'Select the PowerShell Module Folder (must match your .psd1/.psm1 name)'
        $fbd.ShowNewFolderButton = $false
        $cur = $txtPubPath.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($cur) -and (Test-Path -LiteralPath $cur -PathType Container)) { $fbd.SelectedPath = $cur }
        if ($fbd.ShowDialog() -eq 'OK') {
            $txtPubPath.Text = $fbd.SelectedPath
            Add-PubRecentPackage -Path $fbd.SelectedPath -Type 'Module'
            Write-PubLog "Selected module folder: $($fbd.SelectedPath)"
            Import-PubTargetMetadata -TargetPath $fbd.SelectedPath -IsScript $false
        }
    }
})

$stepPubVersion = {
    param([string]$Part)
    $raw = $txtPubVersion.Text.Trim()
    if ($raw -match '^(\d+)(?:\.(\d+))?(?:\.(\d+))?') {
        $maj = [int]$Matches[1]
        $min = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
        $pat = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        switch ($Part) { 'Major' { $maj++; $min = 0; $pat = 0 } 'Minor' { $min++; $pat = 0 } 'Patch' { $pat++ } }
        $txtPubVersion.Text = "$maj.$min.$pat"
        Write-PubLog "Version bumped ($Part): $raw -> $($txtPubVersion.Text)"
    }
    else {
        $txtPubVersion.Text = '1.0.0'
        Write-PubLog "Invalid version format '$raw'. Reset to 1.0.0." 'WARN'
    }
}
$btnPubBumpMajor.Add_Click({ & $stepPubVersion 'Major' })
$btnPubBumpMinor.Add_Click({ & $stepPubVersion 'Minor' })
$btnPubBumpPatch.Add_Click({ & $stepPubVersion 'Patch' })

$btnPubSaveAuthor.Add_Click({
    $auth = $txtPubAuthor.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($auth)) { [Windows.Forms.MessageBox]::Show('Enter your username first.', 'Empty Author', 'OK', 'Warning') | Out-Null; return }
    $script:Config.Username = $auth
    $txtSetUser.Text = $auth
    $txtPubUser.Text = $auth
    Save-AppConfig
    Update-HeaderStatusBadges
    Write-PubLog "Saved default author '$auth' to shared config.json." 'SUCCESS'
    [Windows.Forms.MessageBox]::Show("Saved '$auth' as your default Author for future sessions.", 'Author Saved', 'OK', 'Information') | Out-Null
})

$btnPubSaveMeta.Add_Click({
    $targetPath = $txtPubPath.Text.Trim()
    $isScript   = $rbPubScript.Checked

    if ($isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        [Windows.Forms.MessageBox]::Show('Please select a valid .ps1 file first.', 'Missing File', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        [Windows.Forms.MessageBox]::Show('Please select a valid module folder first.', 'Missing Folder', 'OK', 'Warning') | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($txtPubDesc.Text)) {
        Write-PubLog 'Cannot save metadata: Description field is empty.' 'WARN'
        [Windows.Forms.MessageBox]::Show('Description cannot be empty. Please enter a description before saving metadata to the file.', 'Empty Description', 'OK', 'Warning') | Out-Null
        $txtPubDesc.Focus()
        return
    }

    if ([string]::IsNullOrWhiteSpace($txtPubVersion.Text) -or [string]::IsNullOrWhiteSpace($txtPubAuthor.Text)) {
        [Windows.Forms.MessageBox]::Show('Version, Author, and Description are required fields.', 'Missing Metadata', 'OK', 'Warning') | Out-Null
        return
    }

    try {
        if ($isScript) {
            Sync-PubScriptMetadata -FilePath $targetPath
            $fileLabel = Split-Path $targetPath -Leaf
        }
        else {
            Sync-PubModuleMetadata -FolderPath $targetPath
            $fileLabel = "$(Split-Path $targetPath -Leaf).psd1"
        }

        $lblPubUploadState.Text = 'Status: Metadata Saved'
        Write-PubLog "Successfully wrote updated metadata to '$fileLabel'." 'SUCCESS'
        [Windows.Forms.MessageBox]::Show("Metadata changes have been written to '$fileLabel'.", 'Metadata Saved', 'OK', 'Information') | Out-Null
    }
    catch {
        $lblPubUploadState.Text = 'Status: Save Failed'
        Write-PubLog "Failed to write metadata: $($_.Exception.Message)" 'ERROR'
        [Windows.Forms.MessageBox]::Show("Failed to save metadata:`n$($_.Exception.Message)", 'Save Error', 'OK', 'Error') | Out-Null
    }
})

$btnPubRepairTls.Add_Click({
    if (-not $script:IsAdmin) {
        [Windows.Forms.MessageBox]::Show('Click Elevate in the top bar first to update .NET TLS registry settings and Gallery modules.', 'Administrator Required', 'OK', 'Warning') | Out-Null; return
    }
    Set-PubUiBusyState -IsBusy $true
    $lblPubUploadState.Text = 'Status: Checking TLS & Tools...'
    [Windows.Forms.Application]::DoEvents()
    try {
        Enable-DotNetStrongCrypto -VerboseOutput | Out-Null
        if (-not (Get-Command Publish-PSResource -ErrorAction SilentlyContinue)) {
            Write-PubLog 'Installing NuGet provider and Microsoft.PowerShell.PSResourceGet...'
            [Windows.Forms.Application]::DoEvents()
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
            Install-Module -Name Microsoft.PowerShell.PSResourceGet -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
            Import-Module Microsoft.PowerShell.PSResourceGet -Force -ErrorAction Stop
            Write-PubLog 'Installed Microsoft.PowerShell.PSResourceGet successfully!' 'SUCCESS'
        }
        else { Write-PubLog 'Microsoft.PowerShell.PSResourceGet is already installed and ready.' 'SUCCESS' }
        $lblPubUploadState.Text = 'Status: Tools Ready'
        [Windows.Forms.MessageBox]::Show('TLS 1.2+ Strong Cryptography and PowerShell Gallery tools are configured and ready!', 'Repair Complete', 'OK', 'Information') | Out-Null
    }
    catch {
        $lblPubUploadState.Text = 'Status: Repair Failed'
        Write-PubLog "TLS / Tool repair failed: $($_.Exception.Message)" 'ERROR'
        [Windows.Forms.MessageBox]::Show("Repair failed:`n$($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
    }
    finally { Set-PubUiBusyState -IsBusy $false }
})

$btnPubCheckLive.Add_Click({
    $targetPath = $txtPubPath.Text.Trim()
    $repo = if ([string]::IsNullOrWhiteSpace($txtPubRepo.Text)) { 'PSGallery' } else { $txtPubRepo.Text.Trim() }
    $isScript = $rbPubScript.Checked
    if ($isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { [Windows.Forms.MessageBox]::Show('Select a valid .ps1 file first.', 'Missing File', 'OK', 'Warning') | Out-Null; return }
    if (-not $isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Container)) { [Windows.Forms.MessageBox]::Show('Select a valid module folder first.', 'Missing Folder', 'OK', 'Warning') | Out-Null; return }

    $pkgName = if ($isScript) { [System.IO.Path]::GetFileNameWithoutExtension($targetPath) } else { Split-Path $targetPath -Leaf }
    Set-PubUiBusyState -IsBusy $true
    $lblPubLiveVer.Text = 'Live Gallery Version: Checking...'
    $lblPubUploadState.Text = "Status: Querying $repo..."
    Write-PubLog "Checking live version of '$pkgName' on $repo..."

    $work = {
        param($name, $repoName, $isScriptPkg)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $versions = @()
        if (Get-Command Find-PSResource -ErrorAction SilentlyContinue) {
            try { foreach ($i in @(Find-PSResource -Name $name -Repository $repoName -ErrorAction Stop)) { if ($i.Version) { $versions += [version]$i.Version } } }
            catch { if ($_.Exception.Message -notmatch 'not found|No match|could not be found') { throw } }
        }
        elseif ($repoName -ieq 'PSGallery') {
            $feed = Invoke-RestMethod -Uri "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='$([Uri]::EscapeDataString($name))'" -Method Get -TimeoutSec 15 -ErrorAction Stop
            foreach ($e in @($feed)) {
                $vProp = $e.PSObject.Properties['properties']
                if ($null -ne $vProp -and $null -ne $vProp.Value) {
                    $verVal = $vProp.Value.PSObject.Properties['Version']
                    if ($null -ne $verVal -and ([string]$verVal.Value -match '^(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)')) { $versions += [version]$Matches[1] }
                }
            }
        }
        elseif ($isScriptPkg) {
            try { $r = Find-Script -Name $name -Repository $repoName -ErrorAction Stop; if ($r -and $r.Version) { $versions += [version]$r.Version } } catch { }
        }
        else {
            try { $r = Find-Module -Name $name -Repository $repoName -ErrorAction Stop; if ($r -and $r.Version) { $versions += [version]$r.Version } } catch { }
        }
        if ($versions.Count -eq 0) { return '' }
        return ($versions | Sort-Object -Descending | Select-Object -First 1).ToString()
    }

    Invoke-AsyncTask -Work $work -ArgumentList @($pkgName, $repo, $isScript) -State @{ PkgName = $pkgName; Repo = $repo } -OnComplete {
        param($res, $err, $state)
        Set-PubUiBusyState -IsBusy $false
        if ($err) {
            $lblPubLiveVer.Text = 'Live Gallery Version: Lookup failed'
            $lblPubUploadState.Text = 'Status: Lookup Failed'
            Write-PubLog "Live version lookup failed: $err" 'ERROR'
            return
        }
        $liveVerStr = ($res | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($liveVerStr)) {
            $lblPubLiveVer.Text = 'Live Gallery Version: Not published yet'
            $lblPubUploadState.Text = 'Status: New Package'
            Write-PubLog "Package '$($state.PkgName)' not found on $($state.Repo) (ready for initial publish)." 'INFO'
            return
        }
        $liveVer  = [version]$liveVerStr
        $localRaw = $txtPubVersion.Text.Trim()
        $localVer = if ($localRaw -match '^(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') { [version]$Matches[1] } else { [version]'0.0.0' }
        if ($localVer -gt $liveVer) {
            $lblPubLiveVer.Text = "Live Gallery Version: v$liveVer (OK)"
            $lblPubUploadState.Text = 'Status: Version OK'
            Write-PubLog "Version check PASSED: Local v$localVer > live v$liveVer." 'SUCCESS'
        }
        else {
            $lblPubLiveVer.Text = "Live Gallery Version: v$liveVer (Bump needed!)"
            $lblPubUploadState.Text = 'Status: Version Conflict'
            Write-PubLog "Version WARNING: Local v$localVer <= live v$liveVer on $($state.Repo)!" 'WARN'
            $base = if ($liveVer -ge $localVer) { $liveVer } else { $localVer }
            $nextPatch = if ($base.Build -ge 0) { $base.Build + 1 } else { 1 }
            $suggested = "$($base.Major).$($base.Minor).$nextPatch"
            if ([Windows.Forms.MessageBox]::Show("'$($state.PkgName)' is already at v$liveVer on $($state.Repo). Auto-bump local version to v$suggested now?", 'Live Version Warning', 'YesNo', 'Warning') -eq 'Yes') {
                $txtPubVersion.Text = $suggested
                $lblPubLiveVer.Text = "Live Gallery Version: v$liveVer (OK)"
                $lblPubUploadState.Text = "Status: Bumped to v$suggested"
                Write-PubLog "Auto-bumped local version to v$suggested." 'SUCCESS'
            }
        }
    }
})

$btnPubValidate.Add_Click({
    $targetPath = $txtPubPath.Text.Trim()
    $isScript   = $rbPubScript.Checked
    if ($isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { [Windows.Forms.MessageBox]::Show('Select a valid .ps1 file first.', 'Missing File', 'OK', 'Warning') | Out-Null; return }
    if (-not $isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Container)) { [Windows.Forms.MessageBox]::Show('Select a valid module folder first.', 'Missing Folder', 'OK', 'Warning') | Out-Null; return }

    Add-PubRecentPackage -Path $targetPath -Type $(if ($isScript) { 'Script' } else { 'Module' })
    try {
        if ($chkPubAutoMeta.Checked) {
            if ([string]::IsNullOrWhiteSpace($txtPubDesc.Text) -or [string]::IsNullOrWhiteSpace($txtPubVersion.Text) -or [string]::IsNullOrWhiteSpace($txtPubAuthor.Text)) {
                throw 'Version, Author, and Description are required fields.'
            }
            if ($isScript) { Sync-PubScriptMetadata -FilePath $targetPath } else { Sync-PubModuleMetadata -FolderPath $targetPath }
        }
        if ($isScript) {
            $r = if (Get-Command Test-PSScriptFileInfo -ErrorAction SilentlyContinue) { Test-PSScriptFileInfo -Path $targetPath -ErrorAction Stop } else { Test-ScriptFileInfo -Path $targetPath -ErrorAction Stop }
            $rName = Get-SafeProp -Obj $r -Name 'Name' -Default (Split-Path $targetPath -Leaf)
            $rVer  = Get-SafeProp -Obj $r -Name 'Version' -Default $txtPubVersion.Text
            $rAuth = Get-SafeProp -Obj $r -Name 'Author' -Default $txtPubAuthor.Text
            Write-PubLog "Script validation PASSED: $rName v$rVer by $rAuth" 'SUCCESS'
        }
        else {
            $modName = Split-Path $targetPath -Leaf
            $mPath = Join-Path $targetPath "$modName.psd1"
            if (-not (Test-Path -LiteralPath $mPath -PathType Leaf)) { throw "Expected manifest '$modName.psd1' not found." }
            $r = Test-ModuleManifest -Path $mPath -ErrorAction Stop
            Write-PubLog "Module validation PASSED: $($r.Name) v$($r.Version) by $($r.Author)" 'SUCCESS'
        }
        $lblPubUploadState.Text = 'Status: Validated'
        [Windows.Forms.MessageBox]::Show('Metadata is valid and ready for PowerShell Gallery!', 'Validation Passed', 'OK', 'Information') | Out-Null
    }
    catch {
        $lblPubUploadState.Text = 'Status: Validation Failed'
        Write-PubLog "Validation FAILED: $($_.Exception.Message)" 'ERROR'
        [Windows.Forms.MessageBox]::Show("Validation failed:`n$($_.Exception.Message)", 'Validation Error', 'OK', 'Error') | Out-Null
    }
})

$pubUploadTimer = New-Object System.Windows.Forms.Timer
$pubUploadTimer.Interval = 250
$pubUploadTimer.Add_Tick({
    $job = $script:PublishJob
    if (-not $job) { $pubUploadTimer.Stop(); return }

    $infoStream = $job.Instance.Streams.Information
    while ($job.InfoIdx -lt $infoStream.Count) { Write-PubLog ($infoStream[$job.InfoIdx].ToString()) 'INFO'; $job.InfoIdx++ }
    $warnStream = $job.Instance.Streams.Warning
    while ($job.WarnIdx -lt $warnStream.Count) { Write-PubLog ($warnStream[$job.WarnIdx].Message) 'WARN'; $job.WarnIdx++ }

    $elapsed = [int]((Get-Date) - $job.StartTime).TotalSeconds
    $lblPubUploadState.Text = "Status: Uploading to $($job.Repo)... (${elapsed}s)"

    if ($job.AsyncResult.IsCompleted) {
        $pubUploadTimer.Stop()
        while ($job.InfoIdx -lt $infoStream.Count) { Write-PubLog ($infoStream[$job.InfoIdx].ToString()) 'INFO'; $job.InfoIdx++ }
        while ($job.WarnIdx -lt $warnStream.Count) { Write-PubLog ($warnStream[$job.WarnIdx].Message) 'WARN'; $job.WarnIdx++ }

        try {
            if ($job.Cancelled) {
                $lblPubUploadState.Text = 'Status: Cancelled'
                Write-PubLog 'Upload cancelled by user.' 'WARN'
            }
            else {
                [void]$job.Instance.EndInvoke($job.AsyncResult)
                if ($job.Instance.HadErrors -or $job.Instance.Streams.Error.Count -gt 0) {
                    throw $job.Instance.Streams.Error[0].Exception.Message
                }
                if ([string]::IsNullOrWhiteSpace($script:Config.Username) -and -not [string]::IsNullOrWhiteSpace($job.PublishedAuthor)) {
                    $script:Config.Username = $job.PublishedAuthor
                    $txtSetUser.Text = $job.PublishedAuthor
                    $txtPubUser.Text = $job.PublishedAuthor
                    Update-HeaderStatusBadges
                }
                Save-PubStateToConfig
                $lblPubLiveVer.Text = "Live Gallery Version: v$($job.PublishedVersion) (OK)"
                $lblPubUploadState.Text = 'Status: Upload Complete!'
                Write-PubLog "Successfully published $($job.TypeLabel) '$($job.PackageName)' v$($job.PublishedVersion) to $($job.Repo)! (${elapsed}s)" 'SUCCESS'
                Write-PubLog "Gallery URL: https://www.powershellgallery.com/packages/$($job.PackageName)" 'INFO'
                [Windows.Forms.MessageBox]::Show("Published $($job.TypeLabel) '$($job.PackageName)' (v$($job.PublishedVersion)) successfully to $($job.Repo)!", 'Upload Complete', 'OK', 'Information') | Out-Null
            }
        }
        catch {
            $lblPubUploadState.Text = 'Status: Publish Failed'
            Write-PubLog "Publish FAILED: $($_.Exception.Message)" 'ERROR'
            [Windows.Forms.MessageBox]::Show("Failed to publish $($job.TypeLabel):`n$($_.Exception.Message)", 'Publish Error', 'OK', 'Error') | Out-Null
        }
        finally {
            $job.Instance.Dispose()
            $script:PublishJob = $null
            Set-PubUiBusyState -IsBusy $false
        }
    }
})

$btnPubCancel.Add_Click({
    if ($script:PublishJob -and -not $script:PublishJob.Cancelled) {
        $script:PublishJob.Cancelled = $true
        $lblPubUploadState.Text = 'Status: Cancelling...'
        Write-PubLog 'Stopping background upload task...' 'WARN'
        try { $script:PublishJob.Instance.BeginStop($null, $null) | Out-Null } catch { }
    }
})

$btnPubPublish.Add_Click({
    $targetPath = $txtPubPath.Text.Trim()
    $apiKey     = Get-ProtectedApiKey
    $repo       = if ([string]::IsNullOrWhiteSpace($txtPubRepo.Text)) { 'PSGallery' } else { $txtPubRepo.Text.Trim() }
    $isScript   = $rbPubScript.Checked

    if ($isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { [Windows.Forms.MessageBox]::Show('Select a valid .ps1 script file.', 'Missing File', 'OK', 'Warning') | Out-Null; return }
    if (-not $isScript -and -not (Test-Path -LiteralPath $targetPath -PathType Container)) { [Windows.Forms.MessageBox]::Show('Select a valid module folder.', 'Missing Folder', 'OK', 'Warning') | Out-Null; return }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        [Windows.Forms.MessageBox]::Show('No DPAPI-encrypted API key found. Please enter and save your PowerShell Gallery API key in Settings & Keys first.', 'Missing API Key', 'OK', 'Warning') | Out-Null
        Switch-MainTab 'Settings'; return
    }
    if ([string]::IsNullOrWhiteSpace($txtPubAuthor.Text) -or [string]::IsNullOrWhiteSpace($txtPubDesc.Text) -or [string]::IsNullOrWhiteSpace($txtPubVersion.Text)) {
        [Windows.Forms.MessageBox]::Show('Version, Author, and Description are required fields.', 'Missing Metadata', 'OK', 'Warning') | Out-Null; return
    }

    Add-PubRecentPackage -Path $targetPath -Type $(if ($isScript) { 'Script' } else { 'Module' })
    $pkgName    = if ($isScript) { [System.IO.Path]::GetFileNameWithoutExtension($targetPath) } else { Split-Path $targetPath -Leaf }
    $typeLabel  = if ($isScript) { 'script' } else { 'module' }
    $targetVer  = $txtPubVersion.Text.Trim()
    $targetAuth = $txtPubAuthor.Text.Trim()

    if ([Windows.Forms.MessageBox]::Show("Publish $typeLabel '$pkgName' (v$targetVer) to '$repo'?", 'Confirm Publish', 'YesNo', 'Question') -ne 'Yes') { return }

    Set-PubUiBusyState -IsBusy $true -AllowCancel $true
    $lblPubUploadState.Text = 'Status: Validating...'

    try {
        Enable-DotNetStrongCrypto | Out-Null
        if ($chkPubAutoMeta.Checked) {
            if ($isScript) { Sync-PubScriptMetadata -FilePath $targetPath } else { Sync-PubModuleMetadata -FolderPath $targetPath }
        }
        Write-PubLog "Validating $typeLabel '$pkgName' before upload..."
        if ($isScript) {
            if (Get-Command Test-PSScriptFileInfo -ErrorAction SilentlyContinue) { Test-PSScriptFileInfo -Path $targetPath -ErrorAction Stop | Out-Null }
            else { Test-ScriptFileInfo -Path $targetPath -ErrorAction Stop | Out-Null }
        }
        else {
            Test-ModuleManifest -Path (Join-Path $targetPath "$pkgName.psd1") -ErrorAction Stop | Out-Null
        }

        Write-PubLog "Starting background upload of $typeLabel '$pkgName' to $repo..."
        $psInst = [PowerShell]::Create()
        [void]$psInst.AddScript({
            param($PathArg, $KeyArg, $RepoArg, $IsScriptArg)
            $ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; $ConfirmPreference = 'None'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            if (Get-Command Publish-PSResource -ErrorAction SilentlyContinue) {
                Write-Information 'Publishing via PSResourceGet (Publish-PSResource)...' -InformationAction Continue
                Publish-PSResource -Path $PathArg -ApiKey $KeyArg -Repository $RepoArg -Confirm:$false -ErrorAction Stop
            }
            elseif ($IsScriptArg) {
                Write-Information 'Publishing script via PowerShellGet (Publish-Script)...' -InformationAction Continue
                Publish-Script -Path $PathArg -NuGetApiKey $KeyArg -Repository $RepoArg -Force -Confirm:$false -ErrorAction Stop
            }
            else {
                Write-Information 'Publishing module via PowerShellGet (Publish-Module)...' -InformationAction Continue
                Publish-Module -Path $PathArg -NuGetApiKey $KeyArg -Repository $RepoArg -Force -Confirm:$false -ErrorAction Stop
            }
        })
        [void]$psInst.AddArgument($targetPath); [void]$psInst.AddArgument($apiKey); [void]$psInst.AddArgument($repo); [void]$psInst.AddArgument($isScript)

        $script:PublishJob = @{
            Instance = $psInst; AsyncResult = $psInst.BeginInvoke(); StartTime = Get-Date
            PackageName = $pkgName; TypeLabel = $typeLabel; Repo = $repo
            PublishedAuthor = $targetAuth; PublishedVersion = $targetVer
            InfoIdx = 0; WarnIdx = 0; Cancelled = $false
        }
        $pubUploadTimer.Start()
    }
    catch {
        $lblPubUploadState.Text = 'Status: Failed'
        Write-PubLog "Publish FAILED: $($_.Exception.Message)" 'ERROR'
        [Windows.Forms.MessageBox]::Show("Failed to publish ${typeLabel}:`n$($_.Exception.Message)", 'Publish Error', 'OK', 'Error') | Out-Null
        Set-PubUiBusyState -IsBusy $false
    }
})

# ==============================================================================
# 15. SETTINGS EVENTS & INITIALIZATION
# ==============================================================================
$btnToggleApi.Add_Click({
    $txtSetApiKey.UseSystemPasswordChar = (-not $txtSetApiKey.UseSystemPasswordChar)
    $btnToggleApi.Text = if ($txtSetApiKey.UseSystemPasswordChar) { 'Show' } else { 'Hide' }
})

$btnClearApi.Add_Click({
    $txtSetApiKey.Text = ''
    Save-ProtectedApiKey -PlainApiKey ''
    Update-HeaderStatusBadges
    $lblStatus.Text = 'DPAPI-encrypted API key deleted from disk.'
})

$btnBrowseSave.Add_Click({
    $fbd = New-Object Windows.Forms.FolderBrowserDialog
    if (Test-Path -LiteralPath $txtSetSavePath.Text) { $fbd.SelectedPath = $txtSetSavePath.Text }
    if ($fbd.ShowDialog() -eq 'OK') { $txtSetSavePath.Text = $fbd.SelectedPath }
})

$btnSaveSettings.Add_Click({
    $script:Config.Username            = $txtSetUser.Text.Trim()
    $script:Config.DefaultSavePath     = $txtSetSavePath.Text.Trim()
    $script:Config.PreferredScope      = [string]$cmbSetScope.SelectedItem
    $script:Config.PubDefaultCompany   = $txtSetDefaultCompany.Text.Trim()
    $script:Config.PubDefaultCopyright = $txtSetDefaultCopyright.Text.Trim()
    $script:Config.AutoElevate         = [bool]$chkAutoElevate.Checked

    Save-AppConfig
    Save-ProtectedApiKey -PlainApiKey $txtSetApiKey.Text

    $txtPubUser.Text   = $script:Config.Username
    $txtPubAuthor.Text = $script:Config.Username
    if ([string]::IsNullOrWhiteSpace($txtPubCompany.Text))   { $txtPubCompany.Text   = $script:Config.PubDefaultCompany }
    if ([string]::IsNullOrWhiteSpace($txtPubCopyright.Text)) { $txtPubCopyright.Text = $script:Config.PubDefaultCopyright }

    Update-HeaderStatusBadges
    $lblStatus.Text = 'Configuration saved to config.json and API key encrypted via Windows DPAPI.'
    [Windows.Forms.MessageBox]::Show('Settings saved and API key encrypted with Windows DPAPI.', 'Saved', 'OK', 'Information') | Out-Null
})

$form.Add_FormClosed({
    Save-PubStateToConfig
    $pubUploadTimer.Stop()
    $pubUploadTimer.Dispose()
    if ($script:PublishJob) { try { $script:PublishJob.Instance.Dispose() } catch { } }
})

foreach ($cb in @($cmbTheme, $cmbCategory, $cmbItemType, $cmbSort, $cmbSetScope, $cmbPubRecent)) {
    Initialize-ThemedComboBox -ComboBox $cb
}
foreach ($grp in @($grpPubTarget, $grpPubMeta)) {
    Initialize-ThemedGroupBox -GroupBox $grp
}

$txtPubRepo.Text        = $script:Config.PubRepository
$txtPubAuthor.Text      = $script:Config.Username
$txtPubCompany.Text     = $script:Config.PubDefaultCompany
$txtPubCopyright.Text   = $script:Config.PubDefaultCopyright
$txtPubTags.Text        = $script:Config.PubDefaultTags
$txtPubProjUri.Text     = $script:Config.PubDefaultProjUri
$txtPubLicUri.Text      = $script:Config.PubDefaultLicUri
$chkPubAutoMeta.Checked = [bool]$script:Config.PubAutoInjectMeta

if ($script:Config.PubPackageType -eq 'Module') {
    $rbPubModule.Checked = $true
    $lblPubPath.Text = 'Module Folder:'
    $txtPubPath.Text = $script:Config.PubLastModulePath
}
else {
    $rbPubScript.Checked = $true
    $lblPubPath.Text = 'Script (.ps1):'
    $txtPubPath.Text = $script:Config.PubLastScriptPath
}

Refresh-PubRecentDropdown -SelectPath $txtPubPath.Text
$script:IsInitializing = $false
if ($script:ConfigNeedsUpgrade) {
    Save-AppConfig
}

Switch-MainTab 'Discover'
Switch-MySubTab 'Published'
Apply-Theme
Enable-DotNetStrongCrypto | Out-Null

$form.Add_Shown({
    $form.WindowState = 'Normal'
    if ($script:HasWin32) {
        try {
            [void][PSGalWin32]::ShowWindow($form.Handle, 5)
            [PSGalWin32]::SetDarkTitleBar($form.Handle, (Get-ThemePalette).IsDark)
        }
        catch { }
    }
    $form.TopMost = $true
    $form.Activate()
    $form.TopMost = $false

    if (-not [string]::IsNullOrWhiteSpace($txtPubPath.Text)) {
        Import-PubTargetMetadata -TargetPath $txtPubPath.Text.Trim() -IsScript $rbPubScript.Checked -QuietMissing
    }
    Write-PubLog "Publisher ready (PS $($PSVersionTable.PSVersion))."
    if ([string]::IsNullOrWhiteSpace($script:Config.Username)) {
        $lblStatus.Text = 'Tip: Configure your PowerShell Gallery username and DPAPI API key in Settings & Keys.'
    }
    Invoke-GallerySearch -PageIndex 0
})

[void]$form.ShowDialog()

}
catch {
    $errDetails = "PSGallery Manager failed to start:`n`n$($_.Exception.Message)`n`nLocation: $($_.InvocationInfo.PositionMessage)"
    [System.Windows.Forms.MessageBox]::Show($errDetails, 'PSGallery Manager Startup Error', 'OK', 'Error') | Out-Null
}

