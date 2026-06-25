-- recognition_keys domain queries
-- Natural PK `key` (UPPER_SNAKE, CHECK-enforced). No numeric id, no code allocator.
-- Conventions: $KEY placeholders are replaced+quoted by run-dev-query.sh.

-- @id: register_key
INSERT OR IGNORE INTO recognition_keys (key, text, definition, first_seen, created_by)
VALUES ('$KEY', '$TEXT', NULLIF('$DEFINITION',''), NULLIF('$FIRST_SEEN',''), NULLIF('$CREATED_BY',''));
SELECT key, text FROM recognition_keys WHERE key = '$KEY';
-- @end

-- @id: get_key
SELECT * FROM recognition_keys WHERE key = '$KEY';
-- @end

-- @id: search_keys
SELECT key, text FROM recognition_keys
WHERE key LIKE '%' || '$PATTERN' || '%' OR text LIKE '%' || '$PATTERN' || '%'
ORDER BY key
LIMIT 50;
-- @end

-- @id: all_keys
SELECT key, text FROM recognition_keys
ORDER BY key
LIMIT 200;
-- @end

-- @id: count_keys
SELECT COUNT(*) AS n FROM recognition_keys;
-- @end
