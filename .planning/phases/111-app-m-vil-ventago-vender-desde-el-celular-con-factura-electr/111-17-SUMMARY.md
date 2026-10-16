---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 17
subsystem: api-ventago/mobile
tags: [mercadopago, qr, colibri, tenant-isolation]
requires: ["111-01", "111-03", "111-15"]
provides:
  - PosMpService (createQr, getIntent, cancel, aprobadasSinVenta, validarIntentParaVenta, mpQrDisponible)
  - PosMpController /mobile/pos/mp/*
  - PosMpModule exporting PosMpService (for Plan 05)
key-files:
  created:
    - api-ventago/src/app/mobile/pos/mp/pos-mp.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/mp/pos-mp.controller.ts (+ spec)
  modified:
    - api-ventago/src/app/mobile/pos/mp/pos-mp.module.ts
    - api-ventago/src/app/mobile/pos/shared/pos-contracts.ts
decisions:
  - Same-amount pending QR of the terminal is reused; different amount gives 409 MP_QR_ACTIVO; never auto-cancel
  - QR PNG rendered server-side with qrcode; render failure returns qrPngBase64 null
metrics:
  api-commits: 169b51e7, 6c5e9551
  completed: 2026-10-16
---

# Phase 111 Plan 17: Mercado Pago QR del celular Summary

El celular Colibri genera, sigue y cancela un QR dinamico de Mercado Pago sobre el mismo MpQrService de la web, con tienda/sucursal/terminal/caja tomados solo del dispositivo, y Plan 05 recibe `validarIntentParaVenta` para que un pago aprobado pague una sola venta.

## Que se hizo
- `PosMpService`: toda consulta a `mp_payment_intents` filtra storeId Y terminalId (404 ajeno). `createIntent` recibe `pendingVentaId` = sesion de caja abierta del box del dispositivo. Errores MP_NO_ACCOUNT/DISCONNECTED/NO_EXTERNAL_POS_ID pasan a 409 MP_NO_DISPONIBLE. `validarIntentParaVenta`: 404 / 409 MP_NO_APROBADO / 422 MP_MONTO (centavos) / 409 MP_YA_USADO, con `FOR UPDATE` cuando recibe tx; el uso unico lo respalda `uq_spm_mp_payment_intent`. Sin transaccion alrededor de la llamada a MP.
- `PosMpController`: POST qr, GET intents (antes de :id), GET intents/:id, DELETE qr/:id; `@Auth` con los roles de la web, guards de clase jwt + MobileScopeGuard + MobileTerminalGuard, `@Audit` en POST/DELETE (descripcion desde result), body estricto (solo `amount`, clave extra -> 400).
- `pos-contracts.ts`: `MpQrResponse.qrPngBase64` pasa a `string | null` (cambio aditivo).

## Verificacion
- jest `src/app/mobile/pos/mp src/app/mercadopago`: 15 suites, 153 tests verdes (mp: 30 de servicio + controller). tsc 0, eslint limpio, gate de commit paso en ambos commits.
- Mutacion: quitar `terminalId` del where de `findScoped` (usado por getIntent/cancel) -> falla "intent de otra tienda o terminal -> 404 (where lleva store Y terminal)"; compilo (30 tests ejecutados, no "Tests: 0"). Restaurado (diff vacio).

## Deviations from Plan
- Estas rutas usan `@Auth` por rol (como la web de MP) y no `@FunctionGuard`, segun el plan.
- Sin `@FunctionGuard`: no hay DML de permisos, no aplica nota perm-cache.

## Notas
- No se hizo push (Plan 14 publica en orden). STATE.md / ROADMAP.md quedan sin commitear a proposito.
- `PosMpModule` ya estaba en `MobilePosModule`; nunca se llamo a Mercado Pago real (modelos y MpQrService simulados).
- Sin DDL/DML de produccion.

## Known Stubs
Ninguno.

## Self-Check: PASSED
Commits 169b51e7 y 6c5e9551 existen en api-ventago; archivos presentes.
