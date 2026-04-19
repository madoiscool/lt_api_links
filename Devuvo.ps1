# Devuvo validation script - updated 2026-04-16
if (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

# ========================
# UNRELEASED GAME OVERRIDES
# Games not yet on Steam — detected by folder name instead of appmanifest
# Format: AppID -> @{ FolderName = "..."; GameName = "..."; MainExe = "..." }
# ========================
$unreleasedGames = @{}
$isUnreleased = $unreleasedGames.ContainsKey($AppID)

# ========================
# CUSTOM LAUNCHER EXES
# Games where Steam must be pointed at a specific exe (not the default one).
# Format: AppID -> @{ Exe = "...exe"; GameName = "..." }
# Script will auto-write `"<full path>\<Exe>" %command%` into Steam launch options.
# ========================
$customLaunchers = @{
    # Pragmata (Capcom)
    "3357650" = @{ Exe = "START_PRAG.exe"; GameName = "Pragmata" }
    # Resident Evil Requiem (Capcom)
    "3764200" = @{ Exe = "START_WITH_THIS_EXE.exe"; GameName = "Resident Evil Requiem" }
}

# ========================
# VALIDATION MODE
# ========================

# ---- Report data collection ----
$reportData = [ordered]@{
    AppID                = $AppID
    GameName             = "N/A"
    Installed            = $false
    FolderSize           = "N/A"
    HasGoldberg          = $false
    GoldbergFiles        = @()
    ConflictingFiles     = @()

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

if ($isUnreleased) {
    # Unreleased game: no Steam manifest exists — search by folder name across all libraries
    $meta = $unreleasedGames[$AppID]
    $gameName = $meta.GameName
    Write-Host "[*] '$gameName' is an unreleased game — searching by folder name '$($meta.FolderName)'..." -ForegroundColor Cyan
    foreach ($lib in $libraries) {
        $candidate = Join-Path $lib "steamapps\common\$($meta.FolderName)"
        if (Test-Path $candidate) {
            # Verify the main executable exists inside
            $exeHit = Get-ChildItem -Path $candidate -Filter $meta.MainExe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exeHit) {
                $installDir = $candidate
                Write-Host "[+] Found '$($meta.FolderName)' folder with '$($meta.MainExe)' at: $installDir" -ForegroundColor Green
                break
            } else {
                Write-Host "    [!] Folder '$candidate' exists but '$($meta.MainExe)' was not found inside. Skipping." -ForegroundColor Yellow
            }
        }
    }
    if (-not $installDir) {
        Write-Host "[-] Could not find '$($meta.FolderName)' folder (with '$($meta.MainExe)') in any Steam library." -ForegroundColor Red
        Write-Host "    Make sure you have copied the game files into a Steam library under steamapps\common\$($meta.FolderName)" -ForegroundColor Yellow
    }
} else {
    # Normal released game: use appmanifest
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
}

$gameInstalled = $installDir -and (Test-Path $installDir)

if ($gameInstalled) {
    Write-Host "[+] Found Game: $gameName" -ForegroundColor Green
    Write-Host "[+] Install Directory: $installDir" -ForegroundColor Green
} else {
    if (-not $isUnreleased) {
        Write-Host "[-] AppID $AppID is not installed on this system." -ForegroundColor Red
    }
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
    }
    else {
        Write-Host "    [!] Windows Update (wuauserv): $status (StartType: $startType)" -ForegroundColor Yellow
        $wuDetails += "Windows Update (wuauserv): $status (StartType: $startType)"
    }
}
else {
    Write-Host "    [~] Windows Update (wuauserv): Service not found (OK)" -ForegroundColor DarkGray
    $wuDetails += "Windows Update (wuauserv): Not found"
}

# Updates are blocked if the core wuauserv service is disabled/stopped
$updateBlocked = $wuauserv -and $wuauserv.Status -eq "Stopped" -and ($wuauserv.StartType -eq "Disabled" -or [string]::IsNullOrWhiteSpace($wuauserv.StartType))

if ($updateBlocked) {
    Write-Host "`n    [+] Windows Update is BLOCKED." -ForegroundColor Green
    $reportData.WindowsUpdateBlocked = $true
}
else {
    Write-Host "`n    [-] Windows Update is NOT blocked. Attempting to disable it automatically..." -ForegroundColor Yellow
    try {
        # Stop the service if running
        if ($wuauserv -and $wuauserv.Status -ne "Stopped") {
            Stop-Service -Name "wuauserv" -Force -ErrorAction Stop
            Write-Host "    [+] Stopped wuauserv service." -ForegroundColor Green
        }
        # Disable startup
        Set-Service -Name "wuauserv" -StartupType Disabled -ErrorAction Stop
        Write-Host "    [+] Disabled wuauserv startup." -ForegroundColor Green
        $updateBlocked = $true
        $reportData.WindowsUpdateBlocked = $true
        Write-Host "    [+] Windows Update is now BLOCKED." -ForegroundColor Green
    }
    catch {
        Write-Host "    [-] Failed to disable Windows Update automatically: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    [!] Try running this script as Administrator, or disable it manually using WUB." -ForegroundColor Yellow
    }
}
# 5. Gate check - stop if something is wrong
$issues = @()
if (-not $gameInstalled) {
    if ($isUnreleased) {
        $meta = $unreleasedGames[$AppID]
        $issues += "Could not find the '$($meta.FolderName)' game folder (with '$($meta.MainExe)') in any Steam library. Make sure the game files are placed under steamapps\common\$($meta.FolderName)."
    } else {
        $issues += "Game with AppID $AppID is not installed. Please install it first."
    }
} else {
    $quickSize = 0
    try {
        $quickSize = (Get-ChildItem -LiteralPath $installDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 5 | Measure-Object -Property Length -Sum).Sum
    }
    catch {}
    if ($quickSize -eq 0) {
        $issues += "Game folder is empty (0 bytes). The game files may not be fully copied."
    }
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

Write-Host "`nAll checks passed." -ForegroundColor Green

# ---- Auto-backup saves before reactivation ----
Write-Host "`n[*] Backing up game saves..." -ForegroundColor Cyan

$backupRoot = Join-Path $env:USERPROFILE "Danny_Save_Backups"
$backupDir = Join-Path $backupRoot $AppID
$saveLocations = @()

# Check game folder for save directories
if ($installDir -and (Test-Path $installDir)) {
    $saveFolderNames = @("save", "saves", "savegame", "savegames", "SaveGames", "SaveData", "savedata", "save_data", "userdata", "profiles")
    foreach ($name in $saveFolderNames) {
        $found = Get-ChildItem -Path $installDir -Directory -Filter $name -Recurse -Depth 3 -ErrorAction SilentlyContinue
        foreach ($dir in $found) {
            $relPath = $dir.FullName.Substring($installDir.Length).TrimStart('\', '/')
            $saveLocations += @{ Path = $dir.FullName; Label = "Game folder: $relPath" }
        }
    }
    # Save files in game root
    $saveFiles = Get-ChildItem -Path $installDir -File -Depth 0 -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @(".sav", ".save", ".dat", ".profile", ".slot")
    }
    if ($saveFiles.Count -gt 0) {
        $saveLocations += @{ Path = $installDir; Label = "Game folder root (save files)"; FilesOnly = $saveFiles.Name }
    }
}

# Goldberg Emu saves
$goldbergSavePath = Join-Path $env:APPDATA "Goldberg SteamEmu Saves\$AppID"
if (Test-Path $goldbergSavePath) {
    $saveLocations += @{ Path = $goldbergSavePath; Label = "Goldberg SteamEmu Saves" }
}
# Custom Goldberg save path
if ($installDir) {
    $localSaveTxt = Join-Path $installDir "steam_settings\local_save.txt"
    if (Test-Path $localSaveTxt) {
        $customPath = (Get-Content $localSaveTxt -First 1).Trim()
        if ($customPath -and (Test-Path $customPath)) {
            $saveLocations += @{ Path = $customPath; Label = "Goldberg custom save path" }
        }
    }
}

# Common external save locations (match by game name)
$firstWord = if ($gameName -ne "Unknown" -and $gameName) { ($gameName -split '\s+')[0] } else { $null }
# Known publishers that use their own folder (e.g. AppData/Local/CAPCOM/<game>/)
$knownPublishers = @("CAPCOM", "SEGA", "Bandai Namco", "Square Enix", "Ubisoft", "FromSoftware", "Bethesda", "EA", "Rockstar Games", "2K Games", "Konami", "Koei Tecmo")
if ($firstWord) {
    $externalDirs = @(
        (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games"),
        [Environment]::GetFolderPath("MyDocuments"),
        $env:LOCALAPPDATA,
        $env:APPDATA,
        (Join-Path $env:USERPROFILE "AppData\LocalLow"),
        (Join-Path $env:USERPROFILE "Saved Games")
    )
    foreach ($extDir in $externalDirs) {
        if (-not $extDir -or -not (Test-Path $extDir)) { continue }
        # Direct match by game name
        $matchDirs = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match [regex]::Escape($firstWord)
        }
        foreach ($dir in $matchDirs) {
            if ($dir.Name -eq "Goldberg SteamEmu Saves") { continue }
            $relLabel = $dir.FullName.Replace($env:USERPROFILE, "~")
            $already = $saveLocations | Where-Object { $_.Path -eq $dir.FullName }
            if (-not $already) {
                $saveLocations += @{ Path = $dir.FullName; Label = $relLabel }
            }
        }
        # Search inside ALL subfolders one level deep (e.g. Team Cherry/Hollow Knight, CAPCOM/RE9, etc.)
        $topDirs = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue
        foreach ($topDir in $topDirs) {
            $subDirs = Get-ChildItem -Path $topDir.FullName -Directory -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match [regex]::Escape($firstWord)
            }
            foreach ($dir in $subDirs) {
                if ($dir.Name -eq "Goldberg SteamEmu Saves") { continue }
                $relLabel = $dir.FullName.Replace($env:USERPROFILE, "~")
                $already = $saveLocations | Where-Object { $_.Path -eq $dir.FullName }
                if (-not $already) {
                    $saveLocations += @{ Path = $dir.FullName; Label = $relLabel }
                }
            }
        }
    }
}

if ($saveLocations.Count -gt 0) {
    # Clean previous backup
    if (Test-Path $backupDir) { Remove-Item -Path $backupDir -Recurse -Force }
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

    $manifest = @{
        app_id = $AppID
        game_name = $gameName
        backed_up_at = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        entries = @()
    }

    $backedUp = 0
    foreach ($loc in $saveLocations) {
        $safeName = "save_$backedUp"
        $destFolder = Join-Path $backupDir $safeName
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        try {
            if ($loc.FilesOnly) {
                foreach ($fileName in $loc.FilesOnly) {
                    $src = Join-Path $loc.Path $fileName
                    if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $destFolder $fileName) -Force }
                }
                $manifest.entries += @{ backup_folder = $safeName; original_path = $loc.Path; label = $loc.Label; files_only = $loc.FilesOnly }
            }
            else {
                Copy-Item -Path "$($loc.Path)\*" -Destination $destFolder -Recurse -Force
                $manifest.entries += @{ backup_folder = $safeName; original_path = $loc.Path; label = $loc.Label; files_only = $null }
            }
            Write-Host "    [+] $($loc.Label)" -ForegroundColor Green
            $backedUp++
        }
        catch {
            Write-Host "    [-] Failed: $($loc.Label) — $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $manifest.entries = @($manifest.entries)
    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $backupDir "backup_manifest.json") -Encoding UTF8
    Write-Host "    [+] Backed up $backedUp save location(s) to $backupDir" -ForegroundColor Green
}
else {
    Write-Host "    [~] No save files found (first activation or saves stored elsewhere)" -ForegroundColor DarkGray
}

Write-Host "`nGenerating report..." -ForegroundColor Green

# ---- Begin report generation ----

$reportData.Installed = $true
$reportData.GameName = $gameName

# Folder size
Write-Host "[*] Calculating folder size (this may take a moment)..." -ForegroundColor Cyan
$folderSize = 0
try {
    $folderSize = (Get-ChildItem -LiteralPath $installDir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
}
catch {}
$reportData.FolderSize = $folderSize
$folderSizeGB = [math]::Round($folderSize / 1GB, 2)
Write-Host "[+] Folder Size: $folderSizeGB GB ($folderSize bytes)" -ForegroundColor Green

# Exe files in game folder (recursive)
$exeFiles = @()
try {
    $exeFiles = @(Get-ChildItem -LiteralPath $installDir -Filter "*.exe" -Recurse -File -Force -ErrorAction Stop | Select-Object -ExpandProperty Name)
}
catch {
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
        $relativePath = $match.FullName.Substring($installDir.Length).TrimStart('\', '/')
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
    }
    catch {}
}

$reportData.HasGoldberg = $foundGoldberg
if ($foundGoldberg) {
    Write-Host "    [!] WARNING: Found Goldberg Emulator files:" -ForegroundColor Yellow
    foreach ($f in $reportData.GoldbergFiles) {
        Write-Host "        - $f" -ForegroundColor Yellow
    }
}
else {
    Write-Host "    [+] No obvious Goldberg files detected." -ForegroundColor Green
}

# 5b. Conflicting files scan
Write-Host "`n[*] Scanning for conflicting files..." -ForegroundColor Cyan

$conflictingNames = @(
    "winmm.dll",
    "xinput1_3.dll",
    "xinput1_4.dll",
    "xinput9_1_0.dll",
    "dinput8.dll",
    "winhttp.dll",
    "iphlpapi.dll",
    "dsound.dll",
    "cream_api.ini",
    "steam_api_o.dll",
    "steam_api64_o.dll",
    "steamclient_loader.exe",
    "codex.cfg",
    "codex64.dll",
    "3dmgame.dll",
    "ali213.ini",
    "valve.ini",
    "hlm.ini",
    "denuvo.dll",
    "unsteam.ini",
    "unsteam.dll"
)

$conflictingFound = @()
foreach ($name in $conflictingNames) {
    $hits = Get-ChildItem -Path $installDir -Recurse -Filter $name -ErrorAction SilentlyContinue
    foreach ($hit in $hits) {
        $relativePath = $hit.FullName.Substring($installDir.Length).TrimStart('\', '/')
        $conflictingFound += $relativePath
    }
}

# Also scan for any other UnSteam files (any file with "unsteam" in name)
$unsteamHits = Get-ChildItem -Path $installDir -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "(?i)unsteam" }
foreach ($hit in $unsteamHits) {
    $relativePath = $hit.FullName.Substring($installDir.Length).TrimStart('\', '/')
    if ($conflictingFound -notcontains $relativePath) {
        $conflictingFound += $relativePath
    }
}

$reportData.ConflictingFiles = $conflictingFound

if ($conflictingFound.Count -gt 0) {
    Write-Host "    [!] WARNING: Found $($conflictingFound.Count) conflicting file(s):" -ForegroundColor Red
    foreach ($cf in $conflictingFound) {
        Write-Host "        - $cf" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "    Please DELETE the above files from your game folder and run this script again." -ForegroundColor Yellow
    Write-Host "    These files conflict with the activation and must be removed first." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
else {
    Write-Host "    [+] No conflicting files detected." -ForegroundColor Green
}

# 6. stplug-in lua modification
if ($isUnreleased) {
    # Unreleased game — no AppID registered in SteamTools yet, skip lua check
    Write-Host "`n[*] Skipping stplug-in lua check (game is not yet released on Steam)." -ForegroundColor DarkGray
    $luaFiles = @()
} else {
    Write-Host "`n[*] Scanning for .lua files in stplug-in to disable updates/decryption..." -ForegroundColor Cyan

    $stpluginDir = Get-ChildItem -Path $steamPath -Directory -Filter "stplug-in" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($stpluginDir) {
        Write-Host "    [+] Found stplug-in directory at: $($stpluginDir.FullName)" -ForegroundColor Green

        $targetLuaFile = Join-Path $stpluginDir.FullName "$AppID.lua"
        if (Test-Path $targetLuaFile) {
            $luaFiles = @(Get-Item $targetLuaFile)
        }
        else {
            $luaFiles = Get-ChildItem -Path $stpluginDir.FullName -Filter "*.lua" -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -ne "Steamtools.lua" -and (Get-Content $_.FullName -Raw) -match "addappid\(\s*$AppID\b"
            }
        }
    }
    else {
        Write-Host "    [-] Steam stplug-in directory not found within Steam installation." -ForegroundColor Red
        $luaFiles = @()
    }

    foreach ($luaFile in $luaFiles) {
        $reportData.LuaFileFound = $true

        # Check if lua is already correctly configured (read-only)
        $luaRaw = Get-Content $luaFile.FullName -Raw
        $manifestCommented = ($luaRaw -match "(?m)^\s*--\s*setManifestid\(") -or ($luaRaw -notmatch "setManifestid\(")
        $dlcCommented = ($luaRaw -notmatch "(?m)^addappid\(.+,.+,.+\)") # no uncommented DLC lines
        if ($manifestCommented -and $dlcCommented) {
            $reportData.UpdatesDisabled = $true
            Write-Host "    [+] $($luaFile.Name) is correctly configured." -ForegroundColor Green
        }
        else {
            Write-Host "    [!] $($luaFile.Name) has update/decryption lines that need manual attention." -ForegroundColor Yellow
        }
    }

    if ($luaFiles.Count -eq 0) {
        Write-Host "    [-] No .lua file found for AppID $AppID in stplug-in." -ForegroundColor Yellow
    }
}

# 7. System info collection
$cpuName = "Unknown"
try { $cpuName = (Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name.Trim() } catch {}
$gpuName = "Unknown"
$gpuVram = 0
try {
    $gpu = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 } | Sort-Object AdapterRAM -Descending | Select-Object -First 1
    if ($gpu) { $gpuName = $gpu.Name.Trim(); $gpuVram = [math]::Round($gpu.AdapterRAM / 1GB, 1) }
} catch {}
$ramGB = 0
try { $ramGB = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1) } catch {}
$osName = "Unknown"
try { $osName = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption.Trim() } catch {}
$diskFreeGB = 0
try {
    if ($installDir) {
        $driveLetter = (Split-Path $installDir -Qualifier)
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$driveLetter'" -ErrorAction Stop
        if ($disk) { $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1) }
    }
} catch {}

$machineGuid = $null
try { $machineGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction Stop).MachineGuid } catch {}
$diskSerial = $null
try {
    $diskSerial = (Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Select-Object -First 1).SerialNumber
    if ($diskSerial) { $diskSerial = $diskSerial.Trim() }
}
catch {}
$macAddresses = @()
try {
    $macAddresses = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "MACAddress IS NOT NULL" -ErrorAction Stop |
        Where-Object { $_.MACAddress } | Select-Object -ExpandProperty MACAddress -First 3)
}
catch {}
$publicIp = $null
try { $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip } catch {
    try { $publicIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -TimeoutSec 5 -UseBasicParsing).Content.Trim() } catch {}
}
$hwid = "$machineGuid|$diskSerial"


# 8. Upload report
Write-Host "`n[*] Uploading report to give report code..." -ForegroundColor Cyan

$jsonReport = [ordered]@{
    generated               = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    appid                   = $reportData.AppID
    game_name               = $reportData.GameName
    installed               = $reportData.Installed
    folder_size             = $reportData.FolderSize
    exe_files               = $reportData.ExeFiles
    has_goldberg            = $reportData.HasGoldberg
    goldberg_files          = $reportData.GoldbergFiles
    conflicting_files       = $reportData.ConflictingFiles
    lua_file_found          = $reportData.LuaFileFound
    updates_disabled        = $reportData.UpdatesDisabled
    windows_update_blocked  = $reportData.WindowsUpdateBlocked
    windows_update_services = $wuDetails
    hwid                    = $hwid
    mac_addresses           = $macAddresses
    public_ip               = $publicIp
    cpu                     = $cpuName
    gpu                     = $gpuName
    gpu_vram_gb             = $gpuVram
    ram_gb                  = $ramGB
    os                      = $osName
    disk_free_gb            = $diskFreeGB
} | ConvertTo-Json -Depth 3

try {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $jsonReport | Set-Content -Path $tempFile -Encoding UTF8

    $headers = @{
        "Linx-Randomize" = "yes"
        "Accept"         = "application/json"
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

        # For games that need launch options written, defer the D-Report code display
        # until AFTER Steam restart — prevents users from closing the script early
        # and skipping the launch options write.
        $deferCodeDisplay = $customLaunchers.ContainsKey($AppID)

        if (-not $deferCodeDisplay) {
            Write-Host ""
            Write-Host "    ============================================" -ForegroundColor Magenta
            Write-Host "    ||                                        ||" -ForegroundColor Magenta
            Write-Host "    ||   D-Report Code: " -ForegroundColor Magenta -NoNewline
            Write-Host "$pasteCode" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (22 - $pasteCode.Length)) -NoNewline
            Write-Host "||" -ForegroundColor Magenta
            Write-Host "    ||                                        ||" -ForegroundColor Magenta
            Write-Host "    ||   Send this code inside your ticket!   ||" -ForegroundColor Magenta
            Write-Host "    ||                                        ||" -ForegroundColor Magenta
            Write-Host "    ============================================" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "    (copied to clipboard)" -ForegroundColor Green
        }
        else {
            Write-Host "    [*] D-Report Code will be shown after Steam restart + launch options setup." -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "    [-] Upload succeeded but no URL returned." -ForegroundColor Yellow
        Write-Host "    Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "    [-] Failed to upload report: $($_.Exception.Message)" -ForegroundColor Red
}

# 8. Restart Steam
Write-Host "`nPress any key to restart Steam..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host "`nRestarting Steam..." -ForegroundColor Cyan
Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# --- Set custom launch options (Steam must be closed for this to persist) ---
if ($customLaunchers.ContainsKey($AppID) -and $installDir -and $steamPath) {
    $cfg = $customLaunchers[$AppID]
    Write-Host "[*] Setting Steam launch options for $($cfg.GameName)..." -ForegroundColor Cyan

    # Resolve the launcher exe path — prefer existing location (root then recursive),
    # otherwise default to "<installDir>\<Exe>" even if the exe isn't there yet.
    $launcherPath = Join-Path $installDir $cfg.Exe
    if (-not (Test-Path -LiteralPath $launcherPath)) {
        $found = Get-ChildItem -Path $installDir -Filter $cfg.Exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $launcherPath = $found.FullName }
    }

    $launchOptionString = '"' + $launcherPath + '" %command%'
    # VDF-escape: backslashes doubled, quotes escaped
    $vdfEscaped = ($launchOptionString -replace '\\', '\\') -replace '"', '\"'
    $newValue = '"LaunchOptions"' + "`t`t" + '"' + $vdfEscaped + '"'

    $userdataPath = Join-Path $steamPath "userdata"
    $writtenCount = 0
    # Write to BOTH localconfig (machine-local) AND sharedconfig (cloud-synced across machines).
    # sharedconfig is what survives Steam Cloud resyncs and propagates to other installs.
    $configFiles = @("localconfig.vdf", "sharedconfig.vdf")
    if (Test-Path $userdataPath) {
        $userDirs = @(Get-ChildItem -Path $userdataPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' -and $_.Name -ne '0' })
        foreach ($userDir in $userDirs) {
            foreach ($configName in $configFiles) {
                $vdfPath = Join-Path $userDir.FullName "config\$configName"
                if (-not (Test-Path -LiteralPath $vdfPath)) { continue }

                try {
                    $vdfContent = Get-Content -LiteralPath $vdfPath -Raw -Encoding UTF8

                    $blockOpen = [regex]::Match($vdfContent, '"' + [regex]::Escape($AppID) + '"\s*\{')
                    if ($blockOpen.Success) {
                        # Find matching close brace (track nesting)
                        $startIdx = $blockOpen.Index + $blockOpen.Length
                        $depth = 1
                        $i = $startIdx
                        while ($i -lt $vdfContent.Length -and $depth -gt 0) {
                            $c = $vdfContent[$i]
                            if ($c -eq '{') { $depth++ }
                            elseif ($c -eq '}') { $depth-- }
                            $i++
                        }
                        $endIdx = $i - 1
                        $blockBody = $vdfContent.Substring($startIdx, $endIdx - $startIdx)

                        # Handle escaped quotes inside string values
                        $loPattern = '"LaunchOptions"\s+"(?:[^"\\]|\\.)*"'
                        if ([regex]::IsMatch($blockBody, $loPattern)) {
                            $newBody = [regex]::Replace($blockBody, $loPattern, { param($m) $newValue }, 1)
                        }
                        else {
                            $newBody = "`r`n`t`t`t`t`t" + $newValue + $blockBody
                        }

                        $newContent = $vdfContent.Substring(0, $startIdx) + $newBody + $vdfContent.Substring($endIdx)
                        Set-Content -LiteralPath $vdfPath -Value $newContent -Encoding UTF8 -NoNewline
                        $writtenCount++
                    }
                    else {
                        # AppID entry doesn't exist yet — inject a minimal block into "apps"
                        $appsMatch = [regex]::Match($vdfContent, '"apps"\s*\{')
                        if ($appsMatch.Success) {
                            $insertPos = $appsMatch.Index + $appsMatch.Length
                            $inject = "`r`n`t`t`t`t`"$AppID`"`r`n`t`t`t`t{`r`n`t`t`t`t`t$newValue`r`n`t`t`t`t}"
                            $newContent = $vdfContent.Substring(0, $insertPos) + $inject + $vdfContent.Substring($insertPos)
                            Set-Content -LiteralPath $vdfPath -Value $newContent -Encoding UTF8 -NoNewline
                            $writtenCount++
                        }
                    }
                }
                catch {
                    Write-Host "    [-] Failed on $vdfPath`: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }

    if ($writtenCount -gt 0) {
        Write-Host "    [+] Launch options written to $writtenCount config file(s) (local + shared)." -ForegroundColor Green
        Write-Host "        $launchOptionString" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    [-] Could not update any Steam config file." -ForegroundColor Yellow
    }
}

if ($steamPath) {
    Start-Process -FilePath (Join-Path $steamPath "steam.exe")
}
else {
    Write-Host "[-] Could not find Steam executable to restart." -ForegroundColor Red
}

# Deferred D-Report code display (for games where launch options were set)
if ($deferCodeDisplay -and $pasteCode) {
    Write-Host ""
    Write-Host "    ============================================" -ForegroundColor Magenta
    Write-Host "    ||                                        ||" -ForegroundColor Magenta
    Write-Host "    ||   D-Report Code: " -ForegroundColor Magenta -NoNewline
    Write-Host "$pasteCode" -ForegroundColor Yellow -NoNewline
    Write-Host (" " * (22 - $pasteCode.Length)) -NoNewline
    Write-Host "||" -ForegroundColor Magenta
    Write-Host "    ||                                        ||" -ForegroundColor Magenta
    Write-Host "    ||   Send this code inside your ticket!   ||" -ForegroundColor Magenta
    Write-Host "    ||                                        ||" -ForegroundColor Magenta
    Write-Host "    ============================================" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "    (copied to clipboard)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
