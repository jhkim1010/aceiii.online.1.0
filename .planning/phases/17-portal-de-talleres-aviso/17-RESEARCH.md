# Phase 17: Portal de Talleres Aviso — Research

**Researched:** 2026-04-13
**Domain:** Flutter mobile app + NestJS API extension (vendor portal)
**Confidence:** HIGH (codebase fully verified, Flutter ecosystem verified)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Flutter 독립 앱으로 구현 — Ventago 본체와 완전 분리. 별도 패키지/저장소(또는 모노레포 내 새 디렉토리)
- **D-02:** 업체가 다른 매장의 데이터에 접근 불가 — vendor 기반 인증으로 자기 데이터만 조회
- **D-03:** 전화번호 + 4자리 PIN 로그인. 매장 관리자가 Ventago에서 vendor 등록 시 PIN 발급
- **D-04:** 백엔드에 vendor 전용 인증 엔드포인트 추가 — JWT 토큰 발급, vendor 정보 + 연결된 store 목록 반환
- **D-05:** 하단 탭으로 매장 전환 — 각 매장의 발송/수령/정산이 독립 표시
- **D-06:** 로그인 후 연결된 store 목록 표시, 탭으로 자유 전환
- **D-07:** 진행현황 확인 — 내게 발송된 로트/공정 목록 + 수량 + 납기 확인 (읽기 전용)
- **D-08:** 수령 확인 — 업체가 직접 완료/부분완료 마킹 → 매장 측에 수령 알림 전송
- **D-09:** 알림 수신 — 앱 내 알림만 (푸시 없음). 새 발송, 납기 임박, 정산 완료 등
- **D-10:** 정산 이력 확인 — 나의 정산 금액/상태 확인 (수정 불가, 읽기 전용)
- **D-11:** 앱 내 알림 목록 + 미읽음 배지 카운트. 푸시 알림 없음 (Phase 범위 외)
- **D-12:** 알림 생성은 백엔드에서 envio 생성/납기 임박 cron/정산 완료 시 자동 생성

### Claude's Discretion
- Flutter 프로젝트 구조 (디렉토리, 상태관리)
- UI 디자인 (색상, 레이아웃 — Phase 16 스타일 참고)
- 백엔드 vendor auth 엔드포인트 세부 구현
- 알림 DB 테이블 구조
- PIN 암호화/저장 방식

### Deferred Ideas (OUT OF SCOPE)
- 푸시 알림 (Firebase Cloud Messaging) — 별도 phase
- 채팅/메시지 기능 — 매장-업체 간 커뮤니케이션
- 사진 첨부 (작업 완료 사진 업로드)
- 오프라인 모드
</user_constraints>

---

## Summary

Phase 17 builds two separate artifacts: (1) a Flutter standalone mobile app for vendors (talleres) to track their work, confirm receipt, view notifications, and check settlement history; (2) a NestJS API extension in `api-ventago` that adds vendor-specific authentication and vendor-scoped portal endpoints.

The existing backend has a complete subcon module (`api-ventago/src/app/subcon/`) with 12 controllers/services covering Vendors, Envios, Recepciones, Settlements, Etapas, Lotes, etc. The Vendor model (`talleres_vendors` table) already has a `phone` field — only a `pin` column addition is needed. All existing service methods already support `vendorId` filtering (verified in `EnvioService.findFiltered`). The core implementation risk is building the Flutter app from scratch with Riverpod + proper token storage, and designing the vendor_notifications DB table with correct triggering hooks.

**Primary recommendation:** Create `talleres-vendor-app/` as a new Flutter project inside the monorepo. Add a new `VendorPortalModule` to `api-ventago` (separate from SubconModule) that contains vendor auth, portal API, and notification management. Keep all vendor-portal logic isolated from the main Ventago user auth.

---

## Project Constraints (from CLAUDE.md)

| Directive | Applies To |
|-----------|-----------|
| Flutter: null safety 준수, Riverpod 상태관리 선호, dart 스타일 가이드 따름 | Flutter app |
| 에러 핸들링 항상 포함 | Flutter + NestJS |
| 주석은 한국어로 작성 | Flutter + NestJS |
| 함수/변수명은 영어로 작성 | Flutter + NestJS |
| NestJS: async/await, 에러 핸들링 포함 | Backend |
| PostgreSQL: pool 낭비 없도록 connection 관리 | DB migrations |
| ESLint: lint 오류 특히 주의 (Warning도 빌드 에러) | Frontend (N/A for Flutter) |
| Sequelize `underscored: true` → SQL에서 반드시 snake_case | DB migrations |

---

## Standard Stack

### Flutter App (talleres-vendor-app)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | 3.41.2 | App framework | [VERIFIED: env check] |
| dart | 3.11.0 | Language | [VERIFIED: env check] |
| flutter_riverpod | ^2.5.x | 상태관리 | CLAUDE.md mandated, Riverpod 2.x = current standard |
| hooks_riverpod | ^2.5.x | useRef/useState in widgets | Pairs with Riverpod |
| go_router | ^14.x | 화면 전환 | Flutter 공식 권장 라우터 |
| dio | ^5.x | HTTP client | flutter_http보다 강력, interceptor 지원 |
| flutter_secure_storage | ^9.x | JWT/PIN 보안 저장 | Keychain(iOS)/Keystore(Android) 사용 |
| shared_preferences | ^2.x | 비보안 설정 저장 | 가벼운 설정값 |
| intl | ^0.19.x | 날짜/숫자 형식 | 스페인어 날짜 형식 |

[ASSUMED] — 위 버전들은 2025-08월 기준 훈련 지식이므로, pubspec.yaml 작성 전 `pub.dev`에서 최신 버전 확인 필요.

### NestJS Backend Extension
| Component | Pattern | Source |
|-----------|---------|--------|
| VendorPortalModule | 기존 SubconModule과 분리된 독립 모듈 | [VERIFIED: app.module.ts 분석] |
| VendorPortalStrategy | `passport-jwt`의 별도 Strategy (name: 'vendor-jwt') | [VERIFIED: jwt.strategy.ts 패턴] |
| VendorPortalGuard | `@UseGuards(AuthGuard('vendor-jwt'))` | [VERIFIED: jwt.strategy.ts 패턴] |
| PIN 암호화 | `bcrypt` (이미 auth.service.ts에서 사용) | [VERIFIED: auth.service.ts] |
| Cron (납기 임박) | `@Cron('0 9 * * *')` via @nestjs/schedule | [VERIFIED: store.cron.ts 패턴] |

### Flutter Package Installation
```bash
flutter pub add flutter_riverpod hooks_riverpod go_router dio flutter_secure_storage shared_preferences intl
```

---

## Architecture Patterns

### Flutter App Directory Structure

```
talleres-vendor-app/
├── pubspec.yaml
├── lib/
│   ├── main.dart               # 앱 진입점, ProviderScope 래핑
│   ├── core/
│   │   ├── config/
│   │   │   └── api_config.dart # 베이스 URL, 타임아웃 설정
│   │   ├── network/
│   │   │   ├── dio_client.dart # Dio 인스턴스 + interceptor
│   │   │   └── api_exception.dart
│   │   └── storage/
│   │       └── secure_storage.dart  # flutter_secure_storage 래핑
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── auth_repository.dart
│   │   │   │   └── auth_dto.dart
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart
│   │   │   └── views/
│   │   │       └── login_screen.dart
│   │   ├── envios/             # 진행현황 (read-only)
│   │   │   ├── data/
│   │   │   ├── providers/
│   │   │   └── views/
│   │   ├── recepciones/        # 수령 확인 (write)
│   │   │   ├── data/
│   │   │   ├── providers/
│   │   │   └── views/
│   │   ├── notifications/      # 알림 목록
│   │   │   ├── data/
│   │   │   ├── providers/
│   │   │   └── views/
│   │   └── settlements/        # 정산 이력 (read-only)
│   │       ├── data/
│   │       ├── providers/
│   │       └── views/
│   ├── shared/
│   │   ├── widgets/
│   │   │   ├── store_tab_bar.dart  # 하단 탭 (매장별)
│   │   │   └── status_chip.dart    # 상태 배지
│   │   └── models/
│   │       └── store_info.dart
│   └── router/
│       └── app_router.dart     # go_router 설정
└── android/
└── ios/
```

### Riverpod Provider Pattern (Flutter)

```dart
// auth_provider.dart — 인증 상태 관리
// [ASSUMED: Riverpod 2.x AsyncNotifier 패턴 기반]

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<AuthState?> build() async {
    // 앱 시작 시 저장된 토큰 복구
    final token = await ref.read(secureStorageProvider).read('vendor_token');
    if (token == null) return null;
    return AuthState.fromToken(token);
  }

  Future<void> login(String phone, String pin) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
      ref.read(authRepositoryProvider).signIn(phone: phone, pin: pin)
    );
  }
}
```

### NestJS Backend Module Structure

```
api-ventago/src/app/vendor-portal/
├── vendor-portal.module.ts         # 독립 모듈
├── vendor-auth/
│   ├── vendor-auth.controller.ts   # POST /vendor-portal/auth/login
│   ├── vendor-auth.service.ts      # PIN 검증, JWT 발급
│   ├── vendor-jwt.strategy.ts      # Passport Strategy ('vendor-jwt')
│   └── dto/
│       └── vendor-login.dto.ts
├── vendor-envios/
│   ├── vendor-envios.controller.ts # GET /vendor-portal/envios
│   └── vendor-envios.service.ts
├── vendor-recepciones/
│   ├── vendor-recepciones.controller.ts # POST /vendor-portal/recepciones
│   └── vendor-recepciones.service.ts
├── vendor-settlements/
│   ├── vendor-settlements.controller.ts # GET /vendor-portal/settlements
│   └── vendor-settlements.service.ts
└── vendor-notifications/
    ├── vendor-notifications.controller.ts # GET /vendor-portal/notifications
    ├── vendor-notifications.service.ts    # CRUD + mark-read
    └── vendor-notification.model.ts       # DB 모델
```

### Vendor JWT Strategy (NestJS)

```typescript
// vendor-jwt.strategy.ts
// 기존 JwtStrategy와 분리 — 'vendor-jwt' 전략명 사용

@Injectable()
export class VendorJwtStrategy extends PassportStrategy(Strategy, 'vendor-jwt') {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: process.env.JWT_SECRET_KEY, // 동일 시크릿 사용 가능
    });
  }

  async validate(payload: { vendorId: number; phone: string; type: 'vendor' }): Promise<any> {
    // type 검증으로 일반 사용자 토큰 재사용 차단
    if (payload.type !== 'vendor') {
      throw new UnauthorizedException('Token inválido para vendor portal');
    }
    const vendor = await Vendor.findByPk(payload.vendorId);
    if (!vendor || !vendor.isActive) {
      throw new UnauthorizedException('Vendor inactivo');
    }
    return vendor; // req.user에 vendor 객체 주입
  }
}
```

### DB Migration: Vendor 테이블 PIN 컬럼 추가

```sql
-- snake_case 사용 (underscored: true)
ALTER TABLE talleres_vendors ADD COLUMN pin_hash VARCHAR(255);
ALTER TABLE talleres_vendors ADD COLUMN pin_updated_at TIMESTAMP;
```

Sequelize 모델 업데이트:
```typescript
@Column({ type: DataType.STRING, allowNull: true })
pinHash: string; // bcrypt 해시, nullable (미설정 시 로그인 불가)

@Column({ type: DataType.DATE, allowNull: true })
pinUpdatedAt: Date;
```

### DB 설계: vendor_notifications 테이블

```typescript
// vendor-notification.model.ts
@Table({ timestamps: true, tableName: 'vendor_notifications' })
export class VendorNotification extends Model {
  @PrimaryKey @AutoIncrement @Column
  id: number;

  @ForeignKey(() => Vendor)
  @Column({ type: DataType.INTEGER, allowNull: false })
  vendorId: number;

  @ForeignKey(() => Store)
  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @Column({
    type: DataType.ENUM('NEW_ENVIO', 'DUE_SOON', 'SETTLEMENT_DONE'),
    allowNull: false,
  })
  type: string;

  @Column({ type: DataType.STRING, allowNull: false })
  title: string; // 예: "Nuevo envío recibido"

  @Column({ type: DataType.TEXT, allowNull: true })
  body: string; // 상세 내용

  @Column({ type: DataType.INTEGER, allowNull: true })
  referenceId: number; // envioId 또는 settlementId

  @Column({ type: DataType.BOOLEAN, defaultValue: false })
  isRead: boolean;

  @BelongsTo(() => Vendor)
  vendor: Vendor;

  @BelongsTo(() => Store)
  store: Store;
}
```

### 알림 트리거 지점

| 이벤트 | 발생 위치 | 알림 타입 |
|--------|----------|-----------|
| Envio 생성 | `EnvioService.createEnvio()` 이후 | `NEW_ENVIO` |
| 납기 임박 (D-3 이내) | 새 Cron: `@Cron('0 9 * * *')` | `DUE_SOON` |
| Settlement CLOSED 상태 변경 | `SubconSettlementService.update()` 이후 | `SETTLEMENT_DONE` |

### Vendor Portal API 엔드포인트 설계

```
POST   /vendor-portal/auth/login       # { phone, pin } → { token, vendorInfo, stores[] }
GET    /vendor-portal/auth/me          # 토큰에서 vendor 정보 반환

GET    /vendor-portal/envios           # ?storeId=&status=&page=&pageSize=
POST   /vendor-portal/recepciones      # { envioId, receivedQuantity, rejectedQuantity, notes }

GET    /vendor-portal/settlements      # ?storeId=&from=&to=
GET    /vendor-portal/notifications    # ?storeId=&isRead=
PATCH  /vendor-portal/notifications/:id/read  # 읽음 처리
PATCH  /vendor-portal/notifications/read-all  # 전체 읽음
```

### Anti-Patterns to Avoid

- **일반 JWT Strategy 재사용 금지:** VendorJwtStrategy는 별도 `'vendor-jwt'` 이름을 가져야 일반 user 토큰으로 vendor 엔드포인트 접근 불가
- **SubconModule 직접 수정 금지:** VendorPortalModule은 독립 모듈로 SubconModule의 exported service를 import해서 사용
- **Vendor 데이터에 storeId 교차 접근 금지:** 모든 vendor-portal 쿼리는 `vendorId`와 `storeId` 동시 필터링 필수
- **PIN 평문 저장 금지:** bcrypt(rounds=10) 해시 후 `pin_hash` 컬럼에만 저장

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PIN 해싱 | 자체 해싱 로직 | `bcrypt` (이미 auth.service.ts에 있음) | Rainbow table 공격 방지 |
| Flutter 상태관리 | setState + InheritedWidget | `flutter_riverpod` (CLAUDE.md mandated) | 비동기 상태, 캐싱, 의존성 주입 |
| HTTP 클라이언트 | http 패키지 직접 | `dio` | Interceptor로 JWT 헤더 자동 주입 |
| JWT 저장 | SharedPreferences | `flutter_secure_storage` | 보안 키체인/키스토어 사용 |
| 날짜 포맷 | 직접 포맷팅 | `intl` 패키지 | 스페인어 로케일 지원 |
| 탭 라우팅 | 직접 Navigator 관리 | `go_router` | 딥링크, 뒤로가기 스택 처리 |

**Key insight:** 이미 NestJS 백엔드에 SubconModule의 완성된 데이터 모델과 서비스가 있다. VendorPortalModule은 새 Auth 레이어 + vendor-scoped 필터링 + 알림 트리거를 추가하는 것이 핵심이며, 데이터 로직을 재구현해선 안 된다.

---

## Common Pitfalls

### Pitfall 1: Vendor 모델에 storeId가 1개뿐
**What goes wrong:** `talleres_vendors.store_id`는 1개만 있음. 그러나 1개 vendor가 여러 매장(store)에 서비스할 수 있어야 함 (D-05/D-06).
**Why it happens:** 현재 Vendor 모델은 단일 storeId 관계만 가짐 (1:N from Store).
**How to avoid:** 로그인 시 `phone`으로 검색하면 동일 전화번호를 가진 Vendor 레코드가 여러 매장에 각각 있을 수 있음. 이를 배열로 묶어서 반환 (`stores[]`). 별도 M:N 테이블 불필요 — 같은 phone, 다른 storeId인 Vendor 레코드들을 모두 조회.
**Warning signs:** 로그인 후 한 매장만 탭에 보임

### Pitfall 2: SubconSettlement가 vendorId를 직접 갖지 않음
**What goes wrong:** `talleres_settlements` 테이블은 `subcon_order_id`를 통해 vendorId에 접근 (SubconOrder → vendor). 직접 vendorId FK 없음.
**Why it happens:** Settlement 모델 검증 결과 (`SubconOrder` → `Vendor` 경로).
**How to avoid:** Vendor Portal 정산 조회 시 JOIN 필요: `Settlement → SubconOrder → Vendor WHERE vendor.id = :vendorId`
**Warning signs:** 정산 이력 조회 시 빈 결과 반환

### Pitfall 3: SubconModule이 app.module.ts에 미등록
**What goes wrong:** `api-ventago/src/app.module.ts`에 `SubconModule` import가 없음 (확인됨). `VendorPortalModule`도 동일하게 app.module.ts에 추가해야 함.
**Why it happens:** SubconModule imports 확인 시 app.module.ts에 없었음 — 별도 경로로 로드될 수 있으나 VendorPortalModule은 반드시 명시적 등록 필요.
**How to avoid:** VendorPortalModule을 app.module.ts `imports` 배열에 추가.

### Pitfall 4: Flutter 앱에서 베이스 URL 환경별 분기
**What goes wrong:** 개발 시 `http://localhost:5002/api`, 운영 시 `https://newapi.coolsistema.com/api` — Flutter 앱은 빌드 플래그 없이 환경 분기가 어려움.
**Why it happens:** Flutter는 dart-define 또는 flavor 설정이 필요.
**How to avoid:** `flutter run --dart-define=BASE_URL=http://...` 또는 `lib/core/config/api_config.dart`에 상수로 관리하고 빌드 시 치환.

### Pitfall 5: Recepcion 생성 시 Envio pendingQuantity 업데이트 누락
**What goes wrong:** 업체가 수령 확인 시 `talleres_envios.pending_quantity` 감소 + `status` 업데이트가 트랜잭션으로 처리되지 않으면 데이터 불일치 발생.
**Why it happens:** 기존 RecepcionService 패턴을 확인해야 함 (이미 처리 중일 수 있음).
**How to avoid:** VendorPortalRecepcionService는 기존 `RecepcionService`의 트랜잭션 로직 재사용 또는 위임.

### Pitfall 6: Flutter SecureStorage iOS 시뮬레이터 이슈
**What goes wrong:** `flutter_secure_storage` iOS 시뮬레이터에서 Keychain 접근 실패.
**Why it happens:** iOS 시뮬레이터 Keychain 접근 제한.
**How to avoid:** Info.plist에 `NSAppleEventsUsageDescription` 추가, 또는 개발 중에는 공유 Keychain 그룹 설정 확인.

---

## Code Examples

### NestJS — Vendor 로그인 서비스 패턴

```typescript
// vendor-auth.service.ts
// [VERIFIED: bcrypt/jwt 패턴은 auth.service.ts에서 확인됨]

async vendorLogin(phone: string, pin: string): Promise<any> {
  // 동일 phone의 모든 매장 vendor 조회 (멀티스토어 지원)
  const vendors = await Vendor.findAll({
    where: { phone, isActive: true },
    include: [{ model: Store, attributes: ['id', 'name', 'logoUrl', 'aliasName'] }],
  });

  if (!vendors.length) {
    throw new UnauthorizedException('Vendedor no encontrado');
  }

  // PIN 검증 (첫 번째 vendor 레코드의 해시로 검증)
  const isValid = await bcrypt.compare(pin, vendors[0].pinHash);
  if (!isValid) {
    throw new UnauthorizedException('PIN incorrecto');
  }

  const payload = {
    type: 'vendor',
    vendorPhone: phone,
    vendorIds: vendors.map(v => v.id),
  };
  const token = this.jwtService.sign(payload, { expiresIn: '30d' });

  const stores = vendors.map(v => ({
    vendorId: v.id,
    storeId: v.storeId,
    storeName: v.store?.name,
    logoUrl: v.store?.logoUrl,
    aliasName: v.store?.aliasName,
  }));

  return { token, stores };
}
```

### Flutter — Dio Client with JWT Interceptor

```dart
// dio_client.dart
// [ASSUMED: Dio 5.x interceptor 패턴]

class DioClient {
  late Dio _dio;

  DioClient(String baseUrl, SecureStorage storage) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // JWT 토큰 자동 주입
        final token = await storage.read('vendor_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // 토큰 만료 → 로그인 화면으로
          // go_router redirect 처리
        }

        return handler.next(error);
      },
    ));
  }
}
```

### Flutter — 하단 탭바 (멀티스토어)

```dart
// store_tab_bar.dart — 매장별 탭 전환
// [ASSUMED: Flutter BottomNavigationBar 패턴]

class StoreTabBar extends ConsumerWidget {
  const StoreTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(authNotifierProvider).value?.stores ?? [];
    final selectedIndex = ref.watch(selectedStoreIndexProvider);

    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: (index) => ref.read(selectedStoreIndexProvider.notifier).state = index,
      items: stores.map((store) => BottomNavigationBarItem(
        icon: const Icon(Icons.store),
        label: store.storeName,
      )).toList(),
    );
  }
}
```

### NestJS — 납기 임박 Cron

```typescript
// vendor-portal.cron.ts
// [VERIFIED: @Cron 패턴은 store.cron.ts에서 확인됨]

@Injectable()
export class VendorPortalCronService {
  // 매일 오전 9시 실행 — 3일 이내 납기 임박 알림
  @Cron('0 9 * * *')
  async notifyDueSoonEnvios() {
    const threeDaysLater = new Date();
    threeDaysLater.setDate(threeDaysLater.getDate() + 3);

    const dueSoonEnvios = await Envio.findAll({
      where: {
        status: { [Op.in]: [EnvioStatus.PENDING, EnvioStatus.PARTIAL] },
        dueDate: { [Op.lte]: threeDaysLater.toISOString().split('T')[0] },
      },
    });

    for (const envio of dueSoonEnvios) {
      // 중복 알림 방지: 오늘 이미 생성된 DUE_SOON 알림 확인
      const existing = await VendorNotification.findOne({
        where: {
          vendorId: envio.vendorId,
          referenceId: envio.id,
          type: 'DUE_SOON',
          createdAt: { [Op.gte]: new Date(new Date().setHours(0, 0, 0, 0)) },
        },
      });
      if (existing) continue;

      await VendorNotification.create({
        vendorId: envio.vendorId,
        storeId: envio.storeId,
        type: 'DUE_SOON',
        title: 'Entrega próxima',
        body: `Lote vence el ${envio.dueDate}. Pendiente: ${envio.pendingQuantity} unidades`,
        referenceId: envio.id,
      });
    }
  }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| StatefulWidget + setState | Riverpod AsyncNotifier | Riverpod 2.0 (2023) | 코드 분리, 테스트 용이 |
| Navigator 1.0 | go_router | Flutter 3.x (2023) | 딥링크, 선언적 라우팅 |
| http 패키지 | Dio | 업계 표준 | Interceptor, FormData, 취소 |
| SharedPreferences for tokens | flutter_secure_storage | 보안 강화 | Keychain/Keystore 사용 |

**Deprecated/outdated:**
- `provider` 패키지: CLAUDE.md에서 Riverpod으로 대체
- `get` 패키지: 프로젝트 미사용, Riverpod 사용

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Riverpod ^2.5.x, go_router ^14.x — 최신 버전 [ASSUMED] | Standard Stack | pub.dev 확인으로 해결 가능 |
| A2 | 동일 전화번호로 여러 매장 Vendor 레코드 존재 가능 (멀티스토어 구현 방식) [ASSUMED] | Architecture | DB에서 phone + storeId 조합 확인 필요 |
| A3 | SubconSettlement → SubconOrder → Vendor JOIN으로 vendorId 필터링 [VERIFIED: 모델 분석] | Pitfalls | 낮음 |
| A4 | iOS 시뮬레이터 Keychain 이슈 [ASSUMED] | Pitfalls | 개발 환경 테스트로 확인 |

---

## Open Questions (RESOLVED)

1. **Vendor PIN 초기 발급 UI (Ventago 웹)** — RESOLVED
   - What we know: 매장 관리자가 vendor 등록 시 PIN 발급 필요 (D-03)
   - What's unclear: Phase 17 범위 내인지, Phase 16 UI에서 처리하는지
   - Recommendation: Vendors 관리 화면에서 PIN 발급/재설정 기능 추가 (4자리 숫자 입력 + bcrypt 저장) — Phase 17 Wave 0에 포함
   - **Resolution:** Phase 17 범위. 17-01에 이미 PIN 관리 API(pin_hash 컬럼 + bcrypt) 포함. Ventago 프론트 PIN 설정 UI는 17-01 action의 vendor form drawer에 PIN 필드 추가로 커버 (관리자 화면에서 PIN 발급).

2. **SubconModule이 app.module.ts에 미등록 상태** — RESOLVED
   - What we know: app.module.ts 전체 분석 결과 SubconModule이 없음
   - What's unclear: 별도 라우팅으로 로드되는지, 누락인지
   - Recommendation: VendorPortalModule 추가 전 SubconModule 등록 상태 재확인 (Wave 0 task)
   - **Resolution:** 17-01/17-02에서 VendorPortalModule을 별도 생성하므로 SubconModule 등록 여부 무관. VendorPortalModule이 필요한 Sequelize 모델을 직접 forFeature로 import하며, SubconModule exports가 필요한 경우 imports에 추가.

3. **Vendor 앱 배포 방식** — RESOLVED
   - What we know: Flutter → iOS/Android 빌드
   - What's unclear: APK 직접 배포 vs App Store/Play Store
   - Recommendation: Phase 17 범위는 개발/빌드까지. 배포는 별도 phase.
   - **Resolution:** Deferred — Phase 17 범위는 개발/빌드까지. 배포는 별도 phase에서 결정.
---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Flutter app 빌드 | ✓ | 3.41.2 | — |
| Dart SDK | Flutter app | ✓ | 3.11.0 | — |
| PostgreSQL (Docker) | DB migration | ✓ | 15 (Docker) | — |
| NestJS (@nestjs/schedule) | Cron jobs | ✓ | 이미 app.module.ts에 등록 | — |
| bcrypt | PIN 해싱 | ✓ | 이미 auth.service.ts에서 사용 | — |
| passport-jwt | Vendor JWT Strategy | ✓ | 이미 JwtStrategy에서 사용 | — |

**Missing dependencies with no fallback:** 없음

**Missing dependencies with fallback:** 없음

---

## Validation Architecture

> nyquist_validation 설정 미확인 — 기본값 enabled로 처리.

Flutter 앱은 독립 프로젝트이므로 별도 테스트 프레임워크. NestJS 백엔드는 기존 Jest 환경.

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Notes |
|-----|----------|-----------|-------|
| D-03/D-04 | Phone+PIN 로그인 → JWT 반환 | unit (NestJS) | `vendor-auth.service.spec.ts` |
| D-02 | 다른 매장 데이터 접근 차단 | integration | vendorId + storeId 필터 검증 |
| D-08 | 수령 확인 POST → Envio status 업데이트 | integration | 트랜잭션 무결성 |
| D-12 | Envio 생성 시 NEW_ENVIO 알림 자동 생성 | unit | mock VendorNotification.create |
| D-09 | 알림 목록 조회 + 미읽음 카운트 | unit | |

### Wave 0 Gaps (Backend)
- [ ] `vendor-portal.module.ts` — 신규 모듈 생성
- [ ] `vendor-notification.model.ts` — 신규 DB 모델
- [ ] DB migration: `talleres_vendors` pin_hash 컬럼 추가
- [ ] DB migration: `vendor_notifications` 테이블 생성

### Wave 0 Gaps (Flutter)
- [ ] `talleres-vendor-app/` Flutter 프로젝트 초기화 (`flutter create`)
- [ ] `pubspec.yaml` 의존성 설정
- [ ] `lib/core/` 기반 구조 생성

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | bcrypt PIN + JWT (별도 vendor-jwt strategy) |
| V3 Session Management | yes | JWT 30일 만료, flutter_secure_storage |
| V4 Access Control | yes | VendorPortalGuard + vendorId scope 검증 |
| V5 Input Validation | yes | class-validator DTO (NestJS), Dart null safety |
| V6 Cryptography | yes | bcrypt (이미 사용), JWT RS256 or HS256 |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 다른 vendor 데이터 접근 | Spoofing | JWT payload에 vendorIds[], 모든 쿼리에 vendorId 필터 |
| PIN 브루트포스 | Elevation of Privilege | 6자리도 고려, 향후 rate limiting 추가 가능 |
| JWT 토큰 재사용 (일반 user 토큰으로 vendor API 접근) | Spoofing | payload.type === 'vendor' 검증 in VendorJwtStrategy |
| 타 매장 알림 조회 | Information Disclosure | 알림 쿼리에 vendorId + storeId 동시 필터 |

---

## Sources

### Primary (HIGH confidence — codebase verified)
- `api-ventago/src/app/subcon/vendors/vendor.model.ts` — Vendor 모델 구조 확인
- `api-ventago/src/app/subcon/envios/envio.model.ts` — Envio 모델 + EnvioStatus
- `api-ventago/src/app/subcon/recepciones/recepcion.model.ts` — Recepcion 모델
- `api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.model.ts` — Settlement 구조
- `api-ventago/src/app/auth/auth.service.ts` — JWT/bcrypt 패턴
- `api-ventago/src/app/auth/strategies/jwt.strategy.ts` — Passport Strategy 패턴
- `api-ventago/src/app/store/store.cron.ts` — @Cron 사용 패턴
- `api-ventago/src/app.module.ts` — SubconModule 미등록 확인
- `api-ventago/src/app/subcon/subcon.module.ts` — 12개 controller/service 목록
- `api-ventago/src/app/subcon/envios/envio.service.ts` — vendorId 필터링 지원 확인
- `.planning/codebase/CONVENTIONS.md` — NestJS 모듈 구조, 주석 언어 규칙
- env check: Flutter 3.41.2, Dart 3.11.0 설치 확인

### Secondary (MEDIUM confidence)
- `vendor-cockpit-mockup.html` — UI 참조 (vendor 뷰 형태 파악)
- `api-ventago/src/app/notifications/` — 현재 알림 시스템은 WebSocket 기반 (vendor portal은 별도 DB 기반 알림 사용)

### Tertiary (LOW confidence — assumed)
- Flutter Riverpod ^2.5.x, go_router ^14.x 버전 — pub.dev 확인 필요 [ASSUMED]
- iOS 시뮬레이터 flutter_secure_storage 이슈 — 훈련 데이터 기반 [ASSUMED]

---

## Metadata

**Confidence breakdown:**
- Standard Stack (NestJS 확장): HIGH — 모든 패턴 codebase에서 확인됨
- Standard Stack (Flutter): MEDIUM — Flutter SDK 설치 확인, 패키지 버전 assumed
- Architecture: HIGH — 기존 NestJS 패턴 완전 파악, Flutter 구조는 표준 패턴
- Pitfalls: HIGH — 실제 DB 모델 분석으로 식별

**Research date:** 2026-04-13
**Valid until:** 2026-05-13 (Flutter 패키지 버전 재확인 권장)
