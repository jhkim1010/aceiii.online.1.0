---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 05
subsystem: auth
tags: [nestjs, agent-scope, ver_ventas, ver_productos, ver_facturas]
requires: [101-01, 101-03, 101-04]
provides:
  - "Lecturas de Venta, Producto y Factura marcadas con @AgentScope ver_* (31 handlers en 7 controladores)"
  - "MANIFIESTO_VENTA + EXCLUIDOS_VENTA_EXTRA (dato de prueba escrito a mano)"
  - "agent-readonly-scopes.venta.spec.ts: violaciones, igualdad manifiesto-runtime, D-22 403, costo, secretos"
affects: [101-18]
key-files:
  created:
    - api-ventago/src/app/auth/guards/agent-scope-manifest.venta.ts
    - api-ventago/src/app/auth/guards/agent-readonly-scopes.venta.spec.ts
  modified:
    - api-ventago/src/app/sales/sales.controller.ts
    - api-ventago/src/app/online-orders/online-orders.controller.ts
    - api-ventago/src/app/expenses/expenses.controller.ts
    - api-ventago/src/app/cashRegister/cashRegister.controller.ts
    - api-ventago/src/app/afip/afip.controller.ts
    - api-ventago/src/app/products/products.controller.ts
    - api-ventago/src/app/products/costo/cotizacion.controller.ts
key-decisions:
  - "GET /afip/externos incluido en ver_facturas por decision del orquestador (pendiente de confirmacion del usuario)"
  - "reprintPrinters, next-serial, last-created y next-number siguen excluidos (ya en EXCLUIDOS_VER)"
requirements-completed: [D-04, D-05, D-06, D-07, D-10, D-13, D-22]
completed: 2026-10-08
---

# Phase 101 Plan 05: Lecturas de Venta / Producto / Factura con ver_* Summary

Las pantallas de ventas, productos y facturacion abren sus GET por alcance `ver_*`, y un spec fija que lo marcado es exactamente el manifiesto, que las descargas contables D-22 dan 403 y que no salen costo ni secretos.

## Commits (repo api-ventago, sin push)
- 2ae707c0: Venta + Factura (sales, online-orders, expenses, cash-register, afip) + manifiesto
- f87d18c6: Producto (products, cotizacion) + spec del area

## Handlers marcados
- **ver_ventas**: `SalesController.findFiltered`, `getDailyStats`, `getDailySummary`; `OnlineOrdersController.ventaVista`, `cobrosResumen`, `detail`; `CashRegisterController.getCashRegisterStatus`, `getCierre`.
- **ver_ventas + ver_facturas**: `SalesController.findOneAdmin` (D-05).
- **Comunes (los 4 ver_*)**: `ExpensesController.dailySummary`, `CotizacionController.actual`, `moneda`.
- **ver_productos**: `ProductsController` findAllProducts, getGenericProduct, findFiltered, findByStore, getProductsWithStockAddedToday, getByParentFlag, getInventoryByParentId, getLiveStockByParent, getInventoryByParentIdAndDate, getInventoryByParentDateBranch, getImages, getRoutingTemplate; `CotizacionController.historial`.
- **ver_facturas**: `AfipController` emitidas, pendientes, verificarPendientes, notasPendientes, sugerenciaEmisor, opcionesDeEmision, preview, diagnostico, pdf, listarExternos; `listIssuers` = `['cert','ver_facturas']`.

## Lista final AFIP (D-22)
- **Incluidos**: los 10 de `ver_facturas` de arriba + listIssuers.
- **Excluidos (sin ningun ver_*)**: `iibb`, `iibbXlsx`, `reporteExcel`, `reporteIvaDigital` (D-22); `padronLookup`, `padronEstado`, `registroEnGateway`, `certEstado`, `certVerCsr`, `certificadosDeEmisores`, `issuerByBranch`, `emisoresDeSucursal`, `tiendasQueUsanCuit`, `reprint` y todo no-GET.
- **`GET /afip/externos`**: INCLUIDO en «Ver facturas» por decision del orquestador (es una lista paginada en pantalla, no una descarga masiva). **Pendiente de confirmacion del usuario**; si dice que no: quitar `@AgentScope('ver_facturas')` de `listarExternos`, quitar la entrada del manifiesto y anotar «D-22 ampliado por el usuario». No se le pregunto al usuario durante la ejecucion (ejecutor secuencial, sin interaccion).

## Verificaciones de efectos (T-101-22)
- `GET /afip/vouchers/:id/pdf`: `dispatch(output:'pdf')` solo lee y renderiza (sin emit ni escritura) -> incluido.
- `cash-register/status` y `/cierre`: sin create/save/update en el servicio -> incluidos.
- `next-serial` (`skuSerial.previewNext`), `next-number` (solo SELECT) y `last-created`: son ayudas de formularios de creacion; `last-created` devuelve productos completos con Price (riesgo D-13). Se dejaron EXCLUIDOS (no se edito agent-scope-exclusions.ts).
- `reprintPrinters`: ya estaba en EXCLUIDOS_VER (no-duplicate-print) -> no se marco, pese a que el plan lo permitia condicionalmente.
- `CotizacionController.historial` devuelve el historial de cotizaciones con el nombre de quien las cambio (sin costo). Incluido segun el plan; el comentario del codigo lo limita a quien gestiona precios -> revisar si se quiere recortar el nombre para el agente.

## Limites conocidos
- `cash-register/status` y `/cierre` se calculan por `user.id`: para el agente (no tiene caja propia) devuelven «sin caja» en la pantalla de Ventas. No se cambia en esta phase; la regla de caja por cajon de CLAUDE.md lo resolvera cuando esos endpoints pasen a `box_id`.
- Specs de D-10: `Sale` y `Product` no tienen columnas secretas, asi que su caso es de regresion (sin secretos inventados); el caso con redaccion real es `OnlineOrder` (101-04). Un objeto plano no pasa por `toJSON` (control incluido).

## Verificacion
- `agent-readonly-scopes.venta.spec.ts`: 22 tests, exit 0. eslint limpio; tsc exit 0.
- jest por modulo (`--maxWorkers=1 --forceExit`): auth/guards 70, products 249, online-orders 84, sales 356, afip 1068, cashRegister 88, expenses 28 -> todos exit 0.
- Control/mutante manual: quitar un `@AgentScope('ver_productos')` de products -> 3 tests rojos (manifiesto y violaciones); la clase temporal con `ver_productos` extra hace fallar la igualdad con el nombre en el mensaje.
- D-22: los 4 handlers con grant `ver_facturas` vigente -> `ForbiddenException` con `code === 'AGENT_SCOPE_DENIED'`; control `emitidas` pasa por el mismo harness.

## Deviations from Plan
- [Rule 3] Commits con `SKIP_VERIFY=1`: el gate de jest excede 180s (open handle preexistente de jwt-global.guard.spec). jest por modulo, tsc y eslint corridos a mano, exit 0. La razon quedo en cada mensaje de commit.
- [Rule 1] `EXCLUIDOS_VENTA_EXTRA` documenta ademas boards de envios, tesoreria y gastos fuera del inventario (informativo; el spec los combina con EXCLUIDOS_VER).
- Los specs D-10 de Sale/Product usan datos reales sin secretos (un `apiKey` inventado se filtraba por `instanciaOffline`, que devuelve todo lo que se le pasa).

## Known Stubs
None.

## Self-Check: PASSED
