---
phase: 39-modo-restaurante-pos-mesas
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - api-ventago/migrations/39-01-restaurant-tables.sql
  - api-ventago/migrations/39-02-sales-restaurant-cols.sql
  - api-ventago/migrations/39-03-store-config-restaurant.sql
  - api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts
  - api-ventago/src/app/sales/sales.model.ts
  - api-ventago/src/app/store/config/storeConfig.model.ts
autonomous: true
requirements: [REQ-1, REQ-2, REQ-3]
must_haves:
  truths:
    - "restaurant_tables 테이블이 형태/좌표/좌석수/상태/current_sale_id 컬럼으로 존재한다"
    - "sales 에 table_id + 타이밍 컬럼이 nullable 로 추가되어 기존 소매 sale 회귀가 0 이다"
    - "store_configs 에 use_restaurant_mode(default false) + restaurant_category_ids 컬럼이 존재한다"
  artifacts:
    - path: "api-ventago/migrations/39-01-restaurant-tables.sql"
      provides: "restaurant_tables CREATE TABLE (PG10/15/18 호환)"
      contains: "CREATE TABLE IF NOT EXISTS restaurant_tables"
    - path: "api-ventago/migrations/39-02-sales-restaurant-cols.sql"
      provides: "sales ALTER ADD COLUMN nullable"
      contains: "ADD COLUMN IF NOT EXISTS table_id"
    - path: "api-ventago/migrations/39-03-store-config-restaurant.sql"
      provides: "store_configs ALTER (플래그 + 카테고리 id 목록)"
      contains: "use_restaurant_mode"
    - path: "api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts"
      provides: "RestaurantTable Sequelize 모델"
      contains: "class RestaurantTable"
  key_links:
    - from: "api-ventago/src/app/sales/sales.model.ts"
      to: "restaurant_tables.id"
      via: "tableId @ForeignKey(() => RestaurantTable)"
      pattern: "tableId"
---

<objective>
Phase 39 식당 모드의 DB 토대를 만든다: (1) restaurant_tables 신규 테이블, (2) sales 식당 nullable 컬럼, (3) store_configs 플래그 + 식당 카테고리 id 목록. 마이그레이션 SQL(PG10/15/18 호환) + 대응 Sequelize 모델 확장까지 한 번에 수행한다.

Purpose: 이후 모든 Wave 의 백엔드/프론트가 이 스키마 위에서 동작한다. 소매 회귀 0(신규 컬럼 전부 nullable)이 절대 조건.
Output: 3 마이그레이션 SQL + RestaurantTable 모델 신규 + Sale/StoreConfig 모델 컬럼 추가.
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/39-modo-restaurante-pos-mesas/39-SPEC.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-CONTEXT.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-RESEARCH.md
@.planning/intel/db-schema-tables.md
@.planning/intel/db-schema-fks.md
@CLAUDE.md

<interfaces>
<!-- 확장 대상 모델의 기존 컨트랙트 (코드베이스에서 추출). 추가만 하고 기존 컬럼은 건드리지 말 것. -->

StoreConfig (api-ventago/src/app/store/config/storeConfig.model.ts):
```typescript
@Table({ timestamps: true })
export class StoreConfig extends Model {
  @Column({ allowNull: false }) storeId: number;
  @Column({ type: DataType.BOOLEAN, defaultValue: true }) useSupplier: boolean;
  // ... use* 플래그들 (전부 defaultValue: true)
  @Column({ type: DataType.STRING(3), allowNull: false, defaultValue: 'ARS' }) currency: string;
}
```

Sale (api-ventago/src/app/sales/sales.model.ts) — storeClientId 가 nullable FK 추가 선례:
```typescript
@ForeignKey(() => StoreClient)
@Column({ field: 'store_client_id', type: DataType.INTEGER, allowNull: true })
storeClientId?: number;

@Column status: SaleStatus;          // SaleStatus.DRAFT = 'Borrador'
@Column activityType: SaleActivityType; // 'sale' 명시 필터 규칙 — 불변 유지
@ForeignKey(() => Seller) sellerId: number;
```

마이그레이션 패턴 (api-ventago/migrations/29-01-mp-accounts.sql 선례 — PG10/15/18 호환):
- SERIAL PRIMARY KEY (NOT GENERATED AS IDENTITY)
- CREATE TABLE IF NOT EXISTS
- DO $$ BEGIN ... IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname=...) THEN ALTER TABLE ... ADD CONSTRAINT ... CHECK(...) END$$ (enum 가드)
- CREATE INDEX IF NOT EXISTS
- ALTER TABLE ... ADD COLUMN IF NOT EXISTS (멱등)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: 3개 마이그레이션 SQL 작성 (restaurant_tables + sales ALTER + store_configs ALTER)</name>
  <read_first>
    - api-ventago/migrations/29-01-mp-accounts.sql (PG10/15/18 호환 마이그레이션 패턴 — SERIAL, DO 블록 CHECK 가드, 부분 UNIQUE INDEX)
    - .planning/intel/db-schema-tables.md (stores / branches / sales 실제 컬럼 확인 — snake_case, FK 대상 PK)
    - .planning/intel/db-schema-fks.md (sales FK 관계 확인)
    - 39-RESEARCH.md Pattern 4 (restaurant_tables DDL 초안)
  </read_first>
  <action>
api-ventago/migrations/ 에 3개 SQL 파일 생성. 전부 snake_case 컬럼, PG10/15/18 호환(GENERATED AS IDENTITY 금지, SERIAL 사용). 각 파일 BEGIN; ... COMMIT; 로 감싼다.

**39-01-restaurant-tables.sql:**
```sql
BEGIN;
CREATE TABLE IF NOT EXISTS restaurant_tables (
  id              SERIAL PRIMARY KEY,
  store_id        INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  branch_id       INTEGER NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name            VARCHAR(64) NOT NULL,
  shape           VARCHAR(20) NOT NULL DEFAULT 'square',
  seats           INTEGER NOT NULL DEFAULT 4,
  pos_x           REAL NOT NULL DEFAULT 0,       -- 정규화 0~1 (D-08)
  pos_y           REAL NOT NULL DEFAULT 0,
  zone            VARCHAR(64) NULL,              -- D-09 다중 salón 대비 (UI 미사용)
  status          VARCHAR(20) NOT NULL DEFAULT 'libre',
  current_sale_id INTEGER NULL REFERENCES sales(id) ON DELETE SET NULL,
  created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_rt_shape') THEN
    ALTER TABLE restaurant_tables ADD CONSTRAINT chk_rt_shape
      CHECK (shape IN ('circle','oval','square','rect'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_rt_status') THEN
    ALTER TABLE restaurant_tables ADD CONSTRAINT chk_rt_status
      CHECK (status IN ('libre','ocupada','por_cobrar'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_rt_seats') THEN
    ALTER TABLE restaurant_tables ADD CONSTRAINT chk_rt_seats CHECK (seats > 0);
  END IF;
END$$;
CREATE INDEX IF NOT EXISTS idx_rt_branch ON restaurant_tables (branch_id);
CREATE INDEX IF NOT EXISTS idx_rt_store  ON restaurant_tables (store_id);
COMMIT;
```
주의: restaurant_tables.current_sale_id → sales(id) FK 이고 sales.table_id → restaurant_tables(id) FK 라서 순환 FK. restaurant_tables 를 먼저 만들고(39-01), sales.table_id FK 는 39-02 에서 ADD. 따라서 39-01 의 current_sale_id REFERENCES sales(id) 는 sales 가 이미 존재하므로 OK(sales 는 기존 테이블).

**39-02-sales-restaurant-cols.sql** (전부 nullable — 회귀 0):
```sql
BEGIN;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS table_id  INTEGER NULL REFERENCES restaurant_tables(id) ON DELETE SET NULL;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS ordered_at TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS served_at  TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS closed_at  TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS last_comanda_at TIMESTAMP WITH TIME ZONE NULL; -- comanda 증분 경계 (Open Q2 해소: 직전 emit 시각)
CREATE INDEX IF NOT EXISTS idx_sales_table ON sales (table_id) WHERE table_id IS NOT NULL;
COMMIT;
```
- last_comanda_at: comanda 증분 출력의 "직전 emit 시각" 저장처(39-RESEARCH Open Q2). 새 comanda 출력 시 갱신.
- 부분 인덱스 WHERE table_id IS NOT NULL: 소매 sale(대다수) 인덱스 부담 0.

**39-03-store-config-restaurant.sql:**
```sql
BEGIN;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS use_restaurant_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS restaurant_category_ids JSONB NULL;
COMMIT;
```
- use_restaurant_mode DEFAULT false (기존 use_* 는 true 지만 식당 플래그는 소매 무영향 위해 false — CONTEXT D 결정).
- restaurant_category_ids JSONB NULL (PG10 JSONB 지원 — Phase 25 client_merges.field_picks 선례).

각 파일 헤더에 한국어 주석으로 목적/회귀-0 근거 명시. dev DB(PG18 호스트, ventago)에 적용해 멱등(2회 실행 에러 0) 확인.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0 && psql -d ventago -f api-ventago/migrations/39-01-restaurant-tables.sql && psql -d ventago -f api-ventago/migrations/39-02-sales-restaurant-cols.sql && psql -d ventago -f api-ventago/migrations/39-03-store-config-restaurant.sql && psql -d ventago -f api-ventago/migrations/39-01-restaurant-tables.sql && echo "IDEMPOTENT_OK"</automated>
  </verify>
  <acceptance_criteria>
    - `psql -d ventago -c "\d restaurant_tables"` 출력에 columns: id, store_id, branch_id, name, shape, seats, pos_x, pos_y, zone, status, current_sale_id 전부 존재
    - `psql -d ventago -c "\d sales"` 출력에 table_id, ordered_at, served_at, closed_at, last_comanda_at 존재하며 전부 nullable (NOT NULL 표시 없음)
    - `psql -d ventago -c "\d store_configs"` 출력에 use_restaurant_mode(default false), restaurant_category_ids(jsonb) 존재
    - 39-01 재실행 시 "IDEMPOTENT_OK" 출력 (CREATE TABLE IF NOT EXISTS + DO 블록 가드로 에러 0)
    - 세 SQL 파일 모두 grep "GENERATED AS IDENTITY" 결과 0건 (PG10 호환)
    - 39-03-store-config-restaurant.sql 에 "use_restaurant_mode BOOLEAN NOT NULL DEFAULT false" 정확히 포함
  </acceptance_criteria>
  <done>3개 마이그레이션 SQL 이 dev PG18 에 멱등 적용되고, restaurant_tables/sales/store_configs 스키마가 acceptance 대로 확장됨. 신규 sales 컬럼 전부 nullable.</done>
</task>

<task type="auto">
  <name>Task 2: RestaurantTable 모델 신규 + Sale/StoreConfig 모델 컬럼 추가</name>
  <read_first>
    - api-ventago/src/app/store/config/storeConfig.model.ts (use* 플래그 패턴 — 추가만)
    - api-ventago/src/app/sales/sales.model.ts (storeClientId nullable FK 추가 선례, @ForeignKey/@BelongsTo/@Column 스타일)
    - api-ventago/src/app/sellers/sellers.model.ts (@Table/@Column 모델 골격 참고)
    - 39-RESEARCH.md Pattern 1 / Pattern 2 (모델 컬럼 정의 초안)
  </read_first>
  <action>
**신규 api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts:**
```typescript
import { Column, DataType, ForeignKey, Model, Table, BelongsTo } from 'sequelize-typescript';
import { Store } from '../store/store.model';   // 실제 경로 확인 후 import
import { Branch } from '../branch/branch.model'; // 실제 경로 확인
import { Sale } from '../sales/sales.model';

// 식당 테이블 형태 enum (DB CHECK 와 일치)
export enum TableShape { CIRCLE = 'circle', OVAL = 'oval', SQUARE = 'square', RECT = 'rect' }

// 테이블 상태 enum (libre=빈, ocupada=점유, por_cobrar=결제대기)
export enum TableStatus { LIBRE = 'libre', OCUPADA = 'ocupada', POR_COBRAR = 'por_cobrar' }

@Table({ tableName: 'restaurant_tables', timestamps: true })
export class RestaurantTable extends Model {
  @ForeignKey(() => Store)
  @Column({ field: 'store_id', type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @ForeignKey(() => Branch)
  @Column({ field: 'branch_id', type: DataType.INTEGER, allowNull: false })
  branchId: number;

  @Column({ type: DataType.STRING(64), allowNull: false })
  name: string;

  @Column({ type: DataType.STRING(20), allowNull: false, defaultValue: 'square' })
  shape: string;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 4 })
  seats: number;

  // 정규화 0~1 좌표 (D-08) — 캔버스 크기 무관
  @Column({ field: 'pos_x', type: DataType.FLOAT, allowNull: false, defaultValue: 0 })
  posX: number;

  @Column({ field: 'pos_y', type: DataType.FLOAT, allowNull: false, defaultValue: 0 })
  posY: number;

  @Column({ type: DataType.STRING(64), allowNull: true })
  zone?: string;

  @Column({ type: DataType.STRING(20), allowNull: false, defaultValue: 'libre' })
  status: string;

  @ForeignKey(() => Sale)
  @Column({ field: 'current_sale_id', type: DataType.INTEGER, allowNull: true })
  currentSaleId?: number;

  @BelongsTo(() => Sale, { foreignKey: 'currentSaleId', constraints: false })
  currentSale?: Sale;
}
```
주의: underscored:true 전역이지만 명시적 field: 'snake_case' 로 안전하게. Store/Branch import 경로는 코드베이스 실제 위치로 확인.

**api-ventago/src/app/sales/sales.model.ts 컬럼 추가** (storeClientId 바로 아래 패턴 모방, 기존 컬럼 무수정):
```typescript
// Phase 39: 식당 모드 nullable 컬럼 (소매 회귀 0)
@ForeignKey(() => RestaurantTable)
@Column({ field: 'table_id', type: DataType.INTEGER, allowNull: true })
tableId?: number;

@Column({ field: 'ordered_at', type: DataType.DATE, allowNull: true })
orderedAt?: Date;

@Column({ field: 'served_at', type: DataType.DATE, allowNull: true })
servedAt?: Date;

@Column({ field: 'closed_at', type: DataType.DATE, allowNull: true })
closedAt?: Date;

@Column({ field: 'last_comanda_at', type: DataType.DATE, allowNull: true })
lastComandaAt?: Date;
```
RestaurantTable import 추가. 순환 import 주의 — RestaurantTable 도 Sale 을 import 하므로 sequelize-typescript 는 () => 화살표 lazy ref 로 해결됨(이미 그 패턴). constraints:false 불필요(FK 는 마이그레이션이 생성).

**api-ventago/src/app/store/config/storeConfig.model.ts 컬럼 추가** (use* 블록 끝에):
```typescript
// Phase 39: 식당 모드 플래그 (기존 use* 와 달리 default false — 소매 무영향)
@Column({ field: 'use_restaurant_mode', type: DataType.BOOLEAN, defaultValue: false })
useRestaurantMode: boolean;

// 식당 메뉴로 노출할 카테고리 id 목록 (categories 스키마 무변경)
@Column({ field: 'restaurant_category_ids', type: DataType.JSONB, allowNull: true })
restaurantCategoryIds: number[] | null;
```

ESLint: 모든 import 사용, // 주석 위 빈 줄, 미사용 제거. tsc 컴파일 통과 확인.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -i "restaurant\|storeConfig\|sales.model" | head; echo "TSC_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts 에 `class RestaurantTable` + `tableName: 'restaurant_tables'` + posX/posY/shape/seats/status/currentSaleId 존재
    - grep "useRestaurantMode" api-ventago/src/app/store/config/storeConfig.model.ts 결과 1건 + "defaultValue: false" 동일 라인 인근
    - grep "tableId" api-ventago/src/app/sales/sales.model.ts 결과 존재 + "field: 'table_id'" + allowNull: true
    - grep "orderedAt\|servedAt\|closedAt\|lastComandaAt" api-ventago/src/app/sales/sales.model.ts 4건 전부 allowNull: true
    - `npx tsc --noEmit` 에서 신규/수정 모델 관련 에러 0
    - export enum TableShape / TableStatus 존재 (39-02 service 에서 재사용)
  </acceptance_criteria>
  <done>RestaurantTable 모델 신규 생성 + Sale/StoreConfig 모델에 nullable 식당 컬럼 추가, tsc 통과. 기존 컬럼/매핑 무변경.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| 마이그레이션 → 운영 DB | DDL 이 기존 sales 데이터에 회귀를 일으킬 수 있는 경계 |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-01 | Tampering | sales ALTER | mitigate | 신규 컬럼 전부 nullable + ADD COLUMN IF NOT EXISTS — 기존 INSERT/SELECT 불변. activity_type='sale' 필터 규칙 무변경 |
| T-39-02 | Denial | restaurant_tables 인덱스 | accept | 부분 인덱스(WHERE table_id IS NOT NULL)로 소매 sale 인덱스 부담 0, pool 영향 무시 가능 |
</threat_model>

<verification>
- dev PG18 에 3 SQL 멱등 적용 + 재실행 에러 0
- 기존 소매 sale INSERT smoke (선택): 마이그레이션 후 일반 sale 생성이 동일 동작 — Wave 2 sales spec 회귀로 확인
- tsc 컴파일 0 에러
</verification>

<success_criteria>
- restaurant_tables 테이블 + RestaurantTable 모델 존재
- sales table_id + 4 타이밍 컬럼 nullable, 회귀 0
- store_configs use_restaurant_mode(false) + restaurant_category_ids
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-01-SUMMARY.md` 작성.
</output>
