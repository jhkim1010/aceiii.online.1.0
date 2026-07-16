# 설계: SKU serial 컬럼화 — 문자열 파싱 제거 + 2자리 축소

날짜: 2026-07-16
대상: `api-ventago/src/app/products/`, `api-ventago/migrations/`, `ventago-app/src/views/products/`

## 문제

SKU 자동 생성이 serial 을 **문자열 위치(substring)로 파싱**한다. supplier 를 빼거나 각 요소 자릿수를 바꾸면 baseSku 길이가 변해 파싱 위치가 틀어지고, serial 이 중복·점프한다. 구버전 시스템에서 이 꼬임으로 고생한 이력이 있어 근본 제거를 원한다.

## 현재 상태 (조사 2026-07-16)

- `products` 에 `supplierId`/`colorId`/`sizeId`/`categoryId` FK 컬럼이 **이미 존재** → proveedor/color/talle/category 는 SKU 파싱이 아니라 컬럼으로 저장됨. 통계가 규칙 변경에 안 깨진다.
- **`serial` 만 컬럼이 없다.** SKU 문자열에서만 파싱된다. 코드 전체에서 SKU 를 문자열 파싱하는 곳은 딱 2군데:
  - `api-ventago/src/app/products/products.service.ts:74` — `getNextSerial` 의 `substring(baseSku.length, +3)`
  - `ventago-app/src/views/products/list/components/BasicDataCard.tsx:654` — `sku.slice(-3)` (serial 표시)
- SKU 조립 로직은 프론트(`BasicDataCard.tsx:228-295`)에만 있다. 서버는 프론트가 보낸 SKU 를 그대로 저장한다(`products.service.ts:99` `finalSku = baseSku`).
- 운영 `store_configs`: `supplier_digits` 등 자릿수 + `use_*` 플래그가 컬럼으로 있고 **기본값 3**. `prefix-sku` 는 `configurations` 테이블(key=`prefix-sku`, data=`"25"`, 매장별 수동 설정 문자열).

## 확정 결정

| # | 결정 | 근거 |
|---|------|------|
| D-1 | `products.serial` (smallint, nullable) 컬럼 추가 | 각 상품이 자기 serial 을 보유 → 파싱 의존 제거 |
| D-2 | serial 계산 = 전용 카운터 테이블 `sku_serials` 원자적 upsert-increment | 동시접속 500 race 안전. 사용자의 "명시적 카운터" 철학과 일치 |
| D-3 | serial scope = `(store_id, sku_prefix, supplier_id, category_id, subcategory_id)` | 현행 baseSku 조합과 동일 |
| D-4 | 미사용 scope 요소는 `0` sentinel (NULL 아님) | PG UNIQUE 는 NULL 을 서로 다르게 취급 → 카운터가 쪼개짐 |
| D-5 | serial 표시 **2자리 고정**, 그룹당 01~99 | 사용자 요청 |
| D-6 | 99 초과 시 생성 막고 **"prefix 교체" 안내** (에러 코드 `SKU_SERIAL_EXHAUSTED`) | 하드 리밋을 밸브로. prefix 교체 = 새 그룹 = 01 재시작 |
| D-7 | prefix 는 **매장 전역** 설정 → 교체 시 전 그룹 리셋 | 단순함 우선. 한 그룹이 99 차면 prefix 를 바꾸고 모든 그룹이 새 prefix 그룹에서 01 부터 (사용자 승인) |
| D-8 | SKU 문자열 조립은 유지하되 **어디서도 재파싱 안 함** | 사람이 읽는 코드·바코드 필요. 진실은 컬럼 |
| D-9 | **create 시 서버가 serial 확정 + SKU 최종 조립** | 프론트 미리보기 조립의 동시성 충돌(같은 serial→UNIQUE 409)을 근본 제거 |
| D-10 | 기존 SKU 문자열 **불변**, serial 은 backfill (best-effort) | 라벨·바코드 이미 인쇄됨 |
| D-11 | **prefix 소스 = `products.str_prefix` 신규 컬럼** (configurations 아님) | 아래 재설계 참조 |

## 재설계 (2026-07-16, dry-run 후)

로컬 dry-run 에서 serial 추출 88% 실패(21/172). 근본원인: prefix 를 `configurations.prefix-sku`
전역값에서 읽는데 그 값이 store 6/12 에만 있고 store 1(`26010014001`)·store 25(`25531`) 엔 없어
폴백('25')이 실제 prefix(26 등)와 어긋나 `baseLen` 이 틀어졌다.

**해결: prefix 를 `products.str_prefix` 컬럼으로 이관.**
- **신규 create:** `configurations.prefix-sku`(또는 올해 2자리)를 읽어 `products.str_prefix` 에
  **스냅샷 저장**. 이후 그 상품 prefix 의 권위 소스는 컬럼값. 카운터 scope 의 `sku_prefix` 도 이 값.
- **기존 상품(backfill):** `str_prefix = SKU 앞 2자리`, **'25'/'26' 만 인정**(운영 상품 prefix 는 둘
  뿐 — 사용자 확정). 그 외는 NULL(모호 → 리포트). 각 상품 자기 prefix 로 `baseLen` 을 재현하므로
  store 무관하게 정확히 정렬 → 추출 실패 해소.
- `sku_serials` scope 5컬럼(subcategory 포함)·2자리 serial·99 exhausted 등 나머지 설계는 **변경 없음**.
- 마이그레이션에 `ALTER TABLE products ADD COLUMN str_prefix VARCHAR(16)` 추가.

## 컴포넌트 설계

### 1. 신규 테이블 `sku_serials`

```sql
CREATE TABLE sku_serials (
  id              SERIAL PRIMARY KEY,
  store_id        INTEGER NOT NULL,
  sku_prefix      VARCHAR(16) NOT NULL,
  supplier_id     INTEGER NOT NULL DEFAULT 0,   -- 0 = 미사용/미지정
  category_id     INTEGER NOT NULL DEFAULT 0,
  subcategory_id  INTEGER NOT NULL DEFAULT 0,
  last_serial     SMALLINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_sku_serials UNIQUE (store_id, sku_prefix, supplier_id, category_id, subcategory_id)
);
```

owner + 시퀀스를 coolsistema 로 이전(마이그레이션 끝 DO 블록).

### 2. `products.serial`

```sql
ALTER TABLE products ADD COLUMN serial SMALLINT;
```

nullable — backfill 실패분과 serial 이 의미 없는 상품(generic 등)은 NULL.

### 3. serial 원자적 발급 (`SkuSerialService`, 신규)

```ts
// 반환 last_serial 이 이 상품의 serial. 트랜잭션 t 안에서 호출한다.
async allocate(scope: SerialScope, t: Transaction): Promise<number> {
  const [row] = await this.sequelize.query(`
    INSERT INTO sku_serials (store_id, sku_prefix, supplier_id, category_id, subcategory_id, last_serial)
    VALUES (:storeId, :prefix, :supplierId, :categoryId, :subcategoryId, 1)
    ON CONFLICT (store_id, sku_prefix, supplier_id, category_id, subcategory_id)
    DO UPDATE SET last_serial = sku_serials.last_serial + 1, updated_at = now()
    RETURNING last_serial;
  `, { replacements: {...}, transaction: t, type: QueryTypes.SELECT });

  const serial = Number((row as any).last_serial);

  if (serial > 99) {
    // 롤백(트랜잭션 전체)으로 증가 취소 — 상위 create 트랜잭션이 되돌린다
    throw new ConflictException({
      code: 'SKU_SERIAL_EXHAUSTED',
      message: 'Se alcanzó el máximo de 99 en este grupo. Cambiá el prefijo (p. ej. 25 → 26) para continuar.',
    });
  }

  return serial;
}
```

`SerialScope` = `{ storeId, prefix, supplierId, categoryId, subcategoryId }`, 미사용 요소는 호출자가 `0` 으로 정규화.

**99 초과 롤백:** `allocate` 은 create 트랜잭션 안에서 호출된다. `throw` 하면 create 트랜잭션 전체가 롤백되어 `last_serial + 1` 도 취소된다 → 카운터가 100 에 갇히지 않는다.

### 4. `products.service.ts` create 개편 (D-9)

현행: `finalSku = baseSku`(프론트 조립분 그대로).
개편: 서버가 serial 을 확정하고 SKU 를 조립한다.

```ts
// 트랜잭션 안에서:
const prefix = await this.skuPrefix(storeId);          // configurations prefix-sku
const cfg = await this.storeConfig(storeId);           // store_configs (digits + use_*)
const scope = this.buildScope(storeId, prefix, cfg, dto); // 미사용 요소 0 정규화
const serial = await this.skuSerial.allocate(scope, t);
const finalSku = this.assembleSku(prefix, cfg, dto, serial); // 서버 조립
// products.create({ ..., sku: finalSku, serial })
```

`assembleSku` 는 현행 프론트 조립 규칙을 서버로 옮긴 것:
```
prefix
  + (useSupplier ? pad(supplierId, supplierDigits) : '')
  + (useCategory ? pad(categoryId, categoryDigits) : '')
  + (useSubcategory ? pad(subcategoryId, subcategoryDigits) : '')
  + pad(serial, 2)                              ← 2자리 고정
  + (useColor && colorId ? pad(colorId, colorDigits) : '')
  + (useSize  && sizeId  ? pad(sizeId,  sizeDigits ) : '')
```
`subcategoryId` = 상품의 첫 subcategory(현행 `subcategories[0]` 과 동일). color/size 는 변형 단위라 부모엔 없을 수 있음(그 경우 생략).

프론트가 보낸 `sku` 는 **무시**(미리보기였을 뿐). 재입고 모드(`parentId` 있음)는 부모 SKU 를 그대로 쓰고 serial 을 새로 뽑지 않는다(현행 유지).

### 5. `getNextSerial` 엔드포인트 (미리보기)

`substring` 파싱 제거. 카운터 테이블에서 "다음 예상값"을 **읽기 전용**으로 조회:
```sql
SELECT COALESCE(last_serial, 0) + 1 AS next FROM sku_serials WHERE ...scope... ;
```
없으면 1. 미리보기이므로 실제 확정(create 시 allocate)과 다를 수 있음 — 프론트는 이 값으로 SKU 를 표시만 하고, 최종 SKU 는 create 응답으로 갱신한다.

### 6. 프론트 (`BasicDataCard.tsx`)

- `:236` serial `padStart(3)` → `padStart(2)`.
- `:654` `sku.slice(-3)` → 상품의 `serial` 컬럼값(2자리 표시). slice 는 color/size 가 뒤에 붙으면 애초에 serial 이 아니었다(선존재 버그) — 컬럼값으로 교체하며 해소.
- create 응답의 최종 `sku` 로 폼 갱신(서버 조립분 반영).
- `SKU_SERIAL_EXHAUSTED` 응답 → 인라인 Alert + 토스트 "prefijo 를 교체하세요". (에러 가시성 규약)

### 7. backfill 마이그레이션 (1회성, best-effort)

`api-ventago/migrations/` SQL 또는 스크립트:
1. 각 활성 상품 순회. 현 `store_config` 자릿수로 baseSku 길이 계산.
   - `baseLen = len(prefix) + (useSupplier?supplierDigits:0) + (useCategory?categoryDigits:0) + (useSubcategory?subcategoryDigits:0)`
   - serial = `sku.substring(baseLen, baseLen+3)` (기존은 3자리) → 정수 파싱
2. 파싱 성공 → `products.serial` 채움.
3. 그룹별 `MAX(serial)` → `sku_serials.last_serial` upsert. 신규 발급이 기존과 안 겹침.
4. 파싱 실패(길이 불일치/NaN — 과거 자릿수 변경분) → `serial=NULL` + 리포트 로그. 카운터는 성공분 MAX 기준으로 동작.

**한계 1 (파싱 실패):** backfill 은 현 자릿수 설정 기준이라, 과거에 자릿수를 바꾼 매장의 옛 SKU 는 위치가 안 맞아 실패할 수 있다. 이는 리포트로 남기고 수동 검토 — 카운터의 MAX 만 맞으면 신규 발급은 안전하다.

**한계 2 (2자리/3자리 혼재 + 즉시 exhausted):** 기존 SKU 문자열은 3자리 serial(불변), 신규는 2자리로 조립된다 → 같은 그룹에 `...007...`(기존)과 `...08...`(신규)이 공존한다. 파싱을 안 하므로 기능엔 무해하나 사람 눈엔 혼재한다. 더 중요하게, **backfill 로 `MAX(serial) ≥ 99` 가 된 그룹은 다음 생성이 즉시 `SKU_SERIAL_EXHAUSTED`** → prefix 교체가 강제된다. 배포 전 실데이터로 그런 그룹이 있는지 확인해야 한다.
조사(2026-07-16): 운영에서 `(store, supplier, category)` 기준 그룹당 50개 초과가 **0건** → subcategory 를 더한 실제 scope 는 더 잘게 쪼개지므로 즉시-exhausted 그룹 없음. 배포 직전 재확인.

## 데이터 흐름 (신규 상품 생성)

```
프론트: getNextSerial 미리보기 → SKU 표시(참고용)
  → POST /products { supplierId, categoryId, subcategories, colorId, sizeId, ... }  (sku 는 무시됨)
백엔드 create 트랜잭션:
  prefix(configurations) + cfg(store_configs) 로드
  scope 정규화(미사용=0)
  skuSerial.allocate(scope, t) → serial (원자적, 99 초과 시 롤백+SKU_SERIAL_EXHAUSTED)
  assembleSku → finalSku
  products.create({ sku: finalSku, serial, ...FK })
  → 응답 { sku, serial }
프론트: 응답 sku 로 폼 갱신
```

## 에러 핸들링

- `SKU_SERIAL_EXHAUSTED` (409) → 인라인 Alert + 토스트, prefix 교체 안내.
- 기존 매장내 SKU 중복(UNIQUE(sku,store)) → 현행 `ConflictException('Product already exists')` 유지. 서버 조립이라 발생 확률 급감.
- allocate race → ON CONFLICT 로 원자적, 재시도 불필요.

## 테스트 전략

**백엔드 (jest)**
- `SkuSerialService.allocate`: 순차 발급 1→2→3, ON CONFLICT 증가, scope 다르면 독립 카운터, 미사용 요소 0 정규화
- 99 → 100 시도 → `SKU_SERIAL_EXHAUSTED` + 카운터 롤백(재조회 시 99 유지)
- `assembleSku`: use_* 플래그별 구성, 2자리 serial, color/size 유무, prefix 반영
- create: 프론트 sku 무시하고 서버 조립분 저장, serial 컬럼 채움, 재입고(parentId) 시 serial 미발급
- `getNextSerial`: 카운터 읽기(파싱 제거), 그룹 없으면 1
- backfill 로직: 자릿수 기반 추출 성공/실패 분기, MAX 세팅

**프론트**
- serial 2자리 표시, exhausted 안내

**동시성 (통합, 가능하면)**
- 같은 scope 병렬 create N개 → serial 이 1..N 유일, UNIQUE 충돌 0

## 범위 외 (YAGNI)

- 기존 SKU 문자열 재생성 (라벨 보존)
- serial 을 3자리 이상으로 되돌리는 UI (정수 컬럼이라 `padStart` 상수만 바꾸면 됨 — 필요 시 별건)
- prefix 를 그룹별로 두는 것 (D-7 전역 유지)
- generic/변형 상품의 serial (부모 단위 발급 유지, 변형은 부모 serial 공유)
- talle 를 문자열로 (이미 sizeId FK 로 구조화됨)

## 마이그레이션 / 배포

- **마이그레이션 3단계**, 로컬(5432)+운영(5434) 동시 적용:
  1. `sku_serials` 테이블 생성 (owner→coolsistema)
  2. `products.serial` 컬럼 추가
  3. backfill (products.serial 채움 + sku_serials MAX 세팅)
- 신규 테이블 owner + 시퀀스 coolsistema 이전 필수.
- 백엔드 Jenkins, 프론트 Docker.
- **배포 순서:** 마이그레이션 먼저 → 백엔드 → 프론트. 백엔드가 serial 컬럼/카운터 없이 뜨면 create 500.
- 하위호환: 구 프론트(2자리 모름)가 3자리 미리보기를 보내도 서버가 무시하고 재조립하므로 안전. 단 미리보기 표시만 3자리로 어긋남(무해).
