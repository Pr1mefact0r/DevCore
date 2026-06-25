---
name: dev-observation
description: Use when something is noticed during testing or development that is not yet a confirmed bug or decision. Records the observation in dev/documentation.db (table `observations`) with the next available W### code.
---

# /dev-observation — Log Observation to Watch List

Inserts a row into the `observations` table via `dev/run-dev-query.sh`.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (observations) + related node codes being wired (get_*_by_code)
WRITES:      dev/documentation.db (observations, refs)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no for insert (mints a W###); status transitions are idempotent (re-marking the same
             status is a no-op). On retry of the insert, check next_observation_code before re-inserting.

PRE-CONDITIONS:
  - this is a "thing to watch", NOT yet a confirmed bug (else /dev-bug-log) or decision
    (else /dev-decision-log).
  - allocate next_observation_code as the first write call (code-before-text, PR005-class).
  - scope tag is mandatory; WATCH_FOR names the concrete signal that would confirm/deny it.

POST-CONDITIONS:
  - insert confirmed; status starts `watching` automatically.
  - promotion handled via the right path: confirmed → /dev-bug-log (wires bug --relates--> W###);
    leads-to-decision → /dev-decision-log; monitoring/resolved/false-alarm → status transition only.
  - the observation is never deleted — every outcome is a status transition.

INVARIANTS-RESPECTED:
  - code-before-text (PR005-class); scope tag mandatory; observations transition, never delete.
  - status ∈ {watching, fix_deployed_monitoring, resolved, false_alarm}.
  - no inline SQL — all writes via run-dev-query.sh (never edit documentation.db directly).

INVARIANTS-NOT-CHECKED:
  - schema/query consistency → /dev-schema-validate; whether the watched signal is a real defect —
    that is settled later by promotion to a bug or a query verdict (Q###).
```

---

## Step 1 — Get next observation code

```bash
bash dev/run-dev-query.sh next_observation_code
```

Output e.g. `W007`. Use as `$CODE`.

## Step 2 — Fields

| Field | Required | Notes |
|---|---|---|
| `CODE` | yes | next W### |
| `SCOPE` | yes | `[vX.Y]` / `[DEV]` / `[DEV+vX.Y]` |
| `TITLE` | yes | concise |
| `DESCRIPTION` | yes | what was observed |
| `FOUND_IN` | yes | file, session, or test context |
| `WATCH_FOR` | yes | specific signals that would confirm/deny |

Status starts as `watching` automatically.

## Step 3 — Insert

```bash
bash dev/run-dev-query.sh insert_observation \
  DATE=$(date +%F) \
  CODE=W007 \
  SCOPE='[v0.1]' \
  TITLE='cagg refresh lag' \
  DESCRIPTION='Continuous aggregate appears to lag behind raw rows by ~5 min.' \
  FOUND_IN='v_0.1/dev/schema.sql' \
  WATCH_FOR='Recheck after next refresh policy adjustment.'
```

## Step 4 — Promotion Path

| Outcome | Action |
|---|---|
| Confirmed as bug | `/dev-bug-log` — the bug wires a typed `bug --relates--> W###` edge (no freetext) |
| Leads to decision | `/dev-decision-log` — the decision wires a typed `decision --relates--> W###` edge |
| Fix deployed, monitoring | `bash dev/run-dev-query.sh update_observation_status CODE=W007 STATUS=fix_deployed_monitoring` |
| Resolved | `bash dev/run-dev-query.sh resolve_observation CODE=W007 RESOLUTION='...' DATE=$(date +%F)` |
| False alarm | `bash dev/run-dev-query.sh dismiss_observation CODE=W007 RESOLUTION='not reproducible' DATE=$(date +%F)` |

## Constraints

- Observations are NOT bugs — they are "things to watch."
- Never delete observations — transition status instead.
- Status values: `watching`, `fix_deployed_monitoring`, `resolved`, `false_alarm`.
- **Scope tag is mandatory.**
- **Never edit `documentation.db` directly.**

---

*© {{PROJECT_NAME}} Dev | dev-observation*
