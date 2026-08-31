<#
.SYNOPSIS
    Deploy M365 baseline: enable security defaults and create a Conditional Access MFA baseline.

.DESCRIPTION
    This script connects to Microsoft Graph, optionally enables Entra security defaults, creates
    a Conditional Access policy to require MFA for users, and prints recommended review steps.
    It supports -WhatIf/-Confirm and verbose output.

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

.PARAMETER RunAllSteps
    Run all steps (same as specifying all step switches).

.PARAMETER DryRun
    When set, no changes will be made; operations that support ShouldProcess will be simulated.

.PARAMETER StartTranscript
    When set, capture a transcript of the session to a timestamped log file.

.EXAMPLE
    .\deploy-m365-bp-baseline.ps1 -TenantId 'contoso.onmicrosoft.com' -BreakGlassUsers 'break@contoso.com' -RunAllSteps -Verbose

.NOTES
    - Requires Microsoft.Graph modules. Script can install missing modules for current user.
    - Some Graph scopes require admin consent.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$|^.+\..+$')] # allow GUID or domain/tenant
    [string]$TenantId,

    [string[]]$BreakGlassUsers = @(),

    [switch]$SkipGraphConnection,

    [switch]$EnableSecurityDefaults,

    [switch]$CreateMfaPolicy,

    [switch]$ReviewLegacyAuth,

    [switch]$RunAllSteps,

    [switch]$DryRun,

    [switch]$StartTranscript
)

$ErrorActionPreference = 'Stop'

# Constants
$MfaPolicyDisplayName = 'M365 BP Baseline - Require MFA for all users'

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
    # minimal required granular scopes for these operations:
    # - Policy.ReadWrite.ConditionalAccess (create CA)
    # - Directory.Read.All (to resolve users) or Directory.ReadWrite.All if you need to create objects
    # Note: admin consent required for these scopes.
    $graphScopes = @(
        'Policy.ReadWrite.ConditionalAccess',
        'Directory.Read.All'
    )

    Ensure-RequiredModule -Name 'Microsoft.Graph.Authentication'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Identity.ConditionalAccess' -MinimumVersion '1.0.0'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Users' -MinimumVersion '1.0.0'

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
if (-not $RunAllSteps -and -not $EnableSecurityDefaults -and -not $CreateMfaPolicy -and -not $ReviewLegacyAuth) {
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

    if ($ReviewLegacyAuth -or $RunAllSteps) {
        Step-ReviewLegacyAuth
    }

    Write-Host "`nBaseline deployment sequence complete. Validate in a pilot group before broad production rollout." -ForegroundColor Green
    Write-Host "Recommended next actions:" -ForegroundColor Cyan
    Write-Host "  1. Review sign-in logs for 24-48 hours after enforcement." -ForegroundColor Cyan
    Write-Host "  2. Confirm break-glass accounts are excluded appropriately." -ForegroundColor Cyan
    Write-Host "  3. Validate Intune compliance and device health." -ForegroundColor Cyan
    Write-Host "  4. Block legacy auth only after verifying client compatibility." -ForegroundColor Cyan
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
