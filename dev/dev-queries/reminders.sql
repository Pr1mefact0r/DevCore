-- reminders domain queries
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
-- watchdog_spec / watchdog_fired_at are TEXT (JSON / ISO-8601). No recognition_key on this table.

-- @id: next_reminder_code
SELECT 'R' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 2) AS INTEGER)), 0) + 1) AS next_code
FROM reminders
WHERE code GLOB 'R[0-9][0-9][0-9]';
-- @end

-- @id: insert_reminder
INSERT INTO reminders
  (date, code, scope, title, trigger_when, action)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$TRIGGER_WHEN', '$ACTION');
SELECT id, code, status FROM reminders WHERE code = '$CODE';
-- @end

-- @id: get_reminder_by_code
SELECT * FROM reminders WHERE code = '$CODE';
-- @end

-- @id: get_active_reminders
SELECT code, date, scope, title, trigger_when, action FROM reminders
WHERE status = 'active'
ORDER BY date DESC
LIMIT 50;
-- @end

-- @id: get_resolved_reminders
SELECT code, date, scope, title, status, resolution, resolved_at FROM reminders
WHERE status IN ('resolved','dismissed')
ORDER BY date DESC
LIMIT 50;
-- @end

-- @id: search_reminders
SELECT code, date, scope, title, trigger_when, action, status FROM reminders
WHERE instr(lower(title || ' ' || trigger_when || ' ' || action), lower('$PATTERN')) > 0
ORDER BY date DESC
LIMIT 50;
-- @end

-- @id: count_active_reminders
SELECT COUNT(*) AS n FROM reminders WHERE status = 'active';
-- @end

-- @id: resolve_reminder
UPDATE reminders SET status = 'resolved', resolution = '$RESOLUTION', resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: dismiss_reminder
UPDATE reminders SET status = 'dismissed', resolution = COALESCE(NULLIF('$RESOLUTION',''), resolution), resolved_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: update_reminder_trigger
UPDATE reminders SET trigger_when = '$TRIGGER_WHEN' WHERE code = '$CODE';
-- @end

-- @id: update_reminder_action
UPDATE reminders SET action = '$ACTION' WHERE code = '$CODE';
-- @end

-- @id: update_reminder_memory_ref
UPDATE reminders SET memory_ref = '$MEMORY_REF' WHERE code = '$CODE';
-- @end

-- @id: with_watchdog
SELECT code, title, trigger_when, action, watchdog_spec, watchdog_fired_at FROM reminders
WHERE status = 'active' AND watchdog_spec IS NOT NULL;
-- @end

-- @id: get_watchdog_spec
SELECT watchdog_spec FROM reminders WHERE code = '$CODE';
-- @end

-- @id: set_watchdog_spec
UPDATE reminders SET watchdog_spec = NULLIF('$WATCHDOG_SPEC','') WHERE code = '$CODE';
-- @end

-- @id: set_watchdog_fired
UPDATE reminders SET watchdog_fired_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: clear_watchdog_fired
UPDATE reminders SET watchdog_fired_at = NULL WHERE code = '$CODE';
-- @end
