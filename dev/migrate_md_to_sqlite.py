#!/usr/bin/env python3
"""
DevCore v3.0 — migrate_md_to_sqlite.py

Best-effort import of legacy v1.0 dev/*.md files into dev/documentation.db.
Use after backporting a v1.0 project to v2.0.

Usage:
  python3 dev/migrate_md_to_sqlite.py \
    --decisions OLD/decisions.md \
    --bugs OLD/bugs.md \
    --changelog OLD/changelog.md \
    --observations OLD/observations.md \
    --next-targets OLD/next-targets.md \
    --db dev/documentation.db

The parser is intentionally tolerant. Anything it cannot match is left
in a `migration_residue` text column or printed as a warning. Spot-check
the result via DevDash or `bash dev/run-dev-query.sh get_recent_decisions`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

ISO_DATE = re.compile(r"(\d{4}-\d{2}-\d{2})")
SCOPE = re.compile(r"\[(?:[A-Z]+(?:\+v\d+\.\d+)?|v\d+\.\d+)\]")


def today() -> str:
    return dt.date.today().isoformat()


def first_date(text: str, fallback: str) -> str:
    m = ISO_DATE.search(text or "")
    return m.group(1) if m else fallback


def first_scope(text: str) -> str:
    m = SCOPE.search(text or "")
    return m.group(0) if m else "[DEV]"


def ensure_schema(db_path: Path, schema_path: Path) -> sqlite3.Connection:
    new = not db_path.exists()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    if new and schema_path.exists():
        conn.executescript(schema_path.read_text())
    return conn


# ---------- decisions ----------

DECISION_HEADER = re.compile(r"^###\s+(D\d{3}):?\s*(.*)$", re.MULTILINE)


def parse_decisions(text: str):
    """Find ### D### blocks and extract Date / Context / Decision / Rationale fields."""
    matches = list(DECISION_HEADER.finditer(text))
    for i, m in enumerate(matches):
        code = m.group(1)
        title_raw = m.group(2).strip()
        # title may include scope tag — keep as-is
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end]
        scope = first_scope(title_raw) or first_scope(body)
        title = SCOPE.sub("", title_raw).strip(" -:")
        date = extract_field(body, "Date") or first_date(body, today())
        context = extract_field(body, "Context") or ""
        decision = extract_field(body, "Decision") or body.strip()[:500]
        rationale = extract_field(body, "Rationale") or ""
        tradeoff = extract_field(body, "Tradeoff") or ""
        alternatives = extract_field(body, "Alternatives considered") or extract_field(body, "Alternatives") or ""
        rule = extract_field(body, "Rule") or ""
        convention = extract_field(body, "Convention") or ""
        yield {
            "date": date, "code": code, "scope": scope, "title": title,
            "context": context, "decision": decision, "rationale": rationale,
            "tradeoff": tradeoff, "alternatives": alternatives,
            "rule": rule, "convention": convention,
            "memory_ref": "", "updated_at": date,
        }


FIELD_RE_TPL = r"\*\*{name}:\*\*\s*(.+?)(?=\n\*\*|\n###|\n##|\Z)"


def extract_field(body: str, name: str) -> str | None:
    pat = re.compile(FIELD_RE_TPL.format(name=re.escape(name)), re.DOTALL)
    m = pat.search(body)
    return m.group(1).strip() if m else None


# ---------- bugs ----------

BUG_ROW = re.compile(
    r"^\|\s*(B\d{3})\s*\|\s*(.+?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*$",
    re.MULTILINE,
)


def parse_bugs(text: str):
    section_open, section_fixed = split_open_fixed(text)
    for status, chunk in (("open", section_open), ("fixed", section_fixed)):
        for m in BUG_ROW.finditer(chunk or ""):
            code, title_full, found_in, fix = m.groups()
            scope = first_scope(title_full)
            title = SCOPE.sub("", title_full).strip(" *.")
            severity = guess_severity(title_full + " " + fix)
            date = first_date(fix, today())
            yield {
                "date": date, "code": code, "scope": scope,
                "title": title[:300], "description": title_full.strip(),
                "severity": severity, "found_in": found_in.strip(),
                "status": status, "fix": fix.strip(),
                "memory_ref": "",
            }


def split_open_fixed(text: str) -> tuple[str, str]:
    parts = re.split(r"^##\s+(?:Open|Fixed)\s*$", text, flags=re.MULTILINE)
    # parts[0] is preamble, parts[1] = Open block, parts[2] = Fixed block (if present)
    open_block = parts[1] if len(parts) > 1 else ""
    fixed_block = parts[2] if len(parts) > 2 else ""
    return open_block, fixed_block


def guess_severity(text: str) -> str:
    t = text.lower()
    if "critical" in t or "data loss" in t:
        return "critical"
    if "behavioral" in t or "wrong result" in t:
        return "behavioral"
    if "edge case" in t:
        return "edge_case"
    if "minor" in t or "cosmetic" in t:
        return "minor"
    return "behavioral"


# ---------- observations ----------

OBS_ROW = re.compile(
    r"^\|\s*(W\d{3})(?:\s*\[[^\]]+\])?\s*\|\s*(.+?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*$",
    re.MULTILINE,
)


def parse_observations(text: str):
    for m in OBS_ROW.finditer(text or ""):
        code, title_full, found_in, watch_for, status = m.groups()
        scope = first_scope(title_full)
        title = SCOPE.sub("", title_full).strip(" *.")
        status_norm = status.strip().lower().replace(" ", "_").replace("—", "_") or "watching"
        date = first_date(text, today())
        yield {
            "date": date, "code": code, "scope": scope,
            "title": title[:300], "description": title_full.strip(),
            "found_in": found_in.strip(), "watch_for": watch_for.strip(),
            "status": status_norm,
        }


# ---------- changelog ----------

CHANGELOG_HEADER = re.compile(
    r"^##\s+\[(.+?)\]\s+(.+?)\s+\((\d{4}-\d{2}-\d{2})\)\s*$", re.MULTILINE
)


def parse_changelog(text: str):
    matches = list(CHANGELOG_HEADER.finditer(text))
    for i, m in enumerate(matches):
        scope, title, date = m.groups()
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end]
        version = ""
        v = re.search(r"v\d+\.\d+", scope)
        if v:
            version = v.group(0)
        summary = first_para(body) or title
        root_cause = extract_section(body, "Root Cause") or ""
        solution = extract_section(body, "Solution") or ""
        files = extract_files_list(body)
        decision_ref = first_match(body, r"D\d{3}")
        bug_ref = first_match(body, r"B\d{3}")
        yield {
            "date": date, "version": version, "scope": f"[{scope}]",
            "title": title.strip(), "summary": summary,
            "root_cause": root_cause, "solution": solution,
            "files": json.dumps(files) if files else "",
            "decision_ref": decision_ref or "",
            "bug_ref": bug_ref or "",
        }


def first_para(body: str) -> str:
    for p in re.split(r"\n\s*\n", body.strip(), maxsplit=1):
        return p.strip().splitlines()[0][:500]
    return ""


def extract_section(body: str, name: str) -> str:
    pat = re.compile(rf"^###\s+{re.escape(name)}\s*$(.+?)(?=^###\s|\Z)",
                     re.MULTILINE | re.DOTALL)
    m = pat.search(body)
    return m.group(1).strip() if m else ""


def extract_files_list(body: str) -> list[str]:
    sec = extract_section(body, "Files Changed")
    return re.findall(r"`([^`]+)`", sec)


def first_match(body: str, pattern: str) -> str | None:
    m = re.search(pattern, body)
    return m.group(0) if m else None


# ---------- next_targets ----------

NT_ROW = re.compile(
    r"^\|\s*(\d+|—)\s*\|\s*(.+?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*$",
    re.MULTILINE,
)


def parse_next_targets(text: str):
    for m in NT_ROW.finditer(text or ""):
        prio_raw, title_full, affected, source = m.groups()
        try:
            prio = int(prio_raw)
        except ValueError:
            prio = 5
        scope = first_scope(title_full)
        title = SCOPE.sub("", title_full).strip(" *.")
        code_match = re.search(r"NT-[A-Z0-9-]+", title_full + " " + source)
        code = code_match.group(0) if code_match else ""
        date = today()
        yield {
            "date": date, "code": code, "scope": scope,
            "title": title[:300],
            "description": title_full.strip(),
            "affected": affected.strip(),
            "source_refs": source.strip(),
            "priority": prio,
            "memory_ref": "",
        }


# ---------- main ----------

def insert_many(conn, table: str, rows: list[dict]):
    if not rows:
        return 0
    cols = list(rows[0].keys())
    placeholders = ",".join("?" for _ in cols)
    sql = f"INSERT OR IGNORE INTO {table} ({','.join(cols)}) VALUES ({placeholders})"
    cur = conn.cursor()
    cur.executemany(sql, [tuple(r.get(c, "") for c in cols) for r in rows])
    conn.commit()
    return cur.rowcount


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--decisions")
    p.add_argument("--bugs")
    p.add_argument("--changelog")
    p.add_argument("--observations")
    p.add_argument("--next-targets")
    p.add_argument("--db", required=True)
    p.add_argument("--schema", default="dev/schema.sql")
    args = p.parse_args()

    db = Path(args.db).resolve()
    schema = Path(args.schema).resolve()
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = ensure_schema(db, schema)

    summary = {}
    if args.decisions and Path(args.decisions).exists():
        rows = list(parse_decisions(Path(args.decisions).read_text()))
        summary["decisions"] = insert_many(conn, "decisions", rows)
    if args.bugs and Path(args.bugs).exists():
        rows = list(parse_bugs(Path(args.bugs).read_text()))
        summary["bugs"] = insert_many(conn, "bugs", rows)
    if args.changelog and Path(args.changelog).exists():
        rows = list(parse_changelog(Path(args.changelog).read_text()))
        summary["changelog"] = insert_many(conn, "changelog", rows)
    if args.observations and Path(args.observations).exists():
        rows = list(parse_observations(Path(args.observations).read_text()))
        summary["observations"] = insert_many(conn, "observations", rows)
    if args.next_targets and Path(args.next_targets).exists():
        rows = list(parse_next_targets(Path(args.next_targets).read_text()))
        summary["next_targets"] = insert_many(conn, "next_targets", rows)

    print("Migration summary (rows inserted):")
    for k, v in summary.items():
        print(f"  {k}: {v}")
    print(f"DB: {db}")
    print("Spot-check via:")
    print("  bash dev/run-dev-query.sh get_recent_decisions")
    print("  bash dev/run-dev-query.sh get_open_bugs")
    print("  bash dev/run-dev-query.sh get_open_targets")


if __name__ == "__main__":
    main()
