---
phase: 37-mobile-sales-shell
plan: 03
subsystem: mobile-app-shell
tags: [mobile, flutter, riverpod, dio, go-router, auth, scope, secure-storage]
requires:
  - 37-01 (POST /mobile/auth/login, GET /mobile/me, x-mobile-session-token, 401 MOBILE_SESSION_EXPIRED)
  - 37-02 (GET /mobile/catalog, /mobile/stock/:id, POST /mobile/sales — consumed in Wave 4)
  - talleres-vendor-app Phase 17 infra (Dio + Riverpod + flutter_secure_storage + go_router)
provides:
  - mobile-sales-app Flutter 프로젝트 (org com.ventago, name mobile_sales_app)
  - DioClient (JWT + x-mobile-session-token 주입 + 401 MOBILE_SESSION_EXPIRED 인터셉터, MOBILE-C-07)
  - SecureStorageService (StorageKeys.mobile_token — 토큰은 secure storage 전용, T-37-12)
  - ScopeProvider (resolveScope: /mobile/me → BranchScope/MultiStoreScope)
  - PIN 로그인 화면(S0/UI-D3) + Sucursal 셀렉터(scopeBranchIds only, D-10)
  - go_router (scope 기반 redirect + 세션만료 refreshListenable) + Wave 4 라우트 스텁
  - Ventago 다크네이비+골드 테마(AppTheme, UI-SPEC §2)
affects:
  - (parent repo) 신규 mobile-sales-app/ 디렉토리 — npm workspaces 미등록(talleres/despacho 와 동일 패턴)
tech-stack:
  added:
    - flutter_riverpod ^3.3.1 / hooks_riverpod ^3.3.1
    - go_router ^17.2.0
    - dio ^5.9.2
    - flutter_secure_storage ^10.0.0
    - intl ^0.20.2
    - mobile_scanner ^7.2.0
    - crypto ^3.0.7 (device fingerprint SHA-256)
  patterns:
    - interceptor→UI bridge via SessionExpiredSignal(ChangeNotifier) + rootScaffoldMessengerKey
    - pure resolveScope(user) 함수로 scope 해석 분리 → 네트워크 없이 단위 테스트
    - scope 는 표시/락 전용 클라이언트 상태, 백엔드 MobileScopeGuard 가 권위(D-02/T-37-15)
key-files:
  created:
    - mobile-sales-app/lib/core/config/api_config.dart
    - mobile-sales-app/lib/core/storage/secure_storage.dart
    - mobile-sales-app/lib/core/network/api_exception.dart
    - mobile-sales-app/lib/core/network/session_signal.dart
    - mobile-sales-app/lib/core/network/dio_client.dart
    - mobile-sales-app/lib/core/theme/app_theme.dart
    - mobile-sales-app/lib/core/device/device_fingerprint.dart
    - mobile-sales-app/lib/features/auth/data/auth_dto.dart
    - mobile-sales-app/lib/features/auth/data/auth_repository.dart
    - mobile-sales-app/lib/features/auth/providers/scope_provider.dart
    - mobile-sales-app/lib/features/auth/views/login_screen.dart
    - mobile-sales-app/lib/features/auth/widgets/sucursal_selector.dart
    - mobile-sales-app/lib/features/home/views/home_screen.dart
    - mobile-sales-app/lib/shared/widgets/wave4_placeholder.dart
    - mobile-sales-app/lib/router/app_router.dart
    - mobile-sales-app/lib/main.dart
    - mobile-sales-app/test/scope_provider_test.dart
    - mobile-sales-app/pubspec.yaml
    - (+ 73 flutter-create scaffold 파일: android/ios/gitignore/metadata 등)
  modified: []
decisions:
  - "package.json 미변경: talleres-vendor-app/despacho-app 처럼 Flutter 디렉토리는 npm workspaces 에 등록하지 않는다. (검증: 임시로 추가해 npm install --ignore-scripts 실행 → exit 0 이지만 package.json 없는 dir 을 npm 이 조용히 무시해 심링크 미생성 = 기능적 이득 0. 반면 엄격한 npm/CI 환경에선 오류 위험 + 3개 Flutter 앱 중 1개만 등록되는 불일치. 기존 레포 컨벤션 준수가 옳음. Rule 3.)"
  - "세션만료 인터셉터→UI 브리지: dio onError 는 BuildContext 가 없으므로 SessionExpiredSignal(ChangeNotifier, go_router refreshListenable) + 전역 rootScaffoldMessengerKey 로 /login redirect + 토스트를 구현(MOBILE-C-07)."
  - "device fingerprint: 모바일은 안정 traits 가 제한적이라 최초 1회 생성한 128bit salt 를 secure storage 에 영속화 + 플랫폼 정보 결합 SHA-256. crypto 패키지 추가."
  - "Sucursal 셀렉터는 로그인 후 scope 확정 전엔 안내 placeholder, 확정 후 scopeBranchIds 로만 노출. 1개면 lock(D-10). 실제 다지점 선택 UX 는 로그인 응답 이후 흐름으로 Wave 4 와 연계."
metrics:
  tasks: 3
  files-created: 18 (+73 scaffold)
  files-modified: 0
  tests: 4 passed
  duration: ~45m
  completed: 2026-07-08
---

# Phase 37 Plan 03: Mobile Sales App Shell Summary

talleres-vendor-app(Phase 17) 인프라를 클론해 `mobile-sales-app/` Flutter 앱을
부트스트랩하고, 모든 모드(vendedor Wave 4 / revendedor Wave 5)가 공유할 셸을 구축했다.
Dio 클라이언트가 JWT + `x-mobile-session-token` 을 함께 주입하고 401 `MOBILE_SESSION_EXPIRED`
를 잡아 토큰 삭제 + `/login` 리다이렉트 + 토스트를 수행한다(Phase 17 의 pass-through 를
넘어선 MOBILE-C-07 신규). Riverpod `ScopeProvider` 는 `/mobile/me` 응답으로 BranchScope/
MultiStoreScope 를 결정하고, PIN 로그인 화면(UI-D3)과 Sucursal 셀렉터(D-10)를 제공한다.

## What Was Built

- **Flutter 프로젝트** — `flutter create --org com.ventago --project-name mobile_sales_app`
  (android+ios). deps: flutter_riverpod/hooks_riverpod ^3.3.1, go_router ^17.2.0, dio ^5.9.2,
  flutter_secure_storage ^10.0.0, intl ^0.20.2, mobile_scanner ^7.2.0, crypto ^3.0.7.
  **firebase_messaging(FCM) 미포함 — 계획대로 연기.**
- **core/network/dio_client.dart** — onRequest: `Authorization: Bearer <mobile_token>` +
  `x-mobile-session-token: <mobile_session_token>` 주입. onError: 401 + code∈{MOBILE_SESSION_EXPIRED,
  SESSION_EXPIRED, INVALID_MOBILE_SESSION} → `deleteAll()` + SessionExpiredSignal.trigger() + 토스트.
- **core/network/session_signal.dart** — `SessionExpiredSignal(ChangeNotifier)` +
  전역 `rootScaffoldMessengerKey`. 인터셉터(비 UI)에서 라우터/토스트로 전파하는 브리지.
- **core/storage/secure_storage.dart** — `StorageKeys.mobile_token` / `mobile_session_token` /
  `last_branch_id`. SharedPreferences 미사용(T-37-12).
- **core/device/device_fingerprint.dart** — 설치 salt 영속 + 플랫폼 결합 SHA-256.
- **core/theme/app_theme.dart** — UI-SPEC §2 토큰(navy/gold/ink/…), gold CTA 스타일, tabular figures.
- **features/auth** — dto(MobileLoginRequest/MobileUser/MobileLoginResponse), repository(login→
  POST /mobile/auth/login, getMe→GET /mobile/me), scope_provider(`resolveScope` 순수함수 +
  ScopeNotifier), login_screen(S0), sucursal_selector(D-10).
- **router/app_router.dart** — scope 기반 redirect + 세션만료 refreshListenable + Wave 4 스텁
  (/catalog, /product/:id, /comanda, /done). **home/views/home_screen.dart**(S1 랜딩).
- **main.dart** — ProviderScope + AppTheme + portrait 고정 + rootScaffoldMessengerKey 연결.
- **test/scope_provider_test.dart** — resolveScope 4케이스.

## must_haves Truths — Status

| Truth | Status | Evidence |
|-------|--------|----------|
| talleres-vendor-app 인프라 클론 + Ventago dark-navy+gold 테마 (criterion 10) | ✅ | 동일 core 레이아웃, AppTheme navy/gold 토큰, `flutter analyze` 0 issues |
| 로그인 = Usuario + PIN(숫자 keypad) + Sucursal 셀렉터(user_branches only, 1개면 lock, D-10/UI-D3) | ✅ | login_screen(numberWithOptions+obscure+digitsOnly), sucursal_selector(`branchIds.length<=1 → lock`) |
| ScopeProvider /mobile/me → BranchScope 자동 설정 + secure storage 영속 (criterion 10) | ✅ | scope_provider `resolveScope`/`ScopeNotifier.build`/`_persistScope`; test 4/4 |
| 401 MOBILE_SESSION_EXPIRED → 토큰삭제 + /login redirect + 토스트 (criterion 12, MOBILE-C-07) | ✅ | dio_client `_handleSessionExpired`(deleteAll+signal+toast) + router refreshListenable |
| JWT 는 flutter_secure_storage 에만 저장, SharedPreferences 금지 (T-37-12) | ✅ | secure_storage(FlutterSecureStorage), pubspec 에 shared_preferences 실제 dep 0 |

## Verification Results (honest)

- `flutter analyze`(전체 앱) → **No issues found!** (0 errors/0 warnings) ✅
- `flutter test test/scope_provider_test.dart` → **4/4 passed** ✅
  (vendedor→BranchScope([5]), revendedor→MultiStoreScope([6,8]), unknown+branch→fallback, empty→Unauth)
- `flutter pub get` → 성공 (67 deps 해결) ✅
- Task1 게이트 재현: `grep mobile_token secure_storage` ✓ + `grep MOBILE_SESSION_EXPIRED dio_client` ✓ +
  `! grep firebase_messaging pubspec.yaml` ✓ → **TASK1 GATE: OK** ✅
- `grep SharedPreferences|shared_preferences` → 실제 dep 0 (매치는 전부 "금지" 주석) ✅
- `grep x-mobile-session-token dio_client` → 3 hits(주석/주입 2회) ✅
- **환경:** Flutter 3.41.2 stable / Dart 3.11.0 (pubspec sdk ^3.11.0 정합), flutter=/Users/marcoskim/flutter/bin.

## Deviations from Plan

### Auto-fixed / Auto-added (Rules 1-3)

**1. [Rule 3 - Blocking] package.json 미변경 (계획 files_modified 의 package.json 제외)**
- **Found during:** Task 1 (workspaces 등록 시도)
- **Issue:** 계획은 root `package.json` `workspaces` 에 `mobile-sales-app` 추가를 지시하나,
  Flutter 디렉토리에는 package.json 이 없어 npm workspaces 등록이 부적절하다. 기존 Flutter 앱
  (talleres-vendor-app / despacho-app)도 workspaces·dev.sh·push-both.sh 어디에도 등록돼 있지 않다.
- **검증:** 임시로 `workspaces` 에 추가 후 `npm install --ignore-scripts` → **exit 0**(현 npm 10.8.2 는
  package.json 없는 dir 을 조용히 무시, 심링크 미생성). 즉 **기능적 이득 0**. 반면 엄격한 npm/CI
  버전에선 오류 위험 + 3개 Flutter 앱 중 1개만 등록되는 불일치.
- **Fix:** package.json/package-lock.json 원복(무변경). 기존 레포 컨벤션(Flutter 앱=parent repo
  plain 디렉토리) 준수. mobile-sales-app 은 parent repo 에 커밋되어 monorepo 에 포함됨.
- **Files modified:** 없음 (원복).

**2. [Rule 3 - Blocking] crypto 패키지 추가 (계획 미명시)**
- **Found during:** Task 2 (device fingerprint)
- **Issue:** 백엔드 login 계약이 `deviceFingerprint` 를 요구(mobile_sessions UPSERT 키). UI-SPEC 은
  "SHA-256 of stable device traits". Flutter 기본엔 SHA-256 이 없음.
- **Fix:** `crypto ^3.0.7` 추가 + DeviceFingerprintService(설치 salt 영속 + SHA-256).

**3. [Rule 3 - Blocking] session_signal.dart 신규 (계획 files_modified 외)**
- **Found during:** Task 1 (dio 401 처리)
- **Issue:** dio onError 는 BuildContext 가 없어 직접 라우팅/토스트 불가. MOBILE-C-07 구현에 브리지 필요.
- **Fix:** SessionExpiredSignal(ChangeNotifier, go_router refreshListenable) + rootScaffoldMessengerKey.

**4. [Rule 2 - Design] wave4_placeholder.dart 신규 (계획 files_modified 외)**
- 라우트 트리 스텁(/catalog, /product/:id, /comanda, /done)이 컴파일·네비게이션 되도록 공유 placeholder.
  Wave 4 에서 실제 화면으로 교체.

### Design notes

- **기본 test/widget_test.dart 삭제:** flutter create 가 생성한 스모크 테스트는 제거된 `MyApp` 을
  참조 → analyze/test 실패. Task 3 의 scope_provider_test.dart 로 대체.
- **Sucursal 셀렉터 UX:** 로그인 화면에서는 scope 확정 전이라 안내 placeholder 를 렌더. 실제
  다지점 선택은 로그인 응답(scopeBranchIds)이 확정된 이후 흐름으로 Wave 4 와 연계. 셀렉터 위젯
  자체는 scopeBranchIds only + length==1 lock 규칙을 이미 구현(재사용 가능).

## Known Stubs

- **Wave 4 판매 화면(/catalog, /product/:id, /comanda, /done)** — 의도적 스텁(Wave4Placeholder).
  Wave 4(37-04)에서 S2~S5 실제 화면으로 교체. 셸(Wave 3) 범위 밖으로 계획대로 지연.
- **revendedor 모드 화면** — MultiStoreScope 해석은 구현되어 있으나 UI 는 Wave 5(Phase 24 게이트)까지 스텁.

## Deferred / Out-of-scope (기록만)

- **실기기/에뮬레이터 dev 검증** (Wave 1 백엔드 기동 필요): PIN 로그인→/home 지점 lock 확인,
  2차 디바이스 로그인→1차 앱 /login 바운스+토스트. 계획 verification 의 Manual(dev) 항목 — 브라우저
  UAT 성격으로 별도 단계(37-04/오케스트레이터 게이트).
- **package-lock.json / .planning/STATE.md / ROADMAP.md** — 본 플랜에서 미변경(critical rule 준수).
  사전 존재하던 working-tree 수정(api-ventago/ventago-app 서브모듈, .gsd-snapshot 등)은 손대지 않음.

## Commits (parent repo, base aa4398d)

- `4df3984` feat(37-03): bootstrap mobile-sales-app Flutter shell — core/config/storage/network/theme
- `62d0221` feat(37-03): PIN auth + ScopeProvider + login screen + sucursal selector + go_router
- `d5c638d` test(37-03): ScopeProvider resolveScope unit test + analyze gate
- `c45b2b8` chore(37-03): drop literal push-package name from pubspec comment (keep FCM-absent gate green)

## Self-Check: PASSED

- 핵심 파일 8/8 존재 확인 (dio_client, scope_provider, login_screen, sucursal_selector,
  app_router, scope_provider_test, lib/main.dart, SUMMARY).
- 커밋 4/4 존재 확인 (4df3984, 62d0221, d5c638d, c45b2b8).
- `flutter analyze` 0 issues + `flutter test` 4/4 passed (재현 가능).
