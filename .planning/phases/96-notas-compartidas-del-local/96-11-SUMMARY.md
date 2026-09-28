---
phase: 96-notas-compartidas-del-local
plan: 11
subsystem: notas
tags: [notas, nota-secreta, bcrypt, hmac, rate-limit, tenant]
requires: [96-10]
provides: [nota-secreta-gate-servidor, unlock-endpoint, nota_unlock_attempts]
affects: [api-ventago/src/app/notas, ventago-app/src/views/notas, ventago-app/src/services]
tech-stack:
  added: []
  patterns:
    - "gate de contenido en servidor: una secreta bloqueada NO consulta adjuntos/respuestas/reacciones"
    - "prueba de desbloqueo HMAC firmada (≤5 min) atada a nota+usuario+hash, en header x-nota-unlock"
    - "limitador pesimista persistido en DB bajo lock de fila (4 workers PM2)"
key-files:
  created:
    - api-ventago/migrations/2026-09-28-c-notas-secretas.sql
    - api-ventago/src/app/notas/models/nota-unlock-attempt.model.ts
    - api-ventago/src/app/notas/notas-secret.spec.ts
    - ventago-app/src/__tests__/notas-api-secret.spec.ts
  modified:
    - api-ventago/src/app/notas/{notas-rules,notas-query.service,notas-command.service,notas.controller,nota-adjuntos.controller,notas.types}.ts
    - api-ventago/src/app/notas/models/{nota.model,index,notas-models.spec}.ts
    - ventago-app/src/services/{api.service,notas.api}.ts
    - ventago-app/src/views/notas/{ComposeNotaDialog,NotaDetailPane,NotaAttachmentView,NotaInboxList,NotasView}.tsx
    - ventago-app/src/views/notas/{notas-logic,notas.types}.ts
key-decisions:
  - "Prueba de desbloqueo = token HMAC firmado (no en memoria): el siguiente pedido puede caer en otro worker; el hash de la nota entra en la firma, así re-clavar invalida todo token viejo sin estado en servidor"
  - "Contraseña incorrecta y prueba faltante = 403 con code (NOTA_WRONG_PASSWORD / NOTA_LOCKED), nunca 401: el interceptor del front desloguea con 401"
  - "Reserva pesimista del intento (se cuenta como fallido ANTES de bcrypt, bajo FOR UPDATE): 5 comparaciones máx. por ventana aun con pedidos paralelos"
  - "POST /notas/:id/secret para re-clavar/quitar desde la vista bloqueada (S-09); PATCH también re-clava sin prueba, pero editar contenido de una secreta exige prueba"
  - "En la lista una secreta va siempre bloqueada: sin excerpt y con replyCount/attachmentCount = 0"
metrics:
  completed: 2026-09-28
---

# Phase 96 Plan 11: Nota secreta Summary

Nota secreta con contraseña por nota: hash bcrypt (10 rondas, el paquete de auth), gate
de contenido en servidor, `POST /notas/:id/unlock` que devuelve el detalle completo más
una prueba HMAC de ≤5 min que viaja en el header `x-nota-unlock` (nunca en la URL), y un
contador anti fuerza bruta en DB (5 fallos → 429 por 15 min). Implementado según
S-01..S-10 de `96-11-SECRET-SPEC.md`.

**Estado de despliegue: NADA publicado.** Sin `git push`, sin Jenkins y sin escrituras en la
DB de producción. La migración está aplicada **sólo en local (5432)**. Los punteros de
submódulo del repo raíz **no** se movieron.

## Qué se construyó

### Backend (api-ventago)
- **Esquema:** `notas.is_secret` / `notas.secret_hash`, CHECK `notas_secret_hash_ck`, tabla nueva `nota_unlock_attempts` (ver Migración).
- **Modelos:** `Nota.isSecret` / `Nota.secretHash`, con `type` explícito. `Nota.toJSON()` elimina `secretHash`. Modelo `NotaUnlockAttempt` agregado a `NOTA_MODELS`.
- **Reglas (`notas-rules.ts`):**
  - `buildSearchWhere`: el cuerpo sólo participa del match si `isSecret = false` (S-04).
  - `parseSecretPassword`: 4..64 caracteres.
  - `resolveSecretChange`: crear / conservar / cambiar / quitar.
  - `consumeUnlockAttempt` + `isUnlockLocked`: el limitador S-07.
  - `sign/verifyUnlockToken`: HMAC-SHA256 con clave derivada de `JWT_SECRET_KEY`. Atado a (notaId, userId, secretHash), con vencimiento ≤5 min. Rechaza tokens cuyo vencimiento cae más allá del TTL.
- **Lectura (`notas-query.service.ts`):**
  - `buildDetail(v, n, unlocked)` es el gate. Con una nota bloqueada no consulta adjuntos, respuestas ni reacciones. `body` y `excerpt` quedan vacíos y los conteos en 0. `can.edit`, `can.ack` y `can.reply` quedan en false. `can.resetSecret` sólo es true para el autor.
  - `detail()` acepta la prueba por header.
  - `assertUnlocked()` (403 `NOTA_LOCKED`) protege historial, vista (S-08) y Entendido (S-08).
  - En la lista una secreta siempre va bloqueada.
- **Escritura (`notas-command.service.ts`):**
  - `unlock()`, en este orden:
    1. Visibilidad: 404 antes de cualquier lógica de contraseña.
    2. En una tx: `INSERT … ON CONFLICT DO NOTHING` y después `SELECT … FOR UPDATE`.
    3. Si está bloqueado: 429 `NOTA_UNLOCK_THROTTLED`.
    4. Se consume el intento y se hace commit.
    5. `bcrypt.compare` fuera de la tx.
    6. Correcta: contador a 0, detalle completo y `unlockToken`.
  - Crear: hashea la contraseña antes de subir los archivos o abrir la tx.
  - `edit()`: editar contenido de una secreta exige prueba. Re-clavar o quitar el secreto no la exige (S-09). Contraseña nueva o secreto quitado → se borran los contadores de la nota en la misma tx. Si hay contraseña nueva, el autor recibe la nota desbloqueada con una prueba nueva.
  - `setSecret()`: sólo el autor, sin la contraseña anterior.
  - Responder, reaccionar y abrir adjuntos exigen prueba. El adjunto se chequea antes de MinIO, y el de una secreta sale con `Cache-Control: private, no-store`.
- **Rutas:**
  - Nuevas: `POST /notas/:id/unlock` (`{password}`) y `POST /notas/:id/secret`, las dos con `@FunctionGuard('ver-notas','read')`.
  - El header `x-nota-unlock` se lee en detail, history, seen, ack, replies, reactions, PATCH y `/nota-adjuntos/:id`.
  - Límite multipart `fields` de 10 → 12.

### Frontend (ventago-app)
- **`apiConnector`:** cambios sólo aditivos. Parámetro opcional de headers en `patch`, `sendFile` y `getBlob`; `getWithHeaders` nuevo; `silenceErrorToast` en `post`.
- **`notas.api.ts`:**
  - `unlockNota` manda la contraseña en el cuerpo.
  - `setNotaSecret`, `fetchUnlockedNota`, `fetchNotaHistoryUnlocked` nuevos.
  - Toda acción manda la prueba sólo por header.
- **`notas-logic.ts` (puro, testeable):** `validateSecretForm`, `secretCreateFields` / `secretEditFields`, `unlockHeaders`, `unlockErrorMessage`, `isUnlockLost`, `shownDetail`, `unlockStateFrom`.
- **Compose:** switch «🔒 Nota secreta» + contraseña + confirmación.
  - Al editar, vacía = conservar la actual; apagar el switch = quitar el secreto.
  - El formulario de edición se llena con el detalle desbloqueado que le pasa el panel.
- **Detalle:**
  - Vista bloqueada: título, remitente, destino, importancia, fecha y 🔒, con un campo de contraseña.
  - El desbloqueo vive sólo en `useState` del panel. Se borra al cambiar de nota y muere al desmontar. Nunca pasa por SWR, localStorage ni la URL.
  - Botón «🔒 Bloquear».
  - «Vista» se marca sólo después de desbloquear.
  - Si la prueba vence o la contraseña cambia, vuelve a pedirla.
  - El historial de una secreta se pide a mano con la prueba (no por SWR).
  - El autor tiene «¿Olvidaste la contraseña? Cambiarla o quitar el secreto».
- **Adjuntos:** blob autenticado con la prueba en header. El `blob:` URL se revoca al desmontar.
- **Lista:** 🔒 antes del título, y un aviso en lugar del excerpt.

## Commits

| Repo | SHA | Mensaje |
|---|---|---|
| api-ventago | `b42a6f71` | feat(96-11): schema y modelos de nota secreta |
| api-ventago | `3c400d6b` | feat(96-11): reglas puras de nota secreta |
| api-ventago | `8cbb1d6d` | feat(96-11): gate de nota secreta en servidor |
| ventago-app | `adb20548` | feat(96-11): cliente y lógica de nota secreta |
| ventago-app | `5983a987` | feat(96-11): UI de nota secreta |

Ninguno fue pusheado. Antes de pushear hay que aplicar la migración en 5434 (ver abajo); si no, toda consulta de Notas da 500.

## Tests

| Suite | Resultado |
|---|---|
| api `jest src/app/notas + migration-conventions` | **7 suites / 256 tests pasan** (notas 247 + convenciones 9) |
| ↳ `notas-secret.spec.ts` (nuevo, servicios reales sobre modelos en memoria, bcrypt real) | 32 |
| ↳ `notas-rules.spec.ts` | 91 (+20 nuevos: búsqueda, contraseña, limitador, prueba firmada) |
| ↳ `notas-models.spec.ts` | 8 (+2: columnas nuevas; `toJSON` sin `secretHash`) |
| app `jest notas-logic + notas-api-secret` | **2 suites / 50 tests pasan** (+17 nuevos) |
| api `tsc --noEmit`, `eslint src/app/notas --max-warnings=0` | 0 / 0 |
| app `tsc --noEmit`, `eslint` de los archivos tocados | 0 / 0 |

Qué cubren los requisitos pedidos (todos en `notas-secret.spec.ts`, salvo lo marcado):
- **Detalle bloqueado:** oculta cuerpo, adjuntos, respuestas y reacciones, y ni siquiera consulta esos modelos. El historial sin prueba da 403.
- **Contraseña incorrecta:** 403 `NOTA_WRONG_PASSWORD` y el contador pasa a 1. La reserva se hace con `lock: UPDATE` dentro de la tx.
- **5 fallos:** el siguiente intento da 429 hasta `locked_until`, aunque la contraseña sea correcta, y bcrypt no llega a correr. Un segundo antes del vencimiento sigue en 429. Al vencer, la correcta entra y el contador vuelve a 0.
- **Contraseña correcta:** devuelve el detalle completo y la prueba, y resetea el contador.
- **Sin excepciones:** el autor y un moderador (`notas-enviar-todos`) también necesitan la contraseña.
- **Visibilidad primero:** con una secreta invisible, unlock, detail, history, seen, ack, reply y react dan 404. bcrypt y el contador no se tocan.
- **Búsqueda:** un término que sólo aparece en el cuerpo de una secreta no hace match. Probado en reglas y en el WHERE que llega al modelo.
- **Acciones sin prueba rechazadas:** adjunto (sin tocar MinIO), responder (sin subir ni crear), reaccionar, Entendido y vista (sin escribir `nota_reads`). Una prueba firmada para otra nota no abre ésta.
- **`secret_hash` nunca sale:** `assertNoSecretHash` recorre recursivamente la respuesta serializada de detalle (bloqueado y desbloqueado), unlock, lista, crear, editar y setSecret. `toJSON` se prueba aparte en el spec de modelos.
- **El autor re-clava editando sin la contraseña anterior:** los contadores de todos los usuarios de la nota quedan en 0, la prueba vieja deja de abrir y la contraseña nueva funciona. `setSecret` también; otro usuario recibe 403.
- **Front:** la contraseña va en el cuerpo del POST. Las 8 llamadas con prueba la mandan sólo por el header `x-nota-unlock` y nunca en el path ni en los query params (`notas-api-secret.spec.ts`). El desbloqueo de otra nota no se reutiliza (`shownDetail`).

**Defecto real que atrapó el spec:** `edit()` comparaba el hash nuevo contra `n.secretHash` (la fila leída antes del lock) **después** de `locked.update()`. Se corrigió: el hash previo se toma de la fila bloqueada **antes** del update. Ese test falló antes del fix.

## Resultados de mutación (todas muertas)

Cada mutante se aplicó sobre el archivo real, se corrió jest y se restauró el original.

| # | Mutante | Resultado |
|---|---|---|
| M1 | Gate de contenido apagado (`const locked = false && …` en `buildDetail`) | **8 fallan** |
| M2 | `assertUnlocked` sin efecto (`if (false && …)`) | **9 fallan** |
| M3 | Sin chequeo de 429 (`isUnlockLocked(null, now)`) | **2 fallan** ¹ |
| M4 | Limitador corrido en uno (`>=` → `>`) | **4 fallan** |
| M5 | El intento no se persiste (`row.update(next)` eliminado) | **5 fallan** |
| M6 | Búsqueda sin la guarda `{ isSecret: false }` | **3 fallan** |
| M7 | La lista sin blanquear el excerpt | **1 falla** |
| A1 | Front: la prueba del adjunto en query params | **1 falla** |
| A2 | Front: la prueba del detalle en el path | **1 falla** |
| A3 | Front: `shownDetail` reutiliza el desbloqueo de otra nota | **1 falla** |
| — | Control de la migración: sin `NOT VALID` en el CHECK | el spec de convenciones **falla** |

¹ La primera forma de M3 (`if (false && …)`) rompía la compilación de una suite. Jest reportó «124 passed, 124 total», que parece «sobrevivió» pero no lo es. Se rehízo con una forma que compila y murió.

## Migración

Archivo: `api-ventago/migrations/2026-09-28-c-notas-secretas.sql`

**Cómo correrla:** SIN `--single-transaction`. El archivo abre su propio `BEGIN…COMMIT` y el `VALIDATE` tiene que quedar fuera de esa transacción (regla W4).

```bash
# local (YA APLICADA, 2 corridas: idempotente)
psql -p 5432 -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/2026-09-28-c-notas-secretas.sql
# producción (PENDIENTE — requiere aprobación)
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/2026-09-28-c-notas-secretas.sql
```

SQL exacto (sin los comentarios de cabecera):

```sql
SET lock_timeout = '5s';

BEGIN;

ALTER TABLE notas ADD COLUMN IF NOT EXISTS is_secret BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE notas ADD COLUMN IF NOT EXISTS secret_hash VARCHAR(100);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'notas_secret_hash_ck' AND conrelid = 'notas'::regclass
  ) THEN
    ALTER TABLE notas ADD CONSTRAINT notas_secret_hash_ck CHECK ((is_secret = false) OR (secret_hash IS NOT NULL)) NOT VALID;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS nota_unlock_attempts (
  id           SERIAL PRIMARY KEY,
  store_id     INTEGER     NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  nota_id      INTEGER     NOT NULL,
  user_id      INTEGER     NOT NULL REFERENCES users(id),
  failed_count INTEGER     NOT NULL DEFAULT 0 CHECK (failed_count >= 0),
  locked_until TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT nota_unlock_attempts_nota_user_uq UNIQUE (nota_id, user_id),
  CONSTRAINT nota_unlock_attempts_nota_store_fk
    FOREIGN KEY (nota_id, store_id) REFERENCES notas (id, store_id) ON DELETE CASCADE
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE nota_unlock_attempts OWNER TO coolsistema;
    ALTER SEQUENCE nota_unlock_attempts_id_seq OWNER TO coolsistema;
  END IF;
END $$;

COMMIT;

ALTER TABLE notas VALIDATE CONSTRAINT notas_secret_hash_ck;

DO $$  -- verificación: 2 columnas, CHECK validado, tabla presente; si no, RAISE EXCEPTION
...
END $$;
```

### Impacto esperado en producción (5434)

Estado leído con un SELECT de sólo lectura el 2026-09-28: `notas` = **0 filas**, las columnas `is_secret`/`secret_hash` **no existen**, `nota_unlock_attempts` **no existe** y el rol `coolsistema` **existe**.

| Sentencia | Efecto | Filas |
|---|---|---|
| `ADD COLUMN is_secret … DEFAULT false` | Sólo catálogo en PG18 (default constante: no reescribe la tabla) | 0 existentes modificadas (cualquier fila existente leería `false` por default) |
| `ADD COLUMN secret_hash` | Nullable, sólo catálogo | 0 |
| `ADD CONSTRAINT … NOT VALID` | Sin escaneo | 0 |
| `CREATE TABLE nota_unlock_attempts` + owner coolsistema (tabla y secuencia) | Tabla nueva, vacía | 0 |
| `VALIDATE CONSTRAINT` (fuera de la tx, SHARE UPDATE EXCLUSIVE) | Escanea `notas` (0 filas): instantáneo | 0 |

- Locks: `ACCESS EXCLUSIVE` breve sobre `notas` para los `ADD COLUMN` y el `ADD CONSTRAINT`, con `lock_timeout = 5s`. `notas` no tiene tráfico todavía (0 filas).
- No toca tablas de permisos, así que no necesita la marca `perm-cache`.
- **Orden obligatorio:** aplicar en 5434 **antes** de hacer push de api-ventago. El modelo `Nota` ahora selecciona `is_secret`/`secret_hash`, y sin esas columnas toda consulta de Notas da 500.
- **Qué deploy va primero:** API y app deben salir juntos. Con el API nuevo y la app vieja no se rompe nada: la app vieja ignora `locked`/`isSecret` y simplemente no puede crear secretas. Con la app nueva y el API viejo, el switch se muestra pero el servidor ignora `isSecret` y la nota se guarda **sin secreto**. Por eso el API tiene que salir primero o a la vez.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Comparación del hash previo en `edit()`**
- **Found during:** tests de 96-11 (re-clavar editando).
- **Issue:** el reset de contadores dependía de `n.secretHash` leído fuera del lock y comparado después del `update`.
- **Fix:** se toma `prevHash` de la fila bloqueada antes del update.
- **Commit:** `api-ventago@8cbb1d6d`

**2. [Rule 2 - Correctitud] 403 en lugar de 401 para contraseña incorrecta y prueba faltante**
- El interceptor de `api.service.ts` desloguea ante cualquier 401. Por eso se usa 403 con un `code` que el front distingue.

**3. [Rule 2 - Seguridad] `Cache-Control: private, no-store` para adjuntos de secretas**
- La respuesta depende de un header que la caché del navegador no usa como clave. Los adjuntos no secretos conservan `max-age=300`.

**4. [Rule 3] Límite multipart `fields` de 10 → 12**
- Crear una secreta suma dos campos (`isSecret`, `secretPassword`).

### Decisiones de diseño dentro de lo abierto por el spec
- **S-06, «el mecanismo más simple»:** token HMAC firmado en el header `x-nota-unlock`. Un token en memoria no sirve con 4 workers.
- **S-09:** además del PATCH, se agregó `POST /notas/:id/secret`. Desde la vista bloqueada el autor no ve el cuerpo, y un PATCH exige el cuerpo completo.

## Pendiente (fuera de alcance de este plan)
- Aplicar la migración en 5434 (requiere aprobación), después push de los dos submódulos, mover los punteros del repo raíz y verificar el build de Jenkins.
- Verificación en navegador (cmux, build de producción).
- La revisión CODEX (`codex-review-after-commit`) no se lanzó en esta sesión. Correrla sobre los 5 commits antes del push.

## Known Stubs
Ninguno.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: new-endpoint | api-ventago/src/app/notas/notas.controller.ts | `POST /notas/:id/unlock` (adivinanza de contraseña): limitado a 5/15 min por (usuario, nota) en DB. Un atacante con muchos usuarios multiplica los intentos. Aceptado por S-07, que define el límite por (userId, notaId). |
| threat_flag: new-endpoint | api-ventago/src/app/notas/notas.controller.ts | `POST /notas/:id/secret`: re-clavar o quitar sin la contraseña anterior. Sólo el autor, bajo lock, con 404 primero. |

## Self-Check: PASSED
- Archivos creados: los 4 existen (la migración, `nota-unlock-attempt.model.ts`, `notas-secret.spec.ts`, `notas-api-secret.spec.ts`).
- Commits: `b42a6f71`, `3c400d6b`, `8cbb1d6d` (api-ventago) y `adb20548`, `5983a987` (ventago-app), presentes en `git log`.

## CODEX 96-11

Gap-fix sobre los 7 hallazgos de la revisión manual (`.team/reviews/manual-96-11/api.patch`
y `app.patch`). Un commit por hallazgo (2 y 3 comparten commit — los dos tocan el mismo
chequeo de prueba dentro de `edit()`). Ningún push — igual que el resto de este plan.

| # | Sev | Hallazgo | Commit | Test (mutación) |
|---|-----|----------|--------|------------------|
| 1 | P1 | `unlock()`: la contraseña se comparaba con bcrypt contra `n.secretHash` leído ANTES de la tx del limitador y ANTES de bcrypt (que no toma ningún lock sobre la fila de la nota). Si el autor re-clavaba/quitaba el secreto mientras el pedido estaba en vuelo, una contraseña correcta contra el hash VIEJO igual entregaba contenido y una prueba firmada sobre ese hash desactualizado. Fix: tras bcrypt, relee la fila (`findByPk`, sin lock) y exige `isSecret && secretHash` idénticos al hash recién comparado; si no, 403 `NOTA_WRONG_PASSWORD` sin contenido. | `api-ventago@38a98fb0` | `notas-secret.spec.ts` → *"contraseña correcta contra un hash YA ROTADO (carrera con un re-clavado concurrente) → 403, no desbloquea"*. Mutación: revertir el re-chequeo (usar `n` en vez de `fresh`) hace fallar el test. |
| 2 | P2 | `edit()`: un PATCH que además traía contraseña nueva o `isSecret:false` se dejaba pasar SIN prueba de desbloqueo (se trataba como "el camino del olvido", S-09) — pero el mismo endpoint reescribe título/cuerpo. Eso permitía sobreescribir el contenido de una secreta sin haber demostrado conocer la contraseña vigente, con sólo pedir un reseteo de paso. Fix: `edit()` en una secreta SIEMPRE exige la prueba, cambie o no la contraseña; el olvido real (autor sin la contraseña, que por eso no puede ver el cuerpo) sólo se resuelve con `setSecret()`, que no toca contenido. | `api-ventago@cfc9e7a0` | `notas-secret.spec.ts` → *"editar CONTENIDO + contraseña nueva en el mismo PATCH sin prueba → 403"* (nuevo) y *"CON prueba, el autor cambia contenido Y contraseña…"* (reescrito — antes probaba el camino sin prueba, ahora prueba que con prueba sigue funcionando). Mutación: restaurar el bypass `rekeysOrClears` hace fallar el primero. |
| 3 | P2 | `edit()`: la prueba de desbloqueo se verificaba contra `n` (leída ANTES de abrir la tx, sin lock) — no contra la fila ya bajo `FOR UPDATE`. Si el hash cambiaba entre esa lectura y el lock, una prueba atada al hash VIEJO podía pasar el chequeo. Fix: se repite la verificación DENTRO de la tx, contra `locked`. | `api-ventago@cfc9e7a0` (mismo commit que 2 — mismo bloque de código) | `notas-secret.spec.ts` → *"la prueba se valida contra el hash de la fila LOCKEADA (bajo lock), no contra la lectura previa a la tx"*. Mutación: volver a chequear contra `n` en vez de `locked` hace fallar el test. |
| 4 | P3 | Lista y detalle de una secreta BLOQUEADA exponían `hasNewReplies` aunque el gate ya ocultara excerpt/adjuntos/respuestas/reacciones — "hay una respuesta nueva sin ver" es señal de contenido igual que esas. Fix: se fuerza a `false` cuando `locked`/`secret`, en ambas superficies. | `api-ventago@ab04e238` | `notas-secret.spec.ts` → describe *"hasNewReplies no se expone bloqueada (finding 4)"* (lista + detalle, con sus controles desbloqueados). Mutación: quitar cualquiera de los dos gates hace fallar el test correspondiente. |
| 5 | P1 | `NotaDetailPane.tsx`: las respuestas async de `unlockNota`/`setNotaSecret` (vía `SecretResetDialog`) podían aplicarse sobre una nota distinta de la vigente — el panel se REUSA al cambiar de nota (no se remonta). `handleUnlock` ya comparaba `currentIdRef` pero no `res.id`; `handleSecretReset` no comparaba nada. Fix: `isUnlockResponseForCurrentNota({ requestedId, currentId, res })` (pura) exige que las tres coincidan antes de aplicar; `unlockStateFrom` suma el mismo chequeo de `res.id` como última defensa. | `ventago-app@4e3c6eba` | `notas-logic.spec.ts` → *"unlockStateFrom descarta si res.id no coincide…"* + describe *"isUnlockResponseForCurrentNota…"* (4 casos). Mutación: sacar el chequeo de `res.id` en `unlockStateFrom`, y simplificar `isUnlockResponseForCurrentNota` a sólo `currentId` — ambos mutantes mueren. |
| 6 | P2 | `NotasView.tsx`: si `selectedId` cambiaba (deep link, socket) mientras el editor de OTRA nota seguía abierto, `editId`/`editSeed` quedaban vivos — el editor seguía mostrando contenido desbloqueado de una nota que ya no es la seleccionada. Fix: el efecto de `selectedId` también descarta `editSeed` si es de otra nota (mismo patrón que `paneSeed`) y cierra el editor (`shouldCloseStaleEditor`, pura) si `editId` no coincide con la selección vigente. | `ventago-app@75f7cdf3` | `notas-logic.spec.ts` → describe *"shouldCloseStaleEditor…"* (3 casos). Mutación: `shouldCloseStaleEditor` devolviendo siempre `false` hace fallar el test. |
| 7 | P2 | `NotaDetailPane.tsx`: el campo de contraseña de la vista bloqueada era `useState('')` sin atar a la nota — el efecto que lo resetea corre DESPUÉS del primer render con el `notaId` nuevo (el componente se reusa), así que ese primer render podía mostrar lo tipeado para la nota anterior. Fix: se ata como `{ notaId, value }` (`emptyPwdState`/`pwdValueFor`, puras); el valor mostrado/enviable es `''` si el estado quedó de otra nota. | `ventago-app@3b04aefd` | `notas-logic.spec.ts` → describe *"pwdValueFor / emptyPwdState…"* (3 casos). Mutación: `pwdValueFor` ignorando el id hace fallar el test. |

**Compose/edit y `setSecret()` (aclaración pedida junto con el fix 2):** el flujo de UI
YA enruta el reseteo de contraseña sin prueba exclusivamente por `SecretResetDialog` →
`setNotaSecret()` — no por `ComposeNotaDialog`/`editNota()`. El botón «Editar» (que sí usa
`editNota()`, ahora con prueba obligatoria) sólo se muestra cuando `can.edit` es `true`, y
eso sólo ocurre desbloqueada — así que el compose/edit form nunca necesitó tocarse: siempre
manda el `unlockToken` vigente en el header cuando edita una secreta.

**Checks:** `tsc --noEmit`, `eslint --max-warnings=0` y jest en 0 en ambos repos tras cada
commit (ver comandos en `<environment_notes>` del prompt de este gap-fix). Suites afectadas:
api `src/app/notas` (254 tests) + `migration-conventions` (9); app `notas-logic.spec.ts` +
`notas-api-secret.spec.ts` (61 tests).

**Commits (orden, sin push):**
- `api-ventago@38a98fb0` — finding 1
- `api-ventago@cfc9e7a0` — findings 2 y 3
- `api-ventago@ab04e238` — finding 4
- `ventago-app@4e3c6eba` — finding 5
- `ventago-app@3b04aefd` — finding 7
- `ventago-app@75f7cdf3` — finding 6
