#!/usr/bin/env bash
# ============================================================
# graph-reconcile.sh — PostToolUse(Edit|Write|MultiEdit) recall+reconcile surfacer (PR024/PR029)
# ============================================================
# When code / a query / the schema / a skill is edited, surface live brain nodes whose
# subject is that file's stem — open next_targets or watching observations — so the change
# is reconciled in the SAME pass (implemented NT → done, obsoleted finding → resolve/supersede).
#
# NON-BLOCKING: exit 2 surfaces only. Quiet when out of scope, short stem, already surfaced
# this session, or nothing live matches. Per-session-per-file dedup via a /tmp marker.
#
# Contract: stdin JSON { tool_name, tool_input.file_path, session_id }.
# ============================================================

set -u
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

J() { printf '%s' "$input" | jq -r "$1 // \"\"" 2>/dev/null; }

case "$(J '.tool_name')" in Edit|Write|MultiEdit) : ;; *) exit 0 ;; esac
fp=$(J '.tool_input.file_path'); [ -z "$fp" ] && exit 0
sid=$(J '.session_id'); [ -z "$sid" ] && sid="nosession"

# scope: only framework-relevant artifacts
case "$fp" in
  *dev/dev-queries/*.sql|*dev/schema.sql|*dev/run-dev-query.sh|*dev/migrate_md_to_sqlite.py|*/.claude/skills/*|*/.claude/hooks/*|*devdash/*) : ;;
  *) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0
[ -x dev/run-dev-query.sh ] || exit 0

stem=$(basename "$fp"); stem="${stem%.*}"
[ "${#stem}" -ge 5 ] || exit 0     # too short = noisy

# per-session-per-file dedup
mark_dir="/tmp/devcore-graph-reconcile/${sid}"
cks=$(printf '%s' "$fp" | cksum | cut -d' ' -f1)
mark="${mark_dir}/${cks}"
[ -f "$mark" ] && exit 0

# live nodes mentioning the stem (case-insensitive grep over the open/active lists)
targets=$(bash dev/run-dev-query.sh get_open_targets 2>/dev/null | grep -iF "$stem" | head -5)
obs=$(bash dev/run-dev-query.sh get_active_observations 2>/dev/null | grep -iF "$stem" | head -5)

if [ -z "$targets" ] && [ -z "$obs" ]; then
    exit 0   # nothing live → no marker, so a later edit re-checks
fi

mkdir -p "$mark_dir" 2>/dev/null && : > "$mark"
{
  echo "[graph-reconcile] '$stem' edited — live brain nodes on this subject (PR024 recall-before / PR029 reconcile-after):"
  [ -n "$targets" ] && { echo ">>> open next_targets:"; printf '%s\n' "$targets" | sed 's/^/>>>   /'; }
  [ -n "$obs" ]     && { echo ">>> watching observations:"; printf '%s\n' "$obs" | sed 's/^/>>>   /'; }
  echo ">>> Reconcile in THIS change: implemented target → complete_target; obsoleted observation →"
  echo ">>> resolve/supersede; stale edge → re-wire. Don't leave the graph contradicting the code."
} >&2
exit 2
