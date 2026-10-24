# run-demo.ps1 — 启动 Easy Engine 播放器跑一个 .ee 项目，截图，然后退出
#
# 用法:
#   powershell -File tools/run-demo.ps1 [-Project res://tests/demo.ee.json] [-WaitSec 8] [-Out docs/shot.png] [-MoveMouse x,y]

[CmdletBinding()]
param(
    [string]$Godot = "",
    [string]$Project = "res://tests/demo.ee.json",
    [int]$WaitSec = 8,
    [string]$Out = "",
    # 截图前把鼠标移到窗口内某点，用来演示跟随鼠标的玩法
    [string]$MoveMouse = "",
    [switch]$Diag,
    [string]$Scene = "",
    # 传了就按"打开编辑器"的方式启动（用于验证编辑器里的界面）
    [string]$EditorPath = ""
,
    [string[]]$ExtraFlags = @()
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Cap2 {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $Godot) { $Godot = Join-Path $root "engine\godot\bin\godot.windows.editor.x86_64.exe" }
$runtime = Join-Path $root "runtime"
$log = Join-Path $env:TEMP "ee-demo-out.txt"

Get-Process -Name "godot*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Host "启动播放器：$Project" -ForegroundColor Cyan
$sceneArg = if ($Scene) { "$Scene -- $Project" } else { "-- $Project" }
if ($EditorPath) { $argLine = "--path `"$EditorPath`" -e --rendering-driver opengl3" } else { $argLine = "--path `"$runtime`" --rendering-driver opengl3 $sceneArg" }
$proc = Start-Process -FilePath $Godot -ArgumentList $argLine -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"

# 等窗口出现并且尺寸正常
$h = [IntPtr]::Zero
$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $proc.Refresh()
    if ($proc.HasExited) { break }
    $cand = $proc.MainWindowHandle
    if ($cand -ne [IntPtr]::Zero) {
        [void][Cap2]::ShowWindow($cand, 9)
        Start-Sleep -Milliseconds 400
        $r0 = New-Object Cap2+RECT
        [void][Cap2]::GetWindowRect($cand, [ref]$r0)
        if (($r0.Right - $r0.Left) -gt 200) { $h = $cand; break }
    }
}

if ($proc.HasExited) {
    Write-Host "进程提前退出（退出码 $($proc.ExitCode)）" -ForegroundColor Red
} else {
    Write-Host "窗口已就绪，运行 $WaitSec 秒 ..."
    Start-Sleep -Seconds $WaitSec
}

$proc.Refresh()
$h = $proc.MainWindowHandle

if ($MoveMouse -and $h -ne [IntPtr]::Zero) {
    $r = New-Object Cap2+RECT
    [void][Cap2]::GetWindowRect($h, [ref]$r)
    $p = $MoveMouse.Split(",")
    $x = $r.Left + [int]$p[0]
    $y = $r.Top + [int]$p[1]
    Write-Host "移动鼠标到窗口内 ($($p[0]), $($p[1]))"
    [void][Cap2]::SetCursorPos($x, $y)
    Start-Sleep -Seconds 2
}

if ($h -ne [IntPtr]::Zero -and -not $proc.HasExited) {
    [void][Cap2]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 600
    $r = New-Object Cap2+RECT
    [void][Cap2]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left
    $hh = $r.Bottom - $r.Top
    Write-Host "窗口尺寸: ${w}x${hh}"

    $bmp = New-Object System.Drawing.Bitmap($w, $hh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][Cap2]::PrintWindow($h, $hdc, 2)
    $g.ReleaseHdc($hdc)
    $g.Dispose()
    if (-not $Out) { $Out = Join-Path $root "docs\shot-demo.png" }
    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "已保存: $Out" -ForegroundColor Green
} else {
    Write-Host "没有可截图的窗口" -ForegroundColor Yellow
}

Get-Process -Name "godot*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Host "`n==== 播放器输出 ====" -ForegroundColor Cyan
foreach ($f in @($log, "$log.err")) {
    if (Test-Path $f) {
        Get-Content $f | Where-Object { $_ -notmatch "^\s*Godot Engine v" } | ForEach-Object { Write-Host "  $_" }
    }
}
