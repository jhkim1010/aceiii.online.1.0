# HANDOFF 2026-10-14 (noche) — 다음 세션은 여기부터

## 바로 할 일 (사용자 요청, 미착수)
1. **Historial de ventas — 판매원 이름 옆 배지**: 판매에 descuento 있으면 **노란 원 안 D**, cheque 결제 있으면 **하늘색 원 안 Q**.
   - 위치: `ventago-app/src/views/sales/list/components/DataConfig.tsx` `field: 'seller'` 열(약 283행).
   - 확인할 것: 행 데이터에서 할인 판정(`discountAmount > 0` 또는 `discounts[]`)과 cheque 판정(`salePaymentMethods[].paymentMethod.slug === 'cheque'` 인지 실제 slug 를 DB `payment_methods` 로 확인).
2. **Phase 110 — Anulación 되돌리기**: 계획 `.planning/phases/110-revertir-anulacion-…/110-PLAN.md`. **결정 1~6 사용자 답 대기** — 답 받기 전 구현 금지.
3. **PEDIDO 32** (Print Agent «Actualizar» 가 앱만 닫음) — 계획/목업 미작성. zebra-agent 도 같은 업데이트 구조(`src/updater.js`)라 오늘 릴리스(zebra v1.0.39~42, print v1.2.19)가 매장에 설치되는지와 직결.

## 오늘 배포 완료 (모두 빌드 SUCCESS 확인)
| 항목 | 커밋 / 빌드 |
|---|---|
| Historial de ventas 무한 스크롤(50건씩) | app a5404e18 / #1096 |
| AFIP **자동 발급 영구 금지** (F10 만) — DB 전 매장 false, `AUTO_EMISION_PROHIBIDA` | api 6571dd30 #1157 · app 63bfba34 #1097 |
| Factura B/C 구입자 이름·문서·주소 (CF 문구 유지) | api a63a413a · print-agent v1.2.19 |
| 영수증 있는 판매도 수정 허용(항상 대체 + 확인창) | api a91e5e12 · app 68dbce96 #1098 |
| **Phase 109** 단일 변형 = 부모 코드 (W1 66dd170a, W2 DB 적용, W3 7eeb8118, W4 데이터 267행 + 비활성 5) | #1158 · #1160 |
| 새 코드 **대문자** 트리거 `trg_products_sku_00_mayusculas` (5434·5432) + 조회 대문자화 | 8fb7746e · 370cc26c #1161 |
| 코드 생성 후 POS 목록 다시 받기 (alta 신호 + catalog-version, 인덱스 `idx_products_store_id_id`) | api 370cc26c · app e0eb4474 #1099 |
| 보류 판매: 자식 하나뿐인 마드레 → 그 자식에 예약 (Cache 500 수정) | api b34286b6 #1162 |
| PEDIDO 31 (Zebra Sin precio·Duplicado) | zebra v1.0.41, 매장 답장 완료(resuelto) |
| PEDIDO 33 (Código Madre 다시 켜면 카트 합치기) | app 4b5b2158·444b790a #1101, cmux 확인, 매장 답장 완료 |
| Zebra QR 이름 4줄(v1.0.39/40) · 바코드 라벨 이름 4줄(v1.0.42) | GitHub Actions success |
| Historial: action 열 Ropas 뒤 · Delete(=anular) 버튼 · Anulado 재인쇄 숨김 · Por Estado/Internet 한 줄 · 색상 | #1102~#1105 |

## 미확인 / 주의
- Cache 2501: 목록 재수신은 확인, 화면에서 보이는지는 매장 확인 대기.
- 남은 `-V` 5개(store 6: 1, ACE 4) — 형제 변형 있는 마드레, **의도적으로 유지**.
- store 28 `J532`/`j532` 공존 — 대문자 트리거는 기존 행을 안 건드림. 정리 결정 대기.
- 시험 Factura C #48(Cielo) — 사용자 결정: **유지**(NC 안 함). 판매목록 「Facturar」 버튼 **유지**.
- 메모리 갱신됨: 배포 기준 ≤10명, 자동 발급 금지, 단일 변형 코드 규칙.
- api-ventago 워킹트리의 남의 WIP(cashRegister, offline-sync/*, sales-create.service.ts, offline-cash-target.ts)는 계속 건드리지 말 것.
