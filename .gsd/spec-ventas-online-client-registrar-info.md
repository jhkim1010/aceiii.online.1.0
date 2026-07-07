# SPEC: Ventas Online — 고객 이름/주소 카드 표시 + 등록 컨텍스트(vendedor/terminal/caja)
생성일: 2026-07-07

## 목표
Despacho 보드 카드와 상세에 고객 이름·주소가 항상 나오게 하고,
상세에 "누가/어느 터미널/어느 카하에서" 등록했는지 표시한다.

## 배경 (원인 분석)
- POS 발 주문(createFromPos)이 client_id 는 저장하지만 client_name 을 NULL 로 남김
  → 보드/상세는 order.clientName 만 읽으므로 "Cliente indefinido".
- 이름 데이터는 store_clients → global_clients.fullname 에 존재 (로컬 확인 완료).
- 등록 컨텍스트는 metadata.createdByUserId 만 있고 이름/터미널/카하 없음.
- (부속 발견) 운영/로컬 Ventas Online 화면 차이 = stores.use_envios 분기
  (true=Despacho 칸반 3탭 / false=레거시 Pedidos·Envíos·Devoluciones).

## 태스크 목록
- [x] TASK-1 (api): create() — resolveClientDisplayName() 헬퍼로 client_name 저장 (모든 채널 공통).
- [x] TASK-2 (api): createFromPos() — metadata 에 createdByName/terminalId/terminalName/boxName 저장.
- [x] TASK-3 (api): migrations/20260707-backfill-online-orders-client-name.sql — 로컬/운영 적용 대기.
- [x] TASK-4 (front): 카드는 이미 clientName+address 렌더 — 데이터 픽스로 해결 (코드 변경 불필요).
- [x] TASK-5 (front): EnvioTimeline — "Registrado por: vendedor · Terminal · Caja" 라인 추가.
- [x] TASK-6: front ESLint 통과, api TS transpile 통과.

## 완료 기준
- 신규 POS 주문: 카드에 이름+주소, 상세에 등록 컨텍스트 표시.
- 기존 주문: backfill 후 이름 표시.
- ESLint 오류 0 (front), pool 추가 부담 없음 (생성 시 조회 1~2회 추가뿐).

## 금지사항
- 보드 조회 경로에 JOIN 추가 금지 (읽기 hot path — 쓰기 시점에 저장으로 해결).
- 운영 DB UPDATE 는 사용자 승인 후 실행.
