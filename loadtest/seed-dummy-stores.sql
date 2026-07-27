-- ============================================================================
-- Phase 63 — 더미 매장 N개 생성 (스테이징 전용)
--
-- 300매장 규모를 향한 중간 검증용. 판매가 실제로 가능한 최소 구조를
-- 기존 정상 매장(TEMPLATE_STORE = 6)에서 복제한다.
--
-- 복제 대상:
--   stores → store_configs → store_apps → branches → boxes → terminals(3)
--          → roles(Vendedor) + role_functions + role_function_actions
--          → categories → products(+ProductBranch+stocks) → clients
--   그리고 매장별 테스트 유저(lt_s<store>_<n>) + terminal_devices + IP 등록
--
-- 유저/디바이스 명명 규칙이 seed-burst-multistore.sql 과 동일하므로
-- burst-multistore.js 를 그대로 사용할 수 있다.
--
-- 실행:
--   psql -h 127.0.0.1 -p 6432 -U coolsistema -d ventago_staging \
--     -v n_stores=20 -v n_users=10 -v n_products=20 -v ON_ERROR_STOP=1 \
--     -f seed-dummy-stores.sql
--
-- 되돌리기: cleanup-dummy-stores.sql
-- ============================================================================

DO $$
BEGIN
  IF current_database() <> 'ventago_staging' THEN
    RAISE EXCEPTION '이 스크립트는 ventago_staging 전용입니다. 현재 DB: %', current_database();
  END IF;
END $$;

BEGIN;

CREATE TEMP TABLE _cfg ON COMMIT DROP AS
SELECT 6::int AS tpl_store,
       :n_stores::int   AS n_stores,
       :n_users::int    AS n_users,
       :n_products::int AS n_products;

CREATE TEMP TABLE _new_stores (store_id int, seq int, branch_id int, box_id int,
                               role_id int, category_id int, client_id int) ON COMMIT DROP;

-- ── 1) 매장 골격 생성 (매장 단위로 순차 처리 — id 추적이 명확) ─────────────
DO $$
DECLARE
  cfg        RECORD;
  i          int;
  v_store    int;
  v_cfg_id   int;
  v_branch   int;
  v_box      int;
  v_role     int;
  v_cat      int;
  v_client   int;
  v_tpl_role int;
  nm         text;
  cols_store text;
  cols_cfg   text;
BEGIN
  SELECT * INTO cfg FROM _cfg;

  -- 행 복제용 컬럼 목록 — 다음은 제외한다.
  --   · id           : 시퀀스가 새로 발급
  --   · 생성 컬럼    : slug_canonical (INSERT 불가)
  --   · 고유 식별자  : name/alias_name/slug/cuit — 복제하면 UNIQUE 위반
  --                    (uq_stores_slug / uq_stores_alias_lower). NULL 로 두고 아래 UPDATE 에서 설정.
  -- 컬럼이 추가돼도 자동 반영되도록 information_schema 에서 매번 계산한다.
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
  INTO cols_store
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'stores'
    AND is_generated = 'NEVER'
    AND column_name <> ALL (ARRAY['id', 'name', 'alias_name', 'slug', 'cuit']);

  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
  INTO cols_cfg
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'store_configs'
    AND is_generated = 'NEVER' AND column_name <> 'id';

  -- 템플릿 매장의 Vendedor 역할 (권한 복제 원본)
  SELECT r.id INTO v_tpl_role
  FROM roles r WHERE r.store_id = cfg.tpl_store AND r.name = 'Vendedor' LIMIT 1;

  IF v_tpl_role IS NULL THEN
    RAISE EXCEPTION '템플릿 매장 % 에 Vendedor 역할이 없습니다', cfg.tpl_store;
  END IF;

  FOR i IN 1..cfg.n_stores LOOP
    nm := 'DUMMY-' || lpad(i::text, 2, '0');

    -- 매장: 템플릿 행 복제 후 식별자만 교체 (컬럼 추가에 강함)
    EXECUTE format(
      'INSERT INTO stores (%s) SELECT %s FROM stores WHERE id = $1 RETURNING id',
      cols_store, cols_store
    ) INTO v_store USING cfg.tpl_store;

    UPDATE stores
    SET name            = nm,
        alias_name      = nm,
        slug            = lower(nm),          -- uq_stores_slug (부분 UNIQUE)
                                              -- ※ slug_canonical 은 생성 컬럼이라 직접 설정 불가
                                              --   (slug 에서 자동 파생)
        cuit            = NULL,
        deleted_at      = NULL,
        is_active       = TRUE,
        created_at      = NOW(),
        updated_at      = NOW()
    WHERE id = v_store;

    -- 매장 설정
    EXECUTE format(
      'INSERT INTO store_configs (%s) SELECT %s FROM store_configs WHERE store_id = $1 LIMIT 1 RETURNING id',
      cols_cfg, cols_cfg
    ) INTO v_cfg_id USING cfg.tpl_store;

    UPDATE store_configs SET store_id = v_store, created_at = NOW(), updated_at = NOW()
    WHERE id = v_cfg_id;

    -- 앱 활성화 (템플릿과 동일 세트)
    INSERT INTO store_apps (store_id, app_id, enabled, created_at, updated_at,
                            trial_ends_at, billing_status)
    SELECT v_store, sa.app_id, sa.enabled, NOW(), NOW(), sa.trial_ends_at, sa.billing_status
    FROM store_apps sa WHERE sa.store_id = cfg.tpl_store;

    -- 지점 / 카하 / 터미널 3개
    INSERT INTO branches (name, is_active, is_main, is_warehouse, store_id, created_at, updated_at)
    VALUES (nm || ' Central', TRUE, TRUE, FALSE, v_store, NOW(), NOW())
    RETURNING id INTO v_branch;

    INSERT INTO boxes (name, store_id, branch_id, created_at, updated_at)
    VALUES ('Caja 1', v_store, v_branch, NOW(), NOW())
    RETURNING id INTO v_box;

    INSERT INTO terminals (name, box_id, store_id, created_at, updated_at)
    SELECT 'Terminal ' || g.n, v_box, v_store, NOW(), NOW()
    FROM generate_series(1, 3) AS g(n);

    -- 역할 + 권한 (163개 function 전량 복제)
    INSERT INTO roles (name, slug, store_id, created_at, updated_at)
    VALUES ('Vendedor', 'vendedor', v_store, NOW(), NOW())
    RETURNING id INTO v_role;

    -- ※ 템플릿 역할은 같은 function_id 를 지점(branch_id)별로 여러 행 가질 수 있으나
    --   role_functions 는 (role_id, function_id, store_id) UNIQUE 이므로
    --   function_id 당 1행만 복제한다(branch_id NULL = 전 지점).
    WITH tpl AS (
      SELECT DISTINCT ON (rf.function_id) rf.id, rf.function_id
      FROM role_functions rf
      WHERE rf.role_id = v_tpl_role
      ORDER BY rf.function_id, rf.id
    ),
    ins AS (
      INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
      SELECT v_role, tpl.function_id, v_store, NOW(), NOW()
      FROM tpl
      RETURNING id, function_id
    )
    INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
    SELECT DISTINCT ins.id, rfa.action, NOW(), NOW()
    FROM ins
    JOIN tpl ON tpl.function_id = ins.function_id
    JOIN role_function_actions rfa ON rfa.role_function_id = tpl.id;

    -- 카테고리
    -- ※ 실측: categories.status 는 integer(1=활성), is_active 는 NULL 허용.
    --   store_entity_id 는 NOT NULL 이며 매장 엔티티 식별자로 store_id 를 사용한다.
    INSERT INTO categories (name, status, store_id, store_entity_id, created_at, updated_at)
    VALUES ('General', 1, v_store, v_store, NOW(), NOW())
    RETURNING id INTO v_cat;

    -- 고객 (Consumidor Final)
    INSERT INTO clients (fullname, document, store_id, created_at, updated_at)
    VALUES ('Consumidor Final', '00000000', v_store, NOW(), NOW())
    RETURNING id INTO v_client;

    INSERT INTO _new_stores VALUES (v_store, i, v_branch, v_box, v_role, v_cat, v_client);
  END LOOP;
END $$;

-- ── 2) 상품 + 지점등록 + 재고 ────────────────────────────────────────────
CREATE TEMP TABLE _new_products (store_id int, product_id int) ON COMMIT DROP;

WITH ins AS (
  INSERT INTO products (name, description, sku, price, status, store_id, category_id,
                        is_generic, is_published_shop, created_at, updated_at)
  SELECT 'DUMMY P' || g.n || ' S' || ns.store_id,
         'load test product',
         'LT-' || ns.store_id || '-' || g.n,
         (1000 + g.n * 100)::numeric,
         'active',
         ns.store_id,
         ns.category_id,
         FALSE, FALSE, NOW(), NOW()
  FROM _new_stores ns
  CROSS JOIN generate_series(1, (SELECT n_products FROM _cfg)) AS g(n)
  RETURNING id, store_id
)
INSERT INTO _new_products SELECT store_id, id FROM ins;

-- 지점별 상품 등록 (판매 시 변형/재고 해석 경로)
CREATE TEMP TABLE _new_pb (product_branch_id int) ON COMMIT DROP;

WITH ins AS (
  INSERT INTO "ProductBranch" (product_id, branch_id, created_at, updated_at)
  SELECT np.product_id, ns.branch_id, NOW(), NOW()
  FROM _new_products np
  JOIN _new_stores ns ON ns.store_id = np.store_id
  RETURNING id
)
INSERT INTO _new_pb SELECT id FROM ins;

-- 초기 재고 (stocks 는 product_branch_id 기반)
INSERT INTO stocks (product_branch_id, stock, type, is_active, operation_date, created_at, updated_at)
SELECT pb.product_branch_id, 100000, 'adjust', TRUE, NOW(), NOW(), NOW()
FROM _new_pb pb;

-- ── 3) 테스트 유저 + 역할 + 디바이스 + IP ────────────────────────────────
INSERT INTO users (name, last_name, username, email, password, status, is_verified,
                   store_id, branch_id, created_at, updated_at)
SELECT 'Burst', 'S' || ns.store_id || 'T' || g.n,
       'lt_s' || ns.store_id || '_' || g.n,
       'lt_s' || ns.store_id || '_' || g.n || '@loadtest.local',
       '$2b$10$6/tO6BZH58ObguhO3D2QxubztgDZNfS5WmcX1rlKHYFNL8qNWXgzW',
       'active', TRUE, ns.store_id, ns.branch_id, NOW(), NOW()
FROM _new_stores ns
CROSS JOIN generate_series(1, (SELECT n_users FROM _cfg)) AS g(n);

INSERT INTO user_roles (user_id, role_id, created_at, updated_at)
SELECT u.id, ns.role_id, NOW(), NOW()
FROM users u
JOIN _new_stores ns ON ns.store_id = u.store_id
WHERE u.username LIKE 'lt\_s%';

INSERT INTO terminal_devices (device_fingerprint, public_ip, terminal_id, branch_id, store_id,
                              registered_at, last_seen_at, created_at, updated_at)
SELECT 'lt-s' || ns.store_id || '-fp-' || g.n,
       '127.0.0.1',
       (SELECT te.id FROM terminals te
        WHERE te.box_id = ns.box_id ORDER BY te.id OFFSET (g.n - 1) % 3 LIMIT 1),
       ns.branch_id, ns.store_id, NOW(), NOW(), NOW(), NOW()
FROM _new_stores ns
CROSS JOIN generate_series(1, (SELECT n_users FROM _cfg)) AS g(n);

INSERT INTO branch_ip_registries (public_ip, branch_id, store_id, registered_at, last_seen_at,
                                  created_at, updated_at)
SELECT ip, ns.branch_id, ns.store_id, NOW(), NOW(), NOW(), NOW()
FROM _new_stores ns,
     unnest(ARRAY['127.0.0.1', '::1', '::ffff:127.0.0.1', '172.18.0.1', '::ffff:172.18.0.1']) AS ip;

COMMIT;

-- ── 검증 ────────────────────────────────────────────────────────────────
\echo '=== 생성된 더미 매장 ==='
SELECT s.id, s.name,
       (SELECT count(*) FROM products p WHERE p.store_id = s.id)         AS prods,
       (SELECT count(*) FROM clients c WHERE c.store_id = s.id)          AS clients,
       (SELECT count(*) FROM users u WHERE u.store_id = s.id)            AS users,
       (SELECT count(*) FROM terminals t WHERE t.store_id = s.id)        AS terms,
       (SELECT count(*) FROM terminal_devices d WHERE d.store_id = s.id) AS devices,
       (SELECT count(*) FROM role_functions rf WHERE rf.store_id = s.id) AS role_funcs
FROM stores s
WHERE s.name LIKE 'DUMMY-%'
ORDER BY s.id;

\echo ''
\echo '=== 버스트 대상 매장 목록 (STORES 환경변수용) ==='
SELECT string_agg(id::text, ',' ORDER BY id) AS stores_env
FROM stores
WHERE deleted_at IS NULL AND COALESCE(is_active, FALSE)
  AND EXISTS (SELECT 1 FROM products p WHERE p.store_id = stores.id)
  AND EXISTS (SELECT 1 FROM clients c WHERE c.store_id = stores.id)
  AND EXISTS (SELECT 1 FROM users u WHERE u.store_id = stores.id AND u.username LIKE 'lt\_s%');
