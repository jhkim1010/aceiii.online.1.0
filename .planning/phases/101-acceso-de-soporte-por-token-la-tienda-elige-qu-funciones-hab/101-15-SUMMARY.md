---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 15
subsystem: ventago-app (frontend)
tags: [token-soporte, acceso-ventago, menu, redirects]
requires: [101-10, 101-12]
provides:
  - "Pantalla unica Admin > Token de soporte (/admin/token-soporte)"
  - "token-soporte-logic.ts: filasCodigosYAccesos, accionesDeFila, alcancesVisibles"
affects: [configuracion hub, menuRegistry, superadmin menu]
key-files:
  created:
    - ventago-app/src/views/acceso-ventago/token-soporte-logic.ts
    - ventago-app/src/__tests__/token-soporte-logic.spec.ts
    - ventago-app/src/pages/admin/token-soporte.tsx
    - ventago-app/src/__tests__/menu-token-soporte.spec.ts
  modified:
    - ventago-app/src/views/acceso-ventago/AccesoVentagoView.tsx
    - ventago-app/src/pages/admin/generar-token.tsx
    - ventago-app/src/pages/admin/soporte-remoto.tsx
    - ventago-app/src/pages/configuracion/index.tsx
    - ventago-app/src/navigation/menuRegistry.ts
    - ventago-app/src/components/chat/ChatBubble.tsx
  deleted:
    - ventago-app/src/views/soporte/TokenSoporteView.tsx
decisions:
  - "Puerta de pantalla = WithAccess allowedFunctions ['generar-token-soporte'] (mismo origen que menu y guard del servidor)"
  - "Los alcances enviados al servidor siguen el orden de ALCANCES, no el orden de clics"
metrics:
  tasks: 2
  completed: 2026-10-08
---

# Phase 101 Plan 15: Token de soporte unificado Summary

Una sola pantalla Admin > Token de soporte donde la tienda elige propositos (3 grupos, 8 opciones), genera el codigo con cuenta regresiva, lo manda al chat, anula pendientes, revoca accesos y audita; los caminos viejos redirigen o se retiran.

## Commits (repo ventago-app, sin push)
- `0eae906f` feat(101-15): vista unificada Token de soporte y logica pura de la tabla
- `64b1b694` feat(101-15): pagina Admin Token de soporte, menu y retiro de caminos viejos

## Resultado
- Logica pura (`filasCodigosYAccesos`: pendientes por vencimiento, activos, max 20 cerrados, pendiente vencido excluido; `accionesDeFila`; `alcancesVisibles`) con 10 tests.
- `AccesoVentagoView` reescrita segun UI-SPEC Screen 1: carga con `Promise.all` (accesos, codigos, opciones), checkbox «Sesion remota» solo si `sesionRemota`, sin cuota ni recargo (D-20), dialogos Anular/Revocar, Snackbar de exito, auto-refresco 30 s, dialogo «Que hizo» con Cuando/Que/Alcance/Metodo/Ruta, «x N» y «Bloqueado» en rojo.
- Pagina `/admin/token-soporte` (next/dynamic ssr:false) con `allowedFunctions=['generar-token-soporte']`; `/admin/generar-token` y `?tab=token-soporte|generar-token` redirigen.
- menuRegistry: `/admin/token-soporte` en el orden de Admin tras `/impresoras`, icono `tabler:key`; retirado «Soporte remoto» del menu superadmin. `/admin/soporte-remoto` ahora es una tarjeta informativa con enlace a `/admin/agentes`, sin llamadas a `/support-token`.
- `TokenSoporteView.tsx` eliminado (sin usos).

## Verificacion
jest (token-soporte-logic, menu-token-soporte, menu-paths-exist, menu-chat-entradas) 0 fallos; `tsc --noEmit` exit 0; eslint exit 0 sobre los archivos tocados.

## Deviations from Plan
Ninguna de fondo. Notas:
- `resumenAlcances` y `textoParaChat` se importan de `src/services/modo-soporte-logic.ts` (donde las dejo 101-13), no de `agente-logic.ts`.
- Comentarios del codigo evitan literalmente las cadenas `allowedApps` / `support-token/` para que los grep de aceptacion den 0.

## Known Stubs
Ninguno.

## Notas de despliegue
El seed del modulo (101-02) debe estar en produccion antes de desplegar este front (101-19), o el menu no aparece. Verificacion visual queda en 101-18.

## Self-Check: PASSED
Archivos creados existen; commits 0eae906f y 64b1b694 presentes en ventago-app.
