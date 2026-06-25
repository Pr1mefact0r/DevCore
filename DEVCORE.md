# DevCore v3.0 — Specification

> A generic, SQLite-based development-memory framework for Claude Code projects.
> Maintain once, deploy everywhere. This file is the architecture spec; for installation see `BACKPORT.md`.

---

## What DevCore is

DevCore is the shared **dev layer** that lives at the **root** of your project; your actual project
lives in versioned **`v_X.Y/` folders**:

```
ProjectX-Dev/
├── CLAUDE.md                     ← dev dispatcher (from DevCore)
├── dev/                          ← the brain (from DevCore)
│   └── documentation.db          committed: the project's memory
├── .claude/  devdash/            ← skills + hooks + dashboard (from DevCore)
└── v_0.1/  v_0.2/  …             ← YOUR project, versioned as it grows
```

The dev layer is identical everywhere (modulo placeholders). The contents of the `v_X.Y/` folders are
project-specific. The brain (`dev/documentation.db`) lives at the root and accumulates across **all**
project versions — the history does not break at a version bump.

---

## How it works (end-to-end)

```
Dev skill (a Markdown instruction for the agent)
   │  NEVER writes to the DB/files directly (except dev/check/) — only calls query-ids
   ▼
bash dev/run-dev-query.sh  <query_id>  KEY=VALUE …      ← single entry point for ALL DB ops
   │  1) reads the query body from dev/dev-queries/*.sql via  -- @id: … -- @end  markers
   │  2) substitutes $KEY parameters (token-greedy awk, SQL-escaped)
   │  3) bootstraps the DB on the first call: schema.sql + seeds/projectrules.sql
   │  4) runs sqlite3 against dev/documentation.db
   ▼
documentation.db  (the brain-graph, committed)
   │  typed nodes + typed refs edges
   ▼
Hooks (settings.json) enforce the discipline mechanically
   └─ enforce-runquery blocks direct sqlite3 writes → the path above is the ONLY write route
```

At **session start** the agent visibly loads its binding context from the brain
(`get_active_projectrules` + `with_watchdog`) — the rules are read fresh, never assumed from memory.

### Three hard separations

```
Dev skills    = Markdown instructions for the dev agent — write only via run-dev-query.sh
run-dev-query = single entry point; knows query-ids + parameter substitution + bootstrap
documentation = project memory as a brain-graph (SQLite, committed)
```

---

## The brain-graph

v3.0 lifts the dev memory from a logbook to a relational memory: **typed nodes connected by typed,
directed edges.**

```
Node spectrum (raw → crystallized):

  IDEA###  ──raised──▶  I###  ──produced──▶  Q###   (fact:       question→verdict→evidence)
  (thought)            (investigation)       RS###  (precedent:  problem→solution→reuse)

  Base nodes:    D### Decision · B### Bug · W### Observation · NT### Next-target · changelog
  R###   reminders     (conditional "do X when Y", optional watchdog)
  PR###  projectrules  (the discipline layer, binding — see below)
```

- **`refs` — typed directed edges** (the heart of the graph). One row = one edge
  `(source_table:source_id) --relation--> (target)`. Polymorphic target slots (exactly one non-null,
  matching `ref_kind`), 16 predicates (`raised · investigates · produced · answers · crystallized ·
  resolves · informs · validates · refutes · supersedes · duplicates · relates · documents ·
  references · reopens · reaffirms`). Provenance + supersedes are kept **acyclic at the DB level**
  (a trigger pair with a recursive walk); same-type supersession runs through the node's
  `superseded_by` column, never through an edge.
- **`recognition_keys` — reuse-before-mint.** Canonical UPPER_SNAKE recall signatures: a new finding
  is first checked against existing keys (`/dev-recall`) before a new one is minted — the same
  question is recognized across sessions instead of re-investigated.
- **`projectrules` — the discipline layer.** 28 binding rules, shipped as a seed, auto-applied on the
  first bootstrap, visibly loaded at session start (see below).

---

## The 28 project rules (the hardcoded seed)

`dev/seeds/projectrules.sql` is applied **once** on the first bootstrap (`INSERT OR IGNORE` =
idempotent). **PR001–PR025 are core (always active); PR026–PR028 are optional** (only for projects
with a runtime data/decision loop — a project without one retires them via
`retire_projectrule CODE=PR026`). Codes are template-new; the upstream provenance is in `source_ref`.

| PR | Title | Gist |
|---|---|---|
| PR001 | Data Quality first | Never ship quality-degrading changes; flag instead of silently building; back up before destructive writes |
| PR002 | Mechanical-first | Solve deterministically where possible; LLM only for semantics/judgement/creative; DB CHECK over app validation |
| PR003 | Schema-source parity | Every schema change reaches the live DB **and** `schema.sql`; idempotent DDL |
| PR004 | Code-before-text | First DB call is the allocator (`next_*_code`); get the code, then the prose; crosslink via `get_*_by_code` |
| PR005 | Brain is single source of truth | A query-decidable question is arbitrated by a read-only query; judgement is the operator's call |
| PR006 | Transient analysis never mutates canon | A one-off uses a throwaway script — never edit a query/schema/skill for a one-off result |
| PR007 | Simulate-first | Before a mechanical change: compute it read-only on real data, show before→after, then the operator decides |
| PR008 | Simplicity + reuse | Extend a proven path over a new parallel mechanism; the smallest diff wins |
| PR009 | Provenance-trace before asserting | Trace the full provenance/effect path through the graph (loop-safe) before claiming/changing |
| PR010 | No state without its why | Every state-changing write carries its reason readable **in** the record; the mechanism enforces it |
| PR011 | No new/changed rule without operator-OK | A "should be a rule" reflex is proposed, never autonomously inserted |
| PR012 | Watchdogs are brain-anchored + self-healing | A machine-checkable trigger arms a watchdog whose alarm state lives in the record; session-start re-arms/surfaces |
| PR013 | Shared-query consumer check | Before extending a multi-site query, list all consumers and prove none breaks |
| PR014 | Adjudication-first | On an anomaly/recurring question: recall first; on a hit cite **and** revalidate; crystallize the new (Q/RS) |
| PR015 | Guard fixes the source, not the symptom | Guard corruption at its source (write-time CHECK/FK/trigger); make the symptom safe separately |
| PR016 | Rule-evolution: hardening vs new law | Same concern → inline addition; new concern → a new node + edge |
| PR017 | Edge direction + predicate convention | One directed edge per relationship, queryable from both ends; direction follows the genesis arrow |
| PR018 | Persist, don't note | "done/logged/fixed" is a hypothesis until a durable row proves it (cite the code/id) |
| PR019 | Build-time relation analysis | Before a build on a node/skill/schema, query the typed edges around it (= the dependency map) |
| PR020 | Deep-recall on should-know instructions | When an instruction presupposes prior knowledge, search the brain + follow refs until the surface closes |
| PR021 | Braincode comments are graph entrypoints | Resolve a braincode in a comment (`get_*_by_code` → edges) + read current state; never trust the aging comment |
| PR022 | Channel/store language split | Operator output in the project language; persisted DB free-text in **one** record language (English); identifiers always English |
| PR023 | Post-change graph reconciliation | A change reconciles the graph in the same step (implemented NT → done, obsoleted decision → superseded) |
| PR024 | Evolution/provenance from the timeline | For "how did this come to be", reconstruct the date-ordered brain timeline |
| PR025 | Hook output is binding | Comply with hook surfacing or give an explicit why-on-skip; never a silent pass |
| PR026 | Query-sample validity *(optional)* | Cite the window; a fit on a non-stationary sample is a hypothesis, not a verdict |
| PR027 | Runtime-loop changes pending-live-verify *(optional)* | A runtime-loop change is shipped-pending-verify until a watchdog confirms the first live event |
| PR028 | Monitor home by time-semantics *(optional)* | Discrete trigger → a watchdog; a continuous 24/7 monitor → a co-process service |

Full rule text any time from the brain: `bash dev/run-dev-query.sh get_active_projectrules`.

---

## Skills (17)

Standard frontmatter (`name:` + `description:`) plus a `## Contract` block (11 fields) per `SKILL.md`;
Claude Code's loader registers them automatically.

| Skill | Trigger | writes |
|---|---|---|
| `/dev-bug-log` | bug found | `bugs` |
| `/dev-decision-log` | design decision | `decisions` |
| `/dev-observation` | observation (not yet a bug) | `observations` |
| `/dev-changelog` | skill/schema/query change done | `changelog` |
| `/dev-next-target` | future work identified | `next_targets` |
| `/dev-idea` | raw, undecided thought | `ideas` (IDEA###) |
| `/dev-investigate` | open/close an investigation | `investigations` (I###) |
| `/dev-adjudicate` | a query/data **settled** a fact | `adjudications` (Q###) |
| `/dev-resolution` | reusable "how we solved it" | `resolutions` (RS###) |
| `/dev-reminder` | conditional "do X when Y" | `reminders` (R###) |
| `/dev-recall` | anomaly/recurring question — "did we settle this?" | — (read-only; recall + revalidate) |
| `/dev-audit` | deep trace through skill chains/schema | — (read-only) |
| `/dev-schema-validate` | schema/query/skill consistency | — (read-only) |
| `/dev-note` | a note dropped in chat | composite → routes to the right atomic skill |
| **`/dev-external-review`** | **external AI content pasted** | composite → `dev/check/` → **verify vs brain + codebase** → route |
| `/dev-version-bump` | version bump | composite → schema-validate/audit → changelog |
| `/dev-publish` | ship the project to its clean public repo | — (reads brain; commits the *separate* public repo) |

### `/dev-external-review` — the automated-vetting gate

When you paste content from another model (a suggested patch, a "here's how to fix it", a design
proposal), `/dev-external-review` is the gate that keeps **AI slop out of your commits**. It saves the
content to `dev/check/`, then **verifies every claim against the brain and the actual codebase** —
does this contradict a settled decision (`D###`/`Q###`)? does the file/function it references even
exist? is this already a known bug or a superseded approach? — and only then routes the verified parts
into the brain (or rejects them). External models lack your project context; this skill supplies it,
turning "looks plausible" into "checked against ground truth" before anything lands.

---

## Hooks (7) + lib

`.claude/hooks/`, wired via `.claude/settings.json`. They mechanically enforce what would otherwise
only be documented:

| Hook | Event | Role |
|---|---|---|
| `session-start.sh` | SessionStart | injects the mandate to visibly load projectrules + watchdogs |
| `enforce-runquery.sh` | PreToolUse(Bash) | **blocks** direct `sqlite3` writes to `documentation.db` (exit 2) |
| `query-consumer-gate.sh` | PostToolUse(Edit/Write) | warns on query-file edits (consumer check, PR013) |
| `graph-reconcile.sh` | PostToolUse(Edit/Write) | surfaces graph reconciliation (PR023) |
| `op-error-capture.sh` | PostToolUse(Bash) | passively writes failed bash calls to `op_error_raw` |
| `edge-on-mention.sh` | PostToolUse(Bash) | spots a freshly-minted node with no edge → demands typed refs (PR017/019) |
| `braincode-surface.sh` | PostToolUse(Read) | surfaces braincodes in read files as graph entrypoints (PR021) |

`_op_error_lib.sh` is the shared lib for `op-error-capture`. **Auto-memory is disabled in the
template** (`"autoMemoryEnabled": false`) — the brain is the memory, not Claude's auto-memory.

---

## DB schema (`dev/schema.sql` — 14 tables, 2 triggers)

```
Base nodes:    decisions · bugs · changelog · observations · next_targets
Brain-graph:   adjudications · resolutions · investigations · ideas · reminders · projectrules
               recognition_keys · refs · op_error_raw
```

Shared conventions: a `code` column for human IDs (`D001`, `B007`, `PR014`); a `scope` column for
`[vX.Y]`/`[DEV]`/`[DEV+vX.Y]`; `status` columns with controlled string values (no ENUM); lifecycle
columns (`superseded_by`, `reopened_reason`, `reaffirmed_at`) on the base nodes; an optional
`memory_ref` column. The 2 triggers keep the provenance/supersedes subgraph acyclic (recursive walk,
`RAISE(ABORT)` on a cycle). Indices on frequently-filtered fields.

---

## Query layer (`dev/dev-queries/*.sql` — 14 domains)

Domain files with `-- @id: <name>` / `-- @end` markers. `run-dev-query.sh` extracts the block,
substitutes `$KEY` placeholders (token-greedy awk) and runs it. Query-ids are globally unique and
table-namespaced (e.g. `insert_projectrule`, `next_decision_code`, `link_bug`).

- `decisions · bugs · changelog · observations · next_targets` — base nodes (allocator + CRUD + lifecycle)
- `refs.sql` — the edge graph: `link_*` (per node type), `edges_from`, `get_refs_to_node`, `walk_neighborhood`, `detect_cycles`
- `recognition_keys.sql` — `register_key`, `search_keys`, `all_keys` (reuse-before-mint)
- `adjudications` (Q) · `resolutions` (RS) · `investigations` (I) · `ideas` (IDEA) — answer/process/idea nodes + lifecycle
- `reminders.sql` (R) — reminders + watchdog (`with_watchdog`, `set_watchdog_spec`, `set_watchdog_fired`, …)
- `projectrules.sql` (PR) — the discipline layer (`get_active_projectrules`, `retire_projectrule`, …)
- `op_errors.sql` — the passive bash-error sink

---

## DevDash (16 routes)

A minimal FastAPI server, a **read-only** browser view of `documentation.db` (sidebar layout,
colour-coded node-type badges, dark theme, no auth → localhost only, one port per project):

```
/  dashboard          /decisions   /bugs        /changelog    /observations
/targets              /reminders   /projectrules            /adjudications
/resolutions          /investigations           /ideas       /recognition-keys
/health               /graph       /graph/node  (JSON, ego-focus for the graph explorer)
```

The **`/graph` explorer** renders the whole brain-graph (HTML5 canvas, force-directed, ego-focus).
`/health` shows staleness/revalidation needs. Start: `cd devdash && pip install -r requirements.txt`,
then `DEVCORE_DB=../dev/documentation.db uvicorn main:app --port 87XX`. Details: `devdash/README.md`.

---

## Memory: the brain is the source

DevCore is brain-driven. Claude's auto-memory (`MEMORY.md` / `memory/*.md`) is **mechanically
disabled** in the template (`autoMemoryEnabled: false`) — it is historical archive, not live state.
Durable **discipline** belongs in the brain as a `projectrule`; durable **project facts** in the
`dev/*` tables; never a reflex-write to memory. The `memory_ref` columns exist for projects that
deliberately do want memory (flag back to `true`) — the default is **off**.

---

## Backport / new project

Full recipe in **`BACKPORT.md`** (including where a migrated project's docs must live, and that a
**new Claude Code session** is required after the backport so the skills/hooks load). In short:

- **Existing project:** DevCore into the root, resolve the placeholders, the brain bootstraps on the
  first call. Reorganizing your own project code into `v_X.Y/` is the **human user's** call (path-sensitive).
- **New project:** a `beschreibung.md` in the root → the agent builds DevCore around it first, then the project.

**No automatic synchronization** — backporting is deliberately manual.

### Publishing the result

The workshop (`<Name>-Dev`) keeps everything — the DevCore dev-layer, the brain, and the project in
`v_X.Y/`. **`/dev-publish`** ships only the latest `v_X.Y/` deliverable to a separate **clean public
repo** (no DevCore, no `documentation.db`): it copies the deliverable out, reads the diff, pulls the
matching context from the brain, drafts the GitHub changelog, and pushes — exactly how this repo's own
workshop (`DevCore-Dev`) publishes to `DevCore`. (Decision D017.)

---

## Placeholders

| Placeholder | Meaning | Examples |
|---|---|---|
| `{{PROJECT_NAME}}` | project name (display) | `Acme`, `Ledger`, `Orbit` |
| `{{PREFIX}}` | runtime skill prefix (for the `v_X.Y/` project skills) | `ac`, `ld`, `ob` |
| `{{REPO_SLUG}}` | GitHub slug | `Pr1mefact0r/MyProject-Dev` |

Verify after a backport: `grep -rE '\{\{[A-Z_]+\}\}' . && echo FAIL || echo OK`

---

*DevCore v3.0 · Pr1mefact0r · SQLite-based development-memory framework · CC BY-NC-SA 4.0*
