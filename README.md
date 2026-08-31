# Microsoft 365 Business Premium Security Baseline

This repository contains a comprehensive deployment runbook and a PowerShell helper script for Microsoft 365 Business Premium based on Microsoft and industry best practices. The script enables security defaults, Conditional Access MFA, Defender for Business, Sensitivity Labels, and Data Loss Prevention (DLP) policies.

## The Complete Baseline

The script deploys the following security components:

1. **Microsoft Entra Security Defaults** – Enable baseline security protections
2. **Conditional Access MFA Policy** – Require MFA for all users (with break-glass exclusions)
3. **Defender for Business Security Baseline** – Configure Windows Defender, Firewall, SmartScreen, and Application Guard
4. **Defender Policies** – Device compliance and endpoint protection policies via Intune
5. **Sensitivity Labels** – Create and publish custom sensitivity labels (General, Internal, Confidential) to all users
6. **DLP Policies** – Prevent Copilot from accessing Confidential content and block external sharing of sensitive labels
7. **Legacy Auth Review** – Checklist and commands to validate authentication posture

This approach keeps the tenant secure quickly while leaving room for formal design review and pilot validation.

## PowerShell Deployment

Run this from PowerShell 7+ (or Windows PowerShell) as a Global Administrator, Security Administrator, or Compliance Administrator, or with a service principal that has the required Graph consents.

The script supports:
- `-WhatIf/-Confirm` for ShouldProcess simulation
- `-DryRun` switch for non-destructive testing
- `-StartTranscript` for audit logging
- `-Verbose` for detailed operation tracking

### Quick Start Examples

**Preview all changes (no modifications):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -RunAllSteps -DryRun -Verbose
```

**Preview using PowerShell's WhatIf/Confirm:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -RunAllSteps -WhatIf -Verbose
```

**Run everything (interactive sign-in):**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -TenantId "contoso.onmicrosoft.com" -RunAllSteps -Verbose
```

**Run with transcript for audit:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 -RunAllSteps -StartTranscript -Verbose
```

**Deploy only MFA and security defaults:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -EnableSecurityDefaults -CreateMfaPolicy -Verbose
```

**Deploy Defender and device compliance:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-m365-bp-baseline.ps1 `
  -DeployDefenderBaseline -ConfigureDefenderPolicies -Verbose
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
  -RunAllSteps -Verbose
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
- Enables Microsoft Entra security defaults (via Graph)
- Creates a Conditional Access policy requiring MFA for all users
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
2. Identify break-glass accounts
3. Check for legacy authentication usage
4. Verify Defender agent deployment status

### Phase 2: Pilot (1-2 weeks)
1. Run the script on a pilot tenant or group
2. Monitor sign-in logs for 24-48 hours
3. Test Defender policies on sample devices
4. Validate sensitivity label availability in client apps
5. Test DLP policies with non-critical content

### Phase 3: Production Rollout
1. Confirm pilot validation successful
2. Run the script with full `-RunAllSteps` for production
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
