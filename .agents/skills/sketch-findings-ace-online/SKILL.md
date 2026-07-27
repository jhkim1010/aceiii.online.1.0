---
name: sketch-findings-ace-online
description: Validated design decisions, CSS patterns, and visual direction from sketch experiments for the Ventago POS/ERP project (ACE_online_1.0). Auto-loaded during UI implementation. Covers theme (Ventago dark navy + gold), Mercadopago integration UI, OAuth configuración pages, payment modal + QR side-panel, sandbox indicators, virtual wallet display in control de caja, and refund failure UX.
---

<context>
## Project: ACE_online_1.0 (Ventago POS/ERP)

다점포 소매업 대상 POS/ERP 시스템. 다크 네이비 (#0f0f1e bg / #1a1a2e surface) + 골드 (#f5a623) 톤을 모든 신규 화면 / 모달 / 영역에 일관되게 적용. print-agent / zebra-agent 의 Electron 윈도우와 시각적으로 같은 계열로 묶어, 사용자가 멀티-앱 환경에서 항상 "Ventago" 임을 즉각 인지하게 만든다. MUI 5 컴포넌트와 1:1 매핑 가능한 클래스명 사용.

특수 톤:
- **Mercadopago brand (cyan #00b1ea)** — MP 관련 UI 요소 highlight
- **Sandbox / warning (orange #f5a623)** — 골드 톤과 동일 — 운영자가 "테스트 환경" 임을 즉시 인식
- **Error (red #ef4444)** — 인라인 Alert + 글로벌 토스트 동시 노출 (memory: feedback_error_visibility)

Sketch sessions wrapped: 2026-05-05
</context>

<design_direction>
## Overall Direction

Ventago 의 모든 신규 UI 는 **다크 네이비 + 골드** 단일 테마. MUI 5 위에서 다음 원칙으로 구현:

- **Layout primitives** — `Card` (`.mui-card`), `Button` (4 variants: primary/outlined/danger/text), `Chip` (success/warning/danger/info/mp/neutral), `Alert` (error/warning/info/success), `Modal` 표준화. 모든 클래스는 MUI 5 Component prop 으로 매핑 가능.
- **Sandbox = primary gold reuse** — 별도 위험 색이 아니라 친근한 "Ventago test mode" 시그널.
- **MP brand cyan** 은 Mercadopago 전용 UI 요소 (배지, 행 강조, production environment 모달 borde) 에만 사용. 일반 info 색이 아님.
- **에러 노출 더블 시그널** — 모든 에러는 인라인 Alert + 글로벌 토스트 동시 (memory: feedback_error_visibility).
- **Mono font (JetBrains Mono)** — 통화 금액, payment_id, timestamp, account ID 모두.
- **Sandbox 표시 더블 시그널** — top banner + 모달 borde (외부 결제 통합 공통).
- **POS 흐름 우선** — split payment 동시 입력 가능, 모달 layout 가로 확장 (1fr + 320px panel) 으로 다른 결제수단 입력 방해 안 함.
</design_direction>

<findings_index>
## Design Areas

| Area | Reference | Key Decision |
|------|-----------|--------------|
| **Theme** | [theme.md](references/theme.md) | Dark navy `#0f0f1e` bg + `#1a1a2e` surface + `#f5a623` gold + `#00b1ea` MP cyan. Roboto + JetBrains Mono. MUI 5 createTheme() 매핑 포함. |
| **Configuración pages** | [configuracion-page.md](references/configuracion-page.md) | 3-section structure: store-level hero card + branch-level toggle table + info alert. OAuth scope (store/branch) 자유 설정. D-7 만료 경고 더블 노출 (글로벌 alert + 행마다). |
| **Payment Modal + QR** | [payment-modal-qr.md](references/payment-modal-qr.md) | Side-panel variant winner — 모달 1fr + 320px grid. 우측 패널 borde 색상으로 sandbox/production 구분. webhook + 5초 polling 양쪽 동시, frontend processedIntentRef guard 필수. |
| **Sandbox Indicator** | [sandbox-indicator.md](references/sandbox-indicator.md) | 더블 시그널: top warning banner (페이지 상단) + 모달 panel border (golden 2px). 색상은 primary gold 재사용 — friendly test signal. |
| **Virtual Wallet (Caja MP)** | [caja-virtual-wallet.md](references/caja-virtual-wallet.md) | Highlighted row variant winner — 물리 caja + 가상 wallet 같은 테이블, cyan-tinted bg 로 구분. "Transferir →" 액션 row 직접 노출. transfer/detail 모달 패턴 포함. |
| **Refund Failure UX** | [refund-failure-ux.md](references/refund-failure-ux.md) | 5개 element 동시 노출: 인라인 Alert + 글로벌 토스트 + 재시도 버튼 + 외부 Dashboard 링크 + attempt history. 자동 재시도 금지 (사용자 액션만). |

## Theme

The winning theme file is at `sources/themes/ventago-dark.css`. CSS variables only — 모든 컴포넌트 스타일은 reference 파일에서 별도 정의.

## Source Files

원본 sketch HTML 파일은 `sources/001-phase-29-mp-qr-suite/index.html` 에 보존. 5개 영역 모두 인터랙티브 mockup (state cycler, 모달 open/close, 카운트다운 작동) — 시각 검증용으로 언제든 다시 열람 가능.

```
open .Codex/skills/sketch-findings-ace-online/sources/001-phase-29-mp-qr-suite/index.html
```
</findings_index>

<usage>
## When to Apply

이 skill 은 다음 상황에 자동 또는 명시적으로 참조:

- **Phase 29 (Mercadopago QR)** — 모든 영역 직접 적용
- **Phase 30 (MP Point 단말기)** — theme + sandbox-indicator + caja-virtual-wallet 재사용. configuracion-page 의 OAuth 패턴 재활용.
- **Phase 31 (MP Online Checkout/Bricks)** — theme + sandbox-indicator + refund-failure-ux 재사용
- **향후 다른 외부 결제 / 통합** — configuracion-page (OAuth) + sandbox-indicator + refund-failure-ux 패턴 재사용
- **신규 dashboard / control 페이지** — theme + caja-virtual-wallet 의 row-highlight 패턴

## How to Apply

1. 새 페이지/컴포넌트 작성 시 우선 `references/theme.md` 의 색상/spacing/typography 변수 사용
2. 영역에 맞는 reference 파일을 읽고 CSS Pattern + React Implementation 섹션 모방
3. `What to Avoid` 섹션의 anti-pattern 회피
4. 의문 시 `sources/001-phase-29-mp-qr-suite/index.html` 의 시각 mockup 으로 직접 비교
</usage>

<metadata>
## Processed Sketches

- 001-phase-29-mp-qr-suite (winners: qr=B side-panel · caja=A highlighted row · areas 1/3/5 locked) — wrapped 2026-05-05

## Project conventions referenced

- AGENTS.md (project root) — Sequelize underscored, ESLint warning=error, apiConnector.remove(), postgres pool 변경 금지
- memory: feedback_error_visibility — 인라인 Alert + 글로벌 토스트 더블 노출 규약
</metadata>
