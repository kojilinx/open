# Writing Ops Dashboard - Implementation Spec

A localhost dashboard that discovers paid technical-writing opportunities, tracks each
one through a pipeline, and drives Claude Code to draft the article on demand.

**Status:** specification. Not built.
**Stack:** Node + TypeScript.
**Cost:** $0 in infrastructure. The only variable cost is Claude usage for drafting runs.

---

## 1. Why this exists

The goal is a **steady stream of technical writing assignments**, at 5-10 hrs/week, from a
standing start with **no published bylines**.

Three facts shape every design decision below:

1. **No clips is the binding constraint.** Content agencies gate on 2-3 published samples.
   Until those exist, most agency applications are wasted, and a rejected application is
   hard to reopen. The dashboard must therefore track a *clip count* and gate
   agency-type opportunities behind it, rather than encouraging you to blast applications.
2. **Drafting is the expensive step, not finding work.** A 2,500-3,000 word tutorial with
   working, tested code is 6-8 hours by hand. That is the entire weekly budget. Automating
   the draft is what converts "one article a month" into "a steady stream."
3. **A bad published article is worse than no article.** These pieces carry your name in a
   niche where your professional reputation is the product. Every generated draft must pass
   a mechanical quality gate before you ever look at it, and must never be auto-submitted.

## 2. Scope

**In scope**
- Automated discovery of writing opportunities from feeds and site scrapes
- An opportunity pipeline with explicit states, from discovered through paid
- On-demand drafting: one click kicks off a Claude Code run that produces an article plus
  any companion code, committed to a branch
- A mechanical verification gate over every generated draft
- Local-only web UI with live run progress

**Out of scope (deliberately)**
- Auto-submitting anything to any outlet. Submission is always a human action.
- Auto-sending pitch emails. The dashboard may draft them; you send them.
- Multi-user, auth, hosting, or anything beyond `localhost`.
- Publishing directly to outlet CMSes.

## 3. Non-negotiable safety rules

These are requirements, not suggestions.

| Rule | Why |
| --- | --- |
| Nothing is sent to any third party automatically | An outward-facing action that misfires damages a professional relationship you cannot repair |
| The drafting agent gets a scoped write path and an allowlisted tool set, never blanket bypass | An unattended agent with unrestricted tools on your machine is an unbounded risk |
| Every draft passes the Disclosure Gate before it is markable as ready | Prevents client data reaching a public article. See section 9 |
| Discovery respects `robots.txt` and per-source rate limits | Getting IP-banned from a job board costs you that channel permanently |
| No credentials in the repo; all secrets in `.env`, gitignored | Standard, and these drafts live in a git repo you may later make public |

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Browser (localhost:5173)                                    │
│  React + Vite - pipeline board, opportunity detail, live log │
└────────────────┬────────────────────────────────────────────┘
                 │ REST + SSE
┌────────────────▼────────────────────────────────────────────┐
│  Node + TypeScript API (localhost:8787)  Fastify            │
│                                                              │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Discovery  │  │  Pipeline    │  │  Drafting Engine   │  │
│  │ scheduler  │  │  state mgr   │  │  (drives Claude)   │  │
│  └─────┬──────┘  └──────┬───────┘  └─────────┬──────────┘  │
│        │                │                     │             │
│  ┌─────▼────────────────▼─────────────────────▼──────────┐  │
│  │              SQLite (better-sqlite3)                   │  │
│  └────────────────────────────────────────────────────────┘  │
│                                      │                       │
│                          ┌───────────▼────────────┐          │
│                          │  Verification Gate     │          │
│                          │  (pwsh, ASCII, PII)    │          │
│                          └────────────────────────┘          │
└──────────────────────────────────────┬──────────────────────┘
                                       │ writes to
                          ┌────────────▼─────────────┐
                          │  articles/ git repo      │
                          │  one branch per article  │
                          └──────────────────────────┘
```

**Why SQLite:** zero-config, single file, no daemon, free, trivially backed up. The data
volume here is hundreds of rows, not millions. Do not reach for Postgres.

**Why Fastify:** small, fast, first-class TypeScript types, built-in SSE-friendly. Express
also works; the spec does not depend on the choice.

### 4.1 Repository layout

```
writing-ops/
  package.json
  .env.example
  data/
    writing-ops.db            # SQLite, gitignored
  src/
    server/
      index.ts                # Fastify bootstrap
      routes/
        opportunities.ts
        outlets.ts
        articles.ts
        runs.ts               # includes SSE stream
        sources.ts
      db/
        schema.sql
        migrate.ts
        queries.ts
    discovery/
      scheduler.ts            # cron-ish loop, per-source backoff
      robots.ts               # robots.txt fetch + cache + check
      adapters/
        rss.ts                # generic RSS/Atom
        jsonFeed.ts           # generic JSON endpoints
        weworkremotely.ts     # one file per scraped source
        ...                   # each adapter is independently failable
      normalize.ts            # raw hit -> Opportunity candidate
      score.ts                # fit scoring
    drafting/
      engine.ts               # Claude Code invocation (section 8)
      promptBuilder.ts        # assembles job context
      outletProfiles/
        digitalocean.json     # style guide, word count, md flavor
        logrocket.json
        ...
    verification/
      index.ts                # orchestrates all checks
      powershell.ts           # parse check via pwsh
      ascii.ts
      disclosure.ts           # PII / client-data gate
      wordcount.ts
      codeblocks.ts
    web/                      # React + Vite frontend
  articles/                   # git repo for output (may be a submodule)
```

---

## 5. Data model

SQLite schema. All timestamps ISO-8601 UTC text.

### 5.1 `outlets`

A place that publishes. Relatively static, hand-curated plus discovery-enriched.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | slug, e.g. `digitalocean` |
| `name` | TEXT | |
| `url` | TEXT | |
| `submission_url` | TEXT | where you actually apply/pitch |
| `contact_email` | TEXT | nullable |
| `kind` | TEXT | `publication` / `agency` / `vendor` / `training` |
| `rate_amount` | INTEGER | in cents, nullable |
| `rate_currency` | TEXT | default `USD` |
| `rate_confidence` | TEXT | `verified` / `reported` / `unknown` - drives UI treatment |
| `rate_source_url` | TEXT | where the rate came from. Never show a rate without a source |
| `word_min`, `word_max` | INTEGER | |
| `markdown_flavor` | TEXT | `digitalocean` / `standard` / `custom` |
| `style_guide_path` | TEXT | local path to the outlet profile JSON |
| `topics` | TEXT | JSON array |
| `accepts_new_contributors` | TEXT | `yes` / `no` / `unknown` / `paused` |
| `requires_clips` | INTEGER | count required, 0 if none. Drives the clip gate |
| `notes` | TEXT | |
| `last_checked_at` | TEXT | |

### 5.2 `sources`

A thing discovery polls.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | |
| `kind` | TEXT | `rss` / `json` / `scrape` |
| `url` | TEXT | |
| `adapter` | TEXT | module name in `discovery/adapters/` |
| `enabled` | INTEGER | |
| `robots_allowed` | INTEGER | cached result of robots.txt check |
| `poll_interval_min` | INTEGER | default 360 |
| `last_run_at` | TEXT | |
| `last_status` | TEXT | `ok` / `error` / `blocked` / `empty` |
| `last_error` | TEXT | |
| `consecutive_failures` | INTEGER | drives exponential backoff |
| `backoff_until` | TEXT | |

### 5.3 `opportunities`

A specific chance to get paid for writing.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | |
| `outlet_id` | TEXT FK | nullable for unrecognized outlets |
| `source_id` | TEXT FK | nullable for manually added |
| `kind` | TEXT | `guest_post` / `agency_assignment` / `recurring_column` / `retainer` / `item_writing` |
| `title` | TEXT | |
| `url` | TEXT | unique with `outlet_id` for dedupe |
| `description` | TEXT | |
| `rate_estimate` | INTEGER | cents, nullable |
| `deadline` | TEXT | nullable |
| `discovered_at` | TEXT | |
| `status` | TEXT | see state machine |
| `fit_score` | INTEGER | 0-100, see 6.2 |
| `fit_reasons` | TEXT | JSON array of strings, shown in UI |
| `blocked_reason` | TEXT | e.g. `needs_clips:2` |
| `notes` | TEXT | |

**Dedupe:** unique index on `(outlet_id, url)`. Also fuzzy-match on normalized title within
a 30-day window to catch the same gig reposted at a new URL.

### 5.4 `articles`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | |
| `opportunity_id` | TEXT FK | |
| `working_title` | TEXT | |
| `branch` | TEXT | git branch in the articles repo |
| `dir` | TEXT | path, e.g. `articles/02-conditional-access-drift` |
| `word_count` | INTEGER | |
| `status` | TEXT | `outlining` / `drafting` / `draft_ready` / `revising` / `submitted` / `published` |
| `verification` | TEXT | JSON blob, latest gate result |
| `published_url` | TEXT | set when live. **This is what increments your clip count** |

### 5.5 `runs`

One Claude Code invocation.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | |
| `article_id` | TEXT FK | |
| `kind` | TEXT | `outline` / `draft` / `revise` / `verify_fix` |
| `session_id` | TEXT | Claude Code session, for resuming |
| `status` | TEXT | `queued` / `running` / `succeeded` / `failed` / `cancelled` / `timeout` |
| `started_at`, `ended_at` | TEXT | |
| `cost_usd` | REAL | if reported by the runner |
| `num_turns` | INTEGER | |
| `log_path` | TEXT | newline-delimited JSON event log on disk |
| `exit_reason` | TEXT | |

**Logs live on disk, not in SQLite.** A drafting run emits thousands of events; keep the DB
small and stream from the file.

---

## 6. Discovery subsystem

### 6.1 Design posture

You chose full auto-discovery. The risk is that scrapers rot silently and you end up
trusting an empty board. Mitigations are mandatory:

- **Feeds before scrapes.** If a source publishes RSS/Atom or a JSON endpoint, use it. Only
  scrape HTML where no feed exists.
- **One adapter per source, isolated.** An adapter throwing must mark that source `error`
  and continue the run. One broken site never blocks discovery.
- **robots.txt is checked and cached** before any fetch. A disallowed path sets
  `robots_allowed = 0` and the source is skipped, permanently, until manually overridden.
- **Exponential backoff.** `consecutive_failures` drives `backoff_until`:
  `min(6h * 2^failures, 7d)`.
- **Staleness is surfaced, not hidden.** The UI shows a persistent banner when any enabled
  source has not succeeded in > 72h. A silent scraper is the failure mode that matters.
- **Polite defaults:** one request at a time per host, descriptive User-Agent with contact
  info, minimum 2s between requests to the same host.
- **No source that prohibits automated access in its terms.** Curate the seed list
  accordingly; when in doubt, use the feed or add it manually.

### 6.2 Fit scoring

Discovery finds noise. Scoring surfaces the few that matter. Score 0-100, with reasons
recorded so the UI can explain itself.

```
score = 0
+30  topic match       (M365, Entra, Exchange, PowerShell, security, IT-pro, MSP)
+25  rate known and >= $250/article
+15  rate known and $150-249
+20  outlet accepts new contributors
+15  kind is recurring (recurring_column / retainer / agency_assignment)
+10  no clip requirement, or clip requirement already met
 -40 outlet.accepts_new_contributors == 'no' or 'paused'
 -25 rate unknown
 -30 requires more clips than you currently have
```

Anything scoring < 40 lands in a collapsed **Low fit** section rather than the main board.

### 6.3 The clip gate

`clips_count` is derived: `SELECT COUNT(*) FROM articles WHERE published_url IS NOT NULL`.

When an opportunity's outlet has `requires_clips > clips_count`, the opportunity gets
`status = 'blocked'` and `blocked_reason = 'needs_clips:N'`. The UI shows these in a
distinct **Blocked on clips** lane with a count of how many more you need.

This is the single most important product decision in the dashboard. It stops you
burning agency applications before you can win them.

---

### 6.4 Discovery seed list

Sourced from the recurring-pipeline research (`revenue-plan/recurring-pipeline.md`).
**RSS/JSON first; scrape only where no feed exists.**

**Feed-backed (build these adapters first, phase 5)**

| Source | Feed | Note |
| --- | --- | --- |
| We Work Remotely | `weworkremotely.com/remote-jobs.rss` | No writing category; poll main feed, filter by keyword |
| ProBlogger Job Board | RSS offered, per-category subscriptions available | Confirm exact feed URL at setup |
| Remotive | `remotive.com/remote-jobs/rss-feed` | General board, keyword-filter |
| Himalayas | `himalayas.app/rss` | General board, keyword-filter |
| Substack job newsletters | `<publication>.substack.com/feed` | Substack publishes RSS by default at this path |

**Scrape-or-manual (phase 6, or never)**

| Source | Why no feed | Recommendation |
| --- | --- | --- |
| Superpath job board | No RSS found | Their Slack community is a better real-time source than the board |
| "Write for us" pages (Practical365, Petri, ITPro Today, Redmond) | Static pages, not job feeds | **Monthly manual check, not a poller.** These change open/closed status - Practical365 closed since the last pass |
| CompTIA workshop index | No RSS | Handful of postings a year. Quarterly manual check beats building an adapter |
| nDash | Invite/application-gated | Not publicly pollable |

**Excluded deliberately**

- **LinkedIn** - terms explicitly prohibit scraping. Do not build an adapter.
- **Contena / Writing.io Jobs** - reportedly pivoted away from freelance writing to AI/eng
  roles. No longer relevant.
- **Reddit** - offers RSS at `old.reddit.com/r/<sub>/.rss` and its terms permit RSS
  consumption of public content within rate limits. Viable, but low signal-to-noise for paid
  technical writing specifically. Add only if the feed adapters prove insufficient.

A source's `robots_allowed` flag is checked before any fetch regardless of what this table
says.

## 7. Pipeline state machine

```
discovered ──triage──> qualified ──────> pitched ──> accepted ──> drafting
     │                     │                 │           │            │
     │                     │                 │           │            ▼
     ├──> rejected         ├──> blocked      ├──> declined      draft_ready
     │    (not a fit)      │    (needs clips)│    (no reply /        │
     │                     │                 │     passed)          ▼
     └──> archived         └──> qualified    └──> ...          revising
                                (when unblocked)                     │
                                                                     ▼
                                                                 submitted
                                                                     │
                                                          ┌──────────┴──────────┐
                                                          ▼                     ▼
                                                      published             rejected
                                                          │
                                                          ▼
                                                        paid
```

Legal transitions are enforced in the state manager, not the UI. Every transition writes an
audit row (`opportunity_events`: id, opportunity_id, from, to, at, note).

`published` is the state that increments `clips_count` and can unblock other opportunities,
so the transition handler re-evaluates all `blocked` rows.

---

## 8. Drafting engine

Verified against current Claude Code documentation (links at 8.8). **Version-dependent:
confirm flags and option names against the installed CLI and SDK types before implementing
- see 8.7.**

### 8.1 Choice: the TypeScript Agent SDK, not the CLI

Use `@anthropic-ai/claude-agent-sdk` rather than shelling out to `claude -p`.

| | Agent SDK | `claude -p` |
| --- | --- | --- |
| Message handling | Typed union, maps cleanly to our `RunEvent` | Parse newline-delimited JSON yourself |
| Hooks | `PreToolUse` interception available - this is our path-restriction backstop | Not available |
| Session control | Resume / fork / continue as options | Flags, new subprocess per call |
| Cost | Reported per message | Reported on final result |

The hook support is decisive. Section 8.4 depends on it.

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
    maxTurns: 30,
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

`dontAsk` permits only the explicit `allowedTools` plus reads and read-only Bash. Everything
else is denied rather than prompting - which is what you want for an unattended run, since a
prompt with nobody watching just hangs.

`bypassPermissions` approves essentially everything and is appropriate only inside a
disposable container. This dashboard runs on your workstation, next to client work. Do not
use it, and do not add it as a config option, because a config option is something you will
eventually switch on at 11pm to get past an error.

### 8.4 Path restriction is enforced twice

Scoped `Write`/`Edit` patterns are the first layer. They are string patterns, and a pattern
mistake silently widens access, so a `PreToolUse` hook is the backstop:

```ts
hooks: {
  async preToolUse(toolUse) {
    if (["Write", "Edit"].includes(toolUse.name)) {
      const target = path.resolve(String(toolUse.input.path ?? ""));
      const root = path.resolve(job.workingDir);
      // resolve() first, then check - defeats ../ traversal
      if (target !== root && !target.startsWith(root + path.sep)) {
        return { decision: "deny", reason: `Write outside ${root}` };
      }
    }
    return { decision: "allow" };
  }
}
```

Resolve before comparing. A naive `startsWith` on the raw string is defeated by `../`.

Network tools are denied outright. Drafting needs no network, and an agent that cannot
reach the internet cannot exfiltrate a draft containing client data that slipped past the
Disclosure Gate.

### 8.5 Streaming to the UI

With `includePartialMessages: true`, map the SDK message union onto our `RunEvent` type:

| SDK message | `RunEvent` |
| --- | --- |
| `stream_event` with `delta.type === "text_delta"` | `{ t: 'text', chunk }` |
| `assistant` with a `tool_use` content block | `{ t: 'tool_use', name, summary }` |
| `system` (`subtype: "init"` / `"compact_boundary"`) | `{ t: 'status', status }` |
| `result` | `{ t: 'done', result }` |

`stream_event` payloads are raw API events, not SDK abstractions - parse `delta.type` and
`content_block.type` yourself. Tool *results* are not streamed; they arrive in the following
user message. The run console should therefore show tool *invocations* live and results as
they land, not pretend to stream both.

### 8.6 Bounding the run

- **Turns:** `maxTurns: 30`. An outline run needs far fewer; cap it at 10.
- **Budget:** set a per-job USD ceiling. The run then terminates with a
  `error_max_budget_usd` result subtype rather than running away.
- **Wall clock:** **there is no top-level SDK timeout.** Wrap the iteration in a
  `Promise.race` against a timer and abort the loop yourself. Record the run as `timeout`.
  Do not skip this - it is the difference between a stuck job and a stuck job you find out
  about tomorrow.
- **Result subtypes to handle:** `success`, `error_max_turns`, `error_max_budget_usd`. Store
  the subtype in `runs.exit_reason` verbatim.

### 8.7 Gotchas that shape the design

1. **The agent must write files, not describe them.** Left to itself the model will emit the
   article as text in its reply. The prompt must explicitly instruct it to `Write` the
   article and script to disk at named paths, and the engine must verify those files exist
   before marking the run succeeded. A run that "succeeded" with no files on disk is the
   most likely failure mode of this whole system.
2. **Session transcripts are local.** Stored under the user profile keyed by working
   directory. Fine for a single-process localhost app; it means a machine rebuild loses
   resume history, which is acceptable here.
3. **Each `query()` call spawns a subprocess.** For the outline-then-draft flow, persist
   `session_id` from the first `ResultMessage` and pass it as `resume` on the draft run
   rather than expecting one live process across both.
4. **Context compaction happens automatically** at token thresholds and does not reset cost.
   A 3,000-word draft run may compact mid-flight; that is fine, but do not treat a
   `compact_boundary` system message as an error.
5. **Verify the surface before building.** The flags and option names above are
   version-dependent. Before phase 3, run `claude --help`, check the installed SDK's exported
   types, and smoke-test a trivial job end to end. Treat 8.2 as the intended shape, not as
   an API contract.

### 8.8 Sources

- `code.claude.com/docs/en/headless.md` - CLI flags
- `code.claude.com/docs/en/agent-sdk/typescript.md` - SDK API
- `code.claude.com/docs/en/agent-sdk/streaming-output.md` - event shapes
- `code.claude.com/docs/en/permission-modes.md` - permission modes
- `code.claude.com/docs/en/agent-sdk/permissions.md` - permission evaluation
- `code.claude.com/docs/en/agent-sdk/sessions.md` - resume / fork / continue
- `code.claude.com/docs/en/agent-sdk/modifying-system-prompts.md` - system prompt options

### 8.9 Job context assembly

Each run is given, in order of precedence:

1. **Outlet profile** via `systemPrompt.append` - word range, markdown flavor, house
   conventions, a published example from that outlet.
2. **Domain conventions** via the project `CLAUDE.md` and the existing
   `m365-security-tooling` skill, which governs any PowerShell produced: ASCII-only,
   Graph-first, read-only scanner scopes, the finding schema, recommend-never-apply for
   high-blast-radius changes.
3. **The article brief** - topic, angle, approved outline, in the prompt body.
4. **The verification contract** - the run is told up front exactly which mechanical checks
   its output must pass. An agent told the acceptance criteria hits them far more often than
   one that finds out afterward.

### 8.10 Two-stage drafting

Do not go straight to a 3,000-word draft.

1. **Outline run** - cheap, `maxTurns: 10`. Produces title, hook, prerequisites, numbered
   steps, the code artifact, and the conclusion's extension paths. You review and edit it in
   the UI. This is where you steer, at a cost of minutes.
2. **Draft run** - expensive, resumes the outline session. Takes the *approved* outline,
   writes the full piece plus companion code to disk, then runs the verification gate itself
   and fixes what it can before handing back.

The outline gate is what keeps the economics sane. Rewriting a bad 3,000-word draft costs
more than writing a good one.

### 8.11 Engine contract

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

Requirements: start returns a `runId` immediately and never blocks an HTTP request; progress
streams over SSE; cancel terminates the run and marks it `cancelled`; every run is bounded
per 8.6; all events append to `runs.log_path` as newline-delimited JSON for replay.

## 9. Verification gate

Runs automatically at the end of every draft run, and re-runnable from the UI. A draft
cannot enter `draft_ready` with a failing **blocking** check.

| Check | Blocking | What it does |
| --- | --- | --- |
| **Disclosure Gate** | **Yes** | Scans article and code for client data: admin/privileged UPN patterns, any `*.onmicrosoft.com` domain, tenant GUID patterns, known client names from a local gitignored denylist, internal hostnames, IP ranges. Any hit fails the draft. |
| **Secret scan** | **Yes** | API keys, tokens, connection strings, certificate blobs |
| **PowerShell parse** | **Yes** | Every `.ps1` parsed with the PowerShell AST parser; zero syntax errors required |
| **ASCII purity** | **Yes** | `.ps1` files must be pure ASCII - no em-dashes, smart quotes, or non-breaking spaces. Windows PowerShell 5.1 misreads these as string delimiters and fails far from the real line |
| **Code block parse** | **Yes** | Every PowerShell block in the article extracted and parsed independently. Prose and script drift apart otherwise |
| **Mock execution** | No | If the article ships a script and a mock harness exists, run it and capture output |
| **Word count** | No | Within the outlet's `word_min`/`word_max` |
| **Link check** | No | HTTP HEAD every external link; flag non-200 |
| **Heading structure** | No | Matches the outlet's expected shape |

Results are stored as JSON on `articles.verification` and rendered as a checklist in the UI.

**The Disclosure Gate is the reason this dashboard is safe to use.** You write security
articles while doing client incident response. The risk of client detail bleeding into a
public tutorial is real, and a human proofread is not a reliable control. Make it mechanical.

---

## 10. HTTP API

```
GET    /api/opportunities?status=&minScore=       list, filtered
GET    /api/opportunities/:id
POST   /api/opportunities                         manual add
PATCH  /api/opportunities/:id                     edit fields
POST   /api/opportunities/:id/transition          { to, note }

GET    /api/outlets
POST   /api/outlets
PATCH  /api/outlets/:id

POST   /api/articles                              { opportunityId, workingTitle }
GET    /api/articles/:id
POST   /api/articles/:id/outline                  start outline run  -> { runId }
POST   /api/articles/:id/draft                    start draft run    -> { runId }
POST   /api/articles/:id/verify                   re-run gate        -> result
GET    /api/articles/:id/content                  current draft markdown

GET    /api/runs/:id
GET    /api/runs/:id/stream                       SSE: RunEvent stream
POST   /api/runs/:id/cancel

GET    /api/sources
POST   /api/sources/:id/poll                      force a poll now
PATCH  /api/sources/:id                           enable/disable

GET    /api/stats                                 clips_count, pipeline counts, staleness
```

All bound to `127.0.0.1` only. No auth, because nothing listens on a routable interface.
This is a deliberate trade and the reason the bind address is not configurable.

---

## 11. UI

Single page, three regions.

**Board** - kanban by pipeline state. Lanes: Qualified, Blocked on clips, Pitched, Accepted,
Drafting, Draft ready, Submitted, Published. Cards show outlet, title, rate (with a
confidence marker - an unverified rate renders differently from a sourced one), fit score,
deadline.

**Detail drawer** - opens on card click. Shows the opportunity, its fit reasons, the outlet
profile, the linked article, verification checklist, and the action buttons:
`Generate outline` / `Approve outline` / `Draft article` / `Re-verify` / `Open in editor` /
transition controls.

**Run console** - live SSE log of the current run: status line, tool-use summaries, streamed
text. A cancel button. This matters more than it sounds: a 20-minute opaque job feels broken.

**Header** - clip count (prominent, because it gates everything), source staleness warning,
pipeline totals.

Dark and light both supported via CSS custom properties; no theme toggle needed beyond
`prefers-color-scheme`.

---

## 12. Build phases

Each phase is independently useful. Do not build phase N+1 before N works.

| Phase | Deliverable | Why this order |
| --- | --- | --- |
| **0** | Repo scaffold, SQLite schema, migrations, seed the outlets table with already-researched outlets and rates | Everything needs the data model |
| **1** | Pipeline CRUD + board UI, manual opportunity entry only | Useful on day one as a tracker, with zero discovery risk |
| **2** | Verification gate as a standalone CLI (`npm run verify -- <dir>`) | Independently valuable; can verify the already-drafted article immediately |
| **3** | Drafting engine, outline run only | Cheap runs, proves the Claude Code integration end to end |
| **4** | Full draft run + run console SSE | The payoff feature |
| **5** | Discovery: RSS/JSON adapters only | Lowest-fragility sources first |
| **6** | Discovery: HTML scrape adapters, staleness alerting | Highest maintenance, added last, on a foundation that already works |

Phase 2 is worth pulling forward if you want immediate value: the verification gate can run
against `articles/01-entra-oauth-consent-audit/` today.

---

## 13. Dependencies

All free and local.

| Package | Purpose |
| --- | --- |
| `fastify` | HTTP server |
| `better-sqlite3` | Embedded DB, synchronous, no daemon |
| `zod` | Schema validation on API boundaries and adapter output |
| `node-cron` | Discovery scheduling |
| `undici` | HTTP fetching for discovery |
| `cheerio` | HTML parsing for scrape adapters |
| `fast-xml-parser` | RSS/Atom |
| `robots-parser` | robots.txt compliance |
| `react`, `vite` | Frontend |
| `@anthropic-ai/claude-agent-sdk` | Driving Claude Code (see section 8) |

**External binary:** `pwsh` (PowerShell 7+) must be on PATH for the PowerShell verification
checks. The gate degrades to a warning if absent rather than failing the run.

---

## 14. Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Scrapers rot silently, board looks empty but healthy | High | Staleness banner, per-source status in UI, feeds preferred over scrapes |
| Drafting run costs more than expected | Medium | Turn caps, wall-clock timeouts, two-stage outline-first flow, cost recorded per run |
| Generated article is competent but generic, gets rejected | High | Outline review gate is the control point. The differentiator is your specific expertise; the outline is where you inject it |
| Client data leaks into a public article | **Critical** | Disclosure Gate, blocking, mechanical |
| An unattended agent damages the working tree | High | Scoped write path, tool allowlist, path-enforcing hook, dedicated branch per article |
| Getting IP-banned from a job board | Medium | robots.txt, rate limits, backoff, honest User-Agent |
| Dashboard becomes a procrastination project instead of writing articles | **High** | Phases 0-2 are a weekend. If phase 3 is not started within two weeks, the dashboard is the problem, not the solution |

That last one is not a joke. The purpose is published articles. Build phases 0-2, use it,
and only continue if it is actually saving time.

---

## 15. Open questions

1. ~~Claude Code invocation specifics~~ - **resolved**, section 8. One residual task:
   smoke-test the SDK surface against the installed version before phase 3, per 8.7.5.
2. ~~Which discovery sources make the seed list~~ - **resolved**, section 6.4.
3. **Does the articles output live in this repo or its own?** Recommend its own repo, so the
   dashboard can be public while drafts stay private.
4. ~~Clip strategy~~ - **resolved.** The Foundry Expert Contributor Network
   (CSO Online / CIO / Computerworld / InfoWorld / Network World) is open, self-service, and
   requires **no prior clips**. It is unpaid, but it produces real bylines on recognized
   outlets, which is exactly what agencies gate on. Seed `outlets` with
   `requires_clips = 0` for those, and `requires_clips = 2` for the agencies. See
   `revenue-plan/recurring-pipeline.md` section 2.
5. **Should the dashboard track unpaid clip-building outlets at all?** Recommend yes, as a
   distinct `kind = 'clip_builder'`, so the board shows progress toward unblocking the
   agencies rather than treating $0 opportunities as noise the fit score discards.
