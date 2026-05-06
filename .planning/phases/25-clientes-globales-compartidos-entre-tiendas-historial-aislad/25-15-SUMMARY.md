---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 15
subsystem: backend-sales-reports
tags: [backend, api-ventago, sales, reports, scope, dual-fk, pitfall-4, pitfall-6, wave-7]

requires:
  - 25-05 (OwnerScopeService base)
  - 25-06 (OwnerScope decorator + guard)
  - 25-08 (clients-merge.service spec base)
provides:
  - OwnerScopeService.resolveStoresForOwnerGroup(ownerGroupId) → number[]
  - SalesService.findAllScoped (storeId 명시 / null aggregate 분기)
  - SalesService.resolveSaleClient (Pitfall 4 dual-FK precedence)
  - SalesService.buildClientIncludes (StoreClient + GlobalClient + Clients)
  - SalesCreateService storeClientId 자동 추론 (clientId → document → SC)
  - reports/scope.helper.ts resolveStoreScope (Pitfall 6 helper)
affects:
  - 모든 신규 sales 가 storeClientId 채우면서 legacy clientId 보존 (D2-01 완성)
  - sales read 호출자가 dual-FK 양쪽 join 가능 — 정밀한 client 정보 추출
  - reports services 가 helper 채택 시 ownerGroup 경계 강제 가능

scope-decision:
  - "32 reports services 일괄 ownerGroup 변환은 Plan 25-15 범위 초과 → 후속 plan 으로 deferred"
  - "운영 매장 모두 owner_group=1 (Phase 25 P02) → 즉시 leak 0 — 신규 group 발급 직전 일괄 audit 권고"
  - "Plan 15 핵심: sales 인프라 (OwnerScopeService 확장 + findAllScoped + resolveSaleClient + storeClientId auto-fill) + reports helper sample"

key-files:
  created:
    - api-ventago/src/app/sales/sales.service.spec.ts (9 cases, all green)
    - api-ventago/src/app/reports/scope.helper.ts
    - api-ventago/src/app/reports/scope.helper.spec.ts (4 cases, all green)
    - .planning/phases/25-clientes-globales-compartidos-entre-tiendas-historial-aislad/deferred-items.md
  modified:
    - api-ventago/src/app/common/services/owner-scope.service.ts (+resolveStoresForOwnerGroup)
    - api-ventago/src/app/sales/sales.service.ts (+findAllScoped, resolveSaleClient, buildClientIncludes, OwnerScopeService 주입)
    - api-ventago/src/app/sales/sales-create.service.ts (storeClientId 자동 추론 5+ 라인)
    - api-ventago/src/app/sales/sales.module.ts (CommonModule import)

key-decisions:
  - "findAllScoped: storeId 명시 시 ownerScope 미호출 (조건부 branch — pool 절약)"
  - "Empty ownerGroup → Op.in [] 그대로 (PG 빈 IN 항상 false 평가, leak 안전)"
  - "scope.helper 의 storeIds: Empty → [-1] sentinel (Sequelize 빈배열 NULL 직렬화 회피)"
  - "resolveSaleClient: storeClient OR globalClient eager 미적재 시 legacy 폴백 (호환성 우선)"
  - "storeClientId 자동 추론: clientId → document → SC by storeId (Plan 16 ClientsSyncService 매핑 활용)"
  - "32 reports services 일괄 수정 deferred — 운영 single-group 환경에서 즉시 leak 없음 + 큰 변경 분리"
  - "Reports controllers 의 ownerGroupId 전달 변경은 deferred (모든 reports 컨트롤러 method 시그니처 수정 필요)"

requirements-completed:
  - REQ-25-04 (sales.service read precedence + scope enforcement)
  - REQ-25-07 (sales-create storeClientId dual-FK)
  - REQ-25-08 (reports helper foundation — full audit deferred)

duration: ~30min (read-research + 2 task commits + helpers)
completed: 2026-05-06
---

# Plan 25-15 (Wave 7): Sales storeClientId 정합성 + Reports storeId scope 인프라

## 변경 요약

Phase 25 Wave 7 의 핵심 인프라를 추가했다. sales read 경로는 dual-FK precedence (storeClient → globalClient, fallback clients) 로 동작하고, write 경로는 storeClientId 를 자동 채운다. reports 서비스는 32 개 라 일괄 수정 대신 helper + sample 패턴 + deferred-items 가이드를 마련했다.

## 변경된 파일

### 신규

| 파일 | 역할 |
|------|------|
| `api-ventago/src/app/sales/sales.service.spec.ts` | 9 cases — findAllScoped (4) + resolveSaleClient (4) + 옵션 (1) |
| `api-ventago/src/app/reports/scope.helper.ts` | resolveStoreScope helper (Pitfall 6) |
| `api-ventago/src/app/reports/scope.helper.spec.ts` | 4 cases — 분기/empty/falsy 검증 |
| `.planning/phases/25-.../deferred-items.md` | pre-existing test failures + reports audit 결과 |

### 수정

| 파일 | 변경 |
|------|------|
| `api-ventago/src/app/common/services/owner-scope.service.ts` | `resolveStoresForOwnerGroup(ownerGroupId)` 추가 — Store.findAll attributes ['id'] |
| `api-ventago/src/app/sales/sales.service.ts` | `findAllScoped`, `resolveSaleClient`, `buildClientIncludes` 추가; OwnerScopeService 주입; ResolvedSaleClient 타입 export |
| `api-ventago/src/app/sales/sales-create.service.ts` | sale.create() 호출에 `storeClientId` 추가; clientId → document → store_clients 룩업 추론 (~25 라인) |
| `api-ventago/src/app/sales/sales.module.ts` | CommonModule import (OwnerScopeService 사용) |

## 핵심 설계 결정

### 1. findAllScoped 분기 정책 (Pitfall 6)

```ts
if (opts.storeId) {
  storeFilter = { storeId: opts.storeId };  // single-store
} else {
  const stores = await ownerScopeService.resolveStoresForOwnerGroup(opts.ownerGroupId);
  storeFilter = { storeId: { [Op.in]: stores } };  // owner-group
}
```

- storeId 명시 시 ownerScope 미호출 → DB 한 번 절약
- storeId null + ownerGroup 매장 0 → Op.in [] (PG 항상 false, leak 안전)

### 2. resolveSaleClient — Pitfall 4 dual-FK precedence

```ts
if (sale.storeClientId && sale.storeClient?.globalClient) {
  return { type: 'global', client: sale.storeClient.globalClient };
}
if (sale.clientId && sale.client) {
  return { type: 'local', client: sale.client };
}
return null;
```

- 신규 sales 는 storeClient 경로 우선 (Phase 25 D2-01 dual-FK)
- 레거시 sales (Plan 03 이전 + Plan 16 sync 미적용) 은 clients 폴백
- eager-load 안 된 경우도 안전하게 폴백 (호출자가 별도 조회 가능)

### 3. sales-create storeClientId 자동 추론

DTO 에 storeClientId 가 명시되지 않더라도 (대부분 POS 플로우) clientId 가 있으면 자동 추론:

```
clientId → Clients.findByPk attributes:['id','document']
        → store_clients.findOne where:{ storeId } include:[GC where:{ document }]
        → resolvedStoreClientId
```

- Phase 25 Plan 16 ClientsSyncService 가 이미 매핑을 만든 경우에만 hit
- 추론 실패해도 sale 은 storeClientId NULL 로 생성 (legacy 폴백 정상 동작)
- attributes 최소화 + 인덱스 사용 → pool 절약 (CLAUDE.md 규약)

### 4. Reports services scope 일괄 변환 deferred

**근거:**
- 34 reports services 중 32개가 raw SQL `WHERE (:storeId IS NULL OR s.store_id = :storeId)` 패턴 사용
- 일괄 변환 = ~160 SQL fragment 수정 + 32 controller method 시그니처 변경
- Plan 15 의 검증 가능한 scope (sales infra + helper) 를 유지하기 위해 분리
- **운영 환경 모두 owner_group_id=1** → 현재 leak risk 0 (Phase 25 P02 마이그레이션 결과)
- 신규 매장 추가 시 자동으로 새 group 발급 (P05 store.service nextval) 직전에 일괄 audit 필요

scope.helper.ts 는 후속 plan 의 표준 진입점:
```ts
const { storeIds } = await resolveStoreScope(
  { storeId, ownerGroupId: user.ownerGroupId },
  ownerScopeService,
);
// raw SQL: WHERE s.store_id = ANY(:storeIds)
```

## 테스트 결과

### Plan 15 신규 spec (실행)

| Spec | Cases | Status |
|------|-------|--------|
| `sales.service.spec.ts` (Plan 15 신규) | 9 | ✅ 9 passed |
| `scope.helper.spec.ts` (Plan 15 신규) | 4 | ✅ 4 passed |
| `sales-create.service.spec.ts` (회귀) | ~10 | ✅ all passed |

### 빌드

`npm run build` (api-ventago) — green.

### Pre-existing 테스트 실패 (Plan 15 무관, deferred-items.md 기록)

- `sales.controller.spec.ts` 2 cases — 2026-05-05 Phase A toolbar 필터 (boxId/terminalId/paymentSlugs) spec 미갱신
- `suspended-sales.service.spec.ts` 5 cases — Branch model mock 누락 (테스트 인프라 이슈)

`git stash` 로 Plan 15 변경 제거 후에도 동일 실패 재현 → 우리 작업 영향 없음 검증.

## Manual E2E (Task 3)

**Auto mode active** (`config.json workflow._auto_chain_active=true`) → checkpoint:human-verify 자동 승인.

`⚡ Auto-approved: Phase 25 Plan 15 — sales scope enforcement + reports scope helper`

수동 verify 가 필요한 경우 plan task 3 의 `<how-to-verify>` (Step A~E) 를 참조 — 운영 매장 모두 owner_group=1 인 현재 환경에서는 cross-group leak 시뮬레이션이 즉시 불가능하므로 (manual SQL `UPDATE stores SET owner_group_id = 2 WHERE id = 9` 필요) Phase 25 next plan 또는 Phase 25 deployment 시점에 함께 수행 권고.

## Phase 25 — 22 roadmap requirements 진행 현황

Plan 15 종료 시점 — 22 개 중 다음 항목 완료:

- REQ-25-01 ~ REQ-25-03: 스키마 + 마이그레이션 (P01~P04)
- REQ-25-04: sales.service read precedence + scope (Plan 15 ✅)
- REQ-25-05: OwnerScopeService 인프라 (P05)
- REQ-25-06: OwnerScopeGuard + decorator (P06)
- REQ-25-07: sales-create dual-FK (Plan 15 ✅)
- REQ-25-08: reports helper foundation (Plan 15 ✅; 일괄 audit deferred)
- REQ-25-09: CUIT/DNI 검증 (P09)
- REQ-25-10 ~ REQ-25-12: import 백엔드 (P10~P12)
- REQ-25-13: 테스트/검증 (P13)
- REQ-25-14: import 프론트 wiring (P14)
- REQ-25-16: ClientsSync 추출 (P16 hot fix A)

**남은 작업** (Phase 25 Wave 9/10): Plan 25-17 (백필 B), Plan 25-18 (Plan 18 hook safety net C). Plan 25-15 는 sales/reports 핵심 인프라 1차 완료.

## Follow-up

- [ ] 32 reports services 일괄 ownerGroup 변환 (별도 plan, ideally before 신규 group 발급 운영 시점)
- [ ] storeTemplate Consumidor Final default client (document='00000000') 의 storeClientId 정책 결정 (P16 deferred 와 통합)
- [ ] sales.controller.spec.ts spec 동기화 (boxId/terminalId/paymentSlugs)
- [ ] suspended-sales.service.spec.ts Branch mock 추가
- [ ] Manual E2E (Task 3 Step A~E) — 다중 ownerGroup 환경 진입 직전 수행

## Self-Check: PASSED

- [x] OwnerScopeService.resolveStoresForOwnerGroup present
- [x] sales.service.findAllScoped + buildClientIncludes (StoreClient + GlobalClient + Clients)
- [x] sales.service.resolveSaleClient (Pitfall 4 dual-FK precedence)
- [x] sales-create.service storeClientId 자동 추론
- [x] sales.service.spec.ts (9/9) + scope.helper.spec.ts (4/4) all green
- [x] sales-create.service.spec.ts (회귀) all green
- [x] api-ventago `npm run build` green
- [x] reports/scope.helper.ts + spec 추가
- [x] deferred-items.md 작성 (pre-existing failures + reports audit 결과)
- [x] 2 commits in api-ventago (81e4360, ee3d845)

---
*Completed: 2026-05-06*
