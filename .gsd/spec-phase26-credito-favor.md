# SPEC: Phase 26 — Crédito · Seña · Favor (cuenta corriente)

생성일: 2026-04-29
최종 수정: 2026-04-30 (Seña 개념 정식 반영)
작성자: GSD / Plan
선행 단계: Phase 25 (global_clients / store_clients 분리 완료)

---

## 목표

매장이 손님에게 외상(crédito) 으로 판매하고, 손님은 부분 입금하거나 선납으로 미리 입금할 수 있는 cuenta corriente 시스템을 안전하게 도입한다. 선납 자금은 두 가지 의미로 분리해 관리한다:

- **Seña** — 특정 매출(venta)에 귀속된 예약금/계약금. sale_id 가 반드시 존재.
- **Favor** — 어떤 매출에도 묶이지 않은 자유 잔액. Seña 의 거스름, 환불, 외상 초과 입금 등이 흘러들어옴.

DNI/CUIT 가 검증된 고객만 crédito/seña 사용이 가능하며, 모든 잔액 변동은 immutable 거래 원장(`credit_ledger`) 에 기록한다.

---

## 배경 및 컨텍스트

### 현재 (Phase 25 완료 후) 상태

- `global_clients.document` UNIQUE — DNI/CUIT 형식 검증은 부분적으로 존재 (memory rule: document 없으면 global 등록 금지)
- `store_clients.balance DECIMAL(12,2)` — 이미 존재하지만 **현재 어디서도 자동 갱신되지 않음**
- `store_clients.credit_limit DECIMAL(12,2)` — 컬럼은 있지만 화면에서 노출/검증 안 됨
- `payment_methods` 시드에 `slug='credito'`, `slug='favor'` 이미 존재 (slug='senia' 신규 추가 필요)
- `sales-create.service.ts create()` (L54-255) 는 sale + sale_payment_methods 만 저장하고 **balance 갱신 / 원장 기록 없음**
- `processPaymentMethods()` 는 `slug==='efectivo'` 만 분기 처리 (cash op 등록), 나머지는 단순 INSERT
- 명시적 transaction 미사용 — 순차 await 만

### 문제

1. crédito 결제수단을 선택해도 잔액이 늘어나지 않아 외상 추적 불가
2. favor(선납) 라는 자금 출처가 정의되어 있지 않아 차감 흐름 불가
3. 한도/만기 정책 부재 → 점장이 임의로 운용
4. 누가 언제 얼마 외상을 가져갔는지 원장이 없어 분쟁 시 복구 어려움
5. nueva-venta 결제 모달에 외상 전용 UX 없음

### 운영 환경 제약

- 운영 PostgreSQL 10 (호스트 OS, pgbouncer 5432 프록시) — `GENERATED AS IDENTITY` 사용 금지
- Pool: max=50 고정 — 트랜잭션 내 idle 시간 최소화 필수
- 다점포 멀티테넌트 — `store_id` 격리 절대 위반 금지
- 운영 매장: CART(3), coolsistema(6), genius(8), ACE(9)

---

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (`underscored: true`) → DB 컬럼 snake_case
- DB: PostgreSQL 10 (운영) / 15 (로컬 docker)
- 프론트: Next.js 13 + MUI 5 + Redux Toolkit + SWR
- ESLint: 프로젝트 기본 규칙 (newline-before-return, lines-around-comment, no-unused-vars)
- 트랜잭션: `sequelize.transaction({ isolationLevel: SERIALIZABLE })`
- Pool 안전: 모든 DB 접근은 service 메서드 단일 트랜잭션 내 처리, 끝나면 즉시 release

---

## 데이터 모델 변경

### 3-Bucket 잔액 모델

`store_clients` 는 매출 관점에서 세 개의 독립 버킷을 가진다:

| 버킷 | 컬럼 | 부호 의미 |
|------|------|----------|
| **Crédito (외상)** | `balance` | > 0 = 손님이 갚을 돈 |
| **Seña (예약금)**  | `senia_balance` | ≥ 0, 항상 음수 아님. 특정 sale_id 들에 묶인 합계 |
| **Favor (자유 선수금)** | `favor_balance` | ≥ 0, 자유롭게 다음 매출에 사용 가능 |

> **왜 분리?** Seña 는 회계상 "특정 매출용 선수금" 으로 취급되어 그 venta 가 취소되면 환불 의무가 명확하다. Favor 는 그런 귀속이 없어 다음 매출 어디에든 적용 가능. 합치면 분쟁/세무에서 구분이 어려워진다.
>
> `balance`(crédito) 와 `senia_balance + favor_balance` 는 **항상 양수**. 음수 잔액 표현 금지 (Phase 25 이전의 음수 balance 는 favor_balance 로 마이그레이션).

### 신규 테이블: `credit_ledger`

```sql
CREATE TABLE credit_ledger (
  id              BIGSERIAL PRIMARY KEY,
  store_id        INTEGER  NOT NULL REFERENCES stores(id),
  store_client_id INTEGER  NOT NULL REFERENCES store_clients(id),
  movement_type   VARCHAR(20) NOT NULL
                  CHECK (movement_type IN
                    ('sale_credit','payment_in',
                     'senia_in','senia_apply','senia_refund','senia_to_favor',
                     'favor_in','favor_apply','favor_refund',
                     'adjustment','writeoff')),
  amount          NUMERIC(12,2) NOT NULL CHECK (amount > 0), -- 항상 양수
  bucket          VARCHAR(10) NOT NULL
                  CHECK (bucket IN ('credito','senia','favor')), -- 어느 버킷에 영향?
  bucket_after    NUMERIC(12,2) NOT NULL,    -- 이 movement 적용 후 해당 버킷 값
  sale_id         INTEGER REFERENCES sales(id),
  payment_id      INTEGER REFERENCES credit_payments(id),
  parent_ledger_id BIGINT REFERENCES credit_ledger(id), -- payment_in → sale_credit, senia_apply → senia_in
  due_date        DATE,                          -- sale_credit 시 만기일
  branch_id       INTEGER REFERENCES branches(id),
  terminal_id     INTEGER REFERENCES terminals(id),
  user_id         INTEGER REFERENCES users(id),
  note            TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- senia_in 은 반드시 sale_id 보유, sale_credit 도 동일
  CONSTRAINT credit_ledger_sale_required CHECK (
    (movement_type IN ('sale_credit','senia_in','senia_apply','favor_apply')
     AND sale_id IS NOT NULL)
    OR movement_type NOT IN ('sale_credit','senia_in','senia_apply','favor_apply')
  )
);
CREATE INDEX idx_credit_ledger_client_created
  ON credit_ledger (store_client_id, created_at DESC);
CREATE INDEX idx_credit_ledger_due_open
  ON credit_ledger (store_client_id, due_date)
  WHERE movement_type = 'sale_credit';
CREATE INDEX idx_credit_ledger_store_type
  ON credit_ledger (store_id, movement_type, created_at DESC);
CREATE INDEX idx_credit_ledger_senia_open
  ON credit_ledger (store_client_id, sale_id)
  WHERE movement_type = 'senia_in';  -- 활성 Seña 빠른 조회
```

**movement_type × bucket 매트릭스:**

| type | bucket | 효과 | 발생 시점 |
|------|--------|------|-----------|
| `sale_credit`     | credito | + | nueva-venta 에서 crédito 결제수단 사용 |
| `payment_in`      | credito | − | 손님이 외상 입금 (parent_ledger_id 로 sale_credit 매칭) |
| `senia_in`        | senia   | + | 손님이 특정 venta(예약/계약) 에 선수금 입금. sale_id 필수 |
| `senia_apply`     | senia   | − | venta 확정 시 Seña 가 결제수단으로 흡수. sale_id 동일 |
| `senia_refund`    | senia   | − | venta 취소 + 손님에게 현금 환불 (외부 자금 유출) |
| `senia_to_favor`  | senia   | − | venta 취소 시 Seña 를 favor 로 전환 (단순 이동) — favor_in 과 짝으로 발생 |
| `favor_in`        | favor   | + | 자유 선수금 적립 (입금 시 외상 초과분, Seña 잔여 거스름 등) |
| `favor_apply`     | favor   | − | favor 잔액을 매출에 차감 |
| `favor_refund`    | favor   | − | favor 를 손님에게 현금 환불 |
| `adjustment`      | (any)   | ± | 점장 수동 조정 (note 필수, audit 추적) |
| `writeoff`        | credito | − | 대손 처리 (외상 0 으로 만들고 손실 인식) |

> **불변(append-only)**: ledger 행은 절대 UPDATE/DELETE 하지 않는다. 정정은 반대 방향 movement 로만.
>
> **연쇄 발생**: 일부 movement 는 짝으로 발생한다. 같은 트랜잭션에서 보장:
> - `senia_to_favor` ↔ `favor_in` (Seña → Favor 이동)
> - `senia_apply` ↔ (sale_credit 또는 cash 결제수단) — 매출 확정 시
> - `payment_in` 후 잔여 → `favor_in`

### 신규 테이블: `credit_payments`

```sql
CREATE TABLE credit_payments (
  id                BIGSERIAL PRIMARY KEY,
  store_id          INTEGER NOT NULL REFERENCES stores(id),
  store_client_id   INTEGER NOT NULL REFERENCES store_clients(id),
  total_amount      NUMERIC(12,2) NOT NULL,
  payment_method_id INTEGER NOT NULL REFERENCES payment_methods(id), -- efectivo/banco/...
  option_id         INTEGER REFERENCES payment_methods_options(id),
  receipt_no        VARCHAR(40) NOT NULL,
  branch_id         INTEGER REFERENCES branches(id),
  user_id           INTEGER REFERENCES users(id),
  note              TEXT,
  paid_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (store_id, receipt_no)
);
```

### `store_clients` ALTER

```sql
ALTER TABLE store_clients
  ADD COLUMN senia_balance    NUMERIC(12,2) NOT NULL DEFAULT 0
                              CHECK (senia_balance >= 0),
  ADD COLUMN favor_balance    NUMERIC(12,2) NOT NULL DEFAULT 0
                              CHECK (favor_balance >= 0),
  ADD COLUMN credit_term_days INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN credit_status    VARCHAR(20) NOT NULL DEFAULT 'active'
                              CHECK (credit_status IN ('active','hold','blocked')),
  ADD COLUMN last_payment_at  TIMESTAMPTZ;

ALTER TABLE store_clients
  ADD CONSTRAINT chk_balance_nonneg CHECK (balance >= 0);
```

> `balance`(crédito), `credit_limit` 은 이미 존재. 세 버킷 모두 ledger SUM 과 항상 일치해야 한다 (정합성 점검 쿼리 별도).

### 신규 테이블: `sale_senias` (선택적, sale ↔ senia 빠른 조회용)

```sql
-- senia_in / senia_apply ledger 의 집계를 매번 SUM 하지 않도록 캐시 테이블
CREATE TABLE sale_senias (
  id              BIGSERIAL PRIMARY KEY,
  sale_id         INTEGER NOT NULL UNIQUE REFERENCES sales(id),
  store_client_id INTEGER NOT NULL REFERENCES store_clients(id),
  store_id        INTEGER NOT NULL REFERENCES stores(id),
  amount_received NUMERIC(12,2) NOT NULL DEFAULT 0,  -- senia_in 합계
  amount_applied  NUMERIC(12,2) NOT NULL DEFAULT 0,  -- senia_apply 합계
  status          VARCHAR(20) NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','applied','refunded','converted')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_sale_senias_client_status
  ON sale_senias (store_client_id, status);
```

> 이 테이블은 ledger 의 **derived view** 와 동일한 정보를 갖지만 빠른 조회를 위함. update 는 ledger 쓰기와 같은 트랜잭션 내에서만.
> 정합성 검증: `sale_senias.amount_received - amount_applied == open_senia_amount(sale_id)`

### `payment_methods` 시드 추가

```sql
INSERT INTO payment_methods (title, slug, is_active, type)
VALUES ('Seña', 'senia', true, 'mayorista')
ON CONFLICT (slug) DO NOTHING;
```

### 매장별 UI 모드 — `stores` ALTER

DB · 백엔드 · 회계는 항상 Seña/Favor 를 분리해 운용한다 (법적 추적성 유지). 그러나 즉석 거래 위주 매장에서는 점원이 두 버킷을 구분하는 것이 오버스펙이므로, **UI 만 합쳐서 보여주는 모드**를 매장 단위 설정으로 제공한다.

```sql
ALTER TABLE stores
  ADD COLUMN senia_ui_mode VARCHAR(20) NOT NULL DEFAULT 'separated'
             CHECK (senia_ui_mode IN ('separated','unified'));

COMMENT ON COLUMN stores.senia_ui_mode IS
  'separated: muestra Crédito/Seña/Favor por separado (default, recomendado para muebles, electro, mayoristas).
   unified: muestra "Saldo a favor" combinando Seña+Favor en UI; backend mantiene separación.';
```

| 모드 | 권장 매장 유형 | KPI 표시 | 결제 모달 표시 |
|------|----------------|----------|----------------|
| `separated` (기본) | 가구·전자제품·도매·맞춤 제작 | 3카드: Crédito / Seña / Favor | "Usar favor" + "+ Seña existente" 분리 |
| `unified` | 의류·식료품·키오스코·즉석 거래 | 2카드: Deuda(crédito) / Saldo a favor (Seña+Favor 합산) | "Aplicar saldo $XX" 단일 버튼 |

**중요한 불변식 (mode 와 무관)**:

- ledger 의 movement_type 과 bucket 컬럼은 항상 정확히 기록 (separated 모드 때와 동일)
- `sale_senias` 테이블도 모드와 무관하게 항상 갱신
- unified 모드 UI 에서 손님이 "Aplicar saldo $80.000" 클릭 시, 백엔드는 다음 우선순위로 차감:
  1. **활성 sale_senias 가 있고 그 sale_id 가 현재 venta 와 일치** → senia_apply 우선
  2. 그 외 → favor_apply
  3. 위 둘로 부족하면 손님에게 "saldo insuficiente" 반환
- 모드 변경 (separated ↔ unified) 은 점장 권한, audit 로그 기록

**API 응답 확장** — `GET /api/credit/clients/:id/summary`:

```json
{
  "creditBalance": 86500,
  "seniaBalance": 280000,
  "favorBalance": 18000,
  "creditLimit": 200000,
  "creditStatus": "active",
  "seniaUiMode": "separated",      // ← 매장 설정 미러링
  "combinedSaldoAFavor": 298000,   // ← unified UI 가 그대로 사용
  "activeSenias": [
    { "saleId": 1500, "amountReceived": 80000, "status": "active" },
    { "saleId": 1487, "amountReceived": 200000, "status": "active" }
  ]
}
```

> 백엔드는 항상 4개 필드(`creditBalance`, `seniaBalance`, `favorBalance`, `combinedSaldoAFavor`)를 모두 반환. 프론트가 `seniaUiMode` 에 따라 골라서 표시.

### 기존 데이터 마이그레이션

- 기존 `store_clients.balance > 0` → 그대로 유지 (외상)
- 기존 `store_clients.balance < 0` → `favor_balance = ABS(balance)` 로 이동, `balance = 0`
  - 동시에 ledger 에 `favor_in` adjustment 1건 + `adjustment` 1건 (note='Phase 26 migration: legacy negative balance → favor')
- 모든 store_clients 에 대해 `senia_balance = 0`, `favor_balance` 는 위 규칙대로 초기화
- migrations 파일: `api-ventago/migrations/phase26-credito-favor.sql`
- 운영 적용: 점검 시간(영업 종료 후) `sudo -u postgres psql -d ventago < ...`

---

## DNI/CUIT 검증 정책

### 형식 검증 (백엔드 서비스 + 프론트 폼 둘 다)

- DNI: `/^\d{7,8}$/`
- CUIT/CUIL: 11 자리 + mod-11 checksum (factor `[5,4,3,2,7,6,5,4,3,2]`)
- Pasaporte: 영숫자, 외상은 점장 승인 필요 (`credit_status='hold'` 기본값)

### 중복 차단

- `(owner_group_id, document)` UNIQUE — 이미 존재
- 외상 등록 시 store_client.global_client_id 가 NULL 이면 차단

### 검증 위치

- 백엔드: `CreditValidationService.assertCreditEligible(storeClientId, amount, txn)`
  - global_client.document 비어있으면 `THROW BadRequestException('CRÉDITO requiere DNI/CUIT')`
  - credit_status === 'blocked' 이면 차단
  - balance + amount > credit_limit 이면 차단 (또는 supervisor PIN 으로 override)
- 프론트: PaymentSummaryModal 에서 crédito 추가 시점에 사전 차단 (better UX)

---

## 백엔드 모듈 구조

```
api-ventago/src/app/credit/
  credit.module.ts
  credit-ledger.model.ts
  credit-payments.model.ts
  dto/
    create-credit-payment.dto.ts
    update-credit-policy.dto.ts
  services/
    credit-ledger.service.ts        ← 모든 ledger INSERT 의 단일 진입점
    credit-payment.service.ts       ← 입금 + FIFO 분배
    credit-validation.service.ts    ← 외상 가능 여부 / 한도 / DNI 검증
  controllers/
    credit-payment.controller.ts    ← POST /api/credit/payments
    credit-policy.controller.ts     ← PATCH /api/credit/policy/:storeClientId
    credit-report.controller.ts     ← GET /api/credit/reports/aging, /top-debtors
```

### 핵심 서비스 시그니처

```ts
// credit-ledger.service.ts
async appendMovement(input: {
  storeId: number;
  storeClientId: number;
  movementType: CreditMovementType;
  amount: number;          // 항상 양수
  saleId?: number;
  paymentId?: number;
  parentLedgerId?: number;
  dueDate?: string;        // YYYY-MM-DD
  branchId?: number;
  terminalId?: number;
  userId?: number;
  note?: string;
  transaction: Transaction;  // ★ 외부에서 받은 트랜잭션 필수
}): Promise<CreditLedger>;
```

> **Pool 안전**: `transaction` 을 항상 인자로 받는다. 내부에서 새로 열지 않는다.
> 호출자(sales-create / credit-payment) 가 트랜잭션 lifecycle 을 관리.

### Seña 라이프사이클 (ASCII 다이어그램)

```
┌────────────────────────────────────────────────────────────────┐
│ 1) 손님이 venta 예약 + 선수금 입금 ($100.000)                  │
│    sale 생성 (status=DRAFT)                                    │
│    senia_in $100.000 (sale_id=V-1500, bucket=senia, +)         │
│    sale_senias.amount_received = $100.000, status='active'     │
│    senia_balance: 0 → 100.000                                  │
└────────────────────────────────────────────────────────────────┘
        │
        ├─── 분기 A: 며칠 후 venta 확정 (총액 $80.000) ───┐
        │                                                  │
        │   senia_apply $80.000 (sale_id=V-1500, −)        │
        │   sale_senias.amount_applied = $80.000           │
        │   sale_senias.status = 'applied'                 │
        │   senia_balance: 100.000 → 20.000                │
        │                                                  │
        │   잔여 $20.000 → favor 로 자동 전환 (옵션)       │
        │   senia_to_favor $20.000 + favor_in $20.000      │
        │   senia_balance: 20.000 → 0                      │
        │   favor_balance: 0 → 20.000                      │
        │   sale_senias.status = 'converted'               │
        │                                                  │
        │
        ├─── 분기 B: venta 취소, 손님에게 현금 환불 ──────┐
        │                                                  │
        │   senia_refund $100.000 (현금 출금)              │
        │   senia_balance: 100.000 → 0                     │
        │   sale_senias.status = 'refunded'                │
        │
        └─── 분기 C: venta 취소, favor 로 전환 ───────────┐
                                                           │
            senia_to_favor $100.000 + favor_in $100.000    │
            senia_balance: 100.000 → 0                     │
            favor_balance: 0 → 100.000                     │
            sale_senias.status = 'converted'               │
```

### sales-create.service.ts 수정 지점

`create()` 메서드 (L54-255), 현재 트랜잭션 없음 → **`SERIALIZABLE` 트랜잭션으로 전체 감싸기**.

```ts
// 의사 코드
return await this.sequelize.transaction(
  { isolationLevel: Transaction.ISOLATION_LEVELS.SERIALIZABLE },
  async (t) => {
    const sale = await this.saleModel.create(..., { transaction: t });
    await this.processSaleItems(..., t);
    await this.processPaymentMethods(..., t);

    // 신규: crédito / seña / favor 처리
    const creditoPayments = payments.filter(p => p.slug === 'credito');
    const seniaPayments   = payments.filter(p => p.slug === 'senia');   // Seña 적용
    const favorPayments   = payments.filter(p => p.slug === 'favor');

    if (creditoPayments.length || seniaPayments.length) {
      await this.creditValidationService.assertCreditEligible(
        sale.storeClientId, sumCreditAmount, t,
      );
    }

    // 1) Seña 적용 (이미 받은 예약금 → 매출에 흡수)
    for (const sp of seniaPayments) {
      await this.creditLedgerService.appendMovement({
        movementType: 'senia_apply', amount: sp.amount,
        saleId: sale.id, parentLedgerId: sp.parentSeniaLedgerId,
        ..., transaction: t,
      });
    }

    // 2) Favor 적용 — 손님이 명시적으로 'Usar favor' 클릭한 경우에만 payments 에 포함됨
    //    (UI 에서 자동 추가 금지). 백엔드는 단순히 들어온 그대로 처리하지만,
    //    favor_balance 부족하면 BadRequestException 으로 차단.
    for (const fp of favorPayments) {
      if (fp.amount > storeClient.favorBalance) {
        throw new BadRequestException(
          `Favor insuficiente: pidió ${fp.amount}, disponible ${storeClient.favorBalance}`,
        );
      }
      await this.creditLedgerService.appendMovement({
        movementType: 'favor_apply', amount: fp.amount,
        saleId: sale.id, ..., transaction: t,
      });
    }

    // 3) 외상 발생
    for (const cp of creditoPayments) {
      await this.creditLedgerService.appendMovement({
        movementType: 'sale_credit', amount: cp.amount,
        saleId: sale.id, dueDate: computeDueDate(...), ..., transaction: t,
      });
    }

    return sale;
  },
);
```

### Seña 입금 (sale 생성 시점) — sales-senia.service.ts (신규)

손님이 venta 를 미리 예약하면서 선수금을 낼 때 호출되는 별도 흐름. Sale 은 status=DRAFT 또는 PENDING_DELIVERY 로 생성되고, `senia_in` ledger 1건 + `sale_senias` 1행 + 외부 결제수단(현금/이체) 기록.

```ts
// sales-senia.service.ts
async createSaleWithSenia(dto: CreateSaleSeniaDto): Promise<Sale> {
  return await this.sequelize.transaction({ isolationLevel: SERIALIZABLE }, async (t) => {
    // 1) 클라이언트 검증 (DNI/CUIT 필수)
    await this.creditValidationService.assertSeniaEligible(dto.storeClientId, t);

    // 2) Sale 생성 (status=DRAFT)
    const sale = await this.saleModel.create({...dto, status: 'DRAFT'}, {transaction: t});

    // 3) 외부 결제수단(현금/이체) 기록 (실제 자금 유입)
    await this.salePaymentMethodModel.create({
      saleId: sale.id, paymentMethodId: dto.fundingMethodId, // efectivo/banco/...
      amount: dto.seniaAmount,
    }, {transaction: t});

    // 4) senia_in ledger
    const ledger = await this.creditLedgerService.appendMovement({
      movementType: 'senia_in', amount: dto.seniaAmount,
      saleId: sale.id, ..., transaction: t,
    });

    // 5) sale_senias 캐시 행
    await this.saleSeniaModel.create({
      saleId: sale.id, storeClientId: dto.storeClientId,
      storeId: dto.storeId, amountReceived: dto.seniaAmount,
      amountApplied: 0, status: 'active',
    }, {transaction: t});

    return sale;
  });
}
```

### Seña 환불/전환 (venta 취소 시) — sales-senia.service.ts

```ts
async cancelSaleWithSenia(saleId: number, action: 'refund' | 'to_favor'): Promise<void> {
  return await this.sequelize.transaction({ isolationLevel: SERIALIZABLE }, async (t) => {
    const senia = await this.saleSeniaModel.findOne({
      where: {saleId}, lock: t.LOCK.UPDATE, transaction: t,
    });
    const openAmount = senia.amountReceived - senia.amountApplied;

    if (action === 'refund') {
      await this.creditLedgerService.appendMovement({
        movementType: 'senia_refund', amount: openAmount,
        saleId, note: 'Devolución en efectivo', ..., transaction: t,
      });
      await senia.update({status: 'refunded'}, {transaction: t});
    } else {
      // senia_to_favor + favor_in 짝
      await this.creditLedgerService.appendMovement({
        movementType: 'senia_to_favor', amount: openAmount,
        saleId, ..., transaction: t,
      });
      await this.creditLedgerService.appendMovement({
        movementType: 'favor_in', amount: openAmount,
        note: `Conversión Seña→Favor (sale ${saleId})`, ..., transaction: t,
      });
      await senia.update({status: 'converted'}, {transaction: t});
    }
  });
}
```

> 트랜잭션 내부에서 외부 API/이메일/소켓 emit 호출 금지 (pool blocking 원인).
> 소켓 emit 이 필요하면 트랜잭션 commit 후 별도 try/catch.

### FIFO 입금 분배 (credit-payment.service.ts)

```ts
async registerPayment(dto: CreateCreditPaymentDto): Promise<CreditPayment> {
  return await this.sequelize.transaction({ isolationLevel: SERIALIZABLE }, async (t) => {
    // 1) store_client 잠금
    const sc = await StoreClient.findByPk(dto.storeClientId, {
      lock: t.LOCK.UPDATE, transaction: t,
    });

    // 2) credit_payments INSERT
    const payment = await CreditPayment.create({...}, { transaction: t });

    // 3) 미결제 sale_credit 을 created_at ASC 로 조회
    const openCredits = await this.fetchOpenCredits(sc.id, t);

    // 4) FIFO 차감 → payment_in ledger 생성 (parent_ledger_id 매핑)
    let remaining = dto.totalAmount;
    for (const credit of openCredits) {
      if (remaining <= 0) break;
      const apply = Math.min(remaining, credit.openAmount);
      await this.creditLedgerService.appendMovement({
        movementType: 'payment_in', amount: apply,
        parentLedgerId: credit.id, paymentId: payment.id,
        ..., transaction: t,
      });
      remaining -= apply;
    }

    // 5) 잔여는 favor_in 으로 적립
    if (remaining > 0) {
      await this.creditLedgerService.appendMovement({
        movementType: 'favor_in', amount: remaining,
        paymentId: payment.id, ..., transaction: t,
      });
    }

    // 6) store_clients.balance / last_payment_at 업데이트
    await sc.update({
      balance: sc.balance - dto.totalAmount,
      lastPaymentAt: new Date(),
    }, { transaction: t });

    return payment;
  });
}
```

---

## 프론트엔드 변경

### nueva-venta 결제 흐름

(외상 등록 UX 흐름은 본 SPEC 하단 별도 섹션 참고)

수정 파일:

- `views/homes/components/ProductList/components/PaymentSummaryModal.tsx`
  - 결제수단 옵션에 crédito/favor/seña 추가 시 클라이언트 선택 강제 + 검증
  - crédito 선택 시: 만기일 입력 / credit_limit 표시 / 한도 초과 시 disabled
  - **`seniaUiMode === 'separated'`** (기본):
    - favor 선택 시: 자동 추가 금지. favor_balance > 0 이면 dismissible 알림 박스 표시.
      점원이 손님 의사 확인 후 `[Usar favor]` 클릭해야 추가됨. max = `min(favor_balance, total)`.
    - seña existente 선택 시: 활성 Seña 가 있는 venta 와 매칭 또는 새 reserva 생성 화면으로 이동
  - **`seniaUiMode === 'unified'`**:
    - favor + seña 를 분리 표시하지 않고 `combinedSaldoAFavor` 한 줄로 알림.
      "💰 Cliente tiene $ 298.000 a favor. ¿Usar?" + 단일 `[Aplicar saldo]` 버튼.
    - 자동 적용 금지 정책은 동일하게 유지 (손님 자산 원칙)
    - 백엔드 호출 시에는 `applyClientSaldo` 단일 endpoint 가 senia → favor 우선순위로 자동 분배

### 매장 모드 분기 helper

```ts
// ventago-app/src/utils/senia-ui-mode.ts (신규)
export function shouldUseUnifiedSaldoUI(store?: Pick<Store,'seniaUiMode'>): boolean {
  return store?.seniaUiMode === 'unified';
}
```

`useAuth().user.store.seniaUiMode` 또는 `useStoreSettings()` SWR 훅을 통해 매장 설정 조회.
- `views/homes/hook/SaleProductsContext.tsx`
  - `paymentMethods` 항목 타입에 `dueDate?: string` 추가

### 신규 페이지

- `pages/clientes/[id]/cuenta-corriente.tsx` — mockup `③ 고객 cuenta corriente` 구현
- `pages/credito/cobrar.tsx` 또는 cliente 페이지 내 모달 — mockup `④ 입금/Favor 등록`
- `pages/reportes/cuentas-por-cobrar.tsx` — mockup `⑤ Aging 보고서`

### SWR 훅 추가

| 훅 | 엔드포인트 |
|---|---|
| `useClientCreditSummary(storeClientId)` | `GET /api/credit/clients/:id/summary` |
| `useClientLedger(storeClientId, page)`  | `GET /api/credit/clients/:id/ledger` |
| `useCreditAging(storeId)`               | `GET /api/credit/reports/aging` |
| `useTopDebtors(storeId, limit)`         | `GET /api/credit/reports/top-debtors` |

---

## 태스크 목록

### Wave 1 — DB & 백엔드 코어 (선행, 1~2일)

- [ ] TASK-1: `migrations/phase26-credito-favor.sql` 작성 (credit_ledger / credit_payments / store_clients ALTER / **stores.senia_ui_mode** ALTER)
- [ ] TASK-2: `api-ventago/src/app/credit/` 모듈 스캐폴딩 (module + 2 model + 3 service)
- [ ] TASK-3: `CreditLedgerService.appendMovement()` 구현 + 단위 테스트
- [ ] TASK-4: `CreditValidationService.assertCreditEligible()` 구현 (DNI/CUIT/한도/status)
- [ ] TASK-5: `CreditPaymentService.registerPayment()` 구현 (FIFO + favor_in)
- [ ] TASK-6: `sales-create.service.ts` create() 를 SERIALIZABLE 트랜잭션으로 감싸고 ledger hook 추가
- [ ] TASK-7: opening balance 백필 스크립트 + dry-run

### Wave 2 — 컨트롤러 & 보고서 (1일)

- [ ] TASK-8: `credit-payment.controller.ts` (`POST /api/credit/payments`, `GET /api/credit/clients/:id/summary`, `GET /api/credit/clients/:id/ledger`)
- [ ] TASK-9: `credit-report.controller.ts` (`GET /api/credit/reports/aging`, `GET /api/credit/reports/top-debtors`)
- [ ] TASK-10: 인메모리 캐시 적용 (보고서 30s TTL — 기존 MemoryCacheService 사용)

### Wave 3 — 프론트엔드 (2~3일)

- [ ] TASK-11: SWR 훅 4개 추가 (`src/hooks/api/useClientCreditSummary.ts` 등)
- [ ] TASK-12: `PaymentSummaryModal.tsx` 외상/favor 분기 UI 추가 (next/dynamic 코드 스플리팅 유지) · **separated/unified 두 분기 모두 구현**
- [ ] TASK-12b: `utils/senia-ui-mode.ts` helper + `useStoreSettings` SWR 훅
- [ ] TASK-12c: `pages/configuracion/cuenta-corriente.tsx` — 점장이 senia_ui_mode 토글하는 설정 페이지 (audit 로그 기록)
- [ ] TASK-13: `SaleProductsContext` 타입 확장 (dueDate)
- [ ] TASK-14: `pages/clientes/[id]/cuenta-corriente.tsx` 신규 페이지 (next/dynamic)
- [ ] TASK-15: `pages/reportes/cuentas-por-cobrar.tsx` 신규 페이지 (Aging + Top deudores)
- [ ] TASK-16: 사이드바 메뉴 항목 추가 (Cuentas por cobrar)

### Wave 4 — 검증 & 운영 (1일)

- [ ] TASK-17: `npx eslint .` 0 errors 확인
- [ ] TASK-18: PostgreSQL pool 체크리스트 점검 (모든 transaction commit/rollback 시 release 보장)
- [ ] TASK-19: 정합성 검증 쿼리: `SELECT id, balance, (SELECT SUM(CASE WHEN movement_type IN ('sale_credit','favor_apply','adjustment') THEN amount ELSE -amount END) FROM credit_ledger WHERE store_client_id=sc.id) FROM store_clients sc` 비교
- [ ] TASK-20: 운영 마이그레이션 (영업 종료 후 점검 창)

---

## 완료 기준

- [ ] `eslint .` 오류 0 개
- [ ] `npm run build` (api + app) 모두 성공
- [ ] `credit_ledger` 정합성 쿼리 결과 모든 store_client 가 balance == ledger SUM
- [ ] nueva-venta 에서 crédito 결제수단으로 매출 등록 → store_clients.balance 정확히 증가, ledger 1행 생성
- [ ] 입금 등록 → FIFO 로 가장 오래된 sale_credit 부터 차감, 잔여는 favor_in
- [ ] DNI 없는 고객에게 crédito 시도 → 명확한 에러 메시지 반환
- [ ] 한도 초과 시 차단 동작
- [ ] Aging 보고서 5 버킷(vigente/1-30/31-60/61-90/90+) 정확히 분류
- [ ] separated 모드 매장에서 KPI 3카드, unified 모드 매장에서 KPI 2카드로 정확히 분기 렌더
- [ ] unified 모드에서 `[Aplicar saldo]` 클릭 시 백엔드가 senia → favor 순서로 자동 분배, ledger 에는 정확한 movement_type 으로 기록 (UI 추상화는 ledger 에 영향 없음)

---

## 금지사항 / 주의사항

1. **ledger UPDATE/DELETE 절대 금지** — 정정은 반대 movement 로만
2. **트랜잭션 내부 외부 호출 금지** (HTTP, socket emit, 메일) — pool blocking 원인
3. **store_id 격리 위반 절대 금지** — 모든 쿼리 store_id WHERE 명시
4. **PG10 호환 SQL 사용** — `GENERATED AS IDENTITY` 금지, `BIGSERIAL` 사용
5. **balance 직접 수정 금지** — 항상 ledger 기록 후 balance 갱신, 둘이 한 트랜잭션
6. **운영 적용은 영업 종료 후** — 진행 중 트랜잭션과 충돌 위험
7. **마이그레이션은 별도 SQL 파일** — `api-ventago/migrations/` 에 커밋
8. **Phase 25 store_clients 격리 규칙 그대로 유지** — global_clients 의 document 비어있으면 외상 거부

---

## 별도 follow-up (이번 작업과 분리)

- 운영 로그 `error-2026-04-29.log` 에 `column p.cost_price does not exist` 반복 발생 — `reportsStocksCockpit.service.ts:309` 별건 수정 필요. 본 SPEC 와 무관.

---

## nueva-venta 외상 등록 UX 흐름 (제안)

기존 `PaymentSummaryModal` 에 최소 변경으로 외상/favor 를 자연스럽게 끼워넣는 것이 목표.

### 단계 A — 클라이언트 선택 강제

```
[현재 동작] 클라이언트 미선택 시에도 매출 가능
      ↓
[변경] 결제수단으로 'Crédito' 또는 'Favor' 추가 시,
      selectedClient.globalClientId 가 NULL 이면
      모달 상단에 빨간 알림 + "Seleccionar cliente con DNI/CUIT" 버튼.
      해당 결제수단은 disabled 로 추가 불가.
```

### 단계 B — Crédito 추가 시 추가 입력

결제수단 드롭다운에서 "Crédito" 를 고르면, 금액 옆에 다음 미니 패널이 inline 으로 펼쳐진다:

```
┌─────────────────────────────────────────────────┐
│ Crédito · cuenta corriente                      │
│ Cliente: María Rodríguez (CUIT 27-31456789-4 ✓)│
│ Disponible: $ 132.000 / 200.000 ████░░░░░░ 34% │
│ Vence el: [ 2026-05-29 ]  Plazo: 30 días        │
│ ⚠ Si supera el límite, requiere PIN supervisor  │
└─────────────────────────────────────────────────┘
```

- 만기일 default = today + `store_clients.credit_term_days`
- 사용자가 만기일 변경 가능 (단, max +90 일 / 점장 권한 시 +180 일)
- 입력 금액이 한도 초과 시 input 빨간 테두리 + supervisor PIN 모달 트리거 옵션

### 단계 C — Favor 사용 (구입자 명시적 선택, **자동 적용 금지**)

> **정책**: Favor 는 손님 자산이다. 손님이 "이번에 favor 쓸게요" 라고 *명시적으로* 결정한 경우에만 적용한다. 시스템이 자동으로 차감하면 손님 입장에서 "내가 저축해둔 돈" 이 알림 없이 사라지는 느낌이라 불만 발생 + 점원이 손님에게 묻지 않고 적용해 분쟁 가능.

- 모달 열릴 때 `useClientCreditSummary` 가 favor 잔액을 표시한다 — **알림만**, 자동 추가하지 않는다.
- favor > 0 이면 결제수단 영역 상단에 **dismissible info box** 표시:
  ```
  💰 Este cliente tiene $ 18.000 a favor disponible.
     [ Usar favor en esta venta ]   [ No usar ]
  ```
- 손님 의사 확인 후 점원이 `[Usar favor]` 클릭 → favor 결제수단이 추가됨.
- 추가된 결제수단 행에서 사용 금액을 자유롭게 조정 가능 (max = `min(favor_balance, total)`).
- "No usar" 또는 modal 을 그냥 닫으면 favor 는 **그대로 보존**, 다음 매출에 다시 알림.
- "묻지 마라" 옵션 (개별 client 또는 매장 단위 설정) 은 본 SPEC 범위 밖 — 추후 별도 feature 로 검토.

> 같은 정책이 입금(payment) 화면에도 적용된다. 외상 입금 시 FIFO 차감 후 잔여가 생기면 favor_in 으로 적립되지만, **반대로 favor 가 있는 손님이 다시 외상 결제를 하더라도 favor 가 자동 사용되지 않는다**. 점원이 입금 화면에서 "favor 로 외상 일부 정리할까요?" 묻고 별도 cobro 처리 (Adelanto a Favor → 'Aplicar favor a deuda existente' 기능).

### 단계 D — 혼합 결제 지원

UX 가 자주 쓰이는 시나리오:

1. **순수 외상**: Crédito 1건 = 총액
2. **선납 차감**: Favor + Efectivo 또는 Favor + Crédito
3. **부분 입금 + 외상**: Efectivo + Crédito (자주 쓰임 — 손님이 일부만 가져옴)
4. **여러 결제수단**: Tarjeta + Efectivo + Crédito

→ 모든 조합이 이미 `payments[]` 배열로 표현되므로 UI 변경 최소화.
"Pagado ahora" / "A crédito" 두 줄을 totals 영역에 추가만 하면 충분.

### 단계 E — 확정 직전 미리보기

`Confirmar venta` 누르기 전 alert 영역에 다음 메시지 표시 (favor 사용 시):

```
✓ Venta total: $ 101.500
✓ Pagado ahora: $ 68.000 (Efectivo $ 50.000 + Favor $ 18.000 ← uso explícito)
⏱ Quedará a crédito: $ 33.500, vence 29/05/2026
   → Se generará 1 movimiento sale_credit + 1 favor_apply
```

favor 사용 안 함 시:

```
✓ Venta total: $ 101.500
✓ Pagado ahora: $ 50.000 (Efectivo)
⏱ Quedará a crédito: $ 51.500, vence 29/05/2026
ℹ El cliente tiene $ 18.000 a favor que NO se utilizó (preservado).
```

### 단계 F — 키보드 단축키

- `F9` = Ofrecer / quitar favor (toggle — favor 가 있을 때만, **자동 적용 아님**)
- `F10` = Pagar todo a crédito (한도 충분할 때만)
- `F11` = supervisor PIN
- `F12` = Confirmar venta (기존)

### 단계 G — 에러 시나리오 처리

| 시나리오 | 동작 |
|---------|------|
| DNI 없는 클라이언트 + Crédito | 모달에서 사전 차단, "Editar cliente" 바로가기 |
| 한도 초과 | input 빨간색 + supervisor PIN 모달 또는 금액 자동 cap |
| credit_status='blocked' | Crédito 옵션 자체가 disabled, 툴팁 사유 표시 |
| favor 잔액 < 입력 favor 금액 | 백엔드 차단 (BadRequestException) + 프론트 사전 max 클램프 |
| favor 가 있는데 사용 선택 안 함 | 정상 진행. preview 에 "preservado" 안내만 표시. 절대 자동 적용 금지 |
| 네트워크 실패 (서버 측 한도 검증) | 트랜잭션 롤백, 사용자에게 재시도 버튼 |

---

## 마이그레이션 / 배포 순서

1. dev 환경에서 마이그레이션 SQL 적용 → 백엔드 실행 → 백필 스크립트 dry-run
2. 백엔드 단위 테스트 + 정합성 쿼리 통과 확인
3. 프론트 빌드 + 로컬 nueva-venta 시나리오 7개 수동 테스트
4. staging (만약 별도면) 배포 → 1일 관찰
5. 운영 배포 (영업 종료 후):
   - a. 운영 SQL 적용 (`sudo -u postgres psql -d ventago < phase26-credito-favor.sql`)
   - b. 백필 스크립트 실행
   - c. 정합성 쿼리 0 차이 확인
   - d. Jenkins 백엔드 + 프론트 배포
   - e. 매장당 테스트 매출 1건씩 (CART/coolsistema/genius/ACE)
6. 다음날 영업 시작 전 모니터링 (error log + slow query log)
