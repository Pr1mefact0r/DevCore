"""DevDash — read-only browser view of dev/documentation.db.

Run:
  DEVCORE_DB=/path/to/dev/documentation.db uvicorn main:app --host 127.0.0.1 --port 8765

Falls DEVCORE_DB is unset, defaults to ../dev/documentation.db relative to this file.
"""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

try:
    from . import db as ddb  # uvicorn devdash.main:app  (run from project root)
except ImportError:
    import db as ddb  # uvicorn main:app  (run from devdash/ directory)

# Resolve module location whichever way uvicorn imports us.
HERE = Path(__file__).resolve().parent
templates = Jinja2Templates(directory=str(HERE / "templates"))

app = FastAPI(title="DevDash", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=str(HERE / "static")), name="static")

PROJECT_NAME = os.environ.get("DEVCORE_PROJECT_NAME", "Project")


@app.middleware("http")
async def no_cache(request: Request, call_next):
    # Brain views are live state — never let a browser freeze a stale page.
    resp = await call_next(request)
    resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    return resp


def _ctx(request: Request, **extra) -> dict:
    base = {
        "request": request,
        "project_name": PROJECT_NAME,
        "nav": [
            ("/", "Dashboard"),
            ("/decisions", "Decisions"),
            ("/bugs", "Bugs"),
            ("/changelog", "Changelog"),
            ("/observations", "Observations"),
            ("/targets", "Targets"),
        ],
    }
    base.update(extra)
    return base


@app.get("/", response_class=HTMLResponse)
def dashboard(request: Request):
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        _ctx(
            request,
            stats=ddb.dashboard_stats(),
            recent_decisions=ddb.recent_decisions(),
            open_bugs=ddb.open_bugs()[:10],
            top_targets=ddb.top_targets(8),
            recent_changelog=ddb.changelog()[:10],
        ),
    )


@app.get("/decisions", response_class=HTMLResponse)
def decisions(request: Request, scope: str | None = Query(default=None)):
    scope_like = f"%{scope}%" if scope else None
    return templates.TemplateResponse(
        request,
        "decisions.html",
        _ctx(request, rows=ddb.all_decisions(scope_like), scope=scope or ""),
    )


@app.get("/bugs", response_class=HTMLResponse)
def bugs(request: Request, status: str | None = Query(default=None)):
    return templates.TemplateResponse(
        request,
        "bugs.html",
        _ctx(request, rows=ddb.all_bugs(status), status=status or ""),
    )


@app.get("/changelog", response_class=HTMLResponse)
def changelog(request: Request, version: str | None = Query(default=None)):
    return templates.TemplateResponse(
        request,
        "changelog.html",
        _ctx(request, rows=ddb.changelog(version), version=version or ""),
    )


@app.get("/observations", response_class=HTMLResponse)
def observations(request: Request, active: int = Query(default=0)):
    return templates.TemplateResponse(
        request,
        "observations.html",
        _ctx(request, rows=ddb.observations(only_active=bool(active)), active=active),
    )


@app.get("/targets", response_class=HTMLResponse)
def targets(request: Request, status: str | None = Query(default=None)):
    return templates.TemplateResponse(
        request,
        "targets.html",
        _ctx(request, rows=ddb.targets(status), status=status or ""),
    )


# ---- v3.0 brain-graph views ------------------------------------------------

@app.get("/reminders", response_class=HTMLResponse)
def reminders(request: Request, active: int = Query(default=0)):
    return templates.TemplateResponse(
        request,
        "dev_reminders.html",
        _ctx(request, rows=ddb.reminders(only_active=bool(active)),
             counts=ddb.reminder_status_counts(), active=active),
    )


@app.get("/projectrules", response_class=HTMLResponse)
def projectrules(request: Request, active: int = Query(default=0)):
    return templates.TemplateResponse(
        request,
        "dev_projectrules.html",
        _ctx(request, rows=ddb.projectrules(only_active=bool(active)),
             counts=ddb.projectrule_status_counts(), active=active),
    )


@app.get("/adjudications", response_class=HTMLResponse)
def adjudications(request: Request, scope: str | None = Query(default=None)):
    scope_like = f"%{scope}%" if scope else None
    return templates.TemplateResponse(
        request,
        "dev_adjudications.html",
        _ctx(request, rows=ddb.all_adjudications(scope_like),
             scopes=ddb.adjudication_scopes(), scope=scope or ""),
    )


@app.get("/resolutions", response_class=HTMLResponse)
def resolutions(request: Request, scope: str | None = Query(default=None)):
    scope_like = f"%{scope}%" if scope else None
    return templates.TemplateResponse(
        request,
        "dev_resolutions.html",
        _ctx(request, rows=ddb.all_resolutions(scope_like),
             scopes=ddb.resolution_scopes(), scope=scope or ""),
    )


@app.get("/investigations", response_class=HTMLResponse)
def investigations(request: Request):
    return templates.TemplateResponse(
        request, "dev_investigations.html",
        _ctx(request, rows=ddb.all_investigations()),
    )


@app.get("/ideas", response_class=HTMLResponse)
def ideas(request: Request):
    return templates.TemplateResponse(
        request, "dev_ideas.html",
        _ctx(request, rows=ddb.all_ideas()),
    )


@app.get("/recognition-keys", response_class=HTMLResponse)
def recognition_keys(request: Request):
    return templates.TemplateResponse(
        request, "dev_recognition_keys.html",
        _ctx(request, clusters=ddb.recognition_clusters()),
    )


@app.get("/health", response_class=HTMLResponse)
def health(request: Request):
    return templates.TemplateResponse(
        request, "dev_health.html",
        _ctx(request, rows=ddb.health_findings()),
    )


@app.get("/graph", response_class=HTMLResponse)
def graph(request: Request, focus: str | None = Query(default=None)):
    return templates.TemplateResponse(
        request, "dev_graph.html",
        _ctx(request, graph=ddb.graph_data(focus), focus=focus or ""),
    )


@app.get("/graph/node")
def graph_node(code: str = Query(...)):
    detail = ddb.graph_node_detail(code)
    if not detail:
        return JSONResponse({"error": "not found", "code": code}, status_code=404)
    return JSONResponse(detail)
