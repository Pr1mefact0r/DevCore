-- adjudications domain queries
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
-- recognition_key is an FK; evidence_data / revalidation_params are TEXT JSON — all use NULLIF('$KEY','').

-- @id: next_adjudication_code
SELECT 'Q' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 2) AS INTEGER)), 0) + 1) AS next_code
FROM adjudications
WHERE code GLOB 'Q[0-9][0-9][0-9]';
-- @end

-- @id: insert_adjudication
INSERT INTO adjudications
  (date, code, scope, title, question, verdict, evidence, evidence_data, recognition_key, recognition_text, as_of, validity, revalidation_query, revalidation_params)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$QUESTION', '$VERDICT', '$EVIDENCE', NULLIF('$EVIDENCE_DATA',''), NULLIF('$RECOGNITION_KEY',''), '$RECOGNITION_TEXT', '$AS_OF', '$VALIDITY', '$REVALIDATION_QUERY', NULLIF('$REVALIDATION_PARAMS',''));
SELECT id, code, status FROM adjudications WHERE code = '$CODE';
-- @end

-- @id: get_adjudication_by_code
SELECT * FROM adjudications WHERE code = '$CODE';
-- @end

-- @id: get_settled_adjudications
SELECT code, date, scope, title, verdict, as_of FROM adjudications
WHERE status = 'settled'
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: adjudications_by_recognition_key
SELECT code, date, scope, title, verdict, status FROM adjudications
WHERE recognition_key = '$KEY'
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: get_all_adjudications
SELECT code, date, scope, title, status FROM adjudications
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: revalidatable
SELECT code, date, scope, title, revalidation_query, revalidation_params, last_revalidated FROM adjudications
WHERE status = 'settled' AND revalidation_query IS NOT NULL
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: count_settled_adjudications
SELECT COUNT(*) AS n FROM adjudications WHERE status = 'settled';
-- @end

-- @id: search_adjudications_recognition
SELECT code, date, scope, title, recognition_text, status FROM adjudications
WHERE instr(lower(title || ' ' || question || ' ' || COALESCE(recognition_text, '')), lower('$PATTERN')) > 0
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: supersede_adjudication
UPDATE adjudications SET superseded_by = $NEW_ID, status = 'superseded', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: mark_adjudication_stale
UPDATE adjudications SET status = 'stale' WHERE code = '$CODE';
-- @end

-- @id: mark_adjudication_revalidated
UPDATE adjudications SET status = 'settled', last_revalidated = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: reopen_adjudication
UPDATE adjudications SET status = 'reopened', reopened_reason = '$REASON' WHERE code = '$CODE';
-- @end
