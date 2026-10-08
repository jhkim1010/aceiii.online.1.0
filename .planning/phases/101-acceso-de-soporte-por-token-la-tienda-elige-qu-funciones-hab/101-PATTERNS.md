# Phase 101: Acceso de soporte por token - Pattern Map

**Mapped:** 2026-10-08
**Files analyzed:** 27 (new/modified)
**Analogs found:** 26 / 27 (1 sin analogo directo: tabla `support_sessions.viewer_user_id` DB-enforced single viewer)

Rutas relativas a la raiz del repo. `API` = `api-ventago/src`, `APP` = `ventago-app/src`.
Nota: en este repo algunas fuentes se detectan como binarias; usar `grep -a`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `API/app/auth/decorators/agent-access.decorator.ts` (M) | decorator/config | metadata | si mismo (extender) | exact |
| `API/common/tenant/agent-grant.ts` (M) | utility (decision SQL) | request-response | si mismo | exact |
| `API/app/auth/guards/jwt-global.guard.ts` (M) | middleware/guard | request-response | si mismo (`decidirAgente`) | exact |
| `API/app/auth/guards/function-permission.guard.ts` (M) | guard | request-response | `API/app/auth/guards/user-role.guard.ts` (rama agente) | exact |
| `API/app/legacy-import/admin-role.guard.ts` (M, `d?.scope === 'legacy'` -> `scopes.includes`) | guard | request-response | si mismo | exact |
| `API/app/agente/agente-rules.ts` (M: etiquetas, `ALCANCES_VER`, listas de exclusion) | utility | transform | si mismo | exact |
| `API/app/agente/agente.service.ts` (M: anular codigo pendiente, listar pendientes, contexto) | service | CRUD | si mismo (`generarCodigo`, `revocarTienda`, `accesosTienda`) | exact |
| `API/app/agente/agente.controller.ts` (M: `GET agente/tienda/contexto`, `POST acceso-ventago/codigos/:id/anular`) | controller | request-response | si mismo (`usuariosTerminales` con `@AgentScope`) | exact |
| `GET`-handlers con `@AgentScope(...ALCANCES_VER)` en sales, online-orders, products, afip, branch, print, users, store, config (M) | controller | request-response | `agente.controller.ts` `usuariosTerminales` + `afip.controller.ts listIssuers` | role-match |
| `API/app/online-orders/online-order.model.ts` o servicio (M: redact `confirmToken`) | model | transform | `API/app/store/whatsapp-config/store-whatsapp-config.model.ts` `toJSON` | exact |
| `API/app/branch/branch.service.ts` o `branch.model.ts` (M: excluir `apiKey`) | model/service | CRUD | mismo `toJSON` redact | exact |
| `API/app/support/support.controller.ts` (M: `@AgentScope('sesion_remota')`, `assertCanView`) | controller | request-response | `agente.controller.ts` + `admin-role.guard.ts puedeImportarLegacy` | role-match |
| `API/app/support/support.gateway.ts` (M: handshake grant, `viewer:join`, `setInterval` re-check) | gateway | event-driven (WS) | si mismo `handleConnection`/`handleViewerJoin` + `decidirAcceso` | role-match |
| `API/app/support/support.service.ts` (M: `canView`/`activateSession` para agente, viewer unico en DB) | service | CRUD | si mismo | exact |
| `API/app/support-token/support-token.controller.ts` (M/deprecar `generate`/`validate`) | controller | request-response | si mismo | exact |
| `api-ventago/migrations/2026-10-XX-a-agente-alcances-ver.sql` (new) | migration | DDL + seed | `migrations/2026-10-03-a-agente-alcance-legacy.sql` | exact |
| `api-ventago/migrations/2026-10-XX-b-token-soporte-menu.sql` (new, sidebar structure seed + anular) | migration | DML seed | `migrations/2026-10-02-e-gestionar-permisos.sql` | role-match |
| `API/app/auth/guards/agent-readonly-scopes.spec.ts` (new) | test | runtime enumeration | `API/app/legacy-import/admin-role.guard.spec.ts` (bloque "todos los handlers") | role-match |
| `API/app/auth/guards/function-permission.guard.spec.ts` (M) | test | unit | si mismo | exact |
| `API/app/auth/guards/jwt-global.guard.spec.ts` (M) | test | unit | si mismo (`describe agente de plataforma`) | exact |
| `API/common/tenant/agent-grant.spec.ts` (M) | test | unit | si mismo | exact |
| `API/app/support/support.gateway.agent.spec.ts` (new) | test | unit (harness) | `API/app/agente/agente.spec.ts` (harness) | partial |
| `api-ventago/test/mutantes/agente-ver.json` + `scripts/mutantes-agente.sh` (new) | test script | batch | `scripts/mutantes-wp.sh` + `test/mutantes/wp.json` | exact |
| `APP/services/agent-grant.ts` (M: storeId/alcances/hasta, `CustomEvent`) | utility | storage | si mismo | exact |
| `APP/views/agente/agente-logic.ts` (M: `Alcance`, `ALCANCES`, `ETIQUETAS`) + `__tests__/agente-logic.spec.ts` | utility + test | transform | si mismo | exact |
| `APP/views/acceso-ventago/AccesoVentagoView.tsx` -> vista unificada "Token de soporte" (M/rename) | component | CRUD | si mismo + `APP/views/soporte/TokenSoporteView.tsx` (bloque codigo + "Mandar Token") | exact |
| `APP/views/agente/AgenteAccesoView.tsx` (M) | component | request-response | si mismo | exact |
| `APP/services/api.service.ts` (M: bloqueo no-GET, 403 `code`) + `api-error-presentation.ts` (+ spec) | service/utility | request-response | si mismo (`presentApiError`) | exact |
| `APP/configs/withAccess.tsx`, `APP/context/AuthContext.tsx`, `APP/navigation/vertical/index.ts`, `navigation/menuRegistry.ts`, `pages/configuracion/index.tsx`, `pages/admin/generar-token.tsx` (M) | config/component | request-response | si mismos | exact |
| Banner "Modo soporte", `<SinAlcance />`, `useModoSoporte()` (new) | component/hook | event-driven | `APP/components/support/RemoteSupportLayer.tsx` (barra fija) | partial |

## Pattern Assignments

### `API/app/auth/decorators/agent-access.decorator.ts` (decorator, metadata)

**Analog:** si mismo (lineas 1-45). Extender, no reescribir. Puntos de compatibilidad: un solo scope sigue guardandose como string (la spec `admin-role.guard.spec.ts:105` hace `toBe('legacy')`).

**Estado actual** (a extender):
```typescript
export const AGENT_PERMITIDO_KEY = 'agent:permitido';
export const AGENT_SCOPE_KEY = 'agent:scope';
export const ALCANCES_AGENTE = ['cert','usuarios_terminales','legacy'] as const;
export type AlcanceAgente = (typeof ALCANCES_AGENTE)[number];
export const AgentScope = (scope: AlcanceAgente) => SetMetadata(AGENT_SCOPE_KEY, scope);
export function esAlcanceAgente(v: unknown): v is AlcanceAgente {
  return typeof v === 'string' && (ALCANCES_AGENTE as readonly string[]).includes(v);
}
```
**Cambio (RESEARCH Pattern 1):** `ALCANCES_VER = ['ver_ventas','ver_productos','ver_facturas','ver_admin']`, agregar `'sesion_remota'`; `AgentScope(...scopes)` guarda string si 1, array si >1; helper `scopesDe(meta)`; `AgentScopeVer()` para comunes (D-07). Prohibido `@AgentScope` a nivel de clase (se valida en spec).

---

### `API/common/tenant/agent-grant.ts` (utility, request-response)

**Analog:** si mismo, `decidirAcceso` (lineas 48-76) y `DecisionAgente`.

**SQL actual a multi-scope-izar** (la spec `agent-grant.spec.ts` asserta estos strings; actualizarla a proposito):
```typescript
JOIN agent_action_policies p
  ON p.agent_user_id = g.agent_user_id AND p.action = $3 AND p.enabled
WHERE g.key = $1::uuid AND g.agent_user_id = $2
  AND g.revoked_at IS NULL AND g.expires_at > now()
  AND $3 = ANY (g.scopes)
```
**Cambio:** `p.action = ANY($3::text[])` y `g.scopes && $3::text[]`; devolver `{ grantId, storeId, scopes: string[], expiresAt }`. `DecisionAgente.scope` (singular) -> `scopes` (plural) o `puedeImportarLegacy` se rompe (`d?.scopes.includes('legacy')`). `support_access_events.scope` es `VARCHAR(30)`: registrar el primer scope coincidente.
`registrarEvento` (lineas 94-125) se reusa tal cual desde el gateway con `method:'WS'`.

---

### `API/app/auth/guards/jwt-global.guard.ts` (guard, request-response)

**Analog:** si mismo, `decidirAgente` (lineas ~176-260).

**Lectura de metadata a cambiar** (handler -> clase, como ahora):
```typescript
const scope = this.reflector.getAllAndOverride<AlcanceAgente | undefined>(
  AGENT_SCOPE_KEY, [context.getHandler(), context.getClass()]);
if (!scope) return false;
```
**403 con `code`** (RESEARCH sec. 8): en el bloque `if (!acceso)` lanzar `new ForbiddenException({ message: '...', code: valido ? 'AGENT_SCOPE_DENIED' : 'AGENT_GRANT_INVALID' })`; el 403 de handler sin marca (linea ~173) usa `AGENT_NO_SCOPE`. Mantener: 400 por `X-Store-Id` simultaneo, `registrarEvento` ANTES del handler, `request[AGENT_GRANT_DECISION] = {...}` y `request.user = {...request.user, storeId, actingAsStoreId, agentGrantId}` (copia, nunca mutar el objeto cacheado 30 s).

---

### `API/app/auth/guards/function-permission.guard.ts` (guard)

**Analog:** `API/app/auth/guards/user-role.guard.ts` lineas 51-61 (rama agente ya existente).

**Copiar esta rama al inicio de `canActivate`, tras leer `required`:**
```typescript
const request = context.switchToHttp().getRequest();
if (
  (request as Record<symbol, unknown> | undefined)?.[AGENT_GRANT_DECISION] &&
  this.reflector.getAllAndOverride(AGENT_SCOPE_KEY, [
    context.getHandler(),
    context.getClass(),
  ])
) {
  return true;
}
```
Imports: `AGENT_GRANT_DECISION` de `src/common/tenant/agent-grant`, `AGENT_SCOPE_KEY` del decorator. **Solo en el guard, NUNCA en `FunctionPermissionService.isAllowed()`** (abriria `PERMISO_VER_COSTO`, D-13). Hoy el guard lee con `this.reflector.get(FUNCTION_METADATA_KEY, context.getHandler())` (lineas 25-33).

---

### `API/app/legacy-import/admin-role.guard.ts`

**Analog:** si mismo, `puedeImportarLegacy` (precedente de guard que reconoce el grant):
```typescript
const d = decisionAgenteDe(req, u?.id);
return d?.scope === 'legacy';   // -> d?.scopes.includes('legacy')
```

---

### Handlers GET con `@AgentScope(...)` (controller, request-response)

**Analog:** `API/app/agente/agente.controller.ts` lineas 97-102 (`@Get('tienda/usuarios-terminales')` con `@Auth(ValidRoles.superadmin)` + `@AgentScope('usuarios_terminales')`) y `afip.controller.ts` `listIssuers` (ya `@AgentScope('cert')` -> `['cert','ver_facturas']`).

**Patron:**
```typescript
@Get('tienda/usuarios-terminales')
@Auth(ValidRoles.superadmin)
@AgentScope('usuarios_terminales')
usuariosTerminales(@GetUser() user: UsuarioReq) { ... }
```
- Se agrega a nivel de **handler**, solo GET de la lista de inclusion (RESEARCH sec. 3). Sobreescrituras de `@Get(':id')` van **al final** del controller.
- Nunca en: `@Public`, POST/PUT/PATCH/DELETE, `confirm-link`, `oauth/start`, `padron/*`, `/sellers/devices`, `/despacho/devices`, `*/reprint`, `print-codes` (secc. 4 y 5 de RESEARCH).
- `GET /sales/:id` -> `@AgentScope('ver_ventas','ver_facturas')` (D-05).

---

### Redaccion de secretos (model, transform) - `confirmToken`, `Branch.apiKey`

**Analog:** `API/app/store/whatsapp-config/store-whatsapp-config.model.ts` lineas 55-62:
```typescript
toJSON(): Record<string, unknown> {
  const values = { ...(super.toJSON() as Record<string, unknown>) };
  delete values.accessToken;
  values.accessTokenSet = !!this.getDataValue('accessToken');
  return values;
}
```
Otros ejemplos: `API/app/store/config/storeConfig.model.ts` (`emailApiKeyEnc`), `notas/models/nota.model.ts`. Para `confirmToken` (+`confirmTokenExpiresAt`) en `online-order.model.ts` y `apiKey` en `branch.model.ts`: redact en `toJSON` o `attributes.exclude`. Test: servicio mockeado devuelve modelo con secreto, se serializa a JSON y se asserta ausencia (camelCase y snake_case), con control (quitar el redact debe fallar). Cuidado: la logica interna que usa el token debe leer con `getDataValue`.

---

### `API/app/agente/agente.service.ts` / `agente.controller.ts` (anular codigo pendiente, D-18; contexto)

**Analog:** `generarCodigo` / `accesosTienda` / `revocarTienda` (lineas 95-232).

**Guard de tienda (copiar):**
```typescript
const storeId = await this.exigirAdminDeTienda(user);
```
**Patron de escritura + auditoria en la misma transaccion** (de `revocarTienda`):
```typescript
await this.sequelize.transaction(async (t) => {
  const filas = await this.q<{ id: number; agent_user_id: number }>(
    `UPDATE support_access_grants SET revoked_at = now(), revoked_by = $3, revoke_reason = 'tienda'
      WHERE id = $1 AND store_id = $2 AND revoked_at IS NULL RETURNING id, agent_user_id`,
    [grantId, storeId, user.id], t);
  if (!filas.length) throw new NotFoundException('Acceso no encontrado o ya terminado');
  await registrarEvento({ tipo: 'revocado', storeId, grantId, agentUserId: filas[0].agent_user_id,
    detalle: { por: 'tienda', userId: user.id }, transaction: t });
});
```
Para **Anular**: `UPDATE support_tokens SET status='cancelled'|... WHERE id=$1 AND store_id=$2 AND status='active' AND expires_at>now()` (filtro de `store_id` obligatorio, aislamiento de tenant); `registrarEvento` con tipo nuevo (agregar a `TipoEvento`, p. ej. `'anulado'`, cuidando CHECK de `support_access_events.kind` si existe). `canjear` debe devolver el mismo "Codigo invalido o vencido" para anulado. Listado de pendientes: extender `accesosTienda` (SELECT sobre `support_tokens WHERE store_id=$1 AND scopes IS NOT NULL AND status='active'`) con `UNION`/segunda consulta; `LIMIT 200` de `eventosAccesoTienda` se agota rapido: agrupar por ruta+metodo con `count`.
Controller: copiar el estilo `@Post('accesos/:id/revocar') @HttpCode(200) @Auth(ValidRoles.admin)` (lineas 55-60) para `@Post('codigos/:id/anular')`.
**Endpoint de contexto:** `@Get('tienda/contexto') @Auth(ValidRoles.agent) @AgentScope(...ALCANCES_VER)` (mismo estilo que `tienda/usuarios-terminales`); NUNCA poner `@AgentScope` en `/auth/me` (queda `@AgentePermitido`).
**Regla de costo (OVERAGE_CHARGE)**: sigue pendiente de decision; solo devolver `uso`/`aviso` como hoy.

---

### `API/app/support/support.gateway.ts` (gateway, event-driven)

**Analog:** si mismo (`handleConnection` lineas ~50-117, `handleViewerJoin` ~223-297) + `decidirAcceso`.

**Hoy** `client.data.storeId = payload.storeId` (null para agente) y `viewer:join` usa `supportService.canView(userId, roles)` y `activateSession(uuid, userId, storeId)`.
**Cambio:** en `handleConnection`, si `payload.roles` incluye `'agent'` y no hay `storeId`: leer `client.handshake.auth.agentGrant`, validar UUID, `decidirAcceso(userId, key, ['sesion_remota'])`; si OK -> `client.data.storeId = acceso.storeId`, `client.data.agentGrantId/Key/ExpiresAt`, `registrarEvento({ tipo:'permitido', method:'WS', route:'connect', scope:'sesion_remota', ... })`; si no, `auth_error` + `disconnect`. En `viewer:join`: `canView` O `client.data.agentGrantId` con re-chequeo de `decidirAcceso`. `setInterval` por socket (15-30 s) para re-validar y desconectar; **no usar cron** (workers no lideres pierden crons). Nunca restaurar `storeId` desde el payload al reconectar. El gateway no pasa por `JwtGlobalGuard`; necesita spec propia.
Mantener intactos: flag `isRemoteSupportEnabled()`, `census.admitClient`, `trustedClientIp`, 15 min, aislamiento `session.storeId === viewerStoreId`.

---

### `API/app/support/support.controller.ts`

**Analog:** el propio controlador (`@Auth()` sin roles) + `agente.controller.ts`. Agregar `@AgentScope('sesion_remota')` solo a `listActive`, `detail`, `end`; `assertCanView` reconoce `decisionAgenteDe(req, user.id)?.scopes.includes('sesion_remota')` (patron de `puedeImportarLegacy`). `create` NO lleva scope.

---

### Migraciones SQL

**Analog A (`2026-10-XX-a-agente-alcances-ver.sql`):** `api-ventago/migrations/2026-10-03-a-agente-alcance-legacy.sql` completo:
```sql
-- perm-cache: no toca tablas de permisos (role_functions · user_roles · ...).
-- w4-exempt: agent_action_policies tiene N filas (medido ...); el CHECK nuevo ... sin NOT VALID a proposito
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE agent_action_policies DROP CONSTRAINT IF EXISTS agent_action_policies_action_check;
ALTER TABLE agent_action_policies ADD CONSTRAINT agent_action_policies_action_check
  CHECK (action IN ('cert','usuarios_terminales','legacy','ver_ventas','ver_productos','ver_facturas','ver_admin','sesion_remota'));
INSERT INTO agent_action_policies (agent_user_id, action, enabled, updated_at)
SELECT u.id, 'ver_ventas', TRUE, now() FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id AND r.slug='agent' AND r.store_id IS NULL
WHERE u.store_id IS NULL
ON CONFLICT (agent_user_id, action) DO NOTHING;
COMMIT;
```
(un INSERT por alcance nuevo; valor por defecto enabled = pregunta abierta A7). Va ANTES del deploy del codigo (`crearAgente` inserta una politica por cada alcance; con el CHECK viejo daria 500). Verificar en local 5432 y produccion 5434 con `\d agent_action_policies`. Fecha de archivo >= 2026-08-21: la spec `migration-conventions.spec.ts` aplica (lock_timeout, `-- w4-exempt` con motivo). Si se agrega `support_sessions.grant_id` nullable (expand) o `viewer_user_id`, igual: nullable, sin NOT NULL en la misma entrega, indice con `CREATE INDEX CONCURRENTLY` en archivo aparte sin `--single-transaction`. Columna `support_tokens.status` para "anulado": revisar el CHECK existente antes.

**Analog B (seed del menu, D-19):** `api-ventago/migrations/2026-10-02-e-gestionar-permisos.sql` (patron `INSERT ... SELECT ... WHERE NOT EXISTS` sobre `functions` con `module_id`, `-- perm-cache:` y `-- w4-exempt:`). El menu del sidebar deriva de `structure`: **seed de produccion (DML, requiere aprobacion) antes del codigo**. Si el seed otorga a `role_functions`, el comentario `-- perm-cache:` es obligatorio (corte 2026-09-23). Para la remocion de las entradas antiguas, ver `ventago-app/src/__tests__/menu-paths-exist.spec.ts`.

---

### Test: enumeracion de handlers (`agent-readonly-scopes.spec.ts`)

**Analog:** `API/app/legacy-import/admin-role.guard.spec.ts` lineas 73-110 (bloque "todos los handlers llevan @AgentScope"):
```typescript
const conRuta = Object.getOwnPropertyNames(p).filter(
  (n) => n !== 'constructor' && Reflect.getMetadata('path', p[n]) != null);
expect(conRuta.sort()).toEqual([...nombres].sort());
for (const n of conRuta) expect(Reflect.getMetadata(AGENT_SCOPE_KEY, p[n])).toBe('legacy');
```
**Extender** (RESEARCH sec. 7) con recorrido de cadena de prototipos (controladores heredan de `CrudController`), `Reflect.getMetadata('method', fn)` y lista **explicita** de ~25 controladores (no importar los 205: OOM/ciclos de modelos). Cuatro verificaciones: ver_* solo en GET (o en `POSTS_QUE_LEEN`), exclusiones sin ver_*, `@Public` sin AgentScope, sin AgentScope de clase. Controles obligatorios: clase temporal con `@Post`+`@AgentScope('ver_ventas')` debe fallar; mutantes.

### Test: guards

**Analog:** `jwt-global.guard.spec.ts` lineas 120-215 (`describe('JwtGlobalGuard — agente de plataforma')`: helper `guard(meta)` que inyecta `{[AGENT_SCOPE_KEY]: 'cert'}`, `jest.spyOn(agentGrant,'decidirAcceso')`, `TenantContext.runPending`). Ampliar con arrays y `code`. `function-permission.guard.spec.ts`: helper `createMockContext(user)` (lineas 24-35) hay que ampliarlo con `getClass`, `getRequest` con simbolo `AGENT_GRANT_DECISION`; control: sin la rama el test debe fallar; "agente sin grant -> 403", "usuario normal sin cambios".
Ejecutar siempre por directorio: `cd api-ventago && env -u NODE_OPTIONS npx jest --maxWorkers=1 src/app/auth/guards` (nunca la suite completa ni `--findRelatedTests`).

### Mutaciones

**Analog:** `api-ventago/scripts/mutantes-wp.sh` + `test/mutantes/wp.json`. Formato: arreglo de `[archivo, buscar, reemplazar, descripcion, ambito?]`; `BASE` y `LISTA` por variable. Copiar a `mutantes-agente.sh`, `LISTA=test/mutantes/agente-ver.json`; poner `ambito` explicito por mutante (archivos fuera de BASE). `Tests: 0` / `NO_APLICA` no cuentan como "vivo".

---

## Frontend

### `APP/services/agent-grant.ts` (utility, storage)

**Analog:** si mismo (35 lineas). Hoy guarda solo la key en `sessionStorage` bajo `ventago.agentGrant`; agregar `{key, storeId, tienda, alcances, hasta}` (JSON) y un `getModoSoporte()` puro (vencido = no hay modo). `notifyAgentGrantRejected` hoy usa `new Event(AGENT_GRANT_REJECTED_EVENT)`: cambiar a `CustomEvent` con `detail.code` (D-09).
Logica pura -> `.ts` (la jest de la app no importa `.tsx`).

### `APP/services/api.service.ts` + `api-error-presentation.ts`

**Analog:** si mismos.
Interceptor de request (lineas 123-128):
```typescript
const agentGrant = getAgentGrant();
if (agentGrant) { config.headers['x-agent-grant'] = agentGrant; }
```
-> inmediatamente despues bloquear no-GET en modo `ver_*` (salvo `esPostDeLectura`), `Promise.reject(Object.assign(new Error('Modo solo lectura'), {agenteSoloLectura:true}))`.
Interceptor de respuesta (lineas 230-236): `if (403 && cfg.headers?.['x-agent-grant']) notifyAgentGrantRejected()` -> solo despachar el evento fatal si `data.code === 'AGENT_GRANT_INVALID'`; para `AGENT_SCOPE_DENIED/NO_SCOPE` no (no cierra el modo).
`presentApiError({status, serverMsg, method, url, isNetworkError})` es una funcion pura: agregar entrada `agentMode`/`code` y devolver el copy "Este codigo no permite ver esto" (UI-SPEC) con `severity:'warning'`. Test: `APP/__tests__/api-error-presentation.spec.ts` + una prueba de **sitio de llamada** (que el interceptor use el resultado), no solo del juez.

### `APP/configs/withAccess.tsx`, `AuthContext.tsx`, `navigation/vertical/index.ts`

**Analog:** si mismos.
- `withAccess.tsx`: `isPrivileged = (user?.roles||[]).some(r => PRIVILEGED_ROLES.includes(r))` (linea ~47) - NO anadir `agent` a `PRIVILEGED_ROLES`. Anadir `esAgenteConAcceso` que salte solo `hasRole` (el grant abrio, no un rol) y mantenga `superadminOnly` y las demas puertas sobre el `structure` sintetico.
- `navigation/vertical/index.ts` lineas ~327-355: `if (esAgentePlataforma(rolesArr)) { return [ {title:'Pedidos de tiendas',...}, {title:'Acceso a tiendas', icon:'tabler:key', path:'/admin/agente', action:'read', subject:'venta'}, ... ] }` -> en modo grant, fusionar con items derivados del `structure` sintetico (reusar la rama normal).
- `AuthContext.tsx`: superponer `{storeId, storeName, aliasName, logoUrl, structure}` desde `GET /agente/tienda/contexto` DESPUES de `refreshUser` (que vuelve a leer `/auth/me`); `roles` sigue `['agent']`.

### `APP/views/acceso-ventago/AccesoVentagoView.tsx` -> vista unificada "Token de soporte" (D-16/17/18/19)

**Analog:** si mismo (269 lineas) y `APP/views/soporte/TokenSoporteView.tsx` (bloque del codigo grande, `LinearProgress`, boton "Mandar Token a CoolSistema").

**Imports/estructura a conservar:**
```typescript
import apiConnector from 'src/services/api.service'
import { agruparCodigo, estadoAcceso, ETIQUETA_ESTADO, etiquetasAlcances, mensajeError, mmss, segundosRestantes } from 'src/views/agente/agente-logic'
```
Patron de cargar/generar/revocar: `apiConnector.get<AccesoRow[]>('/acceso-ventago/accesos')`, `apiConnector.post('/acceso-ventago/codigo', { alcances, minutos })`, `apiConnector.post(\`/acceso-ventago/accesos/${id}/revocar\`, {})`, errores con `mensajeError(e, '...')`. Checkbox con `FormControlLabel` + `FormHelperText sx={{ mt:-1, ml:8 }}` (UI-SPEC pide `FormHelperText` indentado 32 px: ajustar). Tabla `Table size='small'` (no fijar alturas: el override da 30 px). Chip de estado con `COLOR_ESTADO` (anadir `pendiente`, `anulado`).
**"Mandar Token a CoolSistema"** (TokenSoporteView ~187-195): se conserva el mecanismo
```typescript
window.dispatchEvent(new Event('openChat'));
setTimeout(() => { window.dispatchEvent(new CustomEvent('chatSendMessage', { detail: { message: `...${codigo}...` } })) }, 600);
```
con el texto de UI-SPEC ("Codigo de soporte de Ventago: {123 456}. Permite: ...").
Mantener ESLint: `newline-before-return`, `lines-around-comment`, sin imports sin usar. Pagina nueva con `next/dynamic(..., { ssr:false })` y `WithAccess allowedApps={['admin']}` (modelo: `APP/pages/admin/generar-token.tsx`).
**Quitar** de `APP/pages/configuracion/index.tsx` (lineas 98-99: `token-soporte`, `generar-token`) y apuntar `pages/admin/generar-token.tsx` a la vista unificada; agregar entrada en Admin del sidebar (esta derivada de `structure` -> seed primero, D-19). `menu-paths-exist.spec.ts` valida que los paths del registro tienen pagina.

### `APP/views/agente/AgenteAccesoView.tsx` y `agente-logic.ts`

**Analog:** si mismos.
`agente-logic.ts` lineas 1-15: `Alcance`, `ALCANCES`, `ETIQUETAS` (3 copias a sincronizar con `agente-rules.ts ETIQUETA_ALCANCE` y el decorator). Test de paridad en `__tests__/agente-logic.spec.ts` (usa `etiquetasAlcances`). `AgenteAccesoView.tsx`: `perdido()` hoy corre ante CUALQUIER 403 (listener de `AGENT_GRANT_REJECTED_EVENT`); limitarlo a `detail.code === 'AGENT_GRANT_INVALID'`. `activo` es state del componente (se pierde al navegar): leer de `agent-grant.ts` para el banner. Tabs actuales (cert/usuarios_terminales/legacy) sin cambios; `ver_*` no crea tab.

### Banner "Modo soporte" / `<SinAlcance />` / `useModoSoporte()`

**Analog parcial:** `APP/components/support/RemoteSupportLayer.tsx` (barra fija, zIndex 13000, textos, `isRemoteSupportEnabled`-style flag) y `hooks/useHasFunction.ts` (patron de hook con `useAuth`). Colores/tipografia: tokens de UI-SPEC (navy `#1a1a2e`, gold `#f5a623`, 4 tamanos / 2 pesos). Variable CSS `--modo-soporte-h` para reservar 48 px en el layout (`UserLayout.tsx` / `VerticalLayout.tsx`, sin romper `React.memo`/`useMemo` de la barra lateral).

### `APP/pages/soporte/visor.tsx` y `APP/realtime/socket-registry.ts`

**Analog:** si mismos. `socket-registry.ts` tiene dos `auth:{token}` (lineas ~167 y ~272) -> anadir `agentGrant: getAgentGrant()` solo en el namespace `support`. El `TextField` de UUID se sustituye por lista de `GET /support/sessions/active` en modo agente.

---

## Shared Patterns

### Fail-closed por metadata del handler
**Fuente:** `agent-access.decorator.ts` + `jwt-global.guard.ts decidirAgente`. Aplica a TODO handler nuevo: sin marca = 403 para el agente.

### Una sola decision por request
**Fuente:** `common/tenant/agent-grant.ts` (cabecera). Guards de ruta leen `request[AGENT_GRANT_DECISION]` (o `decisionAgenteDe(req, user.id)`); nunca rehacen SQL ni infieren de `user.roles`.

### Tenant isolation
`storeId` solo del grant (`request.user.storeId` reemplazado por copia); `X-Store-Id` junto a grant -> 400; nunca `@AgentScope` en `@Public`; URLs con `:storeId` (`/branch/store/:storeId`) deben probarse con otro `storeId` (el hook de tenant debe aislar).

### Secretos en respuestas
**Fuente:** `store-whatsapp-config.model.ts` `toJSON`, `emisor-campos-sensibles.ts` (`CAMPOS_SENSIBLES_EMISOR`, usado en `afip listIssuers`). Lista de inclusion, no de exclusion, y prueba de campos con control.

### Auditoria
`registrarEvento` (agent-grant.ts:94) siempre antes del handler; en transaccion cuando cambia estado (`transaction: t`). Nunca codigos, claves, ni contenido de certificados.

### Migraciones (CLAUDE.md)
`SET LOCAL lock_timeout`, nullable primero, `CONCURRENTLY` fuera de transaccion, `-- perm-cache:` si DML a tablas de permisos, `-- w4-exempt:` con motivo, owner `coolsistema` en tablas nuevas, aplicar en local (5432) y produccion (5434) y verificar con `\d`. DDL/DML de produccion con aprobacion; no durante 08-16 h salvo <=5 usuarios activos.

### Frontend
Logica pura en `.ts`; hooks SWR para datos de referencia; `apiConnector.remove()` (no `.delete()`); sin `rowHeight` manual; `next/dynamic` para paginas; ESLint como error de build.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| Viewer unico forzado en DB (`support_sessions.viewer_user_id` UPDATE condicional) | service | CRUD | Hoy el unico visor vive en un `Map` por worker (`viewerByUuid`); no hay precedente de cerrojo en DB para sockets. Usar `UPDATE ... WHERE viewer_user_id IS NULL RETURNING` (patron de claim atomico similar al canje en `agente.service.ts canjear`). |

## Metadata

**Analog search scope:** `api-ventago/src/app/{auth,agente,support,support-token,legacy-import,store,afip}`, `api-ventago/src/common/tenant`, `api-ventago/migrations`, `api-ventago/scripts`, `api-ventago/test/mutantes`, `ventago-app/src/{services,views,configs,navigation,pages,components/support,__tests__}`.
**Files scanned:** ~45
**Pattern extraction date:** 2026-10-08
