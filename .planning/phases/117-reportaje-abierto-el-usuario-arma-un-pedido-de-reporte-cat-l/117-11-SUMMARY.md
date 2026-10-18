---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 11
subsystem: api
tags: [reporte-medida, http, controller, catalogo, codex-review]
requires: ["117-09", "117-10"]
provides:
  - ReporteMedidaController (12 endpoints bajo /reporte-medida)
  - construirCatalogo (respuesta pura del catálogo)
  - ReporteMedidaModule registrado en AppModule
affects: ["117-12", "117-13"]
requirements: [D-05, D-06, D-07, D-11, D-12, D-13, D-15, D-16, D-18, D-19, D-20, D-23, D-25, D-29]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/reporte-medida.controller.ts
    - api-ventago/src/app/reporte-medida/reporte-medida.controller.spec.ts
    - api-ventago/src/app/reporte-medida/reporte-medida.module.ts
    - api-ventago/src/app/reporte-medida/catalogo-respuesta.ts
    - api-ventago/src/app/reporte-medida/catalogo-respuesta.spec.ts
    - .team/reviews/117-11-codex.md
  modified:
    - api-ventago/src/app.module.ts
    - api-ventago/src/app/reporte-medida/csv.ts
    - api-ventago/src/app/reporte-medida/csv.spec.ts
decisions:
  - "Módulo sin imports: FunctionPermissionService y MemoryCacheService vienen del MemoryCacheModule @Global, Sequelize del DatabaseModule @Global"
  - "Sin exclusiones del agente: los handlers GET de ReporteMedidaController no aparecen en ninguna enumeración (los specs de agente no los marcan)"
metrics:
  tasks: 2
  completed: 2026-10-18
---

# Phase 117 Plan 11: HTTP de Reporte a medida Summary

Doce endpoints guardados por método (`@FunctionGuard('reporte-a-medida','read')`), tienda sólo de la sesión (403 si no hay), margen por `isAllowedStrict('reporte-a-medida-margen')`, pedidos guardados siempre en modo `guardado`, y un `construirCatalogo` puro con disponibilidad, bloqueo de margen y plantillas.

## Commits (api-ventago, repo anidado; sin push)
- c044dee5 feat(117-11): endpoints HTTP, catálogo y módulo
- bcdff35a test(117-11): spec del controlador
- 70ae9cfb fix(117-11): CSV protege fórmulas tras LF/espacios (CODEX)

## Verificación (por código de salida)
- `jest catalogo-respuesta`: 5/5; `jest reporte-medida.controller`: 8/8
- `jest src/app/reporte-medida src/app/store src/common/migrations src/app/reports/venta-universe --forceExit`: 49 suites, 732 tests, exit 0
- `tsc --noEmit` exit 0
- `grep -c "@FunctionGuard('reporte-a-medida', 'read')"` = 12; `PUT pedidos/orden` declarado antes de `pedidos/:id` (spec lo comprueba)
- Mutación: quitar `@FunctionGuard` de `DELETE pedidos/:id` hace fallar el spec de reflexión (1 failed, 7 passed); restaurado con `git checkout`
- Controles: una clase sin decorador falla el mismo helper

## Agente (T-117-44)
`jest src/app/auth/guards`: 7 suites pasan, `agent-readonly-scopes.venta.spec.ts` falla con 5 handlers que NO son de esta fase (`SalesController.findByStoreClient`, `ProductsController.listaCodigoVista|getCatalogVersion|getIngresosAceDelDia|getByParentDelta`; falta en manifiesto). Ningún `ReporteMedidaController.*` aparece, por lo que no se agregó ninguna exclusión (EXCLUIDOS_VER sin cambios). El fallo es previo y ajeno (ver Deferred).

## CODEX de fase (`.team/reviews/117-11-codex.md`)
Sin HIGH reales tras verificar contra la base local (PG18):
- HIGH «anulaciones no firman importes»: importes SÍ vienen firmados (Anulación: `total_amount` y `subtotal` negativos). Parcialmente válido sólo para **unidades y costo** (`quantity` positivo en 11.496 de 11.624 ítems de Anulación). `venta-universe.ts` se comparte con reportes existentes y la paridad con Ganancia es intencional; cambiarlo sin decisión rompería esa paridad. **No se cambió**; se eleva a 117-13/usuario.
- HIGH «JOIN sin store_id» en `sale_items` / `sale_payment_methods`: falso, esas tablas no tienen `store_id` (db-schema-tables); el aislamiento va por `sales.store_id = $1` + `sale_id`.
- HIGH `users u` sin store: 0 filas cruzadas en `reporte_medida_pedidos`; no se tocó (un owner superadmin puede tener `users.store_id` nulo y perdería el nombre).
- MED CSV con LF/espacios previos: corregido con test (70ae9cfb).
- MED mutaciones con `read`: el plan fija `read` y el slug admite una sola acción de menú; se deja y se anota.
- MED `variacionTotal` con período parcial, MED fallback de `spm.amount` nulo (fan-out), LOW reordenar en dos sentencias: pendientes para 117-13 (itest contra Ganancia).
- Sin inyección SQL, sin fuga de margen para no admin, sin I/O dentro de transacción (según CODEX).

## Deviations from Plan
- **Rule 3**: `timeout` no existe en macOS y el jest de guards quedó colgado sin `--forceExit`; se usó `--forceExit` en los suites de registro.
- El controlador toma `FunctionPermissionService` por constructor (no hace falta import de módulo, ver decisión).

## Deferred / notas para 117-13
- `FILTROS.vendedores.tabla` sigue siendo `users`; el servicio mapea a `"Sellers"` localmente (no afecta el contrato HTTP).
- Decidir unidades/costo de Anulación (signo de `quantity`) con paridad Ganancia.
- `variacionTotal` con períodos parciales y fan-out de pagos con `amount` nulo.
- Fallo previo `agent-readonly-scopes.venta.spec.ts` (5 handlers ajenos).

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo.

## Self-Check: PASSED
