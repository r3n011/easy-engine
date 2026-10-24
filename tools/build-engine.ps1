# 同步模块源码并编译 Godot。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\build-engine.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-engine.ps1 -Jobs 8
#
# 关于 -Jobs：默认 2 是保守值。
#   每个 cl.exe 峰值能吃到 1.5 GB 以上，Godot 的 variant.h 尤其重。
#   实测 24 GB 内存、同时开着 IDE 的情况下 -j15 会报 C1060「编译器堆空间不足」，
#   -j5 也炸，-j2 稳定通过。内存富裕时可以往上加。

param(
    [int]$Jobs = 2
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root "engine\godot"

if (-not (Test-Path $engine)) {
    Write-Error "找不到 engine\godot，请先拉取 Godot 源码（见 docs/A-模块骨架.md）"
}

& (Join-Path $PSScriptRoot "sync-module.ps1")

Push-Location $engine
try {
    python -m SCons platform=windows target=editor arch=x86_64 accesskit=no d3d12=no "-j$Jobs"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "编译失败（SCons 退出码 $LASTEXITCODE）"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "编译完成：engine\godot\bin\godot.windows.editor.x86_64.exe"
