# analyze-sb3.ps1
#
# 统计一个 .sb3（或解包后的 project.json）用了哪些积木及数量，
# 用来评估"要跑通社区项目需要实现多少 IR 节点"。
#
# 用法：
#   .\analyze-sb3.ps1 -Path .\some-game.sb3
#   .\analyze-sb3.ps1 -Path .\unpacked\project.json

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    # 对照表：Gandi/TurboWarp irgen.js，用于标出"已能编译为 IR"的积木
    [string]$IrgenPath = "D:\桌面\ee\scratch\Gandi-IDE\scratch-vm\src\compiler\irgen.js"
)

$ErrorActionPreference = "Stop"

$json = $null

if ($Path -like "*.sb3" -or $Path -like "*.zip") {
    # .sb3 就是 zip，内含 project.json
    $tmp = Join-Path $env:TEMP ("sb3_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $Path).Path, $tmp)
    $pj = Join-Path $tmp "project.json"
    if (-not (Test-Path $pj)) { throw "包内未找到 project.json" }
    $json = Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$opcodes = @{}
foreach ($target in $json.targets) {
    foreach ($prop in $target.blocks.PSObject.Properties) {
        $b = $prop.Value
        if ($null -ne $b.opcode) {
            if ($opcodes.ContainsKey($b.opcode)) { $opcodes[$b.opcode]++ }
            else { $opcodes[$b.opcode] = 1 }
        }
    }
}

$total = ($opcodes.Values | Measure-Object -Sum).Sum

Write-Host ""
Write-Host "=== 项目概览 ===" -ForegroundColor Cyan
Write-Host ("角色数      : {0}" -f $json.targets.Count)
Write-Host ("积木总数    : {0}" -f $total)
Write-Host ("不同 opcode : {0}" -f $opcodes.Count)
Write-Host ("扩展        : {0}" -f (($json.extensions | Sort-Object -Unique) -join ", "))

# 与 irgen.js 中已支持的积木对照
if (Test-Path $IrgenPath) {
    $irgen = Get-Content $IrgenPath -Raw
    $supported = @()
    $unsupported = @()
    foreach ($op in $opcodes.Keys) {
        if ($irgen -match [regex]::Escape("case '$op'")) { $supported += $op }
        else { $unsupported += $op }
    }
    Write-Host ""
    Write-Host "=== 可编译为 IR（Gandi/TW 已支持）===" -ForegroundColor Green
    Write-Host ("  {0} 种" -f $supported.Count)
    if ($unsupported.Count -gt 0) {
        Write-Host ""
        Write-Host "=== 需走解释器兜底 / 自研 ===" -ForegroundColor Yellow
        $unsupported | Sort-Object | ForEach-Object {
            Write-Host ("  {0,-40} x{1}" -f $_, $opcodes[$_])
        }
    }
}

Write-Host ""
Write-Host "=== 按使用频次排序 ===" -ForegroundColor Cyan
$opcodes.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    Write-Host ("  {0,-40} x{1}" -f $_.Key, $_.Value)
}
