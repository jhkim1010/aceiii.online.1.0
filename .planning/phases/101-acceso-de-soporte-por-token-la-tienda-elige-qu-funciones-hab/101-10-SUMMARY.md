---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 10
subsystem: api-ventago / agente (acceso de soporte)
tags: [agente, support-tokens, anular, contexto, eventos, D-06, D-11, D-13, D-14, D-18, D-20]
requires: [101-01, 101-02]
provides:
  - GET /agente/tienda/contexto (agente con grant ver_*) con structure sintetico de solo lectura
  - GET /acceso-ventago/codigos, POST /acceso-ventago/codigos/:id/anular, GET /acceso-ventago/opciones
  - eventos agrupados compatibles con el front viejo
  - cascada de revocacion sobre support_sessions por grant_id
  - generarCodigo sin cobro mensual (D-20)
key-files:
  created:
    - api-ventago/src/app/agente/agente-contexto.ts
    - api-ventago/src/app/agente/agente-contexto.spec.ts
    - api-ventago/src/app/agente/agente-anular-canje.itest.ts
  modified:
    - api-ventago/src/app/agente/agente.service.ts
    - api-ventago/src/app/agente/agente.controller.ts
    - api-ventago/src/app/agente/agente.spec.ts
    - api-ventago/src/common/tenant/agent-grant.ts
key-decisions:
  - "anularCodigo es un unico UPDATE condicional (id, store_id, status active, no vencido) con RETURNING; 0 filas -> 404 identico para otra tienda/canjeado/vencido/inexistente"
  - "contexto exige decision del guard (decisionAgenteDe) y lee scopes del grant filtrados por store_id y agent_user_id"
  - "structure sintetico: lista blanca por alcance + doble filtro (regex de verbos de escritura y SLUG_VER_COSTO) aunque la lista declarada ya no los trae"
metrics:
  tasks: 3
  completed: 2026-10-08
---

# Phase 101 Plan 10: Lado servidor del acceso de soporte Summary

Contexto de tienda para el agente, codigos pendientes con Anular atomico frente al canje (probado con una carrera real contra PG local), eventos agrupados que conservan las claves del front viejo, opcion de sesion remota por flag, cascada de revocacion sobre sesiones remotas y fin del cobro mensual en los codigos nuevos.

## Commit (repo api-ventago, sin push)
- 5688620f feat(101-10): contexto de tienda, codigos pendientes/anular atomico, eventos agrupados, opciones, cascada de revocacion y fin del cobro mensual

Las tres tareas tocan los mismos archivos (service, controller, spec), asi que se hizo un solo commit en vez de tres. Ver desviaciones.

## Que se hizo
- **Task 1**: `agente-contexto.ts` (`MODULOS_POR_ALCANCE`, `structureDeAlcances`) intersecta con el catalogo real (apps venta/producto/admin; modulo inexistente no aparece). `contextoTienda` en el servicio y `GET agente/tienda/contexto` con `@Auth(agent)` + `@AgentScopeVer()`. `/auth/me` no se toco. El spec cubre verbos de escritura, `SLUG_VER_COSTO`, metodo GET y exactamente los 4 `ver_*` en `contexto`, y que `AccesoVentagoController` no tiene `AGENT_SCOPE_KEY`. Control: un `contexto` con `@AgentScope('ver_ventas')` solo hace fallar el aserto de «los 4» (caso de control en el spec).
- **Task 2**: `TipoEvento` += `'anulado'`. `listarCodigosTienda` (pendientes + ultimos 20 anulados, sin token ni token_hash), `anularCodigo` (UPDATE unico + evento en la misma transaccion). `canjear` ya consumia con un UPDATE condicional unico; un codigo anulado cae en el mismo camino `fallo('codigo')` que uno inexistente (mismo error, mismo `canje_fallido`). Spec asevera el SQL y la transaccion compartida.
- **Task 3**: `eventosAccesoTienda` agrupa por (kind, scope, method, route) con `cantidad`, `ultimo` y `detalle` del ultimo, y mapea `at`, `tipo`, `alcance`, `method`, `route`, `detalle`. `opciones` (exige admin de tienda) devuelve `sesionRemota`. `generarCodigo` con `sesion_remota` y flag apagado -> 400. `revocarTienda` y `cortar` terminan `support_sessions` con ese `grant_id` en la misma transaccion (las del FAB con `grant_id` NULL no se tocan). Se quitaron el conteo mensual, `is_free`/`charge_amount` del INSERT, `uso`/`aviso` y las constantes de cobro (sin otros usos).

## Verificacion
- `jest src/app/agente`: exit 0 (48 tests, ejecutado con `--maxWorkers=1 --forceExit`); `tsc --noEmit`: exit 0; eslint de los archivos: 0 errores.
- itest `agente-anular-canje.itest.ts` contra PG local 5432: exit 0. Con anular escalonado (0 a 4,5 ms) ambos lados ganan en distintas rondas (p. ej. canje=10/anular=6, 9/7, 12/4) y siempre exactamente uno por ronda. Incluye un control de canje solo y un caso anulado == inexistente.
- Commit paso el gate normal de pre-commit (sin SKIP_VERIFY).
- Criterios: `date_trunc('month'` = 0, `charge_amount` = 0, `grant_id` = 5, `tienda/contexto` = 1, `src/app/support-token` sin cambios (el 410 es de 101-20).

## Deviations from Plan

**1. [Rule 3 - Proceso] Un solo commit para las 3 tareas.** Los tres tasks editan el mismo service/controller/spec; separarlos requeria staging parcial de hunks. Todo quedo verificado junto.

**2. [Rule 1 - Bug en el propio itest] Primera version del itest no probaba nada.** Las primeras corridas usaron la tienda 3 (borrada, `deleted_at` seteado): `canjear` nunca podia ganar y anular ganaba siempre, pasando de forma trivial. Lo detecto un caso de control (canjear solo). Se cambio a la tienda 266 (dummy7, viva) y admin 49, y se escalono el inicio de anular para barrer la zona de choque.

**3. Estructura del itest.** Usa un `Sequelize` plano (sin modelos) y mockea `registrarEvento` (su `db()` depende del modelo `Store`). El evento `anulado` en la misma transaccion se verifica en `agente.spec.ts`, no en el itest.

**4. `opciones` exige admin de tienda** (`exigirAdminDeTienda`) ademas de `@Auth(admin)`, para no depender solo del decorador.

## Artefactos que deja el itest (local, no se borran)
Cada corrida crea filas en PG local con codigo unico por corrida (re-ejecutable):
- `support_tokens` de **store 266 (dummy7)**, `generated_by` 49, `scopes={ver_ventas}`, 15 min de vigencia; quedan `used` (si gano el canje) o `anulado`. Estado actual: 78 `used`, 30 `anulado` en store 266.
- Si gano el canje: un `support_access_grants` del agente 257 (store 266, 30 min, vence solo) y una nota «Ventago entro a tu tienda con tu codigo» para los admin de la tienda 266.
- De las dos primeras corridas fallidas (tienda 3, borrada) quedan unos pocos `support_tokens` en store 3 (`anulado`, y algunos `active` que ya vencieron) sin efecto: la tienda esta borrada y `canjear` exige tienda viva.
Impacto: ninguno sobre otros tests (hash unico, grants vencen solos). Si el agente 257 tiene accesos activos de estas corridas, aparecen en su lista `GET /agente/accesos` hasta que venzan (30 min).

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo; T-101-33..38, 87, 88 mitigados como en el plan (store_id en anular, respuesta identica en canje, sin token/token_hash en listado, regex + costo en structure, evento `anulado` transaccional, cascada transaccional, claves viejas conservadas).

## Notas para 101-18/19/20
- `configurar-*` en `MODULOS_POR_ALCANCE.ver_admin` son provisorios (101-18 los reconcilia).
- El retiro 410 de support-token sigue pendiente (101-20, despues del front de 101-19).

## Self-Check: PASSED
- Archivos creados/modificados existen; commit 5688620f presente en api-ventago.
