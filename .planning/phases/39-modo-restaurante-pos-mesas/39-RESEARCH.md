# Phase 39: Modo Restaurante — POS por mesas - Research

**Researched:** 2026-06-14
**Domain:** NestJS 11/Sequelize 백엔드 확장 + Next.js 13(Pages Router)/MUI 5 프론트 분기 + 식당 테이블 POS 모드
**Confidence:** HIGH (모든 재사용 대상 파일을 코드베이스에서 직접 확인 — 추측 없음)

## Summary

Phase 39는 신규 시스템이 아니라 **기존 Ventago sales 엔진 위에 식당 테이블 UI를 씌우는 확장**이다. scout/SPEC 판단대로 식당 전용 자산은 코드베이스에 전무하지만 재사용 인프라(StoreConfig·Sale·SalePaymentMethod·Seller·print emit·MercadoPago QR·StoreConfigContext)는 전부 존재하며 확장 패턴이 명확하다. 가장 중요한 발견 2가지: (1) 프론트 분기는 이미 존재하는 `StoreConfigContext`(`/store-config/{storeId}` 페치)에 `useRestaurantMode` 한 줄만 추가하면 `nueva-venta/index.tsx`가 `useStoreConfig().useRestaurantMode`로 즉시 분기 가능. (2) **print-agent의 `index.js`는 현재 `print_invoice` 이벤트만 listen하며 `print_temp` 핸들러가 없다** — backend `emitPrintTemp`는 emit하지만 받는 쪽이 없어 comanda/resumen 출력(req 6·9)은 print-agent에 신규 socket 핸들러를 추가하고 CI 재빌드해야 동작한다. 이것이 본 Phase 최대 landmine이다.

드래그 배치도 편집기는 `@dnd-kit/core@6.3.1`이 이미 ventago-app 의존성에 있으나, 정규화 0~1 자유좌표 드래그는 dnd-kit의 sortable/droppable 모델보다 **순수 pointer 이벤트(onPointerDown/Move/Up) + 컨테이너 getBoundingClientRect 정규화**가 더 단순하고 정확하다(권장). DB 마이그레이션은 Phase 29(`29-01-mp-accounts.sql`)·Phase 25·26에서 확립된 PG10/15 호환 패턴(SERIAL, CREATE TABLE IF NOT EXISTS, DO 블록 CHECK 가드, GENERATED AS IDENTITY 회피)을 그대로 따른다.

**Primary recommendation:** 백엔드는 `restaurant_tables` 테이블 + RestaurantTablesModule(model/service/controller) 신규 + `Sale`·`StoreConfig` nullable 컬럼 ALTER로 확장하고, 프론트는 `StoreConfigContext`에 `useRestaurantMode` 추가 + `nueva-venta/index.tsx` 분기 + 신규 `SalonView`(views/restaurante/)로 구현하라. comanda 출력 전에 반드시 **print-agent `print_temp` 핸들러 추가 + CI 빌드** 태스크를 별도 Wave로 잡아라.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| useRestaurantMode 플래그 저장 | Database (store_configs) | API (StoreConfigService) | 매장 단위 설정 = StoreConfig use_* 선례 |
| 플래그 → SalonView 분기 | Frontend (StoreConfigContext) | — | 기존 context가 /store-config 페치, 컴포넌트에 use* 노출 |
| restaurant_tables CRUD | API (신규 RestaurantTablesModule) | Database | 멀티테넌트 store/branch 스코프 = 백엔드 책임 |
| 배치도 좌표 저장/렌더 | Database(정규화 x/y) + Frontend(렌더) | — | 좌표 저장은 DB, 비율→픽셀 변환은 SalonView 렌더 |
| 배치도 드래그 편집 | Frontend (configuración 편집기) | API (PUT 좌표) | 드래그 = 클라이언트 pointer, 저장만 API |
| DRAFT sale 누적/결제 | API (sales-create.service 확장) | Database | 트랜잭션·재고·매출통계 = 백엔드 |
| 테이블 상태 ↔ sale 동기화 | API (트랜잭션 경계) | Database | D-05 drift 방지 = 서비스 트랜잭션 |
| comanda/resumen 출력 | API (emitPrintTemp) → print-agent(Electron) | — | emit은 backend, 렌더/인쇄는 print-agent |
| 타이밍 마킹 | API (sales PATCH served/closed) | Frontend (웨이터 버튼) | 타임스탬프 저장 = DB, 트리거 = 웨이터 UI |
| split/merge 결제 | API (sale_payment_methods INSERT) | Database | 매출 무오염·분배 로직 = 백엔드 트랜잭션 |
| 메뉴 = products 필터 | Frontend (SWR) + API (categoría 필터) | — | 식당 카테고리 id 목록은 store_config, 메뉴는 products |
| 권한 분리 (편집 vs 판매) | Frontend (WithAccess/CASL) + API (route guard) | — | 배치 편집 진입점은 configuración에만 |

## Standard Stack

### Core (전부 기존 의존성 — 신규 설치 0)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NestJS | 11 | 백엔드 모듈/컨트롤러/서비스 | 프로젝트 표준 [VERIFIED: CLAUDE.md] |
| sequelize-typescript | (기존) | restaurant_tables 모델, Sale 컬럼 추가 | underscored:true 전역 [VERIFIED: storeConfig.model.ts] |
| Next.js | 13 (Pages Router) | SalonView 페이지/분기 | 프로젝트 표준 [VERIFIED: nueva-venta/index.tsx] |
| MUI | 5 | SalonView/편집기 UI (Card/Button/Dialog) | 다크네이비+골드 테마 [CITED: sketch-findings SKILL.md] |
| SWR (`useApi`/`useSWR`) | (기존) | 테이블 목록·메뉴 참조 데이터 캐시 | 5분 dedup 규약 [VERIFIED: hooks/useApi.ts] |
| socket.io `/print-agent` | (기존) | comanda/resumen emit | branch:{id} room [VERIFIED: print.service.ts] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@dnd-kit/core` | ^6.3.1 | (선택) 드래그 — 이미 설치됨 | 권장 안 함: 자유좌표는 순수 pointer가 단순 [VERIFIED: ventago-app/package.json] |
| qrcode (print-agent) | (Phase 38 추가) | resumen QR 필요 시 | 본 Phase 미사용 가능 [VERIFIED: print-agent git log] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 순수 pointer 드래그 | `@dnd-kit/core` (설치됨) | dnd-kit는 sortable/grid 모델 — 자유 x/y 정규화엔 과함. 순수 pointer + getBoundingClientRect 정규화가 코드 적고 정확 |
| `restaurant_tables` 신규 모듈 | sales 모듈 내 서브폴더 | 멀티테넌트 CRUD라 독립 모듈이 app.module 등록·테스트에 깔끔 (Phase 29 mp 모듈 선례) |
| StoreConfigContext에 플래그 추가 | /me 응답에 useRestaurantMode 주입 | StoreConfigContext가 이미 use* 전부 페치 — 최소 변경. /me는 손대지 않음 |

**Installation:** 신규 npm 패키지 없음. 모든 도구 기존 설치 확인됨.

## Architecture Patterns

### System Architecture Diagram

```
[웨이터 로그인]
   │
   ▼
nueva-venta/index.tsx ──(useStoreConfig().useRestaurantMode)──┐
   │                                                            │
   │ false                                          true        │
   ▼                                                            ▼
VcontrolHome (기존 소매, 무변경)                        SalonView (신규, next/dynamic ssr:false)
                                                              │
                       ┌──────────────────────────────────────┼──────────────────────────┐
                       ▼                                        ▼                          ▼
              GET /restaurant-tables                   테이블 클릭 → 주문 모달          타이밍 버튼
              (SWR, 상태/좌표/형태)                    │                              (served/closed)
                       │                                ▼                                  │
                       │                    웨이터 선택(useSellers) + 메뉴               PATCH /sales/:id/timing
                       │                    (products + 식당 categoría 필터)                    │
                       │                                │                                       ▼
                       │                    "주방 전달" POST                            sales.served_at/closed_at
                       │                                │
                       ▼                                ▼
          restaurant_tables.status        [DRAFT sale 누적: 첫 주문=create, 추가=add items]
          + current_sale_id                            │
          (서비스 트랜잭션 동기화)                       ▼
                                            emitPrintTemp(branchId, comandaData)
                                                        │
                                          socket.io /print-agent → branch:{id} room
                                                        │
                                                        ▼
                                    ★ print-agent index.js (print_temp 핸들러 — 신규 추가 필요!)
                                          → formatTempTicketHtml → renderHtmlToPng → printImage
                                                        │
                  ┌─────────────────────────────────────┘
                  ▼ (결제 시)
        PaymentModal: 현금/카드/MP(QR intent 재사용)
          │ split = 단일 sale + N sale_payment_methods
          │ merge = N DRAFT sale 동시 PAID + 금액 배분
          ▼
        POST /sales/:id/payments (기존 라우트) → DRAFT→PAID
          + restaurant_tables.status=libre, current_sale_id=NULL (같은 TX)
          + emitPrintTemp(resumen/영수증)
```

### Recommended Project Structure
```
api-ventago/src/app/
├── restaurant-tables/              # 신규 모듈 (mp 모듈 구조 참고)
│   ├── restaurant-tables.model.ts  # store/branch FK, shape enum, x/y float, seats, status, current_sale_id
│   ├── restaurant-tables.service.ts# CRUD + 상태↔sale 동기화 (트랜잭션)
│   ├── restaurant-tables.controller.ts # GET by-branch, POST/PUT/DELETE, PUT 좌표
│   └── restaurant-tables.module.ts # app.module 등록
├── sales/sales.model.ts            # ALTER: tableId FK + orderedAt/servedAt/closedAt (전부 nullable)
├── sales/sales-create.service.ts   # 확장: DRAFT 누적, 식당 분기, 타이밍/결제
├── store/config/storeConfig.model.ts        # ALTER: useRestaurantMode(default false) + restaurantCategoryIds
└── store/config/storeConfig.controller.ts   # update-flag 화이트리스트에 useRestaurantMode 추가

api-ventago/migrations/
├── 39-01-restaurant-tables.sql     # CREATE TABLE (PG10/15 호환)
├── 39-02-sales-restaurant-cols.sql # ALTER sales ADD COLUMN IF NOT EXISTS (nullable)
└── 39-03-store-config-restaurant.sql # ALTER store_configs (플래그 + 카테고리 id 목록)

ventago-app/src/
├── pages/nueva-venta/index.tsx     # 분기 지점 (useRestaurantMode)
├── views/restaurante/              # 신규
│   ├── SalonView.tsx               # 배치도 판매 화면 (상태별 색상)
│   ├── components/TableCard.tsx    # 테이블 1개 렌더 (형태+좌석수 비례 크기)
│   ├── components/OrderModal.tsx   # 메뉴/수량/comanda 전송
│   └── components/RestaurantPaymentModal.tsx # 현금/카드/MP + split/merge
├── views/configuracion/restaurante/SalonEditor.tsx # 드래그 배치 편집기 (configuración 전용)
├── context/StoreConfigContext.tsx  # ALTER: useRestaurantMode + restaurantCategoryIds 추가
└── hooks/api/useRestaurantTables.ts # 신규 SWR 훅

print-agent/src/index.js            # ★ ALTER: socket.on('print_temp') 핸들러 추가 (CI 재빌드)
```

### Pattern 1: StoreConfig use_* 플래그 추가
**What:** BOOLEAN 컬럼 + 마이그레이션 + controller 화이트리스트 + StoreConfigContext 노출
**When to use:** req 1 (useRestaurantMode)
**중요:** 기존 use_* 는 `defaultValue: true`지만 `useRestaurantMode`는 **default false**(소매 무영향, D 결정).
```typescript
// Source: storeConfig.model.ts:20 패턴 + CONTEXT.md D
// storeConfig.model.ts
@Column({ type: DataType.BOOLEAN, defaultValue: false })
useRestaurantMode: boolean;

// 식당 메뉴로 노출할 카테고리 id 목록 (categories 스키마 무변경, D 결정)
// PG10 JSONB 지원 확인됨 (Phase 25 P04 client_merges.field_picks 선례)
@Column({ type: DataType.JSONB, allowNull: true })
restaurantCategoryIds: number[] | null;
```
```typescript
// storeConfig.controller.ts:54 — update-flag allowedFields 배열에 추가 필수 (안 하면 BadRequestException)
const allowedFields = [ ..., 'useRestaurantMode' ];
```

### Pattern 2: Sale nullable 컬럼 추가 (storeClientId 선례)
**What:** Sale 모델에 `@ForeignKey` + nullable 컬럼 추가, 마이그레이션 ADD COLUMN IF NOT EXISTS
**When to use:** req 3 (table_id + 타이밍)
```typescript
// Source: sales.model.ts:67-78 (storeClientId 선례) + :148 provinceId
@ForeignKey(() => RestaurantTable)
@Column({ field: 'table_id', type: DataType.INTEGER, allowNull: true })
tableId?: number;

@Column({ type: DataType.DATE, allowNull: true }) orderedAt?: Date;
@Column({ type: DataType.DATE, allowNull: true }) servedAt?: Date;
@Column({ type: DataType.DATE, allowNull: true }) closedAt?: Date;
```
**회귀 0 보장:** 전부 nullable → 기존 소매 sale INSERT 불변. 매출 쿼리는 `activity_type='sale'` 명시 필터라 영향 없음 (sales.model.ts:47 규칙). 식당 sale도 `activityType=SALE` 유지 → 통계 자동 통합 (req 11).

### Pattern 3: branch:{id} room print emit (branchId 해결)
**What:** sales-create.service.ts:830 `resolveSaleBranchId(sale)` — terminal→box→branch 경유로 branchId 해결 후 `emitPrintTemp(branchId, data)`
**When to use:** req 6 comanda, req 9 resumen
```typescript
// Source: sales-create.service.ts:830-863, print.service.ts:32
const branchId = await this.resolveSaleBranchId(sale); // terminal→box→branch
this.printService.emitPrintTemp(branchId, comandaData);
// 주의: sales 테이블에 branch_id 컬럼 없음 (CLAUDE.md). 식당 sale은 terminalId로 branch 해결.
// 또는 table_id → restaurant_tables.branchId 로 직접 해결 (식당은 이 경로가 더 정확)
```

### Pattern 4: PG10/15 호환 마이그레이션
**What:** Phase 29 `29-01-mp-accounts.sql` 패턴 — BEGIN/COMMIT, SERIAL, CREATE TABLE IF NOT EXISTS, DO 블록 CHECK 가드, 부분 UNIQUE INDEX
```sql
-- Source: 29-01-mp-accounts.sql + Phase 25/26 결정
CREATE TABLE IF NOT EXISTS restaurant_tables (
  id            SERIAL PRIMARY KEY,                    -- NOT GENERATED AS IDENTITY (PG10)
  store_id      INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  branch_id     INTEGER NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name          VARCHAR(64) NOT NULL,
  shape         VARCHAR(20) NOT NULL DEFAULT 'square', -- CHECK로 enum 가드
  seats         INTEGER NOT NULL DEFAULT 4,
  pos_x         REAL NOT NULL DEFAULT 0,               -- 정규화 0~1 (D-08)
  pos_y         REAL NOT NULL DEFAULT 0,
  zone          VARCHAR(64) NULL,                      -- D-09 다중 salón 대비
  status        VARCHAR(20) NOT NULL DEFAULT 'libre',  -- libre/ocupada/por_cobrar
  current_sale_id INTEGER NULL REFERENCES sales(id) ON DELETE SET NULL,
  created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
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
END$$;
CREATE INDEX IF NOT EXISTS idx_rt_branch ON restaurant_tables (branch_id);
```

### Pattern 5: 프론트 분기 (StoreConfigContext)
```typescript
// Source: StoreConfigContext.tsx:13-67 + nueva-venta/index.tsx:7
// StoreConfigContext.tsx — interface/defaultState/fetchConfig 3곳에 추가
useRestaurantMode: boolean;        // interface
useRestaurantMode: false,          // defaultState
useRestaurantMode: res?.useRestaurantMode ?? false,  // fetchConfig

// nueva-venta/index.tsx 분기
const SalonView = dynamic(() => import('src/views/restaurante/SalonView'), { ssr: false })
const { useRestaurantMode, loaded } = useStoreConfig()
// loaded 전엔 스켈레톤 — 깜빡임 방지 (소매 뷰 먼저 뜨고 식당 전환되는 FOUC 회피)
return useRestaurantMode ? <SalonView/> : <VcontrolHome/>
```

### Anti-Patterns to Avoid
- **sales JOIN으로 테이블 상태 계산:** D-05대로 `restaurant_tables.status` + `current_sale_id` 직접 저장. salon 렌더는 단일 SELECT (pool 절약, 300ms). sales JOIN 금지.
- **storeConfig.controller update-flag 화이트리스트 미수정:** `useRestaurantMode`를 배열에 안 넣으면 토글이 BadRequestException. 흔한 누락.
- **print_temp 핸들러 없이 comanda 완료 처리:** backend emit은 되지만 print-agent가 안 받음 → 인쇄 무반응. 반드시 핸들러 추가 + 빌드.
- **드래그 좌표를 픽셀로 저장:** D-08 정규화 0~1 위반 → 화면 크기 바뀌면 배치 깨짐.
- **ESLint:** `return` 위 빈 줄, `//` 주석 위 빈 줄, 미사용 import 금지 (빌드 차단).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| comanda/영수증 ESC/POS 포맷 | 자체 ESC/POS 바이트 빌더 | print-agent `formatTempTicketHtml` (formatter.js:666) → renderHtmlToPng → printImage | 이미 items/variants/totals/payment 렌더 구현됨 |
| 결제수단 기록 | 신규 식당 결제 테이블 | `sale_payment_methods` (saleId+paymentMethodId+optionId+amount) | split=복수 INSERT, merge=복수 sale INSERT로 충족 |
| 웨이터 엔티티 | 신규 waiter 테이블 | `Seller` (branchId/linkedUserId) | branchId 설정 seller = 웨이터 |
| MP QR 결제 | 신규 QR 흐름 | mp-qr.controller `POST` create intent / `DELETE` cancel | Phase 29 intent/webhook 재사용 |
| 매장 플래그 페치 | 신규 context | `StoreConfigContext` (이미 /store-config 페치) | use* 전부 노출 중 |
| branchId 해결 | sales.branch_id (존재 안 함) | `resolveSaleBranchId` terminal→box→branch | 검증된 헬퍼 |
| 메뉴 카테고리 데이터 | 신규 메뉴 모델 | products + categories + store_config 카테고리 id 필터 | req 11 결정 |

**Key insight:** 본 Phase의 신규 코드는 "테이블 배치 + 상태머신 + UI 분기"에 집중되고, sales/payment/print/MP는 전부 기존 자산 호출이다. 새 인프라를 만드는 순간 SPEC constraint("확장 only") 위반.

## Runtime State Inventory

> rename/refactor 아님 — 신규 기능 추가(greenfield slice). 단, 기존 매장 데이터에 영향 가능한 항목만 점검.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | 기존 store_configs 행 (운영 4매장: CART/coolsistema/genius/ACE) — useRestaurantMode 컬럼 추가 시 default false로 채워짐 | 마이그레이션 ADD COLUMN DEFAULT false (자동, 회귀 0) |
| Live service config | print-agent 운영 인스턴스들 — 현재 print_temp 핸들러 없음 | print-agent CI 재빌드 + 사용자 재설치 필요 (Electron 앱) |
| OS-registered state | None — 검증: print-agent는 socket 클라이언트, OS 등록 없음 | 없음 |
| Secrets/env vars | None — 신규 secret 불필요. PUBLIC_WEB_URL 등 기존 재사용 | 없음 |
| Build artifacts | print-agent dist (Electron) — index.js 변경 시 GitHub Actions build-print-agent.yml 트리거 (태그 bump) | push-both.sh가 태그 자동 증가 → CI 빌드 |

## Common Pitfalls

### Pitfall 1: print-agent에 print_temp 핸들러 부재 (★최우선)
**What goes wrong:** backend `emitPrintTemp(branchId, comandaData)` 호출은 성공하지만 comandera에서 아무것도 안 나옴.
**Why it happens:** print-agent `src/index.js`(HEAD/working tree)는 `socket.on('print_invoice')` 하나만 등록. `print_temp`/`print_qr`/`print_fiscal` 핸들러 없음 (grep 확인). `formatTempTicketHtml`는 formatter.js에 export되어 있으나 **호출처가 없다**.
**How to avoid:** print-agent `index.js`에 `socket.on('print_temp', ...)` 핸들러 추가 → `formatTempTicketHtml(data)` → `renderHtmlToPng(html, 576)`(Phase 38 print_qr 패턴) → printImage. push-both.sh로 CI 빌드 트리거. **이걸 별도 Wave/태스크로 명시**하지 않으면 req 6·9가 통째로 미동작.
**Warning signs:** 백엔드 로그엔 emit 성공, 프린터 무반응.

### Pitfall 2: store_configs 행이 없는 매장
**What goes wrong:** `findByStoreId`가 NotFoundException (storeConfig.service.ts:14). useRestaurantMode 조회 실패.
**Why it happens:** StoreConfig는 매장 등록 시 생성(auth.service.ts:300)되지만 레거시 매장 일부 누락 가능.
**How to avoid:** StoreConfigContext는 catch로 default(false) 폴백 이미 처리(StoreConfigContext.tsx:71). 백엔드 토글 저장 전 findOrCreate 고려.
**Warning signs:** 특정 매장만 토글 저장 500.

### Pitfall 3: 테이블 상태 ↔ DRAFT sale drift
**What goes wrong:** sale은 PAID인데 테이블이 ocupada로 남거나, 그 반대.
**Why it happens:** 상태 컬럼과 current_sale_id를 별도 트랜잭션에서 갱신.
**How to avoid:** D-05대로 주문 생성/결제/cuenta를 단일 트랜잭션(`sequelize.transaction`)으로 묶어 sale 상태 변경과 restaurant_tables 갱신을 원자적으로. 결제 완료 시 같은 TX에서 `status=libre, current_sale_id=NULL`.
**Warning signs:** salon에 유령 점유 테이블.

### Pitfall 4: 식당 sale의 branchId 해결 실패
**What goes wrong:** comanda emit이 `no_branch`로 스킵 (sales-create.service.ts:882).
**Why it happens:** 식당 주문 시 cashRegister/terminal이 안 열려 있으면 terminal→box→branch 경유 실패.
**How to avoid:** 식당 sale은 `table_id → restaurant_tables.branch_id`로 branchId 직접 해결 (terminal 경로보다 신뢰). resolveSaleBranchId에 table_id 분기 추가.
**Warning signs:** comanda 안 나가는데 sale은 생성됨.

### Pitfall 5: split 매출 오염
**What goes wrong:** split 시 자식 sale 생성하면 테이블=N sale로 매출 통계 중복.
**Why it happens:** 직관적으로 분할=새 sale로 생각.
**How to avoid:** D-01대로 단일 DRAFT sale 유지 + sale_payment_methods 복수 INSERT. 자식 sale 금지.
**Warning signs:** 한 테이블 결제 후 일일 판매건수가 인원수만큼 증가.

### Pitfall 6: ESLint 빌드 차단
**What goes wrong:** Jenkins 프론트 빌드 실패.
**How to avoid:** `return`/`//` 위 빈 줄, 미사용 import 제거 (CLAUDE.md). apiConnector는 `.remove()` (`.delete()` 아님).

## Code Examples

### 테이블 형태+좌석수 비례 크기 파생 (D-10, w/h 저장 안 함)
```typescript
// Source: CONTEXT.md D-10 + SalonView 렌더 책임
// 정규화 좌표 → 컨테이너 픽셀 + 좌석수 비례 스케일
const BASE = { circle: 56, oval: 72, square: 56, rect: 80 };
const scale = 0.8 + Math.min(seats, 12) / 12 * 0.6; // 2인<4인<8인
const w = BASE[shape] * scale;
const px = posX * containerW;  // posX∈[0,1]
const py = posY * containerH;
```

### 자유 드래그 정규화 좌표 (순수 pointer, 권장)
```typescript
// Source: 표준 pointer 패턴 (라이브러리 불필요)
const onPointerMove = (e: PointerEvent) => {
  const rect = containerRef.current!.getBoundingClientRect();
  const nx = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
  const ny = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height));
  setPos({ x: nx, y: ny }); // 0~1 저장값
};
// drop 시 PUT /restaurant-tables/:id { posX: nx, posY: ny }
```

### DRAFT sale 누적 (req 8)
```typescript
// Source: sales-create.service.ts 확장 + CONTEXT D-07
// 첫 주문: table.current_sale_id 없음 → Sale.create({status: DRAFT, tableId, orderedAt: now})
// 추가 주문: 기존 DRAFT sale에 SaleItem.bulkCreate (신규 created_at 묶음 = 라운드, D)
// comanda는 새 items만 출력 (created_at > 직전 emit 시각)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| sales.branch_id 직접 | terminal→box→branch 해결 | 기존 | 식당은 table_id→branch가 더 정확 |
| use_* default true | useRestaurantMode default false | Phase 39 | 소매 무영향 의도적 차별 |
| ESC/POS 바이트 직접 | HTML→PNG→printImage (Phase 11/38) | Phase 11 | comanda도 이 파이프라인 |

**Deprecated/outdated:** 없음 — 기존 패턴 전부 현행.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | restaurantCategoryIds를 JSONB로 store_configs에 저장 (Claude's Discretion) | Pattern 1 | 별도 매핑 테이블 선호 시 변경 — 낮음 (PG10 JSONB 검증됨, Phase 25 선례) |
| A2 | 식당 sale branchId는 table_id→restaurant_tables.branch_id로 해결 권장 | Pitfall 4 | terminal 경로 강제 시 cashRegister 미오픈 식당에서 comanda 누락 — 중간 |
| A3 | print_temp 핸들러를 print-agent에 추가 (현재 print_invoice만) | Pitfall 1 | 검증됨(grep). 신규 print 이벤트명 쓰면 backend도 변경 필요 — 낮음 |
| A4 | 드래그는 순수 pointer 권장 (dnd-kit 미사용) | Code Examples | dnd-kit 강제 시 자유좌표 구현 복잡 — 낮음 (plan 재량) |
| A5 | resumen/cuenta는 emitPrintTemp 재사용 (전용 이벤트 안 만듦) | Architecture | 영수증/cuenta 구분 위해 data.kind 필드로 분기 — 낮음 |
| A6 | 라운드(curso)는 sale_items.created_at 묶음 추적 (신규 컬럼 없음) | Code Examples | 명시적 round 컬럼 원하면 변경 — 낮음 (CONTEXT 결정) |

## Open Questions (RESOLVED)

1. **타이밍 마킹 API 형태**
   - What we know: served_at/closed_at는 sale 행에 타임스탬프 (req 7). 웨이터 버튼 트리거.
   - What's unclear: 신규 `PATCH /sales/:id/timing { event }` vs 기존 `PUT /sales/:id` 재사용?
   - Recommendation: 전용 경량 엔드포인트 (PATCH /sales/:id/timing) — 단일 컬럼 UPDATE, pool 절약. 라우트 순서 주의(`:id` 위).
   - RESOLVED: 전용 PATCH /restaurant-sale/:id/timing 채택 (39-05 markTiming). 라우트 우선순위 위해 구체 경로(order, pay-merge)를 :id 위 배치.

2. **comanda 증분 출력 기준 시각 저장**
   - What we know: 새 items만 출력, created_at 묶음 (D).
   - What's unclear: "직전 emit 시각"을 어디 저장? (sale 컬럼 없음)
   - Recommendation: orderedAt를 매 comanda 전송마다 갱신하거나, items의 max(created_at)를 클라이언트가 추적해 다음 라운드 경계로 사용. plan에서 확정.
   - RESOLVED: 신규 `last_comanda_at` 컬럼 도입 (39-01 마이그레이션 + 39-05 emit 마다 갱신). 새 items = created_at > last_comanda_at 으로 증분 경계 확정.

3. **결제 시 cashRegister/box-operation 연동**
   - What we know: 소매 결제는 BoxOperationService로 금전함 기록.
   - What's unclear: 식당 결제도 동일 box-operation 기록 필요 (gasto/매상 통계 통합 — req 11)?
   - Recommendation: YES — 기존 sales-create 결제 경로 그대로 타야 매상 통계 자동 통합. 식당이라고 우회 금지.
   - RESOLVED: 39-05 paySale/payMerge 가 BoxOperationService.addOperation 동일 경유 (우회 금지). 열린 cashRegister 없으면 소매와 동일하게 금전함 기록 스킵.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| PostgreSQL (로컬 PG18) | 마이그레이션 dev 검증 | ✓ | 18 (호스트) | — |
| PostgreSQL (운영 PG10) | 운영 마이그레이션 | ✓ (SSH) | 10 | PG10 호환 SQL 필수 |
| @dnd-kit/core | (선택) 드래그 | ✓ | 6.3.1 | 순수 pointer (권장) |
| socket.io /print-agent | comanda emit | ✓ | 기존 | — |
| print-agent print_temp 핸들러 | comanda 인쇄 | ✗ | — | **없음 — 신규 추가 필수 (blocker)** |
| MercadoPago QR 모듈 | MP 결제 | ✓ | Phase 29 | — |

**Missing dependencies with no fallback:**
- print-agent `print_temp` socket 핸들러 — 없으면 comanda/resumen 인쇄 전체 미동작. 신규 코드 + CI 빌드 + 재설치 필요.

**Missing dependencies with fallback:**
- @dnd-kit: 순수 pointer 드래그로 대체 가능 (권장).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Jest (api-ventago, `*.spec.ts`, jest rootDir=src) |
| Config file | api-ventago/package.json jest 블록 (testRegex 기반) |
| Quick run command | `cd api-ventago && npx jest restaurant-tables --silent` |
| Full suite command | `cd api-ventago && npm test` |
| Frontend | 자동화 테스트 미흡 — manual UAT + ESLint 빌드 게이트 |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| req 1 | useRestaurantMode 토글 저장 | unit | `npx jest storeConfig` | ❌ Wave 0 |
| req 2 | restaurant_tables CRUD | unit | `npx jest restaurant-tables.service` | ❌ Wave 0 |
| req 3 | sales nullable 컬럼 회귀 0 | unit | `npx jest sales-create.service` (기존 spec 통과 유지) | ✅ 기존 |
| req 8 | DRAFT 누적 → 단일 sale | unit | `npx jest restaurant-tables.service` | ❌ Wave 0 |
| req 10 | split 단일sale/복수 pm, merge 복수sale | unit | `npx jest` (결제 분배) | ❌ Wave 0 |
| req 3/회귀 | 마이그레이션 멱등 + 회귀 0 | manual (dev DB) | dev DB 적용 + 기존 소매 sale 생성 smoke | manual |
| req 6 | comanda emit + print_temp 인쇄 | manual | print-agent 연결 후 주문→인쇄 확인 | manual |
| req 4/5 | SalonView 분기 + 드래그 저장 | manual | 브라우저 (플래그 on/off 매장 혼용) | manual |

### Sampling Rate
- **Per task commit:** `npx jest <touched-module> --silent`
- **Per wave merge:** `cd api-ventago && npm test` (sales spec 회귀 0 확인)
- **Phase gate:** 전체 jest green + dev DB 마이그레이션 멱등 검증 + print-agent comanda manual smoke

### Wave 0 Gaps
- [ ] `restaurant-tables.service.spec.ts` — req 2/8 (CRUD + 상태↔sale 동기화)
- [ ] `storeConfig.controller.spec.ts` 보강 — req 1 (useRestaurantMode 화이트리스트)
- [ ] sales-create split/merge 분배 spec — req 10
- [ ] 기존 `sales-create.service.spec.ts` 회귀 통과 유지 확인 (nullable 컬럼 추가 후)
- [ ] print-agent: 자동화 테스트 없음 → manual smoke 체크리스트 작성

## Security Domain

> security_enforcement 명시 false 아님 — 포함. 본 Phase는 기존 인증/세션/CASL 재사용.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | 기존 JWT/Passport + SessionGuard 재사용 (신규 인증 없음) |
| V4 Access Control | yes | 배치 편집은 configuración(admin) 전용, SalonView(seller)와 권한 분리 — WithAccess/CASL. 백엔드 라우트도 store/branch 스코프 검증 |
| V5 Input Validation | yes | restaurant_tables DTO class-validator (shape enum, seats 범위, posX/Y 0~1, status enum). store_config update-flag 화이트리스트 |
| V6 Cryptography | no | 신규 암호화 없음 |

### Known Threat Patterns for NestJS/Sequelize/Next.js
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 타 매장 테이블 CRUD (IDOR) | Tampering/Info | service에서 storeId/branchId 스코프 WHERE 강제 (멀티테넌트) |
| update-flag 임의 컬럼 주입 | Tampering | 화이트리스트 배열 (storeConfig.controller.ts:54 패턴) |
| 좌표/좌석 비정상 값 | Tampering | DTO 범위 검증 (posX/Y ∈[0,1], seats>0), DB CHECK enum |
| seller 권한 없이 배치 편집 | Elevation | configuración 라우트 권한 가드 + 프론트 진입점 분리 (req 5) |
| split 음수/초과 금액 | Tampering | 결제 합계 = sale.totalAmount 검증 (sale_payment_methods 합) |

## Sources

### Primary (HIGH confidence — 코드베이스 직접 확인)
- api-ventago/src/app/store/config/storeConfig.model.ts, storeConfig.service.ts, storeConfig.controller.ts — use_* 패턴, update-flag 화이트리스트
- api-ventago/src/app/sales/sales.model.ts — SaleStatus/Source/ActivityType enum, storeClientId nullable 선례, branch_id 부재
- api-ventago/src/app/sales/sales-create.service.ts — DRAFT 생성, resolveSaleBranchId, emitPrintTemp 호출
- api-ventago/src/app/sales/sales-payment-methods/sales-payment-method.model.ts — split/merge 결제 구조
- api-ventago/src/app/sellers/sellers.model.ts — Seller(branchId/linkedUserId)
- api-ventago/src/app/print/print.service.ts — emitPrintTemp(branchId, data) → branch:{id} room
- api-ventago/migrations/29-01-mp-accounts.sql, 2026-04-29-add-store-config-currency.sql — PG10/15 호환 마이그레이션
- print-agent/src/index.js — print_invoice만 listen (print_temp 부재 — grep 검증)
- print-agent/src/formatter.js:666 — formatTempTicketHtml (호출처 없음)
- ventago-app/src/pages/nueva-venta/index.tsx — VcontrolHome dynamic 분기 지점
- ventago-app/src/context/StoreConfigContext.tsx — /store-config 페치, use* 노출 (분기 메커니즘)
- ventago-app/src/views/homes/VcontrolHome.tsx — SalonView 미러 대상 구조
- ventago-app/src/hooks/useApi.ts, hooks/api/useCategoriesByStore.ts — SWR 패턴
- ventago-app/src/configs/withAccess.tsx — 권한 게이팅
- ventago-app/package.json — @dnd-kit/core 6.3.1 설치 확인
- CLAUDE.md, .planning/STATE.md, 39-SPEC.md, 39-CONTEXT.md, sketch-findings SKILL.md

### Secondary (MEDIUM)
- 없음 (전부 1차 소스로 검증)

### Tertiary (LOW)
- 없음

## Project Constraints (from CLAUDE.md)

- Sequelize `underscored:true` → 모델 camelCase, DB snake_case. SQL은 snake_case.
- SQL/마이그레이션 전 .planning/intel/db-schema-{tables,fks}.md 참조 (추측 금지).
- `sales` 테이블 branch_id 없음 — terminal→box→branch 경유 또는 table_id→restaurant_tables.branch_id.
- PG10/PG15 호환: SERIAL(NOT GENERATED AS IDENTITY), CREATE TABLE IF NOT EXISTS, DO 블록 CHECK 가드.
- pool min=10/max=80, slow query 100ms↑ 최적화. salon 렌더 단일 SELECT.
- 프론트 300ms: SalonView next/dynamic(ssr:false), 참조 데이터 SWR.
- ESLint(빌드 차단): newline-before-return, lines-around-comment, no-unused-vars.
- apiConnector는 `.remove()` (`.delete()` 아님).
- comanda/resumen은 emitPrintTemp + branch:{id} room 재사용 (신규 print 인프라 금지).
- 에러 노출: 인라인 Alert + 글로벌 토스트 더블 (feedback_error_visibility).
- DB 마이그레이션은 api-ventago/migrations/ SQL → 운영 PG10 Docker 직접 실행.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 모든 재사용 라이브러리/모델 코드 직접 확인, 신규 의존성 0
- Architecture: HIGH — 분기/모델/마이그레이션 패턴 전부 기존 선례 존재
- Pitfalls: HIGH — print_temp 부재는 grep으로 직접 검증한 사실
- split/merge: MEDIUM — 모델 구조는 확정, 분배 로직 구현 세부는 plan에서 확정

**Research date:** 2026-06-14
**Valid until:** 2026-07-14 (안정 코드베이스 — 단, print-agent index.js가 Phase 38 print_qr 머지로 바뀌면 Pitfall 1 재확인)
