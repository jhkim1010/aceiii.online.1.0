SELECT 'ingq', store_id, count(*), sum(cantidad), count(*) FILTER (WHERE product_id IS NOT NULL), count(*) FILTER (WHERE coalesce(num_corte,'') NOT IN ('','0')), count(DISTINCT num_corte), count(*) FILTER (WHERE borrado), count(*) FILTER (WHERE cantidad<0)
FROM legacy_ingresos GROUP BY 2;
SELECT 'ingyr', store_id, extract(year from fecha)::int y, count(*), sum(cantidad), count(DISTINCT num_corte) FROM legacy_ingresos WHERE store_id IN (26,25,30) AND fecha>='2019-01-01' GROUP BY 2,3 ORDER BY 2,3;
SELECT 'ingchild', li.store_id, count(*) FILTER (WHERE p.parent_id IS NOT NULL), count(*) FILTER (WHERE p.parent_id IS NULL) FROM legacy_ingresos li JOIN products p ON p.id=li.product_id WHERE li.store_id IN (26,25,30) GROUP BY 2;
SELECT 'ingsample', codigo, codigoproducto, left(descripcion,30), cantidad, fecha, num_corte, sucursal FROM legacy_ingresos WHERE store_id=26 AND fecha>='2026-01-01' ORDER BY id DESC LIMIT 8;
