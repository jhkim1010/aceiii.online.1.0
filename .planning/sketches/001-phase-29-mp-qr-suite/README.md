---
sketch: 001
name: phase-29-mp-qr-suite
question: "Phase 29 의 5개 UI 영역이 Ventago 다크-네이비 + 골드 톤에서 일관성 있게 작동하는가? 결제 모달의 QR 배치는 inline / side-panel / dialog 중 어떤 패턴이 가장 자연스러운가?"
winner: null
tags: [phase-29, mercadopago, qr, oauth, modal, control-de-caja, refund, sandbox, multi-area]
---

# Sketch 001: Phase 29 MP QR Suite

## Design Question

Phase 29 (POS Mercadopago — QR Dinámico) 의 5개 UI 영역이 한 디자인 시스템 안에서 일관되게 작동하는지 시각적으로 검증한다.
특히 결제 모달의 QR 배치 패턴(inline / side-panel / 별도 dialog)을 비교해서 어느 흐름이 POS 운영자에게 가장 자연스러운지 판단한다.

## How to View

Launch preview panel 에서 직접 보거나:

```
open .planning/sketches/001-phase-29-mp-qr-suite/index.html
```

상단 탭 5개로 영역 전환. 각 영역 내부에서 variant 비교 가능. 우측 하단 toolbar 에서 viewport (375 / 768 / 1280 / full) 토글.

## Areas (top-level tabs)

| # | 영역 | CONTEXT.md 참조 | Variants |
|---|-----|----------------|----------|
| 1 | Configuración › Mercadopago | D-A4-04, D-A1-02, D-A1-04 | 단일 (locked layout) |
| 2 | PaymentSummaryModal + QR Dinámico | D-A4-01, D-A4-02 | **3** — Inline / Side-panel / Dialog |
| 3 | Sandbox 시각 indicator | D-A4-02 | 단일 (banner + 모달 borde 비교) |
| 4 | Control-de-caja › Caja MP | D-A3-01, D-A3-03, D-A3-04 | **2** — Highlighted row / Sectioned |
| 5 | SalesDetailView › Devolución MP fallida | D-A4-03 | 단일 (locked) |

## What to Look For

**Area 2 (QR variants) — 핵심 결정 포인트:**
- **A: Inline** — QR 이 결제 행 바로 아래 같은 모달 안에서 펼쳐진다. POS 직원이 한 화면에서 다른 결제수단 입력 + QR 모니터링을 동시에 한다. 모달 세로가 길어진다.
- **B: Side panel** — 모달이 가로로 확장돼서 우측 320px 패널에 QR. 좌측 결제수단 영역은 변하지 않음. 가로 화면 POS 에 적합.
- **C: Separate dialog** — QR 이 별도 dialog 로 띄워진다. 결제 모달은 백그라운드에 dimmed. 모바일/타블렛 POS 에 적합.

각 variant 의 상태 cycler ( ⏳ Esperando / ✓ Aprobado / ✗ Expirado ) 로 흐름 확인.

**Area 4 (Caja MP variants):**
- **A: Highlighted row** — 물리 caja 들 사이에 cyan-tinted row 로 표시. 한 테이블에서 모든 자산 한눈에. "Transferir →" 버튼 직접 노출.
- **B: Sectioned** — "💵 Cajas físicas" / "💳 Wallets virtuales" 두 섹션 분리. 개념적으로 깔끔, 행 추가시 확장 용이.

**Area 1 — 자동 작동 확인:**
- Branch toggle 로 "cuenta propia" 활성화/비활성화 시각 변화.
- Renueva 4 días ⚠️ 노란 경고 + "Sucursal Nuñez 3 días ⚠️" 빨간 경고.

**Area 3 — 더블 indicator 정합성:**
- 위쪽 banner 와 아래 모달 borde 가 같은 #f5a623 톤인지.
- Production (cyan) vs Sandbox (orange) 비교 카드.

**Area 5 — 에러 노출 정도:**
- inline Alert + 토스트 + 재시도 버튼 + MP Dashboard 링크 + 시도 history 모두 한눈에 보이는지.
- "Reintentar devolución" 클릭 시 처리 → 토스트 노출 흐름 작동.

## Theme

`.planning/sketches/themes/ventago-dark.css`
- **Bg**: `#0f0f1e` (deeper navy)
- **Surface**: `#1a1a2e` (sidebar tone — print-agent / zebra-agent 와 동일)
- **Primary (gold)**: `#f5a623`
- **MP brand (cyan)**: `#00b1ea`
- **Sandbox = warning** — 동일 #f5a623 사용 (banner / 모달 borde 일관)
- **Danger** `#ef4444` / **Success** `#4ade80`
- **Type**: Roboto + JetBrains Mono (MUI 기본 폰트 체인)
- 모든 컴포넌트는 MUI 5 와 1:1 매핑 가능한 클래스명 (`.mui-card`, `.mui-btn`, `.mui-chip`, `.mui-alert`, `.mui-modal*`, `.mui-toggle`).

## Notable Interactivity

- 5초 단위로 동작하는 `setInterval` 카운트다운 (3분 timer 데모)
- QR state cycler — 동일 모달 안에서 waiting → approved → expired 전환
- Caja MP "Transferir →" / "Detalle" 클릭 → 실제 모달 오픈 (close, 확정 토스트 작동)
- 환불 "Reintentar" 클릭 → 1.4 s 처리 시뮬 → 실패 토스트 자동 노출
- Branch row toggle — 클릭 시 on/off 상태 변경
- Theme switcher + viewport 시뮬 toolbar (우측 하단)

## Notes for Planner

이 sketch 는 CONTEXT.md D-A4-* 의 잠긴 결정을 시각적으로 검증한다. winning variant 선택 후:
- Area 2 winner → `PaymentSummaryModal.tsx` 확장 패턴 결정
- Area 4 winner → `control-de-caja` 페이지 컴포넌트 구조 결정
- Area 1, 3, 5 → CONTEXT.md 결정 그대로 구현

QR SVG 는 mock pattern (의미없는 dot) — 실제 구현은 `qrcode.react` 의 `<QRCodeSVG value={qrData} size={256} level="M">`.

## Status

🟡 검토 대기 — winning variant 선택 후 README frontmatter `winner: "A"|"B"|"C"` 로 마킹.
