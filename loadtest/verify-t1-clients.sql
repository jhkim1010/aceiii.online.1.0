-- ============================================================================
-- Phase 63 T-1 검증 — 고객 전역(global_clients) 중복/격리 확인
--
-- 실행: psql -h 127.0.0.1 -p 6432 -U coolsistema -d ventago_staging -f verify-t1-clients.sql
-- ============================================================================

\echo '=== 1) ★ global_clients 중복 (owner_group + document) — 0 이어야 정상 ==='
-- 여러 매장이 같은 고객을 동시에 등록해도 전역 레코드는 1개여야 한다.
SELECT owner_group_id,
       regexp_replace(document, '[^0-9]', '', 'g') AS doc_norm,
       count(*) AS dup
FROM global_clients
WHERE fullname LIKE 'T1 %'
GROUP BY 1, 2
HAVING count(*) > 1
ORDER BY dup DESC;

\echo ''
\echo '=== 2) 전역 고객 생성 현황 (document 당 1행이어야 함) ==='
SELECT count(*) AS global_rows,
       count(DISTINCT regexp_replace(document, '[^0-9]', '', 'g')) AS distinct_docs,
       count(DISTINCT owner_group_id) AS owner_groups
FROM global_clients
WHERE fullname LIKE 'T1 %';

\echo ''
\echo '=== 3) 매장별 store_clients 매핑 (동일 global 을 여러 매장이 공유하는가) ==='
SELECT gc.document,
       count(DISTINCT sc.store_id) AS stores_linked,
       count(*)                    AS store_client_rows
FROM global_clients gc
JOIN store_clients sc ON sc.global_client_id = gc.id
WHERE gc.fullname LIKE 'T1 %'
GROUP BY 1
ORDER BY stores_linked DESC
LIMIT 10;

\echo ''
\echo '=== 4) ★ store_clients 중복 (global_client_id, store_id) — 0 이어야 정상 ==='
SELECT global_client_id, store_id, count(*) AS dup
FROM store_clients
GROUP BY 1, 2
HAVING count(*) > 1;

\echo ''
\echo '=== 5) 매장 간 로컬 고객 격리 — 같은 document 를 쓰는 매장 수 / 로컬 row 수 ==='
-- 매장마다 clients(로컬) 행은 따로 존재하는 것이 정상 설계.
-- 여기서 확인할 것은 "한 매장의 로컬 행이 다른 매장 것과 섞이지 않았는가".
SELECT document,
       count(*)                    AS local_rows,
       count(DISTINCT store_id)    AS stores,
       CASE WHEN count(*) = count(DISTINCT store_id)
            THEN 'OK (매장당 1행)'
            ELSE '★ 매장 내 중복 있음' END AS verdict
FROM clients
WHERE fullname LIKE 'T1 %' OR fullname LIKE 'T1 EDITADO%'
GROUP BY 1
ORDER BY local_rows DESC
LIMIT 10;

\echo ''
\echo '=== 6) ★ 수정 격리 — 한 매장에서 수정한 이름이 다른 매장 행까지 바꿨는가 ==='
-- EDITADO 는 특정 매장에서만 수정했으므로, 같은 document 의 다른 매장 행은
-- 원래 이름('T1 Cliente N')을 유지해야 한다. 아래는 참고용 분포.
SELECT document,
       count(*) FILTER (WHERE fullname LIKE 'T1 EDITADO%') AS edited_rows,
       count(*) FILTER (WHERE fullname NOT LIKE 'T1 EDITADO%') AS untouched_rows,
       count(DISTINCT store_id) AS stores
FROM clients
WHERE fullname LIKE 'T1 %'
GROUP BY 1
HAVING count(*) FILTER (WHERE fullname LIKE 'T1 EDITADO%') > 0
ORDER BY edited_rows DESC
LIMIT 10;

\echo ''
\echo '=== 7) ★ 삭제 격리 — 삭제(soft delete)가 다른 매장에 전파됐는가 ==='
SELECT document,
       count(*) FILTER (WHERE is_active IS DISTINCT FROM TRUE) AS inactive_rows,
       count(*) FILTER (WHERE is_active IS TRUE)               AS active_rows,
       count(DISTINCT store_id)                                AS stores
FROM clients
WHERE fullname LIKE 'T1 %'
GROUP BY 1
HAVING count(*) FILTER (WHERE is_active IS DISTINCT FROM TRUE) > 0
ORDER BY inactive_rows DESC
LIMIT 10;

\echo ''
\echo '=== 8) 전역 고객이 삭제로 사라지지 않았는지 (매장 삭제는 전역에 영향 없어야 함) ==='
SELECT count(*) AS global_still_present
FROM global_clients
WHERE fullname LIKE 'T1 %';
