---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 19
subsystem: ventago-app / reports-v2 / a-medida / guardados
tags: [reporte-a-medida, guardados, dnd-kit, mui]
requires: [117-15]
provides:
  - guardados-logica (queMuestra, nombreSugerido, nombreCopia, moverGuardado, moverPorArrastre, idsOrdenPropios, ordenarPorPosicion)
  - GuardarDialog, MisReportesTabla, CambioDefinicionPanel, MisReportesMenu
affects: [117-22, 117-23]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/guardados/guardados-logica.ts
    - ventago-app/src/__tests__/reporte-medida-guardados.spec.ts
    - ventago-app/src/views/reports-v2/a-medida/guardados/GuardarDialog.tsx
    - ventago-app/src/views/reports-v2/a-medida/guardados/CambioDefinicionPanel.tsx
    - ventago-app/src/views/reports-v2/a-medida/guardados/MisReportesTabla.tsx
    - ventago-app/src/views/reports-v2/a-medida/guardados/MisReportesMenu.tsx
decisions:
  - "Tabla con MUI Table + @dnd-kit (no FullTable): AG Grid no permite filas arrastrables con teclado"
  - "Panel de cambio de definición sólo con nota genérica: el servidor no entrega notas Antes/Ahora"
metrics:
  tasks: 3
  files: 6
  completed: 2026-10-18
---

# Phase 117 Plan 19: Guardados Summary

Lógica pura probada y cuatro componentes de pedidos guardados (guardar, gestionar, aviso de definición, menú «Mis reportes (n)»), listos para que 117-22 los monte.

## Commits (repo ventago-app, sin push)
- 0da5238c: guardados-logica + spec (15 tests; mutación de `idsOrdenPropios` sin filtrar `esMio` falla 1 test)
- b5a16282: GuardarDialog y CambioDefinicionPanel
- ca1a6622: MisReportesTabla y MisReportesMenu

## Notas
- Reorden: arrastre (asa, sólo propias) y Subir/Bajar en el menú de fila; envía sólo `idsOrdenPropios`, optimista con rollback (`mutate()` + toast) si falla.
- `onEjecutar(id)` se delega al cuerpo (117-22). La tabla tiene `id="mis-reportes-guardados"` como ancla.
- Gates: tsc app y eslint de la carpeta en 0; sin `dangerouslySetInnerHTML` ni `.delete(`.

## Deviations from Plan
Ninguna. (El RED de jest no se corrió por separado: spec e implementación se escribieron juntas; la validez se comprobó con la mutación.)

## Known Stubs
Ninguno. `CambioDefinicionPanel` omite Antes/Ahora a propósito (el servidor no entrega notas).

## Self-Check: PASSED
