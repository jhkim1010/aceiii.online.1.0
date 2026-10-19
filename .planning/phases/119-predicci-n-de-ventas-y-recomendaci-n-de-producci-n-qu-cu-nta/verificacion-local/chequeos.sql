-- Phase 119-16 — chequeos V1..V11 contra la DB LOCAL (psql -p 5432 -d ventago), sólo lectura.
-- Mismos chequeos que 119-14 hará contra prod (5434). Tienda 6 (coolsistema, datos sintéticos).
-- Ejecutar: psql -p 5432 -d ventago -f chequeos.sql
\pset format aligned
\pset null '∅'
SET default_transaction_read_only = on;

\echo '== V0 contexto: modelos con agregado y rango'
SELECT count(DISTINCT model_id) modelos, min(day_local) desde, max(day_local) hasta, sum(qty) sum_qty
FROM daily_sales_agg WHERE store_id = 6;

\echo '== V1 reconciliación: Σqty daily_sales_agg vs consulta independiente (sin usar el constructor)'
WITH modelos AS (SELECT DISTINCT model_id FROM daily_sales_agg WHERE store_id = 6),
agg AS (
  SELECT sum(qty) q FROM daily_sales_agg
  WHERE store_id = 6 AND day_local BETWEEN '2025-11-15' AND '2026-10-18'
),
indep AS (
  SELECT sum(CASE WHEN s.status = 'Anulación' THEN -abs(si.quantity) ELSE si.quantity END) q
  FROM sales s
  JOIN sale_items si ON si.sale_id = s.id
  JOIN products p ON p.id = si.product_id AND p.store_id = 6
  WHERE s.store_id = 6
    AND s.activity_type = 'sale'
    AND s.status IN ('Facturado','Pagado','Pendiente por pagar','Anulado','Anulación')
    AND s.credit_payment_id IS NULL
    AND COALESCE(s.sale_day_local, (s.sale_date AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
        BETWEEN '2025-11-15' AND '2026-10-18'
    AND COALESCE(p.parent_id, p.id) IN (SELECT model_id FROM modelos)
)
SELECT agg.q AS sum_agg, indep.q AS sum_independiente, agg.q - indep.q AS diferencia FROM agg, indep;

\echo '== V2 quiebre: sin_stock y con_stock en daily_sales_agg (hijos de los modelos)'
SELECT stockout, count(*) FROM daily_sales_agg WHERE store_id = 6 GROUP BY 1 ORDER BY 1;

\echo '== V3 invariante de libro: stock_eod (day = watermark) vs Σ stocks (type NULL o <> suspend) hasta el watermark'
WITH wm AS (SELECT agg_watermark_day d FROM forecast_store_settings WHERE store_id = 6),
a AS (
  SELECT branch_id, product_id, stock_eod
  FROM daily_sales_agg, wm
  WHERE store_id = 6 AND day_local = wm.d AND stock_eod IS NOT NULL
),
l AS (
  SELECT pb.branch_id, pb.product_id, sum(st.stock) s
  FROM stocks st
  JOIN "ProductBranch" pb ON pb.id = st.product_branch_id
  JOIN wm ON true
  WHERE st.store_id = 6 AND (st.type IS NULL OR st.type <> 'suspend') AND st.operation_date <= wm.d
  GROUP BY 1, 2
)
SELECT count(*) AS pares, count(*) FILTER (WHERE a.stock_eod IS DISTINCT FROM COALESCE(l.s,0)) AS discrepancias
FROM a LEFT JOIN l ON l.branch_id = a.branch_id AND l.product_id = a.product_id;

\echo '== V4 launch_date de los modelos'
SELECT launch_date_source, count(*), min(launch_date), max(launch_date)
FROM product_attributes WHERE store_id = 6 AND is_synthetic GROUP BY 1;

\echo '== V5 backtest: último run, flags, disclaimer, métricas'
SELECT r.id, r.status, r.is_synthetic, left(r.disclaimer, 60) disclaimer,
       (SELECT count(*) FROM forecast_backtest_metrics m WHERE m.run_id = r.id) metricas,
       (SELECT count(*) FROM forecast_backtest_points p WHERE p.run_id = r.id AND p.nivel = 'variante') puntos_variante
FROM forecast_runs r WHERE store_id = 6 AND kind = 'backtest' ORDER BY id DESC LIMIT 1;
\echo '-- seasonal_naive por estado'
SELECT modelo, estado, count(*) FROM forecast_backtest_metrics
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'backtest')
GROUP BY 1, 2 ORDER BY 1, 2;
\echo '-- WAPE/Bias/MASE nivel modelo, tramo todos'
SELECT modelo, round(wape::numeric,4) wape, round(bias::numeric,4) bias, round(mase::numeric,4) mase, n_series, n_puntos, estado
FROM forecast_backtest_metrics
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'backtest')
  AND nivel = 'modelo' AND horizon_bucket = 'todos' ORDER BY 1;
\echo '-- última cadena'
SELECT id, status, params->>'paso' paso FROM forecast_runs WHERE store_id = 6 AND kind = 'cadena' ORDER BY id DESC LIMIT 1;

\echo '== V6 simulación: último run, filas, candidatos, fill rate y sobrante por CR (moq_tienda)'
SELECT r.id, r.status, (SELECT count(*) FROM forecast_policy_sim_results s WHERE s.run_id = r.id) filas,
       (SELECT count(*) FROM forecast_policy_sim_results s WHERE s.run_id = r.id AND es_candidato) candidatos
FROM forecast_runs r WHERE store_id = 6 AND kind = 'policy_sim' ORDER BY id DESC LIMIT 1;
SELECT cr, moq_politica, modelo_base, round(fill_rate::numeric,4) fill_rate, round(sobrante_ratio::numeric,4) sobrante_ratio, es_candidato
FROM forecast_policy_sim_results
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'policy_sim')
ORDER BY moq_politica, cr, modelo_base;

\echo '== V7 aislamiento: store_id distintos en tablas derivadas'
SELECT 'daily_sales_agg' t, array_agg(DISTINCT store_id) FROM daily_sales_agg
UNION ALL SELECT 'forecast_runs', array_agg(DISTINCT store_id) FROM forecast_runs
UNION ALL SELECT 'product_attributes', array_agg(DISTINCT store_id) FROM product_attributes
UNION ALL SELECT 'forecast_datos_usados', array_agg(DISTINCT store_id) FROM forecast_datos_usados
UNION ALL SELECT 'forecast_modelo_tickets', array_agg(DISTINCT store_id) FROM forecast_modelo_tickets
UNION ALL SELECT 'forecast_policy_sim_traces', array_agg(DISTINCT store_id) FROM forecast_policy_sim_traces
UNION ALL SELECT 'forecast_backtest_points', array_agg(DISTINCT store_id) FROM forecast_backtest_points
UNION ALL SELECT 'forecast_backtest_metrics', array_agg(DISTINCT store_id) FROM forecast_backtest_metrics
UNION ALL SELECT 'forecast_policy_sim_results', array_agg(DISTINCT store_id) FROM forecast_policy_sim_results;
\echo '-- hijas con store_id distinto al de su corrida (esperado 0)'
SELECT (SELECT count(*) FROM forecast_backtest_points x JOIN forecast_runs r ON r.id = x.run_id WHERE x.store_id <> r.store_id)
     + (SELECT count(*) FROM forecast_backtest_metrics x JOIN forecast_runs r ON r.id = x.run_id WHERE x.store_id <> r.store_id)
     + (SELECT count(*) FROM forecast_policy_sim_results x JOIN forecast_runs r ON r.id = x.run_id WHERE x.store_id <> r.store_id)
     + (SELECT count(*) FROM forecast_policy_sim_traces x JOIN forecast_runs r ON r.id = x.run_id WHERE x.store_id <> r.store_id) AS hijas_cruzadas;

\echo '== V8 libro intacto'
SELECT (SELECT count(*) FROM v_stock_balance_drift) drift, (SELECT count(*) FROM v_stock_tenant_leak) tenant_leak;

\echo '== V10 apertura legacy (stocks.source / type)'
SELECT count(*) FILTER (WHERE source = 'legacy_opening') src_legacy_opening,
       count(*) FILTER (WHERE type = 'legacy_opening') type_legacy_opening,
       count(*) FILTER (WHERE source = 'legacy_opening' AND type IS NULL) src_y_type_null
FROM stocks;

\echo '== V11 Fundamento'
\echo '-- unidades_netas = Σqty del período'
SELECT d.unidades_netas, (SELECT sum(qty) FROM daily_sales_agg a WHERE a.store_id = 6 AND a.day_local BETWEEN d.desde AND d.hasta) sum_agg,
       d.unidades_netas - (SELECT sum(qty) FROM daily_sales_agg a WHERE a.store_id = 6 AND a.day_local BETWEEN d.desde AND d.hasta) diferencia,
       d.desde, d.hasta, d.tickets
FROM forecast_datos_usados d WHERE d.store_id = 6;
\echo '-- trazas del último run: total y por estado'
SELECT estado, count(*) FROM forecast_policy_sim_traces
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'policy_sim') GROUP BY 1;
\echo '-- aritmética: objetivo = pronóstico.suma + margen.cuantil (filas ok que violan, esperado 0)'
SELECT count(*) total_ok,
       count(*) FILTER (WHERE abs((pasos->'objetivo'->>'valor')::numeric - ((pasos->'pronostico'->>'suma')::numeric + (pasos->'margen'->>'cuantil')::numeric)) > 1e-6) violan
FROM forecast_policy_sim_traces
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'policy_sim') AND estado = 'ok';
\echo '-- identidad Σ: |wape - sum_abs_error/sum_actual| < 1e-9 (esperado 0 violaciones)'
SELECT count(*) total_ok,
       count(*) FILTER (WHERE abs(wape - sum_abs_error/NULLIF(sum_actual,0)) >= 1e-9) violan
FROM forecast_backtest_metrics
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'backtest') AND estado = 'ok';

\echo '-- aritmética del pedido: antes = max(0, objetivo - neto disponible); despues = ceil(antes/moq)*moq'
SELECT count(*) total_ok,
  count(*) FILTER (WHERE abs((pasos->'moq'->>'antes')::numeric
        - greatest(0, (pasos->'objetivo'->>'valor')::numeric - (pasos->'disponible'->>'neto')::numeric)) > 1e-6) violan_antes,
  count(*) FILTER (WHERE abs((pasos->'moq'->>'despues')::numeric
        - CASE WHEN (pasos->'moq'->>'antes')::numeric <= 0 THEN 0
               ELSE ceil((pasos->'moq'->>'antes')::numeric / (pasos->'moq'->>'moq')::numeric) * (pasos->'moq'->>'moq')::numeric END) > 1e-6) violan_despues
FROM forecast_policy_sim_traces
WHERE run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'policy_sim') AND estado = 'ok';

\echo '-- errores sin futuro: ningún error del margen viene de un origen con origin + 7*semanasProteccion > origen de la traza (esperado 0)'
SELECT count(*) errores_totales,
       count(*) FILTER (WHERE (e->>'origin')::date + 7 * (t.pasos->'periodo'->>'semanasProteccion')::int > t.origin) AS con_futuro
FROM forecast_policy_sim_traces t
CROSS JOIN LATERAL jsonb_array_elements(t.pasos->'margen'->'errores') e
WHERE t.run_id = (SELECT max(id) FROM forecast_runs WHERE store_id = 6 AND kind = 'policy_sim') AND t.estado = 'ok';

\echo '== V9 sell-through: se reporta desde la API (analisis/modelos/:id/fundamento), ver endpoints.md'

\echo '== Retención: corridas por (tienda 6, kind) <= 10'
SELECT kind, count(*) FROM forecast_runs WHERE store_id = 6 GROUP BY 1 ORDER BY 1;
\echo '== TTL: corridas abandonadas / running colgadas'
SELECT status, error, count(*) FROM forecast_runs WHERE store_id = 6 AND (status = 'running' OR error = 'abandonada') GROUP BY 1, 2;
