-- ============================================================================
-- Phase 63 — 더미 매장 정리 (스테이징 전용)
--
-- seed-dummy-stores.sql 로 만든 DUMMY-* 매장과 그 하위 데이터를 전부 삭제한다.
-- FK 역순으로 지운다.
--
-- 실행: psql -h 127.0.0.1 -p 6432 -U coolsistema -d ventago_staging \
--         -v ON_ERROR_STOP=1 -f cleanup-dummy-stores.sql
-- ============================================================================

DO $$
BEGIN
  IF current_database() <> 'ventago_staging' THEN
    RAISE EXCEPTION '이 스크립트는 ventago_staging 전용입니다. 현재 DB: %', current_database();
  END IF;
END $$;

BEGIN;

CREATE TEMP TABLE _dummy ON COMMIT DROP AS
SELECT id AS store_id FROM stores WHERE name LIKE 'DUMMY-%';

-- 판매 관련 (버스트 테스트 산출물)
DELETE FROM sale_payment_methods WHERE sale_id IN
  (SELECT s.id FROM sales s JOIN _dummy d ON d.store_id = s.store_id);
DELETE FROM sale_items WHERE sale_id IN
  (SELECT s.id FROM sales s JOIN _dummy d ON d.store_id = s.store_id);
DELETE FROM sales WHERE store_id IN (SELECT store_id FROM _dummy);

-- 세션/디바이스/IP
DELETE FROM active_sessions WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM terminal_devices WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM branch_ip_registries WHERE store_id IN (SELECT store_id FROM _dummy);

-- 사용자/권한
DELETE FROM user_roles WHERE user_id IN
  (SELECT u.id FROM users u JOIN _dummy d ON d.store_id = u.store_id);

-- 감사 로그 — users FK 참조. 부하 테스트 중 로그인/판매가 audit_logs 를 남기므로
-- 이걸 먼저 지우지 않으면 users 삭제가 audit_logs_user_id_fkey 로 막힌다
-- (2026-07-27 실측: 30매장 재시드 시 정리 실패).
DELETE FROM audit_logs WHERE user_id IN
  (SELECT u.id FROM users u JOIN _dummy d ON d.store_id = u.store_id);
DELETE FROM audit_logs WHERE store_id IN (SELECT store_id FROM _dummy);

DELETE FROM users WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM role_function_actions WHERE role_function_id IN
  (SELECT rf.id FROM role_functions rf JOIN _dummy d ON d.store_id = rf.store_id);
DELETE FROM role_functions WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM roles WHERE store_id IN (SELECT store_id FROM _dummy);

-- 재고/상품
DELETE FROM stocks WHERE product_branch_id IN (
  SELECT pb.id FROM "ProductBranch" pb
  JOIN products p ON p.id = pb.product_id
  JOIN _dummy d ON d.store_id = p.store_id
);
DELETE FROM "ProductBranch" WHERE product_id IN
  (SELECT p.id FROM products p JOIN _dummy d ON d.store_id = p.store_id);
DELETE FROM products WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM categories WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM clients WHERE store_id IN (SELECT store_id FROM _dummy);

-- 매장 구조
DELETE FROM terminals WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM boxes WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM branches WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM store_apps WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM store_configs WHERE store_id IN (SELECT store_id FROM _dummy);
DELETE FROM stores WHERE id IN (SELECT store_id FROM _dummy);

COMMIT;

\echo '=== 남은 DUMMY 매장 (0 이어야 정상) ==='
SELECT count(*) FROM stores WHERE name LIKE 'DUMMY-%';
