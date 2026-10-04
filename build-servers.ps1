# Builds and packages the three servers that ship with CML:
#   CMLS    (server/                — Java TCP + Bedrock UDP multiplayer relay)
#   Aurora  (modules/aurora/server  — party games server, needs modules/aurora/shared)
#   Pulse   (modules/pulse/server   — text / voice chat server, needs modules/pulse/shared)
#
# The only place servers are built — build.ps1 does not output CMLS (run it with -WithServers to call this).
# Output (dist\servers\):
#   CMLS-<ver>-windows-x64.zip  / Aurora-server-<ver>-windows-x64.zip / Pulse-server-<ver>-windows-x64.zip   exe + start script
#   (Aurora also ships its browser client in web\ — served on the web port, default 7790)
#   CML-servers-src-<ver>.zip   source of all three servers (+ shared libs, core) — buildable with `dart compile exe`
#
#   powershell -ExecutionPolicy Bypass -File build-servers.ps1 [-Version 0.2.4] [-SkipTests] [-SourceOnly]
param([string]$Version = "0.2.4", [switch]$SkipTests, [switch]$SourceOnly)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$env:PATH = (($env:PATH -replace '"','') -split ';' | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ';'
if (Test-Path "D:\Tools\flutter\bin\flutter.bat") { $env:PATH = "D:\Tools\flutter\bin;$env:PATH" }
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn" }

$out = Join-Path $root "dist\servers"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null

# name, package dir, entry point, exe name, start script
$servers = @(
  @{ Name = "CMLS";          Dir = "server";                Entry = "bin\cmls.dart";          Exe = "cmls.exe";          Bat = $null },
  @{ Name = "Aurora-server"; Dir = "modules\aurora\server"; Entry = "bin\aurora_server.dart"; Exe = "aurora_server.exe"; Bat = "启动服务器.bat" },
  @{ Name = "Pulse-server";  Dir = "modules\pulse\server";  Entry = "bin\pulse_server.dart";  Exe = "pulse_server.exe";  Bat = "启动服务器.bat" }
)

if (-not $SourceOnly) {
  foreach ($s in $servers) {
    Write-Host "== $($s.Name) ==" -ForegroundColor Cyan
    Push-Location (Join-Path $root $s.Dir)
    dart pub get | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$($s.Name) dependencies failed" }
    if (-not $SkipTests) { dart test; if ($LASTEXITCODE -ne 0) { throw "$($s.Name) tests failed" } }
    $stage = Join-Path $out $s.Name
    New-Item -ItemType Directory -Force $stage | Out-Null
    dart compile exe $s.Entry -o (Join-Path $stage $s.Exe)
    if ($LASTEXITCODE -ne 0) { throw "$($s.Name) build failed" }
    if ($s.Bat) { Copy-Item $s.Bat $stage }
    Pop-Location
    if ($s.Name -eq "Aurora-server") {
      # browser client: static files served by aurora_server on its web port.
      # --no-web-resources-cdn keeps CanvasKit local (gstatic is unreachable on many networks)
      Push-Location (Join-Path $root "modules\aurora\client")
      flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
      if ($LASTEXITCODE -ne 0) { throw "Aurora web client build failed" }
      Copy-Item "build\web" (Join-Path $stage "web") -Recurse
      Pop-Location
    }
    Compress-Archive "$stage\*" (Join-Path $out "$($s.Name)-$Version-windows-x64.zip")
  }
}

Write-Host "== source package ==" -ForegroundColor Cyan
# Source dirs needed to build every server (path dependencies included). Runtime data / secrets are excluded.
$srcDirs = @("server", "core", "modules\aurora\server", "modules\aurora\shared", "modules\aurora\client", "modules\pulse\server", "modules\pulse\shared")
$exclude = '\\(\.dart_tool|build|data|replays|words)\\|server_identity\.key$|\.env$|aurora_server\.json$|pulse_server\.json$|\.exe$'
$srcStage = Join-Path $out "src\CML-servers-src-$Version"
foreach ($d in $srcDirs) {
  Get-ChildItem (Join-Path $root $d) -Recurse -File | Where-Object { $_.FullName -notmatch $exclude } | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length + 1)
    $dst = Join-Path $srcStage $rel
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item $_.FullName $dst
  }
}
Copy-Item (Join-Path $root "build-servers.ps1") $srcStage
@"
CML 服务端源码（CMLS / Aurora / Pulse）

  server\                 CMLS 联机中继（Java TCP + 基岩版 UDP），依赖 core\
  modules\aurora\server\  Aurora 小游戏服务端，依赖 modules\aurora\shared\
  modules\pulse\server\   Pulse 语音聊天服务端，依赖 modules\pulse\shared\

构建（需要 Dart 3.9+ 或 Flutter 自带的 dart）：
  cd server;                dart pub get; dart compile exe bin\cmls.dart -o cmls.exe
  cd modules\aurora\server; dart pub get; dart compile exe bin\aurora_server.dart -o aurora_server.exe
  cd modules\pulse\server;  dart pub get; dart compile exe bin\pulse_server.dart -o pulse_server.exe
或直接运行 build-servers.ps1。首次启动各服务端会生成 server_identity.key（服务器身份私钥，请备份、勿外传）。
"@ | Set-Content (Join-Path $srcStage "README.txt") -Encoding UTF8
Compress-Archive $srcStage (Join-Path $out "CML-servers-src-$Version.zip")
Remove-Item (Join-Path $out "src") -Recurse -Force
Get-ChildItem $out -File | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name } | Set-Content (Join-Path $out "SHA256SUMS.txt")
Write-Host "完成：$out" -ForegroundColor Green
