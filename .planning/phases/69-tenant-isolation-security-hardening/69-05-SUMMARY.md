---
phase: 69-tenant-isolation-security-hardening
plan: 05
subsystem: auth
tags: [jwt, bcrypt, nestjs, flutter, riverpod, vendor-portal, multi-tenant]

# Dependency graph
requires:
  - phase: 69-04
    provides: "벤더 동일 phone·상이 PIN 실측 조사 — 영향 벤더 0명, 마이그레이션 불필요 확인"
provides:
  - "벤더 포털 로그인이 행별 PIN 검증 후 단일 vendorId/storeId scope 토큰만 발급"
  - "vendor-jwt.strategy 가 토큰의 vendorId/storeId 로 정확히 1행만 복원(phone 재조회 제거)"
  - "envios/settlements/notifications/recepciones 4개 컨트롤러의 토큰 storeId 교차 차단"
  - "talleres-vendor-app 매장 선택 로그인 플로우"
affects: [69-06, 69-10-uat, vendor-portal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "벤더 로그인: phone 후보 최대 10개 조회 → bcrypt.compare 행별 순차 검증 → PIN 통과 매장이 1개면 단일 scope 토큰, 2개 이상이면 requiresStoreSelection 응답(토큰 미발급)"
    - "JWT strategy 는 payload.vendorId/storeId 로 findOne({id, storeId, isActive}) 단일 행만 복원 — phone 재조회 금지"
    - "구 토큰(phone+vendorIds 형태) 은 vendorId/storeId 타입 체크 실패 시 TOKEN_LEGACY_REAUTH 401 로 거부"
    - "Flutter: 매장 선택 대기 자격증명은 AuthNotifier 인스턴스 필드(_pendingPhone/_pendingPin)에만 보관, 영속 저장소에 쓰지 않음"

key-files:
  created:
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.spec.ts
  modified:
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/dto/vendor-login.dto.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.strategy.ts
    - api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.service.ts
    - talleres-vendor-app/lib/features/auth/data/auth_repository.dart
    - talleres-vendor-app/lib/features/auth/data/auth_dto.dart
    - talleres-vendor-app/lib/features/auth/providers/auth_provider.dart
    - talleres-vendor-app/lib/features/auth/views/login_screen.dart

key-decisions:
  - "69-04 실측 결과(영향 벤더 0명, pin_hash 전량 NULL) 확인 후 데이터 마이그레이션/매장 통지 없이 순수 코드 변경으로 진행"
  - "vendor-recepciones.service.ts 는 계획 files_modified 에 없었으나 storeId AND 조건을 서비스 조회에 추가해야 해 Task 2 지시에 따라 변경(플랜이 명시적으로 허용한 케이스)"
  - "Flutter storeSelectionPendingProvider 는 Riverpod 3.x 에 StateProvider 가 없어 selectedStoreIndexProvider 와 동일한 Notifier 패턴으로 구현(계획 원안의 StateProvider 표기에서 벗어남)"

patterns-established:
  - "벤더 포털처럼 자체 JWT 전략을 쓰는 서브시스템은 토큰에 매장 scope 를 단일 값으로 못박고, strategy 는 그 값으로만 재조회한다(phone/email 등 열거 가능한 키로 매 요청 재조회 금지)"

requirements-completed: [R3]

# Metrics
duration: ~65min
completed: 2026-08-01
---

# Phase 69 Plan 05: 벤더 포털 토큰 단일 매장 Scope 전환 Summary

**벤더 로그인을 행별 PIN 개별 검증 + 단일 vendorId/storeId JWT scope 로 재작성하고, 4개 벤더 컨트롤러에 토큰-매장 교차 차단을 추가해 R3/CR-03(동일 전화번호 벤더 PIN 1개로 타 매장 권한 획득)을 봉쇄했다.**

## Performance

- **Started:** 이 세션 시작 시점 명시적 타임스탬프 미기록 (harness 의 `record_start_time` 단계 누락) — 대화 진행량 기준 추정
- **Completed:** 2026-08-01T03:42:14Z
- **Duration:** 약 65분 (추정)
- **Tasks:** 4/4 완료
- **Files modified:** 13 (backend 9, Flutter 4) + SUMMARY 1

## 승인 게이트

69-04 조사 결과(운영 7건/로컬 18건 전 벤더 `pin_hash` NULL, 동일 phone 다중 매장 조합 0건)에 따라
**영향 벤더 0명, 데이터 마이그레이션 0건, 매장 통지 0건**이 확정되었고 사용자가 진행을 승인했다.
이 플랜은 순수 코드 변경으로만 진행했다 — opt-a/opt-b 여부와 무관하게 실행 조건이 이미 충족되어 있었다.

## Accomplishments

1. **행별 PIN 검증 + 단일 매장 토큰 발급** — `vendorLogin` 이 `vendors[0].pinHash` 하나만 검증하던 결함을 제거하고, phone(+선택 storeId) 후보 최대 10개를 조회해 각 행에 `bcrypt.compare` 를 개별 수행. PIN 이 통과한 매장이 정확히 1개면 그 `vendorId/storeId` 만 담긴 토큰을 발급하고, 2개 이상이면 토큰 없이 `requiresStoreSelection: true` 응답으로 매장 선택을 요구한다.
2. **JWT strategy 단일 행 복원** — `vendor-jwt.strategy.ts` 가 매 요청마다 phone 으로 벤더 전체를 재조회하던 것을 제거하고, 토큰의 `vendorId/storeId` 로 `findOne({id, storeId, isActive})` 단일 행만 복원한다. `vendorId`/`storeId` 가 없는 구 토큰(phone+vendorIds 형태)은 `TOKEN_LEGACY_REAUTH` 401 로 거부한다.
3. **4개 컨트롤러 storeId 교차 차단** — envios/settlements/notifications 는 쿼리·바디 `storeId` 가 토큰 `storeId` 와 다르면 403. recepciones 는 dto 에 storeId 필드가 없어 컨트롤러가 `req.user.storeId` 를 서비스에 전달하고, 서비스의 envío 조회를 `findByPk` → `findOne({where: {id, storeId}})` 로 바꿔 AND 조건으로 매장 밖 envío 접근을 차단했다.
4. **회귀 테스트 8종** — 매장 6 PIN 만 일치 시 매장 9 미노출(2건), 동일 PIN 2개 매장 통과 시 매장 선택 요구 + 재호출로 단일 토큰(2건), pinHash NULL 401 + limit 적용(2건), strategy 구 토큰 차단 + 단일 행 복원(2건).
5. **Flutter 배선** — `talleres-vendor-app` 로그인이 `requiresStoreSelection` 응답을 받으면 "Seleccioná la tienda" 다이얼로그로 전환하고, "Continuar" 로 매장을 확정하면 메모리에 보관한 phone/PIN 으로 `storeId` 를 실어 재로그인한다. PIN 은 재입력도, 영속 저장도 하지 않는다.

## Task Commits

api-ventago (자체 저장소, main 브랜치):

1. **Task 1: 행별 PIN 검증 + 단일 매장 토큰 발급** — `064c52c` (fix)
2. **Task 2: strategy 단일 행 복원 + 4개 컨트롤러 storeId 교차 차단** — `6e51fbf` (fix)
3. **Task 3: 교차매장 벤더 토큰 회귀 테스트 8종** — `9b47c5f` (test)

루트 저장소 (talleres-vendor-app 은 서브모듈이 아닌 일반 추적 디렉터리):

4. **Task 4: talleres-vendor-app 로그인 매장 선택 배선** — `cc74d1d` (fix)

**주의:** 이 플랜은 `api-ventago` 서브모듈 포인터 bump 를 커밋하지 않았다(오케스트레이터 담당).
`git push` 도 실행하지 않았다(운영 배포 트리거 방지).

## Files Created/Modified

- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts` — vendorLogin 행별 PIN 검증 + 단일 토큰, getMe 단일 행 복원, `VENDOR_LOGIN_MAX_CANDIDATES=10` 상한
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.controller.ts` — login/getMe 시그니처를 새 서비스 계약에 맞춤
- `api-ventago/src/app/vendor-portal/vendor-auth/dto/vendor-login.dto.ts` — 선택 `storeId?: number` 필드 추가
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.strategy.ts` — `findOne` 단일 행 복원 + `TOKEN_LEGACY_REAUTH`
- `api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.controller.ts` — storeId 교차 403
- `api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.controller.ts` — storeId 교차 403
- `api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.controller.ts` — 3개 엔드포인트에 storeId 교차 403 (markAsRead 는 storeId 파라미터가 없어 기존 vendorIds 소유권 검사로 충분 — 이제 vendorIds 가 항상 단일 값이므로 사실상 봉쇄됨)
- `api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.controller.ts` — req.user.storeId 를 서비스에 전달
- `api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.service.ts` — envío 조회를 storeId AND 조건으로 한정 (계획 files_modified 에 없던 필수 추가 변경)
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.spec.ts` (신규) — 회귀 테스트 8종
- `talleres-vendor-app/lib/features/auth/data/auth_repository.dart` — `login(phone, pin, {storeId})`
- `talleres-vendor-app/lib/features/auth/data/auth_dto.dart` — `StoreSelectionRequired` 모델 추가
- `talleres-vendor-app/lib/features/auth/providers/auth_provider.dart` — `storeSelectionPendingProvider` + `AuthNotifier.selectStore()` + 메모리 전용 pending 자격증명
- `talleres-vendor-app/lib/features/auth/views/login_screen.dart` — 매장 선택 다이얼로그

## Decisions Made

- **69-04 근거로 마이그레이션 스킵**: 실측 조사에서 영향 벤더 0명이 확인되어 계획대로 순수 코드 변경만 진행하고 매장 통지·계정 병합 절차를 생략했다.
- **vendor-recepciones.service.ts 추가 변경**: 계획의 `files_modified` 목록에는 컨트롤러만 있었지만, dto 에 storeId 필드가 없는 구조상 서비스의 envío 조회(`findByPk`→`findOne`)에 storeId AND 조건을 추가하지 않고서는 R3/CR-03 을 완전히 봉쇄할 수 없었다. 플랜 본문이 "서비스 파일 변경이 필요하면 추가 기재하고 SUMMARY 에 기록"하도록 명시적으로 허용한 케이스라 Rule 3(블로킹 이슈 자동 수정)으로 처리했다.
- **Flutter StateProvider 대체**: 계획은 `storeSelectionPendingProvider` 를 암묵적으로 단순 상태 provider 로 상정했으나, 이 프로젝트의 Riverpod 3.3.1 은 `StateProvider` 를 노출하지 않는다(`flutter analyze` 에서 `undefined_function` 확인). 기존 `selectedStoreIndexProvider` 와 동일한 `NotifierProvider` 패턴으로 대체했다.
- **home_screen.dart / store_tab_bar.dart 무변경**: 이 두 파일은 플랜 `files_modified` 에 없다. `authState.stores.length > 1` / `stores.length <= 1` 조건으로 매장 전환 UI(드롭다운/탭바)를 이미 조건부 렌더링하고 있어, 로그인 응답이 항상 길이 1이 되는 이 변경 이후에는 그 UI가 자연히 숨겨진다 — "매장 전환이 필요하면 재로그인 경로로" 요구사항이 코드 수정 없이 이미 충족된다.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] vendor-recepciones.service.ts 에 storeId AND 조건 추가**
- **Found during:** Task 2
- **Issue:** recepciones DTO 에는 storeId 필드가 없어 컨트롤러 단독으로는 매장 교차를 차단할 수 없었다. 서비스의 `envioModel.findByPk(dto.envioId)` 는 매장 구분 없이 아무 envío 나 조회했다.
- **Fix:** `findByPk` → `findOne({where: {id: dto.envioId, storeId}})` 로 변경, 컨트롤러가 `req.user.storeId` 를 3번째 인자로 전달하도록 시그니처 확장.
- **Files modified:** `vendor-recepciones.controller.ts`, `vendor-recepciones.service.ts`
- **Verification:** `npx tsc --noEmit` 통과, 기존 recepciones 동작(NotFoundException/ForbiddenException 경로) 무회귀
- **Committed in:** `6e51fbf` (Task 2 commit)

**2. [Rule 3 - Blocking] Flutter storeSelectionPendingProvider 구현체를 StateProvider → NotifierProvider 로 변경**
- **Found during:** Task 4
- **Issue:** `flutter analyze` 가 `StateProvider isn't defined` 컴파일 에러를 냄 (Riverpod 3.x 는 StateProvider 미제공)
- **Fix:** `selectedStoreIndexProvider` 와 동일한 `Notifier<List<StoreInfo>?>` 패턴(`StoreSelectionPendingNotifier`)으로 재구현
- **Files modified:** `auth_provider.dart`
- **Verification:** `flutter analyze` error 0
- **Committed in:** `cc74d1d` (Task 4 commit)

---

**Total deviations:** 2 auto-fixed (둘 다 Rule 3 — 계획대로는 컴파일/동작이 불가능했던 블로킹 이슈)
**Impact on plan:** 두 건 모두 계획이 의도한 보안 목표(R3/CR-03 봉쇄, 매장 선택 UX)를 달성하기 위한 필수 수정. 스코프 확대 없음.

## Issues Encountered

- **ESLint `no-unsafe-*` (type-checked) 경고 다수**: 변경한 컨트롤러 6개와 신규 spec 파일에서 `req.user`/`req: any` 접근에 대해 `@typescript-eslint/no-unsafe-member-access` 등이 다수 발생. `git stash` 로 수정 전 동일 파일에 eslint 를 돌려 비교한 결과, **이 오류들은 전부 수정 전부터 존재하던 패턴**이었다(예: `vendor-envios.controller.ts` 는 수정 전 4건, 수정 후 5건 — 늘어난 1건은 동일 패턴의 storeId 검사 한 줄 추가분). `productStock.service.spec.ts` 등 기존 spec 파일도 동일 규칙으로 197건을 위반하고 있어 프로젝트 전역의 기존 컨벤션임을 확인했다. CLAUDE.md 가 빌드를 막는다고 명시한 규칙(`newline-before-return`, `lines-around-comment`, `no-unused-vars`, `react-hooks/exhaustive-deps`)에는 `no-unsafe-*` 가 포함되지 않는다. 새로 도입된 유일한 lint 위반(prettier 포맷 2건)은 `--fix` 로 즉시 정리했다. 나머지는 스코프 밖 기존 부채로 두었다(SCOPE BOUNDARY 규칙에 따름).
- **`record_start_time` 단계 누락**: 플랜 시작 시 `PLAN_START_TIME`/`PLAN_START_EPOCH` 를 기록하지 않아 Performance 섹션의 소요시간이 정확한 타임스탬프 차이가 아닌 추정치다.

## 검증 결과 (실제 명령 출력)

```
$ cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"
16   # 수정 전과 동일한 사전 존재 오류 16건, vendor-portal 관련 신규 오류 0건

$ npx jest src/app/vendor-portal
Test Suites: 1 passed, 1 total
Tests:       8 passed, 8 total

$ npx jest src/common/tenant src/common/socket
Test Suites: 4 passed, 4 total
Tests:       37 passed, 37 total    # 69-01/69-06 무회귀 확인

$ cd talleres-vendor-app && flutter analyze
1 issue found (info)   # null-aware 스타일 제안, RadioListTile deprecated 제안 — 모두 error 0
```

**교차매장 회귀 증거 (수정 전 코드에서 실패 확인):**
`git checkout 72b7af7 -- vendor-auth.service.ts vendor-jwt.strategy.ts` 로 Task 1·2 를 되돌린 뒤
`npx jest .../vendor-auth.service.spec.ts` 를 재실행한 결과, 타입 시그니처 불일치로 **테스트 스위트 자체가 컴파일 실패**해 8/8 전건이 실패했다(계획이 요구한 "최소 4개 실패"를 초과 충족). 구체적으로 `result.requiresStoreSelection`, 3번째 인자 `storeId`, `result.vendorId`/`result.storeId` 접근이 구 타입(`{token: string; stores: any[]}`, `{vendors: Vendor[]; phone: string}`)에 존재하지 않아 TS2339/TS2554/TS2551 로 실패했다. 확인 후 `git checkout HEAD -- <두 파일>` 로 즉시 복원했다.

## Known Stubs

없음.

## Threat Flags

없음 — 이 플랜은 threat_model 에 등록된 T-69-16~T-69-21 을 mitigate/accept 로 처리했을 뿐 새로운 신뢰 경계나 엔드포인트를 추가하지 않았다.

## 배포 영향 고지 (반드시 확인)

- **기존 벤더 토큰 전부 무효화**: 배포 시 `vendorId`/`storeId` 가 없는 구 토큰은 `TOKEN_LEGACY_REAUTH` 로 401 이 되어 재로그인이 필요하다. 단 69-04 실측 결과 **운영에 유효한 벤더 토큰이 존재할 수 없다**(전 벤더 `pin_hash` NULL → 로그인 자체가 불가능한 상태였음) — 따라서 실제 피해자는 0명이다.
- **(B) 버킷(동일 phone·상이 PIN) 매장 통지**: 69-04 조사에서 해당 조합이 0건으로 확인되어 **통지 불필요**.
- **운영 테스트 데이터**: store 6 에 phone 이 빈값/`jadskljf`/`lee` 등인 7개 행이 남아있다(69-04 에서 식별, 이 플랜 범위 밖 — 삭제하지 않았다).

## Next Phase Readiness

- R3/CR-03 봉쇄 완료. 69-06(TenantContext fail-closed) 등 후속 플랜과 독립적으로 진행 가능.
- 69-10 UAT 단계에서 실제 벤더 로그인 플로우(단일 매장 + 매장 선택 양쪽 경로) 브라우저/앱 수동 검증 필요.
- 운영 배포(git push)는 이 실행에서 하지 않았다 — 오케스트레이터/사용자 지시에 따라 별도 진행.

---
*Phase: 69-tenant-isolation-security-hardening*
*Completed: 2026-08-01*

## Self-Check: PASSED

- 모든 backend/Flutter/SUMMARY 파일 15개 존재 확인 (`FOUND`)
- api-ventago 커밋 3건(`064c52c`, `6e51fbf`, `9b47c5f`) + 루트 저장소 커밋 1건(`cc74d1d`) 전부 `git log --oneline --all` 에서 확인됨
- 누락 항목 없음
