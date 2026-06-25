---
name: dev-reminder
description: Use when a conditional / time-bound "do X when Y" note is given that should fire later, OR when a previously-logged reminder's trigger has fired and the entry needs to be resolved. Records or updates an entry in the `reminders` table of dev/documentation.db with the next available R### code, optionally arming a watchdog.
---

# /dev-reminder — Log or Resolve Conditional Reminder

Inserts or updates a row in the `reminders` table of `dev/documentation.db` via `dev/run-dev-query.sh`, and wires its typed `refs` edge to the subject it concerns.

A reminder is **dormant** until its trigger is met. Then you take the action and mark the entry resolved. Distinct from:
- `/dev-next-target` — **prioritised** future work, always actionable now
- `/dev-observation` — **watch-list** items, not yet a bug or decision
- `/dev-bug-log` — **bugs**, must be fixed

---

## Contract

```contract
TYPE:        atomic
ROLE:        devcore_writer (writes)
READS:       reminders, bugs, decisions, next_targets (via dev/run-dev-query.sh)
WRITES:      reminders, refs (the subject the reminder concerns — usually a B###/D###/NT###) (via dev/run-dev-query.sh)
CALLS:       none
FILES:       dev/run-dev-query.sh (executed, never edited)
IDEMPOTENCY: conditional — insert (new R###) is NOT idempotent; resolve/dismiss/update of an existing reminder IS idempotent (terminal-state converges). On retry, prefer the resolve path.

PRE-CONDITIONS:
  - for a NEW reminder: next_reminder_code is the FIRST DB call; capture with head -1 | cut -d'|' -f1 and echo it (code-before-text). The trigger must be explicit and checkable ("when Y happens"), not a vague aspiration.
  - wire the subject (refs typed edge): a reminder almost always concerns a node — a verify-after watchdog relates to its B###, a deadline relates to its NT###, a "revisit when…" relates to its D###. INSERT a typed refs row (link_bug / link_decision / link_next_target, RELATION=relates) from the reminder to that node. Zero edges only for a genuinely subject-less time-tick — and then say so explicitly.
  - for RESOLVING a fired reminder: locate the entry via get_reminder_by_code first; never hand-type the id. Take the triggered action BEFORE marking resolved.

POST-CONDITIONS:
  - insert / resolve confirmed via the echoed id|code|status (or UPDATE) line (visual check).
  - a dormant reminder is left with a clear, machine-or-human-checkable trigger; a resolved reminder records what action was taken.
  - if the trigger is mechanically checkable, a watchdog_spec JSON is attached (set_watchdog_spec) so it is not forgotten.

INVARIANTS-RESPECTED:
  - data quality (PR001-class) — triggers are concrete and checkable, not vague.
  - code-before-text (PR005-class) — allocator/resolver runs first, code is echoed before any prose.
  - typed-edge-on-mention (PR019-class) — the subject is wired via a RELATION-bearing refs row, never an untyped node-edge.
  - no inline SQL (D004-class) — all writes go through run-dev-query.sh with named query-ids.

INVARIANTS-NOT-CHECKED:
  - watchdog EXECUTOR wiring (tmux / cron / systemd / loop) — out of scope; the executor is the project's choice. This skill only writes the spec.
  - session-start re-arm / fired-marker pickup — handled by the session-start protocol, not here.
  - schema DDL — n/a; no DDL.
```

---

## Step 1 — Decide: new reminder or resolve existing?

| Situation | Action |
|---|---|
| User flags a conditional action ("when X, do Y") | new reminder (Step 2) |
| A trigger has just fired (user mentions it / you spot it) | resolve existing (Step 4) |
| Trigger or action changed mid-flight | update (Step 5) |

## Step 2 — New reminder: allocate the code FIRST

```bash
bash dev/run-dev-query.sh next_reminder_code
```

Output e.g. `R015`. Echo it as `$CODE` before writing any prose (code-before-text).

### Fields

| Field | Required | Notes |
|---|---|---|
| `CODE` | yes | next R### from the allocator |
| `SCOPE` | yes | `[v3.0]` / `[DEV]` / `[DEV+v3.0]` — must NOT contain `v_X.Y` (schema GLOB-rejects it) |
| `TITLE` | yes | one-sentence context — what the reminder is about |
| `TRIGGER_WHEN` | yes | the concrete event/condition that makes it fire (timestamp, threshold, completion of another task) |
| `ACTION` | yes | exactly what to do when it fires — specific enough that future-you can act without re-reading the conversation |

### Quality check before insert

- Is the trigger **objective**? ("when quota cycle resets" is OK; "when ready" is not.)
- Is the action **specific**? ("re-run the fired-marker check on B001" is OK; "review later" is not.)
- Would this fit better in `next_targets` (prioritised work) or `observations` (watch-list)? If so, use those skills instead.

### Insert

```bash
bash dev/run-dev-query.sh insert_reminder \
  DATE=$(date +%F) \
  CODE=R015 \
  SCOPE='[DEV]' \
  TITLE='Re-verify B040 fix after next watchdog restart cycle' \
  TRIGGER_WHEN='watchdog runner restarts (next session-start re-arm)' \
  ACTION='Re-run the fired-marker check on B040; confirm watchdog_fired_at survives restart.'
```

The insert echoes `id|code|status` (e.g. `7|R015|active`) — visual-confirm it.

## Step 3 — Wire the subject + (optional) arm a watchdog

### 3a — Wire the typed edge to the subject (almost always required)

A reminder concerns a node. Capture the reminder's own id, resolve the subject's id, then link:

```bash
# reminder id (first pipe-column of get_reminder_by_code)
R_ID=$(bash dev/run-dev-query.sh get_reminder_by_code CODE=R015 | head -1 | cut -d'|' -f1)

# resolve the subject id by its code:
#   bug         → get_bug_by_code      CODE=B040  | head -1 | cut -d'|' -f1   → link_bug         BUG_ID=…
#   decision    → get_decision_by_code CODE=D012  | head -1 | cut -d'|' -f1   → link_decision    DECISION_ID=…
#   next_target → get_target_by_id     ID=<n>     | head -1 | cut -d'|' -f1   → link_next_target NEXT_TARGET_ID=…
BUG_ID=$(bash dev/run-dev-query.sh get_bug_by_code CODE=B040 | head -1 | cut -d'|' -f1)

bash dev/run-dev-query.sh link_bug \
  SOURCE_TABLE=reminders SOURCE_ID=$R_ID POSITION=0 \
  BUG_ID=$BUG_ID RELATION=relates
```

The link verb names the TARGET kind; `SOURCE_TABLE=reminders SOURCE_ID=$R_ID` names the reminder. `RELATION=relates` is the generic predicate (a reminder doesn't `produce`/`raise`/`supersede` its subject — it just concerns it). If the reminder is a genuinely subject-less time-tick (e.g. "ping me at the start of next month"), skip this and **say so** in your report.

> `next_targets` has no `get_target_by_code`; resolve by its row id with `get_target_by_id ID=<n>`.

### 3b — Arm a watchdog (when the trigger is mechanically checkable)

If the trigger is a **wall-clock time**, a **log signal**, or a **query that returns rows iff the condition is met**, attach a structured `watchdog_spec` JSON so it does not get forgotten. The spec travels with the record (atomic — survives resolve/dismiss).

```bash
# watchdog_spec shape:
#   trigger:  wall_clock | log_signal | query
#   target:   ISO ts (wall_clock) | logfile path (log_signal) | query-id (query)
#   pattern:  regex (log_signal only)
#   runner:   the poller template that checks the trigger
#   executor: tmux | cron | systemd | loop  — PROJECT'S CHOICE; this skill does not wire it
#   alarm:    what to do on fire (e.g. notify+marker)
SPEC='{"trigger":"wall_clock","target":"2026-07-01T00:00:00Z","runner":"dev/watchdogs/re_arm_runner.sh","executor":"loop","alarm":"notify+marker"}'
bash dev/run-dev-query.sh set_watchdog_spec CODE=R015 WATCHDOG_SPEC="$SPEC"

# confirm it is now an armed reminder:
bash dev/run-dev-query.sh with_watchdog
```

Inspect a single spec with `get_watchdog_spec CODE=R015`. The session-start protocol re-arms armed reminders and picks up fired markers — that is **not** this skill's job. Pure-judgment triggers (not mechanically checkable) carry **no** spec; do NOT invent a fake checkable trigger just to attach one.

When a watchdog actually fires, the executor (or you) stamps the marker via `set_watchdog_fired CODE=R015 DATE=$(date +%F)`; `clear_watchdog_fired CODE=R015` resets it if re-armed.

## Step 4 — Resolve an existing reminder

Locate it first, take the action, then mark resolved:

```bash
bash dev/run-dev-query.sh get_reminder_by_code CODE=R001
# … perform the triggered ACTION …
bash dev/run-dev-query.sh resolve_reminder \
  CODE=R001 \
  RESOLUTION='Restart cycle ran; watchdog_fired_at persisted; B040 fix re-verified.' \
  DATE=$(date +%F)
```

If the reminder is no longer relevant (won't fire, superseded), dismiss instead — never silently drop it:

```bash
bash dev/run-dev-query.sh dismiss_reminder \
  CODE=R005 \
  RESOLUTION='Superseded by R007 — adaptive backpressure replaces the manual tuning trigger.' \
  DATE=$(date +%F)
```

## Step 5 — Update trigger or action mid-flight

If the trigger condition changes (e.g. threshold tightened):

```bash
bash dev/run-dev-query.sh update_reminder_trigger \
  CODE=R002 \
  TRIGGER_WHEN='outcomes_distinct_days >= 10 OR first distill rule written'
```

Same pattern for `update_reminder_action ... ACTION='…'`.

## Constraints

- **Never silently drop a reminder.** If a trigger never fires or becomes irrelevant, dismiss it explicitly with a "no longer needed because X" note.
- **Triggers must be observable** — a date, a metric threshold, the completion of a tracked task. Vague "later" / "eventually" doesn't belong here.
- **Wire the subject** via a TYPED `refs` edge (`RELATION=relates`) — an untyped node-edge bypasses the graph's cycle-guard. Only a genuinely subject-less time-tick is edge-less, and then say so.
- **The watchdog executor is the project's choice** — this skill only writes the `watchdog_spec` JSON. Do not hardcode tmux/cron/systemd/loop machinery.
- Status values: `active`, `resolved`, `dismissed`.
- **Scope tag is mandatory** and must not contain `v_X.Y` (use `[v3.0]`, `[DEV]`, `[DEV+v3.0]`).
- **Never edit `documentation.db` directly.** All writes go through `dev/run-dev-query.sh` with named query-ids.

---

*© {{PROJECT_NAME}} Dev | dev-reminder*
