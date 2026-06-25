---
name: dev-version-bump
description: Use when a version bump is requested (new v_X.Y directory). Composite skill that runs schema-validate (if schema changed), audit (if skills changed), and changelog. Writes touch v_X.Y files; the changelog write goes through dev/run-dev-query.sh.
---

# /dev-version-bump — Version Bump Checklist

Composite skill. Executes the full version bump process: creates new version directory, freezes old one, updates all version strings, logs the bump in `dev/documentation.db` via `/dev-changelog`.

---

## Contract

```contract
TYPE:        composite
ROLE:        devcore_writer (edits v_X.Y/root files; the changelog DB write is delegated to /dev-changelog)
READS:       none (DB); queries get_open_bugs as a pre-flight gate
WRITES:      none (DB directly); file edits + delegated SQL via /dev-changelog
CALLS:       /dev-schema-validate, /dev-audit, /dev-changelog
FILES:       v_X.Y/VERSION (rw), ROOT CLAUDE.md (rw), v_X.Y/CLAUDE.md (rw), v_X.Y/README.md (rw), v_X.Y/dev/schema.sql (rw), v_X.Y/dev/dev-queries/*.sql (rw), v_X.Y/.claude/skills/*/SKILL.md (rw)
IDEMPOTENCY: no — copies the version tree and mints a changelog row; re-running would create a second
             v_X.Z/ and a duplicate changelog. On retry, check whether the new dir already exists.
NOTES:       /dev-schema-validate only if schema changed; /dev-audit only if skills changed; /dev-changelog always.

PRE-CONDITIONS:
  - v_X.Y/VERSION is updated FIRST (single source of truth), before any other file.
  - pre-flight passes: changes complete + tested, no open `critical` bug (get_open_bugs),
    /dev-schema-validate if schema changed, /dev-audit if skills changed.

POST-CONDITIONS:
  - a new v_X.Z/ directory is created from the current one; the OLD directory is frozen (never modified).
  - all version strings propagated from VERSION (root CLAUDE.md status table, v_X.Y CLAUDE.md/README,
    schema/query/skill version comments); pre-commit grep verifies each — any mismatch BLOCKS the commit.
  - a changelog row is recorded via /dev-changelog (mandatory; no bump ships without it).

INVARIANTS-RESPECTED:
  - VERSION is the single source of truth (update first, propagate everywhere); no hardcoded version
    numbers (v_X.Y placeholder); archived versions are immutable; never commit on a string mismatch.
  - the changelog write goes through /dev-changelog → run-dev-query.sh, never inline SQL.

INVARIANTS-NOT-CHECKED:
  - schema/query/skill consistency itself → delegated to /dev-schema-validate + /dev-audit (this skill
    gates on them but does not re-run their checks inline).
```

---

## Step 0 — Update VERSION

Edit `v_X.Y/VERSION` first. This is the ONLY place where the new version number is decided.

```
framework=X.Y
```

**VERSION is always updated before any other file.**

## Step 1 — Determine Bump Type

| Type | When |
|---|---|
| Minor bump (v_0.1 → v_0.2) | Bug fixes, skill improvements, query additions |
| Major bump (v_0.X → v_1.0) | Architectural changes, schema restructuring |

**Versioning rule:** Each bump creates a new `v_X.Y/` directory. The old directory is frozen as an archived snapshot — never modified again.

## Step 2 — Pre-Flight Checks

Before bumping, verify:

1. All changes are complete and tested.
2. No open `critical` bugs related to the change:
   ```bash
   bash dev/run-dev-query.sh get_open_bugs
   ```
3. `/dev-schema-validate` passes (if schema changed).
4. `/dev-audit` on affected skill chains passes (if skills changed).

## Step 3 — Create New Version Directory

```bash
# Identify current version directory
current=$(ls -d v_0.* v_[1-9].* 2>/dev/null | sort -V | tail -1)

# Set new version directory name
new_dir="v_X.Z"        # e.g. "v_0.2"
new_ver="X.Z"          # e.g. "0.2"

# Copy to new version
cp -r "$current" "$new_dir"

# Update VERSION
echo "framework=${new_ver}" > "$new_dir/VERSION"
```

**Rule:** After the copy, the OLD directory is frozen. Never modify it again.

## Step 4 — Update Files in New Version (Checklist)

Execute in this order:

| # | File | What to update |
|---|---|---|
| 0 | `$new_dir/VERSION` | `framework=` — done in Step 3 |
| 1 | ROOT `CLAUDE.md` | Current status table (mark old as archived, new as current) |
| 2 | `$new_dir/CLAUDE.md` | Version number in footer |
| 3 | `$new_dir/README.md` | Version info |
| 4 | `$new_dir/dev/schema.sql` | Version comment in header (if schema changed) |
| 5 | `$new_dir/dev/dev-queries/*.sql` | Version comment in headers (if queries changed) |
| 6 | `$new_dir/.claude/skills/*/SKILL.md` | Version in footer for changed skills |
| 7 | `/dev-changelog` | call atomic skill to insert the changelog row |

## Step 5 — Pre-Commit Verification

```bash
source "$new_dir/VERSION"

grep "v${framework}" "$new_dir/CLAUDE.md"  || echo "FAIL: $new_dir/CLAUDE.md"
grep "v${framework}" "$new_dir/README.md"  || echo "FAIL: $new_dir/README.md"
grep "v${framework}" CLAUDE.md             || echo "FAIL: ROOT CLAUDE.md"

git status --short | grep '^!!' && echo "WARN: gitignored files detected — check staging area"
```

**Any mismatch = BLOCK commit, list mismatches, fix first.**

## Atomic Skills Called

| Order | Skill | Purpose | Writes SQL? |
|---|---|---|---|
| 1 | `/dev-schema-validate` | pre-flight (if schema changed) | no |
| 2 | `/dev-audit` | pre-flight (if skills changed) | no |
| 3 | `/dev-changelog` | mandatory changelog entry | yes (changelog table) |

## Constraints

- **VERSION is single source of truth.** Update first, propagate to all files.
- **Never commit if strings don't match VERSION.**
- **Never skip the changelog.** No version bump without `/dev-changelog`.
- **Never modify archived versions.** Old `v_X.Y/` directories are frozen.
- **Test before bump.** A version bump is a release — not a work-in-progress marker.
- **No hardcoded version numbers in dev skills.** Use `v_X.Y` as placeholder.

---

*© {{PROJECT_NAME}} Dev | dev-version-bump*
