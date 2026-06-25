---
name: dev-idea
description: Use when a raw, NOT-YET-DECIDED thought surfaces — a musing, "what if", principle-candidate, or direction-not-chosen — that is neither a watched anomaly (→ dev-observation) nor committed work (→ dev-next-target) nor a settled choice (→ dev-decision-log). Records it in dev/documentation.db (table `ideas`) with the next available IDEA### code.
---

# /dev-idea — Capture an Un-decided Idea (the hypothesis-stage of the brain-graph)

Inserts a row into the `ideas` table of `dev/documentation.db` via `dev/run-dev-query.sh`.
An idea is the **UNSETTLED end of the epistemic spectrum** — the hypothesis below NT###/D###.
It matures into a decision/target/answer (`crystallized` → `promote_idea`), or is `dropped` / `superseded`.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (ideas — recall/inspection) (via dev/run-dev-query.sh)
WRITES:      dev/documentation.db (ideas; refs — typed edges where the idea relates to / sprang from context, but a fresh idea is the genesis-ROOT and is OFTEN legitimately edge-less) (via dev/run-dev-query.sh)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert_idea creates a new IDEA### row. On retry after a partial failure, re-confirm the captured code was not already consumed (re-run next_idea_code) before re-inserting.

PRE-CONDITIONS:
  - recall-first: scan for a matching idea BEFORE minting (get_recent_ideas / search_ideas_recognition / get_ideas_by_recognition_key). It may already be a logged idea (append a note or supersede instead of duplicating), or already settled as a D###/NT###/Q### (then it is NOT an un-decided idea — route there).
  - allocator-first (code-before-text, PR005-class): next_idea_code is the FIRST DB call; capture with `head -1 | cut -d'|' -f1` and echo to confirm before writing any prose.
  - ROUTING gate (this skill exists to STOP the mis-file): confirm the item is genuinely a not-yet-decided thought, NOT a noticed anomaly (→ /dev-observation W###), NOT committed work (→ /dev-next-target NT###), NOT a settled choice (→ /dev-decision-log D###). Forcing a thought into the wrong table is the exact data-quality violation this table was built to end.
  - scope tag must NOT contain `v_X.Y` (use `[v3.0]`, not `[v_3.0]`) — the `scope NOT GLOB '*v_[0-9]*'` CHECK rejects it.

POST-CONDITIONS:
  - insert confirmed by inspecting the printed `id | code | status` line (visual check, not just exit 0); status defaults to `idea`.
  - if the idea relates to a decision/observation/idea that sparked it, the typed edge is wired (Step 4); if it is a standalone genesis-root, that is explicitly fine (an idea is the one node-type where edge-less is normal).
  - on PROMOTION: the `crystallized` edge is wired AND promote_idea is called (status → `promoted`, promoted_to set).

INVARIANTS-RESPECTED:
  - data quality (PR001-class) — ideas are real un-decided thoughts in their OWN home, not noise crammed into W###/NT###.
  - code-before-text (PR005-class) — allocator-first.
  - edge direction+predicate convention — Step 4 wires the canonical directed predicate; one edge per relationship, never reciprocal.
  - code-before-text capture is pipe-cut from get_idea_by_code (no RETURNING / no INSERT-output parsing).
  - same-type IDEA→IDEA supersession via the `superseded_by` COLUMN (supersede_idea), never a `supersedes` refs-edge (CHECK-rejected).

INVARIANTS-NOT-CHECKED:
  - no DDL — the ideas table ships via dev/schema.sql; this skill never alters schema.
  - executor/runtime concerns (tmux, watchdog) — n/a; single sub-2-min wrapper call.
```

---

## When is it an IDEA (vs the neighbours)?

| It is… | Home | Skill |
|---|---|---|
| a not-yet-decided thought / musing / "what if" / principle-candidate / direction-not-chosen | `ideas` IDEA### | **this** |
| something NOTICED in work, to watch for confirm/deny | `observations` W### | /dev-observation |
| committed work to do | `next_targets` NT### | /dev-next-target |
| a settled choice (with rationale) | `decisions` D### | /dev-decision-log |

The maturity ladder: **idea → investigation → adjudication/resolution → decision/next_target.**

## Step 1 — Get next idea code (allocator-first)

```bash
bash dev/run-dev-query.sh next_idea_code | tail -1
```

Output e.g. `IDEA001` (the prefix is the word `IDEA`, NO hyphen). Echo it; use as `$CODE`.

## Step 2 — Fields

| Field | Required | Notes |
|---|---|---|
| `CODE` | yes | next IDEA### from Step 1 |
| `SCOPE` | yes | `[v3.0]` / `[DEV]` / `[DEV+v3.0]` (no `v_X.Y` — CHECK rejects) |
| `TITLE` | yes | concise (no period) |
| `BODY` | yes | the raw thought |
| `RATIONALE` | pass `''` if none | why it might matter |
| `RECOGNITION_KEY` | pass `''` if none | reuse an existing key (recall-first) for cross-spectrum recall — FK into `recognition_keys` |
| `RECOGNITION_TEXT` | pass `''` if none | the signature phrase |
| `AS_OF` | pass `''` if none | context-date |

(`status` is not a parameter — it defaults to `idea`.)

## Step 3 — Insert + confirm

```bash
bash dev/run-dev-query.sh insert_idea \
  DATE=$(date +%F) CODE=IDEA001 SCOPE='[v3.0]' \
  TITLE='role files into the brain-graph' \
  BODY='What if role definitions lived as ideas/decisions in the DB rather than flat files?' \
  RATIONALE='' RECOGNITION_KEY='' RECOGNITION_TEXT='' AS_OF=''
```

Confirm the printed `id | code | status` line (status defaults to `idea`). Then capture the idea's own id for Step 4:

```bash
IDEA_ID=$(bash dev/run-dev-query.sh get_idea_by_code CODE=IDEA001 | head -1 | cut -d'|' -f1)
```

(The id is the FIRST pipe-separated column — there is no RETURNING/INSERT-output id to parse.)

## Step 4 — Wire typed edges

An idea is the **genesis-ROOT**, so it is the one node-type where being edge-less is legitimate
(a brand-new thought has nothing upstream). Wire an edge only when the idea genuinely connects.
The link verb names the TARGET kind; resolve every target id via its `get_<x>_by_code` (pipe-cut, first column):

| Relationship | Edge (directed) | How |
|---|---|---|
| a decision sparked the idea | `D### --informs--> idea` (decision is the SOURCE, idea the TARGET) | `link_idea SOURCE_TABLE=decisions SOURCE_ID=$DEC_ID POSITION=0 IDEA_ID=$IDEA_ID RELATION=informs` |
| idea relates to a related observation | `idea --relates--> W###` (idea is the SOURCE) | `link_observation SOURCE_TABLE=ideas SOURCE_ID=$IDEA_ID POSITION=0 OBSERVATION_ID=$W_ID RELATION=relates` |
| **idea matured → became a D/NT/Q (PROMOTION)** | `idea --crystallized--> D###` (idea is the SOURCE) | `link_decision SOURCE_TABLE=ideas SOURCE_ID=$IDEA_ID POSITION=0 DECISION_ID=$DEC_ID RELATION=crystallized` then `promote_idea CODE=… PROMOTED_TO=D### DATE=…` |

For promotion to a next_target or adjudication, use `link_next_target` (`NEXT_TARGET_ID=…`) or `link_adjudication` (`ADJUDICATION_ID=…`) with `SOURCE_TABLE=ideas RELATION=crystallized`, then `promote_idea`.

**Same-type idea↔idea supersession** (a better idea replaces this one) goes via the COLUMN, never a refs-edge:

```bash
NEW_ID=$(bash dev/run-dev-query.sh get_idea_by_code CODE=IDEA002 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh supersede_idea CODE=IDEA001 NEW_ID=$NEW_ID DATE=$(date +%F)
```

(A `supersedes` refs-edge between two ideas is CHECK-rejected — supersession is monotonic, acyclic by construction. `NEW_ID` must be the newer idea's id, which is > the old one's id.)

ONE directed edge per relationship — never reciprocal.

## Step 5 — Lifecycle (as the idea matures or dies)

| Outcome | Action |
|---|---|
| matured into a decision/target/answer | wire the `crystallized` edge (Step 4) + `promote_idea CODE=IDEA### PROMOTED_TO=<D###/NT###/Q###> DATE=$(date +%F)` |
| considered + rejected/abandoned | `drop_idea CODE=IDEA### REASON='why' DATE=$(date +%F)` |
| replaced by a better idea | `supersede_idea CODE=IDEA### NEW_ID=<newer idea id> DATE=$(date +%F)` |
| still mulling, add a thought | `append_note CODE=IDEA### NOTE='…' DATE=$(date +%F)` |

## Constraints

- Ideas are NOT observations and NOT targets — they are **un-decided thoughts**. Routing them correctly IS the point.
- A fresh idea may be edge-less; that is the ONE node-type where the "wire its root" prompt is satisfied by "standalone genesis-root".
- Code prefix is the literal word `IDEA` with NO hyphen (e.g. `IDEA001`).
- Scope tag is mandatory and must not contain `v_X.Y`.
- **Never edit `dev/documentation.db` directly.** All writes go through `dev/run-dev-query.sh` with named query-ids and `KEY=VALUE` params.

---

*© {{PROJECT_NAME}} Dev | dev-idea*
