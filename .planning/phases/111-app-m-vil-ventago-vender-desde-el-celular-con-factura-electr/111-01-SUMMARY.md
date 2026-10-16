---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 01
subsystem: database
tags: [postgres, migration, sequelize, mobile-pos, expand]
requires: []
provides:
  - tablas mobile_devices y mobile_stock_ingresos (local + prod)
  - columnas nullable sale_payment_methods.received_amount/change_amount/reference/mp_payment_intent_id y sales.invoice_pending_at
  - UNIQUE parcial uq_spm_mp_payment_intent (un intent MP = una línea de pago)
  - modelos MobileDevice, MobileStockIngreso (sin registrar en ningún módulo)
affects: [111-03, 111-05, 111-14, 111-17]
tech-stack:
  added: []
  patterns: [W4 expand-only, FK NOT VALID + VALIDATE separado, índices CONCURRENTLY en archivo aparte]
key-files:
  created:
    - api-ventago/migrations/2026-10-16-phase111-movil-pos.sql
    - api-ventago/migrations/2026-10-16-phase111-movil-pos-idx.sql
    - api-ventago/src/app/mobile/models/mobile-device.model.ts
    - api-ventago/src/app/mobile/models/mobile-stock-ingreso.model.ts
  modified:
    - api-ventago/src/app/sales/sales.model.ts
    - api-ventago/src/app/sales/sales-payment-methods/sales-payment-method.model.ts
    - .planning/intel/db-schema-tables.md
    - .planning/intel/db-schema-fks.md
key-decisions:
  - "mpPaymentIntentId es columna simple sin @BelongsTo (evita ciclo de modelos con mercadopago)"
  - "MOBILE_DEVICE_STATUS se define en el propio modelo, no se importa de otro"
requirements-completed: [D-03, D-04, D-08, D-12, D-15, D-17, D-21]
duration: n/a
completed: 2026-10-16
---

# Phase 111 Plan 01: Expand de esquema para POS móvil Summary

Esquema W4 expand-only aplicado en local y prod (tablas de dispositivos e ingresos idempotentes, columnas de cobro auditable, marca «sin emitir» y UNIQUE parcial del intent MP), con modelos Sequelize de tipos explícitos.

## Tasks

| Task | Commit | Notas |
|---|---|---|
| 1 SQL + aplicar local 5432 | api-ventago `7e07e82b` | spec de convenciones 9/9; count=7; índices y FK válidos; 0 transacciones largas antes |
| 2 Aprobación DDL prod | (orquestador) | ver abajo |
| 3 Modelos + intel | api-ventago `58551888`; intel en commit raíz | tsc 0; sales-create spec 14/14 |

## Task 2 — prod aplicado por el orquestador

El DDL en 5434 NO lo ejecutó este agente: lo aplicó la sesión principal tras la aprobación directa del usuario («승인»), ambos archivos a las 07:32 BA, 0 usuarios activos, 0 transacciones largas (hechos informados por el orquestador). Este agente no recibió la aprobación directamente y por eso se detuvo en el checkpoint. Cifras del checkpoint (00:47 BA): sales 359.605, sale_payment_methods 354.094, 1 usuario activo.

Verificación read-only hecha por este agente en prod después: conteo de columnas = 7; idx_sales_invoice_pending e uq_spm_mp_payment_intent indisvalid = t; fk_spm_mp_payment_intent convalidated = t; owners de mobile_devices y mobile_stock_ingresos = coolsistema; sus dos secuencias = coolsistema. El orquestador informa comparación local vs prod de 79 líneas idénticas.

## Deviations from Plan

- Criterio `grep -c "type: DataType" mobile-device.model.ts ≥ 15`: el modelo tiene 14 columnas, todas con tipo explícito; el umbral era un error de cuenta del plan. Se cumple la intención.
- Prettier corrigió el formato de mobile-device.model.ts tras el rechazo del gate de commit (eslint prettier/prettier).
- La regeneración de intel arrastró deriva previa del catálogo (130 líneas añadidas en total, no sólo los objetos nuevos).

## Known Stubs

None. Los modelos no están registrados en ningún módulo a propósito (Plan 03).

## Threat Flags

None.

## Self-Check: PASSED

Archivos creados presentes y commits `7e07e82b` y `58551888` existen en api-ventago. Sin push realizado.
