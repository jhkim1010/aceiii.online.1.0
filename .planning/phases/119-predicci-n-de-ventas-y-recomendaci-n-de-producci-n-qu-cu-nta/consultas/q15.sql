SELECT 'cs', p.store_id, count(DISTINCT p.color_id), count(DISTINCT p.size_id), string_agg(DISTINCT c.name, ',') FILTER (WHERE c.id IS NOT NULL) , string_agg(DISTINCT z.name, ',')
FROM products p LEFT JOIN colors c ON c.id=p.color_id LEFT JOIN sizes z ON z.id=p.size_id WHERE p.store_id IN (26,28) AND p.parent_id IS NOT NULL GROUP BY 2;
SELECT 'uc', s.store_id, count(*), count(*) FILTER (WHERE coalesce(si.unit_cost,0)>0) FROM sales s JOIN sale_items si ON si.sale_id=s.id WHERE s.store_id IN (26,28,25,30,19) AND s.sale_date>='2026-01-01' GROUP BY 2;
SELECT 'names', store_id, left(name,40), sku FROM products WHERE store_id IN (26,28,25,30) AND parent_id IS NULL ORDER BY random() LIMIT 16;
