$monDll = "$env:TEMP\evilmon.dll"
$pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 2044)
try { [System.IO.File]::WriteAllBytes($monDll, $pe) } catch {}
try { Copy-Item $monDll "$env:SYSTEMROOT\System32\evilmon.dll" -Force -ErrorAction Stop } catch {}

$monKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EvilMonitor"
try {
    New-Item -Path $monKey -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $monKey -Name "Driver" -Value "evilmon.dll" -PropertyType String -Force -ErrorAction Stop | Out-Null
} catch {}

& net.exe stop spooler 2>&1 | Out-Null
& net.exe start spooler 2>&1 | Out-Null

if (-not ('PortMon' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class PortMon {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        public struct MONITOR_INFO_2 { public string pName; public string pEnvironment; public string pDLLName; }
        [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool AddMonitor(string server, int level, ref MONITOR_INFO_2 info);
        [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool DeleteMonitor(string server, string env, string name);
    }
'@
}

$mi = New-Object PortMon+MONITOR_INFO_2
$mi.pName = "EvilPortMon"
$mi.pEnvironment = "Windows x64"
$mi.pDLLName = "evilmon.dll"
[PortMon]::AddMonitor($null, 2, [ref]$mi) | Out-Null
[PortMon]::DeleteMonitor($null, $null, "EvilPortMon") | Out-Null

Remove-Item $monKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $monDll,"$env:SYSTEMROOT\System32\evilmon.dll" -Force -ErrorAction SilentlyContinue
