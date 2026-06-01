-- ============================================================================
-- Phase 37 — vendedor scope 진단 SQL (운영 PG10 / DB: ventago / owner: coolsistema)
-- ============================================================================
-- 목적: vendedor role 사용자 중 모바일 앱 활성화 시 scope 결정 불가능한
--      사용자(branch_id NULL + user_branches 매핑 없음)를 찾아 Plan 37-01
--      backfill 마이그레이션 SQL 범위를 결정한다.
--
-- 실행: SELECT 전용 — 운영 데이터 변경 없음. 사용자 확인 없이 안전.
--
-- 가정 (코드 확인 완료 2026-05-31):
--   - vendedor 식별: roles.slug = 'vendedor' (Role 모델 slug 컬럼)
--   - 다대다 매핑: user_roles(user_id, role_id)
--   - 1지점 레거시: users.branch_id (NULLable, Phase 33 deprecate 진행 중)
--   - 다지점 (Phase 33): user_branches(user_id, branch_id, role_id, valid_until)
--   - Phase 33 valid 매핑 조건: valid_until IS NULL OR valid_until > NOW()
--   - 매장 lifecycle (Phase 9 미적용 가능성) — stores.lifecycle_state 컬럼 없으면 무시
--   - users 활성 조건: status = 'active' (ENUM: active/inactive/trial/suspended)
--     (운영 PG10 에 is_active 컬럼 없음 — 1차 진단에서 확인됨)
-- ============================================================================

\echo '=== Q0: 사전 스키마 확인 ==='
\echo '--- users.branch_id / store_id / status 컬럼 존재 여부 ---'
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name IN ('branch_id', 'store_id', 'status', 'last_login_at');

\echo '--- user_branches 테이블 존재 여부 (Phase 33) ---'
SELECT COUNT(*) AS user_branches_exists
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'user_branches';

\echo '--- roles 테이블 컬럼 ---'
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'roles'
ORDER BY ordinal_position;

\echo ''
\echo '=== Q1: vendedor role 사용자 총 수 (매장별 + global) ==='
SELECT
  COALESCE(r.store_id::text, 'GLOBAL') AS store_scope,
  r.id AS role_id,
  r.name AS role_name,
  r.slug AS role_slug,
  COUNT(DISTINCT ur.user_id) AS vendedor_user_count
FROM roles r
LEFT JOIN user_roles ur ON ur.role_id = r.id
WHERE r.slug = 'vendedor'
GROUP BY r.id, r.store_id, r.name, r.slug
ORDER BY r.store_id NULLS FIRST, r.id;

\echo ''
\echo '=== Q2: 매장별 vendedor 사용자 분포 (활성 유저만) ==='
SELECT
  u.store_id,
  s.name AS store_name,
  COUNT(DISTINCT u.id) AS active_vendedor_users
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id
LEFT JOIN stores s ON s.id = u.store_id
WHERE r.slug = 'vendedor'
  AND (u.status = 'active') = true
GROUP BY u.store_id, s.name
ORDER BY active_vendedor_users DESC, u.store_id;

\echo ''
\echo '=== Q3: vendedor scope 분류 (모바일 활성화 가능 여부) ==='
-- 핵심 진단. 각 vendedor 사용자가 다음 4 bucket 중 어디 속하는지 분류:
--   A. SAFE         — user_branches 에 valid 매핑 N개 (Phase 33 정합)
--   B. LEGACY_OK    — user_branches 없음, 단 users.branch_id NOT NULL (구식 1지점)
--   C. NEEDS_BACKFILL — users.branch_id NULL, user_branches 0 → 모바일 로그인 401 위험
--   D. UNUSABLE     — store_id 도 NULL (이상 데이터, 운영 미사용 가능)
WITH vendedor_users AS (
  SELECT DISTINCT u.id AS user_id, u.store_id, u.branch_id, u.name AS user_name,
         u.email, (u.status = 'active') AS is_active
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.slug = 'vendedor'
),
ub_count AS (
  SELECT user_id, COUNT(*) AS valid_user_branches
  FROM user_branches
  WHERE (valid_until IS NULL OR valid_until > NOW())
  GROUP BY user_id
)
SELECT
  CASE
    WHEN vu.store_id IS NULL THEN 'D. UNUSABLE'
    WHEN COALESCE(ubc.valid_user_branches, 0) > 0 THEN 'A. SAFE'
    WHEN vu.branch_id IS NOT NULL THEN 'B. LEGACY_OK'
    ELSE 'C. NEEDS_BACKFILL'
  END AS bucket,
  COUNT(*) AS user_count,
  COUNT(*) FILTER (WHERE vu.is_active) AS active_user_count
FROM vendedor_users vu
LEFT JOIN ub_count ubc ON ubc.user_id = vu.user_id
GROUP BY 1
ORDER BY 1;

\echo ''
\echo '=== Q4: NEEDS_BACKFILL bucket 상세 (모바일 활성화 불가 사용자 명단) ==='
-- 이 명단이 Plan 37-01 마이그레이션 backfill 의 직접 대상.
-- 운영 vendedor 중 모바일 로그인 시 401 VENDEDOR_SCOPE_NOT_DEFINED 가 떨어질 사용자.
WITH vendedor_users AS (
  SELECT DISTINCT u.id AS user_id, u.store_id, u.branch_id,
         u.name AS user_name, u.email, (u.status = 'active') AS is_active,
         u.created_at
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.slug = 'vendedor'
),
ub_count AS (
  SELECT user_id, COUNT(*) AS valid_user_branches
  FROM user_branches
  WHERE (valid_until IS NULL OR valid_until > NOW())
  GROUP BY user_id
)
SELECT
  vu.user_id,
  vu.user_name,
  vu.email,
  vu.store_id,
  s.name AS store_name,
  vu.is_active,
  vu.created_at::date AS created
FROM vendedor_users vu
LEFT JOIN ub_count ubc ON ubc.user_id = vu.user_id
LEFT JOIN stores s ON s.id = vu.store_id
WHERE vu.store_id IS NOT NULL
  AND COALESCE(ubc.valid_user_branches, 0) = 0
  AND vu.branch_id IS NULL
ORDER BY vu.is_active DESC, vu.store_id, vu.user_id;

\echo ''
\echo '=== Q5: LEGACY_OK bucket — Phase 33 user_branches 로 자동 backfill 가능한 사용자 ==='
-- 이 사용자들은 users.branch_id 가 명확히 있으므로 user_branches 1 row 자동 생성 가능.
-- Plan 37-01 의 마이그레이션 SQL 이 INSERT INTO user_branches (user_id, branch_id, role_id) SELECT ... 로 처리.
WITH vendedor_users AS (
  SELECT DISTINCT u.id AS user_id, u.store_id, u.branch_id, u.name AS user_name,
         (u.status = 'active') AS is_active,
         ur.role_id
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.slug = 'vendedor'
),
ub_count AS (
  SELECT user_id, COUNT(*) AS valid_user_branches
  FROM user_branches
  WHERE (valid_until IS NULL OR valid_until > NOW())
  GROUP BY user_id
)
SELECT
  COUNT(*) AS legacy_ok_total,
  COUNT(*) FILTER (WHERE vu.is_active) AS legacy_ok_active,
  COUNT(DISTINCT vu.store_id) AS distinct_stores,
  COUNT(DISTINCT vu.branch_id) AS distinct_branches
FROM vendedor_users vu
LEFT JOIN ub_count ubc ON ubc.user_id = vu.user_id
WHERE vu.store_id IS NOT NULL
  AND COALESCE(ubc.valid_user_branches, 0) = 0
  AND vu.branch_id IS NOT NULL;

\echo ''
\echo '=== Q6: 다지점 vendedor 존재 여부 (D-05 scope-set 함정 대비) ==='
-- vendedor 가 이미 user_branches 에 2 row 이상이면 모바일 UI 에 branch selector 가 필요.
-- 이 결과가 0이면 "1 vendedor 1 branch" 단순화 가능, >0 이면 multi-branch UI 부터.
WITH vendedor_users AS (
  SELECT DISTINCT u.id AS user_id
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.slug = 'vendedor'
)
SELECT
  vu.user_id,
  u.name AS user_name,
  COUNT(*) AS valid_branch_count,
  ARRAY_AGG(ub.branch_id ORDER BY ub.branch_id) AS branch_ids
FROM vendedor_users vu
JOIN users u ON u.id = vu.user_id
JOIN user_branches ub ON ub.user_id = vu.user_id
WHERE (ub.valid_until IS NULL OR ub.valid_until > NOW())
GROUP BY vu.user_id, u.name
HAVING COUNT(*) > 1
ORDER BY valid_branch_count DESC, vu.user_id;

\echo ''
\echo '=== Q7: users.branch_id 가 가리키는 branch 가 store_id 와 정합한가? ==='
-- LEGACY_OK 자동 backfill 의 안전성 검증. branch.store_id != users.store_id 면 위험.
WITH vendedor_users AS (
  SELECT DISTINCT u.id AS user_id, u.store_id AS user_store_id, u.branch_id, u.name AS user_name
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.slug = 'vendedor'
)
SELECT
  vu.user_id,
  vu.user_name,
  vu.user_store_id,
  vu.branch_id,
  b.store_id AS branch_store_id,
  CASE WHEN b.store_id = vu.user_store_id THEN 'OK' ELSE 'MISMATCH ⚠' END AS check_result
FROM vendedor_users vu
LEFT JOIN branches b ON b.id = vu.branch_id
WHERE vu.branch_id IS NOT NULL
  AND (b.store_id IS NULL OR b.store_id <> vu.user_store_id)
ORDER BY vu.user_id;

\echo ''
\echo ''
\echo '=== Q7b: 운영 role 전체 분포 (vendedor 0명 후속 진단) ==='
-- 1차 진단에서 vendedor user_count = 0 확인됨.
-- 운영에서 실제로 "판매 인력" 을 어떤 role 로 운용하고 있는지 파악.
SELECT
  r.id,
  r.name,
  r.slug,
  r.store_id,
  COALESCE(s.name, 'GLOBAL') AS store_name,
  COUNT(DISTINCT ur.user_id) AS user_count,
  COUNT(DISTINCT ur.user_id) FILTER (WHERE u.status = 'active') AS active_user_count
FROM roles r
LEFT JOIN user_roles ur ON ur.role_id = r.id
LEFT JOIN users u ON u.id = ur.user_id
LEFT JOIN stores s ON s.id = r.store_id
GROUP BY r.id, r.name, r.slug, r.store_id, s.name
ORDER BY r.store_id NULLS FIRST, r.id;

\echo ''
\echo '=== Q7c: sellers 테이블 분포 (User.AfterCreate hook 으로 자동 생성됨) ==='
-- code: Users.AfterCreate → Seller(linkedUserId) 자동 생성.
-- linked_user_id IS NULL 이면 user 없는 순수 판매원 (수동 등록).
-- linked_user_id IS NOT NULL 이면 user 와 1:1 연결된 판매원.
SELECT
  s.store_id,
  st.name AS store_name,
  COUNT(*) AS total_sellers,
  COUNT(*) FILTER (WHERE s.is_active = true) AS active_sellers,
  COUNT(*) FILTER (WHERE s.linked_user_id IS NOT NULL) AS linked_to_user,
  COUNT(*) FILTER (WHERE s.linked_user_id IS NULL) AS standalone_sellers
FROM sellers s
LEFT JOIN stores st ON st.id = s.store_id
GROUP BY s.store_id, st.name
ORDER BY s.store_id;

\echo ''
\echo '=== Q7d: User-Seller 연결 정합성 (linked seller 의 user role 확인) ==='
-- linked seller 의 user 가 어떤 role 을 갖고 있는지.
-- 이 user 들이 모바일 앱의 1차 대상이 될 가능성 높음.
SELECT
  COALESCE(r.slug, '(no_role)') AS user_role_slug,
  COUNT(DISTINCT s.id) AS linked_sellers
FROM sellers s
JOIN users u ON u.id = s.linked_user_id
LEFT JOIN user_roles ur ON ur.user_id = u.id
LEFT JOIN roles r ON r.id = ur.role_id
WHERE s.linked_user_id IS NOT NULL
  AND s.is_active = true
  AND u.status = 'active'
GROUP BY r.slug
ORDER BY linked_sellers DESC;

\echo ''
\echo '=== Q8: 요약 메트릭 (Plan 37-01 범위 결정용) ==='
WITH vendedor_users AS (
  SELECT DISTINCT u.id AS user_id, u.store_id, u.branch_id, (u.status = 'active') AS is_active
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  WHERE r.slug = 'vendedor'
),
ub_count AS (
  SELECT user_id, COUNT(*) AS valid_user_branches
  FROM user_branches
  WHERE (valid_until IS NULL OR valid_until > NOW())
  GROUP BY user_id
),
classified AS (
  SELECT
    CASE
      WHEN vu.store_id IS NULL THEN 'D_UNUSABLE'
      WHEN COALESCE(ubc.valid_user_branches, 0) > 0 THEN 'A_SAFE'
      WHEN vu.branch_id IS NOT NULL THEN 'B_LEGACY_OK'
      ELSE 'C_NEEDS_BACKFILL'
    END AS bucket,
    vu.is_active
  FROM vendedor_users vu
  LEFT JOIN ub_count ubc ON ubc.user_id = vu.user_id
)
SELECT
  COUNT(*) AS total_vendedor,
  COUNT(*) FILTER (WHERE is_active) AS active_total,
  COUNT(*) FILTER (WHERE bucket = 'A_SAFE') AS a_safe,
  COUNT(*) FILTER (WHERE bucket = 'B_LEGACY_OK') AS b_legacy_ok,
  COUNT(*) FILTER (WHERE bucket = 'C_NEEDS_BACKFILL') AS c_needs_backfill,
  COUNT(*) FILTER (WHERE bucket = 'D_UNUSABLE') AS d_unusable,
  COUNT(*) FILTER (WHERE bucket = 'B_LEGACY_OK' AND is_active) AS b_legacy_ok_active,
  COUNT(*) FILTER (WHERE bucket = 'C_NEEDS_BACKFILL' AND is_active) AS c_needs_backfill_active
FROM classified;
