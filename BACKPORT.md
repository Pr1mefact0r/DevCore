# BACKPORT — deploying DevCore v3.0 into a project

> How to install DevCore v3.0 (`v_3.0/`) into an existing or new project.
> v3.0 brings the brain-graph: in addition to the 5 base components, it now also copies **the hooks, the projectrules seed,
> the new query files, and the 6 new skills**.
> Spec: `DEVCORE.md`. Migration from v1.0 (Markdown): see the "Migration v1.0 → v2.0" section below (legacy).

---

## Files in the template

```
v_3.0/
├── BACKPORT.md                          ← this file (do NOT copy)
├── README.md                            ← template docs (do NOT copy)
├── DEVCORE.md                           ← DevCore spec (do NOT copy)
├── CLAUDE.md                            ← COPY (dispatcher + session-start protocol + brain-graph section)
├── .gitignore                           ← COPY
├── VERSION                              ← COPY (framework=3.0)
├── .claude/
│   ├── settings.json                    ← COPY (statusline + hook wiring — the 7 hooks are wired here)
│   ├── statusline.sh                    ← COPY (chmod +x)
│   ├── hooks/                           ← COPY (7 hooks + _op_error_lib.sh, chmod +x)
│   │   ├── session-start.sh             ← load brain context (projectrules + watchdogs)
│   │   ├── enforce-runquery.sh          ← blocks direct sqlite3 writes to documentation.db (exit 2)
│   │   ├── op-error-capture.sh          ← bash error → op_error_raw (single-role)
│   │   ├── braincode-surface.sh
│   │   ├── edge-on-mention.sh
│   │   ├── graph-reconcile.sh
│   │   ├── query-consumer-gate.sh
│   │   └── _op_error_lib.sh             ← shared lib for op-error-capture
│   └── skills/                          ← COPY (all 17 SKILL.md — 13 atomic + 4 composite)
├── .github/
│   └── ISSUE_TEMPLATE/                  ← COPY (3 .yml)
├── dev/
│   ├── schema.sql                       ← COPY (brain-graph schema: 15 tables, 2 triggers)
│   ├── run-dev-query.sh                 ← COPY (chmod +x)
│   ├── dev-queries/                     ← COPY (14 .sql)
│   │   ├── decisions, bugs, changelog,  ← 5 base domains
│   │   │   observations, next_targets
│   │   ├── refs.sql                     ← typed edges (link_*, walk_neighborhood, detect_cycles, search)
│   │   ├── recognition_keys.sql         ← reuse-before-mint
│   │   ├── op_errors.sql                ← op_error_raw sink
│   │   └── adjudications, resolutions,  ← the 6 new nodes
│   │       investigations, ideas,
│   │       reminders, projectrules
│   ├── seeds/projectrules.sql          ← COPY (28-rule PR seed — auto-applied on first bootstrap)
│   ├── migrate_md_to_sqlite.py          ← COPY
│   ├── check/.gitkeep                   ← COPY
│   └── db/.gitkeep                      ← COPY
└── devdash/                             ← COPY (FastAPI app incl. brain-graph explorer, optional setup)
    ├── main.py, db.py, requirements.txt, README.md
    ├── templates/, static/
```

`_init/`, `v_X.Y/` (runtime), and `dev/documentation.db` are deliberately not provided — they are project-specific or are created on the first skill invocation or first `run-dev-query.sh` call.

**Auto-seed:** On the first `run-dev-query.sh` call, the wrapper bootstraps the DB from `schema.sql` **and**
immediately afterwards plays `dev/seeds/projectrules.sql` (`INSERT OR IGNORE` = idempotent) → 28 projectrules are available right away.
A consuming project **without a runtime layer** can retire the 3 optional runtime rules **PR026–PR028**
(`retire_projectrule CODE=PR026` …) — they are already marked as optional/runtime in the seed.

---

## Placeholders

| Placeholder | Meaning | Example |
|---|---|---|
| `{{PROJECT_NAME}}` | project name (display) | `Acme`, `Ledger`, `Orbit` |
| `{{PREFIX}}` | runtime skill prefix | `ac`, `ld`, `ob` |
| `{{REPO_SLUG}}` | GitHub slug | `youruser/MyProject-Dev` |

---

## New project — bootstrap recipe

```bash
TARGET=$HOME/code/MyProject-Dev
mkdir -p "$TARGET"

SRC=$HOME/code/DevCore-Dev/v_3.0
rsync -av \
  --exclude=BACKPORT.md \
  --exclude=README.md \
  --exclude=DEVCORE.md \
  "$SRC/" "$TARGET/"

cd "$TARGET"
PROJECT_NAME="MyProject"
PREFIX="app"
REPO_SLUG="myorg/MyProject-Dev"

grep -rl '{{PROJECT_NAME}}' . | xargs sed -i "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g"
grep -rl '{{PREFIX}}' .       | xargs sed -i "s/{{PREFIX}}/${PREFIX}/g"
grep -rl '{{REPO_SLUG}}' .    | xargs sed -i "s|{{REPO_SLUG}}|${REPO_SLUG}|g"

chmod +x .claude/statusline.sh dev/run-dev-query.sh .claude/hooks/*.sh

# bootstrap documentation.db (schema + projectrules seed are played automatically on the first call)
bash dev/run-dev-query.sh count_decisions
bash dev/run-dev-query.sh get_active_projectrules   # should return 28 rules

# Project WITHOUT a runtime layer: retire the optional runtime rules
# bash dev/run-dev-query.sh retire_projectrule CODE=PR026
# bash dev/run-dev-query.sh retire_projectrule CODE=PR027
# bash dev/run-dev-query.sh retire_projectrule CODE=PR028

# language marker — ASK the operator which language operator-facing output should use,
# then create the matching marker; do NOT default to a language silently.
#   deu = German · eng = English · fra = French · …      (e.g. after asking:  touch eng)

# Verify: no placeholders left
grep -rE '\{\{[A-Z_]+\}\}' . --include='*.md' --include='*.sh' --include='*.yml' --include='*.json' --include='*.sql' --include='*.py' --include='*.html' --include='*.css' && echo "FAIL" || echo "OK"
```

---

## After the backport — start a new Claude Code session

Hooks, skills, and the statusline are loaded via `.claude/settings.json` **at session start**.
A Claude Code already running in the target project will **not** see the freshly installed dev layer —
after the backport, **restart the session** (`/exit` → reopen, or restart the terminal `claude`).
Only then do `session-start` (loads the projectrules + watchdogs visibly),
`enforce-runquery` (write protection), and the `/dev-*` skills take effect.

---

## Where a migrated project's docs must live

There is **no** magic auto-ingest folder — the brain is populated in one of two ways:

**1. Legacy DevCore Markdown** (`decisions.md`, `bugs.md`, `changelog.md`, `observations.md`,
`next-targets.md` from a v1.0 setup) → `migrate_md_to_sqlite.py` takes **explicit paths**
(no fixed location):

```bash
python3 dev/migrate_md_to_sqlite.py \
  --decisions    PATH/decisions.md \
  --bugs         PATH/bugs.md \
  --changelog    PATH/changelog.md \
  --observations PATH/observations.md \
  --next-targets PATH/next-targets.md \
  --db dev/documentation.db
```

The parser is tolerant but expects roughly this format (anything that does not match is reported as a warning):

| File | expects |
|---|---|
| `decisions.md` | `### D### Title` blocks with `**Date:** … **Context:** … **Decision:** … **Rationale:** …` |
| `bugs.md` | table rows `\| B### \| title \| found_in \| fix \|` under `## Open` / `## Fixed` |
| `observations.md` | table rows `\| W### \| title \| found_in \| watch_for \| status \|` |
| `changelog.md` | `## [scope] Title (YYYY-MM-DD)` with `### Root Cause` / `### Solution` / `### Files Changed` |
| `next-targets.md` | table rows `\| prio \| title \| affected \| source \|` (NT code in the text) |

Spot-check afterwards: `bash dev/run-dev-query.sh get_recent_decisions` (or `get_open_bugs` / `get_open_targets`).

**2. Arbitrary project docs / specs / briefs** (not DevCore format) → **no** automatic import.
Place them in **`_init/`** (the gitignored convention for input briefs) or as `beschreibung.md` in the
root; the agent **reads** them and **crystallizes** the content into the brain via skills
(`/dev-decision-log` for founding decisions, `/dev-note` to route, `/dev-next-target` for the
roadmap). Only that turns free text into a typed, queryable node — DevCore does not parse
arbitrary prose automatically.

---

## Memory exclusion — the brain is the memory

The template sets `"autoMemoryEnabled": false` in `.claude/settings.json` — **deliberately**. DevCore projects
are brain-driven: project knowledge lives in `dev/documentation.db` (the brain-graph), not in Claude's
auto-memory (`MEMORY.md` / `memory/*.md`). Auto-memory is a historical archive, not live state — loaded at
session start it would compete with the brain and inject stale "facts".

**Rule in the project:**
- Durable **discipline** → a `projectrule` (`PR###`) in the brain (operator-OK).
- Durable **project facts** → the `dev/*` tables (decisions/bugs/… + `refs` edges).
- **Never** a reflex write of findings/feedback to memory.
- Every self-referential question (what's done/open/decided, which rule applies) → the brain is the
  only source (`run-dev-query.sh` / `*_search` / `get_active_projectrules`).

A project that deliberately does want Claude memory sets the flag back to `true` in its `settings.json`
— the template default is **off**.

---

## Existing v1.0 project (Markdown) → migrate to v2.0  *(legacy)*

> Legacy path for projects still sitting on the Markdown setup. First lift them onto the SQLite foundation (v2.0),
> then the same `rsync` from `v_3.0/` directly brings the brain-graph components (hooks, seed, new queries/skills)
> along; `documentation.db` gets the 28-rule projectrules seed on the first bootstrap.

If the project already has an older setup with `dev/decisions.md`, `dev/bugs.md` etc.:

```bash
TARGET=$HOME/code/MyProject-Dev   # example
SRC=$HOME/code/DevCore-Dev/v_3.0

# 1. Backup the existing dev/*.md files
cp -r "$TARGET/dev" "$TARGET/dev.bak.$(date +%Y%m%d)"

# 2. Install skills + statusline + dev/ infra (do NOT overwrite the old .md)
rsync -av "$SRC/.claude/" "$TARGET/.claude/"
rsync -av "$SRC/.github/" "$TARGET/.github/"
rsync -av --exclude='*.md' "$SRC/dev/" "$TARGET/dev/"
rsync -av "$SRC/devdash/" "$TARGET/devdash/"
cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md.template"   # first as a template, then merge

# 3. Replace placeholders (in the freshly installed files)
cd "$TARGET"
PROJECT_NAME="MyProject"; PREFIX="app"; REPO_SLUG="youruser/MyProject-Dev"
for f in .claude/skills/*/SKILL.md .claude/statusline.sh .github/ISSUE_TEMPLATE/*.yml CLAUDE.md.template devdash/README.md; do
  [ -f "$f" ] || continue
  sed -i "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g; s/{{PREFIX}}/${PREFIX}/g; s|{{REPO_SLUG}}|${REPO_SLUG}|g" "$f"
done

# 4. Migrate the existing .md content into documentation.db
python3 dev/migrate_md_to_sqlite.py \
  --decisions dev.bak.*/decisions.md \
  --bugs dev.bak.*/bugs.md \
  --changelog dev.bak.*/changelog.md \
  --observations dev.bak.*/observations.md \
  --next-targets dev.bak.*/next-targets.md \
  --db dev/documentation.db

# 5. Merge CLAUDE.md — carry over the project-specific sections (Vision, Architecture Decisions, Current Status)
#    from the existing CLAUDE.md; the skill dispatch / workflow structure comes from CLAUDE.md.template

chmod +x .claude/statusline.sh dev/run-dev-query.sh

# 6. Verify
grep -rE '\{\{[A-Z_]+\}\}' . --include='*.md' --include='*.sh' --include='*.yml' --include='*.json' --include='*.sql' --include='*.py' && echo "FAIL" || echo "OK"
```

---

## Additionally required per project

DevCore does not provide:

1. **`README.md`** in the project root (project-specific)
2. **`v_X.Y/`** runtime directory (schema, queries, code, skills with prefix `{{PREFIX}}-*`)
3. **`_init/`** with the project's input specs (gitignored)
4. **Language marker** (`deu`, `eng`, ...)
5. Fill in the **Vision section** in `CLAUDE.md`
6. Enter **Architecture Decisions** as founding decisions via `/dev-decision-log`
7. **Current Status table** in `CLAUDE.md`

---

## Starting DevDash

DevDash is an optional FastAPI app that shows `dev/documentation.db` read-only in the browser:

```bash
cd devdash
pip install -r requirements.txt
DEVCORE_DB=../dev/documentation.db uvicorn main:app --host 127.0.0.1 --port 8765
```

Port convention:
- ProjectA-Dev: 8765
- ProjectB-Dev: 8766
- ProjectC-Dev: 8767
- DevCore-Dev: 8768

Optionally set it up as a systemd user service — see `devdash/README.md`.

---

## Verify checklist after backport

```bash
# No placeholders left
grep -rE '\{\{[A-Z_]+\}\}' . --include='*.md' --include='*.sh' --include='*.yml' --include='*.json' --include='*.sql' --include='*.py' && echo "FAIL" || echo "OK"

# Skills readable with name+description
for f in .claude/skills/*/SKILL.md; do
  grep -q "^name:" "$f" || echo "FAIL: $f missing name:"
  grep -q "^description:" "$f" || echo "FAIL: $f missing description:"
done

# DB bootstraps cleanly
rm -f dev/documentation.db
bash dev/run-dev-query.sh count_decisions  # creates DB from schema.sql

# Skills work end-to-end (smoke test)
bash dev/run-dev-query.sh next_decision_code   # should output D001
```

---

*DevCore v3.0 BACKPORT*
