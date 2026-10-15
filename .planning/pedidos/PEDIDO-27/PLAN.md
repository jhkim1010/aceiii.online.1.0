# PEDIDO 27 — 「HISTORIAL DE DEUDA」: POS 에서 손님을 고르면 판매·외상 내역 버튼

## 요청 원문 요약
- 매장: Shaple (store 26) · 작성자 sebi park · 2026-10-12 11:01 (매장 시각)
- 원문: 「AL SELECCIONAR CLIENTE DEBERIA APARECER EL BOTON VER HISTORIAL DE VENTA Y DEUDA」
- 사진(`captura-tienda.jpg`): POS 「INFO DE CLIENTE」 카드 — WALPEN MARIA LILIANA, 「Debe $ 614.000」 + 「COBRAR DEUDA」.
- **분류: 개선** (지금 없는 기능)

## 현재 동작
| 무엇 | 상태 | 근거 |
|---|---|---|
| 손님의 **판매 내역** | POS 에서 볼 방법 없음. Historial de ventas 는 이름 검색(ILIKE)만 — 손님 id 필터가 없다 | `sales.service.ts:608` |
| 손님의 **외상 내역** | 💵 아이콘 → `/cuentas-corrientes/:id` 로 **POS 를 떠난다**. 그리고 외상이 0 이면 아이콘 자체가 안 보인다 | `InfoClient.tsx:802-805, 962-973` |
| COBRAR DEUDA 모달 | 총액·받을 금액만 — 내역 없음 | `DeudaPagoDialog.tsx` |

부수 발견: 외상 원장 훅이 `?limit=100&offset=` 를 보내는데 서버는 `page/pageSize` 를 읽는다 → 실제로는 첫 50행만 온다
(`useCreditClientLedger.ts` ↔ `credit-report.controller.ts:77`). 이번에 같이 고친다.

## 제안 (권고)
### 손님 카드에 「Historial」 버튼 → POS 위에 오른쪽 패널(Drawer), POS 를 떠나지 않는다
- 손님이 선택돼 있으면 **항상** 보인다(외상 0 이어도). 위치: 카드 아이콘 줄, 💵 왼쪽. 아이콘 `tabler:history`.
- 패널 머리: 손님 이름 · 문서 · **Debe $ X** · [COBRAR DEUDA] (지금 버튼과 같은 흐름 `pos:cobrar-deuda`).
- 탭 2개:
  1. **Ventas** — 이 손님의 판매, 최신순, 50개씩 스크롤.
     칸: Fecha · Nº · Total · Pago(결제수단) · Estado(Pagado / Pendiente / Anulada) · Factura(있으면 번호).
     맨 위에 합계 줄: 판매 수 · 총액 · 마지막 구매일.
  2. **Deuda** — 외상 원장(지금 cuentas-corrientes 화면과 같은 데이터): Fecha · Movimiento · Monto · Saldo · Venta #.
     「Ver cuenta completa」 링크 → 지금의 `/cuentas-corrientes/:id` (새 탭).
- 열려 있는 카트는 그대로 — 패널만 닫으면 판매를 계속한다.

### 서버
- 신규 `GET /sales/by-store-client/:storeClientId?page=` — `sales.store_client_id` 기준(운영 store 26: 판매 37,769건에
  채워져 있음, 인덱스 `idx_sales_store_id_store_client_id` 있음). **`store_id = user.storeId` 필수**,
  권한은 기존 `ver-ventas` 와 같게. 50행/페이지.
- 외상 탭은 기존 `GET /credit/clients/:id/ledger` 를 그대로 쓴다(이미 storeId 격리).
- `ver-ventas` 권한이 없는 계산원에게는 Ventas 탭을 숨기고 Deuda 탭만 보인다(서버도 같은 권한으로 거절).

### 대안
- 버튼이 지금의 cuentas-corrientes 페이지로 이동만 하게 하기 — 가장 작지만 POS 를 떠나고 판매 내역이 없다. 권고하지 않음.

## 범위 밖
- 패널에서 판매 재인쇄·취소·수정(Historial de ventas 에서 한다).
- 판매 줄을 눌러 상세 보기 — 1차에서는 안 함(원하시면 2차).

## 영향
- api: 엔드포인트 1개 + spec(매장 격리·권한·페이지). app: InfoClient 버튼 + Drawer 컴포넌트 1개 + 훅 1개, 원장 훅 파라미터 수정.
- DB 변경 없음. 전 매장 공통(손님 카드는 모든 매장 POS 에 있다).
