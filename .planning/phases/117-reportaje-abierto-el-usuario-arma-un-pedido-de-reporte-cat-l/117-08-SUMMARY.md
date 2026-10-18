---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 08
subsystem: api-ventago/reporte-medida
tags: [size-order, csv, availability, cache, tenant-isolation]
requires: [117-04]
provides: [compararTalles, toCsv, decidirDisponibilidad, ConteosCatalogo, ReporteMedidaDisponibilidadService]
affects: [117-09, 117-11]
requirements: [D-19, D-23, D-30]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/size-order.ts
    - api-ventago/src/app/reporte-medida/size-order.spec.ts
    - api-ventago/src/app/reporte-medida/csv.ts
    - api-ventago/src/app/reporte-medida/csv.spec.ts
    - api-ventago/src/app/reporte-medida/availability.ts
    - api-ventago/src/app/reporte-medida/availability.service.ts
    - api-ventago/src/app/reporte-medida/availability.spec.ts
    - api-ventago/src/app/reporte-medida/availability.itest.ts
decisions:
  - "Talles: numéricos primero, luego escalera de letras, serie N, resto alfabético, null al final (la copia de la app pone letras antes; esta es la regla del plan)"
  - "Clave de caché vía storeKey('reporte-medida:disponibilidad', storeId) porque getOrLoad exige CacheKey (no string crudo)"
  - "Colores y talles también excluyen NONE/General (join con colors/sizes ligado a la tienda), coherente con D-30"
metrics:
  tasks: 2
  completed: 2026-10-18
---

# Phase 117 Plan 08: Orden de talles, CSV y disponibilidad por tienda

Tres bloques puros/baratos para el servicio de ejecución y el catálogo: `compararTalles` (D-23 / PEDIDO 40), `toCsv` (es-AR Excel: BOM, `;`, coma decimal, CRLF, guardia de inyección de fórmulas) y disponibilidad de dimensiones por tienda (una consulta, caché 60 s, centinelas NONE/General fuera).

## Commits (repo api-ventago, sin push)
- `dfec0374` feat(117-08): orden de talles y CSV
- `e171dbf0` feat(117-08): disponibilidad (decisión pura + servicio + spec)
- `1c893a7c` test(117-08): itest de disponibilidad

## Verificación (por código de salida)
- `jest size-order csv`: 9 tests OK
- `jest availability`: 7 tests OK
- `npm run test:itest -- availability`: 3 tests OK (madre cuenta con hijo null, `' General '` no cuenta, caché = 1 consulta en 2 llamadas, control de tenant con segunda tienda)
- eslint de los archivos exit 0; `replacements` = 0 y `getOrLoad` = 1 en el servicio

## Deviations from Plan

1. **[Rule 3] Clave de caché**: el plan indicaba la clave `reporte-medida:disponibilidad:${storeId}`; `getOrLoad` requiere `CacheKey` creado con `storeKey()`, así que la clave real es `storeKey('reporte-medida:disponibilidad', storeId)`. TTL 60_000 sin cambios.
2. **[Rule 2] Colores/talles con centinelas**: el plan sólo detallaba el filtro de centinelas para categorías/temporadas; se aplicó también a colores y talles para cumplir el must-have («sólo NONE/General = sin valor»).
3. **Itest sin harness**: conforme a la regla del repo se usa Sequelize directo y `new MemoryCacheService()` (`cache.clear()` simula el vencimiento) en lugar de `createImportHarness`. `store_entity_id` (NOT NULL sin default) se asigna a mano en las fixtures.
4. **TDD**: la RED se corrió mentalmente junto con la implementación en size-order/csv (specs y módulos escritos juntos); no hubo commit RED, según el plan. Los hooks pidieron corregir prettier/`no-base-to-string` antes del commit; ya corregidos.
5. **Regla de talles vs app**: `ventago-app/src/utils/orden-talles.ts` pone letras antes que números; el plan fija números primero. Se siguió el plan y se documentó en el JSDoc de `size-order.ts`.

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo (T-117-28/29/30 mitigados: apóstrofe, predicados por tienda + itest de tenant, caché single-flight).

## Self-Check: PASSED
