---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 05
subsystem: api-ventago/mobile
tags: [ventas, idempotencia, caja, mercadopago, colibri, tenant-isolation]
requires: ["111-01", "111-03", "111-04", "111-15", "111-17"]
provides:
  - POST /mobile/pos/sales (Idempotency-Key), GET /mobile/pos/sales/by-key/:key
  - POST /mobile/pos/suspended, POST /mobile/pos/sales/:id/print, GET /mobile/pos/sales/:id/printers
  - CreateSaleOpts.paymentAudit / invoiceRequested (internas) y SaleIdempotencyService.findByKey
key-files:
  created:
    - api-ventago/src/app/mobile/pos/sales/pos-sales.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/sales/pos-sales.controller.ts (+ spec)
    - api-ventago/src/app/mobile/pos/sales/pos-sales.itest.ts
  modified:
    - api-ventago/src/app/mobile/pos/sales/pos-sales.module.ts
    - api-ventago/src/app/sales/sales-create.service.ts
    - api-ventago/src/app/sales/sale-idempotency.service.ts (+ spec)
    - api-ventago/src/app/sales/sales-create-payment-boundary.spec.ts
decisions:
  - La clave completada se decide ANTES de cualquier chequeo (paso 0) y salta la validacion de MP
  - Los 409/422 de negocio salvo EN_CURSO y CLAVE_CONFLICTO solo salen sin venta confirmada (contrato escrito en el servicio)
  - Q10 (promos) y Q11 (sales.source) resueltas: el wrapper no manda promos ni source; la venta del celular se identifica por sales.terminal_id
metrics:
  completed: 2026-10-16
  api-commits: [13fdacef, f8f564af, f754b2ce]
---

# Phase 111 Plan 05: Cobro real desde el celular Summary

El celular cobra de verdad: un envoltorio sobre `SalesCreateService` (unico escritor de ventas) ata la venta a la terminal y a la caja (cajon) del dispositivo, exige caja abierta, guarda recibido/vuelto/referencia/intent de Mercado Pago por linea, es idempotente con consulta por clave y solo imprime con un boton.

## Commits (api-ventago, sin push)
- 13fdacef feat(111-05): `paymentAudit` e `invoiceRequested` en SalesCreateService + `findByKey`
- f8f564af feat(111-05): PosSales wrapper (service, controller, module, specs)
- f754b2ce test(111-05): itest de BD

## Que se hizo
- **Task 1**: `CreateSaleOpts.paymentAudit` (alineado por indice con `paymentMethods`, escrito en el mismo `salePaymentMethodModel.create` del bucle normal, misma transaccion) e `invoiceRequested` (`sales.invoice_pending_at` en el INSERT de la venta, via `invoicePendingAtFor`). Largo distinto -> 400 antes de abrir la transaccion. Los opts no entran en el hash de idempotencia (se derivan del mismo body). `SaleIdempotencyService.findByKey(storeId, key)`: lectura por tienda, sin efectos, vencidas -> null.
- **Task 2**: `PosSalesService`: paso 0 (`findByKey` linea 381, antes de `getOpenCashRegisterByBox` linea 411), cuerpo con lista blanca estricta, caja del dispositivo, variantes de la tienda sin madres, precio de lista (PRECIO_CAMBIADO), centavos (TOTAL_NO_CIERRA), efectivo con vuelto recalculado por el servidor, credito exige cliente, linea MP con `validarIntentParaVenta` (referencia `MP <paymentId>` fijada por el servidor), traduccion de errores de `create()` (CAJA_CERRADA, SIN_STOCK, EN_CURSO, CLAVE_CONFLICTO, MP_YA_USADO por UniqueConstraintError), by-key por tienda y terminal, dejar en espera, imprimir solo por boton (lista permitida de comanderas), siempre `suppressAutoPrint: true` y sin `printTicket`/`saleDate`/promos/`source`.
- **Task 3**: itest contra la BD local (10 casos).

## Verificacion
- Unit: `src/app/mobile/pos/sales` 38 tests (32 servicio + 6 controller); `src/app/sales` payment-boundary + idempotency (+ 7 tests nuevos de Task 1). tsc 0, eslint limpio en lo agregado.
- Amplio: jest `src/app/mobile src/app/sales src/app/auth/guards` --maxWorkers=1: 57 suites verdes, 883 tests; fallan 3 preexistentes de `agent-readonly-scopes.venta.spec.ts` (no mios).
- itest `jest --config ./test/itest/jest-itest.json --runInBand src/app/mobile/pos/sales/pos-sales.itest.ts`: 10 pasan, 0 fallan; el dummy store queda eliminado.

### Mutaciones (todas compilaron: se ejecutaron los tests, no «Tests: 0»)
| Mutacion | Test que falla | compiled |
|---|---|---|
| quitar `paymentAudit` (receivedAmount) del create del bucle de pagos | spec payment-boundary «la entrada i-esima cae en la fila i-esima» | yes |
| `suppressAutoPrint: true` -> false (ruta fresca) | itest 4) «pagar y chequear la caja no abre otra sesion» (assert de opts) | yes |
| quitar el chequeo de caja abierta | itest 1) y 7) (CAJA_CERRADA) | yes |
| `offlineCash` -> undefined | itest 4) | yes |
| mover `findByKey` despues del chequeo de caja | itest 7) y 8) (reintento con caja cerrada / con MP) | yes |

Todos restaurados (diff vacio contra la copia).

## Deviations from Plan
1. **[Rule 3 - Blocker] itest no llega a `create()` de punta a punta.** El harness Nest esta roto (SocketCensusService) y `SalesCreateService` pide 30 dependencias (el spec existente asumia 27). El itest usa Sequelize directo y ejecuta de verdad: el bucle de pagos real (`processPaymentMethods`) con `CashRegisterService`/`BoxOperationService` reales, `findByKey` real y `PosSalesService` real con caja real; el escritor `create` va con espia en los casos del envoltorio. Quedan solo en unit (mocks): SIN_STOCK, EN_CURSO, CLAVE_CONFLICTO y el claim/replay interno. **Falta el smoke de Plan 14 con la API levantada** (venta completa por HTTP, incl. SIN_STOCK).
2. **Paridad `mpQrDisponible` (checker W4):** no hay test que compare `PosContextService.getContext().mpQrDisponible` con `PosMpService.mpQrDisponible` con los 3 fixtures; ambos llaman a `resolveForScope(storeId, device.branchId)` y aplican el mismo predicado (`!!account && !disconnectedAt && !!externalPosId`) pero estan escritos dos veces. Recomendado unificar o testear antes de Plan 14.
3. **Reintento (paso 0):** el `paymentAudit` del reintento sale del body tal cual (sin mirar el tipo de medio): nunca se escribe porque `create()` devuelve la respuesta guardada antes del bucle de pagos, ni entra al hash.
4. **`priceTypeId`** de cada item se lee de `store_configs.defaultPriceTypeId` tambien en el reintento; si esa config cambia entre intento y reintento el hash difiere y la respuesta es CLAVE_CONFLICTO («preguntar por clave»), nunca una venta duplicada.
5. Codigos nuevos (fuera de `POS_ERROR`, el tipo admite string): `VARIANTE_REQUERIDA`, `PRECIO_NO_DISPONIBLE`, `CLIENTE_REQUERIDO`, `BODY_INVALIDO`.
6. `POST sales/:id/print` ignora claves extra del body (p. ej. `terminalId`), segun el plan; `POST sales` rechaza claves extra (400).

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo fuera del threat_model del plan. La emision automatica de AFIP sigue cerrada por `AUTO_EMISION_PROHIBIDA`; `suppressAutoPrint` evita la impresion; el wrapper no manda `printTicket`.

## Notes
- No se hizo push (Plan 14 publica en orden). El gitlink de api-ventago en el root no se commiteo. STATE.md y ROADMAP.md quedan SIN commitear (tienen cambios ajenos).
- Requiere la migracion de Phase 111 (Plan 01) en la BD donde corra (en local ya esta: `uq_spm_mp_payment_intent`).
- Sin DDL/DML de produccion.

## Self-Check: PASSED
Commits 13fdacef, f8f564af, f754b2ce existen en api-ventago; los 3 servicios/controller/itest estan presentes.
