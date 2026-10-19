-- Phase 119 — historial de VENTAS SINTÉTICO para la tienda de prueba coolsistema (store 6).
-- Pedido del usuario 2026-10-19: «판매도 합성한다» (después de seed-coolsistema-produccion.sql).
--
-- Qué crea (marcado «SINTÉTICO 119» en sales.notes):
--   · ventas diarias 2025-11-15 → 2026-10-18 de las variantes de los 10 modelos de la producción sintética
--   · demanda = base del modelo × estación (abrigo invierno / remera-short verano) × día de semana × eventos
--     (Navidad, Hot Sale 2026, Día de la Madre 2026), con ruido Poisson
--   · SÓLO se vende lo que hay en stock ese día en Depósito Central (25): los quiebres salen solos
--   · cada ticket: sales (pos, Pagado, sin terminal → fuera de caja, sin factura, daily_number 0)
--     + sale_items (unit_cost = 45 % del precio) + pago Efectivo + descuento de stock (type NULL, como el POS)
-- No toca caja, facturación ni otras tiendas. No borra nada.
SET lock_timeout = '5s';
SET statement_timeout = '300s';

DO $$
DECLARE
  v_store  int := 6;
  v_branch int := 25;
  v_tag    text := 'SINTÉTICO 119';
  modelos  int[]     := ARRAY[123,264,140,147,245,183,79,227,240,222];
  base     numeric[] := ARRAY[0.9,0.5,0.8,0.5,1.1,0.35,0.6,1.0,0.9,0.6];   -- unidades/día
  -- 1 = abrigo (invierno), 2 = verano, 3 = todo el año
  perfil   int[]     := ARRAY[  2,  3,  1,  1,  2,   3,  3,  2,  2,  1];
  est_inv  numeric[] := ARRAY[0.2,0.3,0.7,1.2,1.6,1.8,1.6,1.1,0.6,0.4,0.3,0.3];  -- ene..dic
  est_ver  numeric[] := ARRAY[1.6,1.2,0.8,0.5,0.4,0.3,0.3,0.5,0.9,1.3,1.6,1.8];
  est_anio numeric[] := ARRAY[0.8,0.9,1.1,1.0,1.0,1.0,0.9,1.0,1.0,1.1,1.1,1.2];
  usuarios int[] := ARRAY[7,16];
  vendedores int[] := ARRAY[22,8,13,14];
  d date; i int; lam numeric; f numeric; n int; u int; L numeric; p numeric;
  v_var int; v_q int; v_sale int; v_pb int; v_price numeric; v_ts timestamptz; v_m int;
BEGIN
  PERFORM setseed(0.1191);

  -- stock disponible por variante en 25 (se va descontando en la simulación)
  CREATE TEMP TABLE _s119_stock ON COMMIT DROP AS
    SELECT pb.product_id, pb.id AS pb_id, ch.parent_id, sum(s.stock)::int AS disp
      FROM stocks s JOIN "ProductBranch" pb ON pb.id = s.product_branch_id
      JOIN products ch ON ch.id = pb.product_id
     WHERE s.store_id = v_store AND pb.branch_id = v_branch AND ch.parent_id = ANY(modelos)
     GROUP BY pb.product_id, pb.id, ch.parent_id;
  -- ingresos con su fecha: el stock aparece el día de la recepción final
  CREATE TEMP TABLE _s119_ing ON COMMIT DROP AS
    SELECT pb.product_id, s.operation_date AS dia, sum(s.stock)::int AS q
      FROM stocks s JOIN "ProductBranch" pb ON pb.id = s.product_branch_id
     WHERE s.store_id = v_store AND pb.branch_id = v_branch AND s.type = 'production' AND s.note LIKE '%' || v_tag
     GROUP BY pb.product_id, s.operation_date;
  -- arranca con lo que había ANTES del período sintético (los ingresos sintéticos se suman por fecha)
  UPDATE _s119_stock t SET disp = disp - coalesce((SELECT sum(q) FROM _s119_ing g WHERE g.product_id = t.product_id), 0);
  -- curva de talles para elegir la variante vendida
  CREATE TEMP TABLE _s119_peso ON COMMIT DROP AS
    SELECT ch.id AS product_id, ch.parent_id,
           CASE upper(sz.name) WHEN 'XS' THEN 0.08 WHEN 'S' THEN 0.20 WHEN 'M' THEN 0.32 WHEN 'L' THEN 0.27
           WHEN 'XL' THEN 0.13 WHEN 'XXL' THEN 0.05 ELSE 0.25 END * (1 + 0.4 * sin(ch.color_id)) AS w
      FROM products ch JOIN sizes sz ON sz.id = ch.size_id
     WHERE ch.parent_id = ANY(modelos) AND ch.status <> 'deactivated';

  d := DATE '2025-11-15';
  WHILE d <= DATE '2026-10-18' LOOP
    -- llega la producción del día
    UPDATE _s119_stock t SET disp = disp + g.q FROM _s119_ing g WHERE g.product_id = t.product_id AND g.dia = d;

    FOR i IN 1..array_length(modelos, 1) LOOP
      v_m := extract(month FROM d)::int;
      f := CASE perfil[i] WHEN 1 THEN est_inv[v_m] WHEN 2 THEN est_ver[v_m] ELSE est_anio[v_m] END;
      f := f * CASE extract(isodow FROM d)::int WHEN 6 THEN 1.5 WHEN 7 THEN 0.6 WHEN 5 THEN 1.2 ELSE 1.0 END;
      IF d BETWEEN '2025-12-15' AND '2025-12-24' THEN f := f * 1.6; END IF;   -- Navidad
      IF d BETWEEN '2026-05-11' AND '2026-05-13' THEN f := f * 1.8; END IF;   -- Hot Sale 2026
      IF d BETWEEN '2026-10-12' AND '2026-10-18' THEN f := f * 1.4; END IF;   -- Día de la Madre 2026
      lam := base[i] * f;

      -- Poisson(lam) — Knuth
      L := exp(-lam); n := 0; p := 1;
      LOOP p := p * random(); EXIT WHEN p <= L; n := n + 1; END LOOP;

      WHILE n > 0 LOOP
        -- variante con stock, ponderada por la curva
        SELECT w.product_id INTO v_var
          FROM _s119_peso w JOIN _s119_stock t ON t.product_id = w.product_id
         WHERE w.parent_id = modelos[i] AND t.disp > 0
         ORDER BY -ln(greatest(random(), 1e-9)) / w.w LIMIT 1;
        EXIT WHEN v_var IS NULL;               -- quiebre: la demanda de hoy se pierde
        v_q := CASE WHEN n >= 2 AND random() < 0.2 THEN 2 ELSE 1 END;
        SELECT least(v_q, disp), pb_id INTO v_q, v_pb FROM _s119_stock WHERE product_id = v_var;
        SELECT price INTO v_price FROM products WHERE id = modelos[i];
        v_ts := (d + time '10:00' + (random() * interval '10 hours')) AT TIME ZONE 'America/Argentina/Buenos_Aires';
        u := 1 + floor(random() * 2)::int;

        INSERT INTO sales (store_id, user_id, seller_id, sale_date, subtotal, discount_amount, total_amount, status,
               notes, discount, created_at, updated_at, daily_number, source, activity_type, afip_status,
               sale_day_local, branch_id)
        VALUES (v_store, usuarios[u], vendedores[1 + floor(random() * 4)::int], v_ts, v_price * v_q, 0, v_price * v_q,
               'Pagado', v_tag, 0, v_ts, v_ts, 0, 'pos', 'sale', 'no', d, v_branch)
        RETURNING id INTO v_sale;
        INSERT INTO sale_items (sale_id, product_id, quantity, price, subtotal, discount_amount, created_at, updated_at,
               is_promo_free, unit_cost, list_price)
        VALUES (v_sale, v_var, v_q, v_price, v_price * v_q, 0, v_ts, v_ts, false, round(v_price * 0.45), v_price);
        INSERT INTO sale_payment_methods (sale_id, payment_method_id, amount, created_at, updated_at)
        VALUES (v_sale, 21, v_price * v_q, v_ts, v_ts);
        INSERT INTO stocks (stock, created_at, updated_at, product_branch_id, type, note, is_active, operation_date,
               store_id, branch_id)
        VALUES (-v_q, v_ts, v_ts, v_pb, NULL, NULL, true, d, v_store, v_branch);

        UPDATE _s119_stock SET disp = disp - v_q WHERE product_id = v_var;
        n := n - v_q;
        v_var := NULL;
      END LOOP;
    END LOOP;
    d := d + 1;
  END LOOP;
END $$;

-- Resumen
SELECT 'ventas' t, count(*) FROM sales WHERE store_id = 6 AND notes = 'SINTÉTICO 119'
UNION ALL SELECT 'unidades', sum(si.quantity) FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE s.store_id = 6 AND s.notes = 'SINTÉTICO 119'
UNION ALL SELECT 'stocks_descuentos', count(*) FROM stocks st WHERE st.store_id = 6 AND st.branch_id = 25 AND st.type IS NULL AND st.note IS NULL AND st.operation_date >= '2025-11-15' AND st.stock < 0
UNION ALL SELECT 'monto', round(sum(total_amount)) FROM sales WHERE store_id = 6 AND notes = 'SINTÉTICO 119';
