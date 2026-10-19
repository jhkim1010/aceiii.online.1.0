SELECT 'mon', s.store_id, count(DISTINCT date_trunc('month',s.sale_date)) FILTER (WHERE true) m_all,
 min(date_trunc('month',s.sale_date))::date, max(date_trunc('month',s.sale_date))::date
FROM sales s WHERE s.store_id IN (26,25,28,30,19,6,22) AND s.status='Pagado' GROUP BY 2;
-- months with >=30 sales
SELECT 'mon30', store_id, count(*), min(m)::date, max(m)::date FROM (SELECT store_id, date_trunc('month',sale_date) m, count(*) c FROM sales WHERE store_id IN (26,25,28,30,19,6,22) AND status='Pagado' GROUP BY 1,2 HAVING count(*)>=30) x GROUP BY 2;
-- last 24m: units/month and share child
SELECT 'l24', s.store_id, round(sum(si.quantity)/24.0) units_mo,
 round(100.0*sum(si.quantity) FILTER (WHERE p.parent_id IS NOT NULL)/sum(si.quantity),1) pct_child_units,
 round(100.0*sum(si.quantity) FILTER (WHERE si.product_id IS NULL)/sum(si.quantity),1) pct_null_units,
 count(DISTINCT coalesce(p.parent_id,p.id)) models
FROM sales s JOIN sale_items si ON si.sale_id=s.id LEFT JOIN products p ON p.id=si.product_id
WHERE s.store_id IN (26,25,28,30,19,6,22) AND s.status='Pagado' AND s.sale_date>=now()-interval '24 months' GROUP BY 2;
