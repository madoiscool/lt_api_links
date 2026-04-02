<#
.SYNOPSIS
    Steam Manifest Downloader - Downloads depot manifests for SteamTools

.DESCRIPTION
    Downloads depot manifests when SteamTools servers are unavailable.
    Parses local Lua files and fetches manifests from GitHub mirror or a
    fallback API (Morrenus or ManifestHub) depending on the mode.

.PARAMETER ApiKey
    Your ManifestHub API key (required for github+manifesthub mode).
    Can also be set via $env:MH_API_KEY.

.PARAMETER MorrenusApiKey
    Your Morrenus API key (required for github+morrenus mode).
    Can also be set via $env:MORRENUS_API_KEY.

.PARAMETER AppId
    The Steam App ID to download manifests for.
    Can also be set via $env:APP_ID.

.NOTES
    Mode is controlled by the $env:MANIFEST_MODE environment variable:
      "github"             - GitHub mirror only, no API key needed (default)
      "github+morrenus"    - GitHub first, Morrenus API as fallback
      "github+manifesthub" - GitHub first, ManifestHub API as fallback
#>

param(
    [string]$ApiKey,
    [string]$MorrenusApiKey,
    [string]$AppId
)

# Set console encoding to UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Steam Manifest Downloader (For Steamtools)"

function Write-Header {
    param([string]$Mode = "github")
    Clear-Host
    Write-Host ""
    # Clickable hyperlinks using ANSI escape sequences (works in Windows Terminal)
    $esc = [char]27
    if ($Mode -eq "github+morrenus") {
        $sourceLink = "$esc]8;;https://manifest.morrenus.xyz/$esc\Morrenus$esc]8;;$esc\"
        $sourcePad  = "          "
    } elseif ($Mode -eq "github+manifesthub") {
        $sourceLink = "$esc]8;;https://github.com/SteamAutoCracks/ManifestHub$esc\ManifestHub$esc]8;;$esc\"
        $sourcePad  = "       "
    } else {
        $sourceLink = "$esc]8;;https://github.com/qwe213312/k25FCdfEOoEJ42S6$esc\GitHub Mirror$esc]8;;$esc\"
        $sourcePad  = "    "
    }
    $discordLink = "$esc]8;;https://discord.gg/luatools$esc\discord.gg/luatools$esc]8;;$esc\"
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host "  |        STEAM MANIFEST DOWNLOADER (For Steamtools)              |" -ForegroundColor Cyan
    Write-Host "  |   Downloads Out-Of-Date Manifest Files From $sourceLink$sourcePad|" -ForegroundColor Cyan
    Write-Host "  |                                                                |" -ForegroundColor Cyan
    Write-Host "  |                   by $discordLink                       |" -ForegroundColor DarkCyan
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Label,
        [int]$Width = 40,
        [ConsoleColor]$Color = "Green"
    )

    $percent = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $filled = [math]::Floor(($Current / [math]::Max($Total, 1)) * $Width)
    $empty = $Width - $filled

    $barFilled = "#" * $filled
    $barEmpty = "-" * $empty

    Write-Host ("`r  {0} [{1}" -f $Label, $barFilled) -NoNewline
    Write-Host $barEmpty -NoNewline -ForegroundColor DarkGray
    Write-Host ("] {0}% ({1}/{2})    " -f $percent, $Current, $Total) -NoNewline
}

function Write-Status {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    Write-Host "  [*] $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "  [-] $Message" -ForegroundColor Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Exit-WithPrompt {
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

function Get-SteamPath {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    foreach ($path in $registryPaths) {
        try {
            $steamPath = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).InstallPath
            if ($steamPath -and (Test-Path $steamPath)) {
                return $steamPath
            }
        } catch {}
    }

    return $null
}

function Get-DepotIdsFromLua {
    param([string]$LuaPath)

    $depots = @()
    $content = Get-Content -Path $LuaPath -ErrorAction Stop

    foreach ($line in $content) {
        # Match addappid(depotid, digit, "key") pattern, ignoring comments
        if ($line -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') {
            $depotId = $matches[1]
            $depots += $depotId
        }
    }

    return $depots | Select-Object -Unique
}

function Get-AppInfo {
    param([string]$AppId)

    $url = "https://api.steamcmd.net/v1/info/$AppId"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
        return $response
    } catch {
        return $null
    }
}

function Get-ManifestIdForDepot {
    param(
        [object]$AppInfo,
        [string]$AppId,
        [string]$DepotId
    )

    try {
        $depots = $AppInfo.data.$AppId.depots
        if ($depots.$DepotId -and $depots.$DepotId.manifests -and $depots.$DepotId.manifests.public) {
            return $depots.$DepotId.manifests.public.gid
        }
    } catch {}

    return $null
}

function Try-DownloadUrl {
    param(
        [string]$Url,
        [string]$OutputFile,
        [int]$MaxRetries,
        [string]$Label,
        [int]$RetryDelaySeconds = 3
    )

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            if (Test-Path $OutputFile) {
                Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
            }

            Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 120 -OutFile $OutputFile -ErrorAction Stop

            if (Test-Path $OutputFile) {
                $fileSize = (Get-Item $OutputFile).Length
                if ($fileSize -gt 0) {
                    return @{ Success = $true; Is404 = $false; Size = $fileSize; Attempts = $attempt }
                }
            }

            $lastError = "Empty file received"
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($statusCode -eq 404) {
                if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue }
                return @{ Success = $false; Is404 = $true; Error = "Not found (404)"; Attempts = $attempt }
            }
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $MaxRetries) {
            Write-Host "      Attempt $attempt failed ($Label): $lastError" -ForegroundColor DarkYellow
            Write-Host "      Retrying in ${RetryDelaySeconds}s..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    return @{ Success = $false; Is404 = $false; Error = $lastError; Attempts = $MaxRetries }
}

function Download-Manifest {
    param(
        [string]$DepotId,
        [string]$ManifestId,
        [string]$OutputPath,
        [string]$Mode,
        [string]$ApiKey,
        [int]$RetryDelaySeconds = 3
    )

    $outputFile = Join-Path $OutputPath "${DepotId}_${ManifestId}.manifest"
    $githubUrl = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${DepotId}_${ManifestId}.manifest"

    # Always try GitHub first
    $githubResult = Try-DownloadUrl -Url $githubUrl -OutputFile $outputFile -MaxRetries 2 -Label "GitHub" -RetryDelaySeconds $RetryDelaySeconds

    if ($githubResult.Success) {
        return @{ Success = $true; FilePath = $outputFile; Size = $githubResult.Size; Attempts = $githubResult.Attempts }
    }

    # On GitHub 404 and mode has a secondary API, try it
    if ($githubResult.Is404 -and $Mode -ne "github") {
        if ($Mode -eq "github+morrenus") {
            Write-Host "      Not on GitHub, trying Morrenus..." -ForegroundColor DarkGray
            $secondaryUrl = "https://manifest.morrenus.xyz/api/v1/generate/manifest?depot_id=${DepotId}&manifest_id=${ManifestId}&api_key=${ApiKey}"
            $secondaryLabel = "Morrenus"
        } else {
            Write-Host "      Not on GitHub, trying ManifestHub..." -ForegroundColor DarkGray
            $secondaryUrl = "https://api.manifesthub1.filegear-sg.me/manifest?apikey=${ApiKey}&depotid=${DepotId}&manifestid=${ManifestId}"
            $secondaryLabel = "ManifestHub"
        }

        $secondaryResult = Try-DownloadUrl -Url $secondaryUrl -OutputFile $outputFile -MaxRetries 5 -Label $secondaryLabel -RetryDelaySeconds $RetryDelaySeconds

        if ($secondaryResult.Success) {
            return @{ Success = $true; FilePath = $outputFile; Size = $secondaryResult.Size; Attempts = $secondaryResult.Attempts }
        }

        return @{ Success = $false; Error = $secondaryResult.Error; Attempts = $secondaryResult.Attempts }
    }

    return @{ Success = $false; Error = $githubResult.Error; Attempts = $githubResult.Attempts }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes B"
    }
}

# ===========================================================================
# MAIN SCRIPT
# ===========================================================================

if ($env:MANIFEST_MODE) {
    $resolvedMode = $env:MANIFEST_MODE
} else {
    Clear-Host
    Write-Host ""
    Write-Host "  Select download mode:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    1. Github Mirror    (No Key Required, Try This First!)" -ForegroundColor White
    Write-Host "    2. Morrenus         (Free Key from https://manifest.morrenus.xyz/)" -ForegroundColor White
    Write-Host "    3. ManifestHub      (Free Key from https://manifesthub1.filegear-sg.me/)" -ForegroundColor White
    Write-Host ""
    do {
        $modeChoice = Read-Host "  Enter choice (1-3)"
    } while ($modeChoice -notin @("1","2","3"))
    $resolvedMode = switch ($modeChoice) {
        "1" { "github" }
        "2" { "github+morrenus" }
        "3" { "github+manifesthub" }
    }
}

Write-Header -Mode $resolvedMode

$activeApiKey = $null

if ($resolvedMode -eq "github") {
    Write-Host "  [MODE] GitHub Only - No API key required" -ForegroundColor Yellow
} elseif ($resolvedMode -eq "github+morrenus") {
    Write-Host "  [MODE] GitHub + Morrenus - Morrenus API as fallback" -ForegroundColor Cyan
    $activeApiKey = $MorrenusApiKey
    if (-not $activeApiKey) { $activeApiKey = $env:MORRENUS_API_KEY }
    if (-not $activeApiKey) {
        Write-Host ""
        Write-Host "  How to get your Morrenus API key:" -ForegroundColor DarkGray
        Write-Host "    1. Login at https://manifest.morrenus.xyz/ with your Discord account" -ForegroundColor DarkGray
        Write-Host "    2. Generate your key at https://manifest.morrenus.xyz/api-keys/user" -ForegroundColor DarkGray
        Write-Host "    3. Or get it from LuaTools plugin settings if you set it there" -ForegroundColor DarkGray
        Write-Host ""
        $activeApiKey = Read-Host "  Enter Morrenus API Key"
    }
    if ([string]::IsNullOrWhiteSpace($activeApiKey)) {
        Write-ErrorMsg "Morrenus API Key is required!"
        Exit-WithPrompt
    }
    # Validate key format: smm_ prefix + 96 hex chars = 100 total
    if ($activeApiKey -notmatch '^smm_[0-9a-f]{96}$') {
        Write-ErrorMsg "Invalid Morrenus API key format!"
        Write-Host "  Expected: smm_ followed by 96 hex characters (total 100 chars)" -ForegroundColor DarkGray
        Exit-WithPrompt
    }
    # Validate key against Morrenus API
    Write-Host ""
    Write-Status "Validating Morrenus API key..."
    try {
        $statsResponse = Invoke-RestMethod -Uri "https://manifest.morrenus.xyz/api/v1/user/stats?api_key=$activeApiKey" -Method Get -TimeoutSec 15 -ErrorAction Stop
        if (-not $statsResponse.can_make_requests) {
            Write-ErrorMsg "Your Morrenus key has hit its daily limit ($($statsResponse.daily_usage)/$($statsResponse.daily_limit)). Try again tomorrow."
            Exit-WithPrompt
        }
        Write-Success "Welcome back $($statsResponse.username)! Fetching depots now!"
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        if ($statusCode -eq 401 -or $statusCode -eq 403 -or $statusCode -eq 404) {
            Write-ErrorMsg "API key not found or expired."
        } else {
            # Try to parse the body for the detail message
            try {
                $errBody = $_.ErrorDetails.Message | ConvertFrom-Json
                Write-ErrorMsg $errBody.detail
            } catch {
                Write-ErrorMsg "Failed to validate Morrenus API key: $($_.Exception.Message)"
            }
        }
        Exit-WithPrompt
    }
} elseif ($resolvedMode -eq "github+manifesthub") {
    Write-Host "  [MODE] GitHub + ManifestHub - ManifestHub API as fallback" -ForegroundColor Cyan
    $activeApiKey = $ApiKey
    if (-not $activeApiKey) { $activeApiKey = $env:MH_API_KEY }
    if (-not $activeApiKey) {
        Write-Host "  Get your API key from: " -NoNewline
        Write-Host "https://manifesthub1.filegear-sg.me/" -ForegroundColor Yellow
        Write-Host ""
        $activeApiKey = Read-Host "  Enter ManifestHub API Key"
    }
    if ([string]::IsNullOrWhiteSpace($activeApiKey)) {
        Write-ErrorMsg "ManifestHub API Key is required!"
        Exit-WithPrompt
    }
}

Write-Host ""

while ($true) {

# Get App ID (check param -> env var -> prompt)
if (-not $AppId) {
    $AppId = $env:APP_ID
}
if (-not $AppId) {
    $AppId = Read-Host "  Enter Steam AppID (Not Depot ID or DLC ID)"
}

if ([string]::IsNullOrWhiteSpace($AppId) -or $AppId -notmatch '^\d+$') {
    Write-ErrorMsg "Valid App ID is required!"
    Exit-WithPrompt
}

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor DarkGray
Write-Host ""

# Find Steam installation
Write-Status "Locating Steam installation..."
$steamPath = Get-SteamPath

if (-not $steamPath) {
    Write-ErrorMsg "Could not find Steam installation!"
    exit 1
}

Write-Success "Steam found at: $steamPath"

# Check for Lua file
$luaPath = Join-Path $steamPath "config\stplug-in\$AppId.lua"
Write-Status "Looking for Lua file: $luaPath"

if (-not (Test-Path $luaPath)) {
    Write-Host ""
    Write-ErrorMsg "Lua file not present for AppID $AppId"
    Write-Host "  Expected path: $luaPath" -ForegroundColor DarkGray
    exit 1
}

Write-Success "Lua file found!"
Write-Host ""

# Parse Lua file for depot IDs
Write-Status "Parsing Lua file for depot IDs..."
$depotIds = Get-DepotIdsFromLua -LuaPath $luaPath

if ($depotIds.Count -eq 0) {
    Write-ErrorMsg "No depot IDs found in Lua file!"
    exit 1
}

Write-Success "Found $($depotIds.Count) depot ID(s) in Lua file"
Write-Host ""

# Display found depot IDs
Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host "  | Depot IDs found:                                              |" -ForegroundColor DarkGray
$depotList = ($depotIds -join ", ")
if ($depotList.Length -gt 55) {
    $depotList = $depotList.Substring(0, 52) + "..."
}
$paddedDepotList = $depotList.PadRight(60)
Write-Host "  | $paddedDepotList|" -ForegroundColor White
Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host ""

# Get app info from SteamCMD API
Write-Status "Fetching app info from SteamCMD API..."
$appInfo = Get-AppInfo -AppId $AppId

if (-not $appInfo -or $appInfo.status -ne "success") {
    Write-ErrorMsg "Failed to fetch app info from SteamCMD API!"
    exit 1
}

Write-Success "App info retrieved successfully"
Write-Host ""

# Match depot IDs with manifest IDs
Write-Status "Matching depot IDs with manifest IDs..."
$downloadQueue = @()

foreach ($depotId in $depotIds) {
    $manifestId = Get-ManifestIdForDepot -AppInfo $appInfo -AppId $AppId -DepotId $depotId

    if ($manifestId) {
        $downloadQueue += @{
            DepotId = $depotId
            ManifestId = $manifestId
        }
    }
}

if ($downloadQueue.Count -eq 0) {
    Write-WarningMsg "No matching manifests found for any depot IDs!"
    exit 1
}

Write-Success "Found $($downloadQueue.Count) depot(s) with available manifests"
Write-Host ""

# Prepare output directory
$depotCachePath = Join-Path $steamPath "depotcache"
if (-not (Test-Path $depotCachePath)) {
    New-Item -ItemType Directory -Path $depotCachePath -Force | Out-Null
}

Write-Status "Output directory: $depotCachePath"
Write-Host ""

# ===========================================================================
# DOWNLOAD SECTION
# ===========================================================================

Write-Host "  ================================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  DOWNLOADING MANIFESTS" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$skippedCount = 0
$failedDepots = @()
$totalSize = 0
$startTime = Get-Date

for ($i = 0; $i -lt $downloadQueue.Count; $i++) {
    $item = $downloadQueue[$i]
    $depotId = $item.DepotId
    $manifestId = $item.ManifestId

    # Update overall progress
    Write-Host ""
    Write-ProgressBar -Current ($i) -Total $downloadQueue.Count -Label "Overall Progress" -Color Cyan
    Write-Host ""
    Write-Host ""

    # Check if manifest up-to-date
    $existingFile = Join-Path $depotCachePath "${depotId}_${manifestId}.manifest"
    if (Test-Path $existingFile) {
        $existingSize = (Get-Item $existingFile).Length
        if ($existingSize -gt 0) {
            $skippedCount++
            $sizeStr = Format-FileSize -Bytes $existingSize
            Write-Host "  [=] Depot $depotId - Not Out-Of-Date ($sizeStr), skipping" -ForegroundColor DarkCyan
            continue
        }
    }

    # Show current download info
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    $depotLine = "Downloading: Depot $depotId"
    $manifestLine = "Manifest ID: $manifestId"
    Write-Host ("  | {0,-62}|" -f $depotLine) -ForegroundColor Yellow
    Write-Host ("  | {0,-62}|" -f $manifestLine) -ForegroundColor White
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

    # Download the manifest
    $result = Download-Manifest -DepotId $depotId -ManifestId $manifestId -OutputPath $depotCachePath -Mode $resolvedMode -ApiKey $activeApiKey

    if ($result.Success) {
        $successCount++
        $totalSize += $result.Size
        $sizeStr = Format-FileSize -Bytes $result.Size
        $retryInfo = if ($result.Attempts -gt 1) { " [Attempt $($result.Attempts)]" } else { "" }
        Write-Success "Depot $depotId - Downloaded ($sizeStr)$retryInfo"
    } else {
        $failedDepots += @{
            DepotId = $depotId
            ManifestId = $manifestId
            Error = $result.Error
        }
        Write-ErrorMsg "Depot $depotId - Failed after $($result.Attempts) attempts: $($result.Error)"
    }
}

# Final progress update
Write-Host ""
Write-ProgressBar -Current $downloadQueue.Count -Total $downloadQueue.Count -Label "Overall Progress" -Color Cyan
Write-Host ""

$endTime = Get-Date
$elapsed = $endTime - $startTime

# ===========================================================================
# SUMMARY
# ===========================================================================

Write-Host ""
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  DOWNLOAD COMPLETE" -ForegroundColor Cyan
Write-Host ""
Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host "  |                         SUMMARY                               |" -ForegroundColor DarkGray
Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

$successText = "Downloaded:    $successCount"
Write-Host ("  |  {0,-60}|" -f $successText) -ForegroundColor Green

$skippedText = "Skipped:       $skippedCount (up-to-date)"
Write-Host ("  |  {0,-60}|" -f $skippedText) -ForegroundColor DarkCyan

$failedText = "Failed:        $($failedDepots.Count)"
$failedColor = if ($failedDepots.Count -gt 0) { "Red" } else { "Green" }
Write-Host ("  |  {0,-60}|" -f $failedText) -ForegroundColor $failedColor

$totalText = "Total:         $($downloadQueue.Count) depots"
Write-Host ("  |  {0,-60}|" -f $totalText) -ForegroundColor White

$sizeText = "Downloaded:    $(Format-FileSize -Bytes $totalSize)"
Write-Host ("  |  {0,-60}|" -f $sizeText) -ForegroundColor White

$timeText = "Time Elapsed:  $($elapsed.ToString('mm\:ss'))"
Write-Host ("  |  {0,-60}|" -f $timeText) -ForegroundColor White

$outputText = "Output:        $depotCachePath"
if ($outputText.Length -gt 60) {
    $outputText = $outputText.Substring(0, 57) + "..."
}
Write-Host ("  |  {0,-60}|" -f $outputText) -ForegroundColor White

Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

# Show failed depots if any
if ($failedDepots.Count -gt 0) {
    Write-Host ""
    Write-Host "  FAILED DOWNLOADS:" -ForegroundColor Red
    Write-Host ""
    foreach ($failed in $failedDepots) {
        Write-Host "    Depot $($failed.DepotId) (Manifest: $($failed.ManifestId))" -ForegroundColor Red
        Write-Host "    Error: $($failed.Error)" -ForegroundColor DarkRed
        Write-Host ""
    }
}

Write-Host ""
Write-Host "  What would you like to do next?" -ForegroundColor Cyan
Write-Host ""
Write-Host "    1. Process another AppID" -ForegroundColor White
Write-Host "    2. Done! (close PowerShell)" -ForegroundColor White
Write-Host ""
do {
    $nextChoice = Read-Host "  Enter choice (1-2)"
} while ($nextChoice -notin @("1","2"))

if ($nextChoice -eq "2") { break }

$AppId = $null
Write-Header -Mode $resolvedMode
Write-Host ""

} # end while ($true)

exit 0
