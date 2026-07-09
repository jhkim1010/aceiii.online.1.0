---
phase: 37-mobile-sales-shell
plan: 05
subsystem: mobile-revendedor-skeleton
tags: [mobile, flutter, revendedor, blocked, phase-24-gate, skeleton, D-07]
requires:
  - 37-03 (Flutter shell: scope_provider MultiStoreScope, app_router, AppTheme)
  - 37-04 (vendedor MVP — ships independently; not blocked by this plan)
blocked_by_external:
  - Phase 24 Wave 1-2 (reseller.catalog_unified MV + reseller_tienda_link) — VERIFIED ABSENT
provides:
  - mobile-sales-app/lib/features/revendedor/ 예약 surface (blocked skeleton)
  - README dependency block + activation checklist (Phase 24 활성화 계약)
  - StoreSelectorScreen + QuoteScreen stubs (Próximamente placeholder, NO logic)
  - /revendedor/stores + /revendedor/quote 라우트 (MultiStoreScope 분기 전용)
affects:
  - (parent repo) mobile-sales-app/lib/router/app_router.dart — MultiStoreScope 랜딩 분기 추가
tech-stack:
  added: []
  patterns:
    - "blocked-skeleton: 외부 스키마 의존(Phase 24) 부재 시 UI surface 만 예약 + 활성화 계약 문서화 (D-07, threat T-37-21)"
    - "MultiStoreScope 인증 사용자만 /revendedor/stores 로 redirect — vendedor(BranchScope) 경로 무변경"
key-files:
  created:
    - mobile-sales-app/lib/features/revendedor/README.md
    - mobile-sales-app/lib/features/revendedor/views/store_selector_screen.dart
    - mobile-sales-app/lib/features/revendedor/views/quote_screen.dart
  modified:
    - mobile-sales-app/lib/router/app_router.dart
decisions:
  - "Task 1 결정 게이트 = BLOCKED: reseller.catalog_unified / reseller_tienda_link / reseller.* 모두 .planning/intel/db-schema-tables.md 에 부재(grep 0 hits). Phase 24 디렉토리는 24-CONTEXT.md 만 존재(plan/summary 없음 = 미실행). → skeleton only, halt. vendedor MVP(Wave 1-4) 무영향."
  - "라우트 wiring: app_router.dart 수정(계획 files_modified 3개 외 추가). 계획 action 이 'MultiStoreScope route branch only' wiring 을 명시적으로 지시 → stub 을 reachable/navigable 하게 만들기 위한 필수 변경(Rule 3). 인증 redirect 는 MultiStoreScope 케이스만 /revendedor/stores 로 분기, vendedor(BranchScope) 는 /home 유지(무회귀)."
  - "store_tab_bar.dart 는 현재 리포에 부재(Wave 3 summary 에 미기재). stub 은 이를 import 하지 않음 — 활성화 시 재사용 대상으로 README 에만 기록."
metrics:
  tasks: 1 (decision gate → BLOCKED) + 1 (skeleton)
  files-created: 3
  files-modified: 1
  tests: 10 passed (기존 scope 4 + variant 6 — 회귀 없음)
  duration: ~15m
  completed: 2026-07-08
---

# Phase 37 Plan 05: Revendedor BLOCKED Skeleton Summary

Revendedor 모드를 **의도적으로 차단된 얇은 스켈레톤**으로 예약했다(D-07). Phase 24 Wave 1-2
(`reseller.catalog_unified` MV + `reseller_tienda_link`)가 스키마에 **부재**함을 재확인하고,
실제 카탈로그/재고/cotización 로직은 전혀 구현하지 않았다. 대신 (1) Phase 24 의존 블록 + 활성화
체크리스트 README, (2) "Próximamente — requiere Phase 24" placeholder 두 화면을 만들어,
Phase 24 도착 시 재탐색 없이 바로 구현 가능하도록 활성화 계약을 문서화했다. vendedor MVP(Wave 1-4)는
전혀 영향받지 않는다.

## Task 1 — Decision Gate: BLOCKED (근거)

- `grep reseller_tienda_link | catalog_unified | reseller\.` → `.planning/intel/db-schema-tables.md` **0 hits** (부재 확인).
- `.planning/phases/24-revendedor-marketplace/` → `24-CONTEXT.md` 만 존재, plan/summary 없음 = **미실행**.
- STATE.md → Phase 24 완료 흔적 없음(Phase 42 등 후속만 활성).
- **결정: `blocked`** → Task 2(skeleton)만 수행 후 halt. 백엔드 revendedor scope/guard 작업, MobileAuthService
  혁명 없음.

## What Was Built (skeleton only)

- **`features/revendedor/README.md`** — (1) 부재하는 Phase 24 아티팩트 표(`reseller.catalog_unified`
  materialized view + `reseller_tienda_link` 테이블), (2) 레거시 `revendedores` 모듈과 혼동 금지 경고,
  (3) 활성화 체크리스트(MobileAuthService revendedor scope, MobileScopeGuard cross-store 거부(T-37-20),
  `/mobile/catalog`+`/mobile/stock` revendedor 브랜치, D-14 검색-투-리스트 진입, D-13 cotización=pendiente
  Caja-neutral), (4) 재사용 인터페이스(`MultiStoreScope`, `store_tab_bar.dart` when exists).
- **`views/store_selector_screen.dart`** — MultiStoreScope 진입점 placeholder("Modo revendedor —
  Próximamente (requiere Phase 24)"). Ventago 테마. `Ver cotización` 버튼으로 quote stub 네비게이션
  (navigable 보장). **API 호출 0, 매장 선택 로직 0.**
- **`views/quote_screen.dart`** — cotización placeholder("Cotización — Próximamente", "pendientes
  (Caja-neutral)" 안내). **API 호출 0, cotización 로직 0.**
- **`router/app_router.dart`** — `/revendedor/stores` + `/revendedor/quote` 라우트 추가 +
  인증 redirect 를 `isRevendedor ? '/revendedor/stores' : '/home'` 로 분기. vendedor(BranchScope)
  경로/네비게이션 무변경.

## must_haves Truths — Status

| Truth | Status | Evidence |
|-------|--------|----------|
| Revendedor = thin, explicitly-gated skeleton — NOT ship 까지 Phase 24 Wave 1-2 (D-07) | ✅ | README dependency block + 2 stub(placeholder only) + Task1 BLOCKED 결정 |
| (unblocked 시) store selector(N stores) + search-to-list(NO QR, D-14) + quote=pendiente/보류(D-13) | ✅ (documented) | README 활성화 체크리스트에 계약 명시 — 코드 미구현(게이트 준수) |

## Verification Results (honest)

- `flutter analyze` (전체 앱) → **No issues found!** (0 errors/0 warnings) ✅
- `flutter test` → **10/10 passed** (scope 4 + variant 6 — 회귀 없음) ✅
- 계획 automated 게이트: `grep reseller.catalog_unified README` ✓ + `grep reseller_tienda_link README` ✓
  → **README-CONTAINS-BOTH-LITERALS: OK** ✅
- stub API 호출 검사: `grep -E "apiConnector|DioClient|dio|Repository|http" views/*.dart` → **0 hits**
  (NO-API-CALLS: OK) ✅
- **환경:** Flutter 3.41.2 stable / Dart 3.11.0, flutter=/Users/marcoskim/flutter/bin.

## Deviations from Plan

### Auto-added (Rule 3 — Blocking: navigability)

**1. [Rule 3] app_router.dart 수정 (계획 files_modified 3개 외)**
- **Found during:** Task 2 (stub 을 reachable/navigable 하게 만들기)
- **Issue:** 계획 frontmatter files_modified 는 revendedor 3개 파일만 나열하나, 계획 action 은
  "Wire them behind the MultiStoreScope route branch only (so vendedor navigation is untouched)" 를
  명시 → 라우트 등록 없이는 stub 이 navigable 하지 않음(hard constraint 위배).
- **Fix:** `/revendedor/stores` + `/revendedor/quote` GoRoute 추가 + 인증 redirect 를 MultiStoreScope
  케이스만 `/revendedor/stores` 로 분기. vendedor(BranchScope) redirect(`/home`) 및 모든 vendedor 라우트
  무변경 → 회귀 0 (`flutter test` 10/10, analyze clean).
- **Files modified:** mobile-sales-app/lib/router/app_router.dart

### Design notes

- **store_tab_bar.dart 미참조:** 계획 interfaces 는 Wave 3 에서 클론했다고 언급하나 현재 리포에
  존재하지 않음(37-03-SUMMARY key-files 에도 없음). stub 은 이를 import 하지 않고, README 활성화
  체크리스트에 "when exists" 재사용 대상으로만 기록 → 컴파일 안전.
- **_ComingSoon 공용 위젯:** store_selector 내부 private 위젯으로 placeholder 룩 통일(Ventago 테마
  amberSoft/gold). quote 는 자체 렌더(단순).

## Known Stubs (의도적 — Phase 24 게이트)

- **StoreSelectorScreen / QuoteScreen** — 의도적 placeholder. Phase 24 Wave 1-2 완료 후 후속 플랜에서
  실제 매장 선택기 / cotización(pendiente, D-13) 로 교체. README 활성화 체크리스트가 정확한 구현 계약.
  **이 stub 은 D-07 게이트로 intentional — vendedor MVP goal 미저해, revendedor goal 은 Phase 24 의존.**

## Deferred / Out-of-scope (기록만)

- **revendedor 백엔드 전부** — MobileAuthService revendedor scope resolution, MobileScopeGuard revendedor
  브랜치(T-37-20), `/mobile/catalog`+`/mobile/stock` revendedor 구현. Phase 24 도착 시 후속 플랜.
- **STATE.md / ROADMAP.md** — 본 플랜 미변경(critical rule 5 준수).
- 사전 존재하던 서브모듈 working-tree 수정(api-ventago/ventago-app, .gsd-snapshot) 손대지 않음.

## Threat Model — Status

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-37-20 (EoP: revendedor cross-store read) | mitigate (future) | README 활성화 체크리스트에 MobileScopeGuard revendedor 브랜치로 기록 — Phase 24 도착 시 구현 |
| T-37-21 (Tampering: build against non-existent MV) | mitigate | Task 1 결정 게이트가 구현을 차단(BLOCKED). 코드 미작성으로 silent breakage 원천 차단 ✅ |

## Commits (parent repo, base bc25fbb)

- `73b896a` feat(37-05): revendedor BLOCKED skeleton (D-07 Phase 24 gate)

## Self-Check: PASSED

- 핵심 파일 3/3 존재 확인 (README.md, store_selector_screen.dart, quote_screen.dart) + app_router.dart 수정.
- 커밋 1/1 존재 확인 (73b896a).
- `flutter analyze` 0 issues + `flutter test` 10/10 passed (재현 가능).
- README 리터럴 `reseller.catalog_unified` + `reseller_tienda_link` 존재 확인. stub API 호출 0.
