---
phase: 57
slug: facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-20
---

# Phase 57 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest (api-ventago) + tsc typecheck; ESLint (ventago-app) |
| **Config file** | api-ventago/jest.config / tsconfig; ventago-app .eslintrc |
| **Quick run command** | `npx tsc --noEmit -p api-ventago` |
| **Full suite command** | `cd api-ventago && npx jest afip` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx tsc --noEmit -p api-ventago` (touched-file typecheck)
- **After every plan wave:** Run `cd api-ventago && npx jest afip`
- **Before `/gsd-verify-work`:** Full suite must be green + ESLint clean on ventago-app touched files
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 57-01-01 | 01 | 1 | R1/R2 | — | fiscal-formatter renders letra/QR/IVA | manual+snapshot | `node print-agent render test` | ❌ W0 | ⬜ pending |
| 57-02-01 | 02 | 2 | R3/R4 | — | A4 lists real items + IVA discrim | unit | `npx jest afip/a4` | ❌ W0 | ⬜ pending |
| 57-03-01 | 03 | 3 | R5/R6 | — | decideComprobante A/M gate + PV resolution | unit | `npx jest afip/code-maps afip/issuer` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/afip/__tests__/build-factura.spec.ts` — buildFactura unit stubs (R1-R4)
- [ ] `api-ventago/src/app/afip/__tests__/code-maps.spec.ts` — decideComprobante A/M gate (R5)
- [ ] `api-ventago/src/app/afip/__tests__/manager-header.spec.ts` — PV resolution + fallback (R6)

*Manual for ESC/POS visual + QR scan (hardware/homologación) — see Manual-Only below.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ticket ESC/POS letra/QR/IVA impreso | R1/R2 | Requiere print-agent + comprobante homologación | Emitir Factura A y B en homologación, escanear QR del ticket → decodifica a afip.gob.ar/fe/qr con codAut=CAE |
| A4 PDF descarga on-demand | R4 | Requiere UI + navegador | Emitidas ▸ botón "A4 PDF" → descarga sin re-emitir CAE (afip_number invariante) |
| Selector A/M solo RI | R5 | Depende de Cond.IVA render condicional | ModalBranch con RI muestra selector; MONO/EXENTO no |
| PV desde manager /data/header | R6 | Gateway externo vivo | invoice_sucursal seteado → point proviene de branchs[0].point; header caído → fallback local + log |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
