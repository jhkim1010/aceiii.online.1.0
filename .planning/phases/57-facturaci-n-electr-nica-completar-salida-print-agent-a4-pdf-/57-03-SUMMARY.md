---
phase: 57-facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf-
plan: 03
subsystem: afip-facturacion-electronica
tags: [afip, factura-am, issuer, migration, modalbranch, ri-gate]
requires:
  - afip_issuers table (existente)
  - invoiceSucursal pattern (misma sesión, Plan precondición)
provides:
  - afip_issuers.invoice_type (A|M) columna + modelo + DTO
  - selector A/M RI-gated en ModalBranch (persistencia + UI)
affects:
  - Plan 06 (decideComprobante gate IVA=RI consumirá issuer.invoiceType)
tech-stack:
  added: []
  patterns:
    - "triple migración+modelo+DTO (réplica exacta de invoiceSucursal)"
    - "RI-gated conditional form field vía watch('ivaCondition')"
    - "RadioGroup + Controller (react-hook-form) con tokens MUI color=primary"
key-files:
  created:
    - api-ventago/migrations/afip-issuer-invoice-type.sql
  modified:
    - api-ventago/src/app/afip/models/afip-issuer.model.ts
    - api-ventago/src/app/afip/dto/upsert-issuer.dto.ts
    - ventago-app/src/views/admin/stores/details/components/ModalBranch.tsx
    - ventago-app/src/views/admin/stores/details/components/DataConfig.tsx
decisions:
  - "invoiceType se envía en el PUT solo cuando ivaCondition==='RI' (undefined si no-RI) — refuerza el gate del lado cliente además del server-side (Plan 06)"
  - "invoiceType añadido a branchSchema como oneOf(['A','M']) opcional para default 'A' consistente con la columna DB"
metrics:
  duration: ~15m
  completed: 2026-07-20
  tasks: 2
  files: 5
---

# Phase 57 Plan 03: Selector Factura A/M por sucursal (D-08 scaffolding) Summary

Persistencia + UI para que cada sucursal RI elija emitir Factura A o solo Factura M: columna `afip_issuers.invoice_type` (A|M, default 'A') replicando exactamente el patrón `invoiceSucursal`, más un selector RadioGroup RI-gated en `ModalBranch.tsx` visible solo cuando la condición IVA es Responsable Inscripto. El wiring runtime de `decideComprobante` es del Plan 06 — este plan deja solo persistencia + UI.

## What Was Built

### Task 1 — Migración + modelo + DTO (api-ventago @a8bad4d)
- **`migrations/afip-issuer-invoice-type.sql`** (NEW): `ALTER TABLE afip_issuers ADD COLUMN IF NOT EXISTS invoice_type varchar(1) DEFAULT 'A'` + COMMENT. Solo ADD COLUMN → sin transferencia de owner/secuencia.
- **`afip-issuer.model.ts`**: columna `invoiceType` (`DataType.STRING(1)`, `allowNull:false`, `defaultValue:'A'`). Persiste vía spread `{...dto}` existente en el upsert.
- **`upsert-issuer.dto.ts`**: campo `invoiceType?` con `@IsOptional() @IsIn(['A','M'])`.
- `tsc --noEmit` sin errores nuevos.

### Task 2 — Selector A/M RI-gated en ModalBranch (ventago-app @29029d0)
- **`ModalBranch.tsx`**: añadido `watch` al destructure de `useForm`; `RadioGroup` (Controller) con 2 opciones "Puede emitir Factura A" (A, default) / "Solo Factura M" (M), label "Tipo de factura habilitada" + helper exacto de UI-SPEC. Renderiza **solo** cuando `watch('ivaCondition') === 'RI'` (para MONO/EXENTO no se renderiza, no solo deshabilitado). Colores vía token `color="primary"`, nunca hex. `invoiceType` añadido a `reset` (`issuer.invoiceType ?? 'A'`), al destructure de `onSubmit` y al payload del `PUT /afip/issuers/by-branch/:branchId` (enviado como `undefined` cuando no-RI).
- **`DataConfig.tsx`**: `invoiceType: "A"` en `branchDefaultValues` y `oneOf(["A","M"])` en `branchSchema`.
- ESLint `--max-warnings=0` limpio en ambos archivos.

## Deviations from Plan

**1. [Rule 2 — refuerzo de gate] `invoiceType` enviado como `undefined` cuando `ivaCondition !== 'RI'`**
- **Encontrado en:** Task 2, onSubmit payload.
- **Motivo:** el threat model (T-57-06) exige no confiar en el gate visual del cliente. Además de no renderizar el selector para no-RI, el payload envía `invoiceType: ivaCondition === 'RI' ? (invoiceType || 'A') : undefined` para no persistir un 'M' colgado si el usuario cambia RI→MONO tras haber tocado el selector. El gate real server-side sigue en Plan 06 (`decideComprobante`).
- **Archivos:** ModalBranch.tsx.
- **Commit:** 29029d0.

**2. [Rule 3 — consistencia] `invoiceType` añadido a `branchSchema`/`branchDefaultValues` (DataConfig.tsx)**
- **Encontrado en:** Task 2. El plan menciona "defaults/schema si aplica". `invoiceSucursal` no está en el schema, pero para que el RadioGroup tenga 'A' preseleccionado de forma consistente con el default de la columna DB se añadió a defaults + schema `oneOf(['A','M'])` opcional.
- **Archivos:** DataConfig.tsx.
- **Commit:** 29029d0.

## Pending Migration (NOT executed — user/orchestrator applies)

La migración `api-ventago/migrations/afip-issuer-invoice-type.sql` fue **commiteada pero NO ejecutada** contra ninguna DB (per instrucción sequential + CLAUDE.md "DB 마이그레이션 적용 규칙"). Aplicar a **ambas** con confirmación explícita:

- **Local 5432** (el sandbox no alcanza el Mac local — ejecutar en la Mac):
  ```bash
  psql -p 5432 -d ventago -f api-ventago/migrations/afip-issuer-invoice-type.sql
  ```
- **Prod 5434** (vía SSH):
  ```bash
  ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f -" < api-ventago/migrations/afip-issuer-invoice-type.sql
  ```

Sin aplicar la migración, un upsert con `invoiceType` fallará con `column "invoice_type" does not exist` en runtime. La columna es `ADD COLUMN IF NOT EXISTS` con `DEFAULT 'A'` → los issuers existentes quedan en 'A' automáticamente (sin backfill).

## Verification

- `cd api-ventago && npx tsc --noEmit -p .` — sin errores en afip-issuer.model / upsert-issuer.
- `cd ventago-app && npx eslint ModalBranch.tsx DataConfig.tsx --max-warnings=0` — exit 0.
- grep acceptance: `watch('ivaCondition') === 'RI'` ✓, "Solo Factura M" ✓, "Puede emitir Factura A" ✓, `invoice_type varchar(1) DEFAULT 'A'` ✓, `@IsIn(['A','M'])` ✓.
- Manual (57-VALIDATION.md): ModalBranch con RI muestra el selector; con MONO/EXENTO no aparece. Pendiente de UAT en navegador.

## Known Stubs

Ninguno. El campo persiste y renderiza real; el consumo runtime del valor (gate `decideComprobante`) es explícitamente alcance del Plan 06, documentado en el objetivo del plan, no un stub.

## Self-Check: PASSED

- FOUND: api-ventago/migrations/afip-issuer-invoice-type.sql
- FOUND: .planning/phases/57-.../57-03-SUMMARY.md
- FOUND commit api-ventago@a8bad4d (Task 1)
- FOUND commit ventago-app@29029d0 (Task 2)
