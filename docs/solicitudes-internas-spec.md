# Solicitudes Internas — 사내 구매요청 / 장비 수리의뢰 / 자산·소모품 모듈

> 목업: `mockups/solicitudes-internas-mockup.html` (외부 CDN 의존 없음 · 데스크톱 1440px 기준)
> 결정 사항: 구매+수리 **통합** / **승인 단계 포함** / Telegram **단방향 알림** /
> **내 장비 목록 + 소모품 카탈로그 + 보유 수량 관리** 포함

## 0. 단일 페이지 구조 ★

**페이지는 `/solicitudes` 하나뿐이다. 사이드바 서브메뉴는 만들지 않는다.**
같은 URL이 역할(`superadmin` vs 매장 `admin`)에 따라 다른 내용을 렌더한다.

```
┌─ KPI 4 ─────────────────────────────────────────────────────┐
├─ (매장 admin 전용) 저재고 경고 바 ─────────────────────────┤
├──────────────────────────────┬──────────────────────────────┤
│  요청 목록                    │  우측 레일                    │
│  · 필터/검색 툴바             │                              │
│  · 행 클릭 → 인라인 상세      │  [매장 admin]                │
│    (타임라인·비용·코멘트·     │   탭 ① Mis equipos           │
│     승인 버튼·장비 이력)      │      → 행에서 바로 "Reparar" │
│                              │   탭 ② Insumos               │
│                              │      → 잔량 + 스테퍼 + 장바구니│
│                              │                              │
│                              │  [superadmin]                │
│                              │   · 소진 빠른 부품 랭킹       │
│                              │   · 매장별 현황               │
└──────────────────────────────┴──────────────────────────────┘
       + "Nueva solicitud" 모달 (버튼 또는 장비행 Reparar 로 열림)
```

### 역할별로 보이는 것

| | 매장 admin | superadmin |
|---|---|---|
| KPI | 승인대기 / 진행중 / 당월 지출 / 부족 소모품 | 승인대기 / 진행중(전 매장) / **지연 7일+** / 총비용 |
| 목록 컬럼 | 코드·타입·제목·상태·비용·일자 | + **Tienda** · **Espera(대기일)** |
| 필터 | 타입·상태·검색 | + **매장 선택** |
| 인라인 상세 | 상태 타임라인·비용·코멘트·장비 이력 | + **승인/거절 버튼** · 반복수리 경고 |
| 우측 레일 | 내 장비 / 소모품 (탭) | **소진 랭킹** / 매장 현황 |
| 생성 버튼 | 있음 | 없음 (superadmin은 대행 생성하지 않음) |

### 왜 한 페이지인가

- 매장 admin이 하는 일은 **① 의뢰하고 ② 상태·비용 보고 ③ 소모품 채우기** 3가지뿐이다. 페이지를 나누면 왕복만 늘어난다.
- 인라인 아코디언 상세는 **라우팅이 없어 API 왕복이 없다** — 목록 응답에 상세를 함께 담아 오면 클릭이 즉시 반응한다.
- 우측 레일의 장비 행 `Reparar` 가 그대로 모달을 열고 `assetId` 를 프리필한다. 백지에서 쓰게 하지 않는 게 핵심이다.

---

## 1. 개념 모델

한 테이블 `internal_requests` 에 `type` 컬럼(`compra` | `reparacion`)으로 두 업무를 담는다.
공통 필드(요청자·지점·상태·비용·승인)가 90% 겹치므로 테이블을 쪼개면 조회/집계 쿼리가 두 배가 된다.

```
사용자: "컴퓨터가 죽었다"
  → (즉시) 예비 PC로 교체하고 영업 계속       ← 시스템 개입 없음, 현장 조치
  → Nueva solicitud (reparación) 등록          ← 30초
      ├─ Telegram → 관리자
      ├─ internal_requests INSERT
      └─ internal_request_events INSERT (solicitado)
  → 관리자 Aprobar / Rechazar
  → En proceso (taller 지정, 예상 반납일)
  → Finalizado (실제 비용 입력)
```

### 상태 머신

| 상태 | 라벨 | 다음 상태 | 색 |
|---|---|---|---|
| `solicitado` | Solicitado | `aprobado`, `rechazado`, `cancelado` | blue |
| `aprobado` | Aprobado | `en_proceso`, `cancelado` | cyan |
| `rechazado` | Rechazado | (종료) | red |
| `en_proceso` | En proceso | `finalizado`, `cancelado` | gold |
| `finalizado` | Finalizado | (종료) | green |
| `cancelado` | Cancelado | (종료) | gray |

**승인 임계값**: `store_configs.requestApprovalThreshold` (기본 `0` = 항상 승인 필요).
`estimatedCost <= threshold` 이면 생성 즉시 `aprobado` 로 진입 → 소모품 요청이 승인 큐를 막지 않는다.

---

## 2. DB 스키마

`api-ventago/migrations/internal-requests-create.sql`

```sql
-- ─────────────────────────────────────────────────────────────
-- Solicitudes internas (구매요청 + 수리의뢰)
-- Sequelize underscored:true → 모델 camelCase = DB snake_case
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS internal_assets (
  id                SERIAL PRIMARY KEY,
  store_id          INTEGER NOT NULL REFERENCES stores(id),
  branch_id         INTEGER REFERENCES branches(id),
  terminal_id       INTEGER REFERENCES terminals(id),      -- POS 터미널과 연결(선택)
  branch_agent_id   INTEGER REFERENCES branch_agents(id),  -- 프린터 에이전트와 연결(선택)
  assigned_user_id  INTEGER REFERENCES users(id),          -- "Mis equipos" 필터의 기준
  code              VARCHAR(60)  NOT NULL,                 -- PC-CENTRO-02
  name              VARCHAR(160) NOT NULL,
  category          VARCHAR(40)  NOT NULL,                 -- pc | impresora_termica | zebra | scanner | monitor | red | mobiliario | otro
  serial_number     VARCHAR(80),
  status            VARCHAR(16)  NOT NULL DEFAULT 'operativo'
                      CHECK (status IN ('operativo','en_reparacion','de_baja')),
  purchased_at      DATE,
  warranty_until    DATE,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_internal_assets_store_code UNIQUE (store_id, code)
);
CREATE INDEX IF NOT EXISTS ix_internal_assets_store_branch ON internal_assets (store_id, branch_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS ix_internal_assets_assigned     ON internal_assets (assigned_user_id) WHERE is_active;

CREATE TABLE IF NOT EXISTS internal_requests (
  id                  SERIAL PRIMARY KEY,
  store_id            INTEGER NOT NULL REFERENCES stores(id),
  branch_id           INTEGER NOT NULL REFERENCES branches(id),
  code                VARCHAR(20)  NOT NULL,               -- SOL-0241 (store 단위 시퀀스)
  type                VARCHAR(12)  NOT NULL CHECK (type IN ('compra','reparacion')),
  category            VARCHAR(40)  NOT NULL,
  title               VARCHAR(180) NOT NULL,
  description         TEXT,
  priority            VARCHAR(8)   NOT NULL DEFAULT 'media' CHECK (priority IN ('baja','media','alta')),
  status              VARCHAR(12)  NOT NULL DEFAULT 'solicitado'
                        CHECK (status IN ('solicitado','aprobado','rechazado','en_proceso','finalizado','cancelado')),

  -- 수리 전용
  asset_id            INTEGER REFERENCES internal_assets(id),
  asset_label         VARCHAR(160),                        -- 자산 미등록 시 자유 입력 fallback
  serial_number       VARCHAR(80),
  vendor_name         VARCHAR(120),                        -- taller / servicio técnico
  expected_return_at  DATE,
  replaced_in_place   BOOLEAN NOT NULL DEFAULT FALSE,      -- "예비 장비로 교체하고 계속 운영 중"

  -- 구매 전용
  quantity            NUMERIC(12,2),
  unit                VARCHAR(20),

  -- 비용
  estimated_cost      NUMERIC(14,2) NOT NULL DEFAULT 0,
  actual_cost         NUMERIC(14,2),
  currency            VARCHAR(3)   NOT NULL DEFAULT 'ARS',

  -- 관계자
  requester_user_id   INTEGER NOT NULL REFERENCES users(id),
  approver_user_id    INTEGER REFERENCES users(id),
  approved_at         TIMESTAMPTZ,
  rejected_reason     TEXT,
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_internal_requests_store_code UNIQUE (store_id, code)
);

-- 목록 화면 기본 정렬/필터 대응 (store + status + 최신순)
CREATE INDEX IF NOT EXISTS ix_internal_requests_store_status ON internal_requests (store_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_internal_requests_branch      ON internal_requests (branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_internal_requests_requester   ON internal_requests (requester_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_internal_requests_asset       ON internal_requests (asset_id) WHERE asset_id IS NOT NULL;

-- 상태 전이 + 코멘트 통합 로그 (타임라인 = 이 테이블 하나만 읽으면 됨)
CREATE TABLE IF NOT EXISTS internal_request_events (
  id            SERIAL PRIMARY KEY,
  request_id    INTEGER NOT NULL REFERENCES internal_requests(id) ON DELETE CASCADE,
  kind          VARCHAR(12) NOT NULL CHECK (kind IN ('status','comment')),
  from_status   VARCHAR(12),
  to_status     VARCHAR(12),
  note          TEXT,
  user_id       INTEGER NOT NULL REFERENCES users(id),
  telegram_sent BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_internal_request_events_req ON internal_request_events (request_id, created_at);

CREATE TABLE IF NOT EXISTS internal_request_attachments (
  id           SERIAL PRIMARY KEY,
  request_id   INTEGER NOT NULL REFERENCES internal_requests(id) ON DELETE CASCADE,
  file_name    VARCHAR(255) NOT NULL,   -- MinIO 오브젝트명
  original_name VARCHAR(255),
  mime_type    VARCHAR(100),
  size_bytes   INTEGER,
  uploaded_by  INTEGER NOT NULL REFERENCES users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_internal_request_attachments_req ON internal_request_attachments (request_id);

-- ── 소모품 카탈로그 (Insumos) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS internal_supplies (
  id             SERIAL PRIMARY KEY,
  store_id       INTEGER NOT NULL REFERENCES stores(id),
  code           VARCHAR(40)  NOT NULL,
  name           VARCHAR(160) NOT NULL,
  category       VARCHAR(30)  NOT NULL,   -- papel | etiquetas | cables | perifericos | limpieza | otro
  unit           VARCHAR(20)  NOT NULL DEFAULT 'unidad',
  supplier_name  VARCHAR(120),
  last_unit_cost NUMERIC(14,2),
  track_stock    BOOLEAN NOT NULL DEFAULT TRUE,  -- false = 수량관리 안 하고 주문만
  image_file_name VARCHAR(255),                  -- MinIO
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_internal_supplies_store_code UNIQUE (store_id, code)
);
CREATE INDEX IF NOT EXISTS ix_internal_supplies_store ON internal_supplies (store_id, category) WHERE is_active;

-- 지점별 보유 수량 (현재 잔량 캐시)
CREATE TABLE IF NOT EXISTS internal_supply_stocks (
  id           SERIAL PRIMARY KEY,
  supply_id    INTEGER NOT NULL REFERENCES internal_supplies(id) ON DELETE CASCADE,
  branch_id    INTEGER NOT NULL REFERENCES branches(id),
  quantity     NUMERIC(12,2) NOT NULL DEFAULT 0,
  min_quantity NUMERIC(12,2) NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_internal_supply_stocks UNIQUE (supply_id, branch_id)
);
-- "부족 항목" 조회 전용 부분 인덱스 (알림 cron 이 매일 쓴다)
CREATE INDEX IF NOT EXISTS ix_internal_supply_stocks_low
  ON internal_supply_stocks (branch_id) WHERE quantity <= min_quantity;

-- 수량 변동 원장 (append-only — 잔량 분쟁 시 유일한 진실)
CREATE TABLE IF NOT EXISTS internal_supply_movements (
  id          SERIAL PRIMARY KEY,
  supply_id   INTEGER NOT NULL REFERENCES internal_supplies(id) ON DELETE CASCADE,
  branch_id   INTEGER NOT NULL REFERENCES branches(id),
  kind        VARCHAR(10) NOT NULL CHECK (kind IN ('entrada','consumo','ajuste')),
  quantity    NUMERIC(12,2) NOT NULL,           -- 부호 포함 (+입고 / -소비)
  request_id  INTEGER REFERENCES internal_requests(id),  -- 구매 완료로 인한 자동 입고
  note        TEXT,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_internal_supply_movements ON internal_supply_movements (supply_id, branch_id, created_at DESC);

-- 구매 요청의 품목 라인 (장바구니로 여러 개를 한 건에 담기 위함)
CREATE TABLE IF NOT EXISTS internal_request_items (
  id          SERIAL PRIMARY KEY,
  request_id  INTEGER NOT NULL REFERENCES internal_requests(id) ON DELETE CASCADE,
  supply_id   INTEGER REFERENCES internal_supplies(id),  -- NULL = 자유 입력 품목
  description VARCHAR(180) NOT NULL,
  quantity    NUMERIC(12,2) NOT NULL,
  unit        VARCHAR(20)  NOT NULL DEFAULT 'unidad',
  unit_cost   NUMERIC(14,2),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_internal_request_items_req ON internal_request_items (request_id);

-- 운영(5434) 필수: owner + 시퀀스 이전 (누락 시 앱 permission denied 500)
DO $$
DECLARE t TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    FOREACH t IN ARRAY ARRAY[
      'internal_assets','internal_requests','internal_request_events',
      'internal_request_attachments','internal_request_items',
      'internal_supplies','internal_supply_stocks','internal_supply_movements'
    ] LOOP
      EXECUTE format('ALTER TABLE %I OWNER TO coolsistema', t);
      -- ALTER TABLE OWNER 는 시퀀스 owner 를 안 옮기므로 별도 실행 필수
      EXECUTE format('ALTER SEQUENCE %I_id_seq OWNER TO coolsistema', t);
    END LOOP;
  END IF;
END $$;
```

### 잔량 갱신 규칙

`internal_supply_stocks.quantity` 는 캐시이고, `internal_supply_movements` 가 원장이다.
둘은 **같은 트랜잭션**에서 함께 쓴다 — 나눠 쓰면 `products.stock` 이 겪었던 드리프트가 그대로 재현된다.

```sql
-- 대조 불변식 (주기적으로 0행이어야 함)
CREATE OR REPLACE VIEW v_internal_supply_drift AS
SELECT s.supply_id, s.branch_id, s.quantity AS cached,
       COALESCE(SUM(m.quantity), 0) AS ledger
FROM internal_supply_stocks s
LEFT JOIN internal_supply_movements m
       ON m.supply_id = s.supply_id AND m.branch_id = s.branch_id
GROUP BY s.supply_id, s.branch_id, s.quantity
HAVING s.quantity <> COALESCE(SUM(m.quantity), 0);
```

자동 입고: 구매 요청이 `finalizado` 로 전이될 때 `internal_request_items` 각 행에 대해
`kind='entrada'` movement 를 만들고 `quantity` 를 더한다 — **전이 트랜잭션 안에서**.

추가로 `store_configs` 에 2컬럼:

```sql
ALTER TABLE store_configs
  ADD COLUMN IF NOT EXISTS request_approval_threshold NUMERIC(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS telegram_chat_id VARCHAR(40);
```

> `code` 생성은 애플리케이션에서 `SELECT COALESCE(MAX(...),0)+1 FROM internal_requests WHERE store_id=$1 FOR UPDATE` 대신,
> **store 단위 카운터를 `internal_requests` UNIQUE 제약 + 재시도**로 처리하거나 `store_configs.last_request_seq` 를 같은 트랜잭션에서 `UPDATE ... RETURNING` 한다. 후자를 권장 — 락 범위가 1행이다.

---

## 3. 백엔드 (`api-ventago/src/app/internal-requests/`)

```
internal-requests/
├── internal-request.model.ts
├── internal-request-event.model.ts
├── internal-request-attachment.model.ts
├── internal-asset.model.ts
├── dto/
│   ├── create-request.dto.ts
│   ├── update-status.dto.ts
│   └── query-request.dto.ts
├── internal-requests.service.ts
├── internal-requests.controller.ts
├── internal-requests.notifier.ts     # Telegram 메시지 조립
└── internal-requests.module.ts       # imports: [MinioModule]
```

### 엔드포인트

| Method | Path | 설명 |
|---|---|---|
| **`GET`** | **`/internal-requests/page`** | **★ 페이지 부트스트랩 — KPI + 목록(상세 포함) + 레일 데이터를 1회 응답으로** |
| `GET` | `/internal-requests` | 목록만. query: `type,status,branchId,storeId,priority,q,from,to,page,pageSize(≤50)` |
| `GET` | `/internal-requests/:id` | 상세 + events + attachments (딥링크·새로고침용) |
| `POST` | `/internal-requests` | 생성 |
| `PATCH` | `/internal-requests/:id` | 본문 수정 (solicitado 상태에서 요청자 본인만) |
| `PATCH` | `/internal-requests/:id/status` | 상태 전이 (`{ status, note?, actualCost?, vendorName?, expectedReturnAt? }`) |
| `POST` | `/internal-requests/:id/comments` | 코멘트 |
| `POST` | `/internal-requests/:id/attachments` | MinIO 업로드 (multipart) |
| `GET` | `/internal-assets` | 자산 목록. query: `scope=mine\|branch\|store`, `status`, `q` |
| `POST` | `/internal-assets` | 장비 등록 |
| `GET` | `/internal-assets/:id/history` | 해당 장비의 과거 의뢰 + 누적 비용 |
| `GET` | `/internal-supplies` | 소모품 카탈로그 + 해당 지점 잔량 (1회 join) |
| `GET` | `/internal-supplies/low-stock` | 최소재고 미만 목록 |
| `POST` | `/internal-supplies` | 소모품 등록 |
| `POST` | `/internal-supplies/movements` | 수량 조정 (`entrada` / `consumo` / `ajuste`) |

### `/internal-requests/page` — 단일 페이지 부트스트랩 ★

단일 페이지가 필요한 데이터는 4덩어리(KPI·목록·장비·소모품)다.
**이걸 4번의 HTTP 호출로 만들면 워커당 max=20 pool 을 페이지 로드 1회에 4개씩 소모한다.**
엔드포인트 하나로 묶고, 서버 내부에서도 쿼리 수를 최소화한다.

```ts
// 역할에 따라 payload 가 달라진다 — 프론트가 분기하지 않도록 서버가 결정한다
async getPage(user: AuthUser, q: PageQueryDto): Promise<PagePayload> {
  const isSuper = user.roles.includes('superadmin');

  // 서로 독립적인 쿼리만 병렬 — 3개 이하로 유지한다 (pool 보호)
  const [summary, requests, rail] = await Promise.all([
    this.getSummary(user, isSuper),          // 단일 SQL (FILTER 집계)
    this.getRequests(user, q, isSuper),      // 목록 + events 를 1회 join 으로
    isSuper ? this.getConsumptionRanking(user) : this.getRail(user),
  ]);

  return { role: isSuper ? 'super' : 'store', summary, requests, rail };
}
```

목록 응답에는 **각 행의 상세(타임라인·품목·장비이력 요약)를 함께 담는다.**
아코디언을 펼칠 때 추가 호출이 없어야 클릭이 즉시 반응하고, 행마다 API 를 때리는 N+1 도 막힌다.
페이지 크기가 25 이므로 events 를 함께 실어도 응답은 수십 KB 수준이다.

```jsonc
{
  "role": "store",
  "summary": { "pendientes": 2, "enProceso": 3, "gastoMes": 261300, "insumosBajos": 2 },
  "requests": [{
    "id": 241, "code": "SOL-0241", "type": "reparacion", "status": "solicitado",
    "title": "PC de caja 2 no enciende", "estimatedCost": 85000,
    "asset": { "code": "PC-CENTRO-02", "serialNumber": "4KJ98X",
               "repairCount": 2, "repairTotal": 57000 },   // 반복수리 판단용
    "events": [ /* 타임라인 */ ],
    "items":  [ /* compra 인 경우 품목 라인 */ ]
  }],
  "rail": { "assets": [ /* 최대 20 */ ], "supplies": [ /* 최대 20 */ ] }
}
```

### superadmin — 소진 빠른 부품 랭킹

"어떤 부품이 빨리 닳는가"는 두 곳에서 나온다: **소모품 출고량**(`internal_supply_movements`)과
**수리 요청에 반복 등장하는 부품**(`internal_requests.category`). 둘을 UNION 하지 말고 소모품 기준으로 집계하되,
반복 수리는 별도 지표로 보여준다.

```sql
-- 최근 90일 소진 속도 + 직전 90일 대비 증감 + 부족 매장 수 (단일 쿼리)
WITH mov AS (
  SELECT m.supply_id,
         SUM(-m.quantity) FILTER (WHERE m.kind = 'consumo' AND m.created_at >= NOW() - INTERVAL '90 days')  AS qty_now,
         SUM(-m.quantity) FILTER (WHERE m.kind = 'consumo' AND m.created_at >= NOW() - INTERVAL '180 days'
                                                          AND m.created_at <  NOW() - INTERVAL '90 days')   AS qty_prev
  FROM internal_supply_movements m
  GROUP BY m.supply_id
),
low AS (
  SELECT supply_id, COUNT(*) AS branches_low
  FROM internal_supply_stocks
  WHERE quantity <= min_quantity
  GROUP BY supply_id
)
SELECT s.id, s.name, s.category,
       COALESCE(mov.qty_now, 0)                       AS consumo_90d,
       ROUND(COALESCE(mov.qty_now, 0) / 3.0, 1)       AS por_mes,
       CASE WHEN COALESCE(mov.qty_prev, 0) = 0 THEN NULL
            ELSE ROUND((mov.qty_now - mov.qty_prev) * 100.0 / mov.qty_prev, 0) END AS delta_pct,
       COALESCE(low.branches_low, 0)                  AS tiendas_bajo_minimo,
       s.last_unit_cost
FROM internal_supplies s
LEFT JOIN mov ON mov.supply_id = s.id
LEFT JOIN low ON low.supply_id = s.id
WHERE s.is_active
ORDER BY consumo_90d DESC NULLS LAST
LIMIT 8;
```

> `internal_supply_movements` 는 계속 쌓이는 테이블이다. 위 쿼리가 100ms 를 넘기 시작하면
> `(supply_id, created_at DESC)` 인덱스만으로는 부족해진다 — 그때 월별 집계 테이블을 만든다.
> **지금 만들지는 않는다.** 매장 4개 규모에서 조기 최적화다.

반복 수리 경고(목업의 "3.ª reparación del mismo equipo")는 목록 응답의
`asset.repairCount` / `asset.repairTotal` 로 프론트가 판정한다 — 별도 API 없음.

### 카탈로그 → 요청 (장바구니)

`POST /internal-requests` 가 `items[]` 를 받으면 `type='compra'` 의 다품목 요청이 된다.
장바구니는 **프론트 상태(useState)** 로만 들고 있다가 전송 시 1회 POST — 서버에 장바구니 테이블을 두지 않는다.

```jsonc
POST /internal-requests
{
  "type": "compra",
  "category": "insumo",
  "title": "Reposición de insumos — Centro",
  "branchId": 3,
  "items": [
    { "supplyId": 11, "description": "Papel térmico 80mm",   "quantity": 6, "unit": "rollo", "unitCost": 6200 },
    { "supplyId": 14, "description": "Etiquetas 50×25 doble", "quantity": 4, "unit": "rollo", "unitCost": 9800 }
  ]
}
// estimatedCost 는 서버가 items 합계로 계산한다 — 클라이언트 값을 신뢰하지 않는다.
```

### 자산 카드 → 수리 의뢰

`Mis equipos` 의 `Solicitar reparación` 은 `assetId` 를 들고 화면 2 모달을 연다.
`code` · `serialNumber` · `branchId` · `category` 는 자산에서 자동 채워지고, 사용자는 제목·설명만 쓴다.
저장 시 자산 `status` 를 `en_reparacion` 으로 바꾸고, `finalizado`/`rechazado` 전이에서 되돌린다 — **같은 트랜잭션**.

### 트랜잭션 규칙 (CLAUDE.md 「쓰기 경로 규약」 준수)

```ts
// 생성: 요청 + 최초 이벤트 + 코드 시퀀스를 하나의 트랜잭션에서 커밋
async create(dto: CreateRequestDto, user: AuthUser): Promise<InternalRequest> {
  const created = await this.sequelize.transaction(async (transaction) => {
    // 코드 시퀀스는 store_configs 1행만 잠근다 (락 범위 최소화)
    const code = await this.nextCode(user.storeId, transaction);

    const threshold = await this.getApprovalThreshold(user.storeId, transaction);
    const autoApproved = Number(dto.estimatedCost ?? 0) <= Number(threshold);

    const request = await this.requestModel.create(
      { ...dto, code, storeId: user.storeId, requesterUserId: user.id,
        status: autoApproved ? 'aprobado' : 'solicitado' },
      { transaction },
    );

    // transaction 은 선택이 아닌 필수 인자 — 누락 시 부분 저장 사고
    await this.eventModel.create(
      { requestId: request.id, kind: 'status', toStatus: request.status, userId: user.id },
      { transaction },
    );

    return request;
  });

  // ★ 외부 I/O 는 커밋 후에만. 실패해도 응답 코드는 바꾸지 않는다.
  this.notifier.notifyCreated(created);

  return created;
}
```

**pool 주의**: 목록/요약 쿼리는 반드시 `Promise.all` 없이 **단일 SQL 1회**로 끝낸다.
KPI 4종은 `FILTER (WHERE ...)` 집계 하나로 뽑는다 — 4번 왕복하면 워커당 max=20 pool 을 4배로 소모한다.

```sql
SELECT
  COUNT(*) FILTER (WHERE status = 'solicitado')                                AS pendientes,
  COUNT(*) FILTER (WHERE status IN ('aprobado','en_proceso'))                  AS en_proceso,
  COALESCE(SUM(COALESCE(actual_cost, estimated_cost))
           FILTER (WHERE date_trunc('month', created_at) = date_trunc('month', NOW())), 0) AS gasto_mes,
  AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)
      FILTER (WHERE status = 'finalizado')                                     AS dias_promedio
FROM internal_requests
WHERE store_id = $1 AND ($2::int IS NULL OR branch_id = $2);
```

### Telegram (단방향)

기존 헬퍼 재사용 — 새로 만들지 않는다.

```ts
import { notifyTelegram } from 'src/common/telegram/telegram';

notifyTelegram(msg, {
  dedupKey: `solicitud:${req.id}:${req.status}`,   // 60초 중복 방지
  chatId: storeConfig.telegramChatId || undefined, // 없으면 전역 채널
});
```

메시지 3종(생성 / 상태변경 / 완료)은 목업 4번 탭 참고. 전송 성공 시 `internal_request_events.telegram_sent = true` 로 기록 —
`sendTelegramMessage()` 가 `boolean` 을 반환하므로 "보낸 척" 기록을 피할 수 있다.

---

## 4. 프론트엔드

```
ventago-app/src/
├── pages/solicitudes/index.tsx              # 페이지는 이것 하나뿐. dynamic import, ssr:false
├── views/solicitudes/
│   ├── SolicitudesPage.tsx                  # 역할 분기 + 레이아웃 (부트스트랩 1회 호출)
│   ├── SolicitudesTable.tsx                 # React.memo — 행 + 인라인 상세 아코디언
│   ├── SolicitudDetailRow.tsx               # 펼침 내용 (타임라인·품목·승인바·장비이력)
│   ├── SolicitudFormDialog.tsx              # 생성 모달 (assetId / items 프리필 지원)
│   ├── rail/EquiposRail.tsx                 # 내 장비 목록 + Reparar
│   ├── rail/InsumosRail.tsx                 # 잔량 + 스테퍼 + 장바구니
│   ├── rail/ConsumoRail.tsx                 # superadmin 소진 랭킹
│   ├── rail/TiendasRail.tsx                 # superadmin 매장 현황
│   └── components/{StatusChip,PriorityChip,TypeChip,KpiStrip,Timeline,StockBar,Stepper}.tsx
└── hooks/api/
    └── useSolicitudesPage.ts                # SWR 1개 — /internal-requests/page (필터를 key 에 포함)
```

### 상태 관리 원칙

- **SWR 훅은 1개**(`useSolicitudesPage`). 화면이 하나이므로 캐시 키도 하나다.
  필터 변경은 key 를 바꿔 재검증하고, 나머지는 `keepPreviousData` 로 깜빡임을 막는다.
- **아코디언 펼침 상태는 `useState`** — 서버 왕복 없음. 한 번에 하나만 펼친다.
- **장바구니는 `useState`** — 서버에 장바구니 테이블을 두지 않는다. 전송 시 1회 POST.
- 상태 변경(승인/거절/코멘트) 후에는 전체 재검증 대신 **`mutate` 로 해당 행만 낙관적 갱신**.
  페이지 전체를 다시 받으면 아코디언이 닫히고 사용자가 위치를 잃는다.
- 우측 레일 탭 전환은 **렌더 토글일 뿐 API 호출이 아니다** — 두 탭 데이터 모두 부트스트랩에 들어 있다.

규약 준수 체크:

- `next/dynamic(() => import('src/views/solicitudes/SolicitudesListView'), { ssr: false })`
- 참조 데이터(자산 목록, 카테고리)는 `useEffect + apiConnector.get` 금지 → SWR 훅
- `pageSize` 기본 25, 최대 50
- `apiConnector.remove()` (`.delete()` 아님)
- ESLint: `return` 위 빈 줄, `//` 주석 위 빈 줄, 미사용 import 금지

### 영역별 구성

**KPI 스트립** — 역할별 4개. 매장은 "내가 지금 해야 할 일", superadmin 은 "방치된 것"이 보이게 한다.
superadmin 의 **지연 7일+** 카드가 이 화면의 핵심 지표다 — 승인 안 하고 놔둔 건이 여기 잡힌다.

**저재고 경고 바** (매장 admin 전용) — 부족 품목이 있을 때만 표시.
`Reponer todo` 는 부족분 전부를 장바구니에 담고 Insumos 탭으로 전환한다.

**요청 목록 + 인라인 상세** — 행 클릭으로 아코디언이 펼쳐진다. 펼침 내용:
- 좌: 요약 카드 4(장비·비용·타워·반납일) + 설명·첨부 + 코멘트 + **승인 액션 바**
- 우: 상태 타임라인 + **해당 장비의 과거 수리 이력 + 누적 비용**
- `compra` 타입이면 요약 카드 대신 **품목 라인 + 합계**를 보여준다
- 한 번에 하나만 펼친다. 다른 행을 열면 이전 행은 닫힌다.

**우측 레일 — 탭 ① Mis equipos** (매장 admin)
장비 1행 = 아이콘 + 코드 + 한 줄 요약 + 액션. 상태별로 액션이 달라진다.
- `operativo` → `Reparar` (골드 버튼 → 모달을 `assetId` 프리필로 연다)
- `en_reparacion` → 버튼 대신 진행 중 의뢰 코드 칩 (클릭 시 목록에서 해당 행 펼침)
- `de_baja` → `Pedir` (구매 요청으로 연결)
카드 그리드가 아니라 **행 리스트**다 — 레일 폭(396px)에서 카드는 정보 밀도가 너무 낮다.

**우측 레일 — 탭 ② Insumos** (매장 admin)
행마다 잔량/최소재고 · 잔량 바 · 최근 단가 · 수량 스테퍼.
수량이 1 이상인 품목이 생기면 하단 장바구니 바가 나타나고, `Pedir` 한 번으로 다품목 요청 1건이 만들어진다.
`track_stock = false` 인 품목은 잔량 바 대신 "sin control" 로 표시 — 수량 입력을 강제하지 않는다.

> 운영 부담 완화: 잔량 입력은 **의무가 아니다**. `track_stock` 을 끄면 주문 기능만 쓰고,
> 켜면 부족 알림까지 받는다. 품목 단위 선택이라 "전부 세야 한다"는 부담이 없다.

**우측 레일 — superadmin**
- `소진 빠른 부품 랭킹`: 순위 + 월평균 소비량 + 6구간 스파크라인 + 전월 대비 증감 + 부족 매장 수
- `매장 현황`: 매장별 대기/진행/지연 요약과 심각도 칩

**Nueva solicitud 모달** — 타입 카드 2개(Reparación / Compra)로 필드 블록이 바뀐다.
장비 선택 시 S/N·지점·카테고리는 자동 채워지고, 사용자는 제목과 증상만 쓴다.
**"이미 다른 장비로 교체했고 영업은 계속 중"** 체크가 기본 위치에 있다 — 실제 현장 순서가 그렇기 때문이다.

---

## 5. 사이드바 등록

**메뉴는 최상위 1개, 서브메뉴 없음.** `directPath` 로 그룹 이름 클릭 = 바로 페이지 이동.

```sql
-- app + module 각 1개만 시드
INSERT INTO apps (slug, name, icon) VALUES ('solicitudes', 'Solicitudes', 'tabler:clipboard-list');
INSERT INTO modules (app_id, slug, name, url, icon, is_auxiliary) VALUES
  (<app_id>, 'solicitudes', 'Solicitudes', '/solicitudes', 'tabler:clipboard-list', false);
```

```ts
// menuRegistry.ts — 이 파일만 수정. vertical/index.ts 는 건드리지 않는다.
export const appOrder = ['admin', 'venta', 'producto', 'reportes', 'talleres', 'materia-prima', 'solicitudes']

export const defaultIcons: Record<string, string> = {
  // ...
  solicitudes: 'tabler:clipboard-list',
}

export const forceDefaultIconApps = new Set([/* ... */, 'solicitudes'])

// appMenuConfigs 에 추가 — directPath 는 부메뉴를 없애고 그룹 클릭으로 바로 이동시킨다
{
  slug: 'solicitudes',
  directPath: '/solicitudes',
}
```

`directPath` 와 `defaultPath` 를 헷갈리지 말 것 — `defaultPath` 는 부메뉴를 남기고, `directPath` 가 없앤다.
여기서 필요한 건 `directPath` 다.

권한은 서버가 강제한다. 매장 admin 이 다른 매장 데이터를 못 보는 건 `storeId` 스코프이지 메뉴 가시성이 아니다.
superadmin 여부 판정도 서버가 payload 로 내려주고(`role` 필드), 프론트는 그걸 따를 뿐 자체 판단하지 않는다.

---

## 6. 마이그레이션 적용 (로컬 + 운영 동시)

```bash
# 운영 (srv803182, PG18 클러스터 ventago18, 포트 5434)
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction" \
  < api-ventago/migrations/internal-requests-create.sql

# 로컬 (Mac Homebrew PG18, 포트 5432)
psql -p 5432 -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/internal-requests-create.sql

# 스키마 reference 재생성
./.planning/intel/db-schema.regen.sh
```

한쪽만 적용 금지. 적용 후 양쪽 `\d internal_requests` 대조.

---

## 7. 단계별 구현 순서

| 단계 | 범위 | 산출물 |
|---|---|---|
| 1 | DB | 마이그레이션 SQL(8테이블) + 로컬/운영 동시 적용 + 스키마 reference 재생성 |
| 2 | 백엔드 | 모델 8 + 서비스 + 컨트롤러 + notifier. 단일 트랜잭션 + 커밋 후 Telegram |
| 3 | 백엔드 | `GET /internal-requests/page` 부트스트랩 (역할 분기 + 3쿼리 이하) |
| 4 | 프론트 | 페이지 셸: KPI + 목록 + 인라인 상세 아코디언 |
| 5 | 프론트 | Nueva solicitud 모달 (`assetId` / `items` 프리필) |
| 6 | 프론트 | 우측 레일 — Mis equipos / Insumos 탭 + 장바구니 |
| 7 | 프론트 | superadmin 뷰 — 매장 컬럼·지연 지표·소진 랭킹·매장 현황 |
| 8 | 배치 | 저재고 일일 알림 cron (`@nestjs/schedule`, 지점별 1메시지 그룹) |
| 9 | 메뉴 | apps/modules 시드 1개 + menuRegistry `directPath` (로컬·운영 동시 시드) |
| 10 | 검증 | 상태 전이 전 경로 수동 테스트 · Telegram 실제 수신 · `v_internal_supply_drift` 0행 · ESLint 통과 · `pg_stat_activity` pool 점유 확인 |

**1~5 가 최소 동작 단위(MVP)** — 여기까지면 의뢰하고 상태를 보는 루프가 성립한다.
6~7 은 진입점·감시 도구 개선이라 뒤로 미뤄도 기능은 깨지지 않는다.

### 저재고 알림 cron 주의

```ts
// 지점별로 1건씩 그룹 발송 — 품목당 1건이면 텔레그램이 스팸이 되고 rate limit 에 걸린다
@Cron('0 9 * * *')  // 매일 09:00
async notifyLowStock(): Promise<void> {
  // 단일 쿼리로 전 지점 부족분을 한 번에 읽는다 (지점 수만큼 왕복 금지 = pool 보호)
  const rows = await this.supplyStockModel.sequelize.query(LOW_STOCK_SQL, { type: QueryTypes.SELECT });
  // ... 지점 단위로 groupBy 후 지점당 1회 notifyTelegram
}
```

---

## 8. 결정이 필요한 잔여 항목

1. **자산 대장 초기 데이터** — 기존 `terminals` / `branch_agents` 에서 자동 생성할지, 수동 등록만 할지.
   자동 생성 시 `code` 는 `PC-{BRANCH}-{NN}` / `{AGENT_TYPE}-{LABEL}` 규칙으로 만들면 된다.
2. **승인 임계값 기본값** — `0`(항상 승인)으로 시작할지, 예: `50.000` 으로 시작할지.
3. **소모품 초기 카탈로그** — 열감지 용지·Zebra 라벨 3종은 이미 시스템이 아는 규격이므로 시드 가능.
4. **비용의 회계 연동** — `Finalizado` 시 `expenses` 테이블에 자동으로 지출 1건 생성할지 (별도 Phase 권장).
5. **Telegram chat 분리** — 매장별 chat 을 쓸지, 운영자 단일 채널로 통합할지.
6. **저재고 알림 시각** — 09:00 기준으로 할지, 지점 영업 시작 시각에 맞출지.
