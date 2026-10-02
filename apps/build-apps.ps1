# Builds the three Electron apps for CML and stages them for the shared Electron runtime.
#
#   powershell -ExecutionPolicy Bypass -File apps\build-apps.ps1 [-Only desktoppet,liteeditor] [-SkipRuntime] [-Install]
#
# Output (consumed by ..\build.ps1, which copies it to dist\CML\apps):
#   apps\runtime\electron.exe ...                 shared Electron runtime (node_modules\electron\dist, locales trimmed to zh-CN / en-US)
#   apps\<id>\out\app\package.json                trimmed manifest ("main", identity, shipped deps only)
#   apps\desktoppet\out\app\{src,assets,node_modules\uiohook-napi,node_modules\node-gyp-build}
#   apps\liteeditor\out\app\{electron,dist,build\icon.png}                 (renderer deps are bundled by vite)
#   apps\litereader\out\app\{electron,dist,build\icon.png,node_modules\<word-extractor + music-metadata closure>}
#
# CML launches an app as:  apps\runtime\electron.exe apps\<id>\app   (env CML_THEME_FILE -> %APPDATA%\CML\theme.json)
# All three apps must use the same Electron version; the script fails if they differ.
param(
  [string[]]$Only = @("desktoppet", "liteeditor", "litereader"),
  [switch]$SkipRuntime,
  # run `npm ci` (npmmirror) even when node_modules already exists
  [switch]$Install
)
$ErrorActionPreference = "Stop"
$apps = $PSScriptRoot

# The system PATH on the build machine contains a stray quote that breaks native tooling.
$env:PATH = (($env:PATH -replace '"', '') -split ';' | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ';'
if (-not $env:npm_config_registry) { $env:npm_config_registry = "https://registry.npmmirror.com" }
if (-not $env:ELECTRON_MIRROR) { $env:ELECTRON_MIRROR = "https://npmmirror.com/mirrors/electron/" }

function Invoke-Native([string]$what, [scriptblock]$block) {
  & $block
  if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}
function Get-Size([string]$path) {
  $b = (Get-ChildItem $path -Recurse -File -Force | Measure-Object Length -Sum).Sum
  "{0:N1} MB" -f ($b / 1MB)
}

$all = @("desktoppet", "liteeditor", "litereader")
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($id in $Only) { if ($all -notcontains $id) { throw "unknown app '$id' (expected: $($all -join ', '))" } }

# ---- dependencies + one Electron version for everybody ----
$versions = @{}
foreach ($id in $all) {
  $dir = Join-Path $apps $id
  $needed = ($Only -contains $id) -or (-not $SkipRuntime)
  if (-not $needed) { continue }
  if ($Install -or -not (Test-Path (Join-Path $dir "node_modules\electron\dist\electron.exe"))) {
    Write-Host "== npm ci ($id)" -ForegroundColor Cyan
    Push-Location $dir
    try { Invoke-Native "npm ci ($id)" { npm ci --no-audit --no-fund } } finally { Pop-Location }
  }
  $versions[$id] = (Get-Content (Join-Path $dir "node_modules\electron\package.json") -Raw | ConvertFrom-Json).version
}
$distinct = @($versions.Values | Sort-Object -Unique)
Write-Host ("Electron: " + (($versions.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '))
if ($distinct.Count -ne 1) { throw "Electron versions differ between apps ($($distinct -join ', ')); align package.json and reinstall" }
$electronVersion = $distinct[0]
if (-not $electronVersion.StartsWith("44.")) { Write-Warning "Expected Electron 44.x, found $electronVersion" }

# ---- build + stage each app ----
foreach ($id in $Only) {
  $dir = Join-Path $apps $id
  Write-Host "== $id" -ForegroundColor Cyan
  Push-Location $dir
  try {
    if ($id -ne "desktoppet") {
      # postinstall copies runtime assets (KaTeX fonts, pdf.js cmaps / wasm, libarchive worker ...) to public\vendor
      Invoke-Native "prepare-assets ($id)" { node scripts/prepare-assets.mjs }
      Invoke-Native "vite build ($id)" { node node_modules/vite/bin/vite.js build --logLevel warn }
    } else {
      Get-ChildItem src -Recurse -Filter *.js | ForEach-Object { Invoke-Native "node --check $($_.Name)" { node --check $_.FullName } }
    }
    Invoke-Native "stage ($id)" { node (Join-Path $apps "stage-app.mjs") $id }
  } finally { Pop-Location }
}

# ---- shared runtime ----
if (-not $SkipRuntime) {
  Write-Host "== runtime (Electron $electronVersion)" -ForegroundColor Cyan
  $from = Join-Path $apps "liteeditor\node_modules\electron\dist"
  $runtime = Join-Path $apps "runtime"
  if (Test-Path $runtime) { Remove-Item $runtime -Recurse -Force }
  # everything except the unneeded locales (resources\default_app.asar is required: it loads `electron.exe <app dir>`)
  Copy-Item $from $runtime -Recurse
  Get-ChildItem (Join-Path $runtime "locales") -File | Where-Object { @("zh-CN.pak", "en-US.pak") -notcontains $_.Name } | Remove-Item -Force
  if (-not (Test-Path (Join-Path $runtime "resources\default_app.asar"))) { throw "runtime is missing resources\default_app.asar" }
  Set-Content (Join-Path $runtime "version") $electronVersion -NoNewline -Encoding ascii
}

# ---- summary ----
Write-Host ""
Write-Host "Staged:" -ForegroundColor Green
if (Test-Path (Join-Path $apps "runtime\electron.exe")) { Write-Host ("  apps\runtime            " + (Get-Size (Join-Path $apps "runtime"))) }
foreach ($id in $all) {
  $o = Join-Path $apps "$id\out\app"
  if (Test-Path $o) { Write-Host ("  apps\$id\out\app".PadRight(26) + (Get-Size $o)) }
}
Write-Host "Run:  apps\runtime\electron.exe apps\<id>\out\app"
