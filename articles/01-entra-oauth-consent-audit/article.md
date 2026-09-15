# How To Audit Microsoft 365 OAuth Consent Grants with PowerShell

### Introduction

When an attacker wants durable access to a Microsoft 365 mailbox, stealing a password is the noisy way to do it. The quiet way is to get someone to click **Accept** on a consent prompt.

An OAuth consent grant gives an application ongoing access to data on a user's behalf. Because that access is carried by a refresh token rather than a password, it survives a password reset. Depending on how the grant was issued, it can also sit entirely outside the reach of multi-factor authentication, because no interactive sign-in ever happens again. Microsoft tracks this technique as *illicit consent grant* attacks, and the reason it works so well is mundane: almost nobody ever looks at the list.

Most tenants have accumulated consent grants for years. Some were approved by administrators for software the company genuinely uses. Others were approved by individual users clicking through a prompt for a free PDF converter. From the directory's point of view, they look similar, and the admin center paginates them in a way that makes systematic review tedious.

In this tutorial, you will build a read-only PowerShell tool that enumerates every OAuth consent grant in a Microsoft Entra ID tenant, separates the two kinds of consent that carry very different risk, scores the grants that actually matter, and exports a reviewable report.

By the end, you will have a script you can run on any tenant you administer and a clear inventory of which applications can read your organization's mail.

## Prerequisites

To follow this tutorial, you will need:

- A Microsoft 365 or Microsoft Entra ID tenant. A free [Microsoft 365 Developer tenant](https://developer.microsoft.com/microsoft-365/dev-program) works and is the recommended way to follow along, since you will be reading directory-wide configuration.
- An account with at least the **Global Reader** role in that tenant. Global Reader is sufficient for everything in this tutorial, because the tool never writes. Do not use Global Administrator if you do not need to.
- PowerShell 7 or later. Windows PowerShell 5.1 also works. Verify with `$PSVersionTable.PSVersion`.
- Familiarity with running PowerShell commands and reading objects.

<$>[note]
**Note:** Run this against a tenant you are authorized to audit. Enumerating service principals and consent grants is a read-only operation, but it is still directory reconnaissance, and it belongs in the same category as any other security assessment activity.
<$>

## Step 1 — Installing the Microsoft Graph PowerShell SDK

The tool uses the Microsoft Graph PowerShell SDK. Install it for your user account only, which avoids needing local administrator rights:

```command
Install-Module Microsoft.Graph -Scope CurrentUser
```

The full SDK is large because it covers all of Microsoft Graph. If you prefer a smaller install, the two submodules this tutorial needs are enough:

```command
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Applications -Scope CurrentUser
```

Confirm the module is available:

```command
Get-Module Microsoft.Graph.Applications -ListAvailable | Select-Object Name, Version
```

```
[secondary_label Output]
Name                          Version
----                          -------
Microsoft.Graph.Applications  2.25.0
```

<$>[warning]
**Warning:** If your organization still has the retired **MSOnline** or **AzureAD** modules installed, do not use them here. Both reached end of support and no longer return complete data for newer directory objects. The Graph SDK is the current path.
<$>

If PowerShell refuses to run your saved script file later with a `PSSecurityException` or `UnauthorizedAccess` error, the file is being blocked by execution policy. The cleanest fix is per-invocation and changes nothing machine-wide:

```command
powershell.exe -ExecutionPolicy Bypass -File .\Get-ConsentGrantAudit.ps1
```

A script cannot lift its own load-time policy block, so this has to happen at the point you launch it.

## Step 2 — Connecting with Read-Only Scopes

Connect to Graph requesting only what the audit needs:

```command
Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All" -NoWelcome
```

A browser window opens for sign-in. On first use in a tenant, an administrator has to consent to these scopes for the Microsoft Graph PowerShell application itself.

Both scopes are read-only, and that is deliberate. A scanner has no business holding write permissions. If a bug in your own tooling can only ever read, the worst case is a bad report rather than a damaged tenant. Confirm what you actually received:

```command
(Get-MgContext).Scopes
```

```
[secondary_label Output]
Application.Read.All
Directory.Read.All
```

<$>[note]
**Note:** Resist the temptation to request `Application.ReadWrite.All` so the script can revoke grants it finds. Revoking a consent grant can break a production integration instantly, and the blast radius of a mistake is tenant-wide. This tutorial builds a tool that recommends and never applies. You will see why in Step 6.
<$>

## Step 3 — Understanding the Two Kinds of Consent

Before enumerating anything, you need the distinction that drives the entire risk model. Microsoft Entra ID grants application access in two fundamentally different ways.

**Delegated permissions** let an application act *on behalf of a signed-in user*, and only within what that user can already do. They are stored as `oauth2PermissionGrant` objects. A delegated grant has a `consentType`:

- `Principal` means one specific user consented. The grant covers that user alone.
- `AllPrincipals` means an administrator consented for the whole tenant. One object, every user covered.

**Application permissions** let an application act *as itself*, with no user involved at all. They are stored as `appRoleAssignment` objects. This is the category that should get your attention first:

- There is no signed-in user, so there is no user MFA in the path.
- Disabling a user account does not affect it.
- The access is tenant-wide by nature, not limited to one person's mailbox.

An application permission of `Mail.ReadWrite` means that application can read and write *every mailbox in the tenant*, silently, forever, until someone revokes the assignment. That is why the tool you are building scores app-only permissions harder than delegated ones.

## Step 4 — Enumerating Delegated Permission Grants

Start by pulling the raw grants so you can see the shape of the data:

```command
Get-MgOauth2PermissionGrant -All | Select-Object -First 3 Id, ClientId, ResourceId, ConsentType, Scope
```

```
[secondary_label Output]
Id          : lAFdN2R5aEy0Pz1pVQ3nQ...
ClientId    : 7c9b2f41-5d3a-4e18-9f62-2a1b8c4d7e05
ResourceId  : 41b3a7c2-9e84-4f16-b5d7-3c8e1a6f2d94
ConsentType : AllPrincipals
Scope       : User.Read Mail.Read offline_access
```

Two things stand out. First, `ClientId` and `ResourceId` are object IDs, not names, so the output is unreadable until you resolve them. Second, `Scope` is a single space-delimited string rather than a collection.

Resolve the IDs by building a lookup table of every service principal once, up front, rather than calling Graph for each grant:

```command
$all = @(Get-MgServicePrincipal -All -Property Id, AppId, DisplayName, AppRoles, PublisherName, VerifiedPublisher, SignInAudience, ServicePrincipalType)
$spIndex = @{}
foreach ($sp in $all) { $spIndex[$sp.Id] = $sp }
$spIndex.Count
```

```
[secondary_label Output]
247
```

<$>[note]
**Note:** A tenant that has never had an application registered still reports dozens of service principals. Microsoft pre-provisions its own first-party applications. A high count is normal and is not itself a finding.
<$>

Now the grants become readable. Split the scope string and check it against a list of permissions that carry real data access:

```
$highRiskDelegated = @(
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

foreach ($grant in @(Get-MgOauth2PermissionGrant -All)) {
    $scopeList = @($grant.Scope.Trim() -split '\s+')
    $risky = @($scopeList | Where-Object { $highRiskDelegated -contains $_ })
    if ($risky.Count -eq 0) { continue }

    $clientName = $spIndex[$grant.ClientId].DisplayName
    $tenantWide = ($grant.ConsentType -eq 'AllPrincipals')

    "{0,-30} {1,-14} {2}" -f $clientName, $grant.ConsentType, ($risky -join ', ')
}
```

```
[secondary_label Output]
Timesheet Helper               AllPrincipals  Mail.Read, offline_access
PDF Converter Pro              Principal      Mail.Read, offline_access
```

`offline_access` is on the list for a reason that is easy to miss. On its own it grants no data. What it grants is a **refresh token**, which is what converts a one-time click into persistent access. A grant combining `Mail.Read` and `offline_access` means the application can keep reading that mailbox indefinitely without the user ever signing in again.

<$>[warning]
**Warning:** Note the `@(...)` wrappers around every pipeline result. When `Where-Object` matches exactly one item, PowerShell returns that single object rather than an array, and `.Count` does not exist on it under `Set-StrictMode`. Wrapping in `@()` forces an array every time. This is the single most common source of intermittent failures in directory-auditing scripts, because it only breaks when a tenant happens to have exactly one match.
<$>

## Step 5 — Enumerating Application Permissions

Application permissions live on each service principal rather than in one global collection, so you iterate:

```
foreach ($sp in $spIndex.Values) {
    $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All)
    if ($assignments.Count -eq 0) { continue }

    foreach ($assignment in $assignments) {
        "{0,-30} -> {1}" -f $sp.DisplayName, $assignment.AppRoleId
    }
}
```

```
[secondary_label Output]
Invoice Sync Connector         -> e2a3a72e-5d94-4b21-b3fa-0f4c8b1e7d63
```

The `AppRoleId` is a GUID, and it is meaningless without translation. The permission name lives on the *resource* service principal, in its `AppRoles` collection. Since you already indexed every service principal in Step 4, the lookup is local:

```
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
```

The function returns the raw GUID if it cannot resolve the name, rather than returning nothing. A report that silently drops a permission it could not translate is worse than one that shows an unresolved ID, because the reviewer has no idea something is missing.

With names resolved, the same output becomes actionable:

```
[secondary_label Output]
Invoice Sync Connector         -> Mail.ReadWrite
```

`Mail.ReadWrite` as an application permission is the finding you were looking for. That application can read and modify mail in every mailbox in the tenant, with no user context and nothing for MFA to challenge.

## Step 6 — Scoring Findings and Deciding What the Tool Does About Them

A list of grants is not an audit. An audit tells the reader what is wrong, why it matters, and what to do about it. Give every check a consistent output shape:

```
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
        Severity = $Severity; Area = $Area; Object = $Object
        Detail = $Detail; Risk = $Risk; Remediation = $Remediation
    })
}
```

The severity assignment follows directly from Step 3:

| Finding | Severity | Why |
| --- | --- | --- |
| High-risk **application** permission | Critical | App-only, tenant-wide, no MFA in the path |
| High-risk **delegated** scope, `AllPrincipals` | High | One grant covers every user in the tenant |
| High-risk **delegated** scope, `Principal` | Medium | Limited to one user's data |
| Elevated permissions, unverified publisher | Medium | Corroborating signal, not a finding alone |

Because `Severity` is a string, sort by an explicit rank rather than alphabetically:

```
$script:SeverityRank = @{ 'Critical' = 0; 'High' = 1; 'Medium' = 2; 'Low' = 3; 'Info' = 4 }

$sorted = $script:Findings |
    Sort-Object @{ Expression = { $script:SeverityRank[$_.Severity] } }, 'Area', 'Object'
```

Now the important design decision. Every finding carries the exact command that would fix it:

```
Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId '<^>id<^>' -AppRoleAssignmentId '<^>id<^>'
```

The tool prints that command. It does not run it, and it never offers to.

This is not timidity. Revoking an OAuth grant is an identity change with tenant-wide blast radius, and the failure mode is asymmetric. A tool that misidentifies a legitimate integration and revokes it takes down a production business process in the time it takes to run, with no undo. A tool that prints the command costs the operator thirty seconds. When the downside of automating is catastrophic and the downside of not automating is mild inconvenience, you do not automate.

Keeping the Graph scopes read-only in Step 2 enforces this at the API layer rather than by discipline alone. The tool *cannot* revoke a grant even if a future bug tried to, because the token it holds does not carry the permission.

## Step 7 — Running the Complete Audit

The complete script assembles these pieces and adds a CSV export. Save it as `Get-ConsentGrantAudit.ps1` and run it:

```command
powershell.exe -ExecutionPolicy Bypass -File .\Get-ConsentGrantAudit.ps1
```

```
[secondary_label Output]
Connecting to Microsoft Graph (read-only scopes)...
Enumerating service principals...
  Found 247 service principals.
Auditing delegated permission grants...
  Found 38 delegated grants.
Auditing application permission grants...
  Reviewed 12 application permission assignment(s).
Checking publisher verification...

================ OAuth consent audit ================
  Critical  1
  High      1
  Medium    2
  Info      46

[Critical] Application permission: Invoice Sync Connector
  Detail      : Holds APP-ONLY permission 'Mail.ReadWrite' on Microsoft Graph. Application has no verified publisher.
  Risk        : Runs without a signed-in user. Not gated by any user's MFA and not stopped by disabling a
                user account. 'Mail.ReadWrite' at app-only scope reaches every object the API exposes,
                tenant-wide.
  Remediation : Confirm this app is expected and owned by your organization. If not:
                Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId '...' -AppRoleAssignmentId '...'

[High] Delegated consent: Timesheet Helper
  Detail      : High-risk delegated scope(s) on Microsoft Graph: Mail.Read, offline_access. Consent covers
                ALL USERS in the tenant (admin consented). Application has publisher: Helper Apps Inc (not verified).
  Risk        : This app can act as the consenting user against Microsoft Graph. Delegated mail scopes let it
                read and send mail as that user, which survives a password reset until the refresh token is revoked.
  Remediation : Review in Entra admin center, then if unwanted:
                Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId '...'

Full report (including Info findings): .\consent-grant-audit-20260915-104109.csv
```

Info-severity findings are suppressed on screen by default and always written to the CSV. Use `-IncludeInfo` to see everything:

```command
.\Get-ConsentGrantAudit.ps1 -IncludeInfo -OutputPath C:\Reports
```

Work the report top down. For each Critical and High finding, the question is not "is this permission dangerous" — you already know it is. The question is **"do we recognize this application, and did someone here deliberately approve it?"** Check the app against your software inventory, then review sign-in logs for its application ID to see whether it is being used and from where.

<$>[note]
**Note:** Before sharing this report outside your team, strip tenant identifiers. The CSV can contain application object IDs and your tenant's directory structure. If the report is going to a client or into a ticket, remove tenant GUIDs and any administrative account names first.
<$>

## Conclusion

You built a read-only audit tool that inventories every OAuth consent grant in a Microsoft Entra ID tenant, distinguishes delegated from application permissions, scores them by real blast radius, and produces a report with an exact remediation command for every finding.

The design choices matter as much as the output. Read-only scopes mean the tool cannot damage the tenant it audits. Explicit severity ranking means the reader starts with what matters. Printing remediation commands instead of executing them keeps a human in the loop for a change that cannot be undone.

From here, you can extend the tool in a few directions:

- **Correlate with sign-in activity.** Add the `AuditLog.Read.All` scope and pull sign-in logs per application ID to separate applications that are genuinely in use from dormant grants nobody has touched in a year.
- **Track drift over time.** Save each CSV and diff consecutive runs. A *new* high-risk grant appearing between runs is a much stronger signal than the same grant sitting in a report every month.
- **Harden the consent flow itself.** The durable fix is to stop unreviewed grants from being created. Review Microsoft's guidance on [user consent settings and the admin consent workflow](https://learn.microsoft.com/entra/identity/enterprise-apps/configure-user-consent) so new applications route through an approval step.

To learn more about the objects behind this audit, see the Microsoft Graph reference for [oAuth2PermissionGrant](https://learn.microsoft.com/graph/api/resources/oauth2permissiongrant) and [appRoleAssignment](https://learn.microsoft.com/graph/api/resources/approleassignment).
