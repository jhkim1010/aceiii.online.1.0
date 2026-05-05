# Sketch Manifest

## Design Direction

Ventago POS — 다크 네이비 (#0f0f1e bg / #1a1a2e surface) + 골드 (#f5a623) 톤을 모든 신규 화면 / 모달 / 영역에 일관되게 적용한다.
print-agent / zebra-agent 의 Electron 윈도우와 시각적으로 같은 계열로 묶어, 사용자가 멀티-앱 환경에서 항상 "Ventago"임을 즉각 인지하게 만든다.
MUI 5 컴포넌트 패턴과 1:1 매핑 가능한 클래스명 사용 (구현 단계 마찰 최소화).

특수 톤:
- **Mercadopago brand (cyan #00b1ea)** — MP 관련 UI 요소 highlight (배지, 체크박스, 행 강조)
- **Sandbox / warning (orange #f5a623)** — 골드 톤과 동일 — 운영자가 "테스트 환경"이라는 사실을 즉시 인식
- **Error (red #ef4444)** — 인라인 Alert + 글로벌 토스트 동시 노출 (memory: feedback_error_visibility)

## Reference Points

- **Ventago print-agent / zebra-agent** — 다크 #1a1a2e + 골드 #f5a623 (CLAUDE.md 명시)
- **Material UI 5** — 모든 신규 컴포넌트 베이스
- **Mercadopago brand color** — cyan #00b1ea (MP 관련 시각적 단서)
- **MUI Alert / Toast** — 에러 노출 패턴 (이미 ESLint warning=error + 글로벌 axios interceptor 와 통합)

## Sketches

| # | Name | Design Question | Winner | Tags |
|---|------|----------------|--------|------|
| 001 | phase-29-mp-qr-suite | Phase 29 의 5개 UI 영역이 일관성 있게 작동하는가? + QR 결제 모달의 inline / side-panel / dialog 비교 | ✅ qr=**B** Side-panel · caja=**A** Highlighted row · areas 1/3/5 locked | phase-29, mercadopago, qr, oauth, modal, control-de-caja, refund, sandbox, multi-area |
