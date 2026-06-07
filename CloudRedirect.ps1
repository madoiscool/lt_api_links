# ==============================
# CloudRedirect Installer
# ==============================
$Host.UI.RawUI.WindowTitle = "CloudRedirect Installer | .gg/luatools"

# ===================== LOGGING =====================
function Log {
    param (
        [string]$Type,
        [string]$Message,
        [boolean]$NoNewline = $false
    )
    $Type = $Type.ToUpper()
    $color = switch ($Type) {
        "OK"   { "Green" }
        "INFO" { "Cyan" }
        "ERR"  { "Red" }
        "WARN" { "Yellow" }
        "LOG"  { "Magenta" }
        default { "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $color -NoNewline:$NoNewline
}

# ===================== STEAM DETECTION =====================
Log "INFO" "Searching for Steam installation..."

function Find-SteamPath {
    $PossiblePaths = @()
    try {
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.InstallPath) { $PossiblePaths += $reg.InstallPath }
    } catch {}
   
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.SteamPath) { $PossiblePaths += $reg.SteamPath -replace '\\\\', '\' }
    } catch {}
   
    $DefaultPath = "C:\Program Files (x86)\Steam"
    if (Test-Path $DefaultPath) { $PossiblePaths += $DefaultPath }
   
    $PossiblePaths = $PossiblePaths | Select-Object -Unique | Where-Object { Test-Path $_ }
   
    if ($PossiblePaths.Count -eq 0) {
        Log "ERR" "Steam installation not found. Please install Steam first."
        exit 1
    }
   
    $SteamPath = $PossiblePaths[0]
    Log "OK" "Steam found at: $SteamPath"
    return $SteamPath
}

$steam = Find-SteamPath

# ===================== CLOSE STEAM =====================
Log "INFO" "Closing Steam if running..."
Get-Process -Name "steam" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host ""

# ===================== DOWNLOAD LATEST FILES =====================
Log "INFO" "Fetching latest CloudRedirect files..."

$ApiUrl = "https://api.github.com/repos/Selectively11/CloudRedirect/releases/latest"
$CliFile = Join-Path $env:TEMP "CloudRedirectCLI.exe"
$DllFile = Join-Path $env:TEMP "cloud_redirect.dll"

try {
    $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing -ErrorAction Stop
    Log "LOG" "Latest version: $($Release.tag_name)"

    # Download CloudRedirectCLI.exe
    $CliAsset = $Release.assets | Where-Object { $_.name -eq "CloudRedirectCLI.exe" } | Select-Object -First 1
    if ($CliAsset) {
        Log "LOG" "Downloading CloudRedirectCLI.exe..."
        Invoke-WebRequest -Uri $CliAsset.browser_download_url -OutFile $CliFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Log "OK" "CloudRedirectCLI.exe downloaded"
    }

    # Download cloud_redirect.dll
    $DllAsset = $Release.assets | Where-Object { $_.name -eq "cloud_redirect.dll" } | Select-Object -First 1
    if ($DllAsset) {
        Log "LOG" "Downloading cloud_redirect.dll..."
        Invoke-WebRequest -Uri $DllAsset.browser_download_url -OutFile $DllFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Log "OK" "cloud_redirect.dll downloaded"
    }
}
catch {
    Log "ERR" "Failed to download latest files"
    Log "ERR" $_.Exception.Message
    exit 1
}

# ===================== EXECUTE CLI =====================
for ($i = 5; $i -ge 1; $i--) {
    Log "INFO" "Starting CloudRedirect Fixer in $i second$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

Log "INFO" "Running CloudRedirect Fixer..."
try {
    & $CliFile /stfixer
    Log "OK" "CloudRedirectCLI executed successfully"
}
catch {
    Log "ERR" "Error while executing CloudRedirectCLI"
    Log "ERR" $_.Exception.Message
}

# ===================== INSTALL DLL =====================
Log "INFO" "Installing cloud_redirect.dll to Steam folder..."
$TargetDll = Join-Path $steam "cloud_redirect.dll"

try {
    Copy-Item -Path $DllFile -Destination $TargetDll -Force -ErrorAction Stop
    Log "OK" "cloud_redirect.dll installed successfully"
}
catch {
    Log "ERR" "Failed to copy cloud_redirect.dll"
    Log "ERR" $_.Exception.Message
}

# ===================== CLEANUP =====================
Start-Sleep -Seconds 2
Log "INFO" "Cleaning temporary files..."
Remove-Item -Path $CliFile -Force -ErrorAction SilentlyContinue
Remove-Item -Path $DllFile -Force -ErrorAction SilentlyContinue
Log "OK" "Temporary files removed"

Write-Host ""

# ===================== FINAL =====================
Log "OK" "Operation completed successfully!"
Log "WARN" "Steam startup may take longer than usual."
Write-Host ""

$exe = Join-Path $steam "steam.exe"
if (Test-Path $exe) {
    Log "INFO" "Starting Steam..."
    Start-Process $exe -ArgumentList "-clearbeta"
}

Write-Host ""
Log "INFO" "Press any key to close this window..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit
