-- next_targets domain queries
-- v3.0: source_refs freetext column removed (crosslinks are typed `refs` edges);
--       lifecycle columns superseded_by/reopened_reason added; NT### code allocator.

-- @id: next_target_code
SELECT 'NT' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code,3) AS INTEGER)),0)+1) AS next_code FROM next_targets WHERE code GLOB 'NT[0-9][0-9][0-9]';
-- @end

-- @id: insert_target
INSERT INTO next_targets
  (date, code, scope, title, description, affected, priority, status, memory_ref)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$DESCRIPTION', '$AFFECTED', $PRIORITY, 'open', '$MEMORY_REF');
SELECT id, code, scope, title, priority FROM next_targets ORDER BY id DESC LIMIT 1;
-- @end

-- @id: update_target_status
UPDATE next_targets SET status = '$STATUS' WHERE id = $ID;
-- @end

-- @id: update_target_priority
UPDATE next_targets SET priority = $PRIORITY WHERE id = $ID;
-- @end

-- @id: complete_target
UPDATE next_targets SET status = 'done', done_at = '$DATE' WHERE id = $ID;
-- @end

-- @id: supersede_target
UPDATE next_targets SET status='superseded', superseded_by=CAST(NULLIF('$NEW_ID','') AS INTEGER) WHERE id=$ID;
-- @end

-- @id: reopen_target
UPDATE next_targets SET status='open', reopened_reason='$REASON' WHERE id=$ID;
-- @end

-- @id: get_open_targets
SELECT id, date, code, scope, priority, title FROM next_targets
WHERE status IN ('open', 'in_progress')
ORDER BY priority ASC, id ASC
LIMIT 50;
-- @end

-- @id: get_done_targets
SELECT id, date, code, scope, title, done_at FROM next_targets
WHERE status = 'done'
ORDER BY done_at DESC
LIMIT 50;
-- @end

-- @id: get_target_by_id
SELECT * FROM next_targets WHERE id = $ID;
-- @end

-- @id: get_target_by_code
-- code is optional/nullable on next_targets; use get_target_by_id when no code was assigned
SELECT * FROM next_targets WHERE code = '$CODE';
-- @end

-- @id: count_open_targets
SELECT COUNT(*) AS n FROM next_targets WHERE status IN ('open','in_progress');
-- @end
