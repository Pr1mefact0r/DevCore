#!/usr/bin/env bash
# ============================================================
# session-start.sh — SessionStart hook (brain load + receipt)
# ============================================================
# Injects a TINY imperative (JSON additionalContext) telling the agent to load its active
# project rules + watchdogs FROM THE BRAIN at session start, visibly in the console (the
# query tool-calls are the operator's proof of load), and to open with a receipt line.
# Rules are NOT inlined (they grow past the SessionStart cap and would truncate) — the agent
# reads them fresh via the named queries. Read-only. Exits 0 always.
#
# Contract: stdin JSON (drained, unused). stdout: JSON { hookSpecificOutput.additionalContext }.
# ============================================================
set -u
cat >/dev/null 2>&1 || true          # drain SessionStart stdin (unused)

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -x "$ROOT/dev/run-dev-query.sh" ] || exit 0   # not a DevCore project root → no-op

if command -v python3 >/dev/null 2>&1; then
python3 -c '
import json
ctx = (
 "\U0001F6D1 {{PROJECT_NAME}} DEV — SESSION-START. MANDATORY FIRST ACTIONS, before you answer the user:\n\n"
 "1. Load your active project rules — your FIRST tool call (run it, do not recite from memory):\n"
 "   bash dev/run-dev-query.sh get_active_projectrules\n"
 "2. Re-arm / surface watchdogs:\n"
 "   bash dev/run-dev-query.sh with_watchdog\n"
 "   For each returned reminder: if watchdog_fired_at is set -> surface it + handle the action;\n"
 "   else re-arm it from watchdog_spec via the project executor (tmux/cron/systemd/loop — your choice).\n"
 "3. Open your reply with the receipt: ✅ <N> PRs + <M> watchdogs loaded\n\n"
 "Running these queries IS how your binding context loads, and the operator watches the console for them "
 "as the PROOF of load. The rules are read fresh from the brain, never assumed."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
'
fi

echo "[session-start] {{PROJECT_NAME}} dev: run get_active_projectrules + with_watchdog, then open with the '✅ N PRs + M watchdogs loaded' receipt (console = proof of load)." >&2
exit 0
