SELECT 'tbl', tablename FROM pg_tables WHERE schemaname='public' AND tablename ~ '(rollo|roll|tela|fabric|materia|insumo|corte|cut|notif|alert|forecast|predic)' ORDER BY 2;
SELECT 'mm', store_id, count(*) FROM mes_material_movements GROUP BY 2;
SELECT 'tl', store_id, count(*), max(created_at)::date FROM talleres_lotes GROUP BY 2;
SELECT 'vn', store_id, max(created_at)::date FROM vendor_notifications GROUP BY 2;
