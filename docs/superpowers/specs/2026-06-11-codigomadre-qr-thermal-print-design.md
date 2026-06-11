# 설계: CodigoMadre QR 감열 출력

생성일: 2026-06-11
상태: 승인됨 (사용자 승인 2026-06-11)
유형: 신규 Phase 후보 (milestone v1.1) — 데스크탑 QR 출력 (Half A)

## 목표

CodigoVista(precios) 의 CodigoMadre View 에서 각 parent 행에 QR 출력 버튼을 추가하여,
print-agent(감열/ESC-POS)로 **QR + 코드 + 제품명 + 가격** 라벨을 출력한다. QR 은 딥링크 URL 을
인코딩하며, 나중에 판매원 앱(Phase 37)이 스캔하면 그 제품의 지점별 재고를 변형 테이블로 보여준다.

**범위 결정 (brainstorming 2026-06-11):**
- 이 Phase = **Half A (데스크탑 QR 출력)** 만. 지금 구축 가능, Phase 37 무관.
- **Half B (판매원 앱 스캔 → `/m/stock` 해석 → 크로스 지점 변형 재고 뷰)** 는 **Phase 37 mobile 범위로 편입** (mobile-sales-app 미구축).

## 확정 결정

- **D-1 범위:** 데스크탑 QR 출력만 (Half A). 모바일 스캔은 Phase 37.
- **D-2 QR 페이로드:** 딥링크 URL `https://ventago.coolsistema.com/m/stock?s={storeId}&p={parentProductId}` (운영). storeId 로 멀티테넌트 안전, 웹 fallback 가능. `/m/stock` 라우트 해석은 Phase 37.
- **D-3 라벨 내용:** QR(대) + CodigoMadre 코드 + 제품명 + 가격.
- **D-4 가격:** **출력 시 사용자가 price-type 선택** (Popover).
- **D-5 출력 파이프라인:** 접근법 A — print-agent 가 HTML 에서 QR 생성 → 기존 `renderHtmlToPng`(576px) → `printImage` 파이프라인 (fiscal 영수증과 동일).

## 배경 / 코드 맵 (탐색 2026-06-11)

- **CodigoVista:** `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` (2473줄 모놀리식). `showOnlyParents` 토글 = CodigoMadre view. 행은 `filtered.map()` 인라인 JSX(~line 1423). 행 item: `{id, code(sku), name, productId, parentId, isParent, basePrice, prices[]}`. 현재 행별 액션 버튼 컬럼 없음 — WP 토글 셀이 가장 가까운 패턴. `VariationPanel.tsx` 가 변형 표시.
- **print-agent:** Electron. 파이프라인 = payload → HTML → `renderHtmlToPng(html, 576)`(오프스크린 BrowserWindow, 80mm) → `printImage(pngBuffer, config)`. `main.js` 에 `print_temp/print_invoice/print_fiscal/print_barcode` 핸들러. **네이티브 ESC/POS QR 미사용** — QR 은 HTML 에 넣어야 함. 신규 `print_qr` 핸들러 추가 지점.
- **백엔드 print 디스패치:** `api-ventago/src/app/print/` — `print.gateway.ts`(namespace `/print-agent`, room `branch:{branchId}`, API key 인증), `print.service.ts`(`emitPrintBarcode(branchId, data, agentId?)` 등 emit), `print.controller.ts`(`POST /print/barcode` 등). 신규 `POST /print/qr` + `emitPrintQr` 는 barcode 패턴과 동일.
- **데이터 모델:** `Product.isParent`(codigoMadre) + `parentId`(변형). `ProductBranch`(productId+branchId). `Stocks` append-only 원장(SUM per product_branch_id). 크로스 지점 재고 쿼리 존재(`productStock.service`), `GET /products/:id/live-stock?branchId=` 존재(vendedor 접근). → Half B 의 기반(Phase 37 에서 사용).
- **mobile-sales-app:** 미존재. Phase 37 미실행. Half B 전적 의존.

## 컴포넌트 설계

### 1. 프론트엔드 — `CodigoVistaView.tsx`
- CodigoMadre view 의 parent 행에 액션 셀(IconButton `tabler:qrcode`) 추가 (`e.stopPropagation()`).
- 클릭 → price-type 선택 Popover (`usePriceTypes` SWR 재사용).
- 선택 확정 → `apiConnector.post('/print/qr', { branchId, parentProductId, priceTypeId })`. `branchId` = BranchContext `selectedBranchId`.
- 성공/실패 토스트 + 인라인 에러 (에러 가시성 규약). 에이전트 오프라인 등 노출.
- 버튼은 parent 행만. ESLint 엄격 규약 준수(newline-before-return / lines-around-comment / no-unused-vars).

### 2. 백엔드 — `print` 모듈
- `POST /print/qr` body `{ branchId, parentProductId, priceTypeId, agentId? }`:
  - Product 조회(code/name) + priceType 가격 조회.
  - 딥링크 URL 조립: `https://ventago.coolsistema.com/m/stock?s={storeId}&p={parentProductId}` (운영) / dev 호스트 치환.
  - `PrintService.emitPrintQr(branchId, payload, agentId?)` → `gateway.server.to('branch:{branchId}').emit('print_qr', payload)`.
  - payload: `{ qrUrl, code, name, price, priceLabel, storeName? }`.
  - 권한: 기존 print 컨트롤러 가드 posture 일관.
- Jest: `emitPrintQr` 룸/페이로드 emit 검증, URL 조립 + 가격 조회 단위.

### 3. print-agent — `print_qr` 핸들러
- `main.js` `wsConnection.on('print_qr', payload)` → HTML 빌더(QR `qrcode` JS) → `renderHtmlToPng(html, 576)` → `printImage`.
- 레이아웃: 중앙 큰 QR + 아래 코드(굵게) + 제품명 + `priceLabel: 값`.
- `qrcode` npm 의존성 1개 추가 (또는 HTML 인라인 경량 라이브러리).
- 순수 HTML 빌더 함수 단위 테스트.

### 4. 출력 라우팅
- 현재 지점(`selectedBranchId`) thermal 에이전트로 emit. 다중 시 `branch:{branchId}` 룸 또는 `agentId` 지정 (terminal.thermalAgentId 매핑 활용 가능, barcode 패턴 동일).

## 데이터 흐름

```
CodigoVista parent 행 [QR 버튼]
  → price-type Popover 선택
  → POST /print/qr { branchId, parentProductId, priceTypeId }
  → PrintController → PrintService.emitPrintQr
      (Product/가격 조회 + 딥링크 URL 조립)
  → gateway emit 'print_qr' → branch:{branchId} room
  → print-agent on('print_qr')
      → HTML(QR+코드+명+가격) → renderHtmlToPng(576) → printImage
  → 감열지 출력
```

## 에러 핸들링

- 에이전트 오프라인/미연결: emit 실패 또는 ack 없음 → 프론트 타임아웃 시 에러 토스트.
- parentProductId/priceTypeId 무효: 백엔드 404/400 + 프론트 인라인 Alert.
- print-agent 렌더/출력 실패: agent 로그 + (가능 시) 백엔드로 ack 에러.

## 테스트 전략

- 백엔드 Jest: emitPrintQr emit 인자 + URL 조립 + 가격 조회.
- print-agent: HTML 빌더 순수 함수(QR/코드/명/가격 포함) 단위.
- 프론트: 버튼 parent-only 노출 + price-type 선택 → POST 인자 검증. ESLint 0.

## 범위 외 (Phase 37 편입 / YAGNI)

- 모바일 앱 QR 스캔 + `/m/stock` 라우트 해석 + 변형 테이블 크로스 지점 재고 뷰 → **Phase 37**.
- zebra-agent(ZPL) 무관 — print-agent(감열) 전용.
- QR 일괄 출력(여러 codigoMadre 동시) — MVP 후 검토.

## 의존성

- 프론트: `usePriceTypes`, BranchContext `selectedBranchId`, `apiConnector.post`.
- 백엔드: print.gateway/service/controller (기존), Product/PriceType 모델.
- print-agent: 기존 `renderHtmlToPng`/`printImage` 파이프라인 + `qrcode` 신규 의존성.
- CI: print-agent 변경 시 `build-print-agent.yml` 태그 자동 증가 (push-both.sh).

*Brainstorming 설계 완료 2026-06-11. 신규 Phase 로 로드맵 등록 예정 (gsd-add-phase).*
