# Microsoft 365 Business Premium Security Baseline

This repository contains a four-step deployment runbook and a PowerShell helper script for Microsoft 365 Business Premium based on Microsoft and industry best practice.

## The 4-step baseline

1. Connect to Microsoft Graph with a privileged admin account (or a service principal with the required consents).
2. Enable Microsoft Entra security defaults (or the equivalent Conditional Access controls).
3. Create a Conditional Access baseline requiring MFA for all users.
4. Review and remediate legacy authentication, sign-in risks, and admin exceptions.

This approach keeps the tenant secure quickly while leaving room for a formal design review and pilot validation.

## PowerShell deployment

Run this from PowerShell 7+ (or Windows PowerShell) as a Global Administrator or Security Administrator, or with a service principal that has the required Graph consents.

The improved script supports -WhatIf/-Confirm (SupportsShouldProcess), a -DryRun switch for simulation, -StartTranscript to capture logs, and verbose output.

Examples:

Preview (no changes):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -RunAllSteps -DryRun -Verbose
```

Preview using PowerShell's WhatIf/Confirm support:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -RunAllSteps -WhatIf -Verbose
```

Run for real (interactive sign-in):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -TenantId "contoso.onmicrosoft.com" -RunAllSteps -Verbose
```

Start a transcript when running for audit purposes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -RunAllSteps -StartTranscript
```

Break-glass exclusions (UPNs or object IDs):

The script accepts -BreakGlassUsers with UPNs or Azure AD object IDs. UPNs are automatically resolved to object IDs before the Conditional Access policy is created. Example:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -TenantId "<tenant-guid>" `
  -BreakGlassUsers "breakglass1@contoso.com","breakglass2@contoso.com" `
  -RunAllSteps -Verbose
```

Keep the exclusion list very small and controlled. Do not exclude regular administrators, service accounts, or large groups unless you have a documented reason.

## What the script does

- Verifies and (optionally) installs required Microsoft Graph PowerShell modules.
- Connects to Microsoft Graph with the minimal scopes required for the operations below.
- Enables Microsoft Entra security defaults (via Graph) when requested.
- Creates a Conditional Access policy requiring MFA for all users (with optional break-glass exclusions).
- Prints a legacy authentication review checklist and suggested commands to investigate sign-in logs.

## Minimal Graph scopes and admin consent

The script requests the following least-privilege scopes for its operations (these typically require administrator consent):

- Policy.ReadWrite.ConditionalAccess — create or update Conditional Access policies
- Directory.Read.All — resolve user object IDs for break-glass exclusions

If you need to run additional device-management steps, the script may request further device scopes; check the script header for the exact scopes it uses. When using a service principal, ensure the app has the above delegated or application permissions and admin consent.

## Useful commands

Quick checks and troubleshooting:

```powershell
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess","Directory.Read.All"
Get-MgIdentityConditionalAccessPolicy | Format-Table DisplayName, State
Get-MgContext
```

Exchange/legacy auth checks:

```powershell
Connect-ExchangeOnline
Get-AuthenticationPolicy
Get-OrganizationConfig | Select-Object IsLegacyAuthProtocolsEnabled
```

Sign-in logs sampling:

```powershell
Get-MgAuditActivitySignIns -Top 50
Get-MgReportAuthenticationMethodsUserRegistrationDetail
```

## Recommended best-practice review sequence

1. Review existing Conditional Access policies and confirm break-glass exclusions are minimal.
2. Run the script in DryRun or WhatIf mode to validate actions.
3. Enable security defaults or the MFA CA policy in a pilot group first.
4. Monitor sign-in logs for 24–48 hours and look for unexpected failures or risky sign-ins.
5. Block legacy authentication only after verifying client compatibility and Exchange settings.
6. Validate Intune device compliance and endpoint protection for managed devices.
7. Confirm service accounts, helpdesk accounts, and automation flows are not broken before broad enforcement.

## Notes

- This is a starter baseline and not a substitute for a formal risk assessment.
- Always pilot changes before enforcing globally.
- The account running the script needs sufficient Graph privileges (see scopes above) or use a service principal with admin consent.
