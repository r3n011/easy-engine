# 拉取 WebView2 SDK（只取编译/链接需要的两样东西）。
#
# 为什么不入库：它是微软的第三方二进制包，个头不小（约 14MB），
# 而且版本可以随时换。跑到 modules/easyblocks/thirdparty/webview2/，
# 那个目录在 .gitignore 里。
#
# 用法： powershell -ExecutionPolicy Bypass -File tools\fetch-webview2.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "modules\easyblocks\thirdparty\webview2"
$header = Join-Path $dest "include\WebView2.h"
$lib = Join-Path $dest "x64\WebView2Loader.dll"

if ((Test-Path $header) -and (Test-Path $lib)) {
    Write-Host "WebView2 SDK 已存在，跳过下载。"
    exit 0
}

$version = "1.0.4314.35"
$url = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$version/microsoft.web.webview2.$version.nupkg"
$tmp = Join-Path $env:TEMP "easyblocks-webview2"
$nupkg = Join-Path $tmp "webview2.zip"

Write-Host "下载 WebView2 SDK $version ..."
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing -TimeoutSec 300

if (Test-Path $tmp\extract) { Remove-Item $tmp\extract -Recurse -Force }
Expand-Archive -Path $nupkg -DestinationPath (Join-Path $tmp "extract") -Force

$src = Join-Path $tmp "extract\build\native"
New-Item -ItemType Directory -Force -Path (Join-Path $dest "include") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dest "x64") | Out-Null
Copy-Item (Join-Path $src "include\WebView2.h") (Join-Path $dest "include") -Force
Copy-Item (Join-Path $src "include\WebView2EnvironmentOptions.h") (Join-Path $dest "include") -Force
Copy-Item (Join-Path $src "x64\WebView2Loader.dll") (Join-Path $dest "x64") -Force

Remove-Item $tmp -Recurse -Force

Write-Host "WebView2 SDK 就绪：modules\easyblocks\thirdparty\webview2"
