#!/usr/bin/env bash
# DevCore v3.0 — run-dev-query.sh
#
# Single entry point for ALL dev-layer DB operations.
# Usage:
#   bash dev/run-dev-query.sh <query-id> [KEY=VALUE ...]
#
# Examples:
#   bash dev/run-dev-query.sh next_decision_code
#   bash dev/run-dev-query.sh insert_decision DATE=2026-05-09 CODE=D001 SCOPE='[DEV]' TITLE='...' DECISION='...' RATIONALE='...'
#
# Conventions:
#   - Queries live in dev/dev-queries/*.sql, named with `-- @id: <name>` markers.
#   - Parameter placeholders use $KEY syntax inside SQL strings (we substitute and
#     SQL-escape single quotes).
#   - PreToolUse hook (optional) can enforce that all dev-layer writes go through here.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <query-id> [KEY=VALUE ...]" >&2
  exit 64
fi

QUERY_ID="$1"; shift

HERE="$(cd "$(dirname "$0")" && pwd)"
DB="${DEVCORE_DB:-$HERE/documentation.db}"
QUERIES_DIR="$HERE/dev-queries"
SCHEMA="$HERE/schema.sql"

# Bootstrap DB from schema on first use
if [ ! -f "$DB" ]; then
  if [ -f "$SCHEMA" ]; then
    sqlite3 "$DB" < "$SCHEMA" >/dev/null   # suppress the WAL pragma echo on first bootstrap
    # apply one-time seeds (e.g. projectrules core-set) after the schema
    for seed in "$HERE"/seeds/*.sql; do
      [ -f "$seed" ] && sqlite3 "$DB" < "$seed" >/dev/null 2>&1
    done
  else
    echo "ERR: $DB missing and no schema.sql at $SCHEMA" >&2
    exit 1
  fi
fi

if [ ! -d "$QUERIES_DIR" ]; then
  echo "ERR: dev-queries dir missing at $QUERIES_DIR" >&2
  exit 1
fi

# Locate query block by @id marker
SQL=""
for f in "$QUERIES_DIR"/*.sql; do
  [ -f "$f" ] || continue
  block=$(awk -v target="$QUERY_ID" '
    BEGIN { capturing = 0 }
    /^-- @id:[[:space:]]/ {
      sub(/^-- @id:[[:space:]]+/, "", $0)
      if ($0 == target) { capturing = 1 } else { capturing = 0 }
      next
    }
    /^-- @end/ { capturing = 0; next }
    capturing { print }
  ' "$f")
  if [ -n "$block" ]; then
    SQL="$block"
    break
  fi
done

if [ -z "$SQL" ]; then
  echo "ERR: query-id '$QUERY_ID' not found in $QUERIES_DIR/*.sql" >&2
  exit 2
fi

# Parameter substitution. Each $NAME placeholder is replaced with its passed value
# (single quotes SQL-escaped), or empty string if not passed. Done in ONE token-greedy
# awk pass: the regex matches the FULL identifier, so $EVIDENCE never partial-matches
# inside $EVIDENCE_DATA — correct regardless of arg order or which params are omitted.
# Params are handed to awk via DEVQ_<KEY> env vars (binary/newline-safe; no text roundtrip).
for kv in "$@"; do
  case "$kv" in
    *=*) export "DEVQ_${kv%%=*}=${kv#*=}" ;;
    *)   echo "WARN: ignoring arg without '=' sign: $kv" >&2 ;;
  esac
done

SQL="$(printf '%s' "$SQL" | awk -v q="'" -v qq="''" '
  {
    line = $0; out = ""
    while (match(line, /\$[A-Za-z_][A-Za-z0-9_]*/)) {
      name = substr(line, RSTART + 1, RLENGTH - 1)
      val  = ENVIRON["DEVQ_" name]            # unset -> "" (placeholder becomes empty)
      gsub(q, qq, val)                         # SQL-escape single quotes: '"'"' -> '"''"'
      out  = out substr(line, 1, RSTART - 1) val
      line = substr(line, RSTART + RLENGTH)
    }
    print out line
  }
')"

# Execute
sqlite3 -bail "$DB" <<EOF
$SQL
EOF
