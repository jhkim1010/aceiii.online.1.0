---
phase: 17-portal-de-talleres-aviso
plan: 03
subsystem: mobile-app
tags: [flutter, riverpod, dio, go_router, flutter_secure_storage, jwt, vendor-portal]

# Dependency graph
requires:
  - phase: 17-01
    provides: Backend vendor-portal API endpoints (POST /vendor-portal/auth/login, GET /vendor-portal/auth/me)

provides:
  - Flutter app talleres-vendor-app/ with full project structure
  - Riverpod 3.x auth state management (authNotifierProvider, selectedStoreIndexProvider)
  - Dio HTTP client with JWT auto-injection interceptor
  - flutter_secure_storage wrapper for Keychain/Keystore token storage
  - Phone + 4-digit PIN login screen with form validation
  - go_router with auth redirect guard (/login → /home)
  - Multi-store bottom tab bar (shown only when stores > 1)
  - Home screen shell with placeholder feature list

affects:
  - 17-04 (envios/recepciones feature screens plug into HomeScreen)
  - 17-05 (notifications feature uses authNotifierProvider + currentStoreProvider)

# Tech tracking
tech-stack:
  added:
    - flutter 3.41.2 / dart 3.11.0
    - flutter_riverpod 3.3.1 (Riverpod 3.x — uses Notifier/AsyncNotifier, no StateProvider)
    - hooks_riverpod 3.3.1
    - go_router 17.2.0
    - dio 5.9.2
    - flutter_secure_storage 10.0.0
    - shared_preferences 2.5.5
    - intl 0.20.2
  patterns:
    - AsyncNotifier for async state (auth) — Riverpod 3.x pattern
    - Notifier for sync state (selectedStoreIndex) — replaces deprecated StateProvider
    - Provider<GoRouter> watches authNotifierProvider for reactive redirects
    - DioClient wraps Dio instance; interceptor reads 'vendor_token' from secure storage
    - dart-define=BASE_URL for environment injection (localhost default)

key-files:
  created:
    - talleres-vendor-app/pubspec.yaml
    - talleres-vendor-app/lib/main.dart
    - talleres-vendor-app/lib/core/config/api_config.dart
    - talleres-vendor-app/lib/core/network/dio_client.dart
    - talleres-vendor-app/lib/core/network/api_exception.dart
    - talleres-vendor-app/lib/core/storage/secure_storage.dart
    - talleres-vendor-app/lib/shared/models/store_info.dart
    - talleres-vendor-app/lib/features/auth/data/auth_dto.dart
    - talleres-vendor-app/lib/features/auth/data/auth_repository.dart
    - talleres-vendor-app/lib/features/auth/providers/auth_provider.dart
    - talleres-vendor-app/lib/features/auth/views/login_screen.dart
    - talleres-vendor-app/lib/shared/widgets/store_tab_bar.dart
    - talleres-vendor-app/lib/router/app_router.dart
    - talleres-vendor-app/lib/features/home/views/home_screen.dart
  modified:
    - talleres-vendor-app/test/widget_test.dart (updated to use TalleresVendorApp)

key-decisions:
  - "Riverpod 3.x: StateProvider removed — use NotifierProvider<Notifier, T> for selectedStoreIndex"
  - "GoRouter provider re-instantiates when authNotifierProvider changes — reactive redirect without listenable"
  - "StoreTabBar returns SizedBox.shrink() when stores <= 1, keeping single-store vendors unaffected"
  - "401 handling delegated to auth_provider.build() — on startup, failed getMe() clears storage and returns null"
  - "dart-define=BASE_URL pattern allows per-environment builds without code changes"

patterns-established:
  - "AsyncNotifier pattern: build() restores persisted state; login/logout mutate state via AsyncValue.guard"
  - "Secure token storage: 'vendor_token' and 'vendor_phone' keys in flutter_secure_storage (OS Keychain/Keystore)"
  - "DioClient interceptor: reads token on each request (not cached), ensuring logout invalidation"

requirements-completed: [VP-01, VP-02]

# Metrics
duration: 35min
completed: 2026-04-13
---

# Phase 17 Plan 03: Flutter App Skeleton Summary

**Flutter talleres-vendor-app created from scratch with Riverpod 3.x auth flow, Dio JWT interceptor, secure token storage, and multi-store tab shell — app analyzes clean with no issues.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-04-13T00:00:00Z
- **Completed:** 2026-04-13
- **Tasks:** 2 (executed as 1 combined commit due to interdependent files)
- **Files modified:** 15 lib/ files + 144 total project files

## Accomplishments

- Flutter project `talleres-vendor-app` created with `com.coolsistema` org and all required dependencies
- Complete auth flow: login screen (phone + 4-digit PIN) → secure JWT storage → home screen with store tabs
- go_router auth guard reactive to Riverpod auth state — unauthenticated routes redirect to /login automatically
- Riverpod 3.x compatibility fix: replaced deprecated `StateProvider` with `NotifierProvider<SelectedStoreIndexNotifier, int>`
- `flutter analyze` passes with zero issues

## Task Commits

1. **Task 1 + Task 2: Flutter project creation + core infrastructure + auth flow + router** - `8f46b56` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `talleres-vendor-app/pubspec.yaml` — Flutter project config with all 7 dependencies
- `talleres-vendor-app/lib/main.dart` — ProviderScope + TalleresVendorApp entry point
- `talleres-vendor-app/lib/core/config/api_config.dart` — BASE_URL via dart-define, localhost default
- `talleres-vendor-app/lib/core/network/dio_client.dart` — Dio + JWT Authorization Bearer interceptor
- `talleres-vendor-app/lib/core/network/api_exception.dart` — Structured HTTP error model
- `talleres-vendor-app/lib/core/storage/secure_storage.dart` — FlutterSecureStorage wrapper (Keychain/Keystore)
- `talleres-vendor-app/lib/shared/models/store_info.dart` — Vendor store model with fromJson factory
- `talleres-vendor-app/lib/features/auth/data/auth_dto.dart` — AuthState model with fromLoginResponse
- `talleres-vendor-app/lib/features/auth/data/auth_repository.dart` — POST /vendor-portal/auth/login + GET /me
- `talleres-vendor-app/lib/features/auth/providers/auth_provider.dart` — authNotifierProvider + selectedStoreIndexProvider + currentStoreProvider
- `talleres-vendor-app/lib/features/auth/views/login_screen.dart` — Phone + 4-digit PIN form with validation
- `talleres-vendor-app/lib/shared/widgets/store_tab_bar.dart` — BottomNavigationBar hidden for single-store vendors
- `talleres-vendor-app/lib/router/app_router.dart` — GoRouter with /login and /home routes + auth redirect
- `talleres-vendor-app/lib/features/home/views/home_screen.dart` — Home shell with logout + StoreTabBar
- `talleres-vendor-app/test/widget_test.dart` — Updated smoke test for TalleresVendorApp

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Riverpod 3.x removed StateProvider**
- **Found during:** Task 2 (flutter analyze)
- **Issue:** Plan used `StateProvider<int>` which was removed in Riverpod 3.x (installed: 3.3.1)
- **Fix:** Replaced with `NotifierProvider<SelectedStoreIndexNotifier, int>` + `SelectedStoreIndexNotifier extends Notifier<int>` class; updated `store_tab_bar.dart` to call `setIndex(i)` instead of `.notifier.state = i`
- **Files modified:** `auth_provider.dart`, `store_tab_bar.dart`
- **Commit:** 8f46b56

**2. [Rule 1 - Bug] GoRouter builder used `__` double underscore (unnecessary_underscores lint)**
- **Found during:** Task 2 (flutter analyze info)
- **Fix:** Changed `(_, __)` to `(context, state)` in GoRoute builders
- **Files modified:** `app_router.dart`
- **Commit:** 8f46b56

**3. [Rule 1 - Bug] widget_test.dart referenced deleted MyApp class**
- **Found during:** Task 2 (flutter analyze)
- **Fix:** Rewrote test to use `TalleresVendorApp` inside `ProviderScope`
- **Files modified:** `test/widget_test.dart`
- **Commit:** 8f46b56

## Known Stubs

- `home_screen.dart`: Envíos, Recepciones, Notificaciones, Liquidaciones shown as placeholder text only — intentional; these are Phase 17 plans 04-07 scope

## Threat Flags

No new unplanned network endpoints or auth paths introduced. All surfaces are within the threat model (T-17-09: flutter_secure_storage mitigated; T-17-10: 401 clears token via `build()` restart on token failure).

## Self-Check: PASSED

- `talleres-vendor-app/lib/main.dart` — FOUND
- `talleres-vendor-app/lib/features/auth/providers/auth_provider.dart` — FOUND
- `talleres-vendor-app/lib/features/auth/views/login_screen.dart` — FOUND
- `talleres-vendor-app/lib/router/app_router.dart` — FOUND
- Commit 8f46b56 — FOUND
