-- observations domain queries

-- @id: next_observation_code
SELECT 'W' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 2) AS INTEGER)), 0) + 1) AS next_code
FROM observations
WHERE code GLOB 'W[0-9][0-9][0-9]';
-- @end

-- @id: insert_observation
INSERT INTO observations
  (date, code, scope, title, description, found_in, watch_for, status)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$DESCRIPTION', '$FOUND_IN', '$WATCH_FOR', 'watching');
SELECT code, scope, title, status FROM observations WHERE code = '$CODE';
-- @end

-- @id: update_observation_status
UPDATE observations SET status = '$STATUS' WHERE code = '$CODE';
-- @end

-- @id: resolve_observation
UPDATE observations SET status = 'resolved', resolution = '$RESOLUTION', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: dismiss_observation
UPDATE observations SET status = 'false_alarm', resolution = '$RESOLUTION', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: get_active_observations
SELECT code, date, scope, title, watch_for, status FROM observations
WHERE status IN ('watching', 'fix_deployed_monitoring')
ORDER BY date DESC;
-- @end

-- @id: get_observation_by_code
SELECT * FROM observations WHERE code = '$CODE';
-- @end

-- @id: count_active_observations
SELECT COUNT(*) AS n FROM observations WHERE status IN ('watching','fix_deployed_monitoring');
-- @end
