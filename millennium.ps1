param(
    [switch]$NoLog,
    [switch]$NoWarn,
    [switch]$DontStart,
    [string]$SteamPath,
    [string]$Version
)

if (!$NoLog) { $Host.UI.RawUI.WindowTitle = "Millennium installer | clem.la" }

Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Log {
    param ([string]$Type, [string]$Message, [boolean]$NoNewline = $false)

    if ($NoLog) {
        return
    }

    $Type = $Type.ToUpper()
    switch ($Type) {
        "OK"   { $foreground = "Green" }
        "INFO" { $foreground = "Blue" }
        "ERR"  { $foreground = "Red" }
        "WARN" { $foreground = "Yellow" }
        "LOG"  { $foreground = "Magenta" }
        "AUX"  { $foreground = "DarkGray" }
        default { $foreground = "White" }
    }

    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor "Cyan" -NoNewline

    Write-Host [$Type] $Message -ForegroundColor $foreground -NoNewline:$NoNewline
}

function GetSteam {
    $steam = $null

    if ($SteamPath -and (Test-Path $SteamPath) -and (Test-Path (Join-Path $SteamPath "steam.exe"))) {
        $steam = $SteamPath
    } else {
        $registries = @(
            "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
            "HKLM:\SOFTWARE\Valve\Steam",
            "HKCU:\SOFTWARE\Valve\Steam"
        )

        foreach ($reg in $registries) {
            if (!(Test-Path $reg)) { continue }

            $path = (Get-ItemProperty -Path $reg -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
            if ($path -and (Test-Path $path) -and (Test-Path (Join-Path $path "steam.exe"))) {
                $steam = $path                
                break
            }
        }
    }

    if (!$steam) {
        Log "ERR" "Steam not found..."
        exit
    }

    Log "OK" "Steam found $steam"
    return $steam
}
function GetTemp {
    if (-not $env:TEMP -or -not (Test-Path $env:TEMP)) {
        if ($env:LOCALAPPDATA -and (Test-Path $env:LOCALAPPDATA)) {
            $env:TEMP = Join-Path $env:LOCALAPPDATA "Temp"
        }
        if (-not $env:TEMP -or -not (Test-Path $env:TEMP)) {
            $env:TEMP = Join-Path $root "temp"
        }
    }

    if (-not (Test-Path $env:TEMP)) {
        New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    }

    return $env:TEMP
}


$steam = GetSteam
$temp = GetTemp

function FetchGithub() {
    param( [string]$ver ) 

    if ($ver) {
        $api = "tags/$($ver.Trim())"
    } else {
        $api = "latest"
    }

    function Failed() {
        if ($ver) {
            Log "ERR" "No download link found for version $ver"
            Log "AUX" "Fallback to latest version"
            return FetchGithub
        }

        Log "ERR" "No download link found"
        exit
    }

    try {
        $res = Invoke-RestMethod "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/$api"
        $datas = $null
        foreach ($asset in $res.assets) {
            if ($asset.name -imatch "windows" -and $asset.name -imatch "zip") {
                $datas = @{
                    link = $asset.browser_download_url
                    version = $res.tag_name
                    size = $asset.size
                    sha = ($asset.digest -replace "sha256:", "").ToUpper()
                }
        
                Log "OK" "Found download link"
                break
            }
        }
        if (!$datas -or !$datas.link) {
            return Failed
        }
    } catch {
        return Failed
    }


    return $datas
}
function DownloadArchive() {
    # Download into the Steam folder (clean ASCII path) instead of %TEMP%, which
    # breaks on usernames with spaces/non-ASCII chars (8.3 short paths).
    $downloadPath = Join-Path $steam "millennium.zip"
    Log "LOG" "Downloading the archive"
    
    
    $client = [System.Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0")
    
    $stream = $client.GetStreamAsync($datas.link).Result
    $fileStream = [System.IO.File]::Create($downloadPath)
    
    $stream.CopyTo($fileStream)
    
    $fileStream.Close()
    $stream.Close()
    $client.Dispose()
    
    $file = Get-Item $downloadPath
    if (
        (Test-Path $downloadPath) -and
        ($file.Length -eq $datas.size) -and
        ((Get-FileHash $file -Algorithm SHA256).Hash -eq $datas.sha)
    ) {
        Log "OK" "Download completed and verified"
    } else {
        Log "ERR" "Download failed"
        exit
    }

    return $downloadPath
}
function TerminateSteam() {
    $steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    if ($steamProcess) {
        Stop-Process -Name "steam" -Force
    }
}
function ExtractArchive() {
    $start = Get-Date

    Log "Log" "Extracting the archive"
    try {
        if (-not (Test-Path $steam)) {
            New-Item -ItemType Directory -Path $steam -Force | Out-Null
        }
        
        $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
        
        foreach ($entry in $zip.Entries) {
            $destinationPath = Join-Path $steam $entry.FullName
            
            if (-not $entry.FullName.EndsWith('/') -and -not $entry.FullName.EndsWith('\')) {
                $parentDir = Split-Path -Path $destinationPath -Parent
                if ($parentDir -and $parentDir.Trim() -ne '') {
                    $pathParts = $parentDir -replace [regex]::Escape($steam), '' -split '[\\/]' | Where-Object { $_ }
                    $currentPath = $steam
                    
                    foreach ($part in $pathParts) {
                        $currentPath = Join-Path $currentPath $part
                        if (Test-Path -LiteralPath $currentPath) {
                            $item = Get-Item -LiteralPath $currentPath
                            if (-not $item.PSIsContainer) {
                                Remove-Item -LiteralPath $currentPath -Force
                            }
                        }
                    }
                    
                    [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationPath, $true)
                }
            }
        }
        
        $zip.Dispose()
    }
    catch {
        if ($zip) { $zip.Dispose() }
        Log "ERR" "Error while extracting... Falling back to native function"
        Expand-Archive -Path $path -DestinationPath $steam -Force
    }

    $time = ((Get-Date) - $start).TotalSeconds
    Log "OK" "Millennium extracted in $([Math]::Round($time, 1)) seconds"
}

$datas = FetchGithub($Version)
$path = DownloadArchive
TerminateSteam
ExtractArchive

try {
    if ($path -and (Test-Path -LiteralPath $path)) {
        Remove-Item -LiteralPath $path -Force
    }
} catch {}

# --------------------

function AddToEnv() {
    $bin = Join-Path -Path $steam -ChildPath "/ext/bin"

    if (-not ($env:PATH -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $bin })) {
        [System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$bin", [System.EnvironmentVariableTarget]::User)
    }
}

AddToEnv

if (!$NoLog) { Write-Host } 
Log "OK" "Successfully installed version $($datas.version)"
if (!$NoWarn) { 
    Log "WARN" "Next startup might be longer, don't panic or touch anything!"
}

$exe = Join-Path $steam "steam.exe"
if ((Test-Path $exe) -and (!$DontStart)) {
    Start-Process $exe
} else {
    Log "AUX" "Start steam manually..."
}