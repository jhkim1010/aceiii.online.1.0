# Phase 117 Reportaje abierto — 내부 근거 조사 (interno)

- 작성 2026-10-17 · **읽기 전용** 조사(운영 DB 는 `BEGIN READ ONLY` 안에서 SELECT 만, 서버 파일은 읽기만)
- 출처: `.planning/pedidos/` + `.claude/pedidos-bot/queue/*/pedido.json`(42건) · 운영 `chat_messages` ·
  운영 앱 로그 `/var/lib/ventago-logs/api/combined-2026-10-04 ~ 10-17.log`(14일) · 운영 DB 집계 ·
  `ventago-app/src/pages/reportes/` + `api-ventago/src/app/reports/` · Phase 105 외부 점검 · 레거시 분석 문서
- 개인정보(고객명·CUIT·연락처)는 옮기지 않았다. 사용자는 id 와 역할만, 매장은 이름으로 적는다.
- 「활동 매장」 = 최근 30일 `sales.status='Pagado'` 가 있는 8개 매장:
  Cache · Shaple · NOIX · Charo · ohmydenim · coolsistema · Cielo · ACE

---

## 요약 (핵심 10줄)

1. **매장이 보고서를 직접 요구한 접수(pedido)는 42건 중 0건이다.** 가까운 것은 「손님 판매·외상 내역」(27·37)과 「gastos 를 어디서 보나」(34)뿐 — 수요는 「새 보고서」가 아니라 **이미 있는 것을 찾는 문제**로 나타난다.
2. 보고서 수요의 직접 근거는 Trello 카드 제목이다: «Reportes de ventas: por período, sucursal, vendedor y producto» · «Exportar reportes a Excel» · «Reportes de caja y finanzas» · «Reportaje de ingresos (ranking de stock nuevo)».
3. **AI 도우미에 데이터 질문은 사실상 없다**: 사용자 질문 16건 중 데이터 질문 1건(«cuantas ventas se han hecho?», 3월, 서비스 미가동으로 실패). 나머지는 사용법·지원 토큰. → 「AI 에 물었다 거절당한 보고서 수요」라는 근거는 **존재하지 않는다**.
4. **실제 보고서 트래픽의 77%는 Stock 화면**이다(14일, 매장 직원 12명, `/reports/*` 4,482회 중 stocks-cockpit 3,471). 판매 분석(sales-cockpit 139·items 55·vendedor 32)은 한 자릿수~두 자릿수 명이다.
5. 보고서를 여는 사람은 사실상 **매장 admin/gerente 6~7명**(Shaple 2 · coolsistema 2 · Cache · Cielo · Charo). 내보내기(export)는 14일간 Shaple 1명이 **매일 한 번 sales-report-export(당일)** 를 받은 것이 거의 전부다.
6. **마진은 대부분 매장에서 계산 불가**: 30일 판매 품목의 원가 입력률 Shaple 0% · Cache 0.4% · NOIX 0% · Charo 0% · ohmydenim 0% · Cielo 41.5% · coolsistema 7.1%. → 「Margen」은 기본 템플릿에 넣으면 **거짓 숫자**를 보여 준다.
7. **카테고리·temporada 차원은 대형 매장에서 빈 껍데기**다: Shaple·Cache·Charo·ohmydenim 의 판매 품목 카테고리는 전부 `NONE`(레거시 임포트), temporada 도 대부분 `NONE`. 색은 Shaple 98.6% 「채워짐」이지만 **고유값 1개(Color Único 류)**. 실질적으로 쓸 수 있는 축은 **매장별로 다르다**(NOIX=카테고리, Shaple=talle 35종, Cielo=color 18종, Cache=temporada).
8. **분할결제는 드물다**(Shaple 7.5% · Charo 6.8% · coolsistema 6.5% · 나머지 ≤1.7%) → 「medio de pago」 차원은 금액 배분으로 처리 가능하나 Tickets 지표와 섞으면 안 된다(D-10 유지). 결제수단 이름은 매장마다 자유 입력(«Pagos Dani», «Inmediato» 등).
9. **다지점은 Charo(5개 중 2개 판매)·ohmydenim·coolsistema·ACE 정도**, 나머지 4개 매장은 지점 1개 → 「Sucursal」은 대부분 매장에서 무의미, 그러나 다지점 매장에는 필수(Phase 105 원칙: 지점별 요약을 보이게).
10. **Gastos·Facturación 은 판매와 다른 원장**이다. Gastos 는 6개 매장이 기록(NOIX 30일 105건·Shaple 90건), 카테고리가 매장마다 제각각. Facturación 은 Ventago AFIP 발급이 **30일 12건(Cielo·coolsistema)** 뿐이고 실제 발급은 레거시 `legacy_facturas`(Charo B·NOIX A)에 있다 → 117 에서는 **별도 보고서 종류(후속)** 로 두고 판매 빌더에 섞지 않는 것이 맞다.

---

## 1) Pedidos 에서 나온 보고서 요구

접수 42건(`.claude/pedidos-bot/queue/5~46`) 전수 확인. 범주: 거의 전부 POS·라벨·WooCommerce·인쇄. **「보고서/통계/수치/내보내기/비교」를 직접 요구한 건은 없다.**
관련성이 있는 것만 표로 적는다.

| PEDIDO | 요지(원문 짧게) | 매장 | Reportaje abierto 로 해결? |
|---|---|---|---|
| 27 | «...BOTON VER HISTORIAL DE VENTA Y DEUDA» — POS 에서 손님 판매·외상 내역 | Shaple | **아니오** — 손님 단위 원장 조회(고객 차원은 117 에서 보류). 별도 화면이 맞다 |
| 37 | «Poder ver ticket detallado cuando veo la deuda» (vcontrol 예시 첨부) | Shaple | **아니오** — 드릴다운(티켓 상세) 요구. 다만 「요약→티켓 목록」 드릴다운 원칙의 근거 |
| 34 | «no puedo ver gastos de caja ... en tesorería → gastos no aparecen» | Shaple | **부분** — 찾기 문제 + 카하 지출 조회. Gastos 보고서 종류가 생기면 해결 |
| 38 | «no agrega gasto a pesar de que ... se haya iniciado caja» | coolsistema | 아니오 — 입력 결함 |
| 14 | «agrandar la columna de fallados, no se ve ... el nombre» | coolsistema | 아니오 — Stock 표 UI. 단 Stock 화면이 매일 쓰인다는 방증 |
| 30·46 | WooCommerce 동기화 후 재고가 바뀐다 / 새 상품이 웹에 나오나 | Cielo | 아니오 — 재고 정합 |
| 42 | «no salen la cant de prendas total en el ticket» | NOIX | 아니오 — 티켓 인쇄. 「Unidades(prendas)」가 매장 언어라는 근거 |
| 40 | «Ordenar talles por numero en producto» | Shaple | 간접 — **talle 정렬은 숫자 순**이어야 한다(talle 차원 출력 규칙) |
| 6 | 레거시 임포트 «hay tablas que no hace importacion» (cobranza 등) | Shaple | 아니오 — 그러나 레거시 데이터가 보고서 원천이라는 점이 중요(§6) |

외부(접수 봇 이전) 근거 — `.planning/trello-inbox/latest.json` 카드 제목(소유자/운영자 측):
- «Reportes de ventas: por período, sucursal, vendedor y producto» ← **117 의 핵심 4축과 정확히 일치**
- «Exportar reportes a Excel» · «Reportes de caja y finanzas» · «Reportaje de ingresos (k muestre ranking de registro de stock nuevo)» · «Reportes de producción» · «Que pueda generar Reportajes (SControl)»

해석: 매장 직원은 보고서를 「요청」하지 않고 **있는 화면(Stock)을 매일 쓴다.** 새 빌더의 수요는 소유자(다지점·본사 관점)에게서 나온다.

---

## 2) AI 에 물었다가 거절된 데이터 질문

- 운영 `chat_messages`: 2026-03-26 ~ 10-14, **user 16건 / assistant 16건**. 로그상 14일간 `/api/chat/message*` POST 9회(stream 은 이력이 안 남는 경우가 있음 — user 77 의 stream 2건은 테이블에 없다).

| 분류 | 건수 | 예시(익명) | 응답 |
|---|---|---|---|
| **데이터 질문** | **1** | «cuantas ventas se han hecho?» (2026-03, store 0) | 「IA no disponible (Ollama)」 — 거절이 아니라 장애 |
| 사용법(how-to) | 9 | «¿Cómo cierro la caja?» · «donde puedo redondear la moneda» · «판매를 하려면?» · «como crear un backup» | 일부 답변, 다수 「매뉴얼에서 찾을 수 없음」 |
| 지원 토큰 붙여넣기 | 3 | «Token de soporte técnico: …» | 「매뉴얼에서 찾을 수 없음」 |
| 기타 | 3 | «hola», 매뉴얼 존재 여부 | — |

결론: **AI 경로에서 보고서 수요를 추정할 근거는 없다**(표본 1건). Phase 117 의 「AI 자연어 → 보고서」 보류(Deferred) 결정과 일치한다. 템플릿 설계는 §3·§5·§6 근거로 해야 한다.

---

## 3) 보고서 사용 실태 (14일: 2026-10-04 ~ 10-17)

방법: `combined-*.log` 의 `[HTTP] GET` 중 `/api/reports|expenses|expense-categories|afip|dashboard(s)` 를 집계,
user:1(superadmin)·user:61(agent 봇)·익명 제외. 숫자는 **API 호출 수**(한 화면이 여러 번 부름 — 페이지네이션·필터 변경 포함)이므로 「열람 횟수」가 아니라 **상대적 사용량**으로 읽는다.
※ docker logs 는 오늘 17:04 재기동 이후만 남아 있어 파일 로그(`/var/lib/ventago-logs/api`, 14일 보존)를 썼다.

### 엔드포인트별 상위

| 호출 | 사용자 수 | 엔드포인트 | 화면 |
|---|---|---|---|
| 1,431 / 1,346 / 389 / 134 | 12 / 12 / 2 / 5 | `stocks-cockpit/items` · `/branches` · `/historial` · `/matrix` | Stock (madre×color×talle 매트릭스 포함) |
| 449 | 19 | `dashboard/admin/control-center` | 대시보드(홈) |
| 434 / 266 / 44 | 8 / 8 / 8 | `expenses/search` · `expenses/daily-summary` · `expense-categories/tree` | Gastos **입력 화면**(보고서 아님) |
| 139 / 43 / 21 / 3 | 6 / 5 / 1 / 1 | `sales-cockpit` · `/ventas` · `/mix` · `/vendors` | Ventas |
| 108 | 1 | `sale-items-summary` | (coolsistema 1명) |
| 72 / 38 | 4 / 3 | `movidos-cockpit` | Movidos |
| 55+59+20+18 | 5 | `items-cockpit*` | Items (상품별 판매) |
| 55 | 5 | `breve-venta-cockpit` | Breve Venta (일 요약) |
| 41+38 | 6 | `ingreso-cockpit*` | Ingreso (입고) |
| 42 | 4 | `alertas-cockpit` | Alertas |
| 32 (+5) | 5 | `vendedor-cockpit*` | Vendedor |
| 31 | 3 | `ganancia` | Ganancia/Resultado |
| 19 | 5 | `season-turnover` | Temporada |
| 19+15+5 | 2 | `gasto-cockpit` · `gastos/by-category` | Gasto 보고서 |
| 18+4 | 5 | `clientes-credito-*` | Clientes crédito |
| 10+4 | 2 | `facturacion-cockpit*` | Facturación 보고서 |
| 10+2 | 1 | `cheque-estado-cockpit` | Cheques |
| 24+1 | 1 | `fallados-cockpit` | Fallados |
| 11 | 1 | `sales-report-export` | Excel 내보내기 |
| 2 | 2 | `stocks-cockpit/items-pdf` | PDF |

### 미사용(14일 0회) 라우트
`alertas-report(-export)` · `breve-venta-report-export` · `category-color-pivot` · `cheque-estado-report(-export)` ·
`clientes-credito-report-export` · `corregido-report-export` · `facturacion-report(-export)` · `fallados-report-export` ·
`gasto-report(-export)` · `ingreso-report(-export)` · `movidos-report-export` · `product-sales-summary` · `products-cockpit` ·
`products-report-export` · `provincia-dashboard` · `reservado-*`(전부) · `stock-vistas-export/pdf` · `vendedor-report-export`
→ **export 계열은 sales-report-export 하나 빼고 전부 0회.** 「Excel 로 내보내기」는 카드로는 요구되지만 실제로는 1명이 「당일 판매」만 받는다.

### 사용자별 (역할 · 매장)

| user | 매장 · 역할 | `/reports/*` 호출 | 주로 |
|---|---|---|---|
| 59 | Shaple · admin | 2,085 | stocks 1,944 · sales 49 · movidos 28 · items 19 · **export 11(매일 당일)** |
| 7 | coolsistema · admin | 1,381 | 거의 모든 화면(플랫폼 측 점검 계정일 가능성 — 매장 수요로 과대평가 금지) |
| 60 | Shaple · gerente | 305 | stocks 만 |
| 77 | Cache · admin | 243 | items 94 · stocks 69 · sales 29 · breve 16 · vendedor 10 |
| 16 | coolsistema · gerente | 180 | stocks 136 · **gasto 18** |
| 46 | Cielo · admin | 171 | stocks 143 · facturación 4 |
| 49 | Charo · admin | 17 | items 8 · vendedor 2 |
| 23·43·78·80·83 | ACE·NOIX·Kandente·Naiv·ENEDE | 2~6 | stocks |

- 영속 사용 기록 테이블은 없다: `audit_logs` 에 report/export 행 0건(60일), 사용 분석 테이블 없음(PostHog 외부).
- **시사점**: 판매 분석 화면은 **소유자 1~3명이 주 1~2회** 수준. 빌더의 1차 사용자는 Cache·Shaple·Charo 같은 **판매량 큰 매장의 admin**이다.

---

## 4) 기존 보고서가 이미 다루는 것 vs 비어 있는 것

실제 렌더는 `/reportes-v2`(`ventago-app/src/views/reports-v2/registry.ts` → `*CockpitBody.tsx`, 섹션 Ventas/Cobros/Stock/Resultado). `/reportes/*` 는 레거시(index 는 v2 로 리다이렉트). 백엔드 `api-ventago/src/app/reports/reports*Cockpit.service.ts`.

### 4-1. 이미 있는 것

| 화면 | 지표 | 차원 | 전기 대비 | Top N | 내보내기 |
|---|---|---|---|---|---|
| Ventas (`sales-cockpit`) | venta neta(−반품+외상 조정), tickets, ticket promedio, 할인%, unidades, web; 권한 시 ganancia/costo/gastos | 일 추세, 지점 표, 카테고리 Top5, **mix**(상품/카테고리/color/talle/temporada/provincia), 판매원, 거래 목록(판매/일/월/년) | 예 | mix 10(최대 50) | xlsx |
| Items | unidades, 금액, 판매 건수 | 지점, 상품/마드레×지점, 일자, **color×talle(한 상품)** | 예 | 없음 | 없음 |
| Vendedor | venta neta, tickets, ticket promedio, 반품, 할인% | 판매원 순위, 판매원×일, mix(상품/카테고리/color/talle) | 백엔드만(화면 표시 없음) | mix 10~50 | 없음 |
| Breve Venta | tickets, venta neta, ticket promedio, 최고일, 미수 | 일 | 예 | — | xlsx |
| Ganancia (Resultado) | ventas, 판매시점 원가, 원가 없는 줄, 반품, gastos, ganancia | **일만** | 아니오 | — | 없음 |
| Season turnover | 판매 수량·금액, 현재 재고, 회전 | temporada | 아니오 | — | 없음 |
| Fallados · Corregido · Reservado · Precios fuera de lista · Enviado | 예외 목록 | 상품/판매원/고객 등 | 일부 | 5~8 고정 | 일부 xlsx |
| Stocks · Stock vistas · Movidos · Ingreso · Alertas | 재고 | 지점·카테고리·color·매트릭스 | 일부 | 고정 | xlsx/PDF |
| Control center(홈) | 오늘 현금·지점별 오늘 판매 vs 4주 평균(±30%) 등 | 지점 | 4주 평균만 | — | — |
| 고아 화면 | `category-color-pivot`(카테고리×color), `provincia-dashboard` — registry 에서 빠져 아무 화면도 안 부름 | | | | |

### 4-2. 비어 있는 것 (Reportaje abierto 의 실질 가치)

1. **Medio de pago 차원이 웹 어디에도 없다.** registry 에 `paymentMethod` 필터 타입은 있지만 쓰는 보고서가 0. (모바일 POS 보고서 `api-ventago/src/app/mobile/pos/reports/pos-reports.service.ts` 에만 있음)
2. **Margen 을 차원별로 보는 곳이 없다** — 전체(Ventas 합계) 또는 일(Ganancia)뿐. 지점·카테고리·상품·판매원·temporada·color·talle 별 마진, 마진% 없음. (단 §6-2 원가 입력률 때문에 실익은 제한적)
3. **Devoluciones** 는 지점·일·판매원 별만. 상품/카테고리/color/talle/temporada 별 반품, 반품률% 없음.
4. **Tickets·ticket promedio** 는 지점·판매원·일 별만. 카테고리/temporada/color/talle/결제수단 별 없음.
5. **교차 차원**: 카테고리×color(고아), 한 상품의 color×talle 뿐. 지점×카테고리, 판매원×카테고리, temporada×지점 없음.
6. **시간**: 주 단위·요일·시간대 없음, **전년 동기 비교 없음**(전기 대비만).
7. **전기 대비**가 Ganancia·Season·mix 표에는 없음(mix 는 점유율만).
8. **Top N** 은 백엔드 고정값(5/8/10/20). 사용자 Top N 조절·하위 N(안 팔리는 것) 없음.
9. **저장된 보고서 없음** — 즐겨찾기/최근은 slug 만 localStorage(`views/reports-v2/hooks/useFavorites.ts`). 필터 조합 저장·공유·예약 불가(`reports.schedule.ts` 존재, 미확인).
10. 내보내기 없음: Items · Vendedor · Ganancia · Season · Enviado · Precios fuera de lista.

→ 117 카탈로그(D-08·D-09)는 위 1·3·4·5·6·8·9 를 정확히 채운다. 이미 잘 되는 「지점×일 판매」「판매원 순위」는 빌더가 **같은 숫자를 내는지 대조군**으로 쓰면 된다(105 정합 원칙).

---

## 5) 레거시 ACE 에서 쓰던 보고서

근거: `.planning/phases/06-reportajes/06-CONTEXT.md`(「기존 POS 시스템 스크린샷」 기반 15개 보고서 목록) · `Claude outputs/VControlGrid2-기능목록.md` · `.planning/stock-views-proposal-2026-08-02.md` · `.planning/ANALISIS-2026-09-17-legacy-vcontrolgrid2-격차분석.md`.

| 레거시 보고서 | 내용 | Ventago 대응 | 117 과의 관계 |
|---|---|---|---|
| Ventas · Items (Venta) | 기간 판매, 상품별 판매 | ventas · items | **빌더의 핵심 대체 대상** |
| Vendedor | 판매원별 판매·출근·선급(adelantos)·Encargado 별 | vendedor | Vendedor 차원 |
| Breve Venta (BreveVentaDlg) | **당일/당월 요약** — 실고객 수·판매 의류 수·예약·이동·세무 합계 + 지출 합산, 감열 인쇄 | breve-venta | 「오늘/이번 달 요약」 템플릿의 원형 |
| StockRpt Gen / screendetails2 | stockreal = 입고+조정−판매−예약, % 판매, 최초/최종 입고·최종 판매일, 지점별/통합 × 변형/마드레 | stocks (가장 많이 쓰임) | 117 범위 밖(D-11) |
| Color/Talle 표 | 판매 화면의 color×talle 그리드, 인쇄용 표 | stocks matrix | **color×talle 교차 = 레거시 사용자의 익숙한 모양** |
| Gasto | Rubro(종류)별 지출, 판매 합계에 포함 옵션 | gastos | 별도 종류(§8) |
| Facturación · Cierre Z · Reportaje X | 기간별 판매/청구, Z 번호별 감사 보고 | facturación | 별도 종류(§8) |
| Clientes (Crédito) · Cheque Estado | 채무자 목록 Excel, 손님별 구매 이력, 부도·만기 수표 | clientes-credito · cheque-estado | 손님 차원 보류 |
| Fallados · Corregido · Movidos · Reservado · Ingreso · Alertas | 운영 예외 목록 | 동명 화면 | 범위 밖 |
| 본사 보고(SControl «Pedir Informacion a Central») | 다지점 통합 보고 | 없음 | **«Que pueda generar Reportajes (SControl)»** 카드 = 다지점 통합 수요 |

- 소유자가 「레거시의 X 와 같은 것을 원한다」고 명시한 문서는 찾지 못했다. 직접 근거는 PEDIDO 37(vcontrol 화면을 예시로 첨부)과 Trello SControl 카드뿐.
- Phase 105 외부 점검(소유자 측 감사인)이 문제 삼은 것: **KPI·점유율의 분모(Top N 이 아니라 전체)**, Totales↔Resultado 의 「venta neta」 기준 차이(카하 기준 vs 판매일 기준), **반품(−180,000)이 Totales 에서 빠짐**, 원가 95.8% 미입력인데 마진 98.96% 표시, 같은 화면의 두 가지 ticket promedio, 테스트·$0 판매 혼입. → 빌더는 이 6가지를 **처음부터 정의로 막아야** 한다(이미 D-01~04 에 반영).

---

## 6) 데이터 현실 점검 (활동 8개 매장, 집계만)

공통 조건: `sales.sale_day_local >= current_date-30 AND status='Pagado'`. 모두 `BEGIN READ ONLY … ROLLBACK`.

### 6-0. 원천 구성 — ★ 레거시 행이 판매의 대부분
30일 판매 행: legacy 4,657 · pos 1,028. **Cache·Shaple·NOIX·Charo·ohmydenim 은 30일 판매가 legacy 임포트로도 들어와 있다**(최근 7일: Cache legacy 384 / pos 399 — 같은 날 양쪽에 있음). Charo·ohmydenim 은 사실상 legacy 뿐.
→ 빌더의 「venta」 조각은 `source` 를 어떻게 다룰지(중복·이중 계상 여부) **먼저 정해야** 한다. 이번 조사에서는 중복 여부를 판정하지 않았다(별도 확인 필요).

### 6-1. 일 티켓 수 (판매 있는 날 기준)
```sql
select store, count(*) dias, avg(n), percentile_cont(.5), max(n)
from (select store_id, sale_day_local, count(*) n from sales where … group by 1,2) …
```
| 매장 | 판매일 | 평균 | 중앙값 | 최대 |
|---|---|---|---|---|
| Cache | 26 | 95 | 78.5 | 262 |
| Shaple | 27 | 48 | 48 | 101 |
| NOIX | 22 | 29 | 30 | 75 |
| ohmydenim | 18 | 27 | 23.5 | 74 |
| Charo | 22 | 23 | 21.5 | 53 |
| Cielo | 10 | 4 | 4 | 10 |
| coolsistema | 18 | 4 | 3 | 10 |
| ACE | 6 | 1 | 1 | 2 |

티켓당 품목 수(평균 수량/줄): Cielo 79/14.6(도매) · NOIX 24.7/6.5 · Shaple 14.0/11.3 · Cache 7.0/3.4 · 나머지 2~5.
→ 최대 매장도 **연 3만 티켓·연 30만 품목줄 안팎**. CODEX 한도(일 단위 ≤90일, 화면 1,000행, CSV 10,000행, 5초)는 데이터량으로는 여유가 크다. 병목은 차원 카디널리티(상품 Top N)다.

### 6-2. 원가 입력률 (마진 가능성)
```sql
count(*) filter (where si.unit_cost>0)/count(*)  -- sale_items 30d
+ products.cost(변형 또는 마드레) > 0
```
| 매장 | 품목줄 | unit_cost>0 | 상품 원가>0 |
|---|---|---|---|
| Shaple | 14,498 | 0.0% | 0.0% |
| Cache | 8,525 | 0.4% | 0.4% |
| NOIX | 4,108 | 0.0% | 0.0% |
| Charo | 1,183 | 0.0% | 0.0% |
| ohmydenim | 750 | 0.0% | 0.0% |
| Cielo | 627 | 41.5% | 41.5% |
| coolsistema | 212 | 7.1% | 7.1% |
| ACE | 8 | 0.0% | 0.0% |

→ **마진은 8개 중 0개 매장에서 신뢰 가능.** D-08 의 「원가 입력률 표시」는 필수이며, 입력률이 낮으면(예: <80%) 마진 열을 **값 대신 「원가 미입력 N%」로** 보여 주는 편이 105 의 E9 재발을 막는다.

### 6-3. 분할결제 비율
| 매장 | 티켓 | 2개+ 수단 | 수단 0개 |
|---|---|---|---|
| Cache | 2,479 | 0.8% | 0.0% |
| Shaple | 1,285 | 7.5% | 4.7% |
| NOIX | 634 | 1.7% | 0.3% |
| Charo | 515 | 6.8% | 0.8% |
| ohmydenim | 487 | 0.4% | 1.8% |
| coolsistema | 77 | 6.5% | 0.0% |
| Cielo · ACE | 51 | 0% | 0% |

- 수단 0개 티켓(Shaple 4.7%)이 있다 → medio de pago 합계 ≠ venta neta. 「미지정」 행이 필요.
- 결제수단 제목이 매장별 자유 입력이고 중복도 있다(coolsistema `MercadoPago` / `Mercadopago`, Charo `TARJETA DE CREDITO` / `Tarjeta de Crédito`). Shaple 은 사람 이름 수단(«Pagos Dani», «Pagos Felipe»). → 차원 값은 `payment_methods.id` 로 묶고 이름은 표시용만.

### 6-4. 판매원 수
| 매장 | 30일 판매에 쓰인 seller | 활성 Sellers | seller 미지정 | 판매 등록 user |
|---|---|---|---|---|
| Shaple | 9 | 15 | 0.1% | 2 |
| NOIX | 8 | 5 | 7.6% | 1 |
| coolsistema | 4 | 15 | 5.2% | 2 |
| Cache | 4 | 4 | 1.5% | 1 |
| Charo | 2 | 8 | 4.9% | 1 |
| ACE · Cielo | 2 | 4 · 2 | 0% | 2 |
| ohmydenim | 1 | 4 | 4.1% | 0 |

→ 판매원은 `sales.seller_id`(Sellers) 기준이어야 한다 — `user_id` 는 계산대 계정 1~2개뿐이라 의미 없다. 판매원 최대 9명 → Top N 불필요, 「미지정」 행 필요.

### 6-5. 지점 수
Charo 5(판매 2) · ohmydenim 3(판매 1) · coolsistema 2(2) · ACE 2(2) · 나머지 4개 매장 1.
→ 지점 차원은 **다지점 매장에만 기본 노출**, 단일 지점 매장에는 숨기거나 회색.

### 6-6. 속성 입력률 (판매 품목 기준, 변형→마드레 상속)
| 매장 | 카테고리 | temporada | color | talle | 고유값(cat/season/color/talle/마드레) |
|---|---|---|---|---|---|
| Shaple | 98.8% | 98.8% | 98.6% | 98.6% | **1 / 1 / 1 / 35** / 498 |
| Cache | 94.9% | 95.2% | 0.8% | 0.8% | 1 / **6** / 1 / 1 / 148 |
| NOIX | 94.0% | 94.0% | 1.4% | 1.4% | **11** / 2 / 1 / 1 / 138 |
| Charo | 99.8% | 99.8% | 0.0% | 0.0% | 1 / 1 / 0 / 0 / 279 |
| ohmydenim | 95.7% | 95.5% | 38.8% | 38.8% | 1 / 1 / 2 / 1 / 55 |
| Cielo | 42.1% | 42.1% | 42.1% | 42.1% | 3 / 1 / **18** / **12** / 144 |
| coolsistema | 93.4% | 89.2% | 86.8% | 86.8% | **12 / 5 / 14 / 8** / 31 |

- 「채워짐」 비율은 착시다. 값의 정체: Shaple·Cache·Charo·ohmydenim 카테고리 = 전부 **`NONE`**, temporada 도 대부분 `NONE`(Cache 만 PRIMAVERA-VERANO 등 6종), color = `Color Único`.
- 실제로 의미 있는 축: **NOIX=카테고리(VESTIDO·TOP·SHORT POLLERA…)** · **Shaple=talle(35종)** · **Cache=temporada** · **Cielo=color/talle** · **coolsistema=전부(데모 성격)**.
- 모든 매장에서 의미 있는 축은 **시간 · 상품(마드레) · 판매원 · 결제수단** 넷뿐이다.

### 6-7. 반품·취소
30일 Anulación/Anulado: Cache 33/35 · NOIX 16/18 · Shaple 9/8 · Cielo 6/6 · coolsistema 4/4 · Charo 2/2. 음수 total 의 Pagado(반품형)는 Shaple −115,500 · Charo −92,990 에서만 관측.
→ 「Devoluciones」 지표는 대부분 매장에서 작거나 0 — 템플릿 기본 열로는 「취소 건수」 쪽이 더 의미가 있을 수 있다.

---

## 7) 템플릿·카탈로그에 주는 시사점 (구체적으로)

**A. 템플릿 (첫 화면에 6개 이하)** — 근거를 괄호에
1. **Ventas por día / mes** — 시간 × (venta neta, tickets, ticket promedio, unidades), 전기 대비. (Breve Venta 원형 · 모든 매장에서 유효한 축 · Trello «por período»)
2. **Top productos (madre)** — 상품 Top 20 × (unidades, venta neta), 점유율은 **전체 대비**. (items-cockpit 사용 · 105 E3/E4)
3. **Ventas por vendedor** — Sellers × (venta neta, tickets, ticket promedio, unidades) + 「Sin vendedor」. (레거시 Vendedor · Trello · 판매원 2~9명)
4. **Ventas por sucursal** — 다지점 매장에만 노출(Charo·ohmydenim·coolsistema·ACE). (Trello «sucursal», SControl, 105 원칙)
5. **Medios de pago** — 결제수단 × venta neta(금액 배분) + 「Sin medio」, tickets 지표 차단(D-10). (분할 ≤7.5%, 미지정 4.7%)
6. **Talle × Color (o Talle sola)** — 매장 데이터가 있을 때만 제안(Shaple talle·Cielo color). talle 는 **숫자 순 정렬**(PEDIDO 40). (레거시 color/talle 그리드)

- 「Margen por producto」는 템플릿에 **두지 않는다**(원가 입력률 0~41%). 원가 입력률 ≥80% 인 매장에만 제안.
- 「Por categoría / temporada」는 **값이 `NONE` 외 2개 이상**인 매장에서만 템플릿으로 띄운다(NOIX 카테고리, Cache temporada).

**B. 카탈로그 규칙**
- 차원 노출은 **매장 데이터로 동적으로**: 고유값 ≤1(또는 `NONE`/`Color Único` 만)인 차원은 회색 + 사유(«todos los productos tienen la misma categoría»). 막다른 선택지를 안 보이게(「막힌 이유」 UI 와 연결).
- 「미지정/NONE」 행은 **숨기지 말고 하나의 행**으로 보여 합계가 맞게.
- 판매원 = `sales.seller_id`, 지점 = `sales.branch_id`(CLAUDE.md 규칙), 결제수단 = `payment_methods.id`.
- `source='legacy'` 판매 포함 여부·중복을 venta 조각에서 정의(§6-0). 레거시 매장(Charo·ohmydenim)은 legacy 를 빼면 보고서가 비어 버린다.
- Excel/CSV 는 유지하되 우선순위 낮음 — 실측 수요는 「당일 판매 1개」. 「저장된 보고서 + 원클릭 실행」이 그 사용자(Shaple admin)의 매일 export 를 대체할 수 있다(→ 「Ventas de hoy」 저장 템플릿).
- 한도: 최대 매장 일 262 티켓 → 일 단위 90일 = 최대 ~2.4만 티켓, 상품 마드레 498개. 화면 1,000행 한도는 **상품×일** 조합에서만 걸린다 → 그 조합은 Top N 강제.

**C. 사용자**
- 1차 사용자는 판매량 큰 매장의 admin(Shaple·Cache·Charo). gerente 는 Stock 만 본다 → admin 전용 기본값(D-05)과 부합.

---

## 8) Gastos y Facturación

### 8-1. 요구
- Pedidos: 34(Shaple) «no puedo ver gastos de caja … en tesorería → gastos no aparecen» — **조회 위치를 못 찾음**, 38(coolsistema) 지출 입력 실패(결함). 보고서 요구는 아님.
- Facturación 관련 pedido·AI 질문: **0건**(26 은 지원 토큰의 「Facturas 창」 권한 문제).
- AI 질문 중 gastos/IVA/monotributo/% facturado: 0건.
- Trello: «Reportes de caja y finanzas».

### 8-2. 사용량 (14일)
- Gastos **입력** 화면: `expenses/search` 434 · `daily-summary` 266 · `expense-categories/tree` 44 — 8명. 일상적으로 쓰인다.
- Gastos **보고서**: `gasto-cockpit` 19+5 · `reports/gastos/by-category` 15 — 2명(coolsistema gerente 16 이 대부분). `gasto-report(-export)` 0.
- Facturación **보고서**: `facturacion-cockpit` 10+4 — 2명(Cielo admin, coolsistema). `facturacion-report(-export)` 0.
- AFIP 운영 화면: `afip/cert/aviso-tienda` 711(배너 폴링) · `afip/issuers` 348 · `afip/emitidas` 17 · `afip/pendientes` 15 — 보고서가 아니라 발급 운영.

### 8-3. 데이터 현실
**Gastos** (`expenses`, 90일)
| 매장 | 90일 | 30일 | 금액(90일) | 카테고리(새 트리) | affects_box | 지점 |
|---|---|---|---|---|---|---|
| Shaple | 257 | 90 | 13.0M | 4 | 100% | 1 |
| NOIX | 213 | 105 | 172.2M | 3 | 100% | 1 |
| Cache | 89 | 28 | 6.2M | 16 | 100% | 1 |
| Charo | 23 | 6 | 3.8M | 1 | 100% | 1 |
| coolsistema | 8 | 4 | 0.4M | 6 | 100% | 2 |
| ACE | 4 | 2 | 0.5M | 4 | 25% | 2 |
- 월별: 2025-10 ~ 2026-07 은 3~4개 매장 월 50~115건, 2026-09 317건(6개 매장).
- 카테고리는 **매장마다 자유 트리**이고 질이 고르지 않다: 상위 «MANTENIMIENTO» 204건(2개 매장), 하위에 ELASTICO·EXPRESO·BOLSA·BOTONERA(생산 자재), 의미 없는 «c»·«e»·«ec». 옛 `expenses_subcategories` 사용 0건.
- 거의 전부 `affects_box=true` — 지출 = **카하에서 나간 현금**. 즉 Gastos 는 카하 원장의 일부다.

**Facturación**
- Ventago AFIP(`afip_vouchers`) 누적: coolsistema A 11·B 10(prod), Cielo C 8 + NC-C 2(prod, Monotributo), ACE B 2(homo). **30일 12건.**
- POS 판매 중 CAE 있는 비율(30일): Cielo 16.3%(금액 32.8%) · coolsistema 1.4% · **나머지 0%**.
- 실제 발급은 레거시 원장 `legacy_facturas`(68,600행)에 있다: 최근 120일 Charo 대부분 **B**(월 76~211), NOIX 대부분 **A**(월 100~136, NC-A 소수), coolsistema 소수. Shaple 36,986행은 10-03 이후 갱신 없음.
- 세무 지위: `afip_issuers.iva_condition` RI 5(ACE·Charo·NOIX·Shaple·coolsistema) / MONO 1(Cielo). `stores.type_of_payer` 는 절반이 비어 있어 신뢰 불가. `store_configs.afip_default_pct` 30%(NOIX·coolsistema·Cielo) — **부분 발급(% facturado)이 설정으로 존재**.
- `afip_facturas_sin_venta` 90일 2건 · `afip_comprobantes_externos` 0건.

### 8-3b. 기존 화면이 다루는 것 / 빈 곳
- **Gasto 보고서**(`reportsGastoCockpit.service.ts`): 합계·건수·평균·카테고리 수(전기 대비), 일 추세, **카테고리 Top 8**(`expense_categories.path`, 점유율), 상세 목록, 트리 깊이별 집계(`/reports/gastos/by-category`), xlsx. 빈 곳: 출처(payment_source)·공급자·월별 비교·판매 대비.
- **Facturación 보고서**(`reportsFacturacionCockpit.service.ts`): 원천 `afip_vouchers` 만, NC 음수 처리, 합계·건수·평균(전기 대비), 일 추세, 고객 Top 5, 목록, xlsx. 빈 곳: **종류(A/B/C/NC) 분리 없음** · **neto/IVA 미표시**(컬럼 `neto_gravado`·`iva_liquidado`·`iva_alicuota` 는 테이블에 있다) · **% facturado 없음** · PV/지점별 없음 · `legacy_facturas` 미포함.

### 8-4. 템플릿 시사점 — 별도 보고서 종류로
- **판매 빌더에 섞지 않는다.** 근거: ① 원장이 다르다(gastos=카하 현금 유출, facturación=세무 발급, 판매=상품 거래) ② 차원이 다르다(gastos: 카테고리 트리·지점·출처 / facturación: 종류 A/B/C/NC·발급자 CUIT·PV·IVA 세율) ③ 원천이 둘로 갈린다(facturación = `afip_vouchers` + `legacy_facturas`) ④ 117 CONTEXT 에서 gastos 를 「보고서 종류」로 이미 보류.
- 후속에서 「보고서 종류」 선택(Ventas | Gastos | Facturación)을 두면, 같은 빌더 UI(지표·차원·기간·저장)를 재사용할 수 있다. 117 의 카탈로그 구조(종류 → 허용 지표·차원 목록)를 **종류 확장이 가능하게** 설계해 두는 것이 실질적 시사점이다.
- Gastos 종류 후보: 지표 = 금액·건수 / 차원 = 시간·카테고리(트리 레벨 선택)·지점·출처(payment_source) / 템플릿 = 「Gastos del mes por categoría」·「Gastos vs ventas(día)」(레거시 Breve Venta 가 판매+지출을 한 장에 합쳤다).
- Facturación 종류 후보: 지표 = 발급액·neto·IVA·건수 / 차원 = 시간·종류(A/B/C/NC)·발급자·지점 / 핵심 KPI = **% facturado(발급액 ÷ venta neta)** — 105 점검인도 「매출의 약 0.7%」를 짚었다. 단 Ventago 발급만 보면 대부분 매장 0% 이므로 legacy_facturas 를 합치지 않으면 오해를 만든다.
- 우선순위: Gastos 가 먼저(6개 매장 일상 입력·카하와 직결), Facturación 은 Ventago 발급이 늘어난 뒤.
