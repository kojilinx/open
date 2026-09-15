# DigitalOcean "Write for DOnations" — highest-certainty $300

**Apply:** digitalocean.com/community/pages/write-for-digitalocean
**Pays:** $300 cash via PayPal, plus a separate matching $300 charity donation
(the donation is *in addition to* your payout, not instead of it)
**Gate:** none — no audience, no follower count, no prior byline required

## Why this is the anchor of the 30-day plan

Published rate. Confirmed active. No eligibility threshold. Standard
invoice-to-payment cycle rather than a platform payout lag. It alone gets you to 75%
of $400.

## What they want

Tutorial format: a reader follows along start to finish and ends with a working
result. Prerequisites stated up front, every command shown, explained output. They
care more about a reader succeeding than about your prose.

## Pitch

**Subject:** Tutorial pitch — auditing Microsoft 365 tenant security with PowerShell

Hi,

I'd like to write a tutorial for Write for DOnations.

**Proposed:** *How to Audit Microsoft 365 OAuth Consent Grants with PowerShell*

Third-party app consent is one of the most-exploited and least-inspected surfaces in
a Microsoft 365 tenant — an attacker who gets a user to consent to a malicious app
keeps mailbox access that survives a password reset and, in many configurations,
MFA. Most admins have never enumerated what's actually consented in their tenant.

The tutorial walks through connecting to Microsoft Graph with least privilege,
enumerating service principals and their delegated and application permissions,
flagging high-risk grants (Mail.ReadWrite, full_access_as_app, and similar), and
exporting a reviewable report. Reader finishes with a working script and a real
inventory of their own tenant.

**Prerequisites:** a Microsoft 365 tenant (a free developer tenant works),
PowerShell 7+, Microsoft.Graph module.
**Audience:** sysadmins and cloud/security engineers.
**Length:** ~2,500-3,000 words with complete, tested code.

I'm an M365 security consultant working in Entra ID, Exchange Online, and incident
response; this is tooling I build and use in practice.

Alternative topics if this one's taken: detecting malicious inbox rules and
mail-forwarding in Exchange Online, or building a read-only tenant security posture
scanner.

Thanks,
Koji

## Before submitting

- [ ] Every command tested end-to-end in a clean dev tenant
- [ ] **No client data.** No admin UPNs, no `.onmicrosoft.com` domains, no tenant
      GUIDs, no real org names — in the prose, the code, or the sample output
- [ ] Sample output is from a dev tenant, hand-checked
- [ ] Least-privilege scopes — do not tell readers to grant more than the task needs
