# PEDIDO 33 — 「ticket resumido」: Código Madre 를 다시 켜면 카트를 마드레로 묶기

## 요청 원문 요약
- 매장: coolsistema (store 6) · 작성자 israel samuel · 2026-10-14 09:18
- 원문: 「al hacer venta desactivado Codigo Madre para que pueda leer la pistola de código de barra, si se activa
  nuevamente Código Madre no lo agrupa los que se leyeron y al imprimir ticket tampoco (en este caso FRONT CAT)
  lo que produce que el ticket sea largo」
- 사진: 13/10 02:56 영수증 — `FRONT CAT (AMARILLO / M)` 와 `FRONT CAT (NEGRO / S)` 가 따로 한 줄씩(같은 45.000).
- **분류: 개선** (두 부분 — 영수증은 이미 해결, 카트는 미구현)

## 현재 동작
| 부분 | 상태 | 근거 |
|---|---|---|
| **영수증** — Código Madre 꺼짐 + 스캔한 자식들 | **해결됨 (2026-10-14 09:33 배포, front bb596a5b / #1091)**. 같은 마드레 + 같은 단가는 한 줄 + 색상×사이즈 표로 인쇄 | `views/homes/utils/ticket-agrupado.ts` `lineasTicketCarrito` |
| **카트** — Código Madre 다시 켬 | **안 묶임.** 꺼짐(OFF)일 때는 마드레 줄을 자식 가상 행으로 **펼치는** 기능이 있지만(`ProductList.tsx:1737~`), 켤 때 자식 줄을 마드레로 **합치는** 기능은 없다 | 같은 파일 `displayProducts` |

사진의 영수증은 수정 배포(09:33) **전**(13/10 02:56)에 인쇄된 것이다.

## 제안 (권고)
### Código Madre 를 켜는 순간, 카트의 자식 줄을 마드레 한 줄로 합친다
- 같은 **마드레** + 같은 **단가** + 같은 **부호**(판매/반품) 자식 줄 → 마드레 한 줄 1개.
  수량 = 합계, `variantQuantities` = 색상×사이즈별 수량(마드레 줄이 원래 쓰는 형식 — 보류 판매 복원과 같은 형식).
- 합친 줄을 누르면 **지금 마드레 줄과 똑같이** 색상×사이즈 매트릭스가 열리고 칸별 수량을 고칠 수 있다.
- 다시 끄면 지금처럼 자식 가상 행으로 펼쳐 보인다.
- **합치지 않는 줄** (그대로 둔다 — 금액이 바뀔 위험):
  - 단가가 다른 줄 (영수증과 같은 규칙: 단가가 다르면 따로)
  - 줄 할인·수동 가격·가격 승인 토큰이 붙은 줄
  - 마드레가 「costo por variación」(변형별 가격)인 경우
  - 프로모션 줄, 마드레를 카탈로그에서 못 찾은 줄
- 합치기 전·후 **총액이 같아야** 한다 — 다르면 합치지 않고 그대로 둔다(안전장치).

### 대안
- 화면에서만 묶어 보이기(카트 데이터는 자식 줄 그대로). 데이터를 안 바꿔 안전하지만, 묶인 줄을 눌렀을 때
  매트릭스 편집이 자식 줄 여러 개를 고쳐야 해서 편집 경로가 하나 더 생긴다. 권고하지 않음.

## 범위 밖
- 판매 저장 형식은 바뀌지 않는다(서버는 마드레 + variantQuantities 판매를 이미 받는다).
- 영수증 묶기 규칙은 이미 배포된 것 그대로.

## 영향
- 파일: `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`(토글 시점), 새 순수 함수
  `views/homes/utils/agrupar-carrito.ts` (+jest)
- api / DB: 없음 · 다른 매장: Código Madre 를 껐다 켜는 모든 매장(같은 동작)
- 위험: 합치기 규칙이 금액을 바꾸면 안 된다 → 총액 대조 안전장치 + 시험(합치기 전후 총액·수량·반품 부호)

## 규모 · 검증
- 규모 **S~M**
- jest: ① 같은 마드레·같은 단가 2줄 → 1줄, variantQuantities 정확 ② 단가 다름 → 2줄 ③ 반품 줄은 판매 줄과 안 섞임
  ④ 할인 줄 제외 ⑤ 총액 불변 ⑥ costo por variación 제외 · 돌연변이
- cmux: coolsistema POS 에서 FRONT CAT 두 사이즈 스캔(OFF) → ON → 한 줄 + 매트릭스, F2 판매·영수증 확인

## 매장 답장 초안 (승인·배포 후)
> ¡Hola! Ya está: si vendés con «Código Madre» apagado (para la pistola) y después lo volvés a activar, los
> productos del mismo código madre y mismo precio se juntan en una sola línea con su tabla de colores y talles.
> El ticket ya sale agrupado desde el 14/10 (el de la foto es de antes del cambio). Cualquier cosa nos avisás.
