# LuaTools Validator bootstrap
# Usage:
#   $AppID='3321460'; irm 'https://luatools.vercel.app/LuaToolsValidator.ps1' | iex

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

$ErrorActionPreference = "Continue"
$tempRoot = Join-Path $env:TEMP "LuaToolsValidator"
$exePath = Join-Path $tempRoot "LuaToolsValidator.exe"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$validatorUrls = @(
    "https://luatools.vercel.app/LuaToolsValidator.exe",
    "https://github.com/slomoooo/lt_api_links/releases/latest/download/LuaToolsValidator.exe"
)

$downloaded = $false
foreach ($url in $validatorUrls) {
    try {
        Write-Host "[*] Downloading LuaTools Validator..." -ForegroundColor Cyan
        Write-Host "    $url" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $exePath -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop

        if ((Test-Path -LiteralPath $exePath) -and ((Get-Item -LiteralPath $exePath).Length -gt 100KB)) {
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
        Copy-Item -LiteralPath $localDevExe -Destination $exePath -Force
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

Write-Host "[+] Starting LuaTools Validator for AppID $AppID..." -ForegroundColor Green
Start-Process -FilePath $exePath -ArgumentList @("--appid", "$AppID", "--autorun")
