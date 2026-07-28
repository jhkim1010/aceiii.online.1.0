# Phase 64 Plan 01 — 판매 요청 멱등키 + 커밋 후 500 제거 · SUMMARY

**Executed:** 2026-07-28
**Requirements:** R1
**Status:** 코드 완료 · 마이그레이션 미적용(사용자 승인 대기)

## 변경 파일

| 파일 | 내용 |
|---|---|
| `api-ventago/migrations/2026-07-27-phase64-sale-idempotency-keys.sql` | 신규 — `sale_idempotency_keys` 테이블 + `uq_sale_idem_store_key` + owner/시퀀스 이전 DO 블록 |
| `api-ventago/src/app/sales/sale-idempotency.model.ts` | 신규 — 모델 |
| `api-ventago/src/app/sales/sale-idempotency.service.ts` | 신규 — `claim`(ON CONFLICT DO NOTHING) / `complete` / `markFailed` / `purgeExpired` / `hashRequest` |
| `api-ventago/src/app/sales/sale-idempotency.service.spec.ts` | 신규 — 7 케이스 |
| `api-ventago/src/app/sales/sales.module.ts` | 모델/서비스 등록 + export |
| `api-ventago/src/app/sales/sales.controller.ts` | `@Headers('idempotency-key')` 선택 수신 |
| `api-ventago/src/app/sales/sales-create.service.ts` | claim 배선 + 멱등 재생 + 커밋 후 단계 비치명 격리 |
| `api-ventago/src/app/sales/sales.controller.spec.ts` | create 호출 인자 2개로 갱신(3 케이스) |
| `ventago-app/src/services/api.service.ts` | `post()` 선택 3번째 인자(config) |
| `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` | 멱등키 ref 발급/유지/폐기 + 헤더 전송 |

## 동작

- **claim 위치**: 판매 트랜잭션 내부, `SET LOCAL lock_timeout` 직후. 판매와 커밋/롤백 운명을 공유한다 → "판매는 있는데 키가 없다" 불가능. 롤백 시 키 행도 사라져 같은 키 재시도가 자연히 허용된다.
- **4분기**: `proceed`(최초) / `replay`(완료된 키 → 저장 응답 재생, 트랜잭션 롤백) / `in_flight`(409) / `conflict`(같은 키 다른 본문 → 422). 만료(24h) 행은 재사용해 `proceed`.
- **커밋 후 격리**: `attachCreditLedgerForSale` → try/catch + `sale_ledger_failed` 구조화 로그. `sendToprinters` → try/catch warn. 최종 `findOne` 실패 → 축약 응답(커밋된 sale 객체) 반환, throw 없음.
- **하위 호환**: 헤더 미전송이면 claim 자체를 건너뛰어 현행과 동일 경로.

## 검증 결과

```
# api-ventago
npx tsc --noEmit -p tsconfig.json      → app/sales 에러 0건
                                          (전체 2건은 기존: afip-output.service.spec.ts:37, products.controller.ts:825)
npx eslint sale-idempotency.{model,service,service.spec}.ts → 0 problems
npx jest src/app/sales/sale-idempotency  → 7 passed
npx jest src/app/sales/sales.controller.spec.ts → 18 passed / 2 failed

# 2건 실패가 기존 것임을 stash 로 확정
git stash push -- (4개 sales 파일) && jest sales.controller.spec → 동일하게 18 passed / 2 failed
  ✕ GET /sales/all — storeId 기반 필터링 + 페이지네이션
  ✕ GET /sales/all — 필터 없이 호출 시 null 기본값
  (findAll 인자 불일치 — 본 Plan 과 무관)

# sales-create.service.ts lint 회귀 검사 (HEAD 버전을 임시 파일로 복원해 비교)
문제 유형·개수 다중집합 완전 일치 → LINT_PARITY_OK

# ventago-app
npx eslint api.service.ts ProductList.tsx → 0 problems
npx tsc --noEmit                          → 1건 (기존: DataConfig.tsx @mui/icons-material/DeleteOutline 모듈 없음)
```

## 이번 Plan 범위 밖에서 발견·수정한 것

`ventago-app/src/views/homes/components/ProductList/ProductList.tsx` 워킹트리에 **미커밋 상태로 깨진 코드**가 있었다 — 보류판매 갱신 분기(`if (suspendedSaleId) PUT else POST`)를 추가하면서 `suspendedSaleId` 를 `useSaleProducts()` destructure 에 넣지 않아 `TS2304: Cannot find name` 5건으로 **프런트 빌드가 통째로 실패**하는 상태였다. `SaleProductsContext.tsx:44/467` 이 이미 노출하고 있으므로 destructure 에 이름만 추가해 해소했다(1단어). 본 Plan 과 무관하나 검증을 막아 최소 수정.

## 남은 작업 (blocking)

- [ ] **Task 2 — 마이그레이션 적용**: 로컬 5432 + 운영 5434. DDL 이므로 사용자 승인 필요.
  ```
  psql -p 5432 -d ventago -v ON_ERROR_STOP=1 --single-transaction \
    -f api-ventago/migrations/2026-07-27-phase64-sale-idempotency-keys.sql
  ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction" \
    < api-ventago/migrations/2026-07-27-phase64-sale-idempotency-keys.sql
  ```
  예상 영향: 신규 테이블 1개, 기존 데이터 변경 0행.
- [ ] mobile-sales-app 헤더 송신 — 현재 앱은 `POST /mobile/sales`(보류 생성) 경로라 판매 생성 직접 호출 없음. 64-06(오프라인)에서 `offline:{uuid}` 키로 커버되므로 별도 작업 불필요함을 확인.
- [ ] 만료 키 정리(`purgeExpired`) 스케줄 연결 — 기존 cron 태스크에 얹기(신규 스케줄러 금지). 64-10 에서 처리.

## 배포 주의

마이그레이션이 **코드 배포보다 먼저** 적용돼야 한다. 순서가 뒤집히면 `Idempotency-Key` 를 보내는 클라이언트의 판매가 `relation "sale_idempotency_keys" does not exist` 로 실패한다(헤더 미전송 요청은 무영향).
