# SKU serial 컬럼화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SKU 의 serial 을 문자열 파싱 대신 전용 카운터 테이블 + `products.serial` 컬럼으로 관리하고, serial 을 2자리로 축소한다.

**Architecture:** 신규 `sku_serials` 테이블이 `(store, prefix, supplier, category, subcategory)` 별 카운터를 원자적 upsert-increment 로 발급한다(500 동접 race 안전). `products.serial` 컬럼이 각 상품의 발급값을 보유해 파싱 의존을 제거한다. create 시 서버가 serial 을 확정하고 SKU 를 조립한다(프론트 조립은 미리보기용). 기존 SKU 문자열은 불변, serial 만 backfill.

**Tech Stack:** NestJS 11 + Sequelize (api-ventago), PostgreSQL 18, Next.js/MUI (ventago-app)

**설계 문서:** `docs/superpowers/specs/2026-07-16-sku-serial-column-design.md`

## Global Constraints

- **serial scope = `(store_id, sku_prefix, supplier_id, category_id, subcategory_id)`.** 미사용 요소는 `0` sentinel (NULL 아님 — PG UNIQUE 가 NULL 을 서로 다르게 취급해 카운터가 쪼개짐).
- **serial 표시 2자리 고정** (`padStart(2, '0')`). 그룹당 01~99.
- **99 초과 → 발급 막고 `SKU_SERIAL_EXHAUSTED` (409)**, 스페인어 메시지로 prefix 교체 안내. 발급은 create 트랜잭션 안에서 하므로 throw 시 카운터 증가도 롤백된다.
- **기존 SKU 문자열 불변** (라벨·바코드 보존). serial 은 backfill 로만 채운다.
- **SKU 문자열을 어디서도 다시 파싱하지 않는다.** 통계·다음번호·표시는 컬럼에서.
- **autoSku=false(수동 SKU)**: 프론트가 보낸 sku 를 그대로 저장, `serial=NULL`, 카운터 미발급. 서버 조립·발급은 autoSku=true 일 때만.
- **재입고(parentId 있음)**: 부모 SKU 사용, serial 미발급 (현행 유지).
- **변형(color/size) SKU 는 부모 SKU 접두 + color/size.** 변형은 create 직후 `/products/variants/batch` 로 생성된다(`ProductsView.tsx:945`). 부모를 서버가 2자리로 재조립하므로, 변형도 반드시 **`parent.sku`(서버 조립분)를 접두로** 써야 부모와 일치한다. 프론트가 보내던 `baseSku`(3자리 조립분)는 무시한다. 변형 자신은 `serial=NULL`(부모 serial 공유).
- **DB 마이그레이션은 로컬(Mac PG18 5432)+운영(PG18 5434) 동시 적용.** 신규 테이블 owner+시퀀스를 coolsistema 로 이전(role 존재체크 DO 블록). SQL 은 `api-ventago/migrations/` 에 커밋.
- **pool 보호:** serial 발급은 단일 원자 쿼리. create 의 기존 트랜잭션 구조를 유지한다.
- **store_configs 중복 행 주의:** 운영에서 store 6 이 `store_configs` 에 2행 있다(조사 2026-07-16). `loadSkuConfig` 의 `findOne` 은 비결정적으로 한 행을 잡는다. 두 행의 자릿수/플래그가 같으면 무해하나, 다르면 SKU 조립이 요청마다 달라질 수 있다. Task 4 구현 시 `findOne({ order: [['id','ASC']] })` 로 결정성을 주고, 배포 전 중복 행 정리를 별도 확인(이 플랜 범위 밖, 리포트만).
- **주석은 한국어, 함수/변수명은 영어** (CLAUDE.md). **사용자 노출 문자열은 스페인어.**
- **ESLint (빌드 차단):** `return` 위 빈 줄(`newline-before-return`), 주석 위 빈 줄(`lines-around-comment`), 미사용 import 금지. 프론트 작업 후 `eslint-guardian` 점검.
- api-ventago 테스트: `npx jest src/app/products`. `apiConnector.remove()` (`.delete()` 아님).
- **`git add -A` / `git add .` 금지.** 파일명 명시.
- api-ventago 는 gitlink 서브모듈, ventago-app 도 서브모듈 → 각각 `cd` 후 커밋.

---

### Task 1: 마이그레이션 + 모델 (sku_serials 테이블 + products.serial)

**Files:**
- Create: `api-ventago/migrations/2026-07-16-sku-serials.sql`
- Create: `api-ventago/src/app/products/sku-serial.model.ts`
- Modify: `api-ventago/src/app/products/products.model.ts` (serial 컬럼 추가)
- Modify: `api-ventago/src/app/products/products.module.ts` (SkuSerial 등록)
- Test: `api-ventago/src/app/products/sku-serial.model.spec.ts`

**Interfaces:**
- Produces:
  - `SkuSerial` 모델 (테이블 `sku_serials`): `id, storeId, skuPrefix, supplierId, categoryId, subcategoryId, lastSerial`
  - `Product.serial: number | null`
  - Task 2/3/4 가 `SkuSerial` 모델과 `Product.serial` 을 사용.

- [ ] **Step 1: 마이그레이션 SQL 작성**

Create `api-ventago/migrations/2026-07-16-sku-serials.sql`:

```sql
-- =============================================================================
-- SKU serial 컬럼화 — 카운터 테이블 + products.serial
-- =============================================================================
-- 목적: SKU serial 을 문자열 파싱 대신 (store,prefix,supplier,category,subcategory)
--   별 원자적 카운터로 발급. products.serial 이 각 상품 발급값 보유.
-- 미사용 scope 요소는 0 sentinel (PG UNIQUE 는 NULL 을 서로 다르게 취급 → 0 으로 통일).
-- 적용: 로컬 5432 + 운영 5434 동시 (CLAUDE.md). backfill 은 별도 SQL(Task 6).
-- =============================================================================

CREATE TABLE IF NOT EXISTS sku_serials (
  id              SERIAL PRIMARY KEY,
  store_id        INTEGER NOT NULL,
  sku_prefix      VARCHAR(16) NOT NULL,
  supplier_id     INTEGER NOT NULL DEFAULT 0,
  category_id     INTEGER NOT NULL DEFAULT 0,
  subcategory_id  INTEGER NOT NULL DEFAULT 0,
  last_serial     SMALLINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_sku_serials UNIQUE (store_id, sku_prefix, supplier_id, category_id, subcategory_id)
);

ALTER TABLE products ADD COLUMN IF NOT EXISTS serial SMALLINT;

-- 운영 role 접근 보장 (postgres 소유로 생성 시 coolsistema permission denied 500 방지).
-- ALTER TABLE OWNER 는 시퀀스 owner 를 안 옮기므로 시퀀스도 별도 이전.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE sku_serials OWNER TO coolsistema;
    ALTER SEQUENCE sku_serials_id_seq OWNER TO coolsistema;
  END IF;
END $$;
```

- [ ] **Step 2: 로컬 적용 (사용자에게 명령 전달)**

이 클라우드 세션은 Mac localhost DB 에 못 닿는다. 사용자에게 로컬 적용 명령을 전달:
```
psql -p 5432 -d ventago -f api-ventago/migrations/2026-07-16-sku-serials.sql
```
운영(5434)은 배포 단계에서 별도 적용. 이 태스크에서는 **로컬 적용 확인**만 사용자에게 요청하고 진행한다. (모델 테스트는 mock 이라 DB 불요.)

- [ ] **Step 3: SkuSerial 모델 작성 + 실패 테스트**

Create `api-ventago/src/app/products/sku-serial.model.ts`:

```ts
import {
  Table,
  Column,
  Model,
  DataType,
  PrimaryKey,
  AutoIncrement,
} from 'sequelize-typescript';

// SKU serial 카운터 — (store, prefix, supplier, category, subcategory) 별 last_serial.
// underscored: true 전역 설정으로 camelCase → snake_case 자동 매핑.
@Table({ tableName: 'sku_serials', timestamps: true })
export class SkuSerial extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column(DataType.INTEGER)
  id: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @Column({ type: DataType.STRING(16), allowNull: false })
  skuPrefix: string;

  // 미사용 요소는 0 (NULL 아님 — UNIQUE 카운터 분열 방지)
  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  supplierId: number;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  categoryId: number;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  subcategoryId: number;

  @Column({ type: DataType.SMALLINT, allowNull: false, defaultValue: 0 })
  lastSerial: number;
}
```

Create `api-ventago/src/app/products/sku-serial.model.spec.ts`:

```ts
import { SkuSerial } from './sku-serial.model';

// 모델 정의 계약 — 컬럼/테이블명/기본값이 마이그레이션과 일치하는지.
describe('SkuSerial 모델', () => {
  it('테이블명은 sku_serials', () => {
    expect(SkuSerial.getTableName()).toBe('sku_serials');
  });

  it('scope 컬럼 + lastSerial 을 갖는다', () => {
    const attrs = SkuSerial.getAttributes();
    for (const col of [
      'storeId',
      'skuPrefix',
      'supplierId',
      'categoryId',
      'subcategoryId',
      'lastSerial',
    ]) {
      expect(attrs[col]).toBeDefined();
    }
  });

  it('미사용 scope 요소 기본값은 0 (NULL 아님)', () => {
    const attrs = SkuSerial.getAttributes() as any;
    expect(attrs.supplierId.defaultValue).toBe(0);
    expect(attrs.categoryId.defaultValue).toBe(0);
    expect(attrs.subcategoryId.defaultValue).toBe(0);
  });
});
```

- [ ] **Step 4: products.model 에 serial 추가**

`api-ventago/src/app/products/products.model.ts` 의 `sku: string;` 컬럼(40행 부근) 아래에 추가:

```ts
  // SKU serial (파싱 대신 컬럼 저장). autoSku=false/수동 SKU/재입고 상품은 NULL.
  @Column({ type: DataType.SMALLINT, allowNull: true })
  serial: number | null;
```

`DataType` 이 이미 import 돼 있는지 확인(`grep -n "DataType" products.model.ts`). 없으면 `sequelize-typescript` import 에 추가.

- [ ] **Step 5: 모듈 등록**

`api-ventago/src/app/products/products.module.ts` 의 `SequelizeModule.forFeature([...])` 배열에 `SkuSerial` 추가. 파일 상단에 import:
```ts
import { SkuSerial } from './sku-serial.model';
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-serial.model.spec.ts`
Expected: PASS — 3개.

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -i "sku-serial\|products.model\|products.module" || echo "관련 타입에러 없음"`
Expected: 관련 타입에러 없음

- [ ] **Step 7: 커밋**

```bash
cd api-ventago
git add migrations/2026-07-16-sku-serials.sql src/app/products/sku-serial.model.ts src/app/products/sku-serial.model.spec.ts src/app/products/products.model.ts src/app/products/products.module.ts
git commit -m "feat(products): sku_serials 카운터 테이블 + products.serial 컬럼

serial 을 문자열 파싱 대신 (store,prefix,supplier,category,subcategory) 별
카운터로 관리하기 위한 스키마. 미사용 scope 요소는 0 sentinel.
로컬 5432 적용, 운영 5434 는 배포 단계."
```

---

### Task 2: SkuSerialService.allocate (원자적 발급 + 99 체크)

**Files:**
- Create: `api-ventago/src/app/products/sku-serial.service.ts`
- Modify: `api-ventago/src/app/products/products.module.ts` (providers 에 SkuSerialService)
- Test: `api-ventago/src/app/products/sku-serial.service.spec.ts`

**Interfaces:**
- Consumes: Task 1 의 `SkuSerial` 모델, `Sequelize`
- Produces:
  ```ts
  export interface SerialScope {
    storeId: number; skuPrefix: string;
    supplierId: number; categoryId: number; subcategoryId: number;  // 미사용=0
  }
  class SkuSerialService {
    // 원자적 발급. create 트랜잭션 t 안에서 호출. 99 초과 시 SKU_SERIAL_EXHAUSTED throw.
    allocate(scope: SerialScope, t: Transaction): Promise<number>;
    // 미리보기(읽기 전용). 없으면 1.
    previewNext(scope: SerialScope): Promise<number>;
  }
  ```
  Task 4 가 `allocate`/`previewNext` 를 호출.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/products/sku-serial.service.spec.ts`:

```ts
import { ConflictException } from '@nestjs/common';
import { SkuSerialService, SerialScope } from './sku-serial.service';

// allocate 은 sequelize.query(ON CONFLICT ... RETURNING) 를 호출한다.
// Object.create 로 서비스를 만들고 sequelize.query 를 mock 해 반환 last_serial 을 제어한다.
describe('SkuSerialService', () => {
  const scope: SerialScope = {
    storeId: 6,
    skuPrefix: '25',
    supplierId: 3,
    categoryId: 5,
    subcategoryId: 0,
  };

  const makeService = (returnedLastSerial: number) => {
    const sequelize = {
      query: jest.fn().mockResolvedValue([{ last_serial: returnedLastSerial }]),
    } as any;
    const svc: any = Object.create(SkuSerialService.prototype);
    svc.sequelize = sequelize;

    return { svc, sequelize };
  };

  it('allocate → RETURNING last_serial 을 반환', async () => {
    const { svc } = makeService(1);
    const serial = await svc.allocate(scope, {} as any);
    expect(serial).toBe(1);
  });

  it('allocate → ON CONFLICT upsert 쿼리에 scope 값을 바인딩', async () => {
    const { svc, sequelize } = makeService(7);
    await svc.allocate(scope, {} as any);
    const [sql, opts] = sequelize.query.mock.calls[0];
    expect(sql).toMatch(/ON CONFLICT/i);
    expect(sql).toMatch(/last_serial = sku_serials\.last_serial \+ 1/i);
    expect(opts.replacements).toMatchObject({
      storeId: 6,
      prefix: '25',
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 0,
    });
    expect(opts.transaction).toBeDefined();
  });

  it('반환 99 → 정상 발급', async () => {
    const { svc } = makeService(99);
    await expect(svc.allocate(scope, {} as any)).resolves.toBe(99);
  });

  it('반환 100 → SKU_SERIAL_EXHAUSTED, 스페인어 메시지', async () => {
    const { svc } = makeService(100);
    await expect(svc.allocate(scope, {} as any)).rejects.toMatchObject({
      response: { code: 'SKU_SERIAL_EXHAUSTED' },
    });
    // 메시지에 prefix 교체 안내(스페인어)
    try {
      await svc.allocate(scope, {} as any);
    } catch (e: any) {
      expect(e.response.message).toMatch(/prefijo/i);
    }
  });

  it('previewNext → last_serial+1 (없으면 1)', async () => {
    const sequelize = {
      query: jest.fn().mockResolvedValue([]),  // 그룹 없음
    } as any;
    const svc: any = Object.create(SkuSerialService.prototype);
    svc.sequelize = sequelize;
    const next = await svc.previewNext(scope);
    expect(next).toBe(1);
  });

  it('previewNext → 기존 있으면 last_serial+1', async () => {
    const sequelize = {
      query: jest.fn().mockResolvedValue([{ last_serial: 7 }]),
    } as any;
    const svc: any = Object.create(SkuSerialService.prototype);
    svc.sequelize = sequelize;
    const next = await svc.previewNext(scope);
    expect(next).toBe(8);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-serial.service.spec.ts`
Expected: FAIL — `Cannot find module './sku-serial.service'`

- [ ] **Step 3: 서비스 구현**

Create `api-ventago/src/app/products/sku-serial.service.ts`:

```ts
import { ConflictException, Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Transaction } from 'sequelize';
import { Sequelize } from 'sequelize-typescript';

// serial 발급 scope. 미사용 요소(useSupplier=false 등)는 호출자가 0 으로 정규화한다.
export interface SerialScope {
  storeId: number;
  skuPrefix: string;
  supplierId: number;
  categoryId: number;
  subcategoryId: number;
}

const MAX_SERIAL = 99;

@Injectable()
export class SkuSerialService {
  constructor(
    @InjectConnection() private readonly sequelize: Sequelize,
  ) {}

  // 원자적 발급 — ON CONFLICT DO UPDATE 로 race 없이 last_serial+1 을 확정한다.
  // create 트랜잭션 t 안에서 호출한다: 99 초과로 throw 하면 이 증가도 함께 롤백된다.
  async allocate(scope: SerialScope, t: Transaction): Promise<number> {
    const rows = await this.sequelize.query(
      `
      INSERT INTO sku_serials
        (store_id, sku_prefix, supplier_id, category_id, subcategory_id, last_serial, created_at, updated_at)
      VALUES
        (:storeId, :prefix, :supplierId, :categoryId, :subcategoryId, 1, NOW(), NOW())
      ON CONFLICT (store_id, sku_prefix, supplier_id, category_id, subcategory_id)
      DO UPDATE SET last_serial = sku_serials.last_serial + 1, updated_at = NOW()
      RETURNING last_serial;
      `,
      {
        replacements: {
          storeId: scope.storeId,
          prefix: scope.skuPrefix,
          supplierId: scope.supplierId,
          categoryId: scope.categoryId,
          subcategoryId: scope.subcategoryId,
        },
        transaction: t,
        type: QueryTypes.SELECT,
      },
    );

    const serial = Number((rows[0] as { last_serial: number }).last_serial);

    if (serial > MAX_SERIAL) {
      // 트랜잭션 롤백으로 last_serial+1 취소 (상위 create 트랜잭션이 되돌린다)
      throw new ConflictException({
        code: 'SKU_SERIAL_EXHAUSTED',
        message:
          'Se alcanzó el máximo de 99 en este grupo. Cambiá el prefijo (p. ej. 25 → 26) para continuar.',
      });
    }

    return serial;
  }

  // 미리보기(읽기 전용) — 실제 확정은 allocate. 그룹 없으면 1.
  async previewNext(scope: SerialScope): Promise<number> {
    const rows = await this.sequelize.query(
      `
      SELECT last_serial FROM sku_serials
       WHERE store_id = :storeId AND sku_prefix = :prefix
         AND supplier_id = :supplierId AND category_id = :categoryId
         AND subcategory_id = :subcategoryId
       LIMIT 1;
      `,
      {
        replacements: {
          storeId: scope.storeId,
          prefix: scope.skuPrefix,
          supplierId: scope.supplierId,
          categoryId: scope.categoryId,
          subcategoryId: scope.subcategoryId,
        },
        type: QueryTypes.SELECT,
      },
    );

    if (rows.length === 0) {
      return 1;
    }

    return Number((rows[0] as { last_serial: number }).last_serial) + 1;
  }
}
```

`products.module.ts` 의 `providers` 에 `SkuSerialService` 추가 + import. `exports` 에도 추가(다른 모듈이 쓸 수 있게 — 현재는 불필요하나 관례).

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-serial.service.spec.ts`
Expected: PASS — 6개.

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/products/sku-serial.service.ts src/app/products/sku-serial.service.spec.ts src/app/products/products.module.ts
git commit -m "feat(products): SkuSerialService — 원자적 serial 발급 + 99 초과 exhausted

ON CONFLICT DO UPDATE RETURNING 으로 race 없이 last_serial+1 확정(500 동접 안전).
99 초과 시 SKU_SERIAL_EXHAUSTED(409, 스페인어) — create 트랜잭션 안에서 throw 해
카운터 증가도 롤백. previewNext 는 읽기 전용 미리보기."
```

---

### Task 3: SKU 조립 + scope 빌드 (assembleSku / buildScope)

**Files:**
- Create: `api-ventago/src/app/products/sku-assembler.ts` (순수 함수 모듈)
- Test: `api-ventago/src/app/products/sku-assembler.spec.ts`

**Interfaces:**
- Consumes: 없음 (순수 함수)
- Produces:
  ```ts
  export interface SkuConfig {
    useSupplier: boolean; useCategory: boolean; useSubcategory: boolean;
    useColor: boolean; useSize: boolean;
    supplierDigits: number; categoryDigits: number; subcategoryDigits: number;
    colorDigits: number; sizeDigits: number;
  }
  export interface SkuParts {
    supplierId?: number | null; categoryId?: number | null;
    subcategoryId?: number | null; colorId?: number | null; sizeId?: number | null;
  }
  // scope 정규화: 미사용/미지정 요소는 0.
  buildSerialScope(storeId: number, prefix: string, cfg: SkuConfig, parts: SkuParts):
    { storeId, skuPrefix, supplierId, categoryId, subcategoryId };
  // SKU 문자열 조립 (serial 은 2자리). 파싱 대상 아님 — 표시/바코드용.
  assembleSku(prefix: string, cfg: SkuConfig, parts: SkuParts, serial: number): string;
  ```
  Task 4 가 둘 다 사용.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/products/sku-assembler.spec.ts`:

```ts
import { buildSerialScope, assembleSku, SkuConfig } from './sku-assembler';

// 운영 기본 자릿수 = 3. 프론트 조립 규칙을 서버로 옮긴 것과 동일해야 한다.
const cfg: SkuConfig = {
  useSupplier: true,
  useCategory: true,
  useSubcategory: true,
  useColor: true,
  useSize: true,
  supplierDigits: 3,
  categoryDigits: 3,
  subcategoryDigits: 3,
  colorDigits: 3,
  sizeDigits: 3,
};

describe('buildSerialScope', () => {
  it('모든 요소 사용 → 값 그대로', () => {
    const s = buildSerialScope(6, '25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    });
    expect(s).toEqual({
      storeId: 6,
      skuPrefix: '25',
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    });
  });

  it('useSupplier=false → supplierId 0 정규화', () => {
    const s = buildSerialScope(
      6,
      '25',
      { ...cfg, useSupplier: false },
      { supplierId: 3, categoryId: 5, subcategoryId: 8 },
    );
    expect(s.supplierId).toBe(0);
    expect(s.categoryId).toBe(5);
  });

  it('id 없음(null/undefined) → 0', () => {
    const s = buildSerialScope(6, '25', cfg, {});
    expect(s).toMatchObject({ supplierId: 0, categoryId: 0, subcategoryId: 0 });
  });
});

describe('assembleSku', () => {
  it('전체 구성 — prefix+supplier+cat+subcat+serial(2)+color+size', () => {
    const sku = assembleSku('25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
      colorId: 2,
      sizeId: 4,
    }, 7);
    // 25 | 003 | 005 | 008 | 07 | 002 | 004
    expect(sku).toBe('2500300500807002004');
  });

  it('serial 2자리 패딩 (7 → 07, 12 → 12)', () => {
    const a = assembleSku('25', cfg, { supplierId: 3, categoryId: 5, subcategoryId: 8 }, 7);
    const b = assembleSku('25', cfg, { supplierId: 3, categoryId: 5, subcategoryId: 8 }, 12);
    expect(a.endsWith('07')).toBe(true);
    expect(b.endsWith('12')).toBe(true);
  });

  it('useSupplier=false → supplier 부분 생략', () => {
    const sku = assembleSku('25', { ...cfg, useSupplier: false }, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    }, 7);
    // 25 | (없음) | 005 | 008 | 07
    expect(sku).toBe('2500500807');
  });

  it('color/size 없음(부모 상품) → 뒤 생략', () => {
    const sku = assembleSku('25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    }, 7);
    expect(sku).toBe('25003005008' + '07');
  });

  it('useColor=true 지만 colorId 없음 → color 생략', () => {
    const sku = assembleSku('25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
      sizeId: 4,
    }, 7);
    // color 없음, size 있음
    expect(sku).toBe('2500300500807' + '004');
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-assembler.spec.ts`
Expected: FAIL — `Cannot find module './sku-assembler'`

- [ ] **Step 3: 구현**

Create `api-ventago/src/app/products/sku-assembler.ts`:

```ts
// SKU 문자열 조립 + serial scope 정규화 (순수 함수).
// 프론트(BasicDataCard) 조립 규칙을 서버로 옮긴 것 — 단 serial 은 2자리.
// 이 문자열은 사람이 읽는 코드·바코드용이며 어디서도 다시 파싱하지 않는다.

export interface SkuConfig {
  useSupplier: boolean;
  useCategory: boolean;
  useSubcategory: boolean;
  useColor: boolean;
  useSize: boolean;
  supplierDigits: number;
  categoryDigits: number;
  subcategoryDigits: number;
  colorDigits: number;
  sizeDigits: number;
}

export interface SkuParts {
  supplierId?: number | null;
  categoryId?: number | null;
  subcategoryId?: number | null;
  colorId?: number | null;
  sizeId?: number | null;
}

const pad = (n: number, digits: number): string =>
  String(n).padStart(digits, '0');

// 미사용/미지정 scope 요소는 0 (UNIQUE 카운터 분열 방지).
export function buildSerialScope(
  storeId: number,
  prefix: string,
  cfg: SkuConfig,
  parts: SkuParts,
): {
  storeId: number;
  skuPrefix: string;
  supplierId: number;
  categoryId: number;
  subcategoryId: number;
} {
  return {
    storeId,
    skuPrefix: prefix,
    supplierId: cfg.useSupplier ? Number(parts.supplierId) || 0 : 0,
    categoryId: cfg.useCategory ? Number(parts.categoryId) || 0 : 0,
    subcategoryId: cfg.useSubcategory ? Number(parts.subcategoryId) || 0 : 0,
  };
}

// prefix + supplier + category + subcategory + serial(2자리) + color + size.
export function assembleSku(
  prefix: string,
  cfg: SkuConfig,
  parts: SkuParts,
  serial: number,
): string {
  let sku = prefix;

  if (cfg.useSupplier && parts.supplierId) {
    sku += pad(Number(parts.supplierId), cfg.supplierDigits);
  }

  if (cfg.useCategory && parts.categoryId) {
    sku += pad(Number(parts.categoryId), cfg.categoryDigits);
  }

  if (cfg.useSubcategory && parts.subcategoryId) {
    sku += pad(Number(parts.subcategoryId), cfg.subcategoryDigits);
  }

  // serial 은 항상 2자리 (그룹당 01~99)
  sku += pad(serial, 2);

  if (cfg.useColor && parts.colorId) {
    sku += pad(Number(parts.colorId), cfg.colorDigits);
  }

  if (cfg.useSize && parts.sizeId) {
    sku += pad(Number(parts.sizeId), cfg.sizeDigits);
  }

  return sku;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-assembler.spec.ts`
Expected: PASS — 9개.

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/products/sku-assembler.ts src/app/products/sku-assembler.spec.ts
git commit -m "feat(products): SKU 조립 + scope 정규화 순수 함수

프론트 조립 규칙을 서버로 이관(serial 2자리). buildSerialScope 는 미사용
요소를 0 으로 정규화. 문자열은 표시·바코드용, 재파싱 안 함."
```

---

### Task 4: create 개편 + getNextSerial 교체 + DTO autoSku

**Files:**
- Modify: `api-ventago/src/app/products/dto/create-products.dto.ts` (autoSku 필드)
- Modify: `api-ventago/src/app/products/products.service.ts` (create, getNextSerial)
- Modify: `api-ventago/src/app/products/products.controller.ts` (next-serial 시그니처)
- Test: `api-ventago/src/app/products/products.service.spec.ts` (기존 파일에 describe 추가)

**Interfaces:**
- Consumes: Task 2 `SkuSerialService.allocate/previewNext`, Task 3 `buildSerialScope/assembleSku`
- Produces: create 가 `serial` 을 채우고 서버 조립 SKU 를 저장. `getNextSerial(scope)` 이 카운터 기반.

**주의 — autoSku 분기:**
- `autoSku=true`(기본): 서버가 `allocate` + `assembleSku`. 프론트 `sku` 무시. `serial` 저장.
- `autoSku=false`: 프론트 `sku` 그대로. `serial=null`. 카운터 미발급.
- `parentId` 있음(재입고): 부모 SKU 사용, serial 미발급 (autoSku 무관, 현행 유지).

- [ ] **Step 1: DTO 에 autoSku 추가 + 실패 테스트**

`create-products.dto.ts` 에 필드 추가 (`sku` 근처):
```ts
  // true(기본): 서버가 serial 발급 + SKU 조립. false: 프론트 sku 수동 사용, serial NULL.
  @IsOptional()
  @IsBoolean()
  readonly autoSku?: boolean;
```
`IsOptional`, `IsBoolean` 이 import 돼 있는지 확인, 없으면 추가.

`products.service.spec.ts` 에 describe 추가. 기존 파일의 mock 패턴(`mockProductModel` 등)을 따르되, `skuSerial`/`skuPrefix`/`storeConfig` 의존을 mock 으로 주입한다. 기존 `makeService`/`beforeEach` 구조를 확인 후 정합하게 작성:

```ts
  describe('create — serial 발급 + 서버 SKU 조립', () => {
    // 이 describe 는 create 의 SKU/serial 경로만 검증한다. prices/stock/subcategory
    // 부수효과는 기존 테스트가 커버하므로 최소 입력으로 좁힌다.

    const baseDto = {
      name: 'Camisa',
      sku: 'FRONT-IGNORED',   // autoSku=true 면 무시되어야 함
      autoSku: true,
      storeId: 6,
      supplierId: 3,
      categoryId: 5,
      subcategories: [8],
      colorId: 2,
      sizeId: 4,
      price: 1000,
      prices: [],
    } as any;

    it('autoSku=true → 서버가 serial 발급하고 SKU 를 조립(프론트 sku 무시)', async () => {
      // allocate=7, prefix=25, digits=3 → 25 003 005 008 07 002 004
      const created = await svc.create(baseDto);
      const savedSku = mockProductModel.create.mock.calls[0][0].sku;
      const savedSerial = mockProductModel.create.mock.calls[0][0].serial;
      expect(savedSku).toBe('2500300500807002004');
      expect(savedSku).not.toBe('FRONT-IGNORED');
      expect(savedSerial).toBe(7);
    });

    it('autoSku=false → 프론트 sku 사용, serial NULL, 카운터 미발급', async () => {
      const created = await svc.create({ ...baseDto, autoSku: false, sku: 'MANUAL-001' });
      const call = mockProductModel.create.mock.calls[0][0];
      expect(call.sku).toBe('MANUAL-001');
      expect(call.serial).toBeNull();
      expect(mockSkuSerial.allocate).not.toHaveBeenCalled();
    });

    it('parentId 있음(재입고) → 부모 SKU 보존, serial 미발급', async () => {
      await svc.create({ ...baseDto, parentId: 99, sku: 'PARENT-SKU-01' });
      const call = mockProductModel.create.mock.calls[0][0];
      expect(call.sku).toBe('PARENT-SKU-01');
      expect(mockSkuSerial.allocate).not.toHaveBeenCalled();
    });

    it('allocate 99 초과 → SKU_SERIAL_EXHAUSTED 전파', async () => {
      mockSkuSerial.allocate.mockRejectedValueOnce(
        new ConflictException({ code: 'SKU_SERIAL_EXHAUSTED', message: '...' }),
      );
      await expect(svc.create(baseDto)).rejects.toMatchObject({
        response: { code: 'SKU_SERIAL_EXHAUSTED' },
      });
    });
  });
```

**구현자 주의:** 기존 `products.service.spec.ts` 의 서비스 생성 헬퍼가 `SkuSerialService`/`StoreConfig`/`Configuration` 의존을 주입하도록 확장해야 한다. mock:
- `mockSkuSerial = { allocate: jest.fn().mockResolvedValue(7), previewNext: jest.fn() }`
- storeConfig 조회 → `{ useSupplier:true, useCategory:true, useSubcategory:true, useColor:true, useSize:true, supplierDigits:3, categoryDigits:3, subcategoryDigits:3, colorDigits:3, sizeDigits:3 }`
- prefix 조회 → `'25'`
기존 `sequelize.transaction` mock 이 콜백을 실행하는지 확인(안 하면 allocate 이 안 불림).

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/products/products.service.spec.ts -t '서버 SKU 조립'`
Expected: FAIL — 서버가 아직 프론트 sku 를 그대로 쓰고 serial 을 안 채움.

- [ ] **Step 3: 서비스 의존 주입 + 헬퍼 추가**

`products.service.ts` constructor 에 주입 추가:
```ts
    private readonly skuSerial: SkuSerialService,
    @InjectModel(StoreConfig) private readonly storeConfigModel: typeof StoreConfig,
    @InjectModel(Configuration) private readonly configurationModel: typeof Configuration,
```
상단 import:
```ts
import { SkuSerialService } from './sku-serial.service';
import { buildSerialScope, assembleSku, SkuConfig, SkuParts } from './sku-assembler';
import { StoreConfig } from '../store/config/storeConfig.model';
import { Configuration } from '../config/configuration.model';
```
`products.module.ts` 의 `forFeature` 에 `StoreConfig`, `Configuration` 추가.

프라이빗 헬퍼 추가:
```ts
  // prefix (configurations key=prefix-sku). 없으면 올해 2자리 폴백.
  private async loadPrefix(storeId: number): Promise<string> {
    const row: any = await this.configurationModel.findOne({
      where: { key: 'prefix-sku', storeId },
    });
    const data = row?.data;
    if (typeof data === 'string' && data.trim()) {
      return data.trim();
    }
    if (data && typeof data.prefix === 'string' && data.prefix.trim()) {
      return data.prefix.trim();
    }

    return new Date().getFullYear().toString().slice(-2);
  }

  // store_config 를 SkuConfig 형태로. 없으면 전부 사용 + 자릿수 3.
  // 중복 행(운영 store 6) 대비 id ASC 로 결정성 확보.
  private async loadSkuConfig(storeId: number): Promise<SkuConfig> {
    const c: any = await this.storeConfigModel.findOne({
      where: { storeId },
      order: [['id', 'ASC']],
    });

    return {
      useSupplier: c?.useSupplier ?? true,
      useCategory: c?.useCategory ?? true,
      useSubcategory: c?.useSubcategory ?? true,
      useColor: c?.useColor ?? true,
      useSize: c?.useSize ?? true,
      supplierDigits: c?.supplierDigits ?? 3,
      categoryDigits: c?.categoryDigits ?? 3,
      subcategoryDigits: c?.subcategoryDigits ?? 3,
      colorDigits: c?.colorDigits ?? 3,
      sizeDigits: c?.sizeDigits ?? 3,
    };
  }
```

- [ ] **Step 4: create 개편**

`products.service.ts` create 에서 `const finalSku = \`${baseSku}\`;`(89행 부근) 및 이후 SKU 사용부를 교체한다. 서버 조립은 **트랜잭션 안**에서(allocate 이 트랜잭션 t 를 받아야 하므로).

`finalSku` 선계산과 `existingProduct` 선검사를 제거하고, 트랜잭션 콜백 시작부에 다음을 넣는다 (`step = 'product.create';` 직전):

```ts
        // ── SKU/serial 결정 ──────────────────────────────────────────────
        // autoSku=false(수동) 또는 재입고(parentId): 프론트 sku 그대로, serial 없음.
        // autoSku=true(기본): 서버가 serial 을 원자적으로 발급하고 SKU 를 조립한다.
        const isAuto = createProductDto.autoSku !== false && !parentId;
        let finalSku = baseSku;
        let finalSerial: number | null = null;

        if (isAuto) {
          step = 'sku.assemble';
          const prefix = await this.loadPrefix(storeId);
          const cfg = await this.loadSkuConfig(storeId);
          const parts: SkuParts = {
            supplierId,
            categoryId: (productData as any).categoryId,
            subcategoryId: subcategories?.[0],
            colorId,
            sizeId,
          };
          const scope = buildSerialScope(storeId, prefix, cfg, parts);
          step = 'sku.allocate';
          finalSerial = await this.skuSerial.allocate(scope, t);
          finalSku = assembleSku(prefix, cfg, parts, finalSerial);
        }

        // 동일 매장 SKU 중복 선검사 (수동 SKU 충돌 방지 — 서버 조립분은 거의 안 걸림)
        step = 'sku.dupCheck';
        const dup = await this.productModel.findOne({
          where: { sku: finalSku, storeId },
          transaction: t,
        });
        if (dup) {
          throw new ConflictException('Product already exists');
        }
```

그리고 `productModel.create` 의 `sku: finalSku,` 는 이제 위에서 정한 값이며, 같은 객체에 `serial: finalSerial,` 를 추가한다:
```ts
        const created = await this.productModel.create(
          {
            ...productData,
            price: Number(productData.price) || 0,
            sku: finalSku,
            serial: finalSerial,
            colorId,
            sizeId,
            supplierId,
            parentId,
            storeId,
          },
          { transaction: t },
        );
```

기존 트랜잭션 밖 `existingProduct` 선검사 블록(116-122행)은 삭제(트랜잭션 안 dupCheck 로 대체). `finalSku` 를 참조하던 로그(`[create] sku=${finalSku}`)는 `baseSku` 로 바꾸거나 제거 — 트랜잭션 전엔 최종 sku 를 아직 모른다.

- [ ] **Step 5: getNextSerial 교체 + 컨트롤러**

`getNextSerial`(60-82행) 을 카운터 기반 미리보기로 교체. 시그니처를 scope 기반으로:

```ts
  // 미리보기 — 카운터 기반(문자열 파싱 제거). 실제 확정은 create 의 allocate.
  async getNextSerial(scope: {
    storeId: number;
    skuPrefix: string;
    supplierId: number;
    categoryId: number;
    subcategoryId: number;
  }): Promise<{ nextSerial: number }> {
    const nextSerial = await this.skuSerial.previewNext(scope);

    return { nextSerial };
  }
```

컨트롤러 `next-serial`(75-86행)를 scope 쿼리로 교체:
```ts
  @Get('next-serial')
  @Auth()
  async getNextSerial(
    @Query('prefix') prefix: string,
    @Query('supplierId') supplierId: string,
    @Query('categoryId') categoryId: string,
    @Query('subcategoryId') subcategoryId: string,
    @GetUser() user: Users,
  ): Promise<{ nextSerial: number }> {
    if (!prefix) {
      throw new BadRequestException('prefix es requerido');
    }
    const { storeId } = this.getScope(user);

    return this.productsService.getNextSerial({
      storeId,
      skuPrefix: prefix,
      supplierId: Number(supplierId) || 0,
      categoryId: Number(categoryId) || 0,
      subcategoryId: Number(subcategoryId) || 0,
    });
  }
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/products/products.service.spec.ts`
Expected: PASS — 기존 + 신규 4개. 기존 테스트가 `getNextSerial(baseSku, storeId)` 구 시그니처를 호출하면 신규 scope 시그니처로 갱신(동작 대응). 파싱 기대(`PROD-A-003` 등) 테스트는 카운터 기반으로 바뀌므로 해당 케이스를 previewNext mock 기반으로 재작성.

Run: `cd api-ventago && grep -rn "getNextSerial\|next-serial" src/ | grep -v spec`
Expected: 서비스/컨트롤러만, substring 파싱 잔존 없음.

Run: `cd api-ventago && grep -n "sku.substring\|substring(baseSku" src/app/products/products.service.ts`
Expected: 출력 없음 (파싱 제거됨)

- [ ] **Step 7: 커밋**

```bash
cd api-ventago
git add src/app/products/dto/create-products.dto.ts src/app/products/products.service.ts src/app/products/products.controller.ts src/app/products/products.service.spec.ts src/app/products/products.module.ts
git commit -m "feat(products): create 시 서버 serial 발급 + SKU 조립, 파싱 제거

autoSku=true(기본): 서버가 allocate+assembleSku, 프론트 sku 무시, serial 저장.
autoSku=false/재입고: 프론트 sku 유지, serial NULL. getNextSerial 은 카운터 미리보기
(substring 파싱 제거). 동시 생성 충돌 근본 해소."
```

---

### Task 5: 변형 SKU 부모 정합 (createVariantsBatch)

**Files:**
- Modify: `api-ventago/src/app/products/productStock.service.ts:237,241` (`baseSku ?? parent.sku` → `parent.sku` 강제)
- Test: `api-ventago/src/app/products/productStock.service.spec.ts` (기존 파일에 describe 추가)

**Interfaces:**
- Consumes: Task 4 의 서버 조립 부모 SKU (`parent.sku`)
- Produces: 없음 (변형 SKU 가 항상 부모 접두를 따름)

**배경:** 변형은 create 직후 `/products/variants/batch` 로 생성된다. 현재 `productStock.service.ts:237` 이 `let sku = baseSku ? baseSku : parent.sku;` 로 **프론트가 보낸 `baseSku` 를 우선**한다. 프론트 `baseSku`(3자리 조립분)와 서버 재조립된 `parent.sku`(2자리)가 달라 부모-변형 SKU 접두가 어긋난다. `baseSku` 를 신뢰하지 말고 항상 `parent.sku` 를 쓴다.

- [ ] **Step 1: 실패 테스트 작성**

`productStock.service.spec.ts` 에 describe 추가. 기존 파일의 서비스 생성/mock 패턴을 따른다(`mockProductModel` 등). 부모 `parent.sku='2500300500807'`(서버 2자리 조립분), 프론트가 `baseSku='250030050080999'`(구 3자리, 다른 값)를 보내도 변형이 `parent.sku` 접두를 쓰는지 검증:

```ts
  describe('createVariantsBatch — 변형 SKU 는 부모 접두 강제', () => {
    it('baseSku 파라미터를 무시하고 parent.sku 를 접두로 사용', async () => {
      // 부모 서버 조립분과 프론트 baseSku 가 다른 상황
      const parentSku = '2500300500807';
      // ... 기존 mock 셋업으로 parent.sku=parentSku, color 2/size 4 변형 1개 생성 ...
      await svc.createVariantsBatch({
        parentId: 1,
        baseSku: '250030050080999',   // 프론트 3자리 — 무시되어야 함
        sizeIds: [4],
        colorIds: [2],
        branchIds: [10],
        quantities: { '4-2': 0 },
      } as any);

      const createdSku = mockProductModel.create.mock.calls
        .map((c: any) => c[0].sku)
        .find((s: string) => s && s.startsWith(parentSku));
      expect(createdSku).toBeDefined();       // parent.sku 접두 변형이 생성됨
      const usedFrontBase = mockProductModel.create.mock.calls
        .some((c: any) => (c[0].sku || '').startsWith('250030050080999'));
      expect(usedFrontBase).toBe(false);      // 프론트 baseSku 접두는 없어야
    });

    it('변형은 serial NULL (부모 serial 공유)', async () => {
      // ... 변형 생성 후 ...
      const variantCalls = mockProductModel.create.mock.calls
        .filter((c: any) => c[0].parentId);
      for (const call of variantCalls) {
        expect(call[0].serial ?? null).toBeNull();
      }
    });
  });
```

**구현자 주의:** 기존 `productStock.service.spec.ts` 의 mock 구조를 먼저 읽고(`sed -n '1,60p'`), `createVariantsBatch` 가 요구하는 최소 입력(parentId, sizeIds, colorIds, branchIds, quantities, parent findByPk mock)을 그 구조에 맞춰 채운다. Color/Size 이름('Talle Única' 등) mock 이 SKU 분기에 영향하므로 일반 색/사이즈로 둔다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/products/productStock.service.spec.ts -t '부모 접두'`
Expected: FAIL — 현재는 `baseSku`(프론트) 접두를 쓴다.

- [ ] **Step 3: 구현**

`productStock.service.ts:237` 과 `:241` 의 `baseSku ? baseSku : parent.sku` 를 `parent.sku` 로 교체:

```ts
        let sku = parent.sku;
```
```ts
          sku = parent.sku + '-V';
```

`dto.baseSku` 는 이제 사용하지 않는다(102행 타입은 남겨두되 무시 — 하위호환). 구조분해(123행)에서 `baseSku` 를 빼거나, 뺄 경우 `no-unused-vars` 를 피하도록 참조 제거. **주의:** 1526행의 `const baseSku = parent.sku` 는 별개 지역변수(이미 parent.sku)라 건드리지 않는다.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/products/productStock.service.spec.ts`
Expected: PASS — 기존 + 신규 2개.

Run: `cd api-ventago && grep -n "baseSku ? baseSku" src/app/products/productStock.service.ts`
Expected: 출력 없음 (parent.sku 강제됨)

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/products/productStock.service.ts src/app/products/productStock.service.spec.ts
git commit -m "fix(products): 변형 SKU 는 부모 SKU 접두 강제 (baseSku 무시)

부모를 서버가 2자리 serial 로 재조립하므로, 변형이 프론트 baseSku(3자리)를
접두로 쓰면 부모와 어긋난다. createVariantsBatch 가 parent.sku 를 강제해
부모-변형 SKU 정합을 보장한다. 변형 serial 은 NULL(부모 공유)."
```

---

### Task 6: backfill 마이그레이션 (기존 serial 추출)

**Files:**
- Create: `api-ventago/migrations/2026-07-16-sku-serial-backfill.sql`
- Create: `api-ventago/src/app/products/sku-backfill.ts` (추출 순수 함수 — 재사용/테스트용)
- Test: `api-ventago/src/app/products/sku-backfill.spec.ts`

**Interfaces:**
- Consumes: Task 3 `SkuConfig`
- Produces: `extractSerial(sku, prefix, cfg, parts)` — 기존 3자리 SKU 에서 serial 추출. 실패 시 null.

**설계:** backfill 의 핵심 위험은 위치 파싱이다. 순수 함수 `extractSerial` 로 로직을 분리해 테스트하고, SQL 은 그 규칙을 그대로 옮기되 실패분을 리포트한다. **기존 serial 은 3자리**(구 규칙)임에 주의.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/products/sku-backfill.spec.ts`:

```ts
import { extractSerial } from './sku-backfill';
import { SkuConfig } from './sku-assembler';

const cfg: SkuConfig = {
  useSupplier: true,
  useCategory: true,
  useSubcategory: true,
  useColor: true,
  useSize: true,
  supplierDigits: 3,
  categoryDigits: 3,
  subcategoryDigits: 3,
  colorDigits: 3,
  sizeDigits: 3,
};

describe('extractSerial (backfill)', () => {
  it('구 3자리 SKU 에서 serial 추출', () => {
    // 25 003 005 008 [007] 002 004  → baseLen = 2+3+3+3 = 11, serial = substr(11,3)=007
    const s = extractSerial('2500300500800' + '7002004', '25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    });
    // 위 문자열 구성 주의: '25'+'003'+'005'+'008'+'007'+'002'+'004'
    expect(s).toBe(7);
  });

  it('정확한 구성 문자열', () => {
    const sku = '25' + '003' + '005' + '008' + '007' + '002' + '004';
    const s = extractSerial(sku, '25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    });
    expect(s).toBe(7);
  });

  it('useSupplier=false → baseLen 짧아짐', () => {
    const sku = '25' + '005' + '008' + '007';
    const s = extractSerial(sku, '25', { ...cfg, useSupplier: false }, {
      categoryId: 5,
      subcategoryId: 8,
    });
    expect(s).toBe(7);
  });

  it('길이 부족 → null (파싱 불가)', () => {
    const s = extractSerial('2500', '25', cfg, { supplierId: 3 });
    expect(s).toBeNull();
  });

  it('serial 위치가 숫자 아님 → null', () => {
    const sku = '25' + '003' + '005' + '008' + 'XYZ';
    const s = extractSerial(sku, '25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    });
    expect(s).toBeNull();
  });

  it('prefix 불일치 → null', () => {
    const s = extractSerial('99003005008007', '25', cfg, {
      supplierId: 3,
      categoryId: 5,
      subcategoryId: 8,
    });
    expect(s).toBeNull();
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-backfill.spec.ts`
Expected: FAIL — `Cannot find module './sku-backfill'`

- [ ] **Step 3: 구현**

Create `api-ventago/src/app/products/sku-backfill.ts`:

```ts
import { SkuConfig, SkuParts } from './sku-assembler';

// backfill 전용 — 기존(구 3자리) SKU 문자열에서 serial 을 추출한다.
// 현 store_config 자릿수로 baseSku 길이를 재현해 그 다음 3글자를 읽는다.
// 위치가 안 맞거나 숫자가 아니면 null (리포트 후 수동 검토). 신규 생성은 파싱을 안 하므로
// 이 함수는 1회성 마이그레이션에서만 쓴다.
const OLD_SERIAL_DIGITS = 3;

export function extractSerial(
  sku: string,
  prefix: string,
  cfg: SkuConfig,
  parts: SkuParts,
): number | null {
  if (!sku || !sku.startsWith(prefix)) {
    return null;
  }

  let baseLen = prefix.length;
  if (cfg.useSupplier && parts.supplierId) baseLen += cfg.supplierDigits;
  if (cfg.useCategory && parts.categoryId) baseLen += cfg.categoryDigits;
  if (cfg.useSubcategory && parts.subcategoryId) baseLen += cfg.subcategoryDigits;

  if (sku.length < baseLen + OLD_SERIAL_DIGITS) {
    return null;
  }

  const serialStr = sku.substring(baseLen, baseLen + OLD_SERIAL_DIGITS);

  if (!/^\d+$/.test(serialStr)) {
    return null;
  }

  return parseInt(serialStr, 10);
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/products/sku-backfill.spec.ts`
Expected: PASS — 6개.

- [ ] **Step 5: backfill SQL 작성**

Create `api-ventago/migrations/2026-07-16-sku-serial-backfill.sql`. **주의:** 순수 SQL 로 위치 파싱을 재현하려면 store_config 자릿수 join 이 필요하다. 각 상품의 baseLen 을 계산해 substring.

```sql
-- =============================================================================
-- backfill: products.serial 채움 + sku_serials.last_serial 세팅 (1회성)
-- =============================================================================
-- 기존 SKU 문자열은 불변. 현 store_config 자릿수로 baseLen 을 재현해 구 3자리 serial 추출.
-- 위치 불일치/비숫자는 serial NULL 로 남기고 리포트(아래 SELECT). backfill 후
-- 각 그룹의 MAX(serial) 을 sku_serials 에 upsert → 신규 발급이 기존과 안 겹침.
-- 적용: 로컬 5432 + 운영 5434 동시. 반드시 Task 1 마이그레이션 이후.
-- =============================================================================

-- 1) products.serial 추출 (parent 상품만; 변형은 부모 serial 공유라 대상 아님)
WITH cfg AS (
  SELECT c.store_id,
         COALESCE(cfg2.data #>> '{}', '25') AS prefix,   -- configurations prefix-sku
         c.use_supplier, c.use_category, c.use_subcategory,
         c.supplier_digits, c.category_digits, c.subcategory_digits
    FROM store_configs c
    LEFT JOIN configurations cfg2
      ON cfg2.store_id = c.store_id AND cfg2.key = 'prefix-sku'
),
calc AS (
  SELECT p.id, p.sku, p.store_id,
         cf.prefix,
         (length(cf.prefix)
          + CASE WHEN cf.use_supplier    AND p.supplier_id IS NOT NULL THEN cf.supplier_digits    ELSE 0 END
          + CASE WHEN cf.use_category    AND p.category_id IS NOT NULL THEN cf.category_digits    ELSE 0 END
          + CASE WHEN cf.use_subcategory THEN cf.subcategory_digits ELSE 0 END
         ) AS base_len
    FROM products p
    JOIN cfg cf ON cf.store_id = p.store_id
   WHERE p.is_parent = true
),
extracted AS (
  SELECT id, store_id,
         CASE
           WHEN sku LIKE prefix || '%'
            AND length(sku) >= base_len + 3
            AND substring(sku FROM base_len + 1 FOR 3) ~ '^\d+$'
           THEN substring(sku FROM base_len + 1 FOR 3)::int
           ELSE NULL
         END AS serial
    FROM calc
)
UPDATE products p
   SET serial = e.serial
  FROM extracted e
 WHERE p.id = e.id AND e.serial IS NOT NULL;

-- 2) 리포트: 추출 실패분 (serial 여전히 NULL 인 parent) — 수동 검토용
--   (배포 로그에 개수만 남긴다)
DO $$
DECLARE failed_count INTEGER;
BEGIN
  SELECT count(*) INTO failed_count FROM products WHERE is_parent = true AND serial IS NULL;
  RAISE NOTICE 'backfill: serial 추출 실패 parent 수 = %', failed_count;
END $$;

-- 3) 그룹별 MAX(serial) → sku_serials.last_serial upsert
--   subcategory 는 다대다 → 대표(최소 id) 1개로 그룹핑(현행 subcategories[0] 근사).
INSERT INTO sku_serials (store_id, sku_prefix, supplier_id, category_id, subcategory_id, last_serial, created_at, updated_at)
SELECT p.store_id,
       COALESCE(cfg2.data #>> '{}', '25') AS prefix,
       COALESCE(p.supplier_id, 0),
       COALESCE(p.category_id, 0),
       COALESCE((SELECT min(ps.subcategory_id) FROM product_subcategories ps WHERE ps.product_id = p.id), 0),
       MAX(p.serial),
       NOW(), NOW()
  FROM products p
  LEFT JOIN configurations cfg2 ON cfg2.store_id = p.store_id AND cfg2.key = 'prefix-sku'
 WHERE p.is_parent = true AND p.serial IS NOT NULL
 GROUP BY p.store_id, prefix, COALESCE(p.supplier_id,0), COALESCE(p.category_id,0),
          COALESCE((SELECT min(ps.subcategory_id) FROM product_subcategories ps WHERE ps.product_id = p.id), 0)
ON CONFLICT (store_id, sku_prefix, supplier_id, category_id, subcategory_id)
DO UPDATE SET last_serial = GREATEST(sku_serials.last_serial, EXCLUDED.last_serial), updated_at = NOW();
```

**구현자 주의:** `product_subcategories` 조인 테이블명·컬럼명을 실제로 확인(`\d product_subcategories`). Task 실행 전 `.planning/intel/db-schema-tables.md` 참조. 다르면 SQL 수정. 로컬(5432)에서 먼저 dry-run(BEGIN...ROLLBACK)으로 검증 후 사용자에게 적용 명령 전달.

- [ ] **Step 6: 로컬 dry-run 검증 (사용자 전달)**

사용자에게 전달:
```
psql -p 5432 -d ventago -c "BEGIN; \i api-ventago/migrations/2026-07-16-sku-serial-backfill.sql
SELECT count(*) FILTER (WHERE serial IS NOT NULL) AS filled, count(*) AS total FROM products WHERE is_parent=true;
SELECT count(*) AS counters FROM sku_serials;
ROLLBACK;"
```
결과(filled/total, counters)를 확인해 추출률이 합리적인지 판단. 이상하면 조인/컬럼명 재점검.

- [ ] **Step 7: 커밋**

```bash
cd api-ventago
git add migrations/2026-07-16-sku-serial-backfill.sql src/app/products/sku-backfill.ts src/app/products/sku-backfill.spec.ts
git commit -m "feat(products): serial backfill — 기존 SKU 에서 추출 + 카운터 시딩

extractSerial 순수함수(구 3자리 위치 파싱) + 1회성 SQL. 실패분은 serial NULL +
리포트. 그룹별 MAX 를 sku_serials 에 시딩해 신규 발급이 기존과 안 겹침.
기존 SKU 문자열은 불변."
```

---

### Task 7: 프론트 (2자리 표시 + serial 컬럼 + exhausted 안내 + autoSku 전송 + variants baseSku 제거)

**Files:**
- Modify: `ventago-app/src/views/products/list/components/BasicDataCard.tsx` (next-serial scope, 2자리, serial 컬럼 표시, autoSku state 노출)
- Modify: `ventago-app/src/views/products/list/ProductsView.tsx` (payload autoSku, variants/batch baseSku 제거, exhausted 에러 처리)
- Test: 프론트 자동 하네스 없음 — `eslint-guardian` + 수동 UAT

**Interfaces:**
- Consumes: Task 4 백엔드 (`/products/next-serial?prefix=&supplierId=&categoryId=&subcategoryId=`, create 응답의 `sku`/`serial`, `SKU_SERIAL_EXHAUSTED`), Task 5 (변형 SKU 부모 정합)
- Produces: 없음 (최종)

**이 화면엔 프론트 자동 테스트 하네스가 없다.** 검증 = ESLint + 수동 UAT.

- [ ] **Step 1: next-serial 호출을 scope 쿼리로 교체**

`generateSkuWithSerial`(228-250행)의 `apiConnector.get(\`/products/next-serial?baseSku=${baseSku}\`)` 를 scope 파라미터로 교체:

```ts
  async function generateSkuWithSerial(product: any, config: any, prefix: string): Promise<string> {
    if (!config) return "";
    let serial = "01";
    try {
      const params = new URLSearchParams({
        prefix,
        supplierId: String(product.supplierId || 0),
        categoryId: String(product.categories?.[0] || 0),
        subcategoryId: String(product.subcategories?.[0] || 0),
      });
      const res = await apiConnector.get(`/products/next-serial?${params.toString()}`);
      const nextSerial = (res && typeof res === 'object' && 'nextSerial' in res) ? (res as any).nextSerial : undefined;
      if (typeof nextSerial === 'number') {
        serial = String(nextSerial).padStart(2, "0");
      }
    } catch {
      serial = "01";
    }

    // baseSku 조립 (프론트 미리보기 — 최종 SKU 는 서버 조립분으로 갱신됨)
    let sku = prefix;
    if (config.useSupplier && product.supplierId) {
      sku += String(product.supplierId).padStart(config.supplierDigits || 3, "0");
    }
    if (config.useCategory && product.categories?.[0]) {
      sku += String(product.categories[0]).padStart(config.categoryDigits || 3, "0");
    }
    if (config.useSubcategory && product.subcategories?.[0]) {
      sku += String(product.subcategories[0]).padStart(config.subcategoryDigits || 3, "0");
    }
    sku += serial;
    if (config.useColor && product.colorId) {
      sku += String(product.colorId).padStart(config.colorDigits || 3, "0");
    }
    if (config.useSize && product.sizeId) {
      sku += String(product.sizeId).padStart(config.sizeDigits || 3, "0");
    }

    return sku;
  }
```

`generateSkuWithSerial` 호출부(288, 370행)가 `baseSku` 대신 `skuPrefix` 를 넘기도록 인자 갱신. 기존 useEffect 의 baseSku 조립 블록(271-281)은 이 함수 안으로 흡수됐으므로 useEffect 에서는 `skuPrefix` 만 넘긴다. `lastBaseSku` 재생성 트리거는 유지하되 비교 대상을 조립 요소(supplierId/categories/subcategories)로.

**구현자 주의:** useEffect 의존성 배열·재생성 트리거 로직을 깨지 않게 조정. 미리보기이므로 정확성보다 "요소 바뀌면 다시 조회"만 유지하면 된다.

- [ ] **Step 2: serial 표시를 컬럼값으로**

`:654` `value={(product?.sku && product.sku.length >= 3) ? product.sku.slice(-3) : ''}` 를 교체:
```tsx
value={product?.serial != null ? String(product.serial).padStart(2, '0') : ''}
```
`product.serial` 이 상품 로드 시 채워지는지 확인(상세 조회 응답에 serial 포함). 신규(미저장)면 미리보기 next 를 쓰거나 빈 값.

- [ ] **Step 3: autoSku 를 create payload 에 포함**

create payload 는 `ventago-app/src/views/products/list/ProductsView.tsx:921` 의 `const payload = { ...cleanProduct, storeId, categoryId, subcategories, ... }` 에서 조립되고 `:942` `apiConnector.post('/products', payload)` 로 전송된다. 이 `payload` 객체에 `autoSku` 를 추가:
```ts
          autoSku,   // BasicDataCard 의 autoSku state (기본 true) — 서버가 serial 발급/조립 여부 결정
```
**구현자 주의:** `autoSku` state 는 `BasicDataCard` 로컬(`useState(true)`)이라 ProductsView 에서 안 보인다. `useProductContext`(이미 product/prices 를 공유)에 `autoSku` 를 추가해 올리거나, BasicDataCard 가 product 객체에 `product.autoSku` 로 실어 payload 의 `...cleanProduct` 에 자연 포함되게 한다. 후자가 변경이 작다. 미전송 시 서버 기본 true 이므로 안전(기존 동작 유지).

- [ ] **Step 4: variants/batch 의 baseSku 제거**

`ProductsView.tsx:951` (그리고 :899 기존 부모에 변형 추가 경로)의 `/products/variants/batch` 호출 payload 에서 `baseSku: product.sku,` 줄을 **삭제**한다. Task 5 로 백엔드가 `parent.sku` 를 강제하므로 프론트가 baseSku 를 보낼 필요가 없고, 보내면 무시된다(제거로 혼동 방지).

```ts
        await apiConnector.post('/products/variants/batch', {
          parentId: result.id,
          // baseSku 제거 — 서버가 parent.sku 를 접두로 강제(부모-변형 정합)
          sizeIds,
          colorIds,
          ...
        });
```
**구현자 주의:** 두 호출 지점(:899 재입고 추가, :951 신규) 모두에서 `baseSku` 를 뺀다. 다른 파라미터(sizeIds/colorIds/branchIds/quantities)는 유지.

- [ ] **Step 5: create 응답 SKU/exhausted 처리**

저장 성공 시 응답의 `sku`/`serial` 로 폼 갱신(서버 조립분 반영). `SKU_SERIAL_EXHAUSTED` 에러 시 인라인 Alert + 토스트:
```ts
// 저장 catch 안
if (err?.response?.data?.code === 'SKU_SERIAL_EXHAUSTED' || err?.code === 'SKU_SERIAL_EXHAUSTED') {
  const msg = 'Se alcanzó 99 en este grupo. Cambiá el prefijo (Configuración → prefijo SKU) para continuar.';
  setInlineError(msg);      // 화면의 인라인 에러 상태(기존 패턴 사용)
  toast.error(msg);          // 전역 토스트 (에러 가시성 규약)

  return;
}
```
**구현자 주의:** 이 화면의 기존 에러 표시 패턴(인라인 Alert state + toast)을 따른다. 에러 응답의 code 위치(`err.response.data.code`)를 apiConnector 규약에 맞게 확인.

- [ ] **Step 6: ESLint 점검**

`eslint-guardian` subagent 로 변경 파일 점검. 특히 `newline-before-return`, `lines-around-comment`, `no-unused-vars`(제거된 baseSku 등).

Run: `cd ventago-app && npx eslint src/views/products/list/components/BasicDataCard.tsx src/views/products/list/ProductsView.tsx`
Expected: 에러 0.

- [ ] **Step 7: 커밋**

```bash
cd ventago-app
git add src/views/products/list/components/BasicDataCard.tsx src/views/products/list/ProductsView.tsx
# autoSku 를 context 로 올린 경우 그 파일도 명시 추가
git commit -m "feat(products): SKU serial 2자리 + 컬럼 표시 + exhausted 안내 + variants 정합

next-serial 을 scope 쿼리로(파싱 제거), serial 표시 2자리 padStart, 표시를
product.serial 컬럼값으로(slice(-3) 제거). autoSku 를 create 로 전송.
variants/batch 에서 baseSku 제거(서버가 parent.sku 강제).
SKU_SERIAL_EXHAUSTED → 인라인 Alert + 토스트로 prefix 교체 안내."
```

---

## 수동 UAT (구현 후 필수)

로컬 dev(백엔드 + 프론트) 실행:
1. **신규 상품(autoSku on) + 변형** → SKU 미리보기 표시 → 저장 → 응답 SKU 가 2자리 serial(`...07...`), `products.serial` 채워짐. **변형 SKU 가 부모 SKU 접두 + color/size 로 부모와 일치**(부모 2자리 serial 을 접두로 공유), 변형 serial=NULL
2. **같은 그룹 2개 연속 생성** → serial 01, 02 로 증가
3. **수동 SKU(autoSku off)** → 입력한 SKU 그대로 저장, serial NULL
4. **재입고(부모 선택)** → 부모 SKU 유지, serial 미발급, 변형도 부모 접두
5. **99 도달 시뮬레이션**(sku_serials.last_serial 을 99 로 수동 세팅 후 생성) → `SKU_SERIAL_EXHAUSTED` 인라인 + 토스트, prefix 교체 안내
6. **prefix 교체 후** → 같은 그룹이 새 prefix 에서 serial 01 부터
7. **동시 생성**(가능하면 병렬 2요청) → serial 중복 없음
8. **도매 매장(store 6/10/11, useSupplier=false)** → SKU 에 supplier 부분 없음, serial 은 `(store, prefix, 0, category, 0)` 그룹 카운터로 정상 증가

## 배포

- **마이그레이션 2개 파일**, 로컬(5432)+운영(5434) 동시:
  1. `2026-07-16-sku-serials.sql` (테이블 + serial 컬럼 + owner)
  2. `2026-07-16-sku-serial-backfill.sql` (backfill — 반드시 1 이후)
- 운영(5434): `sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f <file>`
- **배포 순서: 마이그레이션 → 백엔드(Jenkins) → 프론트(Docker).** 백엔드가 serial 컬럼/카운터 없이 뜨면 create 500.
- **배포 직전 재확인:** backfill 후 `MAX(serial) ≥ 99` 그룹이 있으면 즉시 exhausted → prefix 교체 필요. 조사(2026-07-16) 기준 그룹당 50개 초과 0건이라 안전하나 재확인.
- 하위호환: 구 프론트가 3자리 미리보기를 보내도 서버가 무시·재조립 → 안전(미리보기 표시만 어긋남, 무해).
