#requires -Version 5.1
<#
.SYNOPSIS
  Builds the BedrockTool CLI (no GUI tag) to tools\bedrocktool\out\bedrocktool.exe for CML,
  from the source in this folder only.

.DESCRIPTION
  Toolchain: uses -GoRoot if given, else `go` on PATH if it is new enough, else downloads the
  official Go release (-GoVersion) into tools\bedrocktool\.toolchain (gitignored) from
  golang.google.cn (falls back to go.dev). Modules are fetched through GOPROXY
  (default https://goproxy.cn,https://proxy.golang.org,direct) into out\.work\go-mod-cache and
  verified against go.sum / the checksum DB (GOSUMDB=sum.golang.google.cn).

  The go.work workspace in this folder pins the forked gophertunnel / dragonfly / go-nethernet /
  go-raknet modules, so only third-party dependencies are downloaded.

  subcommands\resourcepack-d\resourcepack-d.go is a git-crypt blob; it is only compiled with the
  `packs` build tag (see subcommands\resourcepack-stub.go). We never pass that tag.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\bedrocktool\build.ps1
  powershell -File tools\bedrocktool\build.ps1 -SkipTests -Version v26.53-cml1
#>
[CmdletBinding()]
param(
    [string]$GoRoot = '',
    [string]$GoVersion = '1.27.1',
    [string]$GoProxy = $(if ($env:GOPROXY) { $env:GOPROXY } else { 'https://goproxy.cn,https://proxy.golang.org,direct' }),
    [string]$ModCache = '',
    [string]$Version = 'v26.52-cml',
    [string]$Out = '',
    [switch]$SkipTests
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Src = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $Out) { $Out = Join-Path $Src 'out' }
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$Work = Join-Path $Out '.work'
New-Item -ItemType Directory -Path $Work -Force | Out-Null
if (-not $ModCache) { $ModCache = Join-Path $Work 'go-mod-cache' }
if (-not (Test-Path -LiteralPath (Join-Path $Src 'go.work'))) { throw "Missing: $(Join-Path $Src 'go.work')" }

# go.work needs Go >= 1.26
function Test-GoVersion([string]$exe) {
    try { $v = (& $exe env GOVERSION) 2>$null } catch { return $false }
    if ($v -notmatch '^go(\d+)\.(\d+)') { return $false }
    return ([int]$Matches[1] -gt 1) -or ([int]$Matches[2] -ge 26)
}

if (-not $GoRoot) {
    $onPath = Get-Command go.exe -ErrorAction SilentlyContinue
    if ($onPath -and (Test-GoVersion $onPath.Source)) {
        $GoRoot = Split-Path (Split-Path $onPath.Source)
    } else {
        $GoRoot = Join-Path $Src ".toolchain\go$GoVersion"
        if (-not (Test-Path -LiteralPath (Join-Path $GoRoot 'go\bin\go.exe'))) {
            $zipName = "go$GoVersion.windows-amd64.zip"
            $zip = Join-Path $Work $zipName
            $ok = $false
            foreach ($base in @('https://golang.google.cn/dl/', 'https://go.dev/dl/')) {
                try {
                    Write-Output "Downloading $base$zipName"
                    Invoke-WebRequest -Uri "$base$zipName" -OutFile $zip -UseBasicParsing
                    # verify against the official checksum list
                    $meta = Invoke-RestMethod -Uri "${base}?mode=json&include=all" -UseBasicParsing
                    $want = ($meta | ForEach-Object { $_.files } | Where-Object { $_.filename -eq $zipName } | Select-Object -First 1).sha256
                    $got = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($want -and $want -ne $got) { throw "checksum mismatch ($got != $want)" }
                    $ok = $true
                    break
                } catch { Write-Warning "$base failed: $_" }
            }
            if (-not $ok) { throw "Could not download Go $GoVersion" }
            New-Item -ItemType Directory -Path $GoRoot -Force | Out-Null
            Expand-Archive -LiteralPath $zip -DestinationPath $GoRoot -Force
            Remove-Item -LiteralPath $zip -Force
        }
        $GoRoot = Join-Path $GoRoot 'go'
    }
}
$GoExe = Join-Path $GoRoot 'bin\go.exe'
if (-not (Test-Path -LiteralPath $GoExe)) { throw "Missing: $GoExe" }

$env:GOROOT = $GoRoot
$env:Path = "$(Join-Path $GoRoot 'bin');$env:Path"
$env:GOTOOLCHAIN = 'local'
$env:GOWORK = Join-Path $Src 'go.work'
$env:GOPROXY = $GoProxy
$env:GOSUMDB = 'sum.golang.google.cn'
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
    & $GoExe mod download
    if ($LASTEXITCODE -ne 0) { throw 'go mod download failed' }
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
