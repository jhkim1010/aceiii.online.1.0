-- Shaple launches per year by first ingreso of madre
WITH f AS (SELECT coalesce(p.parent_id,p.id) m, min(li.fecha) d FROM legacy_ingresos li JOIN products p ON p.id=li.product_id WHERE li.store_id=26 AND li.cantidad>0 GROUP BY 1)
SELECT 'launch', extract(year from d)::int, count(*) FROM f GROUP BY 2 ORDER BY 2;
-- Shaple: madre children count distribution + units per madre last 12m
WITH u AS (SELECT coalesce(p.parent_id,p.id) m, sum(si.quantity) q FROM sales s JOIN sale_items si ON si.sale_id=s.id JOIN products p ON p.id=si.product_id WHERE s.store_id=26 AND s.status='Pagado' AND s.sale_date>=now()-interval '12 months' GROUP BY 1)
SELECT 'u12', count(*), percentile_cont(array[0.25,0.5,0.75,0.9]) WITHIN GROUP (ORDER BY q), sum(q) FROM u;
-- Charo: names vs products
SELECT 'charo', count(*), count(DISTINCT lower(trim(name))) FROM products WHERE store_id=25;
-- ingresos per receipt day size (batch proxy) Shaple 2025
SELECT 'batch', count(*) days, percentile_cont(0.5) WITHIN GROUP (ORDER BY q) FROM (SELECT coalesce(p.parent_id,p.id) m, li.fecha, sum(cantidad) q FROM legacy_ingresos li JOIN products p ON p.id=li.product_id WHERE li.store_id=26 AND li.fecha>='2025-01-01' AND li.cantidad>0 GROUP BY 1,2) x;
