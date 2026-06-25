-- changelog domain queries

-- @id: insert_changelog
INSERT INTO changelog
  (date, version, scope, title, summary, root_cause, solution, files)
VALUES
  ('$DATE', '$VERSION', '$SCOPE', '$TITLE', '$SUMMARY', '$ROOT_CAUSE', '$SOLUTION', '$FILES');
SELECT id, date, scope, title FROM changelog ORDER BY id DESC LIMIT 1;
-- @end

-- @id: get_recent_changelog
SELECT date, version, scope, title, summary FROM changelog
ORDER BY date DESC, id DESC
LIMIT 20;
-- @end

-- @id: get_changelog_by_version
SELECT * FROM changelog WHERE version = '$VERSION' ORDER BY date DESC;
-- @end

-- @id: get_changelog_by_scope
SELECT date, version, scope, title, summary FROM changelog
WHERE scope LIKE '$SCOPE_LIKE'
ORDER BY date DESC
LIMIT 50;
-- @end

-- @id: count_changelog
SELECT COUNT(*) AS n FROM changelog;
-- @end
