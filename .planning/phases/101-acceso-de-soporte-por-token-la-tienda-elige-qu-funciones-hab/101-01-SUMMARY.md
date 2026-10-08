---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 01
subsystem: auth
tags: [nestjs, agent-grant, guards, scopes]
requires: []
provides:
  - "ALCANCES_VER, ALCANCES_AGENTE (8), AgentScope(...scopes), scopesDe, AgentScopeVer, esAlcanceVer"
  - "decidirAcceso multi-alcance -> {grantId, storeId, scopes, expiresAt}; grantVigente"
  - "403 del agente con code AGENT_SCOPE_DENIED / AGENT_GRANT_INVALID / AGENT_NO_SCOPE"
affects: [101-02, 101-03, support gateway, frontend]
key-files:
  modified:
    - api-ventago/src/app/auth/decorators/agent-access.decorator.ts
    - api-ventago/src/app/agente/agente-rules.ts
    - api-ventago/src/common/tenant/agent-grant.ts
    - api-ventago/src/app/auth/guards/jwt-global.guard.ts
    - api-ventago/src/app/legacy-import/admin-role.guard.ts
key-decisions:
  - "Un alcance se guarda como string, varios como arreglo (compat con admin-role.guard.spec)"
  - "Coincidencia de alcances y politica habilitada calculadas en SQL en una sola consulta"
  - "grantVigente solo elige el code del 403, nunca autoriza"
requirements-completed: [D-01, D-02, D-03, D-05, D-09, D-11, D-22, PREP-D4]
duration: ~25min
completed: 2026-10-08
---

# Phase 101 Plan 01: Contrato multi-alcance Summary

Decorator `@AgentScope` multi-alcance con 5 alcances nuevos (`ver_*`, `sesion_remota`), `decidirAcceso` que devuelve los alcances coincidentes en una sola consulta, y JwtGlobalGuard con 403 diferenciado por `code`.

## Commits (repo api-ventago, sin push)
- 51b9b7fe: alcances nuevos + @AgentScope multi-alcance + etiquetas
- 58b5bb71: decidirAcceso multi-alcance, grantVigente, codes en el guard, puedeImportarLegacy

## Deviations from Plan
- [Rule 1] `agente.spec.ts` "crear: nace con acciones apagadas" esperaba 3 politicas; ahora 8 (cambio intencional: `crearAgente` siembra una por alcance). Literal actualizado.
- Los 403 sin marca de usuarios que no son agente no cambian (no consultan grantVigente).
- Nota: el CHECK de `agent_action_policies` aun no admite los alcances nuevos; lo amplia la migracion de 101-02 (debe ir antes del deploy).

## Verification
jest (maxWorkers=1) por directorio: src/app/agente, src/common/tenant, src/app/auth/guards, src/app/legacy-import: exit 0. tsc --noEmit exit 0. Commit gate pasado.

## Self-Check: PASSED
