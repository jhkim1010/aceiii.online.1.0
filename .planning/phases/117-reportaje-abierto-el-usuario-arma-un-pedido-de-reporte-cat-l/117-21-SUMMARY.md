---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 21
subsystem: ui
tags: [reporte-medida, constructor, periodo, filtros, plantillas, barra-sticky]
requires: ["117-15", "117-16", "117-17"]
provides:
  - "pasos/PasoPeriodo, pasos/MasFiltros, PlantillasCarrusel, BarraTuReporte"
affects: [117-22]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/pasos/PasoPeriodo.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/MasFiltros.tsx
    - ventago-app/src/views/reports-v2/a-medida/PlantillasCarrusel.tsx
    - ventago-app/src/views/reports-v2/a-medida/BarraTuReporte.tsx
decisions:
  - "Sucursales se cuentan con useBranchByStore (el catálogo no trae sucursalesCount); selector visible con 2 o más"
  - "Nota fija sin nombrar ciudad ni zona horaria (el front no recibe la tz)"
  - "MasFiltros se monta sólo al expandir el Accordion (unmountOnExit); los 6 hooks SWR se llaman dentro de ListaFiltros"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 21: Paso 3, carrusel de plantillas y barra Tu reporte Summary

Paso 3 con todos los presets del catálogo más «Rango de fechas…», línea «Del {rango} · {n} días» con marca de período en curso (parcial), sucursal (>= 2), «Más filtros» con Autocomplete múltiple (máx. 50 ids) sobre hooks SWR, Ordenar por (oculto con 1 opción) y Filas (Todas/Top 10-100). Carrusel de plantillas con atenuado y motivo para las no disponibles y navegación sin ejecutar para «Stock actual». Barra sticky con resumen, estado, errores con botones de arreglo (onAplicarFix), avisos y acciones.

## Commits (ventago-app, no pusheados)
- 22b1ed2d: PasoPeriodo y MasFiltros
- ff3b4c1a: PlantillasCarrusel y BarraTuReporte

## Verificación
- app tsc exit 0; eslint de los 4 archivos exit 0 (y hook de commit).
- Gates grep: sin apiConnector, sin «Buenos Aires», sin «margen» en el carrusel.
- No se probó en navegador (se monta en 117-22).

## Deviations from Plan
None - plan executed as written.

## Known Stubs
Ninguno.

## Self-Check: PASSED
