---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 14
subsystem: api
tags: [reporte-medida, pedidos, nestjs]
requires: []
provides:
  - "GET /reporte-medida/pedidos devuelve `order` en cada fila"
affects: [117-19, 117-24]
key-files:
  modified:
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.service.ts
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.itest.ts
decisions:
  - "Campo aditivo; WHERE de visibilidad sin cambios"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 14: listar() con order Summary

`listar()` de pedidos guardados ahora incluye `p.order_json` como `order`, con el mismo WHERE de tienda/propietario/compartido.

## Commits
- 42a68c57 (api-ventago, no pusheado): feat(117-14) listar devuelve order

## Verificación
- itest pedidos: 12/12 pasan (caso nuevo «listar devuelve el order guardado»).
- jest unitario pedidos: 3/3. tsc --noEmit: exit 0.
- Mutación (quitar `order` del map): el itest falla (error de tipo TS2339 en ts-jest); restaurado, pasa.

## Deviations from Plan
- RED falló por error de compilación de tipos (la propiedad `order` no existía), no por `undefined` en runtime; equivale a rojo. pedidos.service.spec.ts no requirió cambios.
- Sin push, por instrucción (despliegue en 117-24).

## Self-Check: PASSED
