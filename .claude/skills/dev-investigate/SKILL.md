---
name: dev-investigate
description: Use to open or conclude an investigation (I###) — the PROCESS between a question and its settled answer (method, queries tried, dead-ends, findings). Makes the epistemic chain reconstructable - source --raised--> I### --produced--> Q###/RS###. Optional but recommended for non-trivial investigations.
---

# /dev-investigate — Record the investigation PROCESS (I###)

Captures HOW a concern was investigated in the `investigations` table of `dev/documentation.db` via
`dev/run-dev-query.sh`. The bridge node between a question and its crystallised answer, so the full chain
`<origin> --raised--> I### --produced--> Q###/RS###` stays traceable. Optional for trivial checks;
valuable when the path (queries run, dead-ends ruled out) is itself worth keeping.

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (investigations; source/answer node codes via get_*_by_code) — via dev/run-dev-query.sh
WRITES:      dev/documentation.db (investigations; refs typed edges) — via dev/run-dev-query.sh
CALLS:       none (atomic — invokes no dev-* skill). The OUTCOME is crystallised in a SEPARATE follow-on /dev-adjudicate or /dev-resolution, not invoked here.
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no for OPEN (mints a fresh I### each run); conclude/abandon/supersede are idempotent updates by CODE (safe to retry).

PRE-CONDITIONS:
  - OPEN: allocate next_investigation_code FIRST (code-before-text, PR005-class); state the QUESTION being
    investigated; reuse-before-mint a recognition_key if the class is already known.
  - CONCLUDE: the investigation reached a verdict → record findings here, then crystallise the answer
    (/dev-adjudicate for a fact-Q###, /dev-resolution for a precedent-RS###) and wire I### --produced--> that node.

POST-CONDITIONS:
  - on OPEN: I### row exists with status='open', and its origin edge is wired (<origin> --raised--> I###).
  - on CONCLUDE: status='concluded' + findings populated; the produced edge to the answer node is wired.
    A concluded investigation with NO produced answer is a loose end — flag it explicitly.

INVARIANTS-RESPECTED:
  - code-before-text (PR005-class): mint code via allocator before writing the row.
  - one directed edge per relationship; the investigation IS the query-arbitration (no inline SQL).
  - all writes via dev/run-dev-query.sh with named query-ids; documentation.db never edited directly.

INVARIANTS-NOT-CHECKED:
  - schema/query consistency (that is /dev-schema-validate); whether the produced Q###/RS### is itself correct.
```

---

## Step 1 — Decide the lifecycle path

| Situation | Path | Steps |
|---|---|---|
| Starting to investigate a concern | **OPEN** | 2 → 3 → 4 |
| Investigation reached a verdict | **CONCLUDE** | 5 |
| Investigation dead-ended, no usable answer | **ABANDON** | 6 |
| A newer investigation replaces this one | **SUPERSEDE** | 7 |

OPEN mints a new I###. CONCLUDE / ABANDON / SUPERSEDE update an existing I### by `CODE`.

---

## Step 2 — Allocate the code FIRST (OPEN)

```bash
bash dev/run-dev-query.sh next_investigation_code
```

Output is e.g. `I007`. Capture and echo it — this is `$CODE`. Allocate before writing any text (code-before-text).

## Step 3 — Insert the investigation (OPEN)

| Field | Value |
|---|---|
| `CODE` | next I### from step 2 |
| `SCOPE` | `[vX.Y]` for framework, `[DEV]` for dev-only, `[DEV+vX.Y]` for both (scope must NOT contain a literal `v_N` — use the placeholder form) |
| `TITLE` | one-line label of what is being investigated (no period) |
| `QUESTION` | the concern actually being investigated |
| `METHOD` | leave empty on open; fill on conclude (queries run / dead-ends) |
| `FINDINGS` | leave empty on open; fill on conclude (the outcome trail) |
| `RECOGNITION_KEY` | optional — reuse an existing key if the class is known, else empty |
| `RECOGNITION_TEXT` | optional human label for the key |
| `AS_OF` | optional point-in-time the question is asked-as-of (nullable here) |

```bash
bash dev/run-dev-query.sh insert_investigation \
  DATE=$(date +%F) CODE=I007 SCOPE='[vX.Y]' \
  TITLE='what is being investigated' \
  QUESTION='the concern being investigated' \
  METHOD='' FINDINGS='' \
  RECOGNITION_KEY='' RECOGNITION_TEXT='' AS_OF=$(date +%F)
```

`insert_investigation` echoes `id | code | status`. Status should read `open`.

## Step 4 — Wire the origin edge: `<origin> --raised--> I###` (OPEN)

Capture the new I###'s own `id` via `get_investigation_by_code` (id is the first pipe-field — do NOT parse
the insert output for it):

```bash
I_ID=$(bash dev/run-dev-query.sh get_investigation_by_code CODE=I007 | head -1 | cut -d'|' -f1)
```

Resolve the origin node's id by its own `get_<x>_by_code`, then wire `raised` from that origin to the
investigation. `SOURCE_TABLE`/`SOURCE_ID` name the origin; `link_investigation` names the target kind:

```bash
# e.g. a bug B012 raised this investigation
BUG_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B012 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_investigation \
  SOURCE_TABLE=bugs SOURCE_ID=$BUG_ID POSITION=0 \
  INVESTIGATION_ID=$I_ID RELATION=raised
```

Other valid origins: `decisions` (get_decision_by_code), `observations` (get_observation_by_code). Always
wire ≥1 `raised` edge — an investigation with no origin is unmoored.

## Step 5 — Conclude the investigation (CONCLUDE)

```bash
bash dev/run-dev-query.sh conclude_investigation \
  CODE=I007 \
  FINDINGS='what it turned up — the outcome trail' \
  METHOD='queries run / dead-ends ruled out' \
  DATE=$(date +%F)
```

Then crystallise the outcome as a SEPARATE follow-on and wire `I### --produced--> answer`:
- a settled fact → `/dev-adjudicate` (mints Q###), then
  `link_adjudication SOURCE_TABLE=investigations SOURCE_ID=$I_ID ADJUDICATION_ID=$Q_ID RELATION=produced`
- a reusable precedent → `/dev-resolution` (mints RS###), then
  `link_resolution SOURCE_TABLE=investigations SOURCE_ID=$I_ID RESOLUTION_ID=$RS_ID RELATION=produced`

A concluded investigation with no `produced` edge is a **loose end** — flag it so the answer gets crystallised.

## Step 6 — Abandon a dead-ended investigation (ABANDON)

```bash
bash dev/run-dev-query.sh abandon_investigation \
  CODE=I007 \
  FINDINGS='why it dead-ended / what was ruled out' \
  DATE=$(date +%F)
```

Abandoned investigations produce no answer node — that is expected, not a loose end.

## Step 7 — Supersede with a newer investigation (SUPERSEDE)

Same-type supersession is a **column, never an edge**. Resolve the replacement I###'s id first:

```bash
NEW_ID=$(bash dev/run-dev-query.sh get_investigation_by_code CODE=I009 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh supersede_investigation CODE=I007 NEW_ID=$NEW_ID DATE=$(date +%F)
```

Never wire a `supersedes` refs-edge between two investigations — the schema CHECK rejects it
(superseded_by must point at a higher id).

## Constraints

- **The process node, not the answer.** The verdict lives in the Q###/RS### the investigation produces;
  keep `findings` here as the trail (method, dead-ends), not the headline.
- **Code before text.** Always allocate `next_investigation_code` before inserting the row.
- **Capture ids via `get_*_by_code`**, first pipe-field — never parse insert output for an id.
- **One directed edge per relationship.** `raised` (origin→I###) on open; `produced` (I###→Q###/RS###) on conclude.
- **Same-type supersession is a column** (`supersede_investigation`), never a refs-edge.
- **Never edit `documentation.db` directly.** All writes go through `dev/run-dev-query.sh`.

---

*© {{PROJECT_NAME}} Dev | dev-investigate*
