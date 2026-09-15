# Article 1 — Auditing Entra ID OAuth Consent Grants

**Target:** DigitalOcean "Write for DOnations" — $300 cash (PayPal), plus a separate
$300 charity donation. No audience gate, published rate, confirmed active 2026.

**Status:** draft complete, not yet submitted.

## Files

| File | What it is |
|---|---|
| `article.md` | The tutorial, ~2,580 words, in DigitalOcean's markdown conventions (`[secondary_label Output]`, `<$>[note]`, `<^>highlight<^>`) |
| `Get-ConsentGrantAudit.ps1` | The companion script the tutorial builds toward, 461 lines |

## Verification done

- `Get-ConsentGrantAudit.ps1` parses clean under PowerShell 7.4.6 (0 syntax errors)
- Full audit logic exercised end-to-end against a mock tenant: 4 service principals,
  2 delegated grants, 2 app role assignments -> 6 findings, correct severity ordering,
  CSV export verified
- All 15 PowerShell blocks in `article.md` parse independently
- `.ps1` is pure ASCII (no em-dashes, smart quotes, or non-breaking spaces)
- Non-ASCII in `article.md` is confined to prose headings, never code blocks

**One real bug was caught by the mock run and fixed:** under `Set-StrictMode`, a
`Where-Object` pipeline returning exactly one object has no `.Count` property. Every
pipeline result is now wrapped in `@()`. This would have failed intermittently, only in
tenants that happened to have exactly one match — the worst kind of bug to ship in a
tutorial. It is now called out in the article as a warning box, which turns the near-miss
into one of the piece's more useful passages.

## Not yet verified — must happen before submission

- [ ] **Run against a real dev tenant.** The mock proves the logic; it does not prove the
      Graph cmdlet signatures, property names, or `-Property` projection behave as expected
      against live Microsoft Graph. Get a free M365 Developer tenant and run it.
- [ ] Replace the sample output blocks with real (dev-tenant) output
- [ ] Confirm `Microsoft.Graph.Applications` version in Step 1 matches what actually installs
- [ ] Re-read DigitalOcean's current style guide before submitting

## Submission checklist (from the pitch asset)

- [ ] Every command tested end-to-end in a clean dev tenant
- [ ] **No client data.** No admin UPNs, no `.onmicrosoft.com` domains, no tenant GUIDs,
      no real org names — in prose, code, or sample output
- [ ] Sample output is from a dev tenant, hand-checked
- [ ] Least-privilege scopes — the tutorial argues for read-only and must not contradict itself

## Design decisions worth keeping in later articles

1. **Read-only scopes enforced at the API layer**, not by discipline. The tool cannot revoke
   a grant because its token lacks the permission. This is the piece's strongest argument and
   it generalizes to any scanner.
2. **Recommend, never apply.** Matches the standing remediation policy: OAuth/app-role revokes
   are high-blast-radius (Class B), so the tool prints the exact command and stops.
3. **Findings carry Risk and Remediation, not just Detail.** A list of grants is not an audit.
