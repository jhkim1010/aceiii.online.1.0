# Phase 64: 트랜잭션 안전성 · 동시성 · 데이터 정합성 — Research

**Created:** 2026-07-27
**Purpose:** 각 결함에 대해 업계에서 검증된 패턴과 PostgreSQL 구현 형태를 정리. 계획(PLAN) 단계에서 바로 코드로 옮길 수 있는 수준까지.

---

## 1. 요청 멱등키 (R1) — Stripe / AWS 패턴

### 표준 계약
- 클라이언트가 요청마다 UUID 생성 → `Idempotency-Key` 헤더. **재시도는 같은 키를 유지**해야 의미가 있다(키를 새로 만들면 새 판매).
- 서버는 키별로 (요청 지문, 응답 본문, 상태)를 저장. 같은 키 재요청은 **저장된 응답을 그대로 재생**한다 — 다시 계산하지 않는다.
- 요청 본문이 다른데 키가 같으면 422 (키 재사용 오류). 지문 = 정규화된 본문의 SHA-256.
- 처리 중(in-flight) 재요청은 409 + `Retry-After` — 두 요청을 동시에 처리하지 않는다.
- 키는 만료된다(Stripe 24시간). 만료 후 같은 키는 새 요청으로 취급.

### PostgreSQL 구현 핵심
멱등 행 삽입이 **판매와 같은 트랜잭션**이어야 "판매는 됐는데 키는 없다"가 불가능해진다.

```sql
-- 트랜잭션 시작 직후
INSERT INTO sale_idempotency_keys (store_id, idempotency_key, request_hash, status)
VALUES ($1, $2, $3, 'processing')
ON CONFLICT (store_id, idempotency_key) DO NOTHING
RETURNING id;
-- 0 rows = 이미 존재 → 기존 행 조회:
--   status='completed' → response_body 재생 (판매 생성 스킵)
--   status='processing' → 409 Retry-After
--   request_hash 불일치 → 422
```

Ventago 적용 노트:
- `UNIQUE (store_id, idempotency_key)` — 매장 스코프. 다른 매장의 키 충돌 없음.
- Sequelize 에서는 `findOrCreate` 대신 raw `ON CONFLICT DO NOTHING RETURNING` 권장 — `findOrCreate` 는 SELECT 후 INSERT 라 같은 경합에 노출된다(Phase 64 가 고치려는 바로 그 패턴).
- 응답 본문 저장은 `JSONB`. POS 응답은 `findOne(sale.id)` 결과라 수 KB 수준.
- 만료 정리는 기존 cron 에 태스크 추가 — 새 스케줄러를 만들면 워커 복귀 시 중복 실행 위험(부하 진단에서 이미 지적된 항목).

### 참고 계보
- Stripe API `Idempotency-Key` (POST 전용, 24h 보존, 동일 키+다른 본문 = 오류)
- AWS `ClientToken` (EC2/RDS 등, 일정 시간 내 동일 토큰 = 동일 결과)
- IETF draft `The Idempotency-Key HTTP Header Field` — 헤더명/409/422 시맨틱의 근거

---

## 2. "커밋됐는데 500" 제거 — 커밋 후 단계 격리

### 원칙
트랜잭션이 커밋된 순간부터 그 요청은 **성공**이다. 이후 단계(알림·프린터·외부 push·재조회)는 실패해도 응답 코드를 바꾸면 안 된다.

### 세 갈래 처리
| 후속 작업 | 처리 |
|---|---|
| 반드시 일어나야 하고 소비자가 있다 | 같은 트랜잭션에 **outbox 행 INSERT** (R5) — 워커가 나중에 집행 |
| 실패해도 업무가 성립한다 | fire-and-forget + 구조화 로그 (프린터, AFIP 자동발급 — 현행 유지) |
| 응답 조립용 조회 | 실패 시 축약 응답으로 폴백 (200 유지) |

Ventago 현행에서 세 갈래 중 **1번에 해당하는데 2번처럼 처리된 것**이 `attachCreditLedgerForSale`(별도 트랜잭션 + await). 크레디트/세냐는 돈이므로 유실되면 안 된다 → 판매 트랜잭션에 합치거나 outbox 로 보내는 두 선택지. 계획 단계에서 결정(기본: 우선 비치명 격리 + 구조화 로그로 보정 가능하게, 합치기는 락 보유 시간 영향 측정 후).

---

## 3. Transactional Outbox (R5, R6)

### 패턴 정의
"DB 커밋과 메시지 발행을 원자적으로" — 메시지를 브로커에 직접 보내지 말고 **같은 트랜잭션에서 outbox 테이블에 INSERT**, 별도 워커가 읽어 발행한다. 2PC 없이 at-least-once 를 얻는다. (Chris Richardson, *Microservices Patterns* — Transactional Outbox / Polling Publisher)

핵심 성질: **at-least-once 이지 exactly-once 가 아니다.** 소비자(외부 채널 push)는 멱등해야 한다. Ventago 는 `dedupeKey` 부분 UNIQUE 로 이미 중복 적재를 막고 있고, push 자체는 "현재 재고/가격 상태 전송"이라 본질적으로 멱등하다.

### 안전한 claim — `FOR UPDATE SKIP LOCKED`
PG 9.5+ 의 표준 큐 패턴. 잠긴 행을 **에러 없이 건너뛰어** 워커들이 서로 다른 job 을 집는다.

```sql
UPDATE sync_outbox o
   SET status = 'processing',
       attempts = attempts + 1,
       locked_by = $worker,
       lease_expires_at = NOW() + INTERVAL '5 minutes'
  FROM (
    SELECT id FROM sync_outbox
     WHERE status = 'pending' AND next_retry_at <= NOW()
     ORDER BY next_retry_at
     LIMIT $batch
     FOR UPDATE SKIP LOCKED
  ) s
 WHERE o.id = s.id
RETURNING o.*;
```

왜 현행이 위험한가: `SELECT`(락 없음) → `UPDATE status='processing'` 사이에 다른 워커가 같은 행을 읽는다. 두 워커가 같은 외부 push 를 동시에 던진다. 프로세스 로컬 `running` 플래그는 **한 프로세스 안에서만** 유효 — pm2 멀티워커/2인스턴스에서 무의미.

### lease(임대) 로 장애 복구
워커가 job 을 `processing` 으로 바꾼 뒤 죽으면 그 job 은 영원히 갇힌다. `lease_expires_at` 을 두고 만료분을 회수한다:

```sql
UPDATE sync_outbox
   SET status = 'pending', locked_by = NULL, lease_expires_at = NULL,
       last_error = COALESCE(last_error, 'lease expired — reclaimed')
 WHERE status = 'processing' AND lease_expires_at < NOW();
```

- lease 길이는 "정상 처리 최장 시간 × 여유". outbox 는 외부 HTTP 라 5분이 무난.
- 회수는 tick 시작 시 1회 — 별도 cron 을 만들면 중복 스케줄 위험.
- 배포 전환 시 in-flight `processing` 은 lease 컬럼이 NULL 이라 회수 조건에 안 걸린다 → 마이그레이션에 1회성 `UPDATE ... SET status='pending' WHERE status='processing'` 포함(R6 태스크 1).

### 대안 검토
- **LISTEN/NOTIFY 즉시 발행**: 지연은 줄지만 커넥션 상주 필요 + 알림 유실 시 폴링 폴백이 어차피 필요. 현행 cron 폴링 유지가 pool 예산에 안전.
- **pgmq / pg-boss 도입**: 기능은 풍부하나 신규 의존성·스키마. 결함 6 은 쿼리 2개로 해결되므로 과잉.

---

## 4. 원자적 상태 전이와 이중 실행 차단 (R2, R4)

### 안티패턴: check-then-act
```ts
const sale = await findOne(id);              // ← 락 없음
if (sale.status === NULLIFIED) throw ...;    // ← 이 사이에 다른 요청 통과
await doWork();                              // ← 두 번 실행됨
```
Ventago 의 `nullifySale:673-684`, `completeWorkOrder:92` 가 정확히 이 형태.

### 해법 A — 비관적 락 (권장, 본 Phase 채택)
```ts
await sequelize.transaction(async (t) => {
  const sale = await Sale.findByPk(id, { lock: t.LOCK.UPDATE, transaction: t });
  if (sale.status === NULLIFIED) throw new BadRequestException('이미 취소됨');
  // ... 전 작업을 t 로 수행
});
```
- 같은 행을 노린 두 번째 요청은 첫 트랜잭션이 끝날 때까지 대기 → 재검사에서 정상 거부.
- Phase 63 의 `SET LOCAL lock_timeout='3s'` 를 동일 적용해 무한 대기로 pgbouncer 슬롯을 먹지 않게 한다.

### 해법 B — 조건부 UPDATE (경량, 상태 전이만 필요할 때)
```sql
UPDATE sales SET status = 'Anulado', nullified_by_sale_id = $2
 WHERE id = $1 AND status <> 'Anulado'
RETURNING id;      -- 0 rows = 이미 누군가 취소함
```
"영향 행 수"가 곧 경합 판정. 다만 취소는 재고·결제·아이템까지 함께 움직여야 하므로 A 를 쓰고 B 는 보조로 쓴다.

### 교착(deadlock) 회피
여러 행을 잠글 때 **모든 경로가 같은 순서로** 잠근다. Phase 63 B-0c 가 판매 차감을 `productId` ASC 로 정렬한 이유와 동일. 취소·생산도 같은 정렬 규칙을 따라야 판매 ↔ 취소 간 교착이 안 생긴다.

---

## 5. 오프라인 동기화의 멱등 수신 (R7)

### 표준: 업서트 기반 수신 원장
모바일/에지 동기화의 정석은 "클라이언트가 op 마다 UUID 를 붙이고, 서버는 UUID 를 UNIQUE 로 받는다". (CouchDB 리비전, Firebase write id, Stripe 의 키와 같은 계열)

```sql
INSERT INTO offline_sync_ops (op_uuid, agent_id, ..., status)
VALUES ($1, ..., 'received')
ON CONFLICT (op_uuid) DO NOTHING
RETURNING id;
-- 0 rows = 이미 수신됨 → 기존 행 상태로 응답 결정
```

### Ventago 현행의 두 결함과 대응
1. **check-then-insert** → UNIQUE 가 있어도 동시 중복이 500 이 된다. 위 단일 문으로 교체하면 중복은 조용히 `duplicate` 가 된다.
2. **`received` 를 종결 상태로 취급** → insert 후 apply 전 크래시가 "판매 영원히 없음"으로 굳는다. `received` 는 **미완료**이므로 재전송 시 **재적용**해야 한다. 재적용의 안전성은 판매 멱등키(`offline:{op_uuid}`)가 보장 → at-least-once 수신 + 멱등 적용 = 사실상 exactly-once 효과.

이것이 W1(멱등키) → W6 의존성의 이유다. 멱등키 없이 재적용하면 판매가 복제된다.

---

## 6. 멀티테넌시 경계 강제 (R8)

### 계층별 방어
| 계층 | 수단 | Ventago 적용 |
|---|---|---|
| 쿼리 | 모든 조회에 `storeId` 조건 | W7 의 기본 수단 |
| 서비스 | 요청 스코프의 `storeId` 를 단일 출처로 사용 | JWT/세션의 storeId만 신뢰, DTO 의 storeId 는 검증 대상 |
| DB | Row-Level Security (RLS) | 도입 시 pgbouncer transaction pooling + `SET ROLE` 조합 검토 필요 — **본 Phase 범위 밖** |
| 복합 FK | `(id, store_id)` 복합 UNIQUE + 참조 | 스키마 변경 크므로 후속 과제 |

교훈적 사례: 테넌트 경계 사고는 대개 "조회 한 곳에서 storeId 를 빠뜨림"으로 발생한다. 판매 생성은 상품·판매원·지점·고객 네 갈래 참조가 있어 **한 곳만 빠져도 경계가 뚫린다**.

### 도입 순서 (중요)
차단을 먼저 넣으면 기존 위반 데이터가 있는 매장에서 판매가 즉시 멈춘다. 순서는 반드시:
1. 읽기 전용 조사 쿼리로 위반 건수 측정 →
2. 0 이면 차단 도입 / 0 이 아니면 데이터 교정 계획 먼저

---

## 7. 재고를 원장(ledger)으로 다루기 (R4, R9, R10)

### 이중 표현: 원장 + 잔액 캐시
Ventago 는 이미 올바른 구조를 갖고 있다 — `stocks`(append-only 이동 원장, `product_branch_id` 단위) + `products.stock`(잔액 캐시). 문제는 **일부 코드가 원장을 잔액처럼 다루는 것**(`work-order.service.ts:129/143/157`, `stocks.service.ts:73/85`).

회계 원장의 불변식:
- 행은 **추가만** 된다. 잘못된 이동은 삭제가 아니라 **반대 부호 보정 행**으로 상쇄한다(회계의 역분개 = Ventago 판매 취소가 이미 쓰는 방식).
- 잔액 = `SUM(원장)`. 캐시는 파생값이며 원장과 같은 트랜잭션에서만 갱신한다.
- 감사 가능성: 누가·왜 보정했는지가 행에 남는다(`note`, 사용자).

### 재고 초과 판매 방지의 정석 (R10)
검사와 차감을 **한 문장으로** 합치면 TOCTOU 가 원천 소멸한다:

```sql
UPDATE products SET stock = stock - $qty
 WHERE id = $id AND stock >= $qty
RETURNING stock;   -- 0 rows = 재고 부족
```

- `SELECT ... FOR UPDATE` 후 앱에서 비교하는 방식도 정확하지만 왕복이 하나 더 든다. 조건부 UPDATE 가 더 짧고 락 보유도 짧다.
- **Ventago 고유 요건**: 이 방어는 매장 설정 `store_configs.allowSaleWithoutStock` 이 `false`(비허용)일 때만 적용한다. `true`(허용)면 음수 재고가 **의도된 동작**이며, 여기에 조건부 차감을 걸면 정상 업무가 막히는 회귀가 된다. 설정 분기를 코드와 테스트 양쪽에 명시할 것.
- 변형 상품(부모/자식) 은 두 행을 건드리므로 정렬 규칙(productId ASC)을 반드시 유지.

---

## 8. 영업일 기준 번호 채번 (R11)

### 문제 유형
"일자별 연속 번호"는 (a) 어떤 날짜를 기준으로 하는가 (b) 그 날짜 범위에서 원자적으로 다음 번호를 잡는가 두 축이 있다. Phase 63 이 (b)를 advisory lock + `sale_day_local` 컬럼으로 해결했지만, (a)가 항상 `NOW()` 로 고정돼 있어 백데이트 입력에서 어긋난다.

### 해법
채번 함수가 **대상 영업일을 인자로** 받게 한다. 락 키와 저장 컬럼이 같은 날짜를 쓰면 구조적으로 어긋날 수 없다(Phase 63 F-14 가 타임존에 대해 세운 원칙을 날짜 선택에도 확장).

```sql
-- 대상 영업일 d (매장 TZ 기준 YYYY-MM-DD 문자열)
SELECT pg_advisory_xact_lock($store_id::int, replace($d,'-','')::int);
SELECT COALESCE(MAX(daily_number), 0) + 1
  FROM sales
 WHERE store_id = $store_id AND sale_day_local = $d AND activity_type = 'sale';
```

주의: 과거 날짜에 이미 번호가 있으면 그 다음 번호가 나온다 — 이는 정상이며 UNIQUE 인덱스(`store_id, sale_day_local, daily_number`)와도 정합적이다. 취소 역분개를 원본 판매일 기준으로 채번할지 취소일 기준으로 할지는 회계 정책 결정 사항(기본: 취소일 = 현행 유지).

---

## 9. 커넥션 풀 예산 (R12)

### 산식
```
총 클라이언트 커넥션 = 워커 수 × (메인 pool max + 부가 pool max)
필요 조건: 총 클라이언트 ≤ pgbouncer 서버 슬롯이 감당하는 큐 깊이
          pgbouncer pool_size ≤ PG max_connections - 예약분(관리/모니터링)
```
현행(2026-07-27 기준): 메인 20/워커(`database.module.ts:52`), 공개몰 15/워커(`shop-readonly-db.service.ts:34`), pgbouncer `pool_size=50`, PG `max_connections=200`.

### 격리 원칙
- 익명 공개 트래픽과 매출 트래픽은 **다른 예산**을 써야 한다 — Ventago 는 별도 `pg.Pool` + `shop_readonly` role 로 이미 옳은 방향.
- 다만 "격리"는 **다른 서버 슬롯을 쓸 때** 완성된다. `SHOP_DB_*` 미설정으로 같은 pgbouncer/PG 를 가리키면 격리는 이름뿐이고 예산만 두 배가 된다 → 폴백 감지 시 경고 + 상한 축소가 실질적 방어.
- 부하 시 병목은 앱 pool 이 아니라 pgbouncer 서버 슬롯 큐잉이다(Phase 63 실측). 따라서 앱 max 를 올리는 대응은 금물 — 큐만 길어진다.

### 관측
`database.module.ts:184`–`:201` 의 pool 사용률 경고(80%) + `app/diagnostics/*` 의 pool/outbox 조회를 재사용한다. 신규 관측 인프라 불필요.

---

## 10. 동시성 테스트 전략 (W9)

### 무엇을 테스트하나
동시성 결함은 **단위 테스트로 잡히지 않는다**(mock 은 락을 모른다). 실제 PG 에 병렬 요청을 던져 **불변식**을 검사해야 한다:

| 불변식 | 검사 |
|---|---|
| 같은 멱등키로 판매는 1건 | `SELECT count(*) FROM sales WHERE ...` |
| 취소는 원본당 역분개 1건 | `count(*) WHERE nullified_sale_id = $id` |
| 재고 캐시 = 원장 합 | `products.stock == SUM(stocks.stock)` (해당 지점) |
| 번호 중복 0 | `GROUP BY store_id, sale_day_local, daily_number HAVING count(*)>1` |
| outbox job 집행 1회 | processor 호출 카운터 == job 수 |

### 실행 형태
- 병렬성은 `Promise.all` 로 N 요청 동시 발사 후 결과 분포를 판정(성공 1 / 거부 N-1 형태).
- 실 DB 필요 → 유닛 CI 와 분리된 `test:concurrency` 스크립트. 플레이키가 전체 빌드를 막지 않게 한다.
- 반복 실행(예: 20회 루프)으로 경합 창을 넓혀야 재현된다. 1회 통과는 증거가 약하다.
- 기존 자산 재사용: `loadtest/pos-scenario.js`, `loadtest/burst-multistore.js`(Phase 63 하네스), `api-ventago/test/permissions-pool.load-spec.ts`(pool 부하 스펙 선례).

### 참고: 실측이 설계를 이겼던 사례
Phase 63 은 "1매장 20건/s 에서 1,197건 중 13건 번호 중복(한 번호 6회)"이라는 **실측**으로 채번 결함을 확정했다(`sales-create.service.ts:264` 주석). 동일 방식 — 가설이 아니라 카운트로 판정 — 을 Phase 64 전 Wave 에 적용한다.

---

## 참고 계보 요약

| 주제 | 패턴/출처 |
|---|---|
| 요청 멱등 | Stripe `Idempotency-Key`, AWS `ClientToken`, IETF Idempotency-Key draft |
| 메시지 원자성 | Transactional Outbox / Polling Publisher (Richardson, *Microservices Patterns*) |
| 큐 claim | PostgreSQL `FOR UPDATE SKIP LOCKED` (9.5+), lease/visibility timeout (SQS 계열) |
| 이중 실행 차단 | 비관적 락(`SELECT FOR UPDATE`) + 조건부 UPDATE 영향행수 판정 |
| 원장 불변 | 복식부기 역분개, event sourcing 의 append-only log |
| 재고 경합 | 조건부 UPDATE(`WHERE stock >= qty`) — 검사·차감 단일 문 |
| 테넌트 격리 | 쿼리 스코프 강제 → (후속) 복합 FK / RLS |
