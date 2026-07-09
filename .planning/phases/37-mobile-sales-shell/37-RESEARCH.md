# Phase 37: Mobile Sales Shell — Research

**Researched:** 2026-07-08
**Domain:** Flutter 모바일 앱 (vendedor/revendedor 듀얼 모드) + NestJS `/mobile/*` 백엔드 레이어 — **기존 코드 재사용 중심**
**Confidence:** HIGH (모든 재사용 대상 코드/스키마를 세션 내 직접 grep·read 로 검증)

> 이 문서는 greenfield 설계가 아니라 **"무엇을 재사용하고 무엇만 신규로 만들지"** 의 지도다. 코드는 쓰지 않는다. 각 Wave 별로 planner 가 참조할 정확한 파일 경로·패턴·landmine 을 명시한다.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01 ~ D-15 — 절대 대안 탐색 금지)
- **D-01** 단일 앱, 듀얼 모드. Phase 17 코드를 fork 아닌 monorepo workspace 로 흡수. UI 만 분기, 인프라 100% 공유.
- **D-02** Scope 강제 = 100% 백엔드 책임. `?storeId=/?branchId=` 신뢰 금지. `MobileScopeGuard` 가 JWT/세션 scope 로 강제. vendedor→`user_branches.branch_id IN (?)`, 매핑 0건이면 401 `VENDEDOR_SCOPE_NOT_DEFINED`. revendedor→`reseller_tienda_link.store_id IN (?)`.
- **D-03** `GET /mobile/catalog` 단일 엔드포인트, scope 만 다름. 응답 공통 키 동일.
- **D-04** Pool 보호 3-layer: process-local `MemoryCacheService`(catalog 60s / stock 10s) → Phase 24 MV → 실 DB(확정 순간만). 모바일 +20 connection 이하.
- **D-05** Scope 는 boolean 아닌 **set**(INT[]). `user_branches` 1 row=strict, N row=multi-branch.
- **D-06** `mobile_sessions` 를 데스크탑 `active_sessions` 와 분리. UNIQUE `(user_id, device_fingerprint)`.
- **D-07** vendedor MVP 먼저(Wave 1-4), revendedor 는 Phase 24 Wave 1-2 후 Wave 5.
- **D-08** Plan 37-01 backfill = idempotent 2-row INSERT 만 (대규모 마이그레이션 X).
- **D-09** 베타 매장 = coolsistema (store_id=6), vendedor 2명.
- **D-10** Multi-branch vendedor UI 는 1차 출시 제외. 데이터 모델은 set 유지, UI 는 selector lock.
- **D-11** vendedor 폭증 없음 가정. D-07 우선순위 유지.
- **D-12** ACE Phase 33 신규 8 role 미사용 — Phase 37 범위 외.
- **D-13 ⭐** 모바일 판매 = **확정 Sale 아님 → 보류(suspendido)**. Caja/매상 무영향, stock 만 `type:'suspend'` 임시 예약. `SuspendedSalesService.create` 재사용. 확정은 데스크탑 POS 가 보류 목록에서 복원·결제. vendedor+revendedor 공통.
- **D-14 ⭐** 재고 조회 진입점 차이: vendedor=QR 스캔(자기 매장 **전 지점** 재고 read, SELL scope=자기 1지점 과 구분). revendedor=카탈로그 검색(QR 불필요). **STOCK-READ scope ≠ SELL scope.**
- **D-15 ⭐** 상품 상세/수량 = 웹 `VariantsStockVenta.tsx` 색×사이즈 매트릭스 모바일 이식. 셀당 수량 직접 입력(+/- 스테퍼 금지) + 셀당 지점별 재고. `variantQuantities` 키 = `colorId-sizeId`.

### Claude's Discretion (planning 단계 결정)
- Flutter 프로젝트 디렉토리 구조 (Phase 17 패턴 따름)
- `MobileScopeGuard` 의 Sequelize raw SQL vs scope() 메서드 선택
- `mobile_sessions.last_seen_at` heartbeat 갱신 주기
- FCM 토큰 갱신 정책
- 오프라인 캐시 저장 매체 (Hive vs sqflite) — 단 MVP 는 메모리 캐시만 (SPEC 금지사항)
- 바코드 스캐너 라이브러리 (`mobile_scanner` vs `qr_code_scanner`)
- D-15 모바일 이식 시 색 토큰(Ventago 다크 테마 치환), 가로 스와이프 처리

### Deferred Ideas (OUT OF SCOPE)
- 별도 pgbouncer pool 분리 (100명 초과 시)
- Mercadopago POS QR / AFIP 영수증 모바일 통합
- 오프라인 판매 큐잉
- 마진 시뮬레이터 고급 기능, 매니저 승인 워크플로
- PostHog 모바일 이벤트, App Store/Play Store 정식 배포
</user_constraints>

<phase_requirements>
## Phase Requirements (37-SPEC.md 에서 추출한 MOBILE-* ID)

| ID | 설명 | Research Support (재사용/신규) |
|----|------|------------------------------|
| MOBILE-A-01 | `mobile_sessions` 테이블 신규 (PG10/PG15 호환) | **신규**. `active_sessions` 스키마를 템플릿으로. `active_sessions` 확인됨(아래 스키마 표). `mobile_sessions` 未존재 확인. |
| MOBILE-A-02 | `user_branches` backfill (idempotent 2-row INSERT) | **거의 완료**. SPEC 본문에 SQL 완성. `user_branches` 스키마·`mobile_terminal_id` 컬럼 이미 존재. |
| MOBILE-A-03 | JWT payload 확장 (scopeMode/scopeBranchIds/scopeStoreIds/mobileSessionToken) | **신규+주의**. 현 payload = name/lastName/email/status/trialEndsAt/roles/storeId. ⚠️ `JwtStrategy.validate()` 는 payload 를 버리고 DB `Users` 만 반환 → scope claim 은 guard 가 mobile_sessions 조회로 얻어야 함(아래 landmine). |
| MOBILE-A-04 | `POST /mobile/auth/login` (bcrypt + scope 결정 + session UPSERT) | **부분 재사용**. `auth.service.signIn` bcrypt/status 검증 로직 참조. `SessionService` 는 데스크탑 전용 → 모바일용 별도. |
| MOBILE-A-05 | `MobileScopeGuard` (scope 주입 + param 충돌 403) | **재사용 청사진 = `BranchScopeGuard`**(확인됨). set 기반으로 확장. |
| MOBILE-A-06 | `GET /mobile/me` | **신규**. `auth.service` /me 구성 참조. |
| MOBILE-B-01 | `GET /mobile/catalog` 단일 엔드포인트 | **신규**. `products.service` SELECT 패턴 + `ProductBranch` stock 집계. |
| MOBILE-B-02 | catalog `MemoryCacheService` 60s | **재사용**. `MemoryCacheService.get/set(key,val,ttlMs)` 확인됨. |
| MOBILE-B-03 | `GET /mobile/stock/:productId` (vendedor=매장 전 지점, TTL 10s) | **신규**. 응답 shape 은 `VariantsStockVenta` 의 `stockByVariant[].stockByBranch` 와 정렬 필요(아래). |
| MOBILE-B-04 | `POST /mobile/sales` → **보류 생성** | **재사용 = `SuspendedSalesService.create(dto, userId)`**(확인됨). sales-create 금지. |
| MOBILE-B-05 | 재고는 차감 아닌 예약(`type:'suspend'`) | **재사용 = `recordReservationMoves`**(suspended-sales.service.ts:59, 확인됨). 신규 트랜잭션 금지. |
| MOBILE-C-01 | `mobile-sales-app/` 초기화 (Phase 17 복제) | **재사용 = `talleres-vendor-app/`**(구조 확인됨) + 신규 스캐너 dep. |
| MOBILE-C-02 | Riverpod `scopeProvider` | **패턴 재사용 = `auth_provider.dart`**(AsyncNotifier + secure storage). |
| MOBILE-C-03 | 로그인 화면 (email+password) | **부분 재사용**. ⚠️ Phase 17 은 phone+PIN → 재작성 필요(아래). |
| MOBILE-C-04 | 홈 (vendedor=QR 버튼 전면 / revendedor=검색) | **신규 UI**. `store_tab_bar` 멀티매장 패턴 재사용(revendedor). |
| MOBILE-C-05 | 재고/카탈로그 진입 분기 (scan-to-detail vs search-to-list) | **신규 UI** (D-14). |
| MOBILE-C-06 | 카트 → **"보류 전송"** (결제수단 UI 없음) | **신규 UI** (D-13). |
| MOBILE-C-07 | 세션 만료 처리 (`MOBILE_SESSION_EXPIRED` 401) | **부분 재사용**. dio interceptor(아래) — ⚠️ 현재 401 redirect 미구현. |
| MOBILE-C-08 | 상품 상세 = 변형 재고 매트릭스 (D-15) | **이식 = `VariantsStockVenta.tsx`**(378줄, 데이터 모델 확인됨). |
| MOBILE-D-01/02/03 | Pool 측정 + UAT U1-U6 + Pool 변동 검증 | **신규 검증 작업**. `pg_stat_activity` + database.module.ts 80% 경고. |
</phase_requirements>

---

## Summary

Phase 37 은 **거의 모든 building block 이 이미 코드베이스에 존재**하는, 통합·조립형 phase 다. 진짜 신규는 세 가지뿐이다: (1) `mobile_sessions` 테이블·`MobileScopeGuard`·`/mobile/auth/login` 백엔드 레이어, (2) `/mobile/catalog`·`/mobile/stock`·`/mobile/sales` 컨트롤러(내부 로직은 기존 서비스 위임), (3) `mobile-sales-app/` Flutter 앱(Phase 17 인프라 복제 + 신규 화면).

**가장 중요한 발견 3가지:**
1. **판매 = 보류(D-13) 재사용 대상이 완벽히 준비됨.** `SuspendedSalesService.create(dto, userId)` 가 이미 `variantQuantities`(`colorId-sizeId` 키)를 파싱해 `Stocks type:'suspend'` 로 예약하고 `Sale` 을 만들지 않는다. `POST /mobile/sales` 는 이 서비스를 그대로 호출하면 된다. DTO(`CreateSuspendedSaleDto`)도 `variantQuantities` 를 이미 받는다 — Flutter 매트릭스 출력 포맷과 1:1.
2. **Wave 1 의 절반이 이미 merge 됨.** `user_branches.mobile_terminal_id` 컬럼(스키마 확인), `mobile.access` 권한 function seed(`functions-seed-admin.ts`), 3개 migration 파일(`phase37-*.sql`)이 존재. Wave 1 잔여 = `mobile_sessions` 테이블 + guard + login 엔드포인트뿐. backfill SQL 도 이미 작성됨.
3. **Phase 17 "100% 재사용" 은 과장 — 3개 항목은 신규/재작성.** (a) **FCM 없음**: `talleres-vendor-app` pubspec/lib 에 firebase/fcm 依존 0건, 알림은 폴링(`/vendor-portal/notifications`). CONTEXT/SPEC 의 "FCM 재사용" 은 오류 — FCM 은 greenfield. (b) **인증 방식 다름**: Phase 17=phone+PIN(`/vendor-portal/auth/login`), Phase 37=email+password → `auth_repository`·`auth_dto` 재작성. (c) **401 redirect 미구현**: dio interceptor 의 `onError` 는 그냥 pass-through → MOBILE-C-07 을 위해 신규 구현 필요.

**Primary recommendation:** Wave 1 은 "신규 `mobile_sessions` + `MobileScopeGuard`(BranchScopeGuard 복제·set 확장) + `MobileAuthService`(signIn 로직 복제, SessionService 는 복제 안 함)" 로 좁게 잡는다. Flutter 는 `talleres-vendor-app` 을 `mobile-sales-app` 으로 복제하되, 인증·FCM·스캐너는 신규로 명시한다. 판매 경로는 `SuspendedSalesService` 위임 — 절대 `sales-create.service` 를 부르지 않는다.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 로그인/scope 결정 | API (`MobileAuthService`) | DB (`mobile_sessions`, `user_branches`) | scope 는 절대 클라이언트 위임 금지(D-02). 토큰이 아닌 DB(mobile_sessions.scope_*)가 authoritative. |
| scope 강제 | API (`MobileScopeGuard`) | — | 모든 `/mobile/*` 통과. `BranchScopeGuard` 패턴. |
| 카탈로그/재고 read | API + process cache | DB (`ProductBranch`/`Stocks`) | Pool 보호(D-04). 1차 방어선 = `MemoryCacheService`(Node 프로세스 메모리). |
| 판매(=보류) 생성 | API (`SuspendedSalesService`) | DB (`suspended_sales`+`Stocks type:'suspend'`) | Caja 무영향(D-13). 재고 예약만. |
| 확정·Caja 반영 | **데스크탑 POS** (범위 외) | — | 모바일은 절대 Caja 를 건드리지 않음. `nueva-venta` 보류 복원 흐름이 소비. |
| QR 딥링크 발행 | 데스크탑 print (Phase 38, 존재) | print-agent | 모바일은 **소비자**만. `buildQrPayload` 확인됨. |
| 재고 매트릭스 렌더 | Flutter (client) | API `/mobile/stock` | UI 상태(입력 수량)는 client, 재고 수치는 API. |
| 세션 만료 감지 | Flutter dio interceptor | API 401 | `MOBILE_SESSION_EXPIRED` 401 → clear+redirect. |

---

## Existing Code Reuse Map (핵심 산출물 — Wave 별)

### Wave 1 — Backend Auth & Scope

| 필요 | 재사용/신규 | 정확한 경로 + 패턴 |
|------|------------|-------------------|
| `mobile_sessions` 테이블 | **신규** | 템플릿 = `active_sessions`(스키마 아래). SPEC L286 DDL 초안 있음. `id UUID` 는 **app-level `randomUUID()`**(pgcrypto 의존 회피 — 운영 PG10 확인 필요). |
| `MobileSession` 모델 | **신규** | `active-session.model.ts` 패턴 복제. `underscored:true` 전역 → 컬럼 snake_case 자동. |
| `user_branches` backfill | **완료됨(SQL 존재)** | SPEC L320 + `migrations/phase37-*.sql`. 검증쿼리 기대값=2. |
| scope guard | **재사용 = `permissions/guards/branch-scope.guard.ts`** | vendedor 로직(`UserBranch.findOne where userId+branchId+validUntil`)이 그대로 청사진. set 확장: `branch_id IN (scopeBranchIds)`. `PRIVILEGED_ROLES` bypass 패턴도 참고. |
| login 로직 | **부분 재사용** | `auth.service.ts:289` payload 구성 + bcrypt/status 검증. ⚠️ `SessionService.createSession`(데스크탑, active_sessions destroy 로직)은 **복제 안 함** — 모바일 세션 정책이 다름(동시 접속 허용). |
| JWT payload 확장 | **신규+landmine** | 아래 "Common Pitfalls #1". |
| mobile.access 게이트 | **완료됨** | `functions-seed-admin.ts:45` + `phase37-mobile-access-function.sql` + `phase37-beta-mobile-access-data.sql`(coolsistema vendedor action='read'). Wave 1 로그인이 이 키를 체크. |

### Wave 2 — Backend Catalog/Stock/Sales

| 필요 | 재사용/신규 | 정확한 경로 + 패턴 |
|------|------------|-------------------|
| 카탈로그 SELECT | **패턴 재사용** | `products/products.service.ts`. ⚠️ 운영 로그상 products 쿼리 615ms slow → **반드시 `MemoryCacheService` 경유**(D-04). |
| 캐시 | **재사용** | `common/cache/memory-cache.service.ts` — `get<T>(key)`/`set(key,val,ttlMs)`/`delByPrefix(prefix)`. `MemoryCacheModule` 를 `MobileModule` imports 에 추가. |
| 재고 집계 | **재사용** | `ProductBranch`(table `ProductBranch`, PascalCase quoted) + `Stocks`(table `stocks`: `stock`,`product_branch_id`,`type`). 현 재고 = 해당 product_branch 의 stocks 합계(type 무관). |
| **판매(보류) 생성** | **재사용 = `SuspendedSalesService.create(dto,userId)`** | `suspended-sales/suspended-sales.service.ts`. `MobileModule` 이 `SuspendedSalesModule` import 하거나 서비스 주입. |
| 재고 예약 | **재사용 = `recordReservationMoves`** | 동 파일 L59. `variantQuantities` 순회 → `resolveVariantId(parentId,colorId,sizeId)` → `Stocks.create({type:'suspend', stock:-qty})`. |
| DTO | **재사용 = `CreateSuspendedSaleDto`** | `dto/create-suspended-sale.dto.ts`. `variantQuantities?: Record<string,number>` 이미 존재. ⚠️ `branchId` 를 **반드시 명시 전달**(coolsistema=2지점이라 미전달 시 `resolveBranchId`→null→예약 미기록, service.ts:68). |

### Wave 3 — Flutter Shell

| 필요 | 재사용/신규 | 정확한 경로 + 패턴 |
|------|------------|-------------------|
| 프로젝트 골격 | **복제 = `talleres-vendor-app/`** | pubspec: riverpod 3.3.1 / hooks_riverpod 3.3.1 / dio 5.9.2 / flutter_secure_storage 10.0.0 / go_router 17.2.0 / intl 0.20.2. SDK ^3.11.0. |
| Dio 클라이언트 | **재사용 = `core/network/dio_client.dart`** | JWT 자동 주입 인터셉터. ⚠️ 토큰 키 `vendor_token` → `mobile_token` 로. ⚠️ **`onError` 401 redirect 신규 구현**(현재 pass-through). |
| Secure storage | **재사용 = `core/storage/secure_storage.dart`** | read/write/delete/deleteAll. SharedPreferences 금지(SPEC). |
| api_config | **재사용 = `core/config/api_config.dart`** | `--dart-define=BASE_URL`, 기본 `http://localhost:5002/api`. 운영 `https://newapi.coolsistema.com/api`. |
| 인증 provider | **패턴 재사용 = `features/auth/providers/auth_provider.dart`** | `AsyncNotifier<AuthState?>` + build() 시 토큰 복구 + getMe. |
| 인증 repository/dto | **재작성** | phone+PIN → email+password. `/vendor-portal/auth/login` → `/mobile/auth/login`. |
| go_router | **재사용 = `router/app_router.dart`** | authState 기반 redirect. scope 별 route tree 추가. |
| 멀티매장 탭 | **재사용 = `shared/widgets/store_tab_bar.dart`** | stores.length>1 시 노출 — revendedor 매장 selector 로 직행. |
| FCM | **신규(greenfield)** | ⚠️ Phase 17 에 없음. firebase_messaging 의존·플랫폼 설정 신규. 또는 MVP 에서 deferred 검토(planner 결정). |
| 세션 만료 UI | **신규** | 401 `MOBILE_SESSION_EXPIRED` → deleteAll + `/login` + 토스트. |
| 테마 | **신규** | ⚠️ Phase 17=MUI blue `#1976D2`(Ventago 금지색). `Skill("sketch-findings-ace-online")` 다크 네이비+골드로 치환. |

### Wave 4 — Flutter Vendedor (MVP 1차 출시)

| 필요 | 재사용/신규 | 정확한 경로 + 패턴 |
|------|------------|-------------------|
| 홈(QR 버튼 전면) | **신규 UI** (D-14) | branch lock + 매출 요약 + QR 스캐너 1차 액션. |
| QR 스캐너 | **신규 dep** | `mobile_scanner`(권장, 유지보수 활발) vs `qr_code_scanner`(deprecated 경향). 딥링크 `/m/stock?s={storeId}&p={parentProductId}` 파싱 → `GET /mobile/stock/:p`. |
| 상품 상세 매트릭스 | **이식 = `VariantsStockVenta.tsx`** | 아래 "Code Examples" 에 데이터 모델 상세. |
| 카트→보류 전송 | **신규 UI** (D-13) | 결제수단/금전함 UI 없음. |
| QR 딥링크 소비 | **재사용(발행측 존재)** | `print/print.service.ts:140 buildQrPayload` → `${PUBLIC_WEB_URL}/m/stock?s=&p=`. 모바일은 파싱만. |

### Wave 5 — Flutter Revendedor (Phase 24 Wave 1-2 게이트)

| 필요 | 상태 | 비고 |
|------|------|------|
| `reseller.catalog_unified` MV | **미존재** | db-schema 에 없음. Phase 24 Wave 1-2 완료가 하드 전제(D-07). |
| `reseller_tienda_link` | **미존재** | 동일. |
| 기존 `revendedor` 모듈 | **존재하나 별개** | `api-ventago/src/app/revendedor/`(table `revendedores`) — 구 reseller 개념. Phase 24 MV 와 혼동 금지. Wave 5 planning 시 Phase 24 산출물 재확인 필수. |

---

## Standard Stack

### Flutter (mobile-sales-app) — `talleres-vendor-app/pubspec.yaml` 검증
| 패키지 | 버전 | 목적 | Why |
|--------|------|------|-----|
| flutter_riverpod / hooks_riverpod | ^3.3.1 | 상태관리 | Phase 17 검증됨 |
| dio | ^5.9.2 | HTTP + 인터셉터 | JWT 자동주입 |
| flutter_secure_storage | ^10.0.0 | 토큰 저장 | SharedPreferences 금지 |
| go_router | ^17.2.0 | 라우팅 | authState redirect |
| intl | ^0.20.2 | 통화/날짜 포맷 | — |
| **mobile_scanner** | (신규, 최신 확인 필요) | QR 스캔 (D-14) | vendedor 전용 |
| **firebase_messaging** | (신규, MVP deferred 검토) | FCM | ⚠️ Phase 17 미존재 |

### Backend (재사용, 신규 의존 0)
NestJS 11 + Sequelize(`underscored:true`) + PG10(운영)/PG18(로컬). 신규 npm 패키지 불필요 — `randomUUID`(node crypto), bcrypt(기존), class-validator(기존) 모두 존재.

**버전 검증(Flutter 신규 의존):** planner/execute 시 `flutter pub add mobile_scanner` 로 최신 확인. mobile_scanner 는 2024년 이후 활발 유지보수 [ASSUMED — pub.dev 미조회]. `qr_code_scanner` 는 유지보수 정체 경향 [ASSUMED].

### Alternatives Considered
| 대신 | 대안 | Tradeoff |
|------|------|----------|
| mobile_scanner | qr_code_scanner | 후자는 최신 Flutter/AGP 호환 이슈 가능 → mobile_scanner 권장 |
| 메모리 캐시(MVP) | Hive/sqflite 오프라인 | SPEC 가 MVP 오프라인 금지 → 메모리+lastFetch 만 |

---

## Architecture Patterns

### System Data Flow

```
[Flutter mobile-sales-app]
  로그인(email+pass, deviceFingerprint)
        │  POST /mobile/auth/login
        ▼
[MobileAuthService]  bcrypt+status 검증(=signIn 로직)
        │  scope 결정: vendedor→user_branches.branch_id[]  / revendedor→reseller_tienda_link.store_id[]
        │  scope 없음 → 401 VENDEDOR_SCOPE_NOT_DEFINED
        ▼
[mobile_sessions UPSERT]  (user_id,device_fingerprint) UNIQUE
        │  active_session_token(UUID) 발급 + scope_branch_ids/scope_store_ids 캐시
        ▼
  accessToken(JWT) + mobileSessionToken 반환
        │
  이후 모든 요청: Authorization: Bearer + (mobileSessionToken 헤더/claim)
        ▼
[AuthGuard(JWT)] → [MobileScopeGuard]
        │  mobileSessionToken 으로 mobile_sessions 조회(=authoritative scope)
        │  last_seen_at 갱신(heartbeat)
        │  query ?branchId/?storeId 가 scope 밖 → 403 SCOPE_VIOLATION
        │  req.scope = {mode, branchIds[], storeIds[]} 주입
        ▼
┌───────────────┬──────────────────┬──────────────────────────┐
│ GET /catalog  │ GET /stock/:p     │ POST /sales              │
│ MemoryCache   │ MemoryCache       │ (캐시 없음)               │
│ 60s → DB      │ 10s → ProductBranch│ SuspendedSalesService    │
│ scope 필터    │ 매장 전지점 분해   │ .create(dto,userId)      │
│               │ (D-14)            │ → Stocks type:'suspend'  │
│               │                   │   -qty 예약 (Caja 무영향) │
└───────────────┴──────────────────┴──────────────────────────┘
        │                                    │
        │                          [보류 목록] suspended_sales
        │                                    ▼
        │                    데스크탑 POS nueva-venta "복원·확정"
        │                    → 여기서만 Sale 생성 + Caja 반영 (범위 외)
        ▼
[QR 스캔 경로(vendedor)] print.service.buildQrPayload 가 발행한
  /m/stock?s=&p= 딥링크 → GET /mobile/stock/:p → 매트릭스 상세
```

### Pattern 1: Scope-from-DB, not-from-JWT (핵심)
**What:** scope 는 JWT claim 이 아니라 `mobile_sessions` row 에서 읽는다.
**When:** `MobileScopeGuard` 매 요청.
**Why:** `JwtStrategy.validate()` 가 payload 를 버리고 DB Users 만 반환하므로(확인됨), JWT claim 에 scope 를 넣어도 `req.user` 로 전달 안 됨. 또한 DB 기반이면 권한 변경 즉시 반영·무효화 가능. SPEC MOBILE-A-05 가 이미 이 방식.

### Pattern 2: 서비스 위임 (thin controller)
`MobileSalesService` 는 자체 로직 최소 — `SuspendedSalesService.create` 위임. `MobileCatalogService` 는 캐시 래핑 + 기존 products 조회 위임. 신규 SERIALIZABLE 트랜잭션 금지.

### Anti-Patterns to Avoid
- **`sales-create.service` 호출**: D-13 위반. 모바일은 확정 Sale 을 만들지 않는다.
- **`SessionService.createSession` 재사용**: 데스크탑 active_sessions 를 destroy → 데스크탑 세션 죽음. D-06 위반.
- **query param 신뢰**: `req.query.branchId` 로 직접 필터 → IDOR. 반드시 scope 교차검증.
- **branchId 미전달 보류 생성**: coolsistema 2지점 → `resolveBranchId` null → 재고 예약 누락(조용한 실패).
- **MUI blue `#1976D2` 그대로 이식**: Ventago 금지색.

---

## Don't Hand-Roll

| 문제 | 직접 만들지 말 것 | 대신 사용 | Why |
|------|-------------------|-----------|-----|
| 보류 판매 + 재고 예약 | 신규 보류 로직/Stocks 이동 | `SuspendedSalesService.create` + `recordReservationMoves` | variant 파싱·hold/release·branch 해결이 이미 완성·운영 중 |
| variant 수량 파싱 | `colorId-sizeId` 파서 | 기존 `key.split('-')` + `resolveVariantId` | 웹/DTO/service 3곳이 이미 동일 포맷 |
| branch scope 검증 | 신규 IDOR 가드 | `BranchScopeGuard` 로직 복제 | user_branches + validUntil + privileged bypass 검증됨 |
| 프로세스 캐시 | Map+TTL 직접 | `MemoryCacheService` | cleanup·delByPrefix 존재 |
| JWT 자동주입/저장 | 신규 인터셉터 | `dio_client.dart` + `secure_storage.dart` | 검증됨 (401 redirect 만 추가) |
| QR 딥링크 포맷 | 신규 URL 스킴 | `buildQrPayload` 의 `/m/stock?s=&p=` | 발행측(Phase 38) 이미 이 포맷 |
| 세션 UUID | 커스텀 토큰 | node `randomUUID()` | session.service 전반이 이미 사용 |

**Key insight:** 이 phase 의 위험은 "새로 만드는 것"이 아니라 "이미 있는 것을 못 찾고 재발명하는 것"이다. 특히 보류/재고예약/variant파싱은 3중으로 이미 정합되어 있어 재발명 시 포맷 불일치로 조용히 깨진다.

---

## Runtime State Inventory

> Phase 37 은 신규 기능이지만 foundation slice 가 이미 부분 merge 되어 있어 "무엇이 이미 적용됐고 무엇이 남았나"의 상태 점검이 중요하다.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data (DB 스키마) | `user_branches.mobile_terminal_id` 컬럼 **이미 존재**(운영/로컬 스키마 확인). `mobile_sessions` **미존재**. | mobile_terminal_id: 코드만 사용. mobile_sessions: 신규 마이그레이션(Wave 1). |
| Live service config | `mobile.access` function seed 코드 존재(`functions-seed-admin.ts`). migration `phase37-mobile-access-function.sql`·`phase37-beta-mobile-access-data.sql` **작성됨, 운영 미적용**(Phase 35/36 게이트). | 운영 적용은 Phase 35/36 잠금 해제 후 순서대로(migration 헤더 명시). |
| OS-registered state | 없음 — 모바일 앱은 sideload .apk/.ipa, OS 등록 상태 없음. | None. |
| Secrets/env vars | `JWT_SECRET_KEY`(기존, 공용). `PUBLIC_WEB_URL`(QR 딥링크 base, 기존). 신규 secret 없음. | None — 기존 재사용. FCM 도입 시 firebase 설정 파일 신규(google-services.json 등). |
| Build artifacts | `talleres-vendor-app` 복제 시 Android/iOS 네이티브 폴더·bundle id 신규 필요. | `mobile-sales-app` 초기화 시 applicationId/bundleId 신규 지정. |

**foundation slice 상태 요약:** MOBILE-A-02(backfill SQL)·mobile_terminal_id·mobile.access 는 **이미 준비/부분적용**. Wave 1 실질 잔여 = `mobile_sessions` + `MobileScopeGuard` + `MobileAuthService`/`MobileAuthController` + `MobileModule` + Jest. (memory: "Phase 37 foundation slice main 병합/unpushed, Phase 35/36 게이트로 운영 보류".)

---

## Common Pitfalls

### Pitfall 1: JWT scope claim 이 guard 에 전달 안 됨 ⭐
**무엇이 잘못되나:** payload 에 scopeBranchIds 를 넣어도 `req.user` 에 없음.
**근본원인:** `JwtStrategy.validate(data)` 는 `data`(payload)를 버리고 `usersService.findOneByEmail` 로 DB `Users` 만 반환(jwt.strategy.ts:22-31 확인).
**회피:** `MobileScopeGuard` 가 `mobileSessionToken`(헤더 또는 별도 decode)으로 `mobile_sessions` 를 조회해 scope 를 얻는다(SPEC MOBILE-A-05 방식 = 정답). 공용 `JwtStrategy` 를 수정하면 데스크탑 회귀 → 절대 금지.
**조기 경고:** guard 에서 `req.user.scopeBranchIds` 가 undefined.

### Pitfall 2: 데스크탑 세션 죽임 (active_sessions 공유)
**무엇이:** 모바일 로그인 시 데스크탑 POS 세션 401.
**근본원인:** `SessionService.createSession` 이 `activeSessionModel.destroy({userId, fingerprint≠})`. 모바일이 이걸 부르면 데스크탑 세션 제거.
**회피:** 모바일은 `mobile_sessions` 전용 경로. SessionService 미사용(D-06).
**경고:** UAT U3(동시 접속) 실패.

### Pitfall 3: coolsistema 2지점 → 보류 재고 예약 조용히 누락
**무엇이:** 보류는 생성되나 stock hold 안 됨.
**근본원인:** `resolveBranchId(dtoBranchId, storeId)` 가 dtoBranchId 없고 매장 지점이 1개 아니면 **null 반환** → `recordReservationMoves` 가 `branchId null` 이면 warning 후 skip(service.ts:68).
**회피:** `POST /mobile/sales` 는 scope 의 branchId 를 **항상 명시 전달**. vendedor 는 자기 SELL branch(단일).
**경고:** 로그 `[SuspendedSales] branchId 미해결`.

### Pitfall 4: catalog/stock 캐시 우회로 slow query 폭증
**무엇이:** 100명 접속이 615ms products 쿼리를 직격 → pool 고갈.
**근본원인:** 캐시 안 거치는 직접 SELECT.
**회피:** 모든 `/mobile/catalog`·`/mobile/stock` 가 `MemoryCacheService` 경유(D-04). key 접두사 `mobile:catalog:`/`mobile:stock:`.
**경고:** database.module.ts pool using% 80% 경고.

### Pitfall 5: STOCK-READ scope 를 SELL scope 로 좁힘 (D-14 위반)
**무엇이:** vendedor 가 QR 스캔해도 타 지점 재고 안 보임.
**근본원인:** `/mobile/stock` 에 SELL scope(자기 1지점)만 적용.
**회피:** `/mobile/stock` = 매장 전 지점 read(STOCK-READ), `/mobile/sales` = 자기 1지점(SELL). 두 scope 분리 강제.

### Pitfall 6: FCM 을 "재사용"으로 계획 (실제 미존재)
**무엇이:** Wave 3 에서 존재하지 않는 Phase 17 FCM 코드를 찾다 blocked.
**근본원인:** CONTEXT/SPEC 가 "FCM 재사용" 명시하나 `talleres-vendor-app` 에 firebase 의존 0.
**회피:** FCM 은 greenfield 로 계획하거나 MVP deferred. planner 가 사용자 확인.

---

## Code Examples (재사용 대상 데이터 모델 — 코드 아님, 계약 정렬용)

### VariantsStockVenta 데이터 모델 (D-15 이식 계약)
```
// Source: ventago-app/.../VariantsStockVenta.tsx (검증됨)
stockByVariant: Array<{
  color: { id, name },
  size:  { id, name },
  stock: number,                       // 현 지점 재고 (굵은 숫자)
  stockByBranch: Record<branchId, number>  // 지점별 분포 "H:20 A:0 D:50"
}>
quantities: Record<`${colorId}-${sizeId}`, number>   // 입력값
// → variantQuantities 로 카트/보류 적재 (키 포맷 동일)
// 색상 코드: 0=grey / 양수=green / 무재고 입력=orange(→gold) / 초과=red
```
**함의:** `GET /mobile/stock/:productId` 응답이 반드시 `stockByVariant[].stockByBranch`(branchId→qty map)를 포함해야 Flutter 매트릭스가 셀당 지점 분포를 렌더 가능. vendedor 는 매장 전 지점 map, revendedor 는 store 별 map.

### SuspendedSale DTO (D-13 계약)
```
// Source: create-suspended-sale.dto.ts (검증됨)
CreateSuspendedSaleDto {
  storeId(필수), branchId?(모바일은 필수 전달 권장),
  clientId?, sellerId?, provinceId?,
  subtotal, totalAmount, discount?, discountAmount?, transport?, notes?, numPedido?,
  items: [{ productId, quantity, price, customName?,
            variantQuantities?: Record<`colorId-sizeId`, qty> }]
  discounts?, recharges?
}
// SuspendedSalesService.create(dto, userId) → Sale 미생성, Stocks type:'suspend' -qty
```

### mobile_sessions 스키마 참조 (신규 — active_sessions 템플릿)
```
// active_sessions (검증됨): id, user_id, session_token, device_fingerprint,
//   public_ip, user_agent, terminal_id, branch_id, store_id, last_activity_at, created/updated
// mobile_sessions (SPEC L286): id UUID(app-level), user_id FK, device_fingerprint,
//   fcm_token?, scope_mode CHECK(vendedor/revendedor), scope_branch_ids INT[], scope_store_ids INT[],
//   active_session_token UUID UNIQUE, last_seen_at, created/updated
//   UNIQUE(user_id, device_fingerprint) + idx(user_id) + idx(active_session_token)
// PG10 주의: gen_random_uuid() = pgcrypto 필요 → app-level randomUUID() 로 회피(확인 필요)
```

---

## State of the Art

| Old | Current | 영향 |
|-----|---------|------|
| 모바일 판매=확정 Sale (원 SPEC 본문) | **보류(suspendido)** (D-13, 2026-06-11) | sales-create 미사용, Caja 무영향 |
| vendedor stock=자기 1지점 | **매장 전 지점 read** (D-14) | STOCK-READ scope 확장 |
| +/- 스테퍼 수량 | **변형 매트릭스 직접 입력** (D-15) | VariantsStockVenta 이식 |
| Phase 17 phone+PIN | email+password | 인증 재작성 |

**Deprecated/주의:**
- `qr_code_scanner`(Flutter) — 유지보수 정체 → `mobile_scanner` 권장 [ASSUMED].
- `revendedor` 모듈(table `revendedores`) — Phase 24 `reseller.catalog_unified` MV 와 별개. Wave 5 시 혼동 금지.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 운영 PG10 에 pgcrypto 미보장 → app-level UUID 필요 | mobile_sessions | 낮음 — app-level randomUUID 가 안전한 기본값. `SELECT * FROM pg_extension WHERE extname='pgcrypto'` 로 확인. |
| A2 | mobile_scanner 가 현재 활발 유지보수, qr_code_scanner 는 정체 | Standard Stack | 중 — 스캐너 선택 변경 가능. execute 시 pub.dev 확인. |
| A3 | Phase 24 `reseller.catalog_unified` MV·`reseller_tienda_link` 미완성(스키마 부재) | Wave 5 | 낮음 — Wave 5 는 이미 게이트됨. Wave 5 planning 시 Phase 24 STATE 재확인. |
| A4 | Phase 17 talleres-vendor-app 에 FCM 부재 = Phase 37 FCM 은 신규 | Wave 3/Summary | 중 — 확인됨(grep 0건). 다만 다른 Flutter 앱(despacho/tienda)에 FCM 있을 수 있음 → 그쪽 재사용 가능성 planner 확인. |
| A5 | `req.user` 는 DB Users(payload 아님) — 데스크탑 회귀 없이 scope claim 전달 불가 | Pitfall 1 | 낮음 — jwt.strategy.ts:22-31 직접 확인. |

---

## Open Questions

1. **FCM 을 MVP 에 포함할지 vs deferred?**
   - 알려진 것: Phase 17 에 FCM 없음. 신규 도입은 firebase 프로젝트·플랫폼 설정 부담.
   - 불명확: 다른 Flutter 앱(despacho-app/tienda-app)에 FCM 인프라가 있는지(재사용 가능성).
   - 권고: Wave 3 planning 전 despacho/tienda pubspec 확인. 없으면 MVP deferred 권고(핵심 판매 흐름과 무관).

2. **Phase 35/36 배포 게이트가 D-13 이후에도 하드 의존인가?**
   - 알려진 것: 모바일이 확정 Sale(activity_type='sale')을 직접 안 만듦(D-13) → 게이트 완화 가능성.
   - 불명확: 데스크탑 확정 단계는 여전히 Phase 35/36 영향권.
   - 권고: CONTEXT D-13 명시대로 **게이트 변경은 사용자 확인 후 별도 결정**. 이 phase 에서 단정 금지.

3. **MobileScopeGuard 가 scope 를 얻는 정확한 메커니즘 (헤더 vs 별도 passport strategy)?**
   - 권고: `x-mobile-session-token` 헤더 → `mobile_sessions` 조회 방식(SessionGuard 의 `x-session-token` 패턴과 대칭). Claude's Discretion.

4. **Flutter 매트릭스가 소비할 색/사이즈 참조 데이터를 `/mobile/stock` 응답에 embed 할지, 별도 엔드포인트로 줄지?**
   - 권고: `stockByVariant` 에 color/size name 을 embed(웹은 SaleProductsContext 에서 별도 로드하나 모바일은 왕복 최소화 + 캐시).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | mobile-sales-app | 확인 필요(execute) | ^3.11 요구 | — |
| PG18 (로컬 dev) | 마이그레이션 dev 검증 | ✓ | 18 (호스트) | — |
| PG10 (운영) | 운영 마이그레이션 | ✓ (SSH) | 10 | pgcrypto 확인 필요 |
| NestJS/Sequelize | 백엔드 | ✓ | 11 | — |
| Jest | 백엔드 테스트 | ✓ | ^29.7 | — |
| firebase CLI/프로젝트 | FCM(선택) | ✗ | — | MVP deferred |
| mobile_scanner | QR(D-14) | ✗(신규) | — | qr_code_scanner |

**Missing, blocking:** 없음(Flutter SDK 는 execute 시 확인).
**Missing, fallback 있음:** FCM(deferred), scanner(대안 존재).

---

## Validation Architecture

> config.json 에 nyquist_validation 키 없음 → enabled 로 취급.

### Test Framework
| Property | Value |
|----------|-------|
| Backend | Jest ^29.7 (`ts-jest`), `npm test` (api-ventago) |
| Backend e2e | `jest --config ./test/jest-e2e.json` |
| Flutter | flutter_test (widget_test.dart 존재), `flutter test` |
| 기존 spec 예시 | `suspended-sales.service.spec.ts`, `permissions.service.spec.ts` 참조 |

### Phase Requirements → Test Map
| Req | Behavior | Type | Command | 파일 |
|-----|----------|------|---------|------|
| MOBILE-A-05 | scope 충돌 403 / 세션만료 401 / 0-branch 401 | unit | `npm test -- mobile-scope.guard.spec` | ❌ Wave 0 |
| MOBILE-A-04 | login scope 결정 | unit | `npm test -- mobile-auth.service.spec` | ❌ Wave 0 |
| MOBILE-B-04 | `SuspendedSalesService.create` 호출·sales-create 미호출 | unit | `npm test -- mobile-sales.service.spec` | ❌ Wave 0 |
| MOBILE-B-02 | 캐시 hit/miss | unit | `npm test -- mobile-catalog.service.spec` | ❌ Wave 0 |
| MOBILE-C-08 | 매트릭스 입력→variantQuantities | widget | `flutter test` | ❌ Wave 0 |
| MOBILE-D-02 | UAT U1-U6 | manual | dev 환경 시나리오 | 수동 |

### Sampling
- Per task: `npm test -- <spec>` (백엔드), `flutter test` (Flutter)
- Per wave: `npm test` 전체 (api-ventago)
- Phase gate: ESLint 0 + Jest green + UAT U1-U6

### Wave 0 Gaps
- [ ] `mobile-scope.guard.spec.ts` — MOBILE-A-05
- [ ] `mobile-auth.service.spec.ts` — MOBILE-A-04
- [ ] `mobile-sales.service.spec.ts` — MOBILE-B-04/05 (sales-create 미호출 assertion)
- [ ] `mobile-catalog.service.spec.ts` — MOBILE-B-02
- [ ] Flutter widget test — 매트릭스 (MOBILE-C-08)

---

## Security Domain

> security_enforcement 키 없음 → enabled.

### Applicable ASVS
| Category | Applies | Control |
|----------|---------|---------|
| V2 Authentication | yes | bcrypt(기존 signIn), JWT_SECRET_KEY. email+password. |
| V3 Session Management | yes | `mobile_sessions` + active_session_token UNIQUE. 만료 시 401. |
| V4 Access Control | **yes(핵심)** | `MobileScopeGuard` — vendedor branch IDOR, revendedor store IDOR 차단(D-02). |
| V5 Input Validation | yes | class-validator DTO(`CreateSuspendedSaleDto`). |
| V6 Cryptography | yes | randomUUID(node crypto), 자체 crypto 금지. flutter_secure_storage. |

### Threat Patterns
| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| `?branchId=` 조작으로 타 지점 stock/판매 | Elevation/Info Disclosure | MobileScopeGuard scope 교차검증 403 SCOPE_VIOLATION |
| 데스크탑 세션 탈취/충돌 | DoS | mobile_sessions 분리(D-06) |
| 세션 토큰 재사용(다기기) | Spoofing | (user_id,fingerprint) UNIQUE + MOBILE_SESSION_EXPIRED |
| SQL injection (scope IN 절) | Tampering | Sequelize 파라미터화, raw string 금지 |
| 토큰 평문 저장 | Info Disclosure | flutter_secure_storage 만(SharedPreferences 금지) |
| PII 노출 (store_clients) | Info Disclosure | Phase 25 store_clients scope 강제(MOBILE-B-04) |

---

## Sources

### Primary (HIGH — 세션 내 직접 read/grep)
- `talleres-vendor-app/` — pubspec + lib 전체 트리, dio_client, secure_storage, auth_provider/repository/dto, main, app_router, store_tab_bar, store_info, notification_repository (FCM 부재 확인)
- `api-ventago/src/app/suspended-sales/` — service.ts(create/recordReservationMoves), dto
- `api-ventago/src/app/session/` — session.service.ts, session.guard.ts, active-session.model
- `api-ventago/src/app/permissions/` — user-branch.model(mobile_terminal_id 확인), branch-scope.guard, branch-scope.decorator
- `api-ventago/src/common/cache/memory-cache.service.ts` + module
- `api-ventago/src/app/auth/` — auth.service.ts(payload L289), jwt.strategy.ts(validate 반환), valid-roles.ts
- `api-ventago/src/app/print/print.service.ts` — buildQrPayload L140-153
- `ventago-app/.../VariantsStockVenta.tsx` — 데이터 모델 전체
- `api-ventago/migrations/phase37-*.sql` (3개) + `functions-seed-admin.ts` (mobile.access)
- `.planning/intel/db-schema-tables.md` — active_sessions, user_branches, stocks
- 37-CONTEXT.md, 37-SPEC.md, ROADMAP.md L822-857

### Secondary (MEDIUM)
- `.claude/.../memory/` MEMORY.md — Phase 37 foundation slice 상태, 환경 사실

### Tertiary (LOW / 미검증 — Assumptions Log 참조)
- pub.dev mobile_scanner/qr_code_scanner 최신 상태 (미조회)
- Phase 24 reseller MV 완성도 (스키마 부재로 미완성 추정)

---

## Metadata

**Confidence breakdown:**
- 재사용 코드 지도: HIGH — 모든 대상 직접 read
- 백엔드 아키텍처(scope/보류/캐시): HIGH — service·guard·DTO 검증
- Flutter 인프라: HIGH — lib 전체 read (FCM 부재 확정)
- 스캐너/FCM 신규 부분: MEDIUM — 외부 의존 미조회
- Wave 5(revendedor): LOW — Phase 24 미완성, 게이트됨

**Research date:** 2026-07-08
**Valid until:** 2026-08-07 (안정 코드베이스, 30일). 단 Phase 24 진행 시 Wave 5 재확인.
