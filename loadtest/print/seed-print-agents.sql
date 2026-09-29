-- 출력 부하 시험 — 더미 매장(DUMMY-*)마다 가상 comandera 1대 + 그 지점 터미널의 기본 프린터로 배정.
-- ventago_loadtest / ventago_staging 전용. api_key = 'lt-agent-<branchId>' (agent-sim.js 가 읽는다).
DO $$
BEGIN
  IF current_database() NOT IN ('ventago_staging', 'ventago_loadtest') THEN
    RAISE EXCEPTION '출력 부하 시드는 시험 DB 전용입니다. 현재 DB: %', current_database();
  END IF;
END $$;

BEGIN;
INSERT INTO branch_agents (branch_id, agent_type, label, api_key, is_online, created_at, updated_at)
SELECT b.id, 'thermal', 'lt-comandera', 'lt-agent-' || b.id, false, now(), now()
  FROM branches b JOIN stores s ON s.id = b.store_id
 WHERE s.name LIKE 'DUMMY-%'
   AND NOT EXISTS (SELECT 1 FROM branch_agents a WHERE a.api_key = 'lt-agent-' || b.id);

UPDATE terminals t
   SET thermal_agent_id = a.id
  FROM boxes bx
  JOIN branch_agents a ON a.branch_id = bx.branch_id AND a.api_key = 'lt-agent-' || bx.branch_id
 WHERE t.box_id = bx.id;
COMMIT;

\pset tuples_only on
\pset format unaligned
\o print/agent-keys.txt
SELECT a.id || ',' || a.api_key
  FROM branch_agents a JOIN branches b ON b.id = a.branch_id JOIN stores s ON s.id = b.store_id
 WHERE s.name LIKE 'DUMMY-%' ORDER BY a.id;
\o
SELECT count(*) AS agentes FROM branch_agents WHERE api_key LIKE 'lt-agent-%';
