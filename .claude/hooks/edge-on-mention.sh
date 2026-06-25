#!/usr/bin/env bash
# ============================================================
# edge-on-mention.sh — PostToolUse(Bash) write-time edge guard (PR019 step 5)
# ============================================================
# Closes the silent-edge-omission class: a node minted without typed refs is born
# unreachable from its root. Fires AFTER a node-mint (insert_*) and, if no edges were
# wired in the SAME command, surfaces the codes mentioned in the body as candidate
# typed edges + a wire-or-declare-standalone reminder. Mechanical (no LLM).
#
# NON-BLOCKING: the insert already ran. exit 2 only SURFACES to the model (stderr →
# context). Quiet (exit 0) when edges are already wired in the same command, or nothing
# was minted, or the only mint is a fresh idea (genesis-root, legitimately edge-less).
#
# Contract: stdin JSON { tool_name, tool_input.command }.
# ============================================================

set -u

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

J() {
    local field="$1"
    command -v jq >/dev/null 2>&1 && printf '%s' "$input" | jq -r "$field // \"\"" 2>/dev/null
}

[ "$(J '.tool_name')" = "Bash" ] || exit 0
cmd=$(J '.tool_input.command')
[ -z "$cmd" ] && exit 0

# Only act on a node-mint.
node=$(printf '%s' "$cmd" | grep -oE 'insert_(bug|decision|observation|target|adjudication|resolution|investigation|idea|changelog|reminder|projectrule)' | head -1)
[ -z "$node" ] && exit 0

# Already wiring edges in the SAME command? -> author is on it, stay quiet.
if printf '%s' "$cmd" | grep -qE '\blink_[a-z_]+'; then
    exit 0
fi

case "$node" in
  insert_bug)            tbl=bugs ;;
  insert_decision)       tbl=decisions ;;
  insert_observation)    tbl=observations ;;
  insert_target)         tbl=next_targets ;;
  insert_adjudication)   tbl=adjudications ;;
  insert_resolution)     tbl=resolutions ;;
  insert_investigation)  tbl=investigations ;;
  insert_idea)           tbl=ideas ;;
  insert_changelog)      tbl=changelog ;;
  insert_reminder)       tbl=reminders ;;
  insert_projectrule)   tbl=projectrules ;;
  *) exit 0 ;;
esac

# The minted node's OWN code (CODE=... arg) — exclude it. D-K1: no hyphen.
# Order longest/specific prefixes first so the full token is captured.
own=$(printf '%s' "$cmd" | grep -oE 'CODE=(IDEA[0-9]{3}|NT[0-9]{3}|RS[0-9]{3}|PR[0-9]{3}|[A-Z][0-9]{3})' | head -1 | cut -d= -f2)

# Parse ###-code mentions in the body. Exclude own + dedupe.
mentions=$(printf '%s' "$cmd" \
    | grep -oE '\b(IDEA[0-9]{3}|NT[0-9]{3}|RS[0-9]{3}|PR[0-9]{3}|Q[0-9]{3}|D[0-9]{3}|B[0-9]{3}|W[0-9]{3}|I[0-9]{3}|R[0-9]{3}|CL[0-9]+)\b' \
    | grep -vxF "${own:-__none__}" | sort -u | tr '\n' ' ')

{
  echo "[edge-on-mention] $tbl node minted${own:+ ($own)} — PR019 step 5: wire TYPED refs edges (link_<kind> with a RELATION)."
  if [ -n "${mentions// }" ]; then
    echo ">>> Mentioned codes, not yet wired (resolve ids via get_*_by_code, then link_<kind>):"
    self="${own:-this}"
    for m in $mentions; do
      case "$tbl|$m" in
        changelog\|*)      echo ">>>   $self --documents--> $m   (changelog documents the change to $m)";;
        *\|D[0-9]*)        echo ">>>   $m --informs--> $self     (upstream: the decision informs this)";;
        *\|PR[0-9]*)       echo ">>>   $self --relates--> $m     (lateral: relates to the rule)";;
        investigations\|Q[0-9]*|investigations\|RS[0-9]*)
                           echo ">>>   $self --produced--> $m    (the investigation produced this answer)";;
        adjudications\|I[0-9]*|resolutions\|I[0-9]*)
                           echo ">>>   $m --produced--> $self     (upstream: the investigation produced this)";;
        ideas\|*)          echo ">>>   $self --relates--> $m     (idea is a genesis-root; lateral relates; promotion uses crystallized + promote_idea)";;
        *)                 echo ">>>   $self --relates--> $m     (default lateral; pick the precise predicate)";;
      esac
    done
    echo ">>> ONE directed edge per relationship — never reciprocal. Same-type supersession = superseded_by COLUMN, not an edge."
  else
    echo ">>> No ###-codes in the body. Wire its ROOT (the node it stems from), or state it is standalone."
    [ "$tbl" = ideas ] && echo ">>> (A brand-new idea may legitimately be edge-less — the one node-type where that is normal.)"
  fi
} >&2
exit 2
