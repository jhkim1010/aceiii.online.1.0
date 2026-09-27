# 핸드오프 2026-09-27 — Ganancia · 취소 재고 결함 · 교환 취소 · 1 터미널 : N 프린터

> 다음 세션은 **§6 남은 일**부터. 오늘 나간 것은 전부 운영 배포·빌드·컨테이너 확인까지 끝났다.
> ★ 이 세션에서도 **화면을 브라우저로 직접 눌러 보지 못했다**. 서버는 로컬 DB itest 로 검증했다.
>   첫 작업으로 운영 화면 확인(§7).
> 전 세션: `HANDOFF-2026-09-26-c-costo-cotizacion-permisos.md`

## 1. 운영에 나간 것 (배포 순서)

| # | 내용 | api | app | Jenkins |
|---|---|---|---|---|
| 1 | 판매 시점 원가 스냅샷 `sale_items.unit_cost` + **취소 재고 미복원 결함 수정** | `b0499049` | — | api #975 |
| 2 | UX: 원가 칸 풍선도움말(처음 5회) · 로그인 Tab 순서 | — | `9fd70376` | front #820 |
| 3 | 과거 취소분 재고 보정 SQL (파일 커밋) | `45db9d1c` | — | #976 |
| 4 | **Ganancia 보고서** `GET /reports/ganancia` + 화면 | `61c43e38` | `447af255` | #977 · #821 |
| 5 | **교환 판매 취소**(부호 있는 역분개) + codex 2건 | `fd4aaa0d`·`a3e87ddc` | — | #978 |
| 6 | **1 터미널 : N comandera** + codex 2건 | `167f64c7`·`530b53d7` | `21d21b2e` | #979 · #822 |
| 7 | 히스토리·판매상세 재인쇄 프린터 선택 | `9ae7372c` | `c296d816` | #980 · #823 |
| 8 | Ventas 보고서 **Costo·Ganancia 칼럼** | `9d76df14` | `b36f96f5` | #981 · #824 |
| 9 | auto impTiq 를 선택 프린터 기준으로 | — | `47330e67` | #825 |

루트 포인터 최종: `72b281e`.

**운영 DB (전부 사용자 승인 후 실행 · 로컬 5432 · 스테이징 동일 적용)**
- `2026-09-27-sale-items-unit-cost.sql` — `sale_items.unit_cost` (nullable, expand)
- `2026-09-27-b-reparar-anulaciones-sin-stock.sql` — **운영만** (데이터 보정): UPDATE 27 · stocks INSERT 17
- `2026-09-27-c-permiso-reporte-ganancia.sql` — function 1 · role_functions 18 · actions 18
- `2026-09-27-d-terminal-printers.sql` — 새 테이블 (owner coolsistema)
- 확인: `v_stock_tenant_leak` 0 · `v_stock_balance_drift` 0 · 매장 교차 행 0 (6개 대조 쿼리)

## 2. ★ 발견한 결함 — 판매 취소가 재고를 한 번도 복원하지 않았다

- `salesService.findOne` 의 SaleItem attributes 에 **`productId` 가 없었다**(Product include 해도 FK 는 안 실린다).
  `nullifyInTransaction` 의 `item.productId` = undefined → 역분개 품목 product_id NULL, 재고 복원·madre 가드·
  지점 가드가 **전부 한 번도 실행된 적 없다.** 운영: 취소 9건 · 28줄, `anulacion` stocks 행 0.
- 수정: attributes 에 `productId` + promo 3필드. itest 가 재고 복원을 단언, productId 제거 돌연변이가 죽는다.
- 보정(사용자 결정): 실매장 **NOIX(19) +50 · 매장 22 +30**, 테스트 매장 6·9 는 product_id 만.
- ⚠️ **이제 취소 가드가 처음 돈다** — 「취소가 새로 거절된다」 문의가 오면 madre·지점·교환 D2 가드부터.
  메모리 `nullify-never-restored-stock-before-0927`.

## 3. Ganancia

- 결정: ① 판매 시점 스냅샷 ② 지출 = expenses 전체 ③ Reportes. 권한 slug 는 계획의 `ver-ganancia` 대신
  **`reporte-ganancia`**(기존 reporte-* 규칙 → 메뉴 시드 불필요).
- 스냅샷: `SaleItem` 모델 훅(BeforeCreate/BeforeBulkCreate)이 **모든 판매 경로**에서 채운다
  (`src/app/sales/sales-item/costo-unitario.ts`). 요청 본문의 unitCost 는 항상 덮어쓴다.
  취소 역분개만 `keepUnitCost` 옵션으로 원본 값을 복사. madre 원가 · USD × 매장 최신 환율 · 없으면 NULL(0 아님).
- 보고서 두 개(사용자와 합의 — 둘 다 유지):
  - **Ganancia**(Finanzas): 판매 − 반품 환불 − 원가 − 지출, 일별, **발생주의**. 반품 환불액은
    원장(payment_in/favor_in, sale_id=반품) + 서랍 「Devolución #ID — reintegro en efectivo」 문자열로 읽는다.
  - **Ventas › ventas 탭 Costo·Ganancia 칼럼**: 판매별(원가 모르는 줄이 있으면 null「sin costo」),
    일·월·연 묶음은 원가 완전한 판매만 이익, 나머지 「Sin costo」. 기간 Total(현금주의)과 섞지 않는다.
    `reporte-ganancia` 가 없으면 SQL 이 원가를 읽지도 않는다(`isAllowedStrict`).
- ⚠️ **운영에 원가 입력 상품 0개 · 환율 0건** → 지금은 전부 「sin costo」. 소급 없음(9-27 이후 판매부터).

## 4. 교환 판매 취소 (PLAN-2026-09-26-cambio-anulacion-modificacion.md 1단계)

- D1 빚으로 · D2 매장 설정 · D3 취소만(수정은 여전히 ERR-DEV-012).
- `signed = esVentaConDevolucion(original)` 일 때만 `−(x)`, 일반 판매는 종전 `−|x|` 그대로.
  재고 +원본수량 · 합계<0 현금은 서랍 `ingreso` · favor 교환은 `reverseReturnCreditForSale`
  (payment_in→sale_credit, favor_in→favor_apply, 이미 쓴 favor→sale_credit).
- 원장 미완료(후크 전) → ERR-DEV-013. 재고 없음 + 음수 비허용 매장 → ERR-DEV-014.
- codex: ① 자기 외상을 favor 로 자동상계한 payment_in(parent=자기 sale_credit)은 제외(이중 되돌림) ②
  D2 재고 잠금은 **채번 advisory lock 뒤**(판매 생성과 같은 순서 — 교착).
- itest `sale-return` 30/30 · S+R=0 전수 단언 · 돌연변이 5개 사망.

## 5. 1 터미널 : N comandera

- 기본 = `terminals.thermal_agent_id`(단일 출처) · 추가 = `terminal_printers`(같은 매장, 다른 지점 가능).
- `resolveSingleThermalTarget({agentId, storeId})`: 고른 한 대로만. 허용 밖 `printer_not_allowed`,
  꺼짐 `agent_offline` — **다른 대로 대신 보내지 않는다**(중복 인쇄 절대 금지 규칙).
  codex: 잘못된 id(0·"abc")를 「선택 없음」으로 읽지 않기 · 터미널이 요청 지점의 것인지(boxes.branch_id).
- `printerAgentId` 가 흐르는 곳: `/print/temp` · `POST /sales`(sendToprinters + AFIP 자동 발급 감열) ·
  `POST /sales/:id/reprint`. 조회: `GET /print/terminal/:id/printers` · `GET /print/thermal-agents` ·
  `GET /sales/:id/printers`(재인쇄 = **판매 터미널**의 목록) · 설정 `PUT /print/terminal/:id/printers`(editar-terminal).
- 화면: Venta 상태 알약 → 선택 메뉴(세션 유지 sessionStorage `ventago.printer.t{id}`) · Sucursales›Terminales
  「Comanderas adicionales」 · 히스토리/상세 재인쇄 메뉴(2대 이상일 때) · auto impTiq = `printerReady()`.
- 범위 밖(사용자 결정): Zebra. AFIP 화면의 수동 전표 재인쇄(`afip.controller`)는 기본 프린터 그대로.
- itest `terminal-printers` 10/10 · 돌연변이 5개 사망 · app spec `printer-choice` 10/10.

## 6. 남은 일

1. **운영 화면 확인**(§7) — 이번 세션 전부 미확인.
2. 원가·환율 입력은 매장 몫. 입력 후 테스트 판매로 두 보고서 숫자 확인.
3. 교환 **수정(modificar)** — 계획서 §4 (2단계).
4. **Phase 95 멀티테넌트** — W0 부터.
5. `bulkUpdatePrices` N+1(원가 대량 적용) 미측정.
6. NOIX(19): 터미널–comandera 매핑 0 + 에이전트 2대 → `ambiguous_target` 로 영수증 안 나감. 이제
   Terminales 에서 기본 지정만 하면 해결. 사용자에게 알렸고 **미결**.
7. 핸드오프 (b)·(c) 잔여(스테이징 상시화, 현금 환불 권한 통일 등).
8. (기존) Ventas vcode 목록은 지점 필터를 `u.branch_id` 로 건다 — 권위 컬럼은 `sales.branch_id`. 손 안 댐.

## 7. 첫 확인 (운영 화면)

- Productos nuevos: 원가 칸 hover → 풍선도움말(5회), 로그인 Tab 순서
- Reportes › Finanzas › Ganancia · Reportes › Ventas(ventas 탭 · 단위 Día/Mes) — admin 과 비admin 계정 각각
- Sucursales › Terminales: 「Comanderas adicionales」 저장 → Venta 알약 메뉴 → 다른 프린터로 티켓 · Alt+T
- Historial 재인쇄 메뉴(2대 이상 연결된 터미널의 판매)
- 교환 판매 하나 만들고 취소 → 재고·서랍·손님 잔액 원복

## 8. 이번 세션의 교훈

- **오래 안 돈 경로는 결함이 겹겹** — 취소 재고 복원이 넉 달간 0회였다. 한쪽(sales-modify)이
  `it.productId ?? it.product?.id` 로 우회하고 있어 다른 쪽이 가려졌다.
- 모델 훅은 「모든 경로」를 덮지만 **`fields` 지정·`hooks:false`** 면 빠진다(codex 확인 — 현재 해당 경로 없음).
- 선택형 기능의 `Number(x) || null` 은 **「잘못된 값 → 선택 없음 → 기본으로 출력」** 이 된다. null/undefined 만 없음.
- react-hotkeys-hook v5: deps 없으면 매 렌더 최신 콜백(`f.current = r`) — Alt+T 클로저는 안전.
- itest 에서 새 매장은 `store_configs` 행이 없다(없으면 「허용」) — 설정 시험은 행을 넣어야 한다.
- 커밋 게이트: `git add` 와 `git commit` 은 **따로**, 기존 파일 prettier 는 HEAD 가 clean 했는지 먼저.
