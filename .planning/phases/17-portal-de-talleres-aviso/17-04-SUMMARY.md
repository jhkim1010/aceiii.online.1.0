---
phase: 17-portal-de-talleres-aviso
plan: "04"
subsystem: talleres-vendor-app (Flutter)
tags: [flutter, riverpod, envios, recepciones, vendor-portal]
dependency_graph:
  requires: [17-02, 17-03]
  provides: [envio-list-screen, envio-detail-screen, recepcion-dialog, 4-tab-home]
  affects: [talleres-vendor-app]
tech_stack:
  added: []
  patterns:
    - FutureProvider.family.autoDispose (envioListProvider keyed by storeId)
    - AsyncNotifier for createRecepcionProvider (Riverpod 3.x)
    - Notifier for _BottomTabNotifier (replaces removed StateProvider)
    - go_router extra param to pass EnvioDto to detail screen
key_files:
  created:
    - talleres-vendor-app/lib/features/envios/data/envio_dto.dart
    - talleres-vendor-app/lib/features/envios/data/envio_repository.dart
    - talleres-vendor-app/lib/features/envios/providers/envio_provider.dart
    - talleres-vendor-app/lib/features/envios/views/envios_screen.dart
    - talleres-vendor-app/lib/features/envios/views/envio_detail_screen.dart
    - talleres-vendor-app/lib/features/recepciones/data/recepcion_repository.dart
    - talleres-vendor-app/lib/features/recepciones/providers/recepcion_provider.dart
    - talleres-vendor-app/lib/features/recepciones/views/recepcion_dialog.dart
    - talleres-vendor-app/lib/shared/widgets/status_chip.dart
  modified:
    - talleres-vendor-app/lib/router/app_router.dart
    - talleres-vendor-app/lib/features/home/views/home_screen.dart
decisions:
  - "Used Notifier instead of StateProvider for bottom tab index (StateProvider removed in Riverpod 3.x)"
  - "Pass EnvioDto via go_router extra param to avoid redundant API call in detail screen"
  - "AsyncNotifier pattern for createRecepcionProvider so error state is managed inside notifier"
  - "FutureProvider.family.autoDispose for envioListProvider — scoped per storeId, disposed on screen exit"
metrics:
  duration: ~25 minutes
  completed: 2026-04-13
  tasks_completed: 2
  files_created: 9
  files_modified: 2
---

# Phase 17 Plan 04: Envios + Recepciones Feature Summary

**One-liner:** Flutter envio list/detail screens + recepcion confirmation dialog with Riverpod 3.x AsyncNotifier, wired into 4-tab home and go_router.

## Tasks Completed

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | Envio DTOs + repository + provider + list screen + detail screen + StatusChip | Done | 9b94335 |
| 2 | Recepcion dialog + home navigation integration + router update | Done | 9b94335 |

## What Was Built

### Task 1: Envio Feature Layer

**`envio_dto.dart`** — `EnvioDto` + `RecepcionDto` with `fromJson` constructors. Handles both flat and nested `lote`/`etapa` object shapes from the API response. Null-safe throughout.

**`envio_repository.dart`** — `EnvioRepository` wrapping `DioClient`. `fetchEnvios(storeId)` calls `GET /vendor-portal/envios` with `storeId`, `page`, `pageSize` query params. Handles both `{ rows: [...] }` and bare list response shapes. Converts `DioException` → `Exception` with readable message.

**`envio_provider.dart`** — `envioListProvider` as `FutureProvider.family.autoDispose<List<EnvioDto>, int>` keyed by `storeId`. Auto-disposes when screen exits.

**`status_chip.dart`** — `StatusChip` widget mapping status strings to colored `Chip` badges: PENDING→orange, PARTIAL→blue, COMPLETED→green, CANCELLED/unknown→grey, OPEN→orange, CLOSED→green.

**`envios_screen.dart`** — `ConsumerWidget` with `RefreshIndicator` (pull-to-refresh via `ref.invalidate`). Shows loading spinner, error state with retry button, empty state illustration, or `ListView.builder` of `_EnvioCard`. Each card shows lote name + `StatusChip`, etapa, quantity/pendingQuantity, envioDate, and D-day due date with color coding (red=overdue, orange=≤3d, green=ok). Taps navigate to `/envio/:id` with `EnvioDto` as `extra`.

**`envio_detail_screen.dart`** — Shows full envio info card (`_InfoCard`) with all fields, then `_RecepcionesSection` listing recepciones history (date, received/rejected qty, notes). `FloatingActionButton` "Confirmar recepción" opens `RecepcionDialog` via `showModalBottomSheet`. FAB hidden for COMPLETED/CANCELLED status. On success, invalidates `envioListProvider`.

### Task 2: Recepcion Feature + Navigation

**`recepcion_repository.dart`** — `RecepcionRepository` calling `POST /vendor-portal/recepciones` with `envioId`, `receivedQuantity`, `rejectedQuantity`, optional `notes`. Returns raw response map.

**`recepcion_provider.dart`** — `CreateRecepcionNotifier extends AsyncNotifier<void>` with `create(RecepcionParams)` method. After success, calls `ref.invalidate(envioListProvider)` to refresh all store envio lists. Uses Dart record typedef `RecepcionParams` for named params.

**`recepcion_dialog.dart`** — `ConsumerStatefulWidget` bottom sheet with form validation:
- `receivedQuantity`: required, >0
- `rejectedQuantity`: optional, default 0
- T-17-11 validation: `received + rejected <= envio.pendingQuantity`
- `notes`: optional multiline
- Shows loading state on submit button
- `ref.listen` on `createRecepcionProvider`: success → green SnackBar + `Navigator.pop`; error → red SnackBar with message
- Keyboard-aware via `MediaQuery.viewInsets.bottom` padding

**`home_screen.dart`** — Replaced placeholder body with 4-tab `NavigationBar` + `IndexedStack`:
- Tab 0: `EnviosScreen` (implemented)
- Tab 1: Notificaciones placeholder
- Tab 2: Liquidaciones placeholder
- Tab 3: Profile section with logout button
- AppBar title shows `_StoreDropdown` (with `DropdownButton`) when vendor has ≥2 stores, otherwise store name text
- `_BottomTabNotifier extends Notifier<int>` replaces removed `StateProvider`

**`app_router.dart`** — Added `/envio/:id` route. Parses `envioId` from path param, receives `EnvioDto` via `state.extra` for zero-latency detail display.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] StateProvider removed in Riverpod 3.x**
- **Found during:** Task 2 (home_screen bottom tab index)
- **Issue:** `StateProvider` was removed in Riverpod 3.x (pubspec has `flutter_riverpod: ^3.3.1`)
- **Fix:** Replaced with `_BottomTabNotifier extends Notifier<int>` + `NotifierProvider`
- **Files modified:** `home_screen.dart`

**2. [Rule 1 - Bug] AutoDisposeAsyncNotifier required dart:async import**
- **Found during:** Task 2 (recepcion_provider.dart)
- **Issue:** `FutureOr` requires `import 'dart:async'`; also `AutoDisposeAsyncNotifierProvider` is not a standalone function in Riverpod 3.x
- **Fix:** Added `dart:async` import; used `AsyncNotifier<void>` + `AsyncNotifierProvider`
- **Files modified:** `recepcion_provider.dart`

## Known Stubs

| File | Description |
|------|-------------|
| `home_screen.dart` — Notificaciones tab | Placeholder `_PlaceholderSection` — no data wired. Future plan. |
| `home_screen.dart` — Liquidaciones tab | Placeholder `_PlaceholderSection` — no data wired. Future plan. |

These stubs do not block the plan's goal (envio + recepcion workflow is fully functional).

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| Input validation | `recepcion_dialog.dart` | T-17-11 mitigated: `receivedQty + rejectedQty <= pendingQuantity` client-side check applied |

No new unplanned network endpoints or auth paths introduced.

## Self-Check: PASSED

Files verified present:
- talleres-vendor-app/lib/features/envios/data/envio_dto.dart — FOUND
- talleres-vendor-app/lib/features/envios/data/envio_repository.dart — FOUND
- talleres-vendor-app/lib/features/envios/providers/envio_provider.dart — FOUND
- talleres-vendor-app/lib/features/envios/views/envios_screen.dart — FOUND
- talleres-vendor-app/lib/features/envios/views/envio_detail_screen.dart — FOUND
- talleres-vendor-app/lib/features/recepciones/data/recepcion_repository.dart — FOUND
- talleres-vendor-app/lib/features/recepciones/providers/recepcion_provider.dart — FOUND
- talleres-vendor-app/lib/features/recepciones/views/recepcion_dialog.dart — FOUND
- talleres-vendor-app/lib/shared/widgets/status_chip.dart — FOUND
- talleres-vendor-app/lib/router/app_router.dart — FOUND (modified)
- talleres-vendor-app/lib/features/home/views/home_screen.dart — FOUND (modified)

Commit verified: 9b94335 — FOUND in git log

`flutter analyze`: No issues found
