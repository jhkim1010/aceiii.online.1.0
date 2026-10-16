---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 04
subsystem: api-mobile-pos
tags: [nestjs, pos-context, catalog, stock_balances, caja, tenant-isolation]
requires: ["111-03", "111-15"]
provides:
  - GET /mobile/pos/context, /catalog, /scan/:code, /matrix/:productId
  - POST /mobile/pos/cart/check, /mobile/pos/caja/open
  - PosPricingService, PosCatalogService (exported by PosContextModule for Plan 05)
  - MobileStockService.variantId (additive); MobileModule exports catalog/stock/sales services
  - PaymentMethodsModule exports PaymentMethodsService
key-files:
  created:
    - api-ventago/src/app/mobile/pos/context/pos-pricing.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/context/pos-catalog.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/context/pos-context.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/context/pos-context.controller.ts (+ spec)
  modified:
    - api-ventago/src/app/mobile/pos/context/pos-context.module.ts
    - api-ventago/src/app/mobile/stock/mobile-stock.service.ts (+ spec)
    - api-ventago/src/app/mobile/mobile.module.ts
    - api-ventago/src/app/payment-methods/payment-methods.module.ts
    - api-ventago/src/app/mobile/pos/shared/pos-contracts.ts
decisions:
  - Caja is looked up with getOpenCashRegisterByBox(device.boxId); openCaja returns the open session without calling createCashRegister (which would raise a declared initial amount 0 -> N on an already-open session)
  - Variant price per matrix entry added to PosMatrixResponse (costo por variacion makes it differ from the madre)
  - Stock for catalog/scan/matrix/cart check comes from stock_balances with store_id in the WHERE
metrics:
  completed: 2026-10-16
  api-commits: [e19fdf2a, 797cf888]
---

# Phase 111 Plan 04: Contexto, catalogo y caja del celular Summary

El celular ya puede pedir su contexto (sucursal, caja abierta o no segun SU cajon, medios de pago visibles, vendedores, perms, sin emitir sin ventana de dia, sucursales, mpQrDisponible), navegar catalogo/escaneo/matriz con ids de variante y stock de stock_balances, chequear precios/stock del carrito y abrir su propia caja con los roles de la web.

## Commits (api-ventago repo, not pushed)
- e19fdf2a feat(111-04): precios de lista, catalogo/scan/matriz y chequeo de carrito
- 797cf888 feat(111-04): context, caja/open y controlador con guards por ruta

## Verification
- jest `src/app/mobile src/app/payment-methods` (--maxWorkers=1): 19 suites, 215 tests verdes. tsc 0, eslint limpio, gate de commit paso en ambos.
- Mutaciones sobre pos-context.service: buscar la caja con otro boxId y quitar el chequeo `disconnectedAt` -> 3 tests fallan (multi-caja, caja abierta, mp desconectada). Restaurado (13+ tests verdes de nuevo).
- Acceptance greps: `getOpenCashRegisterByBox(` presente / `getOpenCashRegister(` ausente; sin guard de fichaje ni `storeDayWindow`; `resolveForScope(` presente; PaymentMethodsService exportado.

## Deviations from Plan
- **[Rule 2] `price` por variante en PosMatrixResponse:** el contrato de Plan 03 no lo traia; con «costo por variacion» cada variante se vende a su precio, asi que la matriz lo necesita. Cambio aditivo.
- Catalogo: el precio de la lista es el de la madre (como el catalogo existente); el precio exacto por variante se calcula en scan/matrix/cart-check con PosPricingService. El stock de la pagina se recalcula desde stock_balances (el MobileCatalogService existente suma el libro `stocks`).
- `imageUrl` y `barcode` salen `null`: no hay fuente barata; se pueden cablear despues sin cambiar el contrato.
- Un guard extra `AuthGuard('jwt')` se repite por ruta (viene dentro de `@FunctionGuard`/`@Auth`), igual que en MobileSalesController.

## Known Stubs
`imageUrl: null` y `barcode: null` en PosCatalogItem (ver arriba). No impiden el objetivo del plan.

## Notes
- No se hizo push; STATE.md y ROADMAP.md quedan sin commitear (tienen cambios ajenos). El gitlink de api-ventago en el root no se commiteo.
- El arranque real de Nest (DI de PosContextModule: MobileDevicesModule, MobileModule, CashRegisterModule, SellersModule...) no se probo contra una BD; solo tsc y specs con modelos simulados. Revisar al levantar la API local antes de Plan 14.
- Sin DDL/DML de produccion.

## Self-Check: PASSED
Commits e19fdf2a y 797cf888 existen en api-ventago; archivos creados presentes.
