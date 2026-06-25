---
name: dev-audit
description: Use for deep analysis of the runtime layer (latest v_X.Y/). Read-only trace through dispatcher, skills, schema, queries — flags inconsistencies, drift, write conflicts. Does NOT touch dev/documentation.db; findings are reported in chat for the caller to log.
---

# /dev-audit — Deep Runtime-Layer Audit

Read-only trace through the runtime layer (latest `v_X.Y/`). Verifies consistency between dispatcher, skills, schema, and queries. Reports findings; the caller decides whether to invoke `/dev-bug-log`, `/dev-observation`, or `/dev-next-target` for each.

---

## Contract

```contract
TYPE:        atomic
ROLE:        observer (read-only)
READS:       none (no DB access)
WRITES:      none
CALLS:       none
FILES:       v_X.Y/CLAUDE.md, v_X.Y/.claude/skills/*/SKILL.md, v_X.Y/dev/schema.sql, v_X.Y/dev/dev-queries/*.sql (all read-only)
IDEMPOTENCY: yes — read-only; safe to run any number of times. Produces a report, mints nothing.

PRE-CONDITIONS:
  - audit root is the LATEST v_X.Y/ (resolved by sort -V | tail -1); archived versions are out of scope.
  - the audit scope is fixed up front (single skill / chain / schema layer / full dispatch).

POST-CONDITIONS:
  - the full chain in scope is traced end-to-end (no shortcuts) — dispatcher ↔ skills ↔ schema ↔ queries.
  - every finding is reported in chat with a severity (CRITICAL / INCONSISTENCY / DRIFT / UNCLEAR /
    SUGGESTION / OK) and a recommended caller action; findings are reported BEFORE any fix.
  - this skill logs nothing — the CALLER decides whether to invoke /dev-bug-log / /dev-observation /
    /dev-next-target per finding.

INVARIANTS-RESPECTED:
  - read-only — never modifies any file; never touches dev/documentation.db (no SQL writes).
  - latest-version-only; trace the FULL chain; report before fix.

INVARIANTS-NOT-CHECKED:
  - data-layer consistency of dev/documentation.db itself (not read); the structural-mode checks are
    contract/dispatcher-level — they do not execute queries against a live DB.
```

---

## Step 0 — Resolve target version

```bash
ls -d v_0.* v_[1-9].* 2>/dev/null | sort -V | tail -1
```

Use the latest `v_X.Y/` as the audit root. Old archived versions are out of scope.

## Step 1 — Identify Audit Scope

| Scope | Entry point | What to trace |
|---|---|---|
| Single skill | `v_X.Y/.claude/skills/[skill]/SKILL.md` | Read skill → verify DB ops match schema + queries |
| Skill chain | one row of `v_X.Y/CLAUDE.md` dispatcher | Read each skill in order → verify handoff |
| Schema layer | a table group in `v_X.Y/dev/schema.sql` | Schema → queries → skills that call them |
| Full dispatch | entire `v_X.Y/CLAUDE.md` dispatcher | Every chain, every skill, every DB op |

## Step 2 — Load Reference Sources

1. `v_X.Y/CLAUDE.md` — runtime dispatcher map, skill registry, core principles
2. `v_X.Y/dev/schema.sql` — runtime DB ground truth
3. `v_X.Y/dev/dev-queries/*.sql` — runtime query domain files
4. The SKILL.md files in scope

## Step 3 — Trace the Chain

For each skill in the audit scope:

1. **Read SKILL.md** — frontmatter (`name`, `description`), contract, steps, constraints.
2. **Identify DB operations** — which tables are read/written, which query IDs are called via `run-query.sh`.
3. **Verify against schema** — do columns exist? Are types correct? Are FKs valid?
4. **Verify against `dev/dev-queries/*.sql`** — does the referenced query ID exist? Do its parameters match the skill's invocation?
5. **Check dispatcher consistency** — is this skill listed in the right dispatcher row?
6. **Question instruction clarity** — for every step, ask:
   - Is this instruction unambiguous? If you have to interpret or guess → finding.
   - Does this instruction still make sense in the current chain context?
   - Would the runtime agent executing this step know exactly what to do?

**Rule:** Follow the instructions as written; flag every point where you had to stop and think.

## Step 3b — Structural Analysis (`--structural` mode)

Parse all `## Contract` blocks from every SKILL.md and execute:

### S1: Classification Consistency

| Condition | Severity |
|---|---|
| `TYPE=atomic` AND `CALLS≠none` | **INCONSISTENCY** — atomic must not call sub-skills |
| `TYPE=composite` AND `CALLS=none` | **INFO** — internal-steps-only composite (valid if NOTES explains) |

### S2: Call Graph

Build adjacency list from all `CALLS` edges.

### S3: Cycle Detection

Run DFS on call graph. Undocumented cycles → **CRITICAL**.

### S4: Write Conflicts

List skills that write each DB table. Flag tables written by multiple skills in the same chain.

### S5: Orphan Detection

| Condition | Severity |
|---|---|
| Skill not in any `CALLS` field AND not in any CLAUDE.md dispatcher row | **DRIFT** |
| Table in READS/WRITES not in `schema.sql` | **DRIFT** — phantom table reference |
| Query ID called by a skill but missing in `dev/dev-queries/*.sql` | **DRIFT** |

### S6: Dispatcher Consistency

Cross-reference dispatcher rows against `CALLS` chains.

### S7: Frontmatter Completeness

| Condition | Severity |
|---|---|
| SKILL.md missing `name:` or `description:` in frontmatter | **DRIFT** — Claude Code skill loader will not register it |
| SKILL.md has no `## Contract` section | **DRIFT** |
| Contract missing required field (TYPE, READS, WRITES, CALLS, FILES) | **DRIFT** |

## Step 4 — Report Findings

| Severity | Meaning | Caller action after report |
|---|---|---|
| `CRITICAL` | Data loss, wrong DB writes, broken chain | Caller invokes `/dev-bug-log` |
| `INCONSISTENCY` | Dispatcher says X, skill does Y | Caller invokes `/dev-bug-log` or `/dev-observation` |
| `DRIFT` | Skill references outdated column/query/missing frontmatter | Caller invokes `/dev-bug-log` |
| `UNCLEAR` | Ambiguous instruction | Caller invokes `/dev-bug-log` (actionable) or `/dev-observation` |
| `SUGGESTION` | Works but could be cleaner | Caller invokes `/dev-next-target` |
| `OK` | Verified correct | no action |

Output format:
```
## Audit: [scope description] (v_X.Y)
Date: [YYYY-MM-DD]

### Chain: [dispatcher row or skill name]
| Skill | Status | Notes |
|---|---|---|
| /<prefix>-[name] | OK / CRITICAL / ... | [details] |

### Findings
[List of issues with severity and recommended action]
```

## Constraints

- **Read-only.** Never modify any file during an audit.
- **No SQL writes.** This skill does not touch `dev/documentation.db`. Findings are reported in chat for the caller to log via `/dev-bug-log`, `/dev-observation`, or `/dev-next-target`.
- Run against the latest `v_X.Y/` only — never archived versions.
- Trace the FULL chain. No shortcuts.
- Report findings before any fixes are made.

---

*© {{PROJECT_NAME}} Dev | dev-audit*
