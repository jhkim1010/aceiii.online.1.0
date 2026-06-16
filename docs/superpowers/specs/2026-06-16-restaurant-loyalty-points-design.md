# Restaurant Loyalty Points — 식당 주문 고객 캡처 + 포인트 적립

**Date:** 2026-06-16
**Status:** Design approved — ready for implementation plan
**Builds on:** Phase 39 (Modo Restaurante — POS por mesas), Phase 25/34 (Client CRM: global_clients / store_clients)

---

## 1. 목표 (Goal)

식당(restaurante) 모드에서 테이블 주문을 시작할 때, mozo(웨이터) 선택 직후 **고객 대표자의 핸드폰 + 이름을 (선택적으로) 입력**받아 기존 CRM 고객에 연결한다. 식당 결제가 완료되면 **결제 총액의 매장별 설정 % 만큼 포인트를 적립**한다. 주문 모달에서 핸드폰 입력 시 해당 고객의 **현재 누적 포인트 잔액**을 표시해 직원이 안내할 수 있게 한다.

핵심 원칙: **기존 시스템 확장.** 신규 CRM/고객 개념을 만들지 않고 기존 `store_clients`/`global_clients` 를 재사용한다. sales 테이블과 식당 결제 플로우(Phase 39)를 그대로 쓰되 nullable 컬럼만 추가해 소매 모드 회귀 영향 0.

---

## 2. 결정 사항 (locked decisions)

| 항목 | 결정 |
|------|------|
| **범위** | 고객 캡처 + 포인트 **적립만**. 포인트 사용(redemption/할인 차감)은 **다음 Phase**로 분리 |
| **입력 필수 여부** | **선택(optional)** — walk-in 손님은 핸드폰 없이 주문 가능. 입력한 경우에만 고객 연결 + 적립 |
| **고객 매칭** | **기존 CRM 재사용** — 핸드폰으로 `store_clients` 조회 → 있으면 이름 자동완성 + 그 고객에 적립, 없으면 신규 생성(global+store 자동 동기화) |
| **적립률 정의** | admin/configuración 에서 **매장별 "결제액의 %"** 설정 (`store_configs`) |
| **포인트 가시성** | **주문 모달에서 현재 잔액 표시만.** 영수증 인쇄 ❌, CRM 상세 화면 표시 ❌ |
| **적용 범위** | **식당 결제만** (RestaurantPaymentModal / settleSale). 소매 결제 적립은 범위 외 |
| **저장 방식** | 접근 A(경량) — 신규 ledger 테이블 없이 컬럼 2개 + config 2개. redemption Phase 시 ledger 로 확장 |

---

## 3. 데이터 모델 (접근 A — 경량)

신규 테이블 없음. 컬럼 추가만:

### 3.1 마이그레이션

```sql
-- 누적 포인트 잔액 (매장별 고객 단위)
ALTER TABLE store_clients
  ADD COLUMN loyalty_points_balance DECIMAL(12,2) NOT NULL DEFAULT 0;

-- 이 sale 이 적립한 포인트 (멱등성 키 겸 기록). NULL = 아직 적립 안 됨
ALTER TABLE sales
  ADD COLUMN loyalty_points_earned DECIMAL(12,2);

-- 매장별 적립 설정
ALTER TABLE store_configs
  ADD COLUMN loyalty_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE store_configs
  ADD COLUMN loyalty_earn_pct DECIMAL(5,2) NOT NULL DEFAULT 0;
```

**호환성:** PG10/PG15/PG18 모두 `ALTER TABLE ... ADD COLUMN ... DEFAULT` 지원. 모든 신규 컬럼은 default 보유 또는 nullable → 기존 행/소매 모드 회귀 0.

**snake_case 매핑** (`underscored: true`): 모델 `loyaltyPointsBalance` → 컬럼 `loyalty_points_balance` 등.

### 3.2 멱등성 설계

`sales.loyalty_points_earned IS NULL` 이 "아직 적립 안 됨"을 의미. 결제 정산 시 이 값이 NULL 일 때만 1회 적립 → 결제 socket+polling 이중 도착(T-39-17 double-trigger)에도 이중 적립 방지. 별도 unique 제약 불필요.

---

## 4. 백엔드 (api-ventago)

### 4.1 고객 조회 엔드포인트

```
GET /restaurant-sale/client-lookup?phone=<phone>
@Auth()
```
- 핸드폰 **정규화**(공백/하이픈/괄호 제거) 후 store 범위 내 `store_clients` ⨝ `global_clients` 매칭
- 반환: `{ storeClientId, name, pointsBalance }` 또는 `null`
- 다중 매칭 시: 활성(`is_active`) store_client 중 최신 1건 선택
- store_id 스코프 강제 (IDOR 방지)

### 4.2 주문 DTO 확장

`PlaceOrderRequestDto` 에 optional 필드 추가:
```typescript
@IsOptional() @IsString()  customerPhone?: string;
@IsOptional() @IsString()  customerName?: string;
@IsOptional() @IsInt()     storeClientId?: number;  // lookup 으로 이미 해소된 경우
```

### 4.3 placeOrder 서비스

- `customerPhone` 제공 시:
  - `storeClientId` 가 함께 오면 그대로 사용
  - 아니면 핸드폰 정규화 후 resolve-or-create: 기존 store_client 있으면 연결, 없으면 **기존 client 생성 로직 재사용**(global_clients + store_clients 자동 동기화 hook)으로 신규 생성. `customerName` 을 이름으로 사용
  - `sale.storeClientId` 설정
- **첫 주문(DRAFT 생성)에서만** 고객 연결. 같은 테이블에 추가 주문 누적 시 기존 sale 의 storeClientId 유지(덮어쓰지 않음)
- 핸드폰 미제공(walk-in): `storeClientId` null → 적립 대상 아님

### 4.4 결제 정산 시 적립 (settleSale / paySale — Phase 39-05)

PAID 처리 **트랜잭션 내부**에서:
```
if (loyalty_enabled && sale.storeClientId && sale.loyaltyPointsEarned == null) {
  points = round(sale.totalAmount * loyalty_earn_pct / 100, 2)
  sale.loyaltyPointsEarned = points
  storeClient.loyaltyPointsBalance += points   // 동일 트랜잭션
}
```
- 같은 DB 트랜잭션으로 부분 상태 방지
- pool 절약 준수 (추가 connection 없이 기존 결제 트랜잭션에 편승)

### 4.5 update-flag 화이트리스트

Phase 39-04 의 store-config update-flag 화이트리스트에 `loyalty_enabled`, `loyalty_earn_pct` 추가.

---

## 5. 프론트엔드 (ventago-app)

### 5.1 OrderModal (식당 주문 모달)

- **첫 주문(테이블 libre)**: mozo 선택 직후 입력 영역 추가:
  - 핸드폰 입력 필드 + 이름 입력 필드 (둘 다 선택)
  - 핸드폰 입력 debounce → `GET /restaurant-sale/client-lookup` 호출
    - 매칭: 이름 자동완성 + **"누적 포인트: Ypt"** 칩 표시, `storeClientId` 보유
    - 미매칭: 이름 직접 입력 가능, 신규 생성 예정
  - placeOrder 전송 시 `customerPhone` / `customerName` / `storeClientId` 포함
- **기존 주문에 추가 / Cambiar mozo**: 이미 연결된 고객 + 잔액을 **read-only** 표시(재입력 없음)
- 입력 없이 바로 주문 가능(walk-in)

### 5.2 configuración (StoreConfigContext — Phase 39-06)

- 식당 설정 영역에:
  - `loyalty_enabled` 토글
  - `loyalty_earn_pct` % 숫자 입력 (0~100, DECIMAL(5,2))
- 저장은 기존 update-flag 경로 사용

### 5.3 StoreConfigContext

`loyalty_enabled`, `loyalty_earn_pct` 두 값을 컨텍스트에 노출(OrderModal 이 적립 활성 여부 판단 / 미리보기에 활용 가능).

---

## 6. 엣지 케이스 / 정합성

| 케이스 | 처리 |
|--------|------|
| 결제 이중 트리거(socket+polling) | `loyalty_points_earned IS NULL` 가드로 1회만 적립 |
| walk-in (핸드폰 없음) | `storeClientId` null → 적립 없음 |
| `loyalty_enabled = false` | 고객 연결돼도 적립 0 |
| 핸드폰 다중 매칭 | 활성 store_client 중 최신 1건 선택 |
| 멀티테넌트 격리 | lookup·적립·생성 전부 store_id 스코프 |
| 결제 실패/롤백 | 적립은 정산 트랜잭션 내부 → 롤백 시 함께 취소 |
| 소매 결제 | 적립 트리거 없음(식당 settleSale 경로에만) → 회귀 0 |

---

## 7. 범위 외 (Out of Scope — 명시)

- 포인트 **사용/할인 차감**(redemption) — 다음 Phase. 이때 `loyalty_ledger` 테이블로 확장 예정
- 영수증(cuenta/resumen) 포인트 인쇄 — print-agent 변경 없음
- CRM 고객 상세 화면 포인트 잔액/이력 표시
- 소매 결제 포인트 적립
- 포인트 만료(expiry) / 등급(tier) / 리워드 카탈로그

---

## 8. 인수 기준 (Acceptance Criteria)

1. 마이그레이션 적용 후 기존 소매 sale 생성/결제 회귀 0 (신규 컬럼 모두 default/nullable)
2. configuración 에서 `loyalty_enabled` 토글 + `loyalty_earn_pct` 저장/조회 동작
3. 식당 OrderModal 에서 mozo 선택 후 핸드폰+이름 입력 영역 노출, walk-in 은 미입력 주문 가능
4. 핸드폰 입력 시 기존 고객 매칭 → 이름 자동완성 + 현재 누적 포인트 칩 표시
5. 미매칭 핸드폰 → 신규 store_client 생성 + sale 연결 (global_clients 동기화 확인)
6. 식당 결제 완료 시 `loyalty_enabled` 일 때 `round(total * pct/100, 2)` 포인트가 store_client 잔액에 가산, `sales.loyalty_points_earned` 기록
7. 동일 sale 재정산/이중 트리거 시 이중 적립 0
8. `loyalty_enabled=false` 또는 walk-in 시 적립 0
9. lookup/적립 모두 store_id 스코프 밖 데이터 접근 불가
