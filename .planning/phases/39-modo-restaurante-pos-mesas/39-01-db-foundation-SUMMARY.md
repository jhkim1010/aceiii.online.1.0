---
phase: 39-modo-restaurante-pos-mesas
plan: 01
subsystem: db-foundation
tags: [restaurant, migration, sequelize, sales, store-config]
requires: []
provides:
  - "restaurant_tables 테이블 (식당 모드 테이블 배치)"
  - "sales 식당 nullable 컬럼 (table_id + 타이밍 + last_comanda_at)"
  - "store_configs 식당 플래그 (use_restaurant_mode + restaurant_category_ids)"
  - "RestaurantTable Sequelize 모델 + TableShape/TableStatus enum"
affects:
  - api-ventago/src/app/sales/sales.model.ts
  - api-ventago/src/app/store/config/storeConfig.model.ts
tech-stack:
  added: []
  patterns:
    - "PG10/15/18 호환 마이그레이션 (SERIAL + CREATE TABLE IF NOT EXISTS + DO 블록 CHECK 가드)"
    - "nullable 컬럼 추가로 소매 회귀 0 (storeClientId 선례)"
    - "순환 FK 회피: constraints:false BelongsTo (sales.tableId ↔ restaurant_tables.currentSaleId)"
key-files:
  created:
    - api-ventago/migrations/39-01-restaurant-tables.sql
    - api-ventago/migrations/39-02-sales-restaurant-cols.sql
    - api-ventago/migrations/39-03-store-config-restaurant.sql
    - api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts
  modified:
    - api-ventago/src/app/sales/sales.model.ts
    - api-ventago/src/app/store/config/storeConfig.model.ts
decisions:
  - "use_restaurant_mode DEFAULT false (기존 use_* 의 default true 와 차별 — 소매 무영향)"
  - "restaurant_category_ids JSONB nullable (categories 스키마 무변경, id 배열만 저장)"
  - "pos_x/pos_y REAL(FLOAT) 정규화 0~1 — 캔버스 크기 무관 (D-08)"
  - "last_comanda_at 신규 컬럼으로 comanda 증분 경계 확정 (39-RESEARCH Open Q2 해소)"
  - "restaurant_tables.current_sale_id REFERENCES sales(id) 를 39-01 에 먼저, sales.table_id FK 는 39-02 에 ADD (순환 FK 순서)"
metrics:
  duration: ~20min
  tasks: 2
  files: 6
  completed: 2026-06-14
---

# Phase 39 Plan 01: DB Foundation Summary

식당 모드 POS 의 DB 토대 — restaurant_tables 신규 테이블 + sales 식당 nullable 컬럼(table_id/ordered_at/served_at/closed_at/last_comanda_at) + store_configs 플래그(use_restaurant_mode default false + restaurant_category_ids JSONB) 를 PG10/15/18 호환 마이그레이션 3종으로 작성·dev PG18 멱등 적용하고, 대응 Sequelize 모델 3종(RestaurantTable 신규 + Sale/StoreConfig 확장)을 추가. 소매 회귀 0 (신규 sales 컬럼 전부 nullable).

## What Was Built

### Task 1: 마이그레이션 SQL 3종 (dev PG18 멱등 적용)
- **39-01-restaurant-tables.sql**: `CREATE TABLE IF NOT EXISTS restaurant_tables` — id(SERIAL), store_id/branch_id(NOT NULL FK ON DELETE CASCADE), name, shape(default 'square'), seats(default 4), pos_x/pos_y(REAL, 정규화 0~1), zone(nullable), status(default 'libre'), current_sale_id(nullable FK → sales(id) ON DELETE SET NULL). DO 블록 CHECK 가드 3개(chk_rt_shape / chk_rt_status / chk_rt_seats). branch/store 조회 인덱스 2개.
- **39-02-sales-restaurant-cols.sql**: `ADD COLUMN IF NOT EXISTS` 로 table_id(nullable FK → restaurant_tables(id) ON DELETE SET NULL) + ordered_at/served_at/closed_at/last_comanda_at(TIMESTAMPTZ nullable). 부분 인덱스 `idx_sales_table WHERE table_id IS NOT NULL` (소매 sale 인덱스 부담 0).
- **39-03-store-config-restaurant.sql**: `use_restaurant_mode BOOLEAN NOT NULL DEFAULT false` + `restaurant_category_ids JSONB NULL`.
- 적용 검증: 3 SQL 정상 적용 → 동일 3 SQL 재실행 → `IDEMPOTENT_OK` (CREATE TABLE IF NOT EXISTS + DO 가드 + ADD COLUMN IF NOT EXISTS 로 에러 0, NOTICE skipping 만).

### Task 2: Sequelize 모델 3종
- **restaurant-tables.model.ts (신규)**: `class RestaurantTable` (tableName:'restaurant_tables', timestamps) + `export enum TableShape`(circle/oval/square/rect) + `export enum TableStatus`(libre/ocupada/por_cobrar). store/branch FK, posX/posY(FLOAT), shape/seats/status, currentSaleId(constraints:false BelongsTo).
- **sales.model.ts (확장)**: RestaurantTable import + tableId(nullable FK, constraints:false) + orderedAt/servedAt/closedAt/lastComandaAt(전부 DataType.DATE allowNull:true). 기존 컬럼 무변경.
- **storeConfig.model.ts (확장)**: useRestaurantMode(BOOLEAN defaultValue:false) + restaurantCategoryIds(JSONB nullable). 기존 use_* 무변경.
- 검증: `npx tsc --noEmit` 전체 0 에러.

## Acceptance Criteria Verification

| 기준 | 결과 |
|------|------|
| restaurant_tables 13 컬럼 전부 존재 | PASS (id/store_id/branch_id/name/shape/seats/pos_x/pos_y/zone/status/current_sale_id/created_at/updated_at) |
| sales 신규 5 컬럼 전부 nullable | PASS (table_id/ordered_at/served_at/closed_at/last_comanda_at — is_nullable=YES 전부) |
| store_configs use_restaurant_mode(default false) + restaurant_category_ids(jsonb) | PASS (boolean default false / jsonb NULL) |
| 39-01 재실행 IDEMPOTENT_OK | PASS |
| GENERATED AS IDENTITY 실 사용 0 | PASS (39-01 의 1건은 "NOT GENERATED AS IDENTITY" 주석) |
| RestaurantTable class + tableName + posX/posY/shape/seats/status/currentSaleId | PASS |
| TableShape / TableStatus export enum | PASS |
| tsc --noEmit 0 에러 | PASS (전체 프로젝트) |

## Deviations from Plan

**환경 차이 1건 (블로커 해소):** 실행 시작 시 로컬 PG18 서버가 미기동 상태였음 (postmaster.pid stale — PID 793 은 WebKit 프로세스로 재사용됨, brew service `error` 상태, 소켓/리스너 없음). 마이그레이션 적용을 위해 `LC_ALL=en_US.UTF-8` 설정 후 `pg_ctl ... start` 로 로컬 PG18(`/usr/local/var/postgresql@18`, port 5432, unix socket `/tmp/.s.PGSQL.5432`)을 기동했다. (macOS `postmaster became multithreaded during startup` 이슈 → LC_ALL 로 해소). DB 접속은 `psql -h /tmp -U postgres -d ventago` 사용. 운영 PG10 은 미접촉.

그 외 SQL/모델 내용은 플랜과 동일하게 작성. 신규 sales 컬럼 전부 nullable 유지.

## Known Stubs

없음 — 이 플랜은 스키마/모델 정의만 수행. 데이터 흐름 wiring 은 후속 플랜(39-02 CRUD, 39-05 lifecycle)에서 진행.

## Commits

| Task | Submodule(api-ventago) | Parent(main) |
|------|------------------------|--------------|
| 1 (마이그레이션 SQL) | 274a6f0 | fe1e7bd |
| 2 (모델 3종) | 6ddc5d8 | 6846e64 |

## Follow-ups (후속 플랜 입력)

- 39-02 (tables-crud): sales.table_id FK 는 이미 생성됨 — RestaurantTablesModule CRUD + store/branch 스코프 + 상태↔sale 동기화 헬퍼.
- 39-04 (storeconfig-flag): storeConfig.controller.ts update-flag 화이트리스트에 `useRestaurantMode` 추가 필수 (안 하면 토글 BadRequestException — 39-RESEARCH Anti-Pattern).
- 39-05 (lifecycle): last_comanda_at 를 comanda emit 마다 갱신하여 증분 경계로 사용.
- 모델 등록: 신규 RestaurantTable 모델은 39-02 에서 RestaurantTablesModule + SequelizeModule.forFeature 로 등록 필요 (현재는 모델 파일만 존재, DI 미등록).

## Self-Check: PASSED

- 생성 파일 5종 전부 FOUND (마이그레이션 3 + RestaurantTable 모델 + SUMMARY)
- 서브모듈 커밋 274a6f0 / 6ddc5d8 FOUND
- 부모 포인터 커밋 fe1e7bd / 6846e64 FOUND
