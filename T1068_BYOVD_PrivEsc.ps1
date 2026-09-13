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
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess,
        uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode,
        IntPtr lpInBuffer, uint nInBufferSize, IntPtr lpOutBuffer, uint nOutBufferSize,
        ref uint lpBytesReturned, IntPtr lpOverlapped);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr hObject);
}
'@ -ErrorAction SilentlyContinue

$handle = [DriverComm]::CreateFile("\\.\RTCore64", 0xC0000000, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($handle -ne [IntPtr]::new(-1)) {
    $bytesReturned = [uint32]0
    [DriverComm]::DeviceIoControl($handle, 0x80002048, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$bytesReturned, [IntPtr]::Zero) | Out-Null
    [DriverComm]::CloseHandle($handle) | Out-Null
}

& sc.exe delete $serviceName 2>$null | Out-Null
Remove-Item $driverPath -Force -ErrorAction SilentlyContinue
Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
