# Revendedor 지역 추천 — Plan A (백엔드 기반 + 추천 엔진) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 허가매장 통합 카탈로그 + 지역(provincia)×상품 추천 엔진의 **백엔드**를 구축한다. revendedor 웹(Plan B)과 vendedor 앱(Plan C)이 소비할 API·집계·스키마를 완성한다.

**Architecture:** 신규 `reseller` PG 스키마에 허가(`reseller_tienda_link`)·canonical 카테고리·요약 통계(`province_product_stats`)·추천 로그 테이블을 둔다. 30분 `@Cron` 이 `sale_items×sales×clients` 를 집계해 요약 테이블을 선계산하고(런타임 p95 ≤ 300ms), 조회 API 는 요약만 읽는다. 지역 신호는 `COALESCE(sales.province_id, clients.province_id)`. GPS 지역감지는 `provinces` 중심좌표 최근접(오프라인).

**Tech Stack:** NestJS 11 + Sequelize(sequelize-typescript, `underscored: true`) + PostgreSQL 18, `@nestjs/schedule` Cron, jest.

**설계 문서:** `docs/superpowers/specs/2026-07-16-revendedor-zona-recomendacion-design.md`

## Global Constraints

- **DB 컬럼 snake_case** (Sequelize `underscored: true`). SQL 직접 실행 시 snake_case. SQL/마이그레이션 전 `.planning/intel/db-schema-tables.md` 참조.
- **신규 스키마 = `reseller`** (Sequelize 모델 `schema: 'reseller'`). legacy `public.revendedores` 와 혼용 금지.
- **지역 신호 = `COALESCE(sales.province_id, clients.province_id)`**. 매장 = `sales.store_id`(직접 컬럼).
- **추천 랭킹 = 최근 60일 판매량 × `(1 + max(0,trend_pct)/100)`**, `trend_pct = (qty_60d - qty_prev_60d)/nullif(qty_prev_60d,0)*100`.
- **재고 정확수량 비공개** — `inStock` boolean(`stocks.stock > 0`)만 노출.
- **pool 보호**: 전역 pool 재사용(min=2/max=80). Cron 은 단일 배치 + upsert, 겹침 방지 가드. 런타임 조회는 요약 테이블만. slow query(>100ms) 금지.
- **마이그레이션은 로컬(Mac PG18 5432) + 운영(PG18 5434) 동시 적용.** 신규 테이블 owner + 시퀀스 → `coolsistema` (role 존재체크 DO 블록). SQL 은 `api-ventago/migrations/` 커밋.
- **주석 한국어, 함수/변수명 영어, 사용자 노출 문자열 스페인어** (CLAUDE.md).
- **ESLint(빌드 차단)**: `return` 위 빈 줄, 주석 위 빈 줄, 미사용 import 금지.
- 테스트: `cd api-ventago && npx jest src/app/reseller`. **`git add -A` 금지**(파일명 명시). api-ventago 는 gitlink 서브모듈 → `cd` 후 커밋.
- 운영 데이터(2026-07-16): legacy revendedores 0, 국가 AR 1개, categories 46(고유 39). stores 7. `sales.province_id` 채움 23% / `clients.province_id` 48%.

---

### Task 1: 마이그레이션 (reseller 스키마 + 테이블 + FK/좌표 컬럼)

**Files:**
- Create: `api-ventago/migrations/2026-07-16-reseller-zona.sql`
- Create: `scripts/apply-reseller-zona-migration.sql` (아님 — 적용은 기존 psql 패턴)

**Interfaces:**
- Produces: `reseller` 스키마 + 테이블 `resellers`, `reseller_tienda_link`, `canonical_categories`, `province_product_stats`, `store_recommendations`. `public.categories.canonical_category_id`. `public.provinces.lat/lng`. Task 2~10 가 사용.

- [ ] **Step 1: 마이그레이션 SQL 작성**

Create `api-ventago/migrations/2026-07-16-reseller-zona.sql`:

```sql
-- =============================================================================
-- Revendedor 지역 추천 — reseller 스키마 + 추천 엔진 테이블
-- =============================================================================
-- 적용: 로컬 5432 + 운영 5434 동시. 신규 테이블 owner→coolsistema.
-- 설계: docs/superpowers/specs/2026-07-16-revendedor-zona-recomendacion-design.md
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS reseller;

CREATE TABLE IF NOT EXISTS reseller.resellers (
  id              SERIAL PRIMARY KEY,
  document        VARCHAR(40) UNIQUE,
  name            VARCHAR(160) NOT NULL,
  email           VARCHAR(160) UNIQUE,
  phone           VARCHAR(40),
  password        VARCHAR(200),
  province_id     INTEGER,
  province_source VARCHAR(12) NOT NULL DEFAULT 'manual',
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reseller.reseller_tienda_link (
  id           SERIAL PRIMARY KEY,
  reseller_id  INTEGER NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
  store_id     INTEGER NOT NULL,
  status       VARCHAR(12) NOT NULL DEFAULT 'pending',
  approved_by  INTEGER,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_reseller_store UNIQUE (reseller_id, store_id),
  CONSTRAINT chk_rtl_status CHECK (status IN ('pending','approved','revoked'))
);

CREATE TABLE IF NOT EXISTS reseller.canonical_categories (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL UNIQUE,
  slug       VARCHAR(120) NOT NULL UNIQUE,
  parent_id  INTEGER REFERENCES reseller.canonical_categories(id),
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reseller.province_product_stats (
  id            SERIAL PRIMARY KEY,
  province_id   INTEGER NOT NULL,
  store_id      INTEGER NOT NULL,
  canonical_category_id INTEGER,
  product_id    INTEGER NOT NULL,
  qty_60d       INTEGER NOT NULL DEFAULT 0,
  qty_prev_60d  INTEGER NOT NULL DEFAULT 0,
  trend_pct     NUMERIC(6,1),
  rank_in_prov  INTEGER,
  refreshed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_pps UNIQUE (province_id, store_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_pps_prov_cat
  ON reseller.province_product_stats (province_id, canonical_category_id, rank_in_prov);
CREATE INDEX IF NOT EXISTS idx_pps_store
  ON reseller.province_product_stats (store_id, rank_in_prov);

CREATE TABLE IF NOT EXISTS reseller.store_recommendations (
  id           SERIAL PRIMARY KEY,
  reseller_id  INTEGER NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
  store_id     INTEGER NOT NULL,
  product_id   INTEGER NOT NULL,
  province_id  INTEGER,
  reason       VARCHAR(20) NOT NULL,
  note         VARCHAR(300),
  status       VARCHAR(12) NOT NULL DEFAULT 'sent',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_sr_reason CHECK (reason IN ('zona_top','stock_gap')),
  CONSTRAINT chk_sr_status CHECK (status IN ('sent','seen','accepted','dismissed'))
);

-- public.categories 에 canonical 매핑 컬럼 (매핑 안 되면 revendedor 카탈로그 미노출)
ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS canonical_category_id INTEGER
    REFERENCES reseller.canonical_categories(id) ON DELETE SET NULL;

-- public.provinces 중심좌표 (GPS 최근접 매핑용)
ALTER TABLE public.provinces ADD COLUMN IF NOT EXISTS lat NUMERIC(9,6);
ALTER TABLE public.provinces ADD COLUMN IF NOT EXISTS lng NUMERIC(9,6);

-- 운영 role 접근 보장 (postgres 소유 생성 시 coolsistema permission denied 방지)
DO $$
DECLARE t TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    GRANT USAGE ON SCHEMA reseller TO coolsistema;
    FOR t IN
      SELECT tablename FROM pg_tables WHERE schemaname = 'reseller'
    LOOP
      EXECUTE format('ALTER TABLE reseller.%I OWNER TO coolsistema', t);
    END LOOP;
    -- 시퀀스 owner 도 이전 (ALTER TABLE OWNER 는 시퀀스 안 옮김)
    FOR t IN
      SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'reseller'
    LOOP
      EXECUTE format('ALTER SEQUENCE reseller.%I OWNER TO coolsistema', t);
    END LOOP;
  END IF;
END $$;
```

- [ ] **Step 2: 로컬 적용 명령 사용자 전달**

클라우드 세션은 Mac DB 에 못 닿는다. 사용자에게:
```
psql -p 5432 -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/2026-07-16-reseller-zona.sql
```
운영(5434)은 배포 단계에서 SSH 적용. 이 태스크는 로컬 적용 확인만 요청하고 진행(모델 테스트는 mock 이라 DB 불요).

- [ ] **Step 3: 스키마 확인 쿼리 사용자 전달**

```
psql -p 5432 -d ventago -c "\dt reseller.*"
psql -p 5432 -d ventago -c "\d public.categories" | grep canonical
```
Expected: 5개 테이블 + `canonical_category_id` 컬럼 존재.

- [ ] **Step 4: 커밋**

```bash
cd api-ventago
git add migrations/2026-07-16-reseller-zona.sql
git commit -m "feat(reseller): 지역 추천 스키마 — reseller 5테이블 + canonical FK + provinces 좌표

reseller 스키마(resellers/reseller_tienda_link/canonical_categories/
province_product_stats/store_recommendations) + categories.canonical_category_id
+ provinces.lat/lng. owner→coolsistema. 로컬 5432 적용, 운영 5434 배포 단계."
```

---

### Task 2: Sequelize 모델 5종 + 모듈 스캐폴드

**Files:**
- Create: `api-ventago/src/app/reseller/reseller.model.ts`
- Create: `api-ventago/src/app/reseller/reseller-tienda-link.model.ts`
- Create: `api-ventago/src/app/reseller/canonical-category.model.ts`
- Create: `api-ventago/src/app/reseller/province-product-stats.model.ts`
- Create: `api-ventago/src/app/reseller/store-recommendation.model.ts`
- Create: `api-ventago/src/app/reseller/reseller.module.ts`
- Modify: `api-ventago/src/app.module.ts` (ResellerModule import)
- Test: `api-ventago/src/app/reseller/reseller.model.spec.ts`

**Interfaces:**
- Consumes: Task 1 테이블.
- Produces: 모델 클래스. Task 4~10 가 주입해 사용. 모두 `schema: 'reseller'`(단 category/province/sale 은 public 기존 모델 재사용).

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/reseller.model.spec.ts`:

```ts
import { Reseller } from './reseller.model';
import { ResellerTiendaLink } from './reseller-tienda-link.model';
import { ProvinceProductStats } from './province-product-stats.model';

describe('reseller 모델 계약', () => {
  it('resellers 테이블 + reseller 스키마', () => {
    const t = Reseller.getTableName() as any;
    expect(t.tableName ?? t).toBe('resellers');
    expect(t.schema).toBe('reseller');
  });

  it('Reseller 는 provinceId/provinceSource 컬럼', () => {
    const a = Reseller.getAttributes();
    expect(a.provinceId).toBeDefined();
    expect(a.provinceSource).toBeDefined();
  });

  it('ResellerTiendaLink 는 status 기본 pending', () => {
    const a = ResellerTiendaLink.getAttributes() as any;
    expect(a.status.defaultValue).toBe('pending');
  });

  it('ProvinceProductStats 는 qty60d/qtyPrev60d/trendPct/rankInProv', () => {
    const a = ProvinceProductStats.getAttributes();
    for (const c of ['qty60d', 'qtyPrev60d', 'trendPct', 'rankInProv']) {
      expect(a[c]).toBeDefined();
    }
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/reseller.model.spec.ts`
Expected: FAIL — `Cannot find module './reseller.model'`

- [ ] **Step 3: 모델 구현**

Create `api-ventago/src/app/reseller/reseller.model.ts`:

```ts
import { Table, Column, Model, DataType, PrimaryKey, AutoIncrement } from 'sequelize-typescript';

// 재판매자 (Phase 24 reseller 스키마. legacy public.revendedores 와 별개).
@Table({ tableName: 'resellers', schema: 'reseller', timestamps: true })
export class Reseller extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column(DataType.INTEGER)
  id: number;

  @Column({ type: DataType.STRING(40), allowNull: true })
  document: string | null;

  @Column({ type: DataType.STRING(160), allowNull: false })
  name: string;

  @Column({ type: DataType.STRING(160), allowNull: true })
  email: string | null;

  @Column({ type: DataType.STRING(40), allowNull: true })
  phone: string | null;

  @Column({ type: DataType.STRING(200), allowNull: true })
  password: string | null;

  // 홈 지방 (GPS 감지 or 수동). provinces.id.
  @Column({ type: DataType.INTEGER, allowNull: true })
  provinceId: number | null;

  @Column({ type: DataType.STRING(12), allowNull: false, defaultValue: 'manual' })
  provinceSource: string;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  isActive: boolean;
}
```

Create `api-ventago/src/app/reseller/reseller-tienda-link.model.ts`:

```ts
import { Table, Column, Model, DataType, PrimaryKey, AutoIncrement } from 'sequelize-typescript';

// 재판매자 ↔ 매장 허가 (관리자 승인). status: pending|approved|revoked.
@Table({ tableName: 'reseller_tienda_link', schema: 'reseller', timestamps: true })
export class ResellerTiendaLink extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column(DataType.INTEGER)
  id: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  resellerId: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @Column({ type: DataType.STRING(12), allowNull: false, defaultValue: 'pending' })
  status: string;

  @Column({ type: DataType.INTEGER, allowNull: true })
  approvedBy: number | null;
}
```

Create `api-ventago/src/app/reseller/canonical-category.model.ts`:

```ts
import { Table, Column, Model, DataType, PrimaryKey, AutoIncrement } from 'sequelize-typescript';

// 전역 canonical 카테고리 (TIPO 통합). public.categories.canonical_category_id 가 참조.
@Table({ tableName: 'canonical_categories', schema: 'reseller', timestamps: true })
export class CanonicalCategory extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column(DataType.INTEGER)
  id: number;

  @Column({ type: DataType.STRING(100), allowNull: false })
  name: string;

  @Column({ type: DataType.STRING(120), allowNull: false })
  slug: string;

  @Column({ type: DataType.INTEGER, allowNull: true })
  parentId: number | null;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  sortOrder: number;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  isActive: boolean;
}
```

Create `api-ventago/src/app/reseller/province-product-stats.model.ts`:

```ts
import { Table, Column, Model, DataType, PrimaryKey, AutoIncrement } from 'sequelize-typescript';

// 지역×상품 추천 요약 (Cron 선계산). 런타임 조회는 이 테이블만 읽는다.
@Table({ tableName: 'province_product_stats', schema: 'reseller', timestamps: false })
export class ProvinceProductStats extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column(DataType.INTEGER)
  id: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  provinceId: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @Column({ type: DataType.INTEGER, allowNull: true })
  canonicalCategoryId: number | null;

  @Column({ type: DataType.INTEGER, allowNull: false })
  productId: number;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  qty60d: number;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  qtyPrev60d: number;

  @Column({ type: DataType.DECIMAL(6, 1), allowNull: true })
  trendPct: number | null;

  @Column({ type: DataType.INTEGER, allowNull: true })
  rankInProv: number | null;

  @Column({ type: DataType.DATE, allowNull: false, defaultValue: DataType.NOW })
  refreshedAt: Date;
}
```

Create `api-ventago/src/app/reseller/store-recommendation.model.ts`:

```ts
import { Table, Column, Model, DataType, PrimaryKey, AutoIncrement } from 'sequelize-typescript';

// revendedor → 매장 추천 로그. reason: zona_top|stock_gap.
@Table({ tableName: 'store_recommendations', schema: 'reseller', timestamps: false })
export class StoreRecommendation extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column(DataType.INTEGER)
  id: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  resellerId: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  productId: number;

  @Column({ type: DataType.INTEGER, allowNull: true })
  provinceId: number | null;

  @Column({ type: DataType.STRING(20), allowNull: false })
  reason: string;

  @Column({ type: DataType.STRING(300), allowNull: true })
  note: string | null;

  @Column({ type: DataType.STRING(12), allowNull: false, defaultValue: 'sent' })
  status: string;

  @Column({ type: DataType.DATE, allowNull: false, defaultValue: DataType.NOW })
  createdAt: Date;
}
```

Create `api-ventago/src/app/reseller/reseller.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { Reseller } from './reseller.model';
import { ResellerTiendaLink } from './reseller-tienda-link.model';
import { CanonicalCategory } from './canonical-category.model';
import { ProvinceProductStats } from './province-product-stats.model';
import { StoreRecommendation } from './store-recommendation.model';

@Module({
  imports: [
    SequelizeModule.forFeature([
      Reseller,
      ResellerTiendaLink,
      CanonicalCategory,
      ProvinceProductStats,
      StoreRecommendation,
    ]),
  ],
  providers: [],
  controllers: [],
})
export class ResellerModule {}
```

`api-ventago/src/app.module.ts` 의 `imports` 배열에 `ResellerModule` 추가 + 상단 import:
```ts
import { ResellerModule } from './app/reseller/reseller.module';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/reseller.model.spec.ts`
Expected: PASS — 4개.

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -i reseller || echo "reseller 타입에러 없음"`
Expected: reseller 타입에러 없음

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/reseller/reseller.model.ts src/app/reseller/reseller-tienda-link.model.ts src/app/reseller/canonical-category.model.ts src/app/reseller/province-product-stats.model.ts src/app/reseller/store-recommendation.model.ts src/app/reseller/reseller.module.ts src/app/reseller/reseller.model.spec.ts src/app.module.ts
git commit -m "feat(reseller): Sequelize 모델 5종 + 모듈 등록

Reseller/ResellerTiendaLink/CanonicalCategory/ProvinceProductStats/
StoreRecommendation (schema: reseller). app.module 등록."
```

---

### Task 3: 시드 — canonical 카테고리 + AR 24개 주 좌표 + 이름 자동매핑

**Files:**
- Create: `api-ventago/migrations/2026-07-16-reseller-zona-seed.sql`
- Test: `api-ventago/src/app/reseller/canonical-mapping.spec.ts`
- Create: `api-ventago/src/app/reseller/canonical-mapping.ts` (순수 함수 slug/normalize)

**Interfaces:**
- Consumes: Task 1 테이블.
- Produces: canonical seed + provinces 좌표 + `categories.canonical_category_id` 자동매핑. `normalizeCategoryName`, `toSlug` 순수 함수(Task 10 매핑 UI 재사용).

- [ ] **Step 1: 순수 함수 실패 테스트**

Create `api-ventago/src/app/reseller/canonical-mapping.spec.ts`:

```ts
import { normalizeCategoryName, toSlug } from './canonical-mapping';

describe('canonical 이름 정규화', () => {
  it('normalizeCategoryName: 소문자 + trim + 악센트 제거', () => {
    expect(normalizeCategoryName('  Remería ')).toBe('remeria');
    expect(normalizeCategoryName('Pantalón')).toBe('pantalon');
  });

  it('toSlug: 공백 → 하이픈, 악센트 제거, 소문자', () => {
    expect(toSlug('Ropa Interior')).toBe('ropa-interior');
    expect(toSlug('Calzado Niño')).toBe('calzado-nino');
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/canonical-mapping.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 순수 함수 구현**

Create `api-ventago/src/app/reseller/canonical-mapping.ts`:

```ts
// 카테고리 이름 정규화 — 자동매핑(exact match)과 slug 생성에 공용.

const stripAccents = (s: string): string =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '');

export function normalizeCategoryName(name: string): string {
  return stripAccents(String(name || '').trim().toLowerCase());
}

export function toSlug(name: string): string {
  return stripAccents(String(name || '').trim().toLowerCase())
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/canonical-mapping.spec.ts`
Expected: PASS — 2개.

- [ ] **Step 5: 시드 SQL 작성**

Create `api-ventago/migrations/2026-07-16-reseller-zona-seed.sql`. AR 24개 주 좌표 + canonical 은 운영 고유 카테고리명에서 도출 후 이름 exact-match 자동매핑:

```sql
-- =============================================================================
-- 시드: AR 주 중심좌표 + canonical 카테고리(운영 고유명) + 이름 자동매핑
-- 재실행 안전(ON CONFLICT DO NOTHING / 좌표는 갱신).
-- =============================================================================

-- 1) AR 24개 주 중심좌표 (이름으로 매칭. provinces.name 은 스페인어)
UPDATE public.provinces p SET lat = v.lat, lng = v.lng
  FROM (VALUES
    ('Buenos Aires', -36.6769, -60.5588),
    ('Ciudad Autónoma de Buenos Aires', -34.6037, -58.3816),
    ('Catamarca', -27.3359, -66.9478),
    ('Chaco', -26.3864, -60.7658),
    ('Chubut', -43.7886, -68.5266),
    ('Córdoba', -32.1421, -63.8010),
    ('Corrientes', -28.7743, -57.8012),
    ('Entre Ríos', -32.0589, -59.2013),
    ('Formosa', -24.8942, -59.9316),
    ('Jujuy', -23.3200, -65.7642),
    ('La Pampa', -37.1316, -65.4407),
    ('La Rioja', -29.7275, -67.1503),
    ('Mendoza', -34.6291, -68.5830),
    ('Misiones', -26.8753, -54.6516),
    ('Neuquén', -38.6425, -70.1181),
    ('Río Negro', -40.0000, -67.0000),
    ('Salta', -24.2991, -64.8144),
    ('San Juan', -30.8653, -68.8894),
    ('San Luis', -33.7577, -66.0281),
    ('Santa Cruz', -48.6152, -70.0000),
    ('Santa Fe', -30.7069, -60.9498),
    ('Santiago del Estero', -27.7844, -63.2520),
    ('Tierra del Fuego', -54.0000, -67.5000),
    ('Tucumán', -26.9478, -65.3647)
  ) AS v(name, lat, lng)
 WHERE p.name = v.name;

-- 2) canonical 카테고리 seed = 운영 categories 고유명(매핑 시작점).
--    이름 정규화(소문자·악센트제거)로 중복 병합. slug 은 앱과 동일 규칙.
INSERT INTO reseller.canonical_categories (name, slug)
SELECT DISTINCT ON (lower(unaccent_name))
       initcap(name) AS name,
       regexp_replace(unaccent_name, '[^a-z0-9]+', '-', 'g') AS slug
  FROM (
    SELECT name,
           lower(translate(name, 'áéíóúñÁÉÍÓÚÑ', 'aeiaunAEIOUN')) AS unaccent_name
      FROM public.categories
     WHERE name IS NOT NULL AND btrim(name) <> ''
  ) s
ON CONFLICT (name) DO NOTHING;

-- 3) 이름 exact-match 자동매핑: categories.canonical_category_id 채움
UPDATE public.categories c
   SET canonical_category_id = cc.id
  FROM reseller.canonical_categories cc
 WHERE c.canonical_category_id IS NULL
   AND lower(translate(c.name, 'áéíóúñÁÉÍÓÚÑ', 'aeiaunAEIOUN'))
     = lower(translate(cc.name, 'áéíóúñÁÉÍÓÚÑ', 'aeiaunAEIOUN'));

-- 4) 리포트
DO $$
DECLARE mapped INT; total INT; provloc INT;
BEGIN
  SELECT count(*) INTO mapped FROM public.categories WHERE canonical_category_id IS NOT NULL;
  SELECT count(*) INTO total  FROM public.categories;
  SELECT count(*) INTO provloc FROM public.provinces WHERE lat IS NOT NULL;
  RAISE NOTICE 'seed: canonical 매핑 % / % categories, 좌표 채운 주 %', mapped, total, provloc;
END $$;
```

> **주의(구현자):** `translate` 로 악센트 제거는 근사(운영에 `unaccent` extension 없을 수 있어 순정 SQL 사용). `initcap` 결과가 이상하면(예: 'Remera') seed 후 superadmin UI(Plan B Task)에서 병합·정정. slug UNIQUE 충돌 시 `DISTINCT ON`+`ON CONFLICT` 로 흡수.

- [ ] **Step 6: 로컬 적용 명령 사용자 전달**

```
psql -p 5432 -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/2026-07-16-reseller-zona-seed.sql
```
Expected NOTICE: 매핑 수 / 좌표 채운 주 24 근처. 운영은 배포 단계.

- [ ] **Step 7: 커밋**

```bash
cd api-ventago
git add migrations/2026-07-16-reseller-zona-seed.sql src/app/reseller/canonical-mapping.ts src/app/reseller/canonical-mapping.spec.ts
git commit -m "feat(reseller): 시드 — AR 24주 좌표 + canonical 카테고리 + 이름 자동매핑

provinces 중심좌표(GPS 최근접용), canonical_categories 를 운영 고유 카테고리명서
도출, categories.canonical_category_id 이름 exact-match 자동매핑. normalize/slug 순수함수."
```

---

### Task 4: ResellerStatsService — 집계 Cron (province_product_stats 선계산)

**Files:**
- Create: `api-ventago/src/app/reseller/reseller-stats.service.ts`
- Modify: `api-ventago/src/app/reseller/reseller.module.ts` (provider 등록)
- Test: `api-ventago/src/app/reseller/reseller-stats.service.spec.ts`

**Interfaces:**
- Consumes: `Sequelize`(raw query). Task 1 테이블.
- Produces:
  ```ts
  class ResellerStatsService {
    // 60일/이전60일 집계 → trend → rank → province_product_stats upsert. 겹침 방지.
    refreshStats(): Promise<{ rows: number }>;
  }
  ```
  Task 6/9 조회가 이 요약을 읽음.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/reseller-stats.service.spec.ts`:

```ts
import { ResellerStatsService } from './reseller-stats.service';

// refreshStats 는 단일 raw SQL(TRUNCATE+INSERT) 를 실행한다. sequelize.query mock 으로
// 호출·SQL 계약을 검증(실 집계 정확성은 통합/실데이터 UAT 에서).
describe('ResellerStatsService', () => {
  const makeSvc = () => {
    const sequelize = { query: jest.fn().mockResolvedValue([[], 12]) } as any;
    const svc: any = Object.create(ResellerStatsService.prototype);
    svc.sequelize = sequelize;
    svc.running = false;

    return { svc, sequelize };
  };

  it('refreshStats: 지역신호 COALESCE(sales.province_id, clients.province_id) 사용', async () => {
    const { svc, sequelize } = makeSvc();
    await svc.refreshStats();
    const sql = sequelize.query.mock.calls[0][0] as string;
    expect(sql).toMatch(/COALESCE\(s\.province_id,\s*c\.province_id\)/i);
    expect(sql).toMatch(/reseller\.province_product_stats/i);
  });

  it('refreshStats: 60일 + 이전 60일 윈도우 + trend + rank', async () => {
    const { svc, sequelize } = makeSvc();
    await svc.refreshStats();
    const sql = sequelize.query.mock.calls[0][0] as string;
    expect(sql).toMatch(/INTERVAL '60 days'/i);
    expect(sql).toMatch(/INTERVAL '120 days'/i);
    expect(sql).toMatch(/trend_pct/i);
    expect(sql).toMatch(/rank_in_prov/i);
    expect(sql).toMatch(/ROW_NUMBER\(\) OVER/i);
  });

  it('겹침 방지: 이미 실행중이면 skip', async () => {
    const { svc, sequelize } = makeSvc();
    svc.running = true;
    const r = await svc.refreshStats();
    expect(sequelize.query).not.toHaveBeenCalled();
    expect(r).toEqual({ rows: 0, skipped: true });
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/reseller-stats.service.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 서비스 구현**

Create `api-ventago/src/app/reseller/reseller-stats.service.ts`:

```ts
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes } from 'sequelize';
import { Sequelize } from 'sequelize-typescript';

// 지역×상품 추천 요약을 30분마다 선계산한다. 런타임 조회는 이 요약만 읽어 p95 300ms 준수.
// 지역신호 = COALESCE(sales.province_id, clients.province_id). 랭킹 = 60일 판매량에
// 상승세 가중: qty_60d * (1 + max(0,trend_pct)/100). 매장·지방·canonical_category 파티션.
@Injectable()
export class ResellerStatsService {
  private readonly logger = new Logger(ResellerStatsService.name);
  private running = false;

  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  @Cron(CronExpression.EVERY_30_MINUTES)
  async scheduledRefresh(): Promise<void> {
    await this.refreshStats();
  }

  async refreshStats(): Promise<{ rows: number; skipped?: boolean }> {
    // 겹침 방지 — 이전 실행이 안 끝났으면 skip (pool 낭비·중복 집계 방지)
    if (this.running) {
      this.logger.warn('[refreshStats] 이미 실행중 — skip');

      return { rows: 0, skipped: true };
    }
    this.running = true;
    try {
      // 단일 배치: 최근 120일 판매 라인 → 60d/prev-60d 분리 → trend → rank → 전체 교체.
      // TRUNCATE + INSERT 로 stale 제거(요약 테이블이라 안전). province/store/product UNIQUE.
      const sql = `
        TRUNCATE reseller.province_product_stats;
        WITH lines AS (
          SELECT COALESCE(s.province_id, c.province_id) AS province_id,
                 s.store_id,
                 si.product_id,
                 cat.canonical_category_id,
                 si.quantity,
                 s.created_at
            FROM sale_items si
            JOIN sales s        ON s.id = si.sale_id
            LEFT JOIN clients c ON c.id = s.client_id
            LEFT JOIN products p  ON p.id = si.product_id
            LEFT JOIN categories cat ON cat.id = p.category_id
           WHERE s.created_at > NOW() - INTERVAL '120 days'
             AND COALESCE(s.province_id, c.province_id) IS NOT NULL
             AND si.product_id IS NOT NULL
             AND s.store_id IS NOT NULL
        ),
        agg AS (
          SELECT province_id, store_id, product_id,
                 max(canonical_category_id) AS canonical_category_id,
                 SUM(quantity) FILTER (WHERE created_at > NOW() - INTERVAL '60 days')  AS qty_60d,
                 SUM(quantity) FILTER (WHERE created_at <= NOW() - INTERVAL '60 days') AS qty_prev_60d
            FROM lines
           GROUP BY province_id, store_id, product_id
        ),
        scored AS (
          SELECT province_id, store_id, product_id, canonical_category_id,
                 COALESCE(qty_60d,0)      AS qty_60d,
                 COALESCE(qty_prev_60d,0) AS qty_prev_60d,
                 CASE WHEN COALESCE(qty_prev_60d,0) = 0 THEN NULL
                      ELSE round((qty_60d - qty_prev_60d)::numeric / qty_prev_60d * 100, 1)
                 END AS trend_pct,
                 COALESCE(qty_60d,0)
                   * (1 + GREATEST(0, (qty_60d - COALESCE(qty_prev_60d,0)))::numeric
                          / NULLIF(COALESCE(qty_prev_60d,0),0)) AS score
            FROM agg
           WHERE COALESCE(qty_60d,0) > 0
        ),
        ranked AS (
          SELECT *, ROW_NUMBER() OVER (
                      PARTITION BY province_id, store_id
                      ORDER BY score DESC NULLS LAST, qty_60d DESC
                    ) AS rank_in_prov
            FROM scored
        )
        INSERT INTO reseller.province_product_stats
          (province_id, store_id, canonical_category_id, product_id,
           qty_60d, qty_prev_60d, trend_pct, rank_in_prov, refreshed_at)
        SELECT province_id, store_id, canonical_category_id, product_id,
               qty_60d, qty_prev_60d, trend_pct, rank_in_prov, NOW()
          FROM ranked;
      `;
      await this.sequelize.query(sql, { type: QueryTypes.RAW });
      const [cnt] = (await this.sequelize.query(
        'SELECT count(*)::int AS n FROM reseller.province_product_stats',
        { type: QueryTypes.SELECT },
      )) as Array<{ n: number }>;
      this.logger.log(`[refreshStats] 완료 — ${cnt?.n ?? 0} 행`);

      return { rows: cnt?.n ?? 0 };
    } finally {
      this.running = false;
    }
  }
}
```

> **주의(구현자):** `score` 의 NULLIF(prev,0) 이 NULL 이면(신규 상품, prev=0) `1 + x/NULL = NULL` → `COALESCE(...NULL) `가 아니라 곱이 NULL 이 되어 rank 밀림. 신규 상품을 살리려면 score COALESCE 처리: 위 `scored.score` 를 `COALESCE( qty_60d * (1 + GREATEST(0, qty_60d - qty_prev_60d)::numeric / NULLIF(qty_prev_60d,0)), qty_60d )` 로 감싼다. Step 3 구현 시 이 COALESCE 를 포함할 것.

`reseller.module.ts` `providers` 에 `ResellerStatsService` 추가 + `exports` 에도(Task 6 재사용). `@nestjs/schedule` `ScheduleModule` 이 앱에 이미 등록됐는지 확인(`app.module.ts` — 기존 Cron 있으므로 등록됨).

- [ ] **Step 4: 구현 보정 (신규상품 score COALESCE)**

Step 3 `scored` 의 `score` 식을 다음으로 확정:
```sql
COALESCE(
  qty_60d * (1 + GREATEST(0,(qty_60d - COALESCE(qty_prev_60d,0)))::numeric
                 / NULLIF(COALESCE(qty_prev_60d,0),0)),
  qty_60d
) AS score
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/reseller-stats.service.spec.ts`
Expected: PASS — 3개.

- [ ] **Step 6: 커밋**

```bash
cd api-ventago
git add src/app/reseller/reseller-stats.service.ts src/app/reseller/reseller-stats.service.spec.ts src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): 지역×상품 집계 Cron (province_product_stats 선계산)

30분 주기. COALESCE(sales.province_id, clients.province_id), 60d/prev-60d,
trend_pct, 상승세 가중 score 로 지방·매장 파티션 rank. 겹침 방지 가드. TRUNCATE+INSERT."
```

---

### Task 5: reseller 인증 (JWT 전략 + 가드) + 허가 헬퍼

**Files:**
- Create: `api-ventago/src/app/reseller/auth/reseller-jwt.strategy.ts`
- Create: `api-ventago/src/app/reseller/auth/reseller-auth.guard.ts`
- Create: `api-ventago/src/app/reseller/auth/reseller-auth.service.ts`
- Create: `api-ventago/src/app/reseller/auth/reseller-auth.controller.ts`
- Create: `api-ventago/src/app/reseller/auth/dto/reseller-login.dto.ts`
- Modify: `api-ventago/src/app/reseller/reseller.module.ts`
- Test: `api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts`

**Interfaces:**
- Consumes: Task 2 `Reseller` 모델, `JwtService`, bcrypt.
- Produces:
  ```ts
  // payload.type === 'reseller' 로 user JWT 와 구분. req.user = Reseller 인스턴스.
  class ResellerAuthGuard {}  // @UseGuards(ResellerAuthGuard)
  class ResellerAuthService {
    login(dto): Promise<{ token: string; reseller: {...} }>;
    validate(payload): Promise<Reseller>;  // 전략이 호출
  }
  ```
  Task 6/7/8 가 `@UseGuards(ResellerAuthGuard)` + `@GetReseller()`.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts`:

```ts
import { UnauthorizedException } from '@nestjs/common';
import { ResellerAuthService } from './reseller-auth.service';
import * as bcrypt from 'bcrypt';

describe('ResellerAuthService.login', () => {
  const makeSvc = (reseller: any) => {
    const resellerModel = { findOne: jest.fn().mockResolvedValue(reseller) } as any;
    const jwt = { sign: jest.fn().mockReturnValue('TOKEN') } as any;
    const svc: any = Object.create(ResellerAuthService.prototype);
    svc.resellerModel = resellerModel;
    svc.jwt = jwt;

    return { svc, jwt };
  };

  it('올바른 자격 → token + type reseller payload', async () => {
    const hash = await bcrypt.hash('secret', 10);
    const { svc, jwt } = makeSvc({ id: 5, email: 'a@b.com', name: 'R', password: hash, isActive: true });
    const r = await svc.login({ emailOrDocument: 'a@b.com', password: 'secret' });
    expect(r.token).toBe('TOKEN');
    expect(jwt.sign).toHaveBeenCalledWith(expect.objectContaining({ sub: 5, type: 'reseller' }));
  });

  it('비번 불일치 → Unauthorized', async () => {
    const hash = await bcrypt.hash('secret', 10);
    const { svc } = makeSvc({ id: 5, password: hash, isActive: true });
    await expect(svc.login({ emailOrDocument: 'a@b.com', password: 'WRONG' }))
      .rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('비활성 reseller → Unauthorized', async () => {
    const hash = await bcrypt.hash('secret', 10);
    const { svc } = makeSvc({ id: 5, password: hash, isActive: false });
    await expect(svc.login({ emailOrDocument: 'a@b.com', password: 'secret' }))
      .rejects.toBeInstanceOf(UnauthorizedException);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/auth/reseller-auth.service.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 구현**

Create `api-ventago/src/app/reseller/auth/dto/reseller-login.dto.ts`:

```ts
import { IsNotEmpty, IsString } from 'class-validator';

export class ResellerLoginDto {
  // email 또는 document 로 로그인
  @IsString()
  @IsNotEmpty()
  readonly emailOrDocument: string;

  @IsString()
  @IsNotEmpty()
  readonly password: string;
}
```

Create `api-ventago/src/app/reseller/auth/reseller-auth.service.ts`:

```ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { JwtService } from '@nestjs/jwt';
import { Op } from 'sequelize';
import * as bcrypt from 'bcrypt';
import { Reseller } from '../reseller.model';
import { ResellerLoginDto } from './dto/reseller-login.dto';

// 재판매자 인증 — user JWT 와 분리. payload.type='reseller'.
@Injectable()
export class ResellerAuthService {
  constructor(
    @InjectModel(Reseller) private readonly resellerModel: typeof Reseller,
    private readonly jwt: JwtService,
  ) {}

  async login(dto: ResellerLoginDto): Promise<{ token: string; reseller: any }> {
    const reseller: any = await this.resellerModel.findOne({
      where: { [Op.or]: [{ email: dto.emailOrDocument }, { document: dto.emailOrDocument }] },
    });
    if (!reseller || !reseller.isActive || !reseller.password) {
      throw new UnauthorizedException('Credenciales inválidas');
    }
    const ok = await bcrypt.compare(dto.password, reseller.password);
    if (!ok) {
      throw new UnauthorizedException('Credenciales inválidas');
    }
    const token = this.jwt.sign({ sub: reseller.id, type: 'reseller' });

    return {
      token,
      reseller: { id: reseller.id, name: reseller.name, provinceId: reseller.provinceId },
    };
  }

  async validate(payload: { sub: number; type: string }): Promise<Reseller> {
    if (payload?.type !== 'reseller') {
      throw new UnauthorizedException();
    }
    const reseller = await this.resellerModel.findByPk(payload.sub);
    if (!reseller || !(reseller as any).isActive) {
      throw new UnauthorizedException();
    }

    return reseller;
  }
}
```

Create `api-ventago/src/app/reseller/auth/reseller-jwt.strategy.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { ResellerAuthService } from './reseller-auth.service';

// 기존 user JWT 와 같은 시크릿, payload.type 으로 구분(legacy revendedor 전략과 동일 패턴).
@Injectable()
export class ResellerJwtStrategy extends PassportStrategy(Strategy, 'reseller-jwt') {
  constructor(cfg: ConfigService, private readonly authService: ResellerAuthService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: cfg.get<string>('JWT_SECRET_KEY'),
    });
  }

  async validate(payload: { sub: number; type: string }) {
    return this.authService.validate(payload);
  }
}
```

Create `api-ventago/src/app/reseller/auth/reseller-auth.guard.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class ResellerAuthGuard extends AuthGuard('reseller-jwt') {}
```

`@GetReseller()` 데코레이터 — Create `api-ventago/src/app/reseller/auth/get-reseller.decorator.ts`:

```ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const GetReseller = createParamDecorator((_data, ctx: ExecutionContext) => {
  return ctx.switchToHttp().getRequest().user;
});
```

Create `api-ventago/src/app/reseller/auth/reseller-auth.controller.ts`:

```ts
import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ResellerAuthService } from './reseller-auth.service';
import { ResellerLoginDto } from './dto/reseller-login.dto';
import { ResellerAuthGuard } from './reseller-auth.guard';
import { GetReseller } from './get-reseller.decorator';
import { Reseller } from '../reseller.model';

@Controller('reseller/auth')
export class ResellerAuthController {
  constructor(private readonly authService: ResellerAuthService) {}

  @Post('login')
  async login(@Body() dto: ResellerLoginDto) {
    return this.authService.login(dto);
  }

  @Get('me')
  @UseGuards(ResellerAuthGuard)
  me(@GetReseller() reseller: Reseller) {
    const r: any = reseller;

    return { id: r.id, name: r.name, provinceId: r.provinceId, provinceSource: r.provinceSource };
  }
}
```

`reseller.module.ts`: `JwtModule`(기존 설정 재사용 — `auth.module` 패턴 참조), `PassportModule` import. providers 에 `ResellerAuthService`, `ResellerJwtStrategy`. controllers 에 `ResellerAuthController`. exports 에 `ResellerAuthService`.

> **주의(구현자):** JWT 시크릿·만료는 기존 `auth.module.ts` 의 `JwtModule.registerAsync` 설정과 동일하게 구성한다. `JWT_SECRET_KEY` env 명칭은 기존 코드에서 확인(`api-ventago/src/app/auth/`).

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/auth/reseller-auth.service.spec.ts`
Expected: PASS — 3개.

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/reseller/auth/
git add src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): reseller JWT 인증(전략/가드/서비스/컨트롤러)

payload.type='reseller' 로 user JWT 와 분리. login(email|document)+me. bcrypt."
```

---

### Task 6: 추천 조회 서비스 + 컨트롤러 (/reseller/recommendations, stock-gap, POST)

**Files:**
- Create: `api-ventago/src/app/reseller/recommendation/reseller-recommendation.service.ts`
- Create: `api-ventago/src/app/reseller/recommendation/reseller-recommendation.controller.ts`
- Modify: `api-ventago/src/app/reseller/reseller.module.ts`
- Test: `api-ventago/src/app/reseller/recommendation/reseller-recommendation.service.spec.ts`

**Interfaces:**
- Consumes: Task 2 모델, Task 4 요약 테이블, Task 5 가드.
- Produces:
  ```ts
  class ResellerRecommendationService {
    // reseller 지방 top-N (허가매장 한정). 지역 데이터 없으면 매장 전체 베스트셀러 폴백.
    zoneTop(resellerId: number, canonicalCategoryId?: number): Promise<RecItem[]>;
    // 지방 인기인데 허가매장 재고 0
    stockGap(resellerId: number): Promise<RecItem[]>;
    logRecommendation(resellerId, dto): Promise<{ id: number }>;
  }
  // RecItem = { productId, name, sku, storeId, storeName, price, inStock, qty60d, trendPct, rank }
  ```

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/recommendation/reseller-recommendation.service.spec.ts`:

```ts
import { ResellerRecommendationService } from './reseller-recommendation.service';

describe('ResellerRecommendationService', () => {
  const makeSvc = (opts: { reseller?: any; queryRows?: any[][] }) => {
    const calls: any[] = [];
    const sequelize = {
      query: jest.fn().mockImplementation((sql: string) => {
        calls.push(sql);
        const idx = calls.length - 1;

        return Promise.resolve((opts.queryRows ?? [[]])[idx] ?? []);
      }),
    } as any;
    const resellerModel = { findByPk: jest.fn().mockResolvedValue(opts.reseller ?? { id: 1, provinceId: 3 }) } as any;
    const svc: any = Object.create(ResellerRecommendationService.prototype);
    svc.sequelize = sequelize;
    svc.resellerModel = resellerModel;

    return { svc, sequelize, calls };
  };

  it('zoneTop: reseller 지방 + 허가매장(approved) 조인, 요약 테이블 조회', async () => {
    const { svc, calls } = makeSvc({
      reseller: { id: 1, provinceId: 3 },
      queryRows: [[{ product_id: 10, name: 'Remera', store_id: 9, qty_60d: 96, rank_in_prov: 1 }]],
    });
    const rows = await svc.zoneTop(1);
    expect(calls[0]).toMatch(/province_product_stats/i);
    expect(calls[0]).toMatch(/reseller_tienda_link/i);
    expect(calls[0]).toMatch(/status = 'approved'/i);
    expect(rows[0].productId).toBe(10);
  });

  it('zoneTop: reseller.provinceId 없으면 빈 배열(지방 미설정)', async () => {
    const { svc } = makeSvc({ reseller: { id: 1, provinceId: null } });
    const rows = await svc.zoneTop(1);
    expect(rows).toEqual([]);
  });

  it('stockGap: 재고 0 필터 조건 포함', async () => {
    const { svc, calls } = makeSvc({
      reseller: { id: 1, provinceId: 3 },
      queryRows: [[{ product_id: 20, store_id: 9 }]],
    });
    await svc.stockGap(1);
    expect(calls[0]).toMatch(/COALESCE\(st\.stock,\s*0\)\s*=\s*0|stock.*0/i);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/recommendation/reseller-recommendation.service.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 서비스 구현**

Create `api-ventago/src/app/reseller/recommendation/reseller-recommendation.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectConnection, InjectModel } from '@nestjs/sequelize';
import { QueryTypes } from 'sequelize';
import { Sequelize } from 'sequelize-typescript';
import { Reseller } from '../reseller.model';
import { StoreRecommendation } from '../store-recommendation.model';

export interface RecItem {
  productId: number;
  name: string;
  sku: string;
  storeId: number;
  storeName: string;
  price: number;
  inStock: boolean;
  qty60d: number;
  trendPct: number | null;
  rank: number;
}

@Injectable()
export class ResellerRecommendationService {
  constructor(
    @InjectConnection() private readonly sequelize: Sequelize,
    @InjectModel(Reseller) private readonly resellerModel: typeof Reseller,
    @InjectModel(StoreRecommendation) private readonly recModel: typeof StoreRecommendation,
  ) {}

  // reseller 홈 지방 + 허가매장(approved) 상품 랭킹. 요약 테이블만 조회.
  async zoneTop(resellerId: number, canonicalCategoryId?: number): Promise<RecItem[]> {
    const reseller: any = await this.resellerModel.findByPk(resellerId);
    if (!reseller?.provinceId) {
      return [];
    }
    const rows = await this.sequelize.query(
      `
      SELECT pps.product_id, p.name, p.sku, pps.store_id, st.name AS store_name,
             p.price, (COALESCE(stk.stock,0) > 0) AS in_stock,
             pps.qty_60d, pps.trend_pct, pps.rank_in_prov
        FROM reseller.province_product_stats pps
        JOIN reseller.reseller_tienda_link rtl
          ON rtl.store_id = pps.store_id AND rtl.reseller_id = :resellerId AND rtl.status = 'approved'
        JOIN products p ON p.id = pps.product_id
        JOIN stores  st ON st.id = pps.store_id
        LEFT JOIN stocks stk ON stk.product_id = p.id AND stk.is_active = true
       WHERE pps.province_id = :provinceId
         AND (:canonicalCategoryId::int IS NULL OR pps.canonical_category_id = :canonicalCategoryId)
       ORDER BY pps.rank_in_prov ASC
       LIMIT 30;
      `,
      {
        replacements: {
          resellerId,
          provinceId: reseller.provinceId,
          canonicalCategoryId: canonicalCategoryId ?? null,
        },
        type: QueryTypes.SELECT,
      },
    );

    // 지역 데이터 없음 → 매장 전체 베스트셀러 폴백
    if (rows.length === 0) {
      return this.storeFallback(resellerId, canonicalCategoryId);
    }

    return (rows as any[]).map(this.toItem);
  }

  // 지방 인기(요약)인데 허가매장 재고 0 → 그 매장에 추천
  async stockGap(resellerId: number): Promise<RecItem[]> {
    const reseller: any = await this.resellerModel.findByPk(resellerId);
    if (!reseller?.provinceId) {
      return [];
    }
    const rows = await this.sequelize.query(
      `
      SELECT pps.product_id, p.name, p.sku, rtl.store_id, st.name AS store_name,
             p.price, false AS in_stock, pps.qty_60d, pps.trend_pct, pps.rank_in_prov
        FROM reseller.province_product_stats pps
        JOIN reseller.reseller_tienda_link rtl
          ON rtl.reseller_id = :resellerId AND rtl.status = 'approved'
        JOIN products p ON p.id = pps.product_id
        JOIN stores  st ON st.id = rtl.store_id
        LEFT JOIN stocks stk ON stk.product_id = p.id AND stk.is_active = true
       WHERE pps.province_id = :provinceId
       GROUP BY pps.product_id, p.name, p.sku, rtl.store_id, st.name, p.price,
                pps.qty_60d, pps.trend_pct, pps.rank_in_prov
      HAVING COALESCE(SUM(stk.stock) FILTER (WHERE stk.store_id = rtl.store_id), 0) = 0
       ORDER BY pps.rank_in_prov ASC
       LIMIT 30;
      `,
      { replacements: { resellerId, provinceId: reseller.provinceId }, type: QueryTypes.SELECT },
    );

    return (rows as any[]).map(this.toItem);
  }

  async logRecommendation(
    resellerId: number,
    dto: { storeId: number; productId: number; provinceId?: number; reason: string; note?: string },
  ): Promise<{ id: number }> {
    const rec = await this.recModel.create({
      resellerId,
      storeId: dto.storeId,
      productId: dto.productId,
      provinceId: dto.provinceId ?? null,
      reason: dto.reason,
      note: dto.note ?? null,
    } as any);

    return { id: (rec as any).id };
  }

  private async storeFallback(resellerId: number, canonicalCategoryId?: number): Promise<RecItem[]> {
    const rows = await this.sequelize.query(
      `
      SELECT pps.product_id, p.name, p.sku, pps.store_id, st.name AS store_name,
             p.price, (COALESCE(stk.stock,0) > 0) AS in_stock,
             SUM(pps.qty_60d) AS qty_60d, NULL::numeric AS trend_pct,
             ROW_NUMBER() OVER (ORDER BY SUM(pps.qty_60d) DESC) AS rank_in_prov
        FROM reseller.province_product_stats pps
        JOIN reseller.reseller_tienda_link rtl
          ON rtl.store_id = pps.store_id AND rtl.reseller_id = :resellerId AND rtl.status = 'approved'
        JOIN products p ON p.id = pps.product_id
        JOIN stores  st ON st.id = pps.store_id
        LEFT JOIN stocks stk ON stk.product_id = p.id AND stk.is_active = true
       WHERE (:canonicalCategoryId::int IS NULL OR pps.canonical_category_id = :canonicalCategoryId)
       GROUP BY pps.product_id, p.name, p.sku, pps.store_id, st.name, p.price, stk.stock
       ORDER BY qty_60d DESC
       LIMIT 30;
      `,
      { replacements: { resellerId, canonicalCategoryId: canonicalCategoryId ?? null }, type: QueryTypes.SELECT },
    );

    return (rows as any[]).map(this.toItem);
  }

  private toItem(r: any): RecItem {
    return {
      productId: r.product_id,
      name: r.name,
      sku: r.sku,
      storeId: r.store_id,
      storeName: r.store_name,
      price: Number(r.price),
      inStock: r.in_stock === true,
      qty60d: Number(r.qty_60d),
      trendPct: r.trend_pct == null ? null : Number(r.trend_pct),
      rank: Number(r.rank_in_prov),
    };
  }
}
```

> **주의(구현자):** `stocks` 테이블에 `store_id` 컬럼이 있는지 스키마 확인(`.planning/intel/db-schema-tables.md` `stocks`). 없으면 재고→매장 도달 경로를 확인(product→store, 또는 stock→branch→store)해 `stockGap`/`in_stock` 의 store 필터를 그 경로로 교정한다. 이는 stock 스키마 확인 후 확정.

Create `api-ventago/src/app/reseller/recommendation/reseller-recommendation.controller.ts`:

```ts
import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { ResellerRecommendationService } from './reseller-recommendation.service';
import { ResellerAuthGuard } from '../auth/reseller-auth.guard';
import { GetReseller } from '../auth/get-reseller.decorator';

@Controller('reseller/recommendations')
@UseGuards(ResellerAuthGuard)
export class ResellerRecommendationController {
  constructor(private readonly service: ResellerRecommendationService) {}

  @Get()
  zoneTop(@GetReseller() reseller: any, @Query('canonicalCategoryId') cat?: string) {
    return this.service.zoneTop(reseller.id, cat ? Number(cat) : undefined);
  }

  @Get('stock-gap')
  stockGap(@GetReseller() reseller: any) {
    return this.service.stockGap(reseller.id);
  }

  @Post()
  log(
    @GetReseller() reseller: any,
    @Body() dto: { storeId: number; productId: number; provinceId?: number; reason: string; note?: string },
  ) {
    return this.service.logRecommendation(reseller.id, dto);
  }
}
```

`reseller.module.ts`: providers `ResellerRecommendationService`, controllers `ResellerRecommendationController`.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/recommendation/reseller-recommendation.service.spec.ts`
Expected: PASS — 3개.

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/reseller/recommendation/ src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): 추천 조회 API — zoneTop/stockGap/log

reseller 홈 지방 + 허가매장 요약 랭킹, 지역 데이터 없으면 매장 베스트셀러 폴백.
cross-store 재고 갭. 추천 로그. 요약 테이블만 조회(p95 준수)."
```

---

### Task 7: 통합 카탈로그 API (/reseller/catalog, /reseller/canonical-categories)

**Files:**
- Create: `api-ventago/src/app/reseller/catalog/reseller-catalog.service.ts`
- Create: `api-ventago/src/app/reseller/catalog/reseller-catalog.controller.ts`
- Modify: `api-ventago/src/app/reseller/reseller.module.ts`
- Test: `api-ventago/src/app/reseller/catalog/reseller-catalog.service.spec.ts`

**Interfaces:**
- Consumes: Task 2 모델, Task 5 가드.
- Produces:
  ```ts
  class ResellerCatalogService {
    // 허가매장(approved) × canonical_category 필터. inStock boolean. pageSize ≤ 50.
    catalog(resellerId, opts: { canonicalCategoryId?; storeId?; search?; page? }): Promise<{ items: RecItem[]; page; total }>;
    canonicalCategories(resellerId): Promise<{ id; name; slug; hotCount }[]>;
  }
  ```

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/catalog/reseller-catalog.service.spec.ts`:

```ts
import { ResellerCatalogService } from './reseller-catalog.service';

describe('ResellerCatalogService.catalog', () => {
  const makeSvc = (rows: any[]) => {
    const sequelize = { query: jest.fn().mockResolvedValue(rows) } as any;
    const svc: any = Object.create(ResellerCatalogService.prototype);
    svc.sequelize = sequelize;

    return { svc, sequelize };
  };

  it('허가매장(approved) + canonical_category 필터, inStock boolean', async () => {
    const { svc, sequelize } = makeSvc([{ product_id: 1, name: 'X', in_stock: true }]);
    await svc.catalog(7, { canonicalCategoryId: 2, page: 1 });
    const sql = sequelize.query.mock.calls[0][0] as string;
    expect(sql).toMatch(/reseller_tienda_link/i);
    expect(sql).toMatch(/status = 'approved'/i);
    expect(sql).toMatch(/canonical_category_id/i);
    expect(sql).toMatch(/> 0\) AS in_stock|in_stock/i);
  });

  it('pageSize 는 50 이하로 강제', async () => {
    const { svc, sequelize } = makeSvc([]);
    await svc.catalog(7, { page: 1 });
    const opts = sequelize.query.mock.calls[0][1];
    expect(opts.replacements.limit).toBeLessThanOrEqual(50);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/catalog/reseller-catalog.service.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 구현**

Create `api-ventago/src/app/reseller/catalog/reseller-catalog.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes } from 'sequelize';
import { Sequelize } from 'sequelize-typescript';

const PAGE_SIZE = 50;

@Injectable()
export class ResellerCatalogService {
  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  async catalog(
    resellerId: number,
    opts: { canonicalCategoryId?: number; storeId?: number; search?: string; page?: number },
  ): Promise<{ items: any[]; page: number; pageSize: number }> {
    const page = Math.max(1, Number(opts.page) || 1);
    const limit = PAGE_SIZE;
    const offset = (page - 1) * limit;
    const rows = await this.sequelize.query(
      `
      SELECT p.id AS product_id, p.name, p.sku, p.price,
             p.store_id, st.name AS store_name, c.canonical_category_id,
             (COALESCE(stk.stock,0) > 0) AS in_stock
        FROM reseller.reseller_tienda_link rtl
        JOIN products p ON p.store_id = rtl.store_id AND p.is_active = true AND p.is_parent = true
        JOIN stores  st ON st.id = rtl.store_id
        LEFT JOIN categories c ON c.id = p.category_id
        LEFT JOIN stocks stk ON stk.product_id = p.id AND stk.is_active = true
       WHERE rtl.reseller_id = :resellerId AND rtl.status = 'approved'
         AND c.canonical_category_id IS NOT NULL
         AND (:canonicalCategoryId::int IS NULL OR c.canonical_category_id = :canonicalCategoryId)
         AND (:storeId::int IS NULL OR rtl.store_id = :storeId)
         AND (:search::text IS NULL OR p.name ILIKE '%' || :search || '%' OR p.sku ILIKE '%' || :search || '%')
       ORDER BY p.name ASC
       LIMIT :limit OFFSET :offset;
      `,
      {
        replacements: {
          resellerId,
          canonicalCategoryId: opts.canonicalCategoryId ?? null,
          storeId: opts.storeId ?? null,
          search: opts.search ?? null,
          limit,
          offset,
        },
        type: QueryTypes.SELECT,
      },
    );

    return { items: rows as any[], page, pageSize: limit };
  }

  // TIPO 탭 — 허가매장에 매핑된 canonical 카테고리 + zona hot 갯수(요약 기반)
  async canonicalCategories(resellerId: number): Promise<any[]> {
    const rows = await this.sequelize.query(
      `
      SELECT DISTINCT cc.id, cc.name, cc.slug, cc.sort_order
        FROM reseller.reseller_tienda_link rtl
        JOIN products p ON p.store_id = rtl.store_id AND p.is_active = true
        JOIN categories c ON c.id = p.category_id
        JOIN reseller.canonical_categories cc ON cc.id = c.canonical_category_id
       WHERE rtl.reseller_id = :resellerId AND rtl.status = 'approved' AND cc.is_active = true
       ORDER BY cc.sort_order, cc.name;
      `,
      { replacements: { resellerId }, type: QueryTypes.SELECT },
    );

    return rows as any[];
  }
}
```

Create `api-ventago/src/app/reseller/catalog/reseller-catalog.controller.ts`:

```ts
import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ResellerCatalogService } from './reseller-catalog.service';
import { ResellerAuthGuard } from '../auth/reseller-auth.guard';
import { GetReseller } from '../auth/get-reseller.decorator';

@Controller('reseller')
@UseGuards(ResellerAuthGuard)
export class ResellerCatalogController {
  constructor(private readonly service: ResellerCatalogService) {}

  @Get('catalog')
  catalog(
    @GetReseller() reseller: any,
    @Query('canonicalCategoryId') cat?: string,
    @Query('storeId') storeId?: string,
    @Query('search') search?: string,
    @Query('page') page?: string,
  ) {
    return this.service.catalog(reseller.id, {
      canonicalCategoryId: cat ? Number(cat) : undefined,
      storeId: storeId ? Number(storeId) : undefined,
      search: search || undefined,
      page: page ? Number(page) : 1,
    });
  }

  @Get('canonical-categories')
  categories(@GetReseller() reseller: any) {
    return this.service.canonicalCategories(reseller.id);
  }
}
```

`reseller.module.ts`: providers/controllers 등록.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/catalog/reseller-catalog.service.spec.ts`
Expected: PASS — 2개.

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/reseller/catalog/ src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): 통합 카탈로그 API — 허가매장 × canonical + TIPO 탭

catalog(허가매장 approved, canonical 필터, search, inStock boolean, pageSize 50) +
canonical-categories(TIPO 탭). 재고 정확수량 비공개."
```

---

### Task 8: GPS 지역감지 (/reseller/detect-province)

**Files:**
- Create: `api-ventago/src/app/reseller/geo/nearest-province.ts` (순수 함수)
- Create: `api-ventago/src/app/reseller/geo/reseller-geo.service.ts`
- Create: `api-ventago/src/app/reseller/geo/reseller-geo.controller.ts`
- Modify: `api-ventago/src/app/reseller/reseller.module.ts`
- Test: `api-ventago/src/app/reseller/geo/nearest-province.spec.ts`

**Interfaces:**
- Consumes: Task 1 `provinces.lat/lng`, Task 2 `Reseller`.
- Produces:
  ```ts
  nearestProvince(lat, lng, provinces: {id;lat;lng}[]): number | null;  // 순수
  class ResellerGeoService { detectAndSave(resellerId, lat, lng): Promise<{ provinceId; name }>; }
  ```

- [ ] **Step 1: 순수 함수 실패 테스트**

Create `api-ventago/src/app/reseller/geo/nearest-province.spec.ts`:

```ts
import { nearestProvince } from './nearest-province';

const provs = [
  { id: 1, lat: -34.60, lng: -58.38 }, // CABA
  { id: 2, lat: -31.42, lng: -64.18 }, // Córdoba
  { id: 3, lat: -32.89, lng: -68.85 }, // Mendoza
];

describe('nearestProvince', () => {
  it('CABA 근처 좌표 → id 1', () => {
    expect(nearestProvince(-34.55, -58.45, provs)).toBe(1);
  });

  it('Mendoza 근처 → id 3', () => {
    expect(nearestProvince(-32.9, -68.8, provs)).toBe(3);
  });

  it('좌표 없는(빈) provinces → null', () => {
    expect(nearestProvince(-34, -58, [])).toBeNull();
  });

  it('lat/lng 누락 provinces 는 건너뜀', () => {
    expect(nearestProvince(-31.4, -64.2, [{ id: 9, lat: null as any, lng: null as any }, ...provs])).toBe(2);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/geo/nearest-province.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 구현**

Create `api-ventago/src/app/reseller/geo/nearest-province.ts`:

```ts
// GPS 좌표 → 가장 가까운 province.id (하버사인 근사). AR 24개 주라 무차별대입 OK.
interface ProvPoint {
  id: number;
  lat: number | null;
  lng: number | null;
}

const toRad = (d: number): number => (d * Math.PI) / 180;

function haversine(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;

  return 2 * R * Math.asin(Math.sqrt(s));
}

export function nearestProvince(lat: number, lng: number, provinces: ProvPoint[]): number | null {
  let best: number | null = null;
  let bestDist = Infinity;
  for (const p of provinces) {
    if (p.lat == null || p.lng == null) {
      continue;
    }
    const d = haversine(lat, lng, Number(p.lat), Number(p.lng));
    if (d < bestDist) {
      bestDist = d;
      best = p.id;
    }
  }

  return best;
}
```

Create `api-ventago/src/app/reseller/geo/reseller-geo.service.ts`:

```ts
import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectConnection, InjectModel } from '@nestjs/sequelize';
import { QueryTypes } from 'sequelize';
import { Sequelize } from 'sequelize-typescript';
import { Reseller } from '../reseller.model';
import { nearestProvince } from './nearest-province';

@Injectable()
export class ResellerGeoService {
  constructor(
    @InjectConnection() private readonly sequelize: Sequelize,
    @InjectModel(Reseller) private readonly resellerModel: typeof Reseller,
  ) {}

  // GPS → 최근접 province → reseller.province_id 저장(source='gps').
  async detectAndSave(resellerId: number, lat: number, lng: number): Promise<{ provinceId: number; name: string }> {
    if (typeof lat !== 'number' || typeof lng !== 'number' || Number.isNaN(lat) || Number.isNaN(lng)) {
      throw new BadRequestException('Coordenadas inválidas');
    }
    const provinces = (await this.sequelize.query(
      'SELECT id, lat, lng, name FROM provinces WHERE lat IS NOT NULL AND lng IS NOT NULL',
      { type: QueryTypes.SELECT },
    )) as Array<{ id: number; lat: number; lng: number; name: string }>;
    const provinceId = nearestProvince(lat, lng, provinces);
    if (!provinceId) {
      throw new BadRequestException('No se pudo determinar la provincia');
    }
    await this.resellerModel.update(
      { provinceId, provinceSource: 'gps' } as any,
      { where: { id: resellerId } },
    );
    const found = provinces.find((p) => p.id === provinceId)!;

    return { provinceId, name: found.name };
  }
}
```

Create `api-ventago/src/app/reseller/geo/reseller-geo.controller.ts`:

```ts
import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { ResellerGeoService } from './reseller-geo.service';
import { ResellerAuthGuard } from '../auth/reseller-auth.guard';
import { GetReseller } from '../auth/get-reseller.decorator';

@Controller('reseller')
@UseGuards(ResellerAuthGuard)
export class ResellerGeoController {
  constructor(private readonly service: ResellerGeoService) {}

  @Post('detect-province')
  detect(@GetReseller() reseller: any, @Body() dto: { lat: number; lng: number }) {
    return this.service.detectAndSave(reseller.id, dto.lat, dto.lng);
  }
}
```

`reseller.module.ts`: providers/controllers 등록.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/geo/nearest-province.spec.ts`
Expected: PASS — 4개.

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/reseller/geo/ src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): GPS 지역감지 — provinces 최근접 매핑

detect-province(lat,lng) → 하버사인 최근접 province → reseller.province_id 저장
(source=gps). 외부 지오코딩 없이 오프라인, pool 무부하."
```

---

### Task 9: vendedor 내부 추천 API (/mobile/recommended-products) + 판매 provincia 캡처

**Files:**
- Create: `api-ventago/src/app/reseller/mobile/mobile-recommendation.service.ts`
- Create: `api-ventago/src/app/reseller/mobile/mobile-recommendation.controller.ts`
- Modify: `api-ventago/src/app/sales/dto/create-sale.dto.ts` (`provinceId?`)
- Modify: `api-ventago/src/app/sales/sales.service.ts` (판매 생성 시 `province_id` 저장)
- Modify: `api-ventago/src/app/reseller/reseller.module.ts`
- Test: `api-ventago/src/app/reseller/mobile/mobile-recommendation.service.spec.ts`
- Test: `api-ventago/src/app/sales/sales.service.spec.ts` (provincia 저장 describe 추가)

**Interfaces:**
- Consumes: Task 4 요약 테이블. **user(vendedor) JWT** (reseller JWT 아님) — 기존 `@Auth()` + store 스코프.
- Produces:
  ```ts
  class MobileRecommendationService {
    // vendedor 매장 재고>0 인 지역 베스트셀러. provinceId 없으면 매장 베스트셀러.
    recommendedProducts(storeId: number, provinceId?: number): Promise<RecItem[]>;
  }
  ```

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/mobile/mobile-recommendation.service.spec.ts`:

```ts
import { MobileRecommendationService } from './mobile-recommendation.service';

describe('MobileRecommendationService.recommendedProducts', () => {
  const makeSvc = (rows: any[]) => {
    const sequelize = { query: jest.fn().mockResolvedValue(rows) } as any;
    const svc: any = Object.create(MobileRecommendationService.prototype);
    svc.sequelize = sequelize;

    return { svc, sequelize };
  };

  it('자기 매장 재고>0 만 (타 매장 노출 안 됨)', async () => {
    const { svc, sequelize } = makeSvc([{ product_id: 1, in_stock: true }]);
    await svc.recommendedProducts(9, 3);
    const sql = sequelize.query.mock.calls[0][0] as string;
    expect(sql).toMatch(/pps\.store_id = :storeId/i);
    expect(sql).toMatch(/stock.*> 0|> 0/i);
    const opts = sequelize.query.mock.calls[0][1];
    expect(opts.replacements.storeId).toBe(9);
  });

  it('provinceId 없으면 매장 전체 베스트셀러(province 조건 완화)', async () => {
    const { svc, sequelize } = makeSvc([]);
    await svc.recommendedProducts(9, undefined);
    const opts = sequelize.query.mock.calls[0][1];
    expect(opts.replacements.provinceId).toBeNull();
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/mobile/mobile-recommendation.service.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 서비스 + 컨트롤러 구현**

Create `api-ventago/src/app/reseller/mobile/mobile-recommendation.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes } from 'sequelize';
import { Sequelize } from 'sequelize-typescript';

// vendedor "추천제품" — 자기 매장 재고>0 인 지역 베스트셀러. 손님 추천용.
@Injectable()
export class MobileRecommendationService {
  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  async recommendedProducts(storeId: number, provinceId?: number): Promise<any[]> {
    const rows = await this.sequelize.query(
      `
      SELECT pps.product_id, p.name, p.sku, p.price,
             pps.qty_60d, pps.trend_pct, pps.rank_in_prov,
             (COALESCE(stk.stock,0) > 0) AS in_stock
        FROM reseller.province_product_stats pps
        JOIN products p ON p.id = pps.product_id
        JOIN stocks stk ON stk.product_id = p.id AND stk.is_active = true
       WHERE pps.store_id = :storeId
         AND (:provinceId::int IS NULL OR pps.province_id = :provinceId)
         AND COALESCE(stk.stock,0) > 0
       ORDER BY pps.rank_in_prov ASC
       LIMIT 20;
      `,
      { replacements: { storeId, provinceId: provinceId ?? null }, type: QueryTypes.SELECT },
    );

    return (rows as any[]).map((r) => ({
      productId: r.product_id,
      name: r.name,
      sku: r.sku,
      price: Number(r.price),
      qty60d: Number(r.qty_60d),
      trendPct: r.trend_pct == null ? null : Number(r.trend_pct),
      inStock: r.in_stock === true,
    }));
  }
}
```

Create `api-ventago/src/app/reseller/mobile/mobile-recommendation.controller.ts`:

```ts
import { Controller, Get, Query } from '@nestjs/common';
import { MobileRecommendationService } from './mobile-recommendation.service';
import { Auth } from '../../auth/decorators/auth.decorator';
import { GetUser } from '../../auth/decorators/get-user.decorator';
import { Users } from '../../users/users.model';

// vendedor(user JWT). store 스코프는 user 에서 도출(자기 매장만).
@Controller('mobile')
export class MobileRecommendationController {
  constructor(private readonly service: MobileRecommendationService) {}

  @Get('recommended-products')
  @Auth()
  recommended(@GetUser() user: Users, @Query('provinceId') provinceId?: string) {
    const storeId = (user as any).storeId;

    return this.service.recommendedProducts(storeId, provinceId ? Number(provinceId) : undefined);
  }
}
```

> **주의(구현자):** `@Auth()` / `@GetUser()` / `Users` 의 실제 import 경로와 `user.storeId` 접근 방식은 기존 컨트롤러(예: `products.controller.ts` 의 `getScope(user)`)와 동일하게 맞춘다. store 도출이 `getScope` 헬퍼라면 그것을 재사용.

- [ ] **Step 4: 판매 provincia 캡처 — 실패 테스트**

`sales.service.spec.ts` 에 describe 추가(기존 mock 패턴 사용):

```ts
  describe('판매 생성 — provincia 캡처', () => {
    it('dto.provinceId 를 sales.province_id 로 저장', async () => {
      // 기존 create 경로 mock 셋업 재사용
      await svc.create({ ...baseSaleDto, provinceId: 3 } as any);
      const saved = mockSaleModel.create.mock.calls[0][0];
      expect(saved.provinceId).toBe(3);
    });

    it('provinceId 없으면 고객 province 로 폴백(있으면)', async () => {
      // client.provinceId=5 mock 인 경우
      await svc.create({ ...baseSaleDto, clientId: 42 } as any);
      const saved = mockSaleModel.create.mock.calls[0][0];
      expect(saved.provinceId).toBe(5);
    });
  });
```

> **주의(구현자):** 기존 `sales.service.spec.ts` 의 create mock 구조(`mockSaleModel`, `baseSaleDto`)를 먼저 읽고 정합하게. 클라이언트 province 폴백은 create 시 client 조회가 이미 있으면 그 값 사용, 없으면 skip.

- [ ] **Step 5: DTO + sales.service 구현**

`create-sale.dto.ts` 에 추가:
```ts
  // 구매자 지방(POS 스마트기본 캡처). 지역 추천 데이터 소스.
  @IsOptional()
  @IsInt()
  readonly provinceId?: number;
```

`sales.service.ts` create 에서 sale 레코드 생성 시:
```ts
    // provincia 스마트기본: dto 우선, 없으면 고객 province 폴백
    const provinceId = dto.provinceId ?? client?.provinceId ?? null;
    // ... saleModel.create({ ..., provinceId }) 에 포함
```
(기존 create 의 client 조회 결과 변수명에 맞춰 `client?.provinceId` 접근.)

- [ ] **Step 6: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/mobile/mobile-recommendation.service.spec.ts src/app/sales/sales.service.spec.ts`
Expected: PASS (신규 + 기존 회귀 없음).

- [ ] **Step 7: 커밋**

```bash
cd api-ventago
git add src/app/reseller/mobile/ src/app/reseller/reseller.module.ts src/app/sales/dto/create-sale.dto.ts src/app/sales/sales.service.ts src/app/sales/sales.service.spec.ts
git commit -m "feat(reseller): vendedor 추천제품 API + 판매 provincia 캡처

GET /mobile/recommended-products(자기 매장 재고>0 지역 베스트셀러, user JWT).
판매 생성 시 provinceId 스마트기본(dto 우선, 고객 province 폴백) → sales.province_id."
```

---

### Task 10: 관리자 — 매장 허가 승인 + canonical 매핑 (백엔드)

**Files:**
- Create: `api-ventago/src/app/reseller/admin/reseller-admin.service.ts`
- Create: `api-ventago/src/app/reseller/admin/reseller-admin.controller.ts`
- Modify: `api-ventago/src/app/reseller/reseller.module.ts`
- Test: `api-ventago/src/app/reseller/admin/reseller-admin.service.spec.ts`

**Interfaces:**
- Consumes: Task 2 모델, `@Auth()` + CASL `revendedor_admin`.
- Produces:
  ```ts
  class ResellerAdminService {
    listLinks(status?): Promise<...>;
    approveLink(linkId, userId): Promise<...>;   // status='approved', approvedBy
    revokeLink(linkId): Promise<...>;
    unmappedCategories(): Promise<...>;           // canonical_category_id IS NULL
    mapCategory(categoryId, canonicalId): Promise<...>;
  }
  ```

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/reseller/admin/reseller-admin.service.spec.ts`:

```ts
import { ResellerAdminService } from './reseller-admin.service';

describe('ResellerAdminService', () => {
  const makeSvc = () => {
    const linkModel = { update: jest.fn().mockResolvedValue([1]), findAll: jest.fn().mockResolvedValue([]) } as any;
    const svc: any = Object.create(ResellerAdminService.prototype);
    svc.linkModel = linkModel;
    svc.sequelize = { query: jest.fn().mockResolvedValue([[], 1]) };
    svc.categoryModel = { update: jest.fn().mockResolvedValue([1]) };

    return { svc, linkModel };
  };

  it('approveLink → status approved + approvedBy 기록', async () => {
    const { svc, linkModel } = makeSvc();
    await svc.approveLink(7, 100);
    expect(linkModel.update).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'approved', approvedBy: 100 }),
      expect.objectContaining({ where: { id: 7 } }),
    );
  });

  it('mapCategory → categories.canonical_category_id 설정', async () => {
    const { svc } = makeSvc();
    await svc.mapCategory(50, 2);
    expect(svc.categoryModel.update).toHaveBeenCalledWith(
      expect.objectContaining({ canonicalCategoryId: 2 }),
      expect.objectContaining({ where: { id: 50 } }),
    );
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/reseller/admin/reseller-admin.service.spec.ts`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 구현**

Create `api-ventago/src/app/reseller/admin/reseller-admin.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { ResellerTiendaLink } from '../reseller-tienda-link.model';
import { Category } from '../../category/category.model';

@Injectable()
export class ResellerAdminService {
  constructor(
    @InjectModel(ResellerTiendaLink) private readonly linkModel: typeof ResellerTiendaLink,
    @InjectModel(Category) private readonly categoryModel: typeof Category,
  ) {}

  listLinks(status?: string) {
    return this.linkModel.findAll({ where: status ? ({ status } as any) : undefined, order: [['id', 'DESC']] });
  }

  approveLink(linkId: number, userId: number) {
    return this.linkModel.update(
      { status: 'approved', approvedBy: userId } as any,
      { where: { id: linkId } },
    );
  }

  revokeLink(linkId: number) {
    return this.linkModel.update({ status: 'revoked' } as any, { where: { id: linkId } });
  }

  unmappedCategories() {
    return this.categoryModel.findAll({
      where: { canonicalCategoryId: null } as any,
      attributes: ['id', 'name', 'storeId'],
      order: [['name', 'ASC']],
    });
  }

  mapCategory(categoryId: number, canonicalId: number) {
    return this.categoryModel.update(
      { canonicalCategoryId: canonicalId } as any,
      { where: { id: categoryId } },
    );
  }
}
```

Create `api-ventago/src/app/reseller/admin/reseller-admin.controller.ts`:

```ts
import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ResellerAdminService } from './reseller-admin.service';
import { Auth } from '../../auth/decorators/auth.decorator';
import { GetUser } from '../../auth/decorators/get-user.decorator';
import { Users } from '../../users/users.model';

// 관리자 전용. Phase 14 CASL function_slug 'revendedor_admin'.
@Controller('reseller/admin')
export class ResellerAdminController {
  constructor(private readonly service: ResellerAdminService) {}

  @Get('links')
  @Auth()
  links(@Query('status') status?: string) {
    return this.service.listLinks(status);
  }

  @Patch('links/:id/approve')
  @Auth()
  approve(@Param('id') id: string, @GetUser() user: Users) {
    return this.service.approveLink(Number(id), (user as any).id);
  }

  @Patch('links/:id/revoke')
  @Auth()
  revoke(@Param('id') id: string) {
    return this.service.revokeLink(Number(id));
  }

  @Get('unmapped-categories')
  @Auth()
  unmapped() {
    return this.service.unmappedCategories();
  }

  @Post('map-category')
  @Auth()
  map(@Body() dto: { categoryId: number; canonicalId: number }) {
    return this.service.mapCategory(dto.categoryId, dto.canonicalId);
  }
}
```

`reseller.module.ts`: `SequelizeModule.forFeature` 에 `Category` 추가(admin 매핑용), providers/controllers 등록.

> **주의(구현자):** `Category` 모델 import 경로 확인(`../../category/category.model`). `canonicalCategoryId` 속성이 Category 모델에 있어야 함 — 없으면 `category.model.ts` 에 `@Column canonicalCategoryId: number | null` 추가(Task 1 에서 DB 컬럼은 이미 추가됨). CASL `revendedor_admin` 슬러그 등록은 기존 permissions 시드 패턴 따름(Phase 14).

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/reseller/admin/reseller-admin.service.spec.ts`
Expected: PASS — 2개.

- [ ] **Step 5: 전체 reseller 스위트 + tsc**

Run: `cd api-ventago && npx jest src/app/reseller`
Expected: PASS — 전 스위트.

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -i reseller || echo "reseller 타입에러 없음"`
Expected: reseller 타입에러 없음

- [ ] **Step 6: 커밋**

```bash
cd api-ventago
git add src/app/reseller/admin/ src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): 관리자 — 매장 허가 승인 + canonical 매핑

reseller_tienda_link 승인/취소, 미매핑 카테고리 목록 + 수동 매핑. CASL revendedor_admin."
```

---

## Self-Review (스킬 요구)

**스펙 커버리지:** Z-1(스키마 T1) Z-2(허가 T1/T10) Z-3(canonical T1/T3/T10) Z-4(집계 T4) Z-5(랭킹 T4) Z-6(그룹키 T4) Z-7(Cron 선계산 T4) Z-8(폴백 T6) Z-9(stock-gap T6) Z-10(GPS T8) Z-11/14(vendedor T9) Z-12(inStock T6/T7/T9) Z-13(직접쿼리 T7) Z-15(웹—Plan B) Z-16(단일지방 T2/T8) Z-17(스마트기본 T9) Z-18(매핑/공식 T4/T10) Z-19(시드 T3). 웹 UI(Z-15)·관리자 UI·mobile 위젯은 Plan B/C.

**미해결/후속:** `stocks` 테이블의 store 도달 경로(T6 stockGap, T9)는 스키마 확인 후 확정 — 구현자 주의 명시. `sales.store_id`·`province_id` 채움률 배포 전 확인.

## 마이그레이션 적용 순서 (로컬 5432 + 운영 5434)

1. `2026-07-16-reseller-zona.sql` (스키마/테이블/컬럼)
2. `2026-07-16-reseller-zona-seed.sql` (좌표/canonical/자동매핑)
3. 백엔드 배포 → Cron 첫 실행으로 `province_product_stats` 채워짐
4. Plan B(웹)/Plan C(모바일)

## 실행 방식

Plan A 완료 후 Plan B(웹 포털+관리자 UI), Plan C(mobile-sales-app 추천제품+캡처) 각각 별도 플랜 작성.
