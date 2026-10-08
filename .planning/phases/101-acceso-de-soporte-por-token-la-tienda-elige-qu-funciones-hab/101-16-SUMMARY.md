---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 16
subsystem: ventago-app (frontend)
tags: [modo-soporte, solo-lectura, agente, sin-alcance]
requires: [101-12, 101-13, 101-14]
provides:
  - "AgenteAccesoView: Entrar a las pantallas, tarjeta Pantallas de la tienda, perdido() sólo con AGENT_GRANT_INVALID"
  - "Ventas, Productos, Sucursales, Facturación: escrituras ocultas con soloLectura y <SinAlcance /> por región"
key-files:
  modified:
    - ventago-app/src/views/agente/AgenteAccesoView.tsx
    - ventago-app/src/views/sales/list/SalesListView.tsx
    - ventago-app/src/views/products/list/ProductsView.tsx
    - ventago-app/src/views/products/list/components/ProductsList.tsx
    - ventago-app/src/views/products/list/components/ProductParentList.tsx
    - ventago-app/src/views/branches/BranchList.tsx
    - ventago-app/src/views/branches/components/branch/BranchTable.tsx
    - ventago-app/src/views/branches/components/box/BoxTable.tsx
    - ventago-app/src/views/branches/components/terminal/TerminalTable.tsx
    - ventago-app/src/views/facturacion/FacturacionToolbar.tsx
    - ventago-app/src/views/admin/stores/hooks/useBranch.ts
metrics:
  tasks: 2
  completed: 2026-10-08
---

# Phase 101 Plan 16: Experiencia del técnico en las pantallas Summary

El técnico canjea el código, entra a Ventas/Productos/Facturación/Sucursales en modo sólo lectura, sin botones de escritura, y un 403 de alcance ya no le cierra el acceso.

## Commits (repo ventago-app, sin push)
- `9ba7cddf` Task 1 AgenteAccesoView
- `e815f635` Task 2 pantallas objetivo

## Qué se hizo
- **AgenteAccesoView**: `elegir()` guarda `{key, storeId, tienda, alcances, hasta}` con `setModoSoporte`; al montar retoma `getModoSoporte()`. Barra del acceso con chips y botón «Entrar a las pantallas» (`entrarModoSoporte()` + `router.push(primeraPantalla)`). Tarjeta «Pantallas de la tienda» con un acceso por `ver_*` («Sólo lectura»). Texto de ayuda «Admin › Token de soporte». Listener: sólo `detail.code === 'AGENT_GRANT_INVALID'` llama `perdido()`. Pestañas sólo para `ALCANCES_CON_PESTANA` (cert, usuarios_terminales, legacy), también en el tab por defecto y en `onSalir` de legacy.
- **Ventas**: Facturar y Modificar ocultos con `soloLectura`; si `/sales/all` vuelve con `agenteSinAlcance` la tabla se reemplaza por `<SinAlcance />`.
- **Productos**: bloque «Entrada de stock» (formulario/Guardar) oculto con `soloLectura`; `ProductsList` y `ProductParentList` muestran `<SinAlcance />` si su GET vuelve sin alcance.
- **Sucursales**: Editar/Eliminar/Crear de sucursales, cajas y terminales y la tarjeta de niveles de precio ocultos; `SinAlcance` por región (useBranch expone `sinAlcance`; Box/Terminal leen `error.agenteSinAlcance`).
- **Facturación**: los dos checkboxes que escriben configuración (auto-emisión y comandera) se ocultan.

## Deviations from Plan

1. **[Rule 3 - Alcance real de los botones]** Los botones de escritura viven en componentes hijos, no en los archivos listados. Se editaron además `BranchTable`, `BoxTable`, `TerminalTable`, `ProductsList`, `ProductParentList` y `useBranch` (cambios mínimos, sólo condicionan render / capturan sin alcance).
2. **FacturacionToolbar no tiene Emitir/Reimprimir** (la emisión es «Facturar» en Ventas, ya oculto). Lo único de escritura en la barra son los dos checkboxes de configuración; se ocultaron esos.
3. **Productos**: no hay Crear/Editar/Eliminar/Importar como botones sueltos; se ocultó el formulario de entrada de stock (único camino de creación/edición). Los íconos de eliminar en `DataConfig`/diálogo de `ProductParentList` no se tocaron (T-101-63 accept: el servidor devuelve 403).
4. **Copy elegido por el planner** (no está en UI-SPEC): sin pestañas y sin `ver_*` se muestra «Este código no habilita ninguna herramienta en esta pantalla.»

## Límites conocidos
- **Caja por user.id (heredado de 101-05):** `cash-register/status` y `cierre` se consultan por `user.id`; el agente (agent@app) ve «sin caja» en Ventas. No se trata como fallo ni se parchea en la vista.
- Cobertura de botones no es 100 % (UI-SPEC); el bloqueo central (101-12) y el 403 del servidor son el límite real.

## Verificación
- `tsc --noEmit` exit 0; eslint 0 errores en archivos tocados (2 warnings de exhaustive-deps preexistentes en ProductsView). Recorrido visual queda para 101-18.

## Known Stubs
Ninguno.

## Self-Check: PASSED
Commits 9ba7cddf y e815f635 presentes en ventago-app.
