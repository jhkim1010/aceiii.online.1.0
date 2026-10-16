---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 06
subsystem: api-mobile-pos
tags: [nestjs, afip, fiscal, clients, padron, pdf, colibri]
requires: ["111-03", "111-15"]
provides:
  - "GET/POST /mobile/pos/clients, clients/:id, clients/padron, PUT clients/:id/fiscal"
  - "GET /mobile/pos/fiscal/opciones, POST fiscal/check"
  - "GET sales/sin-emitir, sales/:id/fiscal, POST sales/:id/invoice"
  - "GET sales/:id/ticket.pdf, vouchers/:id/pdf, POST vouchers/:id/print"
  - "toFiscalEstado (pure), PosClientsService, PosFiscalService, PosFiscalOutputService"
key-files:
  created:
    - api-ventago/src/app/mobile/pos/fiscal/pos-clients.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/fiscal/fiscal-estado.ts (+ spec)
    - api-ventago/src/app/mobile/pos/fiscal/pos-fiscal.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/fiscal/pos-fiscal-output.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/fiscal/ticket-no-fiscal.pdf.ts (+ spec)
    - api-ventago/src/app/mobile/pos/fiscal/pos-fiscal.controller.ts (+ spec)
  modified:
    - api-ventago/src/app/mobile/pos/fiscal/pos-fiscal.module.ts
    - api-ventago/src/app/afip/afip.module.ts
decisions:
  - Emission reuses AfipVoucherService.issueForSale (which already goes through emitirConGuardas); no guard is duplicated and there is no thermal/print code in the emitting service
  - Thermal output lives only in PosFiscalOutputService.printVoucher (button); a control spec reads both files to enforce it
  - "Debe" of a client = store_clients.balance of the store (same definition as the web debtor filter), not re-derived from credit_ledger
metrics:
  completed: 2026-10-16
  api-commits: [5aeb5beb, 11bb96f2, d71813f2]
---

# Phase 111 Plan 06: Fiscal del celular Summary

El celular ya puede buscar clientes, validar y corregir «Datos para facturar» antes de cobrar, emitir la factura solo con el boton, leer un estado fiscal legible (emitida/emitiendo/verificar/rechazada/sin_emitir/no_solicitada), bajar el PDF de la factura (solo con CAE) o un ticket no fiscal, reimprimir por boton y listar todas las «sin emitir» de la sucursal sin limite de dias.

## Commits (api-ventago repo, not pushed)
- 5aeb5beb feat(111-06): clientes y «Datos para facturar» (search, detail, create, padron, updateFiscal, fiscal/opciones, fiscal/check)
- 11bb96f2 feat(111-06): estado fiscal legible, emision manual y lista sin emitir
- d71813f2 feat(111-06): PDF de factura con CAE, ticket no fiscal, reimpresion por boton y controlador fiscal

## Verification
- jest `src/app/mobile/pos/fiscal src/app/afip` (--maxWorkers=1): 82 suites, 1192 tests verdes (incluye arranque-nest.spec). `src/app/mobile src/app/auth/guards`: 357 verdes, 3 fallos preexistentes de agent-readonly-scopes.venta.spec.ts (no mios).
- tsc 0, eslint limpio, gate de commit paso en los 3 commits (dos reintentos por no-unsafe-assignment / no-unnecessary-type-assertion).
- Mutacion sobre `PosFiscalService.emit`: desactivar el guard de estados sin reemision -> 3 tests fallan (emitida/emitiendo/verificar llaman a issueForSale). Restaurado.
- Greps: `thermal` ausente de pos-fiscal.service.ts, `issueForSale(` exactamente una vez, `sin-emitir` declarado antes de `sales/:id`.

## Deviations from Plan
- **[Rule 3] PosFiscalOutputService (archivo extra):** el criterio de aceptacion exige que `pos-fiscal.service.ts` no contenga «thermal». La reimpresion fiscal (`output:'thermal'`) y los PDF viven en `pos-fiscal-output.service.ts`, para que el servicio que EMITE no tenga ninguna salida a la comandera. Un test estatico lee ambos archivos.
- **[Rule 3] ProvinceService:** `fiscalOpciones` usa el modelo `Province` directo (forFeature) en vez de `ProvinceService.findAll()`, porque necesita filtrar por pais y `is_active`. Filtro: `nation_id = 1` (Argentina; IIBB solo aplica a jurisdicciones argentinas, igual que `resolveJurisdiccion`) y `is_active IS NOT FALSE`.
- **Ticket no fiscal:** las lineas salen de `sale_items` (nombre de producto / customName), no de `groupItemsForPrint` (que exige includes de color/talle/padre privados de SalesCreateService). Sin matriz de variantes en el PDF.
- **`FiscalCheck`:** el body acepta `storeClientId` opcional y la respuesta `mensaje` opcional (tipos locales extendidos en pos-clients.service.ts; pos-contracts.ts no se toco). Con `storeClientId` cuyo receptor sale de global_clients y faltan datos -> `faltan:['editar_en_web']` y mensaje «Este cliente se corrige desde la web».
- `ClientsModule` no hizo falta tocarlo (ya exporta ClientsService y los modelos); `AfipModule` ahora exporta `PadronClienteService`.
- Emitir una venta anulada devuelve 409 `VENTA_ANULADA` (codigo no incluido en POS_ERROR; el cuerpo admite strings).

## Decisiones / supuestos para el usuario
- **A6 (legal):** la leyenda `COMPROBANTE NO VÁLIDO COMO FACTURA` es la propuesta de la investigacion; confirmarla con el usuario / contador (Plan 14 UAT / Plan 20).
- **A7 (tope CF):** `decideComprobante`/`decideDocumentType` NO implementan ningun tope; solo hay un comentario («AFIP 10015: Factura B < $10M ...»). `fiscal/check` define `TOPE_CF_SIN_DOCUMENTO = 10_000_000` a partir de ese comentario y pide `documento` cuando B/C, sin documento y total >= tope. Verificar el valor vigente antes de redactar el copy de la UI.
- «Debe» del detalle = `store_clients.balance` (por `client_id` o por documento via global_clients, solo lectura).

## Known Stubs
Ninguno.

## Notes
- No se hizo push (Plan 14 publica en orden). STATE.md y ROADMAP.md quedan sin commitear a proposito (tienen cambios ajenos). El gitlink de api-ventago en el root no se commiteo.
- El arranque real de Nest contra BD no se probo (arranque-nest.spec y specs con modelos simulados si); revisar al levantar la API local antes de Plan 14.
- Sin DDL/DML de produccion. No se emitio ni se imprimio nada real.
- Emision, PDF y reimpresion dependen de AFIP/impresora reales: se probaron con mocks; el recorrido real es parte del UAT.

## Self-Check: PASSED
Commits 5aeb5beb, 11bb96f2 y d71813f2 existen en api-ventago; archivos creados presentes.
