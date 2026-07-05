$ErrorActionPreference = "Stop"

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

Write-Host "Downloading ost.zip..."
$zipFile = Join-Path $SteamPath "ost.zip"
Invoke-WebRequest -Uri "https://github.com/madoiscool/lt_api_links/releases/download/ost-148/ost.zip" -OutFile $zipFile -TimeoutSec 60 -UseBasicParsing

Write-Host "Stopping Steam..."
Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Extracting ost.zip..."
Expand-Archive -LiteralPath $zipFile -DestinationPath $SteamPath -Force
Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue

$steamCfg = Join-Path $SteamPath "steam.cfg"
$steamCfgBak = Join-Path $SteamPath "steam.cfg.bak"
if (Test-Path -LiteralPath $steamCfg) {
    Write-Host "Renaming steam.cfg to steam.cfg.bak..."
    Move-Item -LiteralPath $steamCfg -Destination $steamCfgBak -Force -ErrorAction SilentlyContinue
}

Write-Host "Done! OpenSteamTool installed successfully." -ForegroundColor Green

Write-Host "Starting Steam..."
Start-Process -FilePath (Join-Path $SteamPath "steam.exe")
