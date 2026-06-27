# SPEC: nueva-venta 고객 카드 — Crédito / Envío 바로가기 버튼

생성일: 2026-06-26

## 목표
nueva-venta 화면에서 고객을 선택했을 때, 그 고객에게 (a) 외상(crédito)이 있으면 외상 확인 화면으로,
(b) 미배송 온라인 envío 가 있으면 Ventas Online 화면으로 바로 이동하는 조건부 버튼을 InfoClient
컴팩트 카드에 추가한다.

## 배경 및 컨텍스트
- 카드 컴포넌트: `ventago-app/src/views/homes/components/InfoClient.tsx` (컴팩트 카드 line 600~712)
- 잔액 배지: `ventago-app/src/views/homes/components/CreditBadges.tsx`
  - 이미 `useCreditClientSummary(storeClientId)` 로 creditBalance/seniaBalance/favorBalance/creditStatus 보유
  - `onClickLedger?` prop 존재하나 InfoClient 에서 미전달 → 클릭 동작 없음
- 외상 화면: `/cuentas-corrientes/[clientId]` → `ClientLedgerView storeClientId={id}` (storeClientId 사용)
- 온라인 주문: `online_orders.clientId`(= legacy clients.id FK, nullable). 미배송 상태 =
  pending/confirmed/preparing/shipped (delivered/cancelled/returned 제외)
- Ventas Online: `/ventas-online` → use_envios 게이트
  - true: EnviosControlCenter (Despacho 칸반 + Cuentas + Historial)
  - false: LegacyVentasOnline (**변경 금지, RD-12 회귀-0**)
- DespachoBoard 는 `useDespachoBoard(branchId)` 로 cards 전체를 클라이언트에 보유. card.clientName 존재.

## 결정 (사용자 확정)
- D-1: 외상 버튼 노출 = CreditBadges 가 이미 가진 creditBalance > 0 (추가 API 없음).
- D-2: Envío 버튼 노출 = 고객별 미배송 envío 건수 > 0 (가벼운 count API 1개 추가).
- D-3: Envío 바로가기 대상 = `/ventas-online` (Despacho 탭). document query 전달.
- D-4: Despacho 칸반에 고객 검색창 추가 + `?search=<document or name>` query 자동 적용
       (클라이언트 측 card.clientName 필터링 — 신규 API 불필요, pool 영향 0).

## 기술 스택
- 백엔드: NestJS + Sequelize. online-orders 모듈. count 는 `model.count({ where })` (pool.connect 직접 호출 X).
- 프론트: Next.js 13 Pages Router + MUI 5 + SWR.
- ESLint: 프로젝트 규칙(warning=error). newline-before-return, lines-around-comment 주의.

## 태스크 목록 (완료 2026-06-26)
- [x] TASK-1: 백엔드 — 고객별 미배송 envío count 엔드포인트
      - `GET /online-orders/pending-count?clientId=N` → { count }
      - service: `countPendingByClient(storeId, clientId)` = orderModel.count({ where:{ storeId, clientId,
        status: { [Op.in]: [pending,confirmed,preparing,shipped] } } })
      - 파일: online-orders.controller.ts, online-orders.service.ts
      - pool: count() 는 pool.query 자동 반환 경로 — release 누락 위험 없음
- [x] TASK-2: 프론트 — SWR 훅 `usePendingEnvioCount(clientId)`
      - 파일: ventago-app/src/hooks/api/usePendingEnvioCount.ts (신규)
      - clientId null 이면 요청 안 함(키 null). dedup 으로 중복 호출 방지.
- [x] TASK-3: 프론트 — InfoClient 컴팩트 카드에 버튼 2개 추가
      - Crédito 버튼: creditBalance>0 시 노출 → router.push(`/cuentas-corrientes/${storeClientId}`)
        (CreditBadges onClickLedger 로도 동일 이동 연결)
      - Envío 버튼: usePendingEnvioCount>0 시 노출 → router.push(`/ventas-online?search=${document}`)
      - 파일: InfoClient.tsx
- [x] TASK-4: 프론트 — Despacho 보드 검색 + query 자동적용
      - DespachoBoard 상단에 검색 TextField 추가, card.clientName(+document if present) 필터.
      - router.query.search 초기값으로 검색어 세팅(useRouter).
      - 파일: DespachoBoard.tsx
- [x] TASK-5: ESLint 검증 (변경 파일 전체)
- [x] TASK-6: 빌드/타입 체크 + 마지막 로그 확인

## 완료 기준
- ESLint 오류 0개
- 외상 0 / envío 0 인 고객은 버튼이 안 보임(잡음 없음, 기존 카드와 동일 레이아웃)
- 새 백엔드 엔드포인트는 count 만 사용(행 fetch X), pool.connect 직접 호출 없음
- 레거시 Ventas Online 경로(use_envios=false) 코드 무변경

## 금지사항 / 주의사항
- LegacyVentasOnline 및 Phase 27 레거시 경로 일절 변경 금지(RD-12 회귀-0).
- online_orders 는 store_client_id 가 아닌 clientId(legacy clients.id) 사용 — 혼동 주의.
- CreditBadges 의 storeClientId 와 envío 의 clientId 는 다른 키. 카드에서 둘 다 추출 필요.
- pool 절약: Despacho 검색은 클라이언트 필터(신규 API X). count 만 신규.
