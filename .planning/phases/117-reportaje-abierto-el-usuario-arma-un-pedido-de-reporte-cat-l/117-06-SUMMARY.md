---
phase: 117-reportaje-abierto
plan: 06
subsystem: api-ventago/reporte-medida
tags: [validator, security, tdd, catalog-driven]
requires: [117-04]
provides: [validarPedido, hashPedido]
affects: [117-09, 117-10, 117-11]
tech-stack:
  added: []
  patterns: [pure-function validator, errors-as-data, allowlist from catalog constants]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/order.validator.ts
    - api-ventago/src/app/reporte-medida/order.validator.spec.ts
key-decisions:
  - "Una dimensión 'alta' sólo cuenta como tal si su cardinalidad real > 30 (producto siempre cuenta; desconocida = alta)"
requirements: [D-07, D-10, D-12, D-14, D-19, D-21, D-30, D-31, D-31a]
metrics:
  completed: 2026-10-17
  tasks: 2
  files: 2
---

# Phase 117 Plan 06: Validador estricto de pedidos Summary

Validador puro y dirigido por el catálogo (`validarPedido`, `hashPedido`) que acepta sólo ids del catálogo, aplica límites, combinaciones prohibidas, bloqueos por grano, permiso de margen y comparación D-31/D-31a, sin dependencias nuevas.

## Resultado

- Commit (repo api-ventago): `0300f9d8` feat(117-06). No se hizo push.
- jest `src/app/reporte-medida --maxWorkers=1`: 4 suites, 124 tests OK. tsc exit 0, eslint limpio sobre ambos archivos.
- Los bloqueos se evalúan iterando `METRICAS[*].bloqueadaCon` y `soloConDimensiones` (datos), con un respaldo por `granos` de la métrica (por ejemplo margen con medio de pago).
- Errores acumulados en la fase 2; la fase 1 (estructura/ids) corta antes de calcular lo que depende de ids válidos.

## RED (Task 1)

Se movió la implementación fuera y se corrió jest: exit 1 con `Cannot find module './order.validator'` (TS2307), sin SyntaxError ni OOM. Spec no commiteado solo; se commiteó junto con la implementación.

## Mutaciones (Task 2)

- (a) Desactivar el chequeo CLAVE_DESCONOCIDA: 8 tests fallan.
- (b) Ignorar el grano `pago` en los bloqueos: 1 test falla (los demás casos de pago los sigue atrapando el respaldo por `granos`; el test que compara el motivoEs exacto del catálogo cae).
Ambas revertidas; archivo restaurado y verificado con diff.

## Deviations from Plan

**1. [Rule 1 - Conflicto de especificación] Umbral de cardinalidad para «alta»**
- **Problema:** la plantilla `talle_por_color` (dos dimensiones `alta` en el catálogo) debía validar ok, pero la regla «>1 alta → DEMASIADAS_ALTA_CARDINALIDAD» la rechazaba.
- **Fix:** siguiendo CONTEXT («según cardinalidad real»), una dimensión alta cuenta sólo si `disponibilidad[d].cardinalidad > 30`; producto siempre cuenta; sin dato se asume alta. Spec cubre ambos lados (talle×color de cardinalidad baja pasa; color 200 × talle 90 falla).

**2. Spec: ejemplo de D-31a «ultimos_12_meses por mes → 2024-10-18..2025-10-17»** corresponde a `periodo_anterior` (con `anio_anterior` y 365 días saltaría COMPARAR_ANIO_LIMITE); se probó con `periodo_anterior`.

**3. Lint del gate** obligó a ajustes menores (tipado `unknown`, quitar aserción innecesaria); sin cambio de comportamiento.

## Known Stubs

Ninguno.

## Self-Check: PASSED

- order.validator.ts y order.validator.spec.ts existen y están commiteados (`0300f9d8`).
