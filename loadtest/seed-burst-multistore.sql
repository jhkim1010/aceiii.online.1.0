-- ============================================================================
-- Phase 63 — 다매장 동시 판매 버스트 테스트 시드 (스테이징 전용)
--
-- 여러 매장이 동시에(0.1~1초 간격) 판매를 발생시킬 때
--   · 매장별 daily_number 채번이 충돌/중복되지 않는지
--   · 요청 수 = DB 저장 수 인지 (누락 없음)
-- 를 검증하기 위해 매장마다 테스트 유저/디바이스를 생성한다.
--
-- 유저명 규칙: lt_s<storeId>_<n>   (예: lt_s6_1)
-- fingerprint: lt-s<storeId>-fp-<n>
-- 비밀번호   : loadtest123 (고정 bcrypt 해시 — 실제 유저 비번은 건드리지 않음)
--
-- 실행:
--   psql -h 127.0.0.1 -p 6432 -U coolsistema -d ventago_staging \
--     -v n_per_store=10 -v ON_ERROR_STOP=1 -f seed-burst-multistore.sql
-- ============================================================================

-- ★ 안전장치: 스테이징 외 DB 에서는 즉시 중단
DO $$
BEGIN
  IF current_database() <> 'ventago_staging' THEN
    RAISE EXCEPTION '이 스크립트는 ventago_staging 전용입니다. 현재 DB: %', current_database();
  END IF;
END $$;

BEGIN;

-- 대상 매장 자동 선별
--   · deleted_at IS NULL      — 소프트 삭제 매장은 로그인 자체가 401 'Tienda no disponible'
--                                (실측 2026-07-26: 3/8/10/11/14 는 2026-07-23 삭제됨)
--   · is_active               — 비활성 매장도 로그인 불가
--   · 상품/고객/터미널 보유    — 판매 생성에 필수
CREATE TEMP TABLE _target_stores ON COMMIT DROP AS
SELECT s.id AS store_id,
       (SELECT b.id FROM branches b WHERE b.store_id = s.id ORDER BY b.is_main DESC NULLS LAST, b.id LIMIT 1) AS branch_id
FROM stores s
WHERE s.deleted_at IS NULL
  AND COALESCE(s.is_active, FALSE)
  AND EXISTS (SELECT 1 FROM products p WHERE p.store_id = s.id)
  AND EXISTS (SELECT 1 FROM clients c WHERE c.store_id = s.id)
  AND EXISTS (
    SELECT 1 FROM terminals te JOIN boxes b ON b.id = te.box_id
    JOIN branches br ON br.id = b.branch_id WHERE br.store_id = s.id
  )
  AND EXISTS (
    SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id = u.id
    WHERE u.store_id = s.id AND u.username NOT LIKE 'lt\_%'
  );

-- 1) 매장별 테스트 유저 생성 (비번은 고정 해시 = loadtest123)
INSERT INTO users (name, last_name, username, email, password, status, is_verified,
                   store_id, branch_id, created_at, updated_at)
SELECT
  'Burst', 'S' || t.store_id || 'T' || g.n,
  'lt_s' || t.store_id || '_' || g.n,
  'lt_s' || t.store_id || '_' || g.n || '@loadtest.local',
  '$2b$10$6/tO6BZH58ObguhO3D2QxubztgDZNfS5WmcX1rlKHYFNL8qNWXgzW',
  'active', TRUE,
  t.store_id, t.branch_id,
  NOW(), NOW()
FROM _target_stores t
CROSS JOIN generate_series(1, :n_per_store) AS g(n)
WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.username = 'lt_s' || t.store_id || '_' || g.n
);

-- 2) 역할 부여 — 같은 매장의 기존(비테스트) 유저가 가진 역할을 그대로 복제
INSERT INTO user_roles (user_id, role_id, created_at, updated_at)
SELECT lt.id, src.role_id, NOW(), NOW()
FROM users lt
JOIN _target_stores t ON t.store_id = lt.store_id
CROSS JOIN LATERAL (
  SELECT ur.role_id
  FROM users u2
  JOIN user_roles ur ON ur.user_id = u2.id
  WHERE u2.store_id = t.store_id AND u2.username NOT LIKE 'lt\_%'
  ORDER BY u2.id
  LIMIT 1
) src
WHERE lt.username LIKE 'lt\_s' || t.store_id || '\_%'
  AND NOT EXISTS (
    SELECT 1 FROM user_roles ur2 WHERE ur2.user_id = lt.id AND ur2.role_id = src.role_id
  );

-- 3) 디바이스 fingerprint 등록 (매장 지점의 터미널에 라운드로빈)
INSERT INTO terminal_devices (device_fingerprint, public_ip, terminal_id, branch_id, store_id,
                              registered_at, last_seen_at, created_at, updated_at)
SELECT
  'lt-s' || t.store_id || '-fp-' || g.n,
  '127.0.0.1',
  term.id,
  t.branch_id, t.store_id,
  NOW(), NOW(), NOW(), NOW()
FROM _target_stores t
CROSS JOIN generate_series(1, :n_per_store) AS g(n)
CROSS JOIN LATERAL (
  SELECT te.id
  FROM terminals te
  JOIN boxes b ON b.id = te.box_id
  WHERE b.branch_id = t.branch_id
  ORDER BY te.id
  OFFSET (g.n - 1) % GREATEST((SELECT count(*) FROM terminals te2
                               JOIN boxes b2 ON b2.id = te2.box_id
                               WHERE b2.branch_id = t.branch_id), 1)
  LIMIT 1
) term
WHERE NOT EXISTS (
  SELECT 1 FROM terminal_devices td
  WHERE td.device_fingerprint = 'lt-s' || t.store_id || '-fp-' || g.n
);

-- 4) 각 매장 지점에 테스트 IP 등록 (미등록 IP 는 로그인 차단됨)
INSERT INTO branch_ip_registries (public_ip, branch_id, store_id, registered_at, last_seen_at,
                                  created_at, updated_at)
SELECT ip, t.branch_id, t.store_id, NOW(), NOW(), NOW(), NOW()
FROM _target_stores t,
     unnest(ARRAY['127.0.0.1', '::1', '::ffff:127.0.0.1', '172.18.0.1', '::ffff:172.18.0.1']) AS ip
WHERE NOT EXISTS (
  SELECT 1 FROM branch_ip_registries r
  WHERE r.public_ip = ip AND r.store_id = t.store_id
);

COMMIT;

-- 검증
SELECT u.store_id,
       count(*) AS users,
       count(DISTINCT td.id) AS devices,
       (SELECT count(*) FROM user_roles ur WHERE ur.user_id = ANY(array_agg(u.id))) AS roles
FROM users u
LEFT JOIN terminal_devices td
  ON td.device_fingerprint = 'lt-s' || u.store_id || '-fp-' ||
     split_part(u.username, '_', 3)
WHERE u.username LIKE 'lt\_s%'
GROUP BY u.store_id
ORDER BY u.store_id;
