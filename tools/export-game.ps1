# 把一个积木项目导出成能直接双击运行的 exe。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\export-game.ps1 -Project test\3d
#   powershell -ExecutionPolicy Bypass -File tools\export-game.ps1 -Project test\3d -Out dist\我的游戏 -Name 我的游戏
#
# 产出：
#   <Out>\<Name>.exe   可双击运行
#   <Out>\<Name>.pck   游戏内容
#
# 说明（重要）：
#   默认用的是**编辑器二进制**当运行时（157MB，里面带着编辑器）。
#   如果引擎树里存在 release 模板（godot.windows.template_release.x86_64.exe），
#   脚本会自动改用它 —— 那才是正式发布该用的（小很多、也不含编辑器）。
#   模板用 `scons target=template_release` 编一次就有。

param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Out = "",
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root "engine\godot\bin"

$projDir = if ([System.IO.Path]::IsPathRooted($Project)) { $Project } else { Join-Path $root $Project }
if (-not (Test-Path (Join-Path $projDir "project.godot"))) {
    Write-Error "这里不是 Godot 项目（找不到 project.godot）：$projDir"
}

if (-not $Name) { $Name = Split-Path -Leaf $projDir }
if (-not $Out) { $Out = Join-Path $root ("dist\" + $Name) }
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $root $Out }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

# 1. 选运行时：优先 release 模板，没有就用编辑器二进制
$template = Join-Path $bin "godot.windows.template_release.x86_64.exe"
$editor = Join-Path $bin "godot.windows.editor.x86_64.exe"
$runtime = if (Test-Path $template) { $template } else { $editor }
$usingTemplate = Test-Path $template

if (-not (Test-Path $runtime)) {
    Write-Error "找不到可用的运行时：$runtime（先跑 tools\build-engine.ps1）"
}

# 2. 打包 .pck
$pck = Join-Path $Out ($Name + ".pck")
$packer = Join-Path $root "tools\packer.gd"
$editorExe = if (Test-Path $editor) { $editor } else { $runtime }

Write-Host "打包 $projDir ..."
# 注意：Godot 的 Windows 二进制往控制台句柄写东西，用 *> 重定向会拿不到输出，
# 必须走管道捕获。
$packOut = & $editorExe --headless --path $projDir --script $packer -- --out $pck 2>&1 |
    ForEach-Object { "$_" }
$ok = $packOut | Where-Object { $_ -match "PACKER_OK" } | Select-Object -First 1
if (-not $ok) {
    $packOut | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }
    Write-Error "打包失败"
}
Write-Host "  $ok"

# 3. 复制运行时并改名
$exe = Join-Path $Out ($Name + ".exe")
Copy-Item $runtime $exe -Force

# 4. 顺手写一个说明文件
$readme = @"
$Name
=====

双击 $Name.exe 就能玩。

文件说明：
  $Name.exe   游戏程序
  $Name.pck   游戏内容（关卡、积木、素材都在这里）

想改内容？用 Easy Engine 编辑器打开项目目录再导出一次。
"@
Set-Content -Path (Join-Path $Out "玩我.txt") -Value $readme -Encoding UTF8

$sizeMb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
$pckMb = [math]::Round((Get-Item $pck).Length / 1MB, 2)

Write-Host ""
Write-Host "导出完成：$Out" -ForegroundColor Green
Write-Host "  $Name.exe  ${sizeMb} MB"
Write-Host "  $Name.pck  ${pckMb} MB"
if ($usingTemplate) {
    Write-Host "  运行时：release 模板（正式发布用这个）"
} else {
    Write-Host "  运行时：编辑器二进制（临时方案，157MB；想要小体积就编一次 template_release）" -ForegroundColor Yellow
}
