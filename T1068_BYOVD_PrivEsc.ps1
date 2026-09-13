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

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class DriverComm {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr CreateFile(string lpFileName, int dwDesiredAccess,
        int dwShareMode, IntPtr lpSecurityAttributes, int dwCreationDisposition,
        int dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, int dwIoControlCode,
        IntPtr lpInBuffer, int nInBufferSize, IntPtr lpOutBuffer, int nOutBufferSize,
        ref int lpBytesReturned, IntPtr lpOverlapped);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@ -ErrorAction SilentlyContinue

$INVALID_HANDLE = [IntPtr]::new(-1)
$handle = [DriverComm]::CreateFile("\\.\RTCore64", [int]0x40000000, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($handle -ne $INVALID_HANDLE -and $handle -ne [IntPtr]::Zero) {
    $bytesReturned = 0
    [DriverComm]::DeviceIoControl($handle, [int]0x7FFF2048, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$bytesReturned, [IntPtr]::Zero) | Out-Null
    [DriverComm]::CloseHandle($handle) | Out-Null
}

& sc.exe delete $serviceName 2>$null | Out-Null
Remove-Item $driverPath -Force -ErrorAction SilentlyContinue
Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
