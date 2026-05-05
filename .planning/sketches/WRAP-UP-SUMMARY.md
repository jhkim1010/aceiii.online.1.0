# Sketch Wrap-Up Summary

**Date:** 2026-05-05
**Sketches processed:** 1
**Design areas:** Theme + 5 (Configuración pages, Payment Modal QR, Sandbox Indicator, Virtual Wallet, Refund Failure UX)
**Skill output:** `./.claude/skills/sketch-findings-ace-online/`

## Included Sketches

| # | Name | Winner | Design Area |
|---|------|--------|-------------|
| 001 | phase-29-mp-qr-suite | qr=B (Side-panel) · caja=A (Highlighted row) · 1/3/5 locked | Configuración + Payment QR + Sandbox + Caja Virtual + Refund UX |

## Excluded Sketches

(없음 — 1개 sketch 모두 포함)

## Design Direction

Ventago POS — 다크 네이비 (`#0f0f1e` bg / `#1a1a2e` surface) + 골드 (`#f5a623`) 톤을 모든 신규 화면 / 모달 / 영역에 일관되게 적용.
print-agent / zebra-agent 의 Electron 윈도우와 시각적으로 같은 계열로 묶어, 사용자가 멀티-앱 환경에서 항상 "Ventago" 임을 즉각 인지하게 만든다.
MUI 5 컴포넌트와 1:1 매핑 가능한 클래스명 사용 — 구현 단계 마찰 최소화.

특수 톤:
- **Mercadopago brand (cyan #00b1ea)** — MP 관련 UI 요소
- **Sandbox/warning (orange #f5a623)** — 골드와 동일, friendly test signal
- **Error (red #ef4444)** — 인라인 Alert + 글로벌 토스트 더블 노출

## Key Decisions

**Layout & spacing:**
- 8px multiplier scale (4/8/12/16/20/24/32/40/48)
- Card radius 12px / Modal radius 16px / Button radius 8px

**Typography:**
- Roboto sans + JetBrains Mono — 통화 / payment_id / timestamp 모두 mono

**Modal layout (winner):**
- PaymentSummaryModal: side-panel (1fr + 320px grid). 좌측 결제수단 입력 + 우측 QR 모니터링 동시.
- QR `<QRCodeSVG size={180} level="M">` (panel context)
- Border 2px (sandbox=warning gold / production=mp cyan)

**Control de caja (winner):**
- 가상 wallet 을 물리 caja 와 같은 테이블 row 로 표시 (cyan-tinted bg `row-highlight`)
- "Transferir →" 액션 버튼 row 직접 노출
- Sectioned 분리 layout 은 reject (시야 분산)

**Sandbox visualization:**
- 더블 시그널 (top banner + 모달 panel borde) — 둘 다 primary gold
- 빨간/노란 alarm 색 reject — friendly Ventago test signal 가 옳다

**Error UX (refund failure 등):**
- 5개 element 동시: 인라인 Alert + 글로벌 토스트 + 재시도 버튼 + 외부 Dashboard 링크 + attempt history
- 자동 재시도 금지 (사용자 액션만)
- memory: feedback_error_visibility 규약 준수

**Configuración pages:**
- 3-section: hero card (store-level) + table (branch-level toggle) + info alert
- D-7 만료 경고 더블 노출 (글로벌 alert + 행마다)
- Disconnect = text button + confirm dialog (less alarming)

## Re-usable for

- Phase 30 (MP Point 단말기): theme + sandbox-indicator + caja-virtual-wallet 재사용
- Phase 31 (MP Online Checkout): theme + sandbox-indicator + refund-failure-ux 재사용
- 향후 외부 결제/통합 (Ualá, Modo, etc.): configuracion-page (OAuth) + sandbox-indicator + refund-failure-ux 재사용
- 신규 dashboard / control 페이지: theme + caja-virtual-wallet 의 row-highlight 패턴

## Files Created

```
.claude/skills/sketch-findings-ace-online/
├── SKILL.md                                 # Auto-load entry point
├── references/
│   ├── theme.md                             # Color/typography/spacing system + MUI createTheme()
│   ├── configuracion-page.md                # OAuth integration page (3-section)
│   ├── payment-modal-qr.md                  # PaymentSummaryModal side-panel + QR + state flow
│   ├── sandbox-indicator.md                 # Banner + modal borde double signal
│   ├── caja-virtual-wallet.md               # Highlighted row + transfer modal + detail modal
│   └── refund-failure-ux.md                 # Inline Alert + toast + retry + Dashboard link + history
└── sources/
    ├── themes/
    │   └── ventago-dark.css                 # Original CSS variable theme
    └── 001-phase-29-mp-qr-suite/
        ├── index.html                       # Full interactive 5-area mockup (preserved)
        └── README.md                        # Original sketch documentation with winners
```
