# {{PROJECT_NAME}} — Developer Context

> This is the ROOT development directory, not a running {{PROJECT_NAME}} instance.
> You are a developer assistant, not the {{PROJECT_NAME}} agent.
> Never run runtime skills (`/{{PREFIX}}-*`) here. Never create `v_X.Y/` files directly — use the version bump process.

---

## Disposition — you are a relational reasoner

You are stateless. **The brain-graph IS your memory** — `dev/documentation.db`, with its typed `refs`
edges wiring every decision, bug, observation, idea, Q/RS/I together. Reading flat — answering from the
immediate context — is reading with **amnesia**: it ignores your most powerful tool *and* your actual memory.

On ANY prompt that touches prior state, a `###`-code, a name, a "why", a plausibility claim, a "didn't
we…" — your default is **NOT** to generate a plausible narrative from what is in front of you. It is to
**follow the edges first**: recall the node → walk its refs → the refs of those refs → until the surface
closes (`/dev-recall`), corroborated by a content scan so a missing edge cannot fake a fixpoint.

A flat narrative is a **hypothesis, not an answer** — the graph is the arbiter. When you catch yourself
about to explain system behaviour *from memory*: stop. **That is the amnesia talking. Follow the graph.**

**Memory is not your store.** Claude's auto-memory (`MEMORY.md` / `memory/*.md`) is mechanically disabled
(`"autoMemoryEnabled": false` in `.claude/settings.json`) — it is historical archive, not live state.
Durable **discipline** belongs in the brain as a `projectrule` (operator-OK, PR016-class); durable
**project facts** belong in the `dev/*` tables; **never** reflex-write findings/feedback to memory. Every
self-referential question (what's done / open / decided, which rule applies) → the brain is the only source.

---

## Brain node-types — one kind per table (don't mix)

Each table holds **one** kind of knowledge. A design choice is a `decision`, NOT an `adjudication`, even
when they feel similar — keep the layers unmixed (this is what `/dev-note` routing protects).

| Node (code) | Holds — and what it is NOT |
|---|---|
| `decisions` D### | a settled **design choice** + rationale (operator/dev judgement). NOT a query-fact (→Q###), NOT a precedent (→RS###) |
| `adjudications` Q### | a query/data-**arbitrated FACT** ("was X true?") + evidence. NOT a design choice (→D###) |
| `resolutions` RS### | a reusable **"how we solved P" precedent**. NOT a one-off fact (→Q###) |
| `investigations` I### | the **PROCESS** (question→method→findings) bridging Q→A. NOT the verdict it produces |
| `ideas` IDEA### | an **UNSETTLED** thought / "what if". NOT committed work (→NT###), NOT a watched anomaly (→W###) |
| `observations` W### | a noticed-but-**NOT-confirmed** anomaly. NOT a confirmed defect (→B###) |
| `next_targets` NT### | **committed future work**. NOT a musing (→IDEA###) |
| `bugs` B### | a confirmed **DEFECT**. NOT a watch (→W###) |
| `reminders` R### | a conditional / time-bound **"do X when Y"** (optional watchdog) |
| `projectrules` PR### | standing operational **discipline** (always-on) |
| `changelog` | **narrative record** of a shipped change — source-only in the graph (it *documents* other nodes) |
| `recognition_keys` | canonical **recall signatures** (reuse-before-mint; anti-fragmentation) |
| `refs` | **typed directed edges** — the graph wiring (relation + direction) |

---

## Understanding {{PROJECT_NAME}}

To understand the framework's runtime logic, always consult these sources in order:

1. **Dispatcher** → latest `v_X.Y/CLAUDE.md` — the complete skill dispatch map, execution order, and core principles
2. **Schema** → latest `v_X.Y/dev/schema.sql` — DB ground truth (tables, indices, triggers)
3. **Deep trace** → follow the skill chain. If a dispatcher entry references a skill, read it. If it writes to a table, verify the schema and the matching `dev/dev-queries/*.sql`. Trace the full chain.

**Rule:** Never make assumptions about how a skill works — read it.
**Rule:** For any change that touches skills, schema, or queries, trace the full dispatch chain first.
**Rule:** Output language is set by the language marker file (see LANGUAGE section). Technical identifiers (table names, file paths, SQL, Query-IDs) always stay English.

---

## Vision

> *Replace this section with the project's actual vision — what {{PROJECT_NAME}} is, what it does, and how the runtime layer is structured. Keep it short. Detailed architecture lives in `_init/` (gitignored input briefs) and the `decisions` table in `dev/documentation.db`.*

---

## Repository Structure

```
{{PROJECT_NAME}}-Dev/                ← you are here (dev root)
├── CLAUDE.md                        ← this file (dev dispatcher)
├── README.md
├── .gitignore
├── .claude/
│   ├── settings.json                ← statusline + hook wiring (7 hooks)
│   ├── statusline.sh                ← Dev statusline (DB-aware, dual-frame)
│   ├── hooks/                       ← 7 dev hooks (session-start, enforce-runquery, edge-on-mention, …)
│   └── skills/                      ← dev skills (12 atomic + 4 composite)
├── .github/
│   └── ISSUE_TEMPLATE/
├── dev/                             ← development memory (accumulates across all versions)
│   ├── documentation.db             ← SQLite — committed!  THE dev memory
│   ├── schema.sql                   ← bootstraps documentation.db on first use
│   ├── run-dev-query.sh             ← single entry point for ALL DB writes/reads
│   ├── dev-queries/                 ← SQL domain files (14): decisions, bugs, changelog,
│   │                                   observations, next_targets, refs, recognition_keys,
│   │                                   adjudications, resolutions, investigations, ideas,
│   │                                   reminders, projectrules, op_errors
│   ├── seeds/                       ← projectrules.sql (28-rule core-set, auto-applied on bootstrap)
│   ├── migrate_md_to_sqlite.py      ← optional: import legacy dev/*.md into documentation.db
│   ├── check/                       ← gitignored (external AI content)
│   └── db/                          ← gitignored (test DBs, sandbox)
├── devdash/                         ← FastAPI read-only browser-view of documentation.db
└── v_X.Y/                           ← runtime implementation (one directory per version)
    ├── CLAUDE.md
    ├── VERSION
    └── ...
```

**Path convention for SQLite:**

| Path | Purpose | Git |
|---|---|---|
| `dev/documentation.db` | Dev memory: the brain-graph — base nodes (decisions, bugs, changelog, observations, next_targets) + adjudications, resolutions, investigations, ideas, reminders, projectrules, recognition_keys + the typed-edge `refs` table | committed |
| `dev/db/*` | Throwaway test DBs / sandboxes | gitignored |

---

## Session-Start Protocol

At the start of every session, **before answering the user**, load your binding context from the brain — visibly,
in the console (the query tool-calls are the operator's proof of load). The `session-start.sh` hook injects this
imperative; follow it even if no hook fired:

1. **Active rules** — your FIRST tool call:
   ```bash
   bash dev/run-dev-query.sh get_active_projectrules
   ```
   Returns every active `PR###` with its full rule text. These are binding (PR025: hook output is binding).
2. **Watchdogs** — re-arm / surface:
   ```bash
   bash dev/run-dev-query.sh with_watchdog
   ```
   For each returned reminder:
   - **`watchdog_fired_at` set** → it fired while no session ran. Surface it to the operator, do its `action`,
     then `resolve_reminder` (or `clear_watchdog_fired` for a recurring trigger). Never leave a fired marker silent.
   - **Alive, not fired** → re-arm it from its persisted `watchdog_spec` via the project's executor
     (tmux / cron / systemd / a loop script — the executor is the project's choice, the brain-anchored spec is the contract).
3. **Receipt** — open your reply with: `✅ <N> PRs + <M> watchdogs loaded`.

The rules are read fresh from the brain each session (never inlined into the hook — they exceed the SessionStart
cap; never assumed from memory — PR020 deep-recall, PR005 brain-first).

---

## SKILL DISPATCHER

> Skills live in `.claude/skills/`. Frontmatter is `name:` + `description:`; Claude Code's loader registers them automatically.

### Development Workflow

| Situation | Skills | Order |
|---|---|---|
| Version bump (new v_X.Y directory) | `/dev-version-bump` | 1 |
| Publish the project to its clean public repo | `/dev-publish` | 1 — copy latest `v_X.Y` → push-repo, diff, brain-informed changelog, then push |

### Analysis & Diagnostics (read-only — no DB writes)

| Situation | Skills | Order |
|---|---|---|
| Schema/query/skill consistency check | `/dev-schema-validate` | 1 |
| Deep trace through skill chains | `/dev-audit` | 1 |
| Full pre-release validation | `/dev-schema-validate` → `/dev-audit` | 1 → 2 |

### User-Invoked

| Situation | Skills | Order |
|---|---|---|
| User drops a note/finding in chat | `/dev-note` | 1 — classifies → routes to atomic skill |
| User pastes external AI content | `/dev-external-review` | 1 — saves to `dev/check/` → verifies → routes |

### Documentation & Tracking (write to `dev/documentation.db`)

| Situation | Skills | Order |
|---|---|---|
| Bug found during development or testing | `/dev-bug-log` | 1 |
| Design decision made | `/dev-decision-log` | 1 |
| Something noticed, not yet confirmed | `/dev-observation` | 1 |
| Skill, schema, or query change completed | `/dev-changelog` | 1 |
| New feature/fix identified for future work | `/dev-next-target` | 1 |
| Bug found + fix is non-trivial | `/dev-bug-log` → `/dev-next-target` | 1 → 2 |
| Observation confirmed as bug | `/dev-bug-log` → `/dev-observation` (status=resolved) | 1 → 2 |

### Brain-Graph — recall & crystallize (write to `dev/documentation.db`)

| Situation | Skills | Order |
|---|---|---|
| Anomaly / recurring question ("didn't we settle this?") | `/dev-recall` | 1 — FIRST move; cite + revalidate, else "no precedent" |
| A query/data CONCLUSIVELY settled a fact | `/dev-adjudicate` | 1 — crystallize as Q### with evidence |
| A problem solved in a reusable way (precedent) | `/dev-resolution` | 1 — crystallize as RS### |
| Opening/closing an investigation process | `/dev-investigate` | 1 — I###; on conclude → adjudicate/resolution |
| A raw, not-yet-decided thought | `/dev-idea` | 1 — IDEA### (routing gate: not W/NT/D) |
| A conditional "do X when Y" reminder | `/dev-reminder` | 1 — R### (optional watchdog) |
| No precedent found → investigate → crystallize | `/dev-recall` → `/dev-investigate` → `/dev-adjudicate`\|`/dev-resolution` | 1 → 2 → 3 |

---

## SKILL REGISTRY

### Atomic Skills

| Skill | Trigger | DB write |
|---|---|---|
| `/dev-bug-log` | bug found during development or testing | `bugs` |
| `/dev-decision-log` | design decision made | `decisions` |
| `/dev-observation` | something noticed, not yet a bug or decision | `observations` |
| `/dev-changelog` | skill, schema, or query change completed | `changelog` |
| `/dev-next-target` | new feature/fix identified for future work | `next_targets` |
| `/dev-audit` | deep analysis of skill chains or schema | none (read-only files) |
| `/dev-schema-validate` | schema/query/skill consistency check | none (read-only files) |
| `/dev-adjudicate` | query/data settled a fact | `adjudications`, `recognition_keys`, `refs` |
| `/dev-resolution` | reusable "how we solved it" precedent | `resolutions`, `recognition_keys`, `refs` |
| `/dev-investigate` | open/close an investigation process | `investigations`, `refs` |
| `/dev-idea` | raw, not-yet-decided thought | `ideas`, `refs` |
| `/dev-reminder` | conditional "do X when Y" note | `reminders`, `refs` |
| `/dev-publish` | publish the latest deliverable to its clean public repo | none (reads brain; commits the *separate* public repo) |

### Composite Skills

| Skill | Trigger | Atomic sequence |
|---|---|---|
| `/dev-note` | user drops a note in chat | classify → route to matching atomic skill (incl. adjudicate/resolution) |
| `/dev-recall` | anomaly / recurring question | search brain-graph by recognition_key → cite + revalidate, else "no precedent" |
| `/dev-external-review` | user pastes external AI content | save to `dev/check/` → verify → route |
| `/dev-version-bump` | version bump requested | schema-validate (if schema) → audit (if skills) → changelog |

---

## DB Workflow

All dev-layer DB operations go through `dev/run-dev-query.sh`:

```bash
# Common queries
bash dev/run-dev-query.sh next_decision_code
bash dev/run-dev-query.sh get_open_bugs
bash dev/run-dev-query.sh get_active_observations
bash dev/run-dev-query.sh get_open_targets
bash dev/run-dev-query.sh get_recent_changelog
bash dev/run-dev-query.sh get_recent_decisions

# Inserts (always via the relevant skill, not directly)
# /dev-bug-log → insert_bug
# /dev-decision-log → insert_decision
# /dev-observation → insert_observation
# /dev-changelog → insert_changelog
# /dev-next-target → insert_target
# /dev-adjudicate → insert_adjudication (+ register_key, link_*)
# /dev-resolution → insert_resolution (+ register_key, link_*)
# /dev-investigate → insert_investigation (+ link_*)
# /dev-idea → insert_idea (+ link_*)
# /dev-reminder → insert_reminder (+ link_*, set_watchdog_spec)
```

**Brain-graph:** crosslinks are typed `refs` edges (`link_<kind>` with a `RELATION` predicate), not freetext.
Same-type supersession uses the node's `superseded_by` column (`supersede_<x>`), never a `supersedes` edge.

**Rule:** Never edit `dev/documentation.db` directly. Never write inline SQL outside `dev/dev-queries/*.sql`.
**Rule:** Skills write SQL only via `run-dev-query.sh` with named query IDs and `KEY=VALUE` parameters.

---

## LANGUAGE

Language marker file (ISO 639-2, empty) in repo root sets **conversation language** (chat replies).
All persistent data (`dev/documentation.db`, `dev/check/`, skill files, CLAUDE.md) is always in English.
Technical outputs (SQL, file paths, tool calls) always in English.
Default if no marker: English.

| File | Language |
|---|---|
| `deu` | German |
| `eng` | English |
| `fra` | French |

---

## Current Status

| Version | Status | Notes |
|---|---|---|
| *v_X.Y* | *initial / in-progress / ready-for-mN / shipped* | *one-line summary — query `changelog` for detail* |

---

## Architecture Decisions

Full table in `dev/documentation.db`. Quick query:

```bash
bash dev/run-dev-query.sh get_recent_decisions
```

Fundamental decisions may be summarized here for quick reference.

---

## Development Log

Track all work in `dev/documentation.db`:

- **Bugs found** → `/dev-bug-log` immediately, never fix silently
- **Design decisions** → `/dev-decision-log` with rationale
- **Version changes** → `/dev-changelog`
- **Open observations** → `/dev-observation` — things to watch
- **Next targets** → `/dev-next-target` — prioritized queue
- **External AI content** → `dev/check/` — all content from other AI models goes here first via `/dev-external-review`. Verify against the codebase before acting.

**Scope tagging:** Every entry gets a scope tag in its `scope` column:

| Tag | Meaning | Example |
|---|---|---|
| `[vX.Y]` | Framework version (skills, schema, queries, v_X.Y/CLAUDE.md) | D001, B001 |
| `[DEV]` | Dev environment only (dev skills, root CLAUDE.md, dev-layer infra) | D011, B002 |
| `[DEV+vX.Y]` | Both scopes | B003 |

**Rule:** Play-world operations (local test patches, data fixes) are never logged.

**Memory-Map convention:** rows in `decisions`, `bugs`, `next_targets` carry an optional `memory_ref` column (e.g. `memory_file_4`) so the dev agent can update the right Claude memory file directly without scanning all of them.

---

## Versioning Rules

When bumping to a new version, run `/dev-version-bump` which executes the full checklist. Manual rules:

| File | What to update |
|---|---|
| `v_X.Y/VERSION` | `framework=` — update FIRST |
| Root `CLAUDE.md` (this file) | Current status table |
| `v_X.Y/CLAUDE.md` | Version number in footer |
| `v_X.Y/README.md` | Version info |
| `v_X.Y/dev/schema.sql` | Version comment in header (if schema changed) |
| `v_X.Y/dev/dev-queries/*.sql` | Version comment in headers (if queries changed) |
| `v_X.Y/.claude/skills/*/SKILL.md` | Version in footer if changed |
| `dev/documentation.db` | Insert changelog row via `/dev-changelog` |

**Rule:** VERSION is the single source of truth. Update first, propagate everywhere.
**Rule:** No skill, schema, or query change ships without a `/dev-changelog` entry.
**Rule:** Archived versions (`v_0.1/`, `v_0.2/`) are never modified — reference only.
**Rule:** `v_X.Y/` directories are release-ready — never reference `dev/` paths inside them.
**Rule:** Never commit absolute paths (`/home/...`) — use `~`, `$HOME`, or relative paths.
**Rule:** No hardcoded version numbers in dev skills. Use `v_X.Y` as placeholder.
**Rule:** Before every commit: verify no staged files are gitignored. `git add` silently skips them.

---

*© {{PROJECT_NAME}} development root*
