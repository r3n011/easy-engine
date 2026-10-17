# setup-vswhere.ps1
#
# 修复本机 Godot/SCons 找不到 MSVC 编译器的问题。
#
# 背景：C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe 已损坏，
#       而 SCons 只取该目录下第一个 vswhere 且不做可用性校验，导致
#       msvc_exists() == False，Godot 构建回落到 MinGW 分支并报：
#       "ERROR: No valid compilers found, use MINGW_PREFIX environment variable to set MinGW path."
#
# 做法：下载一份可用的 vswhere.exe，放到用户目录，并通过用户级 SCons site_init.py
#       以高优先级注册，对所有 SCons 项目生效（无需管理员权限）。

[CmdletBinding()]
param(
    [string]$Target = (Join-Path $env:USERPROFILE ".scons\vswhere.exe")
)

$ErrorActionPreference = "Stop"

Write-Host "[1/3] 下载可用的 vswhere.exe ..." -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP "vswhere.exe"
Invoke-WebRequest -Uri "https://github.com/microsoft/vswhere/releases/latest/download/vswhere.exe" `
    -OutFile $tmp -UseBasicParsing

$size = (Get-Item $tmp).Length
if ($size -lt 100000) { throw "下载的 vswhere.exe 异常（$size 字节）" }

Write-Host "[2/3] 安装到 $Target ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
Copy-Item $tmp $Target -Force
Remove-Item $tmp -Force

Write-Host "[3/3] 写入 SCons site_init.py ..." -ForegroundColor Cyan
$siteInit = Join-Path $env:USERPROFILE ".scons\site_scons\site_init.py"
New-Item -ItemType Directory -Force -Path (Split-Path $siteInit) | Out-Null

@'
"""SCons site init: register a working vswhere.exe (see tools/setup-vswhere.ps1)."""
import os

_vswhere = os.environ.get("EE_VSWHERE") or os.path.join(
    os.path.expanduser("~"), ".scons", "vswhere.exe"
)

try:
    import SCons.Tool.MSCommon.vc as _vc
except Exception:
    _vc = None

if _vc is not None and os.path.isfile(_vswhere):
    try:
        _vc.vswhere_register_executable(_vswhere, priority="high", freeze=True)
    except Exception:
        pass
'@ | Set-Content -Path $siteInit -Encoding UTF8

Write-Host ""
Write-Host "完成。验证：" -ForegroundColor Green
Write-Host "  python -c `"from SCons.Tool.MSCommon import msvc_exists; print(msvc_exists())`""
Write-Host "  期望输出: True"
Write-Host ""
Write-Host "注意：彻底修复请以管理员身份重装 Visual Studio Installer 以替换损坏的 vswhere.exe，"
Write-Host "      之后可删除 $siteInit"
