# owl.nvim — one-shot window tiling.
# Called from Lua (native Windows) or from WSL (via powershell.exe).
# Positions the terminal on one half of the screen and the browser on the other.
# Detects the user's default browser and prefers Chromium --app mode when possible.
# NO polling. NO focus enforcement after the initial launch.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][int]$NvimPid,
    [ValidateSet('left', 'right')][string]$BrowserSide = 'right',
    [int]$BrowserPercent = 50
)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class OwlWin {
    [DllImport("user32.dll")]  public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]  public static extern bool  SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")]  public static extern bool  SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int cy, uint f);
    [DllImport("user32.dll")]  public static extern bool  ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")]  public static extern bool  IsIconic(IntPtr h);
}
'@

$SW_RESTORE      = 9
$SWP_SHOWWINDOW  = 0x0040
$HWND_TOP        = [IntPtr]::Zero

# --------------------------------------------------------------------
# Grab the terminal handle BEFORE anything else can steal focus.
# --------------------------------------------------------------------
$termHwnd = [OwlWin]::GetForegroundWindow()
if ([OwlWin]::IsIconic($termHwnd)) { [OwlWin]::ShowWindow($termHwnd, $SW_RESTORE) | Out-Null }

# --------------------------------------------------------------------
# Compute halves against primary monitor's working area.
# --------------------------------------------------------------------
$area  = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$halfW = [int]($area.Width * $BrowserPercent / 100)
$termW = $area.Width - $halfW
if ($BrowserSide -eq 'right') {
    $termX    = $area.X
    $browserX = $area.X + $termW
} else {
    $browserX = $area.X
    $termX    = $area.X + $halfW
}
$y = $area.Y
$h = $area.Height

# --------------------------------------------------------------------
# Position the terminal (once)
# --------------------------------------------------------------------
[OwlWin]::SetWindowPos($termHwnd, $HWND_TOP, $termX, $y, $termW, $h, $SWP_SHOWWINDOW) | Out-Null

# --------------------------------------------------------------------
# Detect default browser from Windows registry
# --------------------------------------------------------------------
function Get-DefaultBrowserExe {
    $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
    if (-not $progId) { return $null }
    $key = "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command"
    $cmd = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'(default)'
    if (-not $cmd) { return $null }
    if ($cmd -match '^"([^"]+)"')  { return $Matches[1] }
    if ($cmd -match '^(\S+\.exe)') { return $Matches[1] }
    return $null
}

$exe     = Get-DefaultBrowserExe
$exeName = if ($exe) { [System.IO.Path]::GetFileName($exe).ToLower() } else { '' }

# Chromium family supports --app + --window-position/size at launch
$isChromium = $exeName -match '^(chrome|msedge|edge|brave|chromium|vivaldi|opera|opera_gx|thorium)\.exe$'

$dataDir = Join-Path $env:TEMP ("owl-preview-" + $NvimPid)

# --------------------------------------------------------------------
# Launch the browser
# --------------------------------------------------------------------
$launched = $null

if ($exe -and (Test-Path $exe)) {
    if ($isChromium) {
        $args = @(
            "--app=$Url",
            "--window-position=$browserX,$y",
            "--window-size=$halfW,$h",
            "--user-data-dir=$dataDir",
            "--no-first-run",
            "--no-default-browser-check"
        )
        $launched = Start-Process -FilePath $exe -ArgumentList $args -PassThru
    } else {
        # Firefox / Safari-for-Windows / other: open then reposition manually
        $launched = Start-Process -FilePath $exe -ArgumentList $Url -PassThru
        # wait for the main window to materialize (up to ~1.5s)
        $tries = 0
        while ($tries -lt 15 -and (-not $launched.MainWindowHandle -or $launched.MainWindowHandle -eq 0)) {
            Start-Sleep -Milliseconds 100
            $launched.Refresh()
            $tries++
        }
        if ($launched.MainWindowHandle -ne 0) {
            [OwlWin]::SetWindowPos($launched.MainWindowHandle, $HWND_TOP, $browserX, $y, $halfW, $h, $SWP_SHOWWINDOW) | Out-Null
        }
    }
} else {
    # Absolute fallback: shell-open the URL, no positioning
    Start-Process $Url
}

# --------------------------------------------------------------------
# Return focus to the terminal — ONE shot, then exit.
# --------------------------------------------------------------------
Start-Sleep -Milliseconds 350
[OwlWin]::SetForegroundWindow($termHwnd) | Out-Null

# Print marker so the Lua side can identify the child process for later cleanup.
if ($launched -and $launched.Id) {
    Write-Output ("OWL_BROWSER_PID=" + $launched.Id)
}
Write-Output ("OWL_DATA_DIR=" + $dataDir)
