# Phase 37: Mobile Sales Shell — Context

**Gathered:** 2026-05-31
**Status:** Ready for spec (/gsd-spec-phase 37)
**Mode:** New feature — Flutter 모바일 앱 (vendedor + revendedor 듀얼 모드)

<domain>
## Phase Boundary

하나의 Flutter 모바일 앱이 로그인한 사용자의 `role` 을 보고 데이터 가시 범위(scope)를 자동 결정한다. `role=vendedor` 인 사용자는 자기 1지점(branch)의 stock 만 조회·판매할 수 있는 BranchScope 모드로, `role=revendedor` 인 사용자는 owner 그룹 내 허용된 N개 매장의 통합 카탈로그를 보고 견적·주문하는 MultiStoreScope 모드로 작동한다.

별도 앱 2개가 아니라 **동일한 Flutter 앱이 듀얼 모드**. 백엔드는 동일한 `/mobile/*` 엔드포인트에서 JWT claim 의 role 과 scope 를 강제하여, 클라이언트가 URL 파라미터를 조작해 다른 지점/매장의 데이터에 접근하는 것을 원천 차단한다.

Phase 17 Portal de Talleres 의 Flutter 인프라(Dio + Riverpod + secure storage + FCM + JWT auth + 매장 탭 패턴)를 100% 재사용하되, 별도 저장소가 아니라 monorepo workspace 의 새 디렉토리로 흡수한다. 데스크탑 POS 의 `active_sessions` 와 분리된 `mobile_sessions` 테이블을 사용하여 한 유저가 데스크탑 POS 와 모바일을 동시에 운영할 수 있다.

vendedor MVP 를 먼저 출시하고, revendedor 모드는 Phase 24 Wave 1-2 (`reseller.catalog_unified` Materialized View) 완료 후 Wave 5 에서 활성화한다.

</domain>

<decisions>
## Implementation Decisions

### D-01: 단일 앱, 듀얼 모드 (별도 앱 2개 금지)
하나의 Flutter 앱이 `/me` 응답의 `role` 을 보고 BranchScope / MultiStoreScope 를 자동 결정. UI 라우팅만 분기, 인프라(Dio/Riverpod/secure storage/FCM/세션 가드)는 100% 공유. Phase 17 Portal de Talleres 코드를 fork 하지 않고 monorepo workspace 로 흡수.

**Why:** 별도 앱 2개를 만들면 인증/네트워크/세션 가드/UI 컴포넌트의 유지보수 비용이 2배. 6개월 뒤 한쪽에만 적용된 보안 패치가 다른쪽에 빠지는 사고 위험.

### D-02: Scope 강제는 100% 백엔드 책임 (클라이언트에 절대 위임 금지)
모바일이 보내는 `?storeId=` / `?branchId=` 쿼리는 신뢰하지 않는다. 모든 `/mobile/*` 엔드포인트는 `MobileScopeGuard` 를 거쳐 JWT claim 의 `role` 을 보고 자동 scope 좁힘:
- `role=vendedor` → `WHERE user_branches.branch_id IN (?)` 강제. `user_branches` 매핑이 0건이면 401 `VENDEDOR_SCOPE_NOT_DEFINED`
- `role=revendedor` → `WHERE store_id IN (reseller_tienda_link.store_id WHERE reseller_id=?)` 강제

**Why:** Phase 25 의 `OwnerScopeGuard` 와 동일한 철학. URL 파라미터 조작으로 다른 지점 stock 을 보는 사고 원천 차단.

### D-03: Catalog/Stock 은 단일 엔드포인트, scope 만 다름
`GET /mobile/catalog` 하나로 통일. 응답 shape 의 공통 키는 동일하되 vendedor 응답에는 자기 branch 의 product_branch stock 수치, revendedor 응답에는 매장별 stock 합계 + min markup price.

**Why:** 2개 엔드포인트를 만들면 SQL/캐시/권한 로직이 2배 → 유지보수 비용 2배. 응답 shape 통일 → Flutter 가 같은 위젯으로 양쪽 렌더 → UI 코드도 단일.

### D-04: Pool 보호는 캐시 3-layer 로 (read replica 는 100명 넘어가면)
1. **1차 — Process-local `MemoryCacheService`** — 카탈로그 60초 TTL, stock 10초 TTL
2. **2차 — Phase 24 의 `reseller.catalog_unified` Materialized View** — 5분 refresh
3. **3차 — 실 DB SELECT** — 판매 확정 순간 (SERIALIZABLE 트랜잭션) 만

**Why:** 100명 동시 모바일 접속이 데스크탑 POS 의 PG pool 을 막아 매장이 멈추는 사고 방지. CLAUDE.md 의 Pool min=10/max=80 한도 안에서 모바일 +20 connection 이하 유지. (a) 별도 pgbouncer pool 분리 안 (mobile_pool=30, desktop_pool=60)은 동시접속 100명 넘어가면 그때 도입.

### D-05: Scope 는 boolean 이 아닌 set 으로 (확장성 함정 방지)
vendedor 의 `user_branches` row 가 1개면 strict 1지점, N개면 multi-branch. UI 만 selector 보이게 하면 즉시 다지점 vendedor 대응 가능. enum 으로 박지 않음.

**Why:** 처음부터 strict 1지점으로 만들면 6개월 뒤 "옆 지점 stock 만이라도 조회" 요구가 나올 때 데이터 모델 전체 갈아엎어야 함. Phase 33 의 `user_branches` 가 이미 다지점 매핑을 지원하므로 처음부터 set 으로 받는 것이 자연스럽다.

### D-06: `mobile_sessions` 는 데스크탑 `active_sessions` 와 분리
한 유저가 데스크탑 POS 와 모바일을 동시에 운영할 수 있도록 세션 테이블을 분리. `mobile_sessions.user_id` 는 UNIQUE 가 아니라 `(user_id, device_fingerprint)` UNIQUE — 한 유저가 모바일+태블릿 동시 가능.

**Why:** 기존 `active_sessions` 는 userId UNIQUE 라 데스크탑에서 로그인한 채 모바일로 로그인하면 데스크탑 세션이 죽는다. vendedor 가 데스크탑 POS 옆에 모바일 들고 다니는 운영 현실 반영.

### D-07: vendedor MVP 먼저, revendedor 는 Phase 24 완료 후
Plan 04 (vendedor 화면) 까지 MVP 1차 출시. Plan 05 (revendedor 화면) 는 Phase 24 Wave 1-2 (`reseller.catalog_unified` MV) 완료 후 활성화. vendedor 만으로도 충분한 가치 + 운영 검증 가능.

**Why:** 두 모드를 동시에 출시하면 베타 매장에서 두 시나리오를 한 번에 검증해야 해서 회귀 추적 어려움. vendedor 로 운영 PG pool 영향과 모바일 세션 안정성 먼저 검증.

### D-08: Plan 37-01 backfill 은 idempotent 2-row INSERT 만 (대규모 마이그레이션 X)
운영 진단(2026-05-31) 결과 vendedor user 가 2명 뿐이며 모두 `users.branch_id NOT NULL` + `branch.store_id` 정합. C_NEEDS_BACKFILL = 0. Plan 37-01 의 마이그레이션 SQL 은 다음 1개 쿼리로 충분:
```sql
INSERT INTO user_branches (user_id, branch_id, role_id, is_default, valid_from, created_at, updated_at)
SELECT u.id, u.branch_id, ur.role_id, true, NOW(), NOW(), NOW()
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
```

**Why:** 진단 결과 운영 영향 2 row. 대규모 backfill 스크립트/runbook 불필요. Pool 부담 0. 롤백 trivial (`DELETE FROM user_branches WHERE …`).

### D-09: 베타 매장 coolsistema (store_id=6) 확정
운영 vendedor user 2명 모두 coolsistema 소속. 2명이 각각 다른 branch 에 배치되어 1지점 vendedor 시나리오 검증에 이상적. CART/genius/ACE 는 vendedor user 0명이라 베타 불가.

**Why:** 다른 매장으로 베타하면 신규 vendedor user 생성 + Sellers row 매핑 + branch_id 설정까지 모두 준비해야 하는 부담. coolsistema 는 이미 모든 전제 충족.

### D-10: Multi-branch vendedor UI 는 1차 출시에서 제외 (후순위)
데이터 모델(D-05: scope-set, user_branches N-row)은 그대로 유지하되, **Plan 37-04 의 Flutter UI 에서는 branch selector 자체를 렌더링하지 않음**. `user_branches` 가 1 row 인 경우 selector lock + 지점명 readonly 표시.

**Why:** 운영 진단에서 다지점 vendedor 0명. 6개월 후 요구 발생하면 selector 위젯만 unhide 하면 됨 (데이터 모델은 이미 N-row 지원). 1차 출시 일정 단축.

### D-11: Vendedor user 폭증 없음 가정 — D-07 "vendedor MVP 우선" 유지
사용자 결정(2026-05-31): 모바일 도입 후에도 vendedor user 가 크게 늘지 않을 것으로 예상. 그러나 D-07 의 "vendedor MVP 먼저 출시" 결정은 유지 — revendedor 모드는 Phase 24 Wave 1-2 완료 전제라 그 자체로 더 큰 의존성.

**Why:** vendedor 폭증 없음 = 베타 규모 작음 = 운영 안정성/Pool 영향 검증 부담 작음 = 1차 출시 안전. revendedor 우선순위 변경하지 않음 — 두 모드의 의존성 구조가 본질적으로 다르기 때문.

### D-12: ACE (store_id=9) 의 Phase 33 신규 role 8개 미사용 — Phase 37 범위 외 (별도 phase 후보)
Q7b 결과 ACE 의 Phase 33 신규 role 8개(store_owner/store_admin/branch_manager/cashier/inventory_clerk/accountant/viewer/Dueño)가 모두 user_count=0. Phase 33 의 role 마이그레이션이 ACE 에서 실패/미실행 상태일 가능성.

**Why:** Phase 37 모바일 앱과 직접 관련 없으나 별도 점검 phase 등록 권고 사항으로 memory 에 기록. Phase 37 spec/plan/execute 진행 중에는 이 사실에 영향받지 않음.

### D-13: 모바일 판매는 "확정 Sale" 이 아니라 "보류(suspendido)" 로 생성 — Caja/매상 무영향, stock 만 임시 예약 (vendedor + revendedor 공통) ⭐ 핵심 결정 (2026-06-11, 사용자 지시)

**결정:** vendedor / revendedor 가 모바일 앱에서 "판매" 를 만들면, 그 즉시 확정 판매(`Sale` row)로 기록되어 Caja(금전함) 나 그 날 매상(daily revenue)에 영향을 주는 것이 **아니다**. 대신 **stand-by(보류) 상태로 `suspendido lista`(보류 판매 목록)에 대기**한다. 재고(stock)에만 **임시로** 영향을 준다(예약/hold).

확정 매출·Caja 반영은 **데스크탑 POS 운영자가 보류 목록에서 해당 건을 복원(restore)하여 결제·확정할 때** 비로소 발생한다. 모바일은 "판매 제안/대기열 적재" 까지만 책임진다.

**이것이 뒤집는 기존 가정 (SUPERSEDES):**
- MOBILE-B-04/B-05 — `POST /mobile/sales` 가 `sales-create.service` 호출 + `activity_type='sale'` 확정 판매 생성 → **폐기**
- MOBILE-C-06 — 카트 화면의 "판매 확정" → "보류 전송(En espera)" 으로 변경
- ROADMAP 성공기준 6 — "모바일 판매는 sales-create 재사용 + activity_type='sale'" → 보류 생성으로 정정
- UAT U5 — "모바일 판매 → 데스크탑 ventaVista 에 activity_type='sale' 로 표시" → "데스크탑 보류 목록(suspendido lista)에 표시" 로 정정

**재사용할 기존 메커니즘 (신규 발명 금지 — 이미 운영 중):**
- 모듈: `api-ventago/src/app/suspended-sales/` (`SuspendedSalesService`, `SuspendedSalesController`)
- 테이블: `SuspendedSale` + `SuspendedSaleItem` + `SuspendedSaleDiscount` + `SuspendedSaleRecharge`
- 엔드포인트: `POST /suspended-sales`(생성), `GET /suspended-sales`(매장별 목록), `GET/PUT/DELETE /suspended-sales/:id`
- **재고 예약 방식:** `Stocks` 테이블에 `type:'suspend'` row 기록 — 생성 시 `stock:-qty`(hold), 복원/취소(`DELETE`)·수정 시 `stock:+qty`(release). `Sale`·`SaleItem` 은 만들지 않으므로 Caja/매출 통계에 **잡히지 않음** (`recordReservationMoves`, suspended-sales.service.ts:59).
- 데스크탑 프론트: `nueva-venta` 의 "Suspender / 보류 복원" 흐름이 이미 이 목록을 소비·확정함.

**vendedor vs revendedor 모드 모두 적용 ("revendedor 도 마찬가지"):**
- **vendedor** → 자기 1지점 `suspended_sale` 로 적재. 데스크탑 POS 운영자가 같은 지점 보류 목록에서 확정.
- **revendedor** → 본질적으로 동일(비확정). Wave 5 의 revendedor 경로는 Phase 24 `reseller` 스키마의 **견적(quote) → 주문(order) pending** 상태가 곧 "보류" 에 해당한다. Tienda 가 확정·출고할 때까지 Caja/매출 무영향, 재고는 예약 수준. 즉 두 모드 공통 불변식 = **"모바일은 절대 직접 Caja/매상을 건드리지 않는다. 재고만 임시 예약. 확정은 매장측(데스크탑/Tienda)이 한다."**

**Why:**
1. **부정/오기입 방지** — 판매원이 현장에서 만든 건을 매장 운영자가 검토·확정하는 통제 단계를 둔다. 모바일에서 바로 Caja 가 움직이면 정산 사고·분쟁 시 추적이 어렵다.
2. **Caja 무결성** — 금전함은 데스크탑 POS 결제 흐름(현금/카드/MP)에서만 변동. 모바일에 결제수단·금전함 책임을 위임하지 않는다.
3. **매출 통계 무오염** — 보류 건은 `Sale` 이 아니므로 모든 매출 쿼리(`activity_type='sale'` 필터)에 자연히 제외됨. 별도 필터 불필요.
4. **재고 가시성** — 현장에서 잡아둔 물량이 즉시 다른 채널에 안 팔리도록 `type:'suspend'` 예약으로 hold. 확정/취소 시 정확히 release.

**구현 영향 (Plan 37-02 / 37-04 재작성 필요):**
- `MobileSalesService` 는 `sales-create.service` 가 아니라 `SuspendedSalesService.create` 를 호출(또는 동등 로직). 결제수단·금전함 파라미터 받지 않음.
- 모바일 응답: `saleId`(확정 판매번호) 대신 `suspendedSaleId` + "대기열 적재됨" 상태. 영수증 즉시 출력 hint 제거(확정 전이므로).
- **Phase 35/36 배포 게이트 재평가 필요:** 모바일이 확정 `Sale`(activity_type='sale')을 직접 만들지 않으므로, 모바일 출시가 Phase 35/36 운영 잠금 해제에 **하드 의존하지 않을 가능성**. 단, 데스크탑 확정 단계는 여전히 Phase 35/36 영향권 → **게이트 변경은 사용자 확인 후 별도 결정** (이 문서에서 단정하지 않음).

### D-14: 재고 조회 진입점이 다름 — vendedor=QR 스캔(타 지점 stock 포함), revendedor=카탈로그 검색(QR 불필요) ⭐ UI/UX 핵심 차이 (2026-06-11, 사용자 지시)

**결정:** 두 모드의 "재고(stock) 조회 기능" 은 **진입 방식(entry point)과 가시 범위가 본질적으로 다르다.** 이 차이는 **UI/UX 설계 시 반드시 반영**해야 한다.

**vendedor — QR 스캔 기반, 현장형:**
- 판매원은 **자기 매장 안에서 상품 아래쪽에 붙은 QR 코드(CodigoMadre 라벨, Phase 38)** 를 스캔한다.
- 스캔 → **그 상품이 자기 매장의 여러 지점(sucursal)에서 각각 재고가 얼마인지** 한눈에 본다 (멀티-지점 재고 비교 뷰).
- QR 은 이미 존재: Phase 38 `buildQrPayload` 가 딥링크 `${PUBLIC_WEB_URL}/m/stock?s={storeId}&p={parentProductId}` 인코딩 (print.service.ts:92). 모바일 스캐너가 이 URL 의 `s`(storeId)/`p`(parentProductId) 를 파싱해 `GET /mobile/stock` 호출로 연결.
- **물리적 맥락:** 판매원은 매장에서 실물 상품을 손에 들고 있다 → QR 스캔이 가장 빠른 진입.

**revendedor — 카탈로그 검색 기반, 원격형:**
- revendedor 는 **QR 을 스캔할 필요가 없다** (실물 상품을 손에 들고 있지 않음 — 중개상).
- 자기가 **팔고자 하는 제품을 카탈로그에서 검색/브라우즈** → 그 제품의 재고 상황(허용된 N개 매장의 매장별 stock 합계)을 확인.
- 진입점 = 검색/카탈로그, **스캐너 아님**.

**Scope 정합 (중요 — 기존 D-02/D-03 보완):**
- **판매(SELL) scope 와 재고조회(STOCK-READ) scope 는 다르다:**
  - vendedor SELL = 자기 1지점 strict (보류 적재도 자기 지점, D-02 불변)
  - vendedor **STOCK-READ = 자기 매장의 전 지점 read-only** (QR 의 `s=storeId` 단일 매장 내 멀티-지점). 판매는 못 해도 "옆 지점에 재고 있나?" 확인은 가능.
- 이것은 **D-05(scope-set 설계)가 예고한 "옆 지점 stock 만이라도 조회" 요구가 실제로 발현된 것** — 데이터 모델 변경 없이 read scope 만 매장 전 지점으로 확장.
- revendedor STOCK-READ = `reseller_tienda_link` 허용 N개 매장의 매장별 합계 (D-03 그대로).

**UI/UX 설계 함의 (사용자가 명시한 기록 목적):**
- **vendedor 홈/카탈로그:** 1차 액션으로 **QR 스캐너 버튼을 전면 배치**. 스캔 결과 = 단일 상품의 **지점별 재고 분해 뷰**(자기 지점 강조 + 타 지점 비교).
- **revendedor 홈:** 1차 액션은 **검색/카탈로그 브라우즈**. 스캐너 미노출(또는 숨김). 재고 = 매장별 합계 뷰.
- 즉 같은 "stock 화면" 이지만 vendedor 는 _scan-to-detail_, revendedor 는 _search-to-list_. MOBILE-C-04/C-05 가 이 분기를 반영해야 함.

**재사용 (신규 발명 최소):**
- QR 라벨/딥링크: Phase 38 `print/print.service.ts buildQrPayload` + print-agent `qr-formatter.js` (이미 운영). 모바일은 **딥링크 소비자** 역할만 신규.
- 스캐너 라이브러리: MOBILE-C-01 의 `mobile_scanner`/`qr_code_scanner` (vendedor 전용 활성).

### D-15: 상품 상세/수량 화면 = 웹 venta 의 변형 재고 매트릭스 모바일 이식 — 셀당 수량 직접 입력 + 지점별 재고 동시 표시 ⭐ UI 결정 (2026-06-11, 사용자 지시)

**결정:** 제품 선택 후 수량을 정하는 화면(흐름 4번)은 +/- 스테퍼가 아니라, **웹 앱 venta 의 변형(색×사이즈) 재고 매트릭스를 그대로 모바일에 이식**한다. 사용자가 **각 변형 셀에 사고 싶은 수량을 숫자로 직접 기입**하며, 셀마다 **현 지점 + 타 지점 재고가 함께** 보인다.

**원본 패턴 (재사용 — 신규 발명 금지):**
- `ventago-app/src/views/homes/components/ProductList/components/VariantsStockVenta.tsx`
- 구조: 색(행) × 사이즈(열) 스프레드시트. 각 셀 = number input(직접 타이핑) + 현 지점 stock 굵은 숫자 + 지점별 분포 이니셜 라벨(`H:20 A:0 D:50`). 색 코드 0=회색/양수=녹색/무재고=주황/초과=빨강. 수량>0 시 "Agregar" 노출.
- 수량 키: `quantities[`${colorId}-${sizeId}`]` → `variantQuantities` 로 카트 적재 (suspended-sales 의 `variantQuantities` 스키마와 동일 포맷, suspended-sales.service.ts:83 의 `colorId-sizeId` 파싱과 호환).
- `currentBranchId` prop 으로 현 지점 셀 강조 — D-14 의 "타 지점 비교" 가 이 매트릭스에서 셀 단위로 실현됨.

**모바일 이식 시 변경(Claude's Discretion 범위 내):**
- 색 토큰: 웹 MUI 블루(`#1976D2` 색 라벨/포커스)는 Ventago 테마 금지색 → 색 라벨 surface-2 칩, 포커스 골드 아웃라인+halo. 무재고 주황 → gold(warning), 초과 빨강 유지. (theme: sketch-findings-ace-online)
- 가로 폭: 사이즈 4열 초과 시 색 열 sticky + 사이즈 열 가로 스와이프(`SingleChildScrollView` horizontal).
- 무재고/초과 셀 입력은 **hard block 아님 — 경고만**(보류는 예약이라 타 지점 충당 가능, D-13/D-14 정합).

**vendedor vs revendedor (같은 위젯, 데이터 shape 만 분기):**
- vendedor: 컬럼/분포 = 내 매장의 지점들(내 지점 강조).
- revendedor: 분포 = 매장(tienda)별 + min markup price 행 추가 가능.

**Why:** 데스크탑 venta 를 쓰던 판매원이 **동일 인터랙션**(셀 직접 입력)으로 모바일에서 즉시 작업 가능 — 학습비용 0. +/- 스테퍼는 여러 변형을 한 번에 입력할 때 느림. 매트릭스는 "어느 talle/color 가 어느 지점에 있나" 를 한 화면에서 비교하며 입력하게 해줌 → MOBILE-C-08 로 명세.

### Claude's Discretion (planning 단계에서 결정)
- Flutter 프로젝트 디렉토리 구조 (Phase 17 패턴 따름)
- `MobileScopeGuard` 의 Sequelize raw SQL vs scope() 메서드 선택
- `mobile_sessions` 의 `last_seen_at` 갱신 주기 (heartbeat 간격)
- FCM 토큰 갱신 정책
- 오프라인 모드 캐시 저장 매체 (Hive vs sqflite)
- 바코드 스캐너 라이브러리 (mobile_scanner vs camera_kit)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 의존성
- `.planning/phases/33-permissions-v2/` — `user_branches`, `PermissionGuard`, `user_permission_cache` 5분 TTL
- `.planning/phases/17-portal-de-talleres-aviso/17-CONTEXT.md` — Flutter 인프라 결정사항 (D-01..D-12)
- `.planning/phases/17-portal-de-talleres-aviso/17-03-PLAN.md` — Flutter project + Dio + Riverpod + secure storage + auth flow
- `.planning/phases/17-portal-de-talleres-aviso/17-05-PLAN.md` — Notifications + FCM
- `.planning/phases/24-revendedor-marketplace/24-CONTEXT.md` — `reseller.catalog_unified` MV, `reseller_tienda_link`, canonical categories

### 백엔드 모델 (재사용 + 확장)
- `api-ventago/src/app/auth/interfaces/valid-roles.ts` — `ValidRoles.vendedor` 이미 존재
- `api-ventago/src/app/auth/auth.service.ts` — JWT 발급/검증 패턴
- `api-ventago/src/app/session/` — `active_sessions` (데스크탑) + `terminal_devices` + `branch_ip_registries` 패턴 참조
- `api-ventago/src/app/users/user-role/user-role.model.ts` — UserRole 다대다
- `api-ventago/src/app/role/role.model.ts` — Role 모델 + `users.branch_id` deprecate 진행 중 (Phase 33)
- `api-ventago/src/app/branch/branch.model.ts` — Branch 모델
- `api-ventago/src/app/products/products.service.ts` — 카탈로그 SELECT 패턴
- `api-ventago/src/app/sales/sales-create.service.ts` — 판매 확정 SERIALIZABLE 트랜잭션 (⚠️ D-13 으로 **모바일에서는 미사용** — 데스크탑 확정 전용)
- **`api-ventago/src/app/suspended-sales/` (D-13 핵심 재사용)** — `SuspendedSalesService.create` (보류 생성, Caja/매상 무영향), `recordReservationMoves` (`Stocks` `type:'suspend'` 예약, suspended-sales.service.ts:59). `POST/GET/PUT/DELETE /suspended-sales`. 모바일 판매 = 이 서비스 호출.
- **`api-ventago/src/app/print/print.service.ts` (D-14)** — `buildQrPayload` 가 QR 딥링크 `/m/stock?s={storeId}&p={parentProductId}` 인코딩 (line 79~101). 모바일 스캐너의 딥링크 소비 대상.
- `api-ventago/src/database/database.module.ts` — Pool 설정 (min=10, max=80)

### 권한 시스템
- Phase 33 `user_branches` 테이블 — (userId, branchId, roleId) 다지점 매핑
- Phase 25 `OwnerScopeGuard` + `@OwnerScope` 데코레이터 — scope guard 패턴 참조
- Phase 25 `global_clients` + `store_clients` — 매장 격리 패턴

### 활동 원장
- Phase 35 `sales.activity_type='sale'` 필터 — 모바일 판매도 동일 필터 적용
- Phase 35 `StockService.createStockMovement` — stock 차감 트랜잭션 패턴

### Flutter 인프라 (재사용)
- Phase 17 의 Flutter project (Dio + Riverpod + secure storage)
- Phase 17 의 FCM 등록 패턴
- Phase 17 의 세션 만료 처리

### UI 패턴 참조 (Flutter 이식 대상)
- **`ventago-app/src/views/homes/components/ProductList/components/VariantsStockVenta.tsx` (D-15 핵심)** — 상품 상세/수량 화면(MOBILE-C-08)의 원본. 색×사이즈 매트릭스 + 셀당 number input 직접 입력 + 셀당 지점별 재고(`currentBranchId` 강조). `variantQuantities` 키 포맷(`colorId-sizeId`). Flutter 로 이 위젯을 이식, 색만 Ventago 다크 테마로 치환.
- `Skill("sketch-findings-ace-online")` — Ventago 다크 네이비+골드 테마 토큰(모바일 화면 전체 색 기준).

### 프로젝트 컨벤션
- `CLAUDE.md` — Pool min=10/max=80, MemoryCacheService 60s/30s TTL, slow query 100ms
- `.planning/codebase/CONVENTIONS.md` — 코딩 컨벤션
- `.planning/intel/db-schema-tables.md` — 스키마 확인 필수

</canonical_refs>

<diagnostic_results>
## 운영 PG10 진단 결과 (2026-05-31)

`37-diagnostic-vendedor-scope.sql` 실행 결과. Plan 37-01 의 backfill 범위 결정 근거.

### vendedor user 분포
- **총 2명, 모두 active, 모두 store_id=6 (coolsistema)**
- 두 user 가 서로 다른 branch 에 배치 (distinct_branches=2)
- B_LEGACY_OK 2명 (users.branch_id 존재) — 자동 backfill 가능
- C_NEEDS_BACKFILL 0명 — 수동 매핑 필요한 사용자 없음
- D_UNUSABLE 0명 — 좀비 계정 없음

### 데이터 정합성
- `users.branch_id ↔ branches.store_id` MISMATCH 0건
- 다지점 vendedor 0명 (user_branches 아직 0 row)
- `user_branches` 테이블 존재 확인 (Phase 33 적용)

### 매장별 role 활성 사용자 분포 (Q7b)
| store_id | store | admin | gerente | vendedor | 신규 8 role |
|---|---|---|---|---|---|
| GLOBAL | - | 0 | 0 | 0 | superadmin=1 |
| 3 | CART | 2 | 1 | 0 | - |
| 6 | coolsistema | 2 | 0 | **2** | - |
| 8 | genius | 1 | 0 | 0 | - |
| 9 | ACE | 4 | 0 | 0 | **8 role 모두 0** |

### 관련 발견
- `Sellers` 테이블은 PascalCase quoted (운영 표준, memory 의 `ProductBranch` 패턴과 동일). `sellers.model.ts:16` `tableName: 'Sellers'`
- 주석: `Vendedor: 로그인 불가, 판매 시 태그용 엔티티 (User와 완전 별개)` — `vendedor` role user 와 `Sellers` row 는 다른 개념, Phase 37 spec 에서 분리 명시 필요
- ACE 의 Phase 33 신규 8 role 미사용 — D-12 참조 (Phase 37 범위 외, 별도 점검 phase 후보)

### 진단 SQL 파일
- `.planning/phases/37-mobile-sales-shell/37-diagnostic-vendedor-scope.sql`
- 결과 텍스트: `37-diagnostic-result-*.txt` (실행 시 timestamp 부여)

</diagnostic_results>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ValidRoles.vendedor` enum 이미 존재 (`api-ventago/src/app/auth/interfaces/valid-roles.ts:4`) — 신규 role 추가 없음
- Phase 17 Flutter 앱 코드베이스 — Dio + Riverpod + secure storage + FCM + 매장 탭 패턴 모두 검증됨
- Phase 33 `user_branches` 테이블 — vendedor 의 1지점 / 다지점 모두 row 개수로 표현 가능
- Phase 25 `OwnerScopeGuard` 패턴 — `MobileScopeGuard` 의 직접적 청사진
- Phase 35 sales `activity_type='sale'` 필터 — 모바일 판매 격리에 그대로 사용
- `MemoryCacheService` 인프라 — 카탈로그/stock 캐시에 즉시 사용 가능
- `sales-create.service.ts` SERIALIZABLE 트랜잭션 — 모바일 판매 확정에 그대로 호출

### Established Patterns
- NestJS Guard 체인 (`AuthGuard` → `SessionGuard` → 추가 ScopeGuard) — `MobileScopeGuard` 가 동일 패턴
- Sequelize `where` 동적 조건 주입으로 scope 강제 (Phase 25 패턴)
- Flutter Riverpod `Provider` 로 scope 모드 상태 관리 (Phase 17 패턴)
- JWT claim 확장 (Phase 33 의 permissions 맵 추가 패턴)

### Integration Points
- `mobile_sessions` 신규 테이블 (PG10/PG15 호환 마이그레이션)
- JWT payload 에 `scopeMode` + `scopeBranchIds[]` + `scopeStoreIds[]` claim 추가
- 신규 `/mobile/*` 컨트롤러 + `MobileScopeGuard`
- 기존 `sales-create.service` 호출부 — 모바일 판매도 동일 함수 호출 + activity_type='sale' 명시
- Flutter 앱 — monorepo workspace 의 새 디렉토리 (예: `mobile-sales/`)
- FCM 등록 — Phase 17 의 vendor_notifications 와 분리된 신규 `mobile_notifications` 테이블 (deferred to spec)

### Risk Surface
- vendedor 운영 데이터에서 `users.branch_id IS NULL` 또는 `user_branches` 0건인 사용자 존재 가능성 → Step 1 backfill 검증 필수
- Phase 33 의 `users.branch_id` deprecate 진행 중 — `user_branches` 와 동시 fallback 필요
- 운영 PG10 의 max_connections=300, pgbouncer 5432 프록시 — 모바일 트래픽 증가 시 pgbouncer 한도 점검
- `mobile_sessions` UNIQUE 가 device fingerprint 기반이라 fingerprint 충돌 시 세션 강제 종료 가능 → 안정적인 fingerprint 알고리즘 필요

</code_context>

<specifics>
## Specific Ideas (정착 후 spec/plan 에서 정제)

### mobile_sessions 스키마 초안
```sql
CREATE TABLE mobile_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id INT NOT NULL REFERENCES users(id),
  device_fingerprint TEXT NOT NULL,
  fcm_token TEXT,
  scope_mode TEXT CHECK (scope_mode IN ('vendedor','revendedor')) NOT NULL,
  scope_branch_ids INT[],   -- vendedor 의 user_branches 매핑 캐시 (1개 또는 N개)
  scope_store_ids INT[],    -- revendedor 의 reseller_tienda_link 캐시
  active_session_token UUID UNIQUE NOT NULL,
  last_seen_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, device_fingerprint)
);
CREATE INDEX idx_mobile_sessions_user ON mobile_sessions(user_id);
CREATE INDEX idx_mobile_sessions_token ON mobile_sessions(active_session_token);
```

### JWT claim 확장 초안
```typescript
interface MobileJwtPayload extends JwtPayload {
  scopeMode: 'vendedor' | 'revendedor';
  scopeBranchIds?: number[];   // vendedor 만
  scopeStoreIds?: number[];    // revendedor 만
  mobileSessionToken: string;  // mobile_sessions.active_session_token
}
```

### MobileScopeGuard 의사 코드
```typescript
@Injectable()
export class MobileScopeGuard implements CanActivate {
  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest();
    const { scopeMode, scopeBranchIds, scopeStoreIds } = req.user;

    // 토큰 scope 와 쿼리 파라미터 충돌 시 403
    if (req.query.branchId && scopeMode === 'vendedor') {
      const queried = Number(req.query.branchId);
      if (!scopeBranchIds.includes(queried)) {
        throw new ForbiddenException('SCOPE_VIOLATION');
      }
    }

    // 자동 scope 주입 (다운스트림 service 가 읽음)
    req.scope = { mode: scopeMode, branchIds: scopeBranchIds, storeIds: scopeStoreIds };

    return true;
  }
}
```

### 캐시 키 초안
- 카탈로그 vendedor: `catalog:v:${branchId}` TTL 60s
- 카탈로그 revendedor: `catalog:r:${ownerGroupId}:${storeIdsHash}` TTL 60s
- Stock vendedor: `stock:v:${branchId}:${productId}` TTL 10s
- Stock revendedor: `stock:r:${storeId}:${productId}` TTL 10s

### Flutter ScopeProvider 의사 코드
```dart
final scopeProvider = StateNotifierProvider<ScopeNotifier, ScopeState>((ref) {
  return ScopeNotifier(ref);
});

class ScopeNotifier extends StateNotifier<ScopeState> {
  Future<void> initFromMe() async {
    final me = await ref.read(apiProvider).get('/mobile/me');
    state = me.role == 'vendedor'
      ? ScopeState.branch(branchIds: me.scopeBranchIds)
      : ScopeState.multiStore(storeIds: me.scopeStoreIds);
  }
}
```

</specifics>

<deferred>
## Deferred Ideas (Phase 37 범위 외)

- 별도 pgbouncer pool 분리 (mobile_pool=30, desktop_pool=60) — 동시접속 100명 넘어가면 그때
- Mercadopago POS QR (Phase 29) 모바일 통합 — Phase 29 완료 후 별도 wave 또는 Phase 37.1
- AFIP 영수증 발행 (Phase 10) 모바일 통합 — Phase 10 완료 후
- 오프라인 판매 (확정까지 큐잉) — 1차 MVP 는 온라인 필수
- 마진 시뮬레이터 (revendedor 용) 의 고급 기능 — Phase 24 Wave 5 와 같이
- 매니저 승인 워크플로 (vendedor 가 할인 한도 초과 시 승인 요청) — Phase 33 approval_thresholds 와 연동, 별도 wave
- 모바일 화면 분석 이벤트 (PostHog) — 베타 후 결정
- iOS App Store / Android Play Store 배포 — Phase 17 처럼 sideload/enterprise 로 베타 → 정식 배포는 별도

</deferred>

<pitfalls>
## 빠지기 쉬운 함정 (planning 단계에서 명시적으로 회피)

### 함정 1: "vendedor 도 가끔은 옆 지점 stock 을 봐야 한다" 요구가 6개월 뒤 나옴
**회피:** D-05 — scope 를 boolean 아닌 set 으로 설계. `user_branches` row 가 1개면 strict, N개면 multi-branch. UI selector 토글만으로 즉시 대응.

### 함정 2: Pool 낭비를 카탈로그 캐시 없이 `catalog_unified` MV 만 믿음
**회피:** D-04 — 3-layer 캐시 (process-local → MV → DB). 100명 동시 접속이 100개 connection 으로 DB 를 때리지 않도록 process-local 1차 방어선 필수.

### 함정 3: 데스크탑 POS 와 모바일이 같은 `active_sessions` 공유 → 한쪽 죽음
**회피:** D-06 — `mobile_sessions` 별도 테이블, `(user_id, device_fingerprint)` UNIQUE. 한 유저 데스크탑+모바일+태블릿 동시 가능.

</pitfalls>

<checkpoints>
## 진행 점검 포인트

### 1주일 후 (spec 정합성)
- `MobileScopeGuard` 가 Phase 33 의 `PermissionGuard` 와 중복/충돌 없는지 검토
- 운영 vendedor 의 `user_branches` 매핑 실제로 1 row 인지, backfill 필요한지 확인
- Plan 04 / Plan 05 PR 분리 가능성 — 인프라가 너무 얽히면 분리 실패

### 1개월 후 (Vendedor MVP 베타)
- 베타 매장 1곳에서 모바일 판매 건수 / 데스크탑 판매 건수 비율
- `pg_stat_activity` 모바일 connection peak — +20 이하 유지되는지
- 모바일 판매의 `activity_type='sale'` 정확히 기록 (Phase 35 정합성)
- ventaVista 에서 모바일 판매가 데스크탑 판매와 동일하게 보이는지

### 3개월 후 (확장 결정)
- vendedor 모바일 채택률 — 30% 미만이면 UX 재검토
- Phase 24 진행도 맞물려 revendedor 모드 활성화 시점
- "옆 지점 stock 보기" 요구 발생 빈도 → multi-branch vendedor UI 도입 결정
- 모바일 트래픽이 데스크탑 P95 latency 에 영향 주는지

</checkpoints>

---

*Phase: 37-mobile-sales-shell*
*Context gathered: 2026-05-31*
*Next step: /gsd-spec-phase 37 → REQ-IDs (MOBILE-01..NN) 정제 후 plan 분할*
