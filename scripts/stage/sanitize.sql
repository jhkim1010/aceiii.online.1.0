-- [2026-10-22] Stage: después de cada restauración. La copia de producción NO debe hablar con el
--   mundo: tiendas online (WooCommerce), MercadoPago, WhatsApp, Stripe, email.
--   AFIP queda imposible por otro lado: el contenedor de stage no monta los certificados.
-- ★ Columna por columna, mirando el catálogo: si producción agrega/quita columnas el script no se
--   cae y lo dice. NULL si la columna lo admite; si no, un valor inválido «stage-…».
SET lock_timeout = '5s';
DO $$
DECLARE r record; v_null boolean;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('commerce_channels','secret'), ('commerce_channels','wc_consumer_key'), ('commerce_channels','wc_consumer_secret'),
      ('wp_channels','secret'), ('wp_channels','secret_prev'), ('wp_channels','wc_consumer_key'), ('wp_channels','wc_consumer_secret'),
      ('mp_accounts','access_token'), ('mp_accounts','refresh_token'),
      ('subscription_config','mp_access_token'), ('subscription_config','stripe_secret_key'),
      ('store_whatsapp_config','access_token'),
      ('store_configs','email_api_key_enc'), ('store_configs','email_api_url')
    ) AS t(tabla, col)
  LOOP
    SELECT is_nullable = 'YES' INTO v_null FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = r.tabla AND column_name = r.col;
    IF v_null IS NULL THEN
      RAISE WARNING 'stage-sanitize: %.% no existe', r.tabla, r.col;
      CONTINUE;
    END IF;
    EXECUTE format('UPDATE %I SET %I = %s WHERE %I IS NOT NULL', r.tabla, r.col,
                   CASE WHEN v_null THEN 'NULL' ELSE quote_literal('stage-sin-credencial') END, r.col);
  END LOOP;

  -- apagar los canales y lo que dispara envíos solos
  BEGIN UPDATE commerce_channels SET is_active = false; EXCEPTION WHEN undefined_table OR undefined_column THEN RAISE WARNING 'commerce_channels.is_active'; END;
  BEGIN UPDATE wp_channels SET is_active = false; EXCEPTION WHEN undefined_table OR undefined_column THEN RAISE WARNING 'wp_channels.is_active'; END;
  BEGIN UPDATE store_whatsapp_config SET is_active = false; EXCEPTION WHEN undefined_table OR undefined_column THEN RAISE WARNING 'store_whatsapp_config.is_active'; END;
  BEGIN UPDATE store_configs SET afip_auto_issue = false; EXCEPTION WHEN undefined_column THEN RAISE WARNING 'store_configs.afip_auto_issue'; END;
  BEGIN DELETE FROM sync_outbox; EXCEPTION WHEN undefined_table THEN RAISE WARNING 'sync_outbox'; END;
  RAISE NOTICE 'stage-sanitize: listo';
END $$;
-- marca visible: cualquiera que mire la base sabe que es stage
COMMENT ON DATABASE ventago IS 'STAGE — copia de producción saneada (scripts/stage/sanitize.sql)';
