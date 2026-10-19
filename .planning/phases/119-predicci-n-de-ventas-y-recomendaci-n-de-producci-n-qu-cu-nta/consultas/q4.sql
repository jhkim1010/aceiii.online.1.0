SELECT 'nullname', s.store_id, left(coalesce(si.custom_name,'<NULL>'),30), count(*), sum(si.quantity)
FROM sales s JOIN sale_items si ON si.sale_id=s.id
WHERE s.store_id IN (26,28,19,30) AND si.product_id IS NULL AND s.sale_date>='2025-10-01'
GROUP BY 2,3 ORDER BY 4 DESC LIMIT 20;
-- null items by year for store 26 and 28
SELECT 'nullyr', s.store_id, extract(year from s.sale_date)::int, count(*) FILTER (WHERE si.product_id IS NULL), count(*), round(100.0*count(*) FILTER (WHERE si.product_id IS NULL)/count(*),1)
FROM sales s JOIN sale_items si ON si.sale_id=s.id WHERE s.store_id IN (26,28,30,19,25) AND s.status='Pagado' GROUP BY 2,3 ORDER BY 2,3;
