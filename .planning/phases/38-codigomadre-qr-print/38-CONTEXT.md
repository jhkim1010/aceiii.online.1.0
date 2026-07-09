---
phase: 38-codigomadre-qr-print
type: context
source: brainstorming 2026-07-09
spec: docs/superpowers/specs/2026-07-09-zebra-qr-batch-delta-design.md
status: locked
---

# Phase 38 — CONTEXT (확정 결정 잠금)

브레인스토밍(2026-07-09)으로 확정된 사용자 결정. 계획·실행은 이 결정을 **반드시 준수**한다.
전체 설계: `docs/superpowers/specs/2026-07-09-zebra-qr-batch-delta-design.md`.

## 무엇을 만드나 (한 줄)

zebra-agent 에 **QR 배치·델타 출력 탭(TAB3)** 추가 + 백엔드 델타 API 2개 + 신규 `qr_print_log` 테이블.
운영자가 price-type 선택 → 신규/변경 codigomadre 델타 리스트 → 체크 선택 → Zebra ZPL QR 라벨(1:3) 출력 → 성공분 스냅샷 기록.

## 확정 결정 (LOCKED — 재논의 금지)

- **D-1 위치:** zebra-agent 신규 **TAB3 "QR"** (renderer 탭 + preload IPC + main 핸들러). 웹(CodigoVista)에 트리거 **없음**.
- **D-2 프린터:** **Zebra 접착 라벨(zebra-agent, ZPL)** 전용. print-agent thermal per-row(2026-06-11 설계)는 **폐기/보류**.
- **D-3 델타 정의:** 이 지점에 print-log 없음(**NUEVO**) OR 현재 이름 ≠ 스냅샷 이름 OR 현재 {선택 price-type} 가격 ≠ 스냅샷 가격(**CAMBIO**). 동일하면 제외.
- **D-4 추적 단위:** **지점(branch)별**. `qr_print_log` 에 `branch_id` 포함. 각 sucursal zebra-agent 가 자기 지점 독립 추적.
- **D-5 price-type:** **배치 전체 단일 선택**. 델타·스냅샷 모두 이 price-type 기준.
- **D-6 QR 페이로드:** `${PUBLIC_WEB_URL}/m/stock?s={storeId}&p={productId}`. storeId/branchId 는 **API key 에서 서버가 도출**(클라이언트 미전송 = 멀티테넌트/IDOR 안전).
- **D-6b 전송 계층 (계획 중 정정 2026-07-09):** REST(`GET/POST /print/qr/*`) 대신 **`/print-agent` 소켓 ack**(`get_qr_pending` / `mark_qr_printed`)로 구현. 이유: zebra-agent 의 유일한 인증 채널은 소켓이고(`handleConnection` 이 API key→`client.data.branchId` 세팅), 기존 에이전트 데이터 요청(`get_price_types`/`get_branches`/`get_stock_today`)이 모두 `emitWithAck` 패턴이며, `print.controller` 는 웹 JWT 전용이라 에이전트 API key 를 못 받음. 데이터 계약(델타/스냅샷)과 D-6 도출 로직은 동일. 기존 `PrintService.buildQrPayload`(정확한 `/m/stock?s=&p=` 조립) 재사용하되 **base/PRECIO 1 = `products.price` 폴백 보강**(현재 prices 행만 읽는 버그 수정).
- **D-7 대상 상품:** codigomadre parent(`isParent=true`)만.
- **D-8 라벨 레이아웃:** ZPL **1:3 좌우 분할** — 좌 1/4 QR, 우 3/4 제품명(굵게, 줄바꿈) + `{priceLabel}: {price}`. 기본 **50×25mm**, 좌측 패널에서 수치 조정.
- **D-9 출력 단위:** **1개씩(simple) / 2개씩(doble = 같은 상품 2장, 리스트 N → 2N장)** 토글.
- **D-10 TAB3 UI:** 2패널 — 좌 = 라이브 프리뷰 + 수치 조정(폭/높이/QR 모듈/1:3 비율/폰트), 우 = 델타 리스트(NUEVO/CAMBIO 뱃지 + 체크박스). 다크네이비(#1a1a2e)+골드(#f5a623).
- **D-11 스냅샷 시점:** 출력 **성공한 항목만** `qr_print_log` upsert(부분 실패 안전 — 실패분은 다음 배치 재등장).

## 계약/회귀 주의

- QR 포맷은 Phase 37 `mobile-sales-app/lib/features/scanner/views/qr_scanner_sheet.dart` 파서와 **정확히 일치**해야 함(`/m/stock?s=&p=`). 바뀌면 스캔 깨짐 → 회귀 검증.
- PG pool 보호: pending 델타는 N+1 금지(상품·가격·로그 최소 쿼리 세트). codigomadre 수 제한적.
- 마이그레이션 `phase38-qr-print-log.sql` PG10/PG15 호환(멱등), 운영 PG10 수동 적용 RUNBOOK.
- zebra-agent 변경 → `build-zebra-agent.yml` 태그 자동 증가(push-both.sh).

## 재사용할 기존 자산 (재발명 금지)

- `zebra-agent/src/zpl-formatter.js` — QR ZPL(`^BQN,2,{mag}^FDQA,{value}`) 케이스 이미 존재.
- `zebra-agent/src/zebra-printer.js` — `sendZpl` TCP9100/USB.
- `zebra-agent/renderer/index.html` TAB1/TAB2 + `preload.js` label IPC 패턴.
- `zebra-agent/mockups/etiqueta-2panel-mockup.html` — 2패널 UI 참고.
- 백엔드 `api-ventago/src/app/print/` gateway/service/controller(API key 인증) + barcode 패턴.
- 가격 모델: base(PRECIO 1)=`products.price` 컬럼, 그 외=`prices` 행(product_id+price_type_id).
