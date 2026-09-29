# Caja fuerte por sucursal — flag de activación (2026-09-28)

## Qué se construyó

Cada sucursal (`branches`) tiene ahora una columna `caja_fuerte_activa` (boolean,
default `false`) que decide si **el traspaso automático de dinero a la caja fuerte**
(cierre de caja nocturno / apertura del día siguiente) se ejecuta o no.

- **Sucursales existentes y nuevas arrancan con el flag en `false`** (decisión del
  usuario) — nada cambia para ellas hasta que un admin lo prenda explícitamente.
- Con el flag en `false`: el cierre/regularización de caja sigue ocurriendo
  normalmente (se sigue creando `box_settlements`, las sesiones se siguen cerrando),
  pero **el dinero se queda en el cajón** — no se escribe ni el retiro de
  `BoxOperation` ni el ingreso en `caja_fuerte_operations`. `settledAmount` queda en 0
  para ese período. La fórmula de «cuánto debería haber en el cajón» (`expectedCash`)
  **no se tocó** — sigue siendo la misma de siempre.
- Con el flag en `true`: comportamiento idéntico al de antes de este cambio.
- **Las operaciones manuales de la pantalla de caja fuerte NO están gateadas** — un
  admin puede seguir haciendo depósitos/retiros manuales sin importar el flag.

## Todos los caminos de traspaso automático encontrados (y cómo quedó cada uno)

Se buscó con `grep -a` (obligatorio en este repo) en `caja-fuerte/`, `box/`,
`box-operation/`, `cashRegister/` y cualquier cron, por `caja_fuerte`, `cajaFuerte`,
`auto_cierre`, `apertura_caja`, `addOperation`.

| # | Archivo:línea | Qué hace | Gateado |
|---|---|---|---|
| 1 | `api-ventago/src/app/cashRegister/cashRegister.service.ts` → `settleBoxThrough()` (línea ~2170) | **Único** punto de la fórmula de cierre/regularización (lo dice el propio comentario del código: «정산 규칙은 여기 하나뿐이다» — llamado tanto por el cron nocturno (`cash-register-autoclose.cron.ts`) como por la apertura de caja del día siguiente (`autoCloseAndReopen`)). Crea `BoxOperation` tipo `retiro` + `CajaFuerteOperation` tipo `ingreso`/`source=auto_cierre`. | ✅ Sí — se agregó `Branch.findByPk(branchId)` antes de decidir, dentro de la misma transacción. Si `cajaFuerteActiva !== true`, se saltan ambas escrituras y `transferredToSafe = 0`. |
| 2 | `api-ventago/src/app/cashRegister/cashRegister.service.ts` → `withdrawOpeningFromCajaFuerte()` (línea ~310, llamada desde 3 sitios: declaración de apertura a las 0, `settlePreviousAndFundOpening`, y `autoCloseAndReopen`) | El **espejo** de `auto_cierre` — retira de la caja fuerte el monto inicial del día siguiente (`source=apertura_caja`). El propio comentario del código dice: «이 두 방향이 함께 있어야 장부가 닫히고, 한쪽만 있으면 금고가 매일 부풀거나 마른다» (si sólo se gatea un sentido, la caja fuerte se infla o se seca sin motivo). | ✅ Sí — mismo criterio (Branch.cajaFuerteActiva), gateado por la misma razón que el código ya documentaba para el sentido contrario. Esto **no estaba pedido literalmente** en el enunciado (que hablaba sólo de traspasos *hacia* la caja fuerte), pero dejarlo sin gatear permitía que, con el flag apagado, esta función igual intentara sacar plata de una caja fuerte que nunca recibió ese depósito — drenando saldo no relacionado (depósitos manuales/regularización) para financiar una apertura que nunca depositó nada. Documentado como desviación (Regla 1 — bug). |
| 3 | `api-ventago/src/app/cashRegister/cashRegister.service.ts` → `regularizeBoxRange()` (línea ~937-955) | Depósito a caja fuerte con `source='manual'`, descripción «Regularización por arqueo». | ❌ No gateado — a propósito. `source` es literalmente `manual`: lo dispara un admin que cuenta físicamente el cajón, no un cron/cierre automático. Cae bajo «operaciones manuales no gateadas». |
| 4 | `api-ventago/src/app/caja-fuerte/caja-fuerte.controller.ts` (depósito/retiro manual desde la pantalla de caja fuerte) | Endpoints manuales de la pantalla de Caja Fuerte. | ❌ No gateado — a propósito, por enunciado explícito. |

No se tocó ninguna fórmula de saldo (`caja-balance.ts`, `sumByType`, `movNeto`,
`saldoFinal`) — sólo se decide *si* se ejecuta el traspaso, nunca *cuánto*.

## Migración (aplicada sólo en LOCAL, dos veces, confirmando idempotencia)

Archivo: `api-ventago/migrations/2026-09-28-e-branches-caja-fuerte-activa.sql`

```sql
SET lock_timeout = '5s';

ALTER TABLE branches
  ADD COLUMN IF NOT EXISTS caja_fuerte_activa BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN branches.caja_fuerte_activa IS
  'Caja fuerte 자동이체(정산/마감) 허용 여부. false=자동이체 건너뜀(돈은 서랍에 머묾), 수동 입출금과는 무관. 기본 false — 사용자가 명시적으로 켠 지점만 자동이체.';

-- + bloque DO de verificación (columna existe, NOT NULL, default=false,
--   count(*) de branches == count(*) con caja_fuerte_activa=false)
```

- **Tipo**: expand-only, un solo paso. `ADD COLUMN ... NOT NULL DEFAULT false` con
  default constante es *metadata-only* en PG18 (no reescribe la tabla, lock corto) —
  no requiere el patrón expand→migrate→contract de W4 porque no hay backfill: el
  propio default ya es el valor correcto para todas las filas existentes.
  `IF NOT EXISTS` la hace re-ejecutable sin error.
- **Aplicada en LOCAL (5432) dos veces** para confirmar idempotencia:
  - 1ª vez: `25 branches, all false` (verificado por el bloque DO).
  - 2ª vez: `NOTICE: column "caja_fuerte_activa" of relation "branches" already
    exists, skipping` + mismo `25 branches, all false`.
- **NO aplicada en producción** (bloqueado por el orquestador — «modificaría cada
  lectura de sucursal en prod antes de que la migración esté aprobada»).

### Impacto esperado en producción (medido por SELECT de sólo lectura)

```
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c \
  'SELECT count(*) AS total_branches FROM branches;'"
→ 29
```

- **29 filas afectadas** — las 29 sucursales existentes en prod pasarían a tener
  `caja_fuerte_activa = false`.
- **Ningún traspaso automático a caja fuerte volvería a ejecutarse hasta que un admin
  prenda el flag por sucursal** desde Sucursales → columna «Caja fuerte». Esto es
  intencional (decisión del usuario), pero implica que **el día que se apruebe y
  aplique esta migración en prod, todas las sucursales dejan de mandar dinero a la
  caja fuerte automáticamente** hasta que alguien las prenda una por una. Vale la
  pena avisar a los usuarios de Caja Fuerte antes de aplicar en prod.
- Owner/secuencia: no aplica (es una columna sobre tabla existente, no tabla nueva).

## Endpoint nuevo

`PATCH /branch/:id/caja-fuerte` — body `{ activa: boolean }`.

- Mismo guard que `PUT /branch/:id` (`@FunctionGuard('editar-sucursal', 'update')`).
- Aislamiento de tenant delegado 100% a `BranchService.update` →
  `CrudService.update/findOne` — el mismo camino que ya usa el PUT genérico de
  sucursal. No se escribió lógica de aislamiento nueva (evita duplicar la
  verificación y que quede una diferencia sutil entre los dos endpoints).
- Se corrigió al escribirlo un bug que existe en otros `getDescription` de este
  mismo controller: `AuditInterceptor` llama `getDescription(result, body, user)`,
  pero varios callbacks existentes lo etiquetan `(body, result, params)` — funciona
  por casualidad en esos otros casos porque el primer argumento real (`result`)
  también tiene el campo que leen. El callback nuevo usa el orden real.
- `GET /branch/store/:storeId` y demás listados de `Branch` ya devuelven la columna
  sin cambios adicionales (Sequelize incluye todos los atributos por default, ningún
  endpoint de branch restringe `attributes`).

## Frontend

- `Admin › Sucursales` (`ventago-app/src/views/branches/components/branch/BranchTable.tsx`
  + `DataConfig.tsx`) — columna nueva «Caja fuerte» con chip Activado/Desactivado
  (mismo estilo que ¿Activo?), clickeable si el usuario tiene `editar-sucursal`.
  Click = actualización optimista (cambia el chip antes de la respuesta) + rollback
  y toast de error si el PATCH falla.
- No se tocó `ModalBranch.tsx` (formulario de edición) — ya tiene lógica no
  relacionada de AFIP/CUIT/gateway y la columna de la tabla cubre el requerimiento
  tal como está planteado («let an admin toggle it»).
- Helper nuevo reutilizable: `chipBooleanToggle()` en
  `ventago-app/src/components/table/columns.tsx` (mismo look de `chipBoolean` pero
  clickeable).

## Tests (api-ventago)

Todos corridos con `env -u NODE_OPTIONS npx jest <ruta> --maxWorkers=1` (obligatorio
en este repo — jest con opciones default cuelga la máquina).

- `src/app/cashRegister/cash-register-autoclose.spec.ts` — nuevo describe
  `settleBoxThrough — 지점 「Caja fuerte」게이트` (3 tests): flag `false` no llama a
  `addCajaFuerteOp` ni `addBoxOp`, `transferAmount` vuelve 0, `settledAmount: 0` en el
  `BoxSettlement` (pero `expectedCash` intacto); flag `true` sigue igual que antes
  (control); el cierre de sesión y la creación del settlement ocurren igual con el
  flag apagado. Más 1 test nuevo en el describe de `withdrawOpeningFromCajaFuerte`:
  flag apagado → no se llama `addCajaFuerteOp`.
- `src/app/cashRegister/cash-register-declare-opening.spec.ts` — se agregó el mock de
  `Branch.findByPk` (con flag `true`) que faltaba para que el flujo real de
  declaración de apertura (que llama a `withdrawOpeningFromCajaFuerte` de verdad, no
  mockeada) siguiera funcionando tras el cambio.
- `src/app/branch/branch-caja-fuerte-gate.spec.ts` (nuevo, 7 tests) — 4 sobre
  `BranchService.update`: rechaza sucursal de otro matiz (`ForbiddenException`),
  acepta la propia (control), superadmin sin restricción de matiz, 404 si no existe.
  3 sobre `BranchController.setCajaFuerteActiva`: admin normal pasa su `storeId`,
  superadmin pasa `storeId: undefined`, `activa` no-boolean → 400.

**Resultado**: 22 + 4 (declare-opening no cambia de cantidad, sólo se arregla el
mock) + 7 = 29 tests nuevos o tocados, todos en verde. Suite completa de los módulos
afectados (`branch`, `cashRegister`, `caja-fuerte`, `box-operation`, `store`):
**40 suites, 569 tests, todos pasan.**

### Chequeo de mutación (manual, sin infraestructura de mutación en este módulo)

Se invirtió cada condición de gate una por vez (con backup + restore del archivo) y
se confirmó que **exactamente** el test correspondiente fallaba y ningún otro:

- Mutación en `settleBoxThrough` (forzar gate siempre `true`) → falló sólo
  `★★ 게이트가 꺼져 있으면 이체를 건너뛴다`.
- Mutación en `withdrawOpeningFromCajaFuerte` (forzar `if (false)`, nunca saltar) →
  falló sólo `★★ 지점 게이트가 꺼져 있으면 출금도 건너뛴다`.

## Commits

**api-ventago**
- `a8b0f009` — feat(branch): add caja_fuerte_activa flag column (default false)
- `521de6db` — feat(cash-register): gate automatic caja fuerte transfers by branch flag
- `778de42f` — feat(branch): add PATCH /branch/:id/caja-fuerte endpoint

**ventago-app**
- `197ab125` — feat(sucursales): add Caja fuerte column with click-to-toggle chip

No se pusheó nada (bloqueado por el orquestador), no se movió el puntero de
submódulo en el repo raíz, no se tocó producción salvo el `SELECT count(*)`
de sólo lectura citado arriba.
