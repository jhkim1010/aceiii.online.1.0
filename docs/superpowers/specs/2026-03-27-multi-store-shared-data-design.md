# 멀티 스토어 공유 데이터 아키텍처 설계

<!--
============================================================================
설계 문서 개요 (Design Spec Overview)
============================================================================

이 문서는 ACE Online 시스템의 멀티 스토어 공유 데이터 아키텍처 설계서이다.
기존 매장별 완전 격리 구조에서 전역 공유 + 매장별 격리 2계층 구조로 전환하는
전체 설계를 담고 있다.

[문서의 목적]
- DB 스키마 설계 (테이블, 인덱스, 제약조건)
- API 백엔드 모듈 구조 (NestJS)
- 인증 및 권한 구조 (JWT, Guard)
- 데이터 마이그레이션 전략 (기존 → 신규)
- 보안 및 데이터 격리 규칙

[구현 상태 (2026-03-27 기준)]
- 구현 완료: shared 모듈 (global-clients, store-clients, global-categories 등)
- 구현 완료: marketplace 모듈 (config, visibility, public-products, public-purchase)
- 미구현: revendedor 모듈 (향후 구현 예정)
- 미구현: 결제 통합, 주문 추적, 수수료 정산 (FOUNDATION - 향후 확장)

[관련 코드]
- api-ventago/src/app/shared/: 공유 데이터 모듈
- api-ventago/src/app/marketplace/: 마켓플레이스 모듈
- api-ventago/src/database/migrations/migrate-to-shared-data.ts: 마이그레이션 스크립트
============================================================================
-->

## Context

<!--
[컨텍스트 설명]
이 섹션은 왜 이 설계가 필요한지, 현재 시스템의 한계와 목표를 설명한다.
핵심 키워드: 매장별 격리 → 매장간 공유 전환, 500개+ 매장 확장, re-vendedor, 마켓플레이스
-->

현재 ACE Online 시스템은 41개 모델이 `storeId` FK로 **매장별 완전 격리** 구조입니다.
500개 이상 매장 확장을 대비하여, 고객(clientes)과 카테고리(tipos) 데이터를 매장 간 공유하고,
re-vendedor 앱과 향후 공개 마켓플레이스를 위한 기반 구조를 만들어야 합니다.

**핵심 원칙:**
- 고객 기본정보(이름, 주소, 전화)는 전 매장 공유
- 구매내역, 외상 정보는 매장별 완전 격리 <!-- 보안상 가장 중요한 원칙 -->
- 위험 고객 경고는 전 매장 공유 <!-- 모든 매장이 위험 고객을 인지해야 함 -->
- 카테고리/서브카테고리는 공유 마스터 + 매장별 선택(체크박스)
- re-vendedor는 카테고리 기반으로 여러 매장 제품을 브라우징하고 구매

**작업 범위:** DB 스키마(마이그레이션) + API 백엔드(NestJS 모듈) - 프론트엔드 UI는 별도 작업

---

## 1. 데이터베이스 스키마

<!--
[DB 스키마 설계 원칙]
1. Global + Store 2계층 구조:
   - global_* 테이블: 매장 간 공유되는 마스터 데이터 (이름, 전화, 카테고리명 등)
   - store_* 테이블: 매장별 비공개 데이터 (외상, 메모, 잔액 등)
2. 비파괴적 마이그레이션: 기존 테이블(clients, categories)은 변경하지 않음
3. 인덱스 전략: 검색 성능 + 유니크 제약 + 부분 인덱스 활용
4. CASCADE 삭제: 부모 삭제 시 관련 데이터 자동 정리
-->

### 1.1 공유 고객 시스템

<!--
[공유 고객 시스템 구조]
기존: clients (매장별 독립)
신규: global_clients (전역 공유) + store_clients (매장별 비공개)

[핵심 식별 전략]
- document(DNI/CUIT) 우선: 유일한 식별자, 여러 매장에서 같은 고객 인식
- fullname+phone 보조: document가 없는 고객을 위한 대안 식별
- 부분 인덱스(idx_global_clients_name_phone): document IS NULL일 때만 적용
-->

#### `global_clients` - 전체 공유 고객 마스터

```sql
CREATE TABLE global_clients (
    id SERIAL PRIMARY KEY,
    -- 고객 식별: document 우선, 없으면 fullname+phone 조합
    document VARCHAR(50) UNIQUE,          -- DNI/CUIT (nullable, 있으면 고유 식별자)
    fullname VARCHAR(255) NOT NULL,
    name_fantasy VARCHAR(255),
    phone VARCHAR(100),
    email VARCHAR(255),
    address TEXT,
    location VARCHAR(255),
    province_id INTEGER REFERENCES provinces(id),
    transport VARCHAR(255),
    res_iva VARCHAR(50),

    -- 위험 고객 관리 (전 매장 공유)
    is_risky BOOLEAN DEFAULT FALSE,       -- 위험 고객 플래그
    risky_reason TEXT,                     -- 위험 등록 사유
    risky_registered_by_store_id INTEGER REFERENCES stores(id), -- 위험 등록한 매장
    risky_registered_at TIMESTAMP,        -- 위험 등록 시점

    -- 메타데이터
    created_by_store_id INTEGER REFERENCES stores(id) NOT NULL, -- 최초 등록 매장
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- document 없는 고객의 중복 방지: fullname + phone 조합
    CONSTRAINT uq_global_client_identity
        UNIQUE NULLS NOT DISTINCT (document)
);

-- document 없는 고객을 위한 부분 인덱스
CREATE UNIQUE INDEX idx_global_clients_name_phone
    ON global_clients (LOWER(fullname), LOWER(phone))
    WHERE document IS NULL AND phone IS NOT NULL;

-- 검색 성능 인덱스
CREATE INDEX idx_global_clients_fullname ON global_clients (LOWER(fullname));
CREATE INDEX idx_global_clients_phone ON global_clients (phone);
CREATE INDEX idx_global_clients_is_risky ON global_clients (is_risky) WHERE is_risky = TRUE;
```

#### `store_clients` - 매장별 고객 관계 (비공개 데이터)

```sql
CREATE TABLE store_clients (
    id SERIAL PRIMARY KEY,
    global_client_id INTEGER NOT NULL REFERENCES global_clients(id) ON DELETE CASCADE,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,

    -- 매장별 비공개 데이터
    is_active BOOLEAN DEFAULT TRUE,
    note TEXT,                             -- 매장별 메모 (비공개)
    credit_limit DECIMAL(12,2) DEFAULT 0,  -- 매장별 외상 한도
    balance DECIMAL(12,2) DEFAULT 0,       -- 매장별 잔액/외상 (비공개)
    internal_code VARCHAR(50),             -- 매장 내부 고객 코드

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- 한 매장에서 같은 고객은 한 번만
    CONSTRAINT uq_store_client UNIQUE (global_client_id, store_id)
);

CREATE INDEX idx_store_clients_store ON store_clients (store_id);
CREATE INDEX idx_store_clients_global ON store_clients (global_client_id);
```

**관계 설명:**
- `sales.client_id` → `store_clients.id` (매장별 고객 관계 참조)
- `ventas_suspendidas.client_id` → `store_clients.id`
- 다른 매장의 `store_clients` 데이터(잔액, 외상, 메모)는 절대 접근 불가
- `global_clients.is_risky`는 모든 매장에서 조회 가능

---

### 1.2 공유 카테고리 시스템

#### `global_categories` - 전체 공유 카테고리 마스터

```sql
CREATE TABLE global_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,     -- 카테고리명 (전체 유일)
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_by_store_id INTEGER REFERENCES stores(id) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_global_categories_name ON global_categories (LOWER(name));
```

#### `global_subcategories` - 전체 공유 서브카테고리

```sql
CREATE TABLE global_subcategories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    global_category_id INTEGER NOT NULL REFERENCES global_categories(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT TRUE,
    created_by_store_id INTEGER REFERENCES stores(id) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- 같은 카테고리 내에서 서브카테고리명 유일
    CONSTRAINT uq_global_subcategory UNIQUE (name, global_category_id)
);

CREATE INDEX idx_global_subcategories_category ON global_subcategories (global_category_id);
```

#### `store_categories` - 매장별 카테고리 선택 (체크박스)

```sql
CREATE TABLE store_categories (
    id SERIAL PRIMARY KEY,
    global_category_id INTEGER NOT NULL REFERENCES global_categories(id) ON DELETE CASCADE,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT TRUE,       -- 매장에서 이 카테고리 사용 여부
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_store_category UNIQUE (global_category_id, store_id)
);

CREATE INDEX idx_store_categories_store ON store_categories (store_id);
```

#### `store_subcategories` - 매장별 서브카테고리 선택

```sql
CREATE TABLE store_subcategories (
    id SERIAL PRIMARY KEY,
    global_subcategory_id INTEGER NOT NULL REFERENCES global_subcategories(id) ON DELETE CASCADE,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_store_subcategory UNIQUE (global_subcategory_id, store_id)
);

CREATE INDEX idx_store_subcategories_store ON store_subcategories (store_id);
```

---

### 1.3 Re-vendedor 시스템

<!--
[Re-vendedor 시스템 - 미구현 (FOUNDATION)]
Re-vendedor(재판매상)는 여러 매장의 제품을 카테고리 기반으로 브라우징하고 구매하는 사용자.
마켓플레이스와 달리 Re-vendedor는 자체 인증 시스템(별도 JWT)을 사용한다.

[마켓플레이스 vs Re-vendedor 차이]
- 마켓플레이스: 비인증 소비자, 누구나 접근, seller_name="WEB"
- Re-vendedor: 인증된 재판매상, 전용 JWT, seller_name="REVENDEDOR:{name}"

[구현 상태] DB 스키마만 설계됨, NestJS 모듈은 미구현
-->

#### `revendedores` - Re-vendedor 계정

```sql
CREATE TABLE revendedores (
    id SERIAL PRIMARY KEY,
    document VARCHAR(50) UNIQUE NOT NULL,  -- DNI/CUIT (필수)
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(100),
    password VARCHAR(255) NOT NULL,        -- bcrypt 해시
    address TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_revendedores_email ON revendedores (LOWER(email));
CREATE INDEX idx_revendedores_document ON revendedores (document);
```

#### `revendedor_categories` - Re-vendedor의 관심 카테고리

```sql
CREATE TABLE revendedor_categories (
    id SERIAL PRIMARY KEY,
    revendedor_id INTEGER NOT NULL REFERENCES revendedores(id) ON DELETE CASCADE,
    global_category_id INTEGER NOT NULL REFERENCES global_categories(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_revendedor_category UNIQUE (revendedor_id, global_category_id)
);

CREATE INDEX idx_revendedor_categories_rev ON revendedor_categories (revendedor_id);
```

**Re-vendedor 구매 플로우:**
1. Re-vendedor가 카테고리 선택
2. 해당 카테고리를 `store_categories.is_enabled = true`로 사용하는 모든 매장의 제품 조회
3. 제품 선택 및 구매 → 각 매장의 `ventas_suspendidas`에 등록
   - `seller_name` = `"REVENDEDOR:{revendedor.name}"`
   - `client_id` = re-vendedor의 `store_clients` 레코드 (자동 생성)

---

### 1.4 마켓플레이스 기반 구조 (향후 확장용)

<!--
[마켓플레이스 시스템 - 구현 완료 (FOUNDATION)]
이 섹션의 모든 테이블과 API가 구현되었다:
- marketplace_config: 매장별 마켓플레이스 참여 설정
- product_visibility: 개별 제품의 공개 여부 및 전용 가격

[구현된 API 엔드포인트]
비공개 (JWT 필요):
  GET/PUT /marketplace/config          - 매장 설정 관리
  GET/POST/PUT /marketplace/visibility - 제품 공개 관리

공개 (인증 불필요):
  GET /marketplace/products            - 공개 제품 검색/브라우징
  POST /marketplace/purchase           - 구매 처리 (자동 고객 등록)

[향후 확장 (미구현)]
결제 통합, 주문 추적, 수수료 정산, 리뷰, 알림 등
-->

#### `marketplace_config` - 매장별 마켓플레이스 설정

```sql
CREATE TABLE marketplace_config (
    id SERIAL PRIMARY KEY,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE UNIQUE,
    is_published BOOLEAN DEFAULT FALSE,    -- 마켓플레이스에 제품 공개 여부
    commission_rate DECIMAL(5,2) DEFAULT 0, -- 수수료율 (%)
    store_description TEXT,                -- 마켓플레이스에 표시할 매장 설명
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

#### `product_visibility` - 마켓플레이스 공개 제품

```sql
CREATE TABLE product_visibility (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    is_visible BOOLEAN DEFAULT TRUE,       -- 마켓플레이스에서 보이는지
    marketplace_price DECIMAL(12,2),       -- 마켓플레이스 전용 가격 (NULL이면 원래 가격 사용)
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_product_visibility UNIQUE (product_id, store_id)
);

CREATE INDEX idx_product_visibility_visible
    ON product_visibility (store_id) WHERE is_visible = TRUE;
```

**마켓플레이스 구매 플로우:**
1. 비로그인 사용자가 공개 제품 검색/브라우징
2. 구매 시 기본 정보 입력 (이름, 전화, 주소)
3. `global_clients`에 자동 등록 (document 우선 매칭, 없으면 생성)
4. 해당 매장의 `store_clients` 자동 생성
5. `ventas_suspendidas`에 등록: `seller_name = "WEB"`

---

## 2. API 백엔드 구조 (NestJS 모듈)

<!--
[NestJS 모듈 아키텍처]
3개의 새로운 모듈로 구성:

1. shared/ (구현 완료)
   - 전역 고객, 매장별 고객, 전역 카테고리 등
   - 모든 엔드포인트에 JWT 인증 필요 (매장 사용자)
   - storeId 기반 데이터 격리 보장

2. marketplace/ (구현 완료)
   - config, visibility: JWT 인증 필요 (매장 소유자)
   - public-products, public-purchase: 인증 불필요 (공개 API)
   - 구매 시 notes="WEB"으로 마켓플레이스 식별

3. revendedor/ (미구현 - 설계만 완료)
   - 별도 JWT 인증 (RevendedorJwtStrategy)
   - 카테고리 기반 크로스 매장 제품 조회
   - 구매 시 seller_name="REVENDEDOR:{name}"으로 식별
-->

### 2.1 새로운 모듈 구조

```
api-ventago/src/app/
├── shared/                              # 공유 데이터 모듈 (신규)
│   ├── shared.module.ts
│   ├── global-clients/
│   │   ├── global-clients.model.ts      # Sequelize 모델
│   │   ├── global-clients.service.ts    # 비즈니스 로직
│   │   ├── global-clients.controller.ts # REST API
│   │   └── dto/
│   │       ├── create-global-client.dto.ts
│   │       └── update-global-client.dto.ts
│   ├── store-clients/
│   │   ├── store-clients.model.ts
│   │   ├── store-clients.service.ts
│   │   ├── store-clients.controller.ts
│   │   └── dto/
│   ├── global-categories/
│   │   ├── global-categories.model.ts
│   │   ├── global-categories.service.ts
│   │   ├── global-categories.controller.ts
│   │   └── dto/
│   ├── store-categories/
│   │   ├── store-categories.model.ts
│   │   ├── store-categories.service.ts
│   │   ├── store-categories.controller.ts
│   │   └── dto/
│   ├── global-subcategories/
│   │   ├── global-subcategories.model.ts
│   │   ├── global-subcategories.service.ts
│   │   ├── global-subcategories.controller.ts
│   │   └── dto/
│   └── store-subcategories/
│       ├── store-subcategories.model.ts
│       ├── store-subcategories.service.ts
│       ├── store-subcategories.controller.ts
│       └── dto/
│
├── revendedor/                          # Re-vendedor 모듈 (신규)
│   ├── revendedor.module.ts
│   ├── revendedor.model.ts
│   ├── revendedor.service.ts
│   ├── revendedor.controller.ts
│   ├── revendedor-auth.service.ts       # Re-vendedor 전용 인증
│   ├── revendedor-auth.controller.ts
│   ├── revendedor-categories/
│   │   ├── revendedor-categories.model.ts
│   │   └── revendedor-categories.service.ts
│   ├── revendedor-products/
│   │   ├── revendedor-products.service.ts   # 카테고리 기반 크로스 매장 제품 조회
│   │   └── revendedor-products.controller.ts
│   ├── revendedor-purchase/
│   │   ├── revendedor-purchase.service.ts   # 구매 → ventas_suspendidas 생성
│   │   └── revendedor-purchase.controller.ts
│   ├── guards/
│   │   └── revendedor-auth.guard.ts
│   ├── strategies/
│   │   └── revendedor-jwt.strategy.ts
│   └── dto/
│
├── marketplace/                         # 마켓플레이스 모듈 (신규, 향후 확장용)
│   ├── marketplace.module.ts
│   ├── marketplace-config/
│   │   ├── marketplace-config.model.ts
│   │   └── marketplace-config.service.ts
│   ├── product-visibility/
│   │   ├── product-visibility.model.ts
│   │   └── product-visibility.service.ts
│   ├── public-products/                 # 비인증 공개 API
│   │   ├── public-products.service.ts
│   │   └── public-products.controller.ts
│   ├── public-purchase/                 # 비인증 구매 API
│   │   ├── public-purchase.service.ts
│   │   └── public-purchase.controller.ts
│   └── dto/
```

### 2.2 핵심 API 엔드포인트

#### 공유 고객 API

```
# 글로벌 고객 (모든 인증된 매장 접근 가능)
GET    /api/shared/global-clients          # 공유 고객 목록 (검색/페이지네이션)
GET    /api/shared/global-clients/:id      # 공유 고객 상세 (공개 정보만)
POST   /api/shared/global-clients          # 고객 등록 (document 중복 체크)
PUT    /api/shared/global-clients/:id      # 고객 기본정보 수정
PATCH  /api/shared/global-clients/:id/risky # 위험 고객 플래그 설정/해제

# 매장별 고객 관계 (해당 매장만 접근)
GET    /api/shared/store-clients           # 내 매장의 고객 관계 목록
POST   /api/shared/store-clients           # 고객을 내 매장에 연결
PUT    /api/shared/store-clients/:id       # 매장별 메모/외상 등 수정
DELETE /api/shared/store-clients/:id       # 내 매장에서 고객 연결 해제
```

#### 공유 카테고리 API

```
# 글로벌 카테고리 (모든 인증된 매장 접근 가능)
GET    /api/shared/global-categories       # 전체 카테고리 목록
POST   /api/shared/global-categories       # 카테고리 추가
PUT    /api/shared/global-categories/:id   # 카테고리 수정

# 매장별 카테고리 선택 (해당 매장만)
GET    /api/shared/store-categories        # 내 매장이 선택한 카테고리 목록
POST   /api/shared/store-categories/toggle # 카테고리 활성화/비활성화 토글
```

#### Re-vendedor API

```
# 인증
POST   /api/revendedor/auth/register       # Re-vendedor 회원가입
POST   /api/revendedor/auth/login          # Re-vendedor 로그인
GET    /api/revendedor/auth/me             # 현재 Re-vendedor 정보

# 카테고리 관리
GET    /api/revendedor/categories          # 전체 카테고리 목록
POST   /api/revendedor/categories/select   # 관심 카테고리 선택/해제

# 제품 브라우징 (크로스 매장)
GET    /api/revendedor/products            # 선택한 카테고리의 전 매장 제품
GET    /api/revendedor/products/:id        # 제품 상세 (매장 정보 포함)

# 구매
POST   /api/revendedor/purchase            # 구매 → ventas_suspendidas 생성
GET    /api/revendedor/purchase/history     # 구매 이력
```

#### 마켓플레이스 API (향후, 비인증)

```
# 공개 (인증 불필요)
GET    /api/marketplace/products           # 공개 제품 검색/브라우징
GET    /api/marketplace/products/:id       # 제품 상세
GET    /api/marketplace/categories         # 공개 카테고리 목록

# 구매 (간단한 정보 입력만 필요)
POST   /api/marketplace/purchase           # 구매 → global_client 등록 + ventas_suspendidas
```

---

<!--
[API 엔드포인트 보안 분류]
비공개 (JWT 필요): /api/shared/*, /marketplace/config, /marketplace/visibility, /api/revendedor/*
공개 (인증 불필요): /marketplace/products, /marketplace/purchase
-->

## 3. 인증 및 권한 구조

### 3.1 기존 매장 사용자 인증 (변경 없음)
- JWT에 `storeId` 포함
- 기존 `JwtStrategy` + `UserRoleGuard` 그대로 사용

### 3.2 Re-vendedor 전용 인증 (신규)
```typescript
// Re-vendedor JWT 페이로드
{
    id: number;           // revendedor.id
    type: 'revendedor';   // 사용자 유형 구분
    name: string;
    email: string;
}
```
- 별도 JWT Strategy (`RevendedorJwtStrategy`)
- 별도 Guard (`RevendedorAuthGuard`)
- 매장 사용자 JWT와 구분: `type` 필드로 식별

### 3.3 데이터 접근 제어 규칙

| 데이터 | 같은 매장 | 다른 매장 | Re-vendedor | 공개(마켓플레이스) |
|--------|----------|----------|-------------|------------------|
| 고객 기본정보 (이름, 주소, 전화) | ✅ 읽기/쓰기 | ✅ 읽기 | ❌ | ❌ |
| 고객 외상/잔액 | ✅ 읽기/쓰기 | ❌ 절대 불가 | ❌ | ❌ |
| 고객 구매 내역 | ✅ 읽기 | ❌ 절대 불가 | ❌ | ❌ |
| 위험 고객 경고 | ✅ 읽기/쓰기 | ✅ 읽기(경고만) | ❌ | ❌ |
| 카테고리 마스터 | ✅ 읽기/쓰기 | ✅ 읽기 | ✅ 읽기 | ✅ 읽기 |
| 매장 카테고리 선택 | ✅ 읽기/쓰기 | ❌ | ❌ | ❌ |
| 제품 목록 | ✅ 전체 | ❌ | ✅ 가격/이름만 | ✅ 공개분만 |
| 재고 정보 | ✅ 전체 | ❌ | ✅ 유/무만 | ✅ 유/무만 |

---

<!--
[인증 모델 정리]
1. 매장 사용자: 기존 JwtStrategy (JWT에 storeId 포함) → 변경 없음
2. Re-vendedor: 별도 RevendedorJwtStrategy (JWT에 type:'revendedor' 포함) → 미구현
3. 마켓플레이스 공개 API: 인증 없음 (AuthGuard 미적용)

[핵심 보안 원칙]
- 매장 A의 토큰으로 매장 B의 store_clients 접근 불가 (403)
- Re-vendedor 토큰으로 매장 관리 API 접근 불가 (401)
- store_clients의 외상/잔액/메모는 해당 매장에서만 접근 가능
-->

## 4. 데이터 마이그레이션 전략

<!--
[마이그레이션 전략 요약]
비파괴적 + 점진적 전환:
Phase 1: 새 테이블 생성 (기존 테이블 변경 없음, 서비스 중단 없음)
Phase 2: 데이터 복사 + 중복 병합 (migrate-to-shared-data.ts)
Phase 3: FK 전환 (sales.client_id → store_clients.id) - 향후
Phase 4: 기존 테이블 deprecated - 향후

[구현된 마이그레이션 스크립트]
api-ventago/src/database/migrations/migrate-to-shared-data.ts
- Phase 1 + 2를 담당
- 트랜잭션으로 원자성 보장
- ON CONFLICT DO NOTHING으로 재실행 안전
-->

### 4.1 단계별 마이그레이션

**Phase 1: 새 테이블 생성 (비파괴적)**
- `global_clients`, `store_clients`, `global_categories` 등 새 테이블 생성
- 기존 테이블 변경 없음 → 서비스 중단 없음

**Phase 2: 데이터 마이그레이션**
- 기존 `clients` → `global_clients` + `store_clients`로 복사
  - `document`가 같으면 같은 `global_client`로 병합
  - `document`가 없으면 `fullname + phone`으로 매칭
- 기존 `categories` → `global_categories` + `store_categories`로 복사
  - `name`이 같으면 같은 `global_category`로 병합

**Phase 3: FK 전환**
- `sales.client_id` → `store_clients.id`로 전환
- `products.category_id` → 기존 유지 또는 `global_categories.id`로 전환

**Phase 4: 기존 테이블 deprecated**
- 기존 `clients`, `categories` 테이블은 유지하되 점진적으로 사용 중단

### 4.2 안전장치
- 모든 마이그레이션은 롤백 스크립트 포함
- 기존 데이터 백업 후 진행
- 새 API는 기존 API와 병행 운영 (하위 호환)

---

## 5. 위험 고객 경고 시스템

### 5.1 경고 발생 조건
- `global_clients.is_risky = true`인 고객이 판매 대상으로 선택될 때
- 모든 매장에서 동일하게 경고 발생

### 5.2 경고 응답 형식
```typescript
// GET /api/shared/global-clients/:id 응답에 포함
{
    id: 1,
    fullname: "Juan Pérez",
    // ... 기본 정보 ...
    isRisky: true,
    riskyReason: "수표 부도 3회",
    riskyRegisteredByStore: "Tienda Central",  // 어떤 매장이 등록했는지
    riskyRegisteredAt: "2026-03-15T10:00:00Z"
}
```

### 5.3 판매 시 자동 체크
- 기존 판매 플로우에서 고객 선택 시 `is_risky` 확인
- `is_risky = true`이면 경고 메시지와 사유 표시
- 판매 자체를 차단하지는 않음 (경고만) - 매장이 판단

---

## 6. 검증 방법

### 6.1 마이그레이션 검증
```bash
# 새 테이블 생성 후
npm run migrate  # 또는 Sequelize sync

# 데이터 마이그레이션 후 카운트 비교
SELECT COUNT(*) FROM clients;          -- 기존
SELECT COUNT(*) FROM global_clients;   -- 신규 (중복 병합으로 더 적을 수 있음)
SELECT COUNT(*) FROM store_clients;    -- 기존 clients와 동일해야 함
```

### 6.2 API 테스트
```bash
# 공유 고객 API
curl -H "Authorization: Bearer {token_A}" GET /api/shared/global-clients  # 매장 A 토큰
curl -H "Authorization: Bearer {token_B}" GET /api/shared/global-clients  # 매장 B 토큰 - 같은 결과

# 매장별 고객 데이터 격리 확인
curl -H "Authorization: Bearer {token_A}" GET /api/shared/store-clients   # 매장 A의 외상/메모만
curl -H "Authorization: Bearer {token_B}" GET /api/shared/store-clients   # 매장 B의 외상/메모만 (A 데이터 없음)

# 위험 고객 경고
curl -H "Authorization: Bearer {token_A}" PATCH /api/shared/global-clients/1/risky  # A에서 위험 등록
curl -H "Authorization: Bearer {token_B}" GET /api/shared/global-clients/1           # B에서도 위험 표시 확인

# Re-vendedor 제품 조회
curl -H "Authorization: Bearer {revendedor_token}" GET /api/revendedor/products?categoryId=1
# → 해당 카테고리를 사용하는 모든 매장의 제품 반환
```

### 6.3 보안 검증
- 매장 A 토큰으로 매장 B의 `store_clients` 접근 시도 → 403 Forbidden
- Re-vendedor 토큰으로 매장 관리 API 접근 시도 → 401 Unauthorized
- 비인증 요청으로 매장 데이터 접근 시도 → 401 Unauthorized
