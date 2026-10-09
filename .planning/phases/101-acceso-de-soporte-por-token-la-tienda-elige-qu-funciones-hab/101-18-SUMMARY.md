---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 18
subsystem: api-ventago (pruebas de mutación + inventario dinámico)
tags: [mutantes, inventario, agent-scope, D-07, D-10, D-13]
status: PARCIAL — Tasks 1 y 2 hechas; Task 3 (checkpoint visual) pendiente
requires: [101-05, 101-06, 101-07, 101-08, 101-09, 101-10, 101-11, 101-15, 101-16, 101-17]
provides:
  - "21 mutantes (8 de 101-03 + 13 nuevos), 21 MUERTOS, 0 vivos"
  - "scripts/inventario-agente.sh: recorrido por API con un grant local de los 4 ver_*"
  - "101-INVENTARIO.md: pantalla -> GET -> HTTP -> secretos -> costo -> decisión"
key-files:
  created:
    - api-ventago/scripts/inventario-agente.sh
    - .planning/phases/101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab/101-INVENTARIO.md
  modified:
    - api-ventago/test/mutantes/agente-ver.json
    - api-ventago/src/app/agente/agente-contexto.spec.ts
metrics:
  tasks_done: 2 de 3
  completed: 2026-10-09 (parcial)
---

# Phase 101 Plan 18: Mutantes e inventario dinámico — resumen PARCIAL

Tasks 1 y 2 completas y commiteadas; Task 3 queda «pendiente — checkpoint» (recorrido visual humano). El plan NO está marcado completo en ROADMAP.

## Commits (api-ventago, sin push)
- `38435082` Task 1: 13 mutantes nuevos + caso de spec para el filtro de slugs
- `6760c24c` Task 2: `scripts/inventario-agente.sh`

## Task 1 — Mutantes
`bash scripts/mutantes-agente.sh` → `죽음 21 / 생존 0 / 미판정 0 / 적용안됨 0 / 컴파일오류 0`, `git status` de api-ventago sin mutaciones residuales.

Nuevos (9–21): confirm-link con `@AgentScope`, `delete confirmToken`, `delete apiKey` de Branch, filtro de slugs de escritura de `agente-contexto`,
`anularCodigo` sin `store_id`, `anularCodigo` sin `status='active'`, gateway con storeId del payload, `reclamarVisor` sin condición de grant ajeno,
`@AgentScope('ver_facturas')` sobre `iibb` (D-22), `jwt-global` siempre `AGENT_NO_SCOPE`, seed sin `rolPuedeRecibirFuncion` (D-19),
`listAgents` con apiKey completa (D-10), `eventosAccesoTienda` sin `at`.

### Deviations
- **[Rule 1/2 — spec faltante]** El mutante 12 SOBREVIVIÓ en la primera corrida: el filtro `slugPermitido` es defensa propia y la lista blanca no contiene escritura, así que nada lo ejercitaba. Se agregó en `agente-contexto.spec.ts` un caso que contamina `MODULOS_POR_ALCANCE.ver_ventas` (con control: los slugs existen en el catálogo) y exige que el filtro los descarte; restaura en `finally`. Con eso 12 muere.
- **[Rule 3 — falso MUERTO]** El mutante 14 llevaba como ámbito el `.itest.ts`; pasado al jest unit "no encuentra tests" (exit 1) y contaría como muerto sin serlo. Ámbito cambiado a `src/app/agente` (el script cae a itest si sobrevive).
- Mutante 20 usa la rama `listAgents` (`apiKeyPrefix`); los SQL de thermal-agents/printers no seleccionan `api_key` (cubierto por el spec de 101-08, que sigue verde).
- Prettier obligó a reformatear el caso nuevo antes del commit (gate normal, sin `SKIP_VERIFY`).

### jest secuencial por directorio (`--maxWorkers=1`, cada uno exit 0)
| Directorio | Tests |
|---|---|
| src/app/auth/guards | 136 passed (8 suites) |
| src/app/agente | 49 passed (2) |
| src/common/tenant | 49 passed (5) |
| src/app/support | 37 passed (2) |
| src/app/online-orders | 84 passed (7) |
| src/app/branch | 17 passed (4) |
| src/app/print | 161 passed (16) |
| src/app/products | 249 passed (22) |
| src/app/sellers | 6 passed (1) |
| src/app/permissions | 11 passed (3) |
| src/app/users | 108 passed (11) |
| src/app/store | 431 passed (28) |
| src/common/secretos | 4 passed (1) |
| src/app/legacy-import | 163 passed (17) |
| src/common/migrations | 9 passed (1) |
(`agente` cuenta 49 después de agregar el caso nuevo; la corrida fue posterior al último cambio de spec, y `auth/guards` se repitió al final de Task 2: exit 0.)

## Task 2 — Inventario dinámico (detalle en 101-INVENTARIO.md)
- Recorrido con grant 95 (tienda 6, 4 ver_*): 62 GET (53 incluidos + 9 controles negativos), **0 filas no-ok**, **secretos = 0 en todos los 200** (D-10), **ninguna clave de costo/ganancia** en productos/cotización (D-13; control: el admin recibe `cost`/`costCurrency`/`costPorVariacion` en el mismo endpoint).
- **Hallazgo:** los `denegado` de `support_access_events` no listan los comunes faltantes — un handler sin marca se rechaza en `JwtGlobalGuard` antes del grant y no deja evento (grant 95: 57 `permitido`, 0 `denegado`). La evidencia es el 403 HTTP por ruta.
- Primera pasada: 8 filas no-ok, ninguna común faltante real: `sales/:id/printers` (solo reimpresión, excluido), `afip/iibb` (D-22), `terminal/store/:id` (solo superadmin), tres 400 por parámetro faltante, `products/all` 500 preexistente (también con el admin) y `functions/structure` (D-12, incluido a propósito).
- Reconciliación del menú de Configuración con la tabla de 101-08: sin cambios; `configurar-mercadopago` queda fuera del menú (usa wallets/movements sin marca; callejón sin salida).
- **Sin marcas nuevas**: no se tocaron controladores ni los 5 manifiestos de área.

### Diferido (fuera de alcance, preexistente)
- `GET /products/all` → 500 `Stocks is not associated to Product` (local, también con admin; ninguna vista lo llama).

## Task 3 — pendiente — checkpoint
Recorrido visual en build de producción (7 pasos con 5a/5b/5c). Ver mensaje de checkpoint. No iniciado.

## Artefactos de prueba locales (se conservan)
- API local corriendo: `npm run start:dev` (nest --watch) en puerto 5002, PID del puerto 39302 (padre 38918), con `DATABASE_NAME=ventago DATABASE_PORT=5432 DATABASE_HOST=127.0.0.1`; log en el scratchpad de la sesión.
- Grants/códigos creados por el script en la DB local: grants 93, 94, 95 (tienda 6, agente 257; ver_* completos, 2 h) + un código `318075` (alcances ver_*), todos vencen solos.
- Contraseñas locales de dos cuentas se igualaron a `Dummy1234` copiando el hash de `perm.admin@dummy.test`: usuario 37 (`depogte@dummy.test`, gerente, tienda 6) y usuario 257 (`agent@ventago.test`, username `agent@app`). Sólo DB local.

## Self-Check
Commits `38435082` y `6760c24c` existen en api-ventago; `101-INVENTARIO.md`, `inventario-agente.sh`, `agente-ver.json` existen; mutantes 21/21 muertos; 15 directorios jest exit 0.
