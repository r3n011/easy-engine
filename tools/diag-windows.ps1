# 诊断：启动 Godot 编辑器，点击指定位置，然后枚举该进程的所有顶层窗口。
#
# 用来判断「快速设置」这类对话框是内嵌在主窗口，还是独立的原生窗口。
#
# 用法: powershell -File tools/diag-windows.ps1 -Exe <godot.exe> [-Click "1127,51"]

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string]$Click = "",
    [int]$WaitSec = 10
)

$ErrorActionPreference = "Stop"

Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinEnum {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int n);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static List<string> ListForPid(uint want) {
        var res = new List<string>();
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid == want) {
                var sb = new StringBuilder(512);
                GetWindowTextW(h, sb, 512);
                RECT r; GetWindowRect(h, out r);
                res.Add(string.Format("hwnd={0} visible={1} rect=({2},{3})-({4},{5}) size={6}x{7} title=\"{8}\"",
                    h, IsWindowVisible(h), r.Left, r.Top, r.Right, r.Bottom,
                    r.Right - r.Left, r.Bottom - r.Top, sb.ToString()));
            }
            return true;
        }, IntPtr.Zero);
        return res;
    }
}
'@

$proc = Start-Process -FilePath $Exe -PassThru
Write-Host "PID = $($proc.Id)"
Start-Sleep -Seconds $WaitSec
$proc.Refresh()

function Dump($tag) {
    Write-Host "`n--- $tag ---"
    [WinEnum]::ListForPid([uint32]$proc.Id) | ForEach-Object { Write-Host "  $_" }
}

Dump "点击前"

if ($Click) {
    $h = $proc.MainWindowHandle
    [void][WinEnum]::ShowWindow($h, 9)
    [void][WinEnum]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 800
    $r = New-Object WinEnum+RECT
    [void][WinEnum]::GetWindowRect($h, [ref]$r)
    $parts = $Click.Split(",")
    $x = $r.Left + [int]$parts[0]
    $y = $r.Top + [int]$parts[1]
    Write-Host "`n点击屏幕 ($x, $y)  (窗口 $($r.Left),$($r.Top))"
    [void][WinEnum]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 300
    [WinEnum]::mouse_event(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 100
    [WinEnum]::mouse_event(0x0004, 0, 0, 0, 0)
    Start-Sleep -Seconds 2
    Dump "点击后"
}

Write-Host "`n按需关闭: Stop-Process -Id $($proc.Id)"
