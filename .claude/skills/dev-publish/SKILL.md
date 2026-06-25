---
name: dev-publish
description: Publish the project's latest v_x.y deliverable to its clean public repo — copy it out (never the DevCore dev-layer or brain), read the diff, draft a brain-informed changelog, then commit + push. Use when the operator wants to ship/release the project (not to log dev memory).
---

# /dev-publish — workshop → clean public repo (brain-informed)

Replicates the **DevCore-Dev → DevCore** pattern for any project. The workshop (`<Name>-Dev`) holds
the full DevCore dev-layer + brain + the project in `v_X.Y/`. The **public product carries none of
DevCore** — this skill copies only the latest `v_X.Y/` deliverable into a separate clean repo, diffs
it, pulls the matching context from the brain, drafts the GitHub changelog, and only then commits +
pushes. (Decision D017.)

---

## Contract

```contract
TYPE:    atomic
ROLE:    observer (reads the brain; writes only the separate public repo via git)
READS:   changelog, decisions, bugs, next_targets, observations (recent, for the narrative);
         git status/diff of the public push-repo; the latest v_X.Y/ deliverable
WRITES:  nothing in dev/documentation.db — produces a commit in the SEPARATE public repo
CALLS:   none
FILES:   latest v_X.Y/ (read), the public repo dir (rsync target + git commit),
         dev/publish.conf (read; WRITTEN once on first-run setup — gitignored)
IDEMPOTENCY: no — each run is a new commit/push
PRE-CONDITIONS:  the latest v_X.Y/ is the intended deliverable state; the brain is current for this
                 work (decisions/bugs/changelog logged as you went); a publish target is known.
POST-CONDITIONS: the public repo holds the latest v_X.Y/ deliverable (NO DevCore dev-layer, NO
                 documentation.db), committed with a brain-informed message and pushed; the workshop
                 repo is untouched.
INVARIANTS-RESPECTED: D017 (publish the deliverable, not the workshop); the dev-layer + the binary
                 brain NEVER reach the public repo; operator confirms before push.
INVARIANTS-NOT-CHECKED: does not verify the deliverable builds/tests; does not verify brain completeness.
```

---

## Step 1 — Resolve the deliverable + the target

- **Deliverable**: the latest `v_X.Y/` (highest version dir). By design it does NOT contain the DevCore
  dev-layer (that lives at the workshop root), so copying it out is clean.
- **Target** (the clean public repo) comes from **`dev/publish.conf`** — a local, **gitignored** file
  (template: `dev/publish.conf.example`):

  ```ini
  TARGET_DIR=/abs/path/to/<Name>            # the clean public repo dir (a sibling, no -Dev)
  REMOTE=git@github.com:<user>/<Name>.git   # created via gh if missing (Step 2)
  BRANCH=main
  RESOLVE_PLACEHOLDERS=no                    # yes if the deliverable still carries {{…}}
  ```

  **First run — no `publish.conf` yet (one-time setup):** propose the sibling default
  (`…/<Name>-Dev` → `…/<Name>`), **ask the operator** to confirm or override `TARGET_DIR` + `REMOTE`,
  then **write `dev/publish.conf`** with the answers. Every later run reads it and does **not** ask again.

State the resolved deliverable + target and confirm before touching anything.

## Step 2 — Sync the deliverable into the push-repo

```bash
rsync -a --delete \
  --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.venv' \
  <latest v_X.Y>/ <TARGET_DIR>/
```

Resolve any remaining `{{PLACEHOLDER}}` in the target if `RESOLVE_PLACEHOLDERS=yes`. **Never** copy
the workshop root (`dev/`, `.claude/`, `devdash/`, `documentation.db`) — only the `v_X.Y/` contents.
If `TARGET_DIR` is not yet a git repo or the `REMOTE` doesn't exist, `git init` it and
`gh repo create <Name> --public --source=<TARGET_DIR> --remote=origin --push` — **only with explicit
operator OK** (public vs private is the operator's call).

## Step 3 — Diff the public repo

```bash
git -C <TARGET_DIR> add -A
git -C <TARGET_DIR> diff --cached --stat        # what changed vs the last published state
git -C <TARGET_DIR> diff --cached                # full diff for the narrative
```

If the diff is empty, stop and report "nothing to publish".

## Step 4 — Search the brain for the matching context

Scope to "since the last publish": read the public repo's last commit time
(`git -C <TARGET_DIR> log -1 --format=%cI`) and pull brain entries on/after it:

```bash
bash dev/run-dev-query.sh get_recent_changelog
bash dev/run-dev-query.sh get_recent_decisions
bash dev/run-dev-query.sh get_open_bugs          # + recently fixed
bash dev/run-dev-query.sh get_open_targets        # + recently completed
```

Map the changed files → the brain entries that explain them (decisions made, bugs fixed, targets
completed). The brain is NOT in the public repo, so this context only survives if it lands in the
message (Step 5).

## Step 5 — Draft the GitHub changelog / commit message

Synthesize from diff + brain:
- **Subject** — imperative, ≤72 chars, the dominant change.
- **Body** — grouped bullets: **Decisions** (`D###`), **Fixes** (`B###`), **Features/Changes** (`CL###`/`NT###`),
  each one line, citing the brain code as the durable provenance.
- Append the repo's commit trailer convention if it has one.

Show the full drafted message to the operator.

## Step 6 — Commit + push (only after operator OK)

```bash
git -C <TARGET_DIR> commit -F <drafted-message>
git -C <TARGET_DIR> push origin <branch>
```

Report the pushed SHA + the target repo URL. The workshop repo is never modified by this skill.

---

## Constraints

- **The dev-layer + `documentation.db` never enter the public repo.** Only the latest `v_X.Y/` contents.
- **Read-only on the brain.** This skill drafts a commit from the brain; it does not write dev memory.
  (Log decisions/bugs *before* publishing, via the normal `/dev-*` skills.)
- **Operator confirms before push.** Show the diff summary + the drafted message first.
- Resolve the target dynamically (config → sibling convention → ask); never hardcode a path.

---

*© DevCore | dev-publish*
