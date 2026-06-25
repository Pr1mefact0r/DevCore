#!/usr/bin/env bash
# ============================================================
# query-consumer-gate.sh — PostToolUse(Edit|Write|MultiEdit) shared-query consumer check (PR018)
# ============================================================
# When a dev/dev-queries/*.sql file is edited, list every consumer of its query-ids
# (skills + dashboard) so a shape change (renamed/removed columns or @id) can't silently
# break a reader. Surfaces the consumers; the author proves none breaks (additive /
# shape-preserving, or harden the consumer to named columns first).
#
# NON-BLOCKING: exit 2 surfaces only. Quiet when the edited file is not a query file.
# Pure grep over the source tree — no DB access.
#
# Contract: stdin JSON { tool_name, tool_input.file_path }.
# ============================================================

set -u
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

J() { printf '%s' "$input" | jq -r "$1 // \"\"" 2>/dev/null; }

case "$(J '.tool_name')" in Edit|Write|MultiEdit) : ;; *) exit 0 ;; esac
fp=$(J '.tool_input.file_path'); [ -z "$fp" ] && exit 0
case "$fp" in *dev/dev-queries/*.sql) : ;; *) exit 0 ;; esac

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0
[ -f "$fp" ] || exit 0

# query-ids defined in the edited file
ids=$(grep -oE '^-- @id:[[:space:]]+\S+' "$fp" | sed -E 's/^-- @id:[[:space:]]+//' | sort -u)
[ -z "$ids" ] && exit 0

emitted=0
out=""
for id in $ids; do
    hits=$(grep -rlE "run-dev-query\.sh[[:space:]]+${id}\b|[\"']${id}[\"']" \
             .claude/skills devdash 2>/dev/null | sort -u | tr '\n' ' ')
    if [ -n "${hits// }" ]; then
        out="${out}>>>   ${id}  ←  ${hits}\n"
        emitted=1
    fi
done

[ "$emitted" -eq 0 ] && exit 0

{
  echo "[query-consumer-gate] $(basename "$fp") edited — consumers of its query-ids (PR018 shape-break risk):"
  printf '%b' "$out"
  echo ">>> Prove none breaks: keep the change additive / shape-preserving, or harden each consumer to"
  echo ">>> named columns first. A positional read (cut -f1 / head -1) breaks silently on a column shift."
} >&2
exit 2
