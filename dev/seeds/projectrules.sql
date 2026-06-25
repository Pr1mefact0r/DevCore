-- DevCore v3.0 — projectrules seed (25 core + 3 optional runtime-layer = 28 rules)
-- Applied once on first bootstrap (after schema.sql) by run-dev-query.sh.
-- These are the agent's operating discipline for the brain-graph. Rule texts are English
-- (DB content); codes are template-new sequential with upstream provenance in source_ref (←PRxx).
-- Anti-bloat (←PR021): deliberately terse — no incident history. INSERT OR IGNORE = idempotent re-bootstrap.

INSERT OR IGNORE INTO projectrules (date, code, scope, title, rule, source_ref) VALUES
('2026-06-25','PR001','[DEV]','Data Quality first',
 'Never ship changes that could degrade DB quality; flag quality-degrading requests instead of silently building; back up affected tables before any destructive UPDATE/DELETE and verify.','←PR001'),

('2026-06-25','PR002','[DEV]','Mechanical-first',
 'Solve deterministically (code+SQL+math) where possible; reserve LLM calls for semantic extraction, judgement calls structured rules cannot cover, and creative output — never for counters, threshold checks, status transitions, or aggregation. Prefer a DB-level CHECK/trigger over app validation.','←PR003'),

('2026-06-25','PR003','[DEV]','Schema-source parity',
 'Every schema change reaches BOTH the live documentation.db AND schema.sql, so a fresh install inherits it; use idempotent DDL (IF NOT EXISTS).','←PR004'),

('2026-06-25','PR004','[DEV]','Code-before-text',
 'The first DB call is the allocator (next_*_code); capture the code, then write the referencing prose; resolve crosslinks via get_*_by_code, never hand-type ids; for Q/RS/I/IDEA reuse-before-mint the recognition_key.','←PR005'),

('2026-06-25','PR005','[DEV]','Brain is single source of truth',
 'A query-decidable question is arbitrated by a read-only query (write one if none exists); judgement/design/priority is the operator''s call — lay out a balanced brief and withhold the recommendation until asked.','←PR007'),

('2026-06-25','PR006','[DEV]','Transient analysis never mutates a canonical artifact',
 'A one-off analysis uses a throwaway script — never edit a query/schema/skill for a one-off result; a recurring analysis is promoted to a named repo query.','←PR009'),

('2026-06-25','PR007','[DEV]','Simulate-first',
 'Before a mechanically-computable change: compute it read-only on real data, show the before→after projection, give a data-grounded recommendation, and execute only after the operator decides.','←PR010'),

('2026-06-25','PR008','[DEV]','Simplicity + reuse',
 'Prefer extending a proven path (flag/parameter/gate) over a new parallel mechanism; the smallest diff that meets the requirement wins.','←PR011'),

('2026-06-25','PR009','[DEV]','Provenance-trace before asserting/changing',
 'Trace the full provenance + read/effect path through the graph (loop-safe: visited-set + depth-cap) before a confident claim or a change; a claim is a hypothesis until the trace carries it; surface conflicts first.','←PR012'),

('2026-06-25','PR010','[DEV]','No state without its why',
 'Every state-changing write carries its reason readable IN the record, not only reconstructable from logs; the mechanism enforces it (fail-loud).','←PR014'),

('2026-06-25','PR011','[DEV]','No new/changed rule without operator-OK',
 'A "this should be a rule" reflex is PROPOSED (rationale + wording), never autonomously inserted; the operator decides the judgement, the brain arbitrates facts (search for a duplicate/contradiction first).','←PR016'),

('2026-06-25','PR012','[DEV]','Watchdogs are brain-anchored + self-healing',
 'A reminder with a machine-checkable trigger arms a watchdog whose alarm-state lives in the record (watchdog_spec + watchdog_fired_at); at session-start, re-arm dead ones and surface fired ones; the executor is the project''s choice.','←PR017'),

('2026-06-25','PR013','[DEV]','Shared-query consumer check',
 'Before extending a query read from multiple sites, list all consumers and prove none breaks; make it additive/shape-preserving, or harden consumers to named columns first.','←PR018'),

('2026-06-25','PR014','[DEV]','Adjudication-first',
 'On any anomaly/recurring question: recall first; on a hit cite AND revalidate (never blind-cite stale); on a newly settled question crystallize it (Q### fact / RS### precedent); reuse-before-mint the key; wire typed edges.','←PR019'),

('2026-06-25','PR015','[DEV]','Guard fixes the source, not the symptom',
 'Guard corruption at its source (write-time CHECK/FK/trigger) and make the symptom safe separately; a guard that only quiets a failure is a smell.','←PR020'),

('2026-06-25','PR016','[DEV]','Rule-evolution: hardening vs new law',
 'Same core concern → an inline addition; a new concern → a new node + typed ref, never restate a neighbour rule. Keep the rule layer normalized.','←PR021'),

('2026-06-25','PR017','[DEV]','Edge direction + predicate convention',
 'One directed edge per relationship, queryable from both ends (never a reciprocal pair); direction follows the genesis arrow (upstream: raised/investigates/produced/answers/crystallized/validates/refutes/informs; downstream: relates/documents/references); same-type supersession via the superseded_by column.','←PR022'),

('2026-06-25','PR018','[DEV]','Persist, don''t note',
 'A "done/logged/fixed/wired" claim is a hypothesis until proven by a durable row (cite the code / the returned id); "noted" in chat without a row is a false-persistence claim.','←PR023'),

('2026-06-25','PR019','[DEV]','Build-time relation analysis',
 'Before a build touching a coded node or a skill/schema/query, query the typed edges around it to surface dependencies + stumbling blocks; the edge graph IS the dependency map.','←PR024'),

('2026-06-25','PR020','[DEV]','Deep-recall on should-know instructions',
 'When an instruction presupposes prior knowledge, search the brain then follow refs transitively until the surface closes, before acting.','←PR025'),

('2026-06-25','PR021','[DEV]','Braincode comments are graph entrypoints',
 'Resolve a braincode in a comment (get_*_by_code → edges) and read current state; never trust the aging comment; an unresolvable code is itself a finding; new comments carry a minimal gloss + the code; retrieve the enclosing comment block (grep -B/-C, not -A alone).','←PR026'),

('2026-06-25','PR022','[DEV]','Channel/store language split',
 'Operator-facing output is in the project''s operator language (set by the repo language marker file); persisted DB free-text is in one portable record language (English); technical identifiers (tables, paths, SQL, query-ids, codes) stay English in both.','←PR027'),

('2026-06-25','PR023','[DEV]','Post-change graph reconciliation',
 'A change that implements/supersedes/invalidates a node''s subject reconciles the graph in the SAME change (implemented NT → done, obsoleted decision → superseded, stale ref → re-wire/flag).','←PR029'),

('2026-06-25','PR024','[DEV]','Evolution/provenance from the timeline',
 'For how-did-this-come-to-be questions, reconstruct the date-ordered brain timeline (changelog + decisions + observations) until the sequence closes; flat code shows state, not evolution.','←PR030'),

('2026-06-25','PR025','[DEV]','Hook output is binding',
 'Comply with hook surfacing, or give an explicit why-on-skip (out-of-scope / already-done / false-positive); never a memory-asserted "looks fine", never a silent pass; carry a deliberate skip into the summary on long tasks.','←PR031');

-- Optional block — runtime-layer rules. The TEMPLATE ships them active; a backporting project
-- WITHOUT a runtime loop/handler can retire them (retire_projectrule). Marked via rationale.
INSERT OR IGNORE INTO projectrules (date, code, scope, title, rule, rationale, source_ref) VALUES
('2026-06-25','PR026','[DEV]','Query-sample validity',
 'Cite the window; a fit on a non-stationary/unrepresentative sample is a hypothesis, not a verdict; never freeze such a fit into a write path without out-of-sample / live validation.',
 'Optional — applies only to projects with a runtime data/decision loop; retire if not applicable.','←PR008'),

('2026-06-25','PR027','[DEV]','Runtime-loop changes are pending-live-verification',
 'A change to a runtime loop/handler is shipped-pending-verify (not fixed) until a watchdog catches the first live event and the dev semantically confirms it did the right thing.',
 'Optional — applies only to projects with a runtime loop/handler; retire if not applicable.','←PR015'),

('2026-06-25','PR028','[DEV]','Monitor home by time-semantics',
 'Discrete/bounded trigger → a brain-anchored watchdog; a continuous 24/7 monitor → a co-process service, not a per-session watchdog.',
 'Optional — applies only to projects that run continuous monitors; retire if not applicable.','←PR028');
