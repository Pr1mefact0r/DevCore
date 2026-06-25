---
name: dev-adjudicate
description: Use when a query or piece of data has CONCLUSIVELY settled a factual or correctness question ("was X true?"). Crystallizes the finding as an adjudication Q### in dev/documentation.db with the actual evidence data, a canonical recognition_key, and typed edges, so it is recalled and revalidated next time instead of re-investigated.
---

# /dev-adjudicate — Crystallize a settled FACT (Q###)

Records a query/data-arbitered settled fact in the `adjudications` table of `dev/documentation.db`
via `dev/run-dev-query.sh`. Use only when a **query or data was the arbiter**. If the operator made a
judgement → that is a design decision (`/dev-decision-log`, D###). If it is a "how we solved a problem"
precedent → `/dev-resolution` (RS###).

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (recognition_keys, adjudications, and the source/target node codes
             being wired via get_*_by_code) — via dev/run-dev-query.sh
WRITES:      dev/documentation.db (recognition_keys — register a new key if needed; adjudications;
             refs — typed edges) — via dev/run-dev-query.sh
CALLS:       none (atomic — invokes no /dev-* skill). Recall-first is PR discipline stated in
             PRE-CONDITIONS, not an invocation by this skill.
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert mints a new Q###. On retry, check get_adjudication_by_code for the
             captured code before re-inserting (a second insert would mint a duplicate).

PRE-CONDITIONS:
  - recall-first: search for the signature (search_adjudications_recognition / adjudications_by_recognition_key).
    If a still-valid Q### already settles it, mark_adjudication_revalidated and cite it — do NOT mint a
    duplicate. Only adjudicate a genuinely NEW fact, or a finding that SUPERSEDES an existing Q###.
  - arbiter check: the question was settled by a QUERY or by data, not operator judgement (else D###),
    and is a fact, not a how-we-solved-it precedent (else RS###).
  - reuse-before-mint the recognition_key: run search_keys FIRST; reuse an existing canonical
    UPPER_SNAKE key, or register a new one. The recognition_key FK rejects an unregistered key.
  - allocate next_adjudication_code as the first write call (code-before-text, PR005-class); capture + echo.

POST-CONDITIONS:
  - insert confirmed: the SELECT after insert_adjudication echoes `id | code | settled`.
  - evidence_data holds the ACTUAL data that settled it (numbers / refetch JSON), not just prose.
  - typed edges wired: at least the question-source edge (<origin> --raised--> Q###, or
    I### --produced--> Q###), plus the answer-target edge where applicable
    (Q### --validates/informs/refutes--> <node>). Source-of-question and target-of-answer both traceable.

INVARIANTS-RESPECTED:
  - code-before-text + reuse-before-mint (PR005-class), query-is-the-arbiter, evidence-backed
    (no confabulation), one directed edge per relationship, same-type supersession is a column not an edge.
  - All writes via run-dev-query.sh (never edit documentation.db directly).

INVARIANTS-NOT-CHECKED:
  - schema/query consistency (that is /dev-schema-validate); whether the upstream investigation was
    methodologically sound (out of scope — this skill records the verdict, not the method).
```

---

## Step 1 — Recall first

Search for the signature before minting anything:

```bash
bash dev/run-dev-query.sh search_adjudications_recognition PATTERN='<signature>'
# or, if you already know the key:
bash dev/run-dev-query.sh adjudications_by_recognition_key KEY=THE_CANONICAL_KEY
```

If a still-valid Q### already settles this fact → `mark_adjudication_revalidated`, cite it, STOP:

```bash
bash dev/run-dev-query.sh mark_adjudication_revalidated CODE=Q### DATE=$(date +%F)
```

Only proceed if the fact is genuinely new, or supersedes an existing Q### (see Step 6).

## Step 2 — Reuse-before-mint the recognition_key

```bash
bash dev/run-dev-query.sh search_keys PATTERN='<signature>'
```

- Match → reuse that `KEY`.
- None fits → register a canonical key (UPPER_SNAKE, the CHECK enforces the shape):

```bash
bash dev/run-dev-query.sh register_key KEY=NEW_CANONICAL_KEY \
  TEXT='one-line description of the topic/failure class' \
  DEFINITION='when this key applies' \
  FIRST_SEEN=$(date +%F) CREATED_BY=query
```

The recognition_key is an FK on `adjudications` — an unregistered key is rejected.

## Step 3 — Allocate the code (first write call)

```bash
bash dev/run-dev-query.sh next_adjudication_code | grep -oE 'Q[0-9]{3}'   # -> Q###; capture + echo
```

> Note: on a brand-new DB the very first wrapper call may emit a one-time `wal` line (the
> `PRAGMA journal_mode = WAL` echo). The committed dev DB is already warm, so this never happens in
> practice; `grep -oE 'Q[0-9]{3}'` is robust either way. Do not blindly `head -1` the allocator on a
> cold DB.

## Step 4 — Insert the adjudication

```bash
bash dev/run-dev-query.sh insert_adjudication \
  DATE=$(date +%F) CODE=Q### SCOPE='[vX.Y]' \
  TITLE='the question, one line' \
  QUESTION='the concern as raised' \
  VERDICT='the conclusive answer' \
  EVIDENCE='the decisive query / method, in prose' \
  EVIDENCE_DATA='{"...":"the actual numbers/proof"}' \
  RECOGNITION_KEY=THE_CANONICAL_KEY RECOGNITION_TEXT='this case in one line' \
  AS_OF=$(date +%F) VALIDITY='the assumptions under which the verdict holds' \
  REVALIDATION_QUERY='' REVALIDATION_PARAMS=''
```

Confirm the echoed row: `id | code | settled`.

- **`EVIDENCE_DATA` carries the data, `EVIDENCE` carries the prose.** The wrapper substitutes
  longest-key-first, so passing `EVIDENCE_DATA` and `EVIDENCE` together is safe — `$EVIDENCE` no longer
  clobbers inside `$EVIDENCE_DATA`. Put the actual settling data (numbers, JSON, refetch) in
  `EVIDENCE_DATA` so revalidation is mechanical, not a re-read of prose.
- **Structured revalidation handle.** When the verdict has a *single re-runnable decisive query*, set
  `REVALIDATION_QUERY` (a `dev-queries/*.sql` id) + `REVALIDATION_PARAMS` (JSON) so recall can
  revalidate by re-running it and comparing to the verdict. Leave both `''` for multi-step verdicts
  (revalidation falls back to the `evidence` prose).

## Step 5 — Capture the Q### id, then wire the typed edges

Capture the just-minted Q###'s own id via `get_adjudication_by_code` (id is the first pipe-field) —
NOT by parsing the insert output:

```bash
Q_ID=$(bash dev/run-dev-query.sh get_adjudication_by_code CODE=Q### | head -1 | cut -d'|' -f1)
```

Resolve each related node's id by its `get_<kind>_by_code` (id is the first pipe-field too), then wire
the edge. The link verb names the TARGET kind; `SOURCE_TABLE`/`SOURCE_ID` name the source:

```bash
# question arose FROM a bug:            bug --raised--> Q###
BUG_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B### | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_adjudication SOURCE_TABLE=bugs SOURCE_ID=$BUG_ID POSITION=0 ADJUDICATION_ID=$Q_ID RELATION=raised

# produced BY an investigation:         I### --produced--> Q###
I_ID=$(bash dev/run-dev-query.sh get_investigation_by_code CODE=I### | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_adjudication SOURCE_TABLE=investigations SOURCE_ID=$I_ID POSITION=0 ADJUDICATION_ID=$Q_ID RELATION=produced

# the answer validates / informs / refutes a node:   Q### --validates--> bug, --informs--> next_target
bash dev/run-dev-query.sh link_bug         SOURCE_TABLE=adjudications SOURCE_ID=$Q_ID POSITION=0 BUG_ID=$BUG_ID RELATION=validates
NT_ID=$(bash dev/run-dev-query.sh get_target_by_code CODE=NT001 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_next_target SOURCE_TABLE=adjudications SOURCE_ID=$Q_ID POSITION=1 NEXT_TARGET_ID=$NT_ID RELATION=informs
```

Relations: `raised` (origin→Q), `produced` (I→Q), `validates`/`informs`/`refutes` (Q→target). Increment
`POSITION` (0,1,2…) for multiple edges sharing the same source. The link verb (`link_bug`,
`link_next_target`, `link_observation`, `link_decision`, `link_resolution`, …) always names the TARGET.

## Step 6 — Supersession (only if this Q### replaces an older one)

A Q### that supersedes an *older Q###* is recorded via the `superseded_by` **column**, NOT a refs edge —
a same-type `supersedes` edge is CHECK-rejected:

```bash
bash dev/run-dev-query.sh supersede_adjudication CODE=Q_OLD NEW_ID=$Q_ID DATE=$(date +%F)
```

The `supersedes` refs-relation is for CROSS-type only (e.g. a Q### superseding a W### observation, where
no column exists).

## Constraints

- **Only query/data-arbitered facts.** Operator judgement → `/dev-decision-log`; precedent → `/dev-resolution`.
- **Evidence is data, not just prose** — `EVIDENCE_DATA` carries the proof so revalidation is mechanical.
- **No orphan findings** — always wire at least the question-source edge; traceability is the point.
- **Same-type supersession is a column** (`supersede_adjudication`), never a refs edge.
- **Capture ids via `get_*_by_code | head -1 | cut -d'|' -f1`** — never parse insert output for the id.
- **Never edit `documentation.db` directly.** All writes go through `run-dev-query.sh`.

---

*© {{PROJECT_NAME}} Dev | dev-adjudicate*
