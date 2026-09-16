$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 # fix SSL/TSL Error
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads crawl

$Repo = "madoiscool/BetterSteamTools"

Write-Host "Finding Steam..."
$registries = @(
    "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
    "HKLM:\SOFTWARE\Valve\Steam",
    "HKCU:\SOFTWARE\Valve\Steam"
)

$SteamPath = $null
foreach ($reg in $registries) {
    if (Test-Path $reg) {
        $path = (Get-ItemProperty -Path $reg -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
        if ((Test-Path $path) -and (Test-Path (Join-Path $path "steam.exe"))) {
            $SteamPath = $path
            break
        }
    }
}

if (-not $SteamPath) {
    Write-Host "Steam not found." -ForegroundColor Red
    exit 1
}

Write-Host "Steam found at: $SteamPath"

# Resolve the newest BetterSteamTools build. Every release ships a Debug and a
# Release zip; we always want Release. api.github.com is rate limited per IP and
# this installer runs on a lot of machines, so fall back to scraping the release
# pages (no limit) when the API says no.
Write-Host "Looking up the latest BetterSteamTools release..."
$assetUrl = $null
$tag      = $null

try {
    $rel   = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                               -Headers @{ "User-Agent" = "install-ost" } -TimeoutSec 30
    $tag   = $rel.tag_name
    $asset = $rel.assets | Where-Object { $_.name -like "*Release.zip" -and $_.name -notlike "*Debug*" } | Select-Object -First 1
    if ($asset) { $assetUrl = $asset.browser_download_url }
}
catch {
    Write-Host "GitHub API unavailable, falling back to the release pages..." -ForegroundColor Yellow
}

if (-not $assetUrl) {
    # /releases/latest redirects to /releases/tag/<tag>, which gets us the version.
    if (-not $tag) {
        $latest = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" -TimeoutSec 30 -UseBasicParsing
        $m = [regex]::Match($latest.Content, '/releases/tag/(v?[0-9][\w.+-]*)')
        if ($m.Success) { $tag = $m.Groups[1].Value }
    }
    if (-not $tag) {
        Write-Host "Couldn't work out the latest BetterSteamTools version." -ForegroundColor Red
        exit 1
    }

    # The asset list is lazy-loaded from expanded_assets, so ask for it directly.
    try {
        $assets = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/expanded_assets/$tag" -TimeoutSec 30 -UseBasicParsing
        $m = [regex]::Match($assets.Content, "/$Repo/releases/download/[^`"]*Release\.zip")
        if ($m.Success) { $assetUrl = "https://github.com" + $m.Value }
    }
    catch { }

    # Last resort: the asset naming has been stable across every release so far.
    if (-not $assetUrl) {
        $assetUrl = "https://github.com/$Repo/releases/download/$tag/OpenSteamTool-$tag-Release.zip"
    }
}

Write-Host "Downloading BetterSteamTools $tag (Release)..."
$zipFile = Join-Path $env:TEMP "BetterSteamTools-$tag-Release.zip"
$extract = Join-Path $env:TEMP "BetterSteamTools-$tag"
Invoke-WebRequest -Uri $assetUrl -OutFile $zipFile -TimeoutSec 120 -UseBasicParsing

if (Test-Path -LiteralPath $extract) {
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
}
Expand-Archive -LiteralPath $zipFile -DestinationPath $extract -Force

# The zip carries the build's .lib/.exp artifacts too; only the DLLs belong in Steam.
$dlls = Get-ChildItem -LiteralPath $extract -Filter "*.dll" -Recurse
if (-not ($dlls | Where-Object { $_.Name -eq "OpenSteamTool.dll" })) {
    Write-Host "That release didn't contain OpenSteamTool.dll - aborting." -ForegroundColor Red
    Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Stopping Steam..."
Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Installing..."
foreach ($dll in $dlls) {
    Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $SteamPath $dll.Name) -Force
}
Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue

# BetterSteamTools ships without a config, and OST won't read our lua files unless
# the toml points it at config\stplug-in. Leave an existing working one alone.
$tomlPath = Join-Path $SteamPath "opensteamtool.toml"
$tomlOk   = (Test-Path -LiteralPath $tomlPath) -and ((Get-Content -LiteralPath $tomlPath -Raw -ErrorAction SilentlyContinue) -match "stplug-in")
if (-not $tomlOk) {
    Write-Host "Writing opensteamtool.toml..."
    Set-Content -LiteralPath $tomlPath -Value "[lua]`r`npaths = [`"config\\stplug-in`"]" -Encoding ASCII -Force
}

$steamCfg = Join-Path $SteamPath "steam.cfg"
$steamCfgBak = Join-Path $SteamPath "steam.cfg.bak"
if (Test-Path -LiteralPath $steamCfg) {
    Write-Host "Renaming steam.cfg to steam.cfg.bak..."
    Move-Item -LiteralPath $steamCfg -Destination $steamCfgBak -Force -ErrorAction SilentlyContinue
}

Write-Host "Done! BetterSteamTools $tag installed successfully." -ForegroundColor Green

Write-Host "Starting Steam..."
Start-Process -FilePath (Join-Path $SteamPath "steam.exe")
