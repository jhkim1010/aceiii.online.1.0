-- Phase 86 마이그레이션 검증용 최소 부모 스키마 (실제 컬럼 타입 준수)
CREATE TABLE stores (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255)
);
CREATE TABLE branches (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255),
  store_id INTEGER NOT NULL REFERENCES stores(id),
  is_warehouse BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255),
  username VARCHAR(255),
  password VARCHAR(255),
  store_id INTEGER,
  branch_id INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE sales (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL,
  total_amount INTEGER,
  status VARCHAR(255),
  source VARCHAR(20) NOT NULL DEFAULT 'pos',
  activity_type VARCHAR(16) NOT NULL DEFAULT 'sale',
  daily_number INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT sales_source_check CHECK (source IN ('pos','online','factura','delivery'))
);
-- 2026-06-25-legacy-imports.sql 재현 (status 에 CHECK 없음 — M2 주석의 근거)
CREATE TABLE legacy_imports (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  file_name VARCHAR(255),
  file_size_bytes INTEGER NOT NULL DEFAULT 0,
  code_import_id INTEGER,
  tables_summary JSONB,
  errors JSONB,
  error_count INTEGER NOT NULL DEFAULT 0,
  status VARCHAR(32) NOT NULL DEFAULT 'COMPLETED',
  existing_hit_policy VARCHAR(16) NOT NULL DEFAULT 'skip',
  duration_ms INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO stores(name) VALUES ('kandente4-test');
INSERT INTO branches(name, store_id) VALUES ('Sucursal 4', 1);
INSERT INTO users(name, store_id, branch_id) VALUES ('admin', 1, 1);
INSERT INTO legacy_imports(store_id, user_id, file_name) VALUES (1, 1, 'kandente4.backup');
