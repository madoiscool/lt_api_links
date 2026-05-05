# LuaTools Validator bootstrap
# Usage:
#   $LuaToolsInstallOnly=1; irm 'https://luatools.vercel.app/LuaToolsValidator.ps1' | iex
#   $AppID='3321460'; irm 'https://luatools.vercel.app/LuaToolsValidator.ps1' | iex

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ((-not $LuaToolsInstallOnly) -and (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID))) {
    $AppID = Read-Host "Enter Steam AppID"
}

$ErrorActionPreference = "Continue"
$tempRoot = Join-Path $env:TEMP "LuaToolsValidator"
$installRoot = Join-Path $env:LOCALAPPDATA "LuaToolsValidator"
$exePath = Join-Path $installRoot "LuaToolsValidator.exe"
$downloadPath = Join-Path $tempRoot "LuaToolsValidator.latest.exe"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null

$validatorUrls = @(
    "https://raw.githubusercontent.com/Tesla697/fixed-25/main/LuaToolsValidator.exe",
    "https://github.com/Tesla697/fixed-25/releases/download/luatools-validator/LuaToolsValidator.exe",
    "https://luatools.vercel.app/LuaToolsValidator.exe"
)

$downloaded = $false
foreach ($url in $validatorUrls) {
    try {
        Write-Host "[*] Downloading latest LuaTools Validator..." -ForegroundColor Cyan
        Write-Host "    $url" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop

        if ((Test-Path -LiteralPath $downloadPath) -and ((Get-Item -LiteralPath $downloadPath).Length -gt 100KB)) {
            $downloaded = $true
            break
        }
    }
    catch {
        Write-Host "    [!] Mirror failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $downloaded) {
    $localDevExe = "C:\Users\sk443\OneDrive\Documents\GitHub\LuaToolsValidator\publish\LuaToolsValidator.exe"
    if (Test-Path -LiteralPath $localDevExe) {
        Copy-Item -LiteralPath $localDevExe -Destination $downloadPath -Force
        $downloaded = $true
        Write-Host "[*] Using local development build." -ForegroundColor Yellow
    }
}

if (-not $downloaded) {
    Write-Host "[-] Could not download LuaTools Validator from any mirror." -ForegroundColor Red
    Write-Host "    Fallback: run Devuvo.ps1 directly or try again later." -ForegroundColor Yellow
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "[*] Replacing old LuaTools Validator..." -ForegroundColor Cyan
Get-Process -Name "LuaToolsValidator" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
    }
    catch { }
}
Start-Sleep -Milliseconds 500

try {
    if (Test-Path -LiteralPath $exePath) {
        Remove-Item -LiteralPath $exePath -Force -ErrorAction Stop
    }
}
catch {
    Write-Host "    [!] Old app was locked; trying overwrite anyway." -ForegroundColor Yellow
}

Copy-Item -LiteralPath $downloadPath -Destination $exePath -Force
Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $env:TEMP "LuaToolsValidator\LuaToolsValidator.exe") -Force -ErrorAction SilentlyContinue

Write-Host "[+] LuaTools Validator is updated." -ForegroundColor Green
if ($LuaToolsInstallOnly) {
    Write-Host "[+] Starting LuaTools Validator..." -ForegroundColor Green
    Start-Process -FilePath $exePath
}
else {
    Write-Host "[+] Starting LuaTools Validator for AppID $AppID..." -ForegroundColor Green
    Start-Process -FilePath $exePath -ArgumentList @("--appid", "$AppID", "--autorun")
}
