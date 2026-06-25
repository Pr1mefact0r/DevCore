-- refs domain queries — the polymorphic typed-edge graph (v3.0 brain-graph)
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
--   String params: write '$KEY'.  Numeric params: write $KEY (no quotes).
--   Optional → NULL: NULLIF('$KEY','').  Numeric optional: COALESCE(NULLIF('$KEY',''), <default>).
-- One row = one directed edge (source_table:source_id) --relation--> (target).
-- Same-type supersession does NOT live here — it uses the node's superseded_by column.

-- ============================================================================
-- TYPED EDGE INSERTS — link_<targetkind>.  The verb names the TARGET kind;
-- SOURCE_TABLE/SOURCE_ID name the source.  Echoes the new ref id.
-- ============================================================================

-- @id: link_decision
INSERT INTO refs (source_table, source_id, position, ref_kind, decision_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'decision', $DECISION_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_bug
INSERT INTO refs (source_table, source_id, position, ref_kind, bug_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'bug', $BUG_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_observation
INSERT INTO refs (source_table, source_id, position, ref_kind, observation_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'observation', $OBSERVATION_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_reminder
INSERT INTO refs (source_table, source_id, position, ref_kind, reminder_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'reminder', $REMINDER_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_projectrule
INSERT INTO refs (source_table, source_id, position, ref_kind, projectrule_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'projectrule', $PROJECTRULE_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_next_target
INSERT INTO refs (source_table, source_id, position, ref_kind, next_target_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'next_target', $NEXT_TARGET_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_adjudication
INSERT INTO refs (source_table, source_id, position, ref_kind, adjudication_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'adjudication', $ADJUDICATION_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_resolution
INSERT INTO refs (source_table, source_id, position, ref_kind, resolution_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'resolution', $RESOLUTION_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_investigation
INSERT INTO refs (source_table, source_id, position, ref_kind, investigation_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'investigation', $INVESTIGATION_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_idea
INSERT INTO refs (source_table, source_id, position, ref_kind, idea_id, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'idea', $IDEA_ID, NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- raw-text targets (file / commit / external) — pass RAW_TEXT
-- @id: link_file
INSERT INTO refs (source_table, source_id, position, ref_kind, raw_text, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'file', '$RAW_TEXT', NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_commit
INSERT INTO refs (source_table, source_id, position, ref_kind, raw_text, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'commit', '$RAW_TEXT', NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- @id: link_external
INSERT INTO refs (source_table, source_id, position, ref_kind, raw_text, relation)
VALUES ('$SOURCE_TABLE', $SOURCE_ID, COALESCE(NULLIF('$POSITION',''),0), 'external', '$RAW_TEXT', NULLIF('$RELATION',''));
SELECT last_insert_rowid() AS ref_id;
-- @end

-- ============================================================================
-- READ / TRAVERSAL
-- ============================================================================

-- outbound edges from a source node, with target code resolved
-- @id: edges_from
SELECT r.id AS ref_id, r.position, r.relation, r.ref_kind,
       COALESCE(d.code, b.code, o.code, rm.code, pr.code,
                COALESCE(nt.code,'NT#'||nt.id), aj.code, rs.code, inv.code, id.code,
                r.raw_text) AS target_code
FROM refs r
LEFT JOIN decisions      d   ON r.decision_id      = d.id
LEFT JOIN bugs           b   ON r.bug_id           = b.id
LEFT JOIN observations   o   ON r.observation_id   = o.id
LEFT JOIN reminders      rm  ON r.reminder_id      = rm.id
LEFT JOIN projectrules  pr  ON r.projectrule_id  = pr.id
LEFT JOIN next_targets   nt  ON r.next_target_id   = nt.id
LEFT JOIN adjudications  aj  ON r.adjudication_id  = aj.id
LEFT JOIN resolutions    rs  ON r.resolution_id    = rs.id
LEFT JOIN investigations inv ON r.investigation_id = inv.id
LEFT JOIN ideas          id  ON r.idea_id          = id.id
WHERE r.source_table = '$SOURCE_TABLE' AND r.source_id = $SOURCE_ID
ORDER BY r.position, r.id;
-- @end

-- inbound edges to a target node, with source code resolved (generic).
-- Caller passes: TARGET_TABLE (e.g. adjudications), TARGET_COL (e.g. adjudication_id), CODE.
-- @id: get_refs_to_node
SELECT r.id AS ref_id, r.source_table, r.relation, r.ref_kind,
       COALESCE(d.code, b.code, o.code, rm.code, pr.code,
                COALESCE(nt.code,'NT#'||nt.id), aj.code, rs.code, inv.code, id.code,
                'CL'||cl.id) AS source_code
FROM refs r
LEFT JOIN decisions      d   ON r.source_table='decisions'      AND r.source_id=d.id
LEFT JOIN bugs           b   ON r.source_table='bugs'           AND r.source_id=b.id
LEFT JOIN observations   o   ON r.source_table='observations'   AND r.source_id=o.id
LEFT JOIN reminders      rm  ON r.source_table='reminders'      AND r.source_id=rm.id
LEFT JOIN projectrules  pr  ON r.source_table='projectrules'  AND r.source_id=pr.id
LEFT JOIN next_targets   nt  ON r.source_table='next_targets'   AND r.source_id=nt.id
LEFT JOIN adjudications  aj  ON r.source_table='adjudications'  AND r.source_id=aj.id
LEFT JOIN resolutions    rs  ON r.source_table='resolutions'    AND r.source_id=rs.id
LEFT JOIN investigations inv ON r.source_table='investigations' AND r.source_id=inv.id
LEFT JOIN ideas          id  ON r.source_table='ideas'          AND r.source_id=id.id
LEFT JOIN changelog      cl  ON r.source_table='changelog'      AND r.source_id=cl.id
WHERE r.$TARGET_COL = (SELECT id FROM $TARGET_TABLE WHERE code = '$CODE')
ORDER BY r.source_table, source_code;
-- @end

-- loop-safe multi-hop neighbourhood walk (SQLite: text-path visited guard, no LATERAL/ARRAY).
-- Caller passes: START_TABLE, START_ID, MAX_DEPTH (default 4). Returns each reachable node once
-- at its minimum depth, with a resolved code.
-- @id: walk_neighborhood
WITH RECURSIVE walk(node_table, node_id, depth, via_relation, path) AS (
    SELECT '$START_TABLE', $START_ID, 0, NULL,
           '/' || '$START_TABLE' || ':' || $START_ID || '/'
    UNION ALL
    SELECT e.tgt_table, e.tgt_id, w.depth + 1, e.relation,
           w.path || e.tgt_table || ':' || e.tgt_id || '/'
    FROM walk w
    JOIN (
        SELECT r.source_table AS s_table, r.source_id AS s_id, r.relation AS relation,
               (CASE r.ref_kind
                  WHEN 'decision' THEN 'decisions'  WHEN 'bug' THEN 'bugs'
                  WHEN 'observation' THEN 'observations'  WHEN 'reminder' THEN 'reminders'
                  WHEN 'projectrule' THEN 'projectrules'  WHEN 'next_target' THEN 'next_targets'
                  WHEN 'adjudication' THEN 'adjudications'  WHEN 'resolution' THEN 'resolutions'
                  WHEN 'investigation' THEN 'investigations'  WHEN 'idea' THEN 'ideas' END) AS tgt_table,
               COALESCE(r.decision_id, r.bug_id, r.observation_id, r.reminder_id, r.projectrule_id,
                        r.next_target_id, r.adjudication_id, r.resolution_id, r.investigation_id, r.idea_id) AS tgt_id
        FROM refs r
    ) e ON e.s_table = w.node_table AND e.s_id = w.node_id
    WHERE w.depth < CAST(COALESCE(NULLIF('$MAX_DEPTH',''),'4') AS INTEGER)
      AND e.tgt_table IS NOT NULL AND e.tgt_id IS NOT NULL
      AND w.path NOT LIKE '%/' || e.tgt_table || ':' || e.tgt_id || '/%'
)
SELECT q.depth, q.via_relation, q.node_table, q.node_id,
       COALESCE(d.code, b.code, o.code, rm.code, pr.code,
                COALESCE(nt.code,'NT#'||nt.id), aj.code, rs.code, inv.code, id.code,
                'CL'||cl.id) AS node_code
FROM (
    SELECT node_table, node_id, depth, via_relation,
           ROW_NUMBER() OVER (PARTITION BY node_table, node_id ORDER BY depth) AS rn
    FROM walk WHERE depth > 0
) q
LEFT JOIN decisions      d   ON q.node_table='decisions'      AND q.node_id=d.id
LEFT JOIN bugs           b   ON q.node_table='bugs'           AND q.node_id=b.id
LEFT JOIN observations   o   ON q.node_table='observations'   AND q.node_id=o.id
LEFT JOIN reminders      rm  ON q.node_table='reminders'      AND q.node_id=rm.id
LEFT JOIN projectrules  pr  ON q.node_table='projectrules'  AND q.node_id=pr.id
LEFT JOIN next_targets   nt  ON q.node_table='next_targets'   AND q.node_id=nt.id
LEFT JOIN adjudications  aj  ON q.node_table='adjudications'  AND q.node_id=aj.id
LEFT JOIN resolutions    rs  ON q.node_table='resolutions'    AND q.node_id=rs.id
LEFT JOIN investigations inv ON q.node_table='investigations' AND q.node_id=inv.id
LEFT JOIN ideas          id  ON q.node_table='ideas'          AND q.node_id=id.id
LEFT JOIN changelog      cl  ON q.node_table='changelog'      AND q.node_id=cl.id
WHERE q.rn = 1
ORDER BY q.depth, node_code;
-- @end

-- full-text-ish scan over source/target codes + relation
-- @id: refs_search
SELECT r.id AS ref_id, r.source_table, r.source_id, r.relation, r.ref_kind,
       COALESCE(d.code, b.code, o.code, rm.code, pr.code,
                COALESCE(nt.code,'NT#'||nt.id), aj.code, rs.code, inv.code, id.code, r.raw_text) AS target_code
FROM refs r
LEFT JOIN decisions      d   ON r.decision_id      = d.id
LEFT JOIN bugs           b   ON r.bug_id           = b.id
LEFT JOIN observations   o   ON r.observation_id   = o.id
LEFT JOIN reminders      rm  ON r.reminder_id      = rm.id
LEFT JOIN projectrules  pr  ON r.projectrule_id  = pr.id
LEFT JOIN next_targets   nt  ON r.next_target_id   = nt.id
LEFT JOIN adjudications  aj  ON r.adjudication_id  = aj.id
LEFT JOIN resolutions    rs  ON r.resolution_id    = rs.id
LEFT JOIN investigations inv ON r.investigation_id = inv.id
LEFT JOIN ideas          id  ON r.idea_id          = id.id
WHERE instr(lower(COALESCE(r.relation,'') || ' ' ||
                  COALESCE(d.code,b.code,o.code,rm.code,pr.code,nt.code,aj.code,rs.code,inv.code,id.code,r.raw_text,'')),
            lower('$PATTERN')) > 0
ORDER BY r.id
LIMIT 100;
-- @end

-- ============================================================================
-- MAINTENANCE / DIAGNOSTIC
-- ============================================================================

-- @id: count_refs
SELECT COUNT(*) AS n FROM refs;
-- @end

-- @id: refs_by_kind
SELECT ref_kind, COUNT(*) AS n FROM refs GROUP BY ref_kind ORDER BY n DESC;
-- @end

-- @id: refs_by_source_table
SELECT source_table, COUNT(*) AS n FROM refs GROUP BY source_table ORDER BY n DESC;
-- @end

-- @id: delete_refs_by_source
DELETE FROM refs WHERE source_table = '$SOURCE_TABLE' AND source_id = $SOURCE_ID;
SELECT changes() AS deleted;
-- @end

-- @id: delete_ref_by_id
DELETE FROM refs WHERE id = $ID;
SELECT changes() AS deleted;
-- @end

-- edges with no relation predicate (untyped legacy / to-be-classified)
-- @id: untyped_refs
SELECT id, source_table, source_id, ref_kind FROM refs WHERE relation IS NULL ORDER BY id;
-- @end

-- reciprocal pairs (A->B and B->A) — a smell (PR022: one directed edge per relationship)
-- @id: reciprocal_pairs
SELECT a.id AS a_id, b.id AS b_id, a.source_table, a.source_id, a.ref_kind, a.relation
FROM refs a
JOIN refs b
  ON  b.source_table = (CASE a.ref_kind
         WHEN 'decision' THEN 'decisions' WHEN 'bug' THEN 'bugs' WHEN 'observation' THEN 'observations'
         WHEN 'reminder' THEN 'reminders' WHEN 'projectrule' THEN 'projectrules' WHEN 'next_target' THEN 'next_targets'
         WHEN 'adjudication' THEN 'adjudications' WHEN 'resolution' THEN 'resolutions'
         WHEN 'investigation' THEN 'investigations' WHEN 'idea' THEN 'ideas' END)
  AND b.source_id = COALESCE(a.decision_id,a.bug_id,a.observation_id,a.reminder_id,a.projectrule_id,
                             a.next_target_id,a.adjudication_id,a.resolution_id,a.investigation_id,a.idea_id)
  AND a.source_table = (CASE b.ref_kind
         WHEN 'decision' THEN 'decisions' WHEN 'bug' THEN 'bugs' WHEN 'observation' THEN 'observations'
         WHEN 'reminder' THEN 'reminders' WHEN 'projectrule' THEN 'projectrules' WHEN 'next_target' THEN 'next_targets'
         WHEN 'adjudication' THEN 'adjudications' WHEN 'resolution' THEN 'resolutions'
         WHEN 'investigation' THEN 'investigations' WHEN 'idea' THEN 'ideas' END)
  AND a.source_id = COALESCE(b.decision_id,b.bug_id,b.observation_id,b.reminder_id,b.projectrule_id,
                             b.next_target_id,b.adjudication_id,b.resolution_id,b.investigation_id,b.idea_id)
WHERE a.id < b.id
ORDER BY a.id;
-- @end

-- diagnostic cycle detector over the guarded provenance subgraph (belt-and-suspenders to the trigger)
-- @id: detect_cycles
WITH RECURSIVE g(src, tgt, relation) AS (
    SELECT (r.source_table || ':' || r.source_id),
           ((CASE r.ref_kind
               WHEN 'decision' THEN 'decisions' WHEN 'bug' THEN 'bugs' WHEN 'observation' THEN 'observations'
               WHEN 'reminder' THEN 'reminders' WHEN 'projectrule' THEN 'projectrules' WHEN 'next_target' THEN 'next_targets'
               WHEN 'adjudication' THEN 'adjudications' WHEN 'resolution' THEN 'resolutions'
               WHEN 'investigation' THEN 'investigations' WHEN 'idea' THEN 'ideas' END)
            || ':' || COALESCE(r.decision_id,r.bug_id,r.observation_id,r.reminder_id,r.projectrule_id,
                               r.next_target_id,r.adjudication_id,r.resolution_id,r.investigation_id,r.idea_id)),
           r.relation
    FROM refs r
    WHERE r.relation IN ('supersedes','raised','investigates','produced','crystallized','answers')
),
walk(start, node, path, depth) AS (
    SELECT src, tgt, '/'||src||'/'||tgt||'/', 1 FROM g
    UNION ALL
    SELECT w.start, g.tgt, w.path||g.tgt||'/', w.depth+1
    FROM walk w JOIN g ON g.src = w.node
    WHERE w.depth < 50 AND w.path NOT LIKE '%/'||g.tgt||'/%'
)
SELECT DISTINCT start AS cycle_node, depth, path FROM walk WHERE node = start ORDER BY depth LIMIT 50;
-- @end
