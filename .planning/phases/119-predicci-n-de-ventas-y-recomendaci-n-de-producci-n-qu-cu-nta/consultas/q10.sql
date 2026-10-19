SELECT 'categories', store_id, count(*) FROM categories GROUP BY 2 UNION ALL
SELECT 'legacy_facturas', store_id, count(*) FROM legacy_facturas GROUP BY 2 UNION ALL
SELECT 'legacy_ingresos', store_id, count(*) FROM legacy_ingresos GROUP BY 2 UNION ALL
SELECT 'mes_bom', store_id, count(*) FROM mes_bom GROUP BY 2 UNION ALL
SELECT 'mes_bom_items', -1, count(*) FROM mes_bom_items UNION ALL
SELECT 'mes_material_categories', store_id, count(*) FROM mes_material_categories GROUP BY 2 UNION ALL
SELECT 'mes_material_movements', store_id, count(*) FROM mes_material_movements GROUP BY 2 UNION ALL
SELECT 'mes_material_supplier_payments', store_id, count(*) FROM mes_material_supplier_payments GROUP BY 2 UNION ALL
SELECT 'mes_material_suppliers', store_id, count(*) FROM mes_material_suppliers GROUP BY 2 UNION ALL
SELECT 'mes_materials', store_id, count(*) FROM mes_materials GROUP BY 2 UNION ALL
SELECT 'mes_production_results', -1, count(*) FROM mes_production_results UNION ALL
SELECT 'mes_work_orders', store_id, count(*) FROM mes_work_orders GROUP BY 2 UNION ALL
SELECT 'mobile_stock_ingresos', store_id, count(*) FROM mobile_stock_ingresos GROUP BY 2 UNION ALL
SELECT 'origins', store_id, count(*) FROM origins GROUP BY 2 UNION ALL
SELECT 'product_categories', -1, count(*) FROM product_categories UNION ALL
SELECT 'product_subcategories', -1, count(*) FROM product_subcategories UNION ALL
SELECT 'product_variants', -1, count(*) FROM product_variants UNION ALL
SELECT 'seasons', store_id, count(*) FROM seasons GROUP BY 2 UNION ALL
SELECT 'subcategories', store_id, count(*) FROM subcategories GROUP BY 2 UNION ALL
SELECT 'suppliers', store_id, count(*) FROM suppliers GROUP BY 2 UNION ALL
SELECT 'talleres_cut_ticket_counters', store_id, count(*) FROM talleres_cut_ticket_counters GROUP BY 2 UNION ALL
SELECT 'talleres_defect_codes', store_id, count(*) FROM talleres_defect_codes GROUP BY 2 UNION ALL
SELECT 'talleres_defects', -1, count(*) FROM talleres_defects UNION ALL
SELECT 'talleres_deliveries', -1, count(*) FROM talleres_deliveries UNION ALL
SELECT 'talleres_envio_materiales', -1, count(*) FROM talleres_envio_materiales UNION ALL
SELECT 'talleres_envios', store_id, count(*) FROM talleres_envios GROUP BY 2 UNION ALL
SELECT 'talleres_etapas', store_id, count(*) FROM talleres_etapas GROUP BY 2 UNION ALL
SELECT 'talleres_lote_quantity_events', store_id, count(*) FROM talleres_lote_quantity_events GROUP BY 2 UNION ALL
SELECT 'talleres_lotes', store_id, count(*) FROM talleres_lotes GROUP BY 2 UNION ALL
SELECT 'talleres_material_issues', -1, count(*) FROM talleres_material_issues UNION ALL
SELECT 'talleres_orders', store_id, count(*) FROM talleres_orders GROUP BY 2 UNION ALL
SELECT 'talleres_payments', -1, count(*) FROM talleres_payments UNION ALL
SELECT 'talleres_qc_items', store_id, count(*) FROM talleres_qc_items GROUP BY 2 UNION ALL
SELECT 'talleres_recepcion_items', store_id, count(*) FROM talleres_recepcion_items GROUP BY 2 UNION ALL
SELECT 'talleres_recepciones', store_id, count(*) FROM talleres_recepciones GROUP BY 2 UNION ALL
SELECT 'talleres_rework_orders', store_id, count(*) FROM talleres_rework_orders GROUP BY 2 UNION ALL
SELECT 'talleres_settlement_lines', store_id, count(*) FROM talleres_settlement_lines GROUP BY 2 UNION ALL
SELECT 'talleres_settlements', store_id, count(*) FROM talleres_settlements GROUP BY 2 UNION ALL
SELECT 'talleres_vendor_etapas', -1, count(*) FROM talleres_vendor_etapas UNION ALL
SELECT 'talleres_vendors', store_id, count(*) FROM talleres_vendors GROUP BY 2 UNION ALL
SELECT 'vendor_notifications', store_id, count(*) FROM vendor_notifications GROUP BY 2 UNION ALL
SELECT 'end',0,0;
