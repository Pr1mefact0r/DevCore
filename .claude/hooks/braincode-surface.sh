#!/usr/bin/env bash
# ============================================================
# braincode-surface.sh — PostToolUse(Read) windowed-read brain-code surfacer (PR026)
# ============================================================
# After a WINDOWED Read (offset>0) of a source file, re-read the enclosing region and
# surface any brain-codes (D###/B###/W###/NT###/PR###/Q###/RS###/I###/IDEA###/R###/CL#)
# the window may have skipped. They are POINTERS: resolve each via get_*_by_code →
# edges_from / walk_neighborhood and read current state; never trust the aging comment.
# An unresolvable code is itself a finding.
#
# NON-BLOCKING: exit 2 only surfaces (read already ran). Quiet on full reads, wrong file
# types, or no codes. Pure sed/grep — no DB access.
#
# Contract: stdin JSON { tool_name, tool_input.file_path/offset/limit }.
# ============================================================

set -u
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

J() { printf '%s' "$input" | jq -r "$1 // \"\"" 2>/dev/null; }

[ "$(J '.tool_name')" = "Read" ] || exit 0
fp=$(J '.tool_input.file_path');   [ -z "$fp" ] && exit 0
offset=$(J '.tool_input.offset');  [[ "$offset" =~ ^[0-9]+$ ]] || exit 0
[ "$offset" -gt 0 ] || exit 0      # full read → no blind spot
limit=$(J '.tool_input.limit');    [[ "$limit" =~ ^[0-9]+$ ]] || limit=2000
[ -f "$fp" ] || exit 0

# only source-ish files; skip generated / transient / vendored
case "$fp" in
  *.py|*.sql|*.sh|*SKILL.md|*.md|*.yaml|*.yml) : ;;
  *) exit 0 ;;
esac
case "$fp" in
  */check/*|*/memory/*|*/logs/*|*/tool-results/*|*/.claude/projects/*|*/node_modules/*|*/.venv/*) exit 0 ;;
esac

LOOKBACK=12
start=$(( offset - LOOKBACK )); [ "$start" -lt 1 ] && start=1
end=$(( offset + limit - 1 ))

region=$(sed -n "${start},${end}p" "$fp" 2>/dev/null)
[ -z "$region" ] && exit 0

codes=$(printf '%s' "$region" \
    | grep -oE '\b(IDEA[0-9]{3}|NT[0-9]{3}|RS[0-9]{3}|PR[0-9]{3}|Q[0-9]{3}|D[0-9]{3}|B[0-9]{3}|W[0-9]{3}|I[0-9]{3}|R[0-9]{3}|CL[0-9]+)\b' \
    | sort -u | head -8 | tr '\n' ' ')
[ -z "${codes// }" ] && exit 0

{
  echo "[braincode-surface] windowed read of $(basename "$fp") — brain-codes in the enclosing region:"
  echo ">>>   $codes"
  echo ">>> These are POINTERS, not truth. Resolve each: get_*_by_code → edges_from / walk_neighborhood,"
  echo ">>> read current status. An unresolvable code is itself a finding (stale comment)."
} >&2
exit 2
