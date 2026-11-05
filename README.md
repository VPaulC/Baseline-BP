# Microsoft 365 Business Premium Security Baseline

This repository contains a deployment runbook and PowerShell helper script for Microsoft 365 Business Premium based on Microsoft and industry best practices. The script can configure Entra MFA protections, Defender for Business, sensitivity labels and DLP policies; review the operational warning below before selecting steps.

## Important deployment guidance

This script can make tenant-wide changes. Review the script and pilot each selected step in a test tenant or a controlled group before production. `-DryRun` and `-WhatIf` are previews, not substitutes for reviewing the requested scopes, policy content, licensing and expected impact.

**Do not enable Microsoft Entra Security Defaults and Conditional Access policies at the same time.** They are mutually exclusive. The script's full sequence (`-RunAllSteps`) attempts both `-EnableSecurityDefaults` and `-CreateMfaPolicy`, and the script runs the full sequence when no step switches are supplied. Choose one MFA approach for the tenant; do not use `-RunAllSteps` or omit step switches. For a tenant using Conditional Access, select the reviewed steps you need and exclude `-EnableSecurityDefaults`. For a tenant using Security Defaults, exclude `-CreateMfaPolicy`.

## The Complete Baseline

The script deploys the following security components:

1. **Choose one Entra MFA approach:** Microsoft Entra Security Defaults *or* a Conditional Access MFA policy (with break-glass exclusions); never both.
2. **Defender for Business Security Baseline** – Configure Windows Defender, Firewall, SmartScreen, and Application Guard
3. **Defender Policies** – Device compliance and endpoint protection policies via Intune
4. **Sensitivity Labels** – Create and publish custom sensitivity labels (General, Internal, Confidential) to all users
5. **DLP Policies** – Configure the repository's proposed Copilot and external-sharing protections; validate current service support and policy behavior before enforcement
6. **Legacy Auth Review** – Checklist and commands to validate authentication posture

This approach keeps the tenant secure quickly while leaving room for formal design review and pilot validation.

## PowerShell Deployment

### Windows MSI Installer

The x64, per-machine MSI installs this README and the deployment script
under `C:\Program Files\M365 BP Baseline`, with Start menu shortcuts for the
documentation and a PowerShell console. **Installation does not sign in, install
Graph modules, or apply any tenant policies.** The console shortcut only opens
PowerShell in the installation directory; run the script explicitly using the
examples below.

Install x64 PowerShell 7 first in its standard
`C:\Program Files\PowerShell\7` location. The MSI requires administrator elevation
and checks for this prerequisite; it does not download or install PowerShell.
Microsoft Graph modules are still managed by the deployment script when you run it.

Download `M365-BP-Baseline-1.0.0-x64.msi` from the
`M365-BP-Baseline-1.0.0-x64` artifact of a successful **Windows installer** run
on the repository's Actions tab. Unzip the artifact before installing. Artifacts
are retained for 90 days; the workflow can also be run manually to rebuild them.
These builds are unsigned; follow your organization's software approval policy.

For managed deployment, run these commands from an elevated terminal:

```powershell
msiexec.exe /i "M365-BP-Baseline-1.0.0-x64.msi" /qn /norestart /L*v "$env:TEMP\m365-bp-install.log"
msiexec.exe /x "M365-BP-Baseline-1.0.0-x64.msi" /qn /norestart /L*v "$env:TEMP\m365-bp-uninstall.log"
```

Exit codes `0` and `3010` mean success (the latter requests a restart). Uninstall
removes installed files and shortcuts, **not** tenant policies, Graph modules,
or PowerShell. The installed directory is read-only to standard users. To use
`-StartTranscript`, first copy the script to a user-writable directory because
the deployment script writes transcripts alongside itself.

To build locally on Windows, install the .NET 8 SDK and x64 PowerShell 7, then run:

```powershell
pwsh -NoProfile -File .\installer\build.ps1
# On a clean test machine, in an elevated PowerShell 7 session:
.\installer\test.ps1 -MsiPath .\artifacts\M365-BP-Baseline-1.0.0-x64.msi
```

The build restores the pinned WiX tool and produces a self-contained MSI in
`artifacts`. Use `-Version major.minor.build` when building an update, and update
the workflow's package filename and artifact name to match. Keep the MSI upgrade
code unchanged: newer versions replace older installations, and downgrades are
blocked. CI verifies payload integrity, shortcuts, offline script execution,
repair, and complete uninstallation without connecting to Microsoft 365.

Run this from PowerShell 7+ (or Windows PowerShell) as an appropriately privileged administrator, or with a service principal that has the required Graph consents. Required roles vary by step: Conditional Access, Intune/Defender, sensitivity labels and DLP each require their own administrative roles and consent. The role examples are not interchangeable guarantees that every step will succeed.

The script supports:
- `-WhatIf/-Confirm` for ShouldProcess simulation
- `-DryRun` switch for non-destructive testing
- `-StartTranscript` for audit logging
- `-Verbose` for detailed operation tracking

### Quick Start Examples

**Run the offline legacy-auth review only (no sign-in or tenant changes):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -ReviewLegacyAuth -SkipGraphConnection -DryRun -Verbose
```

**Create only the Conditional Access MFA policy (after choosing Conditional Access instead of Security Defaults):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -TenantId "contoso.onmicrosoft.com" `
  -BreakGlassUsers "breakglass1@contoso.com","breakglass2@contoso.com" `
  -CreateMfaPolicy -Verbose
```

**Enable Security Defaults instead (do not also create a Conditional Access MFA policy):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -TenantId "contoso.onmicrosoft.com" -EnableSecurityDefaults -Verbose
```

**Run the Conditional Access step with a transcript for audit:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -TenantId "contoso.onmicrosoft.com" -CreateMfaPolicy -StartTranscript -Verbose
```

**Configure Defender and device compliance (review impact and licensing before deployment):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -DeployDefenderBaseline -ConfigureDefenderPolicies -Verbose
```

**Run the selected Conditional Access, Defender and label steps (Security Defaults is intentionally omitted):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -CreateMfaPolicy -DeployDefenderBaseline -ConfigureDefenderPolicies `
  -CreateSensitivityLabels -CreateDlpPolicies -ReviewLegacyAuth -Verbose
```

**Create and publish sensitivity labels:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -CreateSensitivityLabels -Verbose
```

**Create DLP policies:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -CreateSensitivityLabels -CreateDlpPolicies -Verbose
```

**Custom sensitivity label names:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -SensitivityLabelNames 'Public','Internal','Restricted' `
  -CreateSensitivityLabels -CreateDlpPolicies -Verbose
```

### Break-Glass Exclusions

The script accepts `-BreakGlassUsers` with UPNs or Azure AD object IDs. UPNs are automatically resolved to object IDs before the Conditional Access policy is created.

**Example:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -TenantId "<tenant-guid>" `
  -BreakGlassUsers "breakglass1@contoso.com","breakglass2@contoso.com" `
  -CreateMfaPolicy -Verbose
```

Keep the exclusion list very small and controlled. Do not exclude regular administrators, service accounts, or large groups unless you have a documented reason.

## Features in Detail

### Security Defaults
- Enables baseline protections in Entra ID
- Enforces MFA for admins and end users (configurable)
- Blocks legacy authentication protocols

### Conditional Access MFA Baseline
- Requires MFA for all users across all applications
- Applies to browser and mobile/desktop clients
- Excludes break-glass accounts (with strict controls)
- Policy name: `M365 BP Baseline - Require MFA for all users`

### Defender for Business Security Baseline
- **Windows Defender Configuration**
  - Real-time monitoring enabled
  - High cloud block level
  - Quick scan scheduled at 2:00 AM
  - Behavior monitoring enabled

- **Network & Application Protection**
  - Network protection enabled
  - Application Guard enabled with clipboard/file transfer blocking
  - SmartScreen enabled for shell and file overrides blocked

- **Firewall Configuration**
  - Windows Firewall enabled on all profiles (domain, private, public)
  - Inbound connections blocked by default
  - Outbound connections permitted

- **Exploit Protection**
  - Advanced Threat Protection enabled

### Defender Device Compliance Policy
- Requires Windows 10/11 version 19041+
- Defender enabled with latest signature updates
- 12-character passwords with 90-day expiration
- BitLocker encryption required
- Secure Boot enabled
- Device threat protection at medium level minimum
- Policy name: `M365 BP Baseline - Defender Device Compliance`

### Sensitivity Labels
Creates and publishes three customizable labels to all users:

| Label | Default Name | Color | Use Case |
|-------|--------------|-------|----------|
| Level 1 | General | Green | General use - no restrictions |
| Level 2 | Internal | Gold | Internal organizational use only |
| Level 3 | Confidential | Red | Highly sensitive - maximum protection |

Labels are available in:
- Microsoft Word, Excel, PowerPoint
- Outlook
- Microsoft Teams
- OneDrive & SharePoint
- Copilot (until restricted by DLP)

**Custom labels example:**
```powershell
-SensitivityLabelNames 'Public','Corporate','Secret'
```

### Data Loss Prevention (DLP) Policies

#### DLP Policy 1: Block Copilot from Confidential Content
- **Name:** `M365 BP Baseline - Block Copilot from Confidential Content`
- **Action:** Blocks Copilot from accessing, processing, or analyzing Confidential labeled content
- **Applies to:** Copilot in Teams, Microsoft 365 Chat, and other integrated experiences
- **Override:** Not allowed
- **Notification:** User receives notification when access is blocked

#### DLP Policy 2: Block External Sharing of Sensitive Labels
- **Name:** `M365 BP Baseline - Block External Sharing of Sensitive Labels`
- **Action:** Prevents sharing of Confidential or Internal labeled content with external users
- **Applies to:**
  - Email forwarding outside organization
  - OneDrive/SharePoint external link sharing
  - Teams external guest sharing
  - Cross-organizational access
- **Override:** Not allowed
- **Notification:** User receives notification with reason

## What the Script Does

- Verifies and optionally installs required Microsoft Graph PowerShell modules
- Connects to Microsoft Graph with minimal required scopes
- Enables Microsoft Entra security defaults **or** creates a Conditional Access policy requiring MFA for all users (choose one; do not run both)
- Deploys Defender for Business security baseline configuration
- Creates and publishes device compliance and endpoint protection policies
- Creates sensitivity labels with custom names
- Publishes labels to all users across Microsoft 365 apps
- Creates DLP policies to protect sensitive content
- Prints legacy authentication review checklist and suggested commands

## Required Graph Scopes and Admin Consent

The script requests the following least-privilege scopes (typically requiring administrator consent):

| Scope | Purpose |
|-------|---------|
| `Policy.ReadWrite.ConditionalAccess` | Create/update Conditional Access policies |
| `Directory.Read.All` | Resolve user object IDs for break-glass exclusions |
| `DeviceManagementConfiguration.ReadWrite.All` | Deploy Defender baselines and device policies |
| `DeviceManagementManagedDevices.ReadWrite.All` | Manage Intune device compliance |
| `InformationProtection.ReadWrite.All` | Create and publish sensitivity labels |
| `DlpEvaluate.ReadWrite` | Create and manage DLP policies |

When using a service principal, ensure these scopes are granted via app registration and admin consent is granted for all requested permissions.

## Recommended Deployment Sequence

### Phase 1: Assessment (1-2 days)
1. Review the script in DryRun mode
2. Decide whether the tenant will use Security Defaults or Conditional Access MFA; never enable both.
3. Identify and validate break-glass accounts and exclusions.
4. Check for legacy authentication usage and verify Defender agent deployment status.

### Phase 2: Pilot (1-2 weeks)
1. Run the script on a pilot tenant or group
2. Monitor sign-in logs for 24-48 hours
3. Test Defender policies on sample devices
4. Validate sensitivity label availability in client apps
5. Test DLP policies with non-critical content

### Phase 3: Production Rollout
1. Confirm pilot validation successful
2. Run only the reviewed step switches for production; select Security Defaults or Conditional Access MFA, never both
3. Monitor policy compliance dashboard
4. Watch DLP policy violation reports
5. Validate device compliance across managed devices

### Phase 4: Hardening
1. Block legacy authentication after client verification
2. Enable additional Conditional Access policies as needed
3. Tune DLP policies based on violation patterns
4. Implement additional device security settings

## Useful Commands

### Validate Conditional Access
```powershell
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess","Directory.Read.All"
Get-MgIdentityConditionalAccessPolicy | Format-Table DisplayName, State
Get-MgContext
```

### Check Defender/Intune Policies
```powershell
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"
Get-MgDeviceManagementDeviceConfiguration | Format-Table DisplayName
Get-MgDeviceManagementDeviceCompliancePolicy | Format-Table DisplayName
```

### Verify Sensitivity Labels
```powershell
Connect-MgGraph -Scopes "InformationProtection.ReadWrite.All"
Invoke-MgGraphRequest -Method GET `
  -Uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels'
```

### Check DLP Policies
```powershell
Connect-MgGraph -Scopes "DlpEvaluate.ReadWrite"
Invoke-MgGraphRequest -Method GET `
  -Uri 'https://graph.microsoft.com/beta/security/dataLossPreventionPolicies'
```

### Exchange/Legacy Auth Checks
```powershell
Connect-ExchangeOnline
Get-AuthenticationPolicy
Get-OrganizationConfig | Select-Object IsLegacyAuthProtocolsEnabled
```

### Review Sign-In Logs
```powershell
Get-MgAuditActivitySignIns -Top 50
Get-MgReportAuthenticationMethodsUserRegistrationDetail
```

## Troubleshooting

### Module Installation Issues
If `Ensure-RequiredModule` fails, ensure the Microsoft PowerShell Gallery is accessible:
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Register-PSRepository -Default -Force
```

### Graph Connection Issues
Ensure you have sufficient admin privileges and required consent:
```powershell
Connect-MgGraph -Scopes @(
  'Policy.ReadWrite.ConditionalAccess',
  'Directory.Read.All',
  'DeviceManagementConfiguration.ReadWrite.All',
  'DeviceManagementManagedDevices.ReadWrite.All',
  'InformationProtection.ReadWrite.All',
  'DlpEvaluate.ReadWrite'
) -ErrorAction Stop
```

### DLP Policy Creation Failures
- Ensure you have Compliance Admin or Global Admin role
- Verify sensitivity labels are created before creating DLP policies
- Check that label names match exactly (case-sensitive)

### Sensitivity Label Not Appearing in Apps
- Labels may take 24 hours to appear in Office clients
- Refresh Office apps or restart them
- Verify labels are published (not in draft)
- Check that Office 365 AIP client is up to date

## Notes

- This is a starter baseline and not a substitute for a formal risk assessment
- Always pilot changes before enforcing globally
- The account running the script needs sufficient Graph privileges (see scopes above)
- For service principal execution, pre-grant all required scopes via app registration
- Monitor compliance and violation reports regularly
- Update DLP policies based on organizational needs and pilot feedback
- Keep break-glass accounts minimal and regularly tested for access
