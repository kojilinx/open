<#
.SYNOPSIS
    Read-only audit of OAuth consent grants in a Microsoft Entra ID tenant.

.DESCRIPTION
    Enumerates every service principal in the tenant along with the delegated
    (on-behalf-of-a-user) and application (app-only) permissions it holds, then
    reports the grants that carry real attack value.

    This script is READ-ONLY. It requests read-only Microsoft Graph scopes and
    performs no writes. Revoking an OAuth grant is a high-blast-radius identity
    change, so every finding carries the exact command to revoke it and the
    operator runs that deliberately. The script will never revoke anything.

.PARAMETER OutputPath
    Optional. Directory to write the CSV report to. Defaults to the current
    directory. The report omits tenant identifiers by default.

.PARAMETER IncludeInfo
    Include Info-severity findings (every grant seen, including low-risk ones)
    in the console output. The CSV always contains everything.

.PARAMETER TenantId
    Optional. Target a specific tenant when your account has access to several.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Get-ConsentGrantAudit.ps1

.EXAMPLE
    .\Get-ConsentGrantAudit.ps1 -OutputPath C:\Reports -IncludeInfo

.NOTES
    EXECUTION POLICY
    ----------------
    If this script will not start and you get PSSecurityException or
    UnauthorizedAccess, the file is blocked by execution policy. A .ps1 cannot
    lift its own load-time policy block, so this is documentation, not a fix the
    script can apply to itself.

    Preferred (no machine-wide change, scoped to this one run):
        powershell.exe -ExecutionPolicy Bypass -File .\Get-ConsentGrantAudit.ps1

    If the file came from the internet and is flagged as blocked:
        Unblock-File .\Get-ConsentGrantAudit.ps1

    Session-scoped alternative (reverts when the window closes):
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

    Per-user alternative (persists for your account only):
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

    REQUIREMENTS
    ------------
    PowerShell 7+ recommended (Windows PowerShell 5.1 works).
    Microsoft.Graph PowerShell SDK:
        Install-Module Microsoft.Graph -Scope CurrentUser

    GRAPH SCOPES (all read-only)
    ----------------------------
    Application.Read.All, Directory.Read.All
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ".",
    [switch]$IncludeInfo,
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Finding collection
# ---------------------------------------------------------------------------

$script:Findings = New-Object System.Collections.Generic.List[object]

$script:SeverityRank = @{
    'Critical' = 0
    'High'     = 1
    'Medium'   = 2
    'Low'      = 3
    'Info'     = 4
}

function Add-Finding {
    param(
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low','Info')]
        [string]$Severity,
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Object,
        [Parameter(Mandatory)][string]$Detail,
        [Parameter(Mandatory)][string]$Risk,
        [Parameter(Mandatory)][string]$Remediation
    )

    $script:Findings.Add([pscustomobject]@{
        Severity    = $Severity
        Area        = $Area
        Object      = $Object
        Detail      = $Detail
        Risk        = $Risk
        Remediation = $Remediation
    })
}

# ---------------------------------------------------------------------------
# Risk model
#
# These are the permissions that turn a consented app into mailbox access,
# file access, or a path to privilege escalation. The app-only list is scored
# harder than the delegated list: an application permission runs with no user
# context, no user sign-in, and is unaffected by that user's MFA or by
# disabling their account.
# ---------------------------------------------------------------------------

$script:HighRiskAppOnly = @(
    'full_access_as_app',
    'Mail.ReadWrite', 'Mail.Read', 'Mail.Send',
    'MailboxSettings.ReadWrite',
    'Files.ReadWrite.All', 'Files.Read.All',
    'Sites.ReadWrite.All', 'Sites.FullControl.All',
    'Directory.ReadWrite.All',
    'User.ReadWrite.All',
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All',
    'RoleManagement.ReadWrite.Directory',
    'Group.ReadWrite.All',
    'Exchange.ManageAsApp'
)

$script:HighRiskDelegated = @(
    'Mail.ReadWrite', 'Mail.Read', 'Mail.Send', 'Mail.ReadWrite.Shared', 'Mail.Send.Shared',
    'MailboxSettings.ReadWrite',
    'Files.ReadWrite.All',
    'Sites.ReadWrite.All',
    'Directory.ReadWrite.All',
    'User.ReadWrite.All',
    'Application.ReadWrite.All',
    'RoleManagement.ReadWrite.Directory',
    'offline_access'
)

function Test-HighRiskPermission {
    param(
        [string]$Permission,
        [ValidateSet('Application','Delegated')][string]$Type
    )

    if ([string]::IsNullOrWhiteSpace($Permission)) { return $false }

    $list = if ($Type -eq 'Application') { $script:HighRiskAppOnly } else { $script:HighRiskDelegated }
    return $list -contains $Permission
}

# ---------------------------------------------------------------------------
# Connect (Graph only, read-only scopes)
# ---------------------------------------------------------------------------

function Connect-Tenant {
    $scopes = @('Application.Read.All', 'Directory.Read.All')

    $context = $null
    try { $context = Get-MgContext } catch { $context = $null }

    if ($null -ne $context) {
        $missing = @($scopes | Where-Object { $context.Scopes -notcontains $_ })
        if ($missing.Count -eq 0) {
            Write-Host "Reusing existing Microsoft Graph session." -ForegroundColor DarkGray
            return
        }
        Write-Host "Existing Graph session is missing scopes: $($missing -join ', ')" -ForegroundColor Yellow
    }

    Write-Host "Connecting to Microsoft Graph (read-only scopes)..." -ForegroundColor Cyan

    $params = @{ Scopes = $scopes; NoWelcome = $true }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $params['TenantId'] = $TenantId }

    Connect-MgGraph @params
}

# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

function Get-ServicePrincipalIndex {
    Write-Host "Enumerating service principals..." -ForegroundColor Cyan

    $all = @(Get-MgServicePrincipal -All -Property @(
        'Id', 'AppId', 'DisplayName', 'AppRoles', 'PublisherName',
        'VerifiedPublisher', 'SignInAudience', 'AppOwnerOrganizationId',
        'ServicePrincipalType', 'Tags', 'AccountEnabled'
    ))

    $index = @{}
    foreach ($sp in $all) { $index[$sp.Id] = $sp }

    Write-Host "  Found $($all.Count) service principals." -ForegroundColor DarkGray
    return $index
}

function Resolve-AppRoleName {
    param($ResourceServicePrincipal, [string]$AppRoleId)

    if ($null -eq $ResourceServicePrincipal) { return $AppRoleId }
    if ($null -eq $ResourceServicePrincipal.AppRoles) { return $AppRoleId }

    $role = $ResourceServicePrincipal.AppRoles | Where-Object { $_.Id -eq $AppRoleId }
    if ($null -ne $role -and -not [string]::IsNullOrWhiteSpace($role.Value)) {
        return $role.Value
    }

    return $AppRoleId
}

function Get-PublisherLabel {
    param($ServicePrincipal)

    $verified = $null
    try { $verified = $ServicePrincipal.VerifiedPublisher } catch { $verified = $null }

    if ($null -ne $verified -and -not [string]::IsNullOrWhiteSpace($verified.DisplayName)) {
        return "verified publisher: $($verified.DisplayName)"
    }

    if (-not [string]::IsNullOrWhiteSpace($ServicePrincipal.PublisherName)) {
        return "publisher: $($ServicePrincipal.PublisherName) (not verified)"
    }

    return "no verified publisher"
}

# ---------------------------------------------------------------------------
# Check 1: delegated permission grants (oauth2PermissionGrants)
#
# consentType AllPrincipals means an administrator consented on behalf of the
# entire tenant. That single grant covers every user, so a high-risk scope here
# is materially worse than the same scope consented by one person.
# ---------------------------------------------------------------------------

function Invoke-DelegatedGrantCheck {
    param([hashtable]$SpIndex)

    Write-Host "Auditing delegated permission grants..." -ForegroundColor Cyan

    $grants = @(Get-MgOauth2PermissionGrant -All)
    Write-Host "  Found $($grants.Count) delegated grants." -ForegroundColor DarkGray

    foreach ($grant in $grants) {

        $client = $null
        if ($SpIndex.ContainsKey($grant.ClientId)) { $client = $SpIndex[$grant.ClientId] }

        $resource = $null
        if ($SpIndex.ContainsKey($grant.ResourceId)) { $resource = $SpIndex[$grant.ResourceId] }

        $clientName   = if ($null -ne $client)   { $client.DisplayName }   else { "unknown app ($($grant.ClientId))" }
        $resourceName = if ($null -ne $resource) { $resource.DisplayName } else { "unknown API" }

        $tenantWide = ($grant.ConsentType -eq 'AllPrincipals')
        $scopeList  = @()
        if (-not [string]::IsNullOrWhiteSpace($grant.Scope)) {
            $scopeList = @($grant.Scope.Trim() -split '\s+')
        }

        $risky = @($scopeList | Where-Object { Test-HighRiskPermission -Permission $_ -Type 'Delegated' })

        if ($risky.Count -eq 0) {
            Add-Finding -Severity 'Info' -Area 'Delegated consent' -Object $clientName `
                -Detail "Holds $($scopeList.Count) delegated scope(s) on $resourceName. No high-risk scopes. Consent type: $($grant.ConsentType)." `
                -Risk 'No elevated data access via this grant.' `
                -Remediation 'No action required.'
            continue
        }

        $severity = if ($tenantWide) { 'High' } else { 'Medium' }
        $who = if ($tenantWide) { 'ALL USERS in the tenant (admin consented)' } else { 'a single user' }

        $publisher = if ($null -ne $client) { Get-PublisherLabel -ServicePrincipal $client } else { 'unknown publisher' }

        Add-Finding -Severity $severity -Area 'Delegated consent' -Object $clientName `
            -Detail "High-risk delegated scope(s) on ${resourceName}: $($risky -join ', '). Consent covers $who. Application has $publisher." `
            -Risk "This app can act as the consenting user against $resourceName. Delegated mail scopes let it read and send mail as that user, which survives a password reset until the refresh token is revoked." `
            -Remediation "Review in Entra admin center, then if unwanted: Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId '$($grant.Id)'"
    }
}

# ---------------------------------------------------------------------------
# Check 2: application permission grants (appRoleAssignments)
#
# These run app-only. No user, no interactive sign-in, unaffected by the
# user's MFA. This is the category that matters most in an investigation.
# ---------------------------------------------------------------------------

function Invoke-AppRoleAssignmentCheck {
    param([hashtable]$SpIndex)

    Write-Host "Auditing application permission grants..." -ForegroundColor Cyan

    $assignmentCount = 0

    foreach ($sp in $SpIndex.Values) {

        $assignments = @()
        try {
            $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All)
        }
        catch {
            Add-Finding -Severity 'Low' -Area 'Coverage' -Object $sp.DisplayName `
                -Detail "Could not read app role assignments: $($_.Exception.Message)" `
                -Risk 'This application was not fully assessed.' `
                -Remediation 'Re-run with an account that can read this service principal.'
            continue
        }

        if ($assignments.Count -eq 0) { continue }
        $assignmentCount += $assignments.Count

        foreach ($assignment in $assignments) {

            $resource = $null
            if ($SpIndex.ContainsKey($assignment.ResourceId)) { $resource = $SpIndex[$assignment.ResourceId] }

            $permission   = Resolve-AppRoleName -ResourceServicePrincipal $resource -AppRoleId $assignment.AppRoleId
            $resourceName = if ($null -ne $resource) { $resource.DisplayName } else { $assignment.ResourceDisplayName }

            if (-not (Test-HighRiskPermission -Permission $permission -Type 'Application')) {
                Add-Finding -Severity 'Info' -Area 'Application permission' -Object $sp.DisplayName `
                    -Detail "Holds application permission '$permission' on $resourceName." `
                    -Risk 'Not on the high-risk list.' `
                    -Remediation 'No action required.'
                continue
            }

            $publisher = Get-PublisherLabel -ServicePrincipal $sp

            Add-Finding -Severity 'Critical' -Area 'Application permission' -Object $sp.DisplayName `
                -Detail "Holds APP-ONLY permission '$permission' on $resourceName. Application has $publisher." `
                -Risk "Runs without a signed-in user. Not gated by any user's MFA and not stopped by disabling a user account. '$permission' at app-only scope reaches every object the API exposes, tenant-wide." `
                -Remediation "Confirm this app is expected and owned by your organization. If not: Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId '$($sp.Id)' -AppRoleAssignmentId '$($assignment.Id)'"
        }
    }

    Write-Host "  Reviewed $assignmentCount application permission assignment(s)." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Check 3: publisher trust on apps that hold high-risk access
# ---------------------------------------------------------------------------

function Invoke-PublisherCheck {
    param([hashtable]$SpIndex)

    Write-Host "Checking publisher verification..." -ForegroundColor Cyan

    $elevated = @($script:Findings |
        Where-Object { $_.Severity -in @('Critical', 'High') } |
        Select-Object -ExpandProperty Object -Unique)

    foreach ($sp in $SpIndex.Values) {

        if ($elevated -notcontains $sp.DisplayName) { continue }
        if ($sp.ServicePrincipalType -ne 'Application') { continue }

        $verified = $null
        try { $verified = $sp.VerifiedPublisher } catch { $verified = $null }

        $isVerified = ($null -ne $verified -and -not [string]::IsNullOrWhiteSpace($verified.DisplayName))
        if ($isVerified) { continue }

        Add-Finding -Severity 'Medium' -Area 'Publisher trust' -Object $sp.DisplayName `
            -Detail "Holds elevated permissions but has no verified publisher. Sign-in audience: $($sp.SignInAudience)." `
            -Risk 'Unverified multi-tenant applications are the common shape of an illicit consent grant. Combined with elevated permissions this warrants explicit confirmation that the app is expected.' `
            -Remediation 'Confirm the app against your software inventory. If unrecognized, revoke its grants (see the related findings) and review sign-in logs for the app ID.'
    }
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

function Write-Report {
    param([string]$Path)

    $sorted = $script:Findings | Sort-Object @{ Expression = { $script:SeverityRank[$_.Severity] } }, 'Area', 'Object'

    $shown = if ($IncludeInfo) { $sorted } else { $sorted | Where-Object { $_.Severity -ne 'Info' } }

    Write-Host ""
    Write-Host "================ OAuth consent audit ================" -ForegroundColor White

    $counts = $script:Findings | Group-Object Severity
    foreach ($level in @('Critical', 'High', 'Medium', 'Low', 'Info')) {
        $match = $counts | Where-Object { $_.Name -eq $level }
        $n = if ($null -ne $match) { $match.Count } else { 0 }
        if ($n -eq 0) { continue }

        $color = switch ($level) {
            'Critical' { 'Red' }
            'High'     { 'Red' }
            'Medium'   { 'Yellow' }
            'Low'      { 'DarkYellow' }
            default    { 'DarkGray' }
        }
        Write-Host ("  {0,-9} {1}" -f $level, $n) -ForegroundColor $color
    }
    Write-Host ""

    foreach ($finding in $shown) {
        $color = switch ($finding.Severity) {
            'Critical' { 'Red' }
            'High'     { 'Red' }
            'Medium'   { 'Yellow' }
            'Low'      { 'DarkYellow' }
            default    { 'DarkGray' }
        }

        Write-Host "[$($finding.Severity)] $($finding.Area): $($finding.Object)" -ForegroundColor $color
        Write-Host "  Detail      : $($finding.Detail)"
        Write-Host "  Risk        : $($finding.Risk)"
        Write-Host "  Remediation : $($finding.Remediation)"
        Write-Host ""
    }

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $csv = Join-Path -Path $Path -ChildPath "consent-grant-audit-$stamp.csv"
    $sorted | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

    Write-Host "Full report (including Info findings): $csv" -ForegroundColor Green
    Write-Host ""
    Write-Host "This script made no changes. Revoking an OAuth grant is a" -ForegroundColor DarkGray
    Write-Host "high-blast-radius identity change and is left to you to run" -ForegroundColor DarkGray
    Write-Host "deliberately, using the commands above." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    Connect-Tenant

    $spIndex = Get-ServicePrincipalIndex

    Invoke-DelegatedGrantCheck   -SpIndex $spIndex
    Invoke-AppRoleAssignmentCheck -SpIndex $spIndex
    Invoke-PublisherCheck        -SpIndex $spIndex

    Write-Report -Path $OutputPath
}
catch {
    Write-Host "Audit failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
