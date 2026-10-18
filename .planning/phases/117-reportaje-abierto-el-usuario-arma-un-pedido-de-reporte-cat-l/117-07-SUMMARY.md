---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 07
subsystem: api-ventago/reporte-medida
tags: [sql-compiler, tdd, tenant-isolation, bind-only]
requires: [117-01, 117-04]
provides: [compilarPedido, ReporteCompilado, ColumnaDef]
affects: [117-09]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/compiler.ts
    - api-ventago/src/app/reporte-medida/compiler.spec.ts
    - api-ventago/src/app/reporte-medida/__snapshots__/compiler.spec.ts.snap
decisions:
  - "Devoluciones se combinan con UNION ALL + re-SUM por claves (FULL JOIN de PG no admite IS NOT DISTINCT FROM ni ON TRUE)"
  - "dia_key/semana_key/mes_key son texto YYYY-MM-DD (inicio del bucket)"
  - "Snapshots en archivo (__snapshots__), no inline: Prettier 3 no está soportado por jest inline snapshots"
  - "Participación % no se compila: 117-09 la calcula con totales (independiente del Top N)"
metrics:
  tasks: 2
  completed: 2026-10-17
---

# Phase 117 Plan 07: Compilador SQL de Reporte a medida

Compilador puro `compilarPedido(pedido, {storeId, tz, modo})` que arma principal/totales/fuentes/comparación sobre el fragmento `venta` compartido, con todos los valores en bind y joins de lookup ligados a la tienda.

## Commits
- `bfa544c8` (repo api-ventago): feat(117-07) compilador + spec + snapshots (spec RED no se commiteó solo, según el plan)

## RED (Task 1)
`jest compiler` falló con `Cannot find module './compiler'` (TS2307), sin SyntaxError ni OOM. Salida guardada en `$TMPDIR/rm-red-07.txt`.

## GREEN (Task 2)
- `jest src/app/reporte-medida` : 5 suites / 152 tests OK (compiler: 28 tests, 3 snapshots)
- `tsc --noEmit` exit 0; eslint de los dos archivos exit 0
- grep: `from '../reports/venta-universe'` = 1, `replacements` = 0, `SALE_ITEM_DIM_CTE` = 0

## Mutaciones (ambas hicieron fallar el spec: 1 test rojo, 27 verdes)
a. Cabecera con `JOIN sale_items` directo antes de sumar `total_amount`: spec falla.
b. Sin `AND c.store_id = $1::int` en el join de categorías: spec falla (ayudante `tenantOk`).
Compilador restaurado desde copia tras cada mutación.

## Desviaciones
- [Rule 1] El helper `desdeG` del spec encontraba `g AS (` dentro de `items_agg AS (`; se corrigió a ` g AS (`. El helper de tenant tenía lookahead que no cerraba en fin de cadena (el control lo detectó); corregido.
- [Rule 3] `toMatchInlineSnapshot` no funciona con Prettier 3: se usó `toMatchSnapshot` (archivo `.snap` commiteado).
- `fuentes` sólo lleva $1..$4 (`fuentesSql` no admite filtros); el spec lo refleja.

## Notas para 117-09
- La SQL no fue ejecutada contra PG en este plan (sólo asserts de texto): 117-09 es la prueba de comportamiento.
- Claves de fila: `<dim>_key`, `<dim>_label`, `medio_pago_slug`; métricas en float8 (tickets int).
- Con devoluciones atribuibles el compilador exige dimensiones sucursal/tiempo (lanza Error si no).

## Known Stubs
Ninguno.

## Self-Check: PASSED
Archivos y commit `bfa544c8` verificados.
