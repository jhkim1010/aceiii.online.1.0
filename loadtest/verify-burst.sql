-- ============================================================================
-- Phase 63 — 다매장 버스트 테스트 사후 정합성 검증 (스테이징 전용)
--
-- k6 의 sale_ok 카운터와 아래 total_saved 가 일치해야 하고,
-- daily_number 중복이 0 이어야 한다.
--
-- 실행: psql -h 127.0.0.1 -p 6432 -U coolsistema -d ventago_staging -f verify-burst.sql
-- ============================================================================

\echo '=== 1) 매장별 저장 건수 (BURST 마커 기준) ==='
SELECT s.store_id,
       count(*)                    AS saved,
       min(s.daily_number)         AS dn_min,
       max(s.daily_number)         AS dn_max,
       count(DISTINCT s.daily_number) AS dn_distinct,
       min(s.created_at)::time(0)  AS first_at,
       max(s.created_at)::time(0)  AS last_at
FROM sales s
WHERE s.notes LIKE 'BURST|%'
GROUP BY s.store_id
ORDER BY s.store_id;

\echo ''
\echo '=== 2) ★ daily_number 중복 (0 이어야 정상) ==='
-- 채번 경합 검증: 같은 매장/지점/날짜에서 같은 번호가 두 번 나오면 동시성 버그.
-- ※ sales 에는 branch_id 가 없으므로 user_id → users.branch_id 로 지점을 도출한다.
SELECT store_id, branch_id, sale_day, daily_number, cnt
FROM (
  SELECT s.store_id,
         u.branch_id,
         s.sale_date::date AS sale_day,
         s.daily_number,
         count(*) AS cnt
  FROM sales s
  JOIN users u ON u.id = s.user_id
  WHERE s.notes LIKE 'BURST|%'
  GROUP BY 1, 2, 3, 4
) x
WHERE cnt > 1
ORDER BY store_id, daily_number;

\echo ''
\echo '=== 3) 총 저장 건수 (k6 sale_ok 와 대조) ==='
SELECT count(*) AS total_saved FROM sales WHERE notes LIKE 'BURST|%';

\echo ''
\echo '=== 4) 판매 항목/결제 누락 검사 (0 이어야 정상) ==='
SELECT
  (SELECT count(*) FROM sales s
     WHERE s.notes LIKE 'BURST|%'
       AND NOT EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id = s.id)) AS sales_without_items,
  (SELECT count(*) FROM sales s
     WHERE s.notes LIKE 'BURST|%'
       AND NOT EXISTS (SELECT 1 FROM sale_payment_methods pm WHERE pm.sale_id = s.id)) AS sales_without_payment;

\echo ''
\echo '=== 5) 금액 정합성 (합계 불일치 0 이어야 정상) ==='
SELECT count(*) AS amount_mismatch
FROM (
  SELECT s.id, s.total_amount,
         (SELECT COALESCE(sum(pm.amount), 0) FROM sale_payment_methods pm WHERE pm.sale_id = s.id) AS paid
  FROM sales s
  WHERE s.notes LIKE 'BURST|%'
) x
WHERE abs(x.total_amount - x.paid) > 0.01;

\echo ''
\echo '=== 6) 초당 처리량 분포 (동시성 실제 도달 확인) ==='
SELECT date_trunc('second', created_at)::time(0) AS sec, count(*) AS sales_in_sec
FROM sales
WHERE notes LIKE 'BURST|%'
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;
