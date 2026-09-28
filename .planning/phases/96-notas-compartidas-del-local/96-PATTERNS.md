# Phase 96: Notas compartidas del local - Pattern Map

**Mapped:** 2026-09-28
**Files analyzed:** 24 (backend 14, frontend 10)
**Analogs found:** 22 / 24 (2 have no direct repo analog — sketch is the reference for those)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `api-ventago/migrations/2026-09-28-notas-seed.sql` | migration (seed) | batch | `api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql` | exact |
| `api-ventago/migrations/2026-09-28-notas-tables.sql` | migration (DDL) | batch | `api-ventago/migrations/store-notices.sql` | exact |
| `api-ventago/src/app/notas/models/nota.model.ts` | model | CRUD | `api-ventago/src/app/team-chat/team-message.model.ts` | role-match |
| `api-ventago/src/app/notas/models/nota-recipient.model.ts` | model | CRUD | `team-message.model.ts` (receiverId nullable pattern, generalized to join table) | partial |
| `api-ventago/src/app/notas/models/nota-read.model.ts` | model | CRUD | `team-message.model.ts` (`readAt` column) | partial |
| `api-ventago/src/app/notas/models/nota-reaction.model.ts` | model | CRUD | none (own composition) | no analog |
| `api-ventago/src/app/notas/models/nota-reply.model.ts` | model | CRUD | `team-message.model.ts` (flat message row, no self-FK) | partial |
| `api-ventago/src/app/notas/models/nota-edit-history.model.ts` | model | append-only/CRUD | none (own composition — mirror `stocks` append-only spirit, not code) | no analog |
| `api-ventago/src/app/notas/models/nota-attachment.model.ts` | model | file-I/O | none directly; MinIO key pattern from `minio.service.ts` | partial |
| `api-ventago/src/app/notas/dto/create-nota.dto.ts` | DTO | request-response | `api-ventago/src/app/expense-categories/dto/delete-expense-category.dto.ts` | role-match |
| `api-ventago/src/app/notas/dto/reply-nota.dto.ts` | DTO | request-response | `api-ventago/src/app/attendance/dto/adjust-attendance.dto.ts` | role-match |
| `api-ventago/src/app/notas/notas.service.ts` | service | CRUD + visibility-filter | `api-ventago/src/app/team-chat/team-chat.service.ts` | role-match |
| `api-ventago/src/app/notas/notas.controller.ts` | controller | request-response | `api-ventago/src/app/team-chat/team-chat.controller.ts` + `api-ventago/src/app/box/box.controller.ts` (for `@FunctionGuard`) | role-match |
| `api-ventago/src/app/notas/notas-attachments.controller.ts` | controller | file streaming | `api-ventago/src/common/minio/minio.controller.ts` (`getImage`, but must NOT reuse `@Public()`) | role-match (inverted: must diverge on auth) |
| `api-ventago/src/app/notas/notas.module.ts` | config (module) | — | `api-ventago/src/app/team-chat/team-chat.module.ts` | exact |
| `api-ventago/src/app.module.ts` (edit) | config | — | existing `TeamChatModule`/`BoxModule` import+providers lines | exact |
| `api-ventago/src/app/notas/notas.service.spec.ts` | test | — | `api-ventago/src/app/expense-categories/expense-category.service.spec.ts` | exact |
| `ventago-app/src/pages/notas/index.tsx` | route (page) | request-response | `ventago-app/src/pages/gastos/index.tsx` | exact |
| `ventago-app/src/views/notas/NotasView.tsx` | component (two-column view) | request-response | no direct list+detail split analog; sketch `.planning/sketches/notas-compartidas.html` `.split` layout is the literal spec | no analog (use sketch) |
| `ventago-app/src/views/notas/ComposeNotaDialog.tsx` | component (modal) | request-response | sketch's `compose()` dialog function (literal reference) + MUI Dialog convention repo-wide | no analog (use sketch) |
| `ventago-app/src/hooks/api/useNotasUnreadCount.ts` | hook (SWR) | polling | `ventago-app/src/hooks/api/useNotices.ts` (`useMyNotices`, `refreshInterval: 30_000`) | exact |
| `ventago-app/src/hooks/api/useNotas.ts` | hook (SWR) | CRUD-read | `ventago-app/src/hooks/api/useBranchByStore.ts` | role-match |
| `ventago-app/src/components/notas/NotaToast.tsx` + global listener mounted in `UserLayout.tsx` | component (global socket listener) | event-driven | `ventago-app/src/components/team-chat/TeamChatBubble.tsx` + `TeamChatPanel.tsx` (`useRealtime`) | role-match (must diverge: always-mounted, not `open`-gated) |
| `ventago-app/src/navigation/vertical/index.ts` (edit: inject `badgeContent`) | provider/derived-state | — | `VerticalNavLink.tsx:182` badge render (currently zero producers) | no analog (first producer) |

## Pattern Assignments

### `api-ventago/migrations/2026-09-28-notas-tables.sql` (migration DDL)

**Analog:** `api-ventago/migrations/store-notices.sql`

**Full pattern to copy** (owner DO block, IF NOT EXISTS, indexes before owner block):
```sql
-- Source: api-ventago/migrations/store-notices.sql:1-37 (verified in repo)
CREATE TABLE IF NOT EXISTS store_notices (
  id           BIGSERIAL PRIMARY KEY,
  store_id     INTEGER      NOT NULL,
  campaign_id  UUID         NOT NULL,
  level        VARCHAR(16)  NOT NULL DEFAULT 'info',
  title        VARCHAR(200) NOT NULL,
  body         TEXT         NOT NULL,
  created_by   INTEGER,
  read_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_notices_store_unread_idx
  ON store_notices (store_id, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS store_notices_campaign_idx
  ON store_notices (campaign_id);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE store_notices OWNER TO coolsistema;
    ALTER SEQUENCE store_notices_id_seq OWNER TO coolsistema;
  END IF;
END $$;
```
**Apply this per new table** (`nota`, `nota_recipients`, `nota_reads`, `nota_reactions`,
`nota_replies`, `nota_edit_history`, `nota_attachments`) — each gets its own
`IF NOT EXISTS`, its own indexes, and **its own owner DO block** (owner does not cascade
across tables). Since these are brand-new tables with zero traffic, the
`migration-conventions.spec.ts` "new table" exemption applies — CONCURRENTLY is not
required for the initial `CREATE INDEX`, but still write `-- w4-exempt: tabla nueva sin
lectores existentes` per file per CLAUDE.md's exemption-comment convention.
Also add `SET lock_timeout = '5s';` as the first line (see `2026-09-27-e-modulo-impresoras.sql:16`).

**Key deviation:** `nota_reply` must have **no self-referential `parentReplyId`/FK** —
per RESEARCH Pitfall 7, structural absence of the column is what makes nested replies
impossible, not a service-layer check.

---

### `api-ventago/migrations/2026-09-28-notas-seed.sql` (seed migration)

**Analog:** `api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql` (full file, 57 lines, already read above)

**Pattern to copy exactly:**
```sql
-- Source: api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql:1-56 (verified)
SET lock_timeout = '5s';

INSERT INTO modules (name, slug, description, icon, url, is_main, is_auxiliary, app_id, created_at, updated_at)
SELECT 'Notas', 'notas', 'Notas compartidas del local', 'tabler:notes', '/notas', true, false, a.id, now(), now()
FROM apps a WHERE a.slug = '<TBD by planner Wave 0 — see RESEARCH Open Question 1>'
  AND NOT EXISTS (SELECT 1 FROM modules m WHERE m.slug = 'notas');

INSERT INTO functions (name, slug, description, module_id, created_at, updated_at)
SELECT 'Ver notas', 'ver-notas', '[Notas] Ver y participar en notas del local', m.id, now(), now()
FROM modules m WHERE m.slug = 'notas'
  AND NOT EXISTS (SELECT 1 FROM functions f WHERE f.slug = 'ver-notas');

INSERT INTO functions (name, slug, description, module_id, created_at, updated_at)
SELECT 'Enviar a todos', 'notas-enviar-todos', '[Notas] Enviar nota a todo el local (audience=all) y moderar Todos', m.id, now(), now()
FROM modules m WHERE m.slug = 'notas'
  AND NOT EXISTS (SELECT 1 FROM functions f WHERE f.slug = 'notas-enviar-todos');

-- grants: copiar de una función casi-universal existente, NO sólo los 4 roles globales
-- (ver RESEARCH Open Question 2 — auditar antes de decidir la fuente)
INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
SELECT DISTINCT rf.role_id, fn.id, rf.store_id, now(), now()
FROM role_functions rf
JOIN functions f ON f.id = rf.function_id AND f.slug = '<función casi-universal>'
CROSS JOIN functions fn
WHERE fn.slug = 'ver-notas'
ON CONFLICT (role_id, function_id, store_id) DO NOTHING;

-- notas-enviar-todos: sólo admin (ver Pitfall 4 para el NOT EXISTS de roles NULL store_id)
```

**Anti-pattern to avoid (Pitfall 4):** `ON CONFLICT (role_id, function_id, store_id)` never
fires for the 4 global roles (`store_id IS NULL`, NULL ≠ NULL in Postgres). Use
`NOT EXISTS (... store_id IS NOT DISTINCT FROM ...)` per the `2026-09-24-phase93-p5-seed-herramientas.sql`
convention (file exists at that path — read directly if writing the global-role branch).

**Deploy ordering (Pitfall 3):** this file must be applied to prod (5434) **before** any
code referencing `ver-notas`/`notas-enviar-todos` is deployed — `FunctionGuard` denies
unknown slugs.

---

### `api-ventago/src/app/notas/models/nota.model.ts` (model, CRUD)

**Analog:** `api-ventago/src/app/team-chat/team-message.model.ts` (full file, 47 lines, read above)

**Imports + table decoration pattern:**
```ts
// Source: api-ventago/src/app/team-chat/team-message.model.ts:1-26 (verified)
import {
  AutoIncrement, BelongsTo, Column, DataType, ForeignKey, Model, PrimaryKey, Table,
} from 'sequelize-typescript';
import { Store } from '../store/store.model';
import { Users } from '../users/users.model';

@Table({ timestamps: true, tableName: 'team_messages' })
export class TeamMessage extends Model {
  @PrimaryKey
  @AutoIncrement
  @Column
  id: number;

  @ForeignKey(() => Store)
  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @BelongsTo(() => Store, { onDelete: 'CASCADE' })
  store: Store;
}
```
**Critical:** `storeId` must be present with this exact `@ForeignKey`/`@Column` shape so the
global `TenantGuard` hook (`tenant-hooks.ts`) auto-installs on `Nota` at boot — no manual
wiring needed for store-level isolation (but this is NOT sufficient for D-05, see Notas
service pattern below).

**Deviation required from team-chat:** team-chat encodes "Todos" as `receiverId: null`
(single nullable FK). Notas' D-04 (Todos or 1+ users) requires generalizing this to an
`audience` enum column (`'all' | 'users'`) on `nota` plus a separate `nota_recipients`
join table (one row per `notaId`+`userId`) for the multi-user case — team-chat's model has
no precedent for this fan-out, it is original composition per RESEARCH.

---

### `api-ventago/src/app/notas/notas.service.ts` (service, CRUD + visibility)

**Analog:** `api-ventago/src/app/team-chat/team-chat.service.ts` (full file, 169 lines, read above)

**Imports pattern:**
```ts
// Source: api-ventago/src/app/team-chat/team-chat.service.ts:1-13 (verified)
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { TeamMessage } from './team-message.model';
import { Users } from '../users/users.model';
import { Op } from 'sequelize';
import { WebsocketService } from '../../common/socket/websocket.service';

@Injectable()
export class TeamChatService {
  constructor(
    @InjectModel(TeamMessage) private messageModel: typeof TeamMessage,
    private readonly wsService: WebsocketService,
  ) {}
}
```

**Visibility predicate (D-05) — the one thing team-chat does NOT need but Notas must have:**
```ts
// Source: pattern composed from tenant-hooks.ts comments + team-chat.service.ts:74-85
// idiomatic precedent for Op.or composition (own composition, no direct 1:1 precedent):
let where: any;
if (receiverId) {
  where = {
    storeId,
    [Op.or]: [
      { senderId: userId, receiverId },
      { senderId: receiverId, receiverId: userId },
    ],
  };
} else {
  where = { storeId, receiverId: null };
}
```
Generalize this exact `Op.or` composition shape for Notas' three-way predicate
(sender OR audience='all' OR EXISTS-in-recipients). **Every** read method (list, detail,
search) must apply it — see RESEARCH §Visibility Enforcement Deep Dive for the full
`Op.or` shape including the `'$recipients.user_id$'` include-based clause.

**Realtime emit pattern — copy exactly:**
```ts
// Source: api-ventago/src/app/team-chat/team-chat.service.ts:44-55 (verified)
const payload = fullMessage?.toJSON();
if (receiverId) {
  this.wsService.emitToUser(receiverId, 'team:message', payload);
  this.wsService.emitToUser(senderId, 'team:message', payload);
} else {
  this.wsService.emitToStore(storeId, 'team:message', payload);
}
```
Replace `'team:message'` with `'nota:new'` / `'nota:reply'` / `'nota:reaction'`; for
audience='users' notas, loop `emitToUser` per recipient (mirrors the `receiverId` branch);
for audience='all', use `emitToStore` (mirrors the `else` branch) — same two-branch shape.

**Store-user-list pattern (for the recipient picker) — copy exactly:**
```ts
// Source: api-ventago/src/app/team-chat/team-chat.service.ts:162-168 (verified)
async getStoreUsers(storeId: number): Promise<any[]> {
  return Users.findAll({
    where: { storeId, status: 'active' },
    attributes: ['id', 'name', 'lastName', 'username'],
    order: [['name', 'ASC']],
  });
}
```
Reuse this method directly (D-01 explicitly says to reuse the store user list) rather than
duplicating it in Notas — either import `TeamChatService.getStoreUsers` or lift it to a
shared helper; do not re-derive the query.

**Pagination — copy exactly:**
```ts
// Source: api-ventago/src/app/team-chat/team-chat.service.ts:70-99 (verified)
const { rows, count } = await this.messageModel.findAndCountAll({
  where,
  include: [{ model: Users, as: 'sender', attributes: ['id', 'name', 'lastName', 'username'] }],
  order: [['createdAt', 'DESC']],
  limit: pageSize,
  offset: page * pageSize,
});
return { data: rows.reverse(), total: count, page, pageSize };
```

**Timezone helper — reuse, do not hand-roll (D-16 expiry):**
```ts
// Source: api-ventago/src/app/attendance/attendance-time.util.ts:12-49 (verified)
import { storeNowParts, nextMidnightISO } from 'src/app/attendance/attendance-time.util';
// storeNowParts(store.timezone) -> { date: 'YYYY-MM-DD', time: 'HH:mm:ss' }
```

---

### `api-ventago/src/app/notas/notas.controller.ts` (controller, request-response)

**Analog A (route shape, pagination):** `api-ventago/src/app/team-chat/team-chat.controller.ts` (full file, 81 lines, read above)
**Analog B (`@FunctionGuard` usage for the "send to all" gate):** `api-ventago/src/app/box/box.controller.ts`

**Imports + route pattern (team-chat style, for basic `@Auth()`-only routes):**
```ts
// Source: api-ventago/src/app/team-chat/team-chat.controller.ts:1-13,36-51 (verified)
import { Controller, Post, Get, Body, Query, HttpCode, HttpStatus } from '@nestjs/common';
import { Auth } from '../auth/decorators/auth.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { clampPageSize } from 'src/common/pagination/pagination.util';

@Get('messages')
@Auth()
async messages(
  @Query('page') page: string,
  @Query('pageSize') pageSize: string,
  @GetUser() user: any,
) {
  return this.service.getMessages({
    storeId: user.storeId,
    userId: user.id,
    page: page ? Number(page) : 0,
    pageSize: clampPageSize(pageSize, { fallback: 50 }),
  });
}
```

**`@FunctionGuard` pattern for the create-nota-to-all action:**
```ts
// Source: api-ventago/src/app/box/box.controller.ts:1-38 (verified)
import { FunctionGuard } from '../auth/decorators/function-guard.decorator';

@Post('')
@FunctionGuard('notas-enviar-todos', 'create')
async create(@Body() body: any, @GetUser() user?: Users): Promise<any> { ... }
```
**Important nuance for Notas (NOT a copy-paste, a deviation):** per D-03, `@FunctionGuard`
should gate only the `audience='all'` **branch** of nota creation, not the whole create
endpoint (individual/selected-user notas are open to anyone with menu access). This means
the controller's single `POST /notas` action must check `dto.audience === 'all'` and
call a slug-gated check inside the service/a secondary guard, OR split into two routes.
`box.controller.ts`'s pattern (whole-route gate) does not fit 1:1 — flag this for the
planner as a composition decision, not a literal copy.

**`FunctionGuard` decorator internals** (for understanding, do not modify):
```ts
// Source: api-ventago/src/app/auth/decorators/function-guard.decorator.ts:79-88 (verified)
export function FunctionGuard(functionSlug: string, action: string, moduleSlug?: string) {
  return applyDecorators(
    RequireFunction(functionSlug, action, moduleSlug),
    UseGuards(AuthGuard('jwt'), FunctionPermissionGuard),
  );
}
```

---

### `api-ventago/src/app/notas/notas-attachments.controller.ts` (controller, file streaming)

**Analog (structure only — auth behavior must be INVERTED):** `api-ventago/src/common/minio/minio.controller.ts:94-111`

```ts
// Source: api-ventago/src/common/minio/minio.controller.ts:94-111 (verified) — DO NOT COPY THE @Public()
@Public()
@Get(':filename')
async getImage(@Param('filename') filename: string, @Res() res: any) {
  if (!isPubliclyServable(filename)) {
    throw new ForbiddenException('Objeto no disponible públicamente');
  }
  try {
    const stream = await this.service.getObjectStream(filename);
    res.setHeader('Content-Type', 'image/png');
    stream.pipe(res);
  } catch (err) {
    res.status(404).send('Not found');
  }
}
```

**Required Notas version — structure copied, auth model reversed:**
```ts
// New composition, no direct precedent (per RESEARCH §Attachments and Privacy):
@Auth()
@Get(':notaId/:filename')
async getAttachment(
  @Param('notaId', ParseIntPipe) notaId: number,
  @Param('filename') filename: string,
  @GetUser() user: any,
  @Res() res: any,
) {
  await this.notasService.assertVisible(notaId, user.id); // same Op.or predicate as detail()
  const key = `notas/${user.storeId}/${notaId}/${filename}`;
  const stream = await this.minioService.getObjectStream(key);
  stream.pipe(res);
}
```
**MinioService methods to reuse directly (no changes needed):** `uploadFile()` (`minio.service.ts:74-83`),
`getObjectStream()` (`minio.service.ts:99-101`), `removeFile()` (`minio.service.ts:107-116`).
**Never** extend `MinioController` itself or route through `/minio/:filename` — path-prefixed
keys (`notas/{storeId}/{notaId}/...`) already get rejected there because
`isPubliclyServable()` blocks any name containing `/` (`minio.controller.ts:38`), so this is
belt-and-suspenders, not the only protection — the real protection is that Notas' own
endpoint re-checks the visibility predicate per request.

---

### `api-ventago/src/app/notas/notas.module.ts` (module registration)

**Analog:** `api-ventago/src/app/team-chat/team-chat.module.ts` (full file, 15 lines, read above)

```ts
// Source: api-ventago/src/app/team-chat/team-chat.module.ts (verified)
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { TeamMessage } from './team-message.model';
import { TeamChatService } from './team-chat.service';
import { TeamChatController } from './team-chat.controller';
import { WebsocketModule } from '../../common/socket/websocket.module';

@Module({
  imports: [SequelizeModule.forFeature([TeamMessage]), WebsocketModule],
  controllers: [TeamChatController],
  providers: [TeamChatService],
  exports: [TeamChatService],
})
export class TeamChatModule {}
```
For Notas: `SequelizeModule.forFeature([Nota, NotaRecipient, NotaRead, NotaReaction,
NotaReply, NotaEditHistory, NotaAttachment])`, import `WebsocketModule` and `MinioModule`
(per CLAUDE.md's "MinioModule 을 해당 모듈의 imports 에 추가"), two controllers
(`NotasController`, `NotasAttachmentsController`).

**app.module.ts registration — copy exact insertion style:**
```ts
// Source: api-ventago/src/app.module.ts:80 (import) and :248 (providers array) (verified)
import { TeamChatModule } from './app/team-chat/team-chat.module';
// ...
    TeamChatModule,
```
Add `import { NotasModule } from './app/notas/notas.module';` near the other feature-module
imports, and `NotasModule,` in the same providers/imports array (alphabetical-ish grouping
is not strictly enforced in this file — team-chat sits between `SupportTokenModule` and
`ImportModule`, so placement is not semantically load-bearing).

---

### `api-ventago/src/app/notas/dto/create-nota.dto.ts` (DTO, class-validator)

**Analog A (simple field validation):** `api-ventago/src/app/attendance/dto/adjust-attendance.dto.ts`
**Analog B (conditional validation with `@ValidateIf` + `@Transform`):** `api-ventago/src/app/expense-categories/dto/delete-expense-category.dto.ts`

```ts
// Source: api-ventago/src/app/attendance/dto/adjust-attendance.dto.ts (verified, full file)
import { IsISO8601, IsOptional, IsString } from 'class-validator';

export class AdjustAttendanceDto {
  @IsOptional()
  @IsISO8601()
  checkInAt?: string;

  @IsOptional()
  @IsString()
  note?: string;
}
```

```ts
// Source: api-ventago/src/app/expense-categories/dto/delete-expense-category.dto.ts (verified, full file)
import { IsIn, IsInt, IsOptional, IsString, Min, ValidateIf } from 'class-validator';
import { Transform } from 'class-transformer';

export class DeleteExpenseCategoryDto {
  @IsString()
  @IsIn(['promote', 'move', 'cascade'], {
    message: 'policy 는 promote | move | cascade 중 하나여야 합니다',
  })
  policy: 'promote' | 'move' | 'cascade';

  @ValidateIf((o) => o.policy === 'move')
  @Transform(({ value }) => (value !== undefined ? Number(value) : undefined))
  @IsInt()
  @Min(1)
  @IsOptional()
  moveTo?: number;
}
```
**Apply this shape to `CreateNotaDto`:** `title: @IsString() @MaxLength(200)` (required,
no `@IsOptional`); `body: @IsOptional() @IsString()`; `importance: @IsIn(['normal','importante','urgente'])`;
`audience: @IsIn(['all','users'])`; `recipientIds: @ValidateIf(o => o.audience==='users') @IsArray() @ArrayMinSize(1) @IsInt({each:true})`;
`expiresOn: @IsOptional() @IsISO8601()`. This directly satisfies D-06 (title required) and
D-04 (conditional recipient list) using patterns already idiomatic in this repo — no new
validation library needed.

---

### `api-ventago/src/app/notas/notas.service.spec.ts` (test harness)

**Analog:** `api-ventago/src/app/expense-categories/expense-category.service.spec.ts` (full file, 434 lines, read above — this is the canonical repo harness for "Sequelize model + connection dependency" services)

```ts
// Source: api-ventago/src/app/expense-categories/expense-category.service.spec.ts:1-70 (verified)
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { getConnectionToken, getModelToken } from '@nestjs/sequelize';
import { Test } from '@nestjs/testing';

describe('NotasService', () => {
  let svc: NotasService;
  let model: any;
  let sequelize: any;
  const tx = { commit: jest.fn(), rollback: jest.fn() };

  beforeEach(async () => {
    model = { findAll: jest.fn(), findOne: jest.fn(), findByPk: jest.fn(), create: jest.fn(), update: jest.fn(), count: jest.fn() };
    sequelize = { transaction: jest.fn().mockResolvedValue(tx), query: jest.fn() };
    tx.commit.mockClear();
    tx.rollback.mockClear();

    const moduleRef = await Test.createTestingModule({
      providers: [
        NotasService,
        { provide: getModelToken(Nota), useValue: model },
        { provide: getConnectionToken(), useValue: sequelize },
        { provide: WebsocketService, useValue: { emitToUser: jest.fn(), emitToStore: jest.fn() } },
      ],
    }).compile();

    svc = moduleRef.get(NotasService);
  });
  // ... describe('visibility') / describe('unread') / describe('ack') / describe('expiry') blocks
});
```
**Do not** `new NotasService(...)` manually — per repo convention (memory:
`nest-service-needs-harness-not-manual-new.md`), constructor DI wiring subtleties are
silently skipped without `Test.createTestingModule`.
**Run command:** `cd api-ventago && npx jest src/app/notas --maxWorkers=1` (per RESEARCH
Validation Architecture table — never `--findRelatedTests`, never full suite).

---

### `ventago-app/src/pages/notas/index.tsx` (Next.js page, next/dynamic)

**Analog:** `ventago-app/src/pages/gastos/index.tsx` (full file, 14 lines, read above)

```tsx
// Source: ventago-app/src/pages/gastos/index.tsx (verified, full file)
import React from 'react'
import dynamic from 'next/dynamic'
import WithAccess from 'src/configs/withAccess'

const ExpensesView = dynamic(() => import('src/views/expenses/ExpensesView').then(m => ({ default: m.default as React.ComponentType })), { ssr: false })

const ExpensesPage = () => {
  return (
    <WithAccess allowedApps={["venta"]} allowedModules={["gastos"]}>
      <ExpensesView />
    </WithAccess>
  )
}

export default ExpensesPage
```
Copy exactly, substituting `NotasView` and `allowedModules={["notas"]}`. **Reminder
(RESEARCH §Visibility Enforcement):** `WithAccess` admin-bypass is a page-access
convenience only — it has zero bearing on D-05's server-side row filtering; do not treat
this file as doing any visibility enforcement.

---

### `ventago-app/src/views/notas/NotasView.tsx` (two-column MUI view)

**No direct repo analog for the list+detail split itself.** Searched `Grid container` +
`md={3..4}` two-column views (`SharedFoldersListView.tsx` is a card grid, not a
master-detail split; `ClientLedgerView.tsx` is a single-column summary+table, not a
side-by-side inbox). **The approved sketch `.planning/sketches/notas-compartidas.html`
(`.split { grid-template-columns: 340px 1fr }`, lines 76-77, and its `render()`/`detail()`/
`card()` JS functions, lines 264-336) is the literal reference implementation** per D-02
and RESEARCH's explicit instruction ("read its JS state machine directly"). Translate to
MUI: `<Grid container><Grid item md={4}>` (inbox list, `overflow:auto`, `maxHeight`) `</Grid><Grid item md={8}>` (detail pane) `</Grid></Grid>`, collapsing to a single column
below `md` breakpoint (mirrors the sketch's `@media(max-width:1000px){.split{grid-template-columns:1fr}}`).

**Reuse for sort/filter/unread logic — copy the sketch's pure functions almost verbatim
into a testable `.ts` helper** (repo memory: app jest cannot import `.tsx`, so this logic
must live outside the view component):
```js
// Source: .planning/sketches/notas-compartidas.html:244-260 (the literal spec for D-07/D-11/D-19)
function isUnread(n,w){
  if(n.from===w||n.archived||n.vencida)return false;
  if(n.to==='all'&&USERS[w].since>0&&!n.pin)return false; // D-07 신입: 과거 Todos 는 고정만 안읽음
  const r=state(n,w);return needAck(n)?r!=='ack':!r;
}
function list(){ /* tab filter + sort: pin desc, unread desc, ord asc — matches D-19 */ }
```
Port this to `ventago-app/src/utils/notas/notas-visibility.ts` (or similar `.ts`, not
`.tsx`) so `ventago-app/src/__tests__/notas-unread.spec.ts` can import and test it directly
— per RESEARCH Wave 0 Gaps.

---

### `ventago-app/src/hooks/api/useNotasUnreadCount.ts` (SWR hook, polling)

**Analog:** `ventago-app/src/hooks/api/useNotices.ts` (full file, 57 lines, read above)

```ts
// Source: ventago-app/src/hooks/api/useNotices.ts:52-56 (verified)
export function useMyNotices() {
  return useApi<MyNotice[]>('/admin-console/my-notices', {
    refreshInterval: 30_000,
  })
}
```
Copy this exact shape:
```ts
export function useNotasUnreadCount() {
  return useApi<{ total: number }>('/notas/unread', { refreshInterval: 30_000 })
}
```
Underlying `useApi` is a thin `useSWR` wrapper — copy verbatim:
```ts
// Source: ventago-app/src/hooks/useApi.ts (verified, full file)
import useSWR from 'swr'
import type { SWRConfiguration } from 'swr'

export function useApi<T = unknown>(url: string | null, options?: SWRConfiguration) {
  const { data, error, isLoading, mutate } = useSWR<T>(url, options)
  return { data, error, isLoading, mutate }
}
```
**Note (RESEARCH §Sidebar Badge Injection pitfall):** polling here is fine for the badge
*count value*, but do not let this hook's data feed directly into `useNavigation()`'s
`useMemo` dependency array without isolating it — see the sidebar section below.

---

### `ventago-app/src/hooks/api/useNotas.ts` (SWR hook, list/detail read)

**Analog:** `ventago-app/src/hooks/api/useBranchByStore.ts` (full file, 32 lines, read above)

```ts
// Source: ventago-app/src/hooks/api/useBranchByStore.ts (verified, full file)
import { useMemo } from 'react'
import { useApi } from 'src/hooks/useApi'
import { useAuth } from 'src/hooks/useAuth'

export function useBranchByStore() {
  const { user } = useAuth()
  const storeId = user?.storeId
  const { data, error, isLoading, mutate } = useApi<any>(
    storeId ? `/branch/store/${storeId}` : null,
  )
  const branches = useMemo<any[]>(() => {
    if (Array.isArray(data)) return data
    if (data && Array.isArray((data as any).data)) return (data as any).data
    return []
  }, [data])
  return { data: branches, error, isLoading, mutate }
}
```
Copy the `storeId ? url : null` conditional-fetch guard and the response-shape
normalization defensiveness (team-chat's `/notas` list endpoint will likely return
`{ data, total, page, pageSize }` per `team-chat.service.ts:101`'s shape — normalize the
same way here).

---

### `ventago-app/src/components/notas/NotaToast.tsx` + global mount in `UserLayout.tsx`

**Analog (realtime subscription):** `ventago-app/src/components/team-chat/TeamChatPanel.tsx:44-73`
**Analog (always-mounted dynamic component in UserLayout):** `ventago-app/src/views/components/NoticesBanner.tsx` + its mount point

```tsx
// Source: ventago-app/src/components/team-chat/TeamChatPanel.tsx:1-11,44-73 (verified)
import { useRealtime } from 'src/realtime'

useRealtime(
  'realtime',
  {
    'team:message': (msg: Message) => { /* ... */ },
    'team:read': () => undefined,
  },
  {
    enabled: Boolean(open && user?.id),
    room: { event: 'register_user', payload: { userId: user?.id, storeId: user?.storeId } },
  },
)
```
**Critical deviation (RESEARCH Pattern 3):** team-chat gates `enabled` on `open` — Notas'
D-08 requires the badge+toast listener to fire **from any screen**, so `enabled` must be
`Boolean(user?.id)` only (always true while logged in), not gated on a panel-open flag.
Mirror instead how `NoticesBanner` is mounted — always-on, `dynamic(..., {ssr:false})`:
```tsx
// Source: ventago-app/src/layouts/UserLayout.tsx:31,317 (verified)
const NoticesBanner = dynamic(() => import('src/views/components/NoticesBanner'), { ssr: false })
// ...
<NoticesBanner />
```
Add `const NotaToast = dynamic(() => import('src/components/notas/NotaToast'), { ssr: false })`
and mount `<NotaToast />` alongside it (near line 317, `UserLayout.tsx`). Inside
`NotaToast.tsx`, use `useRealtime('realtime', { 'nota:new': handler }, { enabled:
Boolean(user?.id), room: {...} })` and internally check `router.pathname === '/nueva-venta'`
to suppress the visual toast (D-09) while still updating the badge count (via SWR
`mutate('/notas/unread')` or a shared context) — this route check is pure client logic,
no server involvement, per RESEARCH's Architectural Responsibility Map.

**Socket import guard:** never call `io()` directly in this file — `src/realtime/socket-registry.ts`
is the sole allowed `socket.io-client` import point, enforced by an ESLint
`no-restricted-imports` rule.

**Unread-icon-visibility pattern (optional, for a bubble-style variant):**
```tsx
// Source: ventago-app/src/components/team-chat/TeamChatBubble.tsx:20-47 (verified)
const [unread, setUnread] = useState(0)
useEffect(() => {
  if (!user?.id) return
  apiConnector.get('/team-chat/unread').then((res: any) => setUnread(res.total || 0)).catch(() => {})
}, [user?.id, open])
```
Not required for Notas (badge lives in the sidebar per D-08, not a floating FAB), but
useful if a floating "new nota" shortcut is added later.

---

### `ventago-app/src/navigation/vertical/index.ts` (sidebar badge injection)

**No producer analog exists — this is the first live `badgeContent` producer in the repo**
(RESEARCH confirms `grep badgeContent` shows only the type definition and the dead render
call). The render side is already wired and must NOT be touched:
```tsx
// Source: ventago-app/src/@core/layouts/components/vertical/navigation/VerticalNavLink.tsx:182-189 (verified)
{item.badgeContent ? (
  <Chip size='small' label={item.badgeContent} color={item.badgeColor || 'primary'}
    sx={{ height: 22, minWidth: 22, '& .MuiChip-label': { px: 1.5, textTransform: 'capitalize' } }} />
) : null}
```
**How the `/notas` nav item is currently built** (structure-derived, DB module → child item):
```ts
// Source: ventago-app/src/navigation/vertical/index.ts:129-141 (verified)
const children = (app.modules || [])
  .filter(mod => !mod.isAuxiliary && !(mod.url && hiddenModuleUrls.has(mod.url)) && !hiddenForSuperadmin(mod.url))
  .map(mod => ({
    title: appKey ? t(appKey) : literal || (globalKey ? t(globalKey) : mod.name),
    icon: (mod.url && cfg?.iconOverrides?.[mod.url]) || mod.icon,
    path: mod.url,
    action: 'read',
    subject: mod.slug || mod.name.toLowerCase().replace(/\s+/g, '-'),
  }));
```
**Required addition:** after building `children` (or in `resolveItem`), find the item whose
`path === '/notas'` and merge in `badgeContent: unreadCount || undefined`. Since
`useNavigation()` is itself a `useMemo` keyed on `[user?.structure, user?.roles, t]`
(`index.ts:47`), the unread count must be threaded in as an **explicit new dependency**
(e.g. `useNavigation(unreadNotasCount: number)`), not read from an ambient global — per
RESEARCH's pitfall, adding it as a dependency causes `memoizedNavItems` to get a new array
reference only when unread count changes (infrequent, acceptable per CLAUDE.md's own
"사이드바 리렌더링 방지" analysis), never on frequent/unrelated re-renders. Fetch the count
in `UserLayout.tsx` via `useNotasUnreadCount()` (SWR, 30s poll) and pass it down to
`VerticalNavItems()` — do NOT put it on `useAuth()`'s `user` object (that object is a
dependency of many other memoized trees).

---

## Shared Patterns

### Authentication / Authorization
**Source:** `api-ventago/src/app/auth/decorators/function-guard.decorator.ts:79-88`
(`FunctionGuard`) + `api-ventago/src/app/auth/decorators/auth.decorator.ts` (`@Auth()`)
**Apply to:** every Notas controller route. Plain `@Auth()` for anything gated only by
menu access (individual/selected-audience nota CRUD, reactions, replies, reads); add
`@FunctionGuard('notas-enviar-todos', 'create')` only for the audience='all' branch (D-03).
Gate D-10/D-14's "admin can see Todos read-list / archive others' Todos" behind the
`update` action on the same `notas-enviar-todos` slug (per RESEARCH Pitfall 8/Open
Question 3), never a raw `user.roles.includes('admin')` check.

### Per-row visibility (D-05) — NOT covered by any existing guard
**Source:** composed `Op.or` pattern, precedent style in
`api-ventago/src/app/team-chat/team-chat.service.ts:74-85`
**Apply to:** every read method in `NotasService` (list, detail, search, attachment
streaming). This is the single most safety-critical shared pattern in this phase — see
RESEARCH §Visibility Enforcement Deep Dive for the full predicate.

### Error handling
No repo-wide custom error wrapper is used in team-chat/box/expense-categories — standard
Nest `BadRequestException`/`NotFoundException`/`ForbiddenException` thrown directly from
service methods, caught by Nest's built-in exception filter. Follow
`expense-category.service.spec.ts`'s assertions style (`rejects.toThrow(BadRequestException)`)
for Notas tests (e.g., reply-to-reply attempt, moderation on a personal nota by non-owner).

### Pagination
**Source:** `api-ventago/src/common/pagination/pagination.util.ts` (`clampPageSize`,
`clampPage`) — already used by `team-chat.controller.ts:49`.
**Apply to:** `GET /notas` list/search endpoint. `pageSize` fallback 50 per CLAUDE.md's
"pageSize 최대 50" frontend convention; server-side clamp max stays at
`DEFAULT_MAX_PAGE_SIZE` (200) as a DoS backstop, not a UX cap.

### Realtime transport
**Source:** `api-ventago/src/common/socket/websocket.service.ts` (`emitToUser:79-83`,
`emitToStore:86-90`) — reuse `/realtime` namespace, do not create a new gateway/namespace.
**Frontend:** `ventago-app/src/realtime/useRealtime.ts` via `src/realtime` index — the only
sanctioned `socket.io-client` import point (ESLint-enforced).

### Store-timezone date handling
**Source:** `api-ventago/src/app/attendance/attendance-time.util.ts` (`storeNowParts`,
`nextMidnightISO`) — apply to D-16 expiry evaluation. Do not hand-roll UTC offset math.

### File storage
**Source:** `api-ventago/src/common/minio/minio.service.ts` (`uploadFile`,
`getObjectStream`, `removeFile`) — reuse directly, unchanged. Store nota/reply attachments
under path-prefixed keys (`notas/{storeId}/{notaId}/...`, `notas/{storeId}/replies/{replyId}/...`)
so the shared public `/minio/:filename` route structurally rejects them
(`isPubliclyServable()` blocks any name containing `/`). Never extend `MinioController`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `api-ventago/src/app/notas/models/nota-reaction.model.ts` | model | CRUD | No existing "toggle reaction" table/model exists anywhere in the repo (team-chat has no reactions). Design as `(notaId OR replyId, userId, emoji)` with a unique constraint on `(target, userId, emoji)` to make toggle idempotent; no repo precedent to copy, use RESEARCH's own composition guidance. |
| `api-ventago/src/app/notas/models/nota-edit-history.model.ts` | model | append-only | No "edit history snapshot" table precedent exists (closest philosophical analog is `stocks`' append-only-ledger *principle* from CLAUDE.md, but that is a financial ledger, not a text-revision table — do not literally copy its trigger-based immutability, just the append-only spirit: insert-before-update, never mutate history rows). |
| `ventago-app/src/views/notas/NotasView.tsx` (list+detail split layout) | component | request-response | No MUI two-column inbox/list+detail split exists elsewhere in `ventago-app/src/views/`. Sketch `.planning/sketches/notas-compartidas.html` (§`.split` CSS + `render()`/`detail()`/`card()` JS, lines 76-336) is the literal, user-approved reference implementation — treat it as the primary source, not a "nice to have" mockup. |

## Metadata

**Analog search scope:** `api-ventago/src/app/team-chat/`, `api-ventago/src/app/box/`,
`api-ventago/src/app/expense-categories/`, `api-ventago/src/app/attendance/`,
`api-ventago/src/common/{minio,socket,pagination}/`, `api-ventago/src/app/auth/decorators/`,
`api-ventago/migrations/*.sql`, `api-ventago/src/app.module.ts`,
`ventago-app/src/{pages,views,hooks/api,components/team-chat,components/notas,
navigation,@core/layouts,layouts,realtime}`
**Files scanned:** ~35 read in full or in relevant excerpt; ~15 more located via grep/glob
and not opened (out of scope for this pattern map — team-chat/box/expense-categories were
the representative analogs for their respective shapes)
**Pattern extraction date:** 2026-09-28

## PATTERN MAPPING COMPLETE

**Phase:** 96 - Notas compartidas del local
**Files classified:** 24
**Analogs found:** 22 / 24

### Coverage
- Files with exact analog: 8 (seed migration, DDL migration, module registration, app.module.ts edit, jest harness, page, unread-count hook, list hook)
- Files with role-match/partial analog: 13 (models, DTOs, service, controllers, toast/global-listener, badge injection)
- Files with no analog: 3 (nota-reaction model, nota-edit-history model, two-column split view — all three use the sketch and/or RESEARCH's own composition guidance as the reference instead)

### Key Patterns Identified
- Every backend piece should mirror `team-chat` module shape (model/service/controller/module), but the visibility predicate (`Op.or` sender/audience-all/recipient-EXISTS) is a **new, mandatory addition** team-chat does not need — this is the single highest-risk composition point (D-05).
- Seed-before-code deploy ordering is non-negotiable: copy `2026-09-27-e-modulo-impresoras.sql` structure exactly, including the `NOT EXISTS`/`ON CONFLICT` idempotency guards from `2026-09-24-phase93-p5-seed-herramientas.sql` for the 4 global roles.
- Attachments must NEVER go through the public `/minio/:filename` route — path-prefix the keys and build a new `@Auth()`-gated, visibility-checked streaming endpoint modeled on `minio.controller.ts`'s structure but with inverted auth semantics.
- The sidebar badge (`badgeContent`) has zero existing producers — Notas is the first, and the unread count must be threaded through `useNavigation()`'s explicit dependency array (not ambient global state) to avoid uncontrolled nav-tree re-renders.
- The approved sketch (`.planning/sketches/notas-compartidas.html`) is the literal UI/logic spec for the two-column split, unread computation, and tab/sort behavior — its JS functions (`isUnread`, `list`, `card`, `detail`) should be read directly and ported (pure logic to `.ts`, not `.tsx`, for testability) rather than re-derived from prose.

### File Created
`/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.planning/phases/96-notas-compartidas-del-local/96-PATTERNS.md`

### Ready for Planning
Pattern mapping complete. Planner can now reference analog patterns in PLAN.md files.
