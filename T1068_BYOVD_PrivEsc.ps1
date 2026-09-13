$driverPath = "$env:TEMP\RTCore64.sys"
$serviceName = "RTCore64Svc"

$peHeader = [byte[]]@(0x4D, 0x5A) + (New-Object byte[] 510)
[System.IO.File]::WriteAllBytes($driverPath, $peHeader)

& sc.exe create $serviceName binPath= $driverPath type= kernel start= demand 2>&1 | Out-Null
& sc.exe start $serviceName 2>&1 | Out-Null

$regPath = "HKCU:\System\CurrentControlSet\Services\$serviceName"
New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $regPath -Name "ImagePath" -Value "\??\$driverPath" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path $regPath -Name "Type" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

if (-not ('DriverComm' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class DriverComm {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr CreateFile(string f, int a, int s, IntPtr sa, int d, int fl, IntPtr t);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool DeviceIoControl(IntPtr h, int c, IntPtr i, int ib, IntPtr o, int ob, ref int ret, IntPtr ov);
        [DllImport("kernel32.dll")]
        public static extern bool CloseHandle(IntPtr h);
    }
'@
}

$handle = [DriverComm]::CreateFile("\\.\RTCore64", 0x40000000, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($handle -ne [IntPtr]::new(-1) -and $handle -ne [IntPtr]::Zero) {
    $ret = 0
    [DriverComm]::DeviceIoControl($handle, 0x7FFF2048, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$ret, [IntPtr]::Zero) | Out-Null
    [DriverComm]::CloseHandle($handle) | Out-Null
}

& sc.exe delete $serviceName 2>$null | Out-Null
Remove-Item $driverPath -Force -ErrorAction SilentlyContinue
Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
