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
$downloadsRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads"
$installRoot = Join-Path $downloadsRoot "LuaToolsValidator"
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
        $headers = @{
            "Cache-Control" = "no-cache"
            "Pragma"        = "no-cache"
        }
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing -Headers $headers -TimeoutSec 25 -ErrorAction Stop

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
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

function Test-DotNet10DesktopRuntime {
    try {
        $runtimes = & dotnet --list-runtimes 2>$null
        return [bool]($runtimes | Where-Object { $_ -match '^Microsoft\.WindowsDesktop\.App\s+10\.' })
    }
    catch {
        return $false
    }
}

function Install-DotNet10DesktopRuntime {
    if (Test-DotNet10DesktopRuntime) {
        Write-Host "[+] .NET 10 Desktop Runtime is already installed." -ForegroundColor Green
        return $true
    }

    Write-Host "[*] .NET 10 Desktop Runtime is missing. Installing it now..." -ForegroundColor Cyan
    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw "winget is not available"
        }

        & winget install --id Microsoft.DotNet.DesktopRuntime.10 -e --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            throw "winget exited with code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "[-] Could not auto-install .NET 10 Desktop Runtime: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Install it manually, then run this command again:" -ForegroundColor Yellow
        Write-Host "    https://dotnet.microsoft.com/en-us/download/dotnet/10.0" -ForegroundColor Yellow
        Write-Host "Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }

    if (Test-DotNet10DesktopRuntime) {
        Write-Host "[+] .NET 10 Desktop Runtime installed successfully." -ForegroundColor Green
        return $true
    }

    Write-Host "[-] .NET 10 Desktop Runtime was installed but is not visible yet." -ForegroundColor Red
    Write-Host "    Restart PowerShell or Windows, then run this command again." -ForegroundColor Yellow
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

function Start-LuaToolsValidator {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    try {
        $resolvedFile = Resolve-Path -LiteralPath $FilePath -ErrorAction Stop
        $resolvedFilePath = $resolvedFile.ProviderPath
        $workingDir = Split-Path -Parent $resolvedFilePath
        if ([string]::IsNullOrWhiteSpace($workingDir) -or -not (Test-Path -LiteralPath $workingDir -PathType Container)) {
            $workingDir = $PWD.ProviderPath
        }

        $startInfo = @{
            FilePath = $resolvedFilePath
            WindowStyle = "Normal"
            PassThru = $true
            ErrorAction = "Stop"
        }
        if (-not [string]::IsNullOrWhiteSpace($workingDir) -and (Test-Path -LiteralPath $workingDir -PathType Container)) {
            $startInfo.WorkingDirectory = $workingDir
        }
        if ($ArgumentList.Count -gt 0) {
            $startInfo.ArgumentList = $ArgumentList
        }

        $proc = Start-Process @startInfo
        Start-Sleep -Seconds 2

        if ($proc.HasExited) {
            Write-Host "[-] LuaTools Validator closed immediately. Exit code: $($proc.ExitCode)" -ForegroundColor Red
            Write-Host "    Try running this file manually to see the Windows error:" -ForegroundColor Yellow
            Write-Host "    $FilePath" -ForegroundColor Yellow
            Write-Host "Press any key to exit..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 1
        }
    }
    catch {
        Write-Host "[-] Failed to start LuaTools Validator: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    File: $FilePath" -ForegroundColor Yellow
        Write-Host "Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

Install-DotNet10DesktopRuntime | Out-Null

if ($LuaToolsInstallOnly) {
    Write-Host "[+] Starting LuaTools Validator..." -ForegroundColor Green
    Start-LuaToolsValidator -FilePath $exePath
}
else {
    Write-Host "[+] Starting LuaTools Validator for AppID $AppID..." -ForegroundColor Green
    Start-LuaToolsValidator -FilePath $exePath -ArgumentList @("--appid", "$AppID", "--autorun")
}
