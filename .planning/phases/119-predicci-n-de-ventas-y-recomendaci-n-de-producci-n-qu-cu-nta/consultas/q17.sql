SELECT 'oo', store_id, coalesce(channel::text, '?'), status::text, count(*), min(created_at)::date, max(created_at)::date FROM online_orders GROUP BY 2,3,4 ORDER BY 5 DESC LIMIT 20;
