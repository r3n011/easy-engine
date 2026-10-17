# bootstrap.ps1 — 一键拉起 Easy Engine 的开发环境
#
# 第三方源码（Godot / Gandi-IDE / TurboWarp）体积过大且非我方代码，不入库。
# 本脚本负责把它们拉下来，并打上我们的汉化补丁。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
#   powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -SkipBuild

[CmdletBinding()]
param(
    # 只拉源码不打补丁/不编译
    [switch]$SkipBuild,
    # 只拉取与打包汉化补丁，不编译
    [switch]$PatchOnly,
    [string]$GodotTag = "4.7.2-stable",
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host "`n    XX  $msg" -ForegroundColor Red; exit 1 }

Set-Location $Root

# ---------------------------------------------------------------- 1. 前置检查
Step 1 "检查前置工具"

foreach ($tool in @("git", "python")) {
    $p = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $p) { Die "缺少 $tool，请先安装。git: https://git-scm.com/  python: https://www.python.org/" }
    Ok "$tool -> $($p.Source)"
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { Ok "gh -> $($gh.Source)" } else { Warn "未找到 gh（可选，用于创建/推送仓库）" }

# SCons 是 Godot 构建系统
$scons = python -c "import SCons; print(SCons.__version__)" 2>$null
if ($LASTEXITCODE -ne 0 -or -not $scons) {
    Warn "未安装 SCons，正在安装（若失败请改用 pip 官方源：-i https://pypi.org/simple）"
    python -m pip install scons
    if ($LASTEXITCODE -ne 0) { python -m pip install --index-url https://pypi.org/simple scons }
    if ($LASTEXITCODE -ne 0) { Die "SCons 安装失败" }
}
Ok "scons $(python -c 'import SCons; print(SCons.__version__)')"

# ---------------------------------------------------------------- 2. MSVC 探测修复
Step 2 "修复 MSVC 工具链探测"

Write-Host "    Godot 用 SCons 构建，SCons 依赖 vswhere.exe 定位 MSVC。"
Write-Host "    若系统自带的 vswhere.exe 损坏，构建会误报 'No valid compilers found' 并回落到 MinGW。"

$vswhereGood = Join-Path $env:USERPROFILE ".scons\vswhere.exe"
$siteInit = Join-Path $env:USERPROFILE ".scons\site_scons\site_init.py"

if (Test-Path $vswhereGood) {
    Ok "已存在可用的 vswhere: $vswhereGood"
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $vswhereGood) | Out-Null
    Write-Host "    下载 vswhere.exe ..."
    Invoke-WebRequest -Uri "https://github.com/microsoft/vswhere/releases/latest/download/vswhere.exe" `
        -OutFile $vswhereGood -UseBasicParsing
    Ok "已下载到 $vswhereGood"
}

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
Ok "已写入 $siteInit"

# 验证
$probe = python -c "from SCons.Tool.MSCommon import msvc_exists; print(msvc_exists())" 2>$null
if ($probe -match "True") { Ok "MSVC 探测正常" }
else { Warn "MSVC 仍未探测到，请检查是否装了 Visual Studio C++ 生成工具" }

# ---------------------------------------------------------------- 3. 拉取第三方源码
Step 3 "拉取第三方源码"

$godotDir = Join-Path $Root "engine\godot"
if (Test-Path (Join-Path $godotDir ".git")) {
    Ok "Godot 已存在，跳过"
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $godotDir) | Out-Null
    Write-Host "    克隆 Godot $GodotTag（浅克隆，约 400MB）..."
    git clone --depth 1 --branch $GodotTag https://github.com/godotengine/godot.git $godotDir
    if (-not (Test-Path (Join-Path $godotDir ".git"))) { Die "Godot 克隆失败" }
    Ok "Godot $GodotTag"
}

$repos = @(
    @{ url = "https://github.com/Gandi-IDE/scratch-vm";        dir = "scratch\Gandi-IDE\scratch-vm";        branch = "develop" }
    @{ url = "https://github.com/Gandi-IDE/gandi-blocks";      dir = "scratch\Gandi-IDE\gandi-blocks";      branch = "develop" }
    @{ url = "https://github.com/Gandi-IDE/gandi-plugins";     dir = "scratch\Gandi-IDE\gandi-plugins";     branch = "main" }
    @{ url = "https://github.com/Gandi-IDE/custom-extension";  dir = "scratch\Gandi-IDE\custom-extension";  branch = "main" }
    @{ url = "https://github.com/Gandi-IDE/scratch-render";    dir = "scratch\Gandi-IDE\scratch-render";    branch = "develop" }
    @{ url = "https://github.com/Gandi-IDE/scratch-storage";   dir = "scratch\Gandi-IDE\scratch-storage";   branch = "develop" }
    @{ url = "https://github.com/Gandi-IDE/scratch-paint";     dir = "scratch\Gandi-IDE\scratch-paint";     branch = "develop" }
    @{ url = "https://github.com/Gandi-IDE/scratch-audio";     dir = "scratch\Gandi-IDE\scratch-audio";     branch = "develop" }
    @{ url = "https://github.com/TurboWarp/scratch-gui";       dir = "scratch\TurboWarp\scratch-gui";       branch = "develop" }
    @{ url = "https://github.com/TurboWarp/scratch-vm";        dir = "scratch\TurboWarp\scratch-vm";        branch = "develop" }
    @{ url = "https://github.com/TurboWarp/packager";          dir = "scratch\TurboWarp\packager";          branch = "master" }
)

foreach ($r in $repos) {
    $dst = Join-Path $Root $r.dir
    if (Test-Path (Join-Path $dst ".git")) { Ok "$($r.dir) 已存在"; continue }
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    git clone --depth 1 --branch $r.branch $r.url $dst 2>$null
    if (Test-Path (Join-Path $dst ".git")) { Ok $r.dir } else { Warn "$($r.dir) 克隆失败" }
}

# ---------------------------------------------------------------- 4. 汉化补丁
Step 4 "应用汉化补丁"

$poEditor = Join-Path $godotDir "editor\translations\editor\zh_Hans.po"
if (Test-Path $poEditor) {
    python (Join-Path $Root "tools\zh-apply.py") (Join-Path $Root "tools\zh-translations.json") $godotDir
    Ok "汉化补丁已应用（已存在的条目会自动跳过）"
} else {
    Warn "未找到 Godot 翻译文件，跳过"
}

# ---------------------------------------------------------------- 5. 编译
if ($PatchOnly) {
    Write-Host "`n完成（-PatchOnly，未编译）。" -ForegroundColor Green
    exit 0
}

if ($SkipBuild) {
    Write-Host "`n完成（-SkipBuild，未编译）。" -ForegroundColor Green
    Write-Host "手动编译: cd engine\godot; python -m SCons platform=windows target=editor arch=x86_64 accesskit=no d3d12=no -j15"
    exit 0
}

Step 5 "编译 Godot 编辑器"
Write-Host "    accesskit / d3d12 需要额外依赖下载，若网络受限请保持关闭。"
Write-Host "    首次编译约 20 分钟。"

Push-Location $godotDir
try {
    python -m SCons platform=windows target=editor arch=x86_64 accesskit=no d3d12=no -j15
    if ($LASTEXITCODE -ne 0) { Warn "编译返回非零（若只是 stderr 被 PowerShell 当成错误可忽略）" }
} finally {
    Pop-Location
}

$exe = Join-Path $godotDir "bin\godot.windows.editor.x86_64.exe"
if (Test-Path $exe) {
    Write-Host "`n完成！产物: $exe" -ForegroundColor Green
    Write-Host "启动: `"$exe`" -l zh_Hans"
} else {
    Warn "未找到编译产物，请检查上面的编译日志"
}
