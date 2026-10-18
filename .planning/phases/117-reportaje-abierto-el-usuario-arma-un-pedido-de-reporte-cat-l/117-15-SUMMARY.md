---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 15
subsystem: ui
tags: [reporte-medida, swr, tipos, errores]
requires: ["117-14"]
provides:
  - "tipos.ts con el contrato del servidor"
  - "api.ts (cliente /reporte-medida sin storeId) y apiConnector.postBlob"
  - "useReporteMedidaCatalogo / useReporteMedidaPedidos (SWR 5 min, clave null sin permiso)"
  - "clasificarError / debeAvisarGlobal / focoDeFixCsv"
affects: [117-17, 117-18, 117-19, 117-20, 117-21, 117-22, 117-23, 117-24]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/tipos.ts
    - ventago-app/src/views/reports-v2/a-medida/permiso.ts
    - ventago-app/src/views/reports-v2/a-medida/api.ts
    - ventago-app/src/views/reports-v2/a-medida/errores.ts
    - ventago-app/src/hooks/api/useReporteMedidaCatalogo.ts
    - ventago-app/src/hooks/api/useReporteMedidaPedidos.ts
    - ventago-app/src/__tests__/reporte-medida-errores.spec.ts
  modified:
    - ventago-app/src/services/api.service.ts
decisions:
  - "postBlob decodifica el Blob de error a JSON en error.response.data"
  - "put/patch/remove aceptan silenceErrorToast de forma aditiva"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 15: Contratos y capa de datos del front Summary

Tipos del contrato real del servidor, cliente HTTP sin tienda/permisos, `postBlob`, dos hooks SWR y la traduccion de errores HTTP a estados de UI.

## Commits (ventago-app, no pusheados)
- 14954114: tipos, permiso, api, postBlob, silenceErrorToast, hooks
- 762ea2ed: errores.ts + spec

## Verificacion
- tsc app exit 0; eslint de los archivos exit 0.
- jest reporte-medida-errores: 15/15. Mutacion (429 -> 'servidor') hace fallar 1 test; restaurado, 15/15.
- `store_id`/`storeId` en api.ts: 0 coincidencias.

## Deviations from Plan
- Un comentario de api.ts mencionaba storeId y rompia el gate de grep; reescrito y el commit se enmendo (sin push). Por lo demas, el plan se ejecuto como estaba escrito.

## Self-Check: PASSED
