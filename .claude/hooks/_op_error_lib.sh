# ============================================================
# _op_error_lib.sh — shared op-error capture helper (NT-082)
# ============================================================
# Sourced by both capture points:
#   - .claude/hooks/op-error-capture.sh  (PostToolUse Bash: NONZERO_EXIT / OUTPUT_ERROR)
#   - .claude/hooks/enforce-runquery.sh  (PreToolUse block path: ENFORCE_BLOCK)
# One mechanism. Single-process SQLite: there is NO role isolation (no `guard` role) —
# write-isolation is n/a; the helper inserts directly via dev/run-dev-query.sh capture_raw.
# PASSIVE: a capture failure must NEVER affect the hook's own exit, so every path ends in
# `|| true` and is silenced.

op_error_capture() {
    # args: tool error_class exit_code signal_text query_id cmd_excerpt cwd session_id
    local root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    local w="$root/dev/run-dev-query.sh"
    [ -x "$w" ] || return 0
    bash "$w" capture_raw \
        TOOL="${1:-}" ERROR_CLASS="${2:-}" EXIT_CODE="${3:-}" SIGNAL_TEXT="${4:-}" \
        QUERY_ID="${5:-}" CMD_EXCERPT="${6:-}" CWD="${7:-}" SESSION_ID="${8:-}" \
        >/dev/null 2>&1 || true
    return 0
}
