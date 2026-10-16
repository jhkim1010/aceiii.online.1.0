---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 07
subsystem: api-mobile-pos
tags: [nestjs, stock-ledger, idempotency, tenant-isolation, colibri]
requires: ["111-01", "111-03", "111-15"]
provides:
  - POST /mobile/pos/stock/ingreso, GET /mobile/pos/stock/ingreso/by-key/:key, GET /mobile/pos/stock/balances/:branchId, GET /mobile/pos/stock/branches
  - ProductStockService.ingresarStockPorProductos accepts type null (explicit NULL ledger rows)
key-files:
  created:
    - api-ventago/src/app/mobile/pos/stock/pos-stock.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/stock/pos-stock.controller.ts (+ spec)
    - api-ventago/src/app/mobile/pos/stock/pos-stock.itest.ts
  modified:
    - api-ventago/src/app/mobile/pos/stock/pos-stock.module.ts
    - api-ventago/src/app/products/productStock.service.ts
    - api-ventago/src/app/products/productStock.ingreso-productos.spec.ts
decisions:
  - Idempotency claim row is inserted inside the same transaction as the ledger rows; a unique violation rolls back and the existing row is read in a NEW query
  - Branch of balances goes in the path (MobileScopeGuard rejects ?branchId when scopeBranchIds=[]); a vendedor with a bounded scope gets 403 for out-of-scope branches
  - Permission is editar-stock-de-producto/update; no permission row seeded
metrics:
  completed: 2026-10-16
  api-commits: [314adad8, d511fce7, a22b4e11]
---

# Phase 111 Plan 07: Ingreso de stock desde el celular Summary

Un lote confirmado en el celular escribe filas de `stocks` (type NULL, por product_branch_id, las mismas que el ingreso web) en UNA transaccion junto con su claim idempotente, solo para quien tiene editar-stock-de-producto/update.

## Commits (api-ventago repo, not pushed)
- 314adad8 feat(111-07): ledger writer accepts explicit NULL type
- d511fce7 feat(111-07): PosStock ingreso idempotente en una transaccion, by-key, balances y sucursales
- a22b4e11 test(111-07): itest de ingreso movil contra la BD

## Medicion Task 2 paso 0 (produccion, solo SELECT, 2026-10-16 ~10:03, puerto 5434)
- (a) role_functions de `editar-stock-de-producto` con `delete` sin `update`: **0**
- (b) user_function_actions con `delete` allowed=true sin `update` allowed=true: **0**
Nadie que hoy puede borrar el ingreso queda sin poder ingresar desde el celular. No hay bloque de decision pendiente. No se sembro ningun permiso (sin migracion nueva).

## Callers de ingresarStockPorProductos / writeStockRows
- `ProductStockService.ingresarStockPorMatrix` (-> lote.service.ts:208) pasa `type` sin definir o un StockMovementType: sin cambio ('production').
- `subcon/recepciones/recepcion.service.ts:535` no pasa type: sigue 'production'.
- `PosStockService` (nuevo) es el unico que pasa `null`.

## Verificacion
- jest `src/app/products src/app/mobile/pos/stock` (--maxWorkers=1): 29 suites, 335 tests verdes. tsc 0, eslint limpio, gate de commit paso en los 3 commits.
- itest (`test/itest/jest-itest.json`, PG18 local 5432): 5 tests verdes — filas type NULL por product_branch_id, stock_balances +6/+5, v_product_branch_daily_ingreso +11, claim completed; replay sin filas nuevas; madre -> 422 sin filas ni claim; variante de otra tienda -> 404 sin filas; misma clave otro cuerpo -> 422 CLAVE_CONFLICTO.
- Mutaciones (todas compilaron, no "Tests: 0"):
  - `params.type ?? STOCK_TYPE.PRODUCTION` en vez de `=== undefined`: falla «type: null -> NULL fila (web igual)».
  - quitar `storeId` de la consulta de variantes: sobrevivio al primer spec (el mock lo ignoraba); se agrego «la consulta de variantes lleva storeId del token» y entonces falla.
  - quitar `type: null` del wrapper: el itest falla en «ingreso de 2 variantes: filas type NULL ...» (los otros 4 pasan).
- Acceptance: `params.type === undefined` presente; `params.type ?? STOCK_TYPE.PRODUCTION` ausente; `type: null` en pos-stock.service.ts; `storeId` en la consulta tenant de Product; `git diff --stat -- api-ventago/migrations` vacio.

## Deviations from Plan
- **[Rule 3] itest sin app Nest:** `createImportHarness` no levanta hoy (WebsocketGateway pide SocketCensusService, preexistente; mismo motivo que ya anota `sales-revert-nullify.itest.ts`). Se usa Sequelize directo con `collectModels()` y se instancia `PosStockService` a mano; caja/terminal se crean por SQL (sin createStoreDefaults).
- **[Rule 2]** Chequeo extra de alcance en el controlador: un vendedor con `scopeBranchIds` acotado no puede apuntar a una sucursal fuera de su alcance (salvo la del dispositivo); alcance vacio (admin/gerente) pasa. Cubierto por controller spec.
- El `@Audit` no se agrego (el plan no lo pedia y el tipo exige entidades del catalogo de auditoria).

## Known Stubs
Ninguno.

## Notes
- No se hizo push. STATE.md y ROADMAP.md quedan sin commitear a proposito; el gitlink de api-ventago en el root no se commiteo.
- Requiere la tabla `mobile_stock_ingresos` (migracion Phase 111 del Plan 01) aplicada antes de desplegar; existe en el PG local.
- Este plan toca el escritor de libro de la web (`productStock.service.ts`): debe salir junto con el resto (Plan 14).
- El arranque real de Nest (DI de PosStockModule: MobileDevicesModule, ProductsModule, AuthModule) no se probo contra una BD; solo tsc, specs y el itest sin DI. Revisar al levantar la API local antes de Plan 14.
- Sin DDL/DML de produccion (solo los 2 SELECT del paso 0).

## Self-Check: PASSED
Commits 314adad8, d511fce7, a22b4e11 existen en api-ventago; los 8 archivos del plan presentes.
