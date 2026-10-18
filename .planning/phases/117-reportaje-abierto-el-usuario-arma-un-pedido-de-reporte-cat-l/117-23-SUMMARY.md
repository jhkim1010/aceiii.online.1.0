---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 23
subsystem: ventago-app / reports-v2 navegacion
tags: [reporte-a-medida, registry, sidebar, novedades]
requires: [117-22]
provides:
  - Entrada de registro 'reporte-a-medida' (primera en Ventas) y seccion 'A medida' del diseno Nuevo
  - Grupo «Mis reportes» (max 10 + Ver todos) y badge NUEVO en ReportsSidebar
  - Novedad 2026-10-18-reporte-a-medida (solo admin)
affects: [117-24]
key-files:
  modified:
    - ventago-app/src/views/reports-v2/registry.ts
    - ventago-app/src/views/reports-v2/nuevo/secciones.ts
    - ventago-app/src/__tests__/reportes-secciones.spec.ts
    - ventago-app/src/pages/_app.tsx
    - ventago-app/src/views/reports-v2/ReportsSidebar.tsx
    - ventago-app/src/configs/novedades.ts
    - ventago-app/src/views/reports-v2/a-medida/permiso.ts
decisions:
  - "Badge NUEVO derivado de recentNovedades: se retira solo al salir de la ventana de 7 dias"
  - "Novedad solo para admin (D-05): avisar a gerentes sin permiso seria un CTA muerto"
metrics:
  tasks: 2
  completed: 2026-10-18
---

# Phase 117 Plan 23: Registro y navegacion Summary

«Reporte a medida» es alcanzable desde la navegacion de Reportes en ambos disenos, con guardados a un clic y aviso de novedad.

## Commits (ventago-app, sin push)
- 00feabf1: registro, seccion «A medida», etiqueta de pestana, spec (caso nuevo de permiso)
- 852fe1d9: «Mis reportes», badge NUEVO, entrada de novedades

## Verificacion
- jest reportes-secciones, reportes-titulo-pestana, novedades: verdes. tsc app 0, eslint 0.
- Menu global (navigation/vertical) sin cambios.

## Deviations from Plan

**1. [Rule 3 - Blocking] permiso.ts acepta `permissions: null`**
- **Issue:** `UserDataType.permissions` puede ser null; tsc rechazaba `puedeVerReporteMedida(auth.user)`.
- **Fix:** tipo ampliado con `| null` (comportamiento identico).
- **Commit:** 852fe1d9

**2. Criterio grep:** `grep -c useReporteMedidaPedidos` en ReportsSidebar da 2 (import + uso), no 1; una sola llamada.

## Known Stubs
None.

## Self-Check: PASSED
