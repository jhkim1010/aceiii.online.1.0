SELECT s.store_id, st.name, count(*) n, count(*) FILTER (WHERE source='legacy') leg, count(*) FILTER (WHERE source='pos') pos, count(*) FILTER (WHERE source='online') onl,
 min(sale_date)::date, max(sale_date)::date,
 min(sale_date) FILTER (WHERE source='legacy')::date, max(sale_date) FILTER (WHERE source='legacy')::date,
 min(sale_date) FILTER (WHERE source<>'legacy')::date,
 count(DISTINCT date_trunc('month',sale_date)) months, count(DISTINCT branch_id) branches
FROM sales s JOIN stores st ON st.id=s.store_id GROUP BY 1,2 ORDER BY n DESC;
