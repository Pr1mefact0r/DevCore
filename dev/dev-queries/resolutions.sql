-- resolutions domain queries
-- RS### reusable "how we solved it" precedents (node table).
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
-- FK / CHECK-optional columns use NULLIF('$KEY','') so an unset param becomes NULL.

-- @id: next_resolution_code
SELECT 'RS' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 3) AS INTEGER)), 0) + 1) AS next_code
FROM resolutions
WHERE code GLOB 'RS[0-9][0-9][0-9]';
-- @end

-- @id: insert_resolution
INSERT INTO resolutions
  (date, code, scope, title, problem, resolution, outcome, reuse, source,
   recognition_key, recognition_text, as_of, validity)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$PROBLEM', '$RESOLUTION', '$OUTCOME', '$REUSE',
   NULLIF('$SOURCE',''),
   NULLIF('$RECOGNITION_KEY',''), '$RECOGNITION_TEXT', '$AS_OF', '$VALIDITY');
SELECT id, code, status FROM resolutions WHERE code = '$CODE';
-- @end

-- @id: get_resolution_by_code
SELECT * FROM resolutions WHERE code = '$CODE';
-- @end

-- @id: get_settled_resolutions
SELECT code, date, scope, title, problem, resolution, status FROM resolutions
WHERE status = 'settled'
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: resolutions_by_recognition_key
SELECT code, date, scope, title, status FROM resolutions
WHERE recognition_key = '$KEY'
ORDER BY date DESC, code DESC;
-- @end

-- @id: get_all_resolutions
SELECT code, date, scope, title, status FROM resolutions
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: count_settled_resolutions
SELECT COUNT(*) AS n FROM resolutions WHERE status = 'settled';
-- @end

-- @id: search_resolutions_recognition
SELECT code, date, scope, title, status FROM resolutions
WHERE instr(lower(title || ' ' || problem || ' ' || COALESCE(recognition_text, '')), lower('$PATTERN')) > 0
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: supersede_resolution
UPDATE resolutions SET superseded_by = $NEW_ID, status = 'superseded', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: mark_resolution_stale
UPDATE resolutions SET status = 'stale' WHERE code = '$CODE';
-- @end

-- @id: mark_resolution_revalidated
UPDATE resolutions SET status = 'settled', last_revalidated = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: reopen_resolution
UPDATE resolutions SET status = 'reopened', reopened_reason = '$REASON' WHERE code = '$CODE';
-- @end
