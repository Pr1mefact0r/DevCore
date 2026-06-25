---
name: dev-next-target
description: Use when a new feature, improvement, or fix is identified for future work. Adds, updates, or completes entries in dev/documentation.db (table `next_targets`).
---

# /dev-next-target — Manage Target Queue

Inserts/updates rows in the `next_targets` table via `dev/run-dev-query.sh`.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (next_targets) + source node codes being wired (get_*_by_code)
WRITES:      dev/documentation.db (next_targets, refs)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert mints a target; on retry check get_open_targets before re-inserting.
             Status/priority transitions (update_target_status / _priority / complete / supersede) are idempotent.

PRE-CONDITIONS:
  - read get_open_targets first to avoid duplicates and choose a sensible priority slot.
  - on Add: allocate next_target_code as the first write call (code-before-text, PR005-class);
    codes are NT### (no hyphen — scope lives in SCOPE, not in the code).
  - scope tag is mandatory.

POST-CONDITIONS:
  - insert confirmed; the new row's id is captured (first pipe field) for edge wiring.
  - the source(s) the target came from are wired as typed refs edges (next_target --relates--> B###/W###/D###);
    a net-new target may be edge-less — state it.
  - status/priority transitions applied via the dedicated queries, not by re-inserting.

INVARIANTS-RESPECTED:
  - code-before-text (PR005-class); scope tag mandatory; never orphan a target (wire its source).
  - sources are typed refs edges, never freetext (the old SOURCE_REFS column is gone).
  - no inline SQL — all writes via run-dev-query.sh (never edit documentation.db directly).

INVARIANTS-NOT-CHECKED:
  - schema/query consistency → /dev-schema-validate; whether the target is worth doing — this skill
    queues work, it does not adjudicate priority correctness.
```

---

## Step 1 — Read current queue

```bash
bash dev/run-dev-query.sh get_open_targets
```

Use this to avoid duplicates and to choose a sensible priority slot.

## Step 2 — Determine action

| Action | When |
|---|---|
| **Add** | New target identified |
| **Reprioritize** | Priority shift based on new info |
| **Mark in_progress** | Work has started |
| **Complete** | Target shipped |
| **Supersede** | Replaced by another target |

## Step 3 — Add

Allocate a code first (code-before-text), then insert. Codes are `NT###` (no hyphen) per v3.0.

```bash
bash dev/run-dev-query.sh next_target_code          # e.g. NT001

bash dev/run-dev-query.sh insert_target \
  DATE=$(date +%F) \
  CODE='NT001' \
  SCOPE='[DEV]' \
  TITLE='Migrate dev memory to SQLite' \
  DESCRIPTION='Replace dev/*.md with documentation.db, rewrite skills.' \
  AFFECTED='dev/, .claude/skills/dev-*' \
  PRIORITY=2 \
  MEMORY_REF=''
```

`PRIORITY` is an integer (lower = higher). `CODE` is optional but recommended (the scope lives in `SCOPE`, not in
the code — `NT001`, not `NT-DEV-001`). The insert echoes the new row's `id` (first pipe field) — capture it for Step 5.

## Step 4 — Update

```bash
# Status transition
bash dev/run-dev-query.sh update_target_status ID=42 STATUS=in_progress
# Repriorize
bash dev/run-dev-query.sh update_target_priority ID=42 PRIORITY=1
# Complete
bash dev/run-dev-query.sh complete_target ID=42 DATE=$(date +%F)
# Supersede (replaced by another target — no longer relevant)
bash dev/run-dev-query.sh supersede_target ID=42
```

## Step 5 — Wire typed edges (replaces SOURCE_REFS)

The old `SOURCE_REFS` freetext column is **gone** in v3.0. Wire the source(s) this target came from as typed
`refs` edges. Capture this target's own id, resolve each source by code, then link (`RELATION=relates`):

```bash
NT_ID=$(bash dev/run-dev-query.sh get_open_targets | head -1 | cut -d'|' -f1)   # or from the insert echo

# target came from bug B007
B_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B007 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_bug SOURCE_TABLE=next_targets SOURCE_ID=$NT_ID POSITION=0 BUG_ID=$B_ID RELATION=relates
```

- From an observation → `link_observation … OBSERVATION_ID=$W_ID RELATION=relates`.
- From a decision → `link_decision … DECISION_ID=$D_ID RELATION=relates`.
- Referenced from a Claude memory file → set `MEMORY_REF=memory_file_X` on insert.
- Never orphan a target — wire at least the source it came from (or state it is net-new).

## Constraints

- Targets reference source IDs — never orphan a target.
- Priority numbers can have gaps; no need to renumber when inserting.
- **Scope tag is mandatory.**
- **Never edit `documentation.db` directly.**

---

*© {{PROJECT_NAME}} Dev | dev-next-target*
