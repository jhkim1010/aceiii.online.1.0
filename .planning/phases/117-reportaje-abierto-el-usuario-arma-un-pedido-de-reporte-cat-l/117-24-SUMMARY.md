---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 24
subsystem: deploy + verificacion humana
tags: [reporte-a-medida, deploy, codex, checkpoint]
requires: [117-23]
provides:
  - Ronda de front desplegada en produccion (api #1204 33a3b43b, app #1161 eeede8db)
  - Correcciones CODEX (4 hallazgos) desplegadas — ver 117-24-FIXES.md
  - Verificacion humana aprobada (pasos 1-9 y 11 en prod por el usuario; paso 10 local)
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 24: Deploy y verificacion Summary

## Deploy
- Primera tanda: api 42a68c57 / app 852fe1d9 (root 8eb7b1b).
- Correcciones CODEX: api 33a3b43b (#1204) / app eeede8db (#1161) (root 6dac590). Builds verificados por SHA.
- Desvio: un push de api a las 15:59 BA se hizo sin medir usuarios antes; medido justo despues = 0.

## Verificacion
- Pasos 1-9 y 11: aprobados por el usuario en https://app.coolsistema.com/reportes-v2/reporte-a-medida (2026-10-18).
- Paso 10 (no-admin + Margen): local (API 5012 + build prod 3060), items a-e todos OK.

## Artefactos de prueba (local, se conservan)
- Reporte guardado id 56 «Margen por dia (prueba 117)» compartido (store 6).
- role 21 / store 6 (vendedor): permiso read `reporte-a-medida`.

## Notas menores (no bloqueantes, pendientes de decision)
- Topbar «Ejecutar» deshabilitado al entrar (probable: validacion en curso).
- Etiquetas del eje x del grafico truncadas («2026...»).
- Pie del grafico menciona «Tramo punteado» pero sólo se dibujan puntos huecos (limite ApexCharts, 117-18).
- Linea «próximamente» suelta bajo los chips de tipo de dato.
