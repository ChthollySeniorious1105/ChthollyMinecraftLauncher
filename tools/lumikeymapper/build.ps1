param([switch]$SkipPublish, [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
# A stray double quote in PATH breaks some native build tools.
$env:PATH = $env:PATH -replace '"', ''

dotnet build LumiKeyMapper.sln -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
if (-not $SkipTests) {
    dotnet run --project LumiKeyMapper.Tests -c Release --no-build
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
    dotnet run --project LumiKeyMapper.UiTests -c Release --no-build -- artifacts
    if ($LASTEXITCODE -ne 0) { throw 'UI checks failed.' }
}
if (-not $SkipPublish) {
    # Self-contained single-file exe, bundled by the CML launcher from tools/lumikeymapper/out/.
    $out = Join-Path $PSScriptRoot 'out'
    $staging = Join-Path $PSScriptRoot 'obj/publish-win-x64'
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    dotnet publish LumiKeyMapper/LumiKeyMapper.csproj -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
        -p:DebugType=None -p:DebugSymbols=false -o $staging --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
    $exe = Join-Path $staging 'LumiKeyMapper.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Publish did not produce LumiKeyMapper.exe.' }
    Copy-Item -LiteralPath $exe -Destination (Join-Path $out 'LumiKeyMapper.exe') -Force
    Remove-Item -LiteralPath $staging -Recurse -Force
    $size = [math]::Round((Get-Item (Join-Path $out 'LumiKeyMapper.exe')).Length / 1MB, 1)
    Write-Output "Ready: out/LumiKeyMapper.exe ($size MB)"
}
