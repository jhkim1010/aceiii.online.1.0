---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 12
subsystem: reporte-medida
tags: [reconciliation, deploy, jenkins, read-only]
requires: [117-03, 117-11, 117-13]
provides:
  - conciliación read-only compilado vs SQL a mano en datos de producción
  - código de Reporte a medida desplegado (api_ventago, build #1202)
key-files:
  created:
    - api-ventago/scripts/reporte-medida-conciliacion.ts
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 12: conciliación en producción y despliegue Summary

Conciliación read-only en tiendas 26/30/19 (compilado = SQL a mano al centavo), suites completas verdes salvo fallos preexistentes, y api-ventago desplegado (build #1202, 401 en la ruta nueva).

## Tarea 1 — Conciliación (commit api-ventago `f3380ac5`)

El script genera `BEGIN READ ONLY; … ROLLBACK;` con PREPARE/EXECUTE derivados de los casts del SQL compilado (sin tipos fijos), SQL a mano independiente y monitor de duplicados. Período: 2026-07-01..2026-09-30, sucursal×mes, tz Buenos Aires.

- Dry-run local PG18 (exit 0): tiendas 26/30/19 no tienen datos locales; se repitió con tiendas 1295 y 1293 (con datos): compilado = a mano en todas las filas; item vs cabecera 0.4375 % (1295).
- Producción (puerto 5434, exit 0):

| Tienda | Compilado vs a mano (venta neta, unidades, tickets) | Item vs cabecera | Duplicados |
|---|---|---|---|
| 26 | iguales (3 filas, sucursal 39) | 0.0488 % | 0 |
| 30 | iguales (3 filas, sucursal 45) | 0.0492 % | 0 |
| 19 | iguales (3 filas, sucursal 28) | 0.0055 % | 1: 140311/242 (línea base) |

## Tarea 2 — Suites y despliegue

- Jest completo (`--maxWorkers=1`): 559 suites ok, 2 fallan, 4 tests (6979 ok). Fallos fuera de reporte-medida/reports/store/auth:
  - `auth/guards/agent-readonly-scopes.venta.spec.ts` (preexistente, listado en HANDOFF-2026-10-16).
  - `box-operation/box-operation-amount-sign.spec.ts` (falla por depender de la fila local «caja #241» en la base; ajeno a esta fase, no tocado).
- Itests: `reporte-medida` (5 suites, 52 tests) y `venta-universe` (11 tests) en exit 0.
- Antes del push: hora BA 2026-10-18 01:28 (fuera de 08–16), usuarios activos (15 min, sin user 1/61): 1. Semilla/tabla en prod verificada (tabla `reporte_medida*` presente).
- Push api-ventago `42b039dd..f3380ac5`. Jenkins `api-new-coolsistema` build #1202 contiene el SHA f3380ac5 y terminó SUCCESS. Contenedor `api_ventago` recreado 04:30:46 UTC, healthy. Smoke `GET /api/reporte-medida/catalogo` → 401.
- Push del repo raíz (puntero api-ventago + docs): ver commit de metadatos.

## Deviations from Plan

None - plan ejecutado tal cual (se añadió un argumento opcional de tiendas al script para el dry-run con datos locales).

## Gate pendiente

D-24: validación del mockup v2 por 2–3 dueños es acción del usuario y condiciona la ronda de UI.

## Self-Check: PASSED
