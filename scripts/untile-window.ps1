# owl.nvim — restore the terminal to its pre-tile geometry.
# Reads the marker file written by tile-window.ps1 and either
# maximises the terminal (if it was maximised before) or places it at
# its original rect. Also kills the tracked browser process, if any.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$NvimPid,
    [switch]$KillBrowser
)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class OwlUntile {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@

$SW_SHOWNORMAL  = 1
$SW_MAXIMIZE    = 3
$SWP_SHOWWINDOW = 0x0040
$HWND_TOP       = [IntPtr]::Zero

$markerPath = Join-Path $env:TEMP ("owl-preview-" + $NvimPid + "\term.state.json")
if (-not (Test-Path $markerPath)) {
    Write-Output "OWL_UNTILE_STATUS=no-marker"
    return
}

try {
    $state = Get-Content $markerPath -Raw | ConvertFrom-Json
} catch {
    Write-Output "OWL_UNTILE_STATUS=parse-failed"
    return
}

# Kill the browser first (before restoring the terminal, so the terminal
# lands on top instead of hiding behind an empty browser window).
if ($KillBrowser -and $state.BrowserPid) {
    Stop-Process -Id $state.BrowserPid -Force -ErrorAction SilentlyContinue
}

# Restore the terminal.
$termHwnd = [IntPtr]::new([int64]$state.Hwnd)
if (-not [OwlUntile]::IsWindow($termHwnd)) {
    Write-Output "OWL_UNTILE_STATUS=window-gone"
    Remove-Item $markerPath -ErrorAction SilentlyContinue
    return
}

if ($state.WasMax) {
    [OwlUntile]::ShowWindow($termHwnd, $SW_MAXIMIZE) | Out-Null
} else {
    $x = [int]$state.Left
    $y = [int]$state.Top
    $w = [int]($state.Right  - $state.Left)
    $h = [int]($state.Bottom - $state.Top)
    [OwlUntile]::ShowWindow($termHwnd, $SW_SHOWNORMAL) | Out-Null
    [OwlUntile]::SetWindowPos($termHwnd, $HWND_TOP, $x, $y, $w, $h, $SWP_SHOWWINDOW) | Out-Null
}

# Focus back to the terminal
[OwlUntile]::SetForegroundWindow($termHwnd) | Out-Null

Remove-Item $markerPath -ErrorAction SilentlyContinue
Write-Output "OWL_UNTILE_STATUS=ok"
