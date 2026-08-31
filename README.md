# Microsoft 365 Business Premium Security Baseline

This repository contains a four-step deployment runbook for Microsoft 365 Business Premium based on Microsoft and industry best practice.

## The 4-step baseline

1. Connect to Microsoft Graph with a privileged admin account.
2. Enable Microsoft Entra security defaults.
3. Create a Conditional Access baseline requiring MFA for all users.
4. Review and remediate legacy authentication, sign-in risks, and admin exceptions.

This approach keeps the tenant secure quickly while leaving room for a formal design review and pilot validation.

## PowerShell deployment

Run this from Windows PowerShell or PowerShell 7 as a Global Administrator or Security Administrator:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -TenantId "<tenant-guid>"
```

If you do not know the tenant ID, leave it out and the script will sign in interactively:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1
```

## What the script does

- Verifies the required Microsoft Graph modules are available
- Connects to Microsoft Graph with the required scopes
- Enables Microsoft Entra security defaults
- Creates a Conditional Access policy that requires MFA for all users
- Lists the legacy auth and sign-in review actions needed before final rollout

## Break-glass account exclusions

Best practice is to create at least one, and usually two, emergency accounts that are used only for disaster recovery. These accounts should be excluded from the broad MFA baseline only when absolutely necessary.

Example:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -TenantId "<tenant-guid>" `
  -BreakGlassUsers "breakglass1@contoso.com","breakglass2@contoso.com"
```

Keep the exclusion list very small and controlled. Do not exclude regular administrators, service accounts, or large groups unless you have a documented reason.

## Recommended best-practice review sequence

1. Review existing Conditional Access policies and exclude only break-glass accounts that truly require it.
2. Enable security defaults or the stronger MFA CA policy in a pilot group first.
3. Monitor sign-in logs for MFA fatigue, impossible travel, or risky sign-ins.
4. Block legacy auth clients and verify Exchange Online is not allowing basic authentication for legacy clients.
5. Validate Intune compliance and endpoint protection for all managed devices.
6. Confirm that no service accounts, helpdesk accounts, or shared mailbox scenarios are broken before broad enforcement.

## Useful commands

```powershell
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.ReadWrite.All","User.Read.All"
Get-MgIdentityConditionalAccessPolicy | Format-Table DisplayName, State
Get-MgContext
```

```powershell
Connect-ExchangeOnline
Get-AuthenticationPolicy
Get-OrganizationConfig | Select-Object IsLegacyAuthProtocolsEnabled
```

## More secure baseline recommendations

- Require MFA for all users and admins.
- Keep at least one emergency break-glass admin account outside normal admin workflow.
- Avoid broad exclusion rules in Conditional Access.
- Review and remove stale service principals and legacy app registrations.
- Ensure Intune device compliance is enforced for Windows devices.
- Validate sign-in risk and security alerts after 24–48 hours.

## Notes

- This is a sensible starter baseline, not a substitute for a formal risk assessment.
- Some tenant configurations may already have custom policies that change the recommended order.
- Always pilot first with a subset of users before enforcing globally.
