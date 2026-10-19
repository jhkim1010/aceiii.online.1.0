SELECT 'stores', count(*) FROM stores;
SELECT 'sales', count(*), min(sale_date), max(sale_date) FROM sales;
SELECT 'src', coalesce(source,'NULL'), count(*), min(sale_date)::date, max(sale_date)::date FROM sales GROUP BY 2 ORDER BY 3 DESC;
SELECT 'status', status, count(*) FROM sales GROUP BY 2 ORDER BY 3 DESC LIMIT 10;
SELECT 'activity', coalesce(activity_type,'NULL'), count(*) FROM sales GROUP BY 2 ORDER BY 3 DESC LIMIT 10;
SELECT 'items', count(*) FROM sale_items;
