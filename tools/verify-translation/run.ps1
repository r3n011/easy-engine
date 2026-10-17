# run.ps1 — 运行翻译的离屏验证
#
# 把构建用的 .po 拷贝到本目录，然后用 Godot 以无界面模式断言翻译查找结果。
# 比截图验证可靠：不受前台窗口锁、DPI、渲染的影响。
#
# 用法: powershell -File tools/verify-translation/run.ps1 [-Godot <exe>]

[CmdletBinding()]
param(
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here "..\..")).Path

if (-not $Godot) {
    $Godot = Join-Path $root "engine\godot\bin\godot.windows.editor.x86_64.exe"
}
if (-not (Test-Path $Godot)) {
    Write-Host "找不到 Godot：$Godot" -ForegroundColor Red
    Write-Host "请先运行 bootstrap.ps1 或手动指定 -Godot <路径>"
    exit 1
}

$tr = Join-Path $root "engine\godot\editor\translations"
Copy-Item (Join-Path $tr "editor\zh_Hans.po")      (Join-Path $here "zh_Hans.editor.po") -Force
Copy-Item (Join-Path $tr "extractable\zh_Hans.po") (Join-Path $here "zh_Hans.extractable.po") -Force

& $Godot --headless --path $here --script verify.gd
$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Host "`n全部通过。" -ForegroundColor Green
} else {
    Write-Host "`n有失败项，请检查上面输出。" -ForegroundColor Red
}
exit $code
