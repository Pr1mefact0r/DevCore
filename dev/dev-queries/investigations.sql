-- investigations domain queries
-- The PROCESS between a question and its settled answer. Code I###.
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
-- recognition_key is an FK → must use NULLIF('$RECOGNITION_KEY',''); as_of is nullable here.

-- @id: next_investigation_code
SELECT 'I' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 2) AS INTEGER)), 0) + 1) AS next_code
FROM investigations
WHERE code GLOB 'I[0-9][0-9][0-9]';
-- @end

-- @id: insert_investigation
INSERT INTO investigations
  (date, code, scope, title, question, method, findings, recognition_key, recognition_text, as_of)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$QUESTION', '$METHOD', '$FINDINGS',
   NULLIF('$RECOGNITION_KEY',''), '$RECOGNITION_TEXT', NULLIF('$AS_OF',''));
SELECT id, code, status FROM investigations WHERE code = '$CODE';
-- @end

-- @id: get_investigation_by_code
SELECT * FROM investigations WHERE code = '$CODE';
-- @end

-- @id: get_open_investigations
SELECT code, date, scope, title, question, status FROM investigations
WHERE status = 'open'
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: investigations_by_recognition_key
SELECT code, date, scope, title, question, status FROM investigations
WHERE recognition_key = '$RECOGNITION_KEY'
ORDER BY date DESC, code DESC;
-- @end

-- @id: get_all_investigations
SELECT code, date, scope, title, status FROM investigations
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: search_investigations
SELECT code, date, scope, title, status FROM investigations
WHERE instr(lower(title || ' ' || question || ' ' || COALESCE(findings,'')), lower('$PATTERN')) > 0
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: count_open_investigations
SELECT COUNT(*) AS n FROM investigations WHERE status = 'open';
-- @end

-- @id: conclude_investigation
UPDATE investigations
SET status = 'concluded',
    findings = '$FINDINGS',
    method = COALESCE(NULLIF('$METHOD',''), method),
    resolved_at = '$DATE'
WHERE code = '$CODE';
-- @end

-- @id: abandon_investigation
UPDATE investigations
SET status = 'abandoned',
    findings = COALESCE(NULLIF('$FINDINGS',''), findings),
    resolved_at = '$DATE'
WHERE code = '$CODE';
-- @end

-- @id: supersede_investigation
UPDATE investigations
SET superseded_by = $NEW_ID,
    status = 'superseded',
    resolved_at = '$DATE'
WHERE code = '$CODE';
-- @end
