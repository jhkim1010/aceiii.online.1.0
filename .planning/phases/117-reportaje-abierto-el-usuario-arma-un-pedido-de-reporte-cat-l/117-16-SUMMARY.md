---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 16
subsystem: ui
tags: [reporte-medida, formato, es-AR, periodo, tdd]
requires: []
provides:
  - "formato.ts: formatearValor/Moneda/Entero/Decimal/Porcentaje/Variacion/EjeCorto/RangoFechas, esCifraMono"
  - "periodo-local.ts: resolverPeriodoLocal, alineacionLocal, comparacionLocal, diasEnRango, incluyeHoy, hoyEnZona"
affects: [117-17, 117-18, 117-19, 117-20, 117-21, 117-22, 117-23]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/formato.ts
    - ventago-app/src/views/reports-v2/a-medida/periodo-local.ts
    - ventago-app/src/__tests__/reporte-medida-formato.spec.ts
    - ventago-app/src/__tests__/reporte-medida-periodo.spec.ts
decisions:
  - "Moneda negativa: «−$ 5.000» (signo U+2212 delante del símbolo)"
  - "Agrupado de miles propio (regex), sin Intl.NumberFormat: no depende del ICU"
  - "Variación que redondea a 0 se muestra «= 0 %» (signo cero)"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 16: Formato es-AR y período local Summary

Funciones puras de formato es-AR (miles «.», decimales «,», moneda «$ 1.234», porcentaje desde fracción, variaciones con flecha y signo) y port fiel de period.ts del servidor para el rango orientativo del período y de la comparación.

## Commits (ventago-app, no pusheados)
- fe813e48: formato.ts + spec (14 tests)
- ce5d0f30: periodo-local.ts + spec (24 tests)

## Verificación
- formato: 14/14. Mutación (separador de miles «.» → «,») hace fallar 6 tests; restaurado.
- periodo: 24/24 también con TZ=Asia/Seoul. Mutación 364 → 365 falla 1 test; restaurado.
- eslint de los 4 archivos exit 0; 0 usos de `style: 'currency'`, NBSP ni `getDate/getMonth/getFullYear/getDay` en la implementación.
- Casos de VALIDATION D-31/D-31a (2026-08-14..2026-09-12, 2026-09-01..2026-09-17, 2024-10-18..2025-10-17, 2026-04-20..2026-07-17, −364 días) cubiertos.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] RED no commiteable por el gate de commit**
- **Found during:** Task 1
- **Issue:** el hook pre-commit corre app tsc; una spec que importa un módulo inexistente falla tsc y bloquea el commit `test(...)`. No se usó SKIP_VERIFY.
- **Fix:** RED se confirmó corriendo jest (falla por módulo inexistente) y se commiteó spec + implementación juntas como `feat`. No hay commit `test(117-16)` separado.
- **Commits:** fe813e48, ce5d0f30

## TDD Gate Compliance
Advertencia: no existe commit `test(117-16)` independiente (ver desviación). La fase RED se verificó localmente antes de implementar en ambas tareas.

## Known Stubs
Ninguno.

## Self-Check: PASSED
