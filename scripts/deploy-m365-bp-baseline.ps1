[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [string[]]$BreakGlassUsers = @(),

    [switch]$SkipGraphConnection,

    [switch]$EnableSecurityDefaults,

    [switch]$CreateMfaPolicy,

    [switch]$ReviewLegacyAuth,

    [switch]$RunAllSteps
)

$ErrorActionPreference = 'Stop'

function Ensure-RequiredModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing PowerShell module: $Name" -ForegroundColor Yellow
        Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }
}

function Step-ConnectToGraph {
    Write-Host "Step 1/4: Connect to Microsoft Graph..." -ForegroundColor Cyan
    Ensure-RequiredModule -Name 'Microsoft.Graph.Authentication'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Identity.SignIns'
    Ensure-RequiredModule -Name 'Microsoft.Graph.Identity.DirectoryManagement'

    Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Identity.DirectoryManagement

    $graphScopes = @(
        'Policy.ReadWrite.ConditionalAccess',
        'Policy.Read.All',
        'Directory.ReadWrite.All',
        'Directory.AccessAsUser.All',
        'User.Read.All',
        'DeviceManagementConfiguration.ReadWrite.All',
        'DeviceManagementManagedDevices.ReadWrite.All'
    )

    if ($TenantId) {
        Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes
    }
    else {
        Connect-MgGraph -Scopes $graphScopes
    }

    Write-Host "Connected to Microsoft Graph." -ForegroundColor Green
}

function Step-EnableSecurityDefaults {
    Write-Host "Step 2/4: Enabling Microsoft Entra security defaults..." -ForegroundColor Cyan
    $securityDefaultsUri = 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
    $securityDefaults = Invoke-MgGraphRequest -Method GET -Uri $securityDefaultsUri

    if ($securityDefaults.isEnabled -ne $true) {
        $body = @{
            '@odata.type' = '#microsoft.graph.identitySecurityDefaultsEnforcementPolicy'
            isEnabled     = $true
        }

        Invoke-MgGraphRequest -Method PATCH -Uri $securityDefaultsUri -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host 'Security defaults enabled.' -ForegroundColor Green
    }
    else {
        Write-Host 'Security defaults are already enabled.' -ForegroundColor Yellow
    }
}

function Step-CreateMfaPolicy {
    Write-Host "Step 3/4: Creating Conditional Access MFA baseline for all users..." -ForegroundColor Cyan

    $existingPolicies = Get-MgIdentityConditionalAccessPolicy
    $hasMfaBaseline = $existingPolicies | Where-Object { $_.DisplayName -eq 'M365 BP Baseline - Require MFA for all users' }

    if (-not $hasMfaBaseline) {
        $userCondition = @{
            includeUsers = @('All')
        }

        if ($BreakGlassUsers.Count -gt 0) {
            $userCondition.excludeUsers = @($BreakGlassUsers)
            Write-Host "Break-glass exclusions configured for: $($BreakGlassUsers -join ', ')" -ForegroundColor Yellow
        }

        $mfaPolicy = @{
            displayName = 'M365 BP Baseline - Require MFA for all users'
            state       = 'enabled'
            conditions  = @{
                users = $userCondition
                applications = @{
                    includeApplications = @('All')
                }
                clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync', 'other')
            }
            grantControls = @{
                operator        = 'OR'
                builtInControls = @('mfa')
            }
        }

        New-MgIdentityConditionalAccessPolicy -BodyParameter $mfaPolicy | Out-Null
        Write-Host 'MFA Conditional Access baseline created.' -ForegroundColor Green
    }
    else {
        Write-Host 'The MFA baseline already exists.' -ForegroundColor Yellow
    }
}

function Step-ReviewLegacyAuth {
    Write-Host "Step 4/4: Review legacy authentication and sign-in posture..." -ForegroundColor Cyan

    Write-Host "Legacy auth review checklist:" -ForegroundColor Yellow
    Write-Host "  - Confirm no modern auth exceptions are permitting Basic Auth." -ForegroundColor Yellow
    Write-Host "  - Review sign-in logs for legacy client usage." -ForegroundColor Yellow
    Write-Host "  - Check Exchange Online authentication policy and legacy client behavior." -ForegroundColor Yellow
    Write-Host "  - Validate service accounts and helpdesk accounts before full enforcement." -ForegroundColor Yellow
    Write-Host "  - Review Intune compliance on devices before broad rollout." -ForegroundColor Yellow

    $legacyAuthReview = @(
        'Get-MgAuditLogDirectoryAudit -Top 50',
        'Get-MgReportAuthenticationMethodsUserRegistrationDetail',
        'Get-MgLogEntry -All | Where-Object { $_.Category -like "SignInLogs" }',
        'Connect-ExchangeOnline; Get-AuthenticationPolicy; Get-OrganizationConfig | Select-Object IsLegacyAuthProtocolsEnabled'
    )

    $legacyAuthReview | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor DarkGray
    }
}

if (-not $RunAllSteps -and -not $EnableSecurityDefaults -and -not $CreateMfaPolicy -and -not $ReviewLegacyAuth) {
    $RunAllSteps = $true
}

if (-not $SkipGraphConnection) {
    Step-ConnectToGraph
}

if ($EnableSecurityDefaults -or $RunAllSteps) {
    Step-EnableSecurityDefaults
}

if ($CreateMfaPolicy -or $RunAllSteps) {
    Step-CreateMfaPolicy
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
