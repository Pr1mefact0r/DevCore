-- projectrules domain queries
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.
-- projectrules PR### — the discipline layer (active|retired).

-- @id: next_projectrule_code
SELECT 'PR' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 3) AS INTEGER)), 0) + 1) AS next_code
FROM projectrules
WHERE code GLOB 'PR[0-9][0-9][0-9]';
-- @end

-- @id: insert_projectrule
INSERT INTO projectrules
  (date, code, scope, title, rule, rationale, source_ref)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$RULE', '$RATIONALE', '$SOURCE_REF');
SELECT id, code, status FROM projectrules WHERE code = '$CODE';
-- @end

-- @id: get_projectrule_by_code
SELECT * FROM projectrules WHERE code = '$CODE';
-- @end

-- @id: get_active_projectrules
SELECT code, title, rule, rationale, source_ref FROM projectrules
WHERE status = 'active'
ORDER BY id;
-- @end

-- @id: search_projectrules
SELECT code, status, title, rule FROM projectrules
WHERE instr(lower(title || ' ' || rule || ' ' || COALESCE(rationale, '')), lower('$PATTERN')) > 0
ORDER BY id;
-- @end

-- @id: count_active_projectrules
SELECT COUNT(*) AS n FROM projectrules WHERE status = 'active';
-- @end

-- @id: retire_projectrule
UPDATE projectrules SET status = 'retired', retired_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: update_projectrule_memory_ref
UPDATE projectrules SET memory_ref = '$MEMORY_REF' WHERE code = '$CODE';
-- @end

-- @id: update_projectrule_rule
UPDATE projectrules SET rule = '$RULE' WHERE code = '$CODE';
-- @end

-- @id: append_to_rule
UPDATE projectrules SET rule = rule || ' ' || '$TEXT' WHERE code = '$CODE';
-- @end
