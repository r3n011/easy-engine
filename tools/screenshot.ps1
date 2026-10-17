# screenshot.ps1 — 启动 Godot 编辑器并截取窗口，用于验证汉化效果
#
# 用法:
#   .\tools\screenshot.ps1 -Exe <godot.exe> -Out <png> [-WaitSec 12] [-Args '...']

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$WaitSec = 12,
    [string[]]$ExtraArgs = @(),
    # 截图前依次点击的窗口内坐标，形如 "1127,51"（可多个）
    [string[]]$ClickAt = @()
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32Cap {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

function ClickAt([int]$X, [int]$Y) {
    [void][Win32Cap]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 250
    [Win32Cap]::mouse_event(0x0002, 0, 0, 0, 0)   # LEFTDOWN
    Start-Sleep -Milliseconds 80
    [Win32Cap]::mouse_event(0x0004, 0, 0, 0, 0)   # LEFTUP
    Start-Sleep -Milliseconds 600
}

Write-Host "启动 $Exe ..." -ForegroundColor Cyan
if ($ExtraArgs.Count -gt 0) {
    $proc = Start-Process -FilePath $Exe -ArgumentList $ExtraArgs -PassThru
} else {
    $proc = Start-Process -FilePath $Exe -PassThru
}
Write-Host "PID = $($proc.Id)，等待 $WaitSec 秒让界面渲染 ..."

$deadline = (Get-Date).AddSeconds($WaitSec + 20)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 800
    $proc.Refresh()
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { break }
    if ($proc.HasExited) { throw "进程已退出，退出码 $($proc.ExitCode)" }
}

Start-Sleep -Seconds $WaitSec
$proc.Refresh()
$h = [IntPtr]::Zero
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $proc.Refresh()
    if ($proc.HasExited) { throw "进程已退出，退出码 $($proc.ExitCode)" }
    $cand = $proc.MainWindowHandle
    if ($cand -ne [IntPtr]::Zero) {
        # 9 = SW_RESTORE，处理窗口启动即被最小化的情况
        [void][Win32Cap]::ShowWindow($cand, 9)
        Start-Sleep -Milliseconds 500
        $tmp = New-Object Win32Cap+RECT
        [void][Win32Cap]::GetWindowRect($cand, [ref]$tmp)
        if (($tmp.Right - $tmp.Left) -gt 400 -and ($tmp.Bottom - $tmp.Top) -gt 300) {
            $h = $cand
            break
        }
    }
    Start-Sleep -Milliseconds 500
}
if ($h -eq [IntPtr]::Zero) { throw "未能取得有效的主窗口" }

Start-Sleep -Seconds $WaitSec

$r = New-Object Win32Cap+RECT
[void][Win32Cap]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
Write-Host "窗口尺寸: ${w}x${hh}"

[void][Win32Cap]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 1000

foreach ($spec in $ClickAt) {
    # 支持 "x,y" 或 "x,y;x2,y2;..." 一次传多个点（-File 传数组不可靠）
    foreach ($c in $spec.Split(";")) {
        if (-not $c.Trim()) { continue }
        $parts = $c.Split(",")
        $px = $r.Left + [int]$parts[0]
        $py = $r.Top + [int]$parts[1]
        Write-Host "点击窗口内 ($($parts[0]), $($parts[1])) -> 屏幕 ($px, $py)"
        ClickAt $px $py
    }
}

$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
# PW_RENDERFULLCONTENT = 2，可抓到被遮挡/GPU 渲染的窗口
[void][Win32Cap]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "已保存: $Out" -ForegroundColor Green
Write-Host "PID $($proc.Id) 仍在运行（如需关闭: Stop-Process -Id $($proc.Id)）"
