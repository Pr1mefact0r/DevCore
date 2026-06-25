#!/usr/bin/env bash
# ============================================================
# enforce-runquery.sh — PreToolUse(Bash) write-path guard (D004-class)
# ============================================================
# Prevents ad-hoc sqlite3 writes that bypass the canonical write path
# (dev/run-dev-query.sh) AND touch the committed dev memory (documentation.db).
# Read-only SELECTs and sandbox DBs under dev/db/ are fine.
#
# Whitelist (always allow):
#   * any command invoking dev/run-dev-query.sh
#   * the migration helper (migrate_md_to_sqlite.py)
# Block trigger (exit 2):
#   * `sqlite3` in the command, AND a write keyword, AND it targets `documentation.db`
#
# Contract: stdin JSON { tool_name, tool_input.command, session_id, cwd }.
#   exit 0 — allow (default) ;  exit 2 — block, stderr explains why.
# ============================================================

set -u

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

J() {
    local field="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -r "$field // \"\""
    else
        printf '%s' "$input" | sed -n "s/.*\"command\":[[:space:]]*\"\\(.*\\)\".*/\\1/p" | head -1
    fi
}

[ "$(J '.tool_name')" = "Bash" ] || exit 0
cmd=$(J '.tool_input.command')
[ -z "$cmd" ] && exit 0
session=$(J '.session_id')
cwd=$(J '.cwd')

# --- Whitelist: canonical write path + migration helper ---
if printf '%s' "$cmd" | grep -qE '(^|[^A-Za-z0-9_/-])run-dev-query\.sh\b'; then
    exit 0
fi
if printf '%s' "$cmd" | grep -qE 'migrate_md_to_sqlite\.py\b'; then
    exit 0
fi

# --- Block: sqlite3 + write keyword + documentation.db ---
if printf '%s' "$cmd" | grep -qE '\bsqlite3\b' \
   && printf '%s' "$cmd" | grep -q 'documentation\.db'; then
    if printf '%s' "$cmd" | grep -qiE '\b(insert[[:space:]]+into|replace[[:space:]]+into|update[[:space:]]+[A-Za-z_]+[[:space:]]+set|delete[[:space:]]+from|drop[[:space:]]+(table|index|trigger|view)|alter[[:space:]]+table|create[[:space:]]+(table|index|trigger|view))\b'; then
        cat >&2 <<'MSG'
[enforce-runquery] BLOCKED: direct sqlite3 write to documentation.db detected.

Dev-memory writes must go through `bash dev/run-dev-query.sh <query-id> [KEY=VALUE]`.
Read-only SELECTs are fine. Throwaway sandbox DBs under dev/db/ are fine. Schema/query
changes go in dev/schema.sql + dev/dev-queries/*.sql, never inline.
MSG
        # Passively capture the block (ENFORCE_BLOCK): a blocked PreToolUse means
        # PostToolUse never fires. The capture never affects the exit (stays 2).
        ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
        if source "$ROOT/.claude/hooks/_op_error_lib.sh" 2>/dev/null; then
            exc=$(printf '%s' "$cmd" | tr '\n\t' '  ' | cut -c1-240)
            op_error_capture "Bash" "ENFORCE_BLOCK" "" "direct sqlite3 write to documentation.db blocked" "" "$exc" "$cwd" "$session"
        fi
        exit 2
    fi
fi

exit 0
