-- bugs domain queries

-- @id: next_bug_code
SELECT 'B' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 2) AS INTEGER)), 0) + 1) AS next_code
FROM bugs
WHERE code GLOB 'B[0-9][0-9][0-9]';
-- @end

-- @id: insert_bug
INSERT INTO bugs
  (date, code, scope, title, description, severity, found_in, status, fix, memory_ref)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$DESCRIPTION', '$SEVERITY', '$FOUND_IN', 'open', '$FIX', '$MEMORY_REF');
SELECT code, scope, title, severity, status FROM bugs WHERE code = '$CODE';
-- @end

-- @id: mark_bug_fixed
UPDATE bugs SET status = 'fixed', fix = '$FIX', fixed_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: mark_bug_wontfix
UPDATE bugs SET status = 'wontfix', fix = '$FIX', fixed_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: get_open_bugs
SELECT code, date, scope, severity, title FROM bugs
WHERE status = 'open'
ORDER BY
  CASE severity
    WHEN 'critical' THEN 1
    WHEN 'behavioral' THEN 2
    WHEN 'edge_case' THEN 3
    WHEN 'minor' THEN 4
    ELSE 5
  END,
  date DESC;
-- @end

-- @id: get_bug_by_code
SELECT * FROM bugs WHERE code = '$CODE';
-- @end

-- @id: get_bugs_by_status
SELECT code, date, scope, severity, title FROM bugs WHERE status = '$STATUS' ORDER BY date DESC LIMIT 50;
-- @end

-- @id: count_open_bugs
SELECT COUNT(*) AS n FROM bugs WHERE status = 'open';
-- @end
