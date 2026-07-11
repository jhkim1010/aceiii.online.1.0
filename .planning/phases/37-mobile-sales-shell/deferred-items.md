# Phase 37 — Deferred Items

Out-of-scope discoveries logged during execution. Not fixed (unrelated to the current plan's task changes).

## 37-08 (mobile-sales-app fichaje)

- **`mobile-sales-app/test/widget_test.dart` — stale default scaffold test.**
  Pre-existing breakage: references `const MyApp()` which never existed in this app
  (`lib/main.dart` root widget is `MobileSalesApp`). Last touched by unrelated commit
  `2348463` (superadmin app stabilization), not by 37-08. Causes `flutter analyze`
  (full app) to report `creation_with_non_type: The name 'MyApp' isn't a class` and
  `flutter test` (full suite) to fail-compile on this file only.
  Fix: replace the default counter smoke test with a real `MobileSalesApp` boot test
  (needs ProviderScope + secure-storage/dio overrides) or delete the scaffold test.
  Out of scope for 37-08 (attendance) — the plan's scoped `flutter analyze`
  (attendance/home/revendedor/auth/router) is clean and `flutter test
  test/fichaje_deeplink_test.dart` is green.
