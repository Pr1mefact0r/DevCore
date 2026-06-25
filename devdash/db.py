"""Read-only SQLite access for DevDash."""

from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path


def db_path() -> Path:
    """Resolve the documentation.db path.

    Prefer DEVCORE_DB env var, fall back to ../dev/documentation.db.
    """
    env = os.environ.get("DEVCORE_DB")
    if env:
        return Path(env).resolve()
    return (Path(__file__).resolve().parent.parent / "dev" / "documentation.db").resolve()


@contextmanager
def connect():
    p = db_path()
    if not p.exists():
        raise FileNotFoundError(
            f"documentation.db not found at {p}. Set DEVCORE_DB env var or run "
            f"`bash dev/run-dev-query.sh count_decisions` to bootstrap it."
        )
    # Read-only URI mode
    uri = f"file:{p}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def fetch_all(sql: str, params: tuple = ()) -> list[sqlite3.Row]:
    with connect() as conn:
        return conn.execute(sql, params).fetchall()


def fetch_one(sql: str, params: tuple = ()) -> sqlite3.Row | None:
    with connect() as conn:
        return conn.execute(sql, params).fetchone()


def scalar(sql: str, params: tuple = ()) -> int:
    row = fetch_one(sql, params)
    if row is None:
        return 0
    return list(row)[0] or 0


# ---------- domain helpers ----------

def dashboard_stats() -> dict:
    return {
        "open_bugs": scalar("SELECT COUNT(*) FROM bugs WHERE status='open'"),
        "fixed_bugs": scalar("SELECT COUNT(*) FROM bugs WHERE status='fixed'"),
        "open_targets": scalar("SELECT COUNT(*) FROM next_targets WHERE status IN ('open','in_progress')"),
        "done_targets": scalar("SELECT COUNT(*) FROM next_targets WHERE status='done'"),
        "active_observations": scalar(
            "SELECT COUNT(*) FROM observations WHERE status IN ('watching','fix_deployed_monitoring')"
        ),
        "decisions": scalar("SELECT COUNT(*) FROM decisions"),
        "changelog_entries": scalar("SELECT COUNT(*) FROM changelog"),
        # v3.0 brain-graph nodes
        "adjudications": scalar("SELECT COUNT(*) FROM adjudications"),
        "resolutions": scalar("SELECT COUNT(*) FROM resolutions"),
        "investigations": scalar("SELECT COUNT(*) FROM investigations WHERE status='open'"),
        "ideas": scalar("SELECT COUNT(*) FROM ideas WHERE status='idea'"),
        "active_reminders": scalar("SELECT COUNT(*) FROM reminders WHERE status='active'"),
        "projectrules": scalar("SELECT COUNT(*) FROM projectrules WHERE status='active'"),
    }


def recent_decisions(limit: int = 10):
    return fetch_all(
        "SELECT code, date, scope, title FROM decisions ORDER BY date DESC, code DESC LIMIT ?",
        (limit,),
    )


def open_bugs():
    return fetch_all(
        """
        SELECT code, date, scope, severity, title, fix
        FROM bugs WHERE status='open'
        ORDER BY
          CASE severity WHEN 'critical' THEN 1 WHEN 'behavioral' THEN 2
                        WHEN 'edge_case' THEN 3 WHEN 'minor' THEN 4 ELSE 5 END,
          date DESC
        """
    )


def all_bugs(status: str | None = None):
    if status:
        return fetch_all(
            "SELECT code, date, scope, severity, status, title, fix FROM bugs WHERE status=? ORDER BY date DESC",
            (status,),
        )
    return fetch_all("SELECT code, date, scope, severity, status, title, fix FROM bugs ORDER BY date DESC")


def all_decisions(scope_like: str | None = None):
    if scope_like:
        return fetch_all(
            "SELECT code, date, scope, title, decision, rationale FROM decisions WHERE scope LIKE ? ORDER BY date DESC, code DESC",
            (scope_like,),
        )
    return fetch_all(
        "SELECT code, date, scope, title, decision, rationale FROM decisions ORDER BY date DESC, code DESC"
    )


def changelog(version: str | None = None):
    if version:
        return fetch_all(
            "SELECT date, version, scope, title, summary FROM changelog WHERE version=? ORDER BY date DESC",
            (version,),
        )
    return fetch_all("SELECT date, version, scope, title, summary FROM changelog ORDER BY date DESC, id DESC")


def observations(only_active: bool = False):
    if only_active:
        return fetch_all(
            "SELECT code, date, scope, status, title, watch_for FROM observations WHERE status IN ('watching','fix_deployed_monitoring') ORDER BY date DESC"
        )
    return fetch_all("SELECT code, date, scope, status, title, watch_for, resolution FROM observations ORDER BY date DESC")


def targets(status: str | None = None):
    if status:
        return fetch_all(
            "SELECT id, code, date, scope, status, priority, title FROM next_targets WHERE status=? ORDER BY priority ASC, id ASC",
            (status,),
        )
    return fetch_all(
        "SELECT id, code, date, scope, status, priority, title FROM next_targets ORDER BY priority ASC, id ASC"
    )


def top_targets(limit: int = 5):
    return fetch_all(
        "SELECT id, code, scope, priority, title FROM next_targets WHERE status IN ('open','in_progress') ORDER BY priority ASC, id ASC LIMIT ?",
        (limit,),
    )


# ---------- reminders / projectrules (v3.0 node tables) ----------

def reminders(only_active: bool = False):
    if only_active:
        return fetch_all(
            "SELECT code, date, scope, status, title, trigger_when, action "
            "FROM reminders WHERE status='active' ORDER BY date DESC"
        )
    return fetch_all(
        "SELECT code, date, scope, status, title, trigger_when, action, "
        "resolution, resolved_at "
        "FROM reminders "
        "ORDER BY (status='active') DESC, date DESC"
    )


def reminder_status_counts() -> dict:
    rows = fetch_all("SELECT status, COUNT(*) AS n FROM reminders GROUP BY status")
    return {r["status"]: r["n"] for r in rows}


def active_reminders(limit: int = 5):
    return fetch_all(
        "SELECT code, scope, title, trigger_when FROM reminders "
        "WHERE status='active' ORDER BY date DESC LIMIT ?",
        (limit,),
    )


def projectrules(only_active: bool = False):
    if only_active:
        return fetch_all(
            "SELECT code, date, scope, title, rule, rationale, source_ref "
            "FROM projectrules WHERE status='active' ORDER BY code ASC"
        )
    return fetch_all(
        "SELECT code, date, scope, status, title, rule, rationale, source_ref, retired_at "
        "FROM projectrules "
        "ORDER BY (status='active') DESC, code ASC"
    )


def projectrule_status_counts() -> dict:
    rows = fetch_all("SELECT status, COUNT(*) AS n FROM projectrules GROUP BY status")
    return {r["status"]: r["n"] for r in rows}


# ============================================================
# Brain-graph views (D063 backport): adjudications / resolutions /
# investigations / ideas / recognition-key clusters / health / ego-graph.
# All SELECT-only.
# ============================================================

def all_adjudications(scope_like: str | None = None):
    base = (
        "SELECT code, date, scope, title, question, verdict, evidence, "
        "recognition_key, as_of, validity, status, superseded_by, "
        "last_revalidated, revalidation_query FROM adjudications "
    )
    if scope_like:
        return fetch_all(base + "WHERE scope LIKE ? ORDER BY id DESC", (scope_like,))
    return fetch_all(base + "ORDER BY id DESC")


def adjudication_scopes() -> list[str]:
    rows = fetch_all(
        "SELECT scope, COUNT(*) AS n FROM adjudications "
        "GROUP BY scope ORDER BY n DESC, scope ASC"
    )
    return [r["scope"] for r in rows]


def all_resolutions(scope_like: str | None = None):
    base = (
        "SELECT code, date, scope, title, problem, resolution, outcome, reuse, "
        "recognition_key, as_of, validity, status, superseded_by, last_revalidated "
        "FROM resolutions "
    )
    if scope_like:
        return fetch_all(base + "WHERE scope LIKE ? ORDER BY id DESC", (scope_like,))
    return fetch_all(base + "ORDER BY id DESC")


def resolution_scopes() -> list[str]:
    rows = fetch_all(
        "SELECT scope, COUNT(*) AS n FROM resolutions "
        "GROUP BY scope ORDER BY n DESC, scope ASC"
    )
    return [r["scope"] for r in rows]


def all_investigations():
    return fetch_all(
        "SELECT code, date, scope, title, question, method, findings, "
        "recognition_key, status, superseded_by, as_of FROM investigations "
        "ORDER BY id DESC"
    )


def all_ideas():
    return fetch_all(
        "SELECT code, date, scope, title, body, rationale, "
        "recognition_key, status, promoted_to, superseded_by, as_of FROM ideas "
        "ORDER BY id DESC"
    )


def recognition_clusters() -> list[dict]:
    """Key-centric cluster view: each recognition_key with its member findings
    (Q/RS/I/IDEA) across node-types."""
    keys = fetch_all(
        "SELECT key, text, definition, first_seen, created_by "
        "FROM recognition_keys ORDER BY first_seen DESC, key ASC"
    )
    members = fetch_all(
        "SELECT recognition_key AS key, code, 'Q'    AS kind, title, status FROM adjudications  WHERE recognition_key IS NOT NULL "
        "UNION ALL "
        "SELECT recognition_key, code, 'RS'   AS kind, title, status FROM resolutions    WHERE recognition_key IS NOT NULL "
        "UNION ALL "
        "SELECT recognition_key, code, 'I'    AS kind, title, status FROM investigations WHERE recognition_key IS NOT NULL "
        "UNION ALL "
        "SELECT recognition_key, code, 'IDEA' AS kind, title, status FROM ideas          WHERE recognition_key IS NOT NULL "
    )
    by_key: dict[str, list] = {}
    for m in members:
        by_key.setdefault(m["key"], []).append(dict(m))
    out = []
    for k in keys:
        d = dict(k)
        d["members"] = by_key.get(k["key"], [])
        out.append(d)
    return out


def health_findings():
    """Staleness/revalidation health view: findings that NEED attention surfaced
    first — status not settled/concluded first, then oldest-touched. age_days via
    julianday(CURRENT_DATE) - julianday(as_of), guarding NULL/blank as_of."""
    return fetch_all(
        """
        SELECT kind, code, title, scope, status, as_of, last_revalidated, validity,
               revalidation_query,
               CASE WHEN NULLIF(as_of,'') IS NOT NULL
                    THEN CAST(julianday(CURRENT_DATE) - julianday(as_of) AS INTEGER)
                    ELSE NULL END AS age_days
        FROM (
          SELECT 'Q'  AS kind, code, title, scope, status, as_of, last_revalidated, validity, revalidation_query FROM adjudications
          UNION ALL
          SELECT 'RS' AS kind, code, title, scope, status, as_of, last_revalidated, validity, NULL FROM resolutions
          UNION ALL
          SELECT 'I'  AS kind, code, title, scope, status, as_of, NULL,             NULL,     NULL FROM investigations
        ) x
        ORDER BY (status NOT IN ('settled','concluded')) DESC, age_days DESC, code
        """
    )


def graph_node_counts() -> dict:
    """Counts for the dev sub-nav badges on the brain-graph tabs."""
    return {
        "adjudications":    scalar("SELECT COUNT(*) FROM adjudications"),
        "resolutions":      scalar("SELECT COUNT(*) FROM resolutions"),
        "investigations":   scalar("SELECT COUNT(*) FROM investigations"),
        "ideas":            scalar("SELECT COUNT(*) FROM ideas"),
        "recognition_keys": scalar("SELECT COUNT(*) FROM recognition_keys"),
    }


# ---- ego-graph data (Graph tab) --------------------------------------------
# refs encodes TYPED DIRECTED edges: source=(source_table,source_id), target=the
# single *_id column selected by ref_kind, predicate=relation. Resolve both ends
# to ### codes and tag each edge with its relation-CLASS for color-coding.

_GRAPH_KIND = {
    "adjudications": "Q", "resolutions": "RS", "investigations": "I",
    "bugs": "B", "decisions": "D", "observations": "W", "next_targets": "NT",
    "projectrules": "PR", "reminders": "R", "changelog": "CL",
    "ideas": "IDEA",
}
_REFKIND_TARGET = {
    "decision": ("decisions", "decision_id"), "bug": ("bugs", "bug_id"),
    "observation": ("observations", "observation_id"), "reminder": ("reminders", "reminder_id"),
    "projectrule": ("projectrules", "projectrule_id"), "next_target": ("next_targets", "next_target_id"),
    "adjudication": ("adjudications", "adjudication_id"), "resolution": ("resolutions", "resolution_id"),
    "investigation": ("investigations", "investigation_id"), "idea": ("ideas", "idea_id"),
}
_PROVENANCE = {"raised", "investigates", "produced", "crystallized", "answers"}
_LINEAGE = {"supersedes"}
_STRUCTURAL = {"documents", "references"}


def _relation_class(rel: str) -> str:
    if rel in _PROVENANCE:
        return "provenance"
    if rel in _LINEAGE:
        return "lineage"
    if rel in _STRUCTURAL:
        return "structural"
    return "lateral"


def _code_maps() -> dict:
    """id -> (code, title, status) per node table. decisions has no status column;
    changelog has neither code (uses CL<id>) nor status."""
    maps: dict[str, dict] = {}
    for tbl in ("bugs", "observations", "reminders", "projectrules",
                "next_targets", "adjudications", "resolutions", "investigations", "ideas"):
        maps[tbl] = {
            r["id"]: (r["code"], r["title"], r["status"])
            for r in fetch_all(f"SELECT id, code, title, status FROM {tbl}")
        }
    maps["decisions"] = {
        r["id"]: (r["code"], r["title"], None)
        for r in fetch_all("SELECT id, code, title FROM decisions")
    }
    maps["changelog"] = {
        r["id"]: (f"CL{r['id']}", r["title"], None)
        for r in fetch_all("SELECT id, title FROM changelog")
    }
    return maps


def graph_data(focus: str | None = None) -> dict:
    """Whole brain-graph as code-level directed edges + nodes. Includes BOTH typed
    edges (provenance|lineage|lateral|structural) AND untyped legacy refs
    (relation NULL -> class 'ref'). Codeless next_targets rows carry no code and
    are silently absent (not graph-addressable)."""
    maps = _code_maps()
    refs = fetch_all(
        "SELECT source_table, source_id, relation, ref_kind, decision_id, bug_id, "
        "observation_id, reminder_id, projectrule_id, next_target_id, "
        "adjudication_id, resolution_id, investigation_id, idea_id FROM refs"
    )
    nodes: dict[str, dict] = {}

    def add(table, code, title, status):
        if code and code not in nodes:
            nodes[code] = {"id": code, "kind": _GRAPH_KIND.get(table, "?"),
                           "title": title or "", "status": status}

    edges = []
    typed_count = 0
    for r in refs:
        smap = maps.get(r["source_table"], {})
        if r["source_id"] not in smap:
            continue
        scode, stitle, sstatus = smap[r["source_id"]]
        tgt = _REFKIND_TARGET.get(r["ref_kind"])
        if not tgt:
            continue
        ttable, idcol = tgt
        tid = r[idcol]
        tmap = maps.get(ttable, {})
        if tid not in tmap:
            continue
        tcode, ttitle, tstatus = tmap[tid]
        if not scode or not tcode:        # a codeless endpoint -> not graph-addressable
            continue
        add(r["source_table"], scode, stitle, sstatus)
        add(ttable, tcode, ttitle, tstatus)
        rel = r["relation"] or "ref"
        cls = "ref" if not r["relation"] else _relation_class(r["relation"])
        if r["relation"]:
            typed_count += 1
        edges.append({"a": scode, "b": tcode, "rel": rel, "cls": cls})
    return {
        "nodes": list(nodes.values()),
        "edges": edges,
        "node_count": len(nodes),
        "edge_count": len(edges),
        "typed_count": typed_count,
        "focus": focus,
    }


# per-node-type field shape for the narrative card.
_DETAIL_SHAPE = {
    "adjudications": ("Q",  "code,title,question,verdict,evidence,recognition_key,status,as_of,validity,revalidation_query"),
    "resolutions":   ("RS", "code,title,problem,resolution,outcome,reuse,recognition_key,status,as_of,validity"),
    "investigations":("I",  "code,title,question,method,findings,recognition_key,status,as_of"),
    "decisions":     ("D",  "code,title,decision,rationale,scope"),
    "bugs":          ("B",  "code,title,description,fix,severity,status"),
    "observations":  ("W",  "code,title,description,watch_for,status"),
    "next_targets":  ("NT", "code,title,description,priority,status"),
    "projectrules": ("PR", "code,title,rule,rationale,status"),
    "reminders":     ("R",  "code,title,action,trigger_when,status"),
    "ideas":         ("IDEA", "code,title,body,rationale,status,promoted_to"),
}


def _table_for_code(code: str) -> str | None:
    # order matters: IDEA before I, RS before R, NT/PR/CL before single-letter prefixes
    if code.startswith("IDEA"): return "ideas"
    if code.startswith("NT"):   return "next_targets"
    if code.startswith("RS"):   return "resolutions"
    if code.startswith("PR"):   return "projectrules"
    if code.startswith("CL"):   return "changelog"
    if code.startswith("Q"):    return "adjudications"
    if code.startswith("D"):    return "decisions"
    if code.startswith("B"):    return "bugs"
    if code.startswith("W"):    return "observations"
    if code.startswith("I"):    return "investigations"
    if code.startswith("R"):    return "reminders"
    return None


def graph_node_detail(code: str) -> dict | None:
    """Type-specific content for one node (the narrative card)."""
    tbl = _table_for_code(code)
    if tbl is None:
        return None
    if tbl == "changelog":
        try:
            cid = int(code[2:])
        except ValueError:
            return None
        row = fetch_one("SELECT title, summary, root_cause, solution FROM changelog WHERE id=?", (cid,))
        if not row:
            return None
        return {"code": code, "kind": "CL", "title": row["title"], "status": None,
                "as_of": None, "validity": None, "fields": dict(row)}
    kind, cols = _DETAIL_SHAPE[tbl]
    row = fetch_one(f"SELECT {cols} FROM {tbl} WHERE code=?", (code,))
    if not row:
        return None
    d = dict(row)
    return {"code": code, "kind": kind, "title": d.get("title"),
            "status": d.get("status"), "as_of": d.get("as_of"),
            "validity": d.get("validity"), "fields": d}
