---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 09
subsystem: auth
tags: [nestjs, agent-scope, ver_admin, usuarios, permisos, roles]
requires: [101-01, 101-03, 101-04]
provides:
  - "15 handlers GET con ver_admin en 6 controladores (usuarios, roles, funciones por rol/usuario, catalogo de funciones, /permissions)"
  - "MANIFIESTO_ADMIN + EXCLUIDOS_ADMIN_EXTRA"
  - "agent-readonly-scopes.admin.spec.ts (20 tests)"
affects: [101-18]
key-files:
  created:
    - api-ventago/src/app/auth/guards/agent-scope-manifest.admin.ts
    - api-ventago/src/app/auth/guards/agent-readonly-scopes.admin.spec.ts
  modified:
    - api-ventago/src/app/users/users.controller.ts
    - api-ventago/src/app/role/role.controller.ts
    - api-ventago/src/app/role/role-function/role-function.controller.ts
    - api-ventago/src/app/users/user-function/user-function.controller.ts
    - api-ventago/src/app/functions/functions.controller.ts
    - api-ventago/src/app/permissions/permissions.controller.ts
key-decisions:
  - "RoleController no comprobaba el storeId de la URL/query (GET /role?storeId, GET /role/store/:storeId). Antes de marcarlos se agrego assertTiendaPropia: 403 si no es la tienda de quien llama; superadmin conserva el cruce."
  - "UserFunctionController.getEffectiveFunctions (POST effective/:userId) queda SIN alcance (D-04, POSTS_QUE_LEEN vacio); candidato a «sin alcance» si la pantalla lo necesita."
requirements-completed: [D-03, D-04, D-06, D-10, D-12]
completed: 2026-10-08
---

# Phase 101 Plan 09: ver_admin en usuarios y permisos Summary

Con `ver_admin` el agente ve usuarios (lista, ficha, por tienda), roles, funciones por rol/usuario, el catalogo de funciones y los GET de `/permissions` (matriz, por-funcion, keys, detalle de usuario). Toda escritura de permisos sigue sin alcance (403 para el agente).

## Commits (repo api-ventago, sin push)
- 3b9343f7: decoradores en 6 controladores + comprobacion de tienda en RoleController
- c45121f3: MANIFIESTO_ADMIN + spec

## Handlers marcados (todos `@AgentScope('ver_admin')`, todos GET)
- `UsersController`: findAll, findOne, findAllByStorePaginated
- `RoleController`: findAll, findOne, findAllByStorePaginated
- `RoleFunctionController.getFunctionsByRole`, `UserFunctionController.getUserFunctions`
- `FunctionsController`: getStructure, accionesDeGuardia, findAllFunctionsPaginated (catalogo, sin datos de tienda)
- `PermissionsController`: getMatrix, getPorFuncion, listPermissionKeys, getUserDetail

## Secretos (D-10)
- `users`: `defaultScope` excluye `password`/`mobilePin`; las consultas de lista/ficha/por tienda ademas excluyen `password`. Sequelize 6.37 une los `exclude` (verificado en `_mergeFunction`), asi que `mobilePin` tampoco sale con `attributes` propios. Los roles en la lista por tienda ya se filtran por `role.storeId === user.storeId`.
- Spec: una base simulada cuya fila trae `password` y `mobilePin` aplica el `defaultScope` REAL del modelo + el `exclude` de la consulta; `camposSecretosEn` de las tres respuestas = [] y el valor no aparece. Control: la fila SI trae ambos.
- Mutacion 1: quitar `mobilePin` del defaultScope -> 4 tests fallan. Mutacion 2: quitar la comprobacion de tienda en `role/store/:storeId` -> 1 test falla. Ambas restauradas.

## Aislamiento (D-03)
- `users/store/:storeId` (assertMismaTienda) y `users/:id` (404) ya comprobaban tienda; ahora estan en spec.
- `role` no lo hacia: el hook de tenant estrechaba la consulta, pero se hizo explicito (403) como en 101-08. Cambia el comportamiento solo para quien pedia una tienda ajena (antes: lista vacia por el hook).
- `role-functions/:roleId` y `user-functions/:userId` usan `user.storeId`, no la URL. Permissions: `storeId` por query solo para superadmin.

## Excluidos
`UserFunctionController.getEffectiveFunctions` (POST), `UsersController.getSellersByStore` (lo cubre SellersController), `FunctionsController.getAll/getById` (heredados).

## Deviations from Plan
- [Rule 2] Comprobacion de tienda (403) en `RoleController.findAll` (con `?storeId`) y `findAllByStorePaginated`; se agrego `@GetUser` a ambos.
- [Rule 3] Commit 2 con `SKIP_VERIFY=1`: el gate de jest supera 180s (open handle preexistente). Jest manual `--maxWorkers=1 --forceExit` exit 0 en `src/app/auth/guards`, `src/app/users`, `src/app/permissions`, `src/app/role`; `src/app/functions` no tiene specs; tsc exit 0.

## Pre-existing defects found
- `RoleController` no tenia ningun `@Auth` en sus lecturas y el `:storeId` de la URL llegaba al servicio sin comprobar (corregido arriba porque son handlers que se marcan). Las filas `roles` con `store_id` NULL (globales, 4 en produccion) siguen visibles para todas las tiendas por diseno del hook (`GLOBAL_ROW_TABLES`); no se toco.

## Known Stubs
None.

## Self-Check: PASSED
3b9343f7 y c45121f3 existen en api-ventago; manifiesto y spec existen.
