# Writing Ops Dashboard

**[BUILD-SPEC.md](BUILD-SPEC.md) is the spec.** Single file, self-contained — hand it to a
local Claude Code session with:

> Build this, phase by phase. Stop after each phase and show me it works against the
> acceptance criteria.

It assumes no prior conversation and no other documents: bootstrap commands, full SQLite
DDL, inline seed data for 17 outlets and 4 sources, the drafting-engine contract, the
verification gate, and per-phase acceptance criteria.

## Related, but not needed to build

- `../revenue-plan/recurring-pipeline.md` — the research record behind the seed data, with
  per-item confidence markers and sourcing caveats. Read it to understand *why* an outlet
  carries the rate and `requires_clips` value it does.
- `../articles/01-entra-oauth-consent-audit/` — the worked reference article and companion
  script described in BUILD-SPEC appendix B.

## Start here

Phases 0-2 are a weekend and need nothing verified first. **Phase 2 (the verification gate
CLI) is independently useful** — it runs against the existing article immediately.

Before phase 3, do the ten-minute SDK smoke test in BUILD-SPEC section 8.7.5.
