-- [2026-10-03] Shaple (store 26) — ⑤ 외상 이관 결과를 지운다 (재실행 전, 사용자 승인 2026-10-03)
--
-- 왜: ⑤ 가 ACE 의 Fixed(잔액 재시작)와 cretmp 할인을 빠뜨렸다 → 37명 잔액이 ACE 와 다름.
-- 전제: store 26 은 아직 Ventago 영업 전 — 외상 행은 **전부 ⑤ 임포트가 만든 것**
--       (legacy 아닌 판매 0 · conMovimientosPrevios 0). 아래 DO 블록이 다시 확인한다.
-- 기대: credit_ledger 5,486 · credit_payments 1,890 · sale_senias 2 · maps 177 · store_clients 53명 0 으로.
--
-- 실행: ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction" < 이 파일

SET lock_timeout = '5s';

DO $$
DECLARE
  vivas int := (SELECT count(*) FROM sales WHERE store_id = 26 AND source IS DISTINCT FROM 'legacy');
  ajenas int := (SELECT count(*) FROM credit_ledger cl
                  WHERE cl.store_id = 26
                    AND (cl.note IS NULL OR (cl.note NOT LIKE 'ACE creditoventa %'
                                             AND cl.note NOT LIKE 'ACE saldo anterior%')));
BEGIN
  IF vivas > 0 THEN
    RAISE EXCEPTION 'store 26 tiene % ventas no legacy — ya opera, no se borra', vivas;
  END IF;
  IF ajenas > 0 THEN
    RAISE EXCEPTION 'store 26 tiene % movimientos de cuenta que no vienen de ⑤', ajenas;
  END IF;
END $$;

-- hijos antes que padres (parent_ledger_id / payment_id)
DELETE FROM credit_ledger WHERE store_id = 26 AND parent_ledger_id IS NOT NULL;
DELETE FROM credit_ledger WHERE store_id = 26;
DELETE FROM credit_payments WHERE store_id = 26;
DELETE FROM sale_senias WHERE store_id = 26;
DELETE FROM legacy_entity_maps WHERE store_id = 26 AND entity = 'cuenta_corriente';
UPDATE store_clients
   SET balance = 0, favor_balance = 0, senia_balance = 0
 WHERE store_id = 26 AND (balance <> 0 OR favor_balance <> 0 OR senia_balance <> 0);

DO $$
BEGIN
  IF (SELECT count(*) FROM credit_ledger WHERE store_id = 26) > 0 THEN
    RAISE EXCEPTION 'quedaron movimientos';
  END IF;
END $$;
