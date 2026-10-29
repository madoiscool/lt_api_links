# Devuvo validation script - updated 2026-04-16
if (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

# --- Version-lock helpers (proven standalone before folding in) ---------------
function Get-LtInstalledDepots {
    # @{ depotId = @{ manifest; size } } from the acf's InstalledDepots block ONLY.
    # Shared runtimes live in a separate SharedDepots block and are excluded, so we
    # never pin a shared depot to a guessed build.
    param([string]$AcfPath)
    $result = @{}
    if (-not (Test-Path -LiteralPath $AcfPath)) { return $result }
    $text = Get-Content -LiteralPath $AcfPath -Raw
    $m = [regex]::Match($text, '(?s)"InstalledDepots"\s*\{')
    if (-not $m.Success) { return $result }
    $i = $m.Index + $m.Length; $depth = 1
    while ($i -lt $text.Length -and $depth -gt 0) {
        if ($text[$i] -eq '{') { $depth++ } elseif ($text[$i] -eq '}') { $depth-- }
        $i++
    }
    $block = $text.Substring($m.Index + $m.Length, $i - ($m.Index + $m.Length))
    foreach ($dm in [regex]::Matches($block, '(?s)"(\d+)"\s*\{([^{}]*)\}')) {
        $depot = $dm.Groups[1].Value; $body = $dm.Groups[2].Value
        $gm = [regex]::Match($body, '"manifest"\s*"(\d+)"')
        if (-not $gm.Success) { continue }
        $sm = [regex]::Match($body, '"size"\s*"(\d+)"')
        $result[$depot] = @{ manifest = $gm.Groups[1].Value; size = ($(if ($sm.Success) { $sm.Groups[1].Value } else { '0' })) }
    }
    return $result
}

function Set-LtVersionPin {
    # Pin every INSTALLED depot to its currently-installed manifest (never a stale
    # GID that would downgrade the game); leave shared-runtime depots (not in
    # InstalledDepots) exactly as written. Returns the active-pin count.
    param([string]$LuaPath, [string]$AcfPath)
    $lines = [System.IO.File]::ReadAllLines($LuaPath)
    $rxSet = '^\s*(--)?\s*setmanifestid\s*\('
    $depots = Get-LtInstalledDepots -AcfPath $AcfPath
    $out = New-Object System.Collections.Generic.List[string]
    $handled = @{}
    foreach ($ln in $lines) {
        if ($ln -match $rxSet) {
            $dm = [regex]::Match($ln, 'setmanifestid\s*\(\s*(\d+)', 'IgnoreCase')
            $depot = if ($dm.Success) { $dm.Groups[1].Value } else { $null }
            if ($depot -and $depots.ContainsKey($depot)) {
                $g = $depots[$depot]
                $out.Add(('setManifestid({0}, "{1}", {2})' -f $depot, $g.manifest, $g.size))
                $handled[$depot] = $true
            } else {
                $out.Add($ln); if ($depot) { $handled[$depot] = $true }
            }
        } else { $out.Add($ln) }
    }
    foreach ($depot in $depots.Keys) {
        if (-not $handled.ContainsKey($depot)) {
            $g = $depots[$depot]
            $out.Add(('setManifestid({0}, "{1}", {2})' -f $depot, $g.manifest, $g.size))
        }
    }
    [System.IO.File]::WriteAllLines($LuaPath, $out, (New-Object System.Text.UTF8Encoding($false)))
    return @($out | Where-Object { $_ -match '^\s*setManifestid\(' }).Count
}

function Get-LtDisableUpdatesList {
    # AppIDs listed in disable_updates.txt in this repo. $null when it can't be
    # read, so a failed download never unpins a game that is meant to stay frozen.
    # The contents API first: raw.githubusercontent caches for 5 minutes and
    # ignores query strings, so a freshly added game was missed there.
    $sources = @(
        @{ Url = "https://api.github.com/repos/madoiscool/lt_api_links/contents/disable_updates.txt?ref=main"
           Headers = @{ "Accept" = "application/vnd.github.raw"; "User-Agent" = "LuaToolsValidator" } },
        @{ Url = "https://raw.githubusercontent.com/madoiscool/lt_api_links/main/disable_updates.txt"
           Headers = @{} }
    )
    foreach ($s in $sources) {
        try {
            $raw = (Invoke-WebRequest -UseBasicParsing -Uri $s.Url -Headers $s.Headers -TimeoutSec 10 -ErrorAction Stop).Content
            if ($raw -is [byte[]]) { $raw = [System.Text.Encoding]::UTF8.GetString($raw) }
            $ids = @([regex]::Matches(($raw -replace '(?m)#.*$', ''), '\d+') | ForEach-Object { $_.Value })
            return , $ids
        }
        catch { }
    }
    return $null
}

function Clear-LtAcfReadOnly {
    # A read-only appmanifest stops Steam writing app state for that game at all,
    # so any install, update, downgrade or verify dies before it starts: the
    # library shows DISK WRITE ERROR and content_log records "Failed to write app
    # state file". Nothing about that reads as a permissions problem from the
    # user's side, it just looks like a broken download, and clearing the flag is
    # the only fix. Older runs set it as a second lock on top of the manifest
    # pins in the lua; the pins are what actually hold a build, so the flag is
    # cleared wherever we find one. Returns $true only if it had to change something.
    param([string]$AcfPath)

    if (-not $AcfPath -or -not (Test-Path -LiteralPath $AcfPath)) { return $false }
    try {
        $item = Get-Item -LiteralPath $AcfPath -Force
        if (-not $item.IsReadOnly) { return $false }
        $item.IsReadOnly = $false
        return $true
    }
    catch {
        Write-Host "    [!] Could not clear the read-only flag on the appmanifest: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Set-LtAcfField {
    # Set one top-level AppState key, adding it right after "appid" if it is absent.
    param([string]$Text, [string]$Key, [string]$Value)
    if ($Text -match ('"' + [regex]::Escape($Key) + '"\s+"[^"]*"')) {
        return [regex]::Replace($Text,
            ('("' + [regex]::Escape($Key) + '"\s+")[^"]*(")'),
            ('${1}' + $Value + '${2}'))
    }
    return [regex]::Replace($Text, '("appid"\s+"\d+"\s*\r?\n)',
        ('${1}' + "`t`"$Key`"`t`t`"$Value`"`r`n"), 1)
}

function Repair-LtAppManifest {
    # Rewrite the appmanifest from the user's OWN state, so Steam re-reads it and
    # queues the downgrade the lua asks for.
    #
    # Deleting the manifest also works, and is what people fall back to by hand,
    # but it makes Steam treat the game as a fresh install and run its free-space
    # check against the FULL install size. Someone with 20 GB free cannot start a
    # 157 GB "install" even though the real download is a few GB, so that route is
    # shut to exactly the people who need it most.
    #
    # Keeping InstalledDepots untouched is what keeps this a delta: Steam diffs
    # what it believes is on disk against the pinned manifests and fetches only
    # the difference. Nothing here tells Steam the game is already downgraded,
    # which is why the depot manifests are never rewritten. Everything else is put
    # back to a clean just-installed state, the update-required bit is set so Steam
    # actually looks again, and the file is rewritten as UTF-8 with no BOM.
    param([string]$AcfPath)

    if (-not $AcfPath -or -not (Test-Path -LiteralPath $AcfPath)) { return $false }
    try {
        $item = Get-Item -LiteralPath $AcfPath -Force
        if ($item.IsReadOnly) { $item.IsReadOnly = $false }

        $text = [System.IO.File]::ReadAllText($AcfPath)
        if ($text -notmatch '"AppState"' -or $text -notmatch '"InstalledDepots"') {
            Write-Host "    [!] The appmanifest is not readable as one, leaving it alone." -ForegroundColor Yellow
            return $false
        }

        # An older validator read this file with the ANSI codepage and wrote it
        # back as UTF-8, so a name with a character like the trademark sign in
        # "EA SPORTS FC(tm) 26" came back doubly encoded. Undo that, and only when
        # it round-trips cleanly.
        $nm = [regex]::Match($text, '("name"\s+")([^"]*)(")')
        if ($nm.Success -and $nm.Groups[2].Value -match '[ÂÃâ]') {
            try {
                $cp = [System.Text.Encoding]::GetEncoding(1252)
                $fixed = [System.Text.Encoding]::UTF8.GetString($cp.GetBytes($nm.Groups[2].Value))
                if ($fixed -and $fixed.IndexOf([char]0xFFFD) -lt 0 -and $fixed -ne $nm.Groups[2].Value) {
                    $text = $text.Remove($nm.Groups[2].Index, $nm.Groups[2].Length).Insert($nm.Groups[2].Index, $fixed)
                    Write-Host "    [+] Repaired the game name in the appmanifest ('$fixed')." -ForegroundColor Green
                }
            }
            catch { }
        }

        # 4 = fully installed, 2 = update required. Installed stays on so Steam
        # keeps the files and the small space check; update-required is what puts
        # the download back in the library.
        $text = Set-LtAcfField -Text $text -Key 'StateFlags'          -Value '6'
        $text = Set-LtAcfField -Text $text -Key 'AutoUpdateBehavior'  -Value '0'
        $text = Set-LtAcfField -Text $text -Key 'ScheduledAutoUpdate' -Value '0'
        $text = Set-LtAcfField -Text $text -Key 'UpdateResult'        -Value '0'
        $text = Set-LtAcfField -Text $text -Key 'TargetBuildID'       -Value '0'
        $text = Set-LtAcfField -Text $text -Key 'StagingSize'         -Value '0'
        foreach ($k in @('BytesToDownload', 'BytesDownloaded', 'BytesToStage', 'BytesStaged')) {
            $text = Set-LtAcfField -Text $text -Key $k -Value '0'
        }

        $bak = "$AcfPath.ltbak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
        try { Copy-Item -LiteralPath $AcfPath -Destination $bak -Force } catch { }

        # No BOM. Set-Content -Encoding UTF8 on 5.1 writes one, and this file never
        # had it.
        [System.IO.File]::WriteAllText($AcfPath, $text, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch {
        Write-Host "    [!] Could not rewrite the appmanifest: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Set-LtAcfUpdateLock {
    # Freeze or unfreeze a game through its appmanifest's AutoUpdateBehavior.
    #
    # The read-only flag is never used on a version-locked game, and this always
    # clears it. While it is set Steam cannot write app state at all, so no
    # download can start: the library reports DISK WRITE ERROR and content_log
    # records "Failed to write app state file". Nothing about that reads as a
    # permissions problem from the user's side. A version-locked game is held on
    # its build by the manifest pin in the lua, which does not need the file
    # frozen, so the read-only flag buys nothing here and costs a broken-looking
    # download. Older runs (and the wrapper) may have set it, so clearing it on
    # every call is also the repair for anyone already stuck.
    param([string]$AcfPath, [bool]$Lock)

    if (-not $AcfPath -or -not (Test-Path -LiteralPath $AcfPath)) { return $false }
    try {
        $item = Get-Item -LiteralPath $AcfPath -Force
        if ($item.IsReadOnly) { $item.IsReadOnly = $false }

        $behavior = if ($Lock) { '1' } else { '0' }
        $text = [System.IO.File]::ReadAllText($AcfPath)
        if ($text -match '"AutoUpdateBehavior"\s+"\d+"') {
            $text = [regex]::Replace($text, '("AutoUpdateBehavior"\s+")\d+(")', ('${1}' + $behavior + '${2}'))
        }
        else {
            $text = [regex]::Replace($text, '("appid"\s+"\d+"\s*\r?\n)',
                ('${1}' + "`t`"AutoUpdateBehavior`"`t`t`"$behavior`"`r`n"), 1)
        }
        [System.IO.File]::WriteAllText($AcfPath, $text, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch {
        Write-Host "    [!] Could not change the update lock on the appmanifest: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Get-LtDepotcacheDir {
    # Steam reads a depot's manifest out of depotcache before it asks its CDN for
    # one, so this is where a build's manifests have to land.
    param([string]$SteamRoot)
    if (-not $SteamRoot) { return $null }
    $dir = Join-Path $SteamRoot "depotcache"
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { return $null }
    }
    return $dir
}

function Get-LtManifestVault {
    # Our own copy of every manifest we have ever placed. Steam empties depotcache
    # entries for a game when it is uninstalled, and without the manifest the lua's
    # pin points at a build Steam can no longer fetch, so the reinstall never
    # starts. Keeping a copy off to the side means a later run puts it straight
    # back with no download.
    param([string]$AppID)
    $dir = Join-Path $env:LOCALAPPDATA "LuaTools\manifest-vault\$AppID"
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { return $null }
    }
    return $dir
}

function Copy-LtManifest {
    # Copy one manifest into depotcache and leave it writable.
    #
    # A manual drop of these same files (writable) makes Steam show the
    # downgrade; a read-only copy does not, because Steam rewrites the depot's
    # manifest in depotcache while it stages the build and cannot touch a
    # read-only file, so the update never starts. The vault copy is what carries
    # a manifest across an uninstall now, not a read-only flag. Any read-only
    # copy an older run left behind is cleared here so this self-heals on re-run.
    param([string]$From, [string]$To)
    try {
        if (Test-Path -LiteralPath $To) {
            $existing = Get-Item -LiteralPath $To -Force
            if ($existing.IsReadOnly) { $existing.IsReadOnly = $false }
        }
        Copy-Item -LiteralPath $From -Destination $To -Force -ErrorAction Stop
        $placed = Get-Item -LiteralPath $To -Force
        if ($placed.IsReadOnly) { $placed.IsReadOnly = $false }
        return $true
    }
    catch {
        return $false
    }
}

function Ensure-LtLockedManifests {
    # Put the locked build's manifests where Steam looks.
    #
    # The lua pin alone stopped being enough: Steam will not hand out a manifest
    # request code for a build to an account that does not own the game, so the
    # pinned old manifest can never be fetched and the "update" dies before it
    # downloads anything. Dropping the .manifest files straight into depotcache
    # skips that request entirely, which is the same trick the seeder uses.
    #
    # Files already present are left alone, so this is a no-op on a machine that
    # is already set up. Returns $true when every pinned depot has its manifest.
    param(
        [string]$AppID,
        [string]$Lua,
        [string]$SteamRoot
    )

    $wanted = @{}
    foreach ($m in [regex]::Matches($Lua, '(?im)^[ \t]*setManifestid\s*\(\s*(\d+)\s*,\s*"(\d+)"')) {
        $wanted[$m.Groups[1].Value] = $m.Groups[2].Value
    }
    if ($wanted.Count -eq 0) { return $true }

    $depotcache = Get-LtDepotcacheDir -SteamRoot $SteamRoot
    if (-not $depotcache) {
        Write-Host "    [!] Could not open the depotcache folder, skipping the manifest seed." -ForegroundColor Yellow
        return $false
    }
    $vault = Get-LtManifestVault -AppID $AppID

    $missing = @{}
    foreach ($depot in $wanted.Keys) {
        $name = "$depot`_$($wanted[$depot]).manifest"
        $dest = Join-Path $depotcache $name
        if (Test-Path -LiteralPath $dest) {
            # An earlier run may have left this read-only, which stops Steam
            # staging the downgrade. Clear it so an already-set-up machine heals.
            try {
                $have = Get-Item -LiteralPath $dest -Force
                if ($have.IsReadOnly) { $have.IsReadOnly = $false }
            } catch {}
            # keep the vault topped up from what is already good on disk
            if ($vault) {
                $keep = Join-Path $vault $name
                if (-not (Test-Path -LiteralPath $keep)) {
                    try { Copy-Item -LiteralPath $dest -Destination $keep -Force } catch {}
                }
            }
            continue
        }
        $missing[$depot] = $name
    }
    if ($missing.Count -eq 0) {
        Write-Host "    [+] All $($wanted.Count) pinned manifest(s) are already in depotcache." -ForegroundColor Green
        return $true
    }

    # 1. anything the vault still holds goes back for free
    $restored = 0
    if ($vault) {
        foreach ($depot in @($missing.Keys)) {
            $name = $missing[$depot]
            $keep = Join-Path $vault $name
            if ((Test-Path -LiteralPath $keep) -and (Copy-LtManifest -From $keep -To (Join-Path $depotcache $name))) {
                $missing.Remove($depot)
                $restored++
            }
        }
    }
    if ($restored -gt 0) {
        Write-Host "    [+] Put $restored manifest(s) back from the local copy." -ForegroundColor Green
    }
    if ($missing.Count -eq 0) { return $true }

    # 2. the rest come out of the build's manifest pack. Try any local copy first
    #    (fast, no download), then fall back to the release. A local <AppID>.zip is
    #    often a STALE or partial manual download, so we do not trust it: if it does
    #    not satisfy every missing pin we move on to the authoritative release
    #    instead of stopping with the pins still unplaced.
    $packCandidates = @()
    $localZips = @(
        (Join-Path $env:USERPROFILE "Downloads\$AppID.zip"),
        (Join-Path $env:TEMP "$AppID.zip")
    )
    if ($PSScriptRoot) { $localZips = @((Join-Path $PSScriptRoot "$AppID.zip")) + $localZips }
    foreach ($cand in $localZips) {
        if (Test-Path -LiteralPath $cand) { $packCandidates += $cand }
    }
    # Sentinel handled below: download straight off the release, which GitHub serves
    # from its own CDN (no api.github.com rate limit) with nothing of ours to keep
    # running. To add a game, upload <AppID>.zip to the versionlocks release.
    $packCandidates += "@release@"

    $placed = 0
    $extra = 0
    foreach ($cand in $packCandidates) {
        if ($missing.Count -eq 0) { break }

        if ($cand -eq "@release@") {
            $pack = Join-Path $env:TEMP "$AppID`_lock.zip"
            $url = "https://github.com/madoiscool/lt_api_links/releases/download/versionlocks/$AppID.zip"
            try {
                Write-Host "    [*] Fetching the build's manifests..." -ForegroundColor DarkGray
                $oldProgress = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'   # the progress bar makes this crawl
                try {
                    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $pack -TimeoutSec 180 -ErrorAction Stop
                }
                finally { $ProgressPreference = $oldProgress }
            }
            catch {
                Write-Host "    [-] Could not download the manifest pack: $($_.Exception.Message)" -ForegroundColor Yellow
                continue
            }
        }
        else {
            $pack = $cand
        }

        $stage = Join-Path $env:TEMP "lt_lock_$AppID"
        try {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -LiteralPath $pack -DestinationPath $stage -Force -ErrorAction Stop
        }
        catch {
            Write-Host "    [-] A manifest pack could not be opened: $($_.Exception.Message)" -ForegroundColor Yellow
            continue
        }

        foreach ($depot in @($missing.Keys)) {
            $name = $missing[$depot]
            $src = Get-ChildItem -LiteralPath $stage -Filter $name -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $src) { continue }
            # Keep our permanent vault copy regardless of the depotcache write. The
            # vault lives in LOCALAPPDATA, so it never needs elevation and Steam never
            # prunes it; even if the depotcache copy is blocked, the vault copy lets
            # the next run re-seed and lets the gate recognise this machine as set up.
            $inVault = $false
            if ($vault) {
                try { Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $vault $name) -Force; $inVault = $true } catch {}
            }
            $inCache = Copy-LtManifest -From $src.FullName -To (Join-Path $depotcache $name)
            if ($inCache) { $placed++ }
            if ($inCache -or $inVault) { $missing.Remove($depot) }
        }
        # The pack also carries the shared and redist depots the lua lists without a
        # pin. They are not what this is for, but the archive is already open and a
        # manifest sitting in depotcache is one less thing Steam has to go and ask
        # for, so any that are not there yet go in too (and into the vault).
        foreach ($f in @(Get-ChildItem -LiteralPath $stage -Filter *.manifest -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($vault) {
                $vdest = Join-Path $vault $f.Name
                if (-not (Test-Path -LiteralPath $vdest)) { try { Copy-Item -LiteralPath $f.FullName -Destination $vdest -Force } catch {} }
            }
            $dest = Join-Path $depotcache $f.Name
            if (Test-Path -LiteralPath $dest) { continue }
            if (Copy-LtManifest -From $f.FullName -To $dest) { $extra++ }
        }
        try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    if ($extra -gt 0) {
        Write-Host "    [+] Also placed $extra shared depot manifest(s) from the pack." -ForegroundColor DarkGray
    }
    if ($placed -gt 0) {
        Write-Host "    [+] Placed $placed manifest(s) into depotcache." -ForegroundColor Green
    }
    if ($missing.Count -gt 0) {
        Write-Host "    [!] $($missing.Count) pinned depot(s) still have no manifest: $($missing.Values -join ', ')" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Remove-LtNewerManifests {
    # A manifest for any other build of a locked depot. With one of those in
    # depotcache Steam can keep reading it and never offer the downgrade, which is
    # why wiping the Steam folder fixed it for Lark. Only the locked depots are
    # touched, and the pinned manifest is always kept. Run with Steam closed.
    param([string[]]$Dirs, [hashtable]$Pins)
    $removed = 0
    foreach ($dir in $Dirs) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($depot in $Pins.Keys) {
            $keep = "$depot`_$($Pins[$depot]).manifest"
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "$depot`_*.manifest" -File -ErrorAction SilentlyContinue)) {
                if ($f.Name -eq $keep) { continue }
                try {
                    if ($f.IsReadOnly) { $f.IsReadOnly = $false }
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $removed++
                }
                catch { }
            }
        }
    }
    return $removed
}

function Stop-LtSteam {
    param([string]$SteamRoot)
    if (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) { return }
    $exe = Join-Path $SteamRoot "steam.exe"
    if (Test-Path -LiteralPath $exe) {
        try { Start-Process -FilePath $exe -ArgumentList "-shutdown" } catch { }
    }
    for ($i = 0; $i -lt 30; $i++) {
        if (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Seconds 1
    }
    Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Invoke-LtLockedValidate {
    # The "update" to the pinned build is often so small that it is done before
    # the library ever shows it, or it never shows at all. steam://validate makes
    # Steam check every file against the pinned manifests and fetch what differs,
    # so the downgrade lands either way. Steam is restarted first so OST loads the
    # locked lua, and stale manifests for other builds are cleared while it is down.
    param([string]$AppID, [string]$SteamRoot, [string[]]$CacheDirs, [hashtable]$Pins)
    Write-Host "    [*] Restarting Steam to load the lock..." -ForegroundColor DarkGray
    Stop-LtSteam -SteamRoot $SteamRoot
    $gone = Remove-LtNewerManifests -Dirs $CacheDirs -Pins $Pins
    if ($gone -gt 0) {
        Write-Host "    [+] Removed $gone manifest(s) for other builds of the locked depots." -ForegroundColor Green
    }
    $exe = Join-Path $SteamRoot "steam.exe"
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    try {
        Start-Process -FilePath $exe
        for ($i = 0; $i -lt 20 -and -not (Get-Process -Name "steam" -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
        Start-Sleep -Seconds 15
        Start-Process "steam://validate/$AppID"
        Write-Host "    [+] Asked Steam to verify the game files." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "    [!] Could not start the Steam file check: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Reset-LtSteamFiles {
    # Lark's fix for a downgrade Steam refuses to start: delete everything in the
    # Steam folder except his list and let steam.exe download a clean copy. The
    # engine goes too, so it has to be installed again afterwards. Returns how many
    # items could not be removed, or -1 if the folder doesn't look like Steam.
    param([string]$SteamRoot)
    $keepDirs  = @("appcache", "config", "steam", "steamapps", "userdata")
    $keepFiles = @("steam.exe")

    if (-not $SteamRoot) { return -1 }
    $root = [System.IO.Path]::GetFullPath($SteamRoot).TrimEnd('\')
    if ($root -eq [System.IO.Path]::GetPathRoot($root).TrimEnd('\')) { return -1 }
    if (-not (Test-Path -LiteralPath (Join-Path $root "steam.exe"))) { return -1 }
    if (-not (Test-Path -LiteralPath (Join-Path $root "steamapps"))) { return -1 }

    Stop-LtSteam -SteamRoot $root
    Stop-Process -Name "steamwebhelper" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $failed = 0
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)) {
        $name = $item.Name.ToLowerInvariant()
        if ($item.PSIsContainer -and $keepDirs -contains $name) { continue }
        if (-not $item.PSIsContainer -and $keepFiles -contains $name) { continue }
        # A junction could point anywhere, and a recursive delete would follow it.
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
        try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop }
        catch { $failed++ }
    }
    return $failed
}

function Invoke-LtSteamReset {
    # depotcache goes with the wipe, so the locked game's manifests are put back
    # from the vault before Steam starts. Otherwise the downgrade has nothing to use.
    param([string]$SteamRoot, [string]$VaultDir)
    Write-Host "    [*] Closing Steam and removing its program files..." -ForegroundColor Cyan
    $failed = Reset-LtSteamFiles -SteamRoot $SteamRoot
    if ($failed -lt 0) {
        Write-Host "    [-] $SteamRoot doesn't look like a Steam folder, so nothing was removed." -ForegroundColor Red
        return $false
    }
    if ($failed -gt 0) {
        Write-Host "    [!] $failed item(s) were in use and could not be removed." -ForegroundColor Yellow
    }
    $cache = Join-Path $SteamRoot "depotcache"
    $saved = @(Get-ChildItem -LiteralPath $VaultDir -Filter *.manifest -File -ErrorAction SilentlyContinue)
    if ($saved.Count -gt 0) {
        New-Item -ItemType Directory -Force -Path $cache | Out-Null
        foreach ($m in $saved) { Copy-Item -LiteralPath $m.FullName -Destination $cache -Force -ErrorAction SilentlyContinue }
        Write-Host "    [+] Put back $($saved.Count) locked manifest(s)." -ForegroundColor Green
    }
    Write-Host "    [+] Done. Starting Steam so it can download a clean copy of itself..." -ForegroundColor Green
    try { Start-Process -FilePath (Join-Path $SteamRoot "steam.exe") } catch { }
    return $true
}

# RE Engine + Denuvo titles need REFramework's dinput8.dll in the game folder or
# they crash on new-game. The one dll below is the newest REFramework build and
# covers every one of these games (it detects the game at runtime), so we drop
# that single file rather than a per-game one. We place it here so the user never
# has to copy it by hand: without it they place it themselves, then launch the
# game outside the app, and the save carry-over never runs.
$reframeworkDinput8Games = @("2246340", "2852190", "3764200", "3357650", "2054970", "3500390", "2638890")
$reframeworkDinput8Url    = "https://github.com/madoiscool/lt_api_links/releases/download/reframework/dinput8.dll"
$reframeworkDinput8Sha256 = "1DFE37DEDE668B5A969833DDFB2BBC933C83074E86FB03D46015690ADF8A29F3"

function Get-LtReframeworkDll {
    # Return a local path to the verified dinput8.dll, downloading it once into a
    # cache under LOCALAPPDATA and re-using it after. Returns $null on any failure.
    param([string]$Url, [string]$Sha256)
    $cacheDir = Join-Path $env:LOCALAPPDATA "LuaTools\reframework"
    $cached   = Join-Path $cacheDir "dinput8.dll"
    try {
        if (Test-Path -LiteralPath $cached) {
            $have = (Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash
            if ($have -eq $Sha256) { return $cached }
        }
    }
    catch { }
    try {
        if (-not (Test-Path -LiteralPath $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
        $tmp = Join-Path $cacheDir ("dl_" + [guid]::NewGuid().ToString("N") + ".tmp")
        $old = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 180 -ErrorAction Stop
        }
        finally { $ProgressPreference = $old }
        $dl = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
        if ($dl -ne $Sha256) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            return $null
        }
        Move-Item -LiteralPath $tmp -Destination $cached -Force
        return $cached
    }
    catch {
        return $null
    }
}

function Ensure-LtReframeworkDll {
    # Drop the universal REFramework dinput8.dll into the game folder, but only when
    # it isn't already there. If the folder already has a dinput8.dll we leave it
    # and skip the download entirely, so the 23 MB file is only fetched when it is
    # actually missing. Best effort: never throws.
    param([string]$InstallDir, [string]$Url, [string]$Sha256)
    if (-not $InstallDir -or -not (Test-Path -LiteralPath $InstallDir)) { return }
    $target = Join-Path $InstallDir "dinput8.dll"
    if (Test-Path -LiteralPath $target) {
        Write-Host "    [+] dinput8.dll is already in the game folder; leaving it as is." -ForegroundColor Green
        return
    }
    $src = Get-LtReframeworkDll -Url $Url -Sha256 $Sha256
    if (-not $src) {
        Write-Host "    [!] Could not fetch REFramework dinput8.dll; the game may crash until it is placed." -ForegroundColor Yellow
        return
    }
    try {
        Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
        Write-Host "    [+] Placed REFramework dinput8.dll into the game folder." -ForegroundColor Green
    }
    catch {
        Write-Host "    [!] Could not place REFramework dinput8.dll: $($_.Exception.Message)" -ForegroundColor Yellow
    }
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
    # F1 25 (Denuvo + tokeer)
    "3059520" = @{ Exe = "tokeer_launcher.exe"; GameName = "F1 25" }
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
    # The Adventures of Elliot: The Millennium Tales (Denuvo + tokeer)
    "3483510" = @{ Exe = "tokeer_launcher.exe"; GameName = "The Adventures of Elliot: The Millennium Tales" }
    # STAR WARS: Galactic Racer, launch the Shipping exe directly (written even with OST active)
    "4078430" = @{ Exe = "SWGR-Win64-Shipping.exe"; GameName = "STAR WARS: Galactic Racer"; Always = $true }
    # ACE COMBAT 8: WINGS OF THEVE, launch AceCombat8.exe directly (written even with OST active)
    "2288340" = @{ Exe = "AceCombat8.exe"; GameName = "ACE COMBAT 8: WINGS OF THEVE"; Always = $true }



}

# ========================
# VERSION-LOCKED GAMES
# A game whose LATEST Steam build broke activation gets forced back to a known-good
# older build: we write a version-locked lua (pins every main depot to the good
# build's manifest) and refuse to hand out a D-Report code until Steam has actually
# downgraded to it. A user on the broken latest build gets the lock written + told
# to let Steam "update" (the pin turns that into a downgrade); only a user already
# on the good build proceeds to the report.
# Format: AppID -> @{ GameName; BuildId; CheckDepot; CheckManifest; Lua = @'...'@ }
#   CheckDepot     one main depot from the lua
#   CheckManifest  the manifest GID that depot must be on for the build to count as
#                  downgraded (read back from the appmanifest InstalledDepots block)
#   Lua            the exact locked lua we write to stplug-in\<AppID>.lua
# ========================
$versionLockedGames = @{
    "3751950" = @{
        GameName      = "Assassin's Creed Black Flag Resynced"
        BuildId       = "24424450"
        CheckDepot    = "3751951"
        CheckManifest = "4397710407098141927"
        Lua           = @'
-- Generated with Luie @ https://lua.tools/
-- 3751950 - Assassin's Creed Black Flag Resynced
-- Version-locked to Build 24424450 — released 2026-08-04 13:58:25 UTC
-- Generated 2026-08-07 05:26:55 UTC
-- # Depots (Total/DLC/Shared): 10/0/2

-- Main AppID
addappid(3751950, 1, "e6d96386c77349411f5be39f2955ee0649a9a80abd22c3d69752bfc6e3302539")

-- Main Depots
addappid(3751951, 1, "0495628add2f29892c7a7930e1ed5332f68e374d7621e3338f23492fcd8f23db")
setManifestid(3751951, "4397710407098141927")
addappid(3751953, 1, "f96dc68fd865006d30d7d804bab42593f8bb6a5250624df45771cbc2a9c7aa45") -- French
setManifestid(3751953, "3022415893432196011")
addappid(3751954, 1, "b61e5b022604f5f47312b82b8489487c5b1dc57159c8ee09ecac0c7959631762") -- Italian
setManifestid(3751954, "6892818699399123643")
addappid(3751955, 1, "f2ae043d5d7111cfd549ed1bd3f0611cd26711aa4a55e1af56889e43e8d0fb1c") -- German
setManifestid(3751955, "4309823939662694323")
addappid(3751956, 1, "c6c9dba85bf9b4a6f19551cc87b047ab631cd88317027eb33e30174e4bbe41fc") -- Spanish
setManifestid(3751956, "6870137386025150758")
addappid(3751957, 1, "c98ba5f83bc7269be83bedef8689d8a68ff2bb4ad1d6f7ba221178305af557c4") -- Brazilian
setManifestid(3751957, "4086000294114352953")
addappid(3751958, 1, "17b0d6cff686c37972334878f48648f8982f40f290fdaeddc022e1a795e6452c") -- Japanese
setManifestid(3751958, "5424793249443767029")
addappid(3751959, 1, "6011c824af6fe4db62d3154d751de76d49422e4a56218d54d8ceb716cac7fa6c") -- Schinese
setManifestid(3751959, "6456623308878089663")

-- DLC's (no depot keys required)
addappid(4496490) -- Assassin's Creed Black Flag Resynced - Master Assassin Character Pack
addappid(4496500) -- Assassin's Creed Black Flag Resynced - Master Assassin Character Pack - Ubisoft Activation
addappid(4496510) -- Assassin's Creed Black Flag Resynced - Master Assassin Naval Pack
addappid(4496520) -- Assassin's Creed Black Flag Resynced - Master Assassin Naval Pack - Ubisoft Activation
addappid(4496530) -- Assassin's Creed Black Flag Resynced - Hellfire Character Pack
addappid(4496540) -- Assassin's Creed Black Flag Resynced - Hellfire Character Pack - Ubisoft Activation
addappid(4496550) -- Assassin's Creed Black Flag Resynced - Hellfire Naval Pack
addappid(4496560) -- Assassin's Creed Black Flag Resynced - Hellfire Naval Pack - Ubisoft Activation
addappid(4496580) -- Assassin's Creed Black Flag Resynced - Sea Serpent Character Pack
addappid(4496590) -- Assassin's Creed Black Flag Resynced - Sea Serpent Character Pack - Ubisoft Activation
addappid(4496600) -- Assassin's Creed Black Flag Resynced - Sea Serpent Naval Pack
addappid(4496610) -- Assassin's Creed Black Flag Resynced - Sea Serpent Naval Pack - Ubisoft Activation
addappid(4496620) -- Assassin's Creed Black Flag Resynced - Dragon Storm Character Pack
addappid(4496630) -- Assassin's Creed Black Flag Resynced - Dragon Storm Character Pack - Ubisoft Activation
addappid(4496640) -- Assassin's Creed Black Flag Resynced - Dragon Storm Naval Pack
addappid(4496650) -- Assassin's Creed Black Flag Resynced - Dragon Storm Naval Pack - Ubisoft Activation
addappid(4496660) -- Assassin's Creed Black Flag Resynced - Map Pack
addappid(4496670) -- Assassin's Creed Black Flag Resynced - MAP PACK - Ubisoft Activation
addappid(4496720) -- Assassin's Creed Black Flag Resynced - Standard Edition - Ubisoft Activation
addappid(4496730) -- Assassin's Creed Black Flag Resynced - Deluxe Edition - Ubisoft Activation
addappid(4519940) -- Assassin's Creed Black Flag Resynced - Standard Edition - Prepurchase - Ubisoft Activation
addappid(4519950) -- Assassin's Creed Black Flag Resynced - Deluxe Edition - Prepurchase - Ubisoft Activation
addappid(4872930) -- Assassin's Creed Black Flag Resynced - Standard Edition - PREVIEW - Ubisoft Activation
addappid(4892480) -- Assassin's Creed Black Flag Resynced - Deluxe Edition - PREVIEW - Ubisoft Activation

-- Shared Depots (Runtimes / Launchers / ETC)
addappid(228989, 1, "ad69276eb476cf06c40312df7376d63deac0c838b9a2767005be8bb306ffb853") -- (windows)
addappid(1716751, 1, "84780b728a23b1dabbe8b064807ccd3dbd40c67139ed569101104a418c581675")
'@
    }
    "4080220" = @{
        GameName      = "EA SPORTS FC 27"
        BuildId       = "25171808"
        CheckDepot    = "4080221"
        CheckManifest = "8878500642775157634"
        Lua           = @'
-- 4080220's Lua and Manifest, made by ExeGrabber (Clem engine)
-- EA SPORTS FC 27
-- BuildID: 25171808 (public)
addappid(4080220)
addappid(228989, 1, "ad69276eb476cf06c40312df7376d63deac0c838b9a2767005be8bb306ffb853") -- depot 228989
setManifestid(228989, "5753583882400741046", 25674515)
addappid(3340991, 1, "023daedb070e5af8704dc88ee0af829f5c11923d2e6a42cca11ba5713b9f4491") -- depot 3340991
setManifestid(3340991, "3755387105551220105", 247033311)
addappid(3893181, 1, "7f675c2fe8e758d16f3cf8d3b493956afaee78e96d78cdb668a5edb8ac1580f6") -- depot 3893181
setManifestid(3893181, "4878189275181659469", 344333537)
addappid(4080221, 1, "7049f0ef11b8ebe50c06c4543fe973208ba01b2d8da3069e108627fbf352cce4") -- depot 4080221
setManifestid(4080221, "8878500642775157634", 64355019193)
addappid(4080223, 1, "0573bfe3d4f8b5d2734b56489765324c3df348252909d8bd0687e15ce907a45b") -- depot 4080223
setManifestid(4080223, "2844633327964375509", 219395)
addappid(4080224, 1, "fa1acba06d8e53e502007d40cce2f465d0f11e333e3be79dbe670bf7569c133b") -- depot 4080224
setManifestid(4080224, "1522837532170075092", 1600780918)
addappid(4080225, 1, "6dd81776a48dc671a16191048c046607a79ab4013dadaf3112678d973e3b59c3") -- depot 4080225
setManifestid(4080225, "2830121205034384666", 182514)
addappid(4080226, 1, "773b9f7b9f5a017021c1210016fa5712f25b1034f6ea32ac5097cc071308c13e") -- depot 4080226
setManifestid(4080226, "5335581693918691469", 1212232642)
addappid(4080227, 1, "0821c95d0360dfcdc552c2de7118b4fed735bc21f333c678cb09f78bd5bdc591") -- depot 4080227
setManifestid(4080227, "388339849221300007", 1550722162)
addappid(4080228, 1, "0668b1ca3b4ae8b3c1e8ffbf98f2113b24c72450a400dcb022f96730a276b774") -- depot 4080228
setManifestid(4080228, "1294610170253164355", 1413307272)
addappid(4080229, 1, "847343c0863a7cb9671b65ab73c5a1189b40336f6f730dc4fd59cb5cb80a6aee") -- depot 4080229
setManifestid(4080229, "2678743399729336553", 1672152434)
addappid(4080261, 1, "82236ba461d7223a5639914e8e3218f4bed8dffa99eaa6e1126eac8302c7d6d8") -- depot 4080261
setManifestid(4080261, "770041676407763391", 1411060456)
addappid(4080262, 1, "7623a491ada9aa3c66fb115e6806b1d18e76952ce5ab3e23b25632eb2f214254") -- depot 4080262
setManifestid(4080262, "1897415010352797721", 197617)
addappid(4080263, 1, "e83e3fe2b272babfc141b8d01d702aa7e07021004552a7fd0a044ba0fd6e3076") -- depot 4080263
setManifestid(4080263, "7316453399498713607", 2833805)
addappid(4080264, 1, "57c6089562785df9880fa8af499fa64e0400798cc753e8e3aa128bcdab12a96c") -- depot 4080264
setManifestid(4080264, "6451413580981507559", 1755417986)
addappid(4080265, 1, "3fb5f73a06b7503c3bd74958ce1321884230ed85b835658e95d9b855cf96d2c4") -- depot 4080265
setManifestid(4080265, "7544564129171758317", 209213)
addappid(4080266, 1, "454be933df9a0720926f2edd97d069e879460f5545abfb62169a1924490ba7d5") -- depot 4080266
setManifestid(4080266, "7188230184079753568", 1715079285)
addappid(4080267, 1, "04489429055546441092e4770120b9510acd8af3da0cb628b288c6786479ff14") -- depot 4080267
setManifestid(4080267, "2195535499855198142", 214118)
addappid(4080268, 1, "88a78c4c2533d41ae630cec04f300ddd036446a76610582f07fce03e387b6f28") -- depot 4080268
setManifestid(4080268, "8388817817017844619", 1750770264)
addappid(4080269, 1, "6345670be2dc65acf2de2d327577645a049a3c31928729be7c84ec1a7f6ee741") -- depot 4080269
setManifestid(4080269, "510951353780694361", 214335)
addappid(4160760, 1, "15e8d4fc8ce2f557f097de8b931b420de5441b9b30d9f57548d36790cbf92a0c") -- depot 4160760
setManifestid(4160760, "1648716040609115293", 245995)
addappid(4160761, 1, "34ea8a902031313afc19fc07112d87f7ab7a5f61d1519f94788e2684ad0f4d70") -- depot 4160761
setManifestid(4160761, "1033779594077211551", 1479168048)
addappid(4160762, 1, "74e0165849379dc39f62c32f14f581cde89df83128e7e8b1f884a5047554d38e") -- depot 4160762
setManifestid(4160762, "6242186738971933662", 1902729959)
addappid(4160763, 1, "056ab5df670e8a6d546b48cf2f30c6fda08e7c7f78f9a267425bb3c50e2bb2ad") -- depot 4160763
setManifestid(4160763, "4260402710574580573", 1871893902)
addappid(4160764, 1, "0631805b76b7d3e0e6a4be26e79a01b9810087c6cd3aea02f77d7e969c7a8c1a") -- depot 4160764
setManifestid(4160764, "2393855831714087215", 1642486780)
'@
    }
}

# ========================
# FORCE-GBE OVERRIDE
# AppIDs that must use the GBE/tokeer_launcher method even when OpenSteamTool is
# active — for Denuvo titles that reject the OST registry ticket (code 88500012).
# Keep this in sync with the bot's /tokeer-gbe-add list. Example:
#   $forceGbe = @("493340", "2688950")
# ========================
$forceGbe = @()
$isForceGbe = $forceGbe -contains $AppID

# A force-GBE AppID writes its custom launch options by reading the EXACT launcher
# exe from the $customLaunchers table above (keyed by AppID) - so e.g. a game whose
# launcher lives at "runtime\media\tokeer_launcher.exe" gets that exact path, not a
# generic guess. The $forceGbe flag only decides WHETHER to write it (even under
# OST); the command itself always comes from $customLaunchers. So a force-GBE game
# must also have an entry in $customLaunchers - warn if it doesn't, so it's obvious.
if ($isForceGbe -and -not $customLaunchers.ContainsKey($AppID)) {
    Write-Host "    [!] AppID $AppID is force-GBE but has NO entry in `$customLaunchers - add its launcher exe there or no launch options will be written." -ForegroundColor Yellow
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
    LuaDirs              = @()

    WindowsUpdateBlocked = $false
    OstActive            = $false
    OstEngine            = "none"
    OstTomlOk            = $false
    UpdatesDisabled      = $false   # true for version-locked games and disable_updates.txt
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

function Get-GameTreeMatches {
    # Walk the game folder ONCE with .NET (far faster than repeated
    # Get-ChildItem -Recurse) and return the full paths whose leaf name matches
    # one of the given file/dir name sets. Falls back to a single Get-ChildItem
    # pass if the .NET enumerator trips on an odd/locked tree.
    param(
        [string]$Root,
        [string[]]$FileNames = @(),
        [string[]]$DirNames = @()
    )
    $result = @{
        Files = [System.Collections.Generic.List[string]]::new()
        Dirs  = [System.Collections.Generic.List[string]]::new()
    }
    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) { return $result }

    $fileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $FileNames) { [void]$fileSet.Add($n) }
    $dirSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $DirNames) { [void]$dirSet.Add($n) }

    try {
        if ($fileSet.Count -gt 0) {
            foreach ($p in [System.IO.Directory]::EnumerateFiles($Root, '*', [System.IO.SearchOption]::AllDirectories)) {
                if ($fileSet.Contains([System.IO.Path]::GetFileName($p))) { [void]$result.Files.Add($p) }
            }
        }
        if ($dirSet.Count -gt 0) {
            foreach ($p in [System.IO.Directory]::EnumerateDirectories($Root, '*', [System.IO.SearchOption]::AllDirectories)) {
                if ($dirSet.Contains([System.IO.Path]::GetFileName($p))) { [void]$result.Dirs.Add($p) }
            }
        }
    }
    catch {
        # Fallback: still ONE walk (not one-per-name) if the fast path errors out.
        $result.Files.Clear(); $result.Dirs.Clear()
        Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSIsContainer) { if ($dirSet.Contains($_.Name)) { [void]$result.Dirs.Add($_.FullName) } }
            elseif ($fileSet.Contains($_.Name)) { [void]$result.Files.Add($_.FullName) }
        }
    }
    return $result
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
    # One fast pass for ALL names at once (was one full recursive scan per name).
    $gbeMatches = Get-GameTreeMatches -Root $root -FileNames $fileNames -DirNames $dirNames

    foreach ($full in $gbeMatches.Files) {
        if (-not ($full.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        try {
            Remove-Item -LiteralPath $full -Force -ErrorAction Stop
            $rel = $full.Substring($root.Length).TrimStart('\', '/')
            Write-Host "    [-] Removed $rel" -ForegroundColor DarkGray
            $removed++
        }
        catch {
            Write-Host "    [!] Could not remove $full`: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Delete deepest dirs first so nested matches don't vanish mid-loop.
    foreach ($full in ($gbeMatches.Dirs | Sort-Object { $_.Length } -Descending)) {
        if (-not ($full.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        try {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
            $rel = $full.Substring($root.Length).TrimStart('\', '/')
            Write-Host "    [-] Removed $rel" -ForegroundColor DarkGray
            $removed++
        }
        catch {
            Write-Host "    [!] Could not remove $full`: $($_.Exception.Message)" -ForegroundColor Yellow
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
    # ReadAllText, not Get-Content: Steam writes this file as UTF-8, and under
    # Windows PowerShell 5.1 Get-Content decodes with the machine's ANSI
    # codepage instead. A library folder whose name is not plain ASCII then
    # comes back as mojibake, the path fails Test-Path, and the whole library is
    # dropped without a word. That is a game on a perfectly normal drive being
    # reported as not installed.
    $content = [System.IO.File]::ReadAllText($libraryFoldersPath)
    $vdfMatches = [regex]::Matches($content, $vdfPathPattern)
    foreach ($match in $vdfMatches) {
        $libPath = $match.Groups[1].Value.Replace("\\", "\")
        $libraries += $libPath
    }
}

# libraryfolders.vdf can miss a library (a drive added while Steam was closed, an
# older Steam, or files copied into a library Steam has not re-scanned). Probe the
# usual Steam library locations on every fixed drive too, so a game on D:/E: is not
# false-reported as missing just because the vdf only listed the C: library.
$fixedDrives = @()
try {
    $fixedDrives = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } |
        ForEach-Object { $_.RootDirectory.FullName }
}
catch {
    $fixedDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Root }
}
foreach ($drive in $fixedDrives) {
    if ([string]::IsNullOrWhiteSpace($drive)) { continue }
    $libGuesses = @(
        (Join-Path $drive "SteamLibrary"),
        (Join-Path $drive "Steam"),
        (Join-Path $drive "SteamLibrary\Steam"),
        (Join-Path $drive "Games\SteamLibrary"),
        (Join-Path $drive "Program Files (x86)\Steam"),
        (Join-Path $drive "Program Files\Steam"),
        ($drive.TrimEnd('\'))
    )
    foreach ($guess in $libGuesses) {
        if (Test-Path -LiteralPath (Join-Path $guess "steamapps\common")) {
            $libraries += $guess
        }
    }

    # A library the user named themselves ("E:\Games2", or a localised "New
    # folder") matches none of the guesses above, so the vdf is its only route
    # in. One level down from the drive root is a cheap listing and catches it
    # even when the vdf is missing, stale, or unreadable.
    foreach ($dir in (Get-ChildItem -LiteralPath $drive -Directory -Force -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName "steamapps\common")) {
            $libraries += $dir.FullName
        }
    }
}

# Drop duplicate library paths (case-insensitive), keeping first-seen order.
$seenLib = @{}
$libraries = @($libraries | Where-Object {
    $key = ($_ -replace '[\\/]+$', '').ToLowerInvariant()
    if ($seenLib.ContainsKey($key)) { $false } else { $seenLib[$key] = $true; $true }
})

if ($libraries.Count -eq 0) {
    $libraries = @($steamPath)
}

Write-Host "Scanning $($libraries.Count) Steam library folders..." -ForegroundColor Cyan

# 2. Check if AppID is installed
$installDir = $null
$gameLibrary = $null
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
    # Normal released game: use appmanifest. A library can hold a leftover
    # appmanifest from an old install whose folder is gone, so one whose game
    # folder exists wins; a leftover is only used when nothing better turns up.
    $acfWithFolder = @()
    $acfLeftover = @()
    foreach ($lib in $libraries) {
        $manifestPath = [System.IO.Path]::Combine($lib, "steamapps\appmanifest_$AppID.acf")
        if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
        $dirMatch = [regex]::Match([System.IO.File]::ReadAllText($manifestPath), $manifestInstallDirPattern)
        if ($dirMatch.Success -and (Test-Path -LiteralPath ([System.IO.Path]::Combine($lib, "steamapps\common\$($dirMatch.Groups[1].Value)")))) {
            $acfWithFolder += $lib
        }
        else {
            $acfLeftover += $lib
        }
    }
    foreach ($lib in ($acfWithFolder + $acfLeftover)) {
        $manifestPath = [System.IO.Path]::Combine($lib, "steamapps\appmanifest_$AppID.acf")
        if (Test-Path -LiteralPath $manifestPath) {
            # Same reason as libraryfolders.vdf above: installdir and name are
            # UTF-8 and a game folder with an accent in it must survive the read.
            $manifestContent = [System.IO.File]::ReadAllText($manifestPath)

            $installDirNameMatch = [regex]::Match($manifestContent, $manifestInstallDirPattern)
            $nameMatch = [regex]::Match($manifestContent, $manifestNamePattern)

            if ($installDirNameMatch.Success) {
                $installDir = [System.IO.Path]::Combine($lib, "steamapps\common\$($installDirNameMatch.Groups[1].Value)")
                $gameLibrary = $lib
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

# Clear a read-only appmanifest before anything else runs. While the flag is set
# Steam cannot write app state, so any install, update or downgrade dies as DISK
# WRITE ERROR before it starts. Nothing sets this flag anymore (the old
# disable-updates lock was removed), so a read-only acf is always a leftover from
# an older run and is cleared for whatever game is being validated.
foreach ($lib in $libraries) {
    $acfToFree = [System.IO.Path]::Combine($lib, "steamapps\appmanifest_$AppID.acf")
    if (-not (Test-Path -LiteralPath $acfToFree)) { continue }
    if (Clear-LtAcfReadOnly -AcfPath $acfToFree) {
        Write-Host "[+] Cleared the read-only flag on appmanifest_$AppID.acf so Steam can write app state." -ForegroundColor Green
    }
    break
}

$gameInstalled = $installDir -and (Test-Path $installDir)

if ($gameInstalled) {
    Write-Host "[+] Found Game: $gameName" -ForegroundColor Green
    Write-Host "[+] Install Directory: $installDir" -ForegroundColor Green
    if ($reframeworkDinput8Games -contains $AppID) {
        Write-Host "`n[*] Placing REFramework dinput8.dll..." -ForegroundColor Cyan
        Ensure-LtReframeworkDll -InstallDir $installDir -Url $reframeworkDinput8Url -Sha256 $reframeworkDinput8Sha256
    }
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

# 4.9 Check OpenSteamTool (OST) — the engine that serves the registry/Denuvo ticket.
# TokeerDRM codes only apply when OST is active, so we detect it the exact same way
# the OST installer does and report it. (Reported only — the bot decides whether to
# require it, so this stays safe for the legacy GBE flow.)
Write-Host "`n[*] Checking OpenSteamTool (OST) engine..." -ForegroundColor Cyan
$ostCore   = (Test-Path (Join-Path $steamPath "OpenSteamTool.dll")) -or (Test-Path (Join-Path $steamPath "mktl.dll"))
$ostHijack = (Test-Path (Join-Path $steamPath "dwmapi.dll")) -and (Test-Path (Join-Path $steamPath "xinput1_4.dll"))
$ostActive = $ostCore -and $ostHijack
$writeLaunchOptions = $customLaunchers.ContainsKey($AppID) -and -not $isUnreleased -and (-not $ostActive -or $isForceGbe -or $customLaunchers[$AppID].Always)
if (Test-Path (Join-Path $steamPath "mktl.dll")) {
    $ostEngine = "mktl (fork)"
}
elseif (Test-Path (Join-Path $steamPath "OpenSteamTool.dll")) {
    $ostEngine = "OpenSteamTool (official)"
}
else {
    $ostEngine = "none"
}

# The official OST needs its toml to include config\stplug-in; the mktl fork reads
# stplug-in natively, so it's always considered OK there.
$ostTomlOk = $true
if ($ostActive -and $ostEngine -like "OpenSteamTool*") {
    $tomlPath = Join-Path $steamPath "opensteamtool.toml"
    $ostTomlOk = (Test-Path $tomlPath) -and ((Get-Content $tomlPath -Raw) -match "stplug-in")
}

$reportData.OstActive = $ostActive
$reportData.OstEngine = $ostEngine
$reportData.OstTomlOk = $ostTomlOk

if ($ostActive) {
    Write-Host "    [+] OST engine detected: $ostEngine" -ForegroundColor Green
    # NOTE: we intentionally do NOT block or warn on a missing toml→stplug-in redirect
    # here. Redemption happens in the TokeerDRM app, which refuses to redeem (and
    # pops a repair/setup prompt) until the engine is fully configured, so the validator
    # leaves toml setup entirely to it. $ostTomlOk stays in the report for telemetry.
}
else {
    Write-Host "    [-] OpenSteamTool is not installed/active (needed for TokeerDRM codes)." -ForegroundColor Yellow
}

# Require the OFFICIAL OpenSteamTool engine (OpenSteamTool.dll) before going any
# further. An mktl-only setup does NOT count here on purpose. Without a real engine
# the run would silently fall back to writing tokeer_launcher launch options, which
# we don't want; stop and tell the user how to set the engine up instead. Force-GBE
# titles use the launcher path by design (OST's ticket fails for them) and
# unreleased games are handled separately, so both are exempt.
$ostOfficialActive = (Test-Path (Join-Path $steamPath "OpenSteamTool.dll")) -and $ostHijack
if (-not $ostOfficialActive -and -not $isForceGbe -and -not $isUnreleased) {
    Show-LuaError -Title "Set up your activation engine first" -Message @"
OpenSteamTool isn't installed, so activation can't continue.

Set it up one of these two ways, then run this again:

  1. Open the TokeerDRM app and let it install / repair OpenSteamTool
     (use the Fix DLL button if it prompts you).

  2. Open the LuaTools app, go to the Mode section, and choose BetterSteamTools.

Once OpenSteamTool is active, start the validation again.
"@
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
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
        # UpdateRequired is one we set ourselves on a version-locked game, to make
        # Steam offer the downgrade. On the next run it would read as "mid
        # download" here and hide the version-lock instructions behind a progress
        # message the user can do nothing about. Those games get their own build
        # check further down, so drop that one bit for them. Every other bit still
        # applies, so a genuine download in progress is still caught.
        $busyMask = $STATE_BUSY_MASK
        if ($versionLockedGames.ContainsKey($AppID)) {
            $busyMask = $busyMask -band (-bnot 2)
        }
        $bytesComplete = ($bytesToDownload -le 0) -or ($bytesDownloaded -ge $bytesToDownload)
        $installComplete = (($appStateFlags -band $STATE_FULLY_INSTALLED) -ne 0) -and (($appStateFlags -band $busyMask) -eq 0) -and $bytesComplete
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
$foundGoldberg = $false
$goldbergFoundPaths = @()

# Single fast pass for every indicator + the steam_api DLLs at once (was 6
# separate full recursive walks of the game folder).
$gbFileIndicators = @("steam_interfaces.txt", "coldclientloader.ini", "local_save.txt", "configs.user.ini", "steam_api.dll", "steam_api64.dll")
$gbDirIndicators = @("steam_settings")
$gbScan = Get-GameTreeMatches -Root $installDir -FileNames $gbFileIndicators -DirNames $gbDirIndicators

foreach ($match in $gbScan.Dirs) {
    $relativePath = $match.Substring($installDir.Length).TrimStart('\', '/')
    $foundGoldberg = $true
    $reportData.GoldbergFiles += $relativePath
    $goldbergFoundPaths += $match
}
foreach ($match in $gbScan.Files) {
    $leaf = [System.IO.Path]::GetFileName($match)
    if ($leaf -ieq "steam_api.dll" -or $leaf -ieq "steam_api64.dll") {
        # Only a Goldberg-PATCHED steam_api DLL counts (the real Steam one doesn't).
        try {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($match)
            if ($versionInfo.ProductName -match "Goldberg" -or $versionInfo.CompanyName -match "Goldberg" -or $versionInfo.FileDescription -match "Goldberg") {
                $foundGoldberg = $true
                $relativePath = $match.Substring($installDir.Length).TrimStart('\', '/')
                $reportData.GoldbergFiles += "$relativePath (patched DLL)"
                $goldbergFoundPaths += $match
            }
        }
        catch {}
    }
    else {
        $relativePath = $match.Substring($installDir.Length).TrimStart('\', '/')
        $foundGoldberg = $true
        $reportData.GoldbergFiles += $relativePath
        $goldbergFoundPaths += $match
    }
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
    "cracksteam_api64.dll",
    "voices38.dll",
    "steamclient_loader_x64.exe",
    "SimpleSvm.sys",
    "hyperkd.sys",
    "hyperhv.dll",
    "hyperevade.dll",
    "hyperlog.dll",
    "hyperlog.inf",
    "kdserial.dll"
)

# For RE Engine + Denuvo titles dinput8.dll IS the REFramework helper we place on
# purpose, so it must not be scanned as a conflict and deleted for those games. It
# stays a conflict for every other game.
if ($reframeworkDinput8Games -contains $AppID) {
    $conflictingNames = @($conflictingNames | Where-Object { $_ -ne "dinput8.dll" })
}

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

# Folders OST really loads luas from: <Steam>\config\stplug-in (its default) and any
# [lua] paths in opensteamtool.toml. Only if none exist, search the Steam folder, and
# then keep every match. Taking the first "stplug-in" anywhere under Steam could land
# on a backup or plugin folder and report the lua as missing when it isn't.
function Get-LuaDirs {
    $found = New-Object System.Collections.Generic.List[string]
    $candidates = @(Join-Path $steamPath "config\stplug-in")
    $toml = Join-Path $steamPath "opensteamtool.toml"
    if (Test-Path -LiteralPath $toml) {
        $raw = Get-Content -LiteralPath $toml -Raw
        $section = [regex]::Match($raw, '(?ms)^\s*\[lua\]\s*$(.*?)(?=^\s*\[|\z)')
        $paths = if ($section.Success) { [regex]::Match($section.Groups[1].Value, '(?ms)^\s*paths\s*=\s*\[(.*?)\]') }
        if ($paths -and $paths.Success) {
            foreach ($m in [regex]::Matches($paths.Groups[1].Value, '"([^"]+)"|''([^'']+)''')) {
                $p = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $steamPath $p }
                $candidates += $p
            }
        }
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Container) { $found.Add([System.IO.Path]::GetFullPath($c)) }
    }
    if ($found.Count -eq 0) {
        Get-ChildItem -Path $steamPath -Directory -Filter "stplug-in" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            ForEach-Object { $found.Add($_.FullName) }
    }
    $seen = @{}
    $out = @()
    foreach ($d in $found) {
        $key = $d.TrimEnd('\', '/').ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $out += $d }
    }
    return , $out
}

# 6. stplug-in lua modification
if ($isUnreleased) {
    # Unreleased game - no AppID registered in SteamTools yet, skip lua check
    Write-Host "`n[*] Skipping stplug-in lua check (game is not yet released on Steam)." -ForegroundColor DarkGray
    $luaFiles = @()
}
elseif ($versionLockedGames.ContainsKey($AppID)) {
    # This game's latest Steam build breaks the activation. Force the known-good
    # build: write our locked lua, then only continue to the D-Report once Steam is
    # actually on that build. A user still on the broken build gets the lock written
    # and is told to let Steam "update" (the pin makes that a downgrade), then
    # re-validate. This deliberately re-introduces pinning for this ONE AppID.
    $vl = $versionLockedGames[$AppID]
    Write-Host "`n[*] $($vl.GameName): enforcing version lock to build $($vl.BuildId) (its latest Steam build breaks activation)..." -ForegroundColor Cyan

    $luaDirs = Get-LuaDirs
    $stpluginDir = if ($luaDirs.Count -gt 0) { Get-Item -LiteralPath $luaDirs[0] }
    if (-not $stpluginDir) {
        Show-LuaError -Title "SteamTools not found" -Message @"
Could not find the Steam stplug-in folder, so the version lock can't be written.

Make sure SteamTools / OpenSteamTool is installed and has run at least once, then start the validation again.
"@
        Write-Host "`nPress any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
    Write-Host "    [+] Found stplug-in directory at: $($stpluginDir.FullName)" -ForegroundColor Green

    # Write (or repair) the locked lua as <AppID>.lua, backing up whatever was there.
    $lockedLuaPath = Join-Path $stpluginDir.FullName "$AppID.lua"
    $desiredLua = ($vl.Lua -replace "`r`n", "`n")
    $currentLua = if (Test-Path -LiteralPath $lockedLuaPath) { (Get-Content -LiteralPath $lockedLuaPath -Raw) -replace "`r`n", "`n" } else { "" }

    # The pins this lock needs: depot -> manifest gid, read from the locked lua.
    $wantedPins = @{}
    foreach ($pm in [regex]::Matches($desiredLua, '(?im)^[ \t]*setManifestid\s*\(\s*(\d+)\s*,\s*"(\d+)"')) {
        $wantedPins[$pm.Groups[1].Value] = $pm.Groups[2].Value
    }

    # Is the lock already set in the lua? We do NOT compare the whole file. BetterSteamTools
    # and other forks re-save the lua in their own format once they load it, so an exact match
    # would fail on every re-run and keep nagging. What matters is that every depot is pinned to
    # the exact gid as an active (not commented) setManifestid line. That survives a reformat and
    # is the real meaning of "the lua is set".
    $luaWasCorrect = $true
    foreach ($depot in $wantedPins.Keys) {
        $rx = '(?im)^[ \t]*setManifestid\s*\(\s*' + [regex]::Escape($depot) + '\s*,\s*"' + [regex]::Escape($wantedPins[$depot]) + '"'
        if ($currentLua -notmatch $rx) { $luaWasCorrect = $false; break }
    }
    if ($wantedPins.Count -eq 0) { $luaWasCorrect = ($currentLua.Trim() -eq $desiredLua.Trim()) }

    # Only write when it is not already correct. A lua that is already right is left
    # alone, so a game that is already set up is not needlessly poked.
    if (-not $luaWasCorrect) {
        if ($currentLua) {
            try { Copy-Item -LiteralPath $lockedLuaPath -Destination ($lockedLuaPath + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
        }
        [System.IO.File]::WriteAllText($lockedLuaPath, $desiredLua, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "    [+] Wrote version-locked lua: $lockedLuaPath" -ForegroundColor Green
    }
    else {
        Write-Host "    [+] Version-locked lua already in place." -ForegroundColor Green
    }

    # Sitting in LuaTools' own <AppID>.lua slot is not enough to make the lock
    # stick. When two files pin the same depot SteamTools keeps whichever it read
    # last, and the folder is read in name order, so tokeerdrm_<AppID>.lua (written
    # by the TokeerDRM app on redeem) lands after <AppID>.lua and its pin to the
    # CURRENT build silently cancels ours: the lua looks correct, and no update
    # ever appears. Comment out the competing setManifestid lines only. Everything
    # else in those files, including the appticket and eticket that a redeemed
    # activation depends on, is left exactly as it was.
    $lockedDepots = @(
        [regex]::Matches($desiredLua, '(?im)^[ \t]*setManifestid\s*\(\s*(\d+)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    )
    foreach ($other in @(Get-ChildItem -LiteralPath $stpluginDir.FullName -Filter *.lua -ErrorAction SilentlyContinue)) {
        if ($other.FullName -eq $lockedLuaPath) { continue }
        $otherText = [System.IO.File]::ReadAllText($other.FullName)
        $patched = $otherText
        foreach ($depot in $lockedDepots) {
            # Anchored to the start of a line, so an already commented pin is
            # skipped and nothing inside a ticket string can be hit.
            $patched = [regex]::Replace(
                $patched,
                ('(?im)^(?<indent>[ \t]*)(?<call>setManifestid[ \t]*\([ \t]*' + $depot + '[ \t]*,)'),
                '${indent}-- ${call}'
            )
        }
        if ($patched -ne $otherText) {
            try { Copy-Item -LiteralPath $other.FullName -Destination ($other.FullName + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
            [System.IO.File]::WriteAllText($other.FullName, $patched, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "    [+] Disabled a competing version pin in $($other.Name)" -ForegroundColor Green
        }
    }

    $reportData.LuaFileFound = $true
    $reportData.UpdatesDisabled = $true

    # The pin names an old build's manifest, and Steam can no longer fetch one of
    # those for an account that does not own the game, so the download dies before
    # it starts. Put the manifests into depotcache ourselves and Steam never has to
    # ask. A copy is kept in a vault so an uninstall cannot take them.
    #
    # Snapshot whether we ALREADY hold every pinned manifest locally, before we
    # place anything, so the gate below can tell a fresh setup from a done one.
    # A manifest counts as held if it is in depotcache OR in our vault: Steam
    # prunes depotcache between runs, but the vault is our permanent copy that we
    # re-seed every run, so a vault hit means the lock was set up on a previous run
    # (not a fresh install that needs the "let Steam update" nudge).
    $depotcacheDir = Join-Path $steamPath "depotcache"
    $vaultDir = Join-Path $env:LOCALAPPDATA "LuaTools\manifest-vault\$AppID"
    $manifestsWereAllPresent = $true
    foreach ($depot in $wantedPins.Keys) {
        $name = "$depot`_$($wantedPins[$depot]).manifest"
        $inCache = Test-Path -LiteralPath (Join-Path $depotcacheDir $name)
        $inVault = Test-Path -LiteralPath (Join-Path $vaultDir $name)
        if (-not $inCache -and -not $inVault) { $manifestsWereAllPresent = $false; break }
    }

    $manifestsReady = Ensure-LtLockedManifests -AppID $AppID -Lua $desiredLua -SteamRoot $steamPath
    if (-not $manifestsReady) {
        Write-Host "    [!] Some of the locked build's manifests are missing, so the download may not start." -ForegroundColor Yellow
    }

    # A game in a second library (D:\SteamLibrary next to C:\...\Steam) never
    # showed the downgrade with the manifests only in the Steam folder's
    # depotcache. Steam keeps a depotcache inside each library too, so the
    # game's own library gets a copy as well.
    if ($gameLibrary -and $gameInstalled) {
        $libKey = $gameLibrary.TrimEnd('\', '/').ToLowerInvariant()
        $rootKey = $steamPath.Replace('/', '\').TrimEnd('\', '/').ToLowerInvariant()
        if ($libKey -ne $rootKey) {
            $libCache = Join-Path $gameLibrary "steamapps\depotcache"
            if (-not (Test-Path -LiteralPath $libCache)) {
                try { New-Item -ItemType Directory -Path $libCache -Force | Out-Null } catch {}
            }
            $libPlaced = 0
            foreach ($depot in $wantedPins.Keys) {
                $name = "$depot`_$($wantedPins[$depot]).manifest"
                $src = Join-Path $depotcacheDir $name
                if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $vaultDir $name }
                $dst = Join-Path $libCache $name
                if ((Test-Path -LiteralPath $dst) -or -not (Test-Path -LiteralPath $src)) { continue }
                if (Copy-LtManifest -From $src -To $dst) { $libPlaced++ }
            }
            if ($libPlaced -gt 0) {
                Write-Host "    [+] Placed $libPlaced manifest(s) in the game's library: $libCache" -ForegroundColor Green
                $manifestsWereAllPresent = $false
            }
        }
    }

    # Is the version lock already fully in place? We gate on the lock FILES, not
    # the appmanifest buildid: Steam keeps the old buildid in the acf even after the
    # lua pin is applied, so buildid is unreliable. The real question is whether the
    # correct lua is in stplug-in AND every pinned manifest is in depotcache. If both
    # were already true on entry, the lock is set and we skip to the report. If we
    # had to place anything just now, Steam will show the resulting update; the user
    # runs it and re-validates.
    #
    # The lock files alone are not proof though. When the downgrade glitches Steam
    # shows no update at all, and the game sat on the new build while this let it
    # through. InstalledDepots has the manifest each depot is really installed at,
    # so a locked depot at any other gid has not downgraded yet. Depots that are not
    # installed (an unused language, say) are skipped.
    $acfPath = if ($gameLibrary) { [System.IO.Path]::Combine($gameLibrary, "steamapps\appmanifest_$AppID.acf") } else { $null }
    $installedNow = if ($acfPath) { Get-LtInstalledDepots -AcfPath $acfPath } else { @{} }
    $offBuild = @($wantedPins.Keys | Where-Object { $installedNow.ContainsKey($_) -and $installedNow[$_].manifest -ne $wantedPins[$_] })

    $cacheDirs = @($depotcacheDir)
    if ($gameLibrary) { $cacheDirs += (Join-Path $gameLibrary "steamapps\depotcache") }

    # Forced checks are counted so a game whose acf never catches up can't trap
    # anyone in a loop. After two it goes on to the report like it used to.
    $triesFile = Join-Path $vaultDir "validate_tries.txt"
    $tries = 0
    if (Test-Path -LiteralPath $triesFile) {
        [int]::TryParse(([string](Get-Content -LiteralPath $triesFile -Raw)).Trim(), [ref]$tries) | Out-Null
    }

    $lockSet = $luaWasCorrect -and $manifestsWereAllPresent
    if ($lockSet -and $offBuild.Count -eq 0) {
        if (Test-Path -LiteralPath $triesFile) { Remove-Item -LiteralPath $triesFile -Force -ErrorAction SilentlyContinue }
        Write-Host "    [+] Version lock already set (lua + manifests in place). Continuing to the report." -ForegroundColor Green
    }
    elseif ($lockSet -and $tries -ge 2) {
        # Two file checks didn't move it. Last resort is Lark's Steam reset, offered
        # once per game and only with the user's OK. Afterwards the counter drops back
        # to 1 so the next run (with the engine reinstalled) gets one more file check.
        $resetFile = Join-Path $vaultDir "steam_reset.txt"
        if (-not (Test-Path -LiteralPath $resetFile)) {
            Write-Host ""
            Write-Host "    [!] Steam still won't move $($vl.GameName) to the locked build after two file checks." -ForegroundColor Yellow
            Write-Host "        Resetting Steam usually fixes this. Steam closes and everything in its folder" -ForegroundColor Yellow
            Write-Host "        is deleted except appcache, config, steam, steamapps, userdata and steam.exe," -ForegroundColor Yellow
            Write-Host "        then Steam downloads a clean copy of itself. Installed games are kept." -ForegroundColor Yellow
            Write-Host "        You will need to install the engine again afterwards." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    Press Y to reset Steam now, or any other key to skip." -ForegroundColor Cyan
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ("$($key.Character)" -eq "y") {
                try { Set-Content -LiteralPath $resetFile -Value (Get-Date -Format s) -ErrorAction Stop } catch { }
                try { Set-Content -LiteralPath $triesFile -Value 1 -ErrorAction Stop } catch { }
                $null = Invoke-LtSteamReset -SteamRoot $steamPath -VaultDir $vaultDir
                Show-LuaError -Title "Steam was reset, reinstall the engine then validate again" -Message @"
Steam's program files were deleted and Steam is now downloading a clean copy of itself. Your installed games were not touched.

Do this now:
  1. Let Steam finish updating and sign in if it asks.
  2. Install the engine again: open the TokeerDRM app and let it install OpenSteamTool,
     or open the LuaTools app, go to Mode, and choose BetterSteamTools.
  3. Run this validation again. It will start the file check that moves the game to the right build.
"@
                Write-Host "`nPress any key to exit..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                exit
            }
        }
        Write-Host "    [!] Steam still lists $($offBuild.Count) locked depot(s) on another build. Continuing to the report anyway." -ForegroundColor Yellow
    }
    elseif ($gameInstalled) {
        if ($lockSet) {
            Write-Host "    [!] The lock is set but $($offBuild.Count) depot(s) never downgraded. Forcing a file check..." -ForegroundColor Yellow
        }
        try { Set-Content -LiteralPath $triesFile -Value ($tries + 1) -ErrorAction Stop } catch { }
        $started = Invoke-LtLockedValidate -AppID $AppID -SteamRoot $steamPath -CacheDirs $cacheDirs -Pins $wantedPins
        $how = if ($started) {
            "Steam is now verifying the game files. That check is what moves it to the right build."
        } else {
            "Start the check yourself: right-click the game in Steam, Properties, Installed Files, Verify integrity of game files."
        }
        Show-LuaError -Title "Let Steam finish, then validate again" -Message @"
$($vl.GameName) only works on build $($vl.BuildId). Its newest Steam update breaks the activation, so we locked the supported version on your PC with a version-locked lua.

$how

Do this now:
  1. Leave Steam open and let it finish the check, plus any download it starts.
  2. Wait until Steam lists the game as fully installed (not Queued, Downloading, or Updating).
  3. Run this validation again.

Your game files are not deleted and this is not a reinstall, so it only downloads
the parts that actually differ between the two builds.

If Steam never starts the check, close it fully, open it again, then right-click
the game, Properties, Installed Files, Verify integrity of game files.
"@
        Write-Host "`nPress any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
    else {
        Show-LuaError -Title "Update this game, then validate again" -Message @"
$($vl.GameName) only works on build $($vl.BuildId). Its newest Steam update breaks the activation, so we locked the supported version on your PC with a version-locked lua.

The update is really a downgrade. The lock points Steam back at the build that works, so letting it "update" is what puts you on the right version.

Do this now:
  1. Open your Steam library. This game now shows an Update. Start it and let it finish.
  2. Wait until Steam lists it as fully installed (not Queued, Downloading, or Updating).
  3. Run this validation again.

Your game files are not deleted and this is not a reinstall, so it only downloads
the parts that actually differ between the two builds.

If no Update appears, close Steam completely, open it again, and look once more.

The manifests for that build are already on your PC, so the download has everything
it needs. They are kept even if you uninstall the game, so a reinstall still works.
"@
        Write-Host "`nPress any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
}
else {
    # stplug-in lua handling: re-comment any active setManifestid so the game
    # tracks the latest manifest, which also repairs a stale pin from an older
    # build. Steam no longer gives manifest request codes to non-owning accounts,
    # so a pinned game cannot update itself anyway; there is nothing to lock,
    # which is why the old disable-updates path was dropped.
    Write-Host "`n[*] Checking stplug-in lua (tracks latest manifest)..." -ForegroundColor Cyan

    $luaDirs = Get-LuaDirs
    $reportData.LuaDirs = $luaDirs

    if ($luaDirs.Count -gt 0) {
        $luaFiles = @()
        foreach ($dir in $luaDirs) {
            Write-Host "    [+] Checking lua folder: $dir" -ForegroundColor Green
            $targetLuaFile = Join-Path $dir "$AppID.lua"
            if (Test-Path -LiteralPath $targetLuaFile) {
                $luaFiles += Get-Item -LiteralPath $targetLuaFile
            }
            else {
                $luaFiles += @(Get-ChildItem -LiteralPath $dir -Filter "*.lua" -ErrorAction SilentlyContinue | Where-Object {
                    $_.Name -ne "Steamtools.lua" -and (Get-Content -LiteralPath $_.FullName -Raw) -match "addappid\(\s*$AppID\b"
                })
            }
        }
    }
    else {
        Write-Host "    [-] Steam stplug-in directory not found within Steam installation." -ForegroundColor Red
        $luaFiles = @()
    }

    # Games in disable_updates.txt keep whatever build is installed: every
    # installed depot is pinned to its current manifest, so Steam has nothing to
    # update to. Never a downgrade. Taking a game off the list un-pins it on its
    # next validation like any other game.
    $disableUpdatesGames = Get-LtDisableUpdatesList
    $pinsUntouched = $null -eq $disableUpdatesGames
    if ($pinsUntouched) {
        Write-Host "    [!] Couldn't load the update lock list, leaving manifest pins as they are." -ForegroundColor Yellow
        $disableUpdatesGames = @()
    }
    $pinAcf = $null
    if ($disableUpdatesGames -contains $AppID -and $gameLibrary) {
        $pinAcf = [System.IO.Path]::Combine($gameLibrary, "steamapps\appmanifest_$AppID.acf")
        if (-not (Test-Path -LiteralPath $pinAcf)) { $pinAcf = $null }
    }

    foreach ($luaFile in $luaFiles) {
        $reportData.LuaFileFound = $true
        if ($pinsUntouched) { continue }

        if ($disableUpdatesGames -contains $AppID) {
            if (-not $pinAcf) {
                Write-Host "    [-] $($luaFile.Name): couldn't find the appmanifest to read the installed build, updates not disabled." -ForegroundColor Yellow
                continue
            }
            try { Copy-Item -LiteralPath $luaFile.FullName -Destination ($luaFile.FullName + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
            $pinCount = Set-LtVersionPin -LuaPath $luaFile.FullName -AcfPath $pinAcf
            $reportData.UpdatesDisabled = ($pinCount -gt 0)
            if ($pinCount -gt 0) {
                Write-Host "    [+] $($luaFile.Name): locked $pinCount depot(s) to the installed build, Steam updates disabled." -ForegroundColor Green
            }
            else {
                Write-Host "    [*] $($luaFile.Name): nothing to pin (no installed depots found), left as is." -ForegroundColor DarkGray
            }
            continue
        }

        # Re-comment any active setManifestid so the game tracks the latest
        # manifest. Also repairs a stale pin left by an older build.
        $luaRaw = Get-Content -LiteralPath $luaFile.FullName -Raw
        $activeCount = ([regex]::Matches($luaRaw, "(?m)^\s*setManifestid\(")).Count
        if ($activeCount -gt 0) {
            try { Copy-Item -LiteralPath $luaFile.FullName -Destination ($luaFile.FullName + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
            $unpinned = [regex]::Replace($luaRaw, "(?m)^(\s*)(setManifestid\()", '$1--$2')
            [System.IO.File]::WriteAllText($luaFile.FullName, $unpinned, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "    [+] $($luaFile.Name): removed $activeCount manifest pin(s) - game tracks the latest manifest." -ForegroundColor Green
        }
        else {
            Write-Host "    [*] $($luaFile.Name): no manifest pins (latest manifest)." -ForegroundColor DarkGray
        }
    }

    if ($luaFiles.Count -eq 0) {
        Write-Host "    [-] No .lua file found for AppID $AppID in stplug-in." -ForegroundColor Yellow
    }
}

# 7. System info collection

# Rank an adapter by what it IS, not by how much memory it claims. A laptop with
# an Intel iGPU next to a real card lists both, and the iGPU often reports the
# bigger number because shared system memory is not VRAM. Memory only breaks ties.
function Get-GpuClassRank {
    param([string]$Name)

    $n = ($Name -replace '\s+', ' ').Trim()
    if ($n -match 'GeForce|Quadro|TITAN|Tesla|\bRTX\b|\bGTX\b|FirePro|Radeon (RX|R[579]|HD \d|Pro [WV]|VII)|Radeon RX|\bArc\b.*\b[AB]\d{3}') { return 3 }
    if ($n -match 'Intel.*(UHD|HD|Iris)|Radeon\(TM\) Graphics|Radeon Graphics|Vega \d{1,2} Graphics|Radeon \d{3}M\b|Graphics Media Accelerator') { return 1 }
    return 2
}

# Both memory keys can be a REG_BINARY blob or a plain number depending on the
# driver, and MemorySize is only 32 bits wide.
function Get-AdapterMemoryBytes {
    param($Props)

    foreach ($key in @('HardwareInformation.qwMemorySize', 'HardwareInformation.MemorySize')) {
        $raw = $Props.$key
        if ($null -eq $raw) { continue }

        $value = 0L
        if ($raw -is [byte[]]) {
            if ($raw.Length -ge 8) { $value = [BitConverter]::ToInt64($raw, 0) }
            elseif ($raw.Length -ge 4) { $value = [int64][BitConverter]::ToUInt32($raw, 0) }
        }
        else {
            try { $value = [int64][uint64]$raw } catch { $value = 0L }
        }

        if ($value -gt 0) { return $value }
    }

    return 0L
}

function Get-PrimaryGpuInfo {
    $adapters = @{}

    try {
        Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and ($_.Name -notmatch 'Microsoft Basic|Remote Display|Parsec|Virtual|VMware|Hyper-V|Citrix|DameWare') } |
            ForEach-Object {
                $name = $_.Name.Trim()
                # AdapterRAM is a uint32. Anything at the 4 GB ceiling has wrapped:
                # an 8 GB card and a 4 GB card both land on 4294967295, which is
                # where the bogus VRAM numbers came from. Treat those as unknown.
                $bytes = 0L
                if ($_.AdapterRAM -gt 0 -and $_.AdapterRAM -lt 4293918720) { $bytes = [int64]$_.AdapterRAM }
                $adapters[$name.ToLower()] = [pscustomobject]@{ Name = $name; MemoryBytes = $bytes }
            }
    }
    catch {}

    try {
        $displayClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        Get-ChildItem -LiteralPath $displayClass -ErrorAction Stop |
            Where-Object { $_.PSChildName -match '^\d{4}$' } |
            ForEach-Object {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return }

                $name = $props.DriverDesc
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $props.'HardwareInformation.AdapterString' }
                if ([string]::IsNullOrWhiteSpace($name)) { return }

                $name = $name.Trim()
                $key = $name.ToLower()
                $bytes = Get-AdapterMemoryBytes -Props $props

                if ($adapters.ContainsKey($key)) {
                    # The registry figure is the 64-bit one, so it beats WMI's.
                    if ($bytes -gt 0) { $adapters[$key].MemoryBytes = $bytes }
                }
                else {
                    $adapters[$key] = [pscustomobject]@{ Name = $name; MemoryBytes = $bytes }
                }
            }
    }
    catch {}

    $ranked = @($adapters.Values |
        ForEach-Object {
            $rank = Get-GpuClassRank -Name $_.Name
            [pscustomobject]@{
                Name        = $_.Name
                MemoryBytes = $_.MemoryBytes
                Rank        = $rank
                Integrated  = ($rank -eq 1)
            }
        } |
        Sort-Object @{Expression = 'Rank'; Descending = $true}, @{Expression = 'MemoryBytes'; Descending = $true})

    if ($ranked.Count -eq 0) {
        return [pscustomobject]@{ Name = "Unknown"; VramGB = 0; Integrated = $false; All = @() }
    }

    $best = $ranked[0]
    $all = @($ranked | ForEach-Object {
        [pscustomobject]@{
            name       = $_.Name
            vram_gb    = [math]::Round($_.MemoryBytes / 1GB, 1)
            integrated = $_.Integrated
        }
    })

    return [pscustomobject]@{
        Name       = $best.Name
        VramGB     = [math]::Round($best.MemoryBytes / 1GB, 1)
        Integrated = $best.Integrated
        All        = $all
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
$gpuIntegrated = $false
$gpuAll = @()
try {
    $gpuInfo = Get-PrimaryGpuInfo
    $gpuName = $gpuInfo.Name
    $gpuVram = $gpuInfo.VramGB
    $gpuIntegrated = [bool]$gpuInfo.Integrated
    $gpuAll = @($gpuInfo.All)
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
    # Sorted, because the unordered "first" disk changes between runs on a
    # multi-drive PC and the same machine then looks like a different one.
    $diskSerial = (Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop |
        Sort-Object DeviceID | Select-Object -First 1).SerialNumber
    if ($diskSerial) { $diskSerial = $diskSerial.Trim() }
}
catch {}
# MachineGuid belongs to the Windows installation, so a cloned or imaged system
# carries it onto different hardware and two unrelated people end up sharing it.
# These two come from the board itself and survive a reinstall.
$boardUuid = $null
try {
    $boardUuid = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop |
        Select-Object -First 1).UUID
    if ($boardUuid) { $boardUuid = $boardUuid.Trim() }
}
catch {}
$baseboardSerial = $null
try {
    $baseboardSerial = (Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop |
        Select-Object -First 1).SerialNumber
    if ($baseboardSerial) { $baseboardSerial = $baseboardSerial.Trim() }
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
$hwComponents = [ordered]@{
    machine_guid = $machineGuid
    board_uuid   = $boardUuid
    baseboard    = $baseboardSerial
    disk_serial  = $diskSerial
}


# Ticket auto-submit. A Tokeer ticket's command leaves ticket.json behind. When it
# matches this AppID, the D-Report goes straight to the ticket and the bot's answer
# shows here, so nobody has to paste the code. LuaTools Validator fills its code box
# from the last "D-Report Code: X" line, which is how VALIDATED ends up in it.
function Send-ReportToTicket {
    param([string]$Code)
    $ticketFile = Join-Path $env:LOCALAPPDATA "LuaToolsValidator\ticket.json"
    if (-not $Code -or -not (Test-Path -LiteralPath $ticketFile)) { return }
    try {
        $t = Get-Content -LiteralPath $ticketFile -Raw | ConvertFrom-Json
        $token = "$($t.ticket)".ToLower()
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$t.created
    }
    catch { return }
    if ($token -notmatch '^[a-z0-9]{20,40}$' -or "$($t.appid)" -ne "$AppID" -or $age -gt 7200 -or $age -lt -300) { return }

    Write-Host "`n[*] Sending your report to your ticket..." -ForegroundColor Cyan
    try {
        $claimBody = [System.Text.Encoding]::UTF8.GetBytes((@{ ticket = $token; code = $Code } | ConvertTo-Json -Compress))
        $null = Invoke-RestMethod -Uri "https://luastools.xyz/report/claim" -Method Post -Body $claimBody -ContentType "application/json" -TimeoutSec 20
    }
    catch {
        Write-Host "    [-] Couldn't send it to your ticket automatically. Paste the code above in your ticket." -ForegroundColor Yellow
        return
    }

    Write-Host "    [+] Sent. Waiting for your ticket to check it..." -ForegroundColor Green
    $verdict = $null
    $deadline = (Get-Date).AddMinutes(3)
    $lastNote = Get-Date
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        try {
            $v = Invoke-RestMethod -Uri "https://luastools.xyz/report/verdict/$token" -TimeoutSec 10 -Headers @{ "Cache-Control" = "no-cache" }
            if (@("ok", "fail", "closed") -contains $v.state -and "$($v.code)" -eq $Code) { $verdict = $v; break }
        }
        catch {}
        if (((Get-Date) - $lastNote).TotalSeconds -ge 10) {
            Write-Host "    [*] Still waiting for your ticket..." -ForegroundColor DarkGray
            $lastNote = Get-Date
        }
    }

    if (-not $verdict) {
        Write-Host "    [*] No answer yet. Check your ticket in Discord, and if nothing happened there, paste the code above." -ForegroundColor Yellow
        return
    }
    if ($verdict.state -eq "ok") {
        Write-Host ""
        Write-Host "    ============================================" -ForegroundColor Green
        Write-Host "    ||   D-Report Code: VALIDATED" -ForegroundColor Green
        Write-Host "    ============================================" -ForegroundColor Green
        $okText = "Go back to Discord, your ticket is continuing on its own."
        if ($verdict.message -and "$($verdict.message)" -ne "Validated") { $okText = "$($verdict.message)" }
        Write-Host "    Validated! $okText" -ForegroundColor Green
        Remove-Item -LiteralPath $ticketFile -Force -ErrorAction SilentlyContinue
        return
    }
    if ($verdict.state -eq "closed") {
        Write-Host "    [-] $($verdict.message)" -ForegroundColor Yellow
        Remove-Item -LiteralPath $ticketFile -Force -ErrorAction SilentlyContinue
        return
    }
    Write-Host ""
    Write-Host "    [-] Your ticket couldn't validate this report:" -ForegroundColor Red
    foreach ($e in @($verdict.errors)) {
        if ($e) { Write-Host "        - $e" -ForegroundColor Yellow }
    }
    if ($verdict.message) { Write-Host "    $($verdict.message)" -ForegroundColor Yellow }
    Write-Host "    D-Report Code: NOT-VALIDATED" -ForegroundColor Red
}


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
    lua_dirs                = $reportData.LuaDirs
    updates_disabled        = $reportData.UpdatesDisabled
    windows_update_blocked  = $reportData.WindowsUpdateBlocked
    windows_update_services = $wuDetails
    ost_active              = $reportData.OstActive
    ost_engine              = $reportData.OstEngine
    ost_toml_ok             = $reportData.OstTomlOk
    hwid                    = $hwid
    hw_components           = $hwComponents
    mac_addresses           = $macAddresses
    public_ip               = $publicIp
    cpu                     = $cpuName
    gpu                     = $gpuName
    gpu_vram_gb             = $gpuVram
    gpu_integrated          = $gpuIntegrated
    gpu_all                 = $gpuAll
    ram_gb                  = $ramGB
    os                      = $osName
    disk_free_gb            = $diskFreeGB
} | ConvertTo-Json -Depth 4

try {
    $headers = @{ "Accept" = "application/json" }

    # UTF8.GetBytes gives clean UTF-8 with no BOM, so the store parses it directly.
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonReport)
    $response = Invoke-RestMethod -Uri "https://luastools.xyz/report/upload" -Method Post -Headers $headers -Body $bodyBytes -ContentType "application/json"

    if ($response.code) {
        $pasteCode = $response.code

        Set-Clipboard -Value $pasteCode
        Write-Host "`n    [+] Report uploaded successfully!" -ForegroundColor Green

        # For games that need launch options written, defer the D-Report code display
        # until AFTER Steam restart - prevents users from closing the script early
        # and skipping the launch options write. (When OST is active we don't write
        # launch options at all, so there's nothing to defer for.)
        $deferCodeDisplay = $writeLaunchOptions

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
            Send-ReportToTicket -Code $pasteCode
        }
        else {
            Write-Host "    [*] D-Report Code will be shown after Steam restart + launch options setup." -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "    [-] Upload succeeded but no code returned." -ForegroundColor Yellow
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

function Test-MillenniumInstalled {
    param([string]$SteamPath)
    # Millennium (SteamClientHomebrew) loads into Steam via a wsock32.dll proxy +
    # millennium.dll + python311.dll, with its plugins under Steam\ext. It hosts
    # the LuaTools Steam plugin for many users, so it's commonly present.
    if (-not $SteamPath) { return $false }
    if (Test-Path (Join-Path $SteamPath "millennium.dll")) { return $true }
    if (Test-Path (Join-Path $SteamPath "ext\data")) { return $true }
    return $false
}

function Start-SteamAndWait {
    param([string]$SteamPath, [int]$Retries = 3)
    # Start Steam and CONFIRM it stays up. When Millennium is out of date for the
    # current Steam build it crashes Steam on launch (faulting module
    # python311.dll, 0xc0000409) — the files are placed fine but the game never
    # opens because there's no Steam to launch it. The crash is intermittent, and
    # relaunching also lets Millennium's pending update apply, so we retry; if it
    # keeps dying we tell the user the real cause (update Millennium).
    if (-not $SteamPath) {
        Write-Host "[-] Steam path unknown — cannot start Steam." -ForegroundColor Red
        return $false
    }
    $steamExe = Join-Path $SteamPath "steam.exe"
    if (-not (Test-Path $steamExe)) {
        Write-Host "[-] Could not find Steam executable to start." -ForegroundColor Red
        return $false
    }
    if (Get-Process -Name "steam" -ErrorAction SilentlyContinue) { return $true }  # already up

    $hasMillennium = Test-MillenniumInstalled -SteamPath $SteamPath
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        Write-Host "`n[*] Starting Steam (attempt $attempt of $Retries)..." -ForegroundColor Cyan
        Start-Process -FilePath $steamExe
        Start-Sleep -Seconds 5  # let it spawn before we watch for an early crash
        $crashed = $false
        $watchUntil = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $watchUntil) {
            if (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) { $crashed = $true; break }
            Start-Sleep -Seconds 3
        }
        if (-not $crashed -and (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
            Write-Host "    [+] Steam is up and running." -ForegroundColor Green
            return $true
        }
        Write-Host "    [!] Steam closed right after starting (crash on launch)." -ForegroundColor Yellow
        if ($hasMillennium) {
            Write-Host "        Millennium is installed — when it's out of date for the current Steam" -ForegroundColor Yellow
            Write-Host "        build it crashes Steam on launch (python311.dll). Retrying so its" -ForegroundColor Yellow
            Write-Host "        pending update can apply..." -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds 2
    }

    if ($hasMillennium) {
        Show-LuaError -Title "Steam keeps closing on launch (update Millennium)" -Message @"
Your game files are placed correctly, but Steam closes right after it opens, so the
game can't launch. This is Millennium crashing Steam — it's out of date for your
current Steam version. It is NOT the activation.

Fix it once:
1. Reopen Steam a few times so Millennium's pending update can finish applying, OR
   open Millennium's settings in Steam and update it to the latest version.
2. Once Steam opens and STAYS open, launch the game normally — no re-activation needed.
"@
    }
    else {
        Write-Host "[-] Steam did not stay open after several tries. Open Steam manually, then launch the game." -ForegroundColor Red
    }
    return $false
}

# 8. Restart Steam
if ($writeLaunchOptions) {
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
# GATED on -not $ostActive: CloudRedirect patches the *SteamTools* payload and
# drops cloud_redirect.dll — that's meaningless under OpenSteamTool and can drag
# SteamTools back in (the exact engine conflict that causes Denuvo code 00). With
# OST active the engine serves the manifest/ticket itself, so skip it entirely.
if ($steamPath -and -not $ostActive) {
    Invoke-CloudRedirectStFixer -SteamPath $steamPath | Out-Null
}
elseif ($ostActive) {
    Write-Host "`n[*] OpenSteamTool is active — skipping the SteamTools CloudRedirect patch." -ForegroundColor DarkGray
}

# --- Set custom launch options (Steam must be closed for this to persist) ---
# NOTE: gated on -not $ostActive. With OpenSteamTool active the game launches
# normally (OST serves the registry/Denuvo ticket) — the tokeer_launcher.exe wrapper
# must NOT be set, and any previously-written launch options are cleared below.
if ($writeLaunchOptions -and $installDir -and $steamPath) {
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
    # Restart Steam and verify it stays up — a Millennium-out-of-date crash here
    # is exactly why a correctly-placed game "doesn't open" with no error.
    Start-SteamAndWait -SteamPath $steamPath | Out-Null
}
elseif ($isUnreleased) {
    Write-Host "`n[*] Skipping Steam launch options/restart for unreleased game AppID $AppID." -ForegroundColor DarkGray
    Write-Host "[*] Checking for old Steam LaunchOptions written by older validators..." -ForegroundColor Cyan
    Remove-SteamLaunchOptionsForApp -SteamPath $steamPath -TargetAppID $AppID
}
elseif ($ostActive -and -not $isForceGbe -and $steamPath) {
    # OpenSteamTool/registry method: the game launches normally, no tokeer_launcher
    # wrapper. Strip any custom launch options a previous (legacy) activation left so
    # Steam runs the real game exe and OST serves the ticket. (Skipped for force-GBE
    # games - those KEEP their tokeer_launcher even when OST is active.)
    #
    # Close Steam FIRST. Clearing launch options edits localconfig.vdf, and Steam
    # rewrites that file from memory on exit - so a clear applied while Steam is
    # running gets silently reverted. Closing it also guarantees the restart below
    # (Steam ends up down, so the final block starts it) so the game reloads cleanly
    # and OST re-serves the ticket - the restart users expect even when nothing was
    # actually cleared.
    Write-Host "`n[*] OpenSteamTool is active - closing Steam to clear any custom launch options for AppID $AppID..." -ForegroundColor Cyan
    foreach ($procName in @("steam", "steamwebhelper")) {
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
    }
    $steamDeadline = (Get-Date).AddSeconds(20)
    while ((Get-Process -Name "steam" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $steamDeadline) {
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 1  # grace so the OS releases the VDF handle before we edit it
    Remove-SteamLaunchOptionsForApp -SteamPath $steamPath -TargetAppID $AppID
}

# Steam may have been closed above - by the CloudRedirect STFixer (payload patch),
# the launch-options write block, or the OST clear branch. Whoever closed it, bring
# it back here if it's down so the patched payload/cleared config loads and the user
# can launch normally. (Games that never closed Steam just skip this.)
if ($steamPath -and -not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
    Write-Host "`n[*] Restarting Steam to load the patched payload..." -ForegroundColor Cyan
    Start-SteamAndWait -SteamPath $steamPath | Out-Null
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
    Send-ReportToTicket -Code $pasteCode
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
