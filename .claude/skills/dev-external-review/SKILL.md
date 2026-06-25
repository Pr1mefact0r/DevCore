---
name: dev-external-review
description: Use when the user pastes content from an external AI model (review, draft, analysis from Claude.ai / ChatGPT / Gemini etc). Saves to dev/check/, verifies against the codebase, then routes verified findings to atomic dev skills.
---

# /dev-external-review — Ingest & Verify External AI Content

User pastes content from another AI model directly in chat. Everything goes to `dev/check/` first as a verbatim audit trail. Verified findings are routed to `/dev-bug-log`, `/dev-decision-log`, `/dev-observation`, `/dev-next-target`, or `/dev-changelog` — those skills perform the SQL writes. This skill itself only writes to `dev/check/*.md`.

---

## Contract

```contract
TYPE:        composite
ROLE:        devcore_writer (writes dev/check/*.md only; DB writes are delegated to atomic skills)
READS:       none (DB); reads v_X.Y files + queries get_decisions_by_scope during verification
WRITES:      dev/check/*.md
CALLS:       /dev-bug-log, /dev-decision-log, /dev-observation, /dev-changelog, /dev-next-target
FILES:       dev/check/*.md (rw)
IDEMPOTENCY: conditional — re-running on the same paste overwrites/extends the same dev/check/ file
             (the audit trail), but each delegated atomic write mints its own code (not idempotent there).
NOTES:       Step 4 routes verified findings to atomic skills — not all called every time.

PRE-CONDITIONS:
  - the input is external-AI content pasted by the user; it is saved to dev/check/ VERBATIM, with a
    provenance header (Source / Pasted / Status: UNVERIFIED / Subject), BEFORE any action.
  - the pasted content is never modified — only a verification section is appended.

POST-CONDITIONS:
  - every claim is verified against the codebase (files/schema/queries/skills/architecture exist and
    match) before being acted on; the file's Status is updated to VERIFIED / PARTIALLY VERIFIED.
  - only verified findings are routed to the matching atomic skill (which performs the SQL write);
    the dev/check/ file is retained as a permanent audit trail (never deleted).

INVARIANTS-RESPECTED:
  - everything goes through dev/check/ first; verify-before-integrate; codebase is trusted over
    external claims; original paste is immutable (append-only verification).
  - this skill writes only dev/check/*.md — all DB writes go through the delegated atomic skills.

INVARIANTS-NOT-CHECKED:
  - code allocation / edge wiring / scope tags of the delegated writes (owned by the atomic skills);
    schema/query consistency of v_X.Y → /dev-schema-validate.
```

---

## Step 1 — Save to `dev/check/`

| Content type | Naming convention |
|---|---|
| Review of an existing file | `[reviewed-file-name]_review.md` |
| Draft of a new skill/feature | `[skill-or-feature-name]_draft.md` |
| Analysis of architecture/bugs | `[topic]_analysis.md` |

Write with provenance header:

```markdown
<!--
  Source: [model name if stated, otherwise "external AI"]
  Pasted: [YYYY-MM-DD]
  Status: UNVERIFIED
  Subject: [what this reviews/drafts — file path or topic]
-->

[pasted content verbatim]
```

**Never modify the pasted content.** Save exactly as provided.

## Step 2 — Verify Against Codebase

External models lack project context. You have full context. Verify everything.

| Check | How |
|---|---|
| File references valid? | Do the files/paths mentioned actually exist? |
| Schema claims correct? | Do table/column references match `v_X.Y/dev/schema.sql`? |
| Query references valid? | Do query IDs exist in `v_X.Y/dev/dev-queries/*.sql`? |
| Skill references correct? | Do referenced skills exist in `v_X.Y/.claude/skills/`? Read them. |
| Architecture claims accurate? | Does the claim match `v_X.Y/CLAUDE.md` and core principles? |
| Proposed changes compatible? | Would the suggestion break existing skill chains? |
| Naming conventions followed? | Does the content match existing patterns? |

For reviews: read the reviewed file before evaluating claims. External models often flag intentional design decisions as bugs — check past decisions:

```bash
bash dev/run-dev-query.sh get_decisions_by_scope SCOPE_LIKE='%'
```

## Step 3 — Annotate Findings

Append a verification section to the saved file:

```markdown
---

## Verification ([YYYY-MM-DD])

### Confirmed
- [claims that are correct, with evidence]

### Incorrect
- [claims that are wrong, with correction]

### Needs Investigation
- [claims needing deeper audit — flag for /dev-audit]

### Already Decided
- [claims contradicting existing decisions — reference D###]
```

Update provenance header: `Status: UNVERIFIED` → `VERIFIED` or `PARTIALLY VERIFIED`.

## Step 4 — Act on Verified Findings

| Finding type | Action |
|---|---|
| Valid bug | `/dev-bug-log` |
| Valid improvement idea | `/dev-next-target` |
| Challenges existing decision | `/dev-decision-log` (re-evaluate) |
| Needs watching | `/dev-observation` |
| Accepted draft/skill | **build it** + `/dev-changelog` |
| Accepted documentation change | **write it** directly into target file |

**The file in `dev/check/` remains as an audit trail.** Never deleted.

## Constraints

- **Everything goes through `dev/check/` first.** No exceptions.
- **Never integrate without verification.** Save → verify → act.
- **Never modify the original pasted content** — only append the verification section.
- **External models don't have full context.** Trust the codebase over external claims.
- This skill writes **only** to `dev/check/*.md`. Atomic skills handle SQL writes.

---

*© {{PROJECT_NAME}} Dev | dev-external-review*
