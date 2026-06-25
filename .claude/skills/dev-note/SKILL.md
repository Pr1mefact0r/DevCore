---
name: dev-note
description: Use when the user drops a freeform note, finding, or thought in chat. Classifies the note and routes it to the matching atomic skill (dev-bug-log / dev-decision-log / dev-observation / dev-changelog / dev-next-target).
---

# /dev-note — Context-Aware Note Router

Composite skill. User drops a note in chat → classify → delegate to the matching atomic skill. The atomic skill is responsible for the actual SQL write — this skill never touches `documentation.db` directly.

---

## Contract

```contract
TYPE:        composite
ROLE:        observer (read-only — routes only; the called skill writes)
READS:       none
WRITES:      none
CALLS:       /dev-recall (recall-first gate), /dev-bug-log, /dev-decision-log, /dev-observation,
             /dev-changelog, /dev-next-target, /dev-adjudicate, /dev-resolution
FILES:       none (delegates to called skills)
IDEMPOTENCY: yes — pure router; this skill mints nothing. The called atomic skill owns the write
             (and carries its own idempotency).

PRE-CONDITIONS:
  - input is freeform user text (any language; routing + IDs stay English).
  - recall-first: if the note re-raises a known anomaly/question, run /dev-recall before minting,
    to cite + revalidate a prior finding instead of duplicating it.

POST-CONDITIONS:
  - the note is classified to exactly one atomic skill per item; multiple items are routed separately.
  - the extracted fields are handed to the target skill, which performs the write; the user is shown
    what was logged and where.
  - nothing in the user's input is silently discarded; ambiguity is resolved by asking, not guessing.

INVARIANTS-RESPECTED:
  - router-only — never calls run-dev-query.sh directly; the atomic skill owns the SQL write.
  - recall-first on a re-raised anomaly; disambiguation Q###(fact) vs B###(defect),
    RS###(precedent) vs D###(forward choice).

INVARIANTS-NOT-CHECKED:
  - code allocation, edge wiring, scope-tag correctness — all owned by the delegated atomic skill,
    not verified here; schema/query consistency → /dev-schema-validate.
```

---

## Step 1 — Receive Input

The user provides freeform text. Possible content:
- A bug they found
- A design thought or decision
- Something noticed during testing
- A feature idea or improvement target
- A changelog note about a completed change

The note can be in any language. Technical routing and IDs are always English.

## Step 2 — Classify

| Signal | Classification | Route to |
|---|---|---|
| "broken", "wrong", "fails", "error" | **Bug** | `/dev-bug-log` |
| "I decided", "from now on", design rationale | **Decision** | `/dev-decision-log` |
| "noticed", "seems like", "might be", "watch for" | **Observation** | `/dev-observation` |
| "changed", "added", "fixed", "deployed", "shipped" | **Changelog** | `/dev-changelog` |
| "next", "should do", "todo", "later", feature idea | **Target** | `/dev-next-target` |
| "turns out X is true/false", "the query showed", "confirmed by data" — a factual question now CONCLUSIVELY settled | **Adjudication (Q###)** | `/dev-adjudicate` |
| "how we solved X", "the fix pattern", "reusable approach", "next time do" — a reusable precedent | **Resolution (RS###)** | `/dev-resolution` |

**Recall-first:** if the note re-raises a known anomaly/question, run `/dev-recall` first to cite + revalidate a
prior finding instead of minting a duplicate.

**Disambiguation:** a **Q###** is a settled *fact a query proved* (not a defect to fix → B###); an **RS###** is a
reusable *how-we-handled-it precedent* (not a forward design choice → D###). When the note is "we definitively
answered/handled this", lean Q/RS.

**Other node types** — a not-yet-decided thought (`/dev-idea`), an investigation process (`/dev-investigate`), or a
conditional reminder (`/dev-reminder`) — are reached via their own direct commands, not this router.

**If ambiguous:** ask the user — don't guess.

## Step 3 — Extract Fields

From the user's freeform text, extract the fields required by the target skill:

| Target | Extract |
|---|---|
| Bug | title, description, severity, found_in, fix-hypothesis |
| Decision | title, context, decision, rationale |
| Observation | title, description, found_in, watch_for |
| Changelog | title, summary, root_cause, solution, files |
| Target | title, scope, priority hint, source refs |

**Fill what you can. Ask for what you can't infer.**

## Step 4 — Execute Target Skill

Call the appropriate atomic skill with the extracted fields. The atomic skill performs the SQL insert via `dev/run-dev-query.sh`.

## Step 5 — Confirm

Show the user what was logged and where:

```
Logged as [B###/D###/W### or target id N] in dev/documentation.db
[one-line summary of what was written]
```

## Constraints

- This is a **router**, not a writer. Always delegate to an atomic skill.
- Never call `dev/run-dev-query.sh` directly from this skill.
- If the note contains multiple items, route each separately.
- Never silently discard parts of the user's input.
- If the user explicitly says which file/table they want, skip classification and route directly.

---

*© {{PROJECT_NAME}} Dev | dev-note*
