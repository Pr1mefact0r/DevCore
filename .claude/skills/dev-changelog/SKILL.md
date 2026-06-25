---
name: dev-changelog
description: Use when a skill, schema, query, or framework change is completed. Records the change in dev/documentation.db (table `changelog`). Mandatory for every change that touches v_X.Y or dev skills.
---

# /dev-changelog — Add Changelog Entry

Inserts a row into the `changelog` table via `dev/run-dev-query.sh`.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (changelog) + target node codes being wired (get_*_by_code)
WRITES:      dev/documentation.db (changelog, refs)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert adds a changelog row; on retry, check get_recent_changelog before re-inserting.

PRE-CONDITIONS:
  - the change it records is COMPLETE (a skill/schema/query/framework change actually shipped).
  - scope/version are consistent: VERSION is required whenever SCOPE names a version; DATE is ISO 8601.
  - test-DB patches and local data fixes are out of scope — not logged.

POST-CONDITIONS:
  - insert confirmed; the new row's id is captured (first pipe field) for edge wiring.
  - typed edges wired to the node(s) the change documents (changelog --documents--> D###/B###/NT###;
    `relates` for a looser link); a pure narrative entry may be edge-less — state it.
  - FILES holds a JSON array of the actually-changed paths.

INVARIANTS-RESPECTED:
  - every skill/schema/query change ships with exactly one changelog entry (no exceptions).
  - crosslinks are typed refs edges, never freetext (the old DECISION_REF/BUG_REF columns are gone).
  - no inline SQL — all writes via run-dev-query.sh (never edit documentation.db directly).

INVARIANTS-NOT-CHECKED:
  - schema/query consistency → /dev-schema-validate; that the change itself is correct — this skill
    records the narrative, not its validity (git log carries fine-grained history).
```

---

## Step 1 — Determine entry type

| Change type | `SCOPE` | `VERSION` |
|---|---|---|
| Framework only | `[vX.Y]` | `vX.Y` |
| Schema change | `[vX.Y] Schema` | `vX.Y` |
| Dev environment only | `[DEV]` | empty |
| Both scopes | `[DEV+vX.Y]` | `vX.Y` |

Test DB patches and local data fixes are **not** logged.

## Step 2 — Fields

| Field | Required | Notes |
|---|---|---|
| `DATE` | yes | ISO 8601 |
| `SCOPE` | yes | see table above |
| `VERSION` | conditional | required if scope mentions a version |
| `TITLE` | yes | one-line headline |
| `SUMMARY` | yes | one-sentence "what + why" |
| `ROOT_CAUSE` | yes | what triggered this change ("Initial build" is valid) |
| `SOLUTION` | yes | what was done — be specific |
| `FILES` | yes | JSON array of changed paths, e.g. `["v_0.1/dev/schema.sql","v_0.1/CLAUDE.md"]` |

> Crosslinks (the old `DECISION_REF` / `BUG_REF` freetext columns) are **gone** in v3.0 — wire them as typed `refs` edges in Step 4.

## Step 3 — Insert

```bash
bash dev/run-dev-query.sh insert_changelog \
  DATE=$(date +%F) \
  VERSION='v0.2' \
  SCOPE='[DEV+v0.2]' \
  TITLE='switch dev memory to documentation.db' \
  SUMMARY='Replaced dev/*.md tracking with SQLite documentation.db.' \
  ROOT_CAUSE='Markdown logs grew unbounded; token cost.' \
  SOLUTION='Schema + run-dev-query.sh + 5 query domain files. Skills rewritten.' \
  FILES='["dev/schema.sql","dev/run-dev-query.sh","dev/dev-queries/*"]'
```

The insert echoes the new row's `id` as the first pipe-separated field — capture it for Step 4.

## Step 4 — Wire typed edges (replaces DECISION_REF / BUG_REF)

Capture this changelog row's own id, then link it to the decision/bug/target it documents via the `refs` graph.
Output is pipe-separated; `cut -d'|' -f1` grabs the id.

```bash
# this changelog row's id (most recent)
CL_ID=$(bash dev/run-dev-query.sh get_recent_changelog | head -1 | cut -d'|' -f1)   # or capture from the insert echo

# changelog --documents--> the decision it records
D_ID=$(bash dev/run-dev-query.sh get_decision_by_code CODE=D001 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_decision SOURCE_TABLE=changelog SOURCE_ID=$CL_ID POSITION=0 DECISION_ID=$D_ID RELATION=documents

# changelog --documents--> the bug it fixes
B_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B007 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_bug SOURCE_TABLE=changelog SOURCE_ID=$CL_ID POSITION=1 BUG_ID=$B_ID RELATION=documents
```

Use `RELATION=documents` for the records-this-change link; `relates` for a looser association. Wire one edge per
referenced node (no edge for a pure narrative entry — say so).

## Constraints

- **Every skill, schema, or query change ships with a changelog entry.** No exceptions.
- Use `git log` for fine-grained history; use `changelog` for human-readable narrative.
- **Never edit `documentation.db` directly.**

---

*© {{PROJECT_NAME}} Dev | dev-changelog*
