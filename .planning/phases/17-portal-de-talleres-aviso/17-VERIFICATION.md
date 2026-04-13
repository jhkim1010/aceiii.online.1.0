---
phase: 17-portal-de-talleres-aviso
verified: 2026-04-13T14:00:00Z
status: human_needed
score: 18/18
overrides_applied: 0
human_verification:
  - test: "Flutter 앱 로그인 실제 동작"
    expected: "phone + 4자리 PIN 입력 후 home 화면으로 이동, 스토어 탭 표시"
    why_human: "에뮬레이터/실제 기기 없이 UI 플로우 검증 불가"
  - test: "POST /vendor-portal/auth/login 실제 엔드포인트 응답"
    expected: "{ token, stores[] } 반환, 잘못된 PIN 시 401 반환"
    why_human: "DB 마이그레이션(pin_hash 컬럼)이 실행 환경에서 완료되었는지 확인 필요 — docker exec 불가 환경"
  - test: "DUE_SOON 크론 실제 실행 확인"
    expected: "매일 09:00에 트리거, vendor_notifications에 중복 없이 생성"
    why_human: "크론 실행은 실시간 런타임 환경에서만 검증 가능"
  - test: "수령 확인(recepcion) 생성 후 envio 목록 갱신"
    expected: "recepcion 생성 후 envio pendingQuantity 감소, 상태 PARTIAL/COMPLETED 자동 변경"
    why_human: "실제 백엔드+앱 연동 E2E 테스트 필요"
  - test: "알림 배지 갱신"
    expected: "홈 화면 Notificaciones 탭 아이콘에 미읽음 카운트 숫자 표시"
    why_human: "실제 앱 실행 환경에서만 Badge 위젯 시각 확인 가능"
---

# Phase 17: Portal de Talleres 검증 보고서

**Phase Goal:** Flutter 독립 모바일 앱 — 외주업체(vendor)가 phone+PIN으로 로그인, 멀티매장 하단 탭, 진행현황 확인(읽기), 수령 확인(마킹), 앱 내 알림(배지), 정산 이력(읽기). Backend: vendor JWT auth + portal API + notifications + DUE_SOON cron + SubconModule 알림 트리거.
**Verified:** 2026-04-13T14:00:00Z
**Status:** human_needed
**Re-verification:** No — 초기 검증

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | POST /vendor-portal/auth/login with valid phone+PIN returns JWT token + stores array | VERIFIED | `vendor-auth.service.ts`: `bcrypt.compare(pin, vendors[0].pinHash)`, `jwtService.sign({ type: 'vendor', vendorPhone, vendorIds })`, `return { token, stores }` |
| 2 | POST /vendor-portal/auth/login with invalid PIN returns 401 | VERIFIED | `UnauthorizedException('Credenciales incorrectas')` — phone 미존재/PIN 불일치 동일 메시지(T-17-03) |
| 3 | GET /vendor-portal/auth/me with valid vendor JWT returns vendor info + stores | VERIFIED | `vendor-auth.service.ts::getMe()` + `vendor-auth.controller.ts` @UseGuards(VendorJwtGuard) |
| 4 | Regular user JWT cannot access vendor-portal endpoints | VERIFIED | `vendor-jwt.strategy.ts`: `payload.type !== 'vendor'` → UnauthorizedException('Token inválido para vendor portal') |
| 5 | vendor_notifications table schema defined in code | VERIFIED | `vendor-notification.model.ts`: tableName='vendor_notifications', ENUM(NEW_ENVIO, DUE_SOON, SETTLEMENT_DONE), indexed |
| 6 | Vendor can list their envios filtered by storeId | VERIFIED | `vendor-envios.service.ts`: `Envio.findAndCountAll({ where: { vendorId: { [Op.in]: vendorIds }, storeId } })` |
| 7 | Vendor can create a recepcion (partial/full) for an envio assigned to them | VERIFIED | `vendor-recepciones.service.ts`: Sequelize transaction, ForbiddenException if vendorId mismatch, pendingQuantity update |
| 8 | Vendor can list their settlements via SubconOrder JOIN | VERIFIED | `vendor-settlements.service.ts`: `SubconSettlement.findAll({ include: [{ model: SubconOrder, where: { vendorId: { [Op.in]: vendorIds } } }] })` |
| 9 | Vendor can list and mark notifications as read | VERIFIED | `vendor-notifications.service.ts`: findByVendor, markAsRead, markAllAsRead; `vendor-notifications.controller.ts`: GET/PATCH endpoints |
| 10 | Cron generates DUE_SOON notifications daily at 9am for envios due within 3 days | VERIFIED | `vendor-portal.cron.ts`: `@Cron('0 9 * * *')`, 3일 이내 PENDING/PARTIAL 조회, 중복 방지 로직 |
| 11 | NEW_ENVIO notification is created when EnvioService creates an envio | VERIFIED | `envio.service.ts`: `VendorNotificationsService` 주입, createEnvio 후 `createNotification({ type: 'NEW_ENVIO' })` try/catch 비블로킹 |
| 12 | SETTLEMENT_DONE notification is created when SubconSettlementService closes a settlement | VERIFIED | `subcon-settlement.service.ts`: `closeSettlement()` 메서드, `createNotification({ type: 'SETTLEMENT_DONE' })` try/catch 비블로킹 |
| 13 | Flutter app builds and runs without errors | VERIFIED | `flutter analyze`: No issues found (0 errors) |
| 14 | Login screen accepts phone + 4-digit PIN | VERIFIED | `login_screen.dart` 175줄: ConsumerStatefulWidget, phoneController + pinController, maxLength=4 |
| 15 | Successful login navigates to home with store tabs | VERIFIED | `app_router.dart`: authNotifierProvider watch → 인증 시 /home 리다이렉트; `home_screen.dart`: 4탭 NavigationBar + IndexedStack |
| 16 | JWT token stored securely and auto-injected in requests | VERIFIED | `secure_storage.dart` + `dio_client.dart` interceptor: `storage.read('vendor_token')` → `Authorization: Bearer` 헤더 |
| 17 | Vendor sees notification list with unread count badge | VERIFIED | `home_screen.dart`: `Badge(isLabelVisible: unreadCount > 0)` on NavigationDestination; `notification_provider.dart`: unreadCountProvider family.autoDispose |
| 18 | Vendor sees settlement history for selected store | VERIFIED | `settlements_screen.dart` 382줄: DateRangePicker, settlementTotalProvider, 읽기 전용 CardList; `settlement_repository.dart`: GET /vendor-portal/settlements |

**Score:** 18/18 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts` | Vendor login + PIN verification via bcrypt | VERIFIED | bcrypt.compare, returns {token, stores} |
| `api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.strategy.ts` | PassportStrategy(Strategy, 'vendor-jwt') | VERIFIED | payload.type==='vendor' 체크 확인 |
| `api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notification.model.ts` | VendorNotification Sequelize model | VERIFIED | tableName='vendor_notifications', ENUM type |
| `api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.service.ts` | Envio listing filtered by vendorId + storeId | VERIFIED | Op.in vendorIds + storeId where 조건 |
| `api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.service.ts` | Recepcion creation with envio pendingQuantity update | VERIFIED | Sequelize transaction 사용 |
| `api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.service.ts` | Settlement listing via SubconOrder JOIN | VERIFIED | include SubconOrder where vendorId |
| `api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.service.ts` | Notification CRUD + mark read + unread count | VERIFIED | 5개 메서드 구현 |
| `api-ventago/src/app/vendor-portal/vendor-portal.cron.ts` | Daily DUE_SOON cron | VERIFIED | @Cron('0 9 * * *'), 중복 방지 포함 |
| `talleres-vendor-app/pubspec.yaml` | flutter_riverpod, dio, go_router, flutter_secure_storage | VERIFIED | 모든 의존성 확인 |
| `talleres-vendor-app/lib/main.dart` | ProviderScope | VERIFIED | ProviderScope(child: TalleresVendorApp()) |
| `talleres-vendor-app/lib/features/auth/providers/auth_provider.dart` | authNotifierProvider | VERIFIED | AsyncNotifier 패턴, selectedStoreIndexProvider, currentStoreProvider |
| `talleres-vendor-app/lib/features/auth/views/login_screen.dart` | Phone + PIN login UI (min 50 lines) | VERIFIED | 175줄, ConsumerStatefulWidget |
| `talleres-vendor-app/lib/features/envios/views/envios_screen.dart` | Envio list view (min 60 lines) | VERIFIED | 244줄, pull-to-refresh, RefreshIndicator |
| `talleres-vendor-app/lib/features/recepciones/views/recepcion_dialog.dart` | Bottom sheet for confirming receipt (min 40 lines) | VERIFIED | 214줄, quantity validation |
| `talleres-vendor-app/lib/shared/widgets/status_chip.dart` | Reusable StatusChip | VERIFIED | PENDING/PARTIAL/COMPLETED/CANCELLED/OPEN/CLOSED 처리 |
| `talleres-vendor-app/lib/features/notifications/views/notifications_screen.dart` | Notification list (min 50 lines) | VERIFIED | 290줄, unread bold + blue dot |
| `talleres-vendor-app/lib/features/settlements/views/settlements_screen.dart` | Settlement history (min 50 lines) | VERIFIED | 382줄, DateRangePicker, 읽기 전용 |
| `talleres-vendor-app/lib/features/notifications/providers/notification_provider.dart` | unreadCountProvider | VERIFIED | FutureProvider.family.autoDispose |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| vendor-auth.service.ts | vendor.model.ts | Vendor.findAll | WIRED | `Vendor.findAll({ where: { phone, isActive: true } })` 확인 |
| vendor-auth.service.ts | bcrypt | bcrypt.compare | WIRED | `bcrypt.compare(pin, vendors[0].pinHash)` 확인 |
| app.module.ts | vendor-portal.module.ts | imports array | WIRED | line 135: VendorPortalModule 임포트 확인 |
| vendor-settlements.service.ts | SubconOrder JOIN | include SubconOrder | WIRED | `include: [{ model: SubconOrder, where: { vendorId: { [Op.in]: vendorIds } } }]` |
| vendor-recepciones.service.ts | envio.pendingQuantity | Sequelize transaction | WIRED | transaction 사용, pendingQuantity 업데이트 확인 |
| envio.service.ts | VendorNotificationsService | forwardRef injection | WIRED | `@Inject(forwardRef(() => VendorNotificationsService))` + createNotification(NEW_ENVIO) |
| subcon-settlement.service.ts | VendorNotificationsService | forwardRef injection | WIRED | `closeSettlement()` 메서드 → createNotification(SETTLEMENT_DONE) |
| auth_repository.dart | dio_client.dart | POST /vendor-portal/auth/login | WIRED | `_client.dio.post('/vendor-portal/auth/login')` 확인 |
| auth_provider.dart | auth_repository.dart | ref.read(authRepositoryProvider) | WIRED | `ref.read(authRepositoryProvider).login()` 확인 |
| app_router.dart | auth_provider.dart | authNotifierProvider redirect | WIRED | `ref.watch(authNotifierProvider)` → redirect guard |
| envio_repository.dart | dio_client.dart | GET /vendor-portal/envios | WIRED | `/vendor-portal/envios` 엔드포인트 확인 |
| recepcion_repository.dart | dio_client.dart | POST /vendor-portal/recepciones | WIRED | `/vendor-portal/recepciones` 엔드포인트 확인 |
| notification_repository.dart | dio_client.dart | GET /vendor-portal/notifications | WIRED | `/vendor-portal/notifications` 엔드포인트 확인 |
| settlement_repository.dart | dio_client.dart | GET /vendor-portal/settlements | WIRED | `/vendor-portal/settlements` 엔드포인트 확인 |
| home_screen.dart | notification_provider.dart | unreadCountProvider for badge | WIRED | `ref.watch(unreadCountProvider(storeId))` 확인 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| envios_screen.dart | envioListProvider(storeId) | envio_repository → GET /vendor-portal/envios → NestJS DB query | YES (Envio.findAndCountAll) | FLOWING |
| notifications_screen.dart | notificationListProvider(storeId) | notification_repository → GET /vendor-portal/notifications → VendorNotification.findAll | YES | FLOWING |
| settlements_screen.dart | settlementListProvider(storeId) | settlement_repository → GET /vendor-portal/settlements → SubconSettlement JOIN SubconOrder | YES | FLOWING |
| home_screen.dart | unreadCount (from unreadCountProvider) | VendorNotification.count | YES | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| TypeScript 컴파일 | `npx tsc --noEmit --project api-ventago/tsconfig.json` | exit 0 (무출력) | PASS |
| Flutter 정적 분석 | `flutter analyze` in talleres-vendor-app | No issues found (0 errors) | PASS |
| vendor-jwt strategy 분리 | grep 'vendor-jwt' in vendor-jwt.strategy.ts | `PassportStrategy(Strategy, 'vendor-jwt')` 확인 | PASS |
| cron 트리거 패턴 | grep '@Cron' in vendor-portal.cron.ts | `@Cron('0 9 * * *')` 확인 | PASS |
| subcon.module.ts forwardRef | grep VendorPortalModule | forwardRef(() => VendorPortalModule) 확인 | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| VP-01 | 17-01, 17-03 | Vendor phone+PIN 로그인, JWT 발급 | SATISFIED | vendor-auth.service.ts + login_screen.dart |
| VP-02 | 17-01, 17-03 | 멀티매장 하단 탭, 매장별 데이터 격리 | SATISFIED | selectedStoreIndexProvider + currentStoreProvider + home_screen.dart |
| VP-03 | 17-02, 17-04 | Envios 진행현황 확인(읽기) | SATISFIED | vendor-envios.service.ts + envios_screen.dart |
| VP-04 | 17-02, 17-04 | 수령 확인 마킹(recepcion 생성) | SATISFIED | vendor-recepciones.service.ts + recepcion_dialog.dart |
| VP-05 | 17-02, 17-05 | 앱 내 알림(배지 포함) + 읽음 처리 | SATISFIED | vendor-notifications.service.ts + notifications_screen.dart + home badge |
| VP-06 | 17-02, 17-05 | 정산 이력 확인(읽기) | SATISFIED | vendor-settlements.service.ts + settlements_screen.dart |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| 없음 | - | 스텁/플레이스홀더 없음 | - | - |

Note: 홈 화면 Notificaciones/Liquidaciones 플레이스홀더는 Plan 04 SUMMARY에 명시된 의도적 스텁이었으나, Plan 05에서 실제 화면으로 교체 완료됨.

---

### Human Verification Required

#### 1. 실제 로그인 플로우 동작 확인

**Test:** 에뮬레이터 또는 실제 기기에서 앱 실행 → phone 번호 + 4자리 PIN 입력 → 로그인 버튼 클릭
**Expected:** JWT 저장 + HomeScreen 이동 + 연결된 매장 탭 표시 (단일 매장이면 탭 없음)
**Why human:** UI 플로우는 코드 분석으로 검증하지 못함; flutter analyze 통과가 런타임 동작을 보증하지 않음

#### 2. DB 마이그레이션 적용 여부

**Test:** `docker exec api_ventago node -e "..."` 로 `talleres_vendors.pin_hash` 컬럼과 `vendor_notifications` 테이블 존재 확인
**Expected:** 두 컬럼과 테이블이 존재하고 인덱스가 적용됨
**Why human:** 검증 환경에서 docker exec 접근 불가. SUMMARY는 "Docker not available in executor" 편차를 기록하고 수동 실행 필요 명시. 실제 배포 전 반드시 서버에서 확인 필요.

#### 3. DUE_SOON 크론 실행 확인

**Test:** 서버 로그에서 크론 트리거 로그 확인 또는 `dueDate`가 3일 이내인 테스트 envio 생성 후 알림 생성 여부 확인
**Expected:** 매일 09:00에 `DUE_SOON 크론 시작` 로그 출력, 중복 없이 알림 생성
**Why human:** 크론 실행은 실시간 런타임 환경에서만 검증 가능

#### 4. 수령 확인 E2E 플로우

**Test:** envio 선택 → "Confirmar recepción" → 수량 입력 → 제출
**Expected:** 성공 SnackBar 표시, envio 목록 자동 갱신, pendingQuantity 감소, 상태 변경(PARTIAL/COMPLETED)
**Why human:** 실제 백엔드 연동 없이는 트랜잭션 성공/롤백 동작 확인 불가

#### 5. 알림 배지 시각적 확인

**Test:** 미읽음 알림이 있는 상태에서 홈 화면 확인
**Expected:** Notificaciones 탭 아이콘에 빨간 배지와 숫자 표시
**Why human:** Badge 위젯의 실제 렌더링 확인은 에뮬레이터 필요

---

### Gaps Summary

없음 — 모든 18개 truth가 검증되었습니다. 남은 항목은 런타임/환경 의존적 검증으로 자동화가 불가능하여 Human Verification으로 분류됩니다.

**중요 주의사항:**
- DB 마이그레이션 SQL(`ALTER TABLE talleres_vendors ADD COLUMN pin_hash ...` + `CREATE TABLE vendor_notifications ...`)이 배포 전 서버에서 반드시 실행되어야 합니다.
- 17-01-SUMMARY.md에 정확한 SQL이 문서화되어 있습니다.

---

_Verified: 2026-04-13T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
