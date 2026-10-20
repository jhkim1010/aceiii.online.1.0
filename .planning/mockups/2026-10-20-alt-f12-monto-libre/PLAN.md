# Alt+F12 «monto libre» — 카트가 비어 있고 고객만 선택된 상태에서 영수증만 발급

2026-10-20 · 계획 + 목업만 (코드·DB 변경 없음, push 없음) · 목업: `mockup.png` / `mockup.html`

> 사용자 요청: 아이템 없이 고객만 선택돼 있으면 monto final 과 줄별 금액을 입력받아, 영수증이 어떻게 나갈지
> 미리보기로 보여 주고, 조정한 뒤 발급. 하루 매상에 안 들어가는 것은 지금과 같음.

---

## 1. 지금 동작 (2026-10-15 배포분)

| 단계 | 근거 |
|---|---|
| 단축키 정의 `alt+f12` «Sólo factura al 100% (NO registra la venta)» | `ventago-app/src/views/homes/utils/shortcuts.ts:94` |
| Alt+F12 → `motivoNoSoloFactura()` 가 막을 이유를 찾고, 있으면 toast 만 띄우고 끝 | `ProductList.tsx:3228-3244` |
| **카트가 비면** `'Agregá al menos un producto.'` toast → **다이얼로그 안 열림** | `views/facturacion/solo-factura.ts:53` |
| 그 밖의 차단: FE 미승인 · 오프라인 · Movidos/Fallados · 반품 줄 · 외상 수금 줄 · 수량 0 · 합계 ≤ 0 | `solo-factura.ts:50-57` |
| 카트 줄 → 화면 합계(할인·추가요금·배송 포함)에 비례 배분, 반올림 센타보는 마지막 줄 | `solo-factura.ts:19-38` (`lineasSoloFactura`) |
| 다이얼로그: 고객(없으면 Consumidor Final) · 단위/줄 수 · 합계 · IIBB 관할 · 출력(인쇄 1회/안 함). 줄 편집 불가 | `SoloFacturaDialog.tsx:112-195` |
| ★ 다이얼로그 **어디서든 Enter = 발급** | `SoloFacturaDialog.tsx:118-123` |
| 열 때 멱등 키 1개 생성, AFIP 가 확실히 거절한 경우만 새 키 | `SoloFacturaDialog.tsx:54-60, 101-102` |
| `POST /afip/vouchers/sin-venta` (admin·superadmin·gerente·vendedor) | `api-ventago/src/app/afip/afip.controller.ts:1286-1325` |
| DTO: items 1–200개, 각 `cantidad ≥ 0.001` · `subtotal ≥ 0`(소수 2) · `descripcion 1–120자` · **`productId` 선택** | `afip/dto/emitir-sin-venta.dto.ts` |
| 서버: storeId 는 토큰에서만. 지점·터미널·고객을 그 매장으로 검증, 줄 단가 = `r2(subtotal/cantidad)`, 합계 = Σsubtotal 재계산 | `afip-voucher.service.ts:315-420` |
| 멱등: `(store_id, idempotency_key)` UNIQUE, 키 = `클라이언트키:내용해시16` — 같은 키+다른 내용 = 409, 이미 발급 = 같은 전표 반환(재인쇄 없음) | `afip-voucher.service.ts:422-490` |
| 발급: 판매와 같은 `emitirConGuardas()`(발행자·PV·homo 7일·임시손님 거절·IIBB 관할) → `issue()` | `afip-voucher.service.ts:522, 536-700` |
| 인쇄: **컨트롤러 한 곳, 이번에 새로 발급됐을 때만**, `output==='thermal'` | `afip.controller.ts:1309-1322` |
| 인쇄 원본: `afip_facturas_sin_venta.items` 를 판매 모양으로 변환(`customName = descripcion`, product = null) | `afip-query.service.ts:94-137` |

**저장 구조**: `sales` 행 없음. `afip_facturas_sin_venta` 1행(receptor 스냅샷 + `items jsonb` + `total`) +
`afip_vouchers` 1행(`sin_venta_id` FK, `sale_id` NULL). 줄에 상품이 필요 없다 — `productId` 는 선택이고 인쇄도
`descripcion` 만 쓴다. → **제네릭 상품 불필요.**
운영 실측(2026-10-20): 2행 — #1 store 6 `facturado` 50.000, #2 store 19 `error`(ENOENT, 인증서 파일) 144.000.

**IVA**: 줄별 세율 없음. 전표 하나에 알리쿼트 하나 — `ivaForResiva`(국내 21 %, resiva 4 = 면세, -1 = 해외),
Factura C 는 IVA 분리 없음(`afip-voucher.service.ts:984-1000`). 종류: 발행자 MONO → C, 수신자 CUIT 11자리 → A, 그 외 B
(`code-maps.ts:154-181`). 문서 없으면 DocTipo 99(CF) (`code-maps.ts:183-197`).

---

## 2. 제안 UX

**분기**: Alt+F12 를 눌렀을 때 `products.length === 0` **이고** `selectedClient` 가 있으면 → 새 다이얼로그
`MontoLibreDialog`. 카트에 줄이 있으면 **지금 그대로**(SoloFacturaDialog). 둘 다 없으면 지금 toast 유지
(문구만 «Agregá un producto o elegí un cliente»). 단축키 자체는 그대로라 전 매장 공통 규칙에 맞다.

1. 열리면 포커스 = **Monto final**(IVA 포함). Enter → 1번 줄 설명.
2. 줄 = 설명 · 수량(기본 1) · **금액(줄 합계)** · 단가(읽기 전용 = 금액÷수량). 금액 칸에서 Enter → 새 줄.
   첫 줄은 열 때 비어 있음. ✕ 로 삭제.
3. 아래 띠: **Σ줄 · Monto final · 차이**. 차이 ≠ 0 이면 빨강, 발급 버튼 비활성 + 사유 한 줄.
4. 보조 버튼(다이얼로그 안에서만 작동하는 키):
   - 차이를 마지막 줄에 더함 · 비례 배분(기존 `lineasSoloFactura` 규칙 재사용) · «Varios» 줄 추가 · N 등분.
5. 오른쪽 **미리보기**(서버 계산, 아래 3-②): 종류 A/B/C · 발행자·PV · 수신자 · 줄 · 순액/IVA · 합계.
   번호·CAE 는 «al emitir». 차이 ≠ 0 이면 «BORRADOR» 표시. **미리보기는 인쇄도 발급도 하지 않는다.**
6. IIBB 관할 · 출력(인쇄 1회 / 안 함) — 지금 다이얼로그와 같은 필드.
7. 발급 = **버튼 또는 Ctrl+Enter 만.** (★ 지금처럼 「Enter = 발급」이면 금액 입력 중 Enter 로 발급된다 —
   이 다이얼로그에서는 Enter 를 다음 칸 이동으로 쓴다.)
8. 성공 → toast `CAE …`, 다이얼로그 닫고 고객 선택 해제(resetSale). 실패 → 메시지, 입력 유지.

---

## 3. 서버 변경

① **발급은 기존 엔드포인트 재사용** — `POST /afip/vouchers/sin-venta` 가 이미 상품 없는 줄을 받는다.
  추가 1개만: DTO 에 선택 필드 `montoFinal`. 오면 서버가 `Σsubtotal === montoFinal`(센타보 단위) 아니면 400.
  화면 검증만 믿지 않기 위함. 기존 Alt+F12(카트) 호출은 안 보내므로 영향 없음. 멱등 해시에도 포함.

② **미리보기 엔드포인트 신규** `POST /afip/vouchers/sin-venta/preview` — 같은 body(키 제외).
  발급과 **같은 함수**로 판단: `resolveIssuerForSale` → `decideComprobante` → `ivaForResiva`/`computeNetoIva`
  → 줄 단가 `r2(subtotal/cantidad)`. 반환: `{ tipo, letra, emisor{cuit, razon, pv}, receptor, lines, neto, iva, total, avisos[] }`.
  DB 쓰기 0, AFIP 호출 0, 인쇄 0. (`previewPartial`(`afip-voucher.service.ts:777`) 과 같은 성격.)
  디바운스 300 ms 로 호출. 프론트에서 종류·IVA 를 따로 계산하지 않는다(두 개의 진실 방지).

③ DB 변경 **없음** — `afip_facturas_sin_venta.items` 그대로(`productId` 없이 저장).
  구분이 필요하면 `items[].origen = 'libre'` 를 jsonb 에 넣는 정도(스키마 변경 아님) — 결정 사항 D5.

---

## 4. 검증

| 항목 | 규칙 | 위치 |
|---|---|---|
| 고객 | 이 모드에서는 **필수**(요청이 「고객만 선택」). 임시 손님(S…)은 이미 서버가 거절 | 프론트 + 기존 서버 |
| Factura A | 수신자 CUIT 11자리 + RI. CUIT 없는 고객이면 B 로 나간다는 것을 미리보기가 보여 줌 | preview |
| Factura B · CF | 문서 없는 고객 + 합계가 AFIP 식별 의무 기준(코드 주석상 $10M, `code-maps.ts:191`) 이상이면 **발급 전 거절**. 기준값은 상수 하나로 — 현재값 확인 필요(D3) | preview `avisos` + 서버 |
| 줄 | 설명 1–120자, 수량 > 0, 금액 > 0(0 줄 금지 제안), 최대 200줄 | 프론트 + DTO |
| 합계 | **Σ줄 = monto final** 이어야 발급. 센타보 정수로 비교 | 프론트 + 서버 ① |
| 단가 반올림 | 금액÷수량이 나누어떨어지지 않으면 경고(12 × 3.333,33 = 39.999,96 로 인쇄). AFIP 금액은 줄 금액 합이라 맞지만 종이가 어긋나 보인다 | 프론트 경고 |
| 그 외 | FE 승인 · 온라인 · 특수모드 아님 — 기존 `motivoNoSoloFactura` 의 해당 조건 재사용 | 프론트 |

---

## 5. 위험

- **자동 발급 금지**: 발급은 버튼/Ctrl+Enter 만. 미리보기 엔드포인트는 `issue*` 를 부르지 않는다(spec 으로 고정:
  preview 호출 후 `afip_vouchers`·`afip_facturas_sin_venta` 행 수 불변, CAE provider 호출 0).
- **중복 인쇄**: 인쇄 경로는 기존 컨트롤러 한 곳 그대로. 미리보기는 화면 렌더만, 프린터/소켓 호출 없음.
  다이얼로그 키는 열 때 1개 — 줄을 고쳐 내용이 바뀐 뒤 재시도하면 409 → 「AFIP 확실 거절 시에만 새 키」 규칙 유지.
- **Enter 발급 사고**: 지금 다이얼로그 방식(Enter=발급)을 복사하면 금액 입력 도중 발급. 이 다이얼로그는 Ctrl+Enter.
- **테넌트 격리**: storeId 는 토큰에서만(기존). preview 도 같은 검증(지점·고객이 그 매장인지) — 남의 매장 고객의
  CUIT·이름을 미리보기로 읽는 통로가 되면 안 된다.
- **반올림**: 모든 비교를 센타보 정수로. IVA 분해는 서버 `computeNetoIva`(BigInt) 만.
- **허위 전표 위험**: 상품·재고와 무관한 임의 금액 전표가 된다. 지금도 sin-venta 는 Emitidas 에 «Sin venta»
  칩으로 보이고(`EmitidasPanel.tsx:144`) 감사 가능 — 권한을 admin/gerente 로 좁힐지 결정(D4).

---

## 6. 결정 필요

- **D1 수량 칸**: 둘 것인가? 제안 = 두되 기본 1(대부분 1, 필요 시 «12 × 단가» 표시용).
- **D2 고객 없음 + 카트 없음**: 지금처럼 막을지(제안), CF 로도 허용할지.
- **D3 CF 식별 의무 기준액**: 코드 주석 $10.000.000 — 현재 AFIP 기준으로 확인 후 상수화.
- **D4 권한**: 지금 sin-venta 는 vendedor 도 가능. 「monto libre」는 admin·gerente 만?
- **D5 줄별 IVA(10,5 % 등)**: 지금 엔진은 전표당 세율 1개. v1 은 단일 세율(21 %)로, 다세율은 별도 작업.
- **D6 B 전표의 «IVA contenido»(Ley 27.743)**: 현재 `build-factura.ts` 는 A/M 만 IVA 분해 표시. 미리보기·인쇄에
  넣을지는 이번 범위 밖(별도 확인 권장).

---

## 7. 규모

| 작업 | 크기 |
|---|---|
| 순수 헬퍼 `monto-libre.ts`(차이·배분·N등분·센타보 비교) + jest | 0.3일 |
| `MontoLibreDialog.tsx`(입력 표·키보드·미리보기 렌더) + ProductList 분기 | 0.8일 |
| api: DTO `montoFinal` + 서버 검증, preview 엔드포인트 + spec(쓰기 0·AFIP 0 대조) | 0.5일 |
| 로컬 확인(homo 발급 1건, 인쇄 1장 확인) | 0.3일 |
| **합계** | **약 2일**. DB 마이그레이션 없음. api 를 먼저 배포해도 안전(필드 선택·엔드포인트 신규) |

## 결정 (2026-10-20 사용자)

- **Descripción = 매장별 「자주 쓰는 문구」 목록에서 선택 (안 3).**
  - 매장 설정에 문구 목록을 둔다(추가·수정·삭제·순서). 저장 위치: **새 테이블** `factura_libre_descripciones(id, store_id, texto, orden, activo, timestamps)` (사용자 결정). 신규 테이블이라 owner/시퀀스 coolsistema 이전 DO 블록 필수, 로컬+운영 동시 적용(운영은 SQL 승인 후).
  - 다이얼로그의 설명 칸 = 그 목록의 선택 상자(검색 가능). 목록이 비어 있으면 설정 화면으로 가는 링크를 보여 준다(막다른 화면 금지).
  - **목록 밖 문구도 그 자리에서 바로 입력 가능** (사용자 결정). 선택 상자 = 자유 입력 + 목록 제안(freeSolo).
  - 설명 칸이 비면 발급 불가(공통).
- 남은 결정: D1 수량 칸 · D2 고객 없을 때 · D3 신분 기재 기준액 · D4 사용 역할 · D5 줄별 IVA · D6 B 전표 IVA 포함액 표시 (목록 밖 문구·저장 위치는 결정됨).
