---
name: dev-resolution
description: Use when a PROBLEM was solved/handled in a way worth reusing ("how we did X") — a precedent, not a one-off. Crystallizes it as a resolution RS### (problem→resolution→outcome→reuse) with a canonical recognition_key and typed edges, so the next similar problem recalls "we solved this before, here's how".
---

# /dev-resolution — Crystallize a PRECEDENT (RS###)

Records a reusable "how we solved problem P" precedent in the `resolutions` table of
`dev/documentation.db` via `dev/run-dev-query.sh`. Sibling of `/dev-adjudicate` (Q### = a settled
*fact*) — use this when the value is the *approach*, not a truth-claim. Durable architecture *policy*
still goes to `/dev-decision-log` (D###).

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       dev/documentation.db (recognition_keys, resolutions for reuse-before-mint + allocation;
             source/target node codes being wired via get_*_by_code) — via dev/run-dev-query.sh
WRITES:      dev/documentation.db (recognition_keys if new key, resolutions, refs) — via dev/run-dev-query.sh
CALLS:       none (atomic — invokes no other /dev-skill)
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: no — each insert mints a new RS###. On retry, check get_resolution_by_code first
             before re-inserting; the allocated code is the dedup anchor.
PRE-CONDITIONS:
  - recall-first: search existing precedents (search_resolutions_recognition /
    resolutions_by_recognition_key). If a still-valid RS### already covers it, cite it and
    mark_resolution_revalidated instead of duplicating; if this replaces an older precedent,
    supersede it (see Step 5).
  - kind check: it must be a reusable APPROACH/precedent — else a fact → /dev-adjudicate,
    a durable policy → /dev-decision-log.
  - reuse-before-mint the recognition_key: search_keys first; register_key only if new (UPPER_SNAKE).
  - allocator-first (code-before-text, PR005-class): next_resolution_code is the first write call;
    capture + echo the RS### before composing any prose.
POST-CONDITIONS:
  - insert confirmed (status='settled'); problem / resolution / reuse all populated — reuse is what
    makes it a precedent, never leave it empty.
  - typed edges wired: the origin (<source> --raised--> RS###, or I### --produced--> RS###) and any
    target it resolves/informs. ≥1 edge — an RS### is a precedent for something, not a free-floating note.
INVARIANTS-RESPECTED:
  - code-before-text + reuse-before-mint (PR005-class); recall-first; one directed edge per
    relationship (PR022-class); all writes via dev/run-dev-query.sh (no inline SQL, no direct DB edit).
INVARIANTS-NOT-CHECKED:
  - scope-correctness of the wired targets; whether the precedent is genuinely novel vs. a near-dup
    (recall-first is advisory, not enforced by this skill).
```

---

## Step 1 — Recall first

Search before minting — a precedent already on file should be revalidated, not duplicated.

```bash
bash dev/run-dev-query.sh search_resolutions_recognition PATTERN='retry'
# or, if you already know the canonical key:
bash dev/run-dev-query.sh resolutions_by_recognition_key KEY=IDEMPOTENT_RETRY
```

If a still-valid RS### already covers this case → cite it and stop, or revalidate:

```bash
bash dev/run-dev-query.sh mark_resolution_revalidated CODE=RS007 DATE=$(date +%F)
```

Mint a new RS### only for a genuinely new precedent (or one that supersedes an older RS### — Step 5).

## Step 2 — Reuse-before-mint the recognition_key

```bash
bash dev/run-dev-query.sh search_keys PATTERN=IDEMPOTENT_RETRY
# reuse a hit; only register if none fits (UPPER_SNAKE, CHECK-enforced):
bash dev/run-dev-query.sh register_key \
  KEY=IDEMPOTENT_RETRY TEXT='dedupe retries with an idempotency token' \
  FIRST_SEEN=$(date +%F) CREATED_BY=dev-resolution
```

## Step 3 — Allocate the code FIRST (code-before-text)

```bash
bash dev/run-dev-query.sh next_resolution_code
```

Output is e.g. `RS012`. Capture and echo it as `$CODE` before writing any prose.

## Step 4 — Insert the precedent

`reuse` is the point of the row — concrete "when/how to apply this again". `SOURCE` accepts only
`dialog` / `sentinel` / `review` / `investigation` / `other`; pass `SOURCE=investigation` when it
came out of an I###, omit it to leave NULL.

```bash
bash dev/run-dev-query.sh insert_resolution \
  DATE=$(date +%F) CODE=RS012 SCOPE='[vX.Y]' \
  TITLE='how we made retried writes safe' \
  PROBLEM='the situation/problem faced — be concrete' \
  RESOLUTION='how it was solved/handled — the actual move' \
  OUTCOME='did it work — the observed result' \
  REUSE='when/how to apply this again (the precedent value — never empty)' \
  SOURCE=review \
  RECOGNITION_KEY=IDEMPOTENT_RETRY RECOGNITION_TEXT='this case in one line' \
  AS_OF=$(date +%F) VALIDITY='conditions under which the approach still applies'
```

The insert echoes `id | code | status` (expect `status=settled`). Do NOT scrape this for the numeric
id used in edges — capture it explicitly in Step 5.

## Step 5 — Wire typed edges

Capture the new RS###'s own id by code (first pipe-field), never from the insert output:

```bash
RS_ID=$(bash dev/run-dev-query.sh get_resolution_by_code CODE=RS012 | head -1 | cut -d'|' -f1)
```

Resolve each TARGET id the same way (`get_<kind>_by_code` → id is the first pipe-field), then wire one
directed edge per relationship. The link verb names the TARGET kind; `SOURCE_TABLE`/`SOURCE_ID` name
the source.

**Origin → RS### (where the precedent came from):**

```bash
# a bug raised this precedent:  bugs --raised--> RS###
BUG_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B040 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_resolution \
  SOURCE_TABLE=bugs SOURCE_ID=$BUG_ID POSITION=0 RESOLUTION_ID=$RS_ID RELATION=raised

# an investigation produced this precedent:  investigations --produced--> RS###  (SOURCE=investigation)
INV_ID=$(bash dev/run-dev-query.sh get_investigation_by_code CODE=I007 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_resolution \
  SOURCE_TABLE=investigations SOURCE_ID=$INV_ID POSITION=0 RESOLUTION_ID=$RS_ID RELATION=produced
```

**RS### → target (what the precedent resolves / informs).** The verb names the TARGET kind; source is
`resolutions`:

```bash
# RS### --resolves--> a bug
BUG_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B040 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_bug \
  SOURCE_TABLE=resolutions SOURCE_ID=$RS_ID POSITION=0 BUG_ID=$BUG_ID RELATION=resolves

# RS### --informs--> a decision / a next_target
DEC_ID=$(bash dev/run-dev-query.sh get_decision_by_code CODE=D012 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh link_decision \
  SOURCE_TABLE=resolutions SOURCE_ID=$RS_ID POSITION=0 DECISION_ID=$DEC_ID RELATION=informs
```

**Superseding an older precedent — COLUMN, not an edge.** RS→RS is same-type; a `supersedes` refs-edge
between two resolutions is CHECK-rejected. Set the column instead:

```bash
bash dev/run-dev-query.sh supersede_resolution CODE=RS007 NEW_ID=$RS_ID DATE=$(date +%F)
```

Confirm with `get_resolution_by_code CODE=RS012` (row present, `status=settled`) and
`get_refs_to_node TARGET_TABLE=resolutions TARGET_COL=resolution_id CODE=RS012` (edge rows present).

## Constraints

- **Precedent, not fact/policy.** Fact → `/dev-adjudicate` (Q###); durable architecture choice →
  `/dev-decision-log` (D###).
- **`reuse` is mandatory** — a precedent with no reuse guidance is just a note; do not insert one empty.
- **Code before text** — allocate `next_resolution_code` before composing prose.
- **Recall before mint** — search existing precedents; revalidate or supersede rather than duplicate.
- **Same-type supersession is a column** (`supersede_resolution`), never a `supersedes` edge.
- **Never edit `documentation.db` directly.** All writes go through `dev/run-dev-query.sh`; never write
  inline SQL outside `dev/dev-queries/*.sql`.

---

*© {{PROJECT_NAME}} Dev | dev-resolution*
