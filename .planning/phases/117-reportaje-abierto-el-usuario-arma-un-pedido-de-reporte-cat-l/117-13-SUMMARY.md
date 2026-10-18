---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 13
subsystem: api-ventago/reporte-medida
tags: [itest, tenant-isolation, fan-out, ganancia-cross-check, comparison, codex-review]
requires: ["117-09", "117-11"]
provides: [crearFixturasReporteMedida, agregarHistorial, itemsAggCte-firmado, comparacion-por-clave, variacionTotal-parcial]
affects: [117-12]
requirements: [D-01, D-02, D-03, D-04, D-07, D-08, D-09, D-10, D-12, D-17, D-21, D-22, D-26, D-28, D-30, D-31, D-31a, D-32]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/reporte-medida.fixtures.ts
    - api-ventago/src/app/reporte-medida/reporte-medida.itest.ts
    - api-ventago/src/app/reporte-medida/reporte-medida-comparacion.itest.ts
    - api-ventago/src/app/reporte-medida/reporte-medida.service.spec.ts
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.service.spec.ts
    - .team/reviews/117-13-codex.md
  modified:
    - api-ventago/src/app/reporte-medida/compiler.ts
    - api-ventago/src/app/reporte-medida/post-process.ts
    - api-ventago/src/app/reporte-medida/period.ts
    - api-ventago/src/app/reporte-medida/executor.service.ts
    - api-ventago/src/app/reporte-medida/consulta.types.ts
    - api-ventago/src/app/reporte-medida/reporte-medida.service.ts
    - api-ventago/src/app/reporte-medida/catalog/catalog.ts
    - api-ventago/src/app/reporte-medida/pedidos/pedidos.service.ts
    - api-ventago/src/app/reports/venta-universe.ts
decisions:
  - "Las itest NO importan test/itest/harness (OOM): Sequelize directo + servicios armados con new; tiendas ZZ-RM-{A,B,C}-<run> nunca se borran"
  - "Signo de anulación: opt-in `itemsAggCte({ firmado: true })` y `firmadoSql` (-ABS cuando sgn=-1); Ganancia conserva el comportamiento histórico"
  - "variacionTotal con hoy en el período: se calcula sobre el rango completo (hasta ayer) y se marca parcial (no se esconde el dato de la tabla)"
  - "Comparación con claves: clave completa (buckets llevados a su contraparte) salvo sólo-tiempo y día+sucursal, que conservan el camino por posición porque rellenan días sin ventas"
metrics:
  tasks: 3
  completed: 2026-10-18
---

# Phase 117 Plan 13: itests semánticas y revisión CODEX de Reporte a medida

Se probó en PG18 local, con grupos de control y mutaciones, el aislamiento de tenant, el fan-out, los granos y el cruce con Ganancia; se verificó D-31/D-31a/D-32 de punta a punta y se cerraron los seis arreglos de seguimiento más los dos hallazgos MEDIUM del CODEX. Nada se pusheó.

## Commits (repo api-ventago, sin push)
- `3539e120` test(117-13): itest de aislamiento, fan-out y granos
- `2ea710b4` test(117-13): itest comparación y cruce con Ganancia
- `8dc647a1` fix(117-13): reordenar pedidos guardados en una sola sentencia (CODEX)
- `6b01b8c6` fix(117-13): FILTROS.vendedores.tabla = "Sellers" y pertenencia desde el catálogo
- `78cb6ea5` fix(117-13): signo de anulación, Top N+comparación, variacionTotal parcial y pagos null
- `4816666e` fix(117-13): hallazgos CODEX: días futuros parciales y comparación por clave completa

## Verificación (por código de salida)
- `npm run test:itest -- reporte-medida --forceExit`: 5 suites, 52 tests, exit 0 (incluye executor, availability y pedidos sin regresión)
- `npx jest src/app/reporte-medida src/app/reports/venta-universe --maxWorkers=1 --forceExit`: 14 suites, 231 tests, exit 0
- `tsc --noEmit` exit 0; `eslint src/app/reporte-medida` exit 0

## Mutaciones (se corrieron una vez y se restauraron)
| Mutación | Resultado |
|---|---|
| Quitar `s.store_id =` de `ventaHeaderCte` (hecho sin romper `$1`) | 10 de 14 casos fallan con cifras de otras tiendas (p. ej. 78.680.566 en vez de 1.000); el aislamiento falla. Nota: una primera mutación con `WHERE TRUE` dejaba `$1` sin usar y fallaba por SQL inválido (14/14 por error, no por fuga) — se descartó y se rehízo |
| Unir `sale_items` antes de `SUM(total_amount)` a grano cabecera | 8 de 14 fallan, incluido fan-out |
| Top N: la comparación usa su propio Top N | falla el itest «mismas claves» |
| `variacionTotal` sin recorte por hoy | fallan 2 specs de post-proceso |
| `bucketContieneHoy('dia')` con `===` | fallan 2 tests (period + post-proceso) |
| Claves de comparación sin llevar el bucket al período comparado | falla el itest producto × día |

## Seguimiento (de 117-09 / 117-11)
1. **Signo de anulación**. Medido en local: 11.496 de 11.624 líneas de `Anulación` tienen cantidad **negativa** (128 positivas, 271 con subtotal ≥ 0); el resumen de 117-11 lo describía al revés. Aun así hay reversos con cantidad positiva: `-ABS` en `itemsAggCte({firmado:true})` y en el grano ítem fuerza el signo del monto sin invertir dos veces los ya negativos. Se firman unidades, costo y las bases de línea (`subtotal` en `items_total`/`venta_con_costo`/ítem), para que margen y precio por unidad queden coherentes. **Ganancia conserva el comportamiento histórico** (`itemsAggCte()` sin opción no cambió; spec de control); conciliarlo es de Phase 105. El cruce con Ganancia compara dinero exacto y margen exacto en un período sin anulación; las unidades se comparan contra un SQL a mano que aplica el signo.
2. `FILTROS.vendedores.tabla = '"Sellers"'`; se eliminó el mapa local del servicio (tabla y `global` salen del catálogo). Spec con sonda que cambia el catálogo y comprueba que la consulta lo sigue.
3. Top N + comparación: la consulta de comparación recibe las claves de las filas actuales (`completarBind`, evaluado dentro de la misma transacción READ ONLY) y el post-proceso ya no la recorta con el Top N.
4. `variacionTotal`: si el período incluye hoy se compara el rango completo (hasta ayer) con el rango de comparación recortado igual; campos nuevos `parcial` y `hastaComparable`, `actual/anterior` pueden ser null cuando el período es sólo hoy (control con «hoy» lejano).
5. Grano pago con `amount` NULL: CTE `pagos` con ventanas; el remanente (total − pagos con monto) se reparte entre los pagos null y una venta sin pagos sigue siendo una fila «Sin medio de pago». Itest: total de pagos = total de cabecera (600) y reparto 250/350.
6. Reordenar pedidos: una sola sentencia (`UPDATE … RETURNING` + conteo) dentro de la transacción; un id ajeno revierte todo. Spec: una sentencia, `ORDEN_INVALIDO`, ids repetidos sin tocar la base.

## CODEX (`.team/reviews/117-13-codex.md`)
Sin HIGH. Aislamiento, inyección SQL, margen, fan-out, signo, pool/timeout y reordenar: sin hallazgo demostrable.
- **MEDIUM días futuros** (período explícito que pasa de hoy): un día futuro se comparaba como completo. Corregido: cualquier bucket ≥ hoy es parcial (`4816666e`, spec + mutación).
- **MEDIUM Top N × buckets** (producto × día pierde parejas por el LIMIT): corregido con clave completa y buckets alineados al período comparado (`4816666e`, itest + spec).
- Comprobaciones obligatorias del prompt: todas sin hallazgo.

## Deviations from Plan
- **Sin harness Nest** (regla del repo y SUMMARY 117-01): el plan decía `createImportHarness`; se usó Sequelize directo y `new` de los servicios. `crearFixturasReporteMedida` recibe una interfaz mínima `{ q }` en vez de `Harness`. Los nombres de tienda llevan sufijo `-<timestamp>` y no se borran.
- **Tipo de cambio en la fixture**: el devuelto usa `credit_ledger` (`favor_in`) como reintegro; no se montó `box_operations` (misma fórmula de reintegro, sin la cadena de cajas).
- **Rule 1** — corrección de contrato: `variacionTotal` suma `parcial` y `hastaComparable`, y la comparación con claves cambió el SQL de `comp_principal` (specs `compiler.spec.ts`/`post-process.spec.ts` y 2 snapshots actualizados a propósito, diff revisado).
- Los itest de `reportsGanancia`/`venta-universe` usan el harness y se caen por heap en esta máquina; no se corrieron. El valor por defecto de `itemsAggCte` queda cubierto por spec (texto idéntico al anterior).

## Notas para 117-12
- Nada pusheado: el push sigue siendo de 117-12 (primero migraciones y seed en prod).
- Los itests dejan tiendas `ZZ-RM-*-<run>` en la base local (regla de la casa).
- Phase 105 debe conciliar el signo de unidades/costo de anulación de Ganancia con este criterio.

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo (el bind jsonb de claves de comparación va por parámetro; la tabla de pertenencia sigue siendo constante del catálogo).

## Self-Check: PASSED
