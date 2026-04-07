---
phase: 11
plan: 06
title: "Wave 6 — Nueva Venta 'Imprimir Temp' 임시 티켓 출력"
status: complete
requirements: ["PRINT-01"]
key-files:
  created:
    - ventago-app/src/services/print.service.ts
  modified:
    - print-agent/src/formatter.js
    - print-agent/main.js
    - api-ventago/src/app/print/print.controller.ts
    - ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx
commits:
  - worktree: ddac242  # feat(11-06): add formatTempTicketHtml and wire print_temp handler
  - api-ventago: 146f5e0  # feat(11-06): reject empty cart on POST /print/temp
  - ventago-app: c43a109  # feat(11-06): add printTempTicket frontend helper
  - ventago-app: c3db5e2  # feat(11-06): add Imprimir Temp button to PaymentSummary
metrics:
  tasks_auto: 4
  tasks_checkpoint: 1
  duration_minutes: ~25
  completed_date: 2026-04-07
---

# Phase 11 Plan 06: Nueva Venta "Imprimir Temp" 임시 티켓 출력 — Summary

POS 'nueva-venta' 화면에 카트 스냅샷을 80mm 감열지에 견적용 임시 티켓으로 출력하는 'Imprimir Temp' 버튼을 추가했다. 판매번호/결제수단 없이 출력되며 DB 기록도 없고 Print Agent 오프라인 시에도 POS 흐름은 차단되지 않는다.

## 빌드 결과 (Task 1-4)

| Task | 상태 | 검증 |
|------|------|------|
| 1. Print Agent: formatTempTicketHtml + print_temp 핸들러 | done | smoke test (banner/Forma de Pago/Copia 검사) PASS |
| 2. 백엔드: POST /print/temp 빈 카트 거부 | done | tsc --noEmit clean |
| 3. 프론트엔드 print.service.ts (printTempTicket 헬퍼) | done | tsc --noEmit clean |
| 4. PaymentSummary 'Imprimir Temp' 버튼 | done | tsc + ESLint clean |
| 5. 수동 E2E smoke (checkpoint:user) | **pending user verification** | — |

## 무엇을 만들었나

### print-agent
- `src/formatter.js`: `formatTempTicketHtml(data)` 함수 추가. `formatInvoiceHtml`과 동일한 576px 레이아웃을 그대로 재사용하되 (1) 최상단 배너 → `TICKET PROVISORIO — DOCUMENTO DE CORTESÍA`, (2) `Copia (N) : # ...` 행 → `Presupuesto — {fecha} {hora}`, (3) Forma de Pago 섹션 완전 생략, (4) 푸터 → `Documento de cortesía / No válido como comprobante`. `module.exports`에 신규 함수 추가.
- `main.js`: 상단에 `formatTempTicketHtml` import 추가, 소켓 핸들러 블록 끝(print_fiscal 다음)에 `print_temp` 핸들러 신규 추가. `formatTempTicketHtml → renderHtmlToPng → printImage` 파이프라인. fire-and-forget — 실패는 broadcastLog에만 기록하고 print_ack를 emit하지 않으며 예외를 던지지 않는다.

### api-ventago
- `src/app/print/print.controller.ts`: `POST /print/temp` 핸들러 본문 시작 부분에 빈 카트 거부 검증 추가. `body.items`가 배열 아니거나 길이 0이면 `{ ok: false, error: 'items requerido (carrito vacío)' }` 반환. branchId fallback 로직(body → JWT user.branchId → user.sucursalId)은 그대로 유지.

### ventago-app
- `src/services/print.service.ts` (신규): `TempTicketPayload` 인터페이스 + `printTempTicket(payload)` 헬퍼. `apiConnector.post('/print/temp', payload)`을 try/catch로 감싸 네트워크/Agent 오류를 `{ ok: false, error }`로 정규화 — 호출부에서 throw 처리할 필요 없음.
- `src/views/homes/components/ProductList/components/PaymentSummary.tsx`: `Total:` 행 바로 아래에 outlined 'Imprimir Temp' 버튼 추가. 카트 비었거나 진행 중일 때 disabled. 1초 debounce로 더블 클릭 방지. 성공 시 `toast.success('Ticket provisorio enviado')`, 오프라인 시 `toast('Print Agent desconectado', { icon: '⚠️' })`. 절대 throw하지 않으므로 POS 화면 정상 사용 가능. `confirmar venta` 로직은 전혀 건드리지 않음.

## 미세 사항 처리 (plan-checker minor fixes)

1. **할인 정규화 드리프트 방지** — `useSaleTotal()`이 이미 화면에 표시되는 `subtotal`/`total`을 계산하므로 페이로드의 `totals`는 그 값을 그대로 재사용했다. 개별 할인 행은 화면 JSX(121-143행)와 동일한 `discountType === 'porcentaje' ? subtotal * (raw/100) : raw` 공식으로 정규화하여 amount로 전달. 백분율과 절대 금액이 화면과 영수증에서 동일하게 표시된다.
2. **react-hot-toast 사용 결정** — `grep` 결과 `react-hot-toast`는 프로젝트 표준이며 최소 18개 뷰에서 import 되어 있다(BoxSummaryCard, ModalOperation, ModalUser 등). `<Toaster />`는 이미 어딘가에 마운트되어 있다고 판단하고 `import toast from 'react-hot-toast'`를 그대로 사용. 신규 토스트 시스템 도입 없이 기존 코드 컨벤션을 따랐다.
3. **useAuth 스키마 확인** — `api-ventago/src/app/auth/auth.service.ts`의 `/me` 응답 빌더를 확인한 결과 `branchId`, `storeName`, `aliasName`, `logoUrl`은 존재하지만 `storeAddress`/`storePhone`/`storeCuit`는 노출되지 않는다. 따라서 페이로드에는 `branchId`, `storeName`, `logoUrl`만 포함하고 주소/CUIT는 백엔드 `/print/temp`가 `branchId`로 자체 조회하도록 의존(`emitPrintTemp`가 store 데이터를 hydrate한다고 가정). undefined 필드 송신을 피해 깔끔한 페이로드 유지.

## 계획과의 편차

- **plan 가정 vs 실제 코드 상태:** 플랜은 `POST /print/temp`와 `print-agent/main.js:500` `print_temp` 핸들러가 이미 존재한다고 가정했으나, `api-ventago` HEAD가 Wave 11-04 (`6f1df4a`)에 머물러 있어 `/print/temp` 라우트와 print_temp 소켓 핸들러 둘 다 **존재하지 않았다**. 두 가지 모두 본 Wave에서 신규 작성했다 (Rule 2 — missing critical functionality). main.js에는 print_fiscal 핸들러 다음 위치에 새 핸들러 블록을 추가했다.
- **plan-checker가 명시한 1초 debounce + ESLint newline-before-return 규칙**은 모두 준수.

## 알려진 stub / 후속 작업

없음. 모든 데이터는 실제 카트 상태에서 빌드되며 mock/placeholder는 사용하지 않는다.

## Task 5 — 사용자 수동 smoke 필요

다음은 자동화 불가능하며 사용자 수동 검증이 필요하다:

1. `npm run dev:api`, `npm run dev:app`, `print-agent` 3개 기동
2. `nueva-venta` 진입 → 상품 3개 + 할인 1개 + 추가요금 1개 카트에 담기
3. **'Imprimir Temp' 클릭** → 80mm 프린터에서 다음 확인:
   - 최상단 `TICKET PROVISORIO — DOCUMENTO DE CORTESÍA` 배너
   - 판매번호 (`Copia N / #`) 표기 **없음**
   - 상품 목록, Subtotal/±조정/TOTAL 정상
   - `Forma de Pago` 섹션 **없음**
   - 하단 `Documento de cortesía — No válido como comprobante`
4. **회귀:** 동일 카트로 결제수단 추가 → `Confirmar venta` → 기존 `print_invoice` 티켓이 판매번호/Forma de Pago 포함하여 정상 출력되는지 확인
5. **오프라인 grace:** Print Agent 강제 종료 후 'Imprimir Temp' 재클릭 → 프론트는 warning toast 만 표시, POS 화면 정상 사용 가능

## Self-Check

- [x] `print-agent/src/formatter.js` updated (formatTempTicketHtml exported)
- [x] `print-agent/main.js` updated (print_temp handler added)
- [x] `api-ventago/src/app/print/print.controller.ts` updated (empty cart guard + /print/temp route)
- [x] `ventago-app/src/services/print.service.ts` created
- [x] `ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx` updated
- [x] Worktree commit: `ddac242` (Task 1)
- [x] api-ventago commit: `146f5e0` (Task 2)
- [x] ventago-app commit: `c43a109` (Task 3)
- [x] ventago-app commit: `c3db5e2` (Task 4)

**Self-Check: PASSED**
