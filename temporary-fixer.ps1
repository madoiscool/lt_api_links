$steamPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) { $steamPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath }
$loginUsersPath = Join-Path $steamPath "config\loginusers.vdf"
if (Test-Path $loginUsersPath) {
    $content = Get-Content -Path $loginUsersPath -Raw
    if ($content -match '"WantsOfflineMode"\s+"1"') {
        $newContent = $content -replace '("WantsOfflineMode"\s+)"1"', '$1"0"'
        Set-Content -Path $loginUsersPath -Value $newContent -Encoding UTF8
    }
}

iex "& { $(irm 'https://clemdotla.github.io/millennium-installer-ps1/millennium.ps1') } -DontStart"
irm "https://luatools.vercel.app/st.ps1" | iex
