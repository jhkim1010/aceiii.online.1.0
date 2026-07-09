---
phase: 37-mobile-sales-shell
plan: 04
subsystem: mobile-vendedor-mvp
tags: [mobile, flutter, riverpod, vendedor, catalog, stock-matrix, suspended-sale, offline, qr]
requires:
  - 37-02 (GET /mobile/catalog, GET /mobile/stock/:id, POST /mobile/sales)
  - 37-03 (Flutter shell: dio_client, ScopeProvider, AppTheme, go_router, secure storage)
provides:
  - Home QR-first (Escanear QR → scanner sheet, Ver carrito badge)
  - Catálogo (GET /mobile/catalog, search, stock pills ok/low/out, out→detail)
  - QR scanner (mobile_scanner → parseStockDeeplink /m/stock?p= → /product/:id) — D-14 scan-to-detail
  - Variant matrix detail (D-15 port of VariantsStockVenta): color×size grid, direct qty input, own-branch cap (UI-D2), mine/otras read-only, NO over/red, NO traslado
  - Comanda (variant lines + stepper + cliente opcional + gold "Mandar a Caja") — POST /mobile/sales suspended (D-13), NO payment UI
  - Offline guard (connectivity_plus): offline → CTA disabled + "Requiere conexión" (criterion 11)
  - Done "En la lista de espera" + ticket + reserva box
affects:
  - (parent repo) mobile-sales-app/ Wave 4 vendedor screens (replaced Wave 3 route stubs)
tech-stack:
  added:
    - connectivity_plus ^6.1.0 (offline detection — criterion 11)
  patterns:
    - VariantMatrixController(ChangeNotifier) pure logic — own-branch clamp, colorId-sizeId keying, unit-tested
    - in-memory lastFetch catalog cache (cachedCatalogItem) doubles as QR-path hero/price source
    - cart holds variant(colorId-sizeId) lines; sale_repository groups by productId → items+variantQuantities
    - Riverpod 3: StateProvider→NotifierProvider (legacy removal), FutureProvider.family for stock (test-overridable)
key-files:
  created:
    - mobile-sales-app/lib/core/format/money.dart
    - mobile-sales-app/lib/core/network/connectivity_provider.dart
    - mobile-sales-app/lib/features/catalog/data/catalog_dto.dart
    - mobile-sales-app/lib/features/catalog/data/catalog_repository.dart
    - mobile-sales-app/lib/features/catalog/providers/catalog_provider.dart
    - mobile-sales-app/lib/features/catalog/views/catalog_screen.dart
    - mobile-sales-app/lib/features/scanner/views/qr_scanner_sheet.dart
    - mobile-sales-app/lib/features/product/data/stock_dto.dart
    - mobile-sales-app/lib/features/product/data/stock_repository.dart
    - mobile-sales-app/lib/features/product/providers/variant_matrix_provider.dart
    - mobile-sales-app/lib/features/product/widgets/variant_stock_matrix.dart
    - mobile-sales-app/lib/features/product/views/product_detail_screen.dart
    - mobile-sales-app/lib/features/cart/providers/cart_provider.dart
    - mobile-sales-app/lib/features/cart/data/sale_repository.dart
    - mobile-sales-app/lib/features/cart/views/comanda_screen.dart
    - mobile-sales-app/lib/features/done/views/done_screen.dart
    - mobile-sales-app/test/variant_matrix_test.dart
  modified:
    - mobile-sales-app/lib/features/home/views/home_screen.dart
    - mobile-sales-app/lib/router/app_router.dart
    - mobile-sales-app/pubspec.yaml
decisions:
  - "Riverpod 3.x 에서 StateProvider 가 core export 에서 제거(legacy 이동) → catalogSearchProvider 를 NotifierProvider<String> 로 구현 (Rule 3)."
  - "connectivity_plus 추가(계획 '연결 probe' 허용 범위) — 실시간 offline 스트림으로 criterion 11 CTA 게이트. 판매 시도는 서버가 최종 판정, 클라이언트는 낙관 online 기본값."
  - "QR 직행(캐시 미스) hero/price: /mobile/stock 는 상품 name/price 미반환 → in-memory 카탈로그 lastFetch 캐시(cachedCatalogItem)로 역참조. 캐시에도 없으면 hero 는 'Producto #{id}' + price '—'. 매트릭스(재고 비교 D-14 목적)는 완전 동작."
  - "cart 라인 = 변형(colorId-sizeId) 단위(S4 라인이 color·talle 표시). suspended POST 는 productId 로 그룹핑해 items+variantQuantities 구성(웹 계약 정렬)."
  - "매트릭스 셀 cap = variant.stock(자지점 net). 백엔드 stocks 원장 합계가 이미 예약(type:'suspend' 음수행)을 반영하므로 별도 reserva 차감 불필요 — 🔒 reserva 배지는 데이터 소스 부재로 생략(🛒 로컬 카트만)."
metrics:
  tasks: 2 (code) + 1 (human UAT gate, pending)
  files-created: 17
  files-modified: 3
  tests: 10 passed (scope 4 + variant matrix 6)
  duration: ~70m
  completed: 2026-07-08
---

# Phase 37 Plan 04: Vendedor MVP Screens Summary

Wave 3 셸 위에 vendedor 1차 출시 화면 전부를 구현했다: QR-first Home, Catálogo(검색+stock pill),
시그니처 color×talle 매트릭스 상세(D-15, 웹 VariantsStockVenta 이식), QR 스캐너(딥링크→상세),
Comanda(결제 UI 없이 "Mandar a Caja"→보류), Done("En la lista de espera"). 자지점만 판매(UI-D2),
AI 시착 없음(UI-D1), 결제/금전함 UI 없음(D-13). 오프라인 시 "Mandar a Caja" 는 비활성 +
"Requiere conexión"(criterion 11). 매트릭스 핵심 로직(자지점 cap 클램프 + colorId-sizeId 키잉)은
순수 컨트롤러로 분리해 단위 테스트 6/6 green.

## What Was Built

- **Home (S1)** — Escanear QR 버튼이 `showQrScannerSheet` 로 스캐너 바텀시트를 연다(D-14). Ver carrito
  는 카트 수량 badge(0 이면 숨김).
- **Catálogo (S2)** — `catalog_repository`(GET /mobile/catalog) + `catalog_provider`(검색 상태 +
  FutureProvider + in-memory lastFetch 캐시). 카드에 stock pill(ok≥11 green / low 1–10 amber /
  out=0 grey "Sin stock"), out(0) 카드도 상세 진입 허용(+토스트 "Sin stock en esta sucursal"). 하단
  카트 바(카트 있을 때만).
- **QR 스캐너** — `mobile_scanner` 바텀시트. 순수 함수 `parseStockDeeplink('/m/stock?s=&p=')` →
  parentProductId 추출 → `/product/:p` push. 비매칭 페이로드는 토스트("Código no reconocido"), 계속 스캔.
- **매트릭스 상세 (S3, D-15)** — `VariantMatrixController`(ChangeNotifier): colorId-sizeId 키,
  자지점 available 클램프(over/red 없음), selectedTotal/money/addEnabled 파생. `VariantStockMatrix`
  위젯: 색상 컬럼 sticky + talle 가로 스크롤, 셀 = **직접 숫자 입력(NO +/- stepper)** + 하단
  `{mine} (green/800) · otras:N (muted)` read-only. 상태: sel(gold+amber) / out(dash+비활성) /
  depleted(자지점 소진→비활성). `product_detail_screen`: hero + 매트릭스 + selbar +
  `✨ Probar con foto`(disabled + "Próximamente" 토스트, UI-D1) + `Añadir al carrito ({n})`.
- **Comanda (S4)** — `cart_provider`(변형 라인 + 자지점 stepper cap) + `sale_repository.sendToCaja`
  (POST /mobile/sales, productId 그룹핑, **paymentMethods 없음**). 라인(썸네일+color·talle+−/N/+
  +소계) + totbox + "Nombre del cliente (opcional)" + gold "🧾 Mandar a Caja". **OFFLINE GUARD**:
  `connectivity_plus` → 오프라인이면 CTA disabled + "Requiere conexión para mandar a caja"(criterion 11).
- **Done (S5)** — 초록 링 ✓ + "En la lista de espera" + body + "En espera N°{id}" + reserva 박스
  (셀별 −{qty} → {disp}) + Ver stock / Otra venta.

## must_haves Truths — Status

| Truth | Status | Evidence |
|-------|--------|----------|
| Home = branch lock + prominent QR button (D-14/5b) | ✅ | home_screen QR primary big → showQrScannerSheet |
| QR scan parses /m/stock?s=&p= → product detail matrix | ✅ | qr_scanner_sheet parseStockDeeplink → /product/:p |
| color×size matrix, direct numeric input (no stepper), own(bold)+otras read-only (D-15/UI-D2/5c) | ✅ | variant_stock_matrix TextField cells, mine/otras spans; test 3 |
| Cell input capped at own-branch; no over-order, no traslado (UI-D2) | ✅ | controller.setQty clamp(0,stock); test 2/4b; grep: 0 red/over-state, 0 traslado logic |
| Probar con foto disabled + Próximamente (UI-D1) | ✅ | _ProbarConFotoButton opacity 0.5 + "Próximamente" toast |
| "Mandar a Caja" → POST /mobile/sales suspended; Done "En la lista de espera" (D-13/6) | ✅ | sale_repository /mobile/sales (no paymentMethods); done_screen heading |
| OFFLINE: CTA disabled + "Requiere conexión"; catalog/stock browsable from cache (criterion 11) | ✅ | comanda _CtaBar online-gated; connectivity_provider; catalog in-memory cache |

## Verification Results (honest)

- `flutter analyze` (whole app) → **No issues found!** (0 errors/0 warnings) ✅
- `flutter test` → **10/10 passed** (scope_provider 4 + variant_matrix 6) ✅
- `flutter test test/variant_matrix_test.dart` → **6/6 passed** (keying, cap clamp, otras, addEnabled, depleted) ✅
- Contract greps: variant_stock_matrix `variantQuantities`✓ `colorId`✓ / qr_scanner `/m/stock`✓ /
  comanda `Mandar a Caja`✓ / sale_repository `/mobile/sales`✓ / comanda paymentMethods **0** ✓ /
  matrix `AppColors.red|Colors.red` **0** ✓ ✅
- **환경:** Flutter 3.41.2 stable / Dart 3.11.0, flutter=/Users/marcoskim/flutter/bin.

## TDD Gate Compliance

- variant matrix: RED `dd94918 test(37-04): failing variant matrix test` → GREEN `930449e feat(37-04): variant matrix detail…` (순서 준수 ✅). RED 시 컴파일 실패(getter 미정의)로 fail 확인 후 GREEN 구현.

## Deviations from Plan

### Auto-fixed / Auto-added (Rules 1-3)

**1. [Rule 3 - Blocking] Riverpod 3 StateProvider 제거 → NotifierProvider**
- `catalogSearchProvider` 를 `StateProvider<String>` 로 작성했으나 flutter_riverpod 3.3.1 core export 에서
  StateProvider 가 제거(legacy)되어 `undefined_function`. `NotifierProvider<CatalogSearchNotifier,String>`
  로 교체. **Commit:** 1f2eecf

**2. [Rule 3 - Blocking] connectivity_plus 추가 (계획 pubspec 미명시)**
- criterion 11 오프라인 게이트를 위해 실시간 연결 스트림 필요(계획이 "connectivity_plus 또는 dio probe"
  허용). `connectivity_plus ^6.1.0` 추가 + `isOnlineProvider`(StreamProvider<bool>). **Commit:** 1f2eecf

**3. [설계] QR 직행 hero/price 역참조**
- /mobile/stock 응답에 상품 name/price 가 없어(변형 재고만) QR 직행 경로의 hero 를 채울 수 없다. 카탈로그
  in-memory lastFetch 캐시(`cachedCatalogItem`)로 productId 역참조. 캐시 미스 시 hero='Producto #{id}',
  price='—' — 매트릭스(D-14 재고 비교)는 완전 동작. (아래 Known Stubs 참조)

### Design notes

- 매트릭스 셀 cap = variant.stock(자지점 net). 🔒 reserva 배지는 백엔드가 변형별 예약 수치를 별도 반환하지
  않아 생략(원장 합계가 이미 예약 반영). 🛒 카트 배지는 로컬 cart 로 표현 가능하나 MVP 에선 상세→카트 단방향
  이므로 셀 배지 대신 하단 selbar/카트 화면에서 수량을 확인.

## Known Stubs

- **카테고리 pill** — Wave 2 백엔드에 카테고리 목록 엔드포인트가 없어 Catálogo 의 pill 스트립은 "Todos"
  활성 1개만 렌더(검색이 1차 필터). `/mobile/categories` 추가 시 슬롯인. 계획 goal(브라우징/검색)은 미저해.
- **QR 직행 상품 hero (캐시 미스 시)** — 카탈로그를 한 번도 로드하지 않고 QR 만 스캔하면 hero name/price 가
  'Producto #{id}'/'—' 로 표시. 매트릭스/재고 조회(D-14 목적)는 정상. 판매(가격 필요)는 카탈로그 경유가 주 경로.
  향후 `/mobile/product/:id` 경량 상세 엔드포인트로 해소 가능.
- **wave4_placeholder.dart** — Wave 3 라우트 스텁 위젯. 본 플랜에서 모든 라우트가 실제 화면으로 교체되어
  더 이상 import 되지 않는 orphan(무해). 제거는 후속 정리로 연기.

## Deferred / Out-of-scope (기록만)

- **U1-U6 + U5b + QR-scan + P95 + offline UAT (Task 3, blocking checkpoint)** — dev 환경 human UAT.
  백엔드 dev 기동 + 실기기/에뮬레이터 필요. 아래 "UAT Checklist" 참조. **본 SUMMARY 는 이를 passed 로
  표시하지 않음** — 오케스트레이터가 사용자에게 제시하는 게이트.
- **위젯 레벨 통합 테스트(detail/comanda pump)** — 단위 테스트(순수 컨트롤러)로 핵심 로직 커버. 네트워크
  override 위젯 테스트는 UAT 로 대체.
- 사전 존재하던 서브모듈 working-tree 수정(api-ventago/ventago-app, .gsd-snapshot) 은 손대지 않음.

## UAT Checklist (Task 3 — pending human verification, blocking)

> dev 환경(`npm run dev:api` + Flutter app → localhost:5002, coolsistema vendedor 계정 2개, PIN 선설정).
> **아직 검증 안 됨 — 사용자 승인 전까지 plan 미완료.**

- **U1** (pending) — vendedor1 로그인(Usuario+PIN) → Catálogo/Detalle 에 **자기 지점 재고만** 노출.
- **U2** (pending) — `?branchId={vendedor2 지점}` 요청 → **403 SCOPE_VIOLATION**.
- **U3** (pending) — vendedor1 데스크탑 POS + 모바일 동시 로그인 → **두 세션 모두 유지**.
- **U4** (pending) — vendedor1 2번째 모바일 로그인 → 1번째 앱 **401 MOBILE_SESSION_EXPIRED + 토스트 + /login**.
- **U5** (pending) — vendedor1 "Mandar a Caja" → 데스크탑 보류 목록에 등장(도착 토스트+배지), **Caja 잔액 +
  당일 매상 불변**, 예약 변형에 `stocks type:'suspend'` −qty 행 존재.
- **U5b** (pending) — 보류 취소(데스크탑/모바일) → 예약 해제(+qty), 재고 복원.
- **U6** (pending) — 매장 SUSPENDED 전환 → 다음 모바일 요청 **401 STORE_SUSPENDED**.
- **QR-scan** (pending) — Phase 38 라벨 스캔 → 올바른 상품 매트릭스 오픈(D-14).
- **P95** (pending) — `scripts/monitor-mobile-pool.sh --latency` → /mobile/* **P95 ≤ 300ms** (D-01b sign-off).
- **Offline** (pending) — 기기 연결 차단 → 카탈로그/재고는 캐시로 브라우징, "Mandar a Caja" **비활성 +
  "Requiere conexión"** (criterion 11).
- **D-13 불변식** (pending) — 어떤 모바일 액션도 확정 Sale(activity_type='sale') 미생성. PG pool 신규 경고 없음.

## Self-Check: PASSED

- 핵심 파일 5/5 존재 확인 (variant_stock_matrix, qr_scanner_sheet, comanda_screen, done_screen, variant_matrix_test).
- 커밋 3/3 존재 확인 (1f2eecf, dd94918, 930449e).
- `flutter analyze` 0 issues + `flutter test` 10/10 passed (재현 가능).

## Commits (parent repo, base 98ae966)

- `1f2eecf` feat(37-04): Home QR-first + Catálogo (search/stock pills) + QR scanner deeplink→detail
- `dd94918` test(37-04): failing variant matrix test — keying, own-branch cap, addEnabled (RED)
- `930449e` feat(37-04): variant matrix detail (D-15) + Comanda (Mandar a Caja) + Done (GREEN)
