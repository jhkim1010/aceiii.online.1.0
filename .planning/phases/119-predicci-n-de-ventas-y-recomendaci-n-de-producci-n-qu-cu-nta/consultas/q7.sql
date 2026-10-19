SELECT 'stk', store_id, count(*), min(created_at)::date, max(created_at)::date, min(operation_date), max(operation_date), count(*) FILTER (WHERE operation_date IS NULL)
FROM stocks WHERE store_id IN (26,25,28,30,19,6,22,9) GROUP BY 2 ORDER BY 3 DESC;
SELECT 'typ', store_id, coalesce(type,'NULL'), coalesce(source,'NULL'), count(*), sum(stock), min(coalesce(operation_date,created_at::date)), max(coalesce(operation_date,created_at::date))
FROM stocks WHERE store_id IN (26,28,30,19,25) GROUP BY 2,3,4 ORDER BY 2,5 DESC;
