[CmdletBinding()]
param(
    [int]$ClickX = 100,
    [int]$ClickY = 100,

    [int]$RectX = 0,
    [int]$RectY = 0,
    [int]$RectWidth = 800,
    [int]$RectHeight = 600,

    [int]$Count = 5,

    [int]$DelayAfterClickMs = 1000,
    [int]$IntervalBetweenRunsMs = 1000,

    [ValidateSet('Left','Right')]
    [string]$ClickType = 'Left',

    [switch]$DoubleClick,

    # output in current folder\Screenshots by default
    [string]$OutputDir = (Join-Path -Path (Get-Location) -ChildPath "screenshots")
)

# Reference Win32 APIs: SetCursorPos and mouse_event
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;

public static class User32
{
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@

# Enable DPI awareness for accurate coordinates
[User32]::SetProcessDPIAware()

Start-Sleep -Milliseconds 2000

# Mouse event flags
$MOUSEEVENTF_LEFTDOWN  = 0x0002
$MOUSEEVENTF_LEFTUP    = 0x0004
$MOUSEEVENTF_RIGHTDOWN = 0x0008
$MOUSEEVENTF_RIGHTUP   = 0x0010

function Invoke-MouseClick {
    param(
        [int]$X,
        [int]$Y,
        [ValidateSet('Left','Right')][string]$Type = 'Left',
        [switch]$Double
    )

    # Move cursor to the specified coordinates
    [User32]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 50

    # Trigger click
    switch ($Type) {
        'Left' {
            [User32]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            [User32]::mouse_event($MOUSEEVENTF_LEFTUP,   0, 0, 0, [UIntPtr]::Zero)
            if ($Double) {
                Start-Sleep -Milliseconds 100
                [User32]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
                [User32]::mouse_event($MOUSEEVENTF_LEFTUP,   0, 0, 0, [UIntPtr]::Zero)
            }
        }
        'Right' {
            [User32]::mouse_event($MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            [User32]::mouse_event($MOUSEEVENTF_RIGHTUP,   0, 0, 0, [UIntPtr]::Zero)
            if ($Double) {
                Start-Sleep -Milliseconds 100
                [User32]::mouse_event($MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
                [User32]::mouse_event($MOUSEEVENTF_RIGHTUP,   0, 0, 0, [UIntPtr]::Zero)
            }
        }
    }
}

# Capture the specified screen region
Add-Type -AssemblyName System.Drawing

function Save-ScreenRegion {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [string]$Path
    )
    $bmp = New-Object System.Drawing.Bitmap $Width, $Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)

    # Copy from screen to bitmap
    $gfx.CopyFromScreen($X, $Y, 0, 0, $bmp.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)

    # Clean up
    $gfx.Dispose()
    $bmp.Dispose()
}

# Ensure output directory exists
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "=== Auto Click + Region Screenshot Start ==="
Write-Host "Click coordinates: ($ClickX, $ClickY); Type: $ClickType; Double: $($DoubleClick.IsPresent)"
Write-Host "Capture region: X=$RectX, Y=$RectY, W=$RectWidth, H=$RectHeight"
Write-Host "Iterations: $Count; Delay after click: ${DelayAfterClickMs}ms; Interval between runs: ${IntervalBetweenRunsMs}ms"
Write-Host "Output directory: $OutputDir"
Write-Host "Press Ctrl + C to abort"

for ($i = 1; $i -le $Count; $i++) {
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
        $fileName  = "capture_{0:000}_$timestamp.png" -f $i
        $filePath  = Join-Path $OutputDir $fileName

        Save-ScreenRegion -X $RectX -Y $RectY -Width $RectWidth -Height $RectHeight -Path $filePath
        if ($IntervalBetweenRunsMs -gt 0) {
            Start-Sleep -Milliseconds $IntervalBetweenRunsMs
        }

        Invoke-MouseClick -X $ClickX -Y $ClickY -Type $ClickType -Double:$DoubleClick
        Start-Sleep -Milliseconds $DelayAfterClickMs
    }
       catch {
        Write-Warning "Error on iteration ${i}: $($_.Exception.Message)"
    }
}