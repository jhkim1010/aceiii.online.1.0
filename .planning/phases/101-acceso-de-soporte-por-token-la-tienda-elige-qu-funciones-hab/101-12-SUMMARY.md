---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 12
subsystem: ventago-app (frontend)
tags: [modo-soporte, agente, alcances, api-service]
requires: [101-01]
provides:
  - "modo-soporte-logic.ts (esSoloLectura, bloquearSolicitudAgente, codigoAgenteDe, primeraPantalla, resumenAlcances, textoParaChat, parseModo)"
  - "agent-grant.ts con getModoSoporte/setModoSoporte y CustomEvent con detail.code"
  - "agente-logic.ts con los 8 alcances, CHECKBOX/HELPER/GRUPOS de UI-SPEC"
affects: [101-13, 101-14, 101-15, 101-16, 101-17]
key-files:
  created:
    - ventago-app/src/services/modo-soporte-logic.ts
    - ventago-app/src/__tests__/modo-soporte-logic.spec.ts
  modified:
    - ventago-app/src/services/agent-grant.ts
    - ventago-app/src/services/api.service.ts
    - ventago-app/src/services/api-error-presentation.ts
    - ventago-app/src/services/error-bus.ts
    - ventago-app/src/views/agente/agente-logic.ts
    - ventago-app/src/views/agente/AgentesAdminView.tsx
    - ventago-app/src/views/acceso-ventago/AccesoVentagoView.tsx
    - ventago-app/src/__tests__/agente-logic.spec.ts
    - ventago-app/src/__tests__/api-error-presentation.spec.ts
decisions:
  - "El bloqueo en cliente es ayuda de UX; la frontera sigue siendo el 403 del servidor"
  - "Sólo AGENT_GRANT_INVALID dispara el evento fatal; SCOPE_DENIED/NO_SCOPE marcan error.agenteSinAlcance"
metrics:
  tasks: 3
  completed: 2026-10-08
---

# Phase 101 Plan 12: Base frontend del modo soporte Summary

Modo soporte guardado como JSON en sessionStorage (compatible con la llave en formato string), bloqueo central de escrituras en modo sólo lectura, 403 tratados por `code`, y lista única de 8 alcances con textos exactos de UI-SPEC, con spec de paridad contra el decorator del api.

## Commits (repo ventago-app, sin push)
- d2f9a030 feat(101-12): 8 alcances, textos UI-SPEC y modo soporte (lógica pura)
- 6abc5354 feat(101-12): bloqueo de escrituras en modo solo lectura y 403 por code
- 4b9e1eca feat(101-12): AgentesAdminView con 8 switches agrupados por alcance

## Verificación
- jest (agente-logic, modo-soporte-logic, api-error-presentation): 0 fallos; la paridad con `agent-access.decorator.ts` corre (no se omite) y tiene control con fuente falsa.
- tsc --noEmit exit 0; eslint de los archivos tocados exit 0.

## Deviations from Plan

**1. [Rule 3 - Blocking] Tipo `EstadoAcceso` ampliado rompía tsc en AccesoVentagoView**
- `COLOR_ESTADO` no tenía `pendiente`/`anulado`; se agregaron (warning/default). Commit d2f9a030.

**2. [Rule 3 - Blocking] `errorBus` no aceptaba severity `info`**
- El plan exige severity info para el 403 de alcance; se amplió el tipo en `error-bus.ts` (GlobalErrorBanner ya pasa severity directo a MUI Alert). Commit 6abc5354.

**3. Cambio menor de tipo en AgentesAdminView adelantado al commit 1** (el gate de tsc lo exigía); el resto de la Task 3 va en 4b9e1eca.

## Known Stubs
Ninguno. `POSTS_QUE_LEEN_FRONT` es vacío por contrato del plan.

## Threat Flags
Ninguno.

## Self-Check: PASSED
