-- decisions domain queries
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.

-- @id: next_decision_code
SELECT 'D' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(code, 2) AS INTEGER)), 0) + 1) AS next_code
FROM decisions
WHERE code GLOB 'D[0-9][0-9][0-9]';
-- @end

-- @id: insert_decision
INSERT INTO decisions
  (date, code, scope, title, context, decision, rationale, tradeoff, alternatives, rule, convention, memory_ref, updated_at)
VALUES
  ('$DATE', '$CODE', '$SCOPE', '$TITLE', '$CONTEXT', '$DECISION', '$RATIONALE', '$TRADEOFF', '$ALTERNATIVES', '$RULE', '$CONVENTION', '$MEMORY_REF', '$DATE');
SELECT code, scope, title FROM decisions WHERE code = '$CODE';
-- @end

-- @id: update_decision_memory_ref
UPDATE decisions SET memory_ref = '$MEMORY_REF', updated_at = '$DATE' WHERE code = '$CODE';
-- @end

-- @id: supersede_decision
UPDATE decisions SET rationale = COALESCE(rationale,'') || ' [superseded by $NEW_CODE on $DATE]', updated_at = '$DATE' WHERE code = '$OLD_CODE';
-- @end

-- @id: get_decisions_by_scope
SELECT code, date, scope, title, decision FROM decisions
WHERE scope LIKE '$SCOPE_LIKE'
ORDER BY date DESC, code DESC
LIMIT 50;
-- @end

-- @id: get_decision_by_code
SELECT * FROM decisions WHERE code = '$CODE';
-- @end

-- @id: get_recent_decisions
SELECT code, date, scope, title FROM decisions
ORDER BY date DESC, code DESC
LIMIT 20;
-- @end

-- @id: count_decisions
SELECT COUNT(*) AS n FROM decisions;
-- @end
