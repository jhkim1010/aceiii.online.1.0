---
phase: 69-tenant-isolation-security-hardening
plan: 06
subsystem: api
tags: [nestjs, sequelize, multi-tenant, security]

# Dependency graph
requires:
  - phase: 68-derived-scope-observe
    provides: "ProductBranch/Stocks/Price 3개를 파생 스코프 대상으로 등록(observe 모드) + DerivedScopeRule 단건 계약"
  - phase: 69-03
    provides: "correct-today 호출부 자체 소유권 검증 — 파생 enforce 가 이 위에 안전하게 얹힘"
provides:
  - "DERIVED_SCOPE 다중 부모 지원(DerivedScopeRule[]) — ProductBranch 를 product+branch 양쪽 필수 검증으로 강화"
  - "store_id 미보유 모델 63개 전수 분류 감사 문서(D 40/G 14/X 3/미결 6, 근거 파일:라인 포함)"
  - "새 D 모델 37개 DERIVED_SCOPE 등록(observe 로그 대상 확장, 이 플랜에서 실제 차단은 없음)"
  - "파생 스코프 주입 단위 테스트 7종(다중부모/기존include재사용/2단계/observe·off/컨텍스트없음/bypass)"
affects: [69-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DerivedScopeRule 배열로 다중 부모(AND) 표현 — injectDerived 가 규칙마다 applyDerivedInclude 반복 호출"
    - "GLOBAL_ROW_TABLES 멤버(payment_methods/roles/role_functions)가 유일한 부모인 모델은 buildDerivedInclude 의 allowGlobalRows:false 하드코딩과 충돌해 등록 제외 → 미결로 문서화"
    - "OR-of-nullable-parents(SubconSettlement) 는 현재 AND-only 규칙 엔진으로 표현 불가 → 미결로 문서화, 억지로 단일부모 강제하지 않음"

key-files:
  created:
    - .planning/phases/69-tenant-isolation-security-hardening/69-DERIVED-MODEL-AUDIT.md
    - api-ventago/src/common/tenant/tenant-derived.spec.ts
  modified:
    - api-ventago/src/common/tenant/tenant-scope.registry.ts
    - api-ventago/src/common/tenant/tenant-hooks.ts

key-decisions:
  - "PLAN 이 제시한 일부 association alias 는 실제 모델 파일과 달라 코드 근거로 교정함(BoxOperation→cashRegister, MpMovement/MpRefund/MpRefundAttempt→sale, OnlineOrderItem/OnlineReturn→order, SharedFolderRoleAccess→folder, ProductsCategories→subcategory). PLAN 자체가 '모델 파일에서 확인' 을 명시적으로 요구했으므로 이는 지시 위반이 아니라 그 지시의 이행."
  - "PLAN 의 '반드시 D 로 분류' 목록 중 SubconSettlement/SubconPayment 는 감사 중 subconOrderId/vendorId 가 둘 다 nullable+상호배타(OR) 관계임을 확인해 미결로 재분류함. AND-only 다중부모 엔진으로 OR 를 억지로 표현하면(한쪽을 required 로 고르면) 다른 한쪽만 채워진 정상 행이 미래 enforce 전환 시 사라지는 새로운 버그를 만든다 — PLAN 이 이미 열어둔 미결 탈출구(3단계 이상 모델과 동일한 성격의 엔진 한계)를 그대로 적용."
  - "PaymentMethod/Role/RoleFunction 이 유일한 부모인 3개 모델(PaymentMethodsOption/UserRole/RoleFunctionAction) 도 미결로 분류함 — 이 세 부모 모델은 GLOBAL_ROW_TABLES 멤버라 storeId NULL 인 전역 행이 실측 존재하는데, buildDerivedInclude(tenant-hooks.ts:189-194) 가 allowGlobalRows:false 를 하드코딩해 필수 INNER JOIN 을 걸면 전역 행에 연결된 자식 행이 enforce 시 통째로 사라진다. 감사문서에 근본원인과 69-07 이전 보강 필요사항을 명시."
  - "PaymentMethodsDiscount/SalePaymentMethod/SharedFolderRoleAccess 는 위와 같은 이유로 paymentMethod/role 쪽 부모만 제외하고 나머지 안전한 부모(discount/sale/folder) 로 단일 등록 — 모델 자체를 미결로 두지 않고 부분 등록으로 최대한 관측 범위를 확보함."

requirements-completed: [R4]

# Metrics
duration: ~2h
completed: 2026-08-01
---

# Phase 69 Plan 06: 파생 스코프 다중 부모 지원 + 63개 모델 전수 감사(R4/WR-01) Summary

**`DERIVED_SCOPE` 를 단건→배열(다중 부모) 계약으로 바꿔 `ProductBranch` 를 product+branch 양쪽 필수 검증으로 강화하고, `store_id` 미보유 모델 63개를 FK 그래프 근거로 전수 분류해 37개를 신규 파생 스코프 대상으로 등록(observe 유지)**

## Performance

- **Duration:** ~2시간
- **Completed:** 2026-08-01
- **Tasks:** 3/3
- **Files modified:** 4 (레지스트리 1, 훅 1, 신규 스펙 1, 신규 감사문서 1)

## Accomplishments

- `store_id` 컬럼이 없는 모델 **63개** 전수를 실제 소스(`@ForeignKey`/`@BelongsTo` 선언, nullability, 부모의 `storeId` 보유 여부)로 근거를 남겨 D(40)/G(14)/X(3)/미결(6) 4버킷으로 분류하고 `69-DERIVED-MODEL-AUDIT.md` 로 고정
- `DerivedScopeRule` 을 단건에서 배열로 바꿔 다중 부모(AND) 를 지원하도록 `tenant-scope.registry.ts`/`tenant-hooks.ts` 를 확장 — `injectDerived` 가 규칙 배열을 순회하며 각각 `applyDerivedInclude` 호출
- `ProductBranch` 를 `product` 단독 검증에서 **product+branch 양쪽 필수** 검증으로 강화(R2/CR-02 가 증명한 공격면 — product 만 보면 자기 매장 상품 + 타 매장 지점 조합이 통과함)
- `DERIVED_SCOPE` 를 3개(기존) → **40개** 로 확장 — 신규 37개는 observe 모드에서 이 플랜 배포 직후부터 처음으로 로그를 남기기 시작함(실제 차단은 69-07 에서 `enforce` 로 전환할 때까지 없음)
- 파생 스코프 주입 규약을 고정하는 단위 테스트 7종(`tenant-derived.spec.ts`) 신규 작성 — 다중부모 동시 검증, 기존 include 재사용 시 중복 push 없는 승격, Stocks 2단계 through, observe/off 모드 무변경, 컨텍스트 미해석·bypass 무영향
- 감사 과정에서 **PLAN 이 명시하지 않은 신규 위험**을 발견해 문서화: `PaymentMethod`/`Role`/`RoleFunction` 이 `GLOBAL_ROW_TABLES` 멤버(storeId NULL 전역 행 실측 존재)인데 `buildDerivedInclude` 가 `allowGlobalRows:false` 를 하드코딩해, 이 부모만 가진 3개 모델(UserRole/RoleFunctionAction/PaymentMethodsOption)을 그대로 등록하면 69-07 enforce 전환 시 전역 역할/전역 결제수단에 연결된 정상 행이 사라진다 — 등록하지 않고 미결로 남김

## Task Commits

1. **Task 1: store_id 미보유 모델 전수 분류 감사** - `9c0d5e2` (docs, 루트 레포)
2. **Task 2: 다중 부모 지원 + ProductBranch 양쪽 소유권 + 레지스트리 확장** - `06f0392` (feat, api-ventago)
3. **Task 3: 파생 스코프 주입 단위 테스트** - `72b7af7` (test, api-ventago)

**Plan metadata:** 이 SUMMARY 커밋 — 루트 레포에서 별도 커밋 예정

## Files Created/Modified

- `.planning/phases/69-tenant-isolation-security-hardening/69-DERIVED-MODEL-AUDIT.md` — 63개 모델 D/G/X/미결 분류 + 근거 파일:라인 + 69-07 선행과제 요약
- `api-ventago/src/common/tenant/tenant-scope.registry.ts` — `DerivedScopeRule[]` 로 시그니처 변경, `DERIVED_SCOPE` 40개 항목(신규 37 + 기존 3), `resolveDerivedScope` 배열 반환
- `api-ventago/src/common/tenant/tenant-hooks.ts` — `installDerivedForModel`/`injectDerived` 가 규칙 배열을 `for (const rule of rules)` 로 순회, observe 로그는 모델 단위 1회 유지
- `api-ventago/src/common/tenant/tenant-derived.spec.ts` — 신규, 파생 스코프 주입 규약 7케이스

## Decisions Made

프론트매터 `key-decisions` 참조. 핵심 3가지:
1. PLAN 이 제시한 일부 association alias 표기(예: `BoxOperation(box)`, `MpMovement 등(mpAccount)`)는 실제 모델 파일과 달라, PLAN 자체가 요구한 "association alias 는 모델 파일에서 확인" 원칙에 따라 실제 프로퍼티명으로 교정했다(상세는 감사문서 D 표 "비고" 열).
2. PLAN 의 "반드시 D" 목록에 있던 `SubconSettlement`/`SubconPayment` 를 감사 중 발견한 OR-of-nullable-parents 구조(현재 엔진이 표현 불가) 때문에 미결로 재분류했다 — PLAN 이미 열어둔 미결 절차를 그대로 적용한 것이며, 억지로 단일부모를 강제했다면 정상 행을 지우는 새 버그를 만들었을 것이다.
3. `payment_methods`/`roles`/`role_functions` 가 `GLOBAL_ROW_TABLES` 멤버라는 사실이 파생 스코프의 `allowGlobalRows:false` 하드코딩과 충돌하는 것을 감사 중 새로 발견해, 해당 부모만 가진 3개 모델을 등록에서 제외하고 부분적으로 안전한 대체 부모가 있는 모델(PaymentMethodsDiscount 등)은 그 부모만으로 축소 등록했다.

## Deviations from Plan

### PLAN 명시와 다르게 처리한 항목 (Rule 4 아님 — PLAN 이 열어둔 미결/근거우선 원칙 적용)

**1. [PLAN 정정] Association alias 6건을 모델 소스 근거로 교정**
- **Found during:** Task 1 (전수 감사)
- **Issue:** PLAN 본문의 `<action>` 예시가 `BoxOperation(box)`, `MpMovement/MpRefund/MpRefundAttempt(mpAccount)`, `OnlineOrderItem/OnlineReturn` 을 클래스명 그대로, `ProductsCategories(product)` 등으로 표기했으나 실제 모델 파일엔 해당 alias 가 없거나 다른 이름이었다
- **Fix:** 각 모델 파일의 `@BelongsTo` 프로퍼티명을 직접 확인해 `cashRegister`/`sale`/`order`/`folder`/`subcategory` 로 등록. PLAN 스스로 "association alias 는 모델 파일에서 확인" 을 명시했으므로 이는 PLAN 이행이지 위반이 아님
- **Files modified:** tenant-scope.registry.ts
- **Committed in:** 06f0392

**2. [PLAN 미결 절차 적용] SubconSettlement/SubconPayment 를 D 에서 미결로 재분류**
- **Found during:** Task 1 (전수 감사)
- **Issue:** PLAN 은 이 둘을 "반드시 D" 로 지정했으나, `subcon-settlement.model.ts:49` 주석("vendor 기반 정산은 subconOrderId 없음")과 코드로 `subconOrderId`/`vendorId` 가 둘 다 nullable+상호배타임을 확인. 현재 엔진(AND-of-required-parents, 단일 through)은 OR 를 표현할 수 없다
- **Fix:** D 대신 미결로 분류하고 근본원인·대안(엔진에 `anyOf` 추가 또는 파생 컬럼 검토)을 감사문서에 남김. `DERIVED_SCOPE` 에 등록하지 않음(기존과 동일하게 관측 없음 — 회귀 아님, 새 보호를 추가하지 않은 것뿐)
- **Files modified:** 69-DERIVED-MODEL-AUDIT.md
- **Committed in:** 9c0d5e2

**3. [Rule 1류 - 잠재 버그 회피] PaymentMethod/Role/RoleFunction 유일부모 3모델을 미결로, 관련 3모델은 부분 등록**
- **Found during:** Task 2 (레지스트리 확장)
- **Issue:** `payment_methods`(NULL 13행)·`roles`(NULL 4행)·`role_functions`(NULL 24행) 이 `GLOBAL_ROW_TABLES` 멤버(tenant-scope.registry.ts:20-23, 운영 실측)인데 `buildDerivedInclude` 는 부모 where 에 `allowGlobalRows:false` 를 하드코딩(tenant-hooks.ts:189-194). 이 부모만 가진 `PaymentMethodsOption`/`UserRole`/`RoleFunctionAction` 을 그대로 등록하면 69-07 enforce 전환 즉시 전역 결제수단/전역 역할에 연결된 정상 행이 INNER JOIN 에서 걸러진다(회귀)
- **Fix:** 이 3개는 미결로 분류해 등록하지 않음. `PaymentMethodsDiscount`/`SalePaymentMethod`/`SharedFolderRoleAccess` 는 같은 문제의 부모(paymentMethod/role)만 제외하고 안전한 나머지 부모(discount/sale/folder)로 축소 등록
- **Files modified:** tenant-scope.registry.ts, 69-DERIVED-MODEL-AUDIT.md
- **Committed in:** 06f0392, 9c0d5e2

---

**Total deviations:** 3 (표기 교정 1건, PLAN 미결절차 적용 1건, 신규 발견 회귀위험 회피 1건)
**Impact on plan:** PLAN 의 `must_haves`/`acceptance_criteria` 전부 충족(아래 검증 근거 참조). 미결로 남긴 6개는 감사문서에 근본원인과 69-07 이전 필요 작업을 구체적으로 남겨, 다음 플랜이 다시 조사할 필요가 없도록 했다.

## Issues Encountered

None beyond the deviations documented above — 계획된 범위 내에서 전부 해결됨.

## Verification Evidence

### 1. `npx tsc --noEmit -p tsconfig.json` — baseline 16건 유지, 신규 에러 0건

```
$ npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"
16
```
16건 전부 69-03 SUMMARY 가 이미 기록한 pre-existing 실패(afip-output/sales.controller/suspended-sales 스펙, TS2554) — 이 플랜이 건드리지 않은 파일들.

### 2. `npx jest src/common/tenant` — 신규 7종 포함 13/13 통과

```
$ npx jest src/common/tenant
PASS src/common/tenant/tenant-hooks.spec.ts
PASS src/common/tenant/tenant-derived.spec.ts
Tests: 13 passed, 13 total
```
기존 `tenant-hooks.spec.ts` destroy 규약 6종 + 신규 `tenant-derived.spec.ts` 7종(케이스 1~7) 전부 통과. `resolveDerivedScope` 시그니처 변경(배열)에 따른 컴파일 오류는 없었음(`tenant-hooks.spec.ts` 는 해당 API 를 직접 참조하지 않아 수정 불필요).

### 3. `npx jest src/common/socket src/app/products/productStock.service.spec.ts` — 69-01/69-03 무회귀

```
$ npx jest src/common/socket
Tests: 24 passed, 24 total   ← 69-01 (websocket) 전부 통과

$ npx jest src/app/products/productStock.service.spec.ts
Tests: 14 failed, 36 passed  ← 14건은 69-03 SUMMARY 가 이미 기록한 createVariantsBatch pre-existing 실패(이 플랜 이전부터 존재, 무관 메서드)
```
실패 개수(14)가 69-03 SUMMARY 의 기록과 정확히 일치 — 이 플랜이 새로 깨뜨린 테스트 없음.

### 4. `npx eslint` — 수정 파일 신규 에러 0건(같은 파일, 같은 에러 개수)

```
git stash 로 이 플랜 변경분 제외 후:
  tenant-scope.registry.ts: 12 problems (12 errors, 0 warnings)
  tenant-hooks.ts:          90 problems (86 errors, 4 warnings)
변경분 적용 후(동일 파일):
  tenant-scope.registry.ts: 12 problems (12 errors, 0 warnings)  ← 무변화
  tenant-hooks.ts:          90 problems (86 errors, 4 warnings)  ← 무변화
신규 파일:
  tenant-derived.spec.ts:   0 problems
```
기존 `no-unsafe-*` 계열(테스트 스텁의 `any` 사용 — 69-03 SUMMARY 도 동일 패턴 확인) 외 신규 위반 없음. `nest build` 는 eslint 를 실행하지 않아 배포 빌드에 영향 없음(CLAUDE.md 의 ESLint 강제는 프론트엔드 대상).

### 5. Acceptance criteria 개별 확인

```
$ grep -n "DerivedScopeRule\[\]" tenant-scope.registry.ts        → 3건 (선언부 포함)
$ grep -n "parentModel: 'Product'" ...ProductBranch 항목          → 있음
$ grep -n "parentModel: 'Branch'"  ...ProductBranch 항목          → 있음
$ DERIVED_SCOPE 항목 수                                            → 40 (감사문서 D 버킷 합계와 일치)
$ grep -n "for (const rule" tenant-hooks.ts                       → 1건 (injectDerived 내부)
$ grep -n "?? 'observe'" tenant-scope.registry.ts                 → 1건 (resolveDerivedMode 기본값 무변경)
$ 감사문서 D(40)+G(14)+X(3)+미결(6) = 63                            → 재현 명령 결과(63)와 일치
$ 감사문서 D 표 내 "아마도/추정/아마" 발생                          → 0회(문서 상단 메타 설명 문장 1건은 D 표 밖)
```

## User Setup Required

None - no external service configuration required. DDL 없음(계획서 명시) — 마이그레이션 불필요.

## Next Phase Readiness (69-07 이 반드시 처리해야 할 것)

- **enforce 전환 전 미결 6개 재검토 필수:**
  - `QrPrintLog` — 모델에 `@BelongsTo(() => Branch)` 추가 후 재분류
  - `UserRole`/`RoleFunctionAction`/`PaymentMethodsOption` — `DerivedScopeRule` 에 `allowGlobalRows` 필드를 추가해 `buildDerivedInclude` 가 부모의 전역 행을 union 하도록 엔진 자체를 보강해야 안전하게 등록 가능
  - `SubconSettlement`/`SubconPayment` — OR-of-parents 표현 방법(엔진에 `anyOf` 추가 vs 파생 컬럼) 논의 필요
- **observe 로그 수집 필요:** 신규 37개 모델이 이 플랜 배포 후 처음 로그를 남기기 시작한다. 로그 키 형태는 `${modelName}:derived:${callerHint()}`(60초 스로틀). 69-07 은 배포 후 최소 1영업일 이상 이 로그를 모아 실제 호출부를 특정해야 한다.
- **글로벌 행 caveat 재확인:** `user` 를 부모로 쓰는 5개 모델(`ClientAccessAudit`/`MobileSession`/`Movements`/`UserBranch`/`UserPermissionCache`)은 `users` 가 GLOBAL_ROW_TABLES 멤버(superadmin NULL 1행)라는 낮은 확률의 잠재 위험이 있다 — enforce 직후 "예상 밖 필터링" 로그가 없는지 별도 확인 권장(감사문서 D 표 캐비어트 참조).
- `TENANT_DERIVED_MODE` 기본값은 여전히 `observe` — 이 플랜에서 변경 없음. Wave 1(R1/R2/R3) 은 이미 완료(69-01/69-03), 이 플랜으로 Wave 4(R4) 완료.

## Self-Check: PASSED

- FOUND: .planning/phases/69-tenant-isolation-security-hardening/69-DERIVED-MODEL-AUDIT.md
- FOUND: api-ventago/src/common/tenant/tenant-scope.registry.ts
- FOUND: api-ventago/src/common/tenant/tenant-hooks.ts
- FOUND: api-ventago/src/common/tenant/tenant-derived.spec.ts
- FOUND commit: 9c0d5e2 (docs, Task 1, 루트 레포)
- FOUND commit: 06f0392 (feat, Task 2, api-ventago)
- FOUND commit: 72b7af7 (test, Task 3, api-ventago)

---
*Phase: 69-tenant-isolation-security-hardening*
*Plan: 06*
*Completed: 2026-08-01*
