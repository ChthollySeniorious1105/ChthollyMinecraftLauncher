# CML build script (Windows). Produces dist\:
#   dist\CML\cml.exe (+ Flutter runtime, pulse_native.dll + Opus / ONNX Runtime / DirectML)   launcher
#   dist\CML\tools\bedrocktool\bedrocktool.exe      BedrockTool CLI (Bedrock world/skin/packet tools)
#   dist\CML\tools\netease\NeMcDecrypter.exe         NetEase Bedrock save decrypter
#   dist\CML\tools\lumikeymapper\LumiKeyMapper.exe   key mapper (self-contained .NET)
#   dist\CML\apps\runtime\electron.exe + apps\<desktoppet|liteeditor|litereader>\app
#   dist\CML-<ver>-windows-x64.zip                                          main package
#   dist\CML-addon-<id>-<ver>.zip + dist\cml-addons.json                   optional add-ons (AI model weights)
#
# Servers (CMLS, Aurora, Pulse) are packaged only by build-servers.ps1 → dist\servers\.
# Pass -WithServers to run it at the end of this script.
#
# Code signing (recommended — unsigned exes are often flagged by Defender's ML heuristics):
#   $env:CML_SIGN_PFX = "D:\certs\cml.pfx"; $env:CML_SIGN_PASSWORD = "..."
#   or $env:CML_SIGN_THUMBPRINT = "<cert in CurrentUser\My>"
# Every exe/dll we build is signed with SHA-256 and an RFC 3161 timestamp.
param(
  [switch]$SkipTests, [switch]$NoZip, [switch]$SkipTools, [switch]$SkipApps, [switch]$SkipAddons, [switch]$WithServers,
  [string]$Version = "0.2.1", [string]$MsaClientId = $env:CML_MSA_CLIENT_ID,
  # Pulse AI weights (not in git): base models and optional voices.
  [string]$PulseModels = "$PSScriptRoot\modules\pulse\client\native\models",
  [string]$PulseVoices = ""
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# The system PATH on the build machine contains a stray quote that breaks vcvars / native asset hooks.
$env:PATH = (($env:PATH -replace '"','') -split ';' | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ';'
if (Test-Path "D:\Tools\flutter\bin\flutter.bat") { $env:PATH = "D:\Tools\flutter\bin;$env:PATH" }
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn" }
if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn" }

$dist = Join-Path $root "dist"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$dist\CML" | Out-Null

function Sign-Files([string[]]$files) {
  $pfx = $env:CML_SIGN_PFX; $thumb = $env:CML_SIGN_THUMBPRINT
  if (-not $pfx -and -not $thumb) { Write-Warning "未配置代码签名证书，生成的 exe 未签名（可能被杀毒软件误报）"; return }
  $signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" | Sort-Object FullName | Select-Object -Last 1
  if (-not $signtool) { throw "找不到 signtool.exe（安装 Windows SDK）" }
  $signArgs = @("sign", "/fd", "SHA256", "/tr", "http://timestamp.digicert.com", "/td", "SHA256", "/d", "ChthollyMinecraftLauncher")
  if ($pfx) { $signArgs += @("/f", $pfx); if ($env:CML_SIGN_PASSWORD) { $signArgs += @("/p", $env:CML_SIGN_PASSWORD) } } else { $signArgs += @("/sha1", $thumb) }
  & $signtool.FullName @signArgs @files
  if ($LASTEXITCODE -ne 0) { throw "签名失败" }
}

function Invoke-Step([string]$name, [scriptblock]$body) {
  Write-Host "== $name ==" -ForegroundColor Cyan
  & $body
}

Invoke-Step "core" {
  Push-Location "$root\core"; dart pub get
  if (-not $SkipTests) { dart test; if ($LASTEXITCODE -ne 0) { throw "core tests failed" } }
  Pop-Location
}

# CMLS shares core\ with the launcher, so its tests run here; the exe itself is built by build-servers.ps1.
if (-not $SkipTests) {
  Invoke-Step "CMLS tests" {
    Push-Location "$root\server"; dart pub get
    dart test; if ($LASTEXITCODE -ne 0) { throw "server tests failed" }
    Pop-Location
  }
}

Invoke-Step "launcher" {
  Push-Location "$root\launcher"
  flutter pub get
  if (-not $SkipTests) { flutter test test\i18n_test.dart; if ($LASTEXITCODE -ne 0) { throw "launcher tests failed" } }
  $defines = @("--dart-define=CML_VERSION=$Version", "--dart-define=CML_REPO=ChthollySeniorious1105/ChthollyMinecraftLauncher")
  if ($MsaClientId) { $defines += "--dart-define=CML_MSA_CLIENT_ID=$MsaClientId" }
  flutter build windows --release --no-tree-shake-icons --build-name=$Version @defines
  if ($LASTEXITCODE -ne 0) { throw "launcher build failed" }
  Copy-Item "build\windows\x64\runner\Release\*" "$dist\CML" -Recurse
  Copy-Item "$root\modules\pulse\client\native\third_party\licenses" "$dist\CML\licenses" -Recurse -Force
  # AI models are an add-on; never ship them in the main package
  Remove-Item "$dist\CML\ai\models" -Recurse -Force -ErrorAction SilentlyContinue
  Pop-Location
}

if (-not $SkipTools) {
  Invoke-Step "BedrockTool" {
    $a = @("-ExecutionPolicy", "Bypass", "-File", "$root\tools\bedrocktool\build.ps1")
    if ($SkipTests) { $a += "-SkipTests" }
    powershell @a
    if ($LASTEXITCODE -ne 0) { throw "bedrocktool build failed" }
    New-Item -ItemType Directory -Force "$dist\CML\tools\bedrocktool" | Out-Null
    Copy-Item "$root\tools\bedrocktool\out\bedrocktool.exe" "$dist\CML\tools\bedrocktool\"
    Copy-Item "$root\tools\bedrocktool\LICENSE" "$dist\CML\tools\bedrocktool\LICENSE.txt"
  }
  Invoke-Step "NetEase decrypter" {
    New-Item -ItemType Directory -Force "$dist\CML\tools\netease" | Out-Null
    Copy-Item "$root\tools\netease\NeMcDecrypter.exe" "$dist\CML\tools\netease\"
  }
  Invoke-Step "LumiKeyMapper" {
    $a = @("-ExecutionPolicy", "Bypass", "-File", "$root\tools\lumikeymapper\build.ps1")
    powershell @a
    if ($LASTEXITCODE -ne 0) { throw "LumiKeyMapper build failed" }
    New-Item -ItemType Directory -Force "$dist\CML\tools\lumikeymapper" | Out-Null
    Copy-Item "$root\tools\lumikeymapper\out\LumiKeyMapper.exe" "$dist\CML\tools\lumikeymapper\"
  }
}

if (-not $SkipApps) {
  Invoke-Step "Electron apps" {
    powershell -ExecutionPolicy Bypass -File "$root\apps\build-apps.ps1"
    if ($LASTEXITCODE -ne 0) { throw "apps build failed" }
    New-Item -ItemType Directory -Force "$dist\CML\apps" | Out-Null
    Copy-Item "$root\apps\runtime" "$dist\CML\apps\runtime" -Recurse
    foreach ($id in @("desktoppet", "liteeditor", "litereader")) {
      New-Item -ItemType Directory -Force "$dist\CML\apps\$id" | Out-Null
      Copy-Item "$root\apps\$id\out\app" "$dist\CML\apps\$id\app" -Recurse
    }
  }
}

$toSign = @("$dist\CML\cml.exe", "$dist\CML\pulse_native.dll")
foreach ($f in @("$dist\CML\tools\bedrocktool\bedrocktool.exe", "$dist\CML\tools\lumikeymapper\LumiKeyMapper.exe")) { if (Test-Path $f) { $toSign += $f } }
Sign-Files $toSign

if (-not $NoZip) {
  Invoke-Step "zip" {
    Compress-Archive "$dist\CML\*" "$dist\CML-$Version-windows-x64.zip"
  }
}

# ---- optional add-ons: AI model weights, split from the main zip ----
if (-not $SkipAddons) {
  Invoke-Step "add-ons" {
    $addons = @()
    function Add-Addon([string]$id, [string]$src, [string]$sub, [string]$pattern) {
      if (-not $src -or -not (Test-Path $src)) { Write-Warning "跳过分包 ${id}：找不到 $src"; return $null }
      $files = Get-ChildItem $src -File -Filter $pattern
      if (-not $files) { Write-Warning "跳过分包 ${id}：$src 中没有 $pattern"; return $null }
      $stage = Join-Path $dist "addon-stage\$id\$sub"
      New-Item -ItemType Directory -Force $stage | Out-Null
      $files | Copy-Item -Destination $stage
      $md = Join-Path $src "MODELS.md"; if (Test-Path $md) { Copy-Item $md $stage }
      $zip = Join-Path $dist "CML-addon-$id-$Version.zip"
      # weights barely compress; store keeps zipping fast
      Compress-Archive "$dist\addon-stage\$id\*" $zip -CompressionLevel NoCompression
      $f = Get-Item $zip
      return [ordered]@{ id = $id; version = $Version; asset = $f.Name; size = $f.Length; sha256 = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() }
    }
    $m = Add-Addon "pulse-ai-models" $PulseModels "models" "*.onnx"; if ($m) { $addons += $m }
    $v = Add-Addon "pulse-ai-voices" $PulseVoices "voices" "*.onnx"; if ($v) { $addons += $v }
    Remove-Item "$dist\addon-stage" -Recurse -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText("$dist\cml-addons.json", (@{ version = $Version; addons = $addons } | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
  }
}

if ($WithServers) {
  Invoke-Step "servers" {
    $a = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "build-servers.ps1"), "-Version", $Version)
    if ($SkipTests) { $a += "-SkipTests" }
    powershell @a
    if ($LASTEXITCODE -ne 0) { throw "server build failed" }
  }
}

Get-ChildItem $dist -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" } | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name } | Set-Content "$dist\SHA256SUMS.txt"
Write-Host "完成：$dist" -ForegroundColor Green
