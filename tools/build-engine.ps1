# 同步模块源码、准备内嵌网页资源、编译 Godot。
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

# 1. WebView2 SDK（积木工作区靠它把网页显示在编辑器里）
$wv2 = Join-Path $root "modules\easyblocks\thirdparty\webview2\include\WebView2.h"
if (-not (Test-Path $wv2)) {
    & (Join-Path $PSScriptRoot "fetch-webview2.ps1")
}

# 2. 模块源码 → 引擎树
& (Join-Path $PSScriptRoot "sync-module.ps1")

# 3. 编译
Push-Location $engine
try {
    python -m SCons platform=windows target=editor arch=x86_64 accesskit=no d3d12=no "-j$Jobs"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "编译失败（SCons 退出码 $LASTEXITCODE）"
    }
} finally {
    Pop-Location
}

# 4. 积木工作区网页 → 可执行文件旁边（编辑器运行时从这里加载）
$webSrc = Join-Path $root "web\app"
$webDst = Join-Path $engine "bin\easyblocks_web"
if (Test-Path $webSrc) {
    robocopy $webSrc $webDst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Write-Error "复制积木工作区网页失败（robocopy 退出码 $LASTEXITCODE）"
    }
}

Write-Host ""
Write-Host "编译完成：engine\godot\bin\godot.windows.editor.x86_64.exe"
Write-Host "积木工作区：engine\godot\bin\easyblocks_web"

# 5. WebView2 加载器 → 可执行文件旁边（积木工作区运行时动态加载它）
$loader = Join-Path $root "modules\easyblocks\thirdparty\webview2\x64\WebView2Loader.dll"
if (Test-Path $loader) {
    Copy-Item $loader (Join-Path $engine "bin\WebView2Loader.dll") -Force
}