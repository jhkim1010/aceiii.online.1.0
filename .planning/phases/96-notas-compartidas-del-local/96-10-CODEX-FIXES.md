# Phase 96 — CODEX review fixes (gap-fix, sin PLAN)

Correcciones a los hallazgos de `.team/reviews/auto-api-ventago-f1a3cf93.md` (líneas
8359-8432) sobre el módulo Notas, previas al deploy de producción de `96-10-PLAN.md`
(esa migración de permisos/tablas todavía NO está aplicada en prod — requiere
re-aprobación de este SQL modificado antes de push, por eso este trabajo se hizo sin
tocar producción ni hacer `git push`).

Cada hallazgo → commit → test que lo prueba.

---

## [P1] Migración de permisos falla a mitad de camino bajo autocommit

**Hallazgo:** `2026-09-28-b-notas-permisos.sql:34` — la tabla temporal `ON COMMIT DROP`
se dropea apenas termina su propio `CREATE TABLE AS` si psql corre en autocommit (sin
`--single-transaction`). El `SELECT` del bloque de verificación (sección 6) fallaba
después, pero los `INSERT` de las secciones 1-5 ya habían quedado committeados sueltos
— estado parcial.

**Fix:** todo el cuerpo del archivo (después de los comentarios de cabecera) va dentro
de un `BEGIN;` … `COMMIT;` explícito, con `SET LOCAL lock_timeout` adentro. Ahora un
fallo en el DO de verificación revierte TODO el archivo sin importar cómo se invoque
psql.

**Commit:** `api-ventago@528ad8b9` — fix(96-10): wrap notas-permisos migration in
explicit BEGIN/COMMIT

**Prueba:** no es una prueba jest — es la migración misma. Se re-aplicó localmente
(5432) dos veces después del fix: la segunda corrida pasa el guard de "no revocar
concesiones" (115 concesiones sin cambios) e imprime `p96 OK`. Más abajo (hallazgo
P2 de tablas) se volvió a probar una TERCERA vez tras recrear las 7 tablas de Notas,
con el mismo resultado.

---

## [P1] `create()` puede duplicar la nota si algo post-commit falla

**Hallazgo:** `notas-command.service.ts:331` — después de `tx.commit()`,
`Users.findByPk()` (nombre del remitente) y `query.detail()` podían seguir tirando
(pool agotado, error transitorio). Sin `Idempotency-Key`, un cliente que ve la request
"fallar" reintenta el POST y duplica la nota + adjuntos, aunque el primer `create()` ya
había committeado con éxito ("커밋 후 = 성공", Phase 64).

**Fix:**
- `Users.findByPk()` post-commit envuelto en try/catch — si falla, se loguea y
  `senderName` queda en `''` (no cambia la respuesta).
- `query.detail()` post-commit envuelto en try/catch — si falla, se arma la respuesta
  con `buildFallbackDetail()`, usando SÓLO datos ya guardados en la transacción (no
  vuelve a tocar la DB).
- De paso (mismo método): `sequelize.transaction()` se movió DENTRO del try que
  compensa los adjuntos subidos a MinIO (hallazgo P2, ver abajo).

**Commit:** `api-ventago@472b6112` — fix(96-10): create() never turns a post-commit
failure into a duplicate nota

**Tests:** `notas-command.service.spec.ts` → describe `create post-commit`:
- `[CODEX P1] si query.detail() rechaza DESPUÉS del commit, igual resuelve con la nota
  ya creada (create llamado UNA sola vez)`
- `[CODEX P1] si Users.findByPk (senderRow) rechaza DESPUÉS del commit, igual resuelve
  con la nota ya creada`

**Mutation-check:** se quitó temporalmente el try/catch de `query.detail()` (volviendo
a `return await this.query.detail(user, nota.id);` sin protección) → el primer test de
arriba pasó de PASS a FAIL (el rechazo se propagó). Se restauró el fix y volvió a PASS.

---

## [P1] `reply()` puede duplicar la respuesta si algo post-commit falla

**Hallazgo:** `notas-command.service.ts:576` — mismo patrón que create(): después del
commit, `Users.findByPk()` (nombre) y `recipientIdsOf()` (usado sólo para el emit)
podían tirar y convertir una respuesta ya guardada en un error HTTP, con el mismo
riesgo de duplicado por reintento.

**Fix:** `userRow` lookup y (`recipientIdsOf()` + `emitForAudience()`) envueltos cada
uno en su propio try/catch. Un fallo se loguea; `userName` cae a `''`; el emit
simplemente no se dispara. La respuesta (que sólo depende de datos ya guardados en la
tx: `reply.id`, `text`, `attachment`) siempre se devuelve.

**Commit:** `api-ventago@2528ffd5` — fix(96-10): reply() never duplicates on
post-commit failure, returns real attachment id (mismo commit que el hallazgo P2 de
abajo — comparten método y no tenía sentido partirlos en más commits sin dejar el
archivo en un estado intermedio no compilable)

**Tests:** `notas-command.service.spec.ts` → describe `reply`:
- `[CODEX P1] si Users.findByPk (userName) rechaza DESPUÉS del commit, igual resuelve
  con la respuesta ya creada`
- `[CODEX P1] si recipientIdsOf() (usado sólo para el emit) rechaza DESPUÉS del commit,
  igual resuelve con la respuesta ya creada`

**Mutation-check:** se revirtió temporalmente el bloque a la versión sin try/catch
(`userRow`/`emitForAudience` sin protección) → ambos tests de arriba pasaron a FAIL con
el error inyectado. Se restauró el fix y volvió a PASS (47/47 en el archivo).

---

## [P2] `uploadAll()` antes de `sequelize.transaction()`, pero la adquisición de la tx
quedaba fuera del try que compensa

**Hallazgo:** `notas-command.service.ts:270` y `520-522` — si `sequelize.transaction()`
rechazaba (pool agotado, DB caída), el archivo ya subido a MinIO quedaba huérfano para
siempre porque el catch que compensa (`this.compensate(...)`) nunca se ejecutaba.

**Fix:** en `create()` y `reply()`, la variable `tx` pasó a declararse `Transaction |
undefined` y `tx = await this.sequelize.transaction()` se movió DENTRO del mismo try
que el resto de la escritura. Si la adquisición falla, `tx` queda `undefined`, el catch
detecta eso (`if (tx) await tx.rollback()`) y de todas formas corre `compensate()`.

**Commits:** `api-ventago@472b6112` (create) y `api-ventago@2528ffd5` (reply)

**Tests:**
- `notas-command.service.spec.ts` → `create post-commit` → `[CODEX P2] si
  sequelize.transaction() rechaza (pool agotado), compensa (removeFile) los archivos ya
  subidos a MinIO`
- `notas-command.service.spec.ts` → `reply` → `[CODEX P2] si sequelize.transaction()
  rechaza, compensa (removeFile) la foto ya subida`

Ambos tests también verifican que `tx.rollback` NO se llama en este camino (no hay
`tx` que rollbackear — antes del fix, esa rama ni siquiera se ejecutaba porque el
`await this.sequelize.transaction()` estaba fuera del try).

---

## [P2] El adjunto de una respuesta siempre devolvía `id: 0`

**Hallazgo:** `notas-command.service.ts:598` — la respuesta de `reply()` armaba el
adjunto con `id: 0` en vez del id real de `NotaAttachment.create()`. Un cliente que
pidiera `/nota-adjuntos/0` inmediatamente después de responder siempre recibía 404,
sin importar el adjunto real.

**Fix:** se conserva la instancia devuelta por `this.notaAttachmentModel.create(...)`
(`attachmentRow`) y se usa `attachmentRow?.id ?? 0` en la respuesta.

**Commit:** `api-ventago@2528ffd5`

**Test:** `notas-command.service.spec.ts` → `reply` → `[CODEX P5] el adjunto de la
respuesta devuelve el id REAL de NotaAttachment.create(), no 0` — mockea
`notaAttachmentModel.create` devolviendo `{ id: 777 }` y afirma
`res.attachment.id === 777`.

---

## [P2] El cap de 2.000 filas en `list()` escondía notas fijadas viejas sin aviso

**Hallazgo:** `notas-query.service.ts:229` — el scan inicial cortaba en
`NOTAS_SCAN_CAP` (2000) y todo el orden/paginación/total se hacía en memoria sobre esas
filas. Una nota fijada (pinned) más vieja que el cap desaparecía de la lista, del
`total` y de los conteos de no-leídas, con sólo un `logger.warn()` del lado del
servidor — el cliente no tenía forma de saber que el resultado estaba incompleto.

**Fix:**
- Cuando el scan pega el cap, una segunda consulta dirigida rescata las notas visibles
  que son `pinned=true` (audience='all') o que están en `v.myPins` (fijado personal del
  viewer), excluyendo los ids ya escaneados.
- La respuesta ahora incluye `truncated: boolean`.
- El cap dejó de ser sólo una constante de módulo — es un campo de instancia
  (`private readonly scanCap: number = NOTAS_SCAN_CAP`) para que el test pueda
  bajarlo sin crear miles de filas.
- `NotasListResponse` (backend Y frontend) ganó el campo `truncated`; en el frontend es
  opcional (`truncated?: boolean`) para no romper una respuesta SWR en caché de un
  deploy anterior.
- `NotasView.tsx` muestra un aviso chico ("Mostrando las notas más recientes — usá la
  búsqueda…") cuando `data?.truncated` es true.

**Commits:**
- `api-ventago@45ac4a54` — fix(96-10): list() rescues pinned notas older than the scan
  cap, flags truncation
- `ventago-app@a64924d8` — fix(96-10): surface Notas list truncation to the user

**Tests:** `notas-query.service.spec.ts` → describe `list truncation`:
- `cap alcanzado: una nota fijada más vieja que el cap SÍ aparece y truncated=true` —
  baja `scanCap` a 2, el scan devuelve 2 filas (pega el cap), una consulta de rescate
  devuelve una nota fijada de 2020, y el test verifica que aparece en `data`,
  `truncated===true`, y que la consulta de rescate excluye los ids ya escaneados
  (`Op.notIn`) y sólo pide fijadas (`Op.or` con `pinned:true`).
- `cap NO alcanzado (menos filas que el cap): truncated=false y no hay consulta de
  rescate` — con `scanCap=50` y 1 sola fila, verifica exactamente 3 llamadas a
  `notaModel.findAll` (scan + fullRows de página + `unreadSummary()`, que `list()` ya
  llama al final) — es decir, SIN una 4ta llamada de rescate.

**Mutation-check (RED antes del fix):** se copió el `notas-query.service.ts` de HEAD
(antes de este fix, vía `git show HEAD:...`) sobre el archivo y se corrió la suite: el
test suite ni siquiera compiló — `truncated` es requerido en `NotasListResponse` pero
la versión vieja no lo devuelve (`error TS2741`). Se restauró el fix y la suite volvió
a 177/177.

**Nota:** `unreadSummary()` (usado tanto standalone como al final de `list()`) tiene el
mismo patrón de cap sin rescate de fijadas — el hallazgo original lo menciona como
síntoma ("list/total/unread") pero el pedido concreto de esta tarea (pinned rescue +
flag `truncated`) es específico de `list()`. No se tocó para no ampliar el alcance sin
pedido explícito; queda como posible follow-up si se decide que también importa para
los conteos de no-leídas.

---

## [P2] Los hijos de `notas` no tenían invariante de tenant a nivel DB

**Hallazgo:** `2026-09-28-a-notas-tablas.sql:51` — cada tabla hija (`nota_recipients`,
`nota_reads`, `nota_replies`, `nota_reactions`, `nota_edit_history`,
`nota_attachments`) tenía `nota_id` y `store_id` como FKs INDEPENDIENTES. Nada impedía
una fila con `store_id`=tienda A y `nota_id`=una nota de la tienda B — `TenantGuard`
sólo filtra por `store_id` en la query, así que esa fila inconsistente se vería como
propia de la tienda A aunque en realidad cuelgue de una nota de otro tenant. Lo mismo
para `reply_id` en `nota_reactions`/`nota_attachments`: nada exigía que la respuesta
referenciada fuera de la misma nota.

**Fix:** (editado in-place en el archivo que crea las tablas — están vacías en
producción, no hay migración de alteración separada, siguiendo el propio criterio que
el archivo ya documentaba para este caso)
- `notas` gana `CONSTRAINT notas_id_store_uq UNIQUE (id, store_id)`.
- Cada hijo reemplaza sus 2 FKs independientes por
  `FOREIGN KEY (nota_id, store_id) REFERENCES notas (id, store_id) ON DELETE CASCADE`.
- `nota_replies` gana `CONSTRAINT nota_replies_id_nota_uq UNIQUE (id, nota_id)`.
- `nota_reactions.reply_id` y `nota_attachments.reply_id` ganan
  `FOREIGN KEY (reply_id, nota_id) REFERENCES nota_replies (id, nota_id) ON DELETE
  CASCADE` — con `reply_id` nullable, el MATCH SIMPLE por default de Postgres hace que
  la FK sólo se evalúe cuando `reply_id` no es NULL.

**Commit:** `api-ventago@0b2566bb` — fix(96-10): Notas child tables get composite FKs
enforcing tenant consistency

**Verificación (no es jest — es DDL):**
1. Confirmado que las 7 tablas estaban en 0 filas en local (5432) y en producción no
   aplicadas todavía.
2. `DROP TABLE ... CASCADE` de las 7 tablas en local, re-aplicado
   `2026-09-28-a-notas-tablas.sql` completo con `--single-transaction` → OK.
3. Re-aplicado `2026-09-28-b-notas-permisos.sql` (sin `--single-transaction`, la forma
   que causaba el hallazgo P1 original) → pasa el guard de segunda corrida, imprime
   `p96 OK` — prueba que el fix del hallazgo P1 y el de este hallazgo conviven.
4. Prueba manual de la FK compuesta padre-hijo: INSERT de `nota_recipients` con
   `store_id=6` pero `nota_id` de una nota de `store_id=3` → **rechazado**
   (`nota_recipients_nota_store_fk`, `Key (nota_id, store_id)=(2, 6) is not present`).
5. Prueba manual de la FK compuesta reply-nota: INSERT de `nota_reactions` sobre una
   nota de la tienda 6 con `reply_id` de una respuesta que en realidad pertenece a una
   nota de la tienda 3 → **rechazado** (`nota_reactions_reply_nota_fk`,
   `Key (reply_id, nota_id)=(2, 6) is not present`).
6. Cadena válida nota → reply → reacción → adjunto → inserta sin error.
7. `migration-conventions.spec.ts` sigue en verde (tablas nuevas exentas de las reglas
   W4 de `CONCURRENTLY`/`lock_timeout`).
8. Todo lo anterior corrido dentro de `BEGIN; ... ROLLBACK;` — el estado final de la DB
   local quedó igual que al principio (7 tablas en 0 filas), salvo por las tablas
   recreadas con las FKs nuevas, que también están en 0 filas.

**Regenerado:** `.planning/intel/db-schema-tables.md` y `.planning/intel/db-schema-fks.md`
vía `./.planning/intel/db-schema.regen.sh` — commit `root@32026cc`.

**Caveat documentado en ese commit:** el generador de `db-schema-fks.md` no empareja
`key_column_usage`/`constraint_column_usage` por posición ordinal, así que para FKs
compuestas imprime un producto cruzado de columnas (p. ej. una fila que dice
`nota_recipients.nota_id -> notas.store_id`, que no es una restricción real). Las
restricciones reales en la DB y en el archivo de migración son correctas — sólo ese
generador de documentación rotula mal las compuestas. No se corrigió el generador
(fuera de alcance de esta tarea de gap-fix).

---

## [P3] Ediciones concurrentes podían perder el historial real

**Hallazgo:** `notas-command.service.ts:389` — `edit()` leía la nota (`n`) ANTES de
abrir la transacción, sin lock. Si dos ediciones concurrentes leían el mismo
`n.title/body`, ambas escribían el mismo snapshot de historial y la segunda UPDATE
pisaba a la primera sin dejar rastro real del estado intermedio.

**Fix:** dentro de la transacción, se vuelve a leer la nota con
`this.notaModel.findByPk(id, { transaction: tx, lock: tx.LOCK.UPDATE })`. El snapshot
de `NotaEditHistory` y el `.update()` final usan esa fila LOCKEADA (`locked`), no `n`.
Si la fila desapareció entre el chequeo de visibilidad y el lock, se lanza
`NotFoundException` y se hace rollback.

**Commit:** `api-ventago@ef8910d7` — fix(96-10): edit() re-reads the nota FOR UPDATE
inside the tx before snapshotting history

**Tests:** `notas-command.service.spec.ts` → describe `edit`:
- `[CODEX P3] vuelve a leer la nota DENTRO de la tx con lock FOR UPDATE, usando ese
  snapshot (no el leído antes de abrir la tx)` — usa dos instancias mock DISTINTAS
  (`stale` para `findVisibleOrFail`, `locked` para `notaModel.findByPk`) con valores de
  campo diferentes, y verifica que el snapshot de historial sale de `locked`, que
  `stale.update` NUNCA se llama, y que `notaModel.findByPk` se llamó con
  `{ transaction: tx, lock: tx.LOCK.UPDATE }`.
- `nota bloqueada desaparece entre el chequeo de visibilidad y el lock →
  NotFoundException, rollback, sin historial`.

---

## Resumen de comandos de verificación (todos en verde al final)

```bash
cd api-ventago
env -u NODE_OPTIONS npx tsc --noEmit -p tsconfig.json          # 0 errores
env -u NODE_OPTIONS npx jest src/app/notas \
  src/common/migrations/migration-conventions.spec.ts \
  --maxWorkers=1                                                # 186/186 passed
npx eslint src/app/notas/notas-command.service.ts \
  src/app/notas/notas-command.service.spec.ts \
  src/app/notas/notas-query.service.ts \
  src/app/notas/notas-query.service.spec.ts \
  src/app/notas/notas.types.ts --max-warnings=0                 # 0 problemas

cd ../ventago-app
env -u NODE_OPTIONS npx tsc --noEmit                             # 0 errores
npx eslint src/views/notas/notas.types.ts \
  src/views/notas/NotasView.tsx --max-warnings=0                 # 0 problemas
```

## Commits (orden cronológico)

| # | Hallazgo(s) | Repo | SHA | Mensaje |
|---|---|---|---|---|
| 1 | P1 migración autocommit | api-ventago | `528ad8b9` | wrap notas-permisos migration in explicit BEGIN/COMMIT |
| 2 | P3 edit() sin lock | api-ventago | `ef8910d7` | edit() re-reads the nota FOR UPDATE inside the tx |
| 3 | P1 create() duplica + P2 tx fuera del try | api-ventago | `472b6112` | create() never turns a post-commit failure into a duplicate nota |
| 4 | P1 reply() duplica + P2 tx fuera del try + P2 attachment id=0 | api-ventago | `2528ffd5` | reply() never duplicates on post-commit failure, returns real attachment id |
| 5 | P2 cap de 2000 esconde fijadas | api-ventago | `45ac4a54` | list() rescues pinned notas older than the scan cap, flags truncation |
| 5b | P2 (frontend) | ventago-app | `a64924d8` | surface Notas list truncation to the user |
| 6 | P2 FKs sin invariante de tenant | api-ventago | `0b2566bb` | Notas child tables get composite FKs enforcing tenant consistency |
| 7 | (docs) regen intel | root | `32026cc` | regenerate db-schema intel after Notas composite FK fix |

No se hizo `git push` en ningún repo (regla de la tarea). La migración de producción
(`96-10-PLAN.md`) sigue pendiente de aprobación con este SQL ya corregido.
