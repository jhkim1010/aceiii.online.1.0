---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 09
subsystem: api-ventago/reporte-medida
tags: [post-process, service, tenant-isolation, comparison, csv]
requires: [117-05, 117-06, 117-07, 117-08]
provides: [postProcesar, normalizarMedioPago, exigirCsvCompleto, ResultadoReporte, ReporteMedidaService, resolveReportBranchScope]
affects: [117-10, 117-11, 117-13]
requirements: [D-01, D-02, D-03, D-04, D-06, D-07, D-08, D-09, D-10, D-17, D-19, D-20, D-21, D-22, D-26, D-28, D-30, D-31, D-31a, D-32]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/post-process.ts
    - api-ventago/src/app/reporte-medida/post-process.spec.ts
    - api-ventago/src/app/reporte-medida/reporte-medida.service.ts
decisions:
  - "Porcentajes (participación, variación, margen_pct) salen como fracción; el formato es-AR es de la UI"
  - "Comparación alineada por posición de bucket respecto del inicio de cada rango (no por índice de fila), robusto a huecos"
  - "Un Top N pedido no cuenta como truncamiento; sólo el exceso sobre el límite del modo marca truncado"
  - "`parcial` y variación null sólo se calculan cuando hay comparación"
metrics:
  tasks: 2
  completed: 2026-10-18
---

# Phase 117 Plan 09: Post-proceso y servicio de ejecución

`postProcesar` puro (participación sobre el total, totales, comparación con buckets parciales D-31/D-31a, días sin ventas, orden de talles, etiquetas «Sin X», medios de pago normalizados, meta con fuentes/notas/definición) y `ReporteMedidaService` con la tubería validar → pertenencia de ids → compilar → ejecutar → post-procesar, más CSV.

## Commits (repo api-ventago, sin push)
- `d7783749` feat(117-09): post-proceso de Reporte a medida
- `259fd5fd` feat(117-09): servicio de ejecución de Reporte a medida

## Verificación (por código de salida)
- `jest post-process`: 15 tests OK
- Mutación del denominador (Σ filas en vez del total): el spec «participación» FALLA (1 failed, 14 passed); restaurado y vuelve a 15/15
- `jest src/app/reporte-medida src/app/reports/venta-universe`: 10 suites, 199 tests OK
- `npm run test:itest -- executor availability`: 2 suites, 9 tests OK (sin regresión)
- `tsc --noEmit` exit 0; eslint de los 3 archivos exit 0
- greps: `replacements` 0, `resolveReportBranchScope` 1, `FILTRO_ID_INVALIDO` 1, `exigirCsvCompleto` 2, `new Date()` fuera de comentarios 0

## Deviations from Plan

1. **[Rule 1 - Bug] Filtro vendedores contra "Sellers"**: `FILTROS.vendedores.tabla` dice `users`, pero `sales.seller_id → "Sellers"` (db-schema-fks) y el compilador filtra/etiqueta con "Sellers". La pertenencia se verifica contra `"Sellers"` con una tabla local en el servicio; el catálogo no se tocó. Conviene corregir `FILTROS.vendedores.tabla` (y revisar qué ids manda el selector de la UI en 117-10).
2. **TDD**: implementación y spec se escribieron juntos; no se corrió una RED separada. El control se hizo con la mutación (arriba). Los hooks pidieron corregir prettier y `no-base-to-string` antes del commit.
3. **`hoyDeTienda`/zona**: `exportarCsv` usa `hoy` para el nombre del archivo vía un método privado `correr` (para no consultar zona/hoy dos veces); `ejecutar` es un wrapper.
4. **Fuentes**: `meta.fuentes` siempre trae `legacy` y `pos` (0 si faltan) además de las fuentes devueltas.

## Notas para planes siguientes
- 117-11: `validar`/`ejecutar` lanzan 400/403 con `{ code, messageEs, fixes, errores }`; pertenencia inválida = 400 `FILTRO_ID_INVALIDO`; CSV truncado = 422 `CSV_DEMASIADAS_FILAS`.
- 117-13: stubear `hoyDeTienda` con `jest.spyOn`; probar pertenencia cruzada entre tiendas y la comparación contra Ganancia.
- Con Top N la comparación usa su propio Top N: una fila del período actual puede no tener contraparte (`_comp` null).

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo (T-117-31/33/35 mitigados en el servicio; T-117-32 por `margenPermitido` en el validador; T-117-34 con los controles del spec, el resto en 117-13).

## Self-Check: PASSED
