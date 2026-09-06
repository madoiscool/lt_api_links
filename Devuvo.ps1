# Devuvo validation script - updated 2026-04-16
if (-not $AppID -or [string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter Steam AppID"
}

# $LockVersion is set by the validator wrapper from the "Disable Steam updates for
# this game" checkbox. When ABSENT (older validator app, or a direct run) it stays
# $false, and section 6 keeps its current un-pin behavior — so nothing changes for
# anyone until they're on a validator build that actually passes the flag.
if (-not (Test-Path variable:LockVersion)) { $LockVersion = $false }

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
    # InstalledDepots) EXACTLY as written. Returns the active-pin count.
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
    "3405690" = @{
        GameName      = "EA SPORTS FC 26"
        BuildId       = "23481646"
        CheckDepot    = "3405691"
        CheckManifest = "7181972322428689225"
        Lua           = @'
-- Generated with Luie @ https://lua.tools/
-- 3405690 - EA SPORTS FC™ 26
-- Version-locked to Build 23481646 (EA SPORTS FC 26 version 1.6.1 · EA SPORTS FC™ 26 update for 3 June 2026) — released 2026-06-03 10:37:08 UTC
-- Generated 2026-08-28 22:28:47 UTC
-- # Depots (Total/DLC/Shared): 25/0/3

-- Main AppID
addappid(3405690, 1, "d72f742e665d75526611fdff936f05ab1703820ecf6f6c5764f3173e5b6a401d")

-- Main Depots
addappid(3405691, 1, "12a93ecb44c6b853d762578ffef21df60aa702f723232d87f81f485f7e636684")
setManifestid(3405691, "7181972322428689225")
addappid(3405692, 1, "c6ec306084ddbc34166f66738b51806ae01d351b007df9dbfb5a17531575b5b7") -- English
setManifestid(3405692, "1210142944114678350")
addappid(3405693, 1, "684e872bb91267d94cb6b604f3851b322d7f3097347d27a21ba119c822c80ac1") -- German
setManifestid(3405693, "2287603649351581118")
addappid(3405694, 1, "807a1450e4e3200b6fa0ee63b41651b467484775b8b7cd64e1fdd3f32e2ff466") -- French
setManifestid(3405694, "7810141761506810098")
addappid(3405695, 1, "9d8e39a63134b325186f44ee79df6023adbd4585f926ac27d99fd20d2b4689b1") -- Italian
setManifestid(3405695, "269481456474010913")
addappid(3405696, 1, "b48a48cfacf2e2e24f564c56bea0624d00744fb79f94bc6470e039dbf783b0fb") -- Koreana
setManifestid(3405696, "6279493269620506003")
addappid(3405697, 1, "05c30614464586cbdaa5cc6d2420004ed85be6113860ed3092acba46190d3e10") -- Spanish
setManifestid(3405697, "1036038619115972633")
addappid(3405698, 1, "d4c795b81851da1cdb29d739abcde82d3af4972dde9e4cfb47afe6f602132713") -- Schinese
setManifestid(3405698, "8113010345835013469")
addappid(3405699, 1, "4bd67983492c731beceea51679510dc6a8f3b8dd30f42b307b61803d305082a7") -- Tchinese
setManifestid(3405699, "1659589495670539402")
addappid(3405701, 1, "34125f2eddef4bd7192c97bc6e5daa2280c2f8a2bf449efb544c557bf0c64345") -- Russian
setManifestid(3405701, "7160067943769855728")
addappid(3405702, 1, "280968368ef276032b87f704f89e4e72c508265b1941279a0fd917cce852ccbb") -- Japanese
setManifestid(3405702, "2943157506223451017")
addappid(3405703, 1, "b4952b326fd29fbc8305521132204db66bf42da6f2a1762ba749fc0dfb19fd51") -- Portuguese
setManifestid(3405703, "3349058278510975024")
addappid(3405704, 1, "a9646252767ad1e1b4dadb53f0b3e55aa3f47b24194411c4936119bc38292e13") -- Polish
setManifestid(3405704, "943999907167947805")
addappid(3405705, 1, "6beb7e95413777101eb6bcc85a1d4b3cb8944742ac13fd0b763fd767ad45a2bf") -- Danish
setManifestid(3405705, "5081829873390398300")
addappid(3405706, 1, "49e4266b919686a1e009092bebae33ef34e56a40da196671f5caf22f8a0f10fd") -- Dutch
setManifestid(3405706, "6762897695085081325")
addappid(3405707, 1, "474261f80ec08ec0f21ce91b7ce542b3b9a16e0b716191a81d8dc66683b74cdd") -- Norwegian
setManifestid(3405707, "37663111546116624")
addappid(3405708, 1, "5b4b9d2954b602a49dc87189e660332a7b8c81c88fee10b6350dacfd14704572") -- Swedish
setManifestid(3405708, "7114671847292603932")
addappid(3405709, 1, "efcad7fae359a3dbcb0caa0e2a2f21a3f2996e9d90a94b58e40b635a87a85244") -- Czech
setManifestid(3405709, "3286496823827224693")
addappid(3405711, 1, "a47af223a991d72c48d1af1aa4232265ee7c65ad78a651f5bbd8a7b773a2618a") -- Turkish
setManifestid(3405711, "1968201015215878680")
addappid(3405712, 1, "1af2e8bc3d90234bfd55dd6d7273b412568c2cea29e93dbaa1148cb3ea7426fe") -- Arabic
setManifestid(3405712, "6810121664920485560")
addappid(3405713, 1, "9a264107b9f1925d8e91afb72a2d7f8c706ad8db2ac6aab2cdfc64d2c88ee3ab") -- Brazilian
setManifestid(3405713, "5215600813577852918")
addappid(3405714, 1, "3d05b44725b01a4b2777e069e593450f655d45a0768d7b25590a71c70a68c64b") -- Latam
setManifestid(3405714, "7951949866948330485")

-- DLC's (no depot keys required)
addappid(3405710) -- EA SPORTS FC 26 - EA Play Trial Key
addappid(3405720) -- EA SPORTS FC 26 - Press Offer Key
addappid(3405830) -- EA SPORTS FC 26 - Standard Edition Key
addappid(3484390) -- EA SPORTS FC™ 26 Ultimate Edition Pre-Purchase content
addappid(3484440) -- EA SPORTS FC 26 - Ultimate Preorder Edition Key
addappid(3484530) -- EA SPORTS FC 26 - Ultimate Edition Key
addappid(3707320) -- EA SPORTS FC™ 26 - FC Points
addappid(3765110) -- EA SPORTS FC™ 25 Football Ultimate Team™ rewards
addappid(3922840) -- EA SPORTS FC™ 26
addtoken(3922840, "605253596113519784")
addappid(4146820) -- EA SPORTS FC™ 26 TOTY Edition
addappid(4328110) -- EA SPORTS FC™ 26 ICONS Edition
addappid(4488060) -- EA SPORTS FC™ 26 - The World's Game Edition Catch-Up Pack
addappid(4637600) -- EA SPORTS FC™ 26 Football Ultimate Team™ 92+ OVR ICON Player Item
addappid(4637610) -- EA SPORTS FC™ 26 Football Ultimate Team™ rewards
addappid(4637620) -- EA SPORTS FC™ 26 Football Ultimate Team™ rewards

-- Shared Depots (Runtimes / Launchers / ETC)
addappid(228989, 1, "ad69276eb476cf06c40312df7376d63deac0c838b9a2767005be8bb306ffb853") -- (windows)
addappid(3340991, 1, "023daedb070e5af8704dc88ee0af829f5c11923d2e6a42cca11ba5713b9f4491")
addappid(3893181, 1, "7f675c2fe8e758d16f3cf8d3b493956afaee78e96d78cdb668a5edb8ac1580f6")
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

    WindowsUpdateBlocked = $false
    OstActive            = $false
    OstEngine            = "none"
    OstTomlOk            = $false
    UpdatesDisabled      = $false   # manifest pinning removed; always false now
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
    $content = Get-Content $libraryFoldersPath -Raw
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

# 4.9 Check OpenSteamTool (OST) — the engine that serves the registry/Denuvo ticket.
# TokeerDRM codes only apply when OST is active, so we detect it the exact same way
# the OST installer does and report it. (Reported only — the bot decides whether to
# require it, so this stays safe for the legacy GBE flow.)
Write-Host "`n[*] Checking OpenSteamTool (OST) engine..." -ForegroundColor Cyan
$ostCore   = (Test-Path (Join-Path $steamPath "OpenSteamTool.dll")) -or (Test-Path (Join-Path $steamPath "mktl.dll"))
$ostHijack = (Test-Path (Join-Path $steamPath "dwmapi.dll")) -and (Test-Path (Join-Path $steamPath "xinput1_4.dll"))
$ostActive = $ostCore -and $ostHijack
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
elseif ($versionLockedGames.ContainsKey($AppID)) {
    # This game's latest Steam build breaks the activation. Force the known-good
    # build: write our locked lua, then only continue to the D-Report once Steam is
    # actually on that build. A user still on the broken build gets the lock written
    # and is told to let Steam "update" (the pin makes that a downgrade), then
    # re-validate. This deliberately re-introduces pinning for this ONE AppID.
    $vl = $versionLockedGames[$AppID]
    Write-Host "`n[*] $($vl.GameName): enforcing version lock to build $($vl.BuildId) (its latest Steam build breaks activation)..." -ForegroundColor Cyan

    $stpluginDir = Get-ChildItem -Path $steamPath -Directory -Filter "stplug-in" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
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

    if ($currentLua.Trim() -ne $desiredLua.Trim()) {
        if ($currentLua) {
            try { Copy-Item -LiteralPath $lockedLuaPath -Destination ($lockedLuaPath + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
        }
        [System.IO.File]::WriteAllText($lockedLuaPath, $desiredLua, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "    [+] Wrote version-locked lua: $lockedLuaPath" -ForegroundColor Green
    }
    else {
        Write-Host "    [+] Version-locked lua already in place." -ForegroundColor Green
    }
    $reportData.LuaFileFound = $true
    $reportData.UpdatesDisabled = $true

    # Is Steam actually ON the good build yet? Read the installed manifest for the
    # check depot straight from the appmanifest's InstalledDepots block.
    $acfForLock = $null
    foreach ($lib in $libraries) {
        $cand = [System.IO.Path]::Combine($lib, "steamapps\appmanifest_$AppID.acf")
        if (Test-Path -LiteralPath $cand) { $acfForLock = $cand; break }
    }
    $installedManifest = $null
    if ($acfForLock) {
        $lockDepots = Get-LtInstalledDepots -AcfPath $acfForLock
        if ($lockDepots.ContainsKey($vl.CheckDepot)) { $installedManifest = $lockDepots[$vl.CheckDepot].manifest }
    }

    if ($installedManifest -eq $vl.CheckManifest) {
        Write-Host "    [+] Game is on the supported build ($($vl.BuildId)). Continuing to the report." -ForegroundColor Green
    }
    else {
        $installedShown = if ($installedManifest) { $installedManifest } else { "unknown / not reported" }
        Show-LuaError -Title "Downgrade this game, then validate again" -Message @"
$($vl.GameName) only works on build $($vl.BuildId). Its newest Steam update breaks the activation, so the supported version has now been locked on your PC.

Do this now:
  1. Close Steam completely, then open it again.
  2. This game will show an "Update". Start it and let it finish. With the lock in place, that update puts the game back on the supported build.
  3. Wait until Steam lists it as fully installed (not Queued, Downloading, or Updating).
  4. Run this validation again.

Your installed build did not match yet:
  needed depot $($vl.CheckDepot) manifest $($vl.CheckManifest)
  found $installedShown
"@
        Write-Host "`nPress any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
}
else {
    # stplug-in lua handling depends on the validator's "Disable Steam updates"
    # checkbox ($LockVersion):
    #   • ON  -> pin every INSTALLED depot to its CURRENT build (updates disabled),
    #            so a Steam update can't break the activation. Pins only to what's
    #            installed now, so there's no downgrade.
    #   • OFF -> re-comment any active setManifestid so the game tracks the latest
    #            manifest (the long-standing default; also repairs a stale pin).
    # $LockVersion defaults to OFF when the flag isn't passed (older validator app),
    # so behavior is unchanged until a build that sends it. Either way we locate the
    # lua for LuaFileFound.
    $lockMsg = if ($LockVersion) { "locking to the installed build (updates disabled)" } else { "no pinning - tracks latest manifest" }
    Write-Host "`n[*] Checking stplug-in lua ($lockMsg)..." -ForegroundColor Cyan

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

        if ($LockVersion) {
            # LOCK (checkbox on): pin every installed depot to the build that is
            # CURRENTLY installed, so a Steam update can't break the activation.
            # Never a stale GID (no downgrade); shared runtimes left untouched.
            $acfForLock = $null
            foreach ($lib in $libraries) {
                $cand = [System.IO.Path]::Combine($lib, "steamapps\appmanifest_$AppID.acf")
                if (Test-Path -LiteralPath $cand) { $acfForLock = $cand; break }
            }
            try { Copy-Item -LiteralPath $luaFile.FullName -Destination ($luaFile.FullName + ".bak_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force } catch {}
            if ($acfForLock) {
                $pinCount = Set-LtVersionPin -LuaPath $luaFile.FullName -AcfPath $acfForLock
                $reportData.UpdatesDisabled = ($pinCount -gt 0)
                if ($pinCount -gt 0) {
                    Write-Host "    [+] $($luaFile.Name): locked $pinCount depot(s) to the installed build - Steam updates disabled." -ForegroundColor Green
                }
                else {
                    Write-Host "    [*] $($luaFile.Name): nothing to pin (no installed depots resolved); left as-is." -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host "    [-] $($luaFile.Name): couldn't find appmanifest to read the installed build; left as-is." -ForegroundColor Yellow
            }
        }
        else {
            # UN-PIN (default / older validator): re-comment active setManifestid
            # lines so the game tracks the latest manifest.
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
        # and skipping the launch options write. (When OST is active we don't write
        # launch options at all, so there's nothing to defer for.)
        $deferCodeDisplay = $customLaunchers.ContainsKey($AppID) -and -not $isUnreleased -and (-not $ostActive -or $isForceGbe)

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
if ($customLaunchers.ContainsKey($AppID) -and -not $isUnreleased -and (-not $ostActive -or $isForceGbe)) {
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
if ($customLaunchers.ContainsKey($AppID) -and -not $isUnreleased -and (-not $ostActive -or $isForceGbe) -and $installDir -and $steamPath) {
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
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
