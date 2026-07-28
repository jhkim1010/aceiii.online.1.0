# Phase 64: 트랜잭션 안전성 · 동시성 · 데이터 정합성 — Specification

**Created:** 2026-07-27
**Source:** 외부 코드 리뷰 12건(사용자 제공, 2026-07-27) + 코드 재검증 (`64-CONTEXT.md`)
**Scope:** Wave 1 ~ Wave 10 (결함 12건 전부)
**Requirements:** 12 locked (R1~R12, 결함 번호와 1:1)

## Goal

Ventago 의 돈·재고를 움직이는 쓰기 경로에서 **"부분 저장 · 중복 실행 · 매장 경계 침범"** 세 부류의 정합성 결함을 제거한다.
판매 생성은 요청 단위로 멱등해지고(같은 키 재시도 = 같은 응답, 판매 1건), 판매 취소·보류 판매·생산 완료는 전부-또는-전무로 커밋되며, outbox·오프라인 동기화는 다중 워커에서도 작업을 한 번만 집행한다. 재고 원장은 append-only 로 고정되고, 모든 판매 참조는 요청자의 `storeId` 안에서만 해석된다.

Phase 63 이 잡은 **판매 트랜잭션 내부 경합**(채번·락 순서) 위에, Phase 64 는 **트랜잭션 경계 밖과 요청 단위 멱등**을 얹는다. 신규 기능 0, 전부 무회귀 교정.

## Background

Phase 63 이후 판매 생성 자체(`sales-create.service.ts:354`–`:483`)는 단일 트랜잭션 + advisory lock 채번 + 정렬된 재고 차감으로 건전하다. 그러나:

- 그 트랜잭션 **바깥**(커밋 후 `:486` ledger, `:496` 프린터, `:590` 재조회)에서 던져진 예외가 클라이언트에 500 으로 보이고, 멱등키가 없어 POS 재시도가 판매를 복제한다.
- 취소(`:672`)·보류(`suspended-sales.service.ts:137/265/350`)·생산(`work-order.service.ts:67`)은 애초에 트랜잭션이 없거나 최소 범위만 감싼다.
- 생산 완료는 `Stocks` 에 존재하지 않는 `productId` 컬럼을 참조해 **현재 재고를 전혀 반영하지 못한다**.
- outbox tick(`outbox.service.ts:104`)은 락 없는 `findAll` + 별도 `update` 로 job 을 집는다. 중복 집행·정체가 구조적으로 가능하다.
- 오프라인 push(`offline-push.service.ts:89`)는 DB 에 UNIQUE 가 있음에도 check-then-insert 를 해서, 동시 중복은 500 이 되고 중간 크래시는 판매를 영구 미생성 상태로 굳힌다.
- 판매 DTO 의 `productId`/`sellerId`/`branchId` 는 `storeId` 검증 없이 조회된다.

## Requirements

각 요구사항 = 결함 1건. **Current** = 현행 동작(검증됨), **Target** = 목표, **Acceptance** = 완료 판정.

---

### R1. 판매 생성 요청 멱등 + 커밋 후 500 제거 (결함 1) — Wave 1

- **Current:** 멱등키 없음. 커밋 후 `attachCreditLedgerForSale`(`:486`) / `sendToprinters`(`:496`) / `findOne`(`:590`) 이 await 되어, 여기서 throw 하면 판매는 저장됐는데 500 응답. POS 재시도 → 판매 2건.
- **Target:**
  1. `Idempotency-Key` 헤더(선택)를 받아 (storeId, key) 로 스코프한 멱등 레코드에 요청 해시 + 응답 본문을 저장. 같은 키 재요청 = 저장된 응답 그대로 재생(신규 판매 0건). 키 미전송이면 현행 동작(하위호환).
  2. 커밋 후 단계는 전부 **비치명**으로 격리. ledger 실패는 판매를 500 으로 만들지 않고 경고 + 후속 보정 대상으로 기록. 프린터/AFIP 는 이미 fire-and-forget 이므로 유지.
  3. 커밋 후 최종 조회(`findOne`) 실패 시에도 최소 응답(saleId + dailyNumber)을 200 으로 반환.
- **Acceptance:** 같은 `Idempotency-Key` 로 동시 2요청 → sales 행 1건, 두 응답 body 동일. 커밋 후 단계를 강제로 throw 시키는 테스트에서 응답이 2xx 이고 판매 1건.

### R2. 판매 취소 원자화 + 이중 취소 차단 (결함 2) — Wave 2

- **Current:** `nullifySale`(`:672`) 은 채번+역분개 INSERT(`:697`–`:728`)만 트랜잭션. items/재고/결제/할인/추가요금/원본 상태(`:735`–`:850`)는 트랜잭션 밖. status 검사(`:677`)는 락 없음 → 동시 2회 취소 시 역분개 2건 + 재고 2배 복원.
- **Target:** 메서드 전체를 단일 트랜잭션으로. 진입 즉시 원본 sale 을 `FOR UPDATE` 로 잠그고 트랜잭션 **안에서** status 재검사. 재고 복원은 판매 생성과 **동일한 productId ASC 순서**(교착 방지). MP 환불 등 외부 I/O 는 커밋 후.
- **Acceptance:** 동일 saleId 동시 취소 2요청 → 1건 성공 + 1건 `이미 취소됨` 400, 역분개 1건, `products.stock` 복원 1회분. 중간 강제 실패 주입 시 역분개·재고·원본상태 **전부** 롤백.

### R3. 보류 판매 원자화 (결함 4) — Wave 3

- **Current:** `create`(`:137`) / `update`(`:265`) / `remove`(`:350`) 모두 트랜잭션 없음. `update` 는 items·discount·recharge 를 destroy 후 재생성(`:304`–`:306`) + 예약 재고 ±1(`:283`/`:323`) → 중간 실패 시 아이템 없는 보류 판매 또는 예약 재고 드리프트.
- **Target:** 세 메서드 각각 단일 트랜잭션. `recordReservationMoves`(`:59`)에 `transaction` 인자 추가 후 전 호출부 전달. `update`/`remove` 진입 시 대상 헤더 `FOR UPDATE`.
- **Acceptance:** 각 메서드에 실패 주입 → 헤더/아이템/할인/추가요금/예약 이동이 모두 원복. 동시 `update`+`remove` → 하나만 성공, 예약 재고 복원 1회.

### R4. 생산 완료 스키마 정합 + 원자화 (결함 3) — Wave 4

- **Current:** `completeWorkOrder`(`:67`) 가 `stockModel.findOne({where:{productId}})`(`:123`/`:137`/`:152`) 및 `create({productId})`(`:159`) 사용 — `Stocks` 에는 `productBranchId`(`stocks.model.ts:24`)만 존재. 원장 행을 잔액처럼 `update`(`:129`/`:143`/`:157`). 트랜잭션·락 없음, `status===COMPLETED` 검사(`:92`)는 경합에 무방비.
- **Target:** `createStockMovement`(`stocks.service.ts:98`) 및 판매 경로(`sales-create.service.ts:422`–`:443`)와 동일한 패턴으로 재작성 — 지점 해석 → `findOrCreateProductBranch` → **append-only 원장 INSERT** (원자재 -, 완제품 +) + `products.stock` 잔액 캐시 `increment`/`decrement`. 전 과정 단일 트랜잭션, work order 를 `FOR UPDATE` 로 잠그고 트랜잭션 안에서 COMPLETED 재검사. BOM 재료 락도 productId ASC.
- **Acceptance:** 완료 1회 실행 시 원자재 원장 -N, 완제품 원장 +M, `products.stock` 동일 반영, `production_results` 1건, work order COMPLETED. 동시 2회 완료 → 1건만 성공. 실패 주입 시 전부 롤백. `product_id` 컬럼 참조 SQL 0건(grep 게이트).

### R5. outbox enqueue 원자성 (결함 5) — Wave 5

- **Current:** `sales-create.service.ts:508`–`:526` 이 커밋 **후** `enqueuePush(...).catch(warn)`. `outbox.service.ts:52` 는 `transaction` 을 지원하나 미사용 → 프로세스가 그 사이 죽으면 외부 채널 재고가 영구 미반영.
- **Target:** enqueue 를 판매 트랜잭션 **안에서** INSERT (외부 API 호출 없음 = pool 안전, Phase 43 설계 의도 그대로). `dedupeKey` 부분 UNIQUE 위반은 정상 skip 유지. 트랜잭션 안에서는 절대 HTTP 호출 금지.
- **Acceptance:** 판매 커밋 = outbox 행 존재가 항상 동치. 판매 롤백 시 outbox 행 0. 커밋 직후 프로세스 강제 종료 후 재기동 → 해당 push job 이 pending 으로 남아 처리됨.

### R6. outbox claim/lease 안전화 (결함 6) — Wave 5

- **Current:** `tick()`(`:104`) 이 `findAll`(`:124`) 후 별도 `update({status:'processing'})`(`:138`). 프로세스 로컬 `running` 플래그(`:37`)뿐 → 멀티워커에서 같은 job 중복 집행. `processing` 상태로 죽으면 회수 불가.
- **Target:** 단일 원자 claim 문으로 교체:

  ```sql
  UPDATE sync_outbox SET status = 'processing',
         attempts = attempts + 1,
         locked_by = $1,               -- 워커 식별자
         lease_expires_at = NOW() + INTERVAL '5 minutes'
   WHERE id IN (
     SELECT id FROM sync_outbox
      WHERE status = 'pending' AND next_retry_at <= NOW()
      ORDER BY next_retry_at ASC
      LIMIT $2
      FOR UPDATE SKIP LOCKED           -- 다른 워커가 잡은 행은 건너뜀
   )
   RETURNING *;
  ```

  만료 lease 회수(주기 실행):

  ```sql
  UPDATE sync_outbox
     SET status = 'pending', locked_by = NULL, lease_expires_at = NULL,
         last_error = COALESCE(last_error, 'lease expired — reclaimed')
   WHERE status = 'processing' AND lease_expires_at < NOW();
  ```

  마이그레이션: `locked_by TEXT NULL`, `lease_expires_at TIMESTAMPTZ NULL` 컬럼 추가 + 배포 시 1회성 `UPDATE sync_outbox SET status='pending' WHERE status='processing'` (in-flight 회수) + due 조회용 인덱스(`CONCURRENTLY`).
- **Acceptance:** 워커 2개 동시 tick → 같은 job 을 두 번 집행하지 않음(process 호출 횟수 = job 수). `processing` 상태로 강제 종료한 job 이 lease 만료 후 자동 pending 복귀. 기존 `dedupeKey`/백오프 동작 불변.

### R7. 오프라인 판매 멱등 원자화 (결함 7) — Wave 6

- **Current:** `processOne`(`:89`) 이 `findOne`(`:100`) → `create`(`:115`) → apply(`:129`). DB UNIQUE(`op_uuid`)는 존재하나 코드가 위반을 처리하지 않아 동시 중복 = 500. insert 후 apply 전 크래시 = status `received` 고착 → 재전송이 `received` 를 그대로 반환(`:108`)해 판매 영구 미생성.
- **Target:**
  1. check-then-insert 제거. `INSERT ... ON CONFLICT (op_uuid) DO NOTHING RETURNING id` 로 **삽입 성공자만 적용 수행**. 삽입하지 못했으면 기존 행을 읽어 결과 반환.
  2. `received` 상태(= 적용 미완) 재전송은 **duplicate 로 확정하지 말고 재적용 시도**. 판매 생성 자체가 R1 멱등키(`offline:{op_uuid}`)를 쓰므로 재적용해도 판매는 1건.
  3. 원장 상태 전이(`received` → `applied`/`error`)와 `result_id` 기록은 판매 생성 결과 확정 직후 같은 흐름에서 수행.
- **Acceptance:** 동일 uuid 동시 2 batch → 500 없음, `applied` 1 + `duplicate` 1, sales 1건. insert 후 강제 크래시 → 재전송 시 판매 정상 생성 + `applied` 전이. 기존 배치 응답 형식(`PushOpResult`) 불변.

### R8. 매장 경계 검증 (결함 8) — Wave 7

- **Current:** `Seller.findByPk`(`:163`), `Clients.findByPk`(`:194`/`:302`), `productModel.findByPk`(`:963`) 모두 storeId 스코프 없음. `dtoBranchId`(`:337`)는 `branch.storeId` 검증 없이 사용.
- **Target:** 판매 생성 입력의 모든 FK 를 요청 `storeId` 로 스코프 검증:
  - 상품: `where: { id, storeId }` (generic 상품은 매장별 lazy 생성 규칙 유지) — 불일치 시 404
  - 판매원: `where: { id, storeId }` — 불일치 시 현행처럼 NULL 강등이 아니라 **400** (조용한 데이터 오염 방지)
  - 지점: `branch.storeId === storeId` 아니면 400
  - 고객: `store_clients` 경로 우선(Phase 25 dual-FK), 레거시 `clients` 는 storeId 확인 후 사용
  - 선행 태스크: 운영/로컬에서 **기존 위반 건수 0 조사 쿼리**(SELECT only) 실행 후 차단 도입
- **Acceptance:** 타 매장 productId/sellerId/branchId 로 판매 생성 시도 → 4xx, sales 행 0. 정상 매장 판매 무회귀(회귀 스위트 통과). 조사 쿼리 결과가 문서에 첨부됨.

### R9. 재고 원장 불변 정책 (결함 9) — Wave 7

- **Current:** `stocks.service.ts` `create`(`:62`)/`updateStock`(`:73`)/`findByProduct`(`:81`)/`delete`(`:85`) 가 존재하지 않는 `productId` 를 참조하거나 원장 행을 UPDATE/DELETE 한다. `products.stock` 잔액 캐시와 항상 어긋난다.
- **Target:** `stocks` 는 **append-only 원장**임을 코드로 강제.
  - `findByProduct` → `productBranchId` 경유 조회로 교정(또는 `productId`+`branchId` 인자로 ProductBranch join)
  - `updateStock`/`delete` → 직접 변경 금지. 보정이 필요하면 **반대 부호 보정 이동 행 추가**(`note='ajuste manual'` + 사용자/사유 기록) + `products.stock` 동시 조정, 단일 트랜잭션.
  - 기존 라우트는 즉시 제거하지 않고 보정 이동으로 위임하거나 410 Gone (계획 단계 Q4 결정 반영)
  - `create` 는 `productBranchId` 를 요구하고 store 소유권 검증
- **Acceptance:** 원장 행을 UPDATE/DELETE 하는 코드 경로 0(grep 게이트). 보정 API 호출 후 `SUM(stocks.stock)` 과 `products.stock` 이 일치. 존재하지 않는 컬럼 참조 SQL 0건.

### R10. 재고 부족 검사의 동시성 방어 — **설정값에 따라 동작 분기** (결함 10) — Wave 8

- **Current:** `processSaleItems`(`:981`)가 `product.stock <= 0` 을 **락 없이** 읽고, 실제 차감은 `:467` `applyStockDecrements` 에서 일어난다. 재고 1개를 두 터미널이 동시에 통과 → `products.stock` 음수.
- **Target:** 권위 설정 `store_configs.allowSaleWithoutStock`(v2 단일 권위 소스, `sales-create.service.ts:234`) 값에 따라 **명시적으로 두 갈래**로 동작한다. 설정을 무시한 일률적 차단 금지:

  | 설정 | 동작 | 근거 |
  |------|------|------|
  | `allowSaleWithoutStock = true` (허용, 기본) | **현행 유지** — 재고 검사 없음, 음수 재고 허용. 락 추가 없음(경합·지연 0) | 재고 없이도 팔아야 하는 매장의 업무 요구. 여기서 차단하면 회귀 |
  | `allowSaleWithoutStock = false` (비허용) | 재고 검사를 **차감과 같은 문장으로 원자화** — 검사·차감을 분리하지 않는다 | 설정이 "막겠다"이면 실제로 막혀야 함. 현행은 막힌다고 표시만 하고 동시 판매는 통과 |

  비허용 매장의 원자 차감 패턴(검사 = 차감, TOCTOU 소멸):

  ```sql
  UPDATE products SET stock = stock - $qty
   WHERE id = $productId AND stock >= $qty
  RETURNING stock;
  -- 0 rows = 재고 부족 → 트랜잭션 롤백 + "Sin stock disponible" 400
  ```

  - 잠금/차감 순서는 Phase 63 B-0c 규칙(`productId` ASC) 유지 — 교착 방지.
  - 부모 변형 상품(`parentId`) 차감도 같은 규칙 적용.
  - 설정 조회는 이미 `create` 진입부의 Store+StoreConfig 단일 JOIN(`:215`)에 있으므로 **신규 쿼리 0**.
  - 프런트/관리자 화면(Preferencias 토글)은 변경 없음 — 기존 설정 UI 가 그대로 이 동작을 제어한다.
- **Acceptance:**
  - 비허용 매장: 재고 1개 상품에 동시 2판매 → 1건 성공 + 1건 400, `products.stock = 0`(음수 아님).
  - 허용 매장: 동일 시나리오에서 **2건 모두 성공**하고 `products.stock = -1` (현행과 동일, 회귀 없음).
  - 설정 토글 후 재로그인 없이 다음 판매부터 동작이 바뀐다(캐시 TTL 내 반영 범위 문서화).

### R11. 백데이트 판매 채번 (결함 11) — Wave 8

- **Current:** `now = dtoSaleDate ?? new Date()`(`:258`)로 과거 날짜 판매를 만들 수 있는데, `reserveDailyNumber`(`:610`)는 advisory lock 키(`:618`)와 `saleDayLocal`(`:630`) 둘 다 `NOW()` 기준 → 백데이트 판매가 **오늘 번호**를 소비하고 `sale_day_local=오늘 / sale_date=과거` 로 불일치 저장.
- **Target:** `reserveDailyNumber(storeId, tz, t, targetDate)` 로 확장. 락 키와 `sale_day_local` 모두 **대상 영업일(매장 TZ 기준)** 로 계산. 그 날짜의 최대 번호 + 1 을 발급하므로 과거 일자에도 번호가 연속된다. `sale_date` 와 `sale_day_local` 은 항상 같은 날을 가리킨다.
- **Acceptance:** 3일 전 날짜로 판매 등록 → `sale_day_local = 그 날짜`, `daily_number` = 그 날의 마지막+1, 오늘 번호는 소비되지 않음. UNIQUE 인덱스(`store_id, sale_day_local, daily_number`) 충돌 0. 동일 과거 날짜 동시 2건도 번호 중복 0.

### R12. 공개 쇼핑몰 pool 예산 (결함 12) — Wave 8

- **Current:** `shop-readonly-db.service.ts:23`–`:40` 이 워커당 `max=SHOP_DB_POOL_MAX||15` 의 별도 pool 을 열고, `SHOP_DB_*` 미설정 시 **메인 DB 호스트로 폴백**. 메인 pool 은 워커당 20(`database.module.ts:52`–`:58`). 4워커 기준 80 + 60 = 140 클라이언트가 pgbouncer `pool_size=50` 을 두고 경합 → 공개 트래픽이 POS 를 굶길 수 있음. 서비스 주석(`:12`–`:13`)의 `min=10/max=80` 서술은 현행과 불일치.
- **Target:**
  1. 총 커넥션 예산을 한 곳에 문서화: `워커수 × (메인 max + 공개몰 max) ≤ pgbouncer pool_size 여유` 산식과 현재 실측값.
  2. 폴백 감지(= `SHOP_DB_HOST` 미설정이라 메인과 같은 인스턴스) 시 **경고 로그 + 공개몰 상한 자동 축소**, 기동 로그에 실효 예산 출력.
  3. 부팅 시 pool 설정 요약을 진단 엔드포인트(`app/diagnostics/*`)에 노출해 운영에서 확인 가능하게.
  4. 오래된 주석 교정.
- **Acceptance:** 기동 로그에 `메인 max × 워커 + 공개몰 max × 워커 = 총 N (pgbouncer pool_size=M)` 이 찍힌다. 폴백 상태에서 경고가 뜨고 실효 상한이 축소된다. 공개몰 부하 중 POS 판매 acquire 타임아웃 0건(W9 부하 시나리오로 확인).

---

## Wave 태스크

의존성: **W1 → W6**(오프라인이 판매 멱등키 재사용), **W5 는 W1 이후**(enqueue 를 판매 트랜잭션에 넣으려면 판매 경로가 안정된 뒤), 그 외는 병렬 가능.

```
W1 ──┬─► W5 ──┐
     └─► W6 ──┤
W2 ──────────┤
W3 ──────────┼─► W9 ─► W10
W4 ──────────┤
W7 ──────────┤
W8 ──────────┘
```

### Wave 1 — 판매 멱등키 + 커밋 후 500 제거 (R1)
1. 마이그레이션: `sale_idempotency_keys` (`id`, `store_id`, `idempotency_key`, `request_hash`, `sale_id`, `response_body JSONB`, `status`, `created_at`, `expires_at`) + `UNIQUE (store_id, idempotency_key)` + owner/시퀀스 `coolsistema` 이전 DO 블록. 로컬 5432 + 운영 5434 동시 적용용 SQL 파일 커밋.
2. `SalesController` 에서 `Idempotency-Key` 헤더 수신(선택). 미전송 = 현행 경로.
3. 멱등 래퍼: 판매 트랜잭션 **안에서** 키 행을 `INSERT ... ON CONFLICT DO NOTHING`. 삽입 실패 = 이미 처리 중/완료 → 완료면 저장된 `response_body` 재생, 처리 중이면 409 + `Retry-After`.
4. 커밋 후 단계 격리: `attachCreditLedgerForSale`/`sendToprinters`/`findOne` 실패가 응답 코드에 영향 없도록. ledger 실패는 구조화 로그(`event:'sale_ledger_failed'`)로 남겨 보정 가능하게.
5. 응답 확정 후 `response_body` + `sale_id` 를 멱등 행에 기록.
6. 프런트 송신부: ventago-app POS(`nueva-venta`) + mobile-sales-app 이 판매당 UUID v4 를 생성해 헤더로 전송, 재시도 시 **같은 키 유지**.
7. 만료 정리(24h) — 기존 cron 에 태스크 1개 추가(신규 스케줄러 금지).

### Wave 2 — 판매 취소 트랜잭션화 + FOR UPDATE (R2)
1. `nullifySale` 전체를 `sequelize.transaction` 으로 감싸기(기존 내부 소 트랜잭션 제거, 채번은 같은 트랜잭션 재사용).
2. 진입 즉시 `Sale.findByPk(saleId, { lock: Transaction.LOCK.UPDATE, transaction: t })` + 트랜잭션 안 status/`nullifiedSaleId` 재검사.
3. items·결제수단·할인·추가요금·원본 상태 업데이트를 전부 트랜잭션 인자와 함께 실행.
4. 재고 복원을 `productId` ASC 정렬 후 일괄 수행(판매 생성과 동일 순서, 교착 방지) + `SET LOCAL lock_timeout='3s'` 동일 적용.
5. MP 환불(`mpRefundService.refundForSale`)은 **커밋 후**로 이동, 실패 시 기존처럼 `mpRefundFailed` 플래그만.
6. 회귀: 프로모션 포함 취소(`promo_refund_attempt` 로그), 배송/온라인 미러 취소 경로.

### Wave 3 — 보류 판매 트랜잭션화 (R3)
1. `recordReservationMoves` 에 `transaction` 인자 추가(내부 `ProductBranch.findOne/create`, `Stocks.create` 전부 전달).
2. `create`/`update`/`remove` 각각 단일 트랜잭션화.
3. `update`/`remove` 진입 시 대상 헤더 `FOR UPDATE`(동시 편집/삭제 직렬화).
4. `update` 의 destroy→recreate 구간을 같은 트랜잭션에 포함.
5. 회귀: WP 웹훅 생성 보류 판매(`source='wp'`), 보류 → 판매 확정(restore) 경로, 예약 재고 원장 부호.

### Wave 4 — 생산 완료 스키마 수정 + 트랜잭션화 (R4)
1. `completeWorkOrder` 전체 단일 트랜잭션 + work order `FOR UPDATE` + 트랜잭션 안 COMPLETED 재검사.
2. 재고 반영을 `productBranchId` 원장 패턴으로 재작성: 지점 해석 → `findOrCreateProductBranch` → `Stocks.create({productBranchId, stock: ±qty, note})` + `products.stock` `increment`/`decrement`.
3. 원자재/반제품/완제품 모두 동일 패턴. 락 순서 productId ASC.
4. 생산용 지점 결정 규칙 확정(work order 의 지점 → 없으면 매장 단일 지점 → 없으면 400. 조용한 skip 금지).
5. 비허용 설정 매장에서 원자재 부족 시 R10 과 같은 원자 차감 규칙 적용 여부 결정(기본: 생산은 부족해도 진행 + 경고, 문서화).
6. grep 게이트: `stocks` 대상 쿼리에서 `productId` 사용 0건.

### Wave 5 — outbox 원자성 + claim/lease (R5, R6)
1. 마이그레이션: `sync_outbox` 에 `locked_by`, `lease_expires_at` 추가 + due 인덱스 `CONCURRENTLY` + 배포 시 1회성 `processing → pending` 회수.
2. `enqueue` 호출부(`sales-create.service.ts:508`–`:526`)를 판매 트랜잭션 안으로 이동, `transaction` 전달. 트랜잭션 안 HTTP 호출 금지 규칙 주석 명시.
3. `tick()` 의 조회+갱신을 R6 의 단일 `UPDATE ... FOR UPDATE SKIP LOCKED ... RETURNING` 으로 교체.
4. lease 만료 회수 쿼리를 tick 시작 시 1회 실행(별도 cron 추가 없음).
5. `running` 프로세스 로컬 플래그는 유지하되 **정확성의 근거가 아님**을 주석화(정확성은 SKIP LOCKED + lease 가 담당).
6. 회귀: `dedupeKey` 중복 skip, 백오프 배열, `BATCH_SIZE=20` 상한, 실패 → `failed` 전이.

### Wave 6 — 오프라인 판매 멱등 원자화 (R7)
1. `processOne` 의 `findOne` → `create` 를 `INSERT ... ON CONFLICT (op_uuid) DO NOTHING RETURNING *` 단일 문으로 교체.
2. 삽입 성공자만 적용 수행. 삽입 실패 시 기존 행 조회 후 상태별 응답(`applied`→duplicate / `error`→error / `received`→**재적용 시도**).
3. 판매 적용 시 R1 멱등키로 `offline:{op_uuid}` 전달 → 재적용해도 판매 1건 보장.
4. 상태 전이(`received`→`applied`/`error`) + `result_id` 기록을 적용 결과 확정 직후 수행.
5. 회귀: 배치 50건 상한, per-op try/catch(한 건 실패가 배치 전체를 죽이지 않음), seq 순서 보존.

### Wave 7 — 테넌트 검증 + 재고 CRUD 정리 (R8, R9)
1. **선행(읽기 전용)**: 운영/로컬에서 매장 경계 위반 기존 데이터 조사 쿼리 실행 — 타 매장 product/seller/branch 를 참조하는 sales 건수. 결과를 `64-VALIDATION.md` 에 첨부. **0 이 아니면 차단 도입 전 사용자 확인.**
2. 판매 생성 입력의 상품/판매원/지점/고객 조회를 전부 `storeId` 스코프로 교정(R8 규칙표대로).
3. 판매원 불일치를 NULL 강등 대신 400 으로 전환(조용한 오염 제거).
4. `stocks.service.ts` 의 `findByProduct` 를 ProductBranch 경유로 교정.
5. `updateStock`/`delete` 를 보정 이동(반대 부호 행 + `products.stock` 동시 조정, 단일 트랜잭션)으로 대체, 기존 라우트는 위임 또는 410.
6. `create` 는 `productBranchId` 필수 + 매장 소유권 검증.
7. grep 게이트: 원장 UPDATE/DELETE 경로 0, `stocks` 대상 `productId` 참조 0.

### Wave 8 — 재고 동시성(설정 분기) + 백데이트 + 풀 예산 (R10, R11, R12)
1. R10: `allowSaleWithoutStock=false` 매장에서만 조건부 원자 차감(`UPDATE ... WHERE stock >= qty RETURNING`) 적용. `true` 매장은 락·검사 추가 없이 현행 유지. 두 갈래를 코드 주석과 테스트로 명시.
2. R10: 부모 변형 상품 차감도 동일 규칙, productId ASC 순서 유지.
3. R11: `reserveDailyNumber` 에 대상 영업일 인자 추가 — advisory lock 키와 `sale_day_local` 을 대상 날짜로 계산. `nullifySale` 의 역분개 채번도 원본 판매일 기준 정책 확정(기본: 취소는 취소일 기준 = 현행 유지, 문서화).
4. R12: 커넥션 예산 산식 문서화 + 기동 로그 출력 + 폴백 감지 시 경고/상한 축소 + 진단 엔드포인트 노출 + 오래된 주석 교정.
5. 회귀: 허용 매장 판매 지연 변화 없음(P95), 오늘 날짜 판매 번호 연속성, 공개몰 부하 중 POS 무영향.

### Wave 9 — 동시성 테스트 CI (교차)
1. `npm run test:concurrency` 스크립트 신설 — 실제 PG18 을 쓰는 통합 테스트, 유닛 CI 와 분리(플레이키가 전체 빌드를 막지 않도록).
2. 테스트 케이스(각 Wave 의 Acceptance 를 실행 가능한 형태로):
   - 동일 `Idempotency-Key` 병렬 2요청 → sales 1건 (W1)
   - 동일 saleId 병렬 취소 2요청 → 역분개 1건 (W2)
   - 보류 판매 update 중 실패 주입 → 아이템 원복 (W3)
   - 병렬 `completeWorkOrder` → 1건만 성공 (W4)
   - 워커 2개 병렬 outbox tick → job 중복 집행 0 (W6/R6)
   - 동일 uuid 병렬 offline push → applied 1 + duplicate 1, 500 없음 (W6)
   - 재고 1개 병렬 판매: 비허용 매장 → 1건 성공 / 허용 매장 → 2건 성공 음수 허용 (W8/R10 **두 갈래 모두**)
   - 과거 날짜 병렬 판매 2건 → daily_number 중복 0 (W8/R11)
3. 기존 부하 하네스(`loadtest/pos-scenario.js`, `burst-multistore.js`) 재사용해 공개몰 부하 중 POS acquire 타임아웃 0 확인(R12).
4. GitHub Actions 워크플로 또는 로컬 게이트 스크립트로 등록(운영 배포 전 필수 통과 목록에 추가).

### Wave 10 — 검증 + 문서화
1. 전 Wave Acceptance 재실행 + 결과를 `64-VALIDATION.md` 에 기록.
2. 마이그레이션 3종(W1 멱등키 테이블, W5 outbox 컬럼/인덱스, 필요 시 W7 보정 이동 메타) **로컬 5432 + 운영 5434 동시 적용** 후 스키마 대조 결과 첨부. owner/시퀀스 이전 확인.
3. `.planning/intel/db-schema-*.md` 재생성(`./.planning/intel/db-schema.regen.sh`).
4. 브라우저 UAT: POS 판매/취소/보류/생산/재고 화면 무회귀 확인.
5. CLAUDE.md 에 규약 3줄 추가 — (a) 쓰기 경로는 단일 트랜잭션 원칙, (b) `stocks` 는 append-only 원장, (c) 트랜잭션 안 외부 I/O 금지.
6. 운영 배포 후 관측: 판매 500율, outbox `failed` 증가율, `products.stock` 음수 건수(허용 매장 제외) 모니터.

## 완료 기준 (Phase Exit)

- [ ] R1~R12 전 항목 Acceptance PASS, 근거가 `64-VALIDATION.md` 에 기록됨
- [ ] `test:concurrency` 전 케이스 통과 (W9 목록 전부, R10 은 허용/비허용 두 갈래 모두)
- [ ] 마이그레이션 로컬(5432)·운영(5434) 동시 적용 + 스키마 대조 일치, 신규 객체 owner=coolsistema
- [ ] grep 게이트 0건: `stocks` 대상 `productId` 참조 / 원장 UPDATE·DELETE / 트랜잭션 안 HTTP 호출
- [ ] 소매(의류) 판매 전 경로 무회귀 — 판매·취소·보류·재고 UAT PASS
- [ ] 기동 로그에 커넥션 예산 산식 출력, 공개몰 부하 중 POS acquire 타임아웃 0
- [ ] Jenkins 빌드 PASS (api-ventago + ventago-app, ESLint 포함)

## 회귀 테스트 (필수 통과 목록)

| # | 시나리오 | 기대 | 관련 |
|---|----------|------|------|
| RG-1 | 일반 POS 판매(현금/카드/분할) | 현행과 동일, 응답 shape 불변 | W1 |
| RG-2 | 멱등키 미전송 판매 | 현행 동작 그대로(하위호환) | W1 |
| RG-3 | 구버전 APK/에이전트 요청 | 헤더 없어도 정상 판매 | W1, W6 |
| RG-4 | 프로모션 포함 판매 취소 | `promo_refund_attempt` 로그 + 재고 복원 1회 | W2 |
| RG-5 | MP 결제 판매 취소 | 환불 실패해도 취소 유지 + `mpRefundFailed` | W2 |
| RG-6 | 보류 판매 생성 → 수정 → 확정 | 예약 재고 순증감 0, 아이템 보존 | W3 |
| RG-7 | WP 웹훅 보류 판매(`source='wp'`) | 무회귀 | W3 |
| RG-8 | BOM 기반 생산 완료 | 원자재 -, 완제품 +, `products.stock` 일치 | W4 |
| RG-9 | outbox 켜짐/꺼짐(`USE_OUTBOX_SYNC`) | 두 경로 모두 무회귀 | W5 |
| RG-10 | 오프라인 배치 50건 부분 실패 | 실패 1건이 나머지 49건을 막지 않음 | W6 |
| RG-11 | generic 상품 판매 | 매장별 lazy 생성 유지, 재고 미기록 | W7 |
| RG-12 | 레거시 import 데이터 판매 | 매장 검증 통과(위반 0 사전 확인 기반) | W7 |
| RG-13 | 재고 허용 매장 판매 | 음수 재고 허용, 지연 증가 없음 | W8/R10 |
| RG-14 | 재고 비허용 매장 판매 | 재고 초과 판매 차단, 400 메시지 동일 | W8/R10 |
| RG-15 | 오늘 날짜 판매 번호 | 연속 증가, UNIQUE 충돌 0 | W8/R11 |
| RG-16 | 식당/배달/온라인 판매 경로 | 공유 코드 변경분 무회귀 | 전체 |
| RG-17 | pool 사용률 | P95 지연 및 acquire 타임아웃 현행 이하 | 전체 |
