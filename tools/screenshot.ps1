# screenshot.ps1 — 启动 Godot 编辑器并截取窗口，用于验证汉化效果
#
# 用法:
#   .\tools\screenshot.ps1 -Exe <godot.exe> -Out <png> [-WaitSec 12] [-Args '...']

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$WaitSec = 12,
    [string[]]$ExtraArgs = @()
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
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

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
$h = $proc.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "未能取得主窗口句柄" }

[void][Win32Cap]::ShowWindow($h, 5)
[void][Win32Cap]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 1200

$r = New-Object Win32Cap+RECT
[void][Win32Cap]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
Write-Host "窗口尺寸: ${w}x${hh}"

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
