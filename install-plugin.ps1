# Anyone seeing this? well don't waste time improving this script.
# It's messy and just temporary until i get the new version.

param(
    [string]$DownloadLink # Overwrites the download link (give a direct link)
)

## Configure this
$Host.UI.RawUI.WindowTitle = "Luatools plugin installer | .gg/luatools"
$name = "luatools" # automatic first letter uppercase included
$link = "https://github.com/madoiscool/ltsteamplugin/releases/latest/download/ltsteamplugin.zip"
$milleniumTimer = 5 # in seconds for auto-installation

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Hidden defines
$steam = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath
$upperName = $name.Substring(0, 1).ToUpper() + $name.Substring(1).ToLower()
if ( $DownloadLink ) {
    $link = $DownloadLink
}


#### Logging defines ####
function Log {
    param ([string]$Type, [string]$Message, [boolean]$NoNewline = $false)

    $Type = $Type.ToUpper()
    switch ($Type) {
        "OK" { $foreground = "Green" }
        "INFO" { $foreground = "Cyan" }
        "ERR" { $foreground = "Red" }
        "WARN" { $foreground = "Yellow" }
        "LOG" { $foreground = "Magenta" }
        "AUX" { $foreground = "DarkGray" }
        default { $foreground = "White" }
    }

    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor "Cyan" -NoNewline

    Write-Host [$Type] $Message -ForegroundColor $foreground -NoNewline:$NoNewline
}
Log "WARN" "Hey! Just letting you know that i'm working on a new version combining various scripts of the server"
Log "AUX" "Will include language support on THIS script too, luv y'all brazilians"
Write-Host

# To hide IEX blue box thing
$ProgressPreference = 'SilentlyContinue'



Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force


#### Requirements part ####

# Steamtools check
# TODO: Make this prettier?
$path = Join-Path $steam "dwmapi.dll"
if ( Test-Path $path ) {
    Log "INFO" "Steamtools already installed"
}
else {
    # Filtering the installation script
    $script = Invoke-RestMethod "https://luatools.vercel.app/st.ps1"
    $keptLines = @()

    foreach ($line in $script -split "`n") {
        $conditions = @( # Removes lines containing one of those
            ($line -imatch "Start-Process" -and $line -imatch "steam"),
            ($line -imatch "steam\.exe"),
            ($line -imatch "Start-Sleep" -or $line -imatch "Write-Host"),
            ($line -imatch "cls" -or $line -imatch "exit"),
            ($line -imatch "Stop-Process" -and -not ($line -imatch "Get-Process"))
        )
        
        if (-not($conditions -contains $true)) {
            $keptLines += $line
        }
    }

    $SteamtoolsScript = $keptLines -join "`n"
    Log "ERR" "Steamtools not found."
    
    # Retrying with a max of 5
    for ($i = 0; $i -lt 5; $i++) {

        Log "AUX" "Install it at your own risk! Close this script if you don't want to."
        Log "WARN" "Pressing any key will install steamtools (UI-less)."
        
        [void][System.Console]::ReadKey($true)
        Write-Host
        Log "WARN" "Installing Steamtools"
        
        Invoke-Expression $SteamtoolsScript *> $null

        if ( Test-Path $path ) {
            Log "OK" "Steamtools installed"
            break
        }
        else {
            Log "ERR" "Steamtools installation failed, retrying..."
        }

    }
}

# Millenium check
$milleniumInstalling = $false
foreach ($file in @("millennium.dll", "python311.dll")) {
    if (!( Test-Path (Join-Path $steam $file) )) {
        
        # Ask confirmation to download
        Log "ERR" "Millenium not found, installation process will start in 5 seconds."
        Log "WARN" "Press any key to cancel the installation."
        
        for ($i = $milleniumTimer; $i -ge 0; $i--) {
            # Wheter a key was pressed
            if ([Console]::KeyAvailable) {
                Write-Host
                Log "ERR" "Installation cancelled by user."
                exit
            }

            Log "LOG" "Installing Millenium in $i second(s)... Press any key to cancel." $true
            Start-Sleep -Seconds 1
        }
        Write-Host



        Log "INFO" "Installing millenium"

        Invoke-Expression "& { $(Invoke-RestMethod 'https://clemdotla.github.io/millennium-installer-ps1/millennium.ps1') } -NoLog -DontStart -SteamPath '$steam'"

        Log "OK" "Millenium done installing"
        $milleniumInstalling = $true
        break
    }
}
if ($milleniumInstalling -eq $false) { Log "INFO" "Millenium already installed" }



#### Plugin part ####
# Ensuring \Steam\plugins
if (!( Test-Path (Join-Path $steam "plugins") )) {
    New-Item -Path (Join-Path $steam "plugins") -ItemType Directory *> $null
}


$Path = Join-Path $steam "plugins\$name" # Defaulting if no install found

# Checking for plugin named "$name"
foreach ($plugin in Get-ChildItem -Path (Join-Path $steam "plugins") -Directory) {
    $testpath = Join-Path $plugin.FullName "plugin.json"
    if (Test-Path $testpath) {
        $json = Get-Content $testpath -Raw | ConvertFrom-Json
        if ($json.name -eq $name) {
            Log "INFO" "Plugin already installed, updating it"
            $Path = $plugin.FullName # Replacing default path
            break
        }
    }
}

# Installation 
$subPath = Join-Path $env:TEMP "$name.zip"

Log "LOG" "Downloading $name"
if ($DownloadLink) { Log "Aux" $($link) }
Invoke-WebRequest -Uri $link -OutFile $subPath *> $null
if ( !( Test-Path $subPath ) ) {
    Log "ERR" "Failed to download $name"
    exit
}
Log "LOG" "Unzipping $name"
try {      
    $zip = [System.IO.Compression.ZipFile]::OpenRead($subPath)
    foreach ($entry in $zip.Entries) {
        $destinationPath = Join-Path $Path $entry.FullName
        
        if (-not $entry.FullName.EndsWith('/') -and -not $entry.FullName.EndsWith('\')) {
            $parentDir = Split-Path -Path $destinationPath -Parent
            if ($parentDir -and $parentDir.Trim() -ne '') {
                $pathParts = $parentDir -replace [regex]::Escape($steam), '' -split '[\\/]' | Where-Object { $_ }
                $currentPath = $Path
                
                foreach ($part in $pathParts) {
                    $currentPath = Join-Path $currentPath $part
                    if (Test-Path $currentPath) {
                        $item = Get-Item $currentPath
                        if (-not $item.PSIsContainer) {
                            Remove-Item $currentPath -Force
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
    write-host "Error: $($_.Exception.Message)"
    if ($zip) { $zip.Dispose() }
    Log "ERR" "Extraction failed, trying normal way"
    Expand-Archive -Path $subPath -DestinationPath $Path -Force
}


if ( Test-Path $subPath ) {
    Remove-Item $subPath -ErrorAction SilentlyContinue
}

Log "OK" "$upperName installed"


# Removing beta
$betaPath = Join-Path $steam "package\beta"
if ( Test-Path $betaPath ) {
    Remove-Item $betaPath -Recurse -Force
}
# Removing potential x32 (kinda greedy but ppl got issues and was hard to fix without knowing it was the issue, ppl don't know what they run)
$cfgPath = Join-Path $steam "steam.cfg"
if ( Test-Path $cfgPath ) {
    Remove-Item $cfgPath -Recurse -Force
}
Remove-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue


# Toggling the plugin on (+turning off updateChecking to try fixing a bug where steam doesn't start)
$configPath = Join-Path $steam "ext/config.json"
if (-not (Test-Path $configPath)) {
    $config = @{
        plugins = @{
            enabledPlugins = @($name)
        }
        general = @{
            checkForMillenniumUpdates = $false
        }
    }
    New-Item -Path (Split-Path $configPath) -ItemType Directory -Force | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}
else {
    $config = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json

    function _EnsureProperty {
        param($Object, $PropertyName, $DefaultValue)
        if (-not $Object.$PropertyName) {
            $Object | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $DefaultValue -Force
        }
    }

    _EnsureProperty $config "general" @{}
    _EnsureProperty $config "general.checkForMillenniumUpdates" $false
    $config.general.checkForMillenniumUpdates = $false

    _EnsureProperty $config "plugins" @{ enabledPlugins = @() }
    _EnsureProperty $config "plugins.enabledPlugins" @()
    
    $pluginsList = @($config.plugins.enabledPlugins)
    if ($pluginsList -notcontains $name) {
        $pluginsList += $name
        $config.plugins.enabledPlugins = $pluginsList
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}
Log "OK" "Plugin enabled"


# Result showing
Write-Host
if ($milleniumInstalling) { Log "WARN" "Steam startup will be longer, don't panic and don't touch anything in steam!" }


# Start with the "-clearbeta" argument
$exe = Join-Path $steam "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"

Log "INFO" "Starting steam"
Log "WARN" "Hey so there's a bug where steam may not start"
Log "WARN" "Hopefully this script fixes it"
Log "WARN" "But i had to turn updates of millennium off."
Log "WARN" "In future, they will come back but in the meantime:"
Log "OK" "Manually check for updates of millennium if you want up to date."
Log "AUX" "Millennium is working now tho (latest version)."