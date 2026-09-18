-- Phase 57 보강 W-A6 — 발행자 현황 조사 (읽기 전용)
-- 마이그레이션 전에 «백필 가정이 맞는가» 를 확인한다.
\pset pager off

\echo '── ① 발행자 전체 ─────────────────────────────────────────'
SELECT i.id, i.store_id, s.name AS tienda, i.branch_id, b.name AS sucursal,
       i.cuit, i.punto_venta AS pv, i.cool_user, i.iva_condition, i.invoice_type
  FROM afip_issuers i
  LEFT JOIN stores s   ON s.id = i.store_id
  LEFT JOIN branches b ON b.id = i.branch_id
 ORDER BY i.store_id, i.punto_venta;

\echo '── ② 기본 발행자 중복 (branch_id IS NULL 이 매장당 2개 이상) ──'
\echo '   0행이어야 uq_afip_issuer_store_default 를 만들 수 있다'
SELECT store_id, count(*) AS nulos
  FROM afip_issuers WHERE branch_id IS NULL
 GROUP BY store_id HAVING count(*) > 1;

\echo '── ③ 한 지점에 발행자 2개 이상 (U6 의 목표 상태 — 지금은 UNIQUE 가 막는다) ──'
SELECT store_id, branch_id, count(*) AS emisores
  FROM afip_issuers WHERE branch_id IS NOT NULL
 GROUP BY store_id, branch_id HAVING count(*) > 1;

\echo '── ④ 교차 매장 CUIT (D-11: cuit_compartido=true 로 백필될 대상) ──'
SELECT cuit, count(DISTINCT store_id) AS tiendas,
       string_agg(DISTINCT store_id::text, ',') AS store_ids
  FROM afip_issuers GROUP BY cuit HAVING count(DISTINCT store_id) > 1;

\echo '── ⑤ 발행자가 없는 지점 (발급 불가 — 기본 발행자로 떨어진다) ──'
SELECT b.store_id, b.id AS branch_id, b.name AS sucursal
  FROM branches b
  LEFT JOIN afip_issuers i ON i.branch_id = b.id
 WHERE i.id IS NULL AND b.store_id IN (SELECT DISTINCT store_id FROM afip_issuers)
 ORDER BY b.store_id, b.id;

\echo '── ⑥ sales.branch_id 결측 (D-10 기본값 산출이 불가능한 판매) ──'
SELECT store_id, count(*) AS ventas,
       count(*) FILTER (WHERE branch_id IS NULL) AS sin_branch
  FROM sales WHERE store_id IN (SELECT DISTINCT store_id FROM afip_issuers)
 GROUP BY store_id ORDER BY store_id;

\echo '── ⑦ PV 별 결번 (G3 — 남이 쓴 번호. 전환 전 기준선) ──'
SELECT v.store_id, v.punto_venta AS pv, v.tipo_comprobante AS tipo,
       count(*) AS nuestros, min(v.afip_number) AS n_min, max(v.afip_number) AS n_max,
       (max(v.afip_number) - min(v.afip_number) + 1) - count(*) AS huecos
  FROM afip_vouchers v
 GROUP BY v.store_id, v.punto_venta, v.tipo_comprobante
 ORDER BY v.store_id, v.punto_venta, v.tipo_comprobante;

\echo '── ⑧ 전표 → 발행자 백필 가능 여부 (store_id+pv 로 유일하게 찾히는가) ──'
\echo '   ambiguos 가 0 이어야 afip_vouchers.issuer_id 백필이 안전하다'
SELECT count(*) FILTER (WHERE n = 1) AS resolubles,
       count(*) FILTER (WHERE n = 0) AS sin_emisor,
       count(*) FILTER (WHERE n > 1) AS ambiguos
  FROM (
    SELECT v.id, (SELECT count(*) FROM afip_issuers i
                   WHERE i.store_id = v.store_id AND i.punto_venta = v.punto_venta) AS n
      FROM afip_vouchers v
  ) t;
