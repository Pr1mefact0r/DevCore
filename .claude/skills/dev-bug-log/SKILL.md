---
name: dev-bug-log
description: Use when a bug is found during development or testing. Records the bug in dev/documentation.db (table `bugs`) with the next available B### code.
---

# /dev-bug-log — Log Bug to Tracker

Inserts a row into the `bugs` table of `dev/documentation.db` via `dev/run-dev-query.sh`.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (bugs) + related node codes being wired (get_*_by_code)
WRITES:      dev/documentation.db (bugs, refs)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert mints a B###; on retry check get_bug_by_code before re-inserting.

PRE-CONDITIONS:
  - the bug is logged BEFORE any fix is attempted (never fix silently).
  - allocate next_bug_code as the first write call (code-before-text, PR005-class); capture + echo.
  - scope tag chosen ([vX.Y] / [DEV] / [DEV+vX.Y]) — mandatory.

POST-CONDITIONS:
  - insert confirmed: the printed row echoes `code | scope | title | severity | status` (status `open`).
  - typed edges wired where a related node exists (bug --relates--> W###/D###); a genuinely
    standalone defect may be edge-less — state it.
  - if the fix is non-trivial, a /dev-next-target follow-up is created (wires its own edge).

INVARIANTS-RESPECTED:
  - code-before-text (PR005-class); scope tag mandatory; fixed bugs are immutable (re-open = new B###).
  - no inline SQL — all writes via run-dev-query.sh (never edit documentation.db directly).

INVARIANTS-NOT-CHECKED:
  - schema/query consistency → /dev-schema-validate; whether the bug is a true defect vs. a watched
    anomaly (caller's classification call — observations go to /dev-observation).
```

---

## Step 1 — Get next bug code

```bash
bash dev/run-dev-query.sh next_bug_code
```

Output is e.g. `B013`. Use this as `$CODE` in step 2.

## Step 2 — Classify

| Field | Value |
|---|---|
| `CODE` | next B### from step 1 |
| `SCOPE` | `[vX.Y]` for framework, `[DEV]` for dev-only, `[DEV+vX.Y]` for both |
| `TITLE` | one-line bug title (no period) |
| `DESCRIPTION` | what happened, what was expected |
| `SEVERITY` | `critical` / `behavioral` / `edge_case` / `minor` |
| `FOUND_IN` | file, skill, or test context where noticed |
| `FIX` | initial analysis + possible fixes (status starts `open`) |
| `MEMORY_REF` | optional `memory_file_X` if referenced from a Claude memory file |

### Severity Guide

| Severity | Meaning |
|---|---|
| `critical` | data loss, corruption, wrong DB writes |
| `behavioral` | works but produces wrong/unexpected results |
| `edge_case` | only triggers under specific conditions |
| `minor` | cosmetic, low impact, workaround exists |

## Step 3 — Insert

```bash
bash dev/run-dev-query.sh insert_bug \
  DATE=$(date +%F) \
  CODE=B013 \
  SCOPE='[DEV]' \
  TITLE='short title' \
  DESCRIPTION='full description' \
  SEVERITY=behavioral \
  FOUND_IN='dev/run-dev-query.sh' \
  FIX='Open. Possible fix: …' \
  MEMORY_REF=''
```

Confirm the row exists by inspecting the printed `code | scope | title | severity | status` line.

## Step 4 — Wire typed edges

Capture this bug's own id (pipe-separated output; `cut -d'|' -f1`), then link related nodes via the `refs` graph:

```bash
B_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B013 | head -1 | cut -d'|' -f1)

# bug relates to an existing observation it confirms
W_ID=$(bash dev/run-dev-query.sh get_observation_by_code CODE=W007 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_observation SOURCE_TABLE=bugs SOURCE_ID=$B_ID POSITION=0 OBSERVATION_ID=$W_ID RELATION=relates
```

- Relate to a decision it stems from → `link_decision … DECISION_ID=$D_ID RELATION=relates`.
- If a fix is non-trivial, also create a `/dev-next-target` (which wires its own `next_target --relates--> B###` edge).
- If referenced from a Claude memory file, set `MEMORY_REF=memory_file_X` on insert.
- A genuinely standalone defect may be edge-less — state it.

## Constraints

- **Never fix a bug silently** — always log first, then fix.
- **Never modify fixed bugs.** To re-open, file a new B###.
- **Scope tag is mandatory.**
- **Never edit `documentation.db` directly.** All writes go through `run-dev-query.sh`.

---

*© {{PROJECT_NAME}} Dev | dev-bug-log*
