# Recurring Technical Writing: Pipeline Strategy

Goal: a **steady stream of paid technical writing assignments**, 5-10 hrs/week,
starting from **zero published bylines**.

> **Sourcing caveat, applies to this entire document.** The research pass behind it had
> direct page fetches blocked at the network layer, so nearly every figure comes from search
> snippets and third-party citations (Glassdoor, Indeed, comparison blogs, other writers'
> write-ups) rather than the organizations' own pages. Confidence is marked per item.
> **Verify any rate by applying, before you plan around it.**

---

## 1. The finding that reframes everything

**Developer-content agencies are a poor fit for your actual specialty.**

Draft.dev, Hackmamba, Codeless and similar are cloud-native / DevOps / devtools shops.
Where they cover security at all, it is DevSecOps, AppSec, cloud-workload and API security -
not Windows Server, Active Directory, Exchange, or M365 administration. Pitching
"how to secure Exchange Online" into that network is pitching into the wrong room.

Two usable responses:

**a) Reframe, honestly.** Entra ID, OAuth consent phishing, and Conditional Access *are*
cloud identity security, not legacy on-prem sysadmin. Pitched as "cloud identity security"
or "SaaS security posture," your expertise lands in a category these agencies do buy. This
is accurate positioning, not spin - but it will not make a straight Exchange Online pitch
work.

**b) Target cybersecurity content agencies instead.** This is the more useful redirection.
Pure-play security content shops are a much closer match than devtools shops:

| Agency | Why it fits | Confidence |
| --- | --- | --- |
| **ContentLab** (contentlab.io/writeforus/) | Lists **Security** as a first-class vertical; names **Microsoft** among client brands. The one honest exception among the devtools agencies | Verticals/clients: reported. Rate (~$500/article, one source spread $200-700): **unconfirmed** |
| **Megawatt** (megawattcontent.com, now part of LaunchSquad) | Built around cybersecurity/compliance since 2015. Clients incl. Trend Micro, Snyk, Vanta, Proofpoint. Covers **identity security** - closest match to your OAuth/Entra work | No public writer application found; approach via direct outreach/LinkedIn |
| **Siege Media** | Actively posting a Freelance Cybersecurity Content Writer role. Wants 2-3 yrs security content experience. Zero Trust, threat intel, IR | Role posting: reported. Rate: not found |
| **nDash** | Invite/application-gated marketplace with an active cybersecurity writer pool. Reported $150-450/assignment | Mid-term target, once clips exist |
| **Draft.dev** | Largest network, weekly topic-need emails to writers. Reported $300-500/article | **Weak-to-moderate fit.** Apply only with a cloud-identity angle |

Agencies to deprioritize for this specialty: Hackmamba (Web3/devrel identity, no Microsoft or
security signal), Codeless (devtools-first, no security signal). "Contenty" could not be
confirmed as a real distinct company - the likely match is **Contently.com**, a general
content marketplace that sources via talent scouts rather than open applications.

---

## 2. The clips problem has a concrete answer

You have zero bylines. Agencies gate on 2-3. The fastest credible route found:

### Foundry Expert Contributor Network - do this first

Covers **CSO Online, CIO, Computerworld, InfoWorld, Network World**. It is an open,
self-service, **unpaid** bylined platform. Crucially: **no prior clips required.** Acceptance
turns on signing their writer agreement and submitting quality vendor-neutral content, not on
a portfolio review.

That is the whole unlock. It converts "I have no bylines" into "I have published in CSO
Online" without needing anyone's paid acceptance first.

Two pieces to write there, drawn from genericized consulting experience:
- *What OAuth consent phishing looks like in Entra ID sign-in logs*
- *A practical Conditional Access review checklist*

Both must be vendor-neutral and non-promotional, and both go through the same client-data
hygiene rules as everything else: no privileged UPNs, no `.onmicrosoft.com` domains, no
tenant GUIDs, no client names.

**Similar open, unpaid, no-clips-required outlets** for a third byline:
Help Net Security "Experts Corner"; Infosecurity Magazine op-ed program (800-1,000 words,
exclusive, reply only if accepted).

### Does self-published work count as a clip?

**Confirmed yes** for Contently (their portfolio tool explicitly accepts "at least one
published (or self-published) article") and moot for the Foundry network (no clips needed).
**Plausible but unconfirmed** for the devtools agencies - working writers widely report
personal blog / dev.to posts being accepted, but no agency's own page could be read to
confirm it as policy.

### Sequence

1. **Weeks 1-4** - two Foundry network pieces (CSO Online or Computerworld). Unpaid, real
   bylines, recognized outlets.
2. **In parallel** - the Entra OAuth consent audit tutorial already drafted, either placed at
   DigitalOcean ($300, paid) or self-published as a portfolio-quality sample.
3. **Weeks 4-6** - with 2-3 clips in hand, apply to ContentLab and Pluralsight, and do direct
   outreach to Megawatt and Siege Media.

Zero to a credible application package in roughly 4-6 weeks, without needing anyone's paid
acceptance as a prerequisite.

---

## 3. The under-known lane: certification and training content

This is the most concretely verified paid, recurring work found.

### CompTIA item writing - best verified paid option

- **$440/day** (US-based SME), **$2,200 for a full-week workshop**. International SMEs
  $540/day. *Confidence: figures found and consistent; verify on application.*
- Apply: comptia.org subject-matter-expert program, `examdev@comptia.org`
- Workshops run several times a year (Cloud+, DevOps, SecurityX, Security+ cut-score
  observed on the 2026 schedule)
- **Eligibility catch worth checking before you invest:** CompTIA excludes
  "trainers/teachers, authors, or individuals who may profit or materially benefit from
  knowledge of the credential content." If you later sell CompTIA-aligned training or
  courseware, that may disqualify you from item-writing for the same certification. These two
  paths may be mutually exclusive - pick deliberately.

### Pluralsight authoring - best recurring-royalty option

- Open application via a ~10-minute audition video; reportedly ~10% acceptance
- Course completion fee **plus ongoing royalties tied to viewership**, paid quarterly.
  Dollar figures not public.
- Genuinely recurring - royalties continue while the course is watched
- Matches your expertise directly. Worth prioritizing.

### Ruled out - would have been wasted effort

- **ISC2 exam development: unpaid.** Explicitly voluntary. Covers travel and awards CPEs
  (useful for maintaining your own certs), but it is not income.
- **TryHackMe: does not pay for content.** Public monetization is an affiliate/referral
  program only. Not a "paid to write labs" opportunity.
- **Microsoft exam item writing:** no public application path found. Likely requires an
  existing MCT or MVP relationship rather than an open program.

---

## 4. Publication reality check

The paid-recurring-column landscape is **thinner than expected**. Most big-name IT-pro and
security outlets run *unpaid* expert-contributor or op-ed programs.

| Outlet | Status | Confidence |
| --- | --- | --- |
| **Practical365** | **CURRENTLY CLOSED to new contributors.** Was the single best topical match (Exchange, M365, Azure, PowerShell) | Reported. Recheck periodically |
| **ITPro Today** | Explicitly **does not pay** for unsolicited contributions | Stated on their site |
| **Foundry network** (CSO/CIO/Computerworld) | **Free/unpaid** platform. Great for clips, not income | Confirmed via their own network pages |
| **Help Net Security** | Experts Corner, expert commentary format. No pay signal | Treat as unpaid |
| **Infosecurity Magazine** | Op-ed program. No pay signal | Treat as unpaid |
| **Petri.com** | Has a contributor program; **no rate found anywhere.** Suspect unpaid | Ask directly before investing time |
| **Dark Reading** | Uses freelance contributors; pitch `edgeeditors@darkreading.com`. Reputation says they pay on assignment | **Rate unverified - needs direct inquiry** |
| **ChannelE2E / ChannelPro** | Named contributing editors suggest a small paid stable rather than an open program | **Needs cold outreach to editors** |
| **Redmond Magazine** | No contributor page found at all | Unverified |

**Practical365 closing is the most consequential update** to the earlier plan, which had it
as a top-two target to email for rates. It is not currently an option.

The two leads genuinely worth a direct email: **Dark Reading** and the **MSP channel press**
(ChannelE2E, ChannelPro). Both probably pay; neither publishes a rate.

---

## 5. Revised weekly operating shape

Given 5-10 hrs/week and that one substantial tutorial consumes most of it:

| Cadence | Activity |
| --- | --- |
| **Now, weeks 1-6** | Clips. Two Foundry pieces + place or publish the Entra tutorial |
| **Ongoing, weekly** | One drafting cycle (outline -> draft -> verify), the dashboard's job |
| **Monthly** | Recheck closed/unknown-status outlets (Practical365 especially); one direct-outreach email (Dark Reading, ChannelE2E, Megawatt) |
| **Quarterly** | CompTIA workshop schedule check - low volume, a handful of postings a year |
| **Once** | Pluralsight audition video. Highest recurring upside, one-time cost |

**Realistic income shape:** the recurring money is more likely to come from CompTIA workshops
($2,200/week when they run) and Pluralsight royalties than from a weekly article drumbeat.
Weekly *assignments* and weekly *income* are different things, and the training lane pays
better per hour than most of the publication lane - which is mostly unpaid.

---

## 6. Explicitly unverified

- Every agency rate (fetches blocked; all third-party-reported)
- Clip/sample requirements for Draft.dev, ContentLab, Hackmamba applications
- Whether Petri.com's contributor program pays at all
- Dark Reading, ChannelE2E, ChannelPro freelance rates
- Hackmamba's reported $700-900/article - single source, may conflate client price with
  writer payout. Treat with real skepticism
- Whether devtools agencies formally accept self-published work as clips
- "Contenty" as a distinct company - confirm the exact name/URL you meant
