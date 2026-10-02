# CML build script (Windows). Produces dist\:
#   dist\CML\cml.exe (+ Flutter runtime)        launcher
#   dist\CMLS\cmls.exe                          multiplayer relay server
#   dist\CML-<ver>-windows-x64.zip / dist\CMLS-<ver>-windows-x64.zip
#
# Code signing (recommended — unsigned exes are often flagged by Defender's ML heuristics):
#   $env:CML_SIGN_PFX = "D:\certs\cml.pfx"; $env:CML_SIGN_PASSWORD = "..."
#   or $env:CML_SIGN_THUMBPRINT = "<cert in CurrentUser\My>"
# Every exe/dll we build is signed with SHA-256 and an RFC 3161 timestamp.
param([switch]$SkipTests, [switch]$NoZip, [string]$Version = "0.1.0", [string]$MsaClientId = $env:CML_MSA_CLIENT_ID)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

$env:PATH = (($env:PATH -replace '"','') -split ';' | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ';'
if (Test-Path "D:\Tools\flutter\bin\flutter.bat") { $env:PATH = "D:\Tools\flutter\bin;$env:PATH" }
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn" }
if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn" }

$dist = Join-Path $root "dist"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$dist\CML", "$dist\CMLS" | Out-Null

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

Write-Host "== core ==" -ForegroundColor Cyan
Push-Location "$root\core"; dart pub get
if (-not $SkipTests) { dart test; if ($LASTEXITCODE -ne 0) { throw "core tests failed" } }
Pop-Location

Write-Host "== CMLS ==" -ForegroundColor Cyan
Push-Location "$root\server"; dart pub get
if (-not $SkipTests) { dart test; if ($LASTEXITCODE -ne 0) { throw "server tests failed" } }
dart compile exe bin\cmls.dart -o "$dist\CMLS\cmls.exe"
Pop-Location

Write-Host "== launcher ==" -ForegroundColor Cyan
Push-Location "$root\launcher"
flutter pub get
$defines = @("--dart-define=CML_VERSION=$Version")
if ($MsaClientId) { $defines += "--dart-define=CML_MSA_CLIENT_ID=$MsaClientId" }
flutter build windows --release --no-tree-shake-icons --build-name=$Version @defines
if ($LASTEXITCODE -ne 0) { throw "launcher build failed" }
Copy-Item "build\windows\x64\runner\Release\*" "$dist\CML" -Recurse
Pop-Location

Sign-Files @("$dist\CML\cml.exe", "$dist\CMLS\cmls.exe")

if (-not $NoZip) {
  Compress-Archive "$dist\CML\*" "$dist\CML-$Version-windows-x64.zip"
  Compress-Archive "$dist\CMLS\*" "$dist\CMLS-$Version-windows-x64.zip"
}
Get-ChildItem $dist -File | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name } | Set-Content "$dist\SHA256SUMS.txt"
Write-Host "完成：$dist" -ForegroundColor Green
