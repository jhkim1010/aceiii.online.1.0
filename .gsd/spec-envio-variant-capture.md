# SPEC: Envío 주문 항목의 색/talle 변형 캡처 보장

생성일: 2026-07-07

## 목표

POS에서 만든 envío(online_order) 항목이 **항상 color × talle 변형 단위**로 저장되게 하여,
창고 준비 앱(despacho-app)의 색×talle 매트릭스가 실제로 채워지도록 한다.

## 배경 / 근거 (진단 완료)

- despacho-app 상세 화면은 **색×talle 매트릭스**를 렌더하도록 구현됨(마스터-디테일). 단, 항목에 color/talle가
  있어야 표가 채워짐.
- 실제 주문 #7 (online_orders.id=12) 조회 결과:
  - `channel=webshop`, `metadata.source='pos'` → **POS EnvioRegistroModal 발**(외부 유입 아님)
  - online_order_items: `JEAN aves | color=NULL | size=NULL | quantity=12` **단일 라인** — 변형 정보 없음
- 원인 후보: `EnvioRegistroModal.buildEnvioItems`는 `p.isParent===true && p.variantQuantities && stockByVariant`
  일 때만 변형별 라인으로 분해한다. JEAN이 **código madre(변형) 없이 단순 상품처럼 카트에 추가**되면
  variantQuantities가 없어 단일 라인이 된다.

## 조사 태스크 (Plan)

- [ ] I-1: POS 카트(SaleProducts/products[]) 에 apparel 상품이 들어가는 경로 확인 —
  código madre(BasicDataCard/VariantsStock) vs 단순 추가. 어느 쪽이 variantQuantities/stockByVariant를 채우나?
- [ ] I-2: `EnvioRegistroModal`로 넘어오는 `cartProducts`에 variantQuantities가 실제로 실리는지(런타임/로그) 확인.
- [ ] I-3: 단일 상품(변형 없는 진짜 단순품)과 apparel(변형 필수) 구분 기준 정의 —
  강제 변형 선택이 필요한 상품군(카테고리/hasVariants 플래그?) 파악.

## 수정 방향 (조사 후 확정)

후보 A — **POS 카트 캡처 보강**: envío 대상 apparel 상품은 카트 단계에서 색×talle 수량이 반드시 실리게
  (código madre 흐름 유도). buildEnvioItems 입력이 이미 변형을 담으면 분해는 자동.

후보 B — **EnvioRegistroModal 내 변형 입력**: 카트 상품이 변형 없이 들어온 경우, 등록 모달에서
  색×talle×수량을 입력/확정하게 해서 online_order_items를 변형 단위로 생성.

후보 C — **채널 유입(webshop/ML) 대비**: 외부 주문도 변형 SKU를 online_order_items의 color/size로
  매핑(commerce-connector). (#7은 POS-source라 후보 A/B 우선, C는 후속.)

## 완료 기준

- POS에서 apparel envío 등록 시 online_order_items가 (color,size,qty) 변형별로 저장
- despacho-app 상세에서 해당 주문이 색×talle 매트릭스로 표시됨
- 진짜 단순품(변형 없음)은 기존처럼 단일 라인 유지(회귀 없음)

## 금지 / 주의

- 기존 online_order 생성/상태전이/mirror sale 로직 변경 금지 — 항목 구성(items[]) 캡처만 보강
- 소급 데이터(#7 등 이미 null인 항목)는 변형 복원 불가 — 신규 주문부터 적용
- ESLint(Warning=Error), pool 규칙 준수

## 산출물

- 조사 리포트(I-1~I-3) → 후보 A/B/C 중 확정 → 구현 + despacho-app 검증
