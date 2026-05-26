# Devuvo validation script - updated 2026-04-16
if (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

# ========================
# UNRELEASED GAME OVERRIDES
# Games not yet on Steam - detected by folder name instead of appmanifest
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
    "3357650" = @{ Exe = "tokeer_launcher.exe"; GameName = "Pragmata" }
    # Resident Evil Requiem (Capcom)
    "3764200" = @{ Exe = "tokeer_launcher.exe"; GameName = "Resident Evil Requiem" }
    # Monster Hunter Stories 3: Twisted Reflection (Capcom)
    "2852190" = @{ Exe = "tokeer_launcher.exe"; GameName = "Monster Hunter Stories 3: Twisted Reflection" }
    # Maneater (Denuvo + tokeer)
    "629820"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Maneater" }
    # FAR: Changing Tides (Denuvo + tokeer)
    "1570010" = @{ Exe = "tokeer_launcher.exe"; GameName = "FAR: Changing Tides" }
    # Planet Coaster (Denuvo + tokeer)
    "493340"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Planet Coaster" }
    # Crimson Desert (Denuvo + tokeer)
    "3321460" = @{ Exe = "tokeer_launcher.exe"; GameName = "Crimson Desert" }
    # Sonic Forces (Denuvo + tokeer)
    "637100"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Sonic Forces" }
    # Planet Coaster 2 (Denuvo + tokeer)
    "2688950" = @{ Exe = "tokeer_launcher.exe"; GameName = "Planet Coaster 2" }
    # Black Myth: Wukong (Denuvo + tokeer)
    "2358720" = @{ Exe = "tokeer_launcher.exe"; GameName = "Black Myth: Wukong" }
    # Stellar Blade (Denuvo + tokeer)
    "3489700" = @{ Exe = "tokeer_launcher.exe"; GameName = "Stellar Blade" }
    # METAL GEAR SOLID V: THE PHANTOM PAIN (Denuvo + tokeer)
    "287700"  = @{ Exe = "tokeer_launcher.exe"; GameName = "METAL GEAR SOLID V: THE PHANTOM PAIN" }
    # Sniper Elite 4 (Denuvo + tokeer)
    "312660"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Sniper Elite 4" }
    # Total War: WARHAMMER II (Denuvo + tokeer)
    "594570"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Total War: WARHAMMER II" }
    # Sword Art Online: Fatal Bullet (Denuvo + tokeer)
    "626690"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Sword Art Online: Fatal Bullet" }
    # Atomic Heart
    "668580"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Atomic Heart" }
    # Hogwarts Legacy (Denuvo + tokeer)
    "990080"  = @{ Exe = "tokeer_launcher.exe"; GameName = "Hogwarts Legacy" }
    # Sniper Elite 5 (Denuvo + tokeer)
    "1029690" = @{ Exe = "tokeer_launcher.exe"; GameName = "Sniper Elite 5" }
    # Total War: WARHAMMER III (Denuvo + tokeer)
    "1142710" = @{ Exe = "tokeer_launcher.exe"; GameName = "Total War: WARHAMMER III" }
    # Sonic Frontiers (Denuvo + tokeer)
    "1237320" = @{ Exe = "tokeer_launcher.exe"; GameName = "Sonic Frontiers" }
    # Shin Megami Tensei III Nocturne HD Remaster (Denuvo + tokeer)
    "1413480" = @{ Exe = "tokeer_launcher.exe"; GameName = "Shin Megami Tensei III Nocturne HD Remaster" }
    # Persona 5 Royal (Denuvo + tokeer)
    "1687950" = @{ Exe = "tokeer_launcher.exe"; GameName = "Persona 5 Royal" }
    # Dead Space (Denuvo + tokeer)
    "1693980" = @{ Exe = "tokeer_launcher.exe"; GameName = "Dead Space" }
    # Warhammer Age of Sigmar: Realms of Ruin (Denuvo + tokeer)
    "1844380" = @{ Exe = "tokeer_launcher.exe"; GameName = "Warhammer Age of Sigmar: Realms of Ruin" }
    # Mortal Kombat 1 (Denuvo + tokeer)
    "1971870" = @{ Exe = "tokeer_launcher.exe"; GameName = "Mortal Kombat 1" }
    # Persona 3 Reload (Denuvo + tokeer)
    "2161700" = @{ Exe = "tokeer_launcher.exe"; GameName = "Persona 3 Reload" }
    # LEGO Batman: Legacy of the Dark Knight (Denuvo + tokeer)
    "2215200" = @{ Exe = "tokeer_launcher.exe"; GameName = "LEGO Batman: Legacy of the Dark Knight" }
    # Like a Dragon Gaiden: The Man Who Erased His Name (Denuvo + tokeer) — launcher lives in runtime\media
    "2375550" = @{ Exe = "runtime\media\tokeer_launcher.exe"; GameName = "Like a Dragon Gaiden: The Man Who Erased His Name" }
    # SONIC X SHADOW GENERATIONS (Denuvo + tokeer)
    "2513280" = @{ Exe = "tokeer_launcher.exe"; GameName = "SONIC X SHADOW GENERATIONS" }
    # Like a Dragon: Pirate Yakuza in Hawaii (Denuvo + tokeer)
    "3061810" = @{ Exe = "runtime\media\tokeer_launcher.exe"; GameName = "Like a Dragon: Pirate Yakuza in Hawaii" }
    # WWE 2K26 (Denuvo + tokeer)
    "3717070" = @{ Exe = "tokeer_launcher.exe"; GameName = "WWE 2K26" }
    # 007 First Light (Denuvo + tokeer)
    "3768760" = @{ Exe = "tokeer_launcher.exe"; GameName = "007 First Light" }
    # Street Fighter 6 (Denuvo + tokeer)
    "1364780" = @{ Exe = "tokeer_launcher.exe"; GameName = "Street Fighter 6" }
    # F1 25 (Denuvo + tokeer)
    "3059520" = @{ Exe = "tokeer_launcher.exe"; GameName = "F1 25" }


    
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

function Test-SteamRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $normalized = $Path.Replace("/", "\").Trim('"')
    return (Test-Path -LiteralPath (Join-Path $normalized "steam.exe"))
}

function Add-SteamCandidate {
    param(
        [System.Collections.ArrayList]$Candidates,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $normalized = $Path.Replace("/", "\").Trim('"')
    if ($Candidates -notcontains $normalized) {
        [void]$Candidates.Add($normalized)
    }
}

function Remove-GbeValidationFiles {
    param([string]$GameDir)

    if ([string]::IsNullOrWhiteSpace($GameDir) -or -not (Test-Path -LiteralPath $GameDir)) {
        return
    }

    $root = (Resolve-Path -LiteralPath $GameDir).Path.TrimEnd('\', '/')
    Write-Host "`n[*] Cleaning old GBE files before validation..." -ForegroundColor Cyan

    $fileNames = @(
        "coldloader.dll",
        "coldloader.ini",
        "coldclientloader.ini",
        "mktl.ini",
        "LUA.ini",
        "steam_interfaces.txt",
        "local_save.txt",
        "steamclient.dll",
        "steamclient64.dll",
        "GameOverlayRenderer.dll",
        "GameOverlayRenderer64.dll",
        "cirno.dll",
        "cirno.ini",
        "cracksteam_api64.dll"
    )

    $dirNames = @(
        "steam_settings"
    )

    $removed = 0
    foreach ($name in $fileNames) {
        $hits = Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter $name -ErrorAction SilentlyContinue
        foreach ($hit in $hits) {
            $full = $hit.FullName
            if (-not ($full.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
            try {
                Remove-Item -LiteralPath $full -Force -ErrorAction Stop
                $rel = $full.Substring($root.Length).TrimStart('\', '/')
                Write-Host "    [-] Removed $rel" -ForegroundColor DarkGray
                $removed++
            }
            catch {
                Write-Host "    [!] Could not remove $($hit.FullName): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    foreach ($name in $dirNames) {
        $hits = Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -Filter $name -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending
        foreach ($hit in $hits) {
            $full = $hit.FullName
            if (-not ($full.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
            try {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
                $rel = $full.Substring($root.Length).TrimStart('\', '/')
                Write-Host "    [-] Removed $rel" -ForegroundColor DarkGray
                $removed++
            }
            catch {
                Write-Host "    [!] Could not remove $($hit.FullName): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    if ($removed -gt 0) {
        Write-Host "    [+] Removed $removed old GBE file/folder item(s)." -ForegroundColor Green
    }
    else {
        Write-Host "    [+] No old GBE files found." -ForegroundColor Green
    }
}

$steamCandidates = [System.Collections.ArrayList]::new()

# SteamExe should point to steam.exe, but some broken installs/registry states can
# point at a game folder. Only accept its parent if steam.exe is actually there.
$steamExe = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamExe" -ErrorAction SilentlyContinue).SteamExe
if ($steamExe -and ((Split-Path $steamExe -Leaf) -ieq "steam.exe")) {
    Add-SteamCandidate -Candidates $steamCandidates -Path (Split-Path $steamExe -Parent)
}

# Registry install roots.
Add-SteamCandidate -Candidates $steamCandidates -Path (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
Add-SteamCandidate -Candidates $steamCandidates -Path (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
Add-SteamCandidate -Candidates $steamCandidates -Path (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath

# Common fallback locations.
Add-SteamCandidate -Candidates $steamCandidates -Path "C:\Program Files (x86)\Steam"
Add-SteamCandidate -Candidates $steamCandidates -Path "C:\Program Files\Steam"

foreach ($candidate in $steamCandidates) {
    if (Test-SteamRoot $candidate) {
        $steamPath = $candidate
        break
    }
}

if (-not $steamPath) {
    Write-Host "[-] Could not find Steam installation." -ForegroundColor Red
    if ($steamCandidates.Count -gt 0) {
        Write-Host "    Checked paths:" -ForegroundColor Yellow
        foreach ($candidate in $steamCandidates) {
            Write-Host "    - $candidate" -ForegroundColor DarkGray
        }
    }
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host "[+] Steam found at: $steamPath" -ForegroundColor Green

$libraryFoldersPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
$libraries = @()
$vdfPathPattern = '\x22path\x22\s+\x22([^\x22]+)\x22'
$manifestInstallDirPattern = '\x22installdir\x22\s+\x22([^\x22]+)\x22'
$manifestNamePattern = '\x22name\x22\s+\x22([^\x22]+)\x22'

if (Test-Path $libraryFoldersPath) {
    $content = Get-Content $libraryFoldersPath -Raw
    $vdfMatches = [regex]::Matches($content, $vdfPathPattern)
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
    # Unreleased game: no Steam manifest exists - search every Steam common folder
    $meta = $unreleasedGames[$AppID]
    $gameName = $meta.GameName
    Write-Host "[*] '$gameName' is an unreleased game - searching Steam libraries for '$($meta.MainExe)'..." -ForegroundColor Cyan
    foreach ($lib in $libraries) {
        $commonDir = [System.IO.Path]::Combine($lib, "steamapps\common")
        if (-not (Test-Path -LiteralPath $commonDir)) {
            continue
        }

        $candidate = [System.IO.Path]::Combine($commonDir, $meta.FolderName)
        if (Test-Path -LiteralPath $candidate) {
            $exeHit = Get-ChildItem -LiteralPath $candidate -Filter $meta.MainExe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exeHit) {
                $installDir = $candidate
                Write-Host "[+] Found '$($meta.FolderName)' folder with '$($meta.MainExe)' at: $installDir" -ForegroundColor Green
                break
            }
            else {
                Write-Host "    [!] Folder '$candidate' exists but '$($meta.MainExe)' was not found inside. Skipping." -ForegroundColor Yellow
            }
        }

        $folders = Get-ChildItem -LiteralPath $commonDir -Directory -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            if ($folder.FullName -ieq $candidate) {
                continue
            }

            $exeHit = Get-ChildItem -LiteralPath $folder.FullName -Filter $meta.MainExe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exeHit) {
                $installDir = $folder.FullName
                Write-Host "[+] Found '$($meta.MainExe)' inside clean files folder: $installDir" -ForegroundColor Green
                break
            }
        }

        if ($installDir) {
            break
        }
    }

    if (-not $installDir) {
        Write-Host "[*] '$($meta.MainExe)' was not found in Steam libraries. Searching fixed drives outside Steam too..." -ForegroundColor Cyan

        $driveRoots = @()
        try {
            $driveRoots = [System.IO.DriveInfo]::GetDrives() |
                Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } |
                ForEach-Object { $_.RootDirectory.FullName }
        }
        catch {
            $driveRoots = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Root }
        }

        foreach ($root in $driveRoots) {
            if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
                continue
            }

            Write-Host "    [*] Scanning $root for $($meta.MainExe)..." -ForegroundColor DarkGray
            $exeHit = Get-ChildItem -LiteralPath $root -Filter $meta.MainExe -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($exeHit) {
                $installDir = $exeHit.Directory.FullName
                Write-Host "[+] Found '$($meta.MainExe)' outside Steam at: $($exeHit.FullName)" -ForegroundColor Green
                Write-Host "[+] Using install directory: $installDir" -ForegroundColor Green
                break
            }
        }
    }

    if (-not $installDir) {
        Write-Host "[-] Could not find '$($meta.MainExe)' in Steam libraries or any fixed drive." -ForegroundColor Red
        Write-Host "    Make sure the clean game files are extracted and the main exe exists on this PC." -ForegroundColor Yellow
    }
} else {
    # Normal released game: use appmanifest
    foreach ($lib in $libraries) {
        $manifestPath = [System.IO.Path]::Combine($lib, "steamapps\appmanifest_$AppID.acf")
        if (Test-Path -LiteralPath $manifestPath) {
            $manifestContent = Get-Content -LiteralPath $manifestPath -Raw

            $installDirNameMatch = [regex]::Match($manifestContent, $manifestInstallDirPattern)
            $nameMatch = [regex]::Match($manifestContent, $manifestNamePattern)

            if ($installDirNameMatch.Success) {
                $installDir = [System.IO.Path]::Combine($lib, "steamapps\common\$($installDirNameMatch.Groups[1].Value)")
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
}
else {
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

# 3.5 Check and Add Windows Defender Exclusions
$defenderExcludedAppIDs = @("2852190", "3764200", "3357650")
if ($gameInstalled -and $AppID -in $defenderExcludedAppIDs) {
    Write-Host "`n[*] Adding Windows Defender exclusion for the game folder..." -ForegroundColor Cyan
    try {
        # Check if running as Admin
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            # Note: We must use Add-MpPreference instead of Set-MpPreference so we don't overwrite user's existing exclusions
            Add-MpPreference -ExclusionPath $installDir -ErrorAction Stop
            Write-Host "    [+] Successfully added Defender exclusion for: $installDir" -ForegroundColor Green
        }
        else {
            Write-Host "    [-] Cannot add Defender exclusion: Script is not running as Administrator." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "    [-] Failed to add Defender exclusion automatically: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 5. Gate check - stop if something is wrong
$issues = @()
if (-not $gameInstalled) {
    if ($isUnreleased) {
        $meta = $unreleasedGames[$AppID]
        $issues += "Could not find '$($meta.MainExe)' in Steam libraries or any fixed drive. Make sure the clean game files are extracted and the main exe exists on this PC."
    }
    else {
        $issues += "Game with AppID $AppID is not installed. Please install it first."
    }
}
else {
    $quickSize = 0
    try {
        $quickSize = (Get-ChildItem -LiteralPath $installDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 5 | Measure-Object -Property Length -Sum).Sum
    }
    catch {}
    if ($quickSize -eq 0) {
        $issues += 'Game folder is empty (0 bytes). The game files may not be fully copied.'
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
        app_id       = $AppID
        game_name    = $gameName
        backed_up_at = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        entries      = @()
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
            } else {
                $copySource = Join-Path $loc.Path '*'
                Copy-Item -Path $copySource -Destination $destFolder -Recurse -Force
                $manifest.entries += @{ backup_folder = $safeName; original_path = $loc.Path; label = $loc.Label; files_only = $null }
            }
            Write-Host "    [+] $($loc.Label)" -ForegroundColor Green
            $backedUp++
        } catch {
            Write-Host "    [-] Failed: $($loc.Label) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $manifest.entries = @($manifest.entries)
    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $backupDir "backup_manifest.json") -Encoding UTF8
    Write-Host "    [+] Backed up $backedUp save location(s) to $backupDir" -ForegroundColor Green
} else {
    Write-Host "    [~] No save files found (first activation or saves stored elsewhere)" -ForegroundColor DarkGray
}

Remove-GbeValidationFiles -GameDir $installDir

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
Write-Host ('[+] Folder Size: {0} GB, {1} bytes' -f $folderSizeGB, $folderSize) -ForegroundColor Green

# Exe files in game folder (recursive)
$exeFiles = @()
try {
    $exeFiles = @(Get-ChildItem -LiteralPath $installDir -Filter '*.exe' -Recurse -File -Force -ErrorAction Stop | Select-Object -ExpandProperty Name)
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
$goldbergFoundPaths = @()

foreach ($indicator in $goldbergIndicators) {
    $found = Get-ChildItem -LiteralPath $installDir -Recurse -Force -Filter $indicator -ErrorAction SilentlyContinue
    foreach ($match in $found) {
        $relativePath = $match.FullName.Substring($installDir.Length).TrimStart('\', '/')
        $foundGoldberg = $true
        $reportData.GoldbergFiles += $relativePath
        $goldbergFoundPaths += $match.FullName
    }
}

$steamDlls = Get-ChildItem -LiteralPath $installDir -Recurse -Include "steam_api.dll", "steam_api64.dll" -ErrorAction SilentlyContinue
foreach ($dll in $steamDlls) {
    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dll.FullName)
        if ($versionInfo.ProductName -match "Goldberg" -or $versionInfo.CompanyName -match "Goldberg" -or $versionInfo.FileDescription -match "Goldberg") {
            $foundGoldberg = $true
            $relativePath = $dll.FullName.Substring($installDir.Length).TrimStart('\', '/')
            $reportData.GoldbergFiles += "$relativePath (patched DLL)"
            $goldbergFoundPaths += $dll.FullName
        }
    }
    catch {}
}

if ($foundGoldberg) {
    Write-Host "    [*] Found Goldberg Emulator files, auto-deleting..." -ForegroundColor Yellow
    foreach ($f in $reportData.GoldbergFiles) {
        Write-Host "        - $f" -ForegroundColor Yellow
    }

    $deletedGoldberg = 0
    $failedGoldberg = @()
    $installRoot = (Resolve-Path -LiteralPath $installDir).Path.TrimEnd('\', '/')
    $deleteTargets = $goldbergFoundPaths |
        Select-Object -Unique |
        Sort-Object { $_.Length } -Descending

    foreach ($target in $deleteTargets) {
        try {
            if (-not (Test-Path -LiteralPath $target)) { continue }
            $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
            if (-not ($resolvedTarget.StartsWith($installRoot + "\", [System.StringComparison]::OrdinalIgnoreCase))) {
                $failedGoldberg += "$target (outside game folder)"
                continue
            }

            Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -ErrorAction Stop
            $deletedGoldberg++
        }
        catch {
            $failedGoldberg += "$target ($($_.Exception.Message))"
        }
    }

    if ($deletedGoldberg -gt 0) {
        Write-Host "    [+] Auto-deleted $deletedGoldberg Goldberg file/folder item(s)." -ForegroundColor Green
    }
    if ($failedGoldberg.Count -gt 0) {
        Write-Host "    [!] Could not delete $($failedGoldberg.Count) Goldberg item(s):" -ForegroundColor Yellow
        foreach ($failed in $failedGoldberg) {
            Write-Host "        - $failed" -ForegroundColor Yellow
        }
    }

    $reportData.HasGoldberg = $failedGoldberg.Count -gt 0
}
else {
    $reportData.HasGoldberg = $false
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
    "unsteam.dll",
    "cirno.dll",
    "cirno.ini",
    "cracksteam_api64.dll"
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
    Write-Host "    [*] Found $($conflictingFound.Count) conflicting file(s), auto-deleting..." -ForegroundColor Yellow
    $removedConflicts = 0
    $failedConflicts = @()
    $installRoot = (Resolve-Path -LiteralPath $installDir).Path.TrimEnd('\', '/')

    foreach ($cf in $conflictingFound) {
        $target = Join-Path $installRoot $cf
        Write-Host "        - $cf" -ForegroundColor Yellow

        try {
            if (-not (Test-Path -LiteralPath $target)) { continue }

            $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
            if (-not ($resolvedTarget.StartsWith($installRoot + "\", [System.StringComparison]::OrdinalIgnoreCase))) {
                $failedConflicts += "$cf (outside game folder)"
                continue
            }

            Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -ErrorAction Stop
            $removedConflicts++
        }
        catch {
            $failedConflicts += "$cf ($($_.Exception.Message))"
        }
    }

    if ($removedConflicts -gt 0) {
        Write-Host "    [+] Auto-deleted $removedConflicts conflicting file(s)." -ForegroundColor Green
    }

    if ($failedConflicts.Count -gt 0) {
        Write-Host "    [!] Could not delete $($failedConflicts.Count) conflicting item(s):" -ForegroundColor Yellow
        foreach ($failed in $failedConflicts) {
            Write-Host "        - $failed" -ForegroundColor Yellow
        }
        Write-Host "    [!] Close the game/Steam or run as Administrator if a file is locked." -ForegroundColor Yellow
    }
}
else {
    Write-Host "    [+] No conflicting files detected." -ForegroundColor Green
}

# 6. stplug-in lua modification
if ($isUnreleased) {
    # Unreleased game - no AppID registered in SteamTools yet, skip lua check
    Write-Host "`n[*] Skipping stplug-in lua check (game is not yet released on Steam)." -ForegroundColor DarkGray
    $luaFiles = @()
}
else {
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
function Get-PrimaryGpuInfo {
    $controllers = @()
    try {
        $controllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and ($_.Name -notmatch 'Microsoft Basic|Remote Display|Parsec|Virtual|VMware|Hyper-V') })
    }
    catch {}

    $registryAdapters = @()
    try {
        $displayClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        $registryAdapters = @(Get-ChildItem -LiteralPath $displayClass -ErrorAction Stop |
            Where-Object { $_.PSChildName -match '^\d{4}$' } |
            ForEach-Object {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return }

                $name = $props.DriverDesc
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $props.'HardwareInformation.AdapterString' }
                if ([string]::IsNullOrWhiteSpace($name)) { return }

                $memoryBytes = 0L
                $qwMemory = $props.'HardwareInformation.qwMemorySize'
                if ($qwMemory -is [byte[]] -and $qwMemory.Length -ge 8) {
                    $memoryBytes = [BitConverter]::ToInt64($qwMemory, 0)
                }
                elseif ($qwMemory) {
                    try { $memoryBytes = [int64]$qwMemory } catch {}
                }

                if ($memoryBytes -le 0 -and $props.'HardwareInformation.MemorySize') {
                    try { $memoryBytes = [uint64]$props.'HardwareInformation.MemorySize' } catch {}
                }

                [pscustomobject]@{
                    Name        = $name.Trim()
                    MemoryBytes = [int64]$memoryBytes
                }
            } |
            Where-Object { $_.MemoryBytes -gt 0 } |
            Sort-Object MemoryBytes -Descending)
    }
    catch {}

    if ($registryAdapters.Count -gt 0) {
        $best = $registryAdapters | Select-Object -First 1
        return [pscustomobject]@{
            Name   = $best.Name
            VramGB = [math]::Round($best.MemoryBytes / 1GB, 1)
        }
    }

    $gpu = $controllers |
        Where-Object { $_.AdapterRAM -gt 0 } |
        Sort-Object AdapterRAM -Descending |
        Select-Object -First 1

    if ($gpu) {
        return [pscustomobject]@{
            Name   = $gpu.Name.Trim()
            VramGB = [math]::Round($gpu.AdapterRAM / 1GB, 1)
        }
    }

    return [pscustomobject]@{
        Name   = "Unknown"
        VramGB = 0
    }
}

function Remove-SteamLaunchOptionsForApp {
    param(
        [string]$SteamPath,
        [string]$TargetAppID
    )

    if ([string]::IsNullOrWhiteSpace($SteamPath) -or [string]::IsNullOrWhiteSpace($TargetAppID)) {
        return
    }

    $userdataPath = Join-Path $SteamPath "userdata"
    if (-not (Test-Path -LiteralPath $userdataPath)) {
        return
    }

    $configFiles = @()
    $userDirs = @(Get-ChildItem -LiteralPath $userdataPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' -and $_.Name -ne '0' })
    foreach ($userDir in $userDirs) {
        foreach ($configName in @("localconfig.vdf", "sharedconfig.vdf")) {
            $vdfPath = Join-Path $userDir.FullName "config\$configName"
            if (Test-Path -LiteralPath $vdfPath) {
                $configFiles += $vdfPath
            }
        }
    }

    $pending = @()
    foreach ($vdfPath in $configFiles) {
        try {
            $vdfContent = Get-Content -LiteralPath $vdfPath -Raw -Encoding UTF8
            $blockOpen = [regex]::Match($vdfContent, '"' + [regex]::Escape($TargetAppID) + '"\s*\{')
            if (-not $blockOpen.Success) { continue }

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
            if ($endIdx -le $startIdx) { continue }

            $blockBody = $vdfContent.Substring($startIdx, $endIdx - $startIdx)
            $loPattern = '(?m)^[\t ]*"LaunchOptions"[\t ]+"(?:[^"\\]|\\.)*"[\t ]*\r?\n?'
            if (-not [regex]::IsMatch($blockBody, $loPattern)) { continue }

            $newBody = [regex]::Replace($blockBody, $loPattern, "", 1)
            $newContent = $vdfContent.Substring(0, $startIdx) + $newBody + $vdfContent.Substring($endIdx)
            $pending += @{ Path = $vdfPath; Content = $newContent }
        }
        catch {
            Write-Host "    [!] Could not inspect $vdfPath`: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($pending.Count -eq 0) {
        Write-Host "    [+] No old Steam LaunchOptions found for AppID $TargetAppID." -ForegroundColor DarkGray
        return
    }

    Write-Host "    [*] Found old Steam LaunchOptions for unreleased AppID $TargetAppID. Clearing them..." -ForegroundColor Cyan
    Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $cleared = 0
    foreach ($item in $pending) {
        try {
            Set-Content -LiteralPath $item.Path -Value $item.Content -Encoding UTF8 -NoNewline
            $cleared++
        }
        catch {
            Write-Host "    [!] Could not update $($item.Path): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($cleared -gt 0) {
        Write-Host "    [+] Cleared old Steam LaunchOptions from $cleared config file(s)." -ForegroundColor Green
    }
}

$cpuName = "Unknown"
try { $cpuName = (Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name.Trim() } catch {}
$gpuName = "Unknown"
$gpuVram = 0
try {
    $gpuInfo = Get-PrimaryGpuInfo
    $gpuName = $gpuInfo.Name
    $gpuVram = $gpuInfo.VramGB
}
catch {}
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
}
catch {}

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
    install_dir             = $installDir
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
        # until AFTER Steam restart - prevents users from closing the script early
        # and skipping the launch options write.
        $deferCodeDisplay = $customLaunchers.ContainsKey($AppID) -and -not $isUnreleased

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
if ($customLaunchers.ContainsKey($AppID) -and -not $isUnreleased) {
    Write-Host "`nPress any key to restart Steam and set launch options..." -ForegroundColor Yellow
}
else {
    Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
}
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# --- Set custom launch options (Steam must be closed for this to persist) ---
if ($customLaunchers.ContainsKey($AppID) -and -not $isUnreleased -and $installDir -and $steamPath) {
    Write-Host "`nRestarting Steam..." -ForegroundColor Cyan
    Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $cfg = $customLaunchers[$AppID]
    Write-Host "[*] Setting Steam launch options for $($cfg.GameName)..." -ForegroundColor Cyan

    # Resolve the launcher exe path - prefer existing location (configured path then recursive by filename),
    # otherwise default to "<installDir>\<Exe>" even if the exe isn't there yet.
    # Exe can be either "tokeer_launcher.exe" or a relative path like "runtime\media\tokeer_launcher.exe".
    $launcherPath = Join-Path $installDir $cfg.Exe
    if (-not (Test-Path -LiteralPath $launcherPath)) {
        $exeBaseName = Split-Path -Leaf $cfg.Exe
        $found = Get-ChildItem -Path $installDir -Filter $exeBaseName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
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
                        # AppID entry doesn't exist yet - inject a minimal block into "apps"
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
    if ($steamPath) {
        Start-Process -FilePath (Join-Path $steamPath "steam.exe")
    }
    else {
        Write-Host "[-] Could not find Steam executable to restart." -ForegroundColor Red
    }
}
elseif ($isUnreleased) {
    Write-Host "`n[*] Skipping Steam launch options/restart for unreleased game AppID $AppID." -ForegroundColor DarkGray
    Write-Host "[*] Checking for old Steam LaunchOptions written by older validators..." -ForegroundColor Cyan
    Remove-SteamLaunchOptionsForApp -SteamPath $steamPath -TargetAppID $AppID
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
