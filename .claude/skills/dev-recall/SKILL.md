---
name: dev-recall
description: Use FIRST on any anomaly, plausibility doubt, or recurring question — "didn't we settle this before?". Searches the brain-graph (adjudications Q### / resolutions RS### / investigations I### / ideas IDEA-###) in dev/documentation.db by recognition_key and returns prior settled findings (plus un-decided prior ideas, so a thought is not duplicated) + their typed edges, with a mandatory revalidation gate. Read-only.
---

# /dev-recall — Recall settled findings before re-investigating

The recall reflex. Before spending tokens re-investigating a concern, ask the brain-graph whether
it was already settled — and if so, **cite it AND revalidate it**, never blind-trust a possibly-stale
finding. Pure read (role `observer`); routes to the write-skills only after a verdict.

---

## Contract

```contract
TYPE:        composite
ROLE:        observer (read-only)
READS:       dev/documentation.db (recognition_keys, adjudications, resolutions, investigations,
             ideas, refs) via dev/run-dev-query.sh; plus the decisive/revalidation query named in a
             recalled Q###.revalidation_query for revalidation.
WRITES:      none directly. May CALL a write-skill, or run an adjudication/resolution status
             transition (mark_*_stale / mark_*_revalidated / reopen_*), to flag a stale finding.
CALLS:       /dev-investigate, /dev-adjudicate, /dev-resolution (only after recall concludes
             "no precedent → investigate, then crystallise"); plus the recalled node's own status
             transitions via run-dev-query.sh (mark_adjudication_stale / mark_adjudication_revalidated /
             reopen_adjudication / mark_resolution_stale / mark_resolution_revalidated / reopen_resolution).
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: yes — read-only; safe to run any number of times. (A revalidation status-write, if taken,
             is itself idempotent: re-marking the same status is a no-op.)

PRE-CONDITIONS:
  - this is the FIRST move on an anomaly / plausibility doubt / recurring question (recall-first),
    BEFORE opening an investigation or accepting a narrative.
  - reduce the concern to a recognition signature; search recognition_keys to find the CANONICAL
    key(s) first (reuse-before-mint governs READS too — match the existing key, do not invent one).

POST-CONDITIONS:
  - on a hit: the recalled verdict/resolution is cited WITH its as_of + validity + status, AND
    revalidated against the current state — re-run the decisive query for a Q###, re-confirm with
    the operator for an RS###. NEVER present a recalled finding as current truth without this.
  - if revalidation fails (assumptions no longer hold): mark the node stale/reopened (do not silently
    rely on it); surface to operator.
  - on no hit: state "no precedent" explicitly and proceed to investigate; remind that the eventual
    finding should be crystallised (/dev-adjudicate or /dev-resolution) so the NEXT recall hits.

INVARIANTS-RESPECTED:
  - recall-first (recall is step 1 on any anomaly, before investigation).
  - query-is-the-arbiter — revalidation re-runs the decisive query, never trusts recalled prose.
  - code-before-text (PR005-class) — only relevant to the write-skills this may hand off to; recall
    itself mints nothing.

INVARIANTS-NOT-CHECKED:
  - schema/query consistency — n/a; read-only wrapper calls. Use /dev-schema-validate for that.
```

---

## Step 1 — Find the canonical recognition_key(s)

Reduce the concern to a signature, then search the registry (reuse-before-mint: match an existing
key; never invent a variant):

```bash
bash dev/run-dev-query.sh search_keys PATTERN=absence
# returns canonical key | text rows; pick the matching key(s)
```

**Lexical-recall backstop.** `search_keys` is `LIKE` (lexical) — brittle when a recurrence is
rephrased, and a missed match looks identical to "no precedent" (a *silent* failure). So while the
registry is small, ALSO list the whole closed set and eyeball it before concluding no-hit:

```bash
bash dev/run-dev-query.sh all_keys
```

Treat a `search_keys` miss with skepsis until you have scanned `all_keys`. To inspect one key in
full (text + definition + provenance):

```bash
bash dev/run-dev-query.sh get_key KEY=FALSE_ABSENCE_SCOPE_LIMITED_QUERY
```

If nothing matches even in `all_keys`, the concern is genuinely new (→ Step 4, no precedent).

## Step 2 — Pull the precedent set for each key

```bash
bash dev/run-dev-query.sh adjudications_by_recognition_key  KEY=FALSE_ABSENCE_SCOPE_LIMITED_QUERY
bash dev/run-dev-query.sh resolutions_by_recognition_key    KEY=FALSE_ABSENCE_SCOPE_LIMITED_QUERY
bash dev/run-dev-query.sh investigations_by_recognition_key RECOGNITION_KEY=FALSE_ABSENCE_SCOPE_LIMITED_QUERY
bash dev/run-dev-query.sh get_ideas_by_recognition_key      KEY=FALSE_ABSENCE_SCOPE_LIMITED_QUERY
```

> Note the parameter name differs per query: adjudications / resolutions / ideas take `KEY=`,
> `investigations_by_recognition_key` takes `RECOGNITION_KEY=`. Pass exactly what each expects.

An **ideas (IDEA-###) hit is an un-decided PRIOR THOUGHT**, not a settled precedent — cite + extend it,
or supersede it with a better idea (don't mint a duplicate; don't treat it as an answer — it is the
hypothesis-stage). A settled Q###/RS### on the same signature outranks an open idea.

**Free-text fallback** when the signature is fuzzy (the lexical-brittleness escalation — scans
code/title/question|problem/recognition_text, not just the exact key). Pass a BARE substring (the
queries wrap it with `%` / `instr` by construction):

```bash
bash dev/run-dev-query.sh search_adjudications_recognition PATTERN=absence
bash dev/run-dev-query.sh search_resolutions_recognition   PATTERN=aggregator
bash dev/run-dev-query.sh search_investigations            PATTERN=absence
bash dev/run-dev-query.sh search_ideas_recognition         PATTERN=absence
```

To pull the full row for a recalled code (for `as_of` / `validity` / `revalidation_query` / `evidence`):

```bash
bash dev/run-dev-query.sh get_adjudication_by_code CODE=Q003
bash dev/run-dev-query.sh get_resolution_by_code   CODE=RS007
```

## Step 3 — Show the graph context (typed edges)

For a recalled node, surface what it is connected to (source of the question, target of the answer).
`get_refs_to_node` is generic — pass the node's table, its FK column, and the code:

```bash
# inbound (who raised / crystallised this Q###)
bash dev/run-dev-query.sh get_refs_to_node TARGET_TABLE=adjudications TARGET_COL=adjudication_id CODE=Q003
# outbound, 1 hop (need the node's own id — first column of get_*_by_code)
AJ_ID=$(bash dev/run-dev-query.sh get_adjudication_by_code CODE=Q003 | head -1 | cut -d'|' -f1)
bash dev/run-dev-query.sh edges_from SOURCE_TABLE=adjudications SOURCE_ID=$AJ_ID
```

**Multi-hop walk (the "refs of those refs") — use the LOOP-SAFE query, never hand-chain.**
The graph has LEGITIMATE cycles by design (`reopens`/`reaffirms`/`validates`/`refutes`/`informs`/`relates`
may cycle — only the provenance DAG-subgraph is acyclic). Hand-chaining `edges_from` across hops can
loop the walk forever. So to expand beyond 1 hop, call the visited-set/depth-cap-safe traversal — it
returns each reachable node ONCE at its shortest depth and **terminates by construction**:

```bash
bash dev/run-dev-query.sh walk_neighborhood START_TABLE=adjudications START_ID=$AJ_ID MAX_DEPTH=4
```

Start at `MAX_DEPTH=4`; raise only if the surface has not closed. NEVER replace this with a manual
`edges_from`-of-`edges_from` loop — that is the un-guarded path the LLM can spin on.

## Step 4 — Verdict + MANDATORY revalidation (the gate)

| Situation | Action |
|---|---|
| **No hit** | State "no settled precedent for this signature." Proceed to investigate (`/dev-investigate`). Remind: crystallise the result afterward (`/dev-adjudicate` for a fact, `/dev-resolution` for a precedent) so the next recall hits. |
| **Hit, Q### (fact)** | **Re-run the decisive query.** If the Q### carries a structured handle (`revalidation_query` + `revalidation_params`) → run that query with those params (mechanical). Else reconstruct it from `evidence` prose. Result matches the verdict → cite + `as_of` + `validity`; `mark_adjudication_revalidated CODE=Q### DATE=$(date +%F)`. Diverges → `reopen_adjudication CODE=Q### REASON='…'` (or `mark_adjudication_stale CODE=Q###`) + surface to operator; do NOT rely on the old verdict. |
| **Hit, RS### (precedent)** | Re-confirm the approach still applies under current `validity` — surface to operator ("we solved P this way on `as_of`; still applies?"). On yes → cite + `mark_resolution_revalidated CODE=RS### DATE=$(date +%F)`; on no → `mark_resolution_stale CODE=RS###` / `reopen_resolution CODE=RS### REASON='…'`. |
| **Hit, status already `stale`/`superseded`** | Follow `superseded_by` (id in the full row) to the live node; treat the old one as history. Never cite a superseded finding as current. |

**Never blind-cite.** A recalled finding is a hypothesis about the present until revalidated — that is
the whole point of `as_of` / `validity` / `status`.

Revalidation status-write example (the only writes this skill ever performs, and only through a status query):

```bash
bash dev/run-dev-query.sh mark_adjudication_revalidated CODE=Q003 DATE=$(date +%F)
# or, on divergence:
bash dev/run-dev-query.sh reopen_adjudication CODE=Q003 REASON='decisive query now returns a different verdict'
```

## Step 5 — Output

Report, compactly: the matched `recognition_key`, each recalled `Q###/RS###/I###/IDEA-###` with its
verdict + `as_of` + revalidation result (confirmed / stale), and the connected nodes. If nothing
matched, say so and hand off to `/dev-investigate`. The operator then decides with a settled basis
instead of a cold start.

## Constraints

- **Read-only at heart.** This skill recalls + revalidates; it never *mints* a finding. New findings
  are crystallised by `/dev-adjudicate` / `/dev-resolution` (+ `/dev-investigate` for the process).
  The only writes it may issue are a recalled node's own `mark_*` / `reopen_*` status transition.
- **Recall is not proof.** The revalidation gate (Step 4) is mandatory — citing a stale finding as
  current is the exact failure this layer exists to prevent.
- **Reuse-before-mint governs READS too.** Match an existing `recognition_key`; never invent a variant
  just to phrase the search.
- **Never edit `documentation.db` directly.** All reads and the optional status-writes go through
  `run-dev-query.sh` with named query-ids.

---

*© {{PROJECT_NAME}} Dev | dev-recall*
