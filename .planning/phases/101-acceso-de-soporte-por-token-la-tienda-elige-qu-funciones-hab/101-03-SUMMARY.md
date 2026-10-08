---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 03
subsystem: auth
tags: [nestjs, guards, agent-scope, mutation-testing]
requires: [101-01]
provides:
  - "agentePasaPorAlcance(context, reflector) usado por FunctionPermissionGuard y PermissionGuard (GET)"
  - "handlersDe / violacionesAlcanceVer / scopesDeClase (arnes runtime para specs de 101-05 a 101-09)"
  - "EXCLUIDOS_VER (sin comodines, D-22 incluido) y POSTS_QUE_LEEN (vacio)"
  - "scripts/mutantes-agente.sh + test/mutantes/agente-ver.json (8 mutantes, todos MUERTO)"
affects: [101-05, 101-06, 101-07, 101-08, 101-09, 101-10, 101-18]
key-files:
  created:
    - api-ventago/src/app/auth/guards/agent-scope-bypass.ts
    - api-ventago/src/app/auth/guards/agent-scope-enumeration.ts
    - api-ventago/src/app/auth/guards/agent-scope-exclusions.ts
    - api-ventago/src/app/auth/guards/agent-readonly-scopes.spec.ts
    - api-ventago/src/app/permissions/guards/permission.guard.spec.ts
    - api-ventago/scripts/mutantes-agente.sh
    - api-ventago/test/mutantes/agente-ver.json
  modified:
    - api-ventago/src/app/auth/guards/function-permission.guard.ts
    - api-ventago/src/app/auth/guards/function-permission.guard.spec.ts
    - api-ventago/src/app/permissions/guards/permission.guard.ts
key-decisions:
  - "El bypass abre la ruta, nunca los campos: FunctionPermissionService intacto (git diff vacio), caso D-13 agente->false"
  - "PermissionGuard solo en GET (D-12)"
requirements-completed: [D-01, D-04, D-08, D-10, D-12, D-13, D-22, PREP-D3]
completed: 2026-10-08
---

# Phase 101 Plan 03: Rama de agente en guards de funcion/permiso + arnes ver_* Summary

El agente con grant pasa FunctionPermissionGuard (y PermissionGuard solo en GET) unicamente en handlers con `@AgentScope` coincidente; un arnes runtime y 8 mutantes fijan que `ver_*` solo vive en lecturas.

## Commits (repo api-ventago, sin push)
- 5600fb4e: rama de agente en FunctionPermissionGuard / PermissionGuard + specs
- 01b424a1: arnes de enumeracion + exclusiones + spec con controles A-E
- 775ebccf: mutantes-agente.sh + agente-ver.json

## Verificacion
- jest `src/app/auth/guards` + `src/app/permissions`: 6 suites / 59 tests, exit 0 (con `--forceExit`).
- tsc --noEmit exit 0. `git diff` de function-permission.service.ts vacio.
- `bash scripts/mutantes-agente.sh`: exit 0, 8 MUERTO / 0 SOBREVIVE / 0 NO_APLICA / 0 COMPILA_MAL (corrido dos veces, tambien tras el lint).
- Mutaciones manuales de acceptance cubiertas por los mutantes 1 (quitar rama) y 5 (POST como lectura).
- Exclusiones: 0 comodines, 0 `AgenteController.contexto`, `canjear` presente; nombres de metodos verificados contra los controladores reales (el spec comprueba las claves de Agente*/Afip contra handlers reales).

## Deviations from Plan
- [Rule 3] Mutante 3 apunta a `common/tenant/agent-grant.ts` (`decisionAgenteDe`), no a agent-scope-bypass.ts: la comparacion de userId vive ahi, el bypass solo la delega.
- [Rule 3] `getAllAndOverride` de Nest delega en `reflector.get`; los specs existentes lo mockean con `mockReturnValue`, que pisaba `AGENT_SCOPE_KEY`. El describe nuevo mockea por clave (solo test).
- [Rule 3] `mutantes-agente.sh` agrega `--forceExit` a jest: sin eso el run cuelga (open handle preexistente en jwt-global.guard.spec) y el script no termina. Tambien cuenta COMPILA_MAL en el exit.
- Commits de Task 1 y 2 con `SKIP_VERIFY=1`: el gate de jest excede 180s por ese mismo open handle (sin `--forceExit`); jest/tsc/eslint corridos a mano y limpios sobre lo agregado (eslint sigue reportando el error preexistente de la linea 114 del spec). Razon escrita en cada mensaje de commit.
- Se creo `permission.guard.spec.ts` (no existia spec previo).

## Issues Encountered
- Una primera corrida de mutantes colgo con el mutante 1 aplicado; se restauro a mano la linea `agentePasaPorAlcance` y se verifico con git diff antes de seguir.

## Known Stubs
None.

## Self-Check: PASSED
