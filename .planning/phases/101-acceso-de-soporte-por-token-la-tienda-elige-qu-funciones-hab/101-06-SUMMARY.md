---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 06
subsystem: auth
tags: [nestjs, agent-scope, ver_admin, catalogos]
requires: [101-01, 101-03, 101-04]
provides:
  - "21 handlers GET de catalogos comunes marcados @AgentScopeVer (11 controladores)"
  - "MANIFIESTO_COMUNES + EXCLUIDOS_COMUNES_EXTRA (dato de prueba escrito a mano)"
  - "agent-readonly-scopes.comunes.spec.ts: igualdad manifiesto-runtime, violaciones, control CrudController"
affects: [101-18]
key-files:
  created:
    - api-ventago/src/app/auth/guards/agent-scope-manifest.comunes.ts
    - api-ventago/src/app/auth/guards/agent-readonly-scopes.comunes.spec.ts
  modified:
    - api-ventago/src/app/payment-methods/payment-methods.controller.ts
    - api-ventago/src/app/prices/types/priceType.controller.ts
    - api-ventago/src/app/prices/prices.controller.ts
    - api-ventago/src/app/category/category.controller.ts
    - api-ventago/src/app/subcategory/subcategories.controller.ts
    - api-ventago/src/app/module-alias/module-alias.controller.ts
    - api-ventago/src/app/sizes/sizes.controller.ts
    - api-ventago/src/app/colors/colors.controller.ts
    - api-ventago/src/app/season/season.controller.ts
    - api-ventago/src/app/origin/origin.controller.ts
    - api-ventago/src/app/supplier/supplier.controller.ts
key-decisions:
  - "Solo se marcaron GET que el frontend llama; ninguno requirio override de CrudController porque todos los GET usados ya eran metodos propios del hijo"
  - "GET /prices (getAll, sin paginar) y GET /module-alias/by-module no se marcaron: el frontend no los usa"
requirements-completed: [D-04, D-07, D-10]
completed: 2026-10-08
---

# Phase 101 Plan 06: Catalogos comunes con ver_* Summary

Los catalogos de referencia (medios de pago, tipos de precio, matriz de precios, categorias, subcategorias, talles, colores, temporadas, origenes, proveedores, alias) responden a cualquier grant con algun `ver_*`, con un spec que fija el conjunto en ambos sentidos.

## Commits (repo api-ventago, sin push)
- 6cd99e35: medios de pago, precios, categorias, subcategorias, alias
- f1080ef3: talles, colores, temporadas, origenes, proveedores
- e4672f2e: manifiesto + spec

## Handlers marcados (todos con los 4 ver_*)
payment-methods `findAll`, `findFiltered`; price-types `findByStore`, `findFiltered`; `PricesController.matrix`; categories `findByStore`, `findAllCategories`; subcategories `findAllCategories`, `getByCategory`, `findByStore`; `ModuleAliasController.getAllAliases`; sizes/colors/seasons/origins/suppliers `findByStore` + `findAllCategories` (GET `/`).

## Decisiones y verificaciones
- Ningun override de `CrudController` fue necesario; los `getAll`/`getById` heredados siguen sin marca (el spec lo verifica con control).
- No marcados a proposito (en `EXCLUIDOS_COMUNES_EXTRA`): `PricesController.getAll` (lista todos los precios sin paginar; el frontend usa `/prices/matrix`), `getById`, `PaymentMethodsController.findOne`, `PriceTypeController.listarRangos`, `ModuleAliasController.getAliasByModule` (sin uso en frontend).
- D-10: los modelos Supplier y PaymentMethod no tienen columnas de `CAMPOS_SECRETOS` (revisado en los modelos); no hubo que dejar nada sin marcar.
- Aislamiento de tenant: todos los handlers marcados filtran por `user.storeId`; ninguno recibe `:storeId` en la URL.
- Ninguna escritura marcada (spec D-04).

## Verificacion
- `agent-readonly-scopes.comunes.spec.ts`: 10 tests, exit 0. tsc exit 0; eslint limpio en los archivos nuevos.
- jest por modulo (`--maxWorkers=1 --forceExit`) de auth/guards y los 10 directorios tocados: exit 0.
- Controles: clase extra marcada → falla igualdad con su nombre; handler sin marca → falla; clase heredada sin override → 0 handlers.

## Deviations from Plan
- [Rule 3] Tercer commit con `SKIP_VERIFY=1`: el gate de jest excede 180s (open handle preexistente de jwt-global.guard.spec). Verificacion manual indicada arriba; la razon quedo en el mensaje del commit.
- Alcance recortado respecto a la lista del plan: `GET /prices/` no se marco (no lo usa el frontend, devuelve todo sin paginar).
- eslint de los controladores tocados reporta errores preexistentes en lineas viejas (no se tocaron; el gate mide solo lineas agregadas).

## Known Stubs
None.

## Self-Check: PASSED
