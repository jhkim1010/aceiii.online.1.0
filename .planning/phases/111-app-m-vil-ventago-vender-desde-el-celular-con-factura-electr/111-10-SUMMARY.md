---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 10
subsystem: mobile
tags: [flutter, riverpod, dio, contracts, home-shell]
requires: ["111-02", "111-03", "111-04"]
provides:
  - "colibri core: DioClient, ApiError, online provider, LocalStore, pos_contracts.dart"
  - "AppPaths + venta/ingreso/reportes route registries"
  - "contextProvider (GET /mobile/pos/context) and HomeShell with status header"
affects: [111-11, 111-12, 111-13, 111-16, 111-19]
key-files:
  created:
    - colibri/lib/core/network/{dio_client,api_error,online_provider}.dart
    - colibri/lib/core/storage/local_store.dart
    - colibri/lib/core/contracts/pos_contracts.dart
    - colibri/lib/app/paths.dart
    - colibri/lib/features/{venta/venta_routes,ingreso/ingreso_routes,reportes/reportes_routes}.dart
    - colibri/lib/features/home/{context_provider,home_shell,mas_screen}.dart
    - colibri/test/{api_error_test,contracts_parse_test,home_shell_test}.dart
key-decisions:
  - "Paths use colibri/ (not ventago-movil/); app name Colibri."
  - "401/403 only emit a SessionSignal; storage and drafts are never wiped (differs from mobile-sales-app)."
  - "Offline = connectivity_plus AND last request not a connection failure; ApiError.offline is never a business answer."
  - "Unknown MP intent status parses to failed (never approved)."
  - "HomeShell takes currentPath/onNavigate callbacks (HomeShell.routed helper for go_router) so Plan 16 owns the router."
  - "Stock/Reportes tabs need permission AND a non-empty route registry (no dead-end tab)."
duration: ~25min
completed: 2026-10-16
---

# Phase 111 Plan 10: App foundation Summary

Colibri network/error layer, Dart mirrors of pos-contracts.ts (including Mercado Pago QR, fiscal opciones, branches), draft store, route constants and a home shell whose header always shows sucursal, caja abierta/cerrada, conexión and «N facturas sin emitir».

## Task commits (colibri submodule)
- Task 1: colibri 1667adf (network, contracts, local store, 19 tests)
- Task 2: colibri 67f5375 (paths, registries, context, shell, Más, 5 widget tests)
- colibri pushed to its private remote (deploys nothing). Monorepo root, api-ventago and ventago-app NOT pushed.

## Verification
`flutter analyze`: No issues found. `flutter test`: 29 tests pass. Acceptance greps: x-mobile-session-token present in dio_client; no token names in local_store; no sinEmitirHoy; no «de hoy» in features/home.

## Deviations from Plan
- [Rule 3] Paths colibri/ instead of ventago-movil/ (user decision).
- Plan said «Commit only, do NOT push»; the orchestrator override allows pushing the private colibri repo, so it was pushed.
- Cart bar in the Vender tab is minimal (Escanear + Carrito buttons); Plan 11 fills the body.

## Known Stubs
- `VenderTab` body text is a placeholder until Plan 11. `ingresoRoutes` / `reportesRoutes` are intentionally empty until Plan 12 (tabs hidden meanwhile).
- `sharedPreferencesProvider` throws unless overridden in main(); Plan 16 wires main/router/ProviderScope.

## Notes
STATE.md and ROADMAP.md left uncommitted per instructions.

## Self-Check: PASSED
