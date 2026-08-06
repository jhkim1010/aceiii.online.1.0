# Ventago Database Schema (PostgreSQL public)

> Auto-generated from local PG18 `ventago` DB on 2026-08-06T20:06:49Z.
> **Regenerate**: `./.planning/intel/db-schema.regen.sh`
> **운영 PG10 == local PG18** — 같은 마이그레이션 적용 (api-ventago/migrations/)

## Conventions

- 모든 컬럼 `snake_case` (Sequelize `underscored: true` 전역).
- Sequelize 모델은 `camelCase` 속성 → DB `snake_case` 컬럼 자동 매핑.
- SQL 직접 작성 시 **반드시 이 파일의 snake_case 이름 사용**.
- 멀티테넌트: 거의 모든 테이블에 `store_id` FK.

## `ProductBranch`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('"ProductBranch_id_seq"'::reg... |
| `product_id` | integer |  |  |
| `branch_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `Sellers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('"Sellers_id_seq"'::regclass) |
| `name` | character varying(255) |  |  |
| `last_name` | character varying(255) |  |  |
| `document` | character varying(255) |  |  |
| `phone` | character varying(255) |  |  |
| `is_active` | boolean |  | true |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `linked_user_id` | integer |  |  |
| `pin_hash` | character varying(100) |  |  |
| `pin_updated_at` | timestamp with time zone |  |  |

## `_phase26_cat_map`

| Column | Type | Null | Default |
|---|---|---|---|
| `old_cat_id` | integer |  |  |
| `old_subcat_id` | integer |  |  |
| `new_cat_id` | integer | NOT NULL |  |

## `active_sessions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('active_sessions_id_seq'::reg... |
| `user_id` | integer | NOT NULL |  |
| `session_token` | character varying(255) | NOT NULL |  |
| `device_fingerprint` | character varying(255) |  |  |
| `public_ip` | character varying(255) |  |  |
| `user_agent` | text |  |  |
| `terminal_id` | integer |  |  |
| `branch_id` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `last_activity_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `afip_issuers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('afip_issuers_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `punto_venta` | integer | NOT NULL |  |
| `cuit` | character varying(13) | NOT NULL |  |
| `cool_user` | character varying(100) |  |  |
| `iva_condition` | character varying(10) | NOT NULL | 'RI'::character varying |
| `razon_social` | character varying(200) |  |  |
| `razon_social_l2` | character varying(200) |  |  |
| `domicilio` | character varying(250) |  |  |
| `ingresos_brutos` | character varying(50) |  |  |
| `inicio_actividad` | character varying(20) |  |  |
| `telefono` | character varying(50) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `branch_id` | integer |  |  |
| `invoice_sucursal` | integer |  |  |
| `invoice_type` | character varying(1) | NOT NULL | 'A'::character varying |

## `afip_vouchers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('afip_vouchers_id_seq'::regcl... |
| `store_id` | integer | NOT NULL |  |
| `sale_id` | integer | NOT NULL |  |
| `cae` | character varying(20) | NOT NULL |  |
| `cae_vto` | date | NOT NULL |  |
| `punto_venta` | integer | NOT NULL |  |
| `afip_number` | integer | NOT NULL |  |
| `tipo_comprobante` | integer | NOT NULL |  |
| `doc_tipo` | integer | NOT NULL |  |
| `doc_nro` | character varying(20) |  |  |
| `imp_total` | numeric | NOT NULL |  |
| `neto_gravado` | numeric |  |  |
| `iva_liquidado` | numeric |  |  |
| `iva_alicuota` | integer |  |  |
| `invoice_pct` | numeric | NOT NULL | 100 |
| `nota_credito` | boolean | NOT NULL | false |
| `nota_debito` | boolean | NOT NULL | false |
| `cae_anterior` | character varying(20) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `app_boot_flags`

| Column | Type | Null | Default |
|---|---|---|---|
| `key` | character varying(64) | NOT NULL |  |
| `value` | text | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `approval_requests`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('approval_requests_id_seq'::r... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `requested_by` | integer | NOT NULL |  |
| `function_slug` | character varying(100) | NOT NULL |  |
| `payload` | jsonb | NOT NULL |  |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `approved_by` | integer |  |  |
| `approval_note` | text |  |  |
| `expires_at` | timestamp without time zone | NOT NULL |  |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `resolved_at` | timestamp without time zone |  |  |
| `requester_role_slugs` | ARRAY |  |  |
| `required_approver_roles` | ARRAY |  |  |

## `approval_thresholds`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('approval_thresholds_id_seq':... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `function_slug` | character varying(100) | NOT NULL |  |
| `role_slug` | character varying(50) | NOT NULL |  |
| `max_amount` | numeric |  |  |
| `max_quantity` | integer |  |  |
| `approver_role_slug` | character varying(50) | NOT NULL |  |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `updated_at` | timestamp without time zone | NOT NULL | now() |

## `apps`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('apps_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `color` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `audit_logs`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('audit_logs_id_seq'::regclass) |
| `entity_type` | character varying(50) | NOT NULL |  |
| `entity_id` | integer | NOT NULL |  |
| `action` | USER-DEFINED | NOT NULL |  |
| `description` | text | NOT NULL |  |
| `old_values` | jsonb |  |  |
| `new_values` | jsonb |  |  |
| `user_id` | integer | NOT NULL |  |
| `store_id` | integer |  |  |
| `ip_address` | inet |  |  |
| `user_agent` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `backfill_failures`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('backfill_failures_id_seq'::r... |
| `source_table` | character varying(50) | NOT NULL |  |
| `source_row_id` | bigint | NOT NULL |  |
| `reason` | character varying(255) | NOT NULL |  |
| `raw_note` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `box_operations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('box_operations_id_seq'::regc... |
| `cash_register_id` | integer |  |  |
| `user_id` | integer |  |  |
| `terminal_id` | integer |  |  |
| `description` | character varying(255) |  |  |
| `amount` | double precision | NOT NULL |  |
| `type` | USER-DEFINED | NOT NULL |  |
| `execution_type` | USER-DEFINED | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `boxes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('boxes_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `status` | character varying(255) |  | 'activo'::character varying |
| `is_deleted` | boolean |  | false |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `branch_agents`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('branch_agents_id_seq'::regcl... |
| `branch_id` | integer | NOT NULL |  |
| `agent_type` | character varying(20) | NOT NULL | 'thermal'::character varying |
| `label` | character varying(100) | NOT NULL | 'Agente de Impresión'::character var... |
| `api_key` | character varying(64) | NOT NULL |  |
| `printer_config` | jsonb |  |  |
| `is_online` | boolean | NOT NULL | false |
| `last_seen_at` | timestamp with time zone |  |  |
| `socket_id` | character varying(64) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `branch_ip_registries`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('branch_ip_registries_id_seq'... |
| `public_ip` | character varying(255) | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `registered_at` | timestamp with time zone | NOT NULL |  |
| `last_seen_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `branch_price_types_disabled`

| Column | Type | Null | Default |
|---|---|---|---|
| `branch_id` | integer | NOT NULL |  |
| `price_type_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `branch_printer_configs`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('branch_printer_configs_id_se... |
| `branch_id` | integer | NOT NULL |  |
| `api_key` | character varying(64) | NOT NULL |  |
| `is_online` | boolean | NOT NULL | false |
| `last_seen_at` | timestamp with time zone |  |  |
| `printer_info` | jsonb |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `branches`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('branches_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `is_main` | boolean |  |  |
| `api_key` | character varying(255) |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `point_of_sale` | character varying(255) |  |  |
| `address_commercial` | character varying(255) |  |  |
| `is_warehouse` | boolean | NOT NULL | false |

## `caja_fuerte_operations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('caja_fuerte_operations_id_se... |
| `caja_fuerte_id` | integer | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `type` | USER-DEFINED | NOT NULL |  |
| `source` | USER-DEFINED | NOT NULL |  |
| `description` | text |  |  |
| `cash_register_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `caja_fuertes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('caja_fuertes_id_seq'::regclass) |
| `branch_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `balance` | numeric | NOT NULL | 0 |
| `is_active` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `campaign_recipients`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('campaign_recipients_id_seq':... |
| `campaign_id` | bigint | NOT NULL |  |
| `client_id` | integer |  |  |
| `channel` | character varying(20) | NOT NULL |  |
| `to_address` | character varying(160) | NOT NULL |  |
| `rendered_body` | text |  |  |
| `wa_message_id` | character varying(80) |  |  |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `attempts` | integer | NOT NULL | 0 |
| `max_attempts` | integer | NOT NULL | 5 |
| `next_retry_at` | timestamp with time zone | NOT NULL | now() |
| `last_error` | text |  |  |
| `processed_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `campaigns`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('campaigns_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `name` | character varying(160) | NOT NULL |  |
| `channel` | character varying(20) | NOT NULL | 'whatsapp'::character varying |
| `status` | character varying(20) | NOT NULL | 'draft'::character varying |
| `wa_template_name` | character varying(120) |  |  |
| `wa_template_lang` | character varying(10) |  | 'es_AR'::character varying |
| `subject` | character varying(255) |  |  |
| `body_template` | text |  |  |
| `flyer_url` | character varying(255) |  |  |
| `audience_json` | jsonb | NOT NULL | '{}'::jsonb |
| `scheduled_at` | timestamp with time zone |  |  |
| `total_recipients` | integer | NOT NULL | 0 |
| `sent_count` | integer | NOT NULL | 0 |
| `failed_count` | integer | NOT NULL | 0 |
| `created_by` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `cash_registers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('cash_registers_id_seq'::regc... |
| `box_id` | integer | NOT NULL |  |
| `terminal_id` | integer | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `date` | date | NOT NULL |  |
| `start_time` | time without time zone | NOT NULL |  |
| `closing_time` | time without time zone |  |  |
| `initial_amount` | numeric | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('categories_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 0 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `global_category_id` | integer |  |  |
| `canonical_category_id` | integer |  |  |

## `category_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('category_discounts_id_seq'::... |
| `category_id` | integer |  |  |
| `discount_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `chat_messages`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('chat_messages_id_seq'::regcl... |
| `user_id` | integer | NOT NULL |  |
| `store_id` | integer |  |  |
| `role` | USER-DEFINED | NOT NULL |  |
| `content` | text | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `cheques`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('cheques_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `number` | character varying(50) | NOT NULL |  |
| `bank` | character varying(100) | NOT NULL |  |
| `holder_name` | character varying(150) |  |  |
| `holder_cuit` | character varying(20) |  |  |
| `amount` | numeric | NOT NULL |  |
| `type` | character varying(10) | NOT NULL | 'comun'::character varying |
| `due_date` | date |  |  |
| `status` | character varying(15) | NOT NULL | 'EN_CARTERA'::character varying |
| `sale_id` | integer |  |  |
| `received_at` | timestamp with time zone | NOT NULL | now() |
| `deposited_at` | timestamp with time zone |  |  |
| `rejected_at` | timestamp with time zone |  |  |
| `notes` | character varying(255) |  |  |
| `created_by` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `client_access_audits`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('client_access_audits_id_seq'... |
| `user_id` | integer | NOT NULL |  |
| `caller_store_id` | integer | NOT NULL |  |
| `caller_owner_group_id` | integer | NOT NULL |  |
| `target_store_id` | integer |  |  |
| `target_owner_group_id` | integer |  |  |
| `target_global_client_id` | integer |  |  |
| `endpoint` | text | NOT NULL |  |
| `method` | character varying(10) | NOT NULL |  |
| `ip_address` | character varying(45) |  |  |
| `user_agent` | text |  |  |
| `denied_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `client_contact_prefs`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('client_contact_prefs_id_seq'... |
| `client_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `whatsapp_opt_in` | boolean | NOT NULL | false |
| `whatsapp_opt_out` | boolean | NOT NULL | false |
| `email_opt_out` | boolean | NOT NULL | false |
| `opt_in_source` | character varying(40) |  |  |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `client_imports`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('client_imports_id_seq'::regc... |
| `user_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `file_name` | character varying(255) | NOT NULL |  |
| `total_rows` | integer | NOT NULL | 0 |
| `created_count` | integer | NOT NULL | 0 |
| `updated_count` | integer | NOT NULL | 0 |
| `skipped_count` | integer | NOT NULL | 0 |
| `error_count` | integer | NOT NULL | 0 |
| `executed_at` | timestamp with time zone | NOT NULL | now() |
| `missing_doc_policy` | character varying(20) | NOT NULL | 'local'::character varying |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `client_merges`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('client_merges_id_seq'::regcl... |
| `user_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `winner_global_client_id` | integer | NOT NULL |  |
| `loser_global_client_id` | integer |  |  |
| `local_client_id` | integer |  |  |
| `field_picks` | jsonb | NOT NULL | '{}'::jsonb |
| `merge_reason` | character varying(50) | NOT NULL | 'promote_conflict'::character varying |
| `merged_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `client_segments`

| Column | Type | Null | Default |
|---|---|---|---|
| `client_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `last_purchase_at` | timestamp with time zone |  |  |
| `purchase_count` | integer | NOT NULL | 0 |
| `total_spent` | numeric | NOT NULL | 0 |
| `bought_via_envio` | boolean | NOT NULL | false |
| `last_branch_id` | integer |  |  |
| `cta_cte_balance` | numeric | NOT NULL | 0 |
| `refreshed_at` | timestamp with time zone | NOT NULL | now() |

## `client_segments_backup_20260729`

| Column | Type | Null | Default |
|---|---|---|---|
| `client_id` | integer |  |  |
| `store_id` | integer |  |  |
| `last_purchase_at` | timestamp with time zone |  |  |
| `purchase_count` | integer |  |  |
| `total_spent` | numeric |  |  |
| `bought_via_envio` | boolean |  |  |
| `last_branch_id` | integer |  |  |
| `cta_cte_balance` | numeric |  |  |
| `refreshed_at` | timestamp with time zone |  |  |

## `clients`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('clients_id_seq'::regclass) |
| `fullname` | character varying(255) |  |  |
| `document` | character varying(255) |  |  |
| `name_fantasy` | character varying(255) |  |  |
| `transport` | character varying(255) |  |  |
| `res_iva` | character varying(255) |  |  |
| `email` | character varying(255) |  |  |
| `phone` | character varying(255) |  |  |
| `note` | character varying(255) |  |  |
| `address` | character varying(255) |  |  |
| `location` | character varying(255) |  |  |
| `province_id` | integer |  |  |
| `is_active` | boolean |  | true |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `province_text` | character varying(100) |  |  |
| `whatsapp` | character varying(255) |  |  |
| `seller_id` | integer |  |  |

## `code_imports`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('code_imports_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `file_name` | character varying(255) |  |  |
| `total_rows` | integer | NOT NULL | 0 |
| `colors_created` | integer | NOT NULL | 0 |
| `colors_updated` | integer | NOT NULL | 0 |
| `colors_skipped` | integer | NOT NULL | 0 |
| `parents_created` | integer | NOT NULL | 0 |
| `parents_updated` | integer | NOT NULL | 0 |
| `parents_skipped` | integer | NOT NULL | 0 |
| `variants_created` | integer | NOT NULL | 0 |
| `variants_updated` | integer | NOT NULL | 0 |
| `variants_skipped` | integer | NOT NULL | 0 |
| `prices_created` | integer | NOT NULL | 0 |
| `prices_updated` | integer | NOT NULL | 0 |
| `prices_skipped` | integer | NOT NULL | 0 |
| `error_count` | integer | NOT NULL | 0 |
| `errors_json` | jsonb |  |  |
| `status` | character varying(32) | NOT NULL | 'COMPLETED'::character varying |
| `default_existing_hit_policy` | character varying(16) | NOT NULL | 'skip'::character varying |
| `duration_ms` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `colors`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('colors_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `hex` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `commerce_channels`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('commerce_channels_id_seq'::r... |
| `store_id` | integer | NOT NULL |  |
| `platform` | character varying(20) | NOT NULL | 'woocommerce'::character varying |
| `branch_id` | integer | NOT NULL |  |
| `stock_source_branch_id` | integer | NOT NULL |  |
| `channel_key` | character varying(64) | NOT NULL |  |
| `secret` | character varying(128) | NOT NULL |  |
| `site_url` | character varying(255) |  |  |
| `wc_consumer_key` | character varying(255) |  |  |
| `wc_consumer_secret` | character varying(255) |  |  |
| `external_meta` | jsonb | NOT NULL | '{}'::jsonb |
| `stock_cap` | integer | NOT NULL | 100 |
| `regular_price_type_id` | integer |  |  |
| `promo_price_type_id` | integer |  |  |
| `is_active` | boolean | NOT NULL | true |
| `last_received_at` | timestamp with time zone |  |  |
| `last_pushed_at` | timestamp with time zone |  |  |
| `legacy_wp_channel_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `configurations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('configurations_id_seq'::regc... |
| `key` | character varying(255) |  |  |
| `nombre` | character varying(255) |  |  |
| `data` | json |  |  |
| `description` | character varying(255) |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `credit_ledger`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('credit_ledger_id_seq'::regcl... |
| `store_id` | integer | NOT NULL |  |
| `store_client_id` | integer | NOT NULL |  |
| `movement_type` | character varying(20) | NOT NULL |  |
| `bucket` | character varying(10) | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `bucket_after` | numeric | NOT NULL |  |
| `sale_id` | integer |  |  |
| `payment_id` | bigint |  |  |
| `parent_ledger_id` | bigint |  |  |
| `due_date` | date |  |  |
| `branch_id` | integer |  |  |
| `terminal_id` | integer |  |  |
| `user_id` | integer |  |  |
| `note` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `credit_payments`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('credit_payments_id_seq'::reg... |
| `store_id` | integer | NOT NULL |  |
| `store_client_id` | integer | NOT NULL |  |
| `total_amount` | numeric | NOT NULL |  |
| `payment_method_id` | integer | NOT NULL |  |
| `option_id` | integer |  |  |
| `receipt_no` | character varying(40) | NOT NULL |  |
| `branch_id` | integer |  |  |
| `user_id` | integer |  |  |
| `note` | text |  |  |
| `paid_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `despacho_devices`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('despacho_devices_id_seq'::re... |
| `store_id` | integer | NOT NULL |  |
| `label` | character varying(120) | NOT NULL |  |
| `api_key` | character varying(80) | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |
| `last_seen_at` | timestamp without time zone |  |  |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `updated_at` | timestamp without time zone | NOT NULL | now() |

## `despacho_operarios`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('despacho_operarios_id_seq'::... |
| `store_id` | integer | NOT NULL |  |
| `name` | character varying(120) | NOT NULL |  |
| `pin_hash` | character varying(100) | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `updated_at` | timestamp without time zone | NOT NULL | now() |

## `discount_reasons`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('discount_reasons_id_seq'::re... |
| `sale_id` | integer |  |  |
| `description` | character varying(255) |  |  |
| `discount_value` | integer |  |  |
| `discount_type` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('discounts_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `discount_type` | character varying(255) |  |  |
| `discount_value` | numeric |  |  |
| `start_date` | timestamp with time zone |  |  |
| `end_date` | timestamp with time zone |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |

## `expense_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expense_categories_id_seq'::... |
| `name` | character varying(120) | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `parent_id` | integer |  |  |
| `path` | text | NOT NULL | ''::text |
| `depth` | smallint | NOT NULL | 0 |
| `sort_order` | integer | NOT NULL | 0 |
| `color` | character varying(16) |  |  |
| `icon` | character varying(64) |  |  |
| `status` | smallint | NOT NULL | 1 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `expense_cheques`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expense_cheques_id_seq'::reg... |
| `expense_id` | integer | NOT NULL |  |
| `cheque_id` | integer | NOT NULL |  |
| `applied_amount` | numeric | NOT NULL |  |
| `difference_amount` | numeric | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `expenses`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expenses_id_seq'::regclass) |
| `amount` | numeric | NOT NULL |  |
| `description` | character varying(255) | NOT NULL |  |
| `date` | timestamp with time zone | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `expenses_subcategory_id` | integer | NOT NULL |  |
| `affects_box` | boolean | NOT NULL | true |
| `box_register_id` | integer |  |  |
| `branch_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `category_id` | integer |  |  |
| `payment_source` | character varying(10) | NOT NULL | 'caja'::character varying |

## `expenses_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expenses_categories_id_seq':... |
| `name` | character varying(255) | NOT NULL |  |
| `status` | integer |  | 0 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `expenses_subcategories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expenses_subcategories_id_se... |
| `name` | character varying(255) | NOT NULL |  |
| `category_id` | integer | NOT NULL |  |
| `status` | integer |  | 0 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `functions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('functions_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `module_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `permission_slug` | character varying(100) |  |  |
| `resource_key` | character varying(100) |  |  |

## `functions_bak_slug_20260728`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer |  |  |
| `name` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `module_id` | integer |  |  |
| `created_at` | timestamp with time zone |  |  |
| `updated_at` | timestamp with time zone |  |  |
| `permission_slug` | character varying(100) |  |  |
| `resource_key` | character varying(100) |  |  |

## `global_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('global_categories_id_seq'::r... |
| `name` | character varying(255) | NOT NULL |  |
| `description` | text |  |  |
| `is_active` | boolean |  | true |
| `created_by_store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `global_clients`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('global_clients_id_seq'::regc... |
| `document` | character varying(50) |  |  |
| `fullname` | character varying(255) | NOT NULL |  |
| `name_fantasy` | character varying(255) |  |  |
| `phone` | character varying(100) |  |  |
| `email` | character varying(255) |  |  |
| `address` | text |  |  |
| `location` | character varying(255) |  |  |
| `province_id` | integer |  |  |
| `transport` | character varying(255) |  |  |
| `res_iva` | character varying(50) |  |  |
| `is_risky` | boolean |  | false |
| `risky_reason` | text |  |  |
| `risky_registered_by_store_id` | integer |  |  |
| `risky_registered_at` | timestamp with time zone |  |  |
| `created_by_store_id` | integer | NOT NULL |  |
| `is_active` | boolean |  | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `owner_group_id` | integer | NOT NULL |  |
| `province` | character varying(100) |  |  |
| `postal_code` | character varying(10) |  |  |
| `transport_address` | character varying(500) |  |  |
| `transport_location` | character varying(100) |  |  |
| `transport_province` | character varying(100) |  |  |
| `tipo` | integer |  |  |
| `note` | character varying(800) |  |  |
| `updated_by_store_id` | integer |  |  |
| `whatsapp` | character varying(100) |  |  |

## `global_subcategories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('global_subcategories_id_seq'... |
| `name` | character varying(255) | NOT NULL |  |
| `global_category_id` | integer | NOT NULL |  |
| `is_active` | boolean |  | true |
| `created_by_store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `knowledge_documents`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('knowledge_documents_id_seq':... |
| `title` | character varying(255) | NOT NULL |  |
| `content` | text | NOT NULL |  |
| `source` | character varying(255) |  |  |
| `drive_file_id` | character varying(255) |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `legacy_imports`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('legacy_imports_id_seq'::regc... |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `file_name` | character varying(255) |  |  |
| `file_size_bytes` | integer | NOT NULL | 0 |
| `code_import_id` | integer |  |  |
| `tables_summary` | jsonb |  |  |
| `errors` | jsonb |  |  |
| `error_count` | integer | NOT NULL | 0 |
| `status` | character varying(32) | NOT NULL | 'COMPLETED'::character varying |
| `existing_hit_policy` | character varying(16) | NOT NULL | 'skip'::character varying |
| `duration_ms` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `marketplace_config`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('marketplace_config_id_seq'::... |
| `store_id` | integer | NOT NULL |  |
| `is_published` | boolean |  | false |
| `commission_rate` | numeric |  | 0 |
| `store_description` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mes_bom`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_bom_id_seq'::regclass) |
| `product_id` | integer | NOT NULL |  |
| `version` | character varying(255) |  |  |
| `is_active` | boolean |  | true |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mes_bom_items`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_bom_items_id_seq'::regcl... |
| `bom_id` | integer | NOT NULL |  |
| `material_id` | integer |  |  |
| `sub_product_id` | integer |  |  |
| `quantity` | numeric | NOT NULL |  |
| `unit` | character varying(255) |  |  |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `unit_price_override` | numeric |  |  |

## `mes_material_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_material_categories_id_s... |
| `name` | character varying(255) | NOT NULL |  |
| `slug` | character varying(255) | NOT NULL |  |
| `icon` | character varying(255) |  |  |
| `color` | character varying(255) |  |  |
| `description` | text |  |  |
| `is_default` | boolean |  | false |
| `is_active` | boolean |  | true |
| `sort_order` | integer |  | 0 |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mes_material_movements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_material_movements_id_se... |
| `type` | USER-DEFINED | NOT NULL |  |
| `material_id` | integer | NOT NULL |  |
| `quantity` | numeric | NOT NULL |  |
| `unit` | character varying(255) |  |  |
| `movement_date` | date | NOT NULL |  |
| `supplier_id` | integer |  |  |
| `unit_price` | numeric |  |  |
| `total_amount` | numeric |  |  |
| `payment_status` | USER-DEFINED |  |  |
| `paid_amount` | numeric |  | 0 |
| `work_order_id` | integer |  |  |
| `reference` | character varying(255) |  |  |
| `notes` | text |  |  |
| `created_by` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mes_material_supplier_payments`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_material_supplier_paymen... |
| `supplier_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `method` | USER-DEFINED | NOT NULL | 'EFECTIVO'::enum_mes_material_supplie... |
| `payment_date` | date | NOT NULL |  |
| `reference` | character varying(255) |  |  |
| `note` | text |  |  |
| `movement_id` | integer |  |  |
| `created_by` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mes_material_suppliers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_material_suppliers_id_se... |
| `name` | character varying(255) | NOT NULL |  |
| `cuit` | character varying(64) |  |  |
| `phone` | character varying(64) |  |  |
| `whatsapp` | character varying(64) |  |  |
| `email` | character varying(255) |  |  |
| `address` | text |  |  |
| `contact_person` | character varying(255) |  |  |
| `payment_terms` | character varying(255) |  |  |
| `notes` | text |  |  |
| `is_active` | boolean | NOT NULL | true |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `mes_materials`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_materials_id_seq'::regcl... |
| `code` | character varying(255) | NOT NULL |  |
| `name` | character varying(255) | NOT NULL |  |
| `unit` | character varying(255) |  |  |
| `standard_price` | numeric |  |  |
| `description` | text |  |  |
| `is_active` | boolean |  | true |
| `category_id` | integer |  |  |
| `supplier_id` | integer |  |  |
| `current_stock` | numeric |  | 0 |
| `min_stock` | numeric |  | 0 |
| `last_entry_date` | date |  |  |
| `color` | character varying(255) |  |  |
| `origin` | character varying(255) |  |  |
| `quality` | character varying(255) |  |  |
| `image_url` | character varying(255) |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `parent_id` | integer |  |  |
| `is_parent` | boolean | NOT NULL | false |
| `color_id` | integer |  |  |
| `purchase_unit` | character varying(20) |  |  |
| `consumption_unit` | character varying(20) |  |  |
| `conversion_factor` | numeric |  |  |
| `merma_pct` | numeric | NOT NULL | 0 |

## `mes_production_results`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_production_results_id_se... |
| `work_order_id` | integer | NOT NULL |  |
| `produced_quantity` | numeric | NOT NULL |  |
| `defect_quantity` | numeric |  | 0 |
| `production_date` | timestamp with time zone | NOT NULL |  |
| `operator_id` | integer |  |  |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mes_work_orders`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mes_work_orders_id_seq'::reg... |
| `order_number` | character varying(255) |  |  |
| `product_id` | integer | NOT NULL |  |
| `planned_quantity` | numeric | NOT NULL |  |
| `planned_date` | timestamp with time zone |  |  |
| `due_date` | timestamp with time zone |  |  |
| `start_date` | timestamp with time zone |  |  |
| `completed_date` | timestamp with time zone |  |  |
| `assigned_user_id` | integer |  |  |
| `status` | USER-DEFINED |  | 'PLANNED'::enum_mes_work_orders_status |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mobile_sessions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | uuid | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `device_fingerprint` | text | NOT NULL |  |
| `fcm_token` | text |  |  |
| `scope_mode` | text | NOT NULL |  |
| `scope_branch_ids` | ARRAY |  |  |
| `scope_store_ids` | ARRAY |  |  |
| `active_session_token` | uuid | NOT NULL |  |
| `last_seen_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `module_aliases`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('module_aliases_id_seq'::regc... |
| `module` | character varying(255) |  |  |
| `alias` | character varying(255) |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `modules`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('modules_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `icon` | character varying(255) |  |  |
| `url` | character varying(255) |  |  |
| `is_main` | boolean |  |  |
| `app_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `is_auxiliary` | boolean |  | false |

## `movements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('movements_id_seq'::regclass) |
| `user_id` | integer | NOT NULL |  |
| `type` | USER-DEFINED | NOT NULL |  |
| `amount` | integer | NOT NULL |  |
| `description` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `box_id` | integer |  |  |

## `mp_accounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_accounts_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `mp_user_id` | character varying(64) | NOT NULL |  |
| `access_token` | text | NOT NULL |  |
| `refresh_token` | text | NOT NULL |  |
| `public_key` | character varying(255) |  |  |
| `environment` | character varying(16) | NOT NULL | 'sandbox'::character varying |
| `external_pos_id` | character varying(60) |  |  |
| `expires_at` | timestamp with time zone |  |  |
| `connected_at` | timestamp with time zone | NOT NULL |  |
| `disconnected_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mp_movements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_movements_id_seq'::regclass) |
| `mp_wallet_id` | integer | NOT NULL |  |
| `type` | character varying(16) | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `sale_id` | integer |  |  |
| `refund_id` | integer |  |  |
| `mp_payment_id` | character varying(32) |  |  |
| `transfer_id` | integer |  |  |
| `note` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |

## `mp_payment_intents`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_payment_intents_id_seq'::... |
| `mp_account_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `terminal_id` | integer | NOT NULL |  |
| `pending_venta_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `mp_order_id` | character varying(64) |  |  |
| `qr_data` | text |  |  |
| `payment_id` | character varying(32) |  |  |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `expires_at` | timestamp with time zone | NOT NULL |  |
| `approved_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mp_refund_attempts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_refund_attempts_id_seq'::... |
| `sale_id` | integer | NOT NULL |  |
| `mp_payment_id` | character varying(32) | NOT NULL |  |
| `attempt_no` | integer | NOT NULL |  |
| `status` | character varying(16) | NOT NULL | 'pending'::character varying |
| `error_message` | character varying(500) |  |  |
| `attempted_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mp_refunds`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_refunds_id_seq'::regclass) |
| `sale_id` | integer | NOT NULL |  |
| `mp_payment_id` | character varying(32) | NOT NULL |  |
| `refund_id` | character varying(32) | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `status` | character varying(32) | NOT NULL | 'approved'::character varying |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mp_transfers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_transfers_id_seq'::regclass) |
| `mp_wallet_id` | integer | NOT NULL |  |
| `target_box_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `note` | character varying(255) |  |  |
| `transferred_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `mp_wallets`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_wallets_id_seq'::regclass) |
| `mp_account_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `balance` | numeric | NOT NULL | 0 |
| `currency` | character(3) | NOT NULL | 'ARS'::bpchar |
| `last_synced_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `nations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('nations_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `offline_sync_ops`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('offline_sync_ops_id_seq'::re... |
| `op_uuid` | character varying(64) | NOT NULL |  |
| `agent_id` | integer |  |  |
| `branch_id` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `op_type` | character varying(40) | NOT NULL |  |
| `payload` | jsonb | NOT NULL | '{}'::jsonb |
| `status` | character varying(20) | NOT NULL | 'received'::character varying |
| `result_id` | bigint |  |  |
| `error` | text |  |  |
| `original_at` | timestamp with time zone |  |  |
| `offline_number` | character varying(40) |  |  |
| `received_at` | timestamp with time zone | NOT NULL | now() |
| `processed_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `online_order_items`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('online_order_items_id_seq'::... |
| `online_order_id` | bigint | NOT NULL |  |
| `product_id` | integer |  |  |
| `variant_id` | integer |  |  |
| `sku` | character varying(80) |  |  |
| `product_name` | character varying(200) | NOT NULL |  |
| `size` | character varying(40) |  |  |
| `color` | character varying(40) |  |  |
| `quantity` | integer | NOT NULL |  |
| `unit_price` | numeric | NOT NULL |  |
| `total_price` | numeric | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `online_orders`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('online_orders_id_seq'::regcl... |
| `store_id` | integer | NOT NULL |  |
| `order_number` | integer | NOT NULL |  |
| `channel` | character varying(20) | NOT NULL |  |
| `client_id` | integer |  |  |
| `client_name` | character varying(160) |  |  |
| `client_phone` | character varying(40) |  |  |
| `client_email` | character varying(160) |  |  |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `subtotal` | numeric | NOT NULL | 0 |
| `shipping_cost` | numeric | NOT NULL | 0 |
| `discount` | numeric | NOT NULL | 0 |
| `total` | numeric | NOT NULL | 0 |
| `payment_method` | character varying(40) |  |  |
| `payment_status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `payment_reference` | character varying(120) |  |  |
| `shipping_carrier` | character varying(60) |  |  |
| `tracking_code` | character varying(80) |  |  |
| `shipping_label_url` | text |  |  |
| `external_order_id` | character varying(120) |  |  |
| `notes` | text |  |  |
| `metadata` | jsonb | NOT NULL | '{}'::jsonb |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `confirmed_at` | timestamp with time zone |  |  |
| `shipped_at` | timestamp with time zone |  |  |
| `delivered_at` | timestamp with time zone |  |  |
| `cancelled_at` | timestamp with time zone |  |  |
| `branch_id` | integer |  |  |
| `payment_method_id` | integer |  |  |
| `mirror_sale_id` | integer |  |  |
| `stock_held_at` | timestamp with time zone |  |  |
| `stock_released_at` | timestamp with time zone |  |  |
| `external_order_number` | character varying(60) |  |  |
| `fulfillment_branch_id` | integer |  |  |
| `prepared_at` | timestamp with time zone |  |  |
| `dispatched_at` | timestamp with time zone |  |  |
| `transporte_id` | integer |  |  |

## `online_returns`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('online_returns_id_seq'::regc... |
| `online_order_id` | bigint | NOT NULL |  |
| `reason` | character varying(40) | NOT NULL |  |
| `reason_detail` | text |  |  |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `refund_amount` | numeric | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `resolved_at` | timestamp with time zone |  |  |

## `origins`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('origins_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `payment_methods`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('payment_methods_id_seq'::reg... |
| `title` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `is_active` | boolean |  | true |
| `type` | USER-DEFINED |  | 'minorista'::enum_payment_methods_type |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `adjust_percent` | numeric |  |  |

## `payment_methods_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('payment_methods_discounts_id... |
| `payment_method_id` | integer |  |  |
| `discount_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `payment_methods_options`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('payment_methods_options_id_s... |
| `payment_method_id` | integer |  |  |
| `title` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `is_active` | boolean |  | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `adjust_percent` | numeric |  |  |

## `pending_registrations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('pending_registrations_id_seq... |
| `token` | uuid | NOT NULL | gen_random_uuid() |
| `company_name` | character varying(255) | NOT NULL |  |
| `alias_name` | character varying(255) |  |  |
| `company_cuit` | character varying(20) | NOT NULL |  |
| `company_address` | character varying(255) | NOT NULL |  |
| `name` | character varying(255) | NOT NULL |  |
| `last_name` | character varying(255) | NOT NULL |  |
| `username` | character varying(255) |  |  |
| `email` | character varying(255) | NOT NULL |  |
| `phone` | character varying(32) | NOT NULL |  |
| `password_hash` | character varying(255) | NOT NULL |  |
| `email_verified_at` | timestamp with time zone |  |  |
| `phone_verified_at` | timestamp with time zone |  |  |
| `dni_front_key` | character varying(255) |  |  |
| `dni_back_key` | character varying(255) |  |  |
| `status` | character varying(24) | NOT NULL | 'contact_pending'::character varying |
| `reject_reason` | character varying(500) |  |  |
| `reviewed_by` | integer |  |  |
| `reviewed_at` | timestamp with time zone |  |  |
| `telegram_notified_at` | timestamp with time zone |  |  |
| `created_store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `expires_at` | timestamp with time zone | NOT NULL | (now() + '24:00:00'::interval) |
| `referred_by_apodo` | character varying(255) |  |  |
| `referrer_store_id` | integer |  |  |

## `permissions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('permissions_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `price_types`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('price_types_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `rounding_enabled` | boolean |  | false |
| `precision` | character varying(255) |  |  |
| `rounding_type` | character varying(255) |  |  |
| `increase_type` | character varying(255) |  | 'percentage'::character varying |
| `increase_value` | numeric |  | 0 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer |  |  |
| `status` | integer |  | 1 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `prices`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('prices_id_seq'::regclass) |
| `product_id` | integer |  |  |
| `price_type_id` | integer |  |  |
| `amount` | integer |  |  |
| `currency` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `product_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `product_id` | integer | NOT NULL |  |
| `category_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `product_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `product_id` | integer | NOT NULL |  |
| `discount_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `product_promotions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('product_promotions_id_seq'::... |
| `store_id` | integer | NOT NULL |  |
| `product_id` | integer | NOT NULL |  |
| `type` | character varying(20) | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |
| `min_qty` | integer |  |  |
| `bonus_qty` | integer |  |  |
| `threshold_qty` | integer |  |  |
| `target_price_type_id` | integer |  |  |
| `starts_at` | timestamp with time zone |  |  |
| `ends_at` | timestamp with time zone |  |  |
| `label` | character varying(120) |  |  |
| `priority` | integer | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `deleted_at` | timestamp with time zone |  |  |

## `product_subcategories`

| Column | Type | Null | Default |
|---|---|---|---|
| `product_id` | integer | NOT NULL |  |
| `subcategory_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `product_sync`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('product_sync_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `channel_id` | integer | NOT NULL |  |
| `platform` | character varying(20) | NOT NULL | 'woocommerce'::character varying |
| `branch_id` | integer | NOT NULL |  |
| `product_id` | integer | NOT NULL |  |
| `sku` | character varying(120) | NOT NULL |  |
| `sync_enabled` | boolean | NOT NULL | true |
| `price_mode` | character varying(20) | NOT NULL | 'normal'::character varying |
| `external_product_id` | character varying(120) |  |  |
| `last_synced_stock` | integer |  |  |
| `last_synced_at` | timestamp with time zone |  |  |
| `legacy_wp_sync_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `product_variants`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('product_variants_id_seq'::re... |
| `product_id` | integer |  |  |
| `variant_value_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `product_visibility`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('product_visibility_id_seq'::... |
| `product_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `is_visible` | boolean |  | true |
| `marketplace_price` | numeric |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `products`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('products_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `sku` | character varying(255) |  |  |
| `price` | numeric | NOT NULL |  |
| `stock` | integer |  |  |
| `image_url` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `is_parent` | boolean |  | false |
| `category_id` | integer |  |  |
| `color_id` | integer |  |  |
| `size_id` | integer |  |  |
| `season_id` | integer |  |  |
| `origin_id` | integer |  |  |
| `supplier_id` | integer |  |  |
| `parent_id` | integer |  |  |
| `price_orig` | numeric |  |  |
| `status` | USER-DEFINED | NOT NULL | 'active'::enum_products_status |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `is_generic` | boolean |  | false |
| `allow_revendedor` | boolean |  | false |
| `publish_marketplace` | boolean |  | false |
| `store_id` | integer | NOT NULL |  |
| `image_urls` | jsonb |  |  |
| `slug` | character varying(180) |  |  |
| `long_description` | text |  |  |
| `gender` | character varying(20) |  |  |
| `material` | character varying(120) |  |  |
| `is_published_shop` | boolean | NOT NULL | false |
| `seo_title` | character varying(160) |  |  |
| `seo_description` | character varying(320) |  |  |
| `routing_template` | jsonb |  |  |
| `serial` | smallint |  |  |
| `str_prefix` | character varying(16) |  |  |

## `provinces`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('provinces_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `nation_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `lat` | numeric |  |  |
| `lng` | numeric |  |  |

## `qr_print_log`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('qr_print_log_id_seq'::regclass) |
| `branch_id` | integer | NOT NULL |  |
| `product_id` | integer | NOT NULL |  |
| `price_type_id` | integer | NOT NULL |  |
| `printed_price` | numeric | NOT NULL |  |
| `printed_name` | text | NOT NULL |  |
| `printed_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `recharges`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('recharges_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `recharge_type` | character varying(255) |  |  |
| `recharge_value` | numeric |  |  |
| `start_date` | timestamp with time zone |  |  |
| `end_date` | timestamp with time zone |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |

## `referral_credits`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('referral_credits_id_seq'::re... |
| `referrer_store_id` | integer | NOT NULL |  |
| `referred_store_id` | integer | NOT NULL |  |
| `pending_registration_id` | bigint |  |  |
| `percent` | numeric | NOT NULL | 50 |
| `amount` | numeric | NOT NULL |  |
| `applies_ym` | character varying(7) |  |  |
| `status` | character varying(20) | NOT NULL | 'applied'::character varying |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `repartidores`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('repartidores_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `name` | character varying(120) | NOT NULL |  |
| `phone` | character varying(40) |  |  |
| `is_active` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `reseller_store_qr_auth`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('reseller_store_qr_auth_id_se... |
| `reseller_user_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `authorized_at` | timestamp with time zone | NOT NULL |  |
| `revoked_at` | timestamp with time zone |  |  |
| `revoked_by` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `restaurant_deliveries`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('restaurant_deliveries_id_seq... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `sale_id` | integer | NOT NULL |  |
| `status` | character varying(20) | NOT NULL | 'nuevo'::character varying |
| `tipo` | character varying(16) | NOT NULL | 'delivery'::character varying |
| `canal` | character varying(16) | NOT NULL | 'whatsapp'::character varying |
| `client_id` | integer |  |  |
| `customer_name` | character varying(120) |  |  |
| `customer_phone` | character varying(40) |  |  |
| `address` | text |  |  |
| `payment_mode` | character varying(16) | NOT NULL | 'efectivo'::character varying |
| `repartidor_id` | integer |  |  |
| `ordered_at` | timestamp with time zone |  |  |
| `ready_at` | timestamp with time zone |  |  |
| `dispatched_at` | timestamp with time zone |  |  |
| `delivered_at` | timestamp with time zone |  |  |
| `settled_at` | timestamp with time zone |  |  |
| `external_ref` | character varying(120) |  |  |
| `metadata` | jsonb |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `restaurant_elements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('restaurant_elements_id_seq':... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `type` | character varying(20) | NOT NULL | 'pared'::character varying |
| `pos_x` | real | NOT NULL | 0 |
| `pos_y` | real | NOT NULL | 0 |
| `width` | real | NOT NULL | 0.15 |
| `height` | real | NOT NULL | 0.04 |
| `rotation` | real | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `restaurant_tables`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('restaurant_tables_id_seq'::r... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `name` | character varying(64) | NOT NULL |  |
| `shape` | character varying(20) | NOT NULL | 'square'::character varying |
| `seats` | integer | NOT NULL | 4 |
| `pos_x` | real | NOT NULL | 0 |
| `pos_y` | real | NOT NULL | 0 |
| `zone` | character varying(64) |  |  |
| `status` | character varying(20) | NOT NULL | 'libre'::character varying |
| `current_sale_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `rotation` | real | NOT NULL | 0 |
| `size` | real | NOT NULL | 1 |

## `revendedor_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('revendedor_categories_id_seq... |
| `revendedor_id` | integer | NOT NULL |  |
| `global_category_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `revendedores`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('revendedores_id_seq'::regclass) |
| `document` | character varying(50) | NOT NULL |  |
| `name` | character varying(255) | NOT NULL |  |
| `email` | character varying(255) |  |  |
| `phone` | character varying(100) |  |  |
| `password` | character varying(255) | NOT NULL |  |
| `address` | text |  |  |
| `is_active` | boolean |  | true |
| `last_login_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `rider_settlement_items`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('rider_settlement_items_id_se... |
| `settlement_id` | integer | NOT NULL |  |
| `restaurant_delivery_id` | integer | NOT NULL |  |
| `amount` | double precision | NOT NULL | 0 |
| `rendido` | boolean | NOT NULL | false |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `rider_settlements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('rider_settlements_id_seq'::r... |
| `store_id` | integer | NOT NULL |  |
| `repartidor_id` | integer | NOT NULL |  |
| `box_session_id` | integer |  |  |
| `expected_cash` | double precision | NOT NULL | 0 |
| `received_cash` | double precision | NOT NULL | 0 |
| `difference` | double precision | NOT NULL | 0 |
| `status` | character varying(16) | NOT NULL | 'open'::character varying |
| `note` | text |  |  |
| `opened_at` | timestamp with time zone |  |  |
| `closed_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `role_function_actions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('role_function_actions_id_seq... |
| `role_function_id` | integer |  |  |
| `action` | character varying(20) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `role_function_actions_bak_20260728`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer |  |  |
| `role_function_id` | integer |  |  |
| `action` | character varying(20) |  |  |
| `created_at` | timestamp with time zone |  |  |
| `updated_at` | timestamp with time zone |  |  |

## `role_function_actions_bak_20260728_orig`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer |  |  |
| `role_function_id` | integer |  |  |
| `action` | character varying(20) |  |  |
| `created_at` | timestamp with time zone |  |  |
| `updated_at` | timestamp with time zone |  |  |

## `role_functions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('role_functions_id_seq'::regc... |
| `role_id` | integer |  |  |
| `function_id` | integer |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `branch_id` | integer |  |  |

## `role_functions_bak_20260728`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer |  |  |
| `role_id` | integer |  |  |
| `function_id` | integer |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone |  |  |
| `updated_at` | timestamp with time zone |  |  |
| `branch_id` | integer |  |  |

## `role_functions_bak_20260728_orig`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer |  |  |
| `role_id` | integer |  |  |
| `function_id` | integer |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone |  |  |
| `updated_at` | timestamp with time zone |  |  |
| `branch_id` | integer |  |  |

## `role_permission_functions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('role_permission_functions_id... |
| `role_id` | integer |  |  |
| `permission_id` | integer |  |  |
| `function_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `role_permissions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('role_permissions_id_seq'::re... |
| `role_id` | integer |  |  |
| `permission_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `roles`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('roles_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `slug` | character varying(255) |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sale_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sale_discounts_id_seq'::regc... |
| `sale_id` | integer |  |  |
| `name` | character varying(255) |  |  |
| `amount_discount` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sale_idempotency_keys`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sale_idempotency_keys_id_seq... |
| `store_id` | integer | NOT NULL |  |
| `idempotency_key` | character varying(120) | NOT NULL |  |
| `request_hash` | character(64) | NOT NULL |  |
| `status` | character varying(20) | NOT NULL | 'processing'::character varying |
| `sale_id` | integer |  |  |
| `response_body` | jsonb |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `completed_at` | timestamp with time zone |  |  |
| `expires_at` | timestamp with time zone | NOT NULL | (now() + '24:00:00'::interval) |

## `sale_items`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sale_items_id_seq'::regclass) |
| `sale_id` | integer |  |  |
| `product_id` | integer |  |  |
| `quantity` | integer |  |  |
| `price` | numeric | NOT NULL |  |
| `subtotal` | numeric | NOT NULL |  |
| `discount_amount` | numeric | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `custom_name` | character varying(255) |  |  |
| `is_promo_free` | boolean | NOT NULL | false |
| `promotion_id` | integer |  |  |
| `promo_group_id` | uuid |  |  |

## `sale_payment_methods`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sale_payment_methods_id_seq'... |
| `sale_id` | integer |  |  |
| `payment_method_id` | integer |  |  |
| `option_id` | integer |  |  |
| `amount` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sale_recharges`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sale_recharges_id_seq'::regc... |
| `sale_id` | integer |  |  |
| `name` | character varying(255) |  |  |
| `amount_recharge` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sale_senias`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('sale_senias_id_seq'::regclass) |
| `sale_id` | integer | NOT NULL |  |
| `store_client_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `amount_received` | numeric | NOT NULL | 0 |
| `amount_applied` | numeric | NOT NULL | 0 |
| `status` | character varying(20) | NOT NULL | 'active'::character varying |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `sales`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sales_id_seq'::regclass) |
| `client_id` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer |  |  |
| `seller_id` | integer |  |  |
| `sale_date` | timestamp with time zone |  |  |
| `subtotal` | integer |  |  |
| `discount_amount` | integer |  |  |
| `total_amount` | integer |  |  |
| `status` | character varying(255) |  |  |
| `notes` | character varying(255) |  |  |
| `discount` | integer |  |  |
| `transport` | integer |  |  |
| `taxes` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `daily_number` | integer |  | 0 |
| `nullified_sale_id` | integer |  |  |
| `nullified_by_sale_id` | integer |  |  |
| `province_id` | integer |  |  |
| `store_client_id` | integer |  |  |
| `terminal_id` | integer |  |  |
| `print_count` | integer | NOT NULL | 0 |
| `source` | character varying(20) | NOT NULL | 'pos'::character varying |
| `online_order_id` | bigint |  |  |
| `activity_type` | character varying(16) | NOT NULL | 'sale'::character varying |
| `origin_branch_id` | integer |  |  |
| `target_branch_id` | integer |  |  |
| `num_pedido` | character varying(64) |  |  |
| `table_id` | integer |  |  |
| `ordered_at` | timestamp with time zone |  |  |
| `served_at` | timestamp with time zone |  |  |
| `closed_at` | timestamp with time zone |  |  |
| `last_comanda_at` | timestamp with time zone |  |  |
| `cae` | character varying(20) |  |  |
| `cae_vto` | date |  |  |
| `punto_venta` | integer |  |  |
| `afip_number` | integer |  |  |
| `tipo_comprobante` | integer |  |  |
| `afip_status` | character varying(15) | NOT NULL | 'no'::character varying |
| `sale_day_local` | date |  |  |

## `seasons`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('seasons_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `seller_adelantos`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('seller_adelantos_id_seq'::re... |
| `seller_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer |  |  |
| `amount` | numeric | NOT NULL |  |
| `status` | character varying(12) | NOT NULL | 'pending'::character varying |
| `note` | text |  |  |
| `requested_by_user_id` | integer |  |  |
| `requested_at` | timestamp with time zone | NOT NULL | now() |
| `decided_by_user_id` | integer |  |  |
| `decided_at` | timestamp with time zone |  |  |
| `decision_note` | text |  |  |
| `payroll_period` | character varying(7) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `seller_attendance`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('seller_attendance_id_seq'::r... |
| `seller_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `user_id` | integer |  |  |
| `check_in_at` | timestamp with time zone | NOT NULL |  |
| `check_out_at` | timestamp with time zone |  |  |
| `source` | character varying(16) | NOT NULL | 'qr'::character varying |
| `adjusted_by` | integer |  |  |
| `adjusted_at` | timestamp with time zone |  |  |
| `note` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `shared_folder_access_logs`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('shared_folder_access_logs_id... |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `shared_folder_id` | integer | NOT NULL |  |
| `action` | character varying(20) | NOT NULL |  |
| `google_file_id` | character varying(128) |  |  |
| `file_name` | character varying(500) |  |  |
| `bytes` | bigint |  |  |
| `ip_address` | inet |  |  |
| `user_agent` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `shared_folder_role_access`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('shared_folder_role_access_id... |
| `shared_folder_id` | integer | NOT NULL |  |
| `role_id` | integer | NOT NULL |  |
| `can_read` | boolean | NOT NULL | true |
| `can_write` | boolean | NOT NULL | false |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `shared_folders`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('shared_folders_id_seq'::regc... |
| `store_id` | integer | NOT NULL |  |
| `google_folder_id` | character varying(128) | NOT NULL |  |
| `is_shared_drive` | boolean | NOT NULL | false |
| `shared_drive_id` | character varying(128) |  |  |
| `name` | character varying(255) | NOT NULL |  |
| `description` | text |  |  |
| `sort_order` | integer | NOT NULL | 0 |
| `is_active` | boolean | NOT NULL | true |
| `user_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sizes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sizes_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sku_serials`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('sku_serials_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `sku_prefix` | character varying(16) | NOT NULL |  |
| `supplier_id` | integer | NOT NULL | 0 |
| `category_id` | integer | NOT NULL | 0 |
| `subcategory_id` | integer | NOT NULL | 0 |
| `last_serial` | smallint | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `slow_query_log`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('slow_query_log_id_seq'::regc... |
| `qid` | bigint | NOT NULL |  |
| `duration_ms` | integer | NOT NULL |  |
| `query_type` | character varying(10) | NOT NULL |  |
| `table_name` | character varying(64) |  |  |
| `sql` | text | NOT NULL |  |
| `instance` | character varying(40) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `stock_balances`

| Column | Type | Null | Default |
|---|---|---|---|
| `product_branch_id` | integer | NOT NULL |  |
| `store_id` | integer |  |  |
| `branch_id` | integer |  |  |
| `product_id` | integer |  |  |
| `parent_id` | integer |  |  |
| `total_ingreso` | integer | NOT NULL | 0 |
| `total_anulado` | integer | NOT NULL | 0 |
| `total_ajuste` | integer | NOT NULL | 0 |
| `total_venta` | integer | NOT NULL | 0 |
| `total_transfer` | integer | NOT NULL | 0 |
| `reservado` | integer | NOT NULL | 0 |
| `on_hand` | integer | NOT NULL | 0 |
| `available` | integer | NOT NULL | 0 |
| `fecha_primer_ingreso` | date |  |  |
| `fecha_ultimo_ingreso` | date |  |  |
| `fecha_ultima_venta` | date |  |  |
| `movimientos` | integer | NOT NULL | 0 |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `stock_cache_backfill_20260729`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer |  |  |
| `stock` | integer |  |  |
| `captured_at` | timestamp with time zone |  |  |

## `stocks`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('stocks_id_seq'::regclass) |
| `stock` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `product_branch_id` | integer | NOT NULL |  |
| `type` | character varying(20) |  | NULL::character varying |
| `note` | text |  |  |
| `is_active` | boolean | NOT NULL | true |
| `operation_date` | date | NOT NULL | CURRENT_DATE |
| `backfill_processed_sale_id` | integer |  |  |
| `store_id` | integer |  |  |
| `branch_id` | integer |  |  |

## `store_apps`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_apps_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `app_id` | integer | NOT NULL |  |
| `enabled` | boolean |  | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `trial_ends_at` | date |  |  |
| `billing_status` | character varying(255) |  | 'inactive'::character varying |

## `store_billing_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_billing_discounts_id_s... |
| `store_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL | 0 |
| `kind` | character varying | NOT NULL |  |
| `applies_ym` | character varying |  |  |
| `active` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `created_by` | integer |  |  |
| `source` | character varying(20) | NOT NULL | 'manual'::character varying |
| `referral_credit_id` | integer |  |  |

## `store_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_categories_id_seq'::re... |
| `global_category_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `is_enabled` | boolean |  | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `store_clients`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_clients_id_seq'::regcl... |
| `global_client_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `is_active` | boolean |  | true |
| `note` | text |  |  |
| `credit_limit` | numeric |  | 0 |
| `balance` | numeric |  | 0 |
| `internal_code` | character varying(50) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `senia_balance` | numeric | NOT NULL | 0 |
| `favor_balance` | numeric | NOT NULL | 0 |
| `credit_term_days` | integer | NOT NULL | 30 |
| `credit_status` | character varying(20) | NOT NULL | 'active'::character varying |
| `last_payment_at` | timestamp with time zone |  |  |

## `store_configs`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_configs_id_seq'::regcl... |
| `store_id` | integer | NOT NULL |  |
| `use_supplier` | boolean |  | true |
| `use_season` | boolean |  | true |
| `use_origin` | boolean |  | true |
| `use_size` | boolean |  | true |
| `use_color` | boolean |  | true |
| `use_subcategory` | boolean |  | true |
| `use_category` | boolean |  | true |
| `category_digits` | integer |  | 3 |
| `subcategory_digits` | integer |  | 3 |
| `origin_digits` | integer |  | 3 |
| `supplier_digits` | integer |  | 3 |
| `season_digits` | integer |  | 3 |
| `color_digits` | integer |  | 3 |
| `size_digits` | integer |  | 3 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `currency` | character varying(3) | NOT NULL | 'ARS'::character varying |
| `use_restaurant_mode` | boolean | NOT NULL | false |
| `allow_sale_without_stock` | boolean | NOT NULL | true |
| `use_envios` | boolean | NOT NULL | false |
| `use_factura_electronica` | boolean | NOT NULL | false |
| `afip_provider` | character varying(5) | NOT NULL | 'ws'::character varying |
| `afip_production` | boolean | NOT NULL | false |
| `afip_auto_issue` | boolean | NOT NULL | false |
| `afip_default_pct` | numeric | NOT NULL | 100 |
| `vto_enabled` | boolean | NOT NULL | true |
| `email_from` | character varying(160) |  |  |
| `email_api_url` | character varying(255) |  |  |
| `email_api_key_enc` | text |  |  |
| `unpaid_hold_alert_days` | integer | NOT NULL | 30 |

## `store_error_log`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('store_error_log_id_seq'::reg... |
| `store_id` | integer |  |  |
| `user_id` | integer |  |  |
| `method` | character varying(10) |  |  |
| `path` | text |  |  |
| `status_code` | integer | NOT NULL |  |
| `message` | text |  |  |
| `ip` | character varying(64) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `store_integrations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_integrations_id_seq'::... |
| `integration` | character varying(255) |  |  |
| `store_id` | integer | NOT NULL |  |
| `status` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `store_notices`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('store_notices_id_seq'::regcl... |
| `store_id` | integer | NOT NULL |  |
| `campaign_id` | uuid | NOT NULL |  |
| `level` | character varying(16) | NOT NULL | 'info'::character varying |
| `title` | character varying(200) | NOT NULL |  |
| `body` | text | NOT NULL |  |
| `created_by` | integer |  |  |
| `read_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `store_subcategories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_subcategories_id_seq':... |
| `global_subcategory_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `is_enabled` | boolean |  | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `store_themes`

| Column | Type | Null | Default |
|---|---|---|---|
| `store_id` | integer | NOT NULL |  |
| `base_theme` | character varying(40) | NOT NULL | 'Studio'::character varying |
| `macrostructure` | character varying(40) | NOT NULL | 'marquee'::character varying |
| `published_tokens` | jsonb | NOT NULL | '{}'::jsonb |
| `draft_tokens` | jsonb |  |  |
| `published_at` | timestamp with time zone |  |  |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `enabled` | boolean | NOT NULL | false |

## `store_whatsapp_config`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('store_whatsapp_config_id_seq... |
| `store_id` | integer | NOT NULL |  |
| `waba_id` | character varying(40) |  |  |
| `phone_number_id` | character varying(40) |  |  |
| `display_phone` | character varying(30) |  |  |
| `access_token` | text |  |  |
| `quality_rating` | character varying(20) |  |  |
| `is_active` | boolean | NOT NULL | false |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `stores`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('stores_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `alias_name` | character varying(255) |  |  |
| `cuit` | bigint |  |  |
| `address` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `status` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `integration` | character varying(255) |  |  |
| `type_of_payer` | character varying(255) |  |  |
| `start_activities_date` | timestamp with time zone |  |  |
| `income_number` | bigint |  |  |
| `timezone` | character varying(255) |  | 'America/Bogota'::character varying |
| `logo_url` | character varying(255) |  |  |
| `use_variants` | boolean | NOT NULL | true |
| `owner_group_id` | integer | NOT NULL |  |
| `senia_ui_mode` | character varying(20) | NOT NULL | 'separated'::character varying |
| `representative_user_id` | integer |  |  |
| `slug` | character varying(63) |  |  |
| `slug_canonical` | text |  |  |
| `deleted_at` | timestamp with time zone |  |  |
| `telegram_chat_id` | character varying(64) |  |  |

## `style_cost_sheets`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('style_cost_sheets_id_seq'::r... |
| `product_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `currency` | character varying(3) | NOT NULL | 'USD'::character varying |
| `retail_price` | numeric |  |  |
| `target_margin_pct` | numeric | NOT NULL | 50 |
| `overhead_pct` | numeric | NOT NULL | 11.3 |
| `shipping_cost_per_lote` | numeric | NOT NULL | 200 |
| `lote_size_default` | integer | NOT NULL | 155 |
| `material_cost` | numeric |  |  |
| `cmt_cost` | numeric |  |  |
| `overhead_cost` | numeric |  |  |
| `total_cost` | numeric |  |  |
| `margin_amount` | numeric |  |  |
| `margin_pct` | numeric |  |  |
| `calc_snapshot` | jsonb |  |  |
| `last_calculated_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `subcategories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('subcategories_id_seq'::regcl... |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 0 |
| `category_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `subcategory_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('subcategory_discounts_id_seq... |
| `subcategory_id` | integer |  |  |
| `discount_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `subscription_config`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('subscription_config_id_seq':... |
| `enabled` | boolean |  | false |
| `base_plan_price` | numeric |  | 60000 |
| `extra_branch_price` | numeric |  | 40000 |
| `extra_terminal_price` | numeric |  | 20000 |
| `currency` | character varying(255) |  | 'ARS'::character varying |
| `trial_days` | integer |  | 30 |
| `grace_period_days` | integer |  | 3 |
| `payment_gateway` | character varying(255) |  | 'manual'::character varying |
| `mp_access_token` | character varying(255) |  |  |
| `mp_public_key` | character varying(255) |  |  |
| `stripe_secret_key` | character varying(255) |  |  |
| `stripe_public_key` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `integration_wordpress_price` | numeric |  | 50000 |
| `integration_mercadolibre_price` | numeric |  | 50000 |
| `integration_tienda_nube_price` | numeric |  | 50000 |
| `integration_signo_price` | numeric |  | 70000 |
| `integration_factura_electronica_price` | numeric |  | 30000 |
| `integration_zebra_price` | numeric |  | 10000 |
| `app_talleres_price` | numeric | NOT NULL | 50000 |
| `app_materia_prima_price` | numeric | NOT NULL | 50000 |

## `suppliers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('suppliers_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer | NOT NULL |  |
| `store_entity_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `support_sessions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('support_sessions_id_seq'::re... |
| `uuid` | uuid | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `viewer_user_id` | integer |  |  |
| `status` | character varying(16) | NOT NULL | 'waiting'::character varying |
| `started_at` | timestamp with time zone |  |  |
| `ended_at` | timestamp with time zone |  |  |
| `expires_at` | timestamp with time zone | NOT NULL |  |
| `metadata` | jsonb |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `support_tokens`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('support_tokens_id_seq'::regc... |
| `token` | character varying(6) | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `generated_by` | integer | NOT NULL |  |
| `status` | character varying(255) |  | 'active'::character varying |
| `expires_at` | timestamp with time zone | NOT NULL |  |
| `used_by` | integer |  |  |
| `used_at` | timestamp with time zone |  |  |
| `is_free` | boolean |  | true |
| `charge_amount` | integer |  | 0 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `sync_outbox`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('sync_outbox_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `channel_id` | integer | NOT NULL |  |
| `platform` | character varying(20) | NOT NULL |  |
| `op_type` | character varying(30) | NOT NULL |  |
| `payload` | jsonb | NOT NULL | '{}'::jsonb |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `attempts` | integer | NOT NULL | 0 |
| `max_attempts` | integer | NOT NULL | 8 |
| `next_retry_at` | timestamp with time zone | NOT NULL | now() |
| `last_error` | text |  |  |
| `dedupe_key` | character varying(160) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |
| `processed_at` | timestamp with time zone |  |  |
| `locked_by` | character varying(80) |  |  |
| `lease_expires_at` | timestamp with time zone |  |  |

## `talleres_cut_ticket_counters`

| Column | Type | Null | Default |
|---|---|---|---|
| `store_id` | integer | NOT NULL |  |
| `year` | smallint | NOT NULL |  |
| `last_seq` | integer | NOT NULL | 0 |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `talleres_defect_codes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_defect_codes_id_seq... |
| `code` | character varying(40) | NOT NULL |  |
| `label` | character varying(200) | NOT NULL |  |
| `severity_default` | character varying(20) | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `talleres_defects`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_defects_id_seq'::re... |
| `subcon_delivery_id` | integer | NOT NULL |  |
| `defect_quantity` | numeric | NOT NULL |  |
| `defect_type` | USER-DEFINED |  | 'DEFECT'::enum_talleres_defects_defec... |
| `penalty_amount` | numeric |  |  |
| `deduction_amount` | numeric |  |  |
| `action` | USER-DEFINED |  | 'NONE'::enum_talleres_defects_action |
| `description` | text |  |  |
| `defect_date` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_deliveries`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_deliveries_id_seq':... |
| `subcon_order_id` | integer | NOT NULL |  |
| `delivered_quantity` | numeric | NOT NULL |  |
| `accepted_quantity` | numeric |  |  |
| `rejected_quantity` | numeric |  |  |
| `delivery_date` | timestamp with time zone | NOT NULL |  |
| `unit_price_applied` | boolean |  | true |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_envio_materiales`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_envio_materiales_id... |
| `envio_id` | integer | NOT NULL |  |
| `material_id` | integer | NOT NULL |  |
| `quantity` | numeric | NOT NULL |  |
| `unit` | character varying(255) |  |  |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_envios`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_envios_id_seq'::reg... |
| `lote_id` | integer | NOT NULL |  |
| `vendor_id` | integer | NOT NULL |  |
| `etapa_id` | integer | NOT NULL |  |
| `quantity` | integer | NOT NULL |  |
| `pending_quantity` | integer | NOT NULL |  |
| `envio_date` | date | NOT NULL |  |
| `due_date` | date |  |  |
| `source_recepcion_id` | integer |  |  |
| `status` | USER-DEFINED |  | 'PENDING'::enum_talleres_envios_status |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `priority` | integer | NOT NULL | 0 |
| `rework_order_id` | integer |  |  |

## `talleres_etapas`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_etapas_id_seq'::reg... |
| `name` | character varying(255) | NOT NULL |  |
| `order` | integer |  | 0 |
| `is_active` | boolean |  | true |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_lotes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_lotes_id_seq'::regc... |
| `lote_number` | character varying(255) | NOT NULL |  |
| `product_id` | integer | NOT NULL |  |
| `total_quantity` | integer | NOT NULL |  |
| `available_quantity` | integer | NOT NULL |  |
| `status` | USER-DEFINED |  | 'OPEN'::enum_talleres_lotes_status |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `cut_ticket_number` | character varying(40) |  |  |
| `style_code` | character varying(60) |  |  |
| `season` | character varying(40) |  |  |
| `cut_date` | date |  |  |
| `size_color_matrix` | jsonb |  |  |
| `bom_snapshot` | jsonb |  |  |
| `routing_path` | jsonb |  |  |
| `stocked_quantity` | numeric | NOT NULL | 0 |

## `talleres_material_issues`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_material_issues_id_... |
| `subcon_order_id` | integer | NOT NULL |  |
| `material_id` | integer |  |  |
| `product_id` | integer |  |  |
| `quantity` | numeric | NOT NULL |  |
| `unit` | character varying(255) |  |  |
| `issue_date` | timestamp with time zone | NOT NULL |  |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_orders`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_orders_id_seq'::reg... |
| `order_number` | character varying(255) |  |  |
| `vendor_id` | integer | NOT NULL |  |
| `work_order_id` | integer |  |  |
| `product_id` | integer | NOT NULL |  |
| `requested_quantity` | numeric | NOT NULL |  |
| `unit_price` | numeric | NOT NULL |  |
| `currency` | character varying(255) |  | 'USD'::character varying |
| `expected_amount` | numeric |  |  |
| `due_date` | timestamp with time zone |  |  |
| `start_date` | timestamp with time zone |  |  |
| `completed_date` | timestamp with time zone |  |  |
| `status` | USER-DEFINED |  | 'REQUESTED'::enum_talleres_orders_status |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_payments`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_payments_id_seq'::r... |
| `subcon_settlement_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `payment_date` | timestamp with time zone | NOT NULL |  |
| `payment_method_id` | integer |  |  |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_qc_items`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_qc_items_id_seq'::r... |
| `recepcion_id` | integer | NOT NULL |  |
| `defect_code_id` | integer |  |  |
| `defect_custom_text` | character varying(255) |  |  |
| `quantity` | integer | NOT NULL |  |
| `severity` | character varying(20) | NOT NULL |  |
| `action` | character varying(20) | NOT NULL |  |
| `photo_url` | character varying(500) |  |  |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `talleres_recepciones`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_recepciones_id_seq'... |
| `envio_id` | integer | NOT NULL |  |
| `received_quantity` | integer | NOT NULL |  |
| `rejected_quantity` | integer |  | 0 |
| `recepcion_date` | date | NOT NULL |  |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_rework_orders`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_rework_orders_id_se... |
| `store_id` | integer | NOT NULL |  |
| `lote_id` | integer | NOT NULL |  |
| `cut_ticket_number` | character varying(20) |  |  |
| `source_envio_id` | integer | NOT NULL |  |
| `source_recepcion_id` | integer |  |  |
| `target_etapa_id` | integer | NOT NULL |  |
| `target_vendor_id` | integer |  |  |
| `quantity` | integer | NOT NULL |  |
| `defect_code_id` | integer |  |  |
| `reason` | text |  |  |
| `status` | USER-DEFINED | NOT NULL | 'PENDING'::enum_talleres_rework_order... |
| `resulting_envio_id` | integer |  |  |
| `created_by` | integer |  |  |
| `completed_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `talleres_settlement_lines`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_settlement_lines_id... |
| `settlement_id` | integer | NOT NULL |  |
| `recepcion_id` | integer | NOT NULL |  |
| `envio_id` | integer | NOT NULL |  |
| `etapa_id` | integer | NOT NULL |  |
| `vendor_etapa_id` | integer | NOT NULL |  |
| `quantity` | integer | NOT NULL |  |
| `unit_price` | numeric | NOT NULL |  |
| `line_amount` | numeric | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `talleres_settlements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_settlements_id_seq'... |
| `subcon_order_id` | integer |  |  |
| `period_from` | timestamp with time zone |  |  |
| `period_to` | timestamp with time zone |  |  |
| `total_gross_amount` | numeric | NOT NULL |  |
| `total_penalty_amount` | numeric |  | 0 |
| `deduction_amount` | numeric |  | 0 |
| `net_amount` | numeric | NOT NULL |  |
| `settlement_date` | timestamp with time zone | NOT NULL |  |
| `status` | USER-DEFINED |  | 'OPEN'::enum_talleres_settlements_status |
| `notes` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `vendor_id` | integer |  |  |
| `confirmed_at` | timestamp with time zone |  |  |
| `confirmed_by` | integer |  |  |

## `talleres_vendor_etapas`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_vendor_etapas_id_se... |
| `vendor_id` | integer | NOT NULL |  |
| `etapa_id` | integer | NOT NULL |  |
| `unit_price` | numeric |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `effective_from` | date | NOT NULL | CURRENT_DATE |
| `effective_to` | date |  |  |

## `talleres_vendors`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_vendors_id_seq'::re... |
| `name` | character varying(255) | NOT NULL |  |
| `contact_person` | character varying(255) |  |  |
| `phone` | character varying(255) |  |  |
| `email` | character varying(255) |  |  |
| `address` | character varying(255) |  |  |
| `settlement_terms` | text |  |  |
| `rating` | numeric |  |  |
| `is_active` | boolean |  | true |
| `pin_hash` | character varying(255) |  |  |
| `pin_updated_at` | timestamp with time zone |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `cuit` | character varying(20) |  |  |

## `team_messages`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('team_messages_id_seq'::regcl... |
| `store_id` | integer | NOT NULL |  |
| `sender_id` | integer | NOT NULL |  |
| `receiver_id` | integer |  |  |
| `content` | text | NOT NULL |  |
| `read_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `terminal_devices`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('terminal_devices_id_seq'::re... |
| `device_fingerprint` | character varying(255) | NOT NULL |  |
| `public_ip` | character varying(255) |  |  |
| `terminal_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `registered_at` | timestamp with time zone | NOT NULL |  |
| `last_seen_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `device_token` | character varying(255) |  |  |

## `terminals`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('terminals_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `box_id` | integer | NOT NULL |  |
| `status` | character varying(255) |  | 'activo'::character varying |
| `is_deleted` | boolean |  | false |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `thermal_agent_id` | integer |  |  |
| `zebra_agent_id` | integer |  |  |

## `transportes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('transportes_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `name` | character varying(120) | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `user_branches`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('user_branches_id_seq'::regcl... |
| `user_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `role_id` | integer | NOT NULL |  |
| `is_default` | boolean | NOT NULL | false |
| `valid_from` | timestamp without time zone | NOT NULL | now() |
| `valid_until` | timestamp without time zone |  |  |
| `granted_by` | integer |  |  |
| `reason` | text |  |  |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `updated_at` | timestamp without time zone | NOT NULL | now() |
| `mobile_terminal_id` | integer |  |  |

## `user_function_actions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('user_function_actions_id_seq... |
| `user_function_id` | integer |  |  |
| `action` | character varying(20) |  |  |
| `allowed` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `user_functions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('user_functions_id_seq'::regc... |
| `user_id` | integer |  |  |
| `function_id` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `allowed` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `branch_id` | integer |  |  |
| `valid_from` | timestamp without time zone | NOT NULL | now() |
| `valid_until` | timestamp without time zone |  |  |
| `reason` | text |  |  |
| `granted_by` | integer |  |  |

## `user_permission_cache`

| Column | Type | Null | Default |
|---|---|---|---|
| `user_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `permissions` | jsonb | NOT NULL |  |
| `computed_at` | timestamp without time zone | NOT NULL | now() |

## `user_permission_functions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('user_permission_functions_id... |
| `user_id` | integer |  |  |
| `permission_id` | integer |  |  |
| `function_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `user_permissions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('user_permissions_id_seq'::re... |
| `user_id` | integer |  |  |
| `permission_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `user_roles`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('user_roles_id_seq'::regclass) |
| `user_id` | integer |  |  |
| `role_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `users`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('users_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `last_name` | character varying(255) |  |  |
| `username` | character varying(255) |  |  |
| `email` | character varying(255) |  |  |
| `last_login_at` | timestamp with time zone |  |  |
| `password` | character varying(255) |  |  |
| `status` | USER-DEFINED |  | 'active'::enum_users_status |
| `is_verified` | boolean |  |  |
| `trial_ends_at` | timestamp with time zone |  |  |
| `store_id` | integer |  |  |
| `branch_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `onboarding_completed` | boolean |  | false |
| `ui_mode` | character varying(255) | NOT NULL | 'classic'::character varying |
| `monthly_sales_target` | numeric |  |  |
| `whatsapp_phone` | character varying(30) |  |  |
| `mobile_pin` | text |  |  |

## `variant_types`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('variant_types_id_seq'::regcl... |
| `variant_id` | integer |  |  |
| `type` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `variants`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('variants_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `vendedor_devices`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('vendedor_devices_id_seq'::re... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `label` | character varying(120) | NOT NULL |  |
| `api_key` | character varying(80) | NOT NULL |  |
| `is_active` | boolean | NOT NULL | true |
| `last_seen_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `vendor_notifications`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('vendor_notifications_id_seq'... |
| `vendor_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `type` | USER-DEFINED | NOT NULL |  |
| `title` | character varying(255) | NOT NULL |  |
| `body` | text |  |  |
| `reference_id` | integer |  |  |
| `is_read` | boolean |  | false |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `venta_suspendida_discounts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('venta_suspendida_discounts_i... |
| `venta_suspendida_id` | integer |  |  |
| `name` | character varying(255) |  |  |
| `amount_discount` | integer |  | 0 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `venta_suspendida_items`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('venta_suspendida_items_id_se... |
| `venta_suspendida_id` | integer |  |  |
| `product_id` | integer |  |  |
| `quantity` | integer |  | 1 |
| `price` | numeric |  | 0 |
| `subtotal` | numeric |  | 0 |
| `discount_amount` | numeric |  | 0 |
| `custom_name` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `variant_quantities` | jsonb |  |  |

## `venta_suspendida_recharges`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('venta_suspendida_recharges_i... |
| `venta_suspendida_id` | integer |  |  |
| `name` | character varying(255) |  |  |
| `amount_recharge` | integer |  | 0 |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `ventas_suspendidas`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('ventas_suspendidas_id_seq'::... |
| `client_id` | integer |  |  |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer |  |  |
| `seller_id` | integer |  |  |
| `sale_date` | timestamp with time zone |  |  |
| `subtotal` | integer |  | 0 |
| `discount` | integer |  | 0 |
| `discount_amount` | integer |  | 0 |
| `transport` | integer |  | 0 |
| `taxes` | integer |  | 0 |
| `total_amount` | integer |  | 0 |
| `notes` | character varying(255) |  |  |
| `num_pedido` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `branch_id` | integer |  |  |
| `province_id` | integer |  |  |
| `source` | character varying(10) | NOT NULL | 'pos'::character varying |

## `verification_codes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('verification_codes_id_seq'::... |
| `subject` | uuid | NOT NULL |  |
| `channel` | character varying(16) | NOT NULL |  |
| `code_hash` | character varying(64) | NOT NULL |  |
| `attempts` | smallint | NOT NULL | 0 |
| `last_sent_at` | timestamp with time zone | NOT NULL | now() |
| `expires_at` | timestamp with time zone | NOT NULL |  |
| `consumed_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `vto_generations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('vto_generations_id_seq'::reg... |
| `store_id` | integer | NOT NULL |  |
| `user_id` | integer |  |  |
| `device_fingerprint` | character varying(128) |  |  |
| `product_id` | integer |  |  |
| `status` | character varying(16) | NOT NULL | 'success'::character varying |
| `provider` | character varying(32) | NOT NULL | 'fashn'::character varying |
| `provider_request_id` | character varying(64) |  |  |
| `latency_ms` | integer |  |  |
| `error_code` | character varying(64) |  |  |
| `error_message` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

## `vto_settings`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | smallint | NOT NULL |  |
| `price` | numeric | NOT NULL | 200 |
| `currency` | character varying(8) | NOT NULL | 'ARS'::character varying |
| `updated_by` | integer |  |  |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `whatsapp_messages`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('whatsapp_messages_id_seq'::r... |
| `store_id` | integer | NOT NULL |  |
| `client_id` | integer |  |  |
| `phone` | character varying(30) | NOT NULL |  |
| `template_key` | character varying(60) |  |  |
| `body` | text | NOT NULL |  |
| `provider` | character varying(20) | NOT NULL | 'click_to_chat'::character varying |
| `status` | character varying(20) | NOT NULL |  |
| `sent_by_user_id` | integer |  |  |
| `representative_user_id` | integer |  |  |
| `link_url` | text |  |  |
| `error_message` | text |  |  |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `updated_at` | timestamp without time zone | NOT NULL | now() |

## `whatsapp_templates`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | bigint | NOT NULL | nextval('whatsapp_templates_id_seq'::... |
| `store_id` | integer |  |  |
| `name` | character varying(120) | NOT NULL |  |
| `category` | character varying(20) | NOT NULL | 'MARKETING'::character varying |
| `language` | character varying(10) | NOT NULL | 'es_AR'::character varying |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `body` | text |  |  |
| `header_type` | character varying(20) |  |  |
| `meta_template_id` | character varying(60) |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `wp_channels`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('wp_channels_id_seq'::regclass) |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `stock_source_branch_id` | integer | NOT NULL |  |
| `channel_key` | character varying(64) | NOT NULL |  |
| `secret` | character varying(128) | NOT NULL |  |
| `site_url` | character varying(255) |  |  |
| `wc_consumer_key` | character varying(255) |  |  |
| `wc_consumer_secret` | character varying(255) |  |  |
| `stock_cap` | integer | NOT NULL | 100 |
| `regular_price_type_id` | integer |  |  |
| `promo_price_type_id` | integer |  |  |
| `is_active` | boolean | NOT NULL | true |
| `last_received_at` | timestamp with time zone |  |  |
| `last_pushed_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `wp_product_sync`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('wp_product_sync_id_seq'::reg... |
| `store_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `product_id` | integer | NOT NULL |  |
| `sku` | character varying(120) | NOT NULL |  |
| `sync_enabled` | boolean | NOT NULL | true |
| `price_mode` | character varying(20) | NOT NULL | 'normal'::character varying |
| `wc_product_id` | integer |  |  |
| `last_synced_stock` | integer |  |  |
| `last_synced_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
