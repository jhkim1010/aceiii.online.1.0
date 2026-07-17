# 설계: Revendedor 지역 추천 (Phase 24 MVP 수직슬라이스)

날짜: 2026-07-16
대상: `api-ventago/src/app/reseller/`(신규), `api-ventago/src/app/products/`, `api-ventago/src/app/sales/`, `ventago-app/src/views/revendedor/`(신규), `ventago-app/src/views/.../nueva-venta`
관련 기존 설계: `.planning/phases/24-revendedor-marketplace/24-CONTEXT.md` (정합 유지)

## 문제

재판매자(revendedor)가 허가된 여러 매장의 상품을 **TIPO(category)별로 한꺼번에** 열람하고, **자신의 지방(provincia)에서 잘 팔리는 상품**을 인식해 그 지역 매장에 추천할 수 있어야 한다. 현재:

- Legacy `revendedores` 모듈은 카테고리 간접 접근만 있고 매장 명시 허가가 없다. TIPO 필터도 부정확(매칭 매장의 모든 로컬 카테고리 반환).
- 지역 신호(`sales.province_id` → `clients.province_id` 폴백)는 스키마상 존재하나 **`province × product` 결합 집계가 없다** — 추천 엔진의 핵심 갭.
- 운영 `sales.province_id` 채움률 23%로 희박 → POS 캡처 없이는 추천이 부실하다.

## 역할 정의 (Phase 24 와의 경계)

Phase 24 마켓플레이스는 revendedor 가 **고객에게 견적/주문(커미션)** 판매하는 B2B2C 흐름이다. 본 MVP 의 revendedor 는 **지역 어드바이저** — 자기 지방 베스트셀러를 인식해 **매장에 추천**한다. 견적/주문/정산은 범위 밖. revendedor 액션 = "Recomendar a tienda"(추천 로그), 주문 생성 아님.

MVP 는 Phase 24 의 **허가 모델(`reseller_tienda_link`) + canonical 카테고리 + 통합 카탈로그 기반만** 차용하고, 그 위에 지역 추천을 올린다.

## 추천 표면 2개 (혼동 방지)

같은 지역 베스트셀러 엔진을 두 곳에서 소비한다:

1. **vendedor → 고객** (핵심): 판매원 앱(`mobile-sales-app`, Flutter)의 기본 메뉴 버튼 아래 **"추천제품" 버튼**. 그 판매원 **매장에 재고 있는** 지역 베스트셀러를 보여줘 매장 손님에게 즉석 추천/업셀. 손님 provincia 선택 시 그 지방 기준으로 좁힘.
2. **revendedor → 매장** (어드바이저): 웹 포털에서 허가매장 통합 카탈로그를 열람하고, 자기 지방 인기 상품을 매장에 추천(`store_recommendations` 단순 로그). 매장측 inbox/알림은 후속.

## 확정 결정

| # | 결정 | 근거 |
|---|------|------|
| Z-1 | 플랫폼 = Phase 24 `reseller.*` 스키마 (legacy `revendedores` 와 혼용 금지) | 사용자 선택 B. mobile README 경고 준수 |
| Z-2 | 매장 허가 = `reseller.reseller_tienda_link(reseller_id, store_id, status)` 관리자 승인 | Phase 24 D-08. "허가된 매장" 정식 모델 |
| Z-3 | TIPO 통합 = `reseller.canonical_categories` + `public.categories.canonical_category_id` FK | Phase 24 D-28,29. 이름 exact-match 자동매핑(D-30 1단계) |
| Z-4 | 지역 신호 = `COALESCE(sales.province_id, clients.province_id)` (하이브리드) | 커버리지 최대화. 커밋된 fill-rate(sales 23%/clients 48%) |
| Z-5 | 추천 랭킹 = 최근 60일 판매량 + 지난 60일 대비 상승분(tendencia) 가중 | 사용자 선택. 유행/신상 포착, 오래된 스테디셀러 편중 방지 |
| Z-6 | 추천 그룹키 = `(provincia, store_id, canonical_category_id, product_id)` | 지방·매장·TIPO 별 상품 랭킹 |
| Z-7 | 집계는 `@Cron`(30분)으로 요약 테이블 `reseller.province_product_stats` 선계산, 런타임은 요약만 조회 | p95 ≤ 300ms 규약. slow query 방지 (100ms 규약) |
| Z-8 | 지역 데이터 없으면 매장 전체 베스트셀러로 폴백 | 초기 희박 데이터 graceful degrade |
| Z-9 | cross-store 재고 갭 추천: 지방 인기 상품 중 특정 허가매장 `stocks`=0 → 그 매장에 추천 | 사용자 핵심 아이디어 액션화 |
| Z-10 | revendedor GPS 지역감지: geolocation → `provinces` 중심좌표 최근접 매핑 → `resellers.province_id` 저장(수동 override 가능) | 외부 지오코딩 API 없이 오프라인·pool 무부하. AR 24개 주로 충분 |
| Z-11 | vendedor POS 지방 캡처: 결제 단계 provincia 빠른선택 → `sales.province_id` 기록 + 그 지방 추천 패널 | 데이터 플라이휠 + 판매원 업셀. 사용자 선택 C |
| Z-12 | 재고 정확수량 비공개 — `inStock` boolean 만 노출 | 기존 revendedor 패턴 유지 |
| Z-13 | 통합 카탈로그는 초기 직접 쿼리, 부하 크면 `catalog_unified` MV 로 승격 | YAGNI. MVP 규모에선 MV 오버킬 |
| Z-14 | vendedor "추천제품" 버튼 = `mobile-sales-app`(Flutter) 기본 메뉴 아래. 그 매장 **재고 있는** 지역 베스트셀러만 | 사용자 확정. 손님 즉석 추천/업셀. 표면 #1 |
| Z-15 | revendedor 클라이언트 = **웹 포털 먼저**(ventago-app), Flutter revendedor 앱은 후속 | 사용자 선택. 빠른 구축, GPS=브라우저 geolocation |
| Z-16 | POS 지방 캡처 = **스마트기본**(고객 province 프리필, 없으면 칩 유도, 비강제) | 사용자 선택. 마찰 최소 + 점진 상승 |
| Z-17 | revendedor 지방 = **단일 홈지방**(province_id 1개) | 사용자 선택. 단순·명확. 대부분 자기 지역 담당 |
| Z-18 | canonical 매핑 = superadmin + store admin, tendencia rank = `qty_60d × (1 + max(0,trend_pct)/100)` | 기본값 확정 |
| Z-19 | 신규 시작(legacy revendedores=0), provinces seed=AR 24개 주, canonical seed=운영 고유 카테고리명(39) 자동도출 | 운영 데이터 확인(2026-07-16): legacy 0, 국가 AR 1개, 카테고리 46/고유 39 |

## 컴포넌트 설계

### 1. 신규 스키마 `reseller` (최소분)

Phase 24 D-07 을 따라 별도 PG 스키마. Sequelize `schema: 'reseller'`.

```sql
CREATE SCHEMA IF NOT EXISTS reseller;

-- 재판매자 (legacy public.revendedores 와 별개. 지역 컬럼 추가)
CREATE TABLE reseller.resellers (
  id           SERIAL PRIMARY KEY,
  document     VARCHAR(40) UNIQUE,
  name         VARCHAR(160) NOT NULL,
  email        VARCHAR(160) UNIQUE,
  phone        VARCHAR(40),
  password     VARCHAR(200),              -- bcrypt
  province_id  INTEGER,                   -- provinces.id (GPS 감지 or 수동)
  province_source VARCHAR(12) DEFAULT 'manual',  -- 'gps' | 'manual'
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 매장 허가 (관리자 승인)
CREATE TABLE reseller.reseller_tienda_link (
  id           SERIAL PRIMARY KEY,
  reseller_id  INTEGER NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
  store_id     INTEGER NOT NULL,          -- public.stores.id
  status       VARCHAR(12) NOT NULL DEFAULT 'pending',  -- 'pending'|'approved'|'revoked'
  approved_by  INTEGER,                   -- public.users.id
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_reseller_store UNIQUE (reseller_id, store_id)
);

-- 전역 canonical 카테고리 (TIPO 통합)
CREATE TABLE reseller.canonical_categories (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL UNIQUE,
  slug       VARCHAR(120) NOT NULL UNIQUE,
  parent_id  INTEGER REFERENCES reseller.canonical_categories(id),
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 지역×상품 추천 요약 (Cron 선계산)
CREATE TABLE reseller.province_product_stats (
  id            SERIAL PRIMARY KEY,
  province_id   INTEGER NOT NULL,
  store_id      INTEGER NOT NULL,
  canonical_category_id INTEGER,
  product_id    INTEGER NOT NULL,
  qty_60d       INTEGER NOT NULL DEFAULT 0,   -- 최근 60일 판매량
  qty_prev_60d  INTEGER NOT NULL DEFAULT 0,   -- 그 이전 60일 (상승세 계산)
  trend_pct     NUMERIC(6,1),                 -- (qty_60d - prev)/prev * 100
  rank_in_prov  INTEGER,                      -- 지방 내 순위
  refreshed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_pps UNIQUE (province_id, store_id, product_id)
);
CREATE INDEX idx_pps_prov_cat ON reseller.province_product_stats (province_id, canonical_category_id, rank_in_prov);

-- 추천 액션 로그 (revendedor → store)
CREATE TABLE reseller.store_recommendations (
  id           SERIAL PRIMARY KEY,
  reseller_id  INTEGER NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
  store_id     INTEGER NOT NULL,
  product_id   INTEGER NOT NULL,
  province_id  INTEGER,
  reason       VARCHAR(20) NOT NULL,         -- 'zona_top' | 'stock_gap'
  note         VARCHAR(300),
  status       VARCHAR(12) NOT NULL DEFAULT 'sent',  -- 'sent'|'seen'|'accepted'|'dismissed'
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

`public.categories` 에 컬럼 추가(Phase 24 D-29):
```sql
ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS canonical_category_id INTEGER
    REFERENCES reseller.canonical_categories(id) ON DELETE SET NULL;
```

`public.provinces` 에 중심좌표 추가(Z-10):
```sql
ALTER TABLE public.provinces ADD COLUMN IF NOT EXISTS lat NUMERIC(9,6);
ALTER TABLE public.provinces ADD COLUMN IF NOT EXISTS lng NUMERIC(9,6);
```

owner + 시퀀스 → coolsistema 이전(role 존재체크 DO 블록). 로컬 5432 + 운영 5434 동시 적용.

### 2. 추천 집계 Cron (`ResellerStatsService`, 신규)

30분 주기 `@Cron`. `reseller.province_product_stats` 재계산:

```sql
-- 개념 (실제는 upsert). 지역 = COALESCE(sales.province_id, clients.province_id)
WITH lines AS (
  SELECT COALESCE(s.province_id, c.province_id) AS province_id,
         s.store_id, p.id AS product_id, cat.canonical_category_id,
         si.quantity, s.created_at
    FROM sale_items si
    JOIN sales s        ON s.id = si.sale_id
    LEFT JOIN clients c ON c.id = s.client_id
    JOIN products p     ON p.id = si.product_id
    LEFT JOIN categories cat ON cat.id = p.category_id
   WHERE s.created_at > NOW() - INTERVAL '120 days'
     AND COALESCE(s.province_id, c.province_id) IS NOT NULL
)
-- 60d / prev-60d 분리 집계 → trend_pct → rank_in_prov (province, canonical_category 파티션)
```

매장 = `sales.store_id`(직접 컬럼, 스키마 확인됨). `sales` 엔 `branch_id` 없음 — 지점 단위가 필요하면 `user_id → users.branch_id` 경유(본 MVP 는 store 단위라 불필요). ※배포 전 `sales.store_id` 채움률 확인.

**pool 안전:** Cron 은 단일 배치 쿼리 + upsert. `@Cron` 겹침 방지 가드(실행중 skip).

### 3. 추천 조회 API (`ResellerRecommendationController`, 신규)

- `GET /reseller/recommendations?provinceId&canonicalCategoryId` — 요약 테이블에서 revendedor 지방 top-N(허가매장 한정). 없으면 매장 전체 베스트셀러 폴백(Z-8).
- `GET /reseller/recommendations/stock-gap` — 지방 인기인데 허가매장 재고 0 (Z-9).
- `POST /reseller/recommendations` — "Recomendar a tienda" (store_recommendations insert).

전부 `reseller.province_product_stats` 요약만 읽음(런타임 무거운 조인 없음).

### 4. 통합 카탈로그 API (`ResellerCatalogController`, 신규)

- `GET /reseller/catalog?canonicalCategoryId&storeId&search&page` — 허가매장(approved link) × canonical_category 필터. `inStock` boolean 만. Z-13(직접 쿼리, pageSize ≤ 50).
- `GET /reseller/canonical-categories` — TIPO 탭 목록.

### 5. GPS 지역감지 (`resellers.province_id`)

- 프론트: revendedor 로그인 후 `navigator.geolocation.getCurrentPosition()`(권한 요청). 좌표 → `POST /reseller/detect-province {lat,lng}`.
- 백엔드: `provinces` 중심좌표와 최근접(하버사인 or 단순 유클리드, 24개 주라 무차별대입 OK) → `province_id`. `province_source='gps'`. 실패/거부 시 수동 선택 UI.

### 6. vendedor 앱: 지방 캡처 + "추천제품" 버튼 (`mobile-sales-app`, Flutter)

판매원 앱(mobile-sales-app)에 두 가지 추가:

**(a) 지방 캡처 (`sales.province_id`)** — Z-16 스마트기본:
- 판매 시 provincia 자동 프리필(고객 `clients.province_id`). 없으면 빠른선택 칩 유도(비강제). 판매 생성 payload 에 `provinceId` → `sales.province_id` 저장. 데이터 플라이휠.

**(b) "추천제품" 버튼** — 기본 메뉴 버튼 아래(Z-14):
- 탭 시 그 판매원 **매장에 재고 있는**(`stocks > 0`) 지역 베스트셀러 목록. 손님 provincia 선택되어 있으면 그 지방 기준, 아니면 매장 전체 베스트셀러.
- 내부용 엔드포인트 `GET /mobile/recommended-products?provinceId`(user/vendedor JWT + 자기 store 스코프, reseller JWT 아님). 응답 = `province_product_stats` ⨝ 자기 매장 재고>0, 랭킹순.
- 목적: 손님에게 즉석 추천/업셀. 선택 상품을 바로 장바구니로 담기 가능(기존 판매 흐름 연결).

### 7. 프론트 UI

- **revendedor 포털(웹 신규)** `ventago-app/src/views/revendedor/`: mockup 대로 — 상단 zona chip, "Recomendado para {provincia}" 강조 레일(🔥 badge + 순위 + 상승세), 허가매장 칩, TIPO 탭, 상품 그리드(zona top 골드 강조), "Recomendar a tienda" 버튼. 코드 스플리팅(`next/dynamic`), SWR 캐시(canonical-categories 참조데이터).
- **관리자**: 매장 허가 승인 화면(`reseller_tienda_link` status), canonical 카테고리 매핑(미매핑 목록 + 드롭다운). CASL `revendedor_admin`(Phase 24 D-26).
- **vendedor 앱(`mobile-sales-app`, Flutter)**: 판매 시 provincia 스마트기본 캡처 + 기본 메뉴 아래 "추천제품" 버튼(매장 재고 있는 지역 베스트셀러 → 손님 추천 → 장바구니 담기). Riverpod, 기존 판매 흐름 연결. mobile-sales-app 은 별도 nested repo(커밋/푸시 분리).

## 데이터 흐름

```
[Cron 30분] sale_items×sales×clients×categories → province_product_stats (60d+trend+rank)
[revendedor] GPS → province_id → GET /reseller/recommendations → zona 강조 카탈로그 → Recomendar
[vendedor 앱] 판매 시 provincia 스마트기본 → sales.province_id 기록(플라이휠)
              "추천제품" 버튼 → GET /mobile/recommended-products → 매장 재고>0 지역 top → 손님 추천 → 장바구니
[관리자] reseller_tienda_link 승인 + canonical 매핑
```

## 에러 핸들링

- geolocation 거부/실패 → 수동 provincia 선택 폴백(인라인 Alert + 토스트, 에러 가시성 규약).
- 지역 데이터 없음 → 매장 전체 베스트셀러 폴백(빈 화면 금지).
- 미허가 매장 접근 → 403.

## 테스트 전략

**백엔드(jest)**
- `ResellerStatsService`: 60d/prev-60d 분리, trend_pct, rank, province 폴백(sales null→client), canonical 매핑 join.
- 추천 API: 허가매장 한정, 폴백, stock-gap(재고0 필터).
- detect-province: 최근접 매핑, 경계값, 좌표 없음.
- 허가 가드: 미승인 link 403.
- POS 캡처: sales.province_id 저장(스마트기본), 고객 province 프리필.
- `GET /mobile/recommended-products`: 자기 매장 재고>0 필터, 지방 랭킹순, provincia 없으면 매장 베스트셀러 폴백, 타 매장 재고 노출 안 됨.

**프론트(웹)**
- revendedor: zona 강조 렌더, TIPO 탭 필터, GPS 권한 거부 폴백, Recomendar 액션.

**mobile-sales-app(Flutter, 위젯/프로바이더)**
- "추천제품" 버튼 노출, 재고 있는 항목만 표시, 항목 → 장바구니, provincia 미선택 시 폴백.

## 범위 외 (YAGNI / 후속)

- quotes/orders/정산/커미션 (Phase 24 Wave 3~4)
- 출근 지오펜스 anti-fraud (별도 슬라이스 R3 — `stores.lat/lng` + QR GPS 검증)
- `catalog_unified` MV, 수수료 정책 전체(`tienda_sharing_policy`)
- Flutter **revendedor** 앱(웹 포털 먼저) — 단 **vendedor** 앱(mobile-sales-app) "추천제품"·지방 캡처는 범위 내(Z-14)
- 외부 지오코딩(정밀 도시단위) — 현 MVP 는 주(province) 단위
- canonical 매핑 자동제안(D-30 3단계), 수동매핑 UI 고도화

## 마이그레이션 / 배포

- `reseller` 스키마 + 테이블 + `categories.canonical_category_id` + `provinces.lat/lng`. 로컬 5432 + 운영 5434 동시. owner→coolsistema.
- canonical seed(~50개, 운영 카테고리 분석 후) + 이름 exact-match 자동매핑 배치.
- `provinces` 중심좌표 seed(AR 24개 주).
- pool: 기존 전역 재사용, Cron 단일 배치, 런타임은 요약 조회.
- 배포 순서: 마이그레이션 → 백엔드 → 프론트.
