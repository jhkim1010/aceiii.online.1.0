---
phase: 16
slug: control-de-talleres
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-13
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | none — 프로젝트에 자동화 테스트 미구축 |
| **Config file** | tsconfig.json (TypeScript), .eslintrc.js (ESLint) |
| **Quick run command** | `npx tsc --noEmit && cd ventago-app && npx next lint` |
| **Full suite command** | `npx tsc --noEmit && cd ventago-app && npx next lint` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx tsc --noEmit` (TypeScript) + `npx next lint` (ESLint)
- **After every plan completion:** Run full suite

---

## Validation Matrix

| Plan | Task | Automated Command | What It Validates |
|------|------|-------------------|-------------------|
| 16-01 | T1 | `npx tsc --noEmit` | Backend Dashboard API — TypeScript 컴파일 |
| 16-01 | T2 | `cd ventago-app && npx next lint` | Tab Shell + Dashboard Tab — ESLint + 빌드 |
| 16-02 | T1 | `cd ventago-app && npx next lint` | Pipeline Kanban 컴포넌트 — ESLint |
| 16-02 | T2 | `cd ventago-app && npx next lint` | EtapaFlowVisual 컴포넌트 — ESLint |
| 16-03 | T1 | `cd ventago-app && npx next lint` | Talleres 확장 행 테이블 — ESLint |
| 16-03 | T2 | `cd ventago-app && npx next lint` | Lotes 드로어 + Envios 필터 — ESLint |
| 16-04 | T1 | `cd ventago-app && npx next lint` | Liquidaciones 정산 KPI — ESLint |
| 16-04 | T2 | `cd ventago-app && npx next lint` | Etapas 단가 매트릭스 — ESLint |

---

## Coverage Notes

- 프로젝트에 자동화된 단위/통합 테스트 프레임워크 없음
- TypeScript 컴파일(`tsc --noEmit`)과 ESLint가 주요 검증 수단
- UI 기능 검증은 브라우저 수동 확인 필요

---

*Phase: 16-control-de-talleres*
*Created: 2026-04-13*
