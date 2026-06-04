# Devuvo validation script - updated 2026-04-16
if (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

# Show-LuaError — surface a hard-stop error BOTH in the console (status pane)
# and as a blocking Windows popup in the user's face, because most users ignore
# the scrolling console text. $Title is the popup caption, $Message is the body
# (use plain \n line breaks). Best-effort popup: if the GUI subsystem isn't
# available it silently falls back to the console block, so it never breaks the
# script. Always prints the console version too.
function Show-LuaError {
    param(
        [string]$Title,
        [string]$Message
    )
    Write-Host "`n========================================================" -ForegroundColor Red
    Write-Host " $Title" -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Red
    foreach ($line in ($Message -split "`n")) {
        Write-Host "  $line" -ForegroundColor Yellow
    }
    Write-Host "========================================================" -ForegroundColor Red
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $form = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $true }
        [void][System.Windows.Forms.MessageBox]::Show(
            $form,
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $form.Dispose()
    }
    catch {
        # GUI not available — the console block above is the fallback.
    }
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
    if ($steamCandidates.Count -gt 0) {
        Write-Host "    Checked paths:" -ForegroundColor Yellow
        foreach ($candidate in $steamCandidates) {
            Write-Host "    - $candidate" -ForegroundColor DarkGray
        }
    }
    Show-LuaError -Title "Steam not found" -Message @"
Could not find your Steam installation on this PC.

Make sure Steam is installed normally, then run the validation again.
If Steam is installed on another drive, open it once so Windows registers it, then retry.
"@
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
$manifestStateFlagsPattern = '\x22StateFlags\x22\s+\x22(\d+)\x22'
$manifestBytesToDownloadPattern = '\x22BytesToDownload\x22\s+\x22(\d+)\x22'
$manifestBytesDownloadedPattern = '\x22BytesDownloaded\x22\s+\x22(\d+)\x22'

# Steam appmanifest install-state, parsed from the matched manifest below.
# Defaults (-1 / 0) mean "unknown", which makes the install-progress gate skip
# itself when we can't read them (e.g. unreleased games found by folder instead
# of an appmanifest).
$appStateFlags = -1
$bytesToDownload = 0
$bytesDownloaded = 0

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

                # Capture install state from this manifest so the gate below can
                # refuse to validate a game Steam is still downloading/updating.
                $stateFlagsMatch = [regex]::Match($manifestContent, $manifestStateFlagsPattern)
                if ($stateFlagsMatch.Success) { $appStateFlags = [int64]$stateFlagsMatch.Groups[1].Value }
                $btdMatch = [regex]::Match($manifestContent, $manifestBytesToDownloadPattern)
                if ($btdMatch.Success) { $bytesToDownload = [int64]$btdMatch.Groups[1].Value }
                $bdMatch = [regex]::Match($manifestContent, $manifestBytesDownloadedPattern)
                if ($bdMatch.Success) { $bytesDownloaded = [int64]$bdMatch.Groups[1].Value }

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

# 3.6 Smart App Control (SAC) — detect only.
# SAC (Windows 11 22H2+) blocks unsigned/low-reputation executables like
# tokeer_launcher.exe. We only detect it here and tell the user to turn it
# off themselves, then re-run — we do not touch it automatically.
Write-Host "`n[*] Checking Smart App Control status..." -ForegroundColor Cyan
$sacPolicyKey = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
$sacValueName = "VerifiedAndReputablePolicyState"
$sacState = $null
try {
    $sacState = (Get-ItemProperty -Path $sacPolicyKey -Name $sacValueName -ErrorAction Stop).$sacValueName
}
catch {
    # Key/value missing = SAC not present on this build (older Win10, etc.)
    $sacState = 0
}

# 0 = Off, 1 = Enforced (On), 2 = Evaluation. Anything non-zero blocks us.
if ($sacState -and $sacState -ne 0) {
    $sacLabel = if ($sacState -eq 1) { "ON (enforced)" } elseif ($sacState -eq 2) { "Evaluation mode" } else { "Active (state=$sacState)" }
    Show-LuaError -Title "Smart App Control MUST be OFF" -Message @"
Smart App Control is $sacLabel.

It WILL block the activation (tokeer_launcher.exe) — you cannot get your key until it is turned OFF.

How to turn it off:
  1. Open Windows Security
  2. Go to: App & browser control -> Smart App Control settings
  3. Set it to OFF
  4. Run this validation again

Note: turning Smart App Control OFF is permanent (Windows won't let you turn it back ON without a full reset), so this is normal and expected.
"@
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
else {
    Write-Host "    [+] Smart App Control is OFF or not present." -ForegroundColor Green
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

    # Block validation while Steam is still downloading/installing/updating.
    # $gameInstalled is true the instant the install folder exists, which is the
    # moment a download STARTS — so without this gate a D-Report code gets
    # generated for a half-downloaded game. The appmanifest StateFlags + byte
    # counters tell us whether the game is actually FULLY installed. Only
    # released games with a parsed manifest are gated; unreleased games (no
    # manifest, $appStateFlags stays -1) keep their folder-based behaviour.
    if (-not $isUnreleased -and $appStateFlags -ge 0) {
        $STATE_FULLY_INSTALLED = 4
        # Any of these StateFlags bits means Steam is mid download/update/
        # validate/stage — i.e. the game is NOT ready to validate:
        #   2 UpdateRequired      32 FilesMissing      128 FilesCorrupt
        #   256 UpdateRunning     512 UpdatePaused     1024 UpdateStarted
        #   65536 Reconfiguring   131072 Validating    262144 AddingFiles
        #   524288 Preallocating  1048576 Downloading  2097152 Staging
        #   4194304 Committing    8388608 UpdateStopping
        $STATE_BUSY_MASK = 2 -bor 32 -bor 128 -bor 256 -bor 512 -bor 1024 -bor 65536 -bor 131072 -bor 262144 -bor 524288 -bor 1048576 -bor 2097152 -bor 4194304 -bor 8388608
        $bytesComplete = ($bytesToDownload -le 0) -or ($bytesDownloaded -ge $bytesToDownload)
        $installComplete = (($appStateFlags -band $STATE_FULLY_INSTALLED) -ne 0) -and (($appStateFlags -band $STATE_BUSY_MASK) -eq 0) -and $bytesComplete
        if (-not $installComplete) {
            $progressText = ''
            if ($bytesToDownload -gt 0 -and $bytesDownloaded -lt $bytesToDownload) {
                $pct = [int][math]::Floor(($bytesDownloaded / $bytesToDownload) * 100)
                $progressText = " (about $pct% downloaded)"
            }
            $issues += "Game with AppID $AppID is still downloading/installing/updating in Steam$progressText. Wait until Steam shows it as fully installed (not 'Queued', 'Downloading', or 'Updating'), then run the validation again."
        }
    }
}
if (-not $updateBlocked) {
    $issues += "Windows Update is not disabled. Please disable it using WUB: https://www.sordum.org/9470/windows-update-blocker-v1-8/"
}

if ($issues.Count -gt 0) {
    $issueBody = "Please fix the following before running the validation again:`n`n"
    $issueBody += (($issues | ForEach-Object { "- $_" }) -join "`n`n")
    Show-LuaError -Title "Fix these before continuing" -Message $issueBody
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
    Write-Host "`n[*] Pinning the stplug-in lua to freeze the installed build (blocks Steam updates)..." -ForegroundColor Cyan

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

        # Manifest pinning: UNCOMMENT every setManifestid(...) line so SteamTools
        # locks the game to the build already installed and Steam stops showing
        # "Update Required". The CloudRedirect payload fix (applied below) is what
        # makes SteamTools honor these lines. A commented/absent setManifestid means
        # the app tracks "latest", which is what keeps prompting to update and can
        # break the activation.
        $luaRaw = Get-Content -LiteralPath $luaFile.FullName -Raw
        $commentedCount = ([regex]::Matches($luaRaw, "(?m)^\s*--+[ \t]*setManifestid\(")).Count
        $activeCount = ([regex]::Matches($luaRaw, "(?m)^\s*setManifestid\(")).Count
        if ($commentedCount -gt 0) {
            try { Copy-Item -LiteralPath $luaFile.FullName -Destination ($luaFile.FullName + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
            $pinned = [regex]::Replace($luaRaw, "(?m)^(\s*)--+[ \t]*(setManifestid\()", '$1$2')
            [System.IO.File]::WriteAllText($luaFile.FullName, $pinned, (New-Object System.Text.UTF8Encoding($false)))
            $reportData.UpdatesDisabled = $true
            Write-Host "    [+] Pinned $($luaFile.Name) to the installed build ($commentedCount manifest line(s) activated) - Steam updates disabled." -ForegroundColor Green
        }
        elseif ($activeCount -gt 0) {
            $reportData.UpdatesDisabled = $true
            Write-Host "    [+] $($luaFile.Name) is already pinned ($activeCount manifest line(s)) - Steam updates disabled." -ForegroundColor Green
        }
        else {
            Write-Host "    [!] $($luaFile.Name) has no setManifestid lines to pin - this game can't be frozen via manifest pinning." -ForegroundColor Yellow
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

function Get-SteamUpdateStatus {
    param([string]$SteamPath)
    # Reads steam.cfg and reports whether Steam client auto-updates are allowed.
    # BootStrapperInhibitAll=Enable hard-blocks the client from updating, which
    # also breaks CloudRedirect (it needs an up-to-date Steam).
    $cfg = Join-Path $SteamPath "steam.cfg"
    if (Test-Path $cfg) {
        $content = Get-Content -LiteralPath $cfg -Raw -ErrorAction SilentlyContinue
        if ($content -match "(?im)^\s*BootStrapperInhibitAll\s*=\s*Enable") {
            return "disabled"
        }
    }
    return "enabled"
}

function Invoke-CloudRedirectStFixer {
    param([string]$SteamPath)
    # CLI equivalent of CloudRedirect GUI -> Setup -> "Run All Patches".
    # Patches the SteamTools payload so games work even when ST's payload
    # server is down (the "no internet connection / update queue" error). The
    # CLI finds Steam, shuts it down itself, downloads ST core DLLs if missing,
    # applies the STFixer patches, deploys cloud_redirect.dll, and enables
    # auto-update.
    Write-Host "`n[*] Checking SteamTools payload fix (CloudRedirect)..." -ForegroundColor Cyan

    $isAdminCR = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdminCR) {
        Write-Host "    [-] Not running as Administrator — cannot patch SteamTools. Re-run as admin." -ForegroundColor Yellow
        return $false
    }

    # --- Report Steam auto-update status (from steam.cfg) ---
    $updStatus = Get-SteamUpdateStatus -SteamPath $SteamPath
    if ($updStatus -eq "disabled") {
        Write-Host "    [!] Steam auto-updates are OFF (steam.cfg has BootStrapperInhibitAll=Enable)." -ForegroundColor Yellow
        Write-Host "        The SteamTools fix needs an up-to-date Steam, so updates should be ON." -ForegroundColor Yellow
    }
    else {
        Write-Host "    [+] Steam auto-updates are ON." -ForegroundColor Green
    }

    # --- Skip if already applied for THIS Steam build ---
    # The fix is keyed to the Steam client version: steam.exe changes (new
    # LastWriteTime) whenever Steam updates, which is exactly when the payload
    # patch must be re-applied. If cloud_redirect.dll is present AND our marker
    # matches the current steam.exe, the patch is already in place — skip the
    # download + re-patch + Steam shutdown entirely so it doesn't run on every
    # single validation.
    $crDll = Join-Path $SteamPath "cloud_redirect.dll"
    $steamExe = Join-Path $SteamPath "steam.exe"
    $markerDir = Join-Path $env:LOCALAPPDATA "LuaToolsValidator"
    $marker = Join-Path $markerDir "cloudredirect_patched.marker"
    $currentSig = if (Test-Path $steamExe) { (Get-Item $steamExe).LastWriteTimeUtc.Ticks.ToString() } else { "" }

    if ((Test-Path $crDll) -and (Test-Path $marker) -and $currentSig) {
        $markedSig = (Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue).Trim()
        if ($markedSig -eq $currentSig) {
            Write-Host "    [+] SteamTools payload fix already applied for this Steam build — skipping." -ForegroundColor Green
            return $true
        }
        Write-Host "    [*] Steam was updated since the last patch — re-applying fix..." -ForegroundColor Cyan
    }
    else {
        Write-Host "    [*] No prior patch detected — applying SteamTools payload fix..." -ForegroundColor Cyan
    }

    $crExe = Join-Path $env:TEMP "CloudRedirectCLI.exe"
    $crUrls = @(
        "https://github.com/Selectively11/CloudRedirect/releases/latest/download/CloudRedirectCLI.exe"
    )
    $downloaded = $false
    foreach ($url in $crUrls) {
        try {
            Write-Host "    [*] Downloading CloudRedirect CLI..." -ForegroundColor DarkGray
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $crExe -TimeoutSec 120 -ErrorAction Stop
            $downloaded = $true
            break
        }
        catch {
            Write-Host "    [-] Download failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    if (-not $downloaded -or -not (Test-Path $crExe)) {
        Write-Host "    [-] Could not download CloudRedirect CLI; skipping payload fix." -ForegroundColor Red
        return $false
    }

    try {
        # /stfixer shuts Steam down itself before patching, so it's fine that
        # the launch-options step below also expects Steam closed. Capture the
        # output (while still showing it) so we can detect specific failures
        # like an unsupported Steam version and give the user a clear next step.
        $crOutput = (& $crExe "/stfixer" 2>&1 | Tee-Object -Variable _crLines | Out-String)
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-Host "    [+] SteamTools payload fix applied." -ForegroundColor Green
            # Record the Steam build we patched so future runs can skip.
            try {
                New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
                if ($currentSig) {
                    Set-Content -LiteralPath $marker -Value $currentSig -NoNewline -Encoding ASCII
                }
            }
            catch {}
            return $true
        }

        # Steam too old/new for CloudRedirect — the user just needs to update Steam.
        if ($crOutput -match "version .* is not supported" -or $crOutput -match "not supported") {
            $updNote = ""
            if ($updStatus -eq "disabled") {
                $updNote = "Your Steam auto-updates are currently OFF (steam.cfg) — turn them back ON so Steam can update.`n`n"
            }
            Show-LuaError -Title "Your Steam is out of date" -Message @"
The SteamTools fix needs an up-to-date Steam, and yours is too old.

${updNote}1. Open Steam and let it fully update (Steam -> top-left -> Check for Steam Client Updates)
2. Fully close Steam once it finishes updating
3. Run this validation again
"@
            return $false
        }

        Write-Host "    [-] CloudRedirect STFixer exited with code $exitCode." -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "    [-] Failed to run CloudRedirect STFixer: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 8. Restart Steam
if ($customLaunchers.ContainsKey($AppID) -and -not $isUnreleased) {
    Write-Host "`nPress any key to restart Steam and set launch options..." -ForegroundColor Yellow
}
else {
    Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
}
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Apply the SteamTools payload fix. Skips automatically if already applied for
# the current Steam build. When it does run it closes Steam (the CLI does it
# itself), so it's before the launch-options write, which also needs Steam
# closed — one shutdown covers both, and Steam is restarted afterward.
if ($steamPath) {
    Invoke-CloudRedirectStFixer -SteamPath $steamPath | Out-Null
}

# --- Set custom launch options (Steam must be closed for this to persist) ---
if ($customLaunchers.ContainsKey($AppID) -and -not $isUnreleased -and $installDir -and $steamPath) {
    Write-Host "`nClosing Steam to write launch options..." -ForegroundColor Cyan
    # Steam caches config in memory and rewrites localconfig.vdf on exit. If we
    # touch the VDF while Steam is still alive, our change is either blocked by a
    # file lock or overwritten by Steam's flush-on-exit. So kill steam.exe AND
    # steamwebhelper, then POLL until the process is actually gone (up to 20s)
    # instead of a fixed 2s guess that's too short on slow machines.
    foreach ($procName in @("steam", "steamwebhelper")) {
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
    }
    $steamDeadline = (Get-Date).AddSeconds(20)
    while ((Get-Process -Name "steam" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $steamDeadline) {
        Start-Sleep -Milliseconds 500
    }
    # Extra grace so the OS releases the file handles before we write.
    Start-Sleep -Seconds 1

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
                        # Write UTF-8 WITHOUT BOM. Windows PowerShell 5.1's
                        # Set-Content -Encoding UTF8 prepends a BOM, which Steam's
                        # VDF parser rejects -> it resets the config and the launch
                        # option vanishes. .NET WriteAllText with UTF8Encoding($false)
                        # guarantees no BOM on every PowerShell version.
                        [System.IO.File]::WriteAllText($vdfPath, $newContent, (New-Object System.Text.UTF8Encoding($false)))
                        $writtenCount++
                    }
                    else {
                        # AppID entry doesn't exist yet - inject a minimal block into "apps"
                        $appsMatch = [regex]::Match($vdfContent, '"apps"\s*\{')
                        if ($appsMatch.Success) {
                            $insertPos = $appsMatch.Index + $appsMatch.Length
                            $inject = "`r`n`t`t`t`t`"$AppID`"`r`n`t`t`t`t{`r`n`t`t`t`t`t$newValue`r`n`t`t`t`t}"
                            $newContent = $vdfContent.Substring(0, $insertPos) + $inject + $vdfContent.Substring($insertPos)
                            # UTF-8 without BOM (see note above) — Set-Content would
                            # add a BOM on PowerShell 5.1 and break the config.
                            [System.IO.File]::WriteAllText($vdfPath, $newContent, (New-Object System.Text.UTF8Encoding($false)))
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

    # Verify the option actually landed in at least one file by re-reading,
    # so a silent failure is visible instead of a false "success".
    $verifiedCount = 0
    if (Test-Path $userdataPath) {
        foreach ($userDir in $userDirs) {
            foreach ($configName in $configFiles) {
                $vdfPath = Join-Path $userDir.FullName "config\$configName"
                if (-not (Test-Path -LiteralPath $vdfPath)) { continue }
                try {
                    $check = [System.IO.File]::ReadAllText($vdfPath)
                    if ($check.Contains([System.IO.Path]::GetFileName($launcherPath))) {
                        $verifiedCount++
                    }
                }
                catch {}
            }
        }
    }

    if ($verifiedCount -gt 0) {
        Write-Host "    [+] Launch options set and verified in $verifiedCount config file(s)." -ForegroundColor Green
        Write-Host "        $launchOptionString" -ForegroundColor DarkGray
    }
    elseif ($writtenCount -gt 0) {
        Write-Host "    [!] Wrote launch options to $writtenCount file(s) but could not verify them on re-read." -ForegroundColor Yellow
        Write-Host "        If the game does not auto-launch the activator, set it manually in Steam:" -ForegroundColor Yellow
        Write-Host "        Right-click the game -> Properties -> Launch Options -> paste:" -ForegroundColor Yellow
        Write-Host "        $launchOptionString" -ForegroundColor Cyan
    }
    else {
        Write-Host "    [-] Could not update any Steam config file." -ForegroundColor Yellow
        Write-Host "        Set it manually in Steam: Right-click the game -> Properties ->" -ForegroundColor Yellow
        Write-Host "        Launch Options -> paste:" -ForegroundColor Yellow
        Write-Host "        $launchOptionString" -ForegroundColor Cyan
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

# The CloudRedirect STFixer step closes Steam to patch the payload. For games
# that don't go through the launch-options block above (non-custom-launcher or
# unreleased), nothing restarts Steam — so bring it back here if it's down, so
# the patched payload loads and the user can launch normally.
if ($steamPath -and -not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
    $steamExe = Join-Path $steamPath "steam.exe"
    if (Test-Path $steamExe) {
        Write-Host "`n[*] Restarting Steam to load the patched payload..." -ForegroundColor Cyan
        Start-Process -FilePath $steamExe
    }
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
