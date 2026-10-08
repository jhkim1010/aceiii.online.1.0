---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 11
subsystem: api
tags: [support, websocket, agent-grant, remote-session]
requires: [101-01, 101-02]
provides:
  - "GET /support/sessions/active para el agente: proyeccion exacta {uuid,status,createdAt,expiresAt,usuario}, solo sesiones de SU grant"
  - "createSession con grantId validado por el servidor"
  - "Visor unico en DB (reclamarVisor/latidoVisor/liberarVisor)"
  - "Gateway /support: handshake auth.agentGrant, viewer:join del agente, recheck 15 s, corte a min(sesion, grant)"
affects: [101-17, 101-21]
key-files:
  modified:
    - api-ventago/src/app/support/support-session.model.ts
    - api-ventago/src/app/support/support.service.ts
    - api-ventago/src/app/support/support.controller.ts
    - api-ventago/src/app/support/dto/support.dto.ts
    - api-ventago/src/app/support/support.gateway.ts
  created:
    - api-ventago/src/app/support/support.agent.spec.ts
    - api-ventago/src/app/support/support.gateway.agent.spec.ts
key-decisions:
  - "El claim se reclama con un unico UPDATE condicional (libre | mismo claim | latido > 45 s); el Map por worker queda solo como optimizacion"
  - "El visor interno tambien late y libera su claim; sin latido otro lo retomaria a los 45 s"
  - "Falla cerrada: 3 errores seguidos de re-verificacion cortan el socket del agente"
requirements-completed: [D-01, D-03, D-11, D-14, D-23]
completed: 2026-10-08
---

# Phase 101 Plan 11: Sesion remota por grant Summary

La sesion remota de Phase 41 ahora se une al codigo de acceso: el tecnico con el alcance `sesion_remota` ve solo las sesiones creadas con su grant («Compartir mi pantalla»), con visor unico forzado en la DB, recheck por socket y corte automatico.

## Commits (api-ventago, sin push)
- a5617009: servicio, controlador, modelo, DTO y support.agent.spec.ts
- 984b1dee: gateway y support.gateway.agent.spec.ts

## Que se hizo
- **Servicio**: `createSession(..., grantId)` valida (misma tienda, vigente, no revocado, incluye sesion_remota) o 400. `listarParaAgente` devuelve solo 5 claves; el nombre sale de `users` filtrado por `store_id`. `reclamarVisor` / `latidoVisor` / `liberarVisor` como UPDATE condicionales; `activateSession` (flujo interno) usa `reclamarVisor` y devuelve `occupied` si otro lo tiene.
- **Controlador**: `@AgentScope('sesion_remota')` en `listActive`, `detail`, `end` (no en `create`). El agente sobre una sesion con otro grant_id (o del FAB, NULL) recibe 404.
- **Gateway**: el agente se detecta con `isPlatformAgentUser`; `client.data.storeId` sale solo de `decidirAcceso`. `viewer:join` del agente re-ejecuta `decidirAcceso`, exige tienda y `grant_id` de la sesion y reclama el visor (claim `userId:grantId:socket`). `setInterval` de 15 s por socket (sin cron). Timer de corte = min(vencimiento de sesion, del grant). Eventos `support_access_events` method `WS`, scope `sesion_remota`, en connect / join / session:end / terminado / denegado.

## Verificacion
- jest `src/app/support` (`--maxWorkers=1 --forceExit`): exit 0, 37 tests (los dos specs nuevos).
- `tsc --noEmit`: exit 0.
- Mutaciones sobre el gateway (cada una restaurada): quitar la rama de agente → 15 fallan; quitar el chequeo grant_id de la sesion → 1 falla; quitar el corte del recheck → 9 fallan; storeId fijo en vez de decidirAcceso → compila mal (Tests 0 = no cuenta); quitar `armCut` del join → 1 falla; quitar la comparacion de grantId en el recheck → sobrevivia, se agrego un test y ahora muere (1 falla).
- Atomicidad del claim contra la DB local real (psql, mismo WHERE): A gana, B rechazado, B retoma tras 60 s sin latido.

## Deviations from Plan
- **[Rule 3] DTO**: el plan nombraba `dto/create-support-session.dto.ts`; el DTO real es `dto/support.dto.ts` (ahi se agrego `grantId`).
- **[Rule 2] Latido del visor interno**: como `activateSession` pasa a depender del claim en DB, el visor interno tambien necesita latido y liberacion (si no, el claim seria retomable a los 45 s). Se anadio sin tocar su permiso (`canView`).
- **Lint**: se agrego un `eslint-disable no-unsafe-member-access` a nivel de archivo en el gateway (socket.io tipa `client.data` como any; el archivo ya lo usaba en todas partes y la puerta cuenta lineas anadidas).
- No hizo falta SKIP_VERIFY: el gate paso en ambos commits.

## Artefactos de prueba que quedan (no se borran)
- Fila local `support_sessions` con uuid `11011011-0000-4000-8000-000000000011` (metadata `{"test":"101-11 claim check"}`, status active, viewer_claim `B`, tienda 3, usuario 15, vence en 15 min). Efecto: ninguno funcional; aparece en el listado interno de sesiones activas de la tienda 3 local hasta que expire.

## Known Stubs
Ninguno. La proyeccion `usuario` y el contrato del listado lo consume 101-17.

## Threat Flags
Ninguno nuevo. T-101-40..45 mitigados (specs con control); T-101-46 (rr-block) sigue pendiente en 101-17/101-21 segun el plan.

## Self-Check: PASSED
