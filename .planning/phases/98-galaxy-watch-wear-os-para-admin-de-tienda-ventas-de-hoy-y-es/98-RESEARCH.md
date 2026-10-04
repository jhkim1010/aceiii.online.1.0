# Phase 98: Galaxy Watch (Wear OS) 매장 admin 앱 — Research

**Researched:** 2026-10-04
**Domain:** Wear OS 네이티브 앱(Kotlin+Compose) · NestJS 디바이스 코드 페어링 인증 · 테넌트 격리 · Flutter 화면 · Google Play 배포
**Confidence:** MEDIUM-HIGH (API/DB 쪽은 코드 실측 HIGH, Wear OS/Play 쪽은 공식 문서 기반이나 일부는 영문 문서 요약이라 MEDIUM)

## Summary

이 phase 는 세 레이어를 건드린다 — ① `api-ventago` 에 읽기 전용 `/watch/*` 엔드포인트 3~4개와 새 테이블 1개,
② `tienda-admin-app`(Flutter)에 「Relojes vinculados」 화면 1개, ③ 완전히 새로운 `wear-admin-app`(Kotlin + Jetpack
Compose for Wear OS) 모노레포 디렉터리. 가장 중요한 설계 리스크는 코드 자체가 아니라 **이 저장소의 기존 보안
경계와 충돌하지 않게 짜는 것**이다 — 전역 `JwtGlobalGuard` 는 Passport `AuthGuard('jwt')` 하나로 고정돼 있고,
`@Public()` 라우트는 테넌트 컨텍스트가 비어 Sequelize 격리 훅이 통째로 no-op 이 된다. 이 저장소는 이미 같은
문제를 **두 번** 풀어 놓았다 — `vendor-jwt` 라는 별도 Passport 전략(벤더 포털)과, 전혀 passport 를 쓰지 않고
서비스 레이어에서 직접 해시 비교하는 `admin_device_tokens`(기기 토큰, Phase 72-03). 워치 토큰은 후자의 패턴을
그대로 따르는 것이 안전하다 — `@Public()` + 전용 `WatchTokenGuard`(CanActivate, passport 아님) + 그 가드가
`TenantContext.resolve()` 를 **JwtGlobalGuard 가 하는 것과 똑같이** 직접 호출한다.

매출·카하 집계는 **새로 설계하지 않는다.** `sale-status.constants.ts` 에 이미 「판매의 지점은 `sales.branch_id`
가 권위(`saleBranchSql`)·취소는 반대부호 행(`signedTxSql`)·회수 판매 제외(`EXCLUDE_DEUDA_PAGO_SQL`)」가
SQL 조각 함수로 추출돼 있고, 카하는 `CashRegisterService.getTesoreriaOverview(user)` 가 서랍 단위로 이미
구현돼 있다(raw SQL, storeId 를 쿼리 파라미터로 직접 받아 Sequelize 훅에 의존하지 않음 — `@Public()` 환경에서도
안전하게 재사용 가능). 반면 `sales.service.ts` 의 `getDailyStats()` 는 **구버전 귀속 로직**(`COALESCE(bx.branch_id,
u.branch_id)`)을 쓰고 있어 CLAUDE.md 의 `sales.branch_id` 권위 원칙과 어긋난다 — 이 함수를 재사용하지 말고
`saleBranchSql`/`signedTxSql`/`ACCOUNTING_SALE_STATUSES` 원재료로 새 쿼리를 작성할 것.

워치 쪽은 Wear OS 공식 가이드가 명확하다 — Kotlin + Jetpack Compose for Wear OS Material 3(앱 화면) +
ProtoLayout Material 3(Tile) + `ComplicationDataSourceService`(컴플리케이션)가 2026년 현재 표준이며 Flutter
로는 Tile/컴플리케이션을 못 만든다(PROPUESTA 의 판단과 일치, 공식 문서로 재확인). Google Play 배포에서 가장
중요한 실측 발견은 **`com.coolsistema.tienda_admin_app` 이 현재 release 빌드에서 디버그 키로 서명되고 있다**는
것과, Google 의 Wear OS 품질 가이드 WO-G7 이 "폰 동반 앱이 있으면 워치 앱과 **같은 서명 키**를 써야 한다" 고
명시한다는 것이다 — 이것이 W5(배포) 체크포인트 전에 사용자가 결정해야 할 새 항목이다.

**Primary recommendation:** 가드는 `admin_device_tokens` 패턴(Passport 미사용, 서비스 레이어 해시 비교) +
`JwtGlobalGuard` 와 동일한 수동 `TenantContext.resolve()` 호출로 짠다. 매출 집계는 `sale-status.constants.ts`
의 기존 SQL 조각을 조합해 새로 작성하고, 카하는 `getTesoreriaOverview()` 를 그대로 호출한다. 역할 재판정은
`AuthService.issueAccessToken()` 의 store-필터 로직을 공유 유틸로 뽑아 쓴다(각자 복붙하면 Phase 93 가 고친
"매장 필터 누락" 결함이 재발한다). Wear 앱은 Kotlin + Compose Material3 + ProtoLayout Material3, networking 은
Retrofit+OkHttp(멀티플랫폼 불필요), 토큰 저장은 `EncryptedSharedPreferences` 대신 DataStore(파일) + Android
Keystore 로 직접 암호화.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 플랫폼**: Galaxy Watch = Wear OS 전용. Apple Watch 범위 밖.
- **D-02 방식**: 워치 전용 앱(B). Kotlin + Jetpack Compose for Wear OS, 모노레포 신규 `wear-admin-app/`.
  applicationId = 휴대폰 앱과 동일 `com.coolsistema.tienda_admin_app`.
- **D-03 정보**: 오늘 매출(매장 타임존·지점별·티켓 수·어제 같은 시각 대비) + 카하 현황(서랍 단위·열림/닫힘·잔액·담당자·지난 날 미마감). **읽기 전용.**
- **D-04 배포**: **Google Play** (내부 테스트 트랙으로 시작). Play 개발자 계정·서명키 준비는 사용자 작업 — W5 체크포인트.
- **D-05 대상**: **매장 admin 만**(gerente·기타 역할 제외). 매 요청 시 현재 역할로 재판정 — admin 이 아니게 되면 즉시 401.
- **D-06 연결**: **코드 페어링** — 워치가 코드 표시 → admin 이 **휴대폰 앱(tienda-admin-app) 「Relojes」** 에서 입력. 웹 화면은 이번 범위 밖.
  워치 토큰은 `GET /watch/resumen` 전용(다른 라우트 401), 90일 sliding · 30일 유휴 · 회수 가능, 헤더로만 전달.
- **D-07 금액 표시**: **축약(M)** — 워치 앱·Tile·컴플리케이션 모두. 예: `$1,28 M`, 백만 미만은 `$842 K`, 천 미만은 그대로.
  (es-AR 소수점 콤마.)

### Claude's Discretion

- 새 테이블 이름/컬럼, 코드 길이·만료(제안: 8자 · 5분), rate limit 수치, 캐시 TTL(제안 30초).
- Tile 갱신 주기(시스템 최소 15분 근처), 오프라인 표시 문구.

### Deferred Ideas (OUT OF SCOPE)

- 푸시 알림(FCM) · Apple Watch · 웹 페어링 화면 · 기존 `/dashboards/sales/summary` 의 UTC 「오늘」 버그(별건).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| W98-01 | 요약 API (`GET /watch/resumen`) | §API 설계, §Don't Hand-Roll(매출/카하 집계 재사용), §Validation Architecture |
| W98-02 | 코드 페어링 + 워치 토큰 발급 | §인증 아키텍처(디바이스 코드 플로우), §Common Pitfalls(전역 가드 우회) |
| W98-03 | tienda-admin-app 「Relojes」 화면 | §Flutter 패턴 |
| W98-04 | Wear OS 앱(Ventas·Cajas) | §Wear OS 기술 스택, §Code Examples |
| W98-05 | Tile + 컴플리케이션 | §Tile/Complication 세부, §Common Pitfalls |
| W98-06 | Google Play 배포 | §Google Play 배포, §Package Legitimacy(해당 없음 — 패키지 설치 아님) |

## Project Constraints (from CLAUDE.md)

- DB 마이그레이션은 **로컬(5432)·운영(5434) 동시 적용** — 새 테이블은 owner/시퀀스 coolsistema 이전 DO 블록 필수(§migrations 패턴 참조).
- 무중단 규약(W4): 새 테이블은 트래픽이 없으므로 "새 테이블 면제" 해당(`-- w4-exempt: 이 phase 에서 처음 만들어져 읽는 코드가 아직 없다`) — 단 추후 컬럼 추가 시엔 expand→migrate→contract 적용.
- `stocks`/재고 관련 규약은 이 phase 와 무관(읽기 전용, 재고 비관여).
- 테넌트 격리는 절대 규칙 — `@Public()` 라우트는 컨텍스트가 비므로 직접 확정해야 한다(아래 §인증 아키텍처).
- push 는 검증 통과 후 자동(사용자 승인 불요) — 단 **Google Play 개발자 계정 등록·서명키 결정**은 사용자 작업(D-04/W5 체크포인트와 동일 선상의 "위험한 경우"는 아니지만 사용자가 가진 리소스이므로 체크포인트 유지).
- 커밋 전 훅: api tsc·eslint(추가 줄만)·jest(변경 모듈 디렉터리). Kotlin/Flutter 쪽은 이 훅 대상이 아니므로 각자 `./gradlew test`/`flutter test` 로 별도 검증 필요(§Validation Architecture).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 코드 발급·검증·회전 | API / Backend | — | 서버만이 신뢰 루트. 워치는 토큰을 저장만 한다 |
| 역할 재판정(admin 여부) | API / Backend | — | 클라이언트가 보낸 role 을 믿으면 우회 가능(agent-role-is-allowlist-only 와 동일 원칙) |
| 매출/카하 집계 | API / Backend (Database 위임) | Database / Storage | raw SQL CTE, Postgres 가 집계 수행, API 는 캐시만 |
| 코드 입력 UI | Browser/Client(Flutter, phone tier) | — | 휴대폰은 이미 JWT 세션이 있는 신뢰된 입력 채널 |
| 결과 표시(Ventas/Cajas 화면) | Wear OS 앱(Client) | — | 워치는 순수 렌더러, 계산 없음 |
| Tile 콘텐츠 갱신 | Wear OS 앱(Client, 백그라운드) | API(캐시) | TileService 가 주기적으로 API 를 호출, 서버 캐시가 부하 흡수 |
| 컴플리케이션 값 | Wear OS 앱(Client) | — | ComplicationDataSourceService, 시스템이 호출 주기를 통제 |
| 30초 캐시 | API / Backend(MemoryCacheService) | — | 워치가 수백 개여도 매장당 DB 부하 상한 고정 |

## Standard Stack

### Core (wear-admin-app — Kotlin/Wear OS)

| Library | Version (2026-10 기준) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Jetpack Compose for Wear OS (`androidx.wear.compose:compose-material3`) | **1.7.0** (2026-09-23 stable) [CITED: developer.android.com/jetpack/androidx/releases/wear-compose] | 앱 화면 UI | Google 공식 권장 UI 툴킷, Material 3 Expressive 지원 |
| ProtoLayout Material3 (`androidx.wear.protolayout:protolayout-material3`) | **1.4.2** (2026-07-29 stable) [CITED: developer.android.com/jetpack/androidx/releases/wear-protolayout] | Tile 레이아웃 | Tile 전용 선언형 레이아웃, Compose 와 별도 런타임(RemoteViews 유사) |
| Wear Tiles (`androidx.wear.tiles:tiles`) | **1.6.2** (2026-07-29 stable) [CITED: developer.android.com/jetpack/androidx/releases/wear-tiles] | TileService 기반 클래스 | 표준 Tile API |
| `androidx.wear.watchface:watchface-complications-data-source-ktx` | 최신 stable(1.2.x대, 설치 시 재확인) [ASSUMED — 버전 숫자는 미검증] | 컴플리케이션 데이터 소스 | `ComplicationDataSourceService` 공식 베이스 |
| Retrofit + OkHttp | Retrofit 2.11.x / OkHttp 4.12.x [ASSUMED — 설치 시 `./gradlew dependencies` 로 재확인] | `/watch/*` HTTP 호출 | Android 전용(멀티플랫폼 불필요)이라 Ktor 대비 이점 없음, 팀 경험·튜토리얼 풍부 [CITED: droidshubham.medium.com 비교 요약] |
| kotlinx.serialization 또는 Moshi | 최신 stable | JSON 파싱 | Retrofit 컨버터 표준 |
| Jetpack DataStore (Preferences) | 최신 stable | 워치 토큰 저장 | 아래 §보안 저장소 참조 |
| Android Keystore(직접) 또는 Tink(`com.google.crypto.tink:tink-android`) | 최신 stable | 토큰 암호화 | `EncryptedSharedPreferences` 대체 — 공식 폐기 확인됨 |
| WorkManager | 최신 stable | 오프라인 재시도·백그라운드 폴링(페어링) | 표준, Doze 모드 호환 |

### Supporting (api-ventago 신규 코드)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| 없음 — 기존 의존성(Sequelize, crypto 내장 모듈, @nestjs/throttler)만 사용 | `@nestjs/common` ^11.0.1 / `sequelize` ^6.37.5 / `@nestjs/throttler` ^6.5.0 [VERIFIED: package.json 실측] | 신규 패키지 설치 불필요 | admin-device-token.service.ts 패턴이 `crypto.createHash`/`timingSafeEqual`/`randomBytes` 만으로 충분함을 이미 증명 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Kotlin+Compose 네이티브 | Flutter on Wear OS | Tile·컴플리케이션 공식 지원 없음(PROPUESTA·공식 가이드 모두 확인) — 기각 |
| Retrofit+OkHttp | Ktor Client | 멀티플랫폼(iOS 공유) 계획이 없으므로 이점 없음. 2026 커뮤니티 컨센서스도 "Android 단독이면 Retrofit/OkHttp 가 기본값" [CITED: droidshubham.medium.com] |
| Passport `WatchTokenGuard` (vendor-jwt 식 별도 전략) | 순수 `CanActivate` 가드(전략 없이 서비스 직접 호출) | **순수 가드 채택 권장** — `admin_device_tokens` 가 이미 이 패턴이고, Passport 전략을 하나 더 추가하면 "가드가 두 번 돈다" 류 사고(route-guard-undoes-global-guard-user)의 또 다른 변종을 만들 위험. §인증 아키텍처 참조 |
| `EncryptedSharedPreferences` | DataStore + Tink/Keystore | 전자는 공식 폐기(1.1.0-alpha07, 2025-04-09) — 신규 코드에 쓰면 안 됨 [CITED: developer.android.com/reference/androidx/security/crypto/EncryptedSharedPreferences] |

**Installation (wear-admin-app, 신규 Gradle 모듈 생성 후):**
```bash
# build.gradle.kts (wear module) — 버전은 설치 시 developer.android.com/jetpack/androidx/versions 로 최종 확인
implementation("androidx.wear.compose:compose-material3:1.7.0")
implementation("androidx.wear.protolayout:protolayout-material3:1.4.2")
implementation("androidx.wear.tiles:tiles:1.6.2")
implementation("androidx.wear.watchface:watchface-complications-data-source-ktx:<latest>")
implementation("com.squareup.retrofit2:retrofit:<latest>")
implementation("com.squareup.okhttp3:okhttp:<latest>")
implementation("androidx.datastore:datastore-preferences:<latest>")
implementation("androidx.work:work-runtime-ktx:<latest>")
```

**Version verification:** 설치 직전 `https://developer.android.com/jetpack/androidx/versions` (또는 Context7 `androidx.wear.compose`)로 재확인 — 이 연구는 WebSearch 스냅샷(2026-10-04)이며 패치 릴리스가 더 나왔을 수 있다.

## Package Legitimacy Audit

> 이 phase 는 npm/PyPI/crates 패키지를 설치하지 않는다(Wear OS 쪽은 Google Maven AndroidX 공식 좌표, API 쪽은 기존 의존성 재사용). `slopcheck` 게이트는 **해당 없음**. Gradle 의존성(`androidx.*`, `com.squareup.*`)은 Google/Square 공식 배포이므로 별도 감사 불필요 — 단, 버전 문자열은 설치 시점에 `./gradlew dependencies`로 재검증할 것(위 표의 버전은 WebSearch 스냅샷).

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (해당 없음 — npm/pip 설치 없음) | — | — | — | — | — | N/A |

## Architecture Patterns

### System Architecture Diagram

```
[Galaxy Watch]                         [tienda-admin-app(Flutter, phone)]
  wear-admin-app                          "Relojes vinculados" screen
     │ 1. POST /watch/pairing-codes          │ 2. admin 이 8자리 코드 입력
     │    (unauth, rate-limited)             │    POST /watch/pairing-codes/:code/claim
     │    → {deviceCode, userCode, exp}      │    (JWT 인증, @Auth(admin))
     │                                        │
     │ 3. 화면에 userCode 표시                │
     │                                        │
     │ 4. POST /watch/pairing-codes/poll      │
     │    {deviceCode} (unauth, 반복)         │
     │    → 202 pending | 200 {watchToken}    │
     ▼                                        ▼
  ┌─────────────────────────────────────────────────┐
  │              api-ventago (NestJS)                │
  │  JwtGlobalGuard(전역) ── @Public() 라우트만 우회  │
  │                                                   │
  │  /watch/pairing-codes/*  → PairingController      │
  │     (코드 생성은 @Public()+rate-limit,            │
  │      claim 은 @Auth(admin)+JWT)                   │
  │                                                   │
  │  /watch/resumen → WatchController                 │
  │     @Public() + @UseGuards(WatchTokenGuard)        │
  │     WatchTokenGuard:                               │
  │       1. x-watch-token 헤더 해시 조회(watch_devices)│
  │       2. 회수/만료/유휴 체크                        │
  │       3. 현재 역할 재조회(store-필터 공유 유틸)      │
  │       4. admin 아니면 401 + 토큰 자동 회수(선택)     │
  │       5. TenantContext.resolve() 수동 호출          │
  │       6. request.user = {id, storeId, roles,        │
  │                           branchId} 로 주입          │
  │              │                                      │
  │              ▼                                      │
  │  WatchService.getResumen(user)                      │
  │     ├─ MemoryCacheService.getOrLoad(storeKey(...))   │
  │     │    30초 TTL                                    │
  │     ├─ ventas: 신규 SQL (saleBranchSql·signedTxSql·  │
  │     │    EXCLUDE_DEUDA_PAGO_SQL 조합, 매장 타임존)    │
  │     └─ cajas: CashRegisterService                    │
  │              .getTesoreriaOverview(user) 그대로 호출 │
  └─────────────────────────────────────────────────┘
              │
              ▼
        PostgreSQL(sales, sale_items, boxes, cash_registers,
                    box_operations, branches, stores)
```

### Recommended Project Structure

```
wear-admin-app/                      # 신규 Gradle/Kotlin 모노레포 루트
├── app/
│   ├── src/main/
│   │   ├── AndroidManifest.xml      # android.hardware.type.watch, standalone=true
│   │   ├── java/.../
│   │   │   ├── pairing/             # PairingScreen, PairingViewModel
│   │   │   ├── ventas/              # VentasScreen
│   │   │   ├── cajas/               # CajasScreen
│   │   │   ├── data/
│   │   │   │   ├── WatchApi.kt      # Retrofit interface
│   │   │   │   ├── TokenStore.kt    # DataStore+Keystore
│   │   │   │   └── ResumenRepository.kt
│   │   │   ├── tile/
│   │   │   │   └── ResumenTileService.kt
│   │   │   └── complication/
│   │   │       └── VentasComplicationService.kt
│   │   └── res/
│   └── build.gradle.kts
└── build.gradle.kts

api-ventago/src/app/watch/            # 신규 NestJS 모듈
├── watch.module.ts
├── watch-device.model.ts             # watch_devices 테이블
├── watch-pairing.controller.ts       # 코드 발급/claim/poll
├── watch-pairing.service.ts
├── watch-token.guard.ts              # CanActivate, passport 아님
├── watch-resumen.controller.ts       # GET /watch/resumen
├── watch-resumen.service.ts          # ventas SQL + getTesoreriaOverview 위임
└── *.spec.ts                         # 범위·회수·스코프·타임존 돌연변이 테스트

tienda-admin-app/lib/features/relojes/
├── relojes_screen.dart
└── relojes_repository.dart           # caja_repository.dart 패턴 그대로
```

### Pattern 1: 전역 Passport 가드를 우회하는 "서비스 레이어 인증" (admin_device_tokens 패턴 재사용)

**What:** `/auth/device/refresh`·`/auth/device/revoke` 는 `@Public()` 로 `JwtGlobalGuard`(Passport)를
완전히 건너뛰고, 컨트롤러가 받은 토큰 문자열을 **서비스 레이어에서 직접 해시·조회·만료 판정**한다. Passport
전략을 새로 등록하지 않는다.

**When to use:** 이 phase 의 워치 토큰처럼 "JWT 가 아닌 별도 장기 자격증명으로 단 하나의 엔드포인트만 여는"
경우. Passport 전략을 또 하나 만들면(`vendor-jwt` 식) 전략 등록·모듈 배선이 늘고, "가드가 여러 번 돈다" 류
결함의 표면적이 넓어진다.

**Example:**
```typescript
// Source: api-ventago/src/app/auth/admin-device-token.service.ts (실측, 2026-10-04)
// 이 파일의 register/refresh/revokeByToken 패턴을 watch_devices 에도 그대로 적용한다.
// 차이점: watch 토큰은 "회전"하지 않는다(요구사항에 회전 명시 없음 — sliding expiry만).
//         단일 엔드포인트 스코프이므로 범위 검사가 하나 더 필요(다른 라우트 401).

@Injectable()
export class WatchTokenGuard implements CanActivate {
  constructor(private readonly watchDeviceService: WatchDeviceService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const token = request.headers['x-watch-token'];
    if (!token || typeof token !== 'string') {
      throw new UnauthorizedException();
    }

    // register()/refresh() 와 동일한 sha256 해시 조회 + isUsable() 판정 재사용
    const device = await this.watchDeviceService.resolveUsable(token);
    if (!device) throw new UnauthorizedException();

    // ★ 매 요청 현재 역할 재판정 — store-필터 공유 유틸(아래 Pattern 2) 사용
    const { user, roles } = await this.watchDeviceService.currentUserAndRoles(
      device.userId,
    );
    if (user.status !== 'active' || !roles.includes('admin')) {
      // 선택: 여기서 device 를 회수할지(D-05 "즉시 401"은 회수까지 요구하진 않음 — 매
      // 요청 재판정이면 충분. 회수는 "admin 해제가 영구적"이란 신호가 있을 때만)
      throw new UnauthorizedException();
    }

    // ★ JwtGlobalGuard 와 동일하게 테넌트 컨텍스트를 **직접** 확정한다.
    //   @Public() 라우트는 미들웨어가 심은 pending 컨텍스트만 있고 아무도 resolve()
    //   하지 않으므로, 여기서 안 하면 이후 Sequelize 모델 쿼리(쓰면 안 되지만 실수로
    //   섞일 경우)가 전부 무격리로 돈다.
    TenantContext.resolve({
      storeId: user.storeId,
      isSuperAdmin: false,
      userId: user.id,
    });

    request.user = {
      id: user.id,
      storeId: user.storeId,
      branchId: user.branchId,
      roles,
    };
    request.watchDevice = device; // lastSeenAt 갱신 등에 사용

    return true;
  }
}
```

### Pattern 2: 역할 재판정은 공유 유틸로 — `issueAccessToken()` 중복 금지

**What:** `AuthService.issueAccessToken()` 안에 `user.userRoles.filter(ur => ur.role?.storeId ===
user.storeId)` 가 있다. 이 필터가 없으면(= `UsersService.shapeAuthUser()` 처럼) 다른 매장의 `admin` 행
하나로 가드가 뚫린다(memory: user-roles-need-store-filter).

**When to use:** `WatchTokenGuard` 가 역할을 다시 조회할 때. **절대 `shapeAuthUser()` 의 `roles` 를 쓰지
말 것** — 그 경로는 매장 필터가 없는 유일한 자리로 알려져 있다.

**Example:**
```typescript
// Source: api-ventago/src/app/auth/auth.service.ts:730-752 (실측) 를 추출한 형태.
// 신규 유틸로 뽑아 issueAccessToken() 과 WatchTokenGuard 가 같이 쓴다(복붙 금지).
export async function resolveStoreFilteredRoles(userId: number): Promise<{
  user: Users;
  roles: string[];
}> {
  const user = await Users.findOne({
    where: { id: userId },
    include: [{ model: UserRole, include: [{ model: Role, attributes: ['slug', 'storeId'] }] }],
  });
  if (!user) throw new UnauthorizedException();

  const roles = (user.userRoles || [])
    .filter((ur) => ur.role?.storeId === user.storeId)
    .map((ur) => ur.role?.slug)
    .filter((s): s is string => Boolean(s));

  return { user, roles };
}
```

### Pattern 3: RFC 8628 디바이스 코드 — `user_code` 와 `device_code` 분리

**What:** 표준 OAuth Device Authorization Grant(RFC 8628)는 **두 개의 다른 코드**를 쓴다 —
사람이 입력하는 짧은 `user_code`(화면에 표시, 브루트포스 방어 대상)와, 기기가 폴링에 쓰는 긴/추측 불가능한
`device_code`(URL/바디에만, 범위가 "그 페어링 세션 하나"). PROPUESTA 는 이를 "8자리 코드 하나"로 합쳐
뒀는데, 그렇게 하면 **폴링 엔드포인트 자체가 브루트포스 표적**이 된다(워치가 보내는 값과 화면에 보이는 값이
같으므로, 폴링 API 에 무작위 8자리를 시도하는 것이 곧 코드 추측이 된다).

**When to use:** W1 페어링 설계. `userCode`(8자, 사람이 입력, rate-limit 엄격) 와 `deviceCode`(32바이트
random, base64url, 워치만 보관, rate-limit 느슨)를 분리할 것을 권장.

**Example:**
```jsonc
// POST /watch/pairing-codes (unauth, IP rate-limit)
// → {
//     "userCode": "K7Q4-29XM",     // 사람이 입력, 5분 만료
//     "deviceCode": "9f2a...(32B base64url)", // 워치가 폴링에 사용
//     "expiresIn": 300,
//     "interval": 5                 // 폴링 최소 간격(초) — RFC 8628 §3.2
//   }

// POST /watch/pairing-codes/poll  { "deviceCode": "9f2a..." }  (unauth)
// → 202 { "status": "pending" }  또는
//   200 { "watchToken": "...", "expiresAt": "..." }  또는
//   410 { "status": "expired" }

// POST /watch/pairing-codes/:userCode/claim  (JWT, @Auth(admin), tienda-admin-app 호출)
// → 204
```
Source: RFC 8628 §3 흐름 요약 [CITED: rfc-editor.org/info/rfc8628, oauth.net/2/grant-types/device-code]

### Anti-Patterns to Avoid

- **Passport 전략을 또 하나 등록(`watch-jwt`)**: vendor-jwt 와 패턴은 비슷해 보이지만, 이 저장소에서
  `AuthGuard('jwt')` 를 라우트 레벨에 또 붙이면 "전역 가드가 채운 request.user 를 뒤의 가드가 passport 를
  다시 돌려 지운다"(memory: route-guard-undoes-global-guard-user)는 사고가 **이미 한 번 일어났다.** 워치
  라우트는 전역 가드를 `@Public()` 로 완전히 피하고 수동으로 컨텍스트를 세우는 것이 더 안전하다.
- **`getDailyStats()` 재사용**: 구버전 `COALESCE(bx.branch_id, u.branch_id)` 귀속이라 CLAUDE.md 가 명시한
  "sales.branch_id 가 권위" 원칙과 다르다. 새 쿼리를 `saleBranchSql()` 로 짤 것.
  ⚠ 이 불일치 자체가 기존 결함일 수 있음 — 이 phase 범위는 아니지만 발견 사실을 기록한다(별건 처리 권장).
- **카하 잔액 공식 재구현**: CLAUDE.md 가 "카하 잔액 계산식이 9곳에 복붙돼 있다" 고 명시 경고. `getTesoreriaOverview()` 를 그대로 호출할 것, SQL 을 베끼지 말 것.
- **`shapeAuthUser().roles` 사용**: 매장 필터가 없는 유일한 경로(Pattern 2 참조).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|--------------|-----|
| 카하 서랍별 잔액·열림 상태 | 새 raw SQL | `CashRegisterService.getTesoreriaOverview(user)` | 이미 서랍 단위·지점 스코프·잔액 공식 구현됨, 9곳 중복의 10번째를 만들지 않는다 |
| 판매 지점 귀속 | `terminal→box→branch` 조인 | `saleBranchSql()` (`sale-status.constants.ts`) | `sales.branch_id` 가 트리거로 채워진 권위 컬럼, 취소 역분개는 원본 지점을 써야 함(이미 처리됨) |
| 취소 건수 집계 | `COUNT(*)` | `signedTxSql()` | 취소 쌍을 ±1 로 상계, COUNT(*) 는 2건으로 센다 |
| 역할 조회 | `user.roles` 또는 `shapeAuthUser()` | `issueAccessToken()` 의 store-필터 로직(공유 유틸로 추출) | 매장 필터 누락 결함이 이미 한 번 있었다 |
| 토큰 해시 비교 | `===` | `timingSafeEqual` + 길이 사전 비교(admin-device-token.service.ts 패턴) | 타이밍 공격 방어, 이미 검증된 구현 있음 |
| 매장 타임존 "오늘" 계산 | `new Date().setHours(0,0,0,0)` | `Intl.DateTimeFormat('en-CA', {timeZone})` 패턴(cashRegister.service.ts의 `getNowByTimezone`) | 컨테이너가 UTC 라 자정 계산이 다른 함수(`dashboards/sales/summary`)에서 이미 버그를 냈다(PROPUESTA §2 부수 발견) |
| EncryptedSharedPreferences | 자체 AES 구현 | DataStore + Android Keystore(직접) 또는 Tink | 공식 API 자체가 폐기됐으므로 새 코드에 넣으면 바로 레거시 |
| Tile 갱신 스케줄링 | `AlarmManager` 수동 | `setFreshnessIntervalMillis()` + 시스템 `onTileRequest()` 콜백 | 시스템이 배터리 최적화까지 관리, 직접 구현하면 심사에서 걸릴 수 있음(WO-P7 류 배터리 가이드) |

**Key insight:** 이 저장소는 "집계 공식이 여러 곳에 복붙돼 갈라진" 사고를 반복적으로 겪었다(카하 잔액 9곳,
판매 지점 귀속, credit open 잔액 등 — 전부 MEMORY.md 에 기록됨). 이 phase 의 집계 로직은 **전부 기존 함수
재사용 또는 그 함수가 쓰는 SQL 조각의 조합**이어야 한다. 새 숫자 공식을 작성하는 순간 "10번째 복붙"이 된다.

## Common Pitfalls

### Pitfall 1: `@Public()` 라우트에서 Sequelize 모델 쿼리를 쓰면 테넌트 격리가 통째로 빠진다
**What goes wrong:** `/watch/resumen` 핸들러 안에서(또는 그 서비스가 호출하는 어떤 헬퍼든) `Sale.findAll({
where: {...} })` 같은 Sequelize 모델 쿼리를 쓰면, `@Public()` 라우트엔 테넌트 컨텍스트가 없어 `installTenantGuard`
훅이 no-op 이 되고 **storeId 필터 없이** 전 매장을 조회한다.
**Why it happens:** 이 저장소의 테넌트 격리는 JWT 인증 성공 후 `JwtGlobalGuard` 가 컨텍스트를 확정하는 구조라서,
그 가드를 피하는 모든 라우트(웹훅·공개몰 등)는 구조적으로 이 위험을 안고 있다.
**How to avoid:** ① `WatchTokenGuard` 안에서 Pattern 1처럼 `TenantContext.resolve()` 를 직접 호출한다.
② 그래도 `/watch/resumen` 의 모든 쿼리는 **raw SQL + `storeId` 를 쿼리 파라미터로 명시**(getTesoreriaOverview
와 동일 스타일)하도록 강제한다 — 훅에 기대지 않는 이중 방어.
**Warning signs:** 코드 리뷰에서 `Sale.findAll`/`Box.findAll` 같은 모델 메서드가 watch 모듈에 보이면 멈출 것.

### Pitfall 2: 워치 토큰의 "다른 라우트 401" 요구사항은 가드 하나로 자동으로 안 지켜진다
**What goes wrong:** `WatchTokenGuard` 를 `/watch/resumen` 에만 붙이는 것은 쉽지만, **다른 모든 라우트에서
같은 토큰이 거부되는지**는 별개로 검증해야 한다 — JWT 가 아니므로 `JwtGlobalGuard`(Passport `jwt` 전략)에
아예 안 걸리고, `@Public()` 이 아닌 라우트는 "Authorization 헤더 없음" 으로 401 이 날 것 같지만, 워치 토큰을
실수로 `Authorization: Bearer <watchToken>` 으로 보내면 JWT 파싱이 실패해 역시 401 이 되어 **우연히 통과하는
테스트**를 만들기 쉽다. 진짜 위험은 누군가 나중에 다른 `@Public()` 라우트에 `WatchTokenGuard` 를 재사용하는
것이다.
**How to avoid:** `watch_devices` 테이블에 `scope` 같은 컬럼을 안 둬도 되는 이유는 "이 가드가 선언적으로
`/watch/resumen` 하나에만 import 돼 있다" 는 사실 자체가 범위이기 때문이다 — 대신 jest 로 **"WatchTokenGuard 를
다른 컨트롤러 파일이 import 하지 않는다"** 를 정적으로 단언(tenant-guard-coverage.spec.ts 류 소스 문자열 검사
패턴)하거나, 최소한 itest 로 "유효한 워치 토큰 + `/sales` 호출 → 401" 을 명시 확인한다.

### Pitfall 3: Tile/Complication 은 "15분마다 갱신"이 보장이 아니다
**What goes wrong:** PROPUESTA 의 "Tile 15분(시스템 최소)" 를 하드 보장으로 설계하면, 실측에서 훨씬 느리게
갱신되는 기기가 나와 "왜 오래된 값이 보이냐"는 버그 리포트로 이어진다.
**Why it happens:** `setFreshnessIntervalMillis()` 요청은 "최대 분당 1회로 스로틀, inexact, 경과시간 기준"
이라고 공식 문서가 명시한다 — 정확한 wall-clock 주기가 아니다. 배터리 상태·Doze·OS 버전에 따라 갱신이 밀릴 수
있다.
**How to avoid:** Tile/컴플리케이션 UI 에 **반드시 "마지막 갱신 후 경과 시간"**(목업의 "hace 12 min")을 같이
표시한다(이미 D-07/목업에 반영돼 있음 — 설계는 맞다, 구현에서 이 문구를 생략하지 않는 것이 핵심).
**Warning signs:** QA 체크리스트에 "비행기 모드에서 24시간 방치 후 값/문구 확인"을 넣을 것.

### Pitfall 4: Google Play 서명 키 — 디버그 키로 만든 사이드로드 APK 와 Play 업로드가 섞인다
**What goes wrong:** `tienda-admin-app/android/app/build.gradle.kts` 의 release 빌드가 현재 **debug
서명 키**를 쓴다(`signingConfig = signingConfigs.getByName("debug")`, 실측 2026-10-04). Google Play
Console 은 debug 인증서로 서명된 아티팩트를 **업로드 자체를 거부**한다. 또한 Wear OS 품질 가이드 WO-G7 은
"폰 동반 앱이 있으면 워치 앱과 **같은 서명 키**를 써야 한다"고 명시한다.
**Why it happens:** 지금까지 폰 앱은 Play 를 거치지 않고 Dropbox 로 사이드로드됐기 때문에 서명 키 품질이
문제된 적이 없었다.
**How to avoid:** W5 이전에 **신규 release keystore 를 만들어 안전하게 보관**(비밀번호 관리자 등)하고,
① wear-admin-app 를 그 키로 서명해 Play 에 업로드, ② (이 phase 범위 밖이지만) 언젠가 폰 앱도 Play 에
올릴 계획이면 그 keystore 를 재사용하도록 `build-apk.sh`/`build.gradle.kts` 를 나중에 맞출 것 — 지금
당장 폰 앱 서명을 바꾸지는 않는다(범위 확대 금지, 별건).
**Warning signs:** `flutter build apk --release` 로 만든 산출물과 wear 모듈의 keystore 가 다른지 확인.

### Pitfall 5: Android/Gradle 로컬 빌드에 `JAVA_HOME` 이 안 잡혀 있다
**What goes wrong:** 이 Mac 셸에는 시스템 `java` 가 없다(`java -version` → "Unable to locate a Java
Runtime"). Flutter 는 Android Studio 번들 JBR 을 자동으로 찾지만(`/Applications/Android Studio.app/
Contents/jbr`), `sdkmanager`/순수 Gradle CLI 를 **셸에서 직접** 호출하면(Wear 에뮬레이터 이미지 설치,
수동 Gradle 빌드 등) `JAVA_HOME` 미설정으로 실패한다.
**How to avoid:**
```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
```
**Warning signs:** `sdkmanager --list` 가 "Unable to locate a Java Runtime" 로 죽으면 이 환경변수 누락.

## Code Examples

### 캐시 적용 (30초 TTL, storeKey)
```typescript
// Source: api-ventago/src/common/cache/memory-cache.service.ts (실측 getOrLoad 계약)
const key = storeKey('watch:resumen', user.storeId);
const resumen = await this.memoryCache.getOrLoad(key, 30_000, async () => {
  const ventas = await this.computeVentasHoy(user.storeId);
  const cajas = await this.cashRegisterService.getTesoreriaOverview(user as Users);
  return { ventas, cajas, actualizado: new Date().toISOString() };
});
```

### 매출 SQL 뼈대(새로 작성 — `getDailyStats()` 재사용 금지)
```sql
-- Source: 조합 — saleBranchSql()/signedTxSql()/EXCLUDE_DEUDA_PAGO_SQL()/ACCOUNTING_SALE_STATUSES
-- (api-ventago/src/app/sales/sale-status.constants.ts, 실측)
SELECT
  ${saleBranchSql('s')} AS branch_id,
  ${signedTxSql('s')} AS tickets,
  COALESCE(SUM(s.total_amount), 0) AS total
FROM sales s
WHERE s.store_id = :storeId
  AND s.activity_type = 'sale'
  AND s.status IN (${ACCOUNTING_SALE_STATUSES.map(st => `'${st}'`).join(',')})
  AND ${EXCLUDE_DEUDA_PAGO_SQL('s')}
  AND DATE(s.sale_date AT TIME ZONE :tz) = :today
GROUP BY ${saleBranchSql('s')}
-- "어제 같은 시각" 비교는 같은 조건에 DATE(...) = :yesterday
-- AND (s.sale_date AT TIME ZONE :tz)::time <= :nowTime 을 추가해 별도 질의
```

### Wear OS — ComplicationDataSourceService 뼈대
```kotlin
// Source: 공식 패턴 요약 (developer.android.com/training/wearables/complications/exposing-data,
// developer.android.com/reference/kotlin/androidx/wear/watchface/complications/datasource/ComplicationDataSourceService)
class VentasComplicationService : ComplicationDataSourceService() {
    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener,
    ) {
        val cached = TokenStore.lastResumen() // 로컬 캐시, 네트워크 안 함(시스템이 빈번히 호출 가능)
        val text = cached?.ventasAbreviado ?: "—"
        listener.onComplicationData(
            ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder(text).build(),
                contentDescription = PlainComplicationText.Builder("Ventas hoy").build(),
            ).build(),
        )
    }

    override fun onComplicationDeactivated(complicationInstanceId: Int) {}
    override fun getPreviewData(type: ComplicationType) = /* 미리보기용 고정 샘플 */ TODO()
}
```
```xml
<!-- AndroidManifest.xml — UPDATE_PERIOD_SECONDS 는 최소 5분(300), 0 이면 push-style -->
<service android:name=".complication.VentasComplicationService"
    android:exported="true"
    android:permission="com.google.android.wearable.permission.BIND_COMPLICATION_PROVIDER">
  <meta-data android:name="android.support.wearable.complications.SUPPORTED_TYPES"
      android:value="SHORT_TEXT" />
  <meta-data android:name="android.support.wearable.complications.UPDATE_PERIOD_SECONDS"
      android:value="900" />
</service>
```

### Wear OS — Standalone 매니페스트 선언
```xml
<!-- Source: developer.android.com/training/wearables/apps/standalone-apps -->
<uses-feature android:name="android.hardware.type.watch" />
<application>
  <meta-data android:name="com.google.android.wearable.standalone" android:value="true" />
</application>
```

### Flutter — 「Relojes vinculados」 리포지토리 뼈대
```dart
// Source: tienda-admin-app/lib/features/caja/caja_repository.dart 패턴 그대로 적용
class RelojesRepository {
  final Dio dio;
  RelojesRepository(this.dio);

  Future<List<WatchDevice>> listDevices() async {
    final res = await dio.get('/watch/devices');
    return (res.data as List).map((j) => WatchDevice.fromJson(j)).toList();
  }

  Future<void> claimCode(String userCode) =>
      dio.post('/watch/pairing-codes/$userCode/claim');

  Future<void> revoke(int id) => dio.delete('/watch/devices/$id');
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `EncryptedSharedPreferences` | DataStore + Tink/Keystore | Jetpack Security 1.1.0-alpha07, 2025-04-09 | 신규 Android 보안 저장 코드는 전자를 쓰면 안 됨 |
| Wear OS Tiles(레거시 XML `TileBuilders`) | ProtoLayout Material3(`protolayout-material3`) | 2026 릴리스(1.4.2, 07-29) | Material 3 Expressive 컴포넌트·3-slot 레이아웃·Lottie 지원 |
| Wear Compose(구 Material) | Wear Compose Material3(1.7.0, 09-23) | 2026 | 최신 Expressive 디자인 토큰 |
| targetSdk 31 이하로도 Play 통과 | **targetSdk 34(API 14) 이상 필수**(WO-P1, 2025-08-31부터) | 2025-08-31 | 이 phase 신규 앱은 애초에 최신 타깃이라 문제 없음, 명시적으로 확인할 것 |
| 32-bit만 지원 가능 | **64-bit 필수**(2026-09-15부터) | 2026-09-15(이미 지난 날짜, 2026-10-04 기준) | arm64-v8a/x86_64 이미지만 빌드하면 자동 충족 |

**Deprecated/outdated:**
- `EncryptedSharedPreferences`/`EncryptedFile`: 공식 유지보수 종료, 커뮤니티 포크(SafeBox 등)만 남음.
- `(Deprecated) Exposing data to watch face complications` 코드랩 — 공식 문서에 "Deprecated" 표시, 최신은
  `developer.android.com/training/wearables/complications/exposing-data`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|----------------|
| A1 | `androidx.wear.watchface:watchface-complications-data-source-ktx` 및 Retrofit/OkHttp/DataStore/WorkManager 의 정확한 최신 버전 숫자 | §Standard Stack | 낮음 — Gradle 이 `./gradlew dependencies`/버전 카탈로그로 빌드 시점에 쉽게 재확인되는 영역, 패치 버전 차이는 기능에 영향 적음 |
| A2 | Google Play WO-G7("동반 폰 앱과 같은 서명 키")이 **Play Console 에 오직 Wear 폼팩터만 등록하고 폰 앱은 전혀 업로드하지 않는** 이번 케이스에 실제로 **review 단계에서 강제되는지** | §Google Play 배포 / Pitfall 4 | 중간 — 틀렸다면 당장은 debug-key 로도 Wear-only 업로드가 통과할 수 있으나, 나중에 폰 앱을 같은 Play 리스팅에 추가하려 할 때 재서명 비용이 발생. 안전하게는 처음부터 release keystore 를 쓰는 쪽이 리스크가 적음 |
| A3 | Tile 시스템 "최소 15분" 이 PROPUESTA 의 가정대로 실제 배터리 친화적 권장값인지(공식 문서는 "분당 1회 스로틀"만 명시, 15분이라는 숫자 자체는 못 찾음) | §Common Pitfalls 3 / Tile 갱신 | 낮음 — 어느 쪽이든 "마지막 갱신 경과 시간 표시"로 설계가 흡수하므로 정확한 숫자가 틀려도 사용자 경험이 깨지지 않음 |
| A4 | `watch_devices` 테이블에 "회전"이 필요 없다(요구사항에 명시 안 됨, admin_device_tokens 와 달리 폰 분실 시나리오가 아니라 워치 분실 시나리오라 회전 가치가 낮다고 판단) | §인증 아키텍처 / 테이블 설계 | 중간 — 틀렸다면 유출된 워치 토큰이 90일 내내 유효(단, 유휴 30일·즉시 회수 가능은 동일 적용되므로 영향 제한적) |
| A5 | gerente 는 D-05 확정으로 완전히 배제되므로 `resolveAllowedBranchIds` 호출이 사실상 불필요(admin 은 항상 `null`=전 지점) | §Architectural Responsibility Map | 낮음 — 나중에 gerente 를 허용하기로 바뀌면 `getTesoreriaOverview` 가 이미 그 분기를 처리하므로 재사용만 하면 됨 |

**사용자 확인이 필요한 항목:** A2(서명 키 전략), A4(토큰 회전 여부) — 둘 다 W1 설계 전에 /gsd:discuss-phase 또는
플래너가 명시적으로 결정해야 한다.

## Open Questions

1. **서명 키 전략(A2 연장)**
   - What we know: 현재 폰 앱 release 빌드는 debug 키. WO-G7 은 "동반 앱과 같은 키" 요구.
   - What's unclear: 이번 phase 가 "Wear OS 전용 폼팩터만" Play 에 올리는 것이므로 review 가 실제로
     WO-G7 을 걸고넘어질지, 아니면 폰 앱이 Play 에 없으므로 통과할지.
   - Recommendation: 보수적으로 **새 release keystore 를 지금 만들어** wear-admin-app 서명에 쓰고, 안전하게
     백업해 둔다(향후 폰 앱도 재사용 가능하도록). W5 체크포인트에서 사용자와 확정.

2. **코드/디바이스 코드 테이블 설계 세부(Claude's Discretion 영역이지만 구조 결정 필요)**
   - What we know: PROPUESTA 제안은 "8자 · 5분", 단일 코드.
   - What's unclear: `userCode`/`deviceCode` 분리(Pattern 3 권장) 채택 여부는 플래너가 테이블 컬럼 설계 시
     확정해야 함 — `watch_devices` 에 `pairing_user_code_hash`/`pairing_device_code_hash` 2컬럼이 될지,
     별도 `watch_pairing_codes` 테이블이 될지.
   - Recommendation: 별도 임시 테이블(`watch_pairing_codes`, TTL 5분, claim 성공 시 `watch_devices` 행
     생성 후 삭제)을 권장 — `admin_device_tokens` 와 섞이지 않게, 그리고 영구 테이블에 휘발성 페어링 상태를
     안 남기기 위해.

3. **Flutter 「Relojes」 화면 진입 위치**
   - What we know: `AppShell` 은 고정 5탭 하단 네비(Panel/Caja/Reportes/Usuarios/Actividad), 새 탭 추가는
     언급 없음.
   - What's unclear: 어디서 진입할지(예: Usuarios 탭 안의 서브메뉴, 또는 AppBar 액션 아이콘, 또는
     Configuración 류 설정 화면 — 이 앱엔 명시적 설정 탭이 없음).
   - Recommendation: 플래너가 UI 배치를 정할 때 PROPUESTA 의 "휴대폰 앱 Relojes" 라는 표현만 있고 정확한
     진입 경로가 없으므로, discuss-phase 또는 플래닝 단계에서 사용자에게 1줄 확인 권장(막다른 경로를
     만들지 않기 위해 — memory: dead-end-cta-is-worse-than-none).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Android SDK (cmdline-tools) | wear-admin-app 빌드 | ✓ | platform 34/35/36, build-tools 35/36 [VERIFIED: sdkmanager --list_installed 실측] | — |
| JDK | Gradle/sdkmanager 직접 호출 | ✓(간접) | OpenJDK 25.0.2 (Android Studio 번들 JBR) [VERIFIED: 실측] | `JAVA_HOME` 수동 export 필요(Pitfall 5) |
| Wear OS 에뮬레이터 시스템 이미지 | 로컬 Wear 에뮬레이터 테스트 | ✗ | — | `sdkmanager "system-images;android-36;android-wear-signed;arm64-v8a"` 설치(Wear OS 6, Galaxy Watch6/7/8 현재 버전과 매치) [VERIFIED: sdkmanager --list 실측, 2026-10-04] |
| Android Emulator 바이너리 | 위와 동일 | △(미확인 설치여부, 패키지 자체는 가용) | emulator 37.2.12 [VERIFIED: sdkmanager --list 실측] | `sdkmanager emulator` 로 설치 |
| Flutter SDK | tienda-admin-app 화면 추가 | ✓ | pubspec `sdk: ^3.11.0` [VERIFIED: pubspec.yaml 실측] | — |
| GitHub Actions | Wear 앱 자동 빌드 | ✗ | — | 결제 문제로 중단 상태(memory: github-actions-not-running-billing) — 로컬 빌드만 |
| Google Play 개발자 계정 | W98-06 배포 | ✗(사용자 소유, 미확인) | $25 1회 등록비, 2026 기준 변동 없음 [CITED: 복수 소스 교차검증] | W5 체크포인트에서 사용자가 준비 |
| 실기기 Galaxy Watch | 최종 검증 | 미확인(이 세션에서 확인 불가) | — | 에뮬레이터로 1차 검증 후 실기기 필수(ADB wireless debugging) |

**Missing dependencies with no fallback:**
- 없음 — 전부 설치 가능하거나 로컬 빌드로 우회 가능.

**Missing dependencies with fallback:**
- Wear 에뮬레이터 이미지·emulator 패키지: `sdkmanager` 설치 커맨드로 해결.
- GitHub Actions: 로컬 `flutter build`/`./gradlew` 빌드로 대체(이미 phone 앱이 이렇게 배포 중).

## Validation Architecture

> `workflow.nyquist_validation` 키는 `.planning/config.json` 에서 확인 필요(이 세션에서 직접 읽지 않음 —
> 플래너가 생성 시 재확인할 것). 부재 시 활성으로 간주해 아래 섹션을 포함한다.

### Test Framework

| Property | Value |
|----------|-------|
| Framework(api) | Jest 29.7.0 [VERIFIED: package.json] |
| Config file(api) | `api-ventago/package.json` 내 `jest` 키 (testRegex `.*\.spec\.ts$`) |
| Quick run command(api) | `cd api-ventago && npx jest src/app/watch --maxWorkers=1` (memory: jest-maxworkers-1-required — 전체 jest 는 반드시 `--maxWorkers=1`) |
| Full suite command(api) | 변경 모듈 디렉터리 스코프(`--findRelatedTests` 금지 — memory: scoped jest 가 17 suites 를 끌어온 전례) |
| Framework(wear) | JUnit4/5 + Kotlin(Android Gradle 기본), 신규 모듈이라 설정 0부터 |
| Quick run command(wear) | `cd wear-admin-app && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:testDebugUnitTest` |
| Framework(flutter) | `flutter_test`(기존 `tienda-admin-app/test/` 디렉터리 존재, 패턴 확인 필요) |
| Quick run command(flutter) | `cd tienda-admin-app && flutter test test/features/relojes` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|---------------------|-------------|
| W98-01 | `/watch/resumen` 이 매장 타임존 "오늘" 매출을 반환 | unit+itest | `npx jest src/app/watch/watch-resumen --maxWorkers=1` | ❌ Wave 0 |
| W98-01 | 취소 쌍(Anulado+Anulación)이 상계되어 집계된다 | unit(돌연변이 대상) | 같은 파일, `signedTxSql`/`ACCOUNTING_SALE_STATUSES` 사용 여부 단언 | ❌ Wave 0 |
| W98-01 | 카하 응답이 `getTesoreriaOverview` 결과와 일치 | itest | `npx jest src/app/watch/watch-resumen.itest --maxWorkers=1` | ❌ Wave 0 |
| W98-02 | 워치 토큰으로 `/watch/resumen` 외 라우트 호출 시 401 | itest(돌연변이로 가드 제거 확인) | `npx jest src/app/watch/watch-token.guard --maxWorkers=1` | ❌ Wave 0 |
| W98-02 | 회수된 토큰 즉시 401 | unit | 같은 파일 | ❌ Wave 0 |
| W98-02 | admin 해제된 사용자 다음 요청부터 401(역할 재판정) | unit | 같은 파일, Pattern 2 유틸 모킹 | ❌ Wave 0 |
| W98-02 | 타임존 경계(AR 21:00~24:00 UTC)에 매출이 "오늘"에 남음 | unit | 같은 watch-resumen 스펙에 타임존 고정 테스트 케이스 | ❌ Wave 0 |
| W98-03 | 「Relojes」 화면에서 코드 입력→claim 호출 | widget test | `flutter test test/features/relojes/relojes_screen_test.dart` | ❌ Wave 0 |
| W98-04 | Ventas/Cajas 화면 렌더(금액 축약 포맷 `$1,28 M`) | unit(Kotlin, 포맷 함수만 분리) | `./gradlew :app:testDebugUnitTest --tests "*AmountFormat*"` | ❌ Wave 0 |
| W98-05 | Tile/컴플리케이션 — 자동화 불가(시스템 콜백 의존) | manual-only | — (에뮬레이터+실기기 수동 확인, 아래 근거) | — |

**W98-05 manual-only 근거:** `ComplicationDataSourceService.onComplicationRequest`/`TileService.onTileRequest`
는 시스템이 호출 시점을 결정하므로 결정론적 유닛 테스트로 "실제 갱신 주기"를 검증할 수 없다. 포맷팅 함수
(금액 축약 등)만 유닛 테스트로 분리하고, 실제 Tile/컴플리케이션 동작은 에뮬레이터+실기기 수동 체크리스트로
검증한다(PROPUESTA §7 의 "비행기 모드에서 마지막 값 표시" 포함).

### Sampling Rate

- **Per task commit(api):** `npx jest src/app/watch --maxWorkers=1`
- **Per wave merge(api):** 전체 jest(`npm test` 수준, `--maxWorkers=1` 필수) + `migration-conventions.spec.ts`(새 마이그레이션 파일 검사)
- **Per task commit(wear/flutter):** 각 서브프로젝트 로컬 테스트(위 명령) — api 커밋 게이트(`.claude/hooks/verify-before-commit.sh`)는 Kotlin/Flutter 변경을 검사하지 않으므로 **수동으로 돌릴 것**.
- **Phase gate:** 실데이터 대조(PROPUESTA §7) — 운영 매장 하나로 `/watch/resumen` 값과 웹 Tesorería·판매 목록 합계 비교.

### Wave 0 Gaps

- [ ] `api-ventago/src/app/watch/watch-resumen.spec.ts` — W98-01 매출/카하/타임존
- [ ] `api-ventago/src/app/watch/watch-token.guard.spec.ts` — W98-02 범위·회수·역할 재판정(돌연변이 검증 포함)
- [ ] `api-ventago/src/app/watch/watch-pairing.spec.ts` — W98-02 코드 발급·claim·poll·만료·rate-limit
- [ ] `tienda-admin-app/test/features/relojes/` 디렉터리 신규 — W98-03
- [ ] `wear-admin-app/app/src/test/` 디렉터리 신규(Gradle 유닛 테스트 설정 포함) — W98-04
- [ ] Wave 0 에서 `sqlite`/jest 설정 추가는 불필요(기존 jest 설정 재사용) — 단 Wear 모듈은 Gradle 프로젝트
      자체가 없으므로 "테스트 프레임워크 설치"가 아니라 **Gradle 모듈 생성**이 Wave 0 선행 작업

## Security Domain

> `security_enforcement` 설정 미확인(.planning/config.json 직접 열람 안 함) — 부재 시 활성으로 간주.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | yes | 워치 토큰 = sha256 해시 저장(원문 미보관), `timingSafeEqual` 비교(admin-device-token.service.ts 패턴) |
| V3 Session Management | yes | 90일 sliding + 30일 유휴 만료 + 즉시 회수(revoked_at) |
| V4 Access Control | yes | 매 요청 역할 재판정(store-필터 공유 유틸) + 단일 엔드포인트 스코프(WatchTokenGuard 를 다른 컨트롤러가 import 하지 않음을 테스트로 고정) |
| V5 Input Validation | yes | DTO(class-validator, 기존 `LoggingValidationPipe` 전역 파이프 재사용) — `userCode`/`deviceCode` 형식 검증 |
| V6 Cryptography | yes | `crypto.randomBytes(32)`(Node 내장) — 자체 PRNG 구현 금지. Wear 쪽 토큰 저장은 Android Keystore(하드웨어 백킹 가능 시) |

### Known Threat Patterns for 이 스택

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| `userCode` 브루트포스(8자리, 5분 만료) | Spoofing | SENSITIVE_THROTTLE 류 IP+코드 rate-limit, 코드 공간이 작으면(영숫자 8자) 짧은 TTL 이 핵심 방어 — 5분 만료 유지 필수 |
| `deviceCode` 추측으로 다른 워치의 토큰 탈취 | Spoofing/Info Disclosure | 32바이트 random, 사람이 안 보는 값이라 노출면이 폴링 엔드포인트 자체뿐 — 브루트포스엔 길이로 방어 |
| 워치 토큰을 URL 쿼리로 전달 | Info Disclosure(로그 유출) | 반드시 헤더(`x-watch-token`)로만 — CONTEXT.md D-06 에 이미 명시, memory capability-in-url-is-a-log-leak 와 일치 |
| 테넌트 컨텍스트 미확정 상태로 모델 쿼리 | Elevation of Privilege(교차 매장) | Pitfall 1 참조 — raw SQL + storeId 파라미터 이중 방어 |
| 역할 회수 후에도 토큰이 살아있는 창(갱신까지의 지연) | Elevation of Privilege | "매 요청 재판정"이 캐시(30초 TTL)보다 먼저 평가되는지 순서 확인 — 캐시 키에 역할을 안 태우므로 캐시는 데이터만 캐싱, 인가는 매 요청 가드에서 수행(캐시 우회 경로 없음) |

## Sources

### Primary (HIGH confidence — 코드베이스 실측)
- `api-ventago/src/app/auth/admin-device-token.service.ts`, `admin-device-token.model.ts`, `auth.controller.ts` — 장기 토큰 발급/회전/회수 패턴
- `api-ventago/src/app/auth/guards/jwt-global.guard.ts` — 전역 가드·TenantContext 확정 방식
- `api-ventago/src/app/cashRegister/cashRegister.service.ts:1569-1700`(`getTesoreriaOverview`), `:61-87`(timezone 헬퍼)
- `api-ventago/src/app/sales/sale-status.constants.ts` — `saleBranchSql`/`signedTxSql`/`EXCLUDE_DEUDA_PAGO_SQL`/`ACCOUNTING_SALE_STATUSES`
- `api-ventago/src/common/tenant/tenant-context.ts`, `branch-scope.util.ts`
- `api-ventago/src/common/cache/memory-cache.service.ts`, `cache-key.ts`
- `api-ventago/migrations/2026-08-06-admin-device-tokens.sql` — 신규 테이블 마이그레이션 템플릿
- `tienda-admin-app/android/app/build.gradle.kts`(debug 서명 실측), `lib/shared/app_shell.dart`, `lib/features/caja/caja_repository.dart`, `lib/core/network/dio_client.dart`
- 로컬 환경 실측: `sdkmanager --list_installed`/`--list`(Android SDK, Wear 시스템 이미지 목록), `java -version`(JDK 부재, Android Studio JBR 경로)
- `~/.claude/.../memory/*.md` — route-guard-undoes-global-guard-user, public-routes-disable-tenant-guard, agent-role-is-allowlist-only, user-roles-need-store-filter, caja-balance-formula-duplicated-9-places(CLAUDE.md), capability-in-url-is-a-log-leak, dead-end-cta-is-worse-than-none, jest-maxworkers-1-required, github-actions-not-running-billing

### Secondary (MEDIUM confidence — 공식 문서, WebFetch/WebSearch로 교차)
- [Package and distribute Wear OS apps](https://developer.android.com/training/wearables/packaging) — 패키지명 동일 요구, Multi-APK
- [Standalone versus non-standalone Wear OS apps](https://developer.android.com/training/wearables/apps/standalone-apps) — 매니페스트 메타데이터
- [Wear OS app quality](https://developer.android.com/docs/quality-guidelines/wear-app-quality) — WO-G7(서명 키), WO-P1(targetSdk 34), 64-bit 요구(2026-09-15)
- [Wear Compose releases](https://developer.android.com/jetpack/androidx/releases/wear-compose) — 1.7.0 (2026-09-23)
- [Wear ProtoLayout releases](https://developer.android.com/jetpack/androidx/releases/wear-protolayout) — 1.4.2 (2026-07-29)
- [Wear Tiles releases](https://developer.android.com/jetpack/androidx/releases/wear-tiles) — 1.6.2 (2026-07-29)
- [ComplicationDataSourceService reference](https://developer.android.com/reference/kotlin/androidx/wear/watchface/complications/datasource/ComplicationDataSourceService) — UPDATE_PERIOD_SECONDS 최소 5분
- [Show periodic updates in tiles](https://developer.android.com/training/wearables/tiles/update) — freshness interval 스로틀 특성
- [EncryptedSharedPreferences reference](https://developer.android.com/reference/androidx/security/crypto/EncryptedSharedPreferences) — 폐기 확인
- [RFC 8628: OAuth 2.0 Device Authorization Grant](https://www.rfc-editor.org/info/rfc8628/) / [oauth.net 요약](https://oauth.net/2/grant-types/device-code/)
- Play Console 404 확인(`play.google.com/store/apps/details?id=com.coolsistema.tienda_admin_app`) — 패키지명 미점유 확인

### Tertiary (LOW confidence — WebSearch 요약, 검증 필요)
- Retrofit vs Ktor 2026 비교 글(droidshubham.medium.com 등) — 개인 블로그, 방향성만 참고
- Google Play $25 등록비 — 복수 블로그 교차검증했으나 공식 Play Console 과금 페이지 원문은 직접 열람하지 않음
- Wear Tile "15분" 구체 숫자 — 공식 문서에서 정확한 숫자를 못 찾음(Assumption A3)

## Metadata

**Confidence breakdown:**
- Standard stack(API 재사용 부분): HIGH — 전부 코드 실측
- Standard stack(Wear OS 라이브러리 버전): MEDIUM — WebSearch 스냅샷, 설치 시 재확인 필요
- Architecture(인증 가드 설계): HIGH — 기존 패턴 2개(vendor-jwt, admin-device-token) 실측 비교로 도출
- Architecture(Wear OS 쪽): MEDIUM — 공식 문서 기반이나 실기기 미검증
- Pitfalls: HIGH(가드/테넌트 부분), MEDIUM(Tile 갱신 주기, 서명 키 정책 적용 범위)

**Research date:** 2026-10-04
**Valid until:** 30일(API/DB 부분은 안정적) — Wear OS 라이브러리 버전·Play 정책 부분은 **변경 잦음(7-14일 내 재확인 권장)**, 특히 §Open Questions 1(서명 키)은 플래닝 직전 재확인.
