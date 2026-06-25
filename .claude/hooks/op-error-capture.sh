#!/usr/bin/env bash
# ============================================================
# op-error-capture.sh — PostToolUse(Bash) passive op-error capture (NT-082)
# ============================================================
# Logs mechanically-detected Bash failures to the flat sink op_error_raw via
# dev/run-dev-query.sh (single-role; no isolation). NO node, NO recognition_key,
# NO promotion — pure capture, tuned later on real data.
#
# PASSIVE by contract: ALWAYS exit 0, never emit stdout/stderr, never interfere.
# Mechanical detection only (no LLM):
#   - exit_code != 0        -> NONZERO_EXIT  (authoritative)
#   - else ERROR: in output -> OUTPUT_ERROR  (tooling error printed on exit 0)
# (ENFORCE_BLOCK is captured separately by enforce-runquery.sh.)
#
# Contract: stdin JSON { tool_name, exit_code, session_id, cwd,
#                        tool_input.command, tool_response{.text} }.
# ============================================================

set -u

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=/dev/null
source "$ROOT/.claude/hooks/_op_error_lib.sh" 2>/dev/null || exit 0

J() {
    local field="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -r "$field // \"\"" 2>/dev/null
    fi
}

[ "$(J '.tool_name')" = "Bash" ] || exit 0

exit_code=$(J '.exit_code')
[[ "$exit_code" =~ ^-?[0-9]+$ ]] || exit_code=""    # only a real integer survives
session=$(J '.session_id')
cwd=$(J '.cwd')
cmd=$(J '.tool_input.command')
resp=$(J '.tool_response.text'); [ -z "$resp" ] && resp=$(J '.tool_response')

class=""; signal=""
if [ -n "$exit_code" ] && [ "$exit_code" != "0" ]; then
    class="NONZERO_EXIT"; signal="exit $exit_code"
elif printf '%s' "$resp" | grep -qE '(^|[^A-Za-z_])ERROR:'; then
    class="OUTPUT_ERROR"
    signal=$(printf '%s' "$resp" | grep -oE 'ERROR:.*' | head -1)
fi
[ -z "$class" ] && exit 0   # no detectable failure -> silent pass

# Structural granularity: the flat query-id, when this was a run-dev-query.sh call.
qid=$(printf '%s' "$cmd" \
    | grep -oE 'run-dev-query\.sh[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    | head -1 | sed -E 's/.*\.sh[[:space:]]+//' || true)

exc=$(printf '%s' "$cmd"    | tr '\n\t' '  ' | cut -c1-240)
sig=$(printf '%s' "$signal" | tr '\n\t' '  ' | cut -c1-240)

op_error_capture "Bash" "$class" "$exit_code" "$sig" "$qid" "$exc" "$cwd" "$session"
exit 0
