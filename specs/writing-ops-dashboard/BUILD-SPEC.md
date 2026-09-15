# Writing Ops Dashboard — Build Specification

**Single, self-contained build spec.** Everything needed to build this is in this file. It
assumes no prior conversation and no other documents.

Hand this to a local Claude Code session with: *"Build this, phase by phase. Stop after each
phase and show me it works against the acceptance criteria."*

---

## 0. How to use this document

Build in the phase order given in section 12. Each phase has acceptance criteria that must
pass before moving on. Do not build phase N+1 before N works.

Three rules that override any judgment call you make while building:

1. **Nothing is ever sent to a third party automatically.** No auto-submission, no
   auto-email. Submission is always a human action.
2. **The Disclosure Gate (section 9) is blocking and mechanical.** Never make it advisory,
   never add a skip flag.
3. **Never use `bypassPermissions`** for the drafting agent, and never add it as a config
   option. Section 8.3 explains why.

---

## 1. What this is and why

A localhost dashboard that discovers paid technical-writing opportunities, tracks each one
through a pipeline, and drives Claude Code to draft the article on demand.

**The user:** a Microsoft 365 / Entra ID / Exchange Online security consultant who writes
PowerShell security tooling — tenant audits, OAuth consent-grant auditing, Conditional
Access review, incident response. Available 5–10 hrs/week. **Zero published bylines.**

**The goal:** a steady stream of paid technical-writing assignments.

Four facts drive every design decision. Read them before writing code, because most of the
non-obvious choices below trace back to one of them.

| Fact | Consequence in the build |
| --- | --- |
| **No published clips.** Content agencies gate on 2–3 published samples. A wasted application is hard to reopen. | The clip gate (6.3) holds agency opportunities in a separate lane until clips exist. This is the single most important product decision here. |
| **Drafting is the expensive step, not finding work.** A 2,500–3,000 word tutorial with tested code is 6–8 hours by hand — the entire weekly budget. | The drafting engine (8) is the payoff feature. Discovery is secondary. |
| **A bad published article is worse than none.** These carry the user's name in a niche where professional reputation is the product. | Every draft passes a mechanical gate (9) before a human reads it. |
| **The user writes security articles while doing client incident response.** | The Disclosure Gate is blocking. Human proofreading is not a reliable control for client data leakage. |

### 1.1 Scope

**In scope:** automated opportunity discovery; a pipeline with explicit states; on-demand
drafting that commits an article plus companion code to a branch; a mechanical verification
gate; a local web UI with live run progress.

**Out of scope, deliberately:** auto-submitting to outlets; auto-sending pitch emails;
multi-user, auth, or hosting; publishing to outlet CMSes.

---

## 2. Stack and bootstrap

Node + TypeScript. SQLite. $0 infrastructure — the only variable cost is Claude usage for
drafting runs.

```bash
mkdir writing-ops && cd writing-ops
npm init -y
npm pkg set type=module
npm i fastify better-sqlite3 zod node-cron undici cheerio fast-xml-parser robots-parser \
      @anthropic-ai/claude-agent-sdk
npm i -D typescript tsx @types/node @types/better-sqlite3 vitest
npx tsc --init
```

Frontend (phase 1): `npm create vite@latest web -- --template react-ts`

**External binary:** `pwsh` (PowerShell 7+) must be on PATH for the PowerShell verification
checks. If absent, those checks degrade to a warning rather than failing the run — but say
so loudly in the UI, because silently skipping a blocking check is worse than failing.

### 2.1 Layout

```
writing-ops/
  data/writing-ops.db          # gitignored
  seed/outlets.json            # section 5.6
  seed/sources.json            # section 5.7
  src/
    server/
      index.ts                 # Fastify bootstrap, binds 127.0.0.1 ONLY
      routes/{opportunities,outlets,articles,runs,sources,stats}.ts
      db/{schema.sql,migrate.ts,queries.ts}
    discovery/
      scheduler.ts  robots.ts  normalize.ts  score.ts
      adapters/{rss.ts,jsonFeed.ts,...}      # one file per source
    drafting/
      engine.ts  promptBuilder.ts
      outletProfiles/*.json
    verification/
      index.ts  disclosure.ts  powershell.ts  ascii.ts  codeblocks.ts  wordcount.ts
    web/                       # React + Vite
  articles/                    # output; its own git repo (see 15.3)
```

### 2.2 Environment

`.env` (gitignored; commit `.env.example`):

```
PORT=8787
DB_PATH=./data/writing-ops.db
ARTICLES_REPO=../writing-articles
DISCLOSURE_DENYLIST=./data/client-denylist.txt   # gitignored, one name per line
MAX_BUDGET_USD_PER_RUN=10
RUN_TIMEOUT_MS=1800000
```

`data/client-denylist.txt` must be gitignored and must never be committed. It contains
client names for the Disclosure Gate.

---

## 3. Architecture

```
Browser (localhost:5173)  ──REST + SSE──>  Fastify API (127.0.0.1:8787)
                                                  │
        ┌─────────────────────┬───────────────────┼──────────────────┐
        │                     │                   │                  │
   Discovery            Pipeline state       Drafting engine    Verification
   scheduler            manager              (Agent SDK)        gate
        │                     │                   │                  │
        └─────────────────────┴─────────┬─────────┴──────────────────┘
                                        │
                              SQLite (better-sqlite3)
                                        │
                              articles/ git repo (one branch per article)
```

**Why SQLite:** zero-config, single file, no daemon, free. Hundreds of rows, not millions.
Do not reach for Postgres.

**Why bind 127.0.0.1 only:** there is no auth, by design. The bind address is therefore not
configurable. Do not add a `HOST` env var.

---

## 4. Non-negotiable safety rules

| Rule | Why |
| --- | --- |
| Nothing sent to any third party automatically | A misfired outward action damages a professional relationship that cannot be repaired |
| Drafting agent gets a scoped write path + tool allowlist, never blanket bypass | An unattended agent with unrestricted tools on a workstation next to client work is unbounded risk |
| Every draft passes the Disclosure Gate before it can be marked ready | Prevents client data reaching a public article |
| Discovery respects robots.txt and per-source rate limits | An IP ban costs that channel permanently |
| No credentials in the repo; secrets in `.env`, gitignored | The articles repo may later go public |

---

## 5. Data model

SQLite. All timestamps ISO-8601 UTC text. This is the actual DDL — use it.

```sql
-- src/server/db/schema.sql

CREATE TABLE IF NOT EXISTS outlets (
  id                       TEXT PRIMARY KEY,           -- slug, e.g. 'digitalocean'
  name                     TEXT NOT NULL,
  url                      TEXT,
  submission_url           TEXT,
  contact_email            TEXT,
  kind                     TEXT NOT NULL CHECK (kind IN
                             ('publication','agency','vendor','training','clip_builder')),
  rate_amount              INTEGER,                    -- CENTS. nullable
  rate_currency            TEXT DEFAULT 'USD',
  rate_confidence          TEXT NOT NULL DEFAULT 'unknown'
                             CHECK (rate_confidence IN ('verified','reported','unknown')),
  rate_source_url          TEXT,                       -- never show a rate without a source
  word_min                 INTEGER,
  word_max                 INTEGER,
  markdown_flavor          TEXT DEFAULT 'standard',    -- 'digitalocean'|'standard'|'custom'
  style_guide_path         TEXT,
  topics                   TEXT,                       -- JSON array
  accepts_new_contributors TEXT NOT NULL DEFAULT 'unknown'
                             CHECK (accepts_new_contributors IN
                               ('yes','no','unknown','paused')),
  requires_clips           INTEGER NOT NULL DEFAULT 0,
  notes                    TEXT,
  last_checked_at          TEXT
);

CREATE TABLE IF NOT EXISTS sources (
  id                   TEXT PRIMARY KEY,
  name                 TEXT NOT NULL,
  kind                 TEXT NOT NULL CHECK (kind IN ('rss','json','scrape')),
  url                  TEXT NOT NULL,
  adapter              TEXT NOT NULL,                  -- module in discovery/adapters/
  enabled              INTEGER NOT NULL DEFAULT 1,
  robots_allowed       INTEGER,                        -- NULL = not yet checked
  poll_interval_min    INTEGER NOT NULL DEFAULT 360,
  last_run_at          TEXT,
  last_status          TEXT CHECK (last_status IN ('ok','error','blocked','empty')),
  last_error           TEXT,
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  backoff_until        TEXT
);

CREATE TABLE IF NOT EXISTS opportunities (
  id             TEXT PRIMARY KEY,
  outlet_id      TEXT REFERENCES outlets(id),
  source_id      TEXT REFERENCES sources(id),
  kind           TEXT NOT NULL CHECK (kind IN
                   ('guest_post','agency_assignment','recurring_column',
                    'retainer','item_writing','clip_builder')),
  title          TEXT NOT NULL,
  url            TEXT,
  description    TEXT,
  rate_estimate  INTEGER,                              -- cents
  deadline       TEXT,
  discovered_at  TEXT NOT NULL,
  status         TEXT NOT NULL DEFAULT 'discovered',
  fit_score      INTEGER NOT NULL DEFAULT 0,
  fit_reasons    TEXT,                                 -- JSON array of strings
  blocked_reason TEXT,                                 -- e.g. 'needs_clips:2'
  notes          TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_opp_dedupe ON opportunities(outlet_id, url);
CREATE INDEX IF NOT EXISTS ix_opp_status ON opportunities(status);

CREATE TABLE IF NOT EXISTS opportunity_events (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  opportunity_id TEXT NOT NULL REFERENCES opportunities(id),
  from_status    TEXT,
  to_status      TEXT NOT NULL,
  at             TEXT NOT NULL,
  note           TEXT
);

CREATE TABLE IF NOT EXISTS articles (
  id             TEXT PRIMARY KEY,
  opportunity_id TEXT NOT NULL REFERENCES opportunities(id),
  working_title  TEXT NOT NULL,
  branch         TEXT,
  dir            TEXT,
  word_count     INTEGER,
  status         TEXT NOT NULL DEFAULT 'outlining' CHECK (status IN
                   ('outlining','outline_ready','drafting','draft_ready',
                    'revising','submitted','published')),
  outline        TEXT,
  verification   TEXT,                                 -- JSON, latest gate result
  published_url  TEXT                                  -- set when live -> increments clips
);

CREATE TABLE IF NOT EXISTS runs (
  id          TEXT PRIMARY KEY,
  article_id  TEXT NOT NULL REFERENCES articles(id),
  kind        TEXT NOT NULL CHECK (kind IN ('outline','draft','revise','verify_fix')),
  session_id  TEXT,                                    -- for resume
  status      TEXT NOT NULL DEFAULT 'queued' CHECK (status IN
                ('queued','running','succeeded','failed','cancelled','timeout')),
  started_at  TEXT,
  ended_at    TEXT,
  cost_usd    REAL,
  num_turns   INTEGER,
  log_path    TEXT,                                    -- ndjson on disk, NOT in the DB
  exit_reason TEXT
);
```

**Logs live on disk, not in SQLite.** A drafting run emits thousands of events. Keep the DB
small and stream from the file.

**Dedupe:** the unique index catches exact repeats. Also fuzzy-match normalized titles within
a 30-day window, to catch the same gig reposted at a new URL.

### 5.6 Seed data — `seed/outlets.json`

**Sourcing caveat, applies to every rate below.** These come from a research pass whose
direct page fetches were blocked at the network layer, so figures are from search snippets
and third-party citations, not the organizations' own pages. That is exactly why
`rate_confidence` exists as a column. **Never render a `reported` or `unknown` rate in the
UI the same way as a `verified` one.**

```json
[
  {
    "id": "digitalocean", "name": "DigitalOcean Write for DOnations",
    "url": "https://www.digitalocean.com/community",
    "submission_url": "https://www.digitalocean.com/community/pages/write-for-digitalocean",
    "kind": "publication", "rate_amount": 30000, "rate_confidence": "verified",
    "word_min": 2500, "word_max": 3000, "markdown_flavor": "digitalocean",
    "topics": ["cloud","sysadmin","security","powershell","tutorials"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "Published rate. $300 cash via PayPal plus a SEPARATE matching $300 charity donation. No audience gate. Highest-certainty paid target."
  },
  {
    "id": "logrocket", "name": "LogRocket Blog",
    "submission_url": "https://blog.logrocket.com/become-a-logrocket-guest-author/",
    "kind": "publication", "rate_amount": 35000, "rate_confidence": "reported",
    "word_min": 2500, "word_max": 3000, "markdown_flavor": "standard",
    "topics": ["devtools","frontend","automation","engineering"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "Up to $350. Dev-tooling audience: pitch the automation/engineering angle, not the compliance angle."
  },
  {
    "id": "foundry-cso", "name": "CSO Online (Foundry Expert Contributor Network)",
    "kind": "clip_builder", "rate_amount": 0, "rate_confidence": "verified",
    "topics": ["security","identity","ciso"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "UNPAID but open, self-service, and requires NO prior clips. This is the clip unlock: it converts 'no bylines' into 'published in CSO Online' without needing anyone's paid acceptance. Must be vendor-neutral and non-promotional."
  },
  {
    "id": "foundry-computerworld", "name": "Computerworld (Foundry Expert Contributor Network)",
    "kind": "clip_builder", "rate_amount": 0, "rate_confidence": "verified",
    "topics": ["security","enterprise-it","microsoft"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "Same network as CSO Online. Second clip target."
  },
  {
    "id": "helpnet", "name": "Help Net Security (Experts Corner)",
    "submission_url": "https://www.helpnetsecurity.com/editorial-opportunities/",
    "kind": "clip_builder", "rate_amount": 0, "rate_confidence": "reported",
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "topics": ["security"],
    "notes": "Wants technical experts, explicitly not marketing people. Treat as unpaid. Third clip option."
  },
  {
    "id": "infosecurity-mag", "name": "Infosecurity Magazine (op-ed)",
    "submission_url": "https://www.infosecurity-magazine.com/op-ed/",
    "kind": "clip_builder", "rate_amount": 0, "rate_confidence": "reported",
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "word_min": 800, "word_max": 1000, "topics": ["security"],
    "notes": "Exclusive content, reply only if accepted within a week. Treat as unpaid."
  },
  {
    "id": "contentlab", "name": "ContentLab",
    "submission_url": "https://contentlab.io/writeforus/",
    "kind": "agency", "rate_amount": 50000, "rate_confidence": "reported",
    "topics": ["security","cloud","devops","microsoft"],
    "accepts_new_contributors": "unknown", "requires_clips": 2,
    "notes": "BEST-FIT AGENCY. Lists Security as a first-class vertical and names Microsoft among client brands. Rate unconfirmed; one source gives a $200-700 spread."
  },
  {
    "id": "megawatt", "name": "Megawatt (LaunchSquad)",
    "url": "https://megawattcontent.com", "kind": "agency",
    "rate_confidence": "unknown",
    "topics": ["security","compliance","identity"],
    "accepts_new_contributors": "unknown", "requires_clips": 2,
    "notes": "Cybersecurity/compliance content since 2015; clients incl. Trend Micro, Snyk, Vanta, Proofpoint. Covers identity security - closest match to the OAuth/Entra specialty. No public writer application found; approach by direct outreach."
  },
  {
    "id": "siege-media", "name": "Siege Media",
    "kind": "agency", "rate_confidence": "unknown",
    "topics": ["security","zero-trust","threat-intel","incident-response"],
    "accepts_new_contributors": "yes", "requires_clips": 2,
    "notes": "Actively posting a Freelance Cybersecurity Content Writer role. Wants 2-3 yrs security content experience."
  },
  {
    "id": "ndash", "name": "nDash",
    "submission_url": "https://www.ndash.com/for-writers",
    "kind": "agency", "rate_amount": 30000, "rate_confidence": "reported",
    "topics": ["security","b2b"],
    "accepts_new_contributors": "unknown", "requires_clips": 2,
    "notes": "Invite/application-gated marketplace with an active cybersecurity pool. Reported $150-450/assignment."
  },
  {
    "id": "draft-dev", "name": "Draft.dev",
    "submission_url": "https://draft.dev/write",
    "kind": "agency", "rate_amount": 40000, "rate_confidence": "reported",
    "topics": ["devops","cloud","kubernetes","databases"],
    "accepts_new_contributors": "yes", "requires_clips": 2,
    "notes": "WEAK-TO-MODERATE FIT. Cloud-native/devtools shop; security coverage is DevSecOps, not Windows/M365. Apply only with a cloud-identity-security angle. Reported $300-500."
  },
  {
    "id": "comptia", "name": "CompTIA item writing",
    "contact_email": "examdev@comptia.org",
    "kind": "training", "rate_amount": 220000, "rate_confidence": "reported",
    "topics": ["security","certification","cloud"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "BEST VERIFIED PAID RECURRING OPTION. Reported $440/day US SME, $2,200 per full-week workshop. ELIGIBILITY CATCH: excludes people who profit or materially benefit from knowledge of the credential content - may conflict with selling CompTIA-aligned training. Check before committing."
  },
  {
    "id": "pluralsight", "name": "Pluralsight authoring",
    "submission_url": "https://www.pluralsight.com/teach",
    "kind": "training", "rate_confidence": "unknown",
    "topics": ["security","microsoft","powershell"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "BEST RECURRING-ROYALTY OPTION. ~10-min audition video, reportedly ~10% acceptance. Completion fee plus ongoing royalties paid quarterly; figures not public."
  },
  {
    "id": "4sysops", "name": "4sysops",
    "submission_url": "https://4sysops.com/write-for-4sysops/",
    "kind": "publication", "rate_confidence": "unknown",
    "topics": ["windows","powershell","sysadmin","cloud"],
    "accepts_new_contributors": "unknown", "requires_clips": 0,
    "notes": "Strongest topical fit that is still open. 'Above average' pay plus a traffic bonus, no published figure. EMAIL FOR THE RATE BEFORE WRITING ANYTHING."
  },
  {
    "id": "practical365", "name": "Practical365",
    "kind": "publication", "rate_confidence": "unknown",
    "topics": ["exchange","m365","entra","powershell"],
    "accepts_new_contributors": "no", "requires_clips": 0,
    "notes": "CLOSED to new contributors. Was the single best topical match. Recheck monthly; do not pitch."
  },
  {
    "id": "darkreading", "name": "Dark Reading",
    "contact_email": "edgeeditors@darkreading.com",
    "kind": "publication", "rate_confidence": "unknown",
    "topics": ["security"],
    "accepts_new_contributors": "unknown", "requires_clips": 1,
    "notes": "Uses freelance contributors; reputation says they pay on assignment but no rate is public. Worth a direct email. Pitch with 'Tips' in the subject."
  },
  {
    "id": "itprotoday", "name": "ITPro Today",
    "contact_email": "submissions@itprotoday.com",
    "kind": "publication", "rate_amount": 0, "rate_confidence": "verified",
    "topics": ["windows","enterprise-it"],
    "accepts_new_contributors": "yes", "requires_clips": 0,
    "notes": "Explicitly does NOT pay for unsolicited contributions. Clip value only."
  }
]
```

**Ruled out — do not add these, the effort is wasted:**

- **ISC2 exam development** — explicitly voluntary and unpaid. Covers travel and grants CPEs
  (useful for maintaining certs) but is not income.
- **TryHackMe** — does not pay for content; public monetization is an affiliate program only.
- **Microsoft exam item writing** — no public application path; appears to require an
  existing MCT or MVP relationship.

### 5.7 Seed data — `seed/sources.json`

```json
[
  { "id": "wwr", "name": "We Work Remotely", "kind": "rss", "adapter": "rss",
    "url": "https://weworkremotely.com/remote-jobs.rss", "enabled": 1,
    "notes": "No writing category. Poll main feed, keyword-filter." },
  { "id": "remotive", "name": "Remotive", "kind": "rss", "adapter": "rss",
    "url": "https://remotive.com/remote-jobs/rss-feed", "enabled": 1,
    "notes": "General board. Keyword-filter." },
  { "id": "himalayas", "name": "Himalayas", "kind": "rss", "adapter": "rss",
    "url": "https://himalayas.app/rss", "enabled": 1,
    "notes": "General board. Keyword-filter." },
  { "id": "problogger", "name": "ProBlogger Job Board", "kind": "rss", "adapter": "rss",
    "url": "https://problogger.com/jobs/feed/", "enabled": 0,
    "notes": "RSS is offered with per-category subscriptions; CONFIRM the exact feed URL at setup before enabling." }
]
```

Substack-hosted writing-jobs newsletters publish RSS at
`https://<publication>.substack.com/feed` — add any the user subscribes to using the same
`rss` adapter.

**Scrape-or-manual (phase 6, or never):**

| Source | Why no feed | Recommendation |
| --- | --- | --- |
| Superpath job board | No RSS found | Their Slack community is a better real-time source than the board |
| "Write for us" pages (Practical365, Petri, ITPro Today, Redmond) | Static pages, not job feeds | **Monthly manual check, not a poller.** Status changes — Practical365 closed between research passes |
| CompTIA workshop index | No RSS | A handful of postings a year. Quarterly manual check beats an adapter |
| nDash | Application-gated | Not publicly pollable |

**Excluded deliberately:**

- **LinkedIn** — terms explicitly prohibit scraping. Do not build an adapter.
- **Contena / Writing.io Jobs** — reportedly pivoted away from freelance writing. Not relevant.
- **Reddit** — offers RSS at `old.reddit.com/r/<sub>/.rss` and permits RSS consumption of
  public content within rate limits. Viable but low signal-to-noise here. Add only if the
  feed adapters prove insufficient.

---

## 6. Discovery subsystem

### 6.1 Design posture

Full auto-discovery was requested. The risk is that scrapers rot silently and the user ends
up trusting an empty board. These mitigations are mandatory, not optional:

- **Feeds before scrapes.** Only scrape HTML where no feed exists.
- **One adapter per source, isolated.** An adapter that throws marks that source `error` and
  the run continues. One broken site never blocks discovery.
- **robots.txt checked and cached** before any fetch. Disallowed sets `robots_allowed = 0`
  and the source is skipped until manually overridden.
- **Exponential backoff:** `backoff_until = now + min(6h * 2^consecutive_failures, 7d)`.
- **Staleness is surfaced, not hidden.** A persistent UI banner when any enabled source has
  not succeeded in >72h. **A silently dead scraper is the failure mode that matters** — it
  looks identical to "no new opportunities."
- **Polite defaults:** one request at a time per host, descriptive User-Agent with contact
  info, minimum 2s between requests to the same host.

### 6.2 Fit scoring

```
score = 0
+30  topic match       (M365, Entra, Exchange, PowerShell, security, IT-pro, MSP)
+25  rate known and >= $250/article
+15  rate known and $150-249
+20  outlet accepts new contributors
+15  kind is recurring (recurring_column | retainer | agency_assignment)
+10  no clip requirement, or requirement already met
+10  kind is clip_builder AND clips_count < 3      # unpaid, but unblocks everything
-40  accepts_new_contributors in ('no','paused')
-25  rate unknown
-30  requires more clips than currently held
```

Record `fit_reasons` as a JSON array of human-readable strings so the UI can explain itself.
Score <40 goes to a collapsed **Low fit** section.

Note the `clip_builder` bonus: a $0 opportunity that unblocks three agencies is worth more
right now than a $150 one-off. Without that rule the fit score would bury exactly the
opportunities the user most needs.

### 6.3 The clip gate

```sql
SELECT COUNT(*) FROM articles WHERE published_url IS NOT NULL;  -- clips_count
```

When `outlet.requires_clips > clips_count`, set `status = 'blocked'` and
`blocked_reason = 'needs_clips:N'`. Show these in a distinct **Blocked on clips** lane with
the shortfall.

On any transition to `published`, recompute `clips_count` and re-evaluate every `blocked`
opportunity, unblocking those now satisfied.

**This is the single most important product decision in the dashboard.** It stops the user
burning agency applications before they can win them.

---

## 7. Pipeline state machine

```
discovered ──triage──> qualified ──────> pitched ──> accepted ──> drafting
     │                     │                 │           │            │
     │                     │                 │           │            ▼
     ├──> rejected         ├──> blocked      ├──> declined      draft_ready
     │                     │  (needs clips)  │                        │
     └──> archived         └──> qualified    └──> ...          revising
                             (when unblocked)                         │
                                                                      ▼
                                                                  submitted
                                                          ┌───────────┴──────────┐
                                                          ▼                      ▼
                                                      published              rejected
                                                          │
                                                          ▼
                                                        paid
```

Enforce legal transitions in the state manager, not the UI. Every transition writes an
`opportunity_events` row.

---

## 8. Drafting engine

Verified against Claude Code documentation as of Sept 2026. **Version-dependent — see 8.7.**

### 8.1 Use the TypeScript Agent SDK, not the CLI

`@anthropic-ai/claude-agent-sdk`, not shelling out to `claude -p`.

| | Agent SDK | `claude -p` |
| --- | --- | --- |
| Messages | Typed union, maps cleanly to `RunEvent` | Parse ndjson yourself |
| Hooks | `PreToolUse` interception | Not available |
| Sessions | Resume / fork / continue as options | Flags, new subprocess per call |

Hook support is decisive — section 8.4 depends on it.

### 8.2 Invocation shape

```ts
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: buildPrompt(job),
  options: {
    cwd: job.workingDir,
    permissionMode: "dontAsk",
    allowedTools: [
      "Read", "Glob", "Grep",
      `Write(${job.workingDir}/*)`,
      `Edit(${job.workingDir}/*)`,
      "Bash(git *)",
      "Bash(pwsh *)",
    ],
    disallowedTools: ["Bash(rm *)", "WebFetch", "WebSearch"],
    maxTurns: job.kind === "outline" ? 10 : 30,
    settingSources: ["project"],
    includePartialMessages: true,
    systemPrompt: {
      type: "preset",
      preset: "claude_code",
      append: outletStyleBlock(job.outletProfile),
    },
  },
})) {
  handle(message);
}
```

### 8.3 Permission mode: `dontAsk`, never `bypassPermissions`

`dontAsk` permits only the explicit `allowedTools` plus reads and read-only Bash, and
**denies rather than prompting** — correct for an unattended run, where a prompt with nobody
watching just hangs.

`bypassPermissions` approves essentially everything and suits a disposable container. This
runs on a workstation next to client work. Do not use it, **and do not add it as a config
option** — a config option is something you switch on at 11pm to get past an error.

### 8.4 Path restriction, enforced twice

Scoped `Write`/`Edit` patterns are layer one. They are string patterns and a mistake silently
widens access, so a `PreToolUse` hook is the backstop:

```ts
hooks: {
  async preToolUse(toolUse) {
    if (["Write", "Edit"].includes(toolUse.name)) {
      const target = path.resolve(String(toolUse.input.path ?? ""));
      const root = path.resolve(job.workingDir);
      // resolve() FIRST, then compare - a raw startsWith is defeated by ../
      if (target !== root && !target.startsWith(root + path.sep)) {
        return { decision: "deny", reason: `Write outside ${root}` };
      }
    }
    return { decision: "allow" };
  }
}
```

Network tools are denied outright. Drafting needs no network, and an agent that cannot reach
the internet cannot exfiltrate a draft carrying client data that slipped past the gate.

### 8.5 Streaming to the UI

With `includePartialMessages: true`, map the SDK message union onto `RunEvent`:

| SDK message | `RunEvent` |
| --- | --- |
| `stream_event`, `delta.type === "text_delta"` | `{ t: 'text', chunk }` |
| `assistant` with a `tool_use` content block | `{ t: 'tool_use', name, summary }` |
| `system` (`init`, `compact_boundary`) | `{ t: 'status', status }` |
| `result` | `{ t: 'done', result }` |

`stream_event` payloads are raw API events, not SDK abstractions — parse `delta.type` and
`content_block.type` yourself. **Tool results are not streamed**; they arrive in the
following user message. So show tool *invocations* live and results as they land; do not
pretend to stream both.

### 8.6 Bounding every run

- **Turns:** `maxTurns` 10 for outline, 30 for draft.
- **Budget:** per-job USD ceiling; the run ends with an `error_max_budget_usd` result subtype.
- **Wall clock:** **there is no top-level SDK timeout.** Race the iteration against a timer
  and abort yourself; record `status = 'timeout'`. Without this, a stuck job is one you find
  out about tomorrow.
- **Result subtypes to handle:** `success`, `error_max_turns`, `error_max_budget_usd`. Store
  the subtype verbatim in `runs.exit_reason`.

### 8.7 Gotchas that shape the design

1. **The agent must write files, not describe them.** Left alone the model emits the article
   as text in its reply. The prompt must instruct it to `Write` the article and script to
   named paths, and the engine must **verify those files exist on disk before marking the run
   succeeded.** A run that "succeeded" with no files is the most likely failure mode of this
   whole system.
2. **Session transcripts are local**, keyed by working directory. Fine for single-process
   localhost; a machine rebuild loses resume history.
3. **Each `query()` call spawns a subprocess.** Persist `session_id` from the first
   `ResultMessage` and pass it as `resume` for the draft run; do not expect one live process
   across outline and draft.
4. **Context compaction happens automatically** at token thresholds and does not reset cost.
   A `compact_boundary` system message is not an error.
5. **Verify the surface before building.** Flags and option names are version-dependent.
   Before phase 3: run `claude --help`, check the installed SDK's exported types, and
   smoke-test a trivial job end to end. **Treat 8.2 as the intended shape, not an API
   contract.**

### 8.8 Job context assembly

In order of precedence:

1. **Outlet profile** via `systemPrompt.append` — word range, markdown flavor, house
   conventions, an example published piece.
2. **Domain conventions** via project `CLAUDE.md` in the articles repo. For any PowerShell:
   ASCII-only, Graph-first, read-only scanner scopes, the finding schema, and
   recommend-never-apply for high-blast-radius changes. See appendix A.
3. **The article brief** — topic, angle, approved outline, in the prompt body.
4. **The verification contract** — tell the run up front exactly which mechanical checks its
   output must pass. An agent told the acceptance criteria hits them far more often than one
   that finds out afterward.

### 8.9 Two-stage drafting

Never go straight to a 3,000-word draft.

1. **Outline run** — cheap, `maxTurns: 10`. Produces title, hook, prerequisites, numbered
   steps, the code artifact, and the conclusion's extension paths. The human reviews and
   edits it in the UI.
2. **Draft run** — expensive, resumes the outline session. Takes the *approved* outline,
   writes the full piece plus companion code to disk, runs the verification gate itself, and
   fixes what it can before handing back.

The outline gate is what keeps the economics sane. Rewriting a bad 3,000-word draft costs
more than writing a good one.

### 8.10 Engine contract

```ts
interface DraftRequest {
  articleId: string;
  kind: 'outline' | 'draft' | 'revise' | 'verify_fix';
  outletProfile: OutletProfile;
  topic: string;
  outline?: string;          // required when kind === 'draft'
  priorFeedback?: string;    // for kind === 'revise'
  workingDir: string;        // scoped; enforced by 8.4
  branch: string;
  resumeSessionId?: string;
}

interface DraftRunHandle {
  runId: string;
  events: AsyncIterable<RunEvent>;
  cancel(): Promise<void>;
  result: Promise<DraftResult>;
}

type RunEvent =
  | { t: 'status';   status: string }
  | { t: 'tool_use'; name: string; summary: string }
  | { t: 'text';     chunk: string }
  | { t: 'error';    message: string }
  | { t: 'done';     result: DraftResult };
```

Start returns a `runId` immediately and never blocks an HTTP request. Progress streams over
SSE. Cancel terminates the run and marks it `cancelled`. Every run is bounded per 8.6. All
events append to `runs.log_path` as ndjson for replay.

---

## 9. Verification gate

Runs automatically at the end of every draft run and is re-runnable from the UI. **A draft
cannot enter `draft_ready` with a failing blocking check.**

| Check | Blocking | What it does |
| --- | --- | --- |
| **Disclosure Gate** | **Yes** | Client data: privileged/admin UPN patterns, any `*.onmicrosoft.com` domain, tenant GUID patterns, names from `client-denylist.txt`, internal hostnames, RFC1918 addresses |
| **Secret scan** | **Yes** | API keys, tokens, connection strings, certificate blobs |
| **PowerShell parse** | **Yes** | Every `.ps1` parsed via the PowerShell AST; zero syntax errors |
| **ASCII purity** | **Yes** | `.ps1` files pure ASCII — no em-dashes, smart quotes, non-breaking spaces |
| **Code block parse** | **Yes** | Every PowerShell block in the article extracted and parsed independently |
| **Mock execution** | No | If a mock harness exists, run it and capture output |
| **Word count** | No | Within the outlet's `word_min`/`word_max` |
| **Link check** | No | HTTP HEAD each external link; flag non-200 |
| **Heading structure** | No | Matches the outlet's expected shape |

Store results as JSON on `articles.verification`; render as a checklist in the UI.

### 9.1 Why ASCII purity is blocking

Windows PowerShell 5.1 decodes BOM-less files as Windows-1252, not UTF-8. A multibyte
character — an em-dash whose trailing byte `0x94` maps to a curly quote — is misread as a
string delimiter and produces cascading parser errors far from the real line. A reader hits
this and cannot debug it. Non-ASCII in the article's *prose* is fine; in a `.ps1` it is not.

### 9.2 Implementation notes, proven in practice

```bash
# PowerShell parse check
pwsh -NoProfile -Command '
  $e=$null; $t=$null
  [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e) | Out-Null
  if ($e.Count -gt 0) { $e | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }; exit 1 }'
```

```bash
# ASCII purity
LC_ALL=C grep -n '[^ -~\t]' file.ps1     # any output = fail
```

For code-block extraction, pull every fenced block whose language tag is `powershell`,
`command`, or empty, skip blocks that are output samples, write each to a temp file, and run
the same parser. Prose and script drift apart otherwise — this catches it.

### 9.3 The Disclosure Gate is the reason this is safe to use

The user writes security articles while doing client incident response. The risk of client
detail bleeding into a public tutorial is real and career-grade. A human proofread is not a
reliable control. Make it mechanical, make it blocking, and never add a bypass.

---

## 10. HTTP API

```
GET    /api/opportunities?status=&minScore=
GET    /api/opportunities/:id
POST   /api/opportunities                  manual add
PATCH  /api/opportunities/:id
POST   /api/opportunities/:id/transition   { to, note }

GET    /api/outlets      POST /api/outlets      PATCH /api/outlets/:id

POST   /api/articles                       { opportunityId, workingTitle }
GET    /api/articles/:id
POST   /api/articles/:id/outline           -> { runId }
PATCH  /api/articles/:id/outline           save the human-edited outline
POST   /api/articles/:id/draft             -> { runId }
POST   /api/articles/:id/verify            -> gate result
GET    /api/articles/:id/content

GET    /api/runs/:id
GET    /api/runs/:id/stream                SSE: RunEvent
POST   /api/runs/:id/cancel

GET    /api/sources    PATCH /api/sources/:id    POST /api/sources/:id/poll

GET    /api/stats                          clips_count, pipeline counts, staleness
```

All bound to `127.0.0.1`. No auth, because nothing listens on a routable interface.

---

## 11. UI

**Board** — kanban by pipeline state. Lanes: Qualified, **Blocked on clips**, Pitched,
Accepted, Drafting, Draft ready, Submitted, Published. Cards show outlet, title, rate **with
a visible confidence marker** (a `reported` rate must not look like a `verified` one), fit
score, deadline.

**Detail drawer** — opportunity, fit reasons, outlet profile, linked article, verification
checklist, and actions: Generate outline / Approve outline / Draft article / Re-verify /
Open in editor / transition controls.

**Run console** — live SSE log: status line, tool-use summaries, streamed text, cancel
button. This matters more than it sounds: a 20-minute opaque job feels broken.

**Header** — clips count (prominent, it gates everything), source staleness warning, pipeline
totals.

Light and dark via CSS custom properties and `prefers-color-scheme`.

---

## 12. Build phases and acceptance criteria

Stop after each phase and demonstrate the criteria.

### Phase 0 — Scaffold
Repo, TypeScript config, `schema.sql`, `migrate.ts`, seed loader.
**Accept:** `npm run migrate` creates the DB; `npm run seed` loads `outlets.json` and
`sources.json`; `sqlite3 data/writing-ops.db "SELECT COUNT(*) FROM outlets"` returns ≥17.

### Phase 1 — Pipeline CRUD + board
Opportunity/outlet routes, transition enforcement with `opportunity_events`, React board,
manual opportunity entry. No discovery yet.
**Accept:** create an opportunity by hand, move it through every legal transition, see it in
the right lane; an illegal transition returns 4xx; `/api/stats` returns a correct
`clips_count`; a `requires_clips: 2` outlet's opportunity sits in **Blocked on clips**.

### Phase 2 — Verification gate as a standalone CLI
`npm run verify -- <dir>`. All checks from section 9.
**Accept:** running it against a directory containing an article with an em-dash in a `.ps1`
fails on ASCII purity; a syntax error fails the parse check; a fabricated
`admin@contoso.onmicrosoft.com` in the prose fails the Disclosure Gate; a clean directory
passes. **Build this before the engine — it is independently useful and gives the drafting
run something to be graded against.**

### Phase 3 — Drafting engine, outline runs only
Agent SDK integration, `dontAsk` + allowlist + path hook, run persistence, ndjson logging.
**Accept:** the smoke test from 8.7.5 passes first; then an outline run produces an outline
saved to `articles.outline`; a write attempted outside `workingDir` is denied by the hook and
the denial appears in the log; `maxTurns` and the wall-clock timeout both demonstrably
terminate a run.

### Phase 4 — Full draft runs + SSE console
Draft runs resuming the outline session, gate invoked at the end, live console.
**Accept:** a draft run writes an article file and a `.ps1` **to disk** (verify existence, per
8.7.1), the gate runs automatically, a blocking failure prevents `draft_ready`, and the
browser console shows tool-use events live with a working cancel.

### Phase 5 — Discovery, feed adapters only
Scheduler, robots.txt, RSS/JSON adapters, normalize, fit scoring, dedupe, backoff.
**Accept:** a poll of We Work Remotely creates scored opportunities; a deliberately broken
adapter marks only its own source `error` and the run continues; a source disallowed by
robots.txt is skipped; re-polling creates no duplicates; the staleness banner appears when a
source's `last_run_at` is backdated >72h.

### Phase 6 — Scrape adapters
Only if the feed adapters prove insufficient. Highest maintenance, added last.
**Accept:** as phase 5, plus each scrape adapter fails independently without affecting others.

---

## 13. Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Client data leaks into a public article | **Critical** | Disclosure Gate: blocking, mechanical, no bypass |
| Scrapers rot silently; board looks healthy but empty | High | Staleness banner, per-source status, feeds over scrapes |
| A "successful" run writes no files | High | Verify file existence before marking succeeded (8.7.1) |
| Generated article is competent but generic and gets rejected | High | The outline review gate is the control point. The differentiator is the user's specific expertise; the outline is where it gets injected |
| Unattended agent damages the working tree | High | Scoped write path, tool allowlist, path-enforcing hook, branch per article |
| Drafting costs more than expected | Medium | Turn caps, budget ceiling, outline-first, per-run cost recorded |
| IP ban from a job board | Medium | robots.txt, rate limits, backoff, honest User-Agent |
| **The dashboard becomes a procrastination project instead of published articles** | **High** | Phases 0–2 are a weekend. If phase 3 has not started within two weeks, the dashboard is the problem, not the solution |

That last one is not a joke. The purpose is published articles.

---

## 14. Strategy context the build should respect

The dashboard encodes a strategy. Two points explain why the clip gate and the
`clip_builder` kind exist at all.

**The agencies are a poor topical fit, and the seed data says so.** Draft.dev, Hackmamba and
Codeless are cloud-native/devtools shops whose security coverage is DevSecOps and AppSec, not
Windows/M365 administration. The better targets are pure-play cybersecurity content agencies
— Megawatt, Siege Media, nDash — plus ContentLab, the one devtools agency with Security as a
first-class vertical and Microsoft as a named client. There is an honest reframe available:
Entra ID, OAuth consent phishing and Conditional Access *are* cloud identity security. That
framing gets in the door; a straight "secure Exchange Online" pitch does not.

**The clips bottleneck has a concrete answer.** The Foundry Expert Contributor Network — CSO
Online, CIO, Computerworld, InfoWorld, Network World — is open, self-service, and requires no
prior clips. It is unpaid, but it converts "no bylines" into "published in CSO Online"
without needing anyone's paid acceptance first. That is why `clip_builder` outlets get a
positive fit-score bonus while `clips_count < 3` despite paying nothing.

**Realistic income shape:** weekly *assignments* and weekly *income* are different things.
The publication lane is mostly unpaid. The recurring money is more likely to come from
CompTIA workshops and Pluralsight royalties than from a weekly article drumbeat.

---

## 15. Open decisions for the user

1. **Smoke-test the SDK surface** against the installed Claude Code version before phase 3
   (8.7.5). Ten minutes; prevents building on a wrong API shape.
2. **CompTIA conflict of interest** — item writing excludes people who profit from knowledge
   of the credential content. If the user may later sell CompTIA-aligned training, these two
   paths may be mutually exclusive. Decide before applying.
3. **Articles repo** — recommend its own repo, so the dashboard can be public while drafts
   stay private. `ARTICLES_REPO` points at it.
4. **Confirm the ProBlogger feed URL** before enabling that source (seeded `enabled: 0`).

---

## Appendix A — PowerShell conventions for generated scripts

Any `.ps1` a drafting run produces must follow these. Put them in the articles repo's
`CLAUDE.md` so every run picks them up.

- **Pure ASCII.** No em-dashes, en-dashes, smart quotes, or non-breaking spaces anywhere,
  including comments and string literals. See 9.1 for why.
- **Execution-policy header.** Every `.ps1` opens with a comment block documenting
  `powershell.exe -ExecutionPolicy Bypass -File .\Script.ps1` as the primary run method, with
  `Unblock-File` and `-Scope Process|CurrentUser` as alternates. State plainly that a script
  cannot lift its own load-time policy block.
- **Graph before Exchange.** `Connect-MgGraph` before `Connect-ExchangeOnline`, so Graph's
  newer MSAL loads first. Connect Exchange with `-DisableWAM` (EOM 3.7+). Detect the wrong
  order and warn rather than failing obscurely.
- **Current cmdlets only.** Microsoft Graph SDK and ExchangeOnlineManagement. No retired
  MSOnline or AzureAD modules. `Get-MessageTraceV2`, not `Get-MessageTrace`.
- **Audit-first.** Read-only is the resting state. A default run changes nothing.
- **Finding schema.** Every check emits `Severity` (Critical/High/Medium/Low/Info), `Area`,
  `Object`, `Detail`, `Risk`, `Remediation`. Sort by an explicit severity rank, highest first
  — sorting a severity *string* alphabetically is wrong.
- **Remediation policy: recommend always, ask to apply always, automate never.** Graph-side
  and identity changes (Conditional Access, OAuth/app-role revoke, user disable, credential
  removal) are advise-only — print the exact command, never run it. Never request
  `*.ReadWrite.*` Graph scopes for a scanner.
- **Least privilege.** Do not tell readers to grant more than the task needs.
- **Genericized output.** Never expose privileged account UPNs, the tenant
  `.onmicrosoft.com` domain, or the tenant GUID in any exported report or article sample.

### A.1 The bug to watch for

Under `Set-StrictMode`, a `Where-Object` pipeline that returns **exactly one** object has no
`.Count` property. This fails only in tenants with exactly one match — intermittent, and
humiliating in a published tutorial. **Wrap every pipeline result in `@()`.**

```powershell
$risky = @($scopeList | Where-Object { $highRisk -contains $_ })
if ($risky.Count -eq 0) { ... }   # safe
```

This was caught by a mock-tenant run, not by reading the code. Which is the argument for
phase 2 existing at all.

---

## Appendix B — Reference article

A complete worked example already exists and is worth reading before building the drafting
prompt: a ~2,580-word DigitalOcean-format tutorial on auditing Entra ID OAuth consent grants,
with a 461-line read-only companion script.

What made it good, and what the drafting prompt should aim to reproduce:

- **It leads with an argument, not a walkthrough.** Delegated and application permissions are
  different risk classes: an app-only `Mail.ReadWrite` reads every mailbox in the tenant with
  no user, nothing for MFA to challenge, and survives disabling the account. That claim is
  the spine; the code serves it.
- **It uses the outlet's real markdown conventions** — `[secondary_label Output]`,
  `<$>[note]`, `<^>highlight<^>` for DigitalOcean. Using an outlet's actual syntax signals
  the writer read the style guide.
- **Design decisions are argued, not just stated.** Read-only scopes are justified by the
  asymmetry: a tool that misidentifies a legitimate integration and revokes it breaks
  production instantly with no undo; printing the command costs thirty seconds.
- **Its own near-miss became content.** The `.Count` bug above is now a warning box in the
  article, and one of its most useful passages.
