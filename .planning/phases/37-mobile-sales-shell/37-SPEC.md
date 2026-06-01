# SPEC: Phase 37 — Mobile Sales Shell

생성일: 2026-05-31
작성자: gsd workflow (Plan 단계)
선행 자료: [37-CONTEXT.md](./37-CONTEXT.md) (locked decisions D-01..D-12 + 운영 진단 결과)

---

## 목표

vendedor / revendedor 듀얼 모드 Flutter 모바일 앱을 구축한다. 로그인 응답의 `role` 에 따라 데이터 가시 범위(scope)가 자동 결정되고, 백엔드 `MobileScopeGuard` 가 JWT claim 기반으로 URL 파라미터 조작에 의한 권한 우회를 차단한다. **vendedor MVP (1지점 BranchScope) 를 1차 출시 — coolsistema 베타 매장 2명 vendedor 대상**, revendedor (N매장 MultiStoreScope) 는 Phase 24 Wave 1-2 완료 후 활성화.

---

## 배경 및 컨텍스트

### 운영 진단 결과 (2026-05-31, 37-CONTEXT 의 `<diagnostic_results>`)
- vendedor user 단 2명, 모두 active, 모두 coolsistema(store_id=6), 서로 다른 branch 배치
- C_NEEDS_BACKFILL=0, MISMATCH=0, 다지점 vendedor 0명
- 데이터 정합성 깨끗 → 대규모 backfill 불필요, idempotent 2-row INSERT 만

### 운영 로그 진단 (2026-05-31, error 0건)
- `api-ventago/logs/error-2026-05-31.log` = 0 bytes ✅
- Pool 설정 확인: `min=10, max=80, idle=10000ms` (CLAUDE.md 일치)
- 다수 SlowQuery (>100ms): products, role_functions, Sellers, mp_accounts, cash_registers, sales (CTE WITH bounds)
- 🔴 [615ms] products, 🔴 [557ms] role_functions — Phase 37 모바일 트래픽이 이 위에 얹히면 위험 → **MemoryCacheService 1차 방어선 의무화** (D-04)

### 관련 코드 파일
- `api-ventago/src/app/auth/auth.service.ts` (signIn) — JWT payload 구조 (name/lastName/email/status/trialEndsAt/roles/storeId)
- `api-ventago/src/app/session/` — 기존 데스크탑 active_sessions 패턴 (분리 의무)
- `api-ventago/src/app/sales/sales-create.service.ts` — 트랜잭션 패턴 (read committed + LOCK FOR UPDATE)
- `api-ventago/src/database/database.module.ts` — Pool 설정 + 모니터링 (80% / waiting 경고)
- `api-ventago/src/app/permissions/models/user-branch.model.ts` — Phase 33 user_branches
- `talleres-vendor-app/pubspec.yaml` — Phase 17 Flutter 의존성 (riverpod 3.3.1 / dio 5.9.2 / secure_storage 10.0.0 / go_router 17.2.0 / intl 0.20.2)

### 운영 환경 사실
- 베타 매장: coolsistema (store_id=6)
- 베타 사용자: vendedor 2명 (Q1 결과)
- 운영 PG10, pgbouncer 5432 프록시, max_connections=300
- Mac dev PG18 5432 (postgres·marcoskim) 별도 — postgres-ventago MCP 는 로컬

---

## 기술 스택

- **백엔드**: NestJS 11 + Sequelize + PostgreSQL 10 (운영) / 15 (Docker dev)
- **인증**: JWT (passport-jwt) + 신규 `MobileSessionGuard`
- **모바일**: Flutter 3.11+ / Riverpod 3.3 / Dio 5.9 / flutter_secure_storage 10 / go_router 17
- **DB pool 라이브러리**: Sequelize 내장 pool (min=10/max=80) — gsd 의 pg.Pool 규칙은 Sequelize transaction 의 finally release 패턴으로 환원
- **ESLint 설정 파일**: `api-ventago/.eslintrc.*` (확인 필요, gsd Execute 단계에서)
- **신규 디렉토리**: `mobile-sales-app/` (모노레포 sibling, Phase 17 코드 패턴 복제)

---

## REQ-IDs (정제 완료, 12개 → 4 카테고리)

### 카테고리 A — Backend Auth & Scope (MOBILE-A-*)

- **MOBILE-A-01** — `mobile_sessions` 테이블 신규 (PG10/PG15 호환). 컬럼: id (UUID), user_id (INT FK), device_fingerprint (TEXT), fcm_token (TEXT nullable), scope_mode (TEXT CHECK in vendedor/revendedor), scope_branch_ids (INT[]), scope_store_ids (INT[]), active_session_token (UUID UNIQUE), last_seen_at (TIMESTAMPTZ), created_at. UNIQUE (user_id, device_fingerprint). 인덱스: user_id, active_session_token.
- **MOBILE-A-02** — `user_branches` backfill SQL (idempotent 2-row INSERT, 37-CONTEXT D-08). Plan 37-01 에 단일 SQL 파일로 포함.
- **MOBILE-A-03** — JWT payload 확장: 기존 payload 유지 + `mobileSessionToken: UUID` + `scopeMode: 'vendedor'|'revendedor'` + `scopeBranchIds: number[]` + `scopeStoreIds: number[]` 옵션 추가. 데스크탑 토큰은 이 필드 없음 (호환성).
- **MOBILE-A-04** — `POST /mobile/auth/login` 엔드포인트: bcrypt + 활성/매장상태 검증 (기존 signIn 재사용) + scope 결정 (vendedor: user_branches 또는 users.branch_id → scope_branch_ids / revendedor: reseller_tienda_link → scope_store_ids) + scope 없으면 401 `VENDEDOR_SCOPE_NOT_DEFINED` (vendedor 인데 branch 없음) 또는 `RESELLER_SCOPE_NOT_DEFINED` + mobile_sessions UPSERT.
- **MOBILE-A-05** — `MobileScopeGuard` (NestJS CanActivate): JWT 검증 → req.user.mobileSessionToken 으로 mobile_sessions 조회 → last_seen_at 갱신 (heartbeat) → req.scope 주입. 쿼리 파라미터 storeId/branchId 가 scope 와 충돌 시 403 `SCOPE_VIOLATION`. **PermissionGuard 와 직렬 사용** (PermissionGuard 후행).
- **MOBILE-A-06** — `GET /mobile/me` 엔드포인트: 토큰 검증 후 user + scope 정보 반환 (role, scopeMode, scopeBranchIds, scopeStoreIds, storeId, storeName, branchName, lastLoginAt).

### 카테고리 B — Backend Catalog/Stock/Sales (MOBILE-B-*)

- **MOBILE-B-01** — `GET /mobile/catalog` 단일 엔드포인트 (D-03). vendedor 응답: products + 자기 branch 의 product_branch stock 수치. revendedor 응답: products + 매장별 stock 합계 + min markup price. 응답 shape 공통 키 동일.
- **MOBILE-B-02** — `MemoryCacheService` 카탈로그 캐시 (D-04). 키: `mobile:catalog:v:${branchId}` TTL 60s / `mobile:catalog:r:${ownerGroupId}:${storeIdsHash}` TTL 60s. cache hit 비율 로깅.
- **MOBILE-B-03** — `GET /mobile/stock/:productId` 엔드포인트. vendedor: branch stock, revendedor: 매장별 stock. TTL 10s 캐시.
- **MOBILE-B-04** — `POST /mobile/sales` 엔드포인트. 기존 `sales-create.service` 호출 + `activity_type='sale'` (Phase 35) 명시 + Phase 25 store_clients scope 강제 + sales.user_id = JWT subject. 응답: saleId, dailyNumber, ticketUrl (Phase 11 print-agent 연동 hint).
- **MOBILE-B-05** — 모바일 sales 의 stock 차감은 기존 sales-create.service 의 트랜잭션 그대로 — 신규 SERIALIZABLE 트랜잭션 추가 금지 (race condition 보호는 LOCK FOR UPDATE 가 담당, 37-CONTEXT D-04).

### 카테고리 C — Flutter App (MOBILE-C-*)

- **MOBILE-C-01** — 신규 디렉토리 `mobile-sales-app/` 초기화 (Phase 17 `talleres-vendor-app` 패턴 복제). pubspec.yaml: riverpod 3.3.1 / hooks_riverpod 3.3.1 / dio 5.9.2 / flutter_secure_storage 10.0.0 / go_router 17.2.0 / intl 0.20.2 + (신규) `mobile_scanner` 또는 `qr_code_scanner` (바코드).
- **MOBILE-C-02** — Riverpod `scopeProvider` (StateNotifier): `/mobile/me` 응답 기반 BranchScope / MultiStoreScope 자동 결정. JSON 직렬화 + secure storage 영속.
- **MOBILE-C-03** — 로그인 화면: email + password (Phase 17 PIN 4자리와 다름 — vendedor 는 user 계정). 디바이스 fingerprint 자동 수집 (기존 Ventago 웹 패턴 모바일 환원).
- **MOBILE-C-04** — 홈 화면: vendedor 모드 = branch 정보 lock 표시 + 매출 요약 + 카탈로그 / 카트 / 판매 이력 4 탭. revendedor 모드 = Wave 5 에서 매장 selector + 견적 탭 추가.
- **MOBILE-C-05** — 카탈로그 화면: 상품 검색/필터 + stock 수치 색상 코드 (재고 부족 빨강) + 바코드 스캐너. 캐시 fresh-or-cache 패턴.
- **MOBILE-C-06** — 카트 + 결제 화면: 상품 수량 변경 + 할인 + 결제수단 선택 + 판매 확정 (`POST /mobile/sales`).
- **MOBILE-C-07** — 세션 만료 처리 (`MOBILE_SESSION_EXPIRED` 401): 토큰 폐기 + 로그인 화면 redirect + 토스트 알림 "다른 기기에서 로그인되어 세션이 종료되었습니다".

### 카테고리 D — Pool & Verification (MOBILE-D-*)

- **MOBILE-D-01** — 베타 측정 도구: `pg_stat_activity` 30초 단위 수집 스크립트 + Phase 37 모바일 트래픽 응답 시간 측정 (P95 ≤ 300ms, CLAUDE.md 성능 규약).
- **MOBILE-D-02** — UAT 시나리오 (coolsistema 2명 vendedor):
  - U1: vendedor1 모바일 로그인 → 자기 branch stock 만 보임
  - U2: vendedor1 이 ?branchId=vendedor2의 branch 로 URL 조작 → 403
  - U3: vendedor1 가 데스크탑 POS 동시 로그인 → 둘 다 살아있음
  - U4: 동일 vendedor1 가 다른 모바일 디바이스로 로그인 → 첫 모바일 세션 401 + 토스트
  - U5: vendedor1 가 모바일 판매 → 데스크탑 ventaVista 에 동일하게 표시 (activity_type='sale')
  - U6: 매장 SUSPENDED 전이 시 모바일 다음 요청 401 STORE_SUSPENDED
- **MOBILE-D-03** — 운영 Pool 변동 측정: 베타 시작 전/후 평균 connection 수, peak using%, waiting 발생 여부. CLAUDE.md 의 80% 경고 임계 초과 없음 검증.

---

## 태스크 목록 (Plan 분할 → 5 Waves)

### Wave 1 — Backend Auth & Scope (Plan 37-01)
- [ ] TASK-1.1: `mobile_sessions` 마이그레이션 SQL 작성 (PG10/PG15 호환) — 파일: `api-ventago/migrations/phase37-mobile-sessions.sql`
- [ ] TASK-1.2: `user_branches` backfill SQL (idempotent) — 파일: `api-ventago/migrations/phase37-vendedor-user-branches-backfill.sql`
- [ ] TASK-1.3: `MobileSession` Sequelize 모델 — 파일: `api-ventago/src/app/mobile/models/mobile-session.model.ts`
- [ ] TASK-1.4: `MobileAuthService.loginMobile()` + scope 결정 로직 — 파일: `api-ventago/src/app/mobile/auth/mobile-auth.service.ts`
- [ ] TASK-1.5: `MobileScopeGuard` — 파일: `api-ventago/src/app/mobile/guards/mobile-scope.guard.ts`
- [ ] TASK-1.6: `MobileAuthController` (POST /mobile/auth/login, GET /mobile/me) — 파일: `api-ventago/src/app/mobile/auth/mobile-auth.controller.ts`
- [ ] TASK-1.7: `MobileModule` 등록 + app.module.ts 에 import — 파일: `api-ventago/src/app/mobile/mobile.module.ts`
- [ ] TASK-1.8: Jest spec — `mobile-scope.guard.spec.ts` + `mobile-auth.service.spec.ts` (scope 충돌 403 / 세션 만료 401 / vendedor 0-branch 401)
- [ ] TASK-1.9: ESLint 검증 (`npx eslint api-ventago/src/app/mobile --fix`)

### Wave 2 — Backend Catalog/Stock/Sales (Plan 37-02)
- [ ] TASK-2.1: `MobileCatalogService` + 캐시 — 파일: `api-ventago/src/app/mobile/catalog/mobile-catalog.service.ts`
- [ ] TASK-2.2: `MobileStockService` + 10s 캐시 — 파일: `api-ventago/src/app/mobile/stock/mobile-stock.service.ts`
- [ ] TASK-2.3: `MobileSalesService` (sales-create 재사용 + activity_type=sale 강제) — 파일: `api-ventago/src/app/mobile/sales/mobile-sales.service.ts`
- [ ] TASK-2.4: `MobileCatalogController` (GET /mobile/catalog, GET /mobile/stock/:productId)
- [ ] TASK-2.5: `MobileSalesController` (POST /mobile/sales)
- [ ] TASK-2.6: Jest spec — scope 강제 / 캐시 hit-miss / sales-create 호출 검증
- [ ] TASK-2.7: PostgreSQL pool 안전 점검 — finally release 패턴 강제 (gsd 규칙)
- [ ] TASK-2.8: ESLint 검증

### Wave 3 — Flutter Shell (Plan 37-03)
- [ ] TASK-3.1: `mobile-sales-app/` Flutter 프로젝트 초기화 (Phase 17 패턴)
- [ ] TASK-3.2: Dio + interceptor (JWT 자동 주입, 401 시 secure storage clear + redirect)
- [ ] TASK-3.3: Riverpod `scopeProvider` + 모델 클래스
- [ ] TASK-3.4: 로그인 화면 + FCM 토큰 등록
- [ ] TASK-3.5: 세션 만료 처리 UI (`MOBILE_SESSION_EXPIRED`)
- [ ] TASK-3.6: go_router 라우팅 (BranchScope = home/catalog/cart/sales, MultiStoreScope = +stores selector)

### Wave 4 — Flutter Vendedor (Plan 37-04, MVP 1차 출시)
- [ ] TASK-4.1: 홈 화면 (branch lock + 매출 요약)
- [ ] TASK-4.2: 카탈로그 화면 + 검색 + stock 색상 코드
- [ ] TASK-4.3: 바코드 스캐너 통합 (mobile_scanner)
- [ ] TASK-4.4: 카트 + 결제 화면
- [ ] TASK-4.5: 영수증 인쇄 hint (Phase 11 print-agent WebSocket 호출은 deferred)
- [ ] TASK-4.6: UAT 시나리오 U1-U6 dev 환경 검증
- [ ] TASK-4.7: 베타 매장 coolsistema 배포 (sideload .apk/.ipa)

### Wave 5 — Flutter Revendedor (Plan 37-05, Phase 24 Wave 1-2 후 활성화)
- [ ] TASK-5.1: 매장 selector 위젯
- [ ] TASK-5.2: 매장별 최소가 / 마진 계산기
- [ ] TASK-5.3: 견적 (quote) 생성 화면
- [ ] TASK-5.4: Phase 24 quote API 연동
- [ ] TASK-5.5: 정산 내역 화면

---

## 완료 기준

### Wave 1-4 (Vendedor MVP) — 1차 출시 기준
1. **ESLint 오류 0개** (api-ventago + mobile-sales-app)
2. **PostgreSQL pool 안전 검증** — gsd 체크리스트 통과 (모든 transaction finally release, 신규 Pool 생성 없음, idleTimeoutMillis 설정 유지)
3. **운영 Pool 영향 검증** — 100명 동시 모바일 접속 시뮬레이션에서 `using%` ≤ 30%, `waiting` = 0
4. **UAT U1-U6 dev 환경 PASS**
5. **베타 coolsistema 2명 vendedor 1주 운영** — 운영 에러 로그 신규 0건 확인
6. **모바일 판매가 데스크탑 ventaVista 에 동일 표시** (activity_type='sale' 정합성)
7. **다른 기기 로그인 시 첫 세션 401 + 토스트 동작**
8. **데스크탑 + 모바일 동시 접속 유지** (mobile_sessions 분리 효과 검증)

### Wave 5 (Revendedor) — Phase 24 Wave 1-2 완료 후 별도 release
9. revendedor 매장 selector + 매장별 최소가 표시 + 견적 생성 동작
10. Phase 24 quote API 와 정상 연동

---

## 금지사항 / 주의사항

### 데이터 모델
- **`Sellers` 테이블과 `vendedor` role user 를 혼동 금지** (37-CONTEXT diagnostic_results). `sales.user_id` = vendedor user, `sales.seller_id` (있다면) = Sellers row. 두 FK 가 다른 테이블 참조.
- **`mobile_sessions` 를 데스크탑 `active_sessions` 와 통합 금지** (D-06). 두 테이블 분리 유지.
- **`scope_branch_ids` / `scope_store_ids` 를 boolean 또는 단일 값으로 축소 금지** (D-05). 배열 유지.

### 백엔드
- **신규 `Pool` 인스턴스 생성 금지** — Sequelize 전역 pool 재사용 (database.module.ts).
- **모바일 전용 SERIALIZABLE 트랜잭션 추가 금지** — 기존 sales-create.service 의 LOCK FOR UPDATE 패턴 재사용.
- **클라이언트 query param storeId/branchId 신뢰 금지** — JWT scope 와 충돌 시 403 강제.
- **카탈로그 캐시 누락 금지** — 모든 `GET /mobile/catalog` 호출이 MemoryCacheService 를 거치는지 ESLint custom rule 또는 코드 리뷰 체크.
- **role_functions slow query 위에 모바일 트래픽 얹기 금지** — Phase 33 `user_permission_cache` 5분 TTL 가 작동하는지 spec-execute 사이에 한 번 확인.

### 프론트 (Flutter)
- **JWT 토큰 SharedPreferences 저장 금지** — flutter_secure_storage 만 사용.
- **카탈로그 응답을 Hive/sqflite 영구 저장 금지 (MVP)** — 메모리 + 30분 lastFetch 캐시만. 오프라인 판매는 deferred.
- **모바일 앱에서 별도 Pool/DB 연결 금지** — 모든 데이터는 백엔드 API 경유.

### 운영 배포
- **Phase 35 미적용 운영에 Phase 37 배포 금지** — `activity_type='sale'` 필터 의존. Phase 36 운영 적용 (35 운영 잠금 해제) 완료 후 Phase 37 운영 적용.
- **베타 매장 coolsistema 외 다른 매장 동시 배포 금지** (D-09). 1주 운영 검증 후 매장 확대.

### Phase 37 범위 외 (별도 phase)
- ACE Phase 33 신규 role 8개 미사용 (D-12) — Phase 37 영향 없음.
- Mercadopago Point 모바일 통합 (Phase 30) — Phase 30 완료 후.
- AFIP 영수증 발행 (Phase 10) 모바일 통합 — Phase 10 완료 후.
- 오프라인 판매 큐잉 — MVP 후 deferred.

---

## API 계약 요약

### POST /mobile/auth/login
```json
// Request
{
  "email": "vendedor1@coolsistema.com",
  "password": "...",
  "deviceFingerprint": "sha256-hash",
  "deviceToken": "fcm-token-optional"
}

// Response 200
{
  "accessToken": "eyJ...",
  "mobileSessionToken": "uuid-v4",
  "user": {
    "id": 123, "name": "...", "email": "...",
    "role": "vendedor",
    "scopeMode": "vendedor",
    "scopeBranchIds": [5],
    "scopeStoreIds": null,
    "storeId": 6, "storeName": "coolsistema",
    "branchName": "Sucursal Centro"
  }
}

// Response 401 시나리오
{ "code": "VENDEDOR_SCOPE_NOT_DEFINED", "message": "..." }
{ "code": "USER_INACTIVE_OR_SUSPENDED", "message": "..." }
{ "code": "STORE_SUSPENDED", "message": "..." }
{ "code": "INVALID_CREDENTIALS", "message": "..." }
```

### GET /mobile/me
```json
// Headers: Authorization: Bearer <token>
// Response 200 — login 의 user 객체와 동일 + lastLoginAt + cachedAt
```

### GET /mobile/catalog
```json
// Query: ?search=...&categoryId=...&offset=0&limit=50
// Response (vendedor)
{
  "items": [
    { "productId": 1, "name": "...", "sku": "...", "price": 1000.0,
      "stockByBranch": { "5": 10 } /* 자기 branch 만 */ }
  ],
  "total": 250, "cachedAt": "2026-05-31T08:00:00Z"
}

// Response (revendedor) — items 의 stockByStore: { 6: 30, 8: 12 } + minMarkupPrice
```

### POST /mobile/sales
```json
// Request — 기존 sales-create DTO 와 호환
{
  "branchId": 5, "boxId": 12, "terminalId": 33,
  "items": [{ "productId": 1, "quantity": 2, "unitPrice": 1000 }],
  "paymentMethods": [{ "methodId": 1, "amount": 2000 }],
  "clientId": null
}

// Response 201
{ "saleId": 9876, "dailyNumber": 42, "ticketUrl": "..." }
```

---

## mobile_sessions DDL (TASK-1.1 초안)

```sql
-- PG10/PG15 호환. PG10 은 gen_random_uuid() 가 pgcrypto extension 필요 — 미설치 시 app-level UUID 생성.
-- 운영 PG10 의 pgcrypto 존재 여부 확인 SQL: SELECT * FROM pg_extension WHERE extname='pgcrypto';

CREATE TABLE IF NOT EXISTS mobile_sessions (
  id UUID PRIMARY KEY,                     -- app-level uuidv4() 로 생성 (extension 의존 회피)
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_fingerprint TEXT NOT NULL,
  fcm_token TEXT NULL,
  scope_mode TEXT NOT NULL CHECK (scope_mode IN ('vendedor', 'revendedor')),
  scope_branch_ids INT[] NULL,
  scope_store_ids INT[] NULL,
  active_session_token UUID UNIQUE NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mobile_sessions_user_device
  ON mobile_sessions(user_id, device_fingerprint);
CREATE INDEX IF NOT EXISTS idx_mobile_sessions_user
  ON mobile_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_mobile_sessions_last_seen
  ON mobile_sessions(last_seen_at);

COMMENT ON TABLE mobile_sessions IS 'Phase 37 — 모바일 세션. 데스크탑 active_sessions 와 분리되어 동시 접속 가능.';
COMMENT ON COLUMN mobile_sessions.scope_mode IS 'vendedor=1지점 BranchScope / revendedor=N매장 MultiStoreScope';
COMMENT ON COLUMN mobile_sessions.scope_branch_ids IS 'vendedor 의 user_branches 매핑 캐시 (1개 또는 N개, D-05 scope-set)';
```

---

## user_branches backfill SQL (TASK-1.2)

```sql
-- 운영 진단 결과 active vendedor 2명 모두 users.branch_id NOT NULL + MISMATCH 0건.
-- idempotent INSERT — 이미 user_branches 매핑 있으면 skip.

INSERT INTO user_branches
  (user_id, branch_id, role_id, is_default, valid_from, granted_by, reason, created_at, updated_at)
SELECT
  u.id, u.branch_id, ur.role_id, true, NOW(), NULL,
  'Phase 37 Mobile Sales Shell — vendedor user_branches backfill', NOW(), NOW()
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id
WHERE r.slug = 'vendedor'
  AND u.status = 'active'
  AND u.branch_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM user_branches ub
    WHERE ub.user_id = u.id AND ub.branch_id = u.branch_id
  );

-- 검증 쿼리 (적용 후):
-- SELECT COUNT(*) FROM user_branches ub
-- JOIN user_roles ur ON ur.user_id = ub.user_id AND ur.role_id = ub.role_id
-- JOIN roles r ON r.id = ur.role_id WHERE r.slug = 'vendedor';
-- 예상값: 2
```

---

## 의존성 그래프

```
Phase 33 (Permissions v2) ──┐
                            ├─→ Phase 37 Wave 1 (Backend Auth/Scope)
Phase 35/36 (Activity Ledger 운영) ─┤        ↓
                                    └─→ Phase 37 Wave 2 (Backend Catalog/Sales)
                                                ↓
Phase 17 (Flutter 인프라) ────────────→ Phase 37 Wave 3 (Flutter Shell)
                                                ↓
                                        Phase 37 Wave 4 (Vendedor MVP)
                                                ↓ (1차 출시)
Phase 24 Wave 1-2 (Reseller catalog_unified MV) ─→ Phase 37 Wave 5 (Revendedor)
```

---

## Plan 분할 결정

- **Plan 37-01** = Wave 1 (Backend Auth/Scope) — 9 tasks
- **Plan 37-02** = Wave 2 (Backend Catalog/Sales) — 8 tasks
- **Plan 37-03** = Wave 3 (Flutter Shell) — 6 tasks
- **Plan 37-04** = Wave 4 (Vendedor MVP) — 7 tasks
- **Plan 37-05** = Wave 5 (Revendedor) — 5 tasks (Phase 24 의존, 별도 release)

각 Plan 은 `.planning/phases/37-mobile-sales-shell/37-NN-PLAN.md` 형식으로 spec 승인 후 작성.

---

## SPEC 승인 후 다음 단계

1. 사용자가 SPEC 검토 후 승인
2. `/gsd-plan-phase 37` 또는 직접 Plan 37-01 작성 요청
3. Plan 37-01 의 TASK 1.1 부터 execute 진입

---

*GSD spec phase 완료 2026-05-31. CONTEXT 의 12 locked decisions (D-01..D-12) 와 모순 없음.*
