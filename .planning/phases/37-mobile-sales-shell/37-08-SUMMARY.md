---
phase: 37-mobile-sales-shell
plan: 08
subsystem: mobile-sales-app
tags: [mobile, flutter, riverpod, attendance, fichaje, qr, deeplink, clock-in-gate, revendedor]

# Dependency graph
requires:
  - phase: 37-06
    provides: "POST /attendance/punch (role 라우팅) + GET /mobile/me(clockedIn/openSince) + 에러코드(QR_EXPIRED/QR_OTHER_STORE/RESELLER_NOT_APPROVED 등)"
  - phase: 37-04
    provides: "Flutter vendedor 셸(qr_scanner_sheet 패턴, scope_provider, home_screen, app_router, dio_client)"
provides:
  - "attendance feature — FichajeQr/PunchResult dto + attendance_repository(POST /attendance/punch) + punchController(성공 후 scope invalidate)"
  - "fichaje_scanner_sheet — qr_scanner 클론, parseFichajeDeeplink(/m/fichaje?s=&b=&d=&t=), es-AR 에러 토스트"
  - "fichaje_result_screen — role 분기(entrada/salida 근무시간/store_authorized)"
  - "home 출근 게이트 — clockedIn=false 시 작업 잠금 + 'Fichá tu entrada' + fichaje 버튼, clockedIn=true 시 정상 + 'Fichar salida'"
  - "revendedor_home — 매장 승인 QR 프롬프트('Escaneá el QR de la tienda para habilitar', Phase 24 활성 대기)"
  - "parseFichajeDeeplink 단위 테스트(13 green)"
affects: [phase-24-reseller-marketplace, ventago-app-reportes-asistencia]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "딥링크 파서 형제 확장 — parseStockDeeplink(/m/stock) 옆에 parseFichajeDeeplink(/m/fichaje) 순수 함수(단위 테스트)"
    - "punch 성공 후 ref.invalidate(scopeNotifierProvider) → /mobile/me clockedIn 재조회 → 홈 재게이트"
    - "출근 게이트 = 클라이언트 UX 미러링(백엔드 RequireAttendanceGuard 가 권위, 라운드트립 절약)"
    - "단일 QR role 분기 — vendedor in/out vs revendedor store_authorized 를 PunchResult.action 으로 화면 분기"

key-files:
  created:
    - "mobile-sales-app/lib/features/attendance/data/attendance_dto.dart"
    - "mobile-sales-app/lib/features/attendance/data/attendance_repository.dart"
    - "mobile-sales-app/lib/features/attendance/providers/attendance_provider.dart"
    - "mobile-sales-app/lib/features/attendance/views/fichaje_scanner_sheet.dart"
    - "mobile-sales-app/lib/features/attendance/views/fichaje_result_screen.dart"
    - "mobile-sales-app/lib/features/revendedor/views/revendedor_home.dart"
    - "mobile-sales-app/test/fichaje_deeplink_test.dart"
  modified:
    - "mobile-sales-app/lib/features/auth/data/auth_dto.dart"
    - "mobile-sales-app/lib/features/home/views/home_screen.dart"
    - "mobile-sales-app/lib/router/app_router.dart"

key-decisions:
  - "fichaje 스캐너는 qr_scanner_sheet 를 클론하되 ConsumerStatefulWidget 으로 승격 — ref 로 attendance_repository 호출 + scope 무효화 필요"
  - "revendedor_home 는 이 wave 에서 항상 미승인 프롬프트 렌더(서버 매장권 조회는 Phase 24) — const false 분기 dead_code 회피 위해 프롬프트 직접 렌더 + Phase 24 분기 주석"
  - "/revendedor/stores 라우트를 StoreSelectorScreen → RevendedorHome 로 교체(store_selector 는 orphan, wave4_placeholder 선례)"
  - "punch 성공 후 scope 무효화는 in/out 에만(revendedor store_authorized 는 출근 세션 무관 → 불필요한 /mobile/me 회피)"

requirements-completed: [ATTEND-02, ATTEND-03, ATTEND-08]

# Metrics
duration: 9 min
completed: 2026-07-11
---

# Phase 37 Plan 08: Mobile Fichaje + Clock-in Gate Summary

**mobile-sales-app 출퇴근 feature — caja 데스크톱 일일 QR(`/m/fichaje`)을 기존 mobile_scanner 로 스캔해 POST /attendance/punch, role 로 갈리는 결과화면(vendedor entrada/salida 근무시간 / revendedor 매장권), 그리고 홈 출근 게이트(clockedIn=false 면 Catálogo/스캐너/판매 잠금 + fichaje 만). 딥링크 파서 단위 테스트 13 green, scoped analyze clean. dev 통합 UAT(F1-F8) 는 사용자 대기.**

## Performance

- **Duration:** ~9 min (code tasks; human UAT deferred)
- **Started:** 2026-07-11T14:19:18Z
- **Completed:** 2026-07-11T14:28:17Z
- **Tasks:** 2 code + 1 human-verify checkpoint (pending)
- **Files:** 10 (7 created + 3 modified)

## Accomplishments
- **attendance data 계층** — `FichajeQr{s,b,d,t}` + `PunchResult{action, at, branchName, todayWorkedSeconds, storeId, storeName}` dto, `attendance_repository.punch()` = Dio POST /attendance/punch(백엔드 에러코드 ApiException.code 보존), `punchControllerProvider`(성공 in/out 후 scope 무효화).
- **fichaje 스캐너** — qr_scanner_sheet 클론(ConsumerStatefulWidget). 순수 함수 `parseFichajeDeeplink('/m/fichaje?s=&b=&d=&t=')`(s/b int·d/t 필수, 하나라도 없으면 null). `_onDetect` → punch → 성공 시 `/fichaje/result` push, 실패 시 `fichajeErrorCopy(code)` es-AR 토스트 후 재스캔. gold 뷰파인더 + "Escaneá el QR de fichaje".
- **결과 화면** — role 분기: `in`→초록 "Entrada registrada HH:mm", `out`→"Salida registrada HH:mm · Hoy Xh Ym"(todayWorkedSeconds 포맷), `store_authorized`→"Tienda {name} habilitada" + Ver catálogo CTA.
- **홈 출근 게이트** — `clockedIn` 을 scope user 에서 읽어: false 면 "Fichá tu entrada para empezar" 패널 + 단일 fichaje 버튼, 작업 버튼(Buscar/Ver carrito) 잠금(Opacity 0.45 + onTap null); true 면 정상 3버튼 + "Fichar salida" 어포던스. punch 후 scope 무효화 → 자동 재게이트.
- **revendedor 매장권 프롬프트** — `revendedor_home.dart` 신규: "Escaneá el QR de la tienda para habilitar" + "Escanear QR de la tienda" 버튼 → showFichajeScannerSheet. store_authorized 결과가 카탈로그 개방(Phase 24 완전 강제 대기).
- **MobileUser** 에 `clockedIn`(bool, default false) + `openSince`(DateTime?) — /mobile/me 필드 파싱.
- **라우트** `/fichaje`(진입점, 시트 자동 오픈) + `/fichaje/result` 등록.

## must_haves Truths — Status

| Truth | Status | Evidence |
|-------|--------|----------|
| vendedor 홈 fichaje 진입 → 스캔 → punch → entrada/salida 카피 (criterion 2) | 코드 완료 · UAT 대기 | fichaje_scanner_sheet punch → result_screen in/out; F2 pending |
| clockedIn=false 면 작업 잠금 + "Fichá tu entrada", clock-in 후 해제 (2b) | 코드 완료 · UAT 대기 | home_screen _ClockInGate/_WorkActions; F2b pending |
| 타매장 QR → "QR de otra tienda", 어제/위조 → "Pedí el QR de hoy" (3,4) | 코드 완료 · UAT 대기 | fichajeErrorCopy(QR_OTHER_STORE/QR_EXPIRED); 백엔드 판정 F3/F4 pending |
| revendedor 미승인 차단 + 프롬프트, store_authorized 시 카탈로그 (7) | 코드 완료 · UAT 대기 | revendedor_home 프롬프트 + result store_authorized→/catalog; F7 pending |

## Verification Results (honest)

- `flutter test test/fichaje_deeplink_test.dart` → **13/13 passed** (유효 /m/fichaje 파싱, /m/stock·오형식·파라미터 누락·비숫자·빈값 → null, 에러코드 매핑) ✅
- `flutter analyze` (attendance/home/revendedor/auth/router/test) → **No issues found!** ✅
- Contract greps: fichaje_scanner `/m/fichaje`✓ / attendance_repository `/attendance/punch`✓ / home_screen `clockedIn`✓ `Fichá tu entrada`✓ / revendedor_home `habilitar`✓
- **환경:** Flutter 3.41.2 stable / Dart 3.11.0.
- **전체 앱 analyze:** 1건 error 남음 — `test/widget_test.dart:16 MyApp isn't a class`. **pre-existing 스캐폴드 cruft**(main.dart 루트는 `MobileSalesApp`, 이 error 는 무관 커밋 2348463 소산, 본 플랜 미변경). deferred-items.md 기록. 본 플랜 신규 issue 0.

## Deviations from Plan

### Auto-fixed (Rules 1-3)

**1. [Rule 1 - Bug] revendedor_home const-false 분기 dead_code**
- **Found during:** Task 2
- **Issue:** `storeAuthorized ? SizedBox.shrink() : _StoreAuthPrompt` 에서 `const bool storeAuthorized = false` 라 true 분기가 dead_code(analyze warning).
- **Fix:** 이 wave 는 항상 미승인 프롬프트 렌더로 단순화 + Phase 24 승인 분기 주석. (Phase 24 가 승인 조회를 붙일 위치 명시.)
- **Files modified:** revendedor_home.dart
- **Verification:** flutter analyze lib/features/revendedor clean
- **Commit:** 1f9cfc1

**2. [Rule 3 - Blocking] /revendedor/stores 라우트 대상 교체 + StoreSelectorScreen import 제거**
- **Found during:** Task 2
- **Issue:** 플랜이 `revendedor_home.dart` 를 revendedor 랜딩으로 지목했으나 파일 부재(기존 랜딩은 store_selector_screen). RevendedorHome 신규 생성 + 라우트 교체하지 않으면 프롬프트 미노출. 교체 후 store_selector import 미사용 → unused_import lint.
- **Fix:** `/revendedor/stores` builder 를 RevendedorHome 로 교체, store_selector import 제거(파일은 orphan, wave4_placeholder 선례대로 무해 보존).
- **Files modified:** app_router.dart
- **Verification:** flutter analyze lib/router clean
- **Commit:** 1f9cfc1

**3. [Rule 1 - Bug] 내 테스트 파일 unused_import 제거**
- fichaje_deeplink_test.dart 가 attendance_dto 를 import 했으나 FichajeQr 타입이 추론되어 미사용 → 제거.
- **Commit:** 1f9cfc1

**Total deviations:** 3 auto-fixed (2 bug + 1 blocking). **Impact:** scope creep 없음 — 전부 계획 파일 정합/lint 게이트 통과용. store_selector orphan 은 Wave4 placeholder 선례.

## Known Stubs
- **revendedor_home 매장 승인 상태** — 이 wave 는 서버에서 매장권을 조회하지 않고 항상 미승인 프롬프트를 렌더한다(Phase 24 게이트). store_authorized punch happy-path 는 /fichaje/result 가 카탈로그로 개방. 완전 강제(RequireStoreAuthGuard)는 Phase 24 revendedor 카탈로그와 함께 활성(스펙 L169, 37-06 SUMMARY Known Stubs 일치).
- **store_selector_screen.dart** — /revendedor/stores 가 RevendedorHome 로 이관되어 orphan(무해, wave4_placeholder 선례). 제거는 후속 정리로 연기.
- **QR 직행 hero/price(37-04 선행)** — 본 플랜 무관, 유지.

## Deferred / Out-of-scope
- **F1-F8 dev 통합 UAT (Task 3, blocking checkpoint)** — human-verify. 3표면(백엔드/POS 웹/Flutter) 통합, 실기기 + `ATTENDANCE_QR_SECRET` + 37-06 마이그레이션(2 테이블) 선행. **본 SUMMARY 는 passed 로 표시하지 않음** — 오케스트레이터가 사용자에게 제시하는 게이트. 상세 단계는 `37-HUMAN-UAT.md` Fichaje UAT 섹션(F1-F8, 전 항목 pending).
- **test/widget_test.dart MyApp error** — pre-existing 스캐폴드 cruft(무관), deferred-items.md 기록. 실 부팅 위젯 테스트 또는 삭제로 후속 해소.

## Next Phase Readiness
- vendedor fichaje(entrada/salida) + 출근 게이트가 실동작 부분 — 마이그레이션(37-06) + ATTENDANCE_QR_SECRET 설정 + dev 부팅 후 실기기 F1-F8 UAT 필요(샌드박스 DB/기기 미도달로 런타임 미검증).
- revendedor 매장권 완전 강제는 Phase 24 활성.
- Phase 37 코드 3표면(37-06 백엔드 / 37-07 웹 / 37-08 모바일) 완료 → F1-F8 승인 후 `/gsd-verify-work 37`.

## Self-Check: PASSED
- 7 created files 전부 디스크 확인.
- 2 task 커밋 확인(83c4d4c, 1f9cfc1).
- flutter test 13/13 green + scoped flutter analyze clean(재현 가능).

## Commits (parent repo, base b54d068)
- `83c4d4c` feat(37-08): attendance feature (dto/repo/provider) + fichaje scanner + result screen
- `1f9cfc1` feat(37-08): home clock-in gate (vendedor) + revendedor store-auth prompt

---
*Phase: 37-mobile-sales-shell*
*Completed: 2026-07-11*
