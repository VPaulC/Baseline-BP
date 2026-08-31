<#
.SYNOPSIS
    Deploy M365 baseline: enable security defaults, create a Conditional Access MFA baseline, configure Defender for Business, manage sensitivity labels, and create DLP policies.

.DESCRIPTION
    This script connects to Microsoft Graph, optionally enables Entra security defaults, creates
    a Conditional Access policy to require MFA for users, configures Microsoft Defender for Business
    security baselines and policies, creates/publishes sensitivity labels, and deploys Data Loss Prevention
    policies. It supports -WhatIf/-Confirm and verbose output.

.PARAMETER TenantId
    Optional tenant id to connect to.

.PARAMETER BreakGlassUsers
    Array of user UPNs (or object IDs). UPNs will be resolved to object IDs automatically.

.PARAMETER SkipGraphConnection
    Skip connecting to Microsoft Graph (useful for dry-run or reviewing code).

.PARAMETER EnableSecurityDefaults
    Enable Entra security defaults.

.PARAMETER CreateMfaPolicy
    Create Conditional Access policy requiring MFA.

.PARAMETER ReviewLegacyAuth
    Output review checklist for legacy authentication.

.PARAMETER DeployDefenderBaseline
    Deploy Defender for Business security baseline.

.PARAMETER ConfigureDefenderPolicies
    Configure Defender for Business endpoint protection and device compliance policies.

.PARAMETER SensitivityLabelNames
    Array of three sensitivity label names to create and publish (e.g., 'Internal', 'Confidential', 'Restricted').
    If not specified, defaults to: 'General', 'Internal', 'Confidential'.

.PARAMETER CreateSensitivityLabels
    Create and publish sensitivity labels specified in -SensitivityLabelNames.

.PARAMETER CreateDlpPolicies
    Create Data Loss Prevention policies (Copilot blocking and external sharing restriction).

.PARAMETER RunAllSteps
    Run all steps (same as specifying all step switches).

.PARAMETER DryRun
    When set, no changes will be made; operations that support ShouldProcess will be simulated.

.PARAMETER StartTranscript
    When set, capture a transcript of the session to a timestamped log file.

.EXAMPLE
    .\deploy-m365-bp-baseline.ps1 -TenantId 'contoso.onmicrosoft.com' -BreakGlassUsers 'break@contoso.com' -RunAllSteps -Verbose

.EXAMPLE
    .\deploy-m365-bp-baseline.ps1 -SensitivityLabelNames 'Public', 'Internal', 'Secret' -CreateSensitivityLabels -CreateDlpPolicies -Verbose

.NOTES
    - Requires Microsoft.Graph modules. Script can install missing modules for current user.
    - Defender for Business configuration requires Intune admin rights.
    - Sensitivity label configuration requires Information Protection admin rights.
    - DLP policy creation requires Compliance admin rights.
    - Some Graph scopes require admin consent.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$|^.+\..+$')] # allow GUID or domain/tenant
    [string]$TenantId,

    [string[]]$BreakGlassUsers = @(),

    [string[]]$SensitivityLabelNames = @('General', 'Internal', 'Confidential'),

    [switch]$SkipGraphConnection,

    [switch]$EnableSecurityDefaults,

    [switch]$CreateMfaPolicy,

    [switch]$ReviewLegacyAuth,

    [switch]$DeployDefenderBaseline,

    [switch]$ConfigureDefenderPolicies,

    [switch]$CreateSensitivityLabels,

    [switch]$CreateDlpPolicies,

    [switch]$RunAllSteps,

    [switch]$DryRun,

    [switch]$StartTranscript
)

$ErrorActionPreference = 'Stop'

# Constants
$MfaPolicyDisplayName = 'M365 BP Baseline - Require MFA for all users'
$DefenderBaselineDisplayName = 'M365 BP Baseline - Defender for Business Security'
$DefenderCompliancePolicyDisplayName = 'M365 BP Baseline - Defender Device Compliance'
$DefenderEndpointPolicyDisplayName = 'M365 BP Baseline - Defender Endpoint Protection'
$DlpCopilotPolicyName = 'M365 BP Baseline - Block Copilot from Confidential Content'
$DlpExternalSharePolicyName = 'M365 BP Baseline - Block External Sharing of Sensitive Labels'
$SensitivityLabelParentId = 'M365-BP-Baseline-Labels'

function Ensure-RequiredModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$MinimumVersion
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Verbose "Installing PowerShell module: $Name"
        try {
            if ($PSCmdlet.ShouldProcess("Install module $Name", "Install from PSGallery")) {
                if (-not $DryRun) {
                    if ($MinimumVersion) {
                        Install-Module -Name $Name -MinimumVersion $MinimumVersion -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
                    }
                    else {
                        Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
                    }
                }
                else {
                    Write-Verbose "DryRun: would install $Name"
                }
            }
        }
        catch {
            throw "Failed to install module $Name. $_"
        }
    }
    else {
        Write-Verbose "Module $Name already available."
    }

    try {
        Import-Module -Name $Name -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Failed to import module $Name. $_"
    }
}

function Ensure-GraphConnection {
    Write-Verbose "Ensuring Microsoft Graph connection..."
    # Scopes for Entra, Conditional Access, Intune/Defender, Information Protection, and Compliance
    $graphScopes = @(
        'Policy.ReadWrite.ConditionalAccess',
        'Directory.Read.All',
        'DeviceManagementConfiguration.ReadWrite.All',
        'DeviceManagementManagedDevices.ReadWrite.All',
        'InformationProtection.ReadWrite.All',
        'DlpEvaluate.ReadWrite'
    )

    Ensure-RequiredModule -Name 'Microsoft.Graph.Authentication'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Identity.ConditionalAccess' -MinimumVersion '1.0.0'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Users' -MinimumVersion '1.0.0'
    Ensure-RequiredModule -Name 'Microsoft.Graph.DeviceManagement' -MinimumVersion '1.0.0'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Security' -MinimumVersion '1.0.0'

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    if ($TenantId) {
        Write-Verbose "Connecting to Microsoft Graph for tenant: $TenantId"
        if ($PSCmdlet.ShouldProcess("Connect-MgGraph (Tenant=$TenantId)", "Establish Graph connection")) {
            if (-not $DryRun -and -not $SkipGraphConnection) {
                try {
                    Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes -ErrorAction Stop
                }
                catch {
                    throw "Failed to connect to Microsoft Graph. $_"
                }
            }
            else {
                Write-Verbose "DryRun/Skip: skipping actual Connect-MgGraph call."
            }
        }
    }
    else {
        Write-Verbose "Connecting to Microsoft Graph (interactive tenant)..."
        if ($PSCmdlet.ShouldProcess("Connect-MgGraph", "Establish Graph connection")) {
            if (-not $DryRun -and -not $SkipGraphConnection) {
                try {
                    Connect-MgGraph -Scopes $graphScopes -ErrorAction Stop
                }
                catch {
                    throw "Failed to connect to Microsoft Graph. $_"
                }
            }
            else {
                Write-Verbose "DryRun/Skip: skipping actual Connect-MgGraph call."
            }
        }
    }

    Write-Verbose "Connected to Microsoft Graph."
}

function Resolve-BreakGlassUserIds {
    param(
        [string[]]$Users
    )
    if (-not $Users -or $Users.Count -eq 0) {
        return @()
    }

    $resolved = @()
    foreach ($u in $Users) {
        # If looks like an object id, accept it
        if ($u -match '^[0-9a-fA-F-]{36}$') {
            $resolved += $u
            continue
        }
        try {
            Write-Verbose "Resolving user $u to object id..."
            if ($DryRun) {
                Write-Verbose "DryRun: would resolve $u"
                # add placeholder so not empty
                $resolved += $u
            }
            else {
                $user = Get-MgUser -UserId $u -ErrorAction Stop -Property Id
                if ($user -and $user.Id) {
                    $resolved += $user.Id
                }
                else {
                    Write-Warning "Could not resolve user $u to an object id; skipping."
                }
            }
        }
        catch {
            Write-Warning "Failed to resolve $u: $_"
        }
    }
    return $resolved
}

function Step-EnableSecurityDefaults {
    Write-Host "Step: Enabling Microsoft Entra security defaults..." -ForegroundColor Cyan

    $securityDefaultsUri = 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'

    if (-not $PSCmdlet.ShouldProcess('Enable security defaults', 'Set isEnabled = true')) {
        Write-Verbose "Skipping enable security defaults due to ShouldProcess."
        return
    }

    if ($DryRun) {
        Write-Verbose "DryRun: would PATCH $securityDefaultsUri to enable security defaults."
        return
    }

    try {
        $securityDefaults = Invoke-MgGraphRequest -Method GET -Uri $securityDefaultsUri -ErrorAction Stop
        if ($securityDefaults.isEnabled -ne $true) {
            $body = @{
                '@odata.type' = '#microsoft.graph.identitySecurityDefaultsEnforcementPolicy'
                isEnabled     = $true
            }
            Invoke-MgGraphRequest -Method PATCH -Uri $securityDefaultsUri -Body ($body | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
            Write-Host 'Security defaults enabled.' -ForegroundColor Green
        }
        else {
            Write-Host 'Security defaults are already enabled.' -ForegroundColor Yellow
        }
    }
    catch {
        throw "Error enabling security defaults: $_"
    }
}

function Step-CreateMfaPolicy {
    Write-Host "Step: Creating Conditional Access MFA baseline for all users..." -ForegroundColor Cyan

    if (-not $PSCmdlet.ShouldProcess("Create policy '$MfaPolicyDisplayName'", "Create Conditional Access policy")) {
        Write-Verbose "Skipping CreateMfaPolicy due to ShouldProcess."
        return
    }

    try {
        $existingPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
    }
    catch {
        throw "Unable to list conditional access policies. Ensure the account has Policy.Read.All or Policy.ReadWrite.ConditionalAccess and that admin consent was granted. $_"
    }

    $hasMfaBaseline = $existingPolicies | Where-Object { $_.DisplayName -eq $MfaPolicyDisplayName }
    if ($hasMfaBaseline) {
        Write-Host 'The MFA baseline already exists.' -ForegroundColor Yellow
        return
    }

    # Resolve break-glass users to object IDs (recommended)
    $excludeUserIds = Resolve-BreakGlassUserIds -Users $BreakGlassUsers

    $userCondition = @{
        includeUsers = @('All')
    }
    if ($excludeUserIds.Count -gt 0) {
        $userCondition.excludeUsers = $excludeUserIds
        Write-Host "Break-glass exclusions configured for object IDs: $($excludeUserIds -join ', ')" -ForegroundColor Yellow
    }

    # Build policy body per Graph schema
    $mfaPolicy = @{
        displayName = $MfaPolicyDisplayName
        state       = 'enabled'
        conditions  = @{
            users = $userCondition
            applications = @{
                includeApplications = @('All')
            }
            clientAppTypes = @('Browser','MobileAppsAndDesktopClients')
        }
        grantControls = @{
            operator        = 'OR'
            builtInControls = @('mfa')
        }
    }

    if ($DryRun) {
        Write-Verbose "DryRun: would create Conditional Access policy with body: $(ConvertTo-Json $mfaPolicy -Depth 10)"
        return
    }

    try {
        New-MgIdentityConditionalAccessPolicy -BodyParameter $mfaPolicy -ErrorAction Stop | Out-Null
        Write-Host 'MFA Conditional Access baseline created.' -ForegroundColor Green
    }
    catch {
        throw "Failed to create Conditional Access policy. $_"
    }
}

function Step-DeployDefenderBaseline {
    Write-Host "Step: Deploying Defender for Business security baseline..." -ForegroundColor Cyan

    if (-not $PSCmdlet.ShouldProcess("Deploy Defender for Business baseline", "Create security baseline configuration")) {
        Write-Verbose "Skipping Defender baseline deployment due to ShouldProcess."
        return
    }

    if ($DryRun) {
        Write-Verbose "DryRun: would create Defender for Business security baseline."
        return
    }

    try {
        # Get all security baselines to check if one already exists
        $existingBaselines = Get-MgDeviceManagementDeviceConfiguration -ErrorAction Stop
        $hasDefenderBaseline = $existingBaselines | Where-Object { $_.DisplayName -eq $DefenderBaselineDisplayName }
        
        if ($hasDefenderBaseline) {
            Write-Host "Defender baseline already exists: $DefenderBaselineDisplayName" -ForegroundColor Yellow
            return
        }

        # Create Defender for Business security baseline configuration
        $defenderBaseline = @{
            displayName = $DefenderBaselineDisplayName
            description = 'Baseline configuration for Defender for Business security settings'
            '@odata.type' = '#microsoft.graph.windows10EndpointProtectionConfiguration'
            
            # Windows Defender configuration
            defenderScanType = 'quick'  # or 'full'
            defenderScheduledScanTime = '02:00:00'
            defenderCloudBlockLevel = 'high'
            defenderCloudBlockLevelRaw = 'high'
            defenderRealtimeMonitoringEnabled = $true
            defenderBehaviorMonitoringEnabled = $true
            
            # Network protection
            defenderNetworkProtectionType = 'enabled'
            
            # Application Guard
            applicationGuardEnabled = $true
            applicationGuardBlockFileTransfers = 'blockBoth'
            applicationGuardBlockClipboardSharing = 'blockBoth'
            
            # Windows Defender SmartScreen
            smartScreenEnableInShell = $true
            smartScreenBlockOverrideForFiles = $true
            
            # Exploit Guard
            exploitProtectionOverrideLocalPaths = @()
            
            # Firewall settings
            firewallEnabled = $true
            firewallPreSharedKeyEncodingMethod = 'deviceDefault'
            firewallProfileDomain = @{
                '@odata.type' = '#microsoft.graph.windowsFirewallNetworkProfile'
                firewallBlocked = $false
                inboundConnectionsBlocked = $true
                outboundConnectionsBlocked = $false
                policyRulesFromGroupPolicyMerged = $true
                secretPreSharedKeyLength = 64
            }
            firewallProfilePrivate = @{
                '@odata.type' = '#microsoft.graph.windowsFirewallNetworkProfile'
                firewallBlocked = $false
                inboundConnectionsBlocked = $true
                outboundConnectionsBlocked = $false
                policyRulesFromGroupPolicyMerged = $true
                secretPreSharedKeyLength = 64
            }
            firewallProfilePublic = @{
                '@odata.type' = '#microsoft.graph.windowsFirewallNetworkProfile'
                firewallBlocked = $false
                inboundConnectionsBlocked = $true
                outboundConnectionsBlocked = $false
                policyRulesFromGroupPolicyMerged = $true
                secretPreSharedKeyLength = 64
            }
        }

        New-MgDeviceManagementDeviceConfiguration -BodyParameter $defenderBaseline -ErrorAction Stop | Out-Null
        Write-Host "Defender for Business baseline deployed: $DefenderBaselineDisplayName" -ForegroundColor Green
    }
    catch {
        throw "Failed to deploy Defender for Business baseline. $_"
    }
}

function Step-ConfigureDefenderPolicies {
    Write-Host "Step: Configuring Defender for Business endpoint protection and compliance policies..." -ForegroundColor Cyan

    if (-not $PSCmdlet.ShouldProcess("Configure Defender policies", "Create endpoint protection and device compliance policies")) {
        Write-Verbose "Skipping Defender policy configuration due to ShouldProcess."
        return
    }

    if ($DryRun) {
        Write-Verbose "DryRun: would create Defender endpoint protection and compliance policies."
        return
    }

    try {
        # 1. Create Endpoint Protection Policy
        Write-Verbose "Creating Endpoint Protection policy..."
        
        $existingPolicies = Get-MgDeviceManagementDeviceConfiguration -ErrorAction Stop
        $hasEndpointPolicy = $existingPolicies | Where-Object { $_.DisplayName -eq $DefenderEndpointPolicyDisplayName }
        
        if (-not $hasEndpointPolicy) {
            $endpointPolicy = @{
                displayName = $DefenderEndpointPolicyDisplayName
                description = 'Baseline Endpoint Protection policy for Defender for Business'
                '@odata.type' = '#microsoft.graph.windows10EndpointProtectionConfiguration'
                
                # Advanced Threat Protection
                advancedThreatProtectionEnabled = $true
                
                # Windows Defender Advanced Threat Protection (ATP)
                defenderScheduledQuickScanTime = '02:00:00'
                defenderOfficeMacroCodeAllowedExecutionLevel = 'blockExecutionOfUntrustedMacros'
                
                # Controlled Folder Access
                controlledFolderAccessAllowedApplications = @()
                controlledFolderAccessProtectedFolders = @()
            }
            
            New-MgDeviceManagementDeviceConfiguration -BodyParameter $endpointPolicy -ErrorAction Stop | Out-Null
            Write-Host "Endpoint Protection policy created: $DefenderEndpointPolicyDisplayName" -ForegroundColor Green
        }
        else {
            Write-Host "Endpoint Protection policy already exists: $DefenderEndpointPolicyDisplayName" -ForegroundColor Yellow
        }

        # 2. Create Device Compliance Policy
        Write-Verbose "Creating Device Compliance policy..."
        
        $compliancePolicies = Get-MgDeviceManagementDeviceCompliancePolicy -ErrorAction Stop
        $hasCompliancePolicy = $compliancePolicies | Where-Object { $_.DisplayName -eq $DefenderCompliancePolicyDisplayName }
        
        if (-not $hasCompliancePolicy) {
            $compliancePolicy = @{
                displayName = $DefenderCompliancePolicyDisplayName
                description = 'Baseline Device Compliance policy for Defender for Business'
                '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'
                
                # Windows version compliance
                osMinimumVersion = '10.0.19041'
                
                # Defender compliance
                defenderEnabled = $true
                defenderVersion = 'latestAvailable'
                
                # Firewall requirements
                firewallBlocked = $false
                
                # Security settings
                tpmRequired = $false
                passwordRequired = $true
                passwordMinimumLength = 12
                passwordMinutesOfInactivityBeforeLock = 15
                passwordExpirationDays = 90
                passwordPreviousPasswordBlockCount = 3
                
                # BitLocker
                bitLockerEnabled = $true
                
                # Device Security
                secureBootEnabled = $true
                deviceThreatProtectionEnabled = $true
                deviceThreatProtectionRequiredSecurityLevel = 'medium'
                
                # Encryption
                storageRequireEncryption = $true
                
                # Real-time Protection
                validOperatingSystemBuildRanges = @(@{
                    lowestVersion = '10.0.19041'
                    highestVersion = '10.0.22631'
                })
            }
            
            New-MgDeviceManagementDeviceCompliancePolicy -BodyParameter $compliancePolicy -ErrorAction Stop | Out-Null
            Write-Host "Device Compliance policy created: $DefenderCompliancePolicyDisplayName" -ForegroundColor Green
        }
        else {
            Write-Host "Device Compliance policy already exists: $DefenderCompliancePolicyDisplayName" -ForegroundColor Yellow
        }

    }
    catch {
        throw "Failed to configure Defender policies. $_"
    }
}

function Step-CreateSensitivityLabels {
    Write-Host "Step: Creating and publishing sensitivity labels..." -ForegroundColor Cyan

    if (-not $PSCmdlet.ShouldProcess("Create sensitivity labels", "Create and publish labels: $($SensitivityLabelNames -join ', ')")) {
        Write-Verbose "Skipping sensitivity label creation due to ShouldProcess."
        return
    }

    if ($DryRun) {
        Write-Verbose "DryRun: would create and publish sensitivity labels: $($SensitivityLabelNames -join ', ')"
        return
    }

    try {
        # Define color scheme and protection levels for each label
        $labelConfigs = @(
            @{
                name = $SensitivityLabelNames[0]
                color = '#90EE90'  # Light green
                order = 0
                tooltip = "General use - No special protection required"
            },
            @{
                name = $SensitivityLabelNames[1]
                color = '#FFD700'  # Gold
                order = 1
                tooltip = "Internal use only - Encrypt for organizational members"
            },
            @{
                name = $SensitivityLabelNames[2]
                color = '#FF6347'  # Tomato red
                order = 2
                tooltip = "Highly confidential - Maximum protection and restrictions"
            }
        )

        $createdLabelIds = @()

        foreach ($config in $labelConfigs) {
            Write-Verbose "Creating sensitivity label: $($config.name)"

            $labelBody = @{
                displayName = $config.name
                description = $config.tooltip
                tooltip = $config.tooltip
                isActive = $true
                contentFormats = @('file', 'email')
            }

            try {
                $label = Invoke-MgGraphRequest -Method POST `
                    -Uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels' `
                    -Body ($labelBody | ConvertTo-Json -Depth 10) `
                    -ErrorAction Stop

                if ($label -and $label.id) {
                    $createdLabelIds += $label.id
                    Write-Host "Sensitivity label created: $($config.name) (ID: $($label.id))" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Failed to create label '$($config.name)': $_"
            }
        }

        # Publish labels to all users if any were created successfully
        if ($createdLabelIds.Count -gt 0) {
            Write-Verbose "Publishing $($createdLabelIds.Count) label(s) to all users..."
            
            $publishBody = @{
                labelIds = $createdLabelIds
                userIds = @('all')  # Publish to all users
            }

            try {
                Invoke-MgGraphRequest -Method POST `
                    -Uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels/publish' `
                    -Body ($publishBody | ConvertTo-Json -Depth 10) `
                    -ErrorAction Stop | Out-Null

                Write-Host "Sensitivity labels published to all users successfully." -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to publish labels to users: $_"
            }
        }
        else {
            Write-Warning "No sensitivity labels were created successfully."
        }

    }
    catch {
        throw "Failed to create or publish sensitivity labels. $_"
    }
}

function Step-CreateDlpPolicies {
    Write-Host "Step: Creating Data Loss Prevention (DLP) policies..." -ForegroundColor Cyan

    if (-not $PSCmdlet.ShouldProcess("Create DLP policies", "Block Copilot from Confidential content and block external sharing of sensitive labels")) {
        Write-Verbose "Skipping DLP policy creation due to ShouldProcess."
        return
    }

    if ($DryRun) {
        Write-Verbose "DryRun: would create DLP policies: Copilot blocking and external sharing restrictions."
        return
    }

    try {
        # Get the Confidential and Internal label names
        $confidentialLabel = $SensitivityLabelNames[2]  # Typically 'Confidential'
        $internalLabel = $SensitivityLabelNames[1]      # Typically 'Internal'

        # 1. DLP Policy: Block Copilot from using Confidential content
        Write-Verbose "Creating DLP policy to block Copilot from Confidential labeled content..."

        $copilotBlockPolicy = @{
            displayName = $DlpCopilotPolicyName
            description = "Prevents Copilot from accessing content labeled as $confidentialLabel"
            isEnabled = $true
            mode = 'Enable'
            rules = @(
                @{
                    name = "Block Copilot from Confidential"
                    conditions = @{
                        sensitivityLabels = @($confidentialLabel)
                    }
                    actions = @(
                        @{
                            type = 'Block'
                            userOverride = $false
                            notifyUser = $true
                            actionParameters = @{
                                recipients = @()
                            }
                        }
                    )
                }
            )
            conditionalAccessRules = @(
                @{
                    condition = "app:Copilot"
                    restrictions = @('access')
                }
            )
        }

        try {
            $copilotPolicy = Invoke-MgGraphRequest -Method POST `
                -Uri 'https://graph.microsoft.com/beta/security/dataLossPreventionPolicies' `
                -Body ($copilotBlockPolicy | ConvertTo-Json -Depth 10) `
                -ErrorAction Stop

            if ($copilotPolicy) {
                Write-Host "DLP Policy created: $DlpCopilotPolicyName" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Failed to create Copilot blocking DLP policy: $_"
        }

        # 2. DLP Policy: Block external sharing of Confidential and Internal content
        Write-Verbose "Creating DLP policy to block external sharing of sensitive labeled content..."

        $externalSharePolicy = @{
            displayName = $DlpExternalSharePolicyName
            description = "Prevents sharing of content labeled as $confidentialLabel or $internalLabel with external users"
            isEnabled = $true
            mode = 'Enable'
            rules = @(
                @{
                    name = "Block External Sharing of Sensitive Labels"
                    conditions = @{
                        sensitivityLabels = @($confidentialLabel, $internalLabel)
                    }
                    actions = @(
                        @{
                            type = 'Block'
                            userOverride = $false
                            notifyUser = $true
                            actionParameters = @{
                                recipients = @()
                                comment = "This content is too sensitive to share externally"
                            }
                        }
                    )
                }
            )
            conditionalAccessRules = @(
                @{
                    condition = "sharingWith:ExternalUsers"
                    restrictions = @('share')
                }
            )
        }

        try {
            $sharePolicy = Invoke-MgGraphRequest -Method POST `
                -Uri 'https://graph.microsoft.com/beta/security/dataLossPreventionPolicies' `
                -Body ($externalSharePolicy | ConvertTo-Json -Depth 10) `
                -ErrorAction Stop

            if ($sharePolicy) {
                Write-Host "DLP Policy created: $DlpExternalSharePolicyName" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Failed to create external sharing blocking DLP policy: $_"
        }

        Write-Host "DLP policies deployment complete." -ForegroundColor Green

    }
    catch {
        throw "Failed to create DLP policies. $_"
    }
}

function Step-ReviewLegacyAuth {
    Write-Host "Step: Review legacy authentication and sign-in posture..." -ForegroundColor Cyan

    Write-Host "Legacy auth review checklist:" -ForegroundColor Yellow
    $checklist = @(
        'Confirm no modern auth exceptions are permitting Basic Auth.',
        'Review sign-in logs for legacy client usage (SignIn logs).',
        'Check Exchange Online authentication policy and legacy client behavior.',
        'Validate service accounts and helpdesk accounts before full enforcement.',
        'Review Intune compliance on devices before broad rollout.'
    )
    $checklist | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    Write-Host "`nSuggested commands (interactive):" -ForegroundColor Yellow
    Write-Host "  Get-MgAuditActivitySignIns -Top 50" -ForegroundColor DarkGray
    Write-Host "  Get-MgReportAuthenticationMethodsUserRegistrationDetail" -ForegroundColor DarkGray
    Write-Host "  Connect-ExchangeOnline; Get-AuthenticationPolicy; Get-OrganizationConfig | Select-Object IsLegacyAuthProtocolsEnabled" -ForegroundColor DarkGray
}

# Decide steps
if (-not $RunAllSteps -and -not $EnableSecurityDefaults -and -not $CreateMfaPolicy -and -not $ReviewLegacyAuth -and -not $DeployDefenderBaseline -and -not $ConfigureDefenderPolicies -and -not $CreateSensitivityLabels -and -not $CreateDlpPolicies) {
    $RunAllSteps = $true
}

if ($StartTranscript) {
    try {
        if (-not $DryRun) { Start-Transcript -Path "$($PSScriptRoot)\deploy-m365-bp-baseline-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" -Force }
        else { Write-Verbose "DryRun: would start transcript." }
    }
    catch {
        Write-Warning "Unable to start transcript: $_"
    }
}

try {
    if (-not $SkipGraphConnection) {
        Ensure-GraphConnection
    }

    if ($EnableSecurityDefaults -or $RunAllSteps) {
        if ($PSCmdlet.ShouldProcess('EnableEntraSecurityDefaults', 'Enable security defaults for tenant')) {
            Step-EnableSecurityDefaults
        }
    }

    if ($CreateMfaPolicy -or $RunAllSteps) {
        if ($PSCmdlet.ShouldProcess('CreateMfaPolicy', "Create CA policy '$MfaPolicyDisplayName'")) {
            Step-CreateMfaPolicy
        }
    }

    if ($DeployDefenderBaseline -or $RunAllSteps) {
        if ($PSCmdlet.ShouldProcess('DeployDefenderBaseline', 'Deploy Defender for Business baseline')) {
            Step-DeployDefenderBaseline
        }
    }

    if ($ConfigureDefenderPolicies -or $RunAllSteps) {
        if ($PSCmdlet.ShouldProcess('ConfigureDefenderPolicies', 'Configure Defender endpoint protection and compliance policies')) {
            Step-ConfigureDefenderPolicies
        }
    }

    if ($CreateSensitivityLabels -or $RunAllSteps) {
        if ($PSCmdlet.ShouldProcess('CreateSensitivityLabels', "Create and publish sensitivity labels: $($SensitivityLabelNames -join ', ')")) {
            Step-CreateSensitivityLabels
        }
    }

    if ($CreateDlpPolicies -or $RunAllSteps) {
        if ($PSCmdlet.ShouldProcess('CreateDlpPolicies', 'Create Data Loss Prevention policies')) {
            Step-CreateDlpPolicies
        }
    }

    if ($ReviewLegacyAuth -or $RunAllSteps) {
        Step-ReviewLegacyAuth
    }

    Write-Host "`nBaseline deployment sequence complete. Validate in a pilot group before broad production rollout." -ForegroundColor Green
    Write-Host "Recommended next actions:" -ForegroundColor Cyan
    Write-Host "  1. Review sign-in logs for 24-48 hours after enforcement." -ForegroundColor Cyan
    Write-Host "  2. Confirm break-glass accounts are excluded appropriately." -ForegroundColor Cyan
    Write-Host "  3. Validate Intune compliance and device health." -ForegroundColor Cyan
    Write-Host "  4. Monitor Defender for Business alerts and threat detections." -ForegroundColor Cyan
    Write-Host "  5. Verify endpoint protection policies are applying to managed devices." -ForegroundColor Cyan
    Write-Host "  6. Verify sensitivity labels are available in Office 365 clients (Word, Excel, Outlook, Teams)." -ForegroundColor Cyan
    Write-Host "  7. Monitor DLP policy violations and user notifications." -ForegroundColor Cyan
    Write-Host "  8. Block legacy auth only after verifying client compatibility." -ForegroundColor Cyan
}
catch {
    Write-Error "Deployment failed: $_"
    throw
}
finally {
    if ($StartTranscript -and -not $DryRun) {
        try { Stop-Transcript } catch { Write-Verbose "Stop-Transcript error: $_" }
    }
}
