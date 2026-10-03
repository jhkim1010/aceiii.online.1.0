-- [2026-10-03] Shaple (store 26) — 판매 품목 재연결 (계획서 (a)-2 ③)
--
-- 전제: ① 재실행으로 `codigoproducto` 가 비었던 변형 1,456개가 products 에 생긴 뒤에 돌린다.
-- 대상: 그 변형들의 ACE 판매 줄 = product_id NULL 로 들어간 sale_items 79,346행.
--
-- ★ 짝짓기 키 = (sale_id, custom_name). 임포트가 product_id 를 못 찾으면
--   custom_name = left(coalesce(desc1, sku), 255) 로 넣었다(ace-sales.sql.ts).
--   실측 2026-10-03: 키 79,306개 전부 「ACE 줄 수 == NULL 품목 수」이고, 한 키가 두 SKU 를
--   가리키는 경우 0 → 짝이 유일하다.
-- ★ 정상 품목과 같게 custom_name 은 NULL 로 돌린다(상품이 있으면 임포트도 NULL 로 넣는다).
-- ★ 기대치와 다르면 RAISE → 전체 롤백.
--
-- 실행: ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction" < 이 파일

SET lock_timeout = '5s';
SET statement_timeout = '300s';

CREATE TEMP TABLE perd ON COMMIT DROP AS
SELECT btrim(c.id_codigo) AS id_codigo, btrim(c.codigo) AS sku
  FROM legacy_stage_0000000002.codigos c
 WHERE coalesce(c.borrado, 'f') IN ('f', 'false', '0')
   AND NULLIF(btrim(c.codigoproducto), '') IS NULL
   AND NULLIF(btrim(c.codigo), '') IS NOT NULL;

CREATE TEMP TABLE lin ON COMMIT DROP AS
SELECT m.ventago_id::int AS sale_id,
       p.sku,
       left(COALESCE(NULLIF(btrim(d.desc1), ''), p.sku), 255) AS cname
  FROM legacy_stage_0000000002.vdetalle d
  JOIN perd p ON p.id_codigo = btrim(d.ref_id_codigo)
  JOIN legacy_entity_maps m
    ON m.store_id = 26 AND m.entity = 'sale' AND m.status = 'DONE'
   AND m.legacy_id = btrim(d.vcode1);

-- 키별 SKU 가 하나뿐인 것만, 그리고 그 SKU 의 상품이 store 26 에 있는 것만
CREATE TEMP TABLE clave ON COMMIT DROP AS
SELECT l.sale_id, l.cname, min(l.sku) AS sku, count(*) AS n
  FROM lin l
 GROUP BY l.sale_id, l.cname
HAVING count(DISTINCT l.sku) = 1;

CREATE TEMP TABLE upd ON COMMIT DROP AS
SELECT si.id, pr.id AS product_id
  FROM clave k
  JOIN sales s ON s.id = k.sale_id AND s.store_id = 26 AND s.source = 'legacy'
  JOIN sale_items si
    ON si.sale_id = k.sale_id AND si.product_id IS NULL AND si.custom_name = k.cname
  JOIN products pr ON pr.store_id = 26 AND pr.sku = k.sku;

DO $$
DECLARE
  esperado int := (SELECT count(*) FROM lin);
  hallado  int := (SELECT count(*) FROM upd);
BEGIN
  RAISE NOTICE 'lineas ACE=% · items a reconectar=%', esperado, hallado;
  IF hallado <> esperado THEN
    RAISE EXCEPTION 'esperado % items, hallados % — ¿se corrió ① antes?', esperado, hallado;
  END IF;
END $$;

UPDATE sale_items si
   SET product_id = u.product_id, custom_name = NULL, updated_at = now()
  FROM upd u
 WHERE si.id = u.id;
