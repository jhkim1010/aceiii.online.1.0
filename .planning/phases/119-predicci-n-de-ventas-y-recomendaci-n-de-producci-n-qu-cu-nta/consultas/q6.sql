SELECT 'm', store_id, to_char(date_trunc('month',sale_date),'YYYY-MM'), count(*), count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id=s.id)) noitems
FROM sales s WHERE store_id IN (19,30) AND status='Pagado' GROUP BY 2,3 ORDER BY 2,3;
SELECT 'prod', store_id, count(*) total, count(*) FILTER (WHERE parent_id IS NULL) roots, count(*) FILTER (WHERE parent_id IS NOT NULL) children,
 count(*) FILTER (WHERE parent_id IS NOT NULL AND color_id IS NOT NULL) ch_color, count(*) FILTER (WHERE parent_id IS NOT NULL AND size_id IS NOT NULL) ch_size,
 count(*) FILTER (WHERE parent_id IS NULL AND EXISTS (SELECT 1 FROM products c WHERE c.parent_id=p.id)) roots_with_children
FROM products p WHERE store_id IN (26,25,28,30,19,6,22,9) GROUP BY 2 ORDER BY 3 DESC;
