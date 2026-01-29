# Visual Screenshot Area Selector + Click Position Picker
# Step 1: Click and drag to select the screenshot region
# Step 2: Click to select the click position
# The selected coordinates will be displayed and copied to clipboard

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enable DPI awareness to get actual screen resolution
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DpiAwareness {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
    public const int SW_MINIMIZE = 6;
    public const int SW_RESTORE = 9;
    
    public static int GetScreenWidth() {
        return GetSystemMetrics(SM_CXSCREEN);
    }
    
    public static int GetScreenHeight() {
        return GetSystemMetrics(SM_CYSCREEN);
    }
    
    public static void MinimizeConsole() {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd != IntPtr.Zero) {
            ShowWindow(hWnd, SW_MINIMIZE);
        }
    }
    
    public static void RestoreConsole() {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd != IntPtr.Zero) {
            ShowWindow(hWnd, SW_RESTORE);
        }
    }
}
"@

# Set DPI awareness before getting screen info
[DpiAwareness]::SetProcessDPIAware()

# Minimize console window before taking screenshot
[DpiAwareness]::MinimizeConsole()
Start-Sleep -Milliseconds 2000

# Get actual screen dimensions using Win32 API
$minX = 0
$minY = 0
$totalWidth = [DpiAwareness]::GetScreenWidth()
$totalHeight = [DpiAwareness]::GetScreenHeight()

# Capture the entire screen first (for the background)
$screenBitmap = New-Object System.Drawing.Bitmap($totalWidth, $totalHeight)
$graphics = [System.Drawing.Graphics]::FromImage($screenBitmap)
$graphics.CopyFromScreen($minX, $minY, 0, 0, $screenBitmap.Size)
$graphics.Dispose()

# Create dimmed version
$dimmedBitmap = New-Object System.Drawing.Bitmap($totalWidth, $totalHeight)
$dimGraphics = [System.Drawing.Graphics]::FromImage($dimmedBitmap)
$dimGraphics.DrawImage($screenBitmap, 0, 0)
$dimBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
$dimGraphics.FillRectangle($dimBrush, 0, 0, $totalWidth, $totalHeight)
$dimBrush.Dispose()
$dimGraphics.Dispose()

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Screenshot Area Selector"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location = New-Object System.Drawing.Point($minX, $minY)
$form.Size = New-Object System.Drawing.Size($totalWidth, $totalHeight)
$form.TopMost = $true
$form.Cursor = [System.Windows.Forms.Cursors]::Cross
$form.ShowInTaskbar = $false
# Enable double buffering via reflection (DoubleBuffered is a protected property)
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($form, $true, $null)

# Variables for selection
$script:isSelecting = $false
$script:startPoint = $null
$script:endPoint = $null
$script:selectedRect = $null
$script:cancelled = $false

# Picture box for drawing
$pictureBox = New-Object System.Windows.Forms.PictureBox
$pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$pictureBox.Image = $dimmedBitmap
$pictureBox.Cursor = [System.Windows.Forms.Cursors]::Cross
$form.Controls.Add($pictureBox)

# Info panel
$infoPanel = New-Object System.Windows.Forms.Panel
$infoPanel.Size = New-Object System.Drawing.Size(350, 160)
$infoPanel.Location = New-Object System.Drawing.Point(20, 20)
$infoPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 30, 30, 30)
$form.Controls.Add($infoPanel)
$infoPanel.BringToFront()

# Title
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "SCREENSHOT AREA SELECTOR"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 200, 255)
$titleLabel.Location = New-Object System.Drawing.Point(15, 10)
$titleLabel.AutoSize = $true
$infoPanel.Controls.Add($titleLabel)

# Size label
$sizeLabel = New-Object System.Windows.Forms.Label
$sizeLabel.Text = "Click and drag to select area"
$sizeLabel.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$sizeLabel.ForeColor = [System.Drawing.Color]::White
$sizeLabel.Location = New-Object System.Drawing.Point(15, 45)
$sizeLabel.AutoSize = $true
$infoPanel.Controls.Add($sizeLabel)

# Position label
$posLabel = New-Object System.Windows.Forms.Label
$posLabel.Text = ""
$posLabel.Font = New-Object System.Drawing.Font("Consolas", 11)
$posLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 200, 200)
$posLabel.Location = New-Object System.Drawing.Point(15, 75)
$posLabel.AutoSize = $true
$infoPanel.Controls.Add($posLabel)

# Instructions
$instructLabel = New-Object System.Windows.Forms.Label
$instructLabel.Text = "Drag: Select area | ESC: Cancel | Enter: Confirm"
$instructLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$instructLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 150, 150, 150)
$instructLabel.Location = New-Object System.Drawing.Point(15, 120)
$instructLabel.AutoSize = $true
$infoPanel.Controls.Add($instructLabel)

# Function to draw the selection
function Update-Selection {
    param($startX, $startY, $endX, $endY)
    
    # Calculate rectangle (handle any drag direction)
    $rectX = [Math]::Min($startX, $endX)
    $rectY = [Math]::Min($startY, $endY)
    $rectW = [Math]::Abs($endX - $startX)
    $rectH = [Math]::Abs($endY - $startY)
    
    # Create new composite image
    $compositeBitmap = New-Object System.Drawing.Bitmap($totalWidth, $totalHeight)
    $g = [System.Drawing.Graphics]::FromImage($compositeBitmap)
    
    # Draw dimmed background
    $g.DrawImage($dimmedBitmap, 0, 0)
    
    # Draw clear selected area (show original screenshot)
    if ($rectW -gt 0 -and $rectH -gt 0) {
        $srcRect = New-Object System.Drawing.Rectangle($rectX, $rectY, $rectW, $rectH)
        $g.DrawImage($screenBitmap, $rectX, $rectY, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        
        # Draw selection border
        $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 0, 174, 255), 2)
        $g.DrawRectangle($borderPen, $rectX, $rectY, $rectW, $rectH)
        $borderPen.Dispose()
        
        # Draw corner handles
        $handleSize = 8
        $handleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0, 174, 255))
        # Top-left
        $g.FillRectangle($handleBrush, $rectX - $handleSize/2, $rectY - $handleSize/2, $handleSize, $handleSize)
        # Top-right
        $g.FillRectangle($handleBrush, $rectX + $rectW - $handleSize/2, $rectY - $handleSize/2, $handleSize, $handleSize)
        # Bottom-left
        $g.FillRectangle($handleBrush, $rectX - $handleSize/2, $rectY + $rectH - $handleSize/2, $handleSize, $handleSize)
        # Bottom-right
        $g.FillRectangle($handleBrush, $rectX + $rectW - $handleSize/2, $rectY + $rectH - $handleSize/2, $handleSize, $handleSize)
        $handleBrush.Dispose()
        
        # Draw size indicator on selection
        $sizeText = "${rectW} x ${rectH}"
        $sizeFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $textSize = $g.MeasureString($sizeText, $sizeFont)
        $textX = $rectX + ($rectW - $textSize.Width) / 2
        $textY = $rectY + $rectH + 5
        if ($textY + $textSize.Height -gt $totalHeight) {
            $textY = $rectY - $textSize.Height - 5
        }
        
        # Text background
        $textBgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 0, 0, 0))
        $g.FillRectangle($textBgBrush, $textX - 5, $textY - 2, $textSize.Width + 10, $textSize.Height + 4)
        $textBgBrush.Dispose()
        
        # Text
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $g.DrawString($sizeText, $sizeFont, $textBrush, $textX, $textY)
        $textBrush.Dispose()
        $sizeFont.Dispose()
    }
    
    $g.Dispose()
    
    # Update picture box
    $oldImage = $pictureBox.Image
    $pictureBox.Image = $compositeBitmap
    if ($oldImage -ne $dimmedBitmap -and $oldImage -ne $screenBitmap) {
        $oldImage.Dispose()
    }
    
    return @{ X = $rectX; Y = $rectY; Width = $rectW; Height = $rectH }
}

# Mouse down - start selection
$pictureBox.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isSelecting = $true
        $script:startPoint = $e.Location
        $script:endPoint = $e.Location
    }
})

# Mouse move - update selection
$pictureBox.Add_MouseMove({
    param($sender, $e)
    
    $screenX = $e.X + $minX
    $screenY = $e.Y + $minY
    
    if ($script:isSelecting) {
        $script:endPoint = $e.Location
        $rect = Update-Selection -startX $script:startPoint.X -startY $script:startPoint.Y -endX $e.X -endY $e.Y
        
        $sizeLabel.Text = "Size: $($rect.Width) x $($rect.Height)"
        $posLabel.Text = "X: $($rect.X + $minX), Y: $($rect.Y + $minY)"
    } else {
        $posLabel.Text = "Cursor: X=$screenX, Y=$screenY"
    }
    
    # Move info panel away from cursor
    if ($e.X -lt 400 -and $e.Y -lt 200) {
        $infoPanel.Location = New-Object System.Drawing.Point(($totalWidth - 370), 20)
    } else {
        $infoPanel.Location = New-Object System.Drawing.Point(20, 20)
    }
})

# Mouse up - finish selection
$pictureBox.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:isSelecting) {
        $script:isSelecting = $false
        $script:endPoint = $e.Location
        
        # Calculate final rectangle
        $rectX = [Math]::Min($script:startPoint.X, $script:endPoint.X) + $minX
        $rectY = [Math]::Min($script:startPoint.Y, $script:endPoint.Y) + $minY
        $rectW = [Math]::Abs($script:endPoint.X - $script:startPoint.X)
        $rectH = [Math]::Abs($script:endPoint.Y - $script:startPoint.Y)
        
        if ($rectW -gt 10 -and $rectH -gt 10) {
            $script:selectedRect = @{ X = $rectX; Y = $rectY; Width = $rectW; Height = $rectH }
            $sizeLabel.Text = "Size: $rectW x $rectH"
            $posLabel.Text = "X: $rectX, Y: $rectY`nPress ENTER to confirm"
            $instructLabel.Text = "ENTER: Confirm | ESC: Cancel | Drag: New selection"
            $instructLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 255, 100)
        }
    }
})

# Key handler
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:cancelled = $true
        $form.Close()
    }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $script:selectedRect) {
        $form.Close()
    }
})

$pictureBox.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:cancelled = $true
        $form.Close()
    }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $script:selectedRect) {
        $form.Close()
    }
})

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  STEP 1: SELECT SCREENSHOT AREA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Instructions:" -ForegroundColor Yellow
Write-Host "  1. Click and drag to select the area" -ForegroundColor White
Write-Host "  2. Press ENTER to confirm selection" -ForegroundColor White
Write-Host "  3. Press ESC to cancel" -ForegroundColor White
Write-Host ""

$form.ShowDialog() | Out-Null

# Cleanup first form resources
$screenBitmap.Dispose()
$dimmedBitmap.Dispose()

# Output result
if ($script:cancelled -or $null -eq $script:selectedRect) {
    [DpiAwareness]::RestoreConsole()
    Write-Host "Selection cancelled." -ForegroundColor Red
    exit 1
}

$rect = $script:selectedRect
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  AREA SELECTED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  X      = $($rect.X)" -ForegroundColor White
Write-Host "  Y      = $($rect.Y)" -ForegroundColor White
Write-Host "  Width  = $($rect.Width)" -ForegroundColor White
Write-Host "  Height = $($rect.Height)" -ForegroundColor White
Write-Host ""

# ============================================
# STEP 2: CLICK POSITION PICKER
# ============================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  STEP 2: SELECT CLICK POSITION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "A semi-transparent overlay will appear." -ForegroundColor Yellow
Write-Host "Click anywhere to select that position." -ForegroundColor Yellow
Write-Host "Press ESC to cancel." -ForegroundColor Yellow
Write-Host ""

# Variables for click position
$script:clickX = $null
$script:clickY = $null
$script:clickCancelled = $false

# Store dimensions as integers for the click form
$clickFormWidth = [int]$totalWidth
$clickFormHeight = [int]$totalHeight

# Capture a new screenshot for Step 2
$clickScreenBitmap = New-Object System.Drawing.Bitmap($clickFormWidth, $clickFormHeight)
$clickGraphics = [System.Drawing.Graphics]::FromImage($clickScreenBitmap)
$clickGraphics.CopyFromScreen($minX, $minY, 0, 0, $clickScreenBitmap.Size)
$clickGraphics.Dispose()

# Create dimmed version for Step 2
$clickDimmedBitmap = New-Object System.Drawing.Bitmap($clickFormWidth, $clickFormHeight)
$clickDimGraphics = [System.Drawing.Graphics]::FromImage($clickDimmedBitmap)
$clickDimGraphics.DrawImage($clickScreenBitmap, 0, 0)
$clickDimBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
$clickDimGraphics.FillRectangle($clickDimBrush, 0, 0, $clickFormWidth, $clickFormHeight)
$clickDimBrush.Dispose()
$clickDimGraphics.Dispose()

# Create the click position picker form
$clickForm = New-Object System.Windows.Forms.Form
$clickForm.Text = "Click Position Picker"
$clickForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$clickForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$clickForm.Location = New-Object System.Drawing.Point($minX, $minY)
$clickForm.Size = New-Object System.Drawing.Size($clickFormWidth, $clickFormHeight)
$clickForm.TopMost = $true
$clickForm.Cursor = [System.Windows.Forms.Cursors]::Cross
$clickForm.ShowInTaskbar = $false
# Enable double buffering via reflection (DoubleBuffered is a protected property)
$clickForm.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($clickForm, $true, $null)

# Picture box for Step 2 background
$clickPictureBox = New-Object System.Windows.Forms.PictureBox
$clickPictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$clickPictureBox.Image = $clickDimmedBitmap
$clickPictureBox.Cursor = [System.Windows.Forms.Cursors]::Cross
$clickForm.Controls.Add($clickPictureBox)

# Info panel (same style as Step 1)
$clickInfoPanel = New-Object System.Windows.Forms.Panel
$clickInfoPanel.Size = New-Object System.Drawing.Size(350, 160)
$clickInfoPanel.Location = New-Object System.Drawing.Point(20, 20)
$clickInfoPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 30, 30, 30)
$clickForm.Controls.Add($clickInfoPanel)
$clickInfoPanel.BringToFront()

# Title
$clickTitleLabel = New-Object System.Windows.Forms.Label
$clickTitleLabel.Text = "CLICK POSITION PICKER"
$clickTitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$clickTitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 200, 255)
$clickTitleLabel.Location = New-Object System.Drawing.Point(15, 10)
$clickTitleLabel.AutoSize = $true
$clickInfoPanel.Controls.Add($clickTitleLabel)

# Position label
$clickPosLabel = New-Object System.Windows.Forms.Label
$clickPosLabel.Text = "Move mouse and click to select"
$clickPosLabel.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$clickPosLabel.ForeColor = [System.Drawing.Color]::White
$clickPosLabel.Location = New-Object System.Drawing.Point(15, 45)
$clickPosLabel.AutoSize = $true
$clickInfoPanel.Controls.Add($clickPosLabel)

# Coordinates label
$clickCoordLabel = New-Object System.Windows.Forms.Label
$clickCoordLabel.Text = "X: ---, Y: ---"
$clickCoordLabel.Font = New-Object System.Drawing.Font("Consolas", 11)
$clickCoordLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 200, 200)
$clickCoordLabel.Location = New-Object System.Drawing.Point(15, 75)
$clickCoordLabel.AutoSize = $true
$clickInfoPanel.Controls.Add($clickCoordLabel)

# Instructions
$clickInstructLabel = New-Object System.Windows.Forms.Label
$clickInstructLabel.Text = "Click: Select position | ESC: Cancel"
$clickInstructLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$clickInstructLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 150, 150, 150)
$clickInstructLabel.Location = New-Object System.Drawing.Point(15, 120)
$clickInstructLabel.AutoSize = $true
$clickInfoPanel.Controls.Add($clickInstructLabel)

# Handle mouse move - update coordinates display
$clickPictureBox.Add_MouseMove({
    param($sender, $e)
    $screenX = $e.X + $minX
    $screenY = $e.Y + $minY
    $clickCoordLabel.Text = "X: $screenX, Y: $screenY"
    
    # Move info panel away from cursor
    if ($e.X -lt 400 -and $e.Y -lt 200) {
        $clickInfoPanel.Location = New-Object System.Drawing.Point(($clickFormWidth - 370), 20)
    } else {
        $clickInfoPanel.Location = New-Object System.Drawing.Point(20, 20)
    }
})

# Handle mouse click - capture position
$clickPictureBox.Add_MouseClick({
    param($sender, $e)
    $script:clickX = $e.X + $minX
    $script:clickY = $e.Y + $minY
    $clickForm.Close()
})

# Handle keyboard - ESC to cancel
$clickForm.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:clickCancelled = $true
        $clickForm.Close()
    }
})

$clickPictureBox.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:clickCancelled = $true
        $clickForm.Close()
    }
})

$clickForm.ShowDialog() | Out-Null

# Cleanup Step 2 resources
$clickScreenBitmap.Dispose()
$clickDimmedBitmap.Dispose()

# Check if click position was cancelled
if ($script:clickCancelled) {
    Write-Host "Click position selection cancelled." -ForegroundColor Red
    Write-Host ""
    Write-Host "Area only - Example usage:" -ForegroundColor Cyan
    Write-Host "  .\run.ps1 -RectX $($rect.X) -RectY $($rect.Y) -RectWidth $($rect.Width) -RectHeight $($rect.Height) -ClickX 100 -ClickY 100 -Count 5" -ForegroundColor White
    
    $clipText = "-RectX $($rect.X) -RectY $($rect.Y) -RectWidth $($rect.Width) -RectHeight $($rect.Height)"
    Set-Clipboard -Value $clipText
    Write-Host ""
    Write-Host "Area parameters copied to clipboard!" -ForegroundColor Green
    [DpiAwareness]::RestoreConsole()
    exit 0
}

# ============================================
# STEP 3: ASK FOR CLICK COUNT
# ============================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  STEP 3: ENTER CLICK COUNT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create input dialog for click count
$countForm = New-Object System.Windows.Forms.Form
$countForm.Text = "Enter Click Count"
$countForm.Size = New-Object System.Drawing.Size(350, 200)
$countForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$countForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$countForm.MaximizeBox = $false
$countForm.MinimizeBox = $false
$countForm.TopMost = $true
$countForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)

# Title label
$countTitleLabel = New-Object System.Windows.Forms.Label
$countTitleLabel.Text = "How many times to click?"
$countTitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$countTitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 200, 255)
$countTitleLabel.Location = New-Object System.Drawing.Point(20, 20)
$countTitleLabel.AutoSize = $true
$countForm.Controls.Add($countTitleLabel)

# Description label
$countDescLabel = New-Object System.Windows.Forms.Label
$countDescLabel.Text = "Enter the number of screenshots to take:"
$countDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$countDescLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 180, 180)
$countDescLabel.Location = New-Object System.Drawing.Point(20, 50)
$countDescLabel.AutoSize = $true
$countForm.Controls.Add($countDescLabel)

# TextBox for count input
$countTextBox = New-Object System.Windows.Forms.TextBox
$countTextBox.Text = "5"
$countTextBox.Font = New-Object System.Drawing.Font("Consolas", 14)
$countTextBox.Location = New-Object System.Drawing.Point(20, 80)
$countTextBox.Size = New-Object System.Drawing.Size(290, 30)
$countTextBox.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 50, 50)
$countTextBox.ForeColor = [System.Drawing.Color]::White
$countTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$countForm.Controls.Add($countTextBox)

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$okButton.Location = New-Object System.Drawing.Point(120, 120)
$okButton.Size = New-Object System.Drawing.Size(100, 35)
$okButton.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 120, 215)
$okButton.ForeColor = [System.Drawing.Color]::White
$okButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$countForm.Controls.Add($okButton)
$countForm.AcceptButton = $okButton

# Handle Enter key in textbox
$countTextBox.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $countForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $countForm.Close()
    }
})

# Select all text when form loads
$countForm.Add_Shown({
    $countTextBox.SelectAll()
    $countTextBox.Focus()
})

$countResult = $countForm.ShowDialog()

# Get the count value
$clickCount = 5
if ($countResult -eq [System.Windows.Forms.DialogResult]::OK) {
    $inputValue = $countTextBox.Text.Trim()
    if ($inputValue -match '^\d+$' -and [int]$inputValue -gt 0) {
        $clickCount = [int]$inputValue
    }
}

Write-Host "Click count set to: $clickCount" -ForegroundColor Green
Write-Host ""

# Final output with both area and click position
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ALL SELECTIONS COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Screenshot Area:" -ForegroundColor Cyan
Write-Host "  X      = $($rect.X)" -ForegroundColor White
Write-Host "  Y      = $($rect.Y)" -ForegroundColor White
Write-Host "  Width  = $($rect.Width)" -ForegroundColor White
Write-Host "  Height = $($rect.Height)" -ForegroundColor White
Write-Host ""
Write-Host "Click Position:" -ForegroundColor Cyan
Write-Host "  X = $($script:clickX)" -ForegroundColor White
Write-Host "  Y = $($script:clickY)" -ForegroundColor White
Write-Host ""
Write-Host "Click Count: $clickCount" -ForegroundColor Cyan
Write-Host ""
Write-Host "Complete command:" -ForegroundColor Yellow
Write-Host "  .\screenshot.ps1 -RectX $($rect.X) -RectY $($rect.Y) -RectWidth $($rect.Width) -RectHeight $($rect.Height) -ClickX $($script:clickX) -ClickY $($script:clickY) -Count $clickCount" -ForegroundColor White
Write-Host ""


# output command to a batch script run.cmd
$cmdText = "powershell.exe -ExecutionPolicy Bypass -File %~dp0screenshot.ps1 -RectX $($rect.X) -RectY $($rect.Y) -RectWidth $($rect.Width) -RectHeight $($rect.Height) -ClickX $($script:clickX) -ClickY $($script:clickY) -Count $clickCount"
$cmdFilePath = Join-Path -Path (Get-Location) -ChildPath "run.cmd"
Set-Content -Path $cmdFilePath -Value $cmdText -Encoding ASCII

# # Copy complete parameters to clipboard
# $clipText = "-ClickX $($script:clickX) -ClickY $($script:clickY) -RectX $($rect.X) -RectY $($rect.Y) -RectWidth $($rect.Width) -RectHeight $($rect.Height)"
# Set-Clipboard -Value $clipText

# Restore console window at the end
[DpiAwareness]::RestoreConsole()
# Write-Host "All parameters copied to clipboard!" -ForegroundColor Green
# Write-Host ""
