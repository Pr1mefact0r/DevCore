-- DevCore v3.0 — documentation.db schema  (brain-graph schema)
-- One DB per project. Committed to git (this is the dev memory).
-- Test/sandbox DBs live in dev/db/ (gitignored).
--
-- v3.0 turns the flat 5-table store into a relational brain-graph:
--   * refs            — polymorphic, typed, directed edges (replaces freetext source_refs)
--   * recognition_keys — canonical recall signatures (reuse-before-mint)
--   * 6 node types     — adjudications(Q) resolutions(RS) investigations(I) ideas(IDEA)
--                        reminders(R) projectrules(PR)
--   * lifecycle columns on decisions/next_targets/observations (superseded_by + monotonic guard)
--   * op_error_raw     — passive bash-error capture sink (single-process, no role isolation)
--
-- Code convention (D-K1): NO hyphen, zero-padded 3 digits — D### B### W### R### PR### Q### RS### I### IDEA### NT###.
-- All persisted free-text is English; technical identifiers English.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ============================================================================
-- BASE TABLES (carried from v2.0; freetext refs removed, lifecycle columns added)
-- ============================================================================

CREATE TABLE IF NOT EXISTS decisions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    date            TEXT    NOT NULL,                -- ISO 8601
    code            TEXT    NOT NULL UNIQUE,         -- "D001"
    scope           TEXT    NOT NULL,                -- "[v0.1]", "[DEV]", "[DEV+v0.1]"
    title           TEXT    NOT NULL,
    context         TEXT,
    decision        TEXT    NOT NULL,
    rationale       TEXT,
    tradeoff        TEXT,
    alternatives    TEXT,
    rule            TEXT,
    convention      TEXT,
    memory_ref      TEXT,                            -- "memory_file_4" or NULL
    updated_at      TEXT,
    -- lifecycle (B059/NT-092): supersession via column, acyclic by monotonic CHECK
    superseded_by   INTEGER REFERENCES decisions(id),
    reopened_reason TEXT,
    reaffirmed_at   TEXT,
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

CREATE TABLE IF NOT EXISTS bugs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    date        TEXT    NOT NULL,
    code        TEXT    NOT NULL UNIQUE,          -- "B001"
    scope       TEXT    NOT NULL,
    title       TEXT    NOT NULL,
    description TEXT,
    severity    TEXT,                             -- "critical" | "behavioral" | "edge_case" | "minor"
    found_in    TEXT,
    status      TEXT    NOT NULL DEFAULT 'open',  -- "open" | "fixed" | "wontfix"
    fix         TEXT,
    fixed_at    TEXT,
    memory_ref  TEXT
);

CREATE TABLE IF NOT EXISTS changelog (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    date         TEXT    NOT NULL,
    version      TEXT,                            -- "v0.1" or NULL for [DEV]-only
    scope        TEXT    NOT NULL,
    title        TEXT    NOT NULL,
    summary      TEXT    NOT NULL,
    root_cause   TEXT,
    solution     TEXT,
    files        TEXT                             -- JSON array of paths
    -- v3.0: decision_ref / bug_ref freetext columns removed → use refs edges
    --       (source_table='changelog' --documents/relates--> node)
);

CREATE TABLE IF NOT EXISTS observations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    date            TEXT    NOT NULL,
    code            TEXT    NOT NULL UNIQUE,          -- "W001"
    scope           TEXT    NOT NULL,
    title           TEXT    NOT NULL,
    description     TEXT,
    found_in        TEXT,
    watch_for       TEXT,
    status          TEXT    NOT NULL DEFAULT 'watching',  -- "watching" | "fix_deployed_monitoring" | "resolved" | "false_alarm"
    resolution      TEXT,
    resolved_at     TEXT,
    -- lifecycle (B059/NT-092)
    superseded_by   INTEGER REFERENCES observations(id),
    reopened_reason TEXT,
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

CREATE TABLE IF NOT EXISTS next_targets (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    date            TEXT    NOT NULL,
    code            TEXT,                             -- optional "NT001" or NULL (scope lives in `scope`)
    scope           TEXT    NOT NULL,
    title           TEXT    NOT NULL,
    description     TEXT,
    affected        TEXT,                             -- which skills/files
    priority        INTEGER NOT NULL DEFAULT 5,       -- lower = higher priority
    status          TEXT    NOT NULL DEFAULT 'open',  -- "open" | "in_progress" | "done" | "superseded"
    done_at         TEXT,
    memory_ref      TEXT,
    -- v3.0: source_refs freetext column removed → use refs edges
    -- lifecycle (B059/NT-092)
    superseded_by   INTEGER REFERENCES next_targets(id),
    reopened_reason TEXT,
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

-- ============================================================================
-- recognition_keys — canonical recall signatures (natural PK, UPPER_SNAKE)
-- ============================================================================

CREATE TABLE IF NOT EXISTS recognition_keys (
    key        TEXT PRIMARY KEY,
    text       TEXT NOT NULL,
    definition TEXT,
    first_seen TEXT,
    created_by TEXT,
    -- ~ '^[A-Z][A-Z0-9_]+$'  ≈ starts uppercase, only A-Z0-9_ thereafter (min-length 2 enforced app-level)
    CHECK (key GLOB '[A-Z]*' AND key NOT GLOB '*[^A-Z0-9_]*')
);

-- ============================================================================
-- NODE TABLES (the brain-graph answer/process/intent nodes)
-- ============================================================================

-- adjudications Q### — a query/data-settled FACT
CREATE TABLE IF NOT EXISTS adjudications (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    date                TEXT NOT NULL,
    code                TEXT NOT NULL UNIQUE,            -- "Q001"
    scope               TEXT NOT NULL,
    title               TEXT NOT NULL,
    question            TEXT NOT NULL,
    verdict             TEXT NOT NULL,
    evidence            TEXT,
    evidence_data       TEXT,                            -- JSON string (the actual settling data)
    recognition_key     TEXT REFERENCES recognition_keys(key),
    recognition_text    TEXT,
    as_of               TEXT NOT NULL,
    validity            TEXT,
    revalidation_query  TEXT,
    revalidation_params TEXT,                            -- JSON string
    status              TEXT NOT NULL DEFAULT 'settled'
                          CHECK (status IN ('settled','stale','reopened','superseded')),
    superseded_by       INTEGER REFERENCES adjudications(id),
    last_revalidated    TEXT,
    reopened_reason     TEXT,
    resolved_at         TEXT,
    CHECK (scope NOT GLOB '*v_[0-9]*'),
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

-- resolutions RS### — a reusable "how we solved it" precedent
CREATE TABLE IF NOT EXISTS resolutions (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    date             TEXT NOT NULL,
    code             TEXT NOT NULL UNIQUE,            -- "RS001"
    scope            TEXT NOT NULL,
    title            TEXT NOT NULL,
    problem          TEXT NOT NULL,
    resolution       TEXT NOT NULL,
    outcome          TEXT,
    reuse            TEXT,                            -- what makes it a precedent (never empty in practice)
    source           TEXT CHECK (source IS NULL OR source IN ('dialog','sentinel','review','investigation','other')),
    recognition_key  TEXT REFERENCES recognition_keys(key),
    recognition_text TEXT,
    as_of            TEXT NOT NULL,
    validity         TEXT,
    status           TEXT NOT NULL DEFAULT 'settled'
                       CHECK (status IN ('settled','stale','reopened','superseded')),
    superseded_by    INTEGER REFERENCES resolutions(id),
    last_revalidated TEXT,
    reopened_reason  TEXT,
    resolved_at      TEXT,
    CHECK (scope NOT GLOB '*v_[0-9]*'),
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

-- investigations I### — the PROCESS between a question and its settled answer
CREATE TABLE IF NOT EXISTS investigations (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    date             TEXT NOT NULL,
    code             TEXT NOT NULL UNIQUE,            -- "I001"
    scope            TEXT NOT NULL,
    title            TEXT NOT NULL,
    question         TEXT NOT NULL,
    method           TEXT,
    findings         TEXT,
    recognition_key  TEXT REFERENCES recognition_keys(key),
    recognition_text TEXT,
    status           TEXT NOT NULL DEFAULT 'open'
                       CHECK (status IN ('open','concluded','abandoned','superseded')),
    superseded_by    INTEGER REFERENCES investigations(id),
    as_of            TEXT,                            -- nullable (unlike Q/RS)
    resolved_at      TEXT,
    CHECK (scope NOT GLOB '*v_[0-9]*'),
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

-- ideas IDEA### — a raw, not-yet-decided thought (genesis-root; may be edge-less)
CREATE TABLE IF NOT EXISTS ideas (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    date             TEXT NOT NULL,
    code             TEXT NOT NULL UNIQUE,            -- "IDEA001"
    scope            TEXT NOT NULL,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    rationale        TEXT,
    recognition_key  TEXT REFERENCES recognition_keys(key),
    recognition_text TEXT,
    status           TEXT NOT NULL DEFAULT 'idea'
                       CHECK (status IN ('idea','promoted','dropped','superseded')),
    promoted_to      TEXT,                            -- note of the D###/NT###/Q### (the typed edge is the truth)
    superseded_by    INTEGER REFERENCES ideas(id),
    as_of            TEXT,                            -- nullable
    resolved_at      TEXT,
    CHECK (scope NOT GLOB '*v_[0-9]*'),
    CHECK (superseded_by IS NULL OR superseded_by > id)
);

-- reminders R### — conditional/time-bound "do X when Y"; optional brain-anchored watchdog
CREATE TABLE IF NOT EXISTS reminders (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    date              TEXT NOT NULL,
    code              TEXT NOT NULL UNIQUE,           -- "R001"
    scope             TEXT NOT NULL,
    title             TEXT NOT NULL,
    trigger_when      TEXT NOT NULL,                  -- the future condition that fires it
    action            TEXT NOT NULL,                  -- what to do when it fires
    status            TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','resolved','dismissed')),
    resolution        TEXT,
    resolved_at       TEXT,
    memory_ref        TEXT,
    watchdog_spec     TEXT,                           -- JSON string (PR017)
    watchdog_fired_at TEXT,                           -- ISO 8601 or NULL
    CHECK (scope NOT GLOB '*v_[0-9]*')
);

-- projectrules PR### — the discipline layer
CREATE TABLE IF NOT EXISTS projectrules (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    date        TEXT NOT NULL,
    code        TEXT NOT NULL UNIQUE,                 -- "PR001"
    scope       TEXT NOT NULL,
    title       TEXT NOT NULL,
    rule        TEXT NOT NULL,
    rationale   TEXT,
    source_ref  TEXT,                                 -- e.g. "←PR019" (upstream provenance)
    status      TEXT NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','retired')),
    retired_at  TEXT,
    memory_ref  TEXT,
    CHECK (scope NOT GLOB '*v_[0-9]*')
);

-- ============================================================================
-- refs — polymorphic, typed, directed edges  (the heart of the graph)
--   one row = one directed edge (source_table:source_id) --relation--> (target)
-- ============================================================================

CREATE TABLE IF NOT EXISTS refs (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    source_table TEXT    NOT NULL
                   CHECK (source_table IN ('changelog','next_targets','decisions','bugs','observations',
                                           'reminders','projectrules','adjudications','resolutions',
                                           'investigations','ideas')),
    source_id    INTEGER NOT NULL,                    -- polymorphic origin id (NOT FK-enforced)
    position     INTEGER NOT NULL DEFAULT 0,          -- soft ordering hint, NOT part of the unique key
    ref_kind     TEXT    NOT NULL
                   CHECK (ref_kind IN ('decision','bug','observation','reminder','projectrule','next_target',
                                       'adjudication','resolution','investigation','idea','file','commit','external')),
    relation     TEXT
                   CHECK (relation IS NULL OR relation IN (
                       'raised','investigates','produced','answers','crystallized','resolves',
                       'informs','validates','refutes','supersedes','duplicates','relates',
                       'documents','references','reopens','reaffirms')),
    -- target slots (exactly one non-null, matching ref_kind; raw_text for file/commit/external)
    decision_id      INTEGER REFERENCES decisions(id)      ON DELETE CASCADE,
    bug_id           INTEGER REFERENCES bugs(id)           ON DELETE CASCADE,
    observation_id   INTEGER REFERENCES observations(id)   ON DELETE CASCADE,
    reminder_id      INTEGER REFERENCES reminders(id)      ON DELETE CASCADE,
    projectrule_id  INTEGER REFERENCES projectrules(id)  ON DELETE CASCADE,
    next_target_id   INTEGER REFERENCES next_targets(id)   ON DELETE CASCADE,
    adjudication_id  INTEGER REFERENCES adjudications(id)  ON DELETE CASCADE,
    resolution_id    INTEGER REFERENCES resolutions(id)    ON DELETE CASCADE,
    investigation_id INTEGER REFERENCES investigations(id) ON DELETE CASCADE,
    idea_id          INTEGER REFERENCES ideas(id)          ON DELETE CASCADE,
    raw_text         TEXT,                             -- for ref_kind in (file, commit, external)
    ts_created       TEXT NOT NULL DEFAULT (datetime('now')),

    -- exactly-one-target, matching ref_kind  (num_nonnulls → boolean-sum + match)
    CHECK (
        ((decision_id      IS NOT NULL)
       + (bug_id           IS NOT NULL)
       + (observation_id   IS NOT NULL)
       + (reminder_id      IS NOT NULL)
       + (projectrule_id  IS NOT NULL)
       + (next_target_id   IS NOT NULL)
       + (adjudication_id  IS NOT NULL)
       + (resolution_id    IS NOT NULL)
       + (investigation_id IS NOT NULL)
       + (idea_id          IS NOT NULL)
       + (raw_text         IS NOT NULL)) = 1
    ),
    CHECK (
        (ref_kind='decision'      AND decision_id      IS NOT NULL)
     OR (ref_kind='bug'           AND bug_id           IS NOT NULL)
     OR (ref_kind='observation'   AND observation_id   IS NOT NULL)
     OR (ref_kind='reminder'      AND reminder_id      IS NOT NULL)
     OR (ref_kind='projectrule'  AND projectrule_id  IS NOT NULL)
     OR (ref_kind='next_target'   AND next_target_id   IS NOT NULL)
     OR (ref_kind='adjudication'  AND adjudication_id  IS NOT NULL)
     OR (ref_kind='resolution'    AND resolution_id    IS NOT NULL)
     OR (ref_kind='investigation' AND investigation_id IS NOT NULL)
     OR (ref_kind='idea'          AND idea_id          IS NOT NULL)
     OR (ref_kind IN ('file','commit','external') AND raw_text IS NOT NULL)
    ),
    -- no trivial 1-cycle (a row pointing at its own source within the same table)
    CHECK (NOT (
        (source_table='decisions'      AND decision_id      = source_id)
     OR (source_table='bugs'           AND bug_id           = source_id)
     OR (source_table='observations'   AND observation_id   = source_id)
     OR (source_table='reminders'      AND reminder_id      = source_id)
     OR (source_table='projectrules'  AND projectrule_id  = source_id)
     OR (source_table='next_targets'   AND next_target_id   = source_id)
     OR (source_table='adjudications'  AND adjudication_id  = source_id)
     OR (source_table='resolutions'    AND resolution_id    = source_id)
     OR (source_table='investigations' AND investigation_id = source_id)
     OR (source_table='ideas'          AND idea_id          = source_id)
    )),
    -- same-type supersession must use the node's superseded_by COLUMN, not a refs edge (NT-076)
    CHECK (
        relation IS NOT 'supersedes'
     OR NOT (
            (source_table='adjudications'  AND adjudication_id  IS NOT NULL)
         OR (source_table='resolutions'    AND resolution_id    IS NOT NULL)
         OR (source_table='investigations' AND investigation_id IS NOT NULL)
         OR (source_table='ideas'          AND idea_id          IS NOT NULL)
        )
    )
);

-- ============================================================================
-- op_error_raw — passive bash-error capture sink (NT-082).
--   Single-process SQLite: write-isolation is n/a (no `guard` role); the
--   op-error-capture hook inserts directly via run-dev-query.sh.
-- ============================================================================

CREATE TABLE IF NOT EXISTS op_error_raw (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts_created  TEXT NOT NULL DEFAULT (datetime('now')),
    tool        TEXT,
    error_class TEXT,                                 -- NONZERO_EXIT | OUTPUT_ERROR | ENFORCE_BLOCK
    exit_code   INTEGER,
    signal_text TEXT,
    query_id    TEXT,
    cmd_excerpt TEXT,
    cwd         TEXT,
    session_id  TEXT,
    triaged     INTEGER NOT NULL DEFAULT 0            -- 0=raw/untriaged, 1=triaged
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- base tables
CREATE INDEX IF NOT EXISTS idx_decisions_scope         ON decisions(scope);
CREATE INDEX IF NOT EXISTS idx_decisions_date          ON decisions(date DESC);
CREATE INDEX IF NOT EXISTS idx_decisions_superseded    ON decisions(superseded_by)    WHERE superseded_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bugs_status             ON bugs(status);
CREATE INDEX IF NOT EXISTS idx_bugs_severity           ON bugs(severity);
CREATE INDEX IF NOT EXISTS idx_observations_status     ON observations(status);
CREATE INDEX IF NOT EXISTS idx_observations_superseded ON observations(superseded_by) WHERE superseded_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_targets_status_priority ON next_targets(status, priority);
CREATE INDEX IF NOT EXISTS idx_targets_superseded      ON next_targets(superseded_by) WHERE superseded_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_changelog_date          ON changelog(date DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_version       ON changelog(version);

-- node tables
CREATE INDEX IF NOT EXISTS idx_adjudications_status     ON adjudications(status);
CREATE INDEX IF NOT EXISTS idx_adjudications_recogkey   ON adjudications(recognition_key);
CREATE INDEX IF NOT EXISTS idx_adjudications_superseded ON adjudications(superseded_by) WHERE superseded_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_resolutions_status       ON resolutions(status);
CREATE INDEX IF NOT EXISTS idx_resolutions_recogkey     ON resolutions(recognition_key);
CREATE INDEX IF NOT EXISTS idx_resolutions_superseded   ON resolutions(superseded_by) WHERE superseded_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_investigations_status    ON investigations(status);
CREATE INDEX IF NOT EXISTS idx_investigations_recogkey  ON investigations(recognition_key);
CREATE INDEX IF NOT EXISTS idx_ideas_status             ON ideas(status);
CREATE INDEX IF NOT EXISTS idx_ideas_recogkey           ON ideas(recognition_key);
CREATE INDEX IF NOT EXISTS idx_ideas_superseded         ON ideas(superseded_by) WHERE superseded_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reminders_status         ON reminders(status);
CREATE INDEX IF NOT EXISTS idx_reminders_date           ON reminders(date DESC);
CREATE INDEX IF NOT EXISTS idx_reminders_watchdog       ON reminders(code) WHERE watchdog_spec IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_projectrules_status     ON projectrules(status);
CREATE INDEX IF NOT EXISTS idx_projectrules_scope      ON projectrules(scope);

-- refs
CREATE INDEX IF NOT EXISTS idx_refs_source        ON refs(source_table, source_id);
CREATE INDEX IF NOT EXISTS idx_refs_kind          ON refs(ref_kind);
CREATE INDEX IF NOT EXISTS idx_refs_relation      ON refs(relation)         WHERE relation         IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_decision      ON refs(decision_id)      WHERE decision_id      IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_bug           ON refs(bug_id)           WHERE bug_id           IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_observation   ON refs(observation_id)   WHERE observation_id   IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_reminder      ON refs(reminder_id)      WHERE reminder_id      IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_projectrule  ON refs(projectrule_id)  WHERE projectrule_id  IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_next_target   ON refs(next_target_id)   WHERE next_target_id   IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_adjudication  ON refs(adjudication_id)  WHERE adjudication_id  IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_resolution    ON refs(resolution_id)    WHERE resolution_id    IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_investigation ON refs(investigation_id) WHERE investigation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_refs_idea          ON refs(idea_id)          WHERE idea_id          IS NOT NULL;

-- refs_edge_unique — emulate PG15 "UNIQUE NULLS NOT DISTINCT" via COALESCE sentinels
-- (SQLite treats NULLs in UNIQUE as distinct, so a plain UNIQUE would never fire). position excluded.
CREATE UNIQUE INDEX IF NOT EXISTS refs_edge_unique ON refs(
    source_table, source_id, ref_kind,
    COALESCE(relation,''),
    COALESCE(decision_id,-1), COALESCE(bug_id,-1), COALESCE(observation_id,-1),
    COALESCE(reminder_id,-1), COALESCE(projectrule_id,-1), COALESCE(next_target_id,-1),
    COALESCE(adjudication_id,-1), COALESCE(resolution_id,-1), COALESCE(investigation_id,-1),
    COALESCE(idea_id,-1), COALESCE(raw_text,'')
);

CREATE INDEX IF NOT EXISTS idx_op_error_raw_triaged ON op_error_raw(triaged);
CREATE INDEX IF NOT EXISTS idx_op_error_raw_query   ON op_error_raw(query_id) WHERE query_id IS NOT NULL;

-- ============================================================================
-- refs DAG cycle guard — DB-enforced acyclicity on the provenance/supersedes
--   subgraph (D-K3). SQLite has no "INSERT OR UPDATE" trigger → two triggers,
--   identical body. node identity = source_table || ':' || source_id.
--   Guarded relations: supersedes, raised, investigates, produced, crystallized, answers.
--   (relates/informs/validates/refutes/reopens/reaffirms/documents/references may
--    legitimately cycle and are NOT guarded — read-side traversal is visited-set safe.)
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS refs_dag_acyclic_insert
BEFORE INSERT ON refs
WHEN NEW.relation IN ('supersedes','raised','investigates','produced','crystallized','answers')
BEGIN
    SELECT CASE WHEN EXISTS(
        WITH RECURSIVE walk(node) AS (
            SELECT (CASE NEW.ref_kind
                      WHEN 'decision' THEN 'decisions'  WHEN 'bug' THEN 'bugs'
                      WHEN 'observation' THEN 'observations'  WHEN 'reminder' THEN 'reminders'
                      WHEN 'projectrule' THEN 'projectrules'  WHEN 'next_target' THEN 'next_targets'
                      WHEN 'adjudication' THEN 'adjudications'  WHEN 'resolution' THEN 'resolutions'
                      WHEN 'investigation' THEN 'investigations'  WHEN 'idea' THEN 'ideas' END)
                   || ':' || COALESCE(NEW.decision_id, NEW.bug_id, NEW.observation_id, NEW.reminder_id,
                                      NEW.projectrule_id, NEW.next_target_id, NEW.adjudication_id,
                                      NEW.resolution_id, NEW.investigation_id, NEW.idea_id)
            UNION
            SELECT (CASE r.ref_kind
                      WHEN 'decision' THEN 'decisions'  WHEN 'bug' THEN 'bugs'
                      WHEN 'observation' THEN 'observations'  WHEN 'reminder' THEN 'reminders'
                      WHEN 'projectrule' THEN 'projectrules'  WHEN 'next_target' THEN 'next_targets'
                      WHEN 'adjudication' THEN 'adjudications'  WHEN 'resolution' THEN 'resolutions'
                      WHEN 'investigation' THEN 'investigations'  WHEN 'idea' THEN 'ideas' END)
                   || ':' || COALESCE(r.decision_id, r.bug_id, r.observation_id, r.reminder_id,
                                      r.projectrule_id, r.next_target_id, r.adjudication_id,
                                      r.resolution_id, r.investigation_id, r.idea_id)
            FROM refs r JOIN walk w
              ON (r.source_table || ':' || r.source_id) = w.node
             AND r.relation IN ('supersedes','raised','investigates','produced','crystallized','answers')
        )
        SELECT 1 FROM walk WHERE node = (NEW.source_table || ':' || NEW.source_id)
    ) THEN RAISE(ABORT,'refs DAG cycle: edge would close a provenance/supersedes cycle') END;
END;

CREATE TRIGGER IF NOT EXISTS refs_dag_acyclic_update
BEFORE UPDATE ON refs
WHEN NEW.relation IN ('supersedes','raised','investigates','produced','crystallized','answers')
BEGIN
    SELECT CASE WHEN EXISTS(
        WITH RECURSIVE walk(node) AS (
            SELECT (CASE NEW.ref_kind
                      WHEN 'decision' THEN 'decisions'  WHEN 'bug' THEN 'bugs'
                      WHEN 'observation' THEN 'observations'  WHEN 'reminder' THEN 'reminders'
                      WHEN 'projectrule' THEN 'projectrules'  WHEN 'next_target' THEN 'next_targets'
                      WHEN 'adjudication' THEN 'adjudications'  WHEN 'resolution' THEN 'resolutions'
                      WHEN 'investigation' THEN 'investigations'  WHEN 'idea' THEN 'ideas' END)
                   || ':' || COALESCE(NEW.decision_id, NEW.bug_id, NEW.observation_id, NEW.reminder_id,
                                      NEW.projectrule_id, NEW.next_target_id, NEW.adjudication_id,
                                      NEW.resolution_id, NEW.investigation_id, NEW.idea_id)
            UNION
            SELECT (CASE r.ref_kind
                      WHEN 'decision' THEN 'decisions'  WHEN 'bug' THEN 'bugs'
                      WHEN 'observation' THEN 'observations'  WHEN 'reminder' THEN 'reminders'
                      WHEN 'projectrule' THEN 'projectrules'  WHEN 'next_target' THEN 'next_targets'
                      WHEN 'adjudication' THEN 'adjudications'  WHEN 'resolution' THEN 'resolutions'
                      WHEN 'investigation' THEN 'investigations'  WHEN 'idea' THEN 'ideas' END)
                   || ':' || COALESCE(r.decision_id, r.bug_id, r.observation_id, r.reminder_id,
                                      r.projectrule_id, r.next_target_id, r.adjudication_id,
                                      r.resolution_id, r.investigation_id, r.idea_id)
            FROM refs r JOIN walk w
              ON (r.source_table || ':' || r.source_id) = w.node
             AND r.relation IN ('supersedes','raised','investigates','produced','crystallized','answers')
        )
        SELECT 1 FROM walk WHERE node = (NEW.source_table || ':' || NEW.source_id)
    ) THEN RAISE(ABORT,'refs DAG cycle: edge would close a provenance/supersedes cycle') END;
END;

-- ============================================================================
-- refs source-existence guard (W002) — the polymorphic source slot has no FK;
--   reject an edge whose source_id has no row in source_table (no dangling edges).
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS refs_source_exists_insert
BEFORE INSERT ON refs
BEGIN
    SELECT CASE
        WHEN NEW.source_table='decisions'      AND NOT EXISTS(SELECT 1 FROM decisions      WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no decisions row')
        WHEN NEW.source_table='bugs'           AND NOT EXISTS(SELECT 1 FROM bugs           WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no bugs row')
        WHEN NEW.source_table='observations'   AND NOT EXISTS(SELECT 1 FROM observations   WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no observations row')
        WHEN NEW.source_table='next_targets'   AND NOT EXISTS(SELECT 1 FROM next_targets   WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no next_targets row')
        WHEN NEW.source_table='changelog'      AND NOT EXISTS(SELECT 1 FROM changelog      WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no changelog row')
        WHEN NEW.source_table='reminders'      AND NOT EXISTS(SELECT 1 FROM reminders      WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no reminders row')
        WHEN NEW.source_table='projectrules'   AND NOT EXISTS(SELECT 1 FROM projectrules   WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no projectrules row')
        WHEN NEW.source_table='adjudications'  AND NOT EXISTS(SELECT 1 FROM adjudications  WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no adjudications row')
        WHEN NEW.source_table='resolutions'    AND NOT EXISTS(SELECT 1 FROM resolutions    WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no resolutions row')
        WHEN NEW.source_table='investigations' AND NOT EXISTS(SELECT 1 FROM investigations WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no investigations row')
        WHEN NEW.source_table='ideas'          AND NOT EXISTS(SELECT 1 FROM ideas          WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no ideas row')
    END;
END;

CREATE TRIGGER IF NOT EXISTS refs_source_exists_update
BEFORE UPDATE OF source_table, source_id ON refs
BEGIN
    SELECT CASE
        WHEN NEW.source_table='decisions'      AND NOT EXISTS(SELECT 1 FROM decisions      WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no decisions row')
        WHEN NEW.source_table='bugs'           AND NOT EXISTS(SELECT 1 FROM bugs           WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no bugs row')
        WHEN NEW.source_table='observations'   AND NOT EXISTS(SELECT 1 FROM observations   WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no observations row')
        WHEN NEW.source_table='next_targets'   AND NOT EXISTS(SELECT 1 FROM next_targets   WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no next_targets row')
        WHEN NEW.source_table='changelog'      AND NOT EXISTS(SELECT 1 FROM changelog      WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no changelog row')
        WHEN NEW.source_table='reminders'      AND NOT EXISTS(SELECT 1 FROM reminders      WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no reminders row')
        WHEN NEW.source_table='projectrules'   AND NOT EXISTS(SELECT 1 FROM projectrules   WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no projectrules row')
        WHEN NEW.source_table='adjudications'  AND NOT EXISTS(SELECT 1 FROM adjudications  WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no adjudications row')
        WHEN NEW.source_table='resolutions'    AND NOT EXISTS(SELECT 1 FROM resolutions    WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no resolutions row')
        WHEN NEW.source_table='investigations' AND NOT EXISTS(SELECT 1 FROM investigations WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no investigations row')
        WHEN NEW.source_table='ideas'          AND NOT EXISTS(SELECT 1 FROM ideas          WHERE id=NEW.source_id) THEN RAISE(ABORT,'refs: source_id references no ideas row')
    END;
END;
