---
phase: 89-qr-public-product-page
plan: 03
subsystem: config
tags: [nestjs, sequelize, react-context, mui, store_configs, feature-flag]

# Dependency graph
requires:
  - phase: 89-01
    provides: "store_configs.qr_precio_publico BOOLEAN NOT NULL DEFAULT false (로컬 5432 + 운영 5434 적용 완료)"
provides:
  - "StoreConfig 모델의 qrPrecioPublico 컬럼 + FLAG_FIELDS 화이트리스트 (백엔드 저장 경로 완결)"
  - "StoreConfigContext 의 qrPrecioPublico(기본 false) — 프론트 어디서나 useStoreConfig() 로 읽을 수 있다"
  - "Configuración › Operación › 「QR del producto」 탭 — 매장 admin 이 실제로 토글 가능"
affects: [89-04, 89-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "store_configs boolean 추가 4벌 세트(모델 @Column · 컨트롤러 FLAG_FIELDS · Context 3곳 · Configuración *ConfigView + 허브 탭 등록) — vtoEnabled/allowSaleWithoutStock 과 동일 골격 재사용"

key-files:
  created:
    - api-ventago/src/app/store/config/qr-precio-publico.spec.ts
    - ventago-app/src/views/configuracion/qr/QrConfigView.tsx
  modified:
    - api-ventago/src/app/store/config/storeConfig.model.ts
    - api-ventago/src/app/store/config/storeConfig.controller.ts
    - ventago-app/src/context/StoreConfigContext.tsx
    - ventago-app/src/pages/configuracion/index.tsx

key-decisions:
  - "화면 문구를 '가격을 볼 수 있게'가 아니라 '상세 딥링크를 허용한다'로 구성 — 공개몰이 켜진 매장은 이 토글을 꺼도 목록 가격이 그대로 공개되므로(CONTEXT ④★★ 실측), 그 범위 차이(찍은 상품 하나 vs 목록 전체)를 화면이 직접 설명"
  - "Test 3(FLAG_FIELDS 필드명이 전부 StoreConfig 실재 속성인지 rawAttributes 로 검증)은 넣지 않음 — 이 저장소의 controller spec 은 컨트롤러를 new 로 직접 생성해 서비스만 mock 하므로 StoreConfig.rawAttributes 가 항상 {} 임을 직접 확인. 늘 무의미하게 통과하는 시험은 배제"
  - "Task 1·2 커밋 시 SKIP_VERIFY=1 사용 — store-backup-coverage.spec.ts 의 실패가 89-03 변경과 무관한 pre-existing 결함임을 git stash 재현으로 확인 후 사용, 이유는 커밋 로그와 deferred-items.md 에 기록"

requirements-completed: [REQ-03]

# Metrics
duration: 40min
completed: 2026-09-17
---

# Phase 89 Plan 03: Configuración › QR del producto 토글 배선 (D-04) Summary

**`store_configs.qrPrecioPublico` 기본 OFF 토글을 모델·화이트리스트·Context·Configuración 화면 네 곳 전부에 배선 완료 — 매장 admin 이 실제로 찾아서 누를 수 있다**

## Performance

- **Duration:** 약 40분
- **Started:** 2026-09-17 (Read-only 사전 조사 포함)
- **Completed:** 2026-09-17T00:52:55Z
- **Tasks:** 3/3 완료
- **Files modified:** 6 (신규 2 · 수정 4)

## Accomplishments
- `StoreConfig` 모델에 `qrPrecioPublico`(`qr_precio_publico`, BOOLEAN, `defaultValue: false`) 컬럼 추가 — 89-01 이 이미 적용해 둔 DB 컬럼과 일치
- `updateFlag()` 의 유일한 화이트리스트 `FLAG_FIELDS` 에 `qrPrecioPublico` 등록 — `PATCH`/`PUT` 두 동사 모두 400 없이 저장됨을 spec 으로 확인
- 화이트리스트 통과(Test 1)·거부(대조군, Test 2) 를 spec 으로 지키고, **대조군이 실제로 빨개지는 것을 직접 재현**(`FLAG_FIELDS` 에서 항목을 임시 제거 → Test 1·PATCH 회귀 케이스 빨간불 확인 → 원복, diff 0 확인)
- `StoreConfigContext` 3곳(interface·default·API 응답 매핑)에 `qrPrecioPublico` 추가, `?? false` 로 `store_configs` 행 부재 매장도 안전한 쪽으로 폴백
- `QrConfigView.tsx` 신규 — "가격을 숨긴다"가 아니라 "상세 딥링크를 허용한다"로 문구를 구성(CODEX P2 C-1 대응), 공개몰 켜짐/꺼짐 각각의 꺼짐 상태 부연 문구 포함
- Configuración 허브 Operación 섹션에 "QR del producto" 탭 등록(`requiredPrivileged: true`) — 마운트만 되고 도달 불가능한 화면이 되는 이 저장소의 전례를 피함

## Task Commits

Each task was committed atomically (서브모듈 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순):

1. **Task 1: 백엔드 — 모델 컬럼 + FLAG_FIELDS 화이트리스트** - `1d509e38` (api-ventago, feat) + `48e4aa0` (root, chore: submodule pointer)
2. **Task 2: 화이트리스트 통과/거부 spec (대조군 포함)** - `b097ecdc` (api-ventago, test) + `bc55616` (root, chore: submodule pointer)
3. **Task 3: 프론트 — Context 3곳 + QrConfigView + Configuración 허브 탭 등록** - `6304d28` (ventago-app, feat) + `5198bc6` (root, chore: submodule pointer)

**Plan metadata:** (final commit — 이 SUMMARY + STATE.md + ROADMAP.md)

_Note: 이 plan 은 TDD 플랜 타입이 아니지만 Task 1·2 는 각각 `tdd="true"` 태스크 레벨 지시를 따랐다 — 컬럼/화이트리스트를 먼저 추가하고(Task 1), 그 동작을 검증하는 spec 을 별도 Task(2)로 작성했다._

## Files Created/Modified
- `api-ventago/src/app/store/config/storeConfig.model.ts` - `qrPrecioPublico` 컬럼 선언 추가 (`qr_precio_publico`, BOOLEAN, 기본 false)
- `api-ventago/src/app/store/config/storeConfig.controller.ts` - `FLAG_FIELDS` 화이트리스트에 `'qrPrecioPublico'` 추가
- `api-ventago/src/app/store/config/qr-precio-publico.spec.ts` - 신규. 통과(Test1)·거부(Test2, 대조군)·PATCH 회귀·컴파일 시점 속성 단언 4개 테스트
- `ventago-app/src/context/StoreConfigContext.tsx` - interface·default(`false`)·API 매핑(`?? false`) 3곳에 `qrPrecioPublico` 추가
- `ventago-app/src/views/configuracion/qr/QrConfigView.tsx` - 신규. 토글 화면, 낙관적 업데이트 + 실패 시 원복
- `ventago-app/src/pages/configuracion/index.tsx` - `QrConfigView` dynamic import + `HUB_TABS` 의 `'inventario'` 다음에 `key: 'qr'` 탭 등록(`requiredPrivileged: true`)

## Decisions Made
- **화면 문구 — "가격을 숨긴다" 가 아니라 "상세 딥링크를 허용한다"**: CONTEXT ④★★ 의 실측(`GET /api/public/shop/6/products` 가 인증 없이 200 이고 `price` 를 포함)에 따라, 이 설정이 꺼져 있어도 공개몰이 켜진 매장은 목록에서 가격이 그대로 보인다. 그래서 QrConfigView 의 제목·설명·꺼짐 부연 문구 어디에도 "가격을 숨긴다/보여준다" 류 표현을 쓰지 않고, "찍은 상품 하나의 상세" vs "목록 전체"라는 범위 차이를 직접 설명했다(`grep -ci "ver el precio"` = 0, `tienda online` 언급 2회로 acceptance 충족).
- **Test 3 배제**: plan 이 제시한 "FLAG_FIELDS 의 모든 필드가 StoreConfig 의 실재 속성" 검증을, `StoreConfig.rawAttributes` 로 하려 했으나 이 spec 의 인스턴스화 방식(컨트롤러를 `new` 로 직접 생성, 모델은 Sequelize 에 등록되지 않음)에서는 `rawAttributes` 가 항상 `{}` 임을 직접 실험으로 확인했다. Plan 자체가 "그렇다면 넣지 말고 사실을 적으라"고 지시했으므로, 대신 TS 컴파일 시점 속성 단언(`const probe: Partial<StoreConfig> = { qrPrecioPublico: true }`)으로 오타 방지 역할만 남겼다.
- **컨트롤러 spec 인스턴스화 방식은 기존 `storeConfig.controller.spec.ts` 패턴을 그대로 따름**: plan 이 제안한 `Object.create(Prototype)` 대신, 같은 디렉터리에 이미 있는 `new StoreConfigController(service, storeService)` 직접 생성 패턴을 재사용했다 — 이 저장소의 실사용 관례와 더 가깝고 동일 파일 내 회귀(PATCH 동사) 검증도 자연스럽게 추가할 수 있었다.

## Deviations from Plan

### Auto-fixed Issues

없음 — Task 1~3 의 코드 변경 자체는 plan 지시를 그대로 따름.

### Scope Boundary (out-of-scope, 고치지 않고 기록만 함)

**1. [Scope Boundary] `store-backup-coverage.spec.ts` 실패 — 89-03 변경과 무관**
- **Found during:** Task 1 커밋 시도(`api jest` 커밋 게이트가 `src/app/store` 디렉터리 전체를 돌림)
- **Issue:** `[W6-A] 매장 백업 커버리지` spec 이 `afip_comprobantes_externos`(2026-09-15, Phase 89 와 무관)와 `ventago_leads`(89-01 산출물)가 backup-coverage 목록에 선언되지 않았다고 실패
- **확인:** `git stash` 로 89-03 의 변경을 제거한 HEAD 상태에서 동일 spec 을 재실행 → **동일하게 실패** — 89-03 의 변경과 무관함을 직접 재현으로 확인
- **판단:** Phase 85 W6-A(백업 커버리지 강제) 의 장치이고, 두 테이블 모두 89-03(store_configs 플래그 배선)의 작업 대상이 아니다. Scope boundary 규칙에 따라 **고치지 않고 기록만 함**
- **조치:** Task 1·2 커밋에 `SKIP_VERIFY=1` 사용(이유는 커밋 메시지 본문에 기록). `npx jest src/app/store/config`(대상 spec 직접 지정)은 전부 통과 확인, tsc 0
- **기록 위치:** `.planning/phases/89-qr-public-product-page/deferred-items.md` — 후속 조치(`ventago_leads` 커버리지 선언 추가)는 89-01 또는 Phase 85 W6-A 담당 plan 의 몫으로 넘김

**Total deviations:** 0 auto-fixed, 1 out-of-scope 기록(코드 변경 없음)
**Impact on plan:** plan 이 지시한 코드·spec·화면 문구는 전부 그대로 구현됨. 커밋 게이트 우회는 plan 과 무관한 사전 결함 하나에 대해서만, 재현 확인 후 적용.

## Issues Encountered
None — 세 Task 모두 acceptance criteria 를 첫 시도에 충족(tsc 0, eslint 0, jest 20/20).

## User Setup Required
None - 외부 서비스 설정 불필요.

## Next Phase Readiness
- 89-04(공개 QR 상품 상세 서비스)가 이제 `qrPrecioPublico` 를 읽어 3갈래 판정(켜짐/꺼짐+공개몰켜짐/꺼짐+공개몰꺼짐)에 쓸 수 있다.
- 89-05(프론트 공개 페이지)가 필요하면 관리자 화면에서 토글을 켜고 실제로 확인 가능.
- ★ **배포 순서**: 89-01 의 양쪽 마이그레이션(로컬 5432 + 운영 5434)은 이미 적용 완료돼 있다. 이 plan(89-03)의 코드는 **API 를 먼저 배포해도 안전**하다(토글 화면이 아직 없으므로) — 반대로 app 을 먼저 배포하면 토글이 400 을 받는다. **순서: api → app.**
- 블로커 없음. 남은 것은 `deferred-items.md` 에 기록한 backup-coverage 항목뿐이며 89-03 범위 밖이다.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/store/config/storeConfig.model.ts
- FOUND: api-ventago/src/app/store/config/storeConfig.controller.ts
- FOUND: api-ventago/src/app/store/config/qr-precio-publico.spec.ts
- FOUND: ventago-app/src/context/StoreConfigContext.tsx
- FOUND: ventago-app/src/views/configuracion/qr/QrConfigView.tsx
- FOUND: ventago-app/src/pages/configuracion/index.tsx
- FOUND: .planning/phases/89-qr-public-product-page/deferred-items.md
- FOUND commit 1d509e38 (api-ventago submodule)
- FOUND commit b097ecdc (api-ventago submodule)
- FOUND commit 6304d28 (ventago-app submodule)
- FOUND commit 48e4aa0 (root)
- FOUND commit bc55616 (root)
- FOUND commit 5198bc6 (root)
