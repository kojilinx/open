# +$400/month Revenue Plan

**Goal:** +$400/month
**Time budget:** 5-10 hrs/week
**Deadline:** first money within 30 days
**Chosen vehicles:** content/creator income + small SaaS
**Constraint:** cost-free to start

---

## 1. The core tension, stated plainly

Content income and micro-SaaS are the two **slowest-ramping** revenue vehicles
available, and 30 days is the **fastest** deadline. Research confirms neither
reaches $400/mo *recurring* in 30 days from a standing start:

| Path | Blocker | Realistic first dollar |
|---|---|---|
| YouTube ad revenue | 1,000 subs + 4,000 watch hrs (bar **doubled Aug 2026**, rising again Feb 2027); then $100 AdSense floor, ~day-21-of-next-month payout, mailed PIN + tax form for new payees | 6-12+ months |
| Paid newsletter subs | beehiiv **median free-to-paid conversion is 0.62%**; plan 1-3%. 1,000 subs x 2% x $9 = ~$180/mo — and you need the 1,000 subs first | 6+ months |
| Course authoring | 4-8 weeks production before publish, then net-30/60 royalties | 3-4 months |
| Micro-SaaS | Multi-tenant OAuth + Microsoft publisher verification gate + finding 8-15 payers | 3-6 months minimum |

So the plan does **not** pick one. It runs three layers on different clocks:

- **Layer 1 (days 1-30): paid technical writing.** Write -> submit -> invoice -> paid.
  No audience gate, no eligibility threshold, no platform payout lag. This is what
  actually hits the deadline.
- **Layer 2 (days 14-60): a one-time digital product.** $29-49, sold on a
  zero-upfront-cost platform. Bridges toward recurring.
- **Layer 3 (month 3+): the narrow SaaS.** Gated on demand signal from Layer 2 buyers.

**Honest framing:** Layer 1 produces ~$400 of *cash*, not $400/mo of *recurring*
income. Anyone promising recurring $400 in 30 days from content or SaaS is selling
something. The recurring engine is Layers 2-3 and it takes months.

---

## 2. Layer 1 — Paid technical writing (the 30-day lever)

> **DECISION (2026-09-15): this is the chosen route.** Layers 2 and 3 below are retained as
> the month 2-6 roadmap but are not being worked yet. Article 1 is drafted and verified in
> `articles/01-entra-oauth-consent-audit/`.
>
> **UPDATE: the goal widened from one-off cash to recurring weekly assignments.** See
> [`recurring-pipeline.md`](recurring-pipeline.md), which supersedes parts of this section.
> Two corrections land there: **Practical365 is closed to new contributors**, and the
> developer-content agencies are a **poor fit** for M365/Windows expertise - pure-play
> cybersecurity content agencies are the better target.

Your existing expertise (M365 / Entra / Exchange / PowerShell security tooling,
incident response) maps directly onto outlets that pay cash per article.

### Targets, ranked by certainty

| Outlet | Rate | Fit | Confidence |
|---|---|---|---|
| **DigitalOcean "Write for DOnations"** | **$300 cash** (PayPal) + a separate matching $300 charity donation | Strong — sysadmin/cloud/security tutorials in scope | **Highest.** Published rate, confirmed active 2026, no audience gate |
| **LogRocket Blog** | **up to $350/article** (2,500-3,000 words, code + repo) | Good — pitch a PowerShell/Entra automation angle | High. Public guest-author application |
| **Toptal Engineering Blog** | **$500+** | Good, but vetted-expert positioning, competitive | Medium — stretch submission |
| **4sysops.com** | "above average" + traffic bonus — **no public figure** | *Best topical fit that exists* (Windows/PowerShell/cloud, IT pros) | **Email for rate BEFORE writing** |
| **Practical365.com** | **CLOSED to new contributors** | Was the most on-topic outlet alive (Exchange/Entra/PowerShell, MVP-run) | **Not currently an option.** Recheck monthly - see `recurring-pipeline.md` |

### The math

DigitalOcean ($300) + LogRocket ($350) = **$650**, clearing the goal with room.
Either one alone gets you 75-90% of the way there.

### Do not touch

- **Guest-post SEO farms** (SecureBlitz, VistaInfoSec, CyberSafetyZone and the long
  tail of "cybersecurity write for us" results). These are link-building operations
  that pay in exposure. They will look bad next to real bylines.
- **The New Stack** — contributor program is **paused as of July 2026**.
- **ITPro Today "Industry Perspectives"** — payment status unconfirmed; the format is
  usually an unpaid expert column. Pitch later for authority, not for this goal.

### 30-day schedule (fits 5-10 hrs/week)

| Days | Action | Hours |
|---|---|---|
| 1 | Send rate-inquiry email to 4sysops (template in `pitches/`). **Practical365 is closed - skip it.** Costs 20 min, runs in background all month. | 0.5 |
| 1-2 | Submit DigitalOcean topic pitch + LogRocket guest-author application **in parallel**. Do not wait for one to answer. | 2 |
| 3-10 | Draft article #1 (whichever accepts first). 2,500-3,000 words, working code, real repo. | 6-8 |
| 11-14 | Submit #1. Start article #2 immediately — do not idle waiting on edits. | 4 |
| 15-25 | Draft + submit article #2. Handle revision rounds on #1. | 6-8 |
| 26-30 | Invoice. Chase anything outstanding. | 1 |

### Article topics that fit both your expertise and their editorial needs

1. *Auditing OAuth consent grants in Entra ID with PowerShell* — shadow-IT/app-consent
   attack surface. Genuinely under-covered, directly your IR wheelhouse.
2. *Detecting malicious inbox rules and mail-forwarding at scale in Exchange Online* —
   the single most common BEC persistence mechanism.
3. *Auditing Conditional Access policy drift with PowerShell* — every tenant has this
   problem and nobody has a clean writeup.
4. *Building a read-only M365 tenant security posture scanner* — cloud/sysadmin
   tutorial framing, fits DigitalOcean's format well.

**Critical:** write clean-room. Nothing derived from a client engagement, no client
data, no tenant identifiers, no admin UPNs, no `.onmicrosoft.com` domains, no tenant
GUIDs — in the article *or* the sample output. Use a dev tenant for all screenshots.

---

## 3. Layer 2 — One-time digital product (days 14-60)

### The finding that should change your product idea

The niche is **flooded with high-quality free competition**:

- **Maester** (maester.dev) — 360+ security tests, maps to CISA SCuBA / CIS / EIDSCA, CI-CD ready
- **ScubaGear** (CISA) — M365 assessment against SCuBA baselines
- **CIPP** — free/open-source multi-tenant M365 management
- Dozens of free GitHub repos doing narrow versions of exactly this

So: **a bare script bundle has near-zero differentiation value.** Evidence backs this —
generic PowerShell script packs price at $5-25 (commodity zone), while branded,
structured guides price at $15-60.

**What sells is not the PowerShell. It is the packaging:** client-ready report output,
a written methodology a consultant can drop into a real engagement, and your name
behind it.

### Product spec

- **What:** "M365 Tenant Security Assessment Kit" — scripts *plus* a client-ready
  report template, a written engagement methodology (how to scope, run, and present
  it), and a findings-to-remediation mapping.
- **Buyer:** solo MSP owners and consultants who need to *deliver* an assessment, not
  admins who need to *run* a scan (the latter use Maester for free).
- **Price:** **$29-49**. *Assumption, not a verified fact* — inferred from comparable
  pricing; every M365-niche digital product found sits under $60. No hard
  "expense-without-approval" threshold could be sourced for IT/MSP procurement.
- **Platform: Lemon Squeezy** — 5% + $0.50, **full merchant of record** (handles
  VAT/sales tax globally), no monthly fee.

### Platform comparison (verified, 2026)

| Platform | Fee | Merchant of record | Note |
|---|---|---|---|
| **Lemon Squeezy** | 5% + $0.50 | **Yes** | Cheapest all-in MoR. **Recommended.** |
| Gumroad | 10% + $0.50 (30% via Discover) | **Yes** (since Jan 2025) | Most recognized in this niche; ~2x the fee. Unverified accounts now need $100 balance before first payout. |
| Payhip | 5% free plan / 2% at $29mo / 0% at $99mo — **plus** Stripe ~2.9%+$0.30 always | No | Effective ~8-10% on free plan |
| Stripe Payment Links | 2.9% + $0.30 only | **No** — you own VAT/sales-tax compliance | Cheapest headline rate, real compliance burden solo |
| GitHub Sponsors | 0% on personal accounts | n/a | Recurring support, not product sales |

### Also do this, it is free

**Enable GitHub Sponsors on any public repo you already maintain.** Zero cost, zero
platform fee, zero promotional friction. The niche precedent is strong — CIPP's
maintainer is reported to be the largest individual GitHub Sponsors recipient
worldwide, funded by exactly this audience. Unreliable as a primary plan, but it
costs nothing to turn on.

### Distribution — the actual bottleneck

| Channel | Size | Promo tolerance |
|---|---|---|
| **MSPGeek** (mspgeek.org, Discord + Slack) | Mid | Community-run, likely most tool-friendly. **Start here.** |
| **r/msp** | ~188K | Vendor-skeptical, self-promo restricted. Disclose affiliation explicitly. One post, on-topic only. |
| **r/sysadmin** | ~1.3M | Heavily policed by AutoMod; use designated tool-share threads only |
| **HTMD Community** | Mid | Established Intune/M365 community; no public rate card — direct outreach |

**Verify current self-promotion rules yourself before posting.** Reddit was
unreachable from the research environment, so those rules are secondhand. Getting
banned from r/msp costs you the channel permanently.

---

## 4. Layer 3 — Narrow SaaS (month 3+, gated)

**Do not start this in month 1.** Research confirms 3-6 months minimum even part-time.

### Scope it narrow

Not a CIPP competitor. The real-world anchor is CIPP's **$99/mo hosted tier** for a
full multi-tenant management platform — so a $29-59/mo indie tool must be far
narrower. Viable scope: **one recurring report, delivered by email or Teams, no
dashboard to maintain.** E.g. a weekly Conditional Access drift report, a weekly
OAuth consent-grant diff, or a weekly mail-forwarding-rule scan.

### The hard gates (verified)

- **Publisher verification is effectively mandatory.** Free, but requires a completed
  Partner Center account. Since Nov 2020, Microsoft's risk-based step-up consent
  **blocks users from consenting to unverified multi-tenant apps** requesting more than
  basic sign-in. An unverified app cannot onboard tenants with default settings.
- **Partner Center enrollment is free but in flux** — legacy MPN benefit tiers are
  being discontinued through Jan 2026. Verify the current path before spending time.
- **Admin consent per tenant** — every client's global admin must actively grant
  consent. Real per-customer onboarding friction a script-seller never has.
- **AppSource listing review takes up to 4 weeks.** Skip the marketplace for v1.
- **Liability is a different risk class.** Tech E&O runs ~$60/mo (~$730/yr). The larger
  issue is architectural: one bug in a multi-tenant app holding application
  permissions can expose every customer's tenant simultaneously. You know this better
  than most — build read-only, least-privilege, and log everything.
- **Data residency / GDPR** — unresolved. Needs dedicated work before any EU/UK client.

### Cost-free hosting (verified)

- **Azure Functions** — 1M executions/month free **permanently** (not a trial)
- **Azure Static Web Apps** — free tier: 1GB storage, 100GB bandwidth/month
- **Warning: Azure has no automatic spend cap.** Set budget alerts on day one.

This is a genuine $0/month stack at 8-15 customers, which makes breakeven trivial.

**Note:** no real indie/solo M365-security SaaS in the $29-59/mo range could be found
in research. That is either an open niche or a signal the category does not work at
that price. **Treat $29-59/mo x 8-15 customers as an unvalidated hypothesis** and
validate it in conversations with Layer 2 buyers before writing code.

---

## 5. Affiliate income (passive stack-on, not a lever)

Add to articles and community answers where genuinely relevant. Will not produce $400
alone from a cold start — this is a bonus on content published for other reasons.

| Program | Commission | Cookie |
|---|---|---|
| **Hack The Box** | 10-24% | **90 days** (best found) |
| Pluralsight | $1/trial + ~30% first month | 30-45 days |
| 1Password (Impact) | $2/signup + 25% first year | 30-45 days |
| Keeper Security | 10% | 30 days |
| Udemy | 8-16% | 7 days only — weak |
| TryHackMe | up to 5% | unverified |

Rates unverified: NordLayer, Bitwarden, Proton, INE, Cybrary.
No consumer affiliate program exists: CompTIA, SANS.

---

## 6. Newsletter sponsorship (only if a list already exists)

- B2B SaaS/tech CPM: **$35-70**; specialized B2B niches reach **$80-200**.
- An IT-decision-maker / MSP-owner audience commands the **top** of that range — it is
  among the highest-value audiences per subscriber that exists.
- At 1,000 subs: ~$50-70/send. At 5,000 with a real practitioner audience:
  $150-350/send, so 2 sends clears $400.
- **Marketplace: Swapstack** (beehiiv-owned) — advertisers set their own minimums; a
  booking under 700 subscribers has been reported. **Paved requires ~5,000 subscribers**
  to list as a publisher, so it is likely closed to you initially.
- **Direct vendor outreach beats both** at small scale and has no minimum.
- Platform fees: Substack 10% + Stripe | beehiiv 0% (free under 2,500 subs, then
  ~$39/mo) | Ghost ~$9-11/mo, no free tier. beehiiv only beats Substack above
  ~$430-500/mo of paid-sub revenue.

---

## 7. Decision rules

**Kill criteria — stop and reassess if:**
- Day 14 with zero outlet responses -> the pitch is the problem, not the market. Rewrite
  it around a specific article outline rather than a topic area.
- Day 45 with zero product sales after posting to 2+ communities -> the packaging
  thesis is wrong. Talk to five MSP owners before building anything else.
- Any Layer 3 work starting before Layer 2 has real buyers -> stop. That is the
  expensive mistake this plan exists to prevent.

**Success ladder:**
- Day 30: ~$400-650 cash from writing. Goal met, not yet recurring.
- Day 60: product live, first sales. $50-200/mo, lumpy.
- Month 3-6: recurring layer real, either via repeat writing (the most reliable — it
  is a renewable relationship, not a one-off), product volume, or a narrow SaaS.

**The underrated outcome:** a DigitalOcean or 4sysops byline is a *repeatable*
relationship. Two paid articles a month is $600-700/mo indefinitely and is by far the
most reliable route to durable +$400/mo given your skills and hours.

---

## 8. Confidence and unverified items

Verified with current sources: DigitalOcean and LogRocket rates; YouTube eligibility
thresholds and payout mechanics; beehiiv conversion median; all platform fee
structures; Microsoft publisher-verification consent blocking; Azure free tiers;
AppSource review timeline; the free-competition landscape.

**Explicitly unverified — confirm before relying on:**
- 4sysops per-article rate (page unreachable)
- ~~Practical365 contributor status~~ - resolved: CLOSED to new contributors
- The $29-49 price point (inference from comps, not a sourced threshold)
- r/msp and r/sysadmin exact current self-promo rules (Reddit unreachable in research)
- NordLayer / Bitwarden / Proton affiliate percentages
- M365-specific newsletter sponsorship rate cards (HTMD, Practical365, Petri)
- Whether an indie $29-59/mo M365 security SaaS has ever worked — none found
