# Phase 64 Validation

**Date:** 2026-07-28
**Environment:** 로컬 Mac PG18 :5432 (`ventago`, 동시성 스위트는 `ventago_test`) / 운영 srv803182 PG18 :5434
**Status:** 코드 W1~W9 완료 · **마이그레이션 3종 미적용(사용자 승인 대기)** · 브라우저 UAT 미실행

---

## 1. 마이그레이션 대조

| 파일 | 내용 | 로컬 5432 | 운영 5434 |
|---|---|---|---|
| `2026-07-27-phase64-sale-idempotency-keys.sql` | 신규 테이블 + UNIQUE + owner 이전 | ⬜ 미적용 | ⬜ 미적용 |
| `2026-07-27-phase64-outbox-lease.sql` | `sync_outbox` 컬럼 2개 + in-flight 회수 | ⬜ 미적용 | ⬜ 미적용 |
| `2026-07-27-phase64-outbox-lease-index.sql` | lease 인덱스 (CONCURRENTLY) | ⬜ 미적용 | ⬜ 미적용 |

적용 전 실측(읽기 전용, 2026-07-28):

```
로컬 5432  SELECT status, count(*) FROM sync_outbox GROUP BY status;   → 0행
운영 5434  SELECT status, count(*) FROM sync_outbox GROUP BY status;   → 0행
로컬 5432  SELECT count(*) FROM mes_work_orders;                        → 0
운영 5434  SELECT count(*) FROM mes_work_orders;                        → 0
```
→ in-flight 회수 UPDATE 의 예상 영향 행 수 = **0**. 생산 완료 소급 보정 대상 = **0**.

**적용 순서(중요): 마이그레이션 → 코드 배포.** 순서가 뒤집히면
`Idempotency-Key` 를 보내는 클라이언트의 판매가 `relation "sale_idempotency_keys" does not exist` 로 실패한다.

---

## 2. 매장 경계 위반 사전 조사 (W7 R8 선행)

차단 도입 전 필수 조사. 3개 쿼리 × 2환경.

**로컬 5432** — 3개 쿼리 모두 0행.

**운영 5434**

```
--- (1) 판매 아이템 상품이 판매 매장과 다름 ---
 sale_store | product_store | cnt
------------+---------------+-----
          6 |             3 |   6
          8 |             6 |   2
          3 |             8 |   2
(3 rows)

--- (2) 판매원이 타 매장 소속 ---   → 0행
--- (3) 터미널→box→지점이 타 매장 --- → 0행
```

상세:

| sale_store | prod_store | product | SKU | generic | items | first_sale | last_sale |
|---|---|---|---|---|---|---|---|
| 6 | 3 | CAMPERA ESTAMPADA (S) | CAMP0261013 | f | 2 | 2026-04-23 | 2026-04-30 |
| 6 | 3 | CAMPERA ESTAMPADA (M) | CAMP0261014 | f | 2 | 2026-04-23 | 2026-04-30 |
| 6 | 3 | CAMPERA ESTAMPADA (L) | CAMP0261015 | f | 2 | 2026-04-23 | 2026-04-30 |
| 3 | 8 | CAMPERA ESTAMPADA (verde/36) | 25092026002023018 | f | 1 | 2026-04-08 | 2026-04-08 |
| 8 | 6 | Producto Genérico | GEN-0001 | **t** | 2 | 2026-03-31 | 2026-04-01 |
| 3 | 8 | CAMPERA ESTAMPADA (rojo/36) | 25092026002023017 | f | 1 | 2026-03-31 | 2026-03-31 |

**판정: 차단 도입 진행.** 근거 —
1. 전부 **2026-03-31 ~ 2026-04-30** 구간. 최근 3개월(2026-05~07) 위반 **0건** → 진행 중인 업무 흐름이 아니다.
2. 상품명·SKU 가 테스트 데이터 성격(`CAMPERA ESTAMPADA`, `Producto Genérico`).
3. generic 상품 케이스(GEN-0001)는 이미 매장별 lazy 생성으로 해소됨 —
   `products.service.ts:529 findGenericProduct(storeId)` 가 매장별 `findOrCreate`.
4. 기존 10건은 **과거 데이터**이며 차단은 신규 판매에만 적용된다(소급 삭제/수정 없음).

⚠ 사용자 확인 필요 항목: 위 매장(3/6/8)이 앞으로도 타 매장 상품을 팔 계획이 있다면 이 차단은 재검토 대상이다.

---

## 3. grep 게이트

```
# stocks 대상 productId 참조 (생산/재고 모듈)
grep -n "stockModel\.\(findOne\|findAll\|create\|update\)" -A3 \
  src/app/production src/app/stocks | grep -c "productId:"     → 0 ✅

# 원장 파괴 경로
grep -c "\.destroy()" src/app/stocks/stocks.service.ts          → 0 ✅
grep -cE "stock\.update\(" src/app/stocks/stocks.service.ts     → 0 ✅

# 매장 경계 거부 메시지
grep -c "no pertenece a esta tienda" \
  src/app/sales/sales-create.service.ts                         → 2 ✅

# 조건부 차감 / 백데이트 채번
grep -c "AND stock >= \$1" src/app/sales/sales-create.service.ts → 1 ✅
grep -c "targetDate" src/app/sales/sales-create.service.ts       → 5 ✅

# outbox claim
grep -c "FOR UPDATE SKIP LOCKED" \
  src/app/integrations/core/outbox.service.ts                    → 1 ✅
grep -c "status: 'processing'" (JS 측 claim 표시)                → 0 ✅

# 유닛 CI 오염 없음
npx jest --listTests | grep -c "conc-spec"                       → 0 ✅
```

---

## 4. 빌드 / 유닛 테스트

```
api-ventago
  npx tsc --noEmit -p tsconfig.json
    → Phase 64 대상 모듈 에러 0
      (전체 2건은 기존: afip-output.service.spec.ts:37, products.controller.ts:825
       — 둘 다 본 Phase 미변경 파일, 워킹트리 사전 상태)

  npx jest (Wave 별)
    W1 sale-idempotency.service.spec.ts        7 passed
    W2 sales-nullify.service.spec.ts           7 passed
    W3 suspended-sales (2 suites)             20 passed  (기존 9/14 → 20/20)
    W4 work-order.service.spec.ts             10 passed
    W5 outbox.service.spec.ts                  9 passed
    W6 offline-push.service.spec.ts            9 passed
    W7 stocks.service.spec.ts                  7 passed
    W8 sales-stock-guard.spec.ts              10 passed
    회귀: src/app/sales + src/app/integrations  99 passed / 2 failed
      ✕ GET /sales/all — storeId 기반 필터링 + 페이지네이션
      ✕ GET /sales/all — 필터 없이 호출 시 null 기본값
      → git stash 로 HEAD 버전에서도 동일 2건 실패 확인 = **기존 결함, 본 Phase 무관**

  eslint (파일별 baseline 대조: HEAD 버전을 임시 파일로 복원해 문제 유형·개수 다중집합 비교)
    sales-create.service.ts        147 → 147  (동일)
    work-orders/                    15 → 15   (동일)
    suspended-sales/               107 → 59   (개선 — 정적 모델 모킹으로 기존 실패 해소)
    offline-push.service.ts         21 → 20   (개선)
    신규 파일 전부                    0 problems

ventago-app
  npx eslint (변경 2파일)  → 0 problems
  npx tsc --noEmit         → 1건 (기존: DataConfig.tsx @mui/icons-material/DeleteOutline 모듈 없음)
```

---

## 5. 동시성 스위트 (W9)

`npm run test:concurrency` — 실 PostgreSQL(`ventago_test`)에 병렬 발사 후 **카운트로 판정**.
반복 기본 20회(`CONCURRENCY_ROUNDS`).

실행 (2026-07-28, `CONCURRENCY_ROUNDS=20`):

```
CONCURRENCY_DATABASE_URL=postgres://marcoskim@127.0.0.1:5432/ventago_test \
  npm run test:concurrency

PASS test/concurrency/primitives.conc-spec.ts (29.361 s)
  멱등 claim — INSERT ... ON CONFLICT DO NOTHING (R1/R7)
    ✓ 동일 키 병렬 N 요청 → 삽입 성공은 정확히 1건 (87 ms)
  영업일 채번 — advisory lock (R11)
    ✓ 같은 매장·같은 날 병렬 10건 → 번호 중복 0 (51 ms)
    ✓ 과거 날짜 병렬 등록도 그 날짜 번호만 소비한다 (오늘 번호 불변) (26 ms)
  outbox claim — FOR UPDATE SKIP LOCKED + lease (R6)
    ✓ 워커 4개 동시 claim → 같은 작업을 두 번 집지 않는다 (49 ms)
    ✓ lease 만료된 processing 작업은 회수되어 다시 집힌다 (10 ms)
  재고 차감 — 설정 분기 (R10)
    ✓ 비허용 매장 — 재고 1개에 동시 5판매 → 1건만 성공, stock=0 (47 ms)
    ✓ 허용 매장 — 재고 1개에 동시 2판매 → 둘 다 성공, stock=-1 (회귀 금지) (1 ms)
  이중 실행 차단 — SELECT FOR UPDATE + 상태 재검사 (R2/R4)
    ✓ 동일 문서 병렬 취소 5요청 → 성공 1건, 역분개 1건 (136 ms)

Test Suites: 1 passed, 1 total
Tests:       8 passed, 8 total
```

| 불변식 | 대응 요구사항 | 결과 |
|---|---|---|
| 동일 키 병렬 5요청 → 삽입 성공 1건, 예외 0 | R1/R7 | ✅ (20회) |
| 같은 매장·날짜 병렬 10건 채번 → 번호 중복 0 | R11 | ✅ |
| 백데이트 병렬 5건 → 오늘 번호 불변 | R11 | ✅ |
| 워커 4개 동시 claim → 중복 집행 0 | R6 | ✅ |
| lease 만료분 회수 후 재claim 가능 | R6 | ✅ |
| 비허용 매장 재고 1개 동시 5판매 → 1건 성공, stock=0 | R10 | ✅ (20회) |
| **허용 매장 재고 1개 동시 2판매 → 2건 성공, stock=-1** | R10 (회귀 금지) | ✅ |
| 동일 문서 병렬 취소 5요청 → 성공 1, 역분개 1 | R2/R4 | ✅ (20회) |

**범위 경계(정직하게):** 이 스위트는 Phase 64 가 도입한 **SQL 수준 동시성 구성물**
(advisory lock 채번 / `FOR UPDATE SKIP LOCKED` / `ON CONFLICT DO NOTHING` /
조건부 `UPDATE ... WHERE stock >= qty` / `SELECT FOR UPDATE` + 재검사)을 실 엔진에서 검증한다.
서비스·HTTP 계층 전체를 태우는 E2E 는 아니다 — 계층 분기·트랜잭션 전파는 각 Wave 의 유닛 spec 이 고정한다.

---

## 6. 요구사항별 Acceptance

| R | 요구사항 | 코드 | 유닛 | 동시성 | 마이그 | UAT |
|---|---|---|---|---|---|---|
| R1 | 판매 멱등 + 커밋 후 500 제거 | ✅ | ✅ 7 | ✅ | ⬜ | ⬜ |
| R2 | 취소 원자화 + 이중 취소 차단 | ✅ | ✅ 7 | ✅ | — | ⬜ |
| R3 | 보류 판매 원자화 | ✅ | ✅ 20 | — | — | ⬜ |
| R4 | 생산 완료 스키마 정합 + 원자화 | ✅ | ✅ 10 | ✅ | — | ⬜ |
| R5 | outbox enqueue 원자성 | ✅ | ✅ 9 | — | ⬜ | ⬜ |
| R6 | outbox claim/lease | ✅ | ✅ 9 | ✅ | ⬜ | ⬜ |
| R7 | 오프라인 멱등 원자화 | ✅ | ✅ 9 | ✅ | — | ⬜ |
| R8 | 매장 경계 검증 | ✅ | ✅ | — | — | ⬜ |
| R9 | 재고 원장 불변 | ✅ | ✅ 7 | — | — | ⬜ |
| R10 | 재고 동시성 (설정 분기) | ✅ | ✅ 10 | ✅ | — | ⬜ |
| R11 | 백데이트 채번 | ✅ | ✅ | ✅ | — | ⬜ |
| R12 | 공개몰 pool 예산 | ✅ | — | — | — | ⬜ |

---

## 7. 배포 후 관측 (2주)

| 지표 | 조회 | 기대 |
|---|---|---|
| 판매 500율 | API 로그 `POST /sales` 5xx 비율 | 배포 전 이하 |
| 멱등 재생 | `SELECT status, count(*) FROM sale_idempotency_keys GROUP BY status` | `completed` 누적, 재시도가 판매를 만들지 않음 |
| ledger 보정 대상 | 로그 `event:"sale_ledger_failed"` 건수 | 0 (발생 시 수동 보정) |
| outbox 상태 | `SELECT status, count(*) FROM sync_outbox GROUP BY status` | `failed` 급증 없음 |
| outbox 정체 | `SELECT count(*) FROM sync_outbox WHERE status='processing' AND lease_expires_at < NOW()` | 지속 0 |
| 음수 재고(비허용 매장) | `SELECT p.id FROM products p JOIN store_configs c ON c.store_id=p.store_id WHERE c.allow_sale_without_stock=false AND p.stock<0` | 0건 |
| 번호 중복 | `GROUP BY store_id, sale_day_local, daily_number HAVING count(*)>1` | 0행 |
| pool 경고 | API 로그 `pool` 80% 경고 / 기동 로그 `커넥션 예산` | 배포 전 이하 |

---

## 8. 이번 Phase 범위 밖에서 발견·처리한 것

1. **`ventago-app/ProductList.tsx` 워킹트리 미커밋 코드가 컴파일 불가 상태**였다 —
   보류판매 갱신 분기(`if (suspendedSaleId) PUT else POST`)를 추가하면서 `suspendedSaleId` 를
   `useSaleProducts()` destructure 에 넣지 않아 `TS2304` 5건으로 프런트 빌드가 통째로 실패.
   `SaleProductsContext.tsx:44/467` 이 이미 노출하므로 destructure 에 이름만 추가해 해소(1단어).
2. **`suspended-sales.service.spec.ts` 가 HEAD 에서 이미 5건 실패**(정적 모델 미모킹)였다 —
   W3 작업 중 `Branch/Product/ProductBranch/Stocks` 모킹을 추가해 20/20 통과로 정상화.
3. **`sales.controller.spec.ts` GET /sales/all 2건 실패는 기존 결함** — `findAll` 인자 불일치.
   본 Phase 무관이며 손대지 않았다(별도 과제).
