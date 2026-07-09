---
phase: 37
slug: mobile-sales-shell
status: approved
platform: flutter
preset: ventago-dark-navy-gold
created: 2026-07-08
source_mockup: 37-vendedor-app-mockup-FINAL.html
---

# Phase 37 — UI Design Contract (Vendedor Mobile App)

> Flutter 모바일 앱 **vendedor 모드** 화면/인터랙션 계약. 원본: `37-vendedor-app-mockup-FINAL.html` (사용자 제공 FINAL 목업, phase dir 에 영구 보존).
> revendedor 모드(Wave 5)는 Phase 24 완료 후 별도 UI-SPEC 로 확장 — 본 문서는 **vendedor MVP(Wave 3-4)** 범위.

---

## 0. Scope Decisions (2026-07-08, 사용자 확정 — 목업이 lock SPEC 을 넘어선 부분 정리)

목업은 CONTEXT/SPEC(D-01..D-15)을 넘어서는 신규 기능을 포함했고, 아래처럼 확정했다. **이 결정이 SPEC 본문/목업보다 우선.**

| # | 목업 기능 | 결정 | UI 반영 |
|---|-----------|------|---------|
| UI-D1 | Probador virtual (AI 가상 피팅) | **별도 phase 로 연기** | "✨ Probar con foto" 버튼은 **렌더하되 `enabled:false` + "Próximamente" 툴팁/토스트**. 오버레이/카메라 코드 미구현. AI 는 `/gsd-ai-integration-phase` 로 별도. |
| UI-D2 | Cross-branch traslado (타지점 재고 초과주문/이동판매) | **자지점만 판매** (D-14 준수) | 매트릭스 셀 입력 **max = 자지점 available** 로 캡. `over`(빨강)/`selwarn` traslado 배너 **제거**. 타지점 재고는 `otras:N` **read-only 비교 표시만** 유지. 카트 라인의 `↗ traslado` 칩 제거. |
| UI-D3 | 로그인 인증 | **PIN 인증** | 로그인 화면 `Usuario` + `PIN de vendedor`(숫자 keypad) 유지. 백엔드 PIN 검증 신규(Wave 1 연계). |
| UI-D4 | 데스크탑 수신부(실시간 Caja 보드) | **기존 suspended-sales UI 재사용 + socket 알림만** | 목업의 데스크탑 `.desk` 패널은 **참고용**. Phase 37 은 신규 보드 미구축 — 기존 nueva-venta 보류 복원 UI 에 **socket 도착 배지/토스트**만 추가(ventago-app). |

---

## 1. Platform & Design System

| Property | Value |
|----------|-------|
| Platform | Flutter (null safety, Riverpod, dart 스타일가이드) |
| 앱 위치 | monorepo workspace — Phase 17 `talleres-vendor-app` Flutter 인프라 재사용(Dio + Riverpod + secure storage + JWT). **주의(리서치 발견):** FCM 부재/인증 phone+PIN→PIN 재작성/401 redirect 신규. |
| 화면 방향 | Portrait 고정 (폰 우선, 390×800 기준 설계) |
| Icon | 이모지(목업과 동일) — 별도 아이콘 라이브러리 불필요. 필요 시 `material_icons`. |
| Font | 시스템 폰트(`system-ui` 스택) = Roboto(Android)/SF(iOS). 별도 임베드 없음. |
| 테마 정합 | Ventago dark navy + gold. `sketch-findings-ace-online` 스킬과 동일 토큰. storefront-mockup / despacho-app 와 100% 일치. |

---

## 2. Design Tokens (목업 `:root` 그대로 — Flutter `ThemeData`/상수로 이식)

| Token | Hex | 용도 |
|-------|-----|------|
| navy | `#1a1a2e` | 앱바, 로그인 배경, primary 버튼/hero, 하단 comanda 바 |
| navy-2 | `#0f0f1e` | gold 버튼 위 텍스트, 토스트 배경 |
| gold | `#f5a623` | accent — CTA(Caja 전송), chip, 활성 강조, QR/스캔 |
| gold-d | `#b9760f` | gold 그라디언트 끝, traslado/reserva 텍스트(자지점 판매에선 reserva 만) |
| ink | `#1c1c28` | 기본 텍스트 |
| muted | `#6b6b76` | 보조 텍스트, 코드, placeholder |
| soft | `#f6f6f8` | 카드/썸네일 배경, totbox |
| line | `#e7e7ec` | 보더, 구분선 |
| green / green-s | `#1d9e75` / `#e7f6f0` | 재고 OK pill, 자지점 재고 강조, 완료 링 |
| red | `#e24b4a` | (traslado 경고 제거 후) 파괴적 액션/에러 전용 |
| amber-s | `#fdf1dd` | low stock pill, 선택 셀 배경(sel), reserva 박스 |
| bg | `#ffffff` | 화면 배경 |

**Accent(gold) 예약 대상 (절대 "모든 인터랙션 요소" 금지):** Caja 전송 CTA, chip("En stock"/scope), QR 스캔 hero/hint, 활성 필터·지점 탭, 선택 셀 보더, 완료 티켓 강조.

**Spacing (4의 배수):** 화면 패딩 16, 카드 내부 10~14, 섹션 헤더 14/16, 셀 간격 6, 버튼 패딩 13~17.

**Radius:** 폰 프레임 38, 카드 14~18, 버튼 12~14, pill 20, 셀 11, 입력 8~12.

**Typography:**

| Role | Size | Weight | 용도 |
|------|------|--------|------|
| Display | 23 | 700 | 로그인 로고 타이틀 |
| Heading | 17–19 | 650–800 | 앱바 h2(17/650), hero 상품명(18/700), 가격(19/800) |
| Body | 13–14 | 400–600 | 카드 상품명, 리스트 |
| Label | 11 | 400–600 | 필드 라벨(uppercase), sub, 코드 |
| Numeric | 15 | 800 | 셀 수량 입력(`tabular-nums` 필수), 금액 |

숫자(가격/재고/수량)는 **`FontFeature.tabularFigures()`** 적용. 통화 포맷 `$` + `es-AR` 천단위(`18.900`).

---

## 3. Screens (Flutter route/widget 계약)

목업 화면 = Flutter 화면 1:1 매핑. 공통: 상단 navy `AppBar`(뒤로 `‹` + 타이틀 + sub + 우측 chip), 스크롤 body, 필요 시 하단 고정 바.

### S0. Login (`/login`)
- navy 전면 배경, 중앙 정렬. gold 그라디언트 로고 마크(🏷️) + "Ventago **Ventas**"(gold span) + tag "Punto de venta móvil" + 서버 URL 표시(읽기전용, 코드 고정).
- 필드: `Usuario`(텍스트), `PIN de vendedor`(숫자, obscure). **[UI-D3]** PIN keypad.
- `Ingresar` gold 버튼.
- `Sucursal` 셀렉터(dropdown): **vendedor 의 `user_branches` 에 있는 지점만** 노출(서버 강제). 마지막 선택 지점 secure storage 기억. 1지점뿐이면 자동선택+비활성(D-10).
- hint: "🔒 Sesión móvil independiente de la caja de escritorio" (D: mobile_sessions 분리).
- **에러 표시(feedback_error_visibility 준수):** 인증 실패/스코프 미정의(`VENDEDOR_SCOPE_NOT_DEFINED`)/세션만료(`MOBILE_SESSION_EXPIRED`)/매장정지(`STORE_SUSPENDED`) → 인라인 Alert + prominent 토스트, i18n(es) 카피.

### S1. Home (`/home`)
- navy `hello` 헤더: "Hola, {nombre}" + "📍 {store} · Sucursal {branch}" + 이니셜 아바타.
- 세로 3버튼(`homebtns`, 화면 꽉 채움):
  1. **Buscar producto** (🔎, "Elegir de la lista") → `/catalog`
  2. **Ver carrito** (🛒, "Editar y mandar a caja") + 카트 수량 badge(0 이면 숨김) → `/comanda`
  3. **Escanear QR** (▣, primary big/navy, "Leé la percha y probá al instante") → QR 스캐너
- spacer 로 QR 버튼을 하단에 밀어 엄지 도달 영역 배치.

### S2. Catálogo (`/catalog`)
- AppBar "Buscar producto" / sub "Elegí de la lista o escaneá el QR".
- 검색바(soft, 🔍 + placeholder "Buscar por nombre o código…") — 이름/코드 필터.
- 카테고리 필터 pill 가로스크롤(활성=navy). 카테고리 = 매장 실제 카테고리(SWR/캐시 소스).
- 상품 리스트(`pcard`): 썸네일(next/Image 대응, 없으면 이모지/placeholder) + 상품명 + 코드 + 가격 + **stock pill**(ok≥11 green / low 1–10 amber / out=0 gray "Sin stock"). stock=자지점 수치(D-14 SELL scope).
- out(0) 카드 탭 → "Sin stock en esta sucursal" 토스트(상세 진입 막지 않음: 타지점 조회 위해 진입 허용해도 됨 — **자지점 0 이어도 상세 진입 허용**, 상세에서 otras 표시).
- 하단 카트 바(`comandabar`, 카트 있을 때만): 수량 + 합계 + "Ver ›" → `/comanda`.

### S3. Detalle — **color × talle 매트릭스 (시그니처, D-15)** (`/product/:id`)
- hero: 큰 썸네일 + 상품명 + 코드 + 가격.
- 섹션 헤더 "Stock por color y talle" + 우측 합계 요약 `{미코드} {mine} · otras {oth} · Disp. {tot}`.
- **매트릭스 테이블**(가로스크롤): 행=색상(swatch+이름), 열=talle(S/M/L/XL…). 셀:
  - 상단 수량 입력 `qin`(숫자, placeholder "0", `tabular-nums`, **max = 자지점 available [UI-D2]**).
  - 하단 인라인 `<mine=미코드:N (green/800)> · otras:N (muted)` — **타지점은 read-only 표시만**.
  - 배지: `🔒N`(caja 예약/reserva, 좌상단 gold-d), `🛒N`(내 카트, 우상단 navy).
  - 상태: `sel`(선택=gold 보더+amber 배경), `out`(자+타 물리재고 0 → `—` dash + 비활성), `depleted`(더 담을 수 없음=자지점 소진 → 입력 비활성). **`over`(빨강) 상태 제거 [UI-D2]** — max 캡으로 초과 자체가 불가.
- **범례:** "green = tu sucursal · otras = resto · 🛒 en carrito · 🔒 reservado". (traslado 문구 제거)
- selbar: 선택 수량 요약 "Seleccionado: {n} u · {money}". `selwarn`(빨강 traslado 경고) **제거 [UI-D2]**.
- 하단 액션: `✨ Probar con foto`(**disabled + "Próximamente" [UI-D1]**) + `Añadir al carrito ({n})`(navy solid, n=0 이면 disabled).
- 매트릭스 데이터/입력 로직은 웹 `VariantsStockVenta.tsx` 의 `variantQuantities`(`colorId-sizeId`) 모델을 Flutter 로 이식(리서치 참조).

### S4. Comanda / Carrito (`/comanda`)
- AppBar "Carrito" / sub "Editá y mandá a caja".
- 빈 상태: 🛒 + "El carrito está vacío. Escaneá el QR o buscá un producto."
- 라인(`line`): 썸네일 + 상품명 + `swatch + {color} · Talle {talle}` + **stepper(−/N/+)** + 소계. **[UI-D2]** `xbranch`/`↗ traslado` 칩 제거 — 모든 라인은 자지점.
- stepper `+` 는 자지점 available 한도에서만 증가(초과 시 "Sin disponible" 토스트).
- totbox: 항목수/합계, Descuento($0 자리), **Total**(grand, 800).
- cliente 입력(선택): "Nombre del cliente (opcional)" — store_clients scope 강제(D-13/Phase 25). 없으면 "Sin nombre".
- 하단 고정 CTA: **"🧾 Mandar a Caja"**(gold 그라디언트, 최대 강조) → `POST /mobile/sales`(= suspended-sales 위임, 보류 생성 D-13).

### S5. Done — En espera (`/done`)
- 초록 링 ✓ + "En la lista de espera" + "Quedó en la caja esperando que el administrador la restaure y cobre." (D-13: 확정 아님, Caja 무영향 명시).
- 티켓: "En espera N°" + 번호(서버 반환 보류번호).
- reserva 박스: "🔒 Reservado · stock disponible bajó" + 셀별 `−{qty} → {disp} disp.` (재고 예약 반영).
- 액션: `Ver stock`(→ 상세, 줄어든 재고 확인) + `Otra venta`(→ 홈, 초기화).

### Overlays
- **QR 스캐너**(bottom sheet): 뷰파인더(스캔 라인 애니메이션 + 코너 가이드) + "Simular/Escanear". QR 페이로드 = Phase 38 딥링크 `/m/stock?s={storeId}&p={parentProductId}` → 해당 상품 상세 직행. `mobile_scanner` 등 패키지(리서치 MEDIUM confidence).
- **Probador virtual**: **[UI-D1] 미구현.** 버튼만 disabled 로 존재.

### Desktop (ventago-app) — **[UI-D4]**
- 신규 보드 미구축. 기존 nueva-venta 보류 복원 UI 유지 + 모바일 보류 도착 시 **socket 알림 토스트 + 대기건수 배지**만 추가. 목업 `.desk` 패널은 향후 참고 자료.

---

## 4. Interaction & State Rules

- **Riverpod ScopeProvider**: `/mobile/me` 응답의 role 로 BranchScope(vendedor) 자동 결정. 화면 공통, scope 차이는 selector 잠금 + 표시 규칙(criterion #10).
- **재고 표기 = 실물 − 예약(caja hold) − 내 카트(로컬)**. 셀 입력은 전체 재렌더 없이 해당 셀만 갱신(포커스 유지) — 목업 `setSel` 패턴.
- **카트 적재**: 선택 확정 시 자지점 재고 한도로만 적재 [UI-D2]. 배분 로직(타지점 폴백) 제거.
- **오프라인(criterion #11)**: 카탈로그 lastFetch 캐시로 stock 조회 가능. 판매 확정은 온라인 필수 → 오프라인 시 "Mandar a Caja" 비활성 + 안내.
- **Pool 보호(criterion #7)**: 카탈로그 60s / stock 10s 캐시. 폴링 주기 최소화(FCM 부재로 socket/폴링 사용 시 pool 낭비 금지 — CLAUDE.md).
- **세션(criterion #12)**: `mobile_sessions.active_session_token` UNIQUE. 재로그인 시 기존 모바일 세션 401 `MOBILE_SESSION_EXPIRED` → 로그인 화면 리다이렉트(리서치: dio onError 신규 구현 MOBILE-C-07).

---

## 5. Copywriting Contract (es-AR)

| Element | Copy |
|---------|------|
| Login CTA | `Ingresar` |
| Login hint | `🔒 Sesión móvil independiente de la caja de escritorio` |
| Home 버튼 | `Buscar producto` / `Ver carrito` / `Escanear QR` |
| 검색 placeholder | `Buscar por nombre o código…` |
| stock pill | `{n} u` / `{n} u · bajo` / `Sin stock` |
| out 탭 토스트 | `Sin stock en esta sucursal` |
| 상세 CTA | `Añadir al carrito ({n})` / (disabled) `✨ Probar con foto` + `Próximamente` |
| selbar | `Seleccionado: {n} u · {money}` / `Escribí cuántas unidades querés llevar` |
| 카트 빈 상태 | `El carrito está vacío. Escaneá el QR o buscá un producto.` |
| Caja CTA | `🧾 Mandar a Caja` |
| Done heading | `En la lista de espera` |
| Done body | `Quedó en la caja esperando que el administrador la restaure y cobre.` |
| cliente label | `Nombre del cliente (opcional)` |
| 에러(scope) | `Tu sucursal no está configurada. Contactá al administrador.` (VENDEDOR_SCOPE_NOT_DEFINED) |
| 에러(sesión) | `Tu sesión se cerró porque ingresaste en otro dispositivo.` (MOBILE_SESSION_EXPIRED) |

---

## 6. Checker Sign-Off

- [x] 화면 7개 + 오버레이/데스크탑 매핑 완료
- [x] 디자인 토큰 = Ventago 테마(sketch-findings 정합)
- [x] Scope 결정 4건(UI-D1..D4) SPEC 대비 명시
- [x] D-13(보류)/D-14(자지점 SELL)/D-15(매트릭스) 반영
- [x] 카피 계약(es-AR) + 에러 가시성 규약
- [ ] gsd-planner 소비 → Wave 3-4 PLAN 반영 확인

**Approval:** approved 2026-07-08 (사용자 목업 + 4개 결정 기반, 오케스트레이터 작성)

---

*Phase: 37-mobile-sales-shell · Source: 37-vendedor-app-mockup-FINAL.html*
