-- Phase 119 — datos de producción SINTÉTICOS para la tienda de prueba coolsistema (store 6).
-- Pedido del usuario 2026-10-19: «생산 데이터를 coolsistema 매장에서 10가지 물건에 대해서 임의 생성».
--
-- Qué crea (todo marcado «SINTÉTICO 119» en notes/reference/lote_number):
--   · 10 modelos (madre) con variantes talle×color → 3 lotes históricos cada uno (nov-2025, mar-2026, jul-2026)
--     + 1 lote EN CURSO para 4 de ellos (WIP: en costura, sin volver)
--   · ruta corte → costura → planchero con envíos y recepciones fechados (lead time por taller)
--   · recepción final POSTED con detalle por variante y su ingreso al stock (type 'production',
--     sucursal Depósito Central 25) — el mismo rastro que deja la app
--   · BOM por modelo (tela + avíos) y movimientos de tela: compra (ENTRADA) y consumo al cortar (SALIDA)
-- No toca ventas, caja ni facturación. No borra nada (los datos de prueba se conservan).
--
-- Uso: primero con ROLLBACK (verificación) y recién después con COMMIT, con aprobación.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

DO $$
DECLARE
  v_store   int := 6;
  v_branch  int := 25;                       -- Depósito Central
  v_tag     text := 'SINTÉTICO 119';
  modelos   int[] := ARRAY[123,264,140,147,245,183,79,227,240,222];
  -- tela principal por modelo: material, consumo por prenda, unidad
  tela_mat  int[]     := ARRAY[  5,  6,  3,  3,  7,  9,  9,  5,  6,  3];
  tela_cons numeric[] := ARRAY[0.40,0.45,0.95,1.10,0.35,1.30,1.40,0.33,0.30,1.20];
  cortes    date[] := ARRAY['2025-11-10','2026-03-09','2026-07-06']::date[];
  costureros int[] := ARRAY[2,3,4];          -- lee, park, kim
  lt_cost   int[]  := ARRAY[10,15,19];        -- lead time medio de costura por taller (días)
  i int; k int; n int; lot_seq int := 0;
  v_madre int; v_sku text; v_total int; v_lote int; v_cut date;
  v_env1 int; v_env2 int; v_env3 int; v_rec3 int;
  d1 date; d2 date; d3 date; d4 date; v_rej int; v_fin int; v_cost int; v_ltc int;
  v_bom int; v_wip bool;
  r record; v_w numeric; v_sumw numeric; v_q int; v_asig int; v_pb int;
  v_matrix jsonb; v_sizes jsonb; v_colors jsonb; v_qty jsonb;
BEGIN
  PERFORM setseed(0.119);
  CREATE TEMP TABLE IF NOT EXISTS _s119_var (product_id int, color_id int, size_id int, qty int) ON COMMIT DROP;

  FOR i IN 1..array_length(modelos,1) LOOP
    v_madre := modelos[i];
    SELECT sku INTO v_sku FROM products WHERE id = v_madre AND store_id = v_store;
    IF v_sku IS NULL THEN RAISE EXCEPTION 'modelo % no es de la tienda %', v_madre, v_store; END IF;

    -- BOM (tela + avíos)
    INSERT INTO mes_bom (product_id, version, is_active, store_id, created_at, updated_at)
    VALUES (v_madre, '1.0', true, v_store, '2025-11-01', '2025-11-01') RETURNING id INTO v_bom;
    INSERT INTO mes_bom_items (bom_id, material_id, quantity, unit, notes, created_at, updated_at)
    VALUES (v_bom, tela_mat[i], tela_cons[i], (SELECT unit FROM mes_materials WHERE id = tela_mat[i]), v_tag, now(), now()),
           (v_bom, 11, 0.05, 'cono', v_tag, now(), now());
    IF v_madre IN (264,140,147,222) THEN   -- camisa/abrigos: botones
      INSERT INTO mes_bom_items (bom_id, material_id, quantity, unit, notes, created_at, updated_at)
      VALUES (v_bom, 13, 6, 'unid', v_tag, now(), now());
    END IF;
    IF v_madre IN (147,79,183) THEN        -- cierre
      INSERT INTO mes_bom_items (bom_id, material_id, quantity, unit, notes, created_at, updated_at)
      VALUES (v_bom, 15, 1, 'unid', v_tag, now(), now());
    END IF;
    IF v_madre IN (123,240,183) THEN       -- elástico
      INSERT INTO mes_bom_items (bom_id, material_id, quantity, unit, notes, created_at, updated_at)
      VALUES (v_bom, 17, 0.8, 'm', v_tag, now(), now());
    END IF;

    -- 3 lotes históricos + 1 en curso para los 4 primeros
    FOR k IN 1..(CASE WHEN i <= 4 THEN 4 ELSE 3 END) LOOP
      v_wip := (k = 4);
      lot_seq := lot_seq + 1;
      v_cut := CASE WHEN v_wip THEN DATE '2026-10-06' + (i % 3) ELSE cortes[k] + (i - 1) * 2 END;
      v_total := (6 + floor(random() * 19))::int * 10;          -- 60..240
      v_cost := 1 + ((i + k) % 3);                               -- taller de costura
      v_ltc := lt_cost[v_cost] + floor(random() * 7)::int - 3;   -- ±3 días

      -- matriz talle×color con curva de talles (pesos), sin la variante «Color Único/Talle Única»
      v_sizes := '[]'; v_colors := '[]'; v_qty := '{}';
      SELECT sum(w) INTO v_sumw FROM (
        SELECT CASE upper(sz.name) WHEN 'XS' THEN 0.08 WHEN 'S' THEN 0.20 WHEN 'M' THEN 0.32 WHEN 'L' THEN 0.27
               WHEN 'XL' THEN 0.13 WHEN 'XXL' THEN 0.05 ELSE 0.25 END * (1 + 0.4 * sin(ch.color_id)) AS w
          FROM products ch JOIN sizes sz ON sz.id = ch.size_id JOIN colors co ON co.id = ch.color_id
         WHERE ch.parent_id = v_madre AND ch.status <> 'deactivated'
           AND NOT (co.name = 'Color Único' AND sz.name = 'Talle Única')) x;

      TRUNCATE _s119_var;
      v_asig := 0;
      FOR r IN
        SELECT ch.id, ch.color_id, ch.size_id,
               CASE upper(sz.name) WHEN 'XS' THEN 0.08 WHEN 'S' THEN 0.20 WHEN 'M' THEN 0.32 WHEN 'L' THEN 0.27
               WHEN 'XL' THEN 0.13 WHEN 'XXL' THEN 0.05 ELSE 0.25 END * (1 + 0.4 * sin(ch.color_id)) AS w
          FROM products ch JOIN sizes sz ON sz.id = ch.size_id JOIN colors co ON co.id = ch.color_id
         WHERE ch.parent_id = v_madre AND ch.status <> 'deactivated'
           AND NOT (co.name = 'Color Único' AND sz.name = 'Talle Única')
         ORDER BY ch.id
      LOOP
        v_q := floor(v_total * r.w / v_sumw)::int;
        INSERT INTO _s119_var VALUES (r.id, r.color_id, r.size_id, v_q);
        v_asig := v_asig + v_q;
      END LOOP;
      -- el resto del redondeo a la variante de más peso
      UPDATE _s119_var SET qty = qty + (v_total - v_asig)
       WHERE product_id = (SELECT product_id FROM _s119_var ORDER BY qty DESC, product_id LIMIT 1);

      SELECT jsonb_agg(DISTINCT jsonb_build_object('id', s.size_id, 'name', sz.name)) INTO v_sizes
        FROM _s119_var s JOIN sizes sz ON sz.id = s.size_id;
      SELECT jsonb_agg(DISTINCT jsonb_build_object('id', s.color_id, 'name', co.name)) INTO v_colors
        FROM _s119_var s JOIN colors co ON co.id = s.color_id;
      SELECT jsonb_object_agg(c.color_id::text, c.m) INTO v_qty FROM (
        SELECT color_id, jsonb_object_agg(size_id::text, qty) m FROM _s119_var GROUP BY color_id) c;
      v_matrix := jsonb_build_object('qty', v_qty, 'sizes', v_sizes, 'colors', v_colors);

      -- fechas: corte → costura → planchero
      d1 := v_cut + 2 + floor(random() * 3)::int;      -- vuelve de corte
      d2 := d1 + v_ltc;                                -- vuelve de costura
      d3 := d2 + 2 + floor(random() * 3)::int;         -- vuelve de planchero
      v_rej := floor(v_total * random() * 0.03)::int;  -- rechazo en costura 0–3 %
      v_fin := v_total - v_rej;

      INSERT INTO talleres_lotes (lote_number, product_id, total_quantity, available_quantity, status, notes, store_id,
             created_at, updated_at, cut_ticket_number, style_code, season, cut_date, size_color_matrix, bom_snapshot,
             routing_path, stocked_quantity, production_status, production_reason, inventory_status,
             reconciliation_status, unexplained_quantity, status_computed_at)
      VALUES (format('LOT-S119-%s', lpad(lot_seq::text, 2, '0')), v_madre, v_total,
             CASE WHEN v_wip THEN 0 ELSE 0 END,
             (CASE WHEN v_wip THEN 'IN_PROGRESS' ELSE 'COMPLETED' END)::enum_talleres_lotes_status,
             v_tag || ' — datos de prueba para predicción/recomendación de producción', v_store,
             v_cut::timestamptz + interval '9 hours', now(), format('CT-S119-%s', lpad(lot_seq::text, 2, '0')), v_sku,
             CASE WHEN extract(month FROM v_cut) BETWEEN 2 AND 7 THEN 'OI' ELSE 'PV' END || extract(year FROM v_cut),
             v_cut, v_matrix, '[]'::jsonb,
             jsonb_build_array(
               jsonb_build_object('order',1,'etapaId',1,'vendorId',5,'etapaName','corte','vendorName','ruth'),
               jsonb_build_object('order',2,'etapaId',3,'vendorId',costureros[v_cost],'etapaName','costura',
                                  'vendorName',(SELECT name FROM talleres_vendors WHERE id = costureros[v_cost])),
               jsonb_build_object('order',3,'etapaId',5,'vendorId',7,'etapaName','planchero','vendorName','maria')),
             CASE WHEN v_wip THEN 0 ELSE v_fin END,
             CASE WHEN v_wip THEN 'IN_PROGRESS' ELSE 'COMPLETED' END, NULL,
             CASE WHEN v_wip THEN 'NOT_STARTED' ELSE 'POSTED' END,
             'BALANCED', 0, now())
      RETURNING id INTO v_lote;

      -- etapa 1: corte (ruth)
      INSERT INTO talleres_envios (lote_id, vendor_id, etapa_id, quantity, pending_quantity, envio_date, due_date, status,
             notes, store_id, created_at, updated_at)
      VALUES (v_lote, 5, 1, v_total, 0, v_cut, v_cut + 5, 'COMPLETED', v_tag, v_store, v_cut, d1) RETURNING id INTO v_env1;
      INSERT INTO talleres_recepciones (envio_id, received_quantity, rejected_quantity, recepcion_date, notes, store_id,
             created_at, updated_at, inventory_status)
      VALUES (v_env1, v_total, 0, d1, v_tag, v_store, d1, d1, 'NOT_APPLICABLE');

      -- etapa 2: costura
      IF v_wip THEN
        INSERT INTO talleres_envios (lote_id, vendor_id, etapa_id, quantity, pending_quantity, envio_date, due_date, status,
               notes, store_id, created_at, updated_at)
        VALUES (v_lote, costureros[v_cost], 3, v_total, v_total, d1, d1 + 14, 'PENDING', v_tag, v_store, d1, d1);
        CONTINUE;
      END IF;
      INSERT INTO talleres_envios (lote_id, vendor_id, etapa_id, quantity, pending_quantity, envio_date, due_date, status,
             notes, store_id, created_at, updated_at)
      VALUES (v_lote, costureros[v_cost], 3, v_total, 0, d1, d1 + 14, 'COMPLETED', v_tag, v_store, d1, d2) RETURNING id INTO v_env2;
      INSERT INTO talleres_recepciones (envio_id, received_quantity, rejected_quantity, recepcion_date, notes, store_id,
             created_at, updated_at, inventory_status)
      VALUES (v_env2, v_fin, v_rej, d2, v_tag, v_store, d2, d2, 'NOT_APPLICABLE');

      -- etapa 3: planchero (maria) — recepción final al stock
      INSERT INTO talleres_envios (lote_id, vendor_id, etapa_id, quantity, pending_quantity, envio_date, due_date, status,
             notes, store_id, created_at, updated_at)
      VALUES (v_lote, 7, 5, v_fin, 0, d2, d2 + 5, 'COMPLETED', v_tag, v_store, d2, d3) RETURNING id INTO v_env3;
      INSERT INTO talleres_recepciones (envio_id, received_quantity, rejected_quantity, recepcion_date, notes, store_id,
             created_at, updated_at, target_branch_id, inventory_status, posted_at)
      VALUES (v_env3, v_fin, 0, d3, v_tag, v_store, d3, d3, v_branch, 'POSTED', d3 + interval '18 hours') RETURNING id INTO v_rec3;

      -- el rechazo sale de la variante de más cantidad
      UPDATE _s119_var SET qty = qty - v_rej
       WHERE product_id = (SELECT product_id FROM _s119_var ORDER BY qty DESC, product_id LIMIT 1);

      FOR r IN SELECT * FROM _s119_var WHERE qty > 0 ORDER BY product_id LOOP
        INSERT INTO talleres_recepcion_items (recepcion_id, product_id, quantity, rejected, store_id, created_at, updated_at)
        VALUES (v_rec3, r.product_id, r.qty, 0, v_store, d3, d3);

        SELECT id INTO v_pb FROM "ProductBranch" WHERE product_id = r.product_id AND branch_id = v_branch;
        IF v_pb IS NULL THEN
          INSERT INTO "ProductBranch" (product_id, branch_id, created_at, updated_at)
          VALUES (r.product_id, v_branch, now(), now()) RETURNING id INTO v_pb;
        END IF;
        INSERT INTO stocks (stock, created_at, updated_at, product_branch_id, type, note, is_active, operation_date,
               store_id, branch_id)
        VALUES (r.qty, d3 + interval '18 hours', d3 + interval '18 hours', v_pb, 'production',
               format('Recepción lote LOT-S119-%s (etapa final) — %s', lpad(lot_seq::text, 2, '0'), v_tag),
               true, d3, v_store, v_branch);
      END LOOP;
    END LOOP;
  END LOOP;

  -- tela: compra (ENTRADA) 7 días antes de cada corte y consumo (SALIDA) al cortar
  INSERT INTO mes_material_movements (type, material_id, quantity, unit, movement_date, supplier_id, unit_price,
         total_amount, payment_status, paid_amount, reference, notes, store_id, created_at, updated_at)
  SELECT 'ENTRADA'::enum_mes_material_movements_type, bi.material_id, round(bi.quantity * l.total_quantity * 1.05, 2), bi.unit, l.cut_date - 7, 5,
         coalesce(m.standard_price, 4000), round(bi.quantity * l.total_quantity * 1.05 * coalesce(m.standard_price, 4000)),
         'PAGADO'::enum_mes_material_movements_payment_status, round(bi.quantity * l.total_quantity * 1.05 * coalesce(m.standard_price, 4000)),
         'Compra ' || l.lote_number, v_tag, v_store, l.cut_date - 7, l.cut_date - 7
    FROM talleres_lotes l JOIN mes_bom b ON b.product_id = l.product_id AND b.store_id = v_store
    JOIN mes_bom_items bi ON bi.bom_id = b.id AND bi.notes = v_tag JOIN mes_materials m ON m.id = bi.material_id
   WHERE l.store_id = v_store AND l.lote_number LIKE 'LOT-S119-%'
  UNION ALL
  SELECT 'SALIDA'::enum_mes_material_movements_type, bi.material_id, round(bi.quantity * l.total_quantity, 2), bi.unit, l.cut_date, NULL, NULL, NULL,
         NULL::enum_mes_material_movements_payment_status, 0, l.lote_number, v_tag || ' — consumo de corte', v_store, l.cut_date, l.cut_date
    FROM talleres_lotes l JOIN mes_bom b ON b.product_id = l.product_id AND b.store_id = v_store
    JOIN mes_bom_items bi ON bi.bom_id = b.id AND bi.notes = v_tag
   WHERE l.store_id = v_store AND l.lote_number LIKE 'LOT-S119-%';

  -- current_stock es caché de los movimientos (la app lo incrementa/decrementa): se ajusta igual
  UPDATE mes_materials m
     SET current_stock = m.current_stock + x.neto, last_entry_date = greatest(coalesce(m.last_entry_date, x.ult), x.ult),
         updated_at = now()
    FROM (SELECT material_id,
                 sum(CASE type WHEN 'ENTRADA' THEN quantity ELSE -quantity END) neto,
                 max(movement_date) FILTER (WHERE type = 'ENTRADA') ult
            FROM mes_material_movements WHERE store_id = v_store AND notes LIKE v_tag || '%' GROUP BY material_id) x
   WHERE m.id = x.material_id AND m.store_id = v_store;
END $$;

-- Resumen (lo que se mostró para aprobar)
SELECT 'lotes' t, count(*) FROM talleres_lotes WHERE store_id = 6 AND lote_number LIKE 'LOT-S119-%'
UNION ALL SELECT 'envios', count(*) FROM talleres_envios WHERE store_id = 6 AND notes = 'SINTÉTICO 119'
UNION ALL SELECT 'recepciones', count(*) FROM talleres_recepciones WHERE store_id = 6 AND notes = 'SINTÉTICO 119'
UNION ALL SELECT 'recepcion_items', count(*) FROM talleres_recepcion_items i JOIN talleres_recepciones r ON r.id = i.recepcion_id WHERE r.store_id = 6 AND r.notes = 'SINTÉTICO 119'
UNION ALL SELECT 'stocks', count(*) FROM stocks WHERE store_id = 6 AND note LIKE '%SINTÉTICO 119'
UNION ALL SELECT 'stocks_unidades', coalesce(sum(stock), 0) FROM stocks WHERE store_id = 6 AND note LIKE '%SINTÉTICO 119'
UNION ALL SELECT 'mes_bom', count(*) FROM mes_bom b WHERE store_id = 6 AND EXISTS (SELECT 1 FROM mes_bom_items i WHERE i.bom_id = b.id AND i.notes = 'SINTÉTICO 119')
UNION ALL SELECT 'mes_bom_items', count(*) FROM mes_bom_items WHERE notes = 'SINTÉTICO 119'
UNION ALL SELECT 'material_movements', count(*) FROM mes_material_movements WHERE store_id = 6 AND notes LIKE 'SINTÉTICO 119%';
