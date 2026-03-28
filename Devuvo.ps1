# Devuvo validation script - updated 2026-03-16
if ([string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

# ---- Report data collection ----
$reportData = [ordered]@{
    AppID              = $AppID
    GameName           = "N/A"
    Installed          = $false
    FolderSize         = "N/A"
    HasGoldberg        = $false
    GoldbergFiles      = @()
    UpdatesDisabled    = $false
    LuaFileFound       = $false
    WindowsUpdateBlocked = $false
}

Write-Host "Looking for Steam installation..." -ForegroundColor Cyan

# 1. Find Steam Path and Library Folders
$steamPath = $null

# Try SteamExe first (most reliable — points to steam.exe)
$steamExe = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamExe" -ErrorAction SilentlyContinue).SteamExe
if ($steamExe) {
    $steamPath = (Split-Path $steamExe -Parent).Replace("/", "\")
}

# Fallback: HKLM InstallPath
if (-not $steamPath -or -not (Test-Path $steamPath)) {
    $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
}

# Fallback: SteamPath
if (-not $steamPath -or -not (Test-Path $steamPath)) {
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath) { $steamPath = $steamPath.Replace("/", "\") }
}

if (-not $steamPath -or -not (Test-Path $steamPath)) {
    Write-Host "[-] Could not find Steam installation." -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host "[+] Steam found at: $steamPath" -ForegroundColor Green

$libraryFoldersPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
$libraries = @()

if (Test-Path $libraryFoldersPath) {
    $content = Get-Content $libraryFoldersPath -Raw
    $vdfMatches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
    foreach ($match in $vdfMatches) {
        $libPath = $match.Groups[1].Value.Replace("\\", "\")
        $libraries += $libPath
    }
}

if ($libraries.Count -eq 0) {
    $libraries = @($steamPath)
}

Write-Host "Scanning $($libraries.Count) Steam library folders..." -ForegroundColor Cyan

# 2. Check if AppID is installed
$installDir = $null
$gameName = $null

foreach ($lib in $libraries) {
    $manifestPath = Join-Path $lib "steamapps\appmanifest_$AppID.acf"
    if (Test-Path -LiteralPath $manifestPath) {
        $manifestContent = Get-Content -LiteralPath $manifestPath -Raw

        $installDirNameMatch = [regex]::Match($manifestContent, '"installdir"\s+"([^"]+)"')
        $nameMatch = [regex]::Match($manifestContent, '"name"\s+"([^"]+)"')

        if ($installDirNameMatch.Success) {
            $installDir = Join-Path $lib "steamapps\common\$($installDirNameMatch.Groups[1].Value)"
            if ($nameMatch.Success) {
                $gameName = $nameMatch.Groups[1].Value
            }
            break
        }
    }
}

$gameInstalled = $installDir -and (Test-Path $installDir)

if ($gameInstalled) {
    Write-Host "[+] Found Game: $gameName" -ForegroundColor Green
    Write-Host "[+] Install Directory: $installDir" -ForegroundColor Green
} else {
    Write-Host "[-] AppID $AppID is not installed on this system." -ForegroundColor Red
}

# 3. Check Windows Update status
Write-Host "`n[*] Checking Windows Update status..." -ForegroundColor Cyan

$wuauserv = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue

$wuDetails = @()

if ($wuauserv) {
    $startType = $wuauserv.StartType
    $status = $wuauserv.Status
    if (($startType -eq "Disabled" -or [string]::IsNullOrWhiteSpace($startType)) -and $status -eq "Stopped") {
        Write-Host "    [+] Windows Update (wuauserv): Disabled and Stopped" -ForegroundColor Green
        $wuDetails += "Windows Update (wuauserv): Disabled and Stopped"
    } else {
        Write-Host "    [!] Windows Update (wuauserv): $status (StartType: $startType)" -ForegroundColor Yellow
        $wuDetails += "Windows Update (wuauserv): $status (StartType: $startType)"
    }
} else {
    Write-Host "    [~] Windows Update (wuauserv): Service not found (OK)" -ForegroundColor DarkGray
    $wuDetails += "Windows Update (wuauserv): Not found"
}

# Updates are blocked if the core wuauserv service is disabled/stopped
$updateBlocked = $wuauserv -and $wuauserv.Status -eq "Stopped" -and ($wuauserv.StartType -eq "Disabled" -or [string]::IsNullOrWhiteSpace($wuauserv.StartType))

if ($updateBlocked) {
    Write-Host "`n    [+] Windows Update is BLOCKED." -ForegroundColor Green
    $reportData.WindowsUpdateBlocked = $true
} else {
    Write-Host "`n    [-] Windows Update is NOT blocked." -ForegroundColor Red
}
# 5. Gate check - stop if something is wrong
$issues = @()
if (-not $gameInstalled) {
    $issues += "Game with AppID $AppID is not installed. Please install it first."
}
if (-not $updateBlocked) {
    $issues += "Windows Update is not disabled. Please disable it using WUB: https://www.sordum.org/9470/windows-update-blocker-v1-8/"
}

if ($issues.Count -gt 0) {
    Write-Host "`n[!] Please fix the following before running this script:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "    - $issue" -ForegroundColor Yellow
    }
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# Check for conflicting emulator/crack files
Write-Host "`n[*] Checking for conflicting files in game folder..." -ForegroundColor Cyan
$conflictFiles = @("unsteam.ini", "unsteam.dll", "winmm.dll", "xinput1_4.dll", "millennium-legacy.version.dll")
$foundConflicts = @()

if ($gameInstalled) {
    foreach ($cf in $conflictFiles) {
        $found = @(Get-ChildItem -LiteralPath $installDir -Filter $cf -Recurse -File -Force -ErrorAction SilentlyContinue)
        foreach ($f in $found) {
            $relPath = $f.FullName.Substring($installDir.Length + 1)
            $foundConflicts += $relPath
            Write-Host "    [!] Found conflicting file: $relPath" -ForegroundColor Yellow
        }
    }

    # Additional checks for Resident Evil Requiem (AppID 3764200)
    if ($AppID -eq '3764200') {
        $reConflicts = @("gameoverlayrenderer64.dll", "version.dll", "dinput8.dll")
        foreach ($rc in $reConflicts) {
            $found = @(Get-ChildItem -LiteralPath $installDir -Filter $rc -Recurse -File -Force -ErrorAction SilentlyContinue)
            foreach ($f in $found) {
                $relPath = $f.FullName.Substring($installDir.Length + 1)
                $foundConflicts += $relPath
                Write-Host "    [!] Found conflicting file: $relPath" -ForegroundColor Yellow
            }
        }

    }

    if ($foundConflicts.Count -gt 0) {
        Write-Host "`n[!] Conflicting files detected in your game folder!" -ForegroundColor Red
        Write-Host "    Please delete the following files from:" -ForegroundColor Red
        Write-Host "    $installDir" -ForegroundColor Cyan
        foreach ($cf in $foundConflicts) {
            Write-Host "      - $cf" -ForegroundColor Yellow
        }
        Write-Host "`n    After removing them, run this script again." -ForegroundColor Red
        Write-Host "`nPress any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    } else {
        Write-Host "    [+] No conflicting files found." -ForegroundColor Green
    }
}

if ($issues.Count -gt 0) {
    Write-Host "`n[!] Please fix the following before running this script:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "    - $issue" -ForegroundColor Yellow
    }
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host "`nAll checks passed. Generating report..." -ForegroundColor Green

# ---- Begin report generation ----

$reportData.Installed = $true
$reportData.GameName = $gameName

# Folder size
Write-Host "[*] Calculating folder size (this may take a moment)..." -ForegroundColor Cyan
$folderSize = 0
try {
    $folderSize = (Get-ChildItem -LiteralPath $installDir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
} catch {}
$reportData.FolderSize = $folderSize
$folderSizeGB = [math]::Round($folderSize / 1GB, 2)
Write-Host "[+] Folder Size: $folderSizeGB GB ($folderSize bytes)" -ForegroundColor Green

# Exe files in game folder (recursive)
$exeFiles = @()
try {
    $exeFiles = @(Get-ChildItem -LiteralPath $installDir -Filter "*.exe" -Recurse -File -Force -ErrorAction Stop | Select-Object -ExpandProperty Name)
} catch {
    Write-Host "    [!] Could not read exe files: $_" -ForegroundColor Yellow
}
$reportData.ExeFiles = $exeFiles
Write-Host "[+] Exe files: $($exeFiles -join ', ')" -ForegroundColor Green

# 5. Goldberg scan
Write-Host "`n[*] Scanning for Goldberg Emulator files..." -ForegroundColor Cyan
$goldbergIndicators = @("steam_settings", "steam_interfaces.txt", "coldclientloader.ini", "local_save.txt", "configs.user.ini")
$foundGoldberg = $false

foreach ($indicator in $goldbergIndicators) {
    $found = Get-ChildItem -Path $installDir -Recurse -Filter $indicator -ErrorAction SilentlyContinue
    foreach ($match in $found) {
        $relativePath = $match.FullName.Substring($installDir.Length).TrimStart('\','/')
        $foundGoldberg = $true
        $reportData.GoldbergFiles += $relativePath
    }
}

$steamDlls = Get-ChildItem -Path $installDir -Recurse -Include "steam_api.dll", "steam_api64.dll" -ErrorAction SilentlyContinue
foreach ($dll in $steamDlls) {
    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dll.FullName)
        if ($versionInfo.ProductName -match "Goldberg" -or $versionInfo.CompanyName -match "Goldberg" -or $versionInfo.FileDescription -match "Goldberg") {
            $foundGoldberg = $true
            $reportData.GoldbergFiles += "$($dll.Name) (patched DLL)"
        }
    } catch {}
}

$reportData.HasGoldberg = $foundGoldberg
if ($foundGoldberg) {
    Write-Host "    [!] WARNING: Found Goldberg Emulator files:" -ForegroundColor Yellow
    foreach ($f in $reportData.GoldbergFiles) {
        Write-Host "        - $f" -ForegroundColor Yellow
    }
} else {
    Write-Host "    [+] No obvious Goldberg files detected." -ForegroundColor Green
}

# 6. stplug-in lua modification
Write-Host "`n[*] Scanning for .lua files in stplug-in to disable updates/decryption..." -ForegroundColor Cyan

$stpluginDir = Get-ChildItem -Path $steamPath -Directory -Filter "stplug-in" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1

if ($stpluginDir) {
    Write-Host "    [+] Found stplug-in directory at: $($stpluginDir.FullName)" -ForegroundColor Green

    $targetLuaFile = Join-Path $stpluginDir.FullName "$AppID.lua"
    if (Test-Path $targetLuaFile) {
        $luaFiles = @(Get-Item $targetLuaFile)
    } else {
        $luaFiles = Get-ChildItem -Path $stpluginDir.FullName -Filter "*.lua" -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne "Steamtools.lua" -and (Get-Content $_.FullName -Raw) -match "addappid\(\s*$AppID\b"
        }
    }
} else {
    Write-Host "    [-] Steam stplug-in directory not found within Steam installation." -ForegroundColor Red
    $luaFiles = @()
}

$modifiedFilesCount = 0

foreach ($luaFile in $luaFiles) {
    $reportData.LuaFileFound = $true
    $content = Get-Content $luaFile.FullName
    $modified = $false
    $newContent = @()
    $alreadyConfigured = $true

    foreach ($line in $content) {
        if ($line -match "^\s*--\s*(addappid\(\s*$AppID\s*\)\s*)$") {
            $newContent += $matches[1]
            $modified = $true
            $alreadyConfigured = $false
        }
        elseif (($line -match "(?i)setManifestid\(" -or $line -match "(?i)addappid\(.+,.+,.+\)") -and $line -notmatch "^\s*--") {
            $newContent += "-- $line"
            $modified = $true
            $alreadyConfigured = $false
        } else {
            $newContent += $line
        }
    }

    # Check if lua is already correctly configured
    $luaRaw = Get-Content $luaFile.FullName -Raw
    $manifestCommented = ($luaRaw -match "(?m)^\s*--\s*setManifestid\(") -or ($luaRaw -notmatch "setManifestid\(")
    $dlcCommented = ($luaRaw -notmatch "(?m)^addappid\(.+,.+,.+\)") # no uncommented DLC lines
    if ($manifestCommented -and $dlcCommented) {
        $reportData.UpdatesDisabled = $true
    }

    if ($modified) {
        try {
            $newContent | Set-Content $luaFile.FullName
            Write-Host "    [+] Modified update/decryption/depot lines in: $($luaFile.Name)" -ForegroundColor Green
            $modifiedFilesCount++
            $reportData.UpdatesDisabled = $true
        } catch {
            Write-Host "    [-] Failed to write to $($luaFile.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    [~] No changes needed in: $($luaFile.Name) (already configured)" -ForegroundColor DarkGray
    }
}

if ($luaFiles.Count -eq 0) {
    Write-Host "    [-] No .lua file found for AppID $AppID in stplug-in." -ForegroundColor Yellow
}

Write-Host "`n[*] Done! Modified $modifiedFilesCount .lua files." -ForegroundColor Cyan

# 7. System info collection
$machineGuid = $null
try { $machineGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction Stop).MachineGuid } catch {}
$diskSerial = $null
try {
    $diskSerial = (Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Select-Object -First 1).SerialNumber
    if ($diskSerial) { $diskSerial = $diskSerial.Trim() }
} catch {}
$macAddresses = @()
try {
    $macAddresses = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "MACAddress IS NOT NULL" -ErrorAction Stop |
        Where-Object { $_.MACAddress } | Select-Object -ExpandProperty MACAddress -First 3)
} catch {}
$publicIp = $null
try { $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip } catch {
    try { $publicIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -TimeoutSec 5 -UseBasicParsing).Content.Trim() } catch {}
}
$hwid = "$machineGuid|$diskSerial"

# 7b. VPN detection
$vpnDetected = $false
$vpnReason = ""
if ($publicIp) {
    # Check 1: IP-based detection (only flag proxy, not hosting — hosting has too many false positives)
    try {
        $ipCheck = Invoke-RestMethod -Uri "https://ip-api.com/json/${publicIp}?fields=proxy,hosting" -TimeoutSec 5
        if ($ipCheck.proxy -eq $true) {
            $vpnDetected = $true
            $vpnReason = "IP flagged as proxy by ip-api.com"
        }
    } catch {}

    # Check 2: Active VPN network adapters (only if Status is "Up")
    if (-not $vpnDetected) {
        $vpnAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            ($_.InterfaceDescription -match "(?i)(tap|tun|vpn|wireguard|nordlynx|wintun|cloudflare)" -or
            $_.Name -match "(?i)(vpn|proton|nord|express|surfshark|mullvad|wireguard|warp)") -and
            $_.Status -eq "Up"
        }
        if ($vpnAdapters) {
            $vpnDetected = $true
            $adapterNames = ($vpnAdapters | ForEach-Object { "$($_.Name) ($($_.Status))" }) -join ", "
            $vpnReason = "Active VPN adapter(s): $adapterNames"
        }
    }
}

if ($vpnDetected) {
    Write-Host "`n[!] VPN or proxy detected!" -ForegroundColor Red
    Write-Host "    Reason: $vpnReason" -ForegroundColor Yellow
    Write-Host "    Please turn off your VPN/proxy and run this script again." -ForegroundColor Yellow
    Write-Host "    This is required for security verification." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 8. Upload report
Write-Host "`n[*] Uploading report to give report code..." -ForegroundColor Cyan

$jsonReport = [ordered]@{
    generated   = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    appid       = $reportData.AppID
    game_name   = $reportData.GameName
    installed   = $reportData.Installed
    folder_size = $reportData.FolderSize
    exe_files   = $reportData.ExeFiles
    has_goldberg      = $reportData.HasGoldberg
    goldberg_files    = $reportData.GoldbergFiles
    lua_file_found    = $reportData.LuaFileFound
    updates_disabled  = $reportData.UpdatesDisabled
    windows_update_blocked = $reportData.WindowsUpdateBlocked
    windows_update_services = $wuDetails
    hwid              = $hwid
    mac_addresses     = $macAddresses
    public_ip         = $publicIp
} | ConvertTo-Json -Depth 3

try {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $jsonReport | Set-Content -Path $tempFile -Encoding UTF8

    $headers = @{
        "Linx-Randomize" = "yes"
        "Accept" = "application/json"
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
    $response = Invoke-RestMethod -Uri "https://paste.rtech.support/upload/report.json" -Method Put -Headers $headers -Body $fileBytes -ContentType "application/json"

    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    if ($response.url) {
        $pasteUrl = $response.url
        # Extract just the code from the URL (e.g. mc779imw from https://paste.rtech.support/mc779imw.txt)
        $pasteCode = ($pasteUrl -split '/')[-1] -replace '\.[^.]+$', ''

        Set-Clipboard -Value $pasteCode
        Write-Host "`n    [+] Report uploaded successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "    ============================================" -ForegroundColor Magenta
        Write-Host "    ||                                        ||" -ForegroundColor Magenta
        Write-Host "    ||   D-Report Code: " -ForegroundColor Magenta -NoNewline
        Write-Host "$pasteCode" -ForegroundColor Yellow -NoNewline
        Write-Host (" " * (21 - $pasteCode.Length)) -NoNewline
        Write-Host "||" -ForegroundColor Magenta
        Write-Host "    ||                                        ||" -ForegroundColor Magenta
        Write-Host "    ||   Send this code inside your ticket!   ||" -ForegroundColor Magenta
        Write-Host "    ||                                        ||" -ForegroundColor Magenta
        Write-Host "    ============================================" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "    (copied to clipboard)" -ForegroundColor Green
    } else {
        Write-Host "    [-] Upload succeeded but no URL returned." -ForegroundColor Yellow
        Write-Host "    Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "    [-] Failed to upload report: $($_.Exception.Message)" -ForegroundColor Red
}

# 8. Restart Steam
Write-Host "`nPress any key to restart Steam..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host "`nRestarting Steam..." -ForegroundColor Cyan
Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if ($steamPath) {
    Start-Process -FilePath (Join-Path $steamPath "steam.exe")
} else {
    Write-Host "[-] Could not find Steam executable to restart." -ForegroundColor Red
}
