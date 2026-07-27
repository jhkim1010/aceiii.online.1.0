-- ============================================================================
-- Phase 63 Wave A — 부하 테스트 시드 (스테이징 DB 전용)
--
-- lt_vu_1..N 테스트 유저 생성 + 세션 보안 사전등록 (IP / 디바이스 fingerprint)
--   · active_sessions 는 유저당 1개(UNIQUE user_id) → VU 마다 별도 유저 필수
--   · branch_ip_registries 에 테스트 소스 IP 사전등록 (미등록 IP 는 로그인 차단)
--   · terminal_devices 에 lt-fp-<n> fingerprint 사전등록 (미등록 디바이스 차단)
--
-- 실행 (운영 서버, 스테이징 DB 에만):
--   sudo -u postgres psql -p 5434 -d ventago_staging \
--     -v template_user_id=<POS유저ID> -v n_users=3000 -v test_ip='62.72.7.245' \
--     -v ON_ERROR_STOP=1 -f seed-staging.sql
--
--   template_user_id: 복제 원본이 될 실제 POS 유저 (같은 password 해시 재사용 —
--     비밀번호를 알아야 하므로, 먼저 스테이징에서 해당 유저 비번을 loadtest123 으로
--     변경 권장: UPDATE users SET password='<bcrypt(loadtest123)>' WHERE id=...)
-- ============================================================================

-- ★ 안전장치: 운영 DB(ventago)에서 실행되면 즉시 중단
DO $$
BEGIN
  IF current_database() <> 'ventago_staging' THEN
    RAISE EXCEPTION '이 스크립트는 ventago_staging 전용입니다. 현재 DB: %', current_database();
  END IF;
END $$;

BEGIN;

-- 1) 테스트 유저 N명 생성 (템플릿 유저의 store/branch/password 복제)
INSERT INTO users (name, last_name, username, email, password, status, is_verified,
                   store_id, branch_id, created_at, updated_at)
SELECT
  'LoadTest', 'VU' || g.n,
  'lt_vu_' || g.n,
  'lt_vu_' || g.n || '@loadtest.local',
  t.password,
  'active', TRUE,
  t.store_id, t.branch_id,
  NOW(), NOW()
FROM generate_series(1, :n_users) AS g(n)
CROSS JOIN (SELECT password, store_id, branch_id FROM users WHERE id = :template_user_id) t
ON CONFLICT DO NOTHING;

-- 2) 테스트 소스 IP 를 지점에 사전등록 (k6 실행 위치의 public IP)
INSERT INTO branch_ip_registries (public_ip, branch_id, store_id, registered_at, last_seen_at,
                                  created_at, updated_at)
SELECT :'test_ip', t.branch_id, t.store_id, NOW(), NOW(), NOW(), NOW()
FROM (SELECT store_id, branch_id FROM users WHERE id = :template_user_id) t
WHERE NOT EXISTS (
  SELECT 1 FROM branch_ip_registries r
  WHERE r.public_ip = :'test_ip' AND r.branch_id = t.branch_id
);

-- 로컬호스트 호출 대비 (k6 를 서버 안에서 127.0.0.1 로 실행하는 경우)
INSERT INTO branch_ip_registries (public_ip, branch_id, store_id, registered_at, last_seen_at,
                                  created_at, updated_at)
SELECT ip, t.branch_id, t.store_id, NOW(), NOW(), NOW(), NOW()
FROM (SELECT store_id, branch_id FROM users WHERE id = :template_user_id) t,
     unnest(ARRAY['127.0.0.1', '::1', '::ffff:127.0.0.1']) AS ip
WHERE NOT EXISTS (
  SELECT 1 FROM branch_ip_registries r WHERE r.public_ip = ip AND r.branch_id = t.branch_id
);

-- 3) 디바이스 fingerprint lt-fp-1..N 사전등록 (지점의 터미널에 라운드로빈 매핑)
WITH tmpl AS (
  SELECT u.store_id, u.branch_id FROM users u WHERE u.id = :template_user_id
),
terms AS (
  SELECT te.id, ROW_NUMBER() OVER (ORDER BY te.id) - 1 AS rn, COUNT(*) OVER () AS cnt
  FROM terminals te
  JOIN boxes b ON b.id = te.box_id
  JOIN tmpl ON b.branch_id = tmpl.branch_id
)
INSERT INTO terminal_devices (device_fingerprint, public_ip, terminal_id, branch_id, store_id,
                              registered_at, last_seen_at, created_at, updated_at)
SELECT
  'lt-fp-' || g.n,
  :'test_ip',
  (SELECT id FROM terms WHERE rn = (g.n - 1) % (SELECT cnt FROM terms LIMIT 1) LIMIT 1),
  tmpl.branch_id, tmpl.store_id,
  NOW(), NOW(), NOW(), NOW()
FROM generate_series(1, :n_users) AS g(n), tmpl
ON CONFLICT DO NOTHING;

COMMIT;

-- 검증 조회
SELECT
  (SELECT COUNT(*) FROM users WHERE username LIKE 'lt_vu_%')            AS lt_users,
  (SELECT COUNT(*) FROM terminal_devices WHERE device_fingerprint LIKE 'lt-fp-%') AS lt_devices,
  (SELECT COUNT(*) FROM branch_ip_registries WHERE public_ip = :'test_ip')        AS ip_regs;
