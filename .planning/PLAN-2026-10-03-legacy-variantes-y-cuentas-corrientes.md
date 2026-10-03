# Legacy import — 빠진 변형(a) · 외상 잔액(b) 계획 (2026-10-03, Shaple store 26)

## (a) 원인 — 실측 (staging `legacy_stage_0000000002`, 운영 조회만)

| | 수 |
|---|---|
| ACE 살아 있는 변형(codigos, borrado=false) | 6,277 |
| Ventago 에 생긴 변형 | 4,812 (+ 건너뜀 8) |
| **`codigoproducto` 가 비어 있어 조용히 건너뛴 변형** | **1,457** |
| 그중 재고가 있던 코드 (② 「sin producto」의 실체) | 1,145 · 양수 재고 **24,951개** |
| 그 변형에 해당하는 판매 줄 (sale_items.product_id = NULL) | **약 296,000** / 798,002 |
| 변형이 하나도 없는 madre (Ventago) | 287 |

- 원인: `legacy-import.service.ts` 변형 루프가 부모를 `codigoproducto`(문자열)로만 찾는다
  (`VARIANT_FIELD_CANDIDATES.parent_sku`). 비어 있으면 `continue` — **오류·카운터 없음**.
  ACE 에는 `ref_id_todocodigo`(madre id) 가 있고 1,457개 전부 **madre 가 정상**이다.
- 영향: ① 그 1,457개 상품은 POS 에서 **팔 수 없다**(검색 대상 아님). ② 재고 24,951개 누락.
  ③ 판매 이력 약 30만 줄이 상품과 끊겨 상품별 보고서에 안 잡힌다.
- 나머지 판매 줄의 상품 미연결: ACE 에서 지워진 코드 43,274 · ACE 에 없는 코드 1,202 — 정상(원본에 없음).
- 카탈로그 「13 filas con error」: code_imports.errors_json 은 `[]`, 변형 건너뜀 8 — 별도 소량.

## (a) 고치는 순서 (제안)

1. **코드**: `codigoproducto` 가 비면 `ref_id_todocodigo → todocodigos.tcodigo` 로 부모를 찾는다
   (그 madre 가 살아 있을 때만). 그래도 못 찾은 변형은 **세서 결과에 보인다**(조용히 사라지지 않게).
2. **Shaple 보정** (운영 쓰기 — 승인 필요):
   - ① 재실행 → 1,457 변형 생성 (기존 상품은 skip 정책이라 안 바뀜).
   - ② 재고: 지금은 「이미 들어갔다」로 거절된다 → **새로 생긴 변형에만** 시작 재고를 넣는
     보충 모드 (이미 재고 이동이 있는 product_branch 는 건드리지 않음).
   - ③ 판매 품목 재연결: 상품이 없던 sale_items 를 legacy 코드로 다시 찾아 `product_id` 채움.
     ★ sale_items 에 legacy 코드가 없다 — 연결 키(판매 legacy id + 줄 순서 또는 custom_name)부터 확인 필요.
3. **다른 매장**: 같은 임포트로 들어간 매장도 같은 손실이 있을 수 있다 — 임포트 이력으로 대상 매장 목록부터.

## (b) 외상(⑤) — 현황과 제안

- ACE `creditoventas` 살아 있는 7,559행 · 고객 637명. `caso` 별: `0,DC`(외상 판매 384,683,669) ·
  `0,C`(153,724,958) · `0,P`(입금 409,136,237) · `FC`(favor) · `Fixed` · `Res/DRes`(예약).
  + `cobranzacab` 8,097 · `cheques` 13 · `online_ventas` 1,898.
- Ventago: `credit_ledger`(sale_credit / payment_in / sale_credit_void / favor…) + `credit_payments`.
  잔액 공식은 4곳에 복제돼 있다(메모리 credit-open-balance-formula).

**권고: 이력 전체가 아니라 「고객별 현재 잔액」 1행씩(기초 잔액)으로 들여온다.**
- 이유: ACE `caso` 의미가 문서화돼 있지 않고(위 7종), 30만 원장 이력을 매핑하면 틀릴 자리가 많다.
  매장이 필요한 것은 「누가 지금 얼마 빚졌나 / 얼마 favor 가 있나」다.
- 방법: 고객별 잔액 = (ACE 가 화면에 보여 주는 식) → `credit_ledger` 에 `opening_balance`
  (외상 = credito 버킷, favor = 음수 credito — 메모리 favor-is-negative-credito) 1행.
- ★ **ACE 화면의 잔액과 대조가 먼저다**: 매장에서 고객 3~5명의 ACE 잔액을 받아 우리 계산과 맞춘 뒤 적재.
- online_ventas 는 상태 이력이라 보류 제안. cheques 13건은 수동 입력 권고.

## 승인 필요
- (a)-1 코드 수정 · (a)-2 Shaple 운영 보정 순서
- (b) 「기초 잔액」 방식 + ACE 잔액 샘플 요청
