\timing on
WITH op AS (SELECT pb.product_id, sum(s.stock) opening FROM stocks s JOIN stock_balances pb ON pb.product_branch_id=s.product_branch_id WHERE s.store_id=30 AND s.source='legacy_opening' GROUP BY 1),
ing AS (SELECT product_id, sum(cantidad) q FROM legacy_ingresos WHERE store_id=30 AND product_id IS NOT NULL AND NOT coalesce(borrado,false) GROUP BY 1),
sl AS (SELECT si.product_id, sum(si.quantity) q FROM sales s JOIN sale_items si ON si.sale_id=s.id WHERE s.store_id=30 AND s.status='Pagado' AND s.source='legacy' AND si.product_id IS NOT NULL GROUP BY 1),
j AS (SELECT op.product_id, op.opening, coalesce(ing.q,0) ing, coalesce(sl.q,0) sold, coalesce(ing.q,0)-coalesce(sl.q,0) - op.opening diff FROM op LEFT JOIN ing USING(product_id) LEFT JOIN sl USING(product_id))
SELECT count(*), count(*) FILTER (WHERE diff=0), count(*) FILTER (WHERE abs(diff)<=2), count(*) FILTER (WHERE ing>0), sum(opening), sum(ing), sum(sold), percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(diff)) FROM j;
