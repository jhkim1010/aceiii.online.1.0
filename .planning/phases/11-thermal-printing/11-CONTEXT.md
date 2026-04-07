---
phase: 11
title: "Thermal Printing — VentaGO Print Agent (Electron 데스크탑 앱)"
status: in_progress
depends_on: ["10"]
estimate: 6.5 days
waves: 6
---

# Phase 11: VentaGO Print Agent (Electron 앱)

## 목적

판매 확정 및 AFIP 전자세금계산서 발행 시 80mm 감열 프린터로 자동 출력하는
**독립 데스크탑 애플리케이션**. 비개발자 직원이 더블클릭으로 설치·실행할 수 있어야 한다.

주요 환경: **Windows (우선)**, macOS (지원)

---

## 두 가지 출력 문서

| 문서 | 트리거 | 형식 | 내용 |
|------|--------|------|------|
| **Ticket de Control** | 판매 확정 (`print_invoice`) | 그래픽 (HTML→PNG→ESC/POS) | 매장명, 날짜/시간, 판매번호, 상품 목록, Subtotal, ±조정항목, TOTAL, 결제수단 |
| **Comprobante Fiscal** | AFIP CAE 취득 성공 (`print_fiscal`) | 그래픽 (HTML→PNG→ESC/POS) | 위 내용 + Tipo, Pto.Venta, N°, CAE, Vto.CAE, QR URL 텍스트 |

---

## 그래픽 출력 파이프라인 (핵심)

```
판매 데이터 (JSON)
      │
      ▼
 formatter.js
 formatInvoiceHtml(data)
      │  HTML 문자열 (576px 고정폭)
      ▼
 renderer-engine.js
 renderHtmlToPng(html, width=576)
      │  Electron offscreen BrowserWindow
      │  → capturePage() → PNG Buffer
      ▼
 printer.js
 printImage(pngBuffer, printerConfig)
      │  escpos.Image.load(png)
      │  printer.image(img, 'D24')   ← ESC/POS 래스터
      ▼
 80mm 감열 프린터 출력
```

**왜 그래픽 모드인가:**
- 상품명 2줄 자동 줄바꿈 (`-webkit-line-clamp: 2`)
- Subtotal/+Recargo(파란색)/−Descuento(빨간색)/TOTAL 블록 색상 표현
- 로고, 볼드, 폰트 사이즈 차등 등 현대적 디자인
- 텍스트 모드 ESC/POS로는 불가능한 표현

**80mm 감열지 = 576px @ 203dpi (표준)**

---

## 티켓 레이아웃 (컨트롤 티켓)

```
┌─────────────────────────────────────────┐
│  DOCUMENTO NO VÁLIDO COMO FACTURA       │  ← 최상단 경고 배너 (흰글·검정배경)
├─────────────────────────────────────────┤
│           LA BOUTIQUE                   │  ← 매장명 (대문자·굵게)
│     Av. Corrientes 1234, CABA           │  ← 주소
│          Tel: 11-4567-8901              │
│       CUIT: 30-71234567-1               │  ← CUIT (굵게)
├─────────────────────────────────────────┤
│  Copia (1) : # 00001-00000042           │  ← 티켓 번호 (중앙·굵게)
│  Fecha              06/04/2026          │
│  Hora               14:32:05            │
│  Vendedor           María G.            │
│  Cliente            Juan Pérez          │
│  Doc.               DNI 28.345.678      │
├─────────────────────────────────────────┤
│ Cnt  Descripcion           P.Unit SubTot│  ← 헤더 (검정배경·흰글)
│  2   REMERA PIMA MANGA     45.000 90.000│  ← 2줄 허용
│      CORTA PREMIUM                      │
│  1   PANTALON JEAN SLIM    89.000 89.000│
│  3   MEDIAS DEPORTIVAS     10.000 30.000│
│      PACK x3                            │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│  Subtotal                     209.000   │  ← 굵게
│  + Recargo — Tarjeta 10%    +  20.900   │  ← 파란색
│  − Descuento — Cliente VIP  −  10.450   │  ← 빨간색
│  − Desc. REMERA PIMA        −   5.000   │  ← 빨간색 (상품별 할인)
│  + Envío                    +   2.500   │  ← 파란색
│ ╔═══════════════════════════════════╗   │
│ ║  TOTAL              $  217.950   ║   │  ← 검정 블록·흰글·큰 숫자
│ ╚═══════════════════════════════════╝   │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│  Forma de Pago                          │
│  ★ Tarjeta (VISA Cuotas 3)  217.950    │
├─────────────────────────────────────────┤
│       ★ ¡Gracias x elegirnos! ★        │
│  Cambios solo por falla de fábrica      │
└─────────────────────────────────────────┘
```

---

## Electron 앱 최종 디렉토리 구조

```
print-agent/
├── main.js                     # Electron main process (WebSocket + 트레이 + IPC)
├── preload.js                  # contextBridge (보안 IPC)
├── renderer/
│   ├── index.html              # 설정 화면 (연결상태 + 로그 + 프린터 선택)
│   ├── setup-wizard.html       # 최초 실행 3단계 마법사
│   └── assets/
│       ├── style.css
│       └── logo.png
├── src/
│   ├── formatter.js            # ✅ Wave 1 완료 — HTML 티켓 생성
│   ├── renderer-engine.js      # ✅ Wave 1 완료 — Electron offscreen PNG 렌더
│   ├── print-pipeline.js       # ✅ Wave 1 완료 — 3단계 파이프라인
│   ├── printer.js              # ✅ Wave 1 완료 — ESC/POS 출력 (printImage 포함)
│   ├── fiscal-formatter.js     # Wave 3 — AFIP 영수증 HTML 포맷터
│   └── printer-discovery.js    # Wave 3 — USB + 네트워크 프린터 탐색
├── ticket-preview.html         # 개발용 미리보기 (git 제외 권장)
└── package.json
```

---

## 기존 파일 현황 (Wave 1 완료분)

| 파일 | 상태 | 비고 |
|------|------|------|
| `src/formatter.js` | ✅ Wave 1 완료 | `formatInvoiceHtml()` + `formatInvoice()` fallback |
| `src/renderer-engine.js` | ✅ Wave 1 완료 | 싱글턴 offscreen BrowserWindow, 직렬 큐 |
| `src/print-pipeline.js` | ✅ Wave 1 완료 | `printTicket(data, cfg)` 3단계 파이프라인 |
| `src/printer.js` | ✅ Wave 1 완료 | `printReceipt`, `printImage`, `testConnection` |
| `src/fiscal-formatter.js` | ⏳ Wave 3 | AFIP 영수증 HTML 포맷터 |
| `src/printer-discovery.js` | ⏳ Wave 3 | USB + 네트워크 탐색 |
| `main.js` | ⏳ Wave 2 | Electron 진입점 |
| `preload.js` | ⏳ Wave 2 | IPC 브릿지 |
| `renderer/` | ⏳ Wave 2 | 설정 GUI |

---

## 소계 구역 데이터 계약 (formatter.js 입력 스펙)

```javascript
// data.totals
{
  subtotal:       209000,   // 항상 필수
  discountAmount: 15450,    // optional (총 할인액, 참고용)
  transport:       2500,    // optional (있으면 "+ Envío" 행 표시)
  totalAmount:   217950,    // 최종 합계 (TOTAL 블록)
}

// data.recharges[] — 각 항목이 파란색 "+ Recargo" 행으로 표시
[{ name: 'Tarjeta Crédito 10%', amount: 20900 }]

// data.discounts[] — 각 항목이 빨간색 "− Descuento" 행으로 표시
[{ name: 'Cliente VIP 5%', amount: 10450 }]

// data.items[].discount — 상품별 할인, 빨간색 "− Desc. {name}" 행으로 표시
// (item row에는 표시 안 함 — 소계 구역에만 표시)
```

---

## WebSocket 이벤트 규약

| 이벤트 | 방향 | payload |
|--------|------|---------|
| `print_invoice` | Server → Agent | 컨트롤 티켓 데이터 (위 스펙) |
| `print_fiscal` | Server → Agent | 컨트롤 데이터 + AFIP 필드 (CAE, Vto, QR) |
| `agent_online` | Agent → Server | `{ branchId, version, ts }` |
| `agent_offline` | Agent → Server (disconnect) | — |
| `print_ack` | Agent → Server | `{ invoiceId, status: 'ok'|'error', ts }` |

---

## 주요 의존성

```json
{
  "electron": "^29.0.0",
  "electron-builder": "^24.0.0",
  "electron-store": "^8.1.0",
  "socket.io-client": "^4.7.0",
  "escpos": "^3.0.0-alpha.6",
  "escpos-usb": "^3.0.0-alpha.6",
  "escpos-network": "^3.0.0-alpha.6"
}
```

---

## 성공 기준 (Phase 완료 조건)

1. 판매 확정 시 지점의 print-agent로 `print_invoice` 이벤트 자동 전송 (fire-and-forget)
2. 그래픽 모드 컨트롤 티켓 출력 — Subtotal/+파란색/−빨간색/TOTAL 블록 정상 인쇄
3. CAE 취득 성공 시 `print_fiscal` 이벤트 자동 전송
4. AFIP 영수증 포맷 — CAE, Vto.CAE, QR URL 추가 출력
5. 프린터 미연결 지점에서 출력 이벤트 전송 시 판매/발행 트랜잭션에 영향 없음 (fire-and-forget)
6. Windows NSIS `.exe` 인스톨러, macOS `.dmg` 패키지 모두 빌드 성공
7. 비개발자도 3단계 마법사로 5분 이내 초기 설정 완료 가능
8. 관리자 화면에서 print-agent 온라인/오프라인 상태 실시간 표시
9. 지점별 API Key 관리자 화면에서 확인/복사/재발급 가능

---

## Wave 요약

| Wave | Plan | 작업 | 예상 | 상태 |
|------|------|------|------|------|
| 1 | 11-01 | 그래픽 파이프라인 코어 (formatter + renderer-engine + print-pipeline + printer) | 1일 | ✅ 완료 |
| 2 | 11-02 | Electron 앱 스켈레톤 (main.js + preload.js + 설정 GUI + 셋업 마법사) | 1.5일 | ⏳ 대기 |
| 3 | 11-03 | fiscal-formatter + printer-discovery + WebSocket 루프 + 트레이 로그 | 1.5일 | ⏳ 대기 |
| 4 | 11-04 | 백엔드 PrintService + DB 마이그레이션 + 프론트 설정 UI + electron-builder 패키징 | 2일 | ⏳ 대기 |
| 5 | 11-05 | GitHub Actions 크로스 빌드 + 자동 릴리즈 + 프론트 다운로드 UI | 1일 | ✅ 완료 |
| 6 | 11-06 | Nueva Venta "Imprimir Temp" 버튼 → `print_temp` 임시 티켓 출력 | 0.5일 | ⏳ 대기 |
