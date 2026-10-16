---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 02
subsystem: mobile
tags: [flutter, android, ios, submodule, ci]
requires: []
provides:
  - "colibri/ submodule (private repo jhkim1010/colibri), compiling Flutter shell Android + iOS"
  - "core: api_config, secure_storage, device_fingerprint, money, AppTheme (navy/gold/MP cyan)"
  - ".github/workflows/build-colibri.yml"
affects: [111-10, 111-11, 111-12, 111-13, 111-16, 111-19, 111-20]
tech-stack:
  added: [share_plus, path_provider, shared_preferences, uuid, package_info_plus]
  patterns: ["tokens only in flutter_secure_storage", "BASE_URL via dart-define; release=https prod, debug=localhost"]
key-files:
  created: [colibri/pubspec.yaml, colibri/lib/main.dart, colibri/lib/core/**, colibri/test/money_test.dart, .github/workflows/build-colibri.yml]
  modified: [.gitmodules]
key-decisions:
  - "Names (Task 1, answered by user: «승인, Colibri로 진행해»): repo jhkim1010/colibri (private), folder colibri/, bundle id / applicationId / namespace com.ventago.colibri, display name Colibri. ALL later plans: read ventago-movil/ as colibri/, build-ventago-movil.yml as build-colibri.yml, workflow tags colibri-v*."
  - "iOS deployment target 15.0 (Xcode 27 rejects 13.0)"
duration: ~25min
completed: 2026-10-16
---

# Phase 111 Plan 02: Colibri app scaffold Summary

Private repo jhkim1010/colibri mounted as submodule `colibri/`, with a Flutter Android+iOS shell, core pieces copied from mobile-sales-app, Ventago theme, optional-signing gradle config and a CI workflow.

## Task commits
- Task 1: decision resolved by user (no commit).
- Task 2: colibri baa4809; root 11698b6 (.gitmodules + gitlink)
- Task 3: colibri c1e47bd; root gitlink commit
- Task 4: colibri cc33a38; root e51db11 (workflow + gitlink)
- iOS target fix: colibri 6fea011; root gitlink commit (with this SUMMARY)

Only the new colibri repo was pushed. The monorepo root, api-ventago and ventago-app were NOT pushed.

## Verification
- `flutter analyze`: No issues found; `flutter test`: 5 tests pass (4 money + home widget).
- `flutter build apk --debug` OK (~105 s). `flutter build ios --debug --no-codesign` OK (~24 s) after the deployment-target fix.
- Workflow YAML parses (checked with ruby; python yaml module not installed). `grep 62.72.7.245 lib` empty. Repo is PRIVATE.

## Deviations from Plan
1. [Rule 3] flutter create produced `com.ventago.colibri.colibri` (org + name); normalized to `com.ventago.colibri` in gradle, pbxproj, MainActivity package/dir.
2. [Rule 3] iOS build failed with deployment target 13.0 (Xcode 27 supports 15.0+); set to 15.0.
3. money format is `$83.000` (copied mobile-sales-app behavior, no space) rather than `$ 83.000` in the plan text; tests assert the copied format.
4. Debug-only `usesCleartextTraffic` in `android/app/src/debug/AndroidManifest.xml` for localhost; release has none.
5. Secure storage keys trimmed to mobile token / session token / reseller token (dropped lastBranchId: branch self-selection not copied).
6. Workflow also runs `flutter test` and has a workflow_dispatch trigger as the plan said; GitHub Actions is currently not running due to billing, so local analyze/test/build is the gate.

## Known Stubs
`TemporaryHome` in colibri/lib/main.dart is an intentional placeholder; Plans 10/16 replace it with the router.

## Auth gates
None. Android release signing (key.properties) and Apple signing are left to Plan 20.

## Self-Check: PASSED
