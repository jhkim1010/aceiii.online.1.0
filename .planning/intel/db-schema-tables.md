# Ventago Database Schema (PostgreSQL public)

> Auto-generated from local PG18 `ventago` DB on 2026-06-02T10:11:30Z.
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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `branch_id` | integer |  |  |
| `linked_user_id` | integer |  |  |

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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `branch_printer_configs`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('branch_printer_configs_id_se... |
| `branch_id` | integer | NOT NULL |  |
| `api_key` | character varying(64) | NOT NULL |  |
| `is_online` | boolean | NOT NULL | false |
| `last_seen_at` | timestamp with time zone |  |  |
| `printer_info` | jsonb |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `branches`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('branches_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `is_main` | boolean |  |  |
| `api_key` | character varying(255) |  |  |
| `point_of_sale` | character varying(255) |  |  |
| `address_commercial` | character varying(255) |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `store_id` | integer |  |  |
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
| `denied_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `executed_at` | timestamp with time zone | NOT NULL |  |
| `missing_doc_policy` | character varying(20) | NOT NULL | 'local'::character varying |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `merged_at` | timestamp with time zone | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `province_text` | character varying(100) |  |  |
| `whatsapp` | character varying(255) |  |  |

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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `colors`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('colors_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `hex` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer |  |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `configurations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('configurations_id_seq'::regc... |
| `key` | character varying(255) |  |  |
| `nombre` | character varying(255) |  |  |
| `data` | json |  |  |
| `description` | character varying(255) |  |  |
| `store_id` | integer |  |  |
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
| `discount_value` | integer |  |  |
| `start_date` | timestamp with time zone |  |  |
| `end_date` | timestamp with time zone |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `expense_categories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expense_categories_id_seq'::... |
| `store_id` | integer | NOT NULL |  |
| `parent_id` | integer |  |  |
| `name` | character varying(120) | NOT NULL |  |
| `path` | text | NOT NULL | ''::text |
| `depth` | smallint | NOT NULL | 0 |
| `sort_order` | integer | NOT NULL | 0 |
| `color` | character varying(16) |  |  |
| `icon` | character varying(64) |  |  |
| `status` | smallint | NOT NULL | 1 |
| `created_at` | timestamp without time zone | NOT NULL | now() |
| `updated_at` | timestamp without time zone | NOT NULL | now() |

## `expenses`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('expenses_id_seq'::regclass) |
| `amount` | numeric | NOT NULL |  |
| `description` | character varying(255) | NOT NULL |  |
| `date` | timestamp with time zone | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `expenses_subcategory_id` | integer |  |  |
| `affects_box` | boolean | NOT NULL | true |
| `box_register_id` | integer |  |  |
| `branch_id` | integer | NOT NULL |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `category_id` | integer |  |  |

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
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |

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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |

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

## `module_aliases`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('module_aliases_id_seq'::regc... |
| `module` | character varying(255) |  |  |
| `alias` | character varying(255) |  |  |
| `store_id` | integer |  |  |
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
| `connected_at` | timestamp with time zone | NOT NULL | now() |
| `disconnected_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `mp_movements`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_movements_id_seq'::regclass) |
| `mp_wallet_id` | integer | NOT NULL |  |
| `type` | character varying(20) | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `sale_id` | integer |  |  |
| `refund_id` | integer |  |  |
| `mp_payment_id` | character varying(32) |  |  |
| `transfer_id` | integer |  |  |
| `note` | text |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |

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
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `mp_refund_attempts`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_refund_attempts_id_seq'::... |
| `sale_id` | integer | NOT NULL |  |
| `mp_payment_id` | character varying(32) | NOT NULL |  |
| `attempt_no` | integer | NOT NULL |  |
| `status` | character varying(20) | NOT NULL | 'pending'::character varying |
| `error_message` | character varying(500) |  |  |
| `refund_id` | character varying(32) |  |  |
| `attempted_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `mp_refunds`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_refunds_id_seq'::regclass) |
| `sale_id` | integer | NOT NULL |  |
| `mp_payment_id` | character varying(32) | NOT NULL |  |
| `refund_id` | character varying(32) | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `refunded_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `mp_transfers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('mp_transfers_id_seq'::regclass) |
| `mp_wallet_id` | integer | NOT NULL |  |
| `target_box_id` | integer | NOT NULL |  |
| `amount` | numeric | NOT NULL |  |
| `user_id` | integer | NOT NULL |  |
| `status` | character varying(20) | NOT NULL | 'completed'::character varying |
| `note` | text |  |  |
| `transferred_at` | timestamp with time zone | NOT NULL | now() |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

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
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

## `nations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('nations_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `store_id` | integer |  |  |
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
| `store_id` | integer |  |  |
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

## `provinces`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('provinces_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `nation_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `recharges`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('recharges_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `description` | character varying(255) |  |  |
| `recharge_type` | character varying(255) |  |  |
| `recharge_value` | integer |  |  |
| `start_date` | timestamp with time zone |  |  |
| `end_date` | timestamp with time zone |  |  |
| `store_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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

## `role_function_actions`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('role_function_actions_id_seq... |
| `role_function_id` | integer |  |  |
| `action` | character varying(20) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `store_id` | integer |  |  |
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

## `seasons`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('seasons_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer |  |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `store_id` | integer |  |  |
| `store_entity_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `stocks`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('stocks_id_seq'::regclass) |
| `stock` | integer |  |  |
| `product_branch_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `type` | character varying(20) |  | NULL::character varying |
| `note` | text |  |  |
| `is_active` | boolean | NOT NULL | true |
| `operation_date` | date | NOT NULL | CURRENT_DATE |
| `backfill_processed_sale_id` | integer |  |  |

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
| `billing_status` | character varying(20) |  | 'inactive'::character varying |

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

## `store_integrations`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_integrations_id_seq'::... |
| `integration` | character varying(255) |  |  |
| `store_id` | integer |  |  |
| `status` | character varying(255) |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `store_subcategories`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('store_subcategories_id_seq':... |
| `global_subcategory_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `is_enabled` | boolean |  | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

## `stores`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('stores_id_seq'::regclass) |
| `name` | character varying(255) |  |  |
| `alias_name` | character varying(255) |  |  |
| `cuit` | bigint |  |  |
| `address` | character varying(255) |  |  |
| `is_active` | boolean |  |  |
| `integration` | character varying(255) |  |  |
| `status` | character varying(255) |  |  |
| `type_of_payer` | character varying(255) |  |  |
| `start_activities_date` | timestamp with time zone |  |  |
| `income_number` | bigint |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `timezone` | character varying(255) |  | 'America/Bogota'::character varying |
| `logo_url` | character varying(255) |  |  |
| `use_variants` | boolean | NOT NULL | true |
| `owner_group_id` | integer | NOT NULL |  |
| `senia_ui_mode` | character varying(20) | NOT NULL | 'separated'::character varying |
| `representative_user_id` | integer |  |  |

## `style_cost_sheets`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('style_cost_sheets_id_seq'::r... |
| `product_id` | integer | NOT NULL |  |
| `store_id` | integer | NOT NULL |  |
| `currency` | character(3) | NOT NULL | 'USD'::bpchar |
| `retail_price` | numeric |  |  |
| `target_margin_pct` | numeric | NOT NULL | 50.00 |
| `overhead_pct` | numeric | NOT NULL | 11.30 |
| `shipping_cost_per_lote` | numeric | NOT NULL | 200.00 |
| `lote_size_default` | integer | NOT NULL | 155 |
| `material_cost` | numeric |  |  |
| `cmt_cost` | numeric |  |  |
| `overhead_cost` | numeric |  |  |
| `total_cost` | numeric |  |  |
| `margin_amount` | numeric |  |  |
| `margin_pct` | numeric |  |  |
| `calc_snapshot` | jsonb |  |  |
| `last_calculated_at` | timestamp with time zone |  |  |
| `created_at` | timestamp with time zone | NOT NULL | now() |
| `updated_at` | timestamp with time zone | NOT NULL | now() |

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
| `app_talleres_price` | numeric |  | 50000 |
| `app_materia_prima_price` | numeric |  | 50000 |

## `suppliers`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('suppliers_id_seq'::regclass) |
| `name` | character varying(255) | NOT NULL |  |
| `is_active` | boolean |  |  |
| `status` | integer |  | 1 |
| `store_id` | integer |  |  |
| `store_entity_id` | integer |  |  |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |

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
| `status` | character varying(20) |  | 'PENDING'::character varying |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |
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
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |

## `talleres_lotes`

| Column | Type | Null | Default |
|---|---|---|---|
| `id` | integer | NOT NULL | nextval('talleres_lotes_id_seq'::regc... |
| `lote_number` | character varying(255) | NOT NULL |  |
| `product_id` | integer | NOT NULL |  |
| `total_quantity` | integer | NOT NULL |  |
| `available_quantity` | integer | NOT NULL |  |
| `status` | character varying(20) |  | 'OPEN'::character varying |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |
| `cut_ticket_number` | character varying(40) |  |  |
| `style_code` | character varying(60) |  |  |
| `season` | character varying(40) |  |  |
| `cut_date` | date |  |  |
| `size_color_matrix` | jsonb |  |  |
| `bom_snapshot` | jsonb |  |  |
| `routing_path` | jsonb |  |  |

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
| `envio_id` | integer |  |  |
| `received_quantity` | integer | NOT NULL |  |
| `rejected_quantity` | integer |  | 0 |
| `recepcion_date` | date | NOT NULL |  |
| `notes` | text |  |  |
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |

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
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |
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
| `store_id` | integer | NOT NULL |  |
| `created_at` | timestamp with time zone |  | now() |
| `updated_at` | timestamp with time zone |  | now() |
| `pin_hash` | character varying(255) |  |  |
| `pin_updated_at` | timestamp with time zone |  |  |
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
| `store_id` | integer |  |  |
| `allowed` | boolean | NOT NULL | true |
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `branch_id` | integer |  |  |
| `valid_from` | timestamp with time zone | NOT NULL |  |
| `valid_until` | timestamp with time zone |  |  |
| `reason` | text |  |  |
| `granted_by` | integer |  |  |

## `user_permission_cache`

| Column | Type | Null | Default |
|---|---|---|---|
| `user_id` | integer | NOT NULL |  |
| `branch_id` | integer | NOT NULL |  |
| `permissions` | jsonb | NOT NULL |  |
| `computed_at` | timestamp without time zone | NOT NULL | now() |

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
| `ui_mode` | USER-DEFINED |  | 'classic'::ui_mode_enum |
| `monthly_sales_target` | numeric |  |  |
| `whatsapp_phone` | character varying(30) |  |  |

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
| `store_id` | integer |  |  |
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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |
| `num_pedido` | character varying(255) |  |  |
| `branch_id` | integer |  |  |
| `province_id` | integer |  |  |
| `source` | character varying(10) | NOT NULL | 'pos'::character varying |

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
| `created_at` | timestamp with time zone | NOT NULL |  |
| `updated_at` | timestamp with time zone | NOT NULL |  |

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
