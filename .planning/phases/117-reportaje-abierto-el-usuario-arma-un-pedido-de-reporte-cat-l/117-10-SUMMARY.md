---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 10
subsystem: api
tags: [reporte-medida, pedidos-guardados, raw-sql, tenant-isolation]
requires: ["117-02", "117-06"]
provides:
  - ReporteMedidaPedidosService (listar, obtener, crear, actualizar, reordenar, eliminar)
  - CrearPedidoDto, ActualizarPedidoDto, OrdenPedidosDto
affects: ["117-11"]
tech-stack:
  added: []
  patterns: ["raw SQL with bind, no Sequelize model", "uniform NotFound instead of 403"]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.dto.ts
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.service.ts
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.itest.ts
decisions:
  - "Itest sin harness Nest (regla del repo); servicio instanciado a mano con Sequelize directo"
  - "Tiendas de prueba con sufijo por corrida y sin borrado (regla del repo, en lugar de drop al inicio)"
metrics:
  completed: 2026-10-18
  tasks: 2
---

# Phase 117 Plan 10: Pedidos guardados Summary

Servicio de pedidos guardados de «Reporte a medida» en SQL crudo con bind: cada sentencia filtra `store_id = $1` (tienda de la sesión), las escrituras exigen dueño, y un id ajeno o de otra tienda siempre da NotFound.

## Commits (api-ventago, repo anidado)
- 96a99716 feat(117-10): pedidos guardados de Reporte a medida (dto + service)
- b1e9ddf7 test(117-10): itest pedidos guardados

No se hizo push.

## Verificación
- `npx tsc --noEmit` exit 0; eslint de la carpeta exit 0
- `npm run test:itest -- pedidos --forceExit`: 11/11 pasan
- Mutación: reemplazar `store_id = $1` por `$1::int IS NOT NULL` en `obtener` hace fallar el caso de tienda cruzada (restaurado)
- Criterios: 0 `replacements`, 0 `ForbiddenException`, NOMBRE_DUPLICADO presente, 1 mención de la tabla vs 8 `store_id = $1`

## Deviations from Plan
- Itest no usa `createImportHarness` ni borra tiendas al inicio (reglas del repo prevalecen sobre el plan).
- `validar` se tipa como `(order: Record<string, unknown>) => ErrorPedido[] | null` tal cual el contrato.

## Notas para 117-11
- Los errores 400/409 llevan `{ code, messageEs }` (400 de validación además `errores`).
- Ejecutar un pedido guardado debe revalidar con los permisos de quien abre (modo 'guardado').

## Self-Check: PASSED
