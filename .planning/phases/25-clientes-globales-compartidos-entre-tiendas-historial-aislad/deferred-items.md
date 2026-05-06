# Phase 25 — Deferred Items

작업 진행 중 발견된 우리의 task scope 외 항목들을 기록.

## Plan 25-15 발견 사항

### Pre-existing test failures (Plan 15 작업과 무관)

스코프 외 — Plan 15 변경 전에도 실패:

1. **`api-ventago/src/app/sales/sales.controller.spec.ts`**
   - `GET /sales/all — storeId 기반 필터링 + 페이지네이션` 실패
   - `GET /sales/all — 필터 없이 호출 시 null 기본값` 실패
   - 원인: 2026-05-05 Phase A 에서 `boxId`/`terminalId`/`paymentSlugs` 필터가 추가되었으나 spec 미갱신.
   - 검증: `git stash` 로 Plan 15 변경 제거 후에도 동일 실패 재현 (변경 영향 없음 확인됨).
   - 권고: 별도 hotfix plan 으로 spec 동기화 (1라인 obj literal).

2. **`api-ventago/src/app/suspended-sales/suspended-sales.service.spec.ts`**
   - `update / 기존 하위 데이터 삭제 후 재생성` 등 `Branch.findAll` Sequelize 미초기화 에러 5건.
   - 원인: spec 이 NestJS DI 우회하면서 Branch model 을 mock 안 함 (테스트 인프라 이슈).
   - 검증: 동일하게 stash 검증 통과 (Plan 15 작업 무관).

### Reports services scope audit (Wave 7 원래 범위 일부)

**32 개 reports services 중 storeId scope handling 패턴 분석:**

이미 다수 서비스가 `WHERE (:storeId::int IS NULL OR s.store_id = :storeId::int)` 패턴 사용 중.
이는 Pitfall 6 위험 — `storeId=null` 일 때 raw SELECT 와 동등 (caller 의 ownerGroup 무관하게
모든 매장 합산). 그러나 운영 현황(2026-05-06):

- 운영 매장 4개 모두 `owner_group_id=1` (Phase 25 P02 마이그레이션 결과)
- 따라서 현재 운영 환경에서는 leak 가능성 0 (모든 매장이 동일 group)
- 신규 매장 추가 시 자동으로 새 group 발급 (P05 store.service nextval) → 그 시점 이후 위험 발생

**전체 서비스 일괄 수정은 Plan 15 범위 초과** — STATE.md 의 "P15-deferred" 결정 (2026-04-26) 와
일치하는 결론. Plan 15 는 sales.* 의 핵심 인프라 (`OwnerScopeService.resolveStoresForOwnerGroup`,
`SalesService.findAllScoped`, dual-FK precedence) 만 추가하고, 32 개 reports 서비스는 후속 plan
(차기 phase `26-reports-scope-audit` 또는 동등) 에서 일괄 처리 권고.

**즉시 leak 발생 매장 신규 등록 가능성 차단 가드 (당장 추가 필요한지)**:
- 현재 32 services 중 `OwnerScopeService` 통합 0건
- 단기 완화: superadmin 가 신규 매장 owner_group 분리하기 전까지 `WHERE :storeId IS NULL` fallback 의
  현재 동작이 그대로 동작 (모든 매장 합산). 이는 group=1 단일 환경에서는 정상.
- 진짜 다중 ownerGroup 환경 진입 직전에 일괄 audit 수행 필요.

### sales-create.service storeClientId 추론 비용

Plan 15 에서 `clientId → document → store_clients(via globalClient)` 추론 1쿼리 추가.
정상 hit 시 비용은 attributes 최소화 + 인덱스 사용 (`store_clients.uq_store_client` + `global_clients.document`).
slow query 발생 시 (>100ms) 캐시 검토 필요 — 현재는 캐시 없음 (per-sale 다른 (storeId, clientId)).
