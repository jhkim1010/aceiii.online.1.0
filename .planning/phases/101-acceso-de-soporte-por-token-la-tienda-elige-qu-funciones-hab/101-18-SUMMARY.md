---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 18
subsystem: api-ventago (pruebas de mutación + inventario dinámico)
tags: [mutantes, inventario, agent-scope, D-07, D-10, D-13]
status: CHECKPOINT — Tasks 1-3 ejecutadas; espera «aprobado» y 2 decisiones del usuario
requires: [101-05, 101-06, 101-07, 101-08, 101-09, 101-10, 101-11, 101-15, 101-16, 101-17]
provides:
  - "23 mutantes (8 de 101-03 + 15 nuevos), 23 MUERTOS, 0 vivos"
  - "scripts/inventario-agente.sh: recorrido por API con un grant local de los 4 ver_*"
  - "101-INVENTARIO.md: pantalla -> GET -> HTTP -> secretos -> costo -> decisión"
key-files:
  created:
    - api-ventago/scripts/inventario-agente.sh
    - .planning/phases/101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab/101-INVENTARIO.md
  modified:
    - api-ventago/test/mutantes/agente-ver.json
    - api-ventago/src/app/agente/agente-contexto.spec.ts
    - api-ventago/src/app/terminal/terminal.service.ts
    - api-ventago/src/app/terminal/terminal.service.spec.ts
    - ventago-app/src/components/agente/ModoSoporteBanner.tsx
    - ventago-app/src/views/sales/list/SalesListView.tsx
metrics:
  tasks_done: 2 de 3
  completed: 2026-10-09 (parcial)
---

# Phase 101 Plan 18: Mutantes, inventario dinámico y recorrido visual

Tasks 1–3 ejecutadas. El recorrido visual encontró y corrigió 2 defectos; las 2 diferencias con el plan (5a–c, 7) se corrigieron según la decisión del usuario. Espera «aprobado»; el plan NO está marcado completo en ROADMAP.

## Commits (api-ventago, sin push)
- `38435082` Task 1: 13 mutantes nuevos + caso de spec para el filtro de slugs
- `6760c24c` Task 2: `scripts/inventario-agente.sh`
- `4ee515c8` fix: `GET /terminal` sin `branch.apiKey` anidado (D-10, hallado en la revisión 2)
- `2830fc13` 23 mutantes + inventario con 37 GET de montaje, semillas sin fallback, costo amplio

## Commits (ventago-app, sin push)
- `31dfe4f8` fix: banner del modo soporte en Portal (tapaba /productos) y Gastos → SinAlcance en /ventas
- `959ad682` fix: SinAlcance en el lugar (5a–c) y aviso de revocación en ≤30 s con diálogo (7)

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

## Task 2 — revisión 2 (CODEX)
Ver «Revisión 2» en 101-INVENTARIO.md: 37 GET de montaje que faltaban, 1 fuga real corregida
(`GET /terminal` → `box.branch.apiKey`), semilla de pedido que era el fallback `|| 1`, costo amplio
con control, IDOR con ids de la tienda 9, matriz por alcance. Final: 99 filas, 0 no-ok.

## Task 3 — recorrido visual (build de producción local, cmux, 2026-10-09 ~01:00–01:30)
Front `next build && next start -p 3050` con fetch/XHR/WS reescritos a `localhost:5002`
(verificado: el login escribió `active_sessions` local). Capturas en `101-18-capturas/`.

| paso | resultado | evidencia |
|---|---|---|
| 1 admin | OK — «Token de soporte» una sola vez bajo Admin; Configuración sin «Token de soporte»/«Acceso de Ventago» | p1-admin-sidebar |
| 1 gerente | OK — sin el ítem; `/admin/token-soporte` → `/unauthorized` | p1-gerente |
| 2 | OK — código `297 322` con cuenta regresiva, sin cuota/recargo (D-20); Pendiente → Anular (diálogo) → Anulado | p2-codigo, p2-anulado |
| 3 | OK — canje en /admin/agente, banner «Modo soporte · Tienda … · Sólo lectura · vence en 29:56»; «Entrar» → /ventas | p3-canje, p3-ventas |
| 4 | OK **tras 2 correcciones** — ver abajo. Detalle de venta sin botones; /productos sin costo/ganancia ni Guardar | p4-ventas2, p4-detalle, p4-productos4 |
| 5a/5b/5c | ~~DIFIERE~~ → OK tras `959ad682` (captura 14). Antes: — la pantalla sin alcance redirige a `/unauthorized` (sin banner, texto «Pedile a un administrador…») en vez de montar con SinAlcance | p5a-sucursales, p5b-ventas |
| 6 paso 6 | OK — `fetch` crudo `POST /api/products` → **403** `AGENT_SCOPE_DENIED` del servidor; 0 filas creadas | — |
| 7 | ~~PARCIAL~~ → OK tras `959ad682`, diálogo a los 8–15 s (captura 15). Antes: — revocación inmediata en el servidor; el agente se entera en la **siguiente petición** (1 s tras un clic), no por sí solo en ≤ 30 s; el aviso sale como toast y la pantalla cae en `/unauthorized` en vez del diálogo con «Volver a Usar código» | p7-terminado |

### Corregido durante el recorrido
1. **Banner estirado a 881 px** en pantallas de alto fijo (/productos): `.layout-page-content > :first-of-type { height:100% }`
   es por tipo de etiqueta; el banner (div) era el primer div porque la página empieza con `<form>`. Con zIndex 1400
   tapaba toda la pantalla. Mover el banner después de `{children}` **no** alcanzaba (sigue siendo el primer div);
   se pasó a `Portal` → 48 px, padre `BODY`.
2. **«Crear» de Gastos en /ventas** + un 403 por cada cambio de fecha: `expenses/search` no entra en ningún alcance.
   En modo soporte la región muestra `<SinAlcance />`.

### Decidido por el usuario (2026-10-09: «1, 2 둘 다 권장대로») — corregido en app `959ad682`
- **5a/5b/5c → SinAlcance en el lugar.** `WithAccess`: con llave de soporte guardada (vigente, vencida o revocada;
  `hayLlaveSoporte` = `parseModo` sin vencimiento) lo denegado muestra `<SinAlcance />` dentro del layout. Sin llave,
  `/unauthorized` como siempre (control: agente sin código → `/unauthorized`).
- **7 → sondeo de 30 s + diálogo.** `ModoSoporteBanner` pregunta `GET /agente/accesos` (sin `@AgentScope`: no escribe
  eventos de auditoría) con `setTimeout` encadenado y timeout 10 s; si la llave no está → `AGENT_GRANT_INVALID` →
  diálogo «El acceso terminó». El toast duplicado se quitó. Salir/Volver recargan `/admin/agente`
  (`router.push` perdía contra el `/unauthorized` de WithAccess). Logout borra la llave.
- CODEX (revisión del parche): aplicado — comparar la llave antes de avisar, sin consultas solapadas, `hayLlaveSoporte`
  ignora basura. No aplicado — AbortController (acotado con timeout 10 s) y suscripción reactiva de WithAccess (baja).
- Re-verificación (build de producción, cmux, códigos generados y canjeados a mano en el recorrido):
  /productos · /facturacion · /sucursales con sólo «Ver ventas» → SinAlcance con banner (captura 14);
  revocar grant 112 → diálogo a los 15 s sin acción del agente, sin toast, sigue en /sucursales (captura 15);
  «Volver a Usar código» y «Salir» → `/admin/agente`, llave borrada.
  1ª corrida: 8 s (grant 109). jest 31/31 (`modo-soporte-vigencia.spec.ts` nuevo).

### Notado, sin cambio
- Toast «Este código no permite ver esto» además del SinAlcance regional: diseño de `api-error-presentation`
  (fijado por su spec), se agrupa por título.
- `VariantsStock` muestra «Borrar stocks de esta fila» (sólo estado local; Guardar oculto). UI-SPEC: cobertura
  100 % de botones no es requisito de v1, el resto cae en el 403 central (paso 6).

## Artefactos de prueba locales (se conservan)
- API local corriendo: `npm run start:dev` (nest --watch) en puerto 5002, PID del puerto 39302 (padre 38918), con `DATABASE_NAME=ventago DATABASE_PORT=5432 DATABASE_HOST=127.0.0.1`; log en el scratchpad de la sesión.
- Grants 96–112 (script, matriz y recorrido; 108, 109 y 112 revocados en el paso 7; 110 revocado por un clic en la fila equivocada; 111 sigue vigente hasta vencer) y códigos 297322 (anulado), 517492, 199069, 957692. Perfiles cmux `admin101`/`agente101`.
- Grants/códigos creados por el script en la DB local: grants 93, 94, 95 (tienda 6, agente 257; ver_* completos, 2 h) + un código `318075` (alcances ver_*), todos vencen solos.
- Contraseñas locales de dos cuentas se igualaron a `Dummy1234` copiando el hash de `perm.admin@dummy.test`: usuario 37 (`depogte@dummy.test`, gerente, tienda 6) y usuario 257 (`agent@ventago.test`, username `agent@app`). Sólo DB local.

## Self-Check
Commits `38435082` `6760c24c` `4ee515c8` `2830fc13` (api) y `31dfe4f8` (app) existen; `101-INVENTARIO.md`, `inventario-agente.sh`, `agente-ver.json` existen; mutantes 23/23 muertos; script de inventario 99 filas 0 no-ok; 15 directorios jest exit 0.
