-- op_error_raw domain queries
-- Passive bash-error capture sink (NT-082): single-role, no allocator, no code.
-- capture_raw is called from the op-error-capture hook on the error path — it must
-- tolerate any missing param (NULLIF strips unset → NULL) and never fail loud.

-- @id: capture_raw
INSERT INTO op_error_raw(tool,error_class,exit_code,signal_text,query_id,cmd_excerpt,cwd,session_id)
VALUES(NULLIF('$TOOL',''), NULLIF('$ERROR_CLASS',''), CAST(NULLIF('$EXIT_CODE','') AS INTEGER), NULLIF('$SIGNAL_TEXT',''), NULLIF('$QUERY_ID',''), NULLIF('$CMD_EXCERPT',''), NULLIF('$CWD',''), NULLIF('$SESSION_ID',''));
SELECT last_insert_rowid() AS id;
-- @end

-- @id: get_untriaged
SELECT id, ts_created, tool, error_class, exit_code, query_id, cmd_excerpt
FROM op_error_raw
WHERE triaged = 0
ORDER BY id DESC
LIMIT 50;
-- @end

-- @id: recent_errors
SELECT id, ts_created, tool, error_class, query_id
FROM op_error_raw
ORDER BY id DESC
LIMIT 20;
-- @end

-- @id: mark_triaged
UPDATE op_error_raw SET triaged = 1 WHERE id = $ID;
-- @end

-- @id: count_untriaged
SELECT COUNT(*) AS n FROM op_error_raw WHERE triaged = 0;
-- @end
