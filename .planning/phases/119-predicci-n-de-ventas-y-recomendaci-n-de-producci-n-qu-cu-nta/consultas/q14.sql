SELECT 'attr', store_id, count(*) roots,
 count(*) FILTER (WHERE category_id IS NOT NULL) cat, count(DISTINCT category_id) ncat,
 count(*) FILTER (WHERE season_id IS NOT NULL) seas, count(DISTINCT season_id) nseas,
 count(*) FILTER (WHERE origin_id IS NOT NULL) ori, count(*) FILTER (WHERE supplier_id IS NOT NULL) sup,
 count(*) FILTER (WHERE coalesce(cost,0)>0) cost, count(*) FILTER (WHERE coalesce(price,0)>0) price,
 count(*) FILTER (WHERE coalesce(gender,'')<>'') gender, count(*) FILTER (WHERE coalesce(material,'')<>'') material,
 count(*) FILTER (WHERE EXISTS (SELECT 1 FROM product_subcategories ps WHERE ps.product_id=p.id)) subcat,
 min(created_at)::date, max(created_at)::date, count(DISTINCT created_at::date) ndays
FROM products p WHERE store_id IN (26,25,28,30,19,22,6) AND parent_id IS NULL GROUP BY 2;
SELECT 'cats', c.store_id, string_agg(c.name, ', ') FROM categories c WHERE store_id IN (26,25,28,30,19,22) GROUP BY 2;
SELECT 'seas', store_id, string_agg(name, ', ') FROM seasons WHERE store_id IN (26,25,28,30,19,22) GROUP BY 2;
