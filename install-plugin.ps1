# Configuration -- edit these before running, or override via env vars:
#   $env:LT_DOWNLOAD_LINK, $env:LT_PLUGIN_NAME, $env:LT_BRANCH, $env:LT_CULTURE
$Script:DownloadLink = $env:LT_DOWNLOAD_LINK
$Script:PluginName   = $env:LT_PLUGIN_NAME
$Script:Branch       = if ($env:LT_BRANCH) { [int]$env:LT_BRANCH } else { 1 }
$Script:Culture      = $env:LT_CULTURE
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 # fix SSL/TSL Error
$Script:ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$null = chcp 65001
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Net.Http

# ---------------------------------------------------------------------------
# Locale defaults
# ---------------------------------------------------------------------------
function Get-DefaultStrings {
    param([string]$Culture)

    $tables = @{
        "en" = @{
            Title                 = "Luatools plugin installer | .gg/luatools"
            SteamRegNotFound      = "Steam registry key not found. Is Steam installed?"
            SteamKilling          = "Stopping Steam"
            SteamKilled           = "Steam stopped"
            SteamtoolsFound       = "Steamtools already installed"
            SteamtoolsNotFound    = "Steamtools not found"
            SteamtoolsInstalling  = "Installing Steamtools"
            SteamtoolsInstalled   = "Steamtools installed"
            SteamtoolsRetrying    = "Steamtools installation failed, retrying..."
            SteamtoolsFailed      = "Steamtools installation failed after 5 attempts"
            MillenniumNotFound    = "Millennium not found"
            MillenniumCountdown   = "Millennium will be installed in {0} second(s)... Press any key to cancel"
            MillenniumCancelled   = "Installation cancelled by user"
            MillenniumInstalling  = "Installing Millennium"
            MillenniumInstalled   = "Millennium installed"
            MillenniumAlready     = "Millennium already installed"
            MillenniumFirstBoot   = "Steam startup may be slower on first boot -- let it sit."
            PluginUpdating        = "Plugin already installed, updating"
            PluginDuplicates      = "Multiple conflicting copies found, cleaning up and reinstalling"
            PluginDownloading     = "Downloading {0}"
            PluginDownloadFailed  = "Failed to download {0}"
            PluginExtracting      = "Extracting {0}"
            PluginExtractFailed   = "Extraction failed, trying built-in Expand-Archive"
            PluginInstalled       = "{0} installed"
            PluginEnabled         = "Plugin enabled"
            RemovingBeta          = "Cleaning up beta flag"
            RemovingCfg           = "Cleaning up steam.cfg"
            RemovingFlags         = "Cleaning up ForceX86 flags and offline mode"
            StartingSteam         = "Starting Steam"
            UpdateCheckDisabled   = "Millennium auto-updates disabled to prevent startup hangs."
            UpdateCheckManual     = "Check for Millennium updates manually if you want the latest."

            ErrorTitle            = "Luatools installer - ERROR"
            ErrorHeader           = "AN ERROR OCCURRED"
            ErrorBody             = "The Luatools plugin installer encountered a problem and could not complete. This is often caused by your ISP blocking the download servers we use."
            ErrorFaq              = "Visit the server (.gg/luatools) for more information & fixes."
            ErrorExit             = "Press any key to exit."
        }

        "pt-BR" = @{
            Title                 = "Instalador do Luatools | .gg/luatools"
            SteamRegNotFound      = "Steam não encontrada no registro. Sua Steam ta instalada?"
            SteamKilling          = "Parando a Steam"
            SteamKilled           = "Steam Encerrada"
            SteamtoolsFound       = "Steamtools ja instalado"
            SteamtoolsNotFound    = "Steamtools não encontrado"
            SteamtoolsInstalling  = "Instalando Steamtools"
            SteamtoolsInstalled   = "Steamtools instalado"
            SteamtoolsRetrying    = "Falha ao instalar Steamtools, tentando denovo..."
            SteamtoolsFailed      = "Falha ao instalar Steamtools após 5 tentativas"
            MillenniumNotFound    = "Millennium não encontrado"
            MillenniumCountdown   = "Millennium vai ser instalado em {0} segundo(s)... Aperte qualquer tecla pra cancelar"
            MillenniumCancelled   = "Instalação cancelada pelo usuário"
            MillenniumInstalling  = "Instalando Millennium"
            MillenniumInstalled   = "Millennium instalado"
            MillenniumAlready     = "O Millennium ja está instalado"
            MillenniumFirstBoot   = "A Steam pode demorar um pouco pra abrir pela primeira vez -- deixa rolar."
            PluginUpdating        = "Plugin já instalado, atualizando"
            PluginDuplicates      = "Várias cópias conflitantes encontradas, limpando e reinstalando"
            PluginDownloading     = "Baixando {0}"
            PluginDownloadFailed  = "Falha ao baixar {0}"
            PluginExtracting      = "Extraindo {0}"
            PluginExtractFailed   = "Falha ao extrair, tentando via Expand-Archive"
            PluginInstalled       = "{0} instalado"
            PluginEnabled         = "Plugin habilitado"
            RemovingBeta          = "Limpando flag de beta da Steam"
            RemovingCfg           = "Apagando steam.cfg"
            RemovingFlags         = "Limpando flags do ForceX86 e o modo offline"
            StartingSteam         = "Abrindo a Steam"
            UpdateCheckDisabled   = "Atualizações automáticas do Millennium desabilitadas pra evitar travamentos ao iniciar"
            UpdateCheckManual     = "Verifique manualmente por atualizações do Millennium caso você queira a ultima versão"

            ErrorTitle            = "Instalador do Luatools - ERRO"
            ErrorHeader           = "OCORREU UM ERRO"
            ErrorBody             = "O instalador do Luatools encontrou um problema e não pôde ser concluído. Isso geralmente é causado pela tua internet bloqueando nossos servidores de Download"
            ErrorFaq              = "Visite o servidor (.gg/luatools) pra mais informações e detalhes em como consertar"
            ErrorExit             = "Aperte qualquer botão pra sair."
        }

        "es" = @{
            Title                 = "Instalador del plugin de Luatools | .gg/luatools"
            SteamRegNotFound      = "La clave de registro de Steam no se ha encontrado. Está Steam instalado?"
            SteamKilling          = "Deteniendo Steam"
            SteamKilled           = "Steam se ha detenido"
            SteamtoolsFound       = "Steamtools ya está instalado"
            SteamtoolsNotFound    = "Steamtools no se ha encontrado"
            SteamtoolsInstalling  = "Instalando Steamtools"
            SteamtoolsInstalled   = "Steamtools se ha instalado"
            SteamtoolsRetrying    = "La instalación de Steamtools ha fallado, reintentando..."
            SteamtoolsFailed      = "La instalación de Steamtools ha fallado despues de 5 intentos"
            MillenniumNotFound    = "Millenium no encontrado"
            MillenniumCountdown   = "Millenium sera instalado en {0} segundo(s) ... Presiona cualquier tecla para cancelar"
            MillenniumCancelled   = "Instalación cancelada por el usuario"
            MillenniumInstalling  = "Instalando Millenium"
            MillenniumInstalled   = "Millenium instalado"
            MillenniumAlready     = "Millenium ya estaba instalado"
            MillenniumFirstBoot   = "La carga de steam puede ser más lenta la primera vez para cargar las dependencias -- espera pacientemente"
            PluginUpdating        = "El plugin ya esta instalado, actualizando"
            PluginDuplicates      = "Se encontraron varias copias en conflicto, limpiando y reinstalando"
            PluginDownloading     = "Descargando {0}"
            PluginDownloadFailed  = "Error al descargar {0}"
            PluginExtracting      = "Extrayendo {0}"
            PluginExtractFailed   = "Extracción fallida, intentando descomprimir archivos"
            PluginInstalled       = "{0} instalado"
            PluginEnabled         = "Plugin establecido"
            RemovingBeta          = "Limpiando indicador beta"
            RemovingCfg           = "Limpiando steam.cfg"
            RemovingFlags         = "Limpiando flags de ForceX86 y el modo sin conexión"
            StartingSteam         = "Iniciando Steam"
            UpdateCheckDisabled   = "Las auto-actualizaciones de Millenium están deshabilitadas para prevenir cuelgues al inicio"
            UpdateCheckManual     = "Comprueba las actualizaciones de Millenium manualmente si necesitas la última versión"

            ErrorTitle            = "Error con el instalador Luatools - ERROR"
            ErrorHeader           = "UN ERROR HA OCURRIDO"
            ErrorBody             = "El instalador del plugin Luatools encontró un problema y no pudo completarse. Esto suele ocurrir cuando tu proveedor de internet (ISP) bloquea los servidores de descarga que utilizamos."
            ErrorFaq              = "Visita el servidor (.gg/luatools) para mas información o fixes."
            ErrorExit             = "Presiona cualquier tecla para salir."
        }

        "fr" = @{
            Title                 = "Installateur du plugin Luatools | .gg/luatools"
            SteamRegNotFound      = "Clé de registre steam introuvable. Est ce que Steam est installé?"
            SteamKilling          = "Arrêt de Steam"
            SteamKilled           = "Steam arreté"
            SteamtoolsFound       = "Steamtools déjà installé"
            SteamtoolsNotFound    = "Steamtools introuvable"
            SteamtoolsInstalling  = "Installation de Steamtools"
            SteamtoolsInstalled   = "Steamtools installé"
            SteamtoolsRetrying    = "L'instalation de Steamtools a echoué, nouvelle tentative..."
            SteamtoolsFailed      = "L'installation de Steamtools a echoué apres 5 tentatives"
            MillenniumNotFound    = "Millennium introuvable"
            MillenniumCountdown   = "Millennium sera installé dans {0} seconde(s)... Appuyez sur une touche pour annuler"
            MillenniumCancelled   = "Installation annuléee par l'utilisateur"
            MillenniumInstalling  = "Installation de Millennium"
            MillenniumInstalled   = "Millennium installé"
            MillenniumAlready     = "Millennium déjà installé"
            MillenniumFirstBoot   = "Le prochain lancement de Steam sera plus long -- laisser le temps."
            PluginUpdating        = "Plugin déjà installé, mise à jour"
            PluginDuplicates      = "Plusieurs copies en conflit trouvées, nettoyage et réinstallation"
            PluginDownloading     = "Installation {0}"
            PluginDownloadFailed  = "Echec de l'installation {0}"
            PluginExtracting      = "Extraction {0}"
            PluginExtractFailed   = "Extraction echouée, tentative avec la fonction native"
            PluginInstalled       = "{0} installé"
            PluginEnabled         = "Plugin activé"
            RemovingBeta          = "Nettoyage de la beta"
            RemovingCfg           = "Nettoyage de steam.cfg"
            RemovingFlags         = "Nettoyage des flags ForceX86 et du mode hors ligne"
            StartingSteam         = "Lancement de Steam"
            UpdateCheckDisabled   = "Les mises à jour de Millennium ont été désactivée pour éviter les blocages au demarrage."
            UpdateCheckManual     = "Vérifiez manuellement les mises à jour de Millennium si vous souhaitez la derniere version."

            ErrorTitle            = "Installateur Luatools - ERREUR"
            ErrorHeader           = "UNE ERREUR EST SURVENUE"
            ErrorBody             = "L'installation du plugin Luatools a rencontré un problème et n'a pas pu se terminer. Ça se produit souvent quand votre fournisseur d'internet (ISP) bloque les serveurs de téléchargement."
            ErrorFaq              = "Allez voir le serveur (.gg/luatools) pour plus d'informations & corrections."
            ErrorExit             = "Appuyez sur une touche pour quitter."
        }
    }

    foreach ($key in @($Culture, $Culture.Split('-')[0], "en")) {
        if ($tables.ContainsKey($key)) {
            return $tables[$key]
        }
    }
    return $tables["en"]
}

# ---------------------------------------------------------------------------
# Resolve messages based on locale
# ---------------------------------------------------------------------------
$DetectedCulture = if ($Script:Culture) { $Script:Culture } else { [System.Globalization.CultureInfo]::CurrentUICulture.Name }
$L = Get-DefaultStrings -Culture $DetectedCulture

# ---------------------------------------------------------------------------
# Global error trap -- catches ANY terminating error and shows error page
# MUST be placed after $L is populated so error strings are available
# ---------------------------------------------------------------------------
$Script:OriginalErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Stop"

trap {
    $errMsg = $_.Exception.Message

    # Ensure $L has something even if the hashtable failed
    if (-not $L) { $L = Get-DefaultStrings -Culture "en" }

    $host.UI.RawUI.CursorPosition = @{ X=0; Y=0 }
    $errTitle = if ($L.ContainsKey("ErrorTitle")) { $L["ErrorTitle"] } else { "Luatools installer - ERROR" }
    $host.UI.RawUI.WindowTitle = $errTitle
    Clear-Host

    $width = $host.UI.RawUI.WindowSize.Width

    Write-Host ("=" * $width) -ForegroundColor Red
    Write-Host ""

    $header = if ($L.ContainsKey("ErrorHeader")) { $L["ErrorHeader"] } else { "AN ERROR OCCURRED" }
    $pad = [Math]::Max(0, [int](($width - $header.Length) / 2))
    Write-Host (" " * $pad) -NoNewline
    Write-Host $header -ForegroundColor Red -BackgroundColor Black
    Write-Host ""

    $body = if ($L.ContainsKey("ErrorBody")) { $L["ErrorBody"] } else { "The installer encountered a problem." }
    Write-Host $body -ForegroundColor White
    Write-Host ""

    Write-Host ">>> " -NoNewline -ForegroundColor Yellow
    Write-Host $errMsg -ForegroundColor Gray
    Write-Host ""

    $faq = if ($L.ContainsKey("ErrorFaq")) { $L["ErrorFaq"] } else { "Visit (.gg/luatools)" }
    Write-Host $faq -ForegroundColor Cyan
    Write-Host ""

    Write-Host ("=" * $width) -ForegroundColor Red
    Write-Host ""

    $exitMsg = if ($L.ContainsKey("ErrorExit")) { $L["ErrorExit"] } else { "Press any key to exit." }
    Write-Host $exitMsg -ForegroundColor Yellow
    try { $null = [System.Console]::ReadKey($true) } catch {}

    $ErrorActionPreference = $Script:OriginalErrorAction
    break
}

# ---------------------------------------------------------------------------
# Console helpers
# ---------------------------------------------------------------------------
$Host.UI.RawUI.WindowTitle = $L["Title"]

$LogColors = @{
    "OK"   = "Green"
    "INFO" = "Cyan"
    "ERR"  = "Red"
    "WARN" = "Yellow"
    "LOG"  = "Magenta"
    "AUX"  = "DarkGray"
}

function Write-Log {
    param(
        [ValidateSet("OK","INFO","ERR","WARN","LOG","AUX")]
        [string]$Type,
        [string]$Message,
        [switch]$NoNewline
    )
    $color = $LogColors[$Type]
    $ts = Get-Date -Format "HH:mm:ss"
    if ($NoNewline) {
        Write-Host "`r[$ts] " -ForegroundColor Cyan -NoNewline
        Write-Host "[$Type] $Message" -ForegroundColor $color -NoNewline
    } else {
        Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
        Write-Host "[$Type] $Message" -ForegroundColor $color
    }
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$Script:Name      = "luatools"
$Script:Link      = "https://github.com/piqseu/ltsteamplugin/releases/latest/download/ltsteamplugin.zip"
$MillenniumTimer  = 5

if ($Script:Branch -eq 2) {
    $Script:Name = "steamtools-collection"
    $Script:Link = "https://github.com/clemdotla/steamtools-collection/releases/download/Latest/steamtools-collection.zip"
}
if ($Script:DownloadLink) { $Script:Link = $Script:DownloadLink }
if ($Script:PluginName)   { $Script:Name = $Script:PluginName }

$DisplayName = $Script:Name.Substring(0,1).ToUpper() + $Script:Name.Substring(1).ToLower()

# ---------------------------------------------------------------------------
# Steam path
# ---------------------------------------------------------------------------
function Get-SteamPath {
    $registries = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    foreach ($reg in $registries) {
        if (!(Test-Path $reg)) { continue }

        $path = (Get-ItemProperty -Path $reg -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
        $potentialExe = Join-Path $path "steam.exe"
        if ((Test-Path $path) -and (Test-Path $potentialExe)) {
            return $path
        }
    }
    Write-Log -Type ERR -Message $L["SteamRegNotFound"]
}

# ---------------------------------------------------------------------------
# Steamtools -- REQUIRED, no user choice
# ---------------------------------------------------------------------------
function Test-Steamtools {
    param([string]$SteamPath)
    foreach ($f in @("dwmapi.dll", "xinput1_4.dll")) {
        if (Test-Path -LiteralPath (Join-Path $SteamPath $f)) { return $true }
    }
    return $false
}
function Install-Steamtools {
    param([string]$SteamPath)

    Write-Log -Type WARN -Message $L["SteamtoolsInstalling"]

    $zipFile = Join-Path $SteamPath "ost.zip"
    Invoke-WebRequest -Uri "https://github.com/madoiscool/lt_api_links/releases/download/ost-148/ost.zip" -OutFile $zipFile -TimeoutSec 60 -UseBasicParsing
    if (-not (Test-Path -LiteralPath $zipFile)) { throw $L["SteamtoolsFailed"] }

    Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $zipFile -DestinationPath $SteamPath -Force
    Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue

    $steamCfg = Join-Path $SteamPath "steam.cfg"
    $steamCfgBak = Join-Path $SteamPath "steam.cfg.bak"
    if (Test-Path -LiteralPath $steamCfg) {
        Move-Item -LiteralPath $steamCfg -Destination $steamCfgBak -Force -ErrorAction SilentlyContinue
    }

    if (Test-Steamtools $SteamPath) {
        Write-Log -Type OK -Message $L["SteamtoolsInstalled"]
        return
    }

    throw $L["SteamtoolsFailed"]
}

# ---------------------------------------------------------------------------
# Millennium
# ---------------------------------------------------------------------------
function Test-Millennium {
    param([string]$SteamPath)
    # wsock32.dll is the Millennium proxy DLL dropped at the Steam root by BOTH
    # v2.x and v3.x; millennium.dll / python311.dll only exist on the older v2.x
    # layout. Match on any of them so detection works across versions.
    foreach ($f in @("wsock32.dll", "millennium.dll", "python311.dll")) {
        if (Test-Path -LiteralPath (Join-Path $SteamPath $f)) { return $true }
    }
    return $false
}

function Install-Millennium {
    param([string]$SteamPath)

    Write-Log -Type INFO -Message $L["MillenniumInstalling"]
    # Our own copy of clem's installer (clemdotla.github.io/millennium-installer-ps1),
    # patched so the temp-zip cleanup can't crash on accounts whose username has a
    # space/non-ASCII char (8.3 short paths). Clem's upstream copy is the fallback.
    $msUrls = @(
        "https://ps.lua.tools/millennium.ps1",
        "https://luatools.vercel.app/millennium.ps1"
    )
    # Try each mirror up to 3x with a browser UA -- guards against transient
    # failures and bot-protection 403s. (A full ISP/region block of every host
    # can't be solved here; that needs a VPN/DNS on the user's end.)
    $msCode = $null
    foreach ($url in $msUrls) {
        for ($try = 1; $try -le 3 -and -not $msCode; $try++) {
            try {
                $msCode = Invoke-RestMethod $url -TimeoutSec 30 -Headers @{ "User-Agent" = "Mozilla/5.0 (Luatools Installer)" }
            } catch { Start-Sleep -Milliseconds 800 }
        }
        if ($msCode) { break }
    }
    if (-not $msCode) { throw $L["MillenniumNotFound"] }

    # Run the Millennium installer with a relaxed error preference + try/catch so
    # its own non-fatal hiccups (e.g. temp-zip cleanup crashing on accounts whose
    # username has a space/non-ASCII char) can't trip our global trap. Success is
    # judged by whether Millennium's files actually landed, not by whether the
    # sub-script returned cleanly.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        Invoke-Expression "& { $msCode } -NoLog -DontStart -SteamPath '$SteamPath'"
    } catch {
        Write-Log -Type WARN -Message "Millennium installer: $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # NOTE: Test-Millennium only checks the classic root DLLs (millennium.dll /
    # python311.dll). Newer Millennium uses a different layout, so a "false" here
    # does NOT reliably mean it failed -- never make it fatal, just warn and let
    # the install continue (matches the long-standing behaviour).
    if (Test-Millennium $SteamPath) {
        Write-Log -Type OK -Message $L["MillenniumInstalled"]
    } else {
        Write-Log -Type WARN -Message $L["MillenniumInstalled"]
    }
}

# ---------------------------------------------------------------------------
# Plugin install / update
# ---------------------------------------------------------------------------
function Install-Plugin {
    param([string]$SteamPath, [string]$Name, [string]$Link)

    $pluginsDir = Join-Path $millDir "plugins"
    if (-not (Test-Path $pluginsDir)) {
        $null = New-Item -Path $pluginsDir -ItemType Directory -Force
    }

    # Scan the new path AND the legacy <Steam>\plugins for any folder whose
    # plugin.json declares our plugin name. Millennium 3+ migrates the legacy
    # folder into the new path on boot, so a stale copy there (e.g. a manual
    # Python install under a different folder name) would end up colliding with
    # ours -- two folders, same plugin name -> Millennium crashes on enable.
    $legacyDir = Join-Path $SteamPath "plugins"
    $scanDirs  = @($pluginsDir, $legacyDir) | Where-Object { Test-Path $_ } | Select-Object -Unique

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($scanDir in $scanDirs) {
        foreach ($dir in (Get-ChildItem $scanDir -Directory -ErrorAction SilentlyContinue)) {
            $j = Join-Path $dir.FullName "plugin.json"
            if (Test-Path $j) {
                try {
                    $m = Get-Content $j -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($m.name -eq $Name) { $found.Add($dir.FullName) }
                } catch {}
            }
        }
    }

    $targetDir = Join-Path $pluginsDir $Name
    if ($found.Count -eq 1) {
        # Single existing install (anywhere) -> update it in place.
        Write-Log -Type INFO -Message $L["PluginUpdating"]
        $targetDir = $found[0]
    } elseif ($found.Count -gt 1) {
        # Multiple folders claim this plugin name -> remove every copy and
        # reinstall a single canonical folder to avoid the collision crash.
        Write-Log -Type WARN -Message $L["PluginDuplicates"]
        foreach ($dup in $found) {
            Remove-Item $dup -Recurse -Force -ErrorAction SilentlyContinue
        }
        $targetDir = Join-Path $pluginsDir $Name
    }

    $zipPath = Join-Path $SteamPath "$Name.zip"

    Write-Log -Type LOG -Message ($L["PluginDownloading"] -f $Name)
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [System.TimeSpan]::FromSeconds(60)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Luatools Installer)")
    
    $stream = $client.GetStreamAsync($Link).Result
    $fileStream = [System.IO.File]::Create($zipPath)
    $stream.CopyTo($fileStream)
    
    $fileStream.Close()
    $stream.Close()
    $client.Dispose()

    # Invoke-WebRequest -Uri $Link -OutFile $zipPath -TimeoutSec 60

    if (-not (Test-Path $zipPath)) {
        throw ($L["PluginDownloadFailed"] -f $Name)
    }

    Write-Log -Type LOG -Message ($L["PluginExtracting"] -f $Name)

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) { continue }
            $dest   = Join-Path $targetDir $entry.FullName
            $parent = Split-Path $dest -Parent

            $relParts = $parent.Substring($targetDir.Length).TrimStart('\','/') -split '[\\/]' | Where-Object { $_ }
            $cursor = $targetDir
            foreach ($part in $relParts) {
                $cursor = Join-Path $cursor $part
                if (Test-Path $cursor) {
                    $item = Get-Item $cursor
                    if (-not $item.PSIsContainer) { Remove-Item $cursor -Force }
                }
            }

            $null = [System.IO.Directory]::CreateDirectory($parent)
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
        }
        $zip.Dispose()
    } catch {
        if ($zip) { $zip.Dispose() }
        Write-Log -Type WARN -Message $L["PluginExtractFailed"]
        Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -ErrorAction SilentlyContinue }
    Write-Log -Type OK -Message ($L["PluginInstalled"] -f $DisplayName)
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
function Enable-Plugin {
    param([string]$SteamPath, [string]$Name)


    $configDir = Join-Path $millDir "config"
    $configPath = Join-Path $configDir "config.json"
    # Brang back old code cause newest wasn't working for some reason..
    # + Attempt to turn back on updates, hopefully the bug is fixed

    if (-not (Test-Path $configPath)) {
    $config = @{
        plugins = @{
            enabledPlugins = @($name)
        }
        # general = @{
        #     checkForMillenniumUpdates = $false
        # }
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

    # _EnsureProperty $config "general" @{}
    # _EnsureProperty $config "general.checkForMillenniumUpdates" $false
    # $config.general.checkForMillenniumUpdates = $false

    _EnsureProperty $config "plugins" @{ enabledPlugins = @() }
    _EnsureProperty $config "plugins.enabledPlugins" @()
    
    $pluginsList = @($config.plugins.enabledPlugins)
    if ($pluginsList -notcontains $name) {
        $pluginsList += $name
        $config.plugins.enabledPlugins = $pluginsList
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

    Write-Log -Type OK -Message $L["PluginEnabled"]
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
function Remove-BetaFlag {
    param([string]$SteamPath)
    $beta = Join-Path $SteamPath "package\beta"
    if (Test-Path $beta) {
        Write-Log -Type AUX -Message $L["RemovingBeta"]
        Remove-Item $beta -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Reset-SteamFlags {
    param([string]$SteamPath)
    Write-Log -Type AUX -Message $L["RemovingFlags"]

    # Clear ForceX86 (32-bit) registry flags
    @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam") | ForEach-Object {
        Remove-ItemProperty -Path $_ -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue
    }

    # Reset Steam offline mode for all accounts (WantsOfflineMode "1" -> "0")
    $loginUsersPath = Join-Path $SteamPath "config\loginusers.vdf"
    if (Test-Path $loginUsersPath) {
        $content = Get-Content -Path $loginUsersPath -Raw
        if ($content -match '"WantsOfflineMode"\s+"1"') {
            $newContent = $content -replace '("WantsOfflineMode"\s+)"1"', '$1"0"'
            Set-Content -Path $loginUsersPath -Value $newContent -Encoding UTF8
        }
    }
}

function Remove-SteamCfg {
    param([string]$SteamPath)
    $cfg = Join-Path $SteamPath "steam.cfg"
    if (Test-Path $cfg) {
        Write-Log -Type AUX -Message $L["RemovingCfg"]
        Remove-Item $cfg -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {

    $steamPath = Get-SteamPath
    $script:millDir = Join-Path $steamPath "millennium"
    if (-not (Test-Path $millDir)) {
        $null = New-Item -Path $millDir -ItemType Directory -Force
    }

    Write-Log -Type INFO -Message $L["SteamKilling"]
    while (Get-Process steam -ErrorAction SilentlyContinue) {
        Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    #if (Test-Steamtools $steamPath) {
    #    Write-Log -Type INFO -Message $L["SteamtoolsFound"]
    #} else {
    #    Write-Log -Type ERR -Message $L["SteamtoolsNotFound"]
    Install-Steamtools $steamPath # checks commented out so reinstalls get people out of china tools
    #}

    # Temporary (or not) forcing to get stable lua only backend
    # $millenniumWasInstalled = Test-Millennium $steamPath
    # if ($millenniumWasInstalled) {
    #     Write-Log -Type INFO -Message $L["MillenniumAlready"]
    # }
    Install-Millennium $steamPath

    Install-Plugin $steamPath $Script:Name $Script:Link

    Remove-BetaFlag $steamPath
    Remove-SteamCfg $steamPath
    Reset-SteamFlags $steamPath

    Enable-Plugin $steamPath $Script:Name

    Write-Host
    if (-not $millenniumWasInstalled) {
        Write-Log -Type WARN -Message $L["MillenniumFirstBoot"]
    }
    # Write-Log -Type WARN -Message $L["UpdateCheckDisabled"]
    # Write-Log -Type OK   -Message $L["UpdateCheckManual"]

    Write-Log -Type INFO -Message $L["StartingSteam"]
    Start-Process (Join-Path $steamPath "steam.exe") -ArgumentList "-clearbeta"
    $ErrorActionPreference = $Script:OriginalErrorAction
}

Main

# By clem
# Waike contributed a lot
