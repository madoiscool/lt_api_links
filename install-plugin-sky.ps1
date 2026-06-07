$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
# ==================== By Skyflare =====================
# ==================== DETECÇÃO DE IDIOMA =====================
$uiCulture = (Get-UICulture).Name
$lang = "en" # padrão

if ($uiCulture -match "^pt-BR") {
    $lang = "pt-BR"
}
elseif ($uiCulture -match "^pt-PT") {
    $lang = "pt-PT"
}
elseif ($uiCulture -match "^es") {
    $lang = "es"
}
else {
    $lang = "en"
}

# ==================== DICIONÁRIO DE TEXTOS ====================
$strings = @{
    "pt-BR" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "Procurando pasta raiz da Steam..."
        ErrSteamNotFound      = "Steam não encontrada. Instale/abra a Steam pelo menos uma vez e tente novamente."
        OkSteamFound          = "Steam encontrada:"
        WarnMillenniumMissing = "Millennium não encontrado. Instalando pela última release do GitHub..."
        InfoMillenniumUpdate  = "Millennium encontrado. Atualizando diretamente pela última release do GitHub..."
        InfoFetchMillennium   = "Buscando última release do Millennium no GitHub..."
        OkMillenniumRelease   = "Release do Millennium encontrada: {0}"
        Downloading           = "Baixando {0}..."
        Extracting            = "Extraindo {0}..."
        CopyingMillennium     = "Copiando/atualizando arquivos do Millennium na raiz da Steam..."
        WarnMillenniumFolder  = "Os arquivos foram extraídos, mas a pasta 'millennium' não foi encontrada. Confira se o asset da release mudou."
        OkMillenniumInstalled = "Millennium instalado/atualizado via GitHub."
        StoppingSteam         = "Fechando Steam..."
        StartingSteam         = "Abrindo Steam novamente..."
        InfoFetchLuaTools     = "Buscando última release do Luatools no GitHub..."
        OkLuaToolsRelease     = "Release do Luatools encontrada: {0}"
        RemovingOldPlugins    = "Removendo plugins antigos/conflitantes..."
        FolderRemoved         = "Pasta removida: {0}"
        InstallingLuaTools    = "Instalando Luatools..."
        OkLuaToolsInstalled   = "Luatools instalado em: {0}"
        EnablingPluginConfig  = "Plugin '{0}' habilitado no config.json."
        RestartingSteam       = "Reiniciando Steam para carregar o plugin..."
        SendingEnableCmd      = "Enviando comando para habilitar o plugin no Millennium..."
        OkEnableCmdSent       = "Comando de habilitação enviado ao Millennium."
        FinalSuccess          = "Luatools instalado/atualizado e habilitado!"
        InstallingSteamTools  = "Abrindo nova janela do PowerShell para instalar/atualizar o SteamTools..."
        OkSteamToolsLaunched  = "SteamTools sendo instalado/atualizado na nova janela."
        PressEnterToExit      = "Pressione Enter para sair"
        ErrGeneric            = "Erro: {0}"
        WarnTempKept          = "Arquivos temporários mantidos em: {0}"
        RunAsAdminErr         = "Execute este instalador como Administrador. A pasta da Steam geralmente fica em Program Files."
        # Mensagens para a janela do SteamTools
        SteamToolsTitle       = "Instalação do SteamTools"
        SteamToolsWarning     = "AVISO: Este comando pode ser bloqueado por alguns antivírus. Certifique-se de que confia na origem (steam.run)."
        SteamToolsCommand     = "Comando a ser executado: irm steam.run | iex"
        SteamToolsAskExecute  = "Deseja executar o comando agora? (S/N)"
        SteamToolsExecuted    = "Comando executado. Aguarde a conclusão."
        SteamToolsCopyHint    = "Comando não foi executado. Copie o comando acima e execute manualmente em um PowerShell como Administrador quando desejar."
        SteamToolsError       = "Erro ao executar o comando: {0}"
    }
    "pt-PT" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "A procurar a pasta raiz da Steam..."
        ErrSteamNotFound      = "Steam não encontrada. Instale/abra a Steam pelo menos uma vez e tente novamente."
        OkSteamFound          = "Steam encontrada:"
        WarnMillenniumMissing = "Millennium não encontrado. A instalar pela última release do GitHub..."
        InfoMillenniumUpdate  = "Millennium encontrado. A atualizar diretamente pela última release do GitHub..."
        InfoFetchMillennium   = "A buscar a última release do Millennium no GitHub..."
        OkMillenniumRelease   = "Release do Millennium encontrada: {0}"
        Downloading           = "A baixar {0}..."
        Extracting            = "A extrair {0}..."
        CopyingMillennium     = "A copiar/atualizar ficheiros do Millennium na raiz da Steam..."
        WarnMillenniumFolder  = "Os ficheiros foram extraídos, mas a pasta 'millennium' não foi encontrada. Verifique se o asset da release mudou."
        OkMillenniumInstalled = "Millennium instalado/atualizado via GitHub."
        StoppingSteam         = "A fechar a Steam..."
        StartingSteam         = "A abrir a Steam novamente..."
        InfoFetchLuaTools     = "A buscar a última release do Luatools no GitHub..."
        OkLuaToolsRelease     = "Release do Luatools encontrada: {0}"
        RemovingOldPlugins    = "A remover plugins antigos/em conflito..."
        FolderRemoved         = "Pasta removida: {0}"
        InstallingLuaTools    = "A instalar Luatools..."
        OkLuaToolsInstalled   = "Luatools instalado em: {0}"
        EnablingPluginConfig  = "Plugin '{0}' ativado no config.json."
        RestartingSteam       = "A reiniciar a Steam para carregar o plugin..."
        SendingEnableCmd      = "A enviar comando para ativar o plugin no Millennium..."
        OkEnableCmdSent       = "Comando de ativação enviado ao Millennium."
        FinalSuccess          = "Luatools instalado/atualizado e ativado!"
        InstallingSteamTools  = "A abrir nova janela do PowerShell para instalar/atualizar o SteamTools..."
        OkSteamToolsLaunched  = "SteamTools a ser instalado/atualizado na nova janela."
        PressEnterToExit      = "Prima Enter para sair"
        ErrGeneric            = "Erro: {0}"
        WarnTempKept          = "Ficheiros temporários mantidos em: {0}"
        RunAsAdminErr         = "Execute este instalador como Administrador. A pasta da Steam geralmente fica em Program Files."
        SteamToolsTitle       = "Instalação do SteamTools"
        SteamToolsWarning     = "AVISO: Este comando pode ser bloqueado por alguns antivírus. Certifique-se de que confia na origem (steam.run)."
        SteamToolsCommand     = "Comando a executar: irm steam.run | iex"
        SteamToolsAskExecute  = "Deseja executar o comando agora? (S/N)"
        SteamToolsExecuted    = "Comando executado. Aguarde a conclusão."
        SteamToolsCopyHint    = "Comando não foi executado. Copie o comando acima e execute manualmente num PowerShell como Administrador quando desejar."
        SteamToolsError       = "Erro ao executar o comando: {0}"
    }
    "es" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "Buscando carpeta raíz de Steam..."
        ErrSteamNotFound      = "Steam no encontrada. Instala/abre Steam al menos una vez e inténtalo de nuevo."
        OkSteamFound          = "Steam encontrada:"
        WarnMillenniumMissing = "Millennium no encontrado. Instalando la última release desde GitHub..."
        InfoMillenniumUpdate  = "Millennium encontrado. Actualizando directamente desde la última release de GitHub..."
        InfoFetchMillennium   = "Buscando la última release de Millennium en GitHub..."
        OkMillenniumRelease   = "Release de Millennium encontrada: {0}"
        Downloading           = "Descargando {0}..."
        Extracting            = "Extrayendo {0}..."
        CopyingMillennium     = "Copiando/actualizando archivos de Millennium en la raíz de Steam..."
        WarnMillenniumFolder  = "Los archivos fueron extraídos, pero la carpeta 'millennium' no se encontró. Comprueba si el asset de la release cambió."
        OkMillenniumInstalled = "Millennium instalado/actualizado vía GitHub."
        StoppingSteam         = "Cerrando Steam..."
        StartingSteam         = "Abriendo Steam nuevamente..."
        InfoFetchLuaTools     = "Buscando la última release de Luatools en GitHub..."
        OkLuaToolsRelease     = "Release de Luatools encontrada: {0}"
        RemovingOldPlugins    = "Eliminando plugins antiguos/conflictivos..."
        FolderRemoved         = "Carpeta eliminada: {0}"
        InstallingLuaTools    = "Instalando Luatools..."
        OkLuaToolsInstalled   = "Luatools instalado en: {0}"
        EnablingPluginConfig  = "Plugin '{0}' habilitado en config.json."
        RestartingSteam       = "Reiniciando Steam para cargar el plugin..."
        SendingEnableCmd      = "Enviando comando para habilitar el plugin en Millennium..."
        OkEnableCmdSent       = "Comando de habilitación enviado a Millennium."
        FinalSuccess          = "¡Luatools instalado/actualizado y habilitado!"
        InstallingSteamTools  = "Abriendo nueva ventana de PowerShell para instalar/actualizar SteamTools..."
        OkSteamToolsLaunched  = "SteamTools se está instalando/actualizando en la nueva ventana."
        PressEnterToExit      = "Presiona Enter para salir"
        ErrGeneric            = "Error: {0}"
        WarnTempKept          = "Archivos temporales mantenidos en: {0}"
        RunAsAdminErr         = "Ejecuta este instalador como Administrador. La carpeta de Steam suele estar en Program Files."
        SteamToolsTitle       = "Instalación de SteamTools"
        SteamToolsWarning     = "ADVERTENCIA: Este comando puede ser bloqueado por algunos antivirus. Asegúrate de confiar en el origen (steam.run)."
        SteamToolsCommand     = "Comando a ejecutar: irm steam.run | iex"
        SteamToolsAskExecute  = "¿Deseas ejecutar el comando ahora? (S/N)"
        SteamToolsExecuted    = "Comando ejecutado. Espera a que termine."
        SteamToolsCopyHint    = "El comando no se ejecutó. Copia el comando de arriba y ejecútalo manualmente en PowerShell como Administrador cuando quieras."
        SteamToolsError       = "Error al ejecutar el comando: {0}"
    }
    "en" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "Looking for Steam root folder..."
        ErrSteamNotFound      = "Steam not found. Please install/run Steam at least once and try again."
        OkSteamFound          = "Steam found at:"
        WarnMillenniumMissing = "Millennium not found. Installing from latest GitHub release..."
        InfoMillenniumUpdate  = "Millennium found. Updating directly from latest GitHub release..."
        InfoFetchMillennium   = "Fetching latest Millennium release from GitHub..."
        OkMillenniumRelease   = "Millennium release found: {0}"
        Downloading           = "Downloading {0}..."
        Extracting            = "Extracting {0}..."
        CopyingMillennium     = "Copying/updating Millennium files to Steam root..."
        WarnMillenniumFolder  = "Files were extracted, but 'millennium' folder was not found. Check if the release asset has changed."
        OkMillenniumInstalled = "Millennium installed/updated via GitHub."
        StoppingSteam         = "Closing Steam..."
        StartingSteam         = "Opening Steam again..."
        InfoFetchLuaTools     = "Fetching latest Luatools release from GitHub..."
        OkLuaToolsRelease     = "Luatools release found: {0}"
        RemovingOldPlugins    = "Removing old/conflicting plugins..."
        FolderRemoved         = "Folder removed: {0}"
        InstallingLuaTools    = "Installing Luatools..."
        OkLuaToolsInstalled   = "Luatools installed at: {0}"
        EnablingPluginConfig  = "Plugin '{0}' enabled in config.json."
        RestartingSteam       = "Restarting Steam to load the plugin..."
        SendingEnableCmd      = "Sending command to enable plugin in Millennium..."
        OkEnableCmdSent       = "Enable command sent to Millennium."
        FinalSuccess          = "Luatools installed/updated and enabled!"
        InstallingSteamTools  = "Opening new PowerShell window to install/update SteamTools..."
        OkSteamToolsLaunched  = "SteamTools is being installed/updated in the new window."
        PressEnterToExit      = "Press Enter to exit"
        ErrGeneric            = "Error: {0}"
        WarnTempKept          = "Temporary files kept at: {0}"
        RunAsAdminErr         = "Run this installer as Administrator. Steam folder is usually in Program Files."
        SteamToolsTitle       = "SteamTools Installation"
        SteamToolsWarning     = "WARNING: This command might be blocked by some antivirus. Make sure you trust the source (steam.run)."
        SteamToolsCommand     = "Command to run: irm steam.run | iex"
        SteamToolsAskExecute  = "Do you want to execute the command now? (Y/N)"
        SteamToolsExecuted    = "Command executed. Wait for completion."
        SteamToolsCopyHint    = "Command not executed. Copy the command above and run it manually in PowerShell as Administrator when ready."
        SteamToolsError       = "Error executing command: {0}"
    }
}

$text = $strings[$lang]

# ==================== FUNÇÕES COM TRADUÇÃO ====================
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[AVISO] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERRO] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Environment {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Err $text.RunAsAdminErr
        Write-Host ""
        Read-Host $text.PressEnterToExit
        exit 1
    }

    if (Test-Path $WorkRoot) {
        Remove-Item -Path $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $WorkRoot -ItemType Directory -Force | Out-Null
}

function Get-SteamPath {
    $candidates = New-Object System.Collections.Generic.List[string]

    $steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($steamProcess -and $steamProcess.Path) {
        $candidates.Add((Split-Path $steamProcess.Path -Parent))
    }

    $registryPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($registryPath in $registryPaths) {
        $reg = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
        if ($reg) {
            if ($reg.InstallPath) { $candidates.Add($reg.InstallPath) }
            if ($reg.SteamPath)   { $candidates.Add($reg.SteamPath) }
        }
    }

    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root

    foreach ($driveRoot in $drives) {
        $possiblePaths = @(
            (Join-Path $driveRoot "Program Files (x86)\Steam"),
            (Join-Path $driveRoot "Program Files\Steam"),
            (Join-Path $driveRoot "Steam")
        )

        foreach ($path in $possiblePaths) {
            $candidates.Add($path)
        }
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        $normalized = $candidate -replace "/", "\"
        if (Test-Path (Join-Path $normalized "steam.exe")) {
            return (Resolve-Path $normalized).Path
        }
    }

    return $null
}

function Invoke-GitHubApi {
    param([string]$Uri)

    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "LuatoolsInstaller"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing
}

function Get-LatestGitHubRelease {
    param([string]$Repo)

    return Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/latest"
}

function Select-ReleaseAsset {
    param(
        [Parameter(Mandatory=$true)]$Release,
        [Parameter(Mandatory=$true)][string[]]$NamePatterns,
        [Parameter(Mandatory=$true)][string]$FriendlyName
    )

    $assets = @($Release.assets)
    if (-not $assets -or $assets.Count -eq 0) {
        throw "A release $($Release.tag_name) de $FriendlyName nao possui assets para baixar."
    }

    foreach ($pattern in $NamePatterns) {
        $asset = $assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if ($asset) {
            return $asset
        }
    }

    $assetNames = ($assets | Select-Object -ExpandProperty name) -join ", "
    throw "Nao encontrei asset compativel para $FriendlyName. Assets encontrados: $assetNames"
}

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile
    )

    if (Test-Path $OutFile) {
        Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
    }

    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing

    if (-not (Test-Path $OutFile)) {
        throw "Falha ao baixar: $Url"
    }
}

function Stop-Steam {
    $steamProcesses = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    if ($steamProcesses) {
        Write-Info $text.StoppingSteam
        $steamProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
    }
}

function Start-SteamClient {
    param([string]$SteamPath)

    $steamExe = Join-Path $SteamPath "steam.exe"
    if (Test-Path $steamExe) {
        Start-Process -FilePath $steamExe
        Start-Sleep -Seconds 8
    }
}

function Restart-Steam {
    param([string]$SteamPath)

    Stop-Steam
    Write-Info $text.StartingSteam
    Start-SteamClient -SteamPath $SteamPath
}

function Get-CopySourceFromExtractedZip {
    param([string]$ExtractPath)

    $items = @(Get-ChildItem -Path $ExtractPath -Force)

    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        return $items[0].FullName
    }

    return $ExtractPath
}

function Install-OrUpdateMillenniumFromGitHub {
    param([string]$SteamPath)

    Write-Info $text.InfoFetchMillennium
    $release = Get-LatestGitHubRelease -Repo $MillenniumRepo
    Write-Ok ($text.OkMillenniumRelease -f $release.tag_name)

    $asset = Select-ReleaseAsset `
        -Release $release `
        -FriendlyName "Millennium" `
        -NamePatterns @(
            "millennium-*-windows-x86_64.zip",
            "*windows*x86_64*.zip",
            "*windows*.zip",
            "*.zip"
        )

    Write-Info ($text.Downloading -f $asset.name)
    Download-File -Url $asset.browser_download_url -OutFile $MillenniumZip

    if (Test-Path $MillenniumExtractTemp) {
        Remove-Item -Path $MillenniumExtractTemp -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $MillenniumExtractTemp -ItemType Directory -Force | Out-Null

    Write-Info ($text.Extracting -f "Millennium")
    Expand-Archive -Path $MillenniumZip -DestinationPath $MillenniumExtractTemp -Force

    $source = Get-CopySourceFromExtractedZip -ExtractPath $MillenniumExtractTemp

    Stop-Steam

    Write-Info $text.CopyingMillennium
    Copy-Item -Path (Join-Path $source "*") -Destination $SteamPath -Recurse -Force

    if (-not (Test-Path (Join-Path $SteamPath "millennium"))) {
        Write-Warn $text.WarnMillenniumFolder
    }

    Write-Ok $text.OkMillenniumInstalled
    Restart-Steam -SteamPath $SteamPath
}

function Enable-MillenniumPluginInConfig {
    param(
        [string]$ConfigFile,
        [string]$PluginId
    )

    $configDir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $config = $null

    if (Test-Path $ConfigFile) {
        $raw = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
        if ($raw.Trim().Length -gt 0) {
            $config = $raw | ConvertFrom-Json
        }
    }

    if (-not $config) {
        $config = [pscustomobject]@{
            general = [pscustomobject]@{
                accentColor = "DEFAULT_ACCENT_COLOR"
                checkForMillenniumUpdates = $true
                checkForPluginAndThemeUpdates = $true
                injectCSS = $true
                injectJavascript = $true
                millenniumUpdateChannel = "stable"
                onMillenniumUpdate = 1
                shouldShowThemePluginUpdateNotifications = $true
            }
            misc = [pscustomobject]@{
                hasShownWelcomeModal = $true
            }
            notifications = [pscustomobject]@{
                showNotifications = $true
                showPluginNotifications = $true
                showUpdateNotifications = $true
            }
            plugins = [pscustomobject]@{
                enabledPlugins = @()
            }
            themes = [pscustomobject]@{
                activeTheme = "default"
                allowedScripts = $true
                allowedStyles = $true
            }
        }
    }

    if ($config.PSObject.Properties.Name -notcontains "plugins") {
        $config | Add-Member -MemberType NoteProperty -Name "plugins" -Value ([pscustomobject]@{})
    }

    if ($config.plugins.PSObject.Properties.Name -notcontains "enabledPlugins") {
        $config.plugins | Add-Member -MemberType NoteProperty -Name "enabledPlugins" -Value @()
    }

    $enabled = @($config.plugins.enabledPlugins) | Where-Object { $_ }

    if ($enabled -notcontains $PluginId) {
        $enabled += $PluginId
    }

    $config.plugins.enabledPlugins = @($enabled | Select-Object -Unique)

    $json = $config | ConvertTo-Json -Depth 100
    Set-Content -Path $ConfigFile -Value $json -Encoding UTF8

    Write-Ok ($text.EnablingPluginConfig -f $PluginId)
}

function Install-LuaToolsLatest {
    param([string]$SteamPath)

    $pluginsRoot = Join-Path $SteamPath "millennium\plugins"
    $pluginDir = Join-Path $pluginsRoot $PluginFolderName
    $configFile = Join-Path $SteamPath "millennium\config\config.json"

    Stop-Steam

    if (-not (Test-Path $pluginsRoot)) {
        New-Item -Path $pluginsRoot -ItemType Directory -Force | Out-Null
    }

    Write-Info $text.InfoFetchLuaTools
    $release = Get-LatestGitHubRelease -Repo $LuaToolsRepo
    Write-Ok ($text.OkLuaToolsRelease -f $release.tag_name)

    $asset = Select-ReleaseAsset `
        -Release $release `
        -FriendlyName "Luatools" `
        -NamePatterns @(
            "ltsteamplugin.zip",
            "*ltsteamplugin*.zip",
            "*luatools*.zip",
            "*.zip"
        )

    Write-Info ($text.Downloading -f $asset.name)
    Download-File -Url $asset.browser_download_url -OutFile $PluginZip

    if (Test-Path $PluginExtractTemp) {
        Remove-Item -Path $PluginExtractTemp -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $PluginExtractTemp -ItemType Directory -Force | Out-Null

    Write-Info ($text.Extracting -f "Luatools")
    Expand-Archive -Path $PluginZip -DestinationPath $PluginExtractTemp -Force

    Write-Info $text.RemovingOldPlugins

    # ========== REMOÇÃO ADICIONAL: plugins antigos na raiz Steam\plugins ==========
    $legacyPluginsRoot = Join-Path $SteamPath "plugins"
    if (Test-Path $legacyPluginsRoot) {
        $legacyPluginDirs = @(
            (Join-Path $legacyPluginsRoot "itsteamplugin"),
            (Join-Path $legacyPluginsRoot "luatools"),
            (Join-Path $legacyPluginsRoot $PluginFolderName)
        )
        foreach ($dir in $legacyPluginDirs) {
            if (Test-Path $dir) {
                Remove-Item -Path $dir -Recurse -Force
                Write-Ok ($text.FolderRemoved -f $dir)
            }
        }
    }
    # =============================================================================

    # Remoção dentro da estrutura Millennium (já existente)
    $oldPluginDirs = @(
        (Join-Path $pluginsRoot "itsteamplugin"),
        (Join-Path $pluginsRoot "luatools"),
        $pluginDir
    )

    foreach ($dir in $oldPluginDirs) {
        if (Test-Path $dir) {
            Remove-Item -Path $dir -Recurse -Force
            Write-Ok ($text.FolderRemoved -f $dir)
        }
    }

    New-Item -Path $pluginDir -ItemType Directory -Force | Out-Null

    $source = Get-CopySourceFromExtractedZip -ExtractPath $PluginExtractTemp

    Write-Info $text.InstallingLuaTools
    Copy-Item -Path (Join-Path $source "*") -Destination $pluginDir -Recurse -Force

    Enable-MillenniumPluginInConfig -ConfigFile $configFile -PluginId $PluginId

    Write-Ok ($text.OkLuaToolsInstalled -f $pluginDir)
}

function Enable-PluginByProtocol {
    param([string]$SteamPath)

    Write-Info $text.RestartingSteam
    Restart-Steam -SteamPath $SteamPath

    Write-Info $text.SendingEnableCmd
    Start-Process "steam://millennium/settings/plugins/enable/$PluginId"
    Write-Ok $text.OkEnableCmdSent
}

function Install-SteamTools {
    Write-Info $text.InstallingSteamTools

    # Gera o script que será executado na nova janela, já no idioma correto
    $steamToolsScript = @"
`$ErrorActionPreference = "Continue"
`$lang = "$lang"

# Dicionário de mensagens para a janela secundária
`$steamText = `$null
if (`$lang -eq "pt-BR") {
    `$steamText = @{
        Title = "$($text.SteamToolsTitle)"
        Warning = "$($text.SteamToolsWarning)"
        Command = "$($text.SteamToolsCommand)"
        Ask = "$($text.SteamToolsAskExecute)"
        Executed = "$($text.SteamToolsExecuted)"
        CopyHint = "$($text.SteamToolsCopyHint)"
        ErrorMsg = "$($text.SteamToolsError)"
    }
} elseif (`$lang -eq "pt-PT") {
    `$steamText = @{
        Title = "$($text.SteamToolsTitle)"
        Warning = "$($text.SteamToolsWarning)"
        Command = "$($text.SteamToolsCommand)"
        Ask = "$($text.SteamToolsAskExecute)"
        Executed = "$($text.SteamToolsExecuted)"
        CopyHint = "$($text.SteamToolsCopyHint)"
        ErrorMsg = "$($text.SteamToolsError)"
    }
} elseif (`$lang -eq "es") {
    `$steamText = @{
        Title = "$($text.SteamToolsTitle)"
        Warning = "$($text.SteamToolsWarning)"
        Command = "$($text.SteamToolsCommand)"
        Ask = "$($text.SteamToolsAskExecute)"
        Executed = "$($text.SteamToolsExecuted)"
        CopyHint = "$($text.SteamToolsCopyHint)"
        ErrorMsg = "$($text.SteamToolsError)"
    }
} else {
    `$steamText = @{
        Title = "SteamTools Installation"
        Warning = "WARNING: This command might be blocked by some antivirus. Make sure you trust the source (steam.run)."
        Command = "Command to run: irm steam.run | iex"
        Ask = "Do you want to execute the command now? (Y/N)"
        Executed = "Command executed. Wait for completion."
        CopyHint = "Command not executed. Copy the command above and run it manually in PowerShell as Administrator when ready."
        ErrorMsg = "Error executing command: {0}"
    }
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " `$(`$steamText.Title) " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[AVISO] " -ForegroundColor Yellow -NoNewline
Write-Host `$steamText.Warning
Write-Host ""
Write-Host `$steamText.Command -ForegroundColor Cyan
Write-Host ""
`$choice = Read-Host `$steamText.Ask
if (`$choice -match '^[SsYy]$') {
    try {
        irm steam.run | iex
        Write-Host "[OK] " -ForegroundColor Green -NoNewline
        Write-Host `$steamText.Executed
    }
    catch {
        Write-Host "[ERRO] " -ForegroundColor Red -NoNewline
        Write-Host (`$steamText.ErrorMsg -f `$_.Exception.Message)
    }
} else {
    Write-Host "[INFO] " -ForegroundColor Yellow -NoNewline
    Write-Host `$steamText.CopyHint
}
Write-Host ""
Read-Host "Pressione Enter para fechar esta janela"
"@

    # Salva o script temporário
    $tempScript = Join-Path $env:TEMP "SteamToolsInstaller_$([System.Guid]::NewGuid().Guid).ps1"
    Set-Content -Path $tempScript -Value $steamToolsScript -Encoding UTF8

    # Abre nova janela do PowerShell executando o script temporário
    Start-Process powershell.exe -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$tempScript`""
    Write-Ok $text.OkSteamToolsLaunched
}

function Cleanup-InstallerFiles {
    foreach ($path in @($MillenniumZip, $MillenniumExtractTemp, $PluginZip, $PluginExtractTemp)) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ==================== VARIÁVEIS PRINCIPAIS ====================
$MillenniumRepo = "SteamClientHomebrew/Millennium"
$LuaToolsRepo  = "piqseu/ltsteamplugin"
$PluginFolderName = "ltsteamplugin"
$PluginId         = "luatools"
$WorkRoot = Join-Path $env:TEMP "LuatoolsInstaller"
$MillenniumZip = Join-Path $WorkRoot "millennium.zip"
$MillenniumExtractTemp = Join-Path $WorkRoot "millennium_extract"
$PluginZip = Join-Path $WorkRoot "ltsteamplugin.zip"
$PluginExtractTemp = Join-Path $WorkRoot "ltsteamplugin_extract"

# ==================== EXECUÇÃO PRINCIPAL ====================
try {
    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " $($text.InstallerTitle) " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    Initialize-Environment

    Write-Info $text.InfoSteamSearch
    $steamPath = Get-SteamPath

    if (-not $steamPath) {
        Write-Host ""
        Write-Err $text.ErrSteamNotFound
        Write-Host ""
        Read-Host $text.PressEnterToExit
        exit 1
    }

    Write-Ok $text.OkSteamFound
    Write-Host $steamPath -ForegroundColor Cyan
    Write-Host ""

    $millenniumPath = Join-Path $steamPath "millennium"

    if (Test-Path $millenniumPath) {
        Write-Info $text.InfoMillenniumUpdate
    }
    else {
        Write-Warn $text.WarnMillenniumMissing
    }

    Install-OrUpdateMillenniumFromGitHub -SteamPath $steamPath
    Install-LuaToolsLatest -SteamPath $steamPath
    Enable-PluginByProtocol -SteamPath $steamPath

    Cleanup-InstallerFiles

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host " $($text.FinalSuccess) " -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green

    Install-SteamTools

    Write-Host ""
    Read-Host $text.PressEnterToExit
}
catch {
    Write-Host ""
    Write-Err ($text.ErrGeneric -f $_.Exception.Message)
    Write-Host ""
    Write-Warn ($text.WarnTempKept -f $WorkRoot)
    Write-Host ""
    Read-Host $text.PressEnterToExit
    exit 1
}
