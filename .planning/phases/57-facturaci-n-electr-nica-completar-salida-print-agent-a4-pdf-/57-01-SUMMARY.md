---
phase: 57-facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf-
plan: 01
subsystem: afip
tags: [afip, factura-electronica, build-factura, tdd, backend]
requires:
  - code-maps.ts::letraOf, computeNetoIva, decideDocumentType, decideComprobante
  - partial-invoice.ts::applyPartial
  - qr-builder.ts::buildQrUrl
provides:
  - build-factura.ts::buildFactura (fuente única D-02/D-04)
  - build-factura.ts::Factura, FacturaItem, FacturaReceptor (tipos D-02)
  - code-maps.ts::condIvaLabel (display map)
affects:
  - api-ventago/src/app/afip/build-factura.ts
  - api-ventago/src/app/afip/code-maps.ts
tech-stack:
  added: []
  patterns:
    - "Función pura sin DB (input plano) para testabilidad + anti cross-tenant"
    - "AFIP single-source-of-truth: nunca reimplementar letra/IVA fuera de code-maps"
key-files:
  created:
    - api-ventago/src/app/afip/build-factura.ts
    - api-ventago/src/app/afip/build-factura.spec.ts
  modified:
    - api-ventago/src/app/afip/code-maps.ts
    - api-ventago/src/app/afip/code-maps.spec.ts
decisions:
  - "buildFactura recibe input plano (BuildFacturaSale/Voucher/Issuer), no importa Sequelize — pureza + T-57-01 (caller pasa sale store-scoped)"
  - "total = impTotal reconstruido por applyPartial (coherente con Σsubtotal e items del preview F10)"
  - "receptor.condIva y emisor.condIva siempre via condIvaLabel — nunca código crudo"
metrics:
  duration: ~20min
  completed: 2026-07-20
  tasks: 2
  files: 4
---

# Phase 57 Plan 01: buildFactura fuente única D-02/D-04 Summary

Fuente única `buildFactura(voucher, sale, issuer)` que produce el objeto `Factura` D-02 (consumido por thermal y A4), reusando `applyPartial` + helpers canónicos AFIP sin duplicar reglas; más el map `condIvaLabel` y unit tests del A/M gate.

## What Was Built

- **`build-factura.ts` (NEW, puro):** `buildFactura(voucher, sale, issuer): Factura`. Reconstruye líneas con `applyPartial` (D-05, `Σsubtotal === impTotal`), deriva letra con `letraOf`, discrimina IVA 21% con `computeNetoIva` (solo A/M), arma receptor `identificado` (A/M) vs `consumidorFinal` (B), emisor desde issuer, y `qrUrl` con `buildQrUrl`. No consulta DB (input plano) — el caller (Plan 04) debe pasar un `sale` ya store-scoped (T-57-01). No reimplementa reglas AFIP (T-57-02).
- **`code-maps.ts` (MOD):** `condIvaLabel: Record<string,string>` (RI/MONO/EXENTO/CF → texto español) para el bloque receptor/emisor.
- **Tests:** `build-factura.spec.ts` (Factura A/B/M, ivaDiscrim por letra, receptor por letra, `Σsubtotal===impTotal`) + `code-maps.spec.ts` extendido con `describe('decideComprobante A/M gate (R5)')` (M / A / undefined→A / MONO→C).

## TDD Gate Compliance

- **RED:** `test(57-01)` `ac5fd32` — build-factura.spec falla (módulo inexistente); code-maps A/M gate pasa (característico de `decideComprobante` ya existente — la rama A/M ya estaba implementada, estos tests cubren R5 sin cambiar lógica).
- **GREEN:** `feat(57-01)` `1095563` — 23/23 tests verdes, `tsc --noEmit` limpio en afip.
- **REFACTOR:** no necesario (código limpio en GREEN).

## Verification

- `npx jest src/app/afip/build-factura src/app/afip/code-maps` → 23 passed, 2 suites.
- `npx tsc --noEmit -p .` → sin errores nuevos en afip (`build-factura`/`code-maps` limpios).
- Acceptance greps: buildFactura export, condIvaLabel, canonicals (applyPartial/letraOf/computeNetoIva), sin `/1.21` manual, ivaDiscrim, spec `consumidorFinal`, code-maps `'M'`, pureza (sin `saleModel/findOne/@InjectModel`) — todos OK.

## Deviations from Plan

None - plan executed exactly as written. El único matiz esperado: los tests del A/M gate de `decideComprobante` pasan ya en RED porque la rama A/M es preexistente (documentado en 57-PLAN interfaces); son tests de caracterización R5, no nueva lógica.

## Known Stubs

None. `buildFactura` es completo para su contrato D-02; el cargador store-scoped del `sale` y el cableado a thermal/A4 son responsabilidad explícita de Plan 02/04 (no stubs de este plan).

## Self-Check: PASSED
