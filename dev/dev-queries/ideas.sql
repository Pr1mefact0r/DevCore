-- ideas domain queries
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
-- recognition_key is FK → recognition_keys(key); use NULLIF for optional FK. Code prefix is the word 'IDEA' (no hyphen).

-- @id: next_idea_code
SELECT 'IDEA' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 5) AS INTEGER)), 0) + 1) AS next_code
FROM ideas
WHERE code GLOB 'IDEA[0-9][0-9][0-9]';
-- @end

-- @id: insert_idea
INSERT INTO ideas
  (date, code, scope, title, body, rationale, recognition_key, recognition_text, as_of)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$BODY', '$RATIONALE', NULLIF('$RECOGNITION_KEY',''), '$RECOGNITION_TEXT', NULLIF('$AS_OF',''));
SELECT id, code, status FROM ideas WHERE code = '$CODE';
-- @end

-- @id: get_idea_by_code
SELECT * FROM ideas WHERE code = '$CODE';
-- @end

-- @id: get_open_ideas
SELECT code, date, scope, title, body FROM ideas
WHERE status = 'idea'
ORDER BY date DESC, id DESC
LIMIT 50;
-- @end

-- @id: count_open_ideas
SELECT COUNT(*) AS n FROM ideas WHERE status = 'idea';
-- @end

-- @id: get_recent_ideas
SELECT code, date, scope, title, status FROM ideas
ORDER BY date DESC, id DESC
LIMIT 20;
-- @end

-- @id: get_ideas_by_recognition_key
SELECT code, date, scope, title, status FROM ideas
WHERE recognition_key = '$KEY'
ORDER BY date DESC, id DESC;
-- @end

-- @id: search_ideas_recognition
SELECT code, date, scope, title, status FROM ideas
WHERE instr(lower(title || ' ' || body || ' ' || COALESCE(recognition_text,'')), lower('$PATTERN')) > 0
ORDER BY date DESC, id DESC;
-- @end

-- @id: promote_idea
UPDATE ideas SET status = 'promoted', promoted_to = '$PROMOTED_TO', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: drop_idea
UPDATE ideas SET status = 'dropped', rationale = COALESCE(rationale,'') || ' [dropped ' || '$DATE' || ': ' || '$REASON' || ']', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: supersede_idea
UPDATE ideas SET superseded_by = $NEW_ID, status = 'superseded', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: append_note
UPDATE ideas SET rationale = COALESCE(rationale,'') || ' [' || '$DATE' || ': ' || '$NOTE' || ']' WHERE code = '$CODE';
-- @end
