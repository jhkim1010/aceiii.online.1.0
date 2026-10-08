---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 17
subsystem: ventago-app (frontend)
tags: [sesion-remota, rrweb, rr-block, socket, agente]
requires: [101-11, 101-15, 101-16]
provides:
  - "authSocketSoporte: agentGrant sólo en el handshake del namespace /support"
  - "Visor y pestaña «Sesión remota» con lista de sesiones del grant (GET /support/sessions/active cada 5 s)"
  - "«Compartir mi pantalla» en la fila Activo con sesion_remota -> POST /support/sessions {grantId}"
  - "rr-block en los secretos visibles como texto + spec con inventario y controles (R-4)"
key-files:
  created:
    - ventago-app/src/views/agente/soporte-remoto-logic.ts
    - ventago-app/src/views/soporte/VisorSoporte.tsx
    - ventago-app/src/__tests__/soporte-remoto-logic.spec.ts
    - ventago-app/src/__tests__/rr-block-secretos.spec.ts
  modified:
    - ventago-app/src/realtime/socket-registry.ts
    - ventago-app/src/pages/soporte/visor.tsx
    - ventago-app/src/views/agente/AgenteAccesoView.tsx
    - ventago-app/src/hooks/useRemoteSupport.ts
    - ventago-app/src/components/support/RemoteSupportLayer.tsx
    - ventago-app/src/views/acceso-ventago/AccesoVentagoView.tsx
    - ventago-app/src/views/branches/components/agents/ApiKeyCell.tsx
    - ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx
    - ventago-app/src/views/branches/components/wp/WpConfigTab.tsx
metrics:
  tasks: 2
  completed: 2026-10-08
---

# Phase 101 Plan 17: Sesión remota unida al código Summary

El técnico elige la sesión de la lista de su grant (sin dictar UUID), la tienda comparte pantalla desde la fila del acceso con consentimiento explícito, y los secretos visibles quedan fuera de la grabación.

## Commits (repo ventago-app, sin push)
- `8dcc70c2` Task 1: socket con grant, lista en visor y pestaña
- `a0e01271` Task 2: Compartir mi pantalla, avisos, rr-block

## Qué se hizo
- `soporte-remoto-logic.ts`: `authSocketSoporte`, `filasSesiones` (orden por createdAt desc, omite vencidas, «Sesión de {usuario} · pedida hace mm:ss», Esperando/En vivo), constantes del evento y del aviso.
- `socket-registry.ts`: los dos puntos de handshake usan `authSocketSoporte(ns, token, getAgentGrant())`.
- Visor: la página `pages/soporte/visor.tsx` queda como guard del flag + `dynamic`; el cuerpo vive en `views/soporte/VisorSoporte.tsx`, que también renderiza la pestaña «Sesión remota» de `AgenteAccesoView` (visible sólo con `REMOTE_SUPPORT_ENABLED`). Con acceso `sesion_remota` reemplaza el campo UUID por la lista; vacío «Nadie pidió soporte remoto todavía»; fin -> «Sesión finalizada» + Alert «El acceso terminó.». Usuarios internos conservan el flujo UUID.
- Tienda: `requestSupport({grantId})`; barra roja con «(máx. 15 min)»; aviso inline en el formulario y en la fila.
- R-4: spec con control (el detector falla sin rr-block; un rr-block en otro elemento no cuenta). Mutación manual: quitar el rr-block de ApiKeyCell hace fallar el spec.

## Inventario R-4 (insumo para la verificación de 101-21)
1. `views/branches/components/agents/ApiKeyCell.tsx` (texto enmascarado y botón de copia)
2. `views/branches/components/printer/PrinterConfigTab.tsx` (TextField de la API key; input, doble cobertura)
3. `views/branches/components/wp/WpConfigTab.tsx` (secret de un solo uso)
4. `views/acceso-ventago/AccesoVentagoView.tsx` (código de 6 dígitos)
Los `<input>` de contraseña (login, ModalUser, etc.) los cubre `maskAllInputs`.

## Deviations from Plan
- **[Rule 3] Extracción de VisorSoporte.tsx**: para compartir el visor con la pestaña sin duplicar lógica (la página no se puede importar como componente con el guard).
- **[Rule 1] Compartir vía evento**: `AccesoVentagoView` no instancia `useRemoteSupport` (habría grabado sin mostrar la barra roja, que vive en `RemoteSupportLayer`). Despacha `ventago:compartir-pantalla {grantId}` y la capa, única dueña de rrweb y barra, crea la sesión.
- **[Rule 1] FAB**: `onClick={requestSupport}` pasaba el evento de clic como `opts`; ahora `() => requestSupport()`.
- Archivos extra tocados: `WpConfigTab.tsx` (secret visible como texto, hallado por el inventario).

## Notas
- El socket compartido se crea una vez por namespace: si /support ya estaba abierto antes de elegir el acceso, el handshake no lleva el grant hasta reconectar. Verificar en el recorrido de 101-21.
- Flag sigue apagado; sin push.

## Self-Check: PASSED
Specs (14 tests), tsc 0 y eslint 0 en los archivos tocados; commits 8dcc70c2 y a0e01271 existen.
