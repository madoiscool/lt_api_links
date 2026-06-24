# LuaTools Validator bootstrap with auto-WARP recovery.
#
# This is a self-contained wrapper meant to be PASTED INLINE into PowerShell.
# It does NOT need to be downloaded — putting it on Vercel does not help users
# who are seeing the TLS failure (Vercel itself is the blocked target).
#
# Usage (copy the whole block into PowerShell as Administrator):
#
#   [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
#   $LuaToolsInstallOnly=1
#   <<paste the rest of this file>>
#
# Flow:
#   1. Try `irm luatools.vercel.app/LuaToolsValidator.ps1 | iex`
#   2. On TLS / connection error, auto-install Cloudflare WARP silently
#   3. Connect WARP
#   4. Retry the install
#   5. Fall back to the FAQ link only if WARP recovery itself fails

# Enable TLS 1.2 defensively. The numeric 3072 = Tls12 bit; using it instead of
# the enum name avoids the "Cannot convert value Tls12" error on very old
# PowerShell installs (.NET < 4.5) where the enum value doesn't exist. Wrapped
# in try/catch so even an OS that can't OR-in the bit doesn't bomb line 1.
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Host '[LuaTools] This PowerShell is too old to enable TLS 1.2. Update Windows / .NET 4.5+ and retry.' -ForegroundColor Red
        return
    }
}
if (-not $LuaToolsInstallOnly -and -not $AppID) { $LuaToolsInstallOnly = 1 }
$LuaToolsUrl = 'https://luatools.vercel.app/LuaToolsValidator.ps1'
$WarpCli     = 'C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe'
$WarpMsiUrl  = 'https://1.1.1.1/Cloudflare_WARP_Release-x64.msi'
$DocsUrl     = 'https://ltdocs.waike.dev/docs/luatools/faq/powershell-error'

function Test-LuaToolsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-LuaToolsValidator {
    Invoke-RestMethod -Uri $LuaToolsUrl | Invoke-Expression
}

function Install-CloudflareWarp {
    if (-not (Test-LuaToolsAdmin)) {
        Write-Host '[LuaTools] WARP install needs admin. Right-click PowerShell -> Run as Administrator, then re-run.' -ForegroundColor Red
        return $false
    }
    if (-not (Test-Path $WarpCli)) {
        $msi = Join-Path $env:TEMP 'cf_warp.msi'
        Write-Host '[LuaTools] Downloading Cloudflare WARP (one-time, ~30 MB)...' -ForegroundColor Yellow
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $WarpMsiUrl -OutFile $msi -TimeoutSec 180 -ErrorAction Stop
        } catch {
            Write-Host "[LuaTools] WARP download failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        Write-Host '[LuaTools] Installing WARP silently (no UI, ~30 seconds)...' -ForegroundColor Yellow
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart ACCEPT_TOS=1" -Wait -PassThru
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
        if ($proc.ExitCode -ne 0 -or -not (Test-Path $WarpCli)) {
            Write-Host "[LuaTools] WARP install failed (exit $($proc.ExitCode))." -ForegroundColor Red
            return $false
        }
        Write-Host '[LuaTools] WARP installed.' -ForegroundColor Green
    } else {
        Write-Host '[LuaTools] WARP already installed, reusing.' -ForegroundColor Yellow
    }
    Write-Host '[LuaTools] Registering WARP device...' -ForegroundColor Yellow
    & $WarpCli registration new 2>$null | Out-Null
    Write-Host '[LuaTools] Connecting WARP...' -ForegroundColor Yellow
    & $WarpCli connect 2>$null | Out-Null
    Start-Sleep -Seconds 5
    $status = (& $WarpCli status 2>$null) -join ' '
    if ($status -match 'Connected') {
        Write-Host '[LuaTools] WARP is connected.' -ForegroundColor Green
        return $true
    }
    Write-Host "[LuaTools] WARP did not connect (status: $status). Open the Cloudflare WARP system-tray icon and click Connect, then re-run." -ForegroundColor Red
    return $false
}

try {
    Invoke-LuaToolsValidator
} catch {
    $err = $_.Exception.Message
    $isTlsLike = $err -match 'underlying connection|WebException|operation timed out|unable to connect|Could not establish trust|SSL|TLS|aborted|name not resolved'
    if (-not $isTlsLike) { throw }

    Write-Host "[LuaTools] Connection to luatools.vercel.app failed: $err" -ForegroundColor Yellow
    Write-Host '[LuaTools] Auto-installing Cloudflare WARP to bypass the network issue and retrying...' -ForegroundColor Yellow

    if (Install-CloudflareWarp) {
        Start-Sleep -Seconds 2
        try {
            Invoke-LuaToolsValidator
        } catch {
            Write-Host "[LuaTools] Still failing after WARP: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[LuaTools] Manual fix walkthrough: $DocsUrl" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[LuaTools] WARP setup did not complete. Manual fix: $DocsUrl" -ForegroundColor Cyan
    }
}
