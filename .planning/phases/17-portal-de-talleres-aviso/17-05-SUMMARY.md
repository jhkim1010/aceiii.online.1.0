---
phase: 17-portal-de-talleres-aviso
plan: "05"
subsystem: talleres-vendor-app
tags: [flutter, riverpod, notifications, settlements, mobile]
dependency_graph:
  requires: [17-03, 17-04]
  provides: [notifications-feature, settlements-feature, home-badge]
  affects: [talleres-vendor-app]
tech_stack:
  added: []
  patterns:
    - Riverpod 3.x FutureProvider.family.autoDispose for data fetching
    - Riverpod 3.x Notifier (not StateProvider — removed in v3) for mutable state
    - Flutter Badge widget for unread count on NavigationDestination
    - intl DateFormat for Spanish locale relative time formatting
    - double.tryParse for safe JSON amount parsing
key_files:
  created:
    - talleres-vendor-app/lib/features/notifications/data/notification_dto.dart
    - talleres-vendor-app/lib/features/notifications/data/notification_repository.dart
    - talleres-vendor-app/lib/features/notifications/providers/notification_provider.dart
    - talleres-vendor-app/lib/features/notifications/views/notifications_screen.dart
    - talleres-vendor-app/lib/features/settlements/data/settlement_dto.dart
    - talleres-vendor-app/lib/features/settlements/data/settlement_repository.dart
    - talleres-vendor-app/lib/features/settlements/providers/settlement_provider.dart
    - talleres-vendor-app/lib/features/settlements/views/settlements_screen.dart
  modified:
    - talleres-vendor-app/lib/features/home/views/home_screen.dart
decisions:
  - Used Riverpod 3.x Notifier instead of removed StateProvider for settlementDateRangeProvider
  - Used Badge widget (Flutter Material 3) on NavigationDestination for unread count
  - Spanish locale relative time formatting without external package (manual calculation)
metrics:
  duration: 22min
  completed: "2026-04-13T13:22:13Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 8
  files_modified: 1
---

# Phase 17 Plan 05: Notifications + Settlements Features Summary

**One-liner:** Flutter notifications screen with unread badge + settlements screen with date-range filter, wired into 4-tab home navigation via Riverpod 3.x providers.

## What Was Built

### Task 1: Notifications Feature (commit 52f4d23)

- **notification_dto.dart** — `NotificationDto` with type-based icon getter (`NEW_ENVIO` → `local_shipping`, `DUE_SOON` → `warning_amber`, `SETTLEMENT_DONE` → `payments`)
- **notification_repository.dart** — 4 methods: `fetchNotifications`, `fetchUnreadCount`, `markAsRead`, `markAllAsRead` with DioException handling
- **notification_provider.dart** — `notificationListProvider` and `unreadCountProvider` (both `FutureProvider.family.autoDispose`)
- **notifications_screen.dart** — List with read/unread visual distinction (bold title + blue dot), "Marcar todo como leído" button (conditional on unread count), pull-to-refresh, Spanish relative time (hace N minutos/horas/días)

### Task 2: Settlements Feature + Home Integration (commit 7ed2602)

- **settlement_dto.dart** — `SettlementDto` with `double.tryParse` safe amount conversion (handles string or numeric API responses)
- **settlement_repository.dart** — `fetchSettlements(storeId, {from, to})` → `GET /vendor-portal/settlements`
- **settlement_provider.dart** — `settlementDateRangeProvider` (Notifier), `settlementListProvider` (family.autoDispose, watches dateRange), `settlementTotalProvider` (computed Provider.family)
- **settlements_screen.dart** — DateRangePicker filter, "Total neto del período" Card, read-only CardList with StatusChip (OPEN/CLOSED), pull-to-refresh, no create/edit actions (T-17-12 mitigated)
- **home_screen.dart** — `Badge` widget on Notificaciones `NavigationDestination` (both icon and selectedIcon), all 4 tabs replaced with real screens (`EnviosScreen`, `NotificationsScreen`, `SettlementsScreen`, `_ProfileSection`), placeholder sections removed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] StateProvider removed in Riverpod 3.x**
- **Found during:** Task 2 — flutter analyze
- **Issue:** Plan specified `StateProvider<DateTimeRange?>` but `StateProvider` was removed in flutter_riverpod 3.3.1
- **Fix:** Replaced with `Notifier<DateTimeRange?>` class `_DateRangeNotifier` with `setRange()` method; updated settlements_screen to call `.notifier.setRange()` instead of `.notifier.state =`
- **Files modified:** settlement_provider.dart, settlements_screen.dart
- **Commit:** 7ed2602

## Known Stubs

None — all 4 tabs are wired to real screens with live API calls.

## Self-Check: PASSED

All 9 required files exist. Commits 52f4d23 and 7ed2602 verified in git log. `flutter analyze` passes with no issues.
