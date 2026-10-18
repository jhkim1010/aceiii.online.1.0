---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 17
subsystem: ui
tags: [reporte-medida, logica-pura, tdd, espejo]
requires: ["117-15", "117-16"]
provides:
  - "pedido-logica.ts: PEDIDO_INICIAL, GRANO_POR_DIMENSION, granoDelPedido, estadoMetricas, estadoDimensiones, alternarMetrica, alternarDimension, quitarBloqueadas, adaptarGuardadoAlCatalogo, idDesdeQuery, cambiarGranoTiempo, metricasAuto, aplicarFix, serializarPedido, firmaPedido, resumenLocal, opcionesOrden"
  - "spec espejo contra catalog.ts / order.types.ts / order.validator.ts"
affects: [117-20, 117-21, 117-22]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/pedido-logica.ts
    - ventago-app/src/__tests__/reporte-medida-pedido.spec.ts
    - ventago-app/src/__tests__/reporte-medida-espejo.spec.ts
decisions:
  - "Firmas: granoDelPedido/estadoMetricas/etc. reciben (catalogo, pedido); alternarDimension devuelve {pedido, quitadas, avisoEs}"
  - "idDesdeQuery devuelve number | null"
  - "Sin dimensiones, opcionesOrden ofrece sólo «Orden natural»; con talle, «Talle (orden natural)»"
  - "El texto «sólo los N primeros» va al final de la cola del resumen"
  - "Las métricas automáticas no se bloquean por máximo y alternarMetrica nunca pasa de 4 elegidas"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 17: Lógica del constructor y espejo Summary

Reglas puras del constructor (bloqueos con motivo del catálogo, auto-quitar métricas al cambiar grano/filtros, métricas automáticas con comparación, guardado sin margen, serialización de contrato v1) más una spec espejo que falla si el servidor cambia ids, granos o el umbral de alta cardinalidad.

## Commits (ventago-app, no pusheados)
- a6c5d196: pedido-logica.ts + spec (34 tests)
- 529a9f92: spec espejo (5 tests)

## Verificación
- jest: pedido 34/34, espejo 5/5; eslint de los 3 archivos exit 0.
- Mutaciones (restauradas): medio_pago → cabecera = 8 fallos; ignorar `bloqueada` = 2; quitarBloqueadas sólo tickets = 2; talle → cabecera rompe el espejo; ruta de servidor inexistente = 5 fallos (no pasa vacía).
- Gates grep: sin textos fijos de métricas, sin store_id/isAdmin/roles en pedido-logica.ts.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] RED no commiteable por el gate de commit**
- El hook corre app tsc; una spec que importa un módulo inexistente bloquea el commit. Spec + implementación se commitearon juntos como `feat`. Además la implementación se escribió antes de correr la spec, así que RED (módulo inexistente) no se ejecutó por separado; la validez de la spec se respaldó con las mutaciones.
- Commits: a6c5d196

## TDD Gate Compliance
Advertencia: no existe commit `test(117-17)` previo a `feat(117-17)` para la Task 1 (ver desviación).

## Known Stubs
Ninguno.

## Self-Check: PASSED
