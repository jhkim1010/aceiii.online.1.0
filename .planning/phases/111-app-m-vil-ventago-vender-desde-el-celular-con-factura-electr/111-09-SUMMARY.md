---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 09
subsystem: ventago-app/config-ventas
tags: [colibri, mobile-devices, approval, swr, web]
requires: ["111-03", "111-15"]
provides:
  - Modal «Celulares (Colibri)» en Configuración > Ventas > Vendedores (aprobar, renombrar, comandera, dar de baja)
  - Hooks SWR useMobileDevices, useBoxesByStore, useBranchAgents
key-files:
  created:
    - ventago-app/src/views/config/ventas/sellers/list/components/celulares.ts
    - ventago-app/src/views/config/ventas/sellers/list/components/CelularesModal.tsx
    - ventago-app/src/__tests__/celulares.spec.ts
    - ventago-app/src/hooks/api/useMobileDevices.ts
    - ventago-app/src/hooks/api/useBoxesByStore.ts
    - ventago-app/src/hooks/api/useBranchAgents.ts
  modified:
    - ventago-app/src/views/config/ventas/sellers/list/SellersList.tsx
decisions:
  - useBoxesByStore usa GET /box/store/:storeId (no GET /box) porque GET /box filtra por la sucursal del usuario y esconderia cajas de otras sucursales
  - Mensaje 403 fijo («editar-terminal»); el servidor es la frontera, el boton no
metrics:
  completed: 2026-10-16
  app-commits: f9481d50, 14be6a7c
---

# Phase 111 Plan 09: Pantalla web de celulares Summary

Un encargado ve los celulares Colibri esperando aprobacion (badge con el conteo en el boton «Celulares»), los aprueba eligiendo Sucursal → Caja, los renombra, les asigna comandera (PUT /terminal/:id thermalAgentId) y los da de baja con confirmacion.

## Commits (repo ventago-app, NO pushed)
- f9481d50 helpers puros + spec (8 tests) + 3 hooks SWR
- 14be6a7c CelularesModal + boton con Badge en SellersList (dynamic ssr:false)

## Verificacion
- jest celulares.spec: 8/8. tsc 0. eslint --max-warnings=0 limpio en todos los archivos tocados. Gate de commit paso.
- Greps de aceptacion: approve/revoke/PATCH en el modal, thermalAgentId, dynamic(), sin `.delete(` ni `apiConnector.get`.
- Verificacion visual: queda para el UAT (pasos 1 y 11).

## Deviations from Plan
- **[Rule 1] Fuente de cajas:** el plan pedia `/box`; ese endpoint filtra por la sucursal del usuario cuando no se pasa branchId, asi que un encargado de una sucursal no veria las demas. Se uso `/box/store/:storeId?page=0&pageSize=50&isDeleted=false` (cada caja trae branchId).
- Se agrego `mensajeErrorCelular` (+ test) a celulares.ts para el texto del 403.
- No se uso TABLE_ROW_HEIGHT: la pantalla son tarjetas, no una tabla.
- Toasts con react-hot-toast (el mismo que SellersList).

## Notas
- No se hizo push (Plan 14 publica en orden). Esta pantalla llama a /mobile/devices/*, que existe solo tras desplegar Plan 15: el web no debe salir antes que el api. Ademas el badge consulta GET /mobile/devices al montar SellersList: sin api desplegado daria 404, y usuarios sin editar-terminal recibirian 403 (el badge queda en 0, sin romper la pantalla).
- STATE.md y ROADMAP.md quedan sin commitear a proposito.
- Sin DDL/DML de produccion ni seeds de menu (no hay entrada nueva en el sidebar).

## Known Stubs
Ninguno.

## Self-Check: PASSED
Commits f9481d50 y 14be6a7c existen en ventago-app; archivos creados presentes.
