---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 16
subsystem: forecast / verificacion local
tags: [forecast, backup-restore, vaciado, verificacion-local, checkpoint]
requires: [119-12]
provides:
  - cobertura backup/restore/vaciado de las 10 tablas 119 (gate de commit desbloqueado)
  - evidencia local V1..V11, endpoints y capturas
affects: [119-13, 119-14]
key-files:
  created:
    - api-ventago/src/app/forecast/runs/run-registro.spec.ts
    - .planning/phases/119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta/verificacion-local/ (chequeos.sql, chequeos-resultado.txt, endpoints.md, 9 capturas, codex-review.md)
  modified:
    - api-ventago/src/app/store/store-backup-coverage.ts (+ inventario y 5 catalogos store-restore-*.txt regenerados, store-restore-unlinked-refs.ts, store-restore-manifest.spec.ts)
    - api-ventago/src/app/store/vaciado/vaciado-catalogo.ts
    - api-ventago/src/app/forecast/runs/run-registro.ts
    - ventago-app/src/views/reports-v2/prediccion/prediccion-logica.ts
status: PAUSADO EN CHECKPOINT (Task 3 pendiente de aprobacion del usuario)
---

# Phase 119 Plan 16: Verificacion local completa — Summary (parcial, checkpoint abierto)

Tasks 0-2 ejecutadas; Task 3 (aprobacion del usuario) NO escrita: queda pendiente la respuesta literal del usuario.

## Commits
| Repo | Hash | Mensaje |
|---|---|---|
| api-ventago | 462dfbc1 | feat(119-16): cobertura backup/restore/vaciado de las 10 tablas de Phase 119 |
| api-ventago | 96946e75 | fix(119-16): crearRun devuelve en_curso por ON CONFLICT en vez de 500 |
| ventago-app | 3084d503 | fix(119-16): cuenta de simulacion paso 2 mostraba [object Object] |

Sin push, sin escrituras en prod (cero comandos ssh/psql 5434).

## Task 0 — cobertura backup/restore/borrado
- `product_attributes` y `forecast_store_settings` -> `SIMPLE_STORE_TABLES` (se respaldan/restauran; ids de usuario `updated_by_user_id` declarados REMAP->users en `store-restore-unlinked-refs.ts`; el contador de manifiesto 178->180).
- Las 8 derivadas (daily_sales_agg, forecast_runs, forecast_backtest_points/metrics, forecast_policy_sim_results, forecast_datos_usados, forecast_modelo_tickets, forecast_policy_sim_traces) -> `EXCLUDED_TABLES` con motivo.
- Borrado de tienda: las 8 derivadas van a `VACIADO_BORRAR` con `porTienda` (`t.store_id = $1`); las 2 de usuario a `VACIADO_CONSERVAR` en el vaciado, y en «eliminar tienda» (`catalogoEliminar`) se borran por `porTienda` al ser SIMPLE. El orden sale de las FK reales al correr (hijas de forecast_runs antes que la corrida; product_attributes antes de products). Nunca se tocan tablas globales. Cubierto por `vaciado-catalogo.spec.ts` (toda tabla de tienda en BORRAR o CONSERVAR).
- `npx jest src/app/store --maxWorkers=1`: 36 suites / 511 tests, exit 0. Los commits pasaron el gate sin SKIP_VERIFY.

## Task 1 — DB local y chequeos (psql -p 5432)
Estado: las 10 tablas, columnas Sigma, funcion `prediccion-produccion` y `forecast_store_settings` store 6 enabled ya estaban en local. Seeds sinteticos ya aplicados (2.061 ventas 'SINTÉTICO 119' / 2.226 u.; 34 lotes LOT-S119-%, 4 IN_PROGRESS). **Difiere de prod (2.020 / 2.175)**: la DB local viene de un backup y ademas tiene ventas reales de store 6 sobre los mismos productos (22 modelos con agregado, no 10; 3.392 u. netas en total). Cadena corrida por el endpoint POST /prediccion/ejecutar (no por script); ver chequeos.sql / chequeos-resultado.txt.

| Chequeo | Resultado local |
|---|---|
| V1 reconciliacion | Σagg 3.392 vs consulta independiente 3.392: **diferencia 0** |
| V2 quiebre | con_stock 59.872 / sin_stock 2.999 / indeterminado 568 |
| V3 invariante de libro | 433 pares, **0 discrepancias** |
| V4 launch_date | 10 filas 'recepcion', 2025-11-26..2025-12-27 |
| V5 backtest | run 182 done, is_synthetic true, 45 metricas, 0 puntos 'variante', seasonal_naive historia_insuficiente x9; WAPE modelo/todos: mm4 0,764 · mm8 0,728 · naive 0,974 · tendencia 1,122 |
| V6 simulacion | run 183 done, 12 filas, **1 candidato** (CR 0,50 moq_tienda, mm8: fill 98,2 %, sobrante 91,4 %) |
| V7 aislamiento | hijas cruzadas 0; los otros store_id que aparecen en las tablas derivadas son tiendas fixture de los itests locales (1445..1533), no datos de otra tienda real |
| V8 libro | v_stock_balance_drift 0 · v_stock_tenant_leak 0 |
| V9 sell-through (API) | 245: 107 % · 140: 104 % · 264: 88 % · 79: 75 % · 123: 73 % · 227: 72 % · 147: 61 % · 183: 61 % · 240: 50 % · 222: 40 %. Tres modelos fuera de 32-85 %: causa = ventas NO sinteticas de store 6 sobre los mismos productos (p. ej. 245: 324 sint. + 56 otras vs ingreso 358). No se ajusto el calculo |
| V10 apertura legacy | source legacy_opening 58.471 / type legacy_opening 0 / source con type NULL 58.471 |
| V11 fundamento | unidades_netas 3.392 = Σagg (dif 0); trazas ok 61 / sin_distribucion 14; objetivo=pronostico+margen **0 violaciones**; pedido (antes/despues MOQ) **0 violaciones**; errores sin futuro: 1.287 errores, **0 con futuro**; wape = Σ|err|/Σreal: 36 filas, **0 violaciones** |
| TTL | fila 'running' de hace 61 min -> pasa a failed/'abandonada' al iniciar la siguiente; una de 5 min bloquea (en_curso) |
| Retencion | backtest 3 · cadena 4 · policy_sim 3 (<= 10); itest `retención del backtest` y `cadena ... retención de 10` verdes |
| legacy_opening / rama legacy | itests `apertura legacy` (agg y resumenes) verdes contra 5432; 7 suites / 69 tests itest forecast pasan |

## Task 2 — API/app locales, endpoints, capturas
- API: build propio (tsc a `api-ventago/dist-l119`, puerto 5012) contra DB local; el log y `lsof` confirman conexion a 127.0.0.1:5432, CRON_ENABLED=false. El dev API del usuario en 5002 apunta al tunel de STAGING (15432) y NO se toco. Capturas: Chrome headless + driver CDP (capturas.mjs) que reescribe `localhost:5002` -> `5012` en el navegador, contra el dev de la app en 3050 (sin `next build`).
- Token real de `perm.admin@dummy.test` (admin store 6) por /auth/login; superadmin sin tienda con JWT firmado localmente (clave de .env local; sin contrasenas en archivos).
- endpoints.md: **34 casos, 34 OK, 0 discrepancias** (401 sin token, 400 sin tienda/nivel=variante/dimension invalida/rango, 403 otra tienda y enabled por admin, 404 run/model/product ajenos, superadmin con `X-Store-Id: 6` -> 200, ejecutar -> iniciado luego en_curso).
- 9 capturas en verificacion-local/ (5 pestanas + Ⓐ Ⓑ Ⓒ Ⓓ).

## Deviations from Plan
**1. [Rule 1 - Bug] POST /prediccion/ejecutar daba HTTP 500 si ya habia una corrida running** — el pool tiene `retry.max=3`; dentro de la transaccion abortada por el 23505 el reintento del INSERT devolvia "current transaction is aborted". Pasaba con doble clic entre workers o cron + manual. Fix: `ON CONFLICT (store_id, kind) WHERE status='running' DO NOTHING` y 0 filas -> `{enCurso:true}`. Spec nuevo `run-registro.spec.ts`. Commit 96946e75.
**2. [Rule 1 - Bug] Ⓓ paso 2 mostraba `[object Object]`** — el API entrega `semanas` como `{semana, valor}`; el formateador las unia como numeros. Fix + test. Commit 3084d503.
**3. [Rule 3] Cobertura extra** — hubo que declarar 2 columnas `updated_by_user_id` en `store-restore-unlinked-refs.ts` y subir el contador del manifiesto (178->180) para que `store-restore-*` quedara verde.
**4.** Datos locales difieren de prod (2.061 vs 2.020 ventas; ventas reales extra en store 6): los numeros V1/V5/V6/V9 locales no son los de prod; lo que se compara en 119-14 son los chequeos, no los valores.

## CODEX (verificacion-local/codex-review.md)
c1 (agregado/orquestador), c2 (modelos/backtest/simulacion/insumos), c3 (controller/API): revisados. **c4 (migraciones + backup/vaciado) y c5 (frontend): NO revisados — CODEX respondio 429 (cupo) incluso a un prompt de control.**
- MEDIUM cron nocturno usa la TZ por defecto para todas las tiendas (05:35 ART).
- HIGH x4 (lead time y WIP «ven» lotes posteriores al origen; llegada parcial anticipada; modelo base elegido con el MASE de toda la corrida): los dos primeros son un limite **ya declarado y aceptado** en la cabecera de `politica-runner.service.ts` (params.limitaciones); el tercero (seleccion de modelo con toda la corrida) y la llegada anticipada de parciales no estan declarados.
- MEDIUM ceil((L+R)/7) semanas vs L+R dias; WIP fuera de ventana reduce la orden. LOW seasonal_naive pide 52+h semanas.
- c3: SIN HALLAZGOS. No se cambio codigo por estos hallazgos (decision de diseno del usuario).

## Known Stubs
Ninguno.

## Checkpoint
Task 3 abierto: ver mensaje de checkpoint. 119-13 no arranca hasta "aprobado" escrito por el usuario.

## Estado de los servicios (dejados asi)
- 5002 / 3050 / tunel 15432 del usuario: intactos.
- 5012 (API local, DB 5432) sigue corriendo desde `api-ventago/dist-l119` (directorio sin trackear; borrar al terminar).
- Efectos en la DB local: PUT atributos de product 19 (fabric 'Algodón'...), una fila 'cadena' abandonada de prueba (id 179), corridas nuevas de store 6.
