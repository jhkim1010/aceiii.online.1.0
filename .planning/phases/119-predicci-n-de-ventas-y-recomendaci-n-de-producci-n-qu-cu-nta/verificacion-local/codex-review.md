# CODEX — revisión de Phase 119 (2026-10-19, 119-16)

Método: diffs por área generados a mano (sin specs/itests) desde antes de 119-01 hasta HEAD y pasados a `codex exec` con prompt corto
(api-ventago `6cca1597~1..HEAD`, ventago-app `2066ea28~1..HEAD`). Sin `-o`, sin `--model`.

Cobertura real: c1, c2, c3 revisados. **c4 (migraciones + backup/vaciado) y c5 (frontend) NO se pudieron revisar: CODEX devolvió
`429 Too Many Requests` (también un prompt de control de una línea) — cupo agotado.** Falta repetirlos.

## c1 — agregado, resúmenes, runs, orquestador, cron
[MEDIUM] src/app/forecast/forecast-nightly.cron.ts:23 — El cron usa `DEFAULT_STORE_TZ` para todas las tiendas. La única ejecución diaria recorre todas las tiendas a las 05:35 de Buenos Aires, no a las 05:35 de cada `stores.timezone`; para tiendas en otros husos el cálculo puede correr en horario comercial.

## c2 — modelos, backtest, simulación, insumos de producción
[HIGH] produccion-insumos.sql.ts:33 — El backtest usa lead times calculados con lotes completados después del origen (mediana sobre toda la historia sin límite temporal).
[HIGH] produccion-insumos.sql.ts:53 — El WIP histórico incorpora recepciones futuras (`proxima` consulta recepciones posteriores a la fecha simulada y usa el estado actual del lote).
[HIGH] politica-runner.service.ts:463 — El modelo base se elige por el MASE agregado de toda la corrida y se aplica también a los primeros orígenes (fuga por selección de modelo).
[HIGH] produccion-insumos.sql.ts:55 — Con recepciones parciales futuras se asigna todo `total_quantity - recibido` a la fecha de la primera recepción posterior (llegada anticipada, infla el fill rate).
[MEDIUM] politica-runner.service.ts:746 — El pronóstico de protección suma `ceil((L+R)/7)` semanas completas pero la demanda se simula `L+R` días: hasta 6 días extra de pronóstico.
[MEDIUM] politica-sim.ts:65 — Todo el WIP reduce la orden aunque su `llegaDia` quede fuera de la ventana simulada.
[LOW] baselines.ts:82 — `seasonal_naive` exige 52+h semanas aunque con 52 bastaría para h ≤ 52.

## c3 — controller /prediccion, DTO, scope, resultados, análisis
SIN HALLAZGOS

## c4, c5
No ejecutados (429).
