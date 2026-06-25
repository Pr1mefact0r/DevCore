# DevDash

Read-only browser view of `dev/documentation.db`. Built with FastAPI + Jinja2.
No auth — bind to `127.0.0.1` only and access via Twingate / SSH tunnel if needed.

## Run

```bash
cd devdash
pip install -r requirements.txt

# DB-Pfad via env (Default: ../dev/documentation.db relativ zur main.py)
DEVCORE_DB=$(pwd)/../dev/documentation.db \
DEVCORE_PROJECT_NAME="MyProject" \
uvicorn main:app --host 127.0.0.1 --port 8765
```

Endpunkte:

| Pfad | Inhalt |
|---|---|
| `/` | Dashboard: Stats, Top Targets, Open Bugs, Recent Decisions, Recent Changelog |
| `/decisions?scope=DEV` | Decisions, optional gefiltert nach Scope-Substring |
| `/bugs?status=open` | Bugs, optional nach Status (`open`/`fixed`/`wontfix`) |
| `/changelog?version=v0.1` | Changelog, optional nach Version |
| `/observations?active=1` | Observations, optional nur `watching`/`monitoring` |
| `/targets?status=open` | Targets, optional nach Status |
| `/reminders?active=1` | Reminders (R###) + Watchdog-Status |
| `/projectrules?active=1` | Projectrules (PR###) — die Disziplin-Schicht |
| `/adjudications?scope=DEV` | Adjudications (Q###) — gesettelte Fakten + evidence |
| `/resolutions?scope=DEV` | Resolutions (RS###) — wiederverwendbare Präzedenzfälle |
| `/investigations` | Investigations (I###) — der Prozess Frage→Antwort |
| `/ideas` | Ideas (IDEA###) — noch-nicht-entschiedene Gedanken |
| `/recognition-keys` | Recognition-Keys + ihre Q/RS/I/IDEA-Cluster |
| `/health` | Staleness/Revalidation der Answer-Nodes |
| `/graph` (`?focus=Q001`) | Brain-Graph-Explorer (Canvas, Ego-Fokus) |
| `/graph/node?code=Q001` | Narrative-Card eines Knotens (JSON) |

## Optional: systemd-User-Service

`~/.config/systemd/user/devdash-{{PROJECT_NAME}}.service`:

```ini
[Unit]
Description=DevDash — {{PROJECT_NAME}}
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/ClaudeCode/{{PROJECT_NAME}}-Dev/devdash
Environment="DEVCORE_DB=%h/ClaudeCode/{{PROJECT_NAME}}-Dev/dev/documentation.db"
Environment="DEVCORE_PROJECT_NAME={{PROJECT_NAME}}"
ExecStart=%h/.local/bin/uvicorn main:app --host 127.0.0.1 --port 8765
Restart=on-failure

[Install]
WantedBy=default.target
```

Aktivieren: `systemctl --user enable --now devdash-{{PROJECT_NAME}}.service`.

**Port-Konvention:**

| Projekt | Port |
|---|---|
| ProjectA-Dev | 8765 |
| ProjectB-Dev | 8766 |
| ProjectC-Dev | 8767 |
| DevCore-Dev | 8768 |
