---
phase: 57
slug: facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-20
---

# Phase 57 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> All verification is inline (each task carries its own `<automated>` command) — no separate Wave 0 plan required.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Jest `^29.7.0` (ts-jest, api-ventago) + `tsc` typecheck; ESLint `--max-warnings=0` (ventago-app); `node --check` + render harness (print-agent) |
| **Config file** | api-ventago `package.json` (`jest` key, rootDir `src`); ventago-app `.eslintrc` |
| **Quick run command** | `cd api-ventago && npx tsc --noEmit -p .` |
| **Full suite command** | `cd api-ventago && npx jest src/app/afip --silent` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** ejecutar el `<automated>` de la task (jest afip / tsc / eslint / node harness / curl)
- **After every plan wave:** `cd api-ventago && npx jest src/app/afip --silent`
- **Before `/gsd-verify-work`:** suite afip verde + ESLint limpio en archivos ventago-app tocados
- **Max feedback latency:** 60 segundos (sin watch-mode, sin E2E completo)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command (resumen) | Status |
|---------|------|------|-------------|-----------|------------------------------|--------|
| 57-01-01 | 01 | 1 | R1/R3/R5 | tdd/tsc | `tsc --noEmit` afip (build-factura/code-maps) | ⬜ pending |
| 57-01-02 | 01 | 1 | R1/R3/R5 | tdd/jest | `jest afip/build-factura afip/code-maps` | ⬜ pending |
| 57-02-01 | 02 | 1 | R1/R2 | render harness | `node -e formatFiscalHtml` → QR/IVA/emisor asserts (FISCAL_A_OK) | ⬜ pending |
| 57-02-02 | 02 | 1 | R1/R2 | wiring grep (GAP#1) | `node --check main.js` + grep `formatFiscalHtml(payload.factura` | ⬜ pending |
| 57-03-01 | 03 | 1 | R5 | migration+model grep | grep `invoice_type` SQL + `invoiceType` model/DTO + tsc | ⬜ pending |
| 57-03-02 | 03 | 1 | R5 | eslint+grep UI | eslint ModalBranch + grep `watch('ivaCondition')`/`invoiceType` | ⬜ pending |
| 57-04-01 | 04 | 2 | R1/R3 | jest+grep (GAP#3/#4) | `jest afip-output.service` + grep `getSaleForVoucher`/`buildFactura` + letra_removed | ⬜ pending |
| 57-04-02 | 04 | 2 | R1/R3 | tdd/jest | `jest afip/pdf/a4-generator` | ⬜ pending |
| 57-05-01 | 05 | 1 | R6 | live curl (D-07 gate) | `curl manager…/data/header` → 200 json (MANAGER_LIVE_OK\|FALLBACK) | ⬜ pending |
| 57-05-02 | 05 | 1 | R6 | tdd/jest | `jest afip/afip-issuer.service` (caché 60s + fallback) | ⬜ pending |
| 57-06-01 | 06 | 3 | R5/R6 | tdd/jest+grep | `jest afip-voucher.service` + grep `resolvePvAndCoolUser`/`configInvoiceType` | ⬜ pending |
| 57-06-02 | 06 | 3 | R5/R6 | jest+grep (GAP#2) | `jest afip.controller` + grep `outputService.dispatch` | ⬜ pending |
| 57-07-01 | 07 | 3 | R7 | tdd/jest+grep (GAP#3) | `jest nota-credito.service` + grep `outputService.dispatch` | ⬜ pending |
| 57-07-02 | 07 | 3 | R7 | tdd/jest+grep (GAP#3) | `jest nota-debito.service` + grep `outputService.dispatch` | ⬜ pending |
| 57-08-01 | 08 | 3 | R4 | eslint+grep | eslint EmitidasPanel + grep `responseType: 'blob'`/`vouchers/` | ⬜ pending |
| 57-08-02 | 08 | 3 | R4 | eslint+grep | eslint PartialInvoiceModal + grep `Descargar PDF A4`/`setIssued` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 (inline — no separate plan)

Cada una de las 16 tasks lleva su propio `<automated>` verify rápido (jest afip / tsc / eslint / node harness / curl), por lo que **no se requiere un plan Wave 0 separado**. Los specs unitarios se crean dentro de sus planes en `api-ventago/src/app/afip/` (flat, junto a los specs existentes — NO en `__tests__/`):

- `build-factura.spec.ts` + `code-maps` (R1/R3/R5) → Plan 01
- `afip-output.service.spec.ts` + `a4-generator` (R1/R3) → Plan 04
- `afip-issuer.service.spec.ts` PV resolution + fallback (R6) → Plan 05
- `afip-voucher.service` / `afip.controller` / `nota-credito` / `nota-debito` specs → Planes 06/07

*ESC/POS visual + escaneo QR físico quedan como Manual-Only (hardware/homologación) — ver abajo.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ticket ESC/POS letra/QR/IVA impreso | R1/R2 | Requiere print-agent + comprobante homologación | Emitir Factura A y B en homologación, escanear QR del ticket → decodifica a afip.gob.ar/fe/qr con codAut=CAE |
| A4 PDF descarga on-demand | R4 | Requiere UI + navegador | Emitidas ▸ botón "PDF A4" → descarga sin re-emitir CAE (afip_number invariante) |
| Selector A/M solo RI | R5 | Depende de Cond.IVA render condicional | ModalBranch con RI muestra selector; MONO/EXENTO no |
| PV desde manager /data/header | R6 | Gateway externo vivo | invoice_sucursal seteado → point proviene de branchs[0].point; header caído → fallback local + log |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify (16/16, inline — sin dependencias Wave 0 externas)
- [x] Sampling continuity: sin 3 tasks consecutivas sin automated verify
- [x] Wave 0 cubierto inline (specs creados dentro de sus planes)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` en frontmatter

**Approval:** ready
