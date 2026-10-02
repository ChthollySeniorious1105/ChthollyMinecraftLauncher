#requires -Version 5.1
<#
.SYNOPSIS
  Builds the BedrockTool CLI (no GUI tag) to tools\bedrocktool\out\bedrocktool.exe for CML.

.DESCRIPTION
  Fully offline build: uses a local Go toolchain and a pre-populated module cache
  (GOTOOLCHAIN=local, GOPROXY=off, GOSUMDB=off). The go.work workspace in this folder
  pins the forked gophertunnel / dragonfly / go-nethernet / go-raknet modules.

  subcommands\resourcepack-d\resourcepack-d.go is a git-crypt blob; it is only compiled
  with the `packs` build tag (see subcommands\resourcepack-stub.go). We never pass that tag.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\bedrocktool\build.ps1
  powershell -File tools\bedrocktool\build.ps1 -SkipTests -Version v26.53-cml1
#>
[CmdletBinding()]
param(
    [string]$GoRoot = 'D:\Server\Others\Sample\BedrockTools\go',
    [string]$ModCache = 'D:\Server\Others\Sample\BedrockTools\work\go-mod-cache',
    [string]$Version = 'v26.52-cml',
    [string]$Out = '',
    [switch]$SkipTests
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Src = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $Out) { $Out = Join-Path $Src 'out' }
$GoExe = Join-Path $GoRoot 'bin\go.exe'
foreach ($need in @($GoExe, $ModCache, (Join-Path $Src 'go.work'))) {
    if (-not (Test-Path -LiteralPath $need)) { throw "Missing: $need" }
}
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$Work = Join-Path $Out '.work'
New-Item -ItemType Directory -Path $Work -Force | Out-Null

$env:GOROOT = $GoRoot
$env:Path = "$(Join-Path $GoRoot 'bin');$env:Path"
$env:GOTOOLCHAIN = 'local'
$env:GOWORK = Join-Path $Src 'go.work'
$env:GOPROXY = 'off'
$env:GOSUMDB = 'off'
$env:GOMODCACHE = $ModCache
$env:GOCACHE = Join-Path $Work 'go-build-cache'
$env:GOPATH = Join-Path $Work 'go-path'
$env:CGO_ENABLED = '0'
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'

$goVersion = & $GoExe version
Write-Output "GO=$goVersion"

Push-Location $Src
try {
    if (-not $SkipTests) {
        & $GoExe test -count=1 ./cmd/bedrocktool
        if ($LASTEXITCODE -ne 0) { throw 'go test ./cmd/bedrocktool failed' }
    }
    $exe = Join-Path $Out 'bedrocktool.exe'
    $ld = "-s -w -X github.com/bedrock-tool/bedrocktool/utils.Version=$Version -X github.com/bedrock-tool/bedrocktool/utils.CmdName=bedrocktool"
    & $GoExe build -buildvcs=false -trimpath -ldflags $ld -o $exe ./cmd/bedrocktool
    if ($LASTEXITCODE -ne 0) { throw 'go build failed' }

    # Smoke test. bedrocktool chdirs to its data dir (cwd on Windows), so run it inside out\.work.
    Push-Location $Work
    try {
        $help = & $exe help 2>&1
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code -ne 0) { $help | Write-Output; throw "bedrocktool.exe help exited with $code" }
    $help | Select-Object -First 30 | Write-Output

    $info = Get-Item -LiteralPath $exe
    $sha = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{ version = $Version; go = "$goVersion"; size = $info.Length; sha256 = $sha; built = (Get-Date).ToString('s') } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Out 'BUILD_INFO.json') -Encoding UTF8
    Write-Output "EXE=$exe"
    Write-Output "SIZE=$($info.Length)"
    Write-Output "SHA256=$sha"
} finally { Pop-Location }
