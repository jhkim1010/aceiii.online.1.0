# Phase 96 — CODEX review fixes (gap-fix, sin PLAN)

Correcciones a los hallazgos de `.team/reviews/auto-api-ventago-f1a3cf93.md` (líneas
8359-8432) sobre el módulo Notas, previas al deploy de producción de `96-10-PLAN.md`
(esa migración de permisos/tablas todavía NO está aplicada en prod — requiere
re-aprobación de este SQL modificado antes de push, por eso este trabajo se hizo sin
tocar producción ni hacer `git push`).

Cada hallazgo → commit → test que lo prueba.

**Este documento se actualizó dos veces.** El hook `codex-review-after-commit.sh`
(automático, en background, CLAUDE.md § "검증은 자동으로 돈다") revisó cada commit de
la primera pasada y encontró problemas nuevos EN el código recién escrito — no en el
código original. La sección «Segunda pasada» de abajo documenta esos hallazgos y sus
fixes. Si estás leyendo esto por primera vez, las secciones 1-8 son la pasada inicial;
la tabla de commits al final tiene el estado final real (algunos SHA de la tabla
original quedaron superados por commits posteriores en el mismo archivo).

**Sobre los gitlinks de `api-ventago`/`ventago-app` en los commits de este repo raíz:**
un CODEX auto-review del commit raíz `eb3df1e` marcó como [P1] que el gitlink de
`api-ventago`/`ventago-app` sigue apuntando a un commit ANTERIOR a los fixes descritos
acá, y que por lo tanto un `clone` limpio de este repo raíz no trae los fixes. Eso es
correcto como observación pero es el comportamiento **pedido explícitamente para esta
tarea** (`<environment_notes>`: "Don't bump submodule pointers") — los commits reales
SÍ existen en el historial de cada submódulo (verificable con
`git -C api-ventago log --oneline` / `git -C ventago-app log --oneline`, SHAs listados
en la tabla de abajo), simplemente el puntero del repo raíz no se movió a propósito,
porque bumpear el gitlink sin haber hecho `git push` de los submódulos dejaría el
puntero raíz señalando a un commit que no existe en ningún remoto compartido. Cuando se
decida pushear esta rama, bumpear los 2 gitlinks al SHA final de cada submódulo es un
paso pendiente explícito (no un olvido).

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

# Segunda pasada — CODEX revisó los fixes de arriba y encontró más

El hook automático corrió sobre cada commit de la pasada 1. Esto es lo que encontró EN
el código nuevo (no en el original) y cómo se resolvió cada cosa.

## [P2] `edit()`: el re-chequeo de permiso no se repetía sobre la fila lockeada

**Hallazgo** (sobre `ef8910d7`): el fix de la pasada 1 agregó `FOR UPDATE` para el
snapshot de historial, pero `archivedAt`/`senderId` se seguían chequeando sólo contra
`n` (leída ANTES de la tx, sin lock). Si otra request archivaba la nota (o cambiaba el
remitente) y comiteaba entre esa lectura y el lock, la edición se aplicaba igual contra
una nota que debería haber sido rechazada — el lock serializaba la ESCRITURA pero no el
PERMISO.

**Fix:** `locked.storeId`, `locked.archivedAt`, `locked.senderId` se re-validan contra
la fila lockeada antes de crear el historial o actualizar.

**Commit:** `api-ventago@0d891ec8`

**Tests:** 3 casos nuevos en `edit` — archivado entre chequeo y lock, remitente
cambiado entre chequeo y lock, `storeId` cruzado (defensa en profundidad). Los 3 usan
una instancia `locked` DISTINTA de `n` para probar que el chequeo real es sobre la fila
lockeada.

**Mutation-check:** se quitó el bloque de re-validación → los 3 tests nuevos fallaron
(la nota se resolvía en vez de rechazar); se restauró.

## [P2] `rollback()` fallido tapaba el error original e impedía compensar MinIO

**Hallazgo** (sobre `472b6112`/`2528ffd5`): si `tx.rollback()` TAMBIÉN rechazaba
(conexión caída), el catch dejaba que ese error de rollback reemplazara el error
original de escritura, Y nunca llegaba a `compensate()` — el archivo ya subido a MinIO
quedaba huérfano para siempre y además se perdía la causa real del fallo.

**Fix:** `rollback()` va en su propio try/catch (loguea si falla, no relanza);
`compensate()` corre siempre después, sin condicionarse al resultado del rollback; el
error que se relanza sigue siendo el original (`e`).

**Commits:** `api-ventago@0d891ec8` (create + reply)

**Tests:** "si tx.rollback() TAMBIÉN rechaza, igual compensa (removeFile) y relanza el
error ORIGINAL" en create y en reply.

## [P2] El fallback de `create()` calculaba vencimiento con UTC en vez del timezone real

**Hallazgo** (sobre `472b6112`): `buildFallbackDetail()` usaba
`now.toISOString().slice(0,10)` (día UTC) para `isExpired` y devolvía siempre
`DEFAULT_STORE_TZ`, en vez del timezone/hoy reales de la tienda que usa toda lectura
normal. De noche en Buenos Aires (UTC-3) esto podía marcar una nota recién creada como
vencida hasta 3 horas antes de tiempo.

**Fix:** en el catch de `query.detail()`, se intenta (best-effort)
`this.query.resolveViewer(user)` — la MISMA fuente que usa cualquier lectura normal —
para obtener `storeTimezone`/`today` reales; si eso TAMBIÉN falla, recién ahí cae al
UTC/`DEFAULT_STORE_TZ` como último recurso.

**Commit:** `api-ventago@0d891ec8`

**Tests:** "el fallback usa el storeTimezone REAL de resolveViewer()" y "si
query.detail() Y resolveViewer() rechazan, cae a DEFAULT_STORE_TZ".

## [P1] `tx.commit()` rechazando es un resultado AMBIGUO, no una prueba de fallo — riesgo residual conocido

**Hallazgo** (sobre `0d891ec8`, el fix de rollback/compensate de arriba): CODEX señaló,
correctamente, que el fix de rollback/compensate independiente tiene un problema más
profundo: si lo que rechaza es `tx.commit()` EN SÍ (p. ej. la conexión se cae justo
después de que Postgres ya completó el COMMIT), no hay forma de saber desde el cliente
si el commit tuvo éxito o no. El código de la pasada 1 corría `compensate()`
incondicionalmente en ese caso — si el commit en realidad había tenido éxito, eso
BORRABA el objeto de MinIO que una fila YA GUARDADA (nota_attachments) apuntaba,
dejando una referencia rota visible para el usuario. Eso es peor que el objeto huérfano
que el fix intentaba evitar.

**Fix parcial aplicado:** se separó el try/catch en dos — uno para todo lo ANTERIOR al
commit (ahí sí es seguro rollback+compensate, nada quedó durable) y uno SÓLO para
`tx.commit()`. Un rechazo de ese segundo bloque:
- se loguea con `logger.error` (ruidoso, no silencioso) y se re-lanza tal cual;
- NO compensa MinIO (evita el daño visible: fila comprometida apuntando a objeto
  borrado);
- NO intenta rollback (no aporta nada sobre una tx cuyo commit ya se envió).

**Lo que este fix parcial NO resuelve — decisión pendiente:** si el commit en realidad
FALLÓ (no sólo el ack se perdió), el cliente sigue sin Idempotency-Key para saber que
puede reintentar seguro, y un reintento en el caso "el commit sí tuvo éxito" duplicaría
la nota/respuesta. Arreglar esto del todo requiere la misma infraestructura que ya
existe para `sales` (CLAUDE.md: "Idempotency-Key header (opcional)") — una columna/tabla
de deduplicación por request, chequeada antes de escribir. Eso es un cambio de
arquitectura (nueva tabla o columna, migración, contrato de API) fuera del alcance de
un gap-fix — **queda pendiente de decisión del usuario**, no implementado acá.

**Commit:** `api-ventago@5c8f36fe`

**Tests:** "si tx.commit() en sí rechaza (resultado incierto), NO se compensa MinIO ni
se llama rollback" en create y en reply.

**Mutation-check:** se volvió a compensar incondicionalmente en el catch de commit() →
el test de create falló (removeFile llamado 1 vez en vez de 0); se restauró.

## [P3] `truncated=true` aunque hubiera EXACTAMENTE `scanCap` notas (ni una más)

**Hallazgo** (sobre `45ac4a54`): `rows.length === scanCap` no distingue "hay más de
scanCap" de "hay justo scanCap, no hay ni una más" — un store con exactamente 2000
notas visibles disparaba una advertencia de "lista incompleta" falsa y una consulta de
rescate de fijadas innecesaria.

**Fix:** el scan pide `scanCap + 1` filas; `truncated = scanned.length > scanCap`;
recién ahí se recorta a las primeras `scanCap` antes de seguir procesando.

**Commit:** `api-ventago@88f1fc84`

**Test:** "resultado con EXACTAMENTE scanCap notas (ni una más) → truncated=false, sin
consulta de rescate".

**Mutation-check:** se volvió a `limit: scanCap` / `rows.length === scanCap` → el test
nuevo falló (truncated=true en vez de false); se restauró.

## [P2] La consulta de rescate de fijadas no tenía límite propio

**Hallazgo** (sobre `45ac4a54`): la segunda consulta (fijadas fuera del scan principal)
no llevaba `limit` — un store con muchísimas fijadas viejas volvía a convertir esto en
el scan sin tope que `NOTAS_SCAN_CAP` existe para evitar, aunque la respuesta final
sólo muestre `pageSize` (≤50) filas.

**Fix:** la consulta de rescate también lleva `limit: scanCap`. Si esa consulta en sí
pega el cap, se loguea aparte (el `truncated` que ve el cliente ya es `true` en ese
caso, pero queda rastro de cuál de los dos scans se quedó corto).

**Commit:** `api-ventago@88f1fc84`

**Test:** la aserción de `limit` en la consulta de rescate del test de truncation.

## [P1] `CREATE TABLE IF NOT EXISTS` no aplica el fix en un entorno donde las tablas ya existían

**Hallazgo** (sobre `0b2566bb`): ese commit sólo editó las definiciones `CREATE TABLE`.
`CREATE TABLE IF NOT EXISTS` es un no-op TOTAL sobre una tabla existente — en cualquier
entorno donde las 7 tablas de Notas ya se hubieran creado con la versión ANTERIOR
(FKs simples), reaplicar el archivo editado terminaría "exitoso" sin agregar ni una
restricción nueva. El único entorno conocido con ese problema era el DB local de este
desarrollador (ya arreglado a mano con DROP+CREATE ANTES del commit `0b2566bb`, ver más
abajo), pero cualquier otro clon que ya hubiera corrido la versión vieja tendría el
mismo hueco silencioso.

**Fix:** bloque `DO $$ ... $$` de actualización in-place después de los CREATE
TABLE/INDEX: por cada tabla hija, dropea la FK simple auto-nombrada vieja
(`<tabla>_<columna>_fkey`) SI EXISTE, y agrega la FK compuesta nueva SI FALTA. Converge
igual sea cual sea el estado de partida (DB fresca: ambos pasos son no-ops; DB con
forma vieja: DROP+ADD hacen el trabajo real). `ADD CONSTRAINT` sin `NOT VALID` valida
filas existentes por sí sola — si hubiera una fila cruzada de tenant, Postgres rechaza
el ALTER con error claro, no hace falta chequeo previo aparte. Un bloque de
verificación final confirma las 10 restricciones esperadas y `RAISE EXCEPTION`
ruidosamente si falta alguna.

**Commit:** `api-ventago@e118a2d8`

**Verificación manual (no es jest, es DDL):** se recrearon las 7 tablas usando la
versión ORIGINAL del archivo (`git show 24c0aed4:migrations/...`) para simular un
entorno ya migrado con la forma vieja; se confirmó que los nombres de constraint
auto-generados coincidían con lo que el bloque de upgrade espera; se corrió el archivo
EDITADO sobre esa DB de forma vieja → subió las 10 restricciones, borró las 9 FKs
simples viejas, y el bloque de verificación imprimió "las 10 restricciones ... están
OK". Se corrió una segunda vez: totalmente idempotente (todo "already exists,
skipping" / "does not exist, skipping"). Se re-confirmó el rechazo de INSERT cruzado de
tenant de `0b2566bb` después del upgrade. `migration-conventions.spec.ts` sigue en
verde.

## [P2] El generador de `db-schema-fks.md` fabricaba FKs compuestas inexistentes (fix real, no sólo documentado)

**Hallazgo** (repetido en dos reviews distintas — sobre `0b2566bb` y sobre el commit
raíz `docs(96-10)`): el primer intento de esta tarea sólo DOCUMENTÓ esto como caveat
conocido en vez de arreglarlo ("fuera de alcance"). CODEX insistió — con razón — en que
un generador de intel de esquema que fabrica relaciones inexistentes (p. ej.
`nota_attachments.nota_id -> notas.store_id`, que nunca existió) es un riesgo real para
cualquier revisión futura de fronteras de tenant que use ese archivo como fuente.

**Fix real (esta vez sí):** `./.planning/intel/db-schema.regen.sh` — la consulta de FKs
se reescribió dos veces:
1. Primer intento: unir `information_schema.referential_constraints` con dos lecturas
   de `key_column_usage` emparejando por `position_in_unique_constraint` (en vez de
   sólo por nombre de constraint). Correcto, pero `key_column_usage` llama a
   `_pg_expandarray()` internamente por cada columna de cada constraint de la DB — con
   ~130 tablas tardó varios MINUTOS y hubo que cancelarlo (`pg_cancel_backend`).
2. Versión final: `pg_constraint` (catálogo nativo) directo — `conkey`/`confkey` son
   dos arrays PARALELOS que el catálogo ya garantiza alineados por posición, así que
   `unnest(conkey, confkey) WITH ORDINALITY` los empareja sin joins adicionales.
   Mismo resultado (verificado fila por fila contra la versión con
   information_schema), pero ~0.03s en vez de minutos.

Las FKs compuestas ahora salen como UNA fila con la tupla de columnas en orden
(`nota_id, store_id` → `id, store_id`), no como el producto cartesiano de antes.
Control de regresión: FKs de una sola columna en tablas no relacionadas con Notas
(`sales`, `mp_movements`, etc.) — idénticas antes y después salvo por reordenamiento;
el total de filas bajó de 534 a 511 (exactamente las filas cartesianas espurias de las
6 FKs compuestas de Notas que se eliminaron). Bonus: una fila legítima
(`categories.canonical_category_id -> canonical_categories.id`) que el generador viejo
NO mostraba apareció con el fix — la vieja consulta la perdía por algún efecto del join
por nombre de constraint sin acotar por tabla; no se investigó más a fondo por no ser
parte del alcance de Notas.

**Commit:** `root@<pendiente de este mismo commit>` (ver tabla de abajo)

## [P2] `unreadSummary()` comparte el mismo patrón de cap sin rescate — sigue diferido a propósito

**Hallazgo** (confirmado por CODEX sobre el commit raíz de docs): `list().counts.mi`
sale de `unreadSummary()`, que tiene el mismo cap `NOTAS_SCAN_CAP` sin la lógica de
rescate de fijadas ni bandera de truncamiento — si hay notas no-leídas más viejas que
el cap, el número de "no leídas" que ve el usuario puede ser menor al real, sin ningún
aviso.

**Decisión:** se mantiene diferido, ahora de forma explícita y con el hallazgo de
CODEX como segunda confirmación (no es un caso hipotético que se me ocurrió a mí solo).
El pedido concreto de esta tarea de gap-fix para el hallazgo de `list()` era
específicamente "pinned rescue + `truncated` flag" en el endpoint de LISTA — extender
la misma lógica a `unreadSummary()` (que se usa standalone Y al final de `list()`) es
un cambio de forma razonable pero más amplio (tocaría el contrato `NotasUnread`, capaz
sumando un `truncated` ahí también) que no estaba en el pedido original y que no se
hizo sin decisión explícita del usuario, seguiendo la regla del repo de no ampliar
alcance sobre la marcha. **Queda como follow-up explícito, no como omisión.**

---

## Resumen de comandos de verificación (todos en verde al final, estado final tras la 2ª pasada)

```bash
cd api-ventago
env -u NODE_OPTIONS npx tsc --noEmit -p tsconfig.json          # 0 errores
env -u NODE_OPTIONS npx jest src/app/notas \
  src/common/migrations/migration-conventions.spec.ts \
  --maxWorkers=1                                                # 196/196 passed
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

## Commits (orden cronológico, estado final)

### Pasada 1 — hallazgos originales de `auto-api-ventago-f1a3cf93.md`

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

### Pasada 2 — CODEX revisó los commits de arriba y encontró más (ver secciones «Segunda pasada»)

| # | Hallazgo(s) | Repo | SHA | Mensaje |
|---|---|---|---|---|
| 8 | P2 edit() sin re-validar tras lock + P2 rollback tapa error/compensate + P2 fallback timezone UTC | api-ventago | `0d891ec8` | address CODEX follow-up findings on the notas-command.service.ts fixes |
| 9 | P3 exact-cap boundary + P2 rescate de fijadas sin límite | api-ventago | `88f1fc84` | address CODEX follow-up findings on the list() truncation fix |
| 10 | P1 tx.commit() ambiguo seguía compensando MinIO | api-ventago | `5c8f36fe` | stop compensating MinIO on an ambiguous tx.commit() rejection |
| 11 | P1 CREATE TABLE IF NOT EXISTS no upgradea DBs ya migradas | api-ventago | `e118a2d8` | make the composite-FK upgrade idempotent for already-applied DBs |
| 12 | (docs) regen intel tras el upgrade idempotente | root | `c253fc5` | regenerate db-schema intel after idempotent-upgrade re-verification |
| 13 | P2 generador de FKs fabricaba compuestas inexistentes (fix real) | root | `<este commit>` | fix db-schema-fks.md generator + regen |

No se hizo `git push` en ningún repo (regla de la tarea). Los gitlinks de
`api-ventago`/`ventago-app` en este repo raíz NO se movieron a propósito (ver nota al
principio del documento) — los SHAs de arriba existen en el historial de cada
submódulo, verificables con `git -C api-ventago log --oneline` /
`git -C ventago-app log --oneline`. La migración de producción (`96-10-PLAN.md`) sigue
pendiente de aprobación con este SQL ya corregido (dos veces: BEGIN/COMMIT explícito +
upgrade idempotente).

## Riesgo residual conocido (no implementado, requiere decisión del usuario)

**`tx.commit()` ambiguo puede seguir duplicando una nota/respuesta en reintento del
cliente.** Ver la sección «[P1] tx.commit() rechazando es un resultado AMBIGUO» arriba.
El fix aplicado evita el daño MÁS grave (referencia rota a un objeto de MinIO borrado),
pero no cierra la duplicación en el caso "el commit en realidad tuvo éxito, el cliente
reintenta creyendo que falló". Cerrar esto del todo necesita infraestructura de
Idempotency-Key equivalente a la que ya existe para `sales` (columna/tabla de
deduplicación por request + chequeo antes de escribir) — un cambio de arquitectura, no
un gap-fix. Se propone como línea de trabajo futura, no se decide unilateralmente acá.
