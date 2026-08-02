---
phase: 69-tenant-isolation-security-hardening
plan: 11
subsystem: api
tags: [nestjs, sequelize, multi-tenant, derived-scope, crud]

# Dependency graph
requires:
  - phase: 69-06
    provides: "파생 스코프 규칙 40개 + 다중 부모 — 미결 6종을 식별한 감사"
  - phase: 69-07
    provides: "TENANT_DERIVED_MODE 기본값 enforce — 등록이 곧 강제가 되는 상태"
provides:
  - "DerivedScopeRule.allowGlobalRows — 전역 행을 갖는 부모를 union 으로 처리"
  - "DerivedScopeRule.anyOf — 배타적 OR 부모(2단계 경로 포함) 지원"
  - "미결 6종 전부 파생 등록 — 파생 대상 39 → 45, 사각지대 제외 30 → 24"
  - "assertDerivedParentsInScope — 파생 모델의 쓰기 소유권 검증"
  - "CrudService × store_id 부재 모델 결함 수정 (findAll 500 / findOne 상시 403)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "부모가 전역 행을 갖는 파생 모델에 INNER JOIN 을 그냥 걸면 권한이 사라진다 — union 이 필요하다"
    - "Sequelize 는 2단계 이상 `$a.b.c$` 경로에서 attribute→column 매핑을 하지 않는다 — 물리 컬럼명을 써야 한다"
    - "OR 조건 분기는 required:false 로 붙여야 한다. where 를 걸면 Sequelize 가 INNER JOIN 으로 승격시켜 한쪽만 채운 정상 행이 사라진다"
    - "store_id 가 없는 모델에 where.storeId 를 거는 코드는 조용히 깨진 게 아니라 500 을 내며 깨져 있었다"

key-files:
  created: []
  modified:
    - api-ventago/src/common/tenant/tenant-scope.registry.ts
    - api-ventago/src/common/tenant/tenant-hooks.ts
    - api-ventago/src/common/crud/crud.service.ts
    - api-ventago/src/app/print/qr-print-log.model.ts
    - api-ventago/test/tenant/cross-tenant.tenant-spec.ts
    - api-ventago/check-derived-assoc.js
---

# 69-11 — 파생 스코프 미결 6종 봉쇄 + CrudService 결함 수정

## 왜 지금 했나

69-06 감사가 남긴 미결 6종(`QrPrintLog`/`UserRole`/`RoleFunctionAction`/`PaymentMethodsOption`/
`SubconSettlement`/`SubconPayment`)은 처음에 "별도 phase 로 defer" 로 결정됐다. 사용자가
**"문제가 발생하면 고치자는 것은 안 맞다"** 로 뒤집어, 이 플랜에서 엔진까지 보강해 전부 닫았다.

defer 판단의 근거였던 사실은 그대로다 — 당시 코드 경로에는 교차 매장 읽기·쓰기 통로가 없었다.
다만 **방어선이 없다**는 것과 **미등록이라 observe 로그조차 남지 않는다**는 것이 남은 위험이었다.

## 엔진 보강 — 왜 종전 규칙으로는 등록할 수 없었나

| 문제 | 종전 동작 | 보강 |
|---|---|---|
| 부모가 전역 행(store_id NULL)을 정당하게 가짐 | `buildDerivedInclude` 가 `allowGlobalRows:false` 하드코딩 → INNER JOIN 이 전역 부모를 잘라냄 | `DerivedScopeRule.allowGlobalRows` — 부모 조건을 `store_id IN (...) OR IS NULL` 로 union |
| 부모 FK 가 둘 다 nullable + 상호배타(OR) | AND-of-부모만 표현 가능 → 한쪽 고르면 다른 쪽만 채운 정상 행이 사라짐 | `DerivedScopeRule.anyOf` — 분기를 **LEFT JOIN**(where 없음)으로 붙이고 루트 where 에 `$경로.store_id$` OR |
| 2단계 위가 OR (`SubconPayment`) | through 는 leaf where 만 지원 | `through` 안에 `anyOf` 허용, 경로를 누적해 `$subconSettlement.subconOrder.store_id$` 생성 |
| `QrPrintLog` 에 association 없음 | 훅이 붙을 자리가 없음 | 모델에 `@ForeignKey/@BelongsTo(Branch)` 추가 (DDL 아님, 조회는 여전히 in-memory 조인) |

구현에서 실제로 물린 함정 두 개:

1. **`$a.b.storeId$` 는 매핑되지 않는다.** Sequelize 는 2단계 이상 경로에서 attribute→column 변환을 하지 않아
   `column "storeId" does not exist` 로 죽었다. 부모 모델의 `rawAttributes.storeId.field` 를 읽어 **물리 컬럼명**을 쓴다.
2. **`limit` 이 있으면 subQuery 가 켜져** JOIN 별칭이 서브쿼리 밖에서 안 보인다. 분기는 전부 belongsTo(N:1)라
   행이 늘지 않으므로 `subQuery:false` 로 고정한다.

## 쓰기 경로

파생 훅은 `beforeFind`/`beforeCount` 만 덮는다. store_id 가 없으면 스탬프할 컬럼도 없어
`beforeCreate` 가 막을 방법이 없다 — 타 매장 부모 FK 를 그대로 넣으면 들어간다.
`assertDerivedParentsInScope(model, data)` 가 **부모를 실제로 조회**한다. 부모는 guarded(또는 자기도 파생 등록)
모델이라 조회 자체에 격리가 걸려 있어 타 매장이면 `null` 이 돌아온다. `anyOf` 는 분기 하나만 통과하면 되고,
분기 FK 가 전부 비어 있으면 귀속 불가 행이므로 차단한다.

## CrudService — 깨진 채 굴러가던 코드

`CrudService` 를 쓰는 38개 모델 중 **11개에 `store_id` 컬럼이 없다**(Price/Stocks/Movements/Subcon* 등).
그런데 구현은 컬럼이 있다고 가정했다:

- `findAll` → `where: { storeId }` → `column store_id does not exist` 로 **500**
- `findOne` → `record.storeId === undefined` 라 `undefined !== scope.storeId` → **자기 매장 행도 항상 403**

즉 보호가 아니라 고장이었다(프론트가 해당 라우트를 안 써서 표면화되지 않았을 뿐).
이제 storeId 컬럼이 없으면 파생 스코프(부모 JOIN)에 위임하고, **스코프를 특정할 수단이 전혀 없는 모델은
fail-closed 로 차단**한다. 매장 개념 자체가 없는 전역 참조(`Province`/`Nation`)만 `TENANT_FREE_MODELS` 예외다.

## 검증

| 검증 | 결과 |
|---|---|
| `npm run test:tenant` | **31/31** (R6 파생 엔진 7종 + R7 CrudService 5종 신규) |
| `npx jest src/common` | 40/40 |
| `npx jest src/app/print` | 29/29 |
| `check-derived-assoc.js` | 57개 규칙(분기 포함) 전부 association 해석 — 사문 `BranchPrinterConfig` 제외 |
| 로컬 실 DB 쿼리 | 6종 전부 SQL 생성·실행 OK. 격리 실증: `RoleFunctionAction` 전체 11,952 → store9 72 / store6 3,588 |
| `nest build` + `node dist/main.js` | 부팅 OK — `derivedMode=enforce 대상=45` (39 → 45), 제외 30 → 24 |

### 운영 데이터 대조 — 사라지는 정상 행 0

read-only SQL 로 "새 필터가 정상 행을 숨기는가" 를 먼저 확인하고 배포했다.

| 항목 | 결과 |
|---|---|
| `user_roles` — 사용자 매장과 역할 매장이 다른 행 | **0건** |
| `role_function_actions` — 부모 store 불일치 / 고아 | **0건 / 0건**, 전역 부모 96건은 `allowGlobalRows` 로 유지 |
| store9 가시성 | 소유 4,404 + 전역 96 = **4,500** (손실 없음) |
| `payment_methods_options` | 9행 **전부** 부모가 전역 → union 없으면 전멸했을 자리. 유지 확인 |
| `qr_print_log` | 4행, 고아 0. store9 가시 0 = 타 매장 지점 소유 → 격리 정상 |
| `talleres_settlements` / `talleres_payments` | 운영 0행 |

## 알려진 사항 (pre-existing, 이번 변경과 무관)

`git stash` 로 변경분을 빼고 동일하게 재현되는 실패:

- `src/app/role/role-function/role-function.service.spec.ts` — `bulkUpdateRoleFunctionActions` 4건
- `src/app/users/user-function/user-function.service.spec.ts` — `updateUserFunctionActions` 1건

## Commits

- `6819f44` (api-ventago) — fix(security): 파생 스코프 미결 6종 봉쇄 + CrudService storeId 부재 결함 수정 (69-11)
