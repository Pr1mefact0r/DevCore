---
name: dev-decision-log
description: Use when a design decision is made during development. Records the decision in dev/documentation.db (table `decisions`) with the next available D### code.
---

# /dev-decision-log — Document Design Decision

Inserts a row into the `decisions` table via `dev/run-dev-query.sh`.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (decisions) + related node codes being wired (get_*_by_code)
WRITES:      dev/documentation.db (decisions, refs)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert mints a D###; on retry check get_decision_by_code before re-inserting.

PRE-CONDITIONS:
  - this is an operator JUDGEMENT (a design choice), not a query/data-arbitered fact (else Q###,
    /dev-adjudicate) nor a how-we-solved-it precedent (else RS###, /dev-resolution).
  - allocate next_decision_code as the first write call (code-before-text, PR005-class); capture + echo.
  - scope tag and a non-empty RATIONALE are mandatory ("because it's better" is not a rationale).

POST-CONDITIONS:
  - insert confirmed; DATE is ISO 8601 (YYYY-MM-DD).
  - typed edges wired to the node(s) it resolves/reopens (decision --relates/reopens--> B###/W###/D###);
    same-type supersession uses the supersede_decision column, NOT a supersedes refs edge.
  - a fundamental architectural rule is mirrored into root CLAUDE.md → ## Architecture Decisions.

INVARIANTS-RESPECTED:
  - code-before-text (PR005-class); scope tag mandatory; decisions are append-only (supersede, never
    delete/modify); same-type supersession is a column not an edge.
  - no inline SQL — all writes via run-dev-query.sh (never edit documentation.db directly).

INVARIANTS-NOT-CHECKED:
  - schema/query consistency → /dev-schema-validate; whether the decision is sound — this skill
    records the choice + rationale, not its correctness.
```

---

## Step 1 — Get next decision code

```bash
bash dev/run-dev-query.sh next_decision_code
```

Output is e.g. `D013`. Use as `$CODE` in step 2.

## Step 2 — Fields

| Field | Required | Notes |
|---|---|---|
| `CODE` | yes | next D### from step 1 |
| `SCOPE` | yes | `[vX.Y]` / `[DEV]` / `[DEV+vX.Y]` |
| `TITLE` | yes | concise, imperative form |
| `CONTEXT` | yes | what problem or situation led here |
| `DECISION` | yes | what was decided — be specific |
| `RATIONALE` | yes | why this approach over alternatives |
| `TRADEOFF` | no | what we are giving up |
| `ALTERNATIVES` | no | what was rejected and why |
| `RULE` | no | new invariant created by this decision |
| `CONVENTION` | no | new naming/formatting pattern |
| `MEMORY_REF` | no | `memory_file_X` if referenced from a Claude memory file |

## Step 3 — Insert

```bash
bash dev/run-dev-query.sh insert_decision \
  DATE=$(date +%F) \
  CODE=D013 \
  SCOPE='[DEV]' \
  TITLE='switch to documentation.db' \
  CONTEXT='Markdown logs grew unbounded; agent had to read full files.' \
  DECISION='All dev tracking moves to dev/documentation.db.' \
  RATIONALE='Targeted SELECT replaces full-file reads. Token savings + structured queries.' \
  TRADEOFF='' \
  ALTERNATIVES='' \
  RULE='' \
  CONVENTION='' \
  MEMORY_REF=''
```

## Step 4 — Wire typed edges

Capture this decision's own id (pipe output; `cut -d'|' -f1`), then link the nodes it relates to:

```bash
D_ID=$(bash dev/run-dev-query.sh get_decision_by_code CODE=D013 | head -1 | cut -d'|' -f1)

# decision relates to the bug/observation it resolves
B_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B007 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_bug SOURCE_TABLE=decisions SOURCE_ID=$D_ID POSITION=0 BUG_ID=$B_ID RELATION=relates
```

- Resolves/relates to an observation → `link_observation … OBSERVATION_ID=$W_ID RELATION=relates`.
- Reopens a prior decision's question (then later supersede/reaffirm it) → `link_decision … DECISION_ID=$OLD_ID RELATION=reopens`.
- Same-type supersession (a new D### replaces an old one) uses the `supersede_decision` query (column/prose), **not** a `supersedes` refs edge.
- If the decision creates a fundamental architectural rule, also note it in root `CLAUDE.md` → `## Architecture Decisions` (Phase-8 mirror).
- If referenced from a Claude memory file, set `MEMORY_REF=memory_file_X` on insert.

## Constraints

- **Every decision needs a rationale.** "Because it's better" is not a rationale.
- **Never delete or modify past decisions.** Use the `supersede_decision` query to mark an old D### as superseded by a new one.
- **Date is always ISO 8601 (YYYY-MM-DD).**
- **Scope tag is mandatory.**
- **Never edit `documentation.db` directly.**

---

*© {{PROJECT_NAME}} Dev | dev-decision-log*
