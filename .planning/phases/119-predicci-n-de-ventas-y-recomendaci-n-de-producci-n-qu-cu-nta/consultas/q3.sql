-- item linkage per store: child (parent_id not null), madre (is_parent or parent_id null with children), null product, generic
SELECT s.store_id,
 count(*) items,
 sum(si.quantity) units,
 count(*) FILTER (WHERE si.product_id IS NULL) null_prod,
 count(*) FILTER (WHERE p.parent_id IS NOT NULL) child,
 count(*) FILTER (WHERE p.id IS NOT NULL AND p.parent_id IS NULL AND coalesce(p.is_parent,false)) madre_isparent,
 count(*) FILTER (WHERE p.id IS NOT NULL AND p.parent_id IS NULL AND NOT coalesce(p.is_parent,false)) standalone,
 count(*) FILTER (WHERE p.is_generic) generic,
 count(*) FILTER (WHERE p.id IS NOT NULL AND p.store_id<>s.store_id) cross_store,
 count(*) FILTER (WHERE si.product_id IS NOT NULL AND p.id IS NULL) dangling,
 count(DISTINCT si.product_id) dist_prod,
 count(DISTINCT coalesce(p.parent_id,p.id)) dist_model
FROM sales s JOIN sale_items si ON si.sale_id=s.id LEFT JOIN products p ON p.id=si.product_id
WHERE s.store_id IN (26,25,28,30,19,6,22,9) AND s.status='Pagado'
GROUP BY 1 ORDER BY items DESC;
