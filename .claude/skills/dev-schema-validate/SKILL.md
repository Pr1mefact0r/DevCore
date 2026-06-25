---
name: dev-schema-validate
description: Use when schema, query, or skill changes need a consistency check. Read-only validation that v_X.Y/dev/schema.sql, dev/dev-queries/*.sql, and skills are in sync. Does NOT touch dev/documentation.db.
---

# /dev-schema-validate — Schema Consistency Check

Read-only validation. Verifies that `schema.sql`, query domain files (`dev/dev-queries/*.sql`), and skills are mutually consistent. Same purity as `/dev-audit`: reports findings, does not modify any file.

---

## Contract

```contract
TYPE:        atomic
ROLE:        observer (read-only)
READS:       none (no DB access)
WRITES:      none
CALLS:       none
FILES:       v_X.Y/dev/schema.sql, v_X.Y/dev/dev-queries/*.sql, v_X.Y/.claude/skills/*/SKILL.md (all read-only)
IDEMPOTENCY: yes — read-only; safe to run any number of times. Produces a report, mints nothing.

PRE-CONDITIONS:
  - validation root is the LATEST v_X.Y/ (resolved by sort -V | tail -1); archived versions are out of scope.
  - schema.sql + all dev-queries/*.sql + the in-scope SKILL.md contracts are loaded before checking.

POST-CONDITIONS:
  - schema↔queries, queries↔skills, skills(Contract READS/WRITES)↔schema, and cross-reference
    (orphan tables/queries, dispatcher listing, write-bypass) checks all run.
  - every result is reported with PASS / FAIL / WARN; issues are surfaced for the caller to log
    (/dev-bug-log or /dev-observation) — this skill writes nothing.

INVARIANTS-RESPECTED:
  - read-only — never modifies schema, queries, or skills; never touches dev/documentation.db.
  - latest-version-only; DB-engine-specific constructs are valid schema (not flagged); report before fix.

INVARIANTS-NOT-CHECKED:
  - runtime correctness / data state of dev/documentation.db (static analysis only); skill-chain
    behavioural drift (that is /dev-audit's structural mode).
```

---

## Step 0 — Resolve version path

```bash
ls -d v_0.* v_[1-9].* 2>/dev/null | sort -V | tail -1
```

Use that path (e.g. `v_0.1`) for all subsequent steps.

## Step 1 — Load Sources

```bash
cat v_X.Y/dev/schema.sql
cat v_X.Y/dev/dev-queries/*.sql
```

Note: `schema.sql` may contain DB-engine-specific constructs (extension calls, materialized views, custom functions). These are valid — verify against the engine the project actually uses.

## Step 2 — Schema → Queries Check

For every query in `dev/dev-queries/*.sql`:

| Check | Pass condition |
|---|---|
| Referenced tables exist in schema | Table name appears in `CREATE TABLE` or `CREATE MATERIALIZED VIEW` |
| Referenced columns exist | Column name appears in the correct table definition |
| Column types match usage | e.g., `DOUBLE PRECISION` columns not compared with string literals |
| JOINs use valid FK relationships | FK exists in schema |
| Query ID is unique | No duplicate `-- @id:` markers across domain files |

## Step 3 — Queries → Skills Check

For every runtime skill (`v_X.Y/.claude/skills/<prefix>-*/SKILL.md`) that references a query ID:

| Check | Pass condition |
|---|---|
| Query ID exists in `dev/dev-queries/*.sql` | grep on `-- @id: <name>` confirms presence |
| Parameters match | Skill passes correct `KEY=VALUE` parameters for the query |
| Result columns used correctly | Skill reads columns that the query actually `SELECT`s |

## Step 4 — Skills → Schema Check (Contract READS/WRITES)

For every skill Contract that declares READS or WRITES tables:

| Check | Pass condition |
|---|---|
| Tables exist in schema | Every table listed in READS/WRITES appears in `CREATE TABLE` |
| No undeclared table access | Skill doesn't reference queries for tables outside its Contract |

Note: Since all DB operations go through `run-query.sh` templates, no inline SQL should exist in skills.

## Step 5 — Cross-Reference Check

| Check | Pass condition |
|---|---|
| Every table in schema has at least one query | No orphan tables |
| Every query is referenced by at least one skill | No orphan queries |
| Dispatcher lists all skills that exist | No unlisted skills |
| PreToolUse hook (if any) covers write patterns | No write bypass possible |

## Step 6 — Report

```
## Schema Validation: v_X.Y schema / v_X.Y framework
Date: [YYYY-MM-DD]

### Results
| Check | Status | Details |
|---|---|---|
| [check name] | PASS / FAIL / WARN | [details] |

### Issues Found
[List with severity — caller should invoke /dev-bug-log or /dev-observation after this report]
```

## Constraints

- **Read-only.** Never modify schema, queries, or skills during validation.
- **No SQL writes.** This skill does not touch `dev/documentation.db`.
- Run against the latest `v_X.Y/` only — never archived versions.
- DB-engine-specific constructs are valid schema — do not flag as errors.
- Report all findings before any fixes.

---

*© {{PROJECT_NAME}} Dev | dev-schema-validate*
