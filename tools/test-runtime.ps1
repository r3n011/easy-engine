# test-runtime.ps1 — 运行 M1 的全部验收（一条命令跑回归）
#
# 用法: powershell -File tools/test-runtime.ps1 [-Godot <exe>]

[CmdletBinding()]
param([string]$Godot = "")

$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $Godot) { $Godot = Join-Path $root "engine\godot\bin\godot.windows.editor.x86_64.exe" }
if (-not (Test-Path $Godot)) { Write-Host "找不到 Godot：$Godot" -ForegroundColor Red; exit 1 }

$runtime = Join-Path $root "runtime"
$cli = "tools/cli.gd"
$failed = 0

function Run-Phase($title, $cliArgs) {
    Write-Host ""
    Write-Host "==== $title ====" -ForegroundColor Cyan
    & $Godot --headless --path $runtime --script $cli -- $cliArgs 2>&1 |
        Where-Object { $_ -notmatch "^\s*Godot Engine v" } |
        ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  -> 失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
        $script:failed++
    } else {
        Write-Host "  -> 通过" -ForegroundColor Green
    }
}

Run-Phase "1. 定义注册表"     @("defs")
Run-Phase "2. 示例项目校验"   @("check", "tests/sample.ee.json")
Run-Phase "3. IR 回归"        @("regress")
Run-Phase "4. 端到端运行示例" @("run", "tests/sample.ee.json", "--frames", "60")

Write-Host ""
Write-Host "==== 5. 调度器测试（M2）====" -ForegroundColor Cyan
& $Godot --headless --path $runtime --script "tests/m2_tests.gd" 2>&1 |
    Where-Object { $_ -notmatch "^\s*Godot Engine v" } |
    Where-Object { $_ -match "^\s*(OK|FAIL|通过|==)" } |
    ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    Write-Host "  -> 失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
    $script:failed++
} else {
    Write-Host "  -> 通过" -ForegroundColor Green
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "M1 + M2 全部验收通过。" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failed 项失败。" -ForegroundColor Red
    exit 1
}
