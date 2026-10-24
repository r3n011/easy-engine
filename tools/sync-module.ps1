# 把仓库里的模块真源码同步进引擎源码树。
#
# 为什么要有这一步：
#   engine/ 是本仓库 .gitignore 掉的「可重建构建目录」（Godot 浅克隆），
#   真正的模块源码在 modules/easyblocks，受版本管理。
#   编译前同步一次，引擎树随时可以整个删掉重来，工作不会丢。
#
# 用法： powershell -ExecutionPolicy Bypass -File tools\sync-module.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "modules\easyblocks"
$dst = Join-Path $root "engine\godot\modules\easyblocks"

if (-not (Test-Path $src)) {
    Write-Error "找不到模块源码：$src"
}

if (-not (Test-Path (Join-Path $root "engine\godot"))) {
    Write-Error "找不到引擎源码树 engine\godot（先按 docs/A-模块骨架.md 拉取 Godot 源码）"
}

# /MIR 让目标严格等于来源：引擎树里多出来的旧文件（含构建生成的 block_defs.gen.h）会被清掉，
# 下次编译会重新生成。
robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$code = $LASTEXITCODE
if ($code -ge 8) {
    Write-Error "同步失败（robocopy 退出码 $code）"
}

# 顺手清掉 Python 缓存，免得把 __pycache__ 带进引擎树
Get-ChildItem $dst -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

Write-Host "已同步模块源码 -> engine\godot\modules\easyblocks"
