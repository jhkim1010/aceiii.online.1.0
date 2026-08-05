# Customer WhatsApp + CRM Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated `whatsapp` phone column to `clients` (and the canonical `global_clients` mirror) so that the existing Phase 29 Wave B Click-to-Chat flow targets the customer's WhatsApp number — independent of `phone`. Strict mode: no fallback. Existing customers backfilled once from `phone` at migration time.

**Architecture:** Add `whatsapp varchar` to `clients` + `global_clients`; propagate through Sequelize models, DTOs, and `ClientsSyncService.syncFromLegacy`. Rewire `ClickToChatService.buildLink` to read `client.whatsapp` and throw `WHATSAPP_NOT_REGISTERED` (422) / `INVALID_WHATSAPP_NUMBER` (422) when missing or unnormalizable. Surface as a new optional form field with an "Igual que teléfono" mirror checkbox and a default-visible list column on the existing customer views.

**Tech Stack:** PostgreSQL (PG10 prod / PG15 docker dev), NestJS 11 + Sequelize (`underscored: true`), Next.js 13 Pages Router + Material-UI, Jest specs.

**Spec reference:** [docs/superpowers/specs/2026-05-14-client-whatsapp-crm-design.md](../specs/2026-05-14-client-whatsapp-crm-design.md)

---

## File touch summary

Backend:
- Create: `api-ventago/migrations/phase29-wave-c-client-whatsapp.sql`
- Modify: `api-ventago/src/app/clients/clients.model.ts`
- Modify: `api-ventago/src/app/clients/dto/create-clients.dto.ts`
- Modify: `api-ventago/src/app/global-clients/global-clients.model.ts`
- Modify: `api-ventago/src/app/global-clients/dto/create-global-client.dto.ts`
- Modify: `api-ventago/src/app/shared/clients-sync/clients-sync.service.ts`
- Modify: `api-ventago/src/app/whatsapp/services/click-to-chat.service.ts`
- Modify: `api-ventago/src/app/clients/clients-create-with-store-link.spec.ts`
- Create: `api-ventago/src/app/whatsapp/services/click-to-chat.whatsapp.spec.ts`

Frontend:
- Modify: `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx`
- Modify: `ventago-app/src/views/clientes-globales/GlobalClientesView.tsx`
- Modify: `ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx`

Intel (auto-regenerated):
- Modify: `.planning/intel/db-schema-tables.md`

---

## Task 1: DB migration — add `whatsapp` columns + backfill from `phone`

**Files:**
- Create: `api-ventago/migrations/phase29-wave-c-client-whatsapp.sql`
- Modify (after running): `.planning/intel/db-schema-tables.md`

- [ ] **Step 1: Write the migration SQL**

Create `api-ventago/migrations/phase29-wave-c-client-whatsapp.sql` with this exact content:

```sql
-- Phase 29 Wave C — clients.whatsapp + global_clients.whatsapp
-- 운영(PG10) / 로컬 dev(PG15) 모두 호환. 재실행 무해 (IF NOT EXISTS + WHERE 필터).

BEGIN;

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS whatsapp varchar(255);

ALTER TABLE global_clients
  ADD COLUMN IF NOT EXISTS whatsapp varchar(100);

-- 기존 phone 값을 whatsapp 으로 1회성 backfill.
-- whatsapp IS NULL 조건으로 재실행 시 no-op 보장.
UPDATE clients
   SET whatsapp = phone
 WHERE whatsapp IS NULL
   AND phone IS NOT NULL
   AND TRIM(phone) <> '';

UPDATE global_clients
   SET whatsapp = phone
 WHERE whatsapp IS NULL
   AND phone IS NOT NULL
   AND TRIM(phone) <> '';

COMMIT;
```

- [ ] **Step 2: Run migration on local dev DB**

Local dev DB lives in the `dbpostgres` Docker container per CLAUDE.md. Use the documented `docker exec` path:

```bash
docker exec -i dbpostgres psql -U coolsistema -d ventago < api-ventago/migrations/phase29-wave-c-client-whatsapp.sql
```

Expected output (BEGIN / ALTER TABLE / UPDATE rows / COMMIT lines). No errors.

- [ ] **Step 3: Verify columns + backfill row counts**

```bash
docker exec -i dbpostgres psql -U coolsistema -d ventago -c "
  SELECT
    (SELECT COUNT(*) FROM clients WHERE whatsapp IS NOT NULL) AS clients_with_whatsapp,
    (SELECT COUNT(*) FROM clients WHERE phone IS NOT NULL AND TRIM(phone) <> '') AS clients_with_phone,
    (SELECT COUNT(*) FROM global_clients WHERE whatsapp IS NOT NULL) AS global_with_whatsapp,
    (SELECT COUNT(*) FROM global_clients WHERE phone IS NOT NULL AND TRIM(phone) <> '') AS global_with_phone;
"
```

Expected: `clients_with_whatsapp == clients_with_phone` and `global_with_whatsapp == global_with_phone` (exact equality — every non-blank phone was copied).

- [ ] **Step 4: Regenerate schema intel files**

```bash
./.planning/intel/db-schema.regen.sh
```

Verify the diff in `.planning/intel/db-schema-tables.md` shows `whatsapp` added to both `clients` and `global_clients` sections.

- [ ] **Step 5: Commit migration + intel**

```bash
git add api-ventago/migrations/phase29-wave-c-client-whatsapp.sql .planning/intel/db-schema-tables.md .planning/intel/db-schema-fks.md
git commit -m "feat(db): phase 29 wave C — clients.whatsapp + global_clients.whatsapp

- ADD COLUMN whatsapp (clients varchar(255), global_clients varchar(100))
- One-time backfill: UPDATE ... SET whatsapp = phone WHERE phone <> ''
- Idempotent (IF NOT EXISTS + WHERE whatsapp IS NULL)
- PG10/PG15 compatible

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Sequelize models — `Clients.whatsapp` + `GlobalClient.whatsapp`

**Files:**
- Modify: `api-ventago/src/app/clients/clients.model.ts`
- Modify: `api-ventago/src/app/global-clients/global-clients.model.ts`

- [ ] **Step 1: Add `whatsapp` column to `Clients` model**

In `api-ventago/src/app/clients/clients.model.ts`, locate the `phone` column declaration (currently lines 43-44):

```ts
  @Column
  phone: string;
```

Insert **immediately after** the `phone` block, separated by a blank line (ESLint `lines-around-comment` requires it):

```ts

  // Phase 29 Wave C — CRM (Click-to-Chat) 의 wa.me 대상 번호. phone 과 별개 관리.
  // 비어 있으면 WhatsApp 발송 버튼 비활성화 (strict — fallback 없음).
  // Sequelize 전역 underscored:true → DB 컬럼은 snake_case (whatsapp).
  @Column
  whatsapp: string;
```

- [ ] **Step 2: Add `whatsapp` column to `GlobalClient` model**

In `api-ventago/src/app/global-clients/global-clients.model.ts`, locate the existing `phone` column (lines 47-49):

```ts
  // 전화번호
  @Column({ type: DataType.STRING(50), allowNull: true })
  phone?: string;
```

Insert **immediately after** the `phone` block:

```ts

  // Phase 29 Wave C — CRM 발송 대상 WhatsApp 번호 (phone 과 별개 관리)
  @Column({ type: DataType.STRING(100), allowNull: true })
  whatsapp?: string;
```

(Width 100 matches the DB column declared in the migration — DB stays the source of truth.)

- [ ] **Step 3: Run TypeScript compiler check**

```bash
cd api-ventago && npx tsc --noEmit
```

Expected: PASS (no new errors). If a type error surfaces from existing code that consumes `Clients`/`GlobalClient`, leave it — Task 4 will reconcile via `SyncableClient`.

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/clients/clients.model.ts api-ventago/src/app/global-clients/global-clients.model.ts
git commit -m "feat(api): add whatsapp column to Clients + GlobalClient models

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: DTOs — accept optional `whatsapp` on create

**Files:**
- Modify: `api-ventago/src/app/clients/dto/create-clients.dto.ts`
- Modify: `api-ventago/src/app/global-clients/dto/create-global-client.dto.ts`

- [ ] **Step 1: Add `whatsapp` to `CreateClientsDto`**

In `api-ventago/src/app/clients/dto/create-clients.dto.ts`, locate the existing `phone` field (lines 35-37):

```ts
  @IsString({ message: 'El teléfono debe ser una cadena de texto' })
  @IsOptional()
  readonly phone?: string;
```

Insert **immediately after**, blank line separator:

```ts

  @IsString({ message: 'El WhatsApp debe ser una cadena de texto' })
  @IsOptional()
  readonly whatsapp?: string;
```

- [ ] **Step 2: Add `whatsapp` to `CreateGlobalClientDto`**

In `api-ventago/src/app/global-clients/dto/create-global-client.dto.ts`, locate the existing `phone` field (lines 46-49):

```ts
  // 전화번호 - 선택
  @IsString({ message: '전화번호는 문자열이어야 합니다' })
  @IsOptional()
  readonly phone?: string;
```

Insert **immediately after**, blank line separator:

```ts

  // Phase 29 Wave C — CRM 발송 대상 WhatsApp 번호 - 선택
  @IsString({ message: 'WhatsApp 번호는 문자열이어야 합니다' })
  @IsOptional()
  readonly whatsapp?: string;
```

- [ ] **Step 3: TypeScript compile check**

```bash
cd api-ventago && npx tsc --noEmit
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/clients/dto/create-clients.dto.ts api-ventago/src/app/global-clients/dto/create-global-client.dto.ts
git commit -m "feat(api): accept optional whatsapp in client/global-client create DTOs

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `ClientsSyncService` — propagate `whatsapp` to `global_clients`

**Files:**
- Modify: `api-ventago/src/app/shared/clients-sync/clients-sync.service.ts`

- [ ] **Step 1: Extend `SyncableClient` interface**

In `api-ventago/src/app/shared/clients-sync/clients-sync.service.ts`, locate the `SyncableClient` interface (lines 34-47). Modify it by adding `whatsapp` immediately after `phone`:

```ts
export interface SyncableClient {
  id: number;
  storeId: number;
  document: string | null;
  fullname?: string | null;
  email?: string | null;
  phone?: string | null;
  whatsapp?: string | null;
  address?: string | null;
  location?: string | null;
  provinceId?: number | null;
  transport?: string | null;
  resIva?: string | null;
  nameFantasy?: string | null;
}
```

- [ ] **Step 2: Propagate `whatsapp` in `findOrCreate` defaults**

Locate the `globalClientModel.findOrCreate` call around line 140-158. The `defaults` block currently includes `phone: legacy.phone ?? null,`. Add `whatsapp` immediately after:

```ts
    const [gc, gcCreated] = await this.globalClientModel.findOrCreate({
      where: { ownerGroupId, document: doc } as any,
      defaults: {
        ownerGroupId,
        document: doc,
        fullname: legacy.fullname ?? null,
        nameFantasy: legacy.nameFantasy ?? null,
        email: legacy.email ?? null,
        phone: legacy.phone ?? null,
        whatsapp: legacy.whatsapp ?? null,
        address: legacy.address ?? null,
        location: legacy.location ?? null,
        provinceId: legacy.provinceId ?? null,
        transport: legacy.transport ?? null,
        resIva: legacy.resIva ?? null,
        createdByStoreId: legacy.storeId,
        isActive: true,
      } as any,
      transaction,
    });
```

- [ ] **Step 3: TypeScript compile check**

```bash
cd api-ventago && npx tsc --noEmit
```

Expected: PASS. The `Clients` model now has `whatsapp: string` (Task 2), so the AfterCreate hook's `instance as unknown as SyncableClient` cast remains valid.

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/shared/clients-sync/clients-sync.service.ts
git commit -m "feat(api): propagate clients.whatsapp through ClientsSyncService to global_clients

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `ClickToChatService` — switch recipient to `client.whatsapp` (TDD)

**Files:**
- Modify: `api-ventago/src/app/whatsapp/services/click-to-chat.service.ts`
- Create: `api-ventago/src/app/whatsapp/services/click-to-chat.whatsapp.spec.ts`

- [ ] **Step 1: Write the failing test**

Create `api-ventago/src/app/whatsapp/services/click-to-chat.whatsapp.spec.ts` with this exact content:

```ts
import { Test, TestingModule } from '@nestjs/testing';
import { getModelToken } from '@nestjs/sequelize';
import { UnprocessableEntityException } from '@nestjs/common';

import { ClickToChatService } from './click-to-chat.service';
import { PhoneNormalizerService } from './phone-normalizer.service';
import { Store } from '../../store/store.model';
import { Clients } from '../../clients/clients.model';
import { Users } from '../../users/users.model';
import { WhatsAppMessage } from '../whatsapp-message.model';

/**
 * Phase 29 Wave C — Click-to-Chat 대상이 client.whatsapp 으로 전환되었음을 검증.
 * Strict 모드 (fallback 없음).
 */
describe('ClickToChatService — whatsapp recipient (Phase 29 Wave C)', () => {
  let service: ClickToChatService;
  let clientModel: { findOne: jest.Mock };
  let storeModel: { findByPk: jest.Mock };
  let messageModel: { create: jest.Mock };

  const buildStoreFixture = () => ({
    id: 9,
    name: 'ACE',
    representative: {
      id: 42,
      fullname: 'Admin',
      whatsappPhone: '+5491111111111',
    },
  });

  const buildClientFixture = (overrides: Partial<{
    phone: string | null;
    whatsapp: string | null;
  }> = {}) => ({
    id: 100,
    storeId: 9,
    fullname: 'Cliente Test',
    phone: '+5491100000000',
    whatsapp: '+5491122222222',
    ...overrides,
  });

  beforeEach(async () => {
    clientModel = { findOne: jest.fn() };
    storeModel = { findByPk: jest.fn() };
    messageModel = { create: jest.fn().mockResolvedValue({ id: 1 }) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ClickToChatService,
        PhoneNormalizerService,
        { provide: getModelToken(Store), useValue: storeModel },
        { provide: getModelToken(Clients), useValue: clientModel },
        { provide: getModelToken(Users), useValue: { findByPk: jest.fn() } },
        { provide: getModelToken(WhatsAppMessage), useValue: messageModel },
      ],
    }).compile();

    service = module.get(ClickToChatService);
  });

  it('throws WHATSAPP_NOT_REGISTERED when client.whatsapp is null', async () => {
    storeModel.findByPk.mockResolvedValue(buildStoreFixture());
    clientModel.findOne.mockResolvedValue(buildClientFixture({ whatsapp: null }));

    await expect(
      service.buildLink({
        storeId: 9,
        clientId: 100,
        templateKey: 'general_hello',
        variables: {},
        triggeredByUserId: 1,
      }),
    ).rejects.toMatchObject({
      response: { errorCode: 'WHATSAPP_NOT_REGISTERED' },
    });
    expect(messageModel.create).not.toHaveBeenCalled();
  });

  it('throws WHATSAPP_NOT_REGISTERED when client.whatsapp is blank string', async () => {
    storeModel.findByPk.mockResolvedValue(buildStoreFixture());
    clientModel.findOne.mockResolvedValue(buildClientFixture({ whatsapp: '   ' }));

    await expect(
      service.buildLink({
        storeId: 9,
        clientId: 100,
        templateKey: 'general_hello',
        variables: {},
        triggeredByUserId: 1,
      }),
    ).rejects.toMatchObject({
      response: { errorCode: 'WHATSAPP_NOT_REGISTERED' },
    });
  });

  it('does NOT fall back to client.phone when whatsapp is missing', async () => {
    storeModel.findByPk.mockResolvedValue(buildStoreFixture());
    clientModel.findOne.mockResolvedValue(
      buildClientFixture({ whatsapp: null, phone: '+5491100000000' }),
    );

    await expect(
      service.buildLink({
        storeId: 9,
        clientId: 100,
        templateKey: 'general_hello',
        variables: {},
        triggeredByUserId: 1,
      }),
    ).rejects.toThrow(UnprocessableEntityException);
  });

  it('uses client.whatsapp (not client.phone) for the wa.me link when valid', async () => {
    storeModel.findByPk.mockResolvedValue(buildStoreFixture());
    clientModel.findOne.mockResolvedValue(
      buildClientFixture({
        whatsapp: '+5491122222222',
        phone: '+5491100000000',
      }),
    );

    const result = await service.buildLink({
      storeId: 9,
      clientId: 100,
      templateKey: 'general_hello',
      variables: {},
      triggeredByUserId: 1,
    });

    expect(result.url).toContain('5491122222222');
    expect(result.url).not.toContain('5491100000000');
    expect(result.client.phone).toBe('+5491122222222');
    expect(messageModel.create).toHaveBeenCalled();
  });

  it('throws INVALID_WHATSAPP_NUMBER when whatsapp cannot be normalized', async () => {
    storeModel.findByPk.mockResolvedValue(buildStoreFixture());
    clientModel.findOne.mockResolvedValue(
      buildClientFixture({ whatsapp: 'not-a-phone' }),
    );

    await expect(
      service.buildLink({
        storeId: 9,
        clientId: 100,
        templateKey: 'general_hello',
        variables: {},
        triggeredByUserId: 1,
      }),
    ).rejects.toMatchObject({
      response: { errorCode: 'INVALID_WHATSAPP_NUMBER' },
    });
  });
});
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd api-ventago && npx jest src/app/whatsapp/services/click-to-chat.whatsapp.spec.ts
```

Expected: All five tests FAIL with `INVALID_CLIENT_PHONE` (current behavior) or because `client.whatsapp` is not yet consulted. This confirms the test is exercising the change surface.

- [ ] **Step 3: Update `ClickToChatService.buildLink` to read `whatsapp` (strict, no fallback)**

In `api-ventago/src/app/whatsapp/services/click-to-chat.service.ts`:

First, update the import at the top of the file. Find the existing NestJS imports and ensure `UnprocessableEntityException` is included alongside `BadRequestException`:

```ts
import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
```

(Adjust to the actual existing import shape — add `UnprocessableEntityException` only.)

Then locate lines 104-113 of `buildLink`:

```ts
    // 3. 손님 조회 + 번호 정규화
    const client = await this.fetchClient(input.clientId, input.storeId);
    const normalized = this.phoneNormalizer.normalize(client.phone);

    if (!normalized.isValid) {
      throw new BadRequestException({
        errorCode: 'INVALID_CLIENT_PHONE',
        message: `손님 (${client.fullname}) 의 전화번호가 유효하지 않습니다.`,
      });
    }
```

Replace with:

```ts
    // 3. 손님 조회 + WhatsApp 번호 정규화 (Phase 29 Wave C — strict, fallback 없음)
    const client = await this.fetchClient(input.clientId, input.storeId);

    if (!client.whatsapp || client.whatsapp.trim() === '') {
      throw new UnprocessableEntityException({
        errorCode: 'WHATSAPP_NOT_REGISTERED',
        message: `손님 (${client.fullname}) 에 WhatsApp 번호가 등록되어 있지 않습니다.`,
      });
    }

    const normalized = this.phoneNormalizer.normalize(client.whatsapp);

    if (!normalized.isValid) {
      throw new UnprocessableEntityException({
        errorCode: 'INVALID_WHATSAPP_NUMBER',
        message: `손님 (${client.fullname}) 의 WhatsApp 번호 형식이 유효하지 않습니다.`,
      });
    }
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
cd api-ventago && npx jest src/app/whatsapp/services/click-to-chat.whatsapp.spec.ts
```

Expected: All five tests PASS.

- [ ] **Step 5: Run the existing Click-to-Chat tests to confirm no regression**

```bash
cd api-ventago && npx jest src/app/whatsapp
```

Expected: PASS. If pre-existing tests referenced `INVALID_CLIENT_PHONE`, update those tests to expect `WHATSAPP_NOT_REGISTERED` / `INVALID_WHATSAPP_NUMBER` (the error code is renamed; fixtures must seed `whatsapp` instead of `phone`).

- [ ] **Step 6: Commit**

```bash
git add api-ventago/src/app/whatsapp/services/click-to-chat.service.ts api-ventago/src/app/whatsapp/services/click-to-chat.whatsapp.spec.ts
git commit -m "feat(api): Click-to-Chat targets client.whatsapp (strict, no fallback)

- Throw WHATSAPP_NOT_REGISTERED (422) when whatsapp missing or blank
- Throw INVALID_WHATSAPP_NUMBER (422) when whatsapp present but unnormalizable
- Remove INVALID_CLIENT_PHONE code (replaced by the two above)
- Five new specs covering null / blank / valid / invalid / no-fallback paths

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Update existing clients sync spec to seed `whatsapp`

**Files:**
- Modify: `api-ventago/src/app/clients/clients-create-with-store-link.spec.ts`

- [ ] **Step 1: Locate phone fixtures**

Open `api-ventago/src/app/clients/clients-create-with-store-link.spec.ts` and search for `phone:` literals (every place a `Clients.create` fixture is built):

```bash
grep -n "phone:" api-ventago/src/app/clients/clients-create-with-store-link.spec.ts
```

- [ ] **Step 2: Add a new test case for `whatsapp` propagation**

Append the following test block to the existing `describe(...)` in the file (place it before the closing `});` of the outer describe):

```ts
  // Phase 29 Wave C — whatsapp 필드가 sync 를 통해 global_clients 로 전파되는지 검증.
  it('propagates whatsapp from legacy Clients to global_clients on create', async () => {
    const phone = '+5491100000000';
    const whatsapp = '+5491122222222';

    const created = await Clients.create({
      storeId: testStoreId,
      document: '20111111111',
      fullname: 'WA Test',
      phone,
      whatsapp,
    } as any);

    const gc = await GlobalClient.findOne({
      where: { document: '20111111111' },
    });

    expect(gc).not.toBeNull();
    expect(gc?.phone).toBe(phone);
    expect(gc?.whatsapp).toBe(whatsapp);
    expect(created.whatsapp).toBe(whatsapp);
  });
```

(If `GlobalClient` is not yet imported in this spec, add `import { GlobalClient } from '../global-clients/global-clients.model';` at the top with the existing imports.)

- [ ] **Step 3: Run the spec**

```bash
cd api-ventago && npx jest src/app/clients/clients-create-with-store-link.spec.ts
```

Expected: All tests PASS (existing tests unaffected since `whatsapp` is optional; new test asserts the round-trip).

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/clients/clients-create-with-store-link.spec.ts
git commit -m "test(api): verify whatsapp propagates from Clients to global_clients

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Frontend — extend `WhatsAppSendDialog` to gate on `whatsapp`

**Files:**
- Modify: `ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx`

- [ ] **Step 1: Extend the dialog props interface**

In `ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx` lines 51-58, the current interface is:

```ts
export interface WhatsAppSendDialogProps {
  open: boolean
  onClose: () => void
  client: {
    id: number
    fullname: string
    phone?: string | null
  }

  onSent?: (logId: number | null) => void
}
```

Add `whatsapp?: string | null` immediately after `phone`:

```ts
export interface WhatsAppSendDialogProps {
  open: boolean
  onClose: () => void
  client: {
    id: number
    fullname: string
    phone?: string | null
    whatsapp?: string | null
  }

  onSent?: (logId: number | null) => void
}
```

- [ ] **Step 2: Update the title subtitle (line 240)**

The current line reads:

```tsx
              {client.phone ? ` · ${client.phone}` : ''}
```

Change to:

```tsx
              {client.whatsapp ? ` · ${client.whatsapp}` : ''}
```

- [ ] **Step 3: Replace the empty-state warning (lines 262-267)**

Current code:

```tsx
        {/* 손님 정보 + 전화번호 없음 경고 */}
        {!client.phone && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            손님의 전화번호가 등록되지 않았습니다. 발송이 실패할 수 있습니다.
          </Alert>
        )}
```

Replace with (strict — also blocks send via `isReadyToSend` next step):

```tsx
        {/* Phase 29 Wave C — whatsapp 미등록 시 발송 차단 + 안내 */}
        {!client.whatsapp && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            Este cliente no tiene un número de WhatsApp registrado.
            Edite los datos del cliente para agregarlo.
          </Alert>
        )}
```

- [ ] **Step 4: Gate `isReadyToSend` on `client.whatsapp`**

Locate the `isReadyToSend` `useMemo` (lines 122-129):

```tsx
  const isReadyToSend = useMemo(() => {
    if (!selectedTemplate) return false
    if (sending) return false

    return userInputVariables.every(
      (v) => variables[v] && variables[v].trim() !== '',
    )
  }, [selectedTemplate, userInputVariables, variables, sending])
```

Replace with:

```tsx
  const isReadyToSend = useMemo(() => {
    if (!selectedTemplate) return false
    if (sending) return false
    if (!client.whatsapp || client.whatsapp.trim() === '') return false

    return userInputVariables.every(
      (v) => variables[v] && variables[v].trim() !== '',
    )
  }, [selectedTemplate, userInputVariables, variables, sending, client.whatsapp])
```

- [ ] **Step 5: Add `WHATSAPP_NOT_REGISTERED` / `INVALID_WHATSAPP_NUMBER` error handling in `handleSend`**

Locate the `catch` branch of `handleSend` (it currently calls `toast.error(...)` with a generic message). Right before the generic fallback, add:

```tsx
      const errorCode = err?.response?.data?.errorCode
      if (errorCode === 'WHATSAPP_NOT_REGISTERED') {
        toast.error('Este cliente no tiene un número de WhatsApp registrado. Edite los datos del cliente para agregarlo.')

        return
      }
      if (errorCode === 'INVALID_WHATSAPP_NUMBER') {
        toast.error('El formato del número de WhatsApp del cliente no es válido.')

        return
      }
```

(If the existing `catch` block already extracts `err.response.data.errorCode`, reuse it; otherwise grab it inline as above. Match the project pattern of `toast` from `react-toastify` already imported at line 42. The blank line before each `return` satisfies `newline-before-return`.)

- [ ] **Step 6: Run ESLint on the file**

```bash
cd ventago-app && npx eslint src/views/whatsapp/WhatsAppSendDialog.tsx
```

Expected: 0 errors, 0 warnings.

- [ ] **Step 7: Commit**

```bash
git add ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx
git commit -m "feat(app): gate WhatsAppSendDialog on client.whatsapp (strict)

- Add whatsapp to client prop interface
- Show subtitle / empty-state warning based on whatsapp (not phone)
- Disable send button when whatsapp missing/blank
- Handle WHATSAPP_NOT_REGISTERED / INVALID_WHATSAPP_NUMBER errors

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Frontend — `ClienteVistaView` (form + column + actions + dialog payload)

**Files:**
- Modify: `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx`

- [ ] **Step 1: Add `whatsapp` to local `Client` type (line ~27)**

Find the local interface that declares `phone: string` (around line 27). Add `whatsapp?: string | null` immediately after:

```ts
  phone: string
  whatsapp?: string | null
```

Repeat for the secondary type around line 43 (`phone: string` again — likely the form-state type).

- [ ] **Step 2: Add `whatsapp` to the empty form state (line ~54)**

The current line reads:

```ts
fullname: '', document: '', email: '', phone: '',
```

Change to:

```ts
fullname: '', document: '', email: '', phone: '', whatsapp: '',
```

- [ ] **Step 3: Populate `whatsapp` from the row when opening edit dialog (line ~182)**

The current code is:

```ts
      phone: client.phone || '',
```

Add **immediately after** that line:

```ts
      whatsapp: client.whatsapp || '',
```

- [ ] **Step 4: Add `whatsapp` column to the DataGrid (after line 267)**

Current column definitions include phone at lines 262-267:

```ts
    {
      field: 'phone',
      headerName: 'Teléfono',
      flex: 1,
      minWidth: 120,
    },
```

Insert a new column **immediately after** the `phone` block:

```ts
    {
      field: 'whatsapp',
      headerName: 'WhatsApp',
      flex: 1,
      minWidth: 120,
      renderCell: (params) => (
        <Typography
          variant="body2"
          sx={{ color: params.value ? 'text.primary' : 'text.disabled' }}
        >
          {params.value || '—'}
        </Typography>
      ),
    },
```

- [ ] **Step 5: Switch the Actions Click-to-Chat gate to `whatsapp` (lines 305-328)**

Current code uses `params.row.phone`. Replace all four occurrences inside the WhatsApp `<Tooltip>` + `<IconButton>` block (lines 305-328):

```tsx
          {/* Phase 29 Wave C — WhatsApp Click-to-Chat. whatsapp 미보유 시 비활성. */}
          <Tooltip
            title={
              params.row.whatsapp
                ? 'Enviar WhatsApp (link se abrirá con el número del admin)'
                : 'Sin WhatsApp registrado'
            }
          >
            <span>
              <IconButton
                size="small"
                disabled={!params.row.whatsapp || !params.row.isActive}
                onClick={(e) => {
                  e.stopPropagation()
                  openWhatsAppDialog(params.row)
                }}
                sx={{
                  color: params.row.whatsapp && params.row.isActive ? '#25d366' : 'action.disabled',
                }}
              >
                <Icon icon="mdi:whatsapp" />
              </IconButton>
            </span>
          </Tooltip>
```

- [ ] **Step 6: Pass `whatsapp` into the WhatsAppSendDialog payload (line ~649)**

Current code (lines 646-650):

```tsx
          client={{
            id: whatsappDialog.target.id,
            fullname: whatsappDialog.target.fullname,
            phone: whatsappDialog.target.phone,
          }}
```

Change to:

```tsx
          client={{
            id: whatsappDialog.target.id,
            fullname: whatsappDialog.target.fullname,
            phone: whatsappDialog.target.phone,
            whatsapp: whatsappDialog.target.whatsapp,
          }}
```

- [ ] **Step 7: Add the form field + "Igual que teléfono" checkbox (after line 580)**

Current code at lines 579-580 renders the phone CustomTextField:

```tsx
                  fullWidth label="Teléfono" value={form.phone}
                  onChange={handleFormChange('phone')}
```

Find the closing tag of that field (likely the next line after `onChange`). **Immediately after** the phone field's closing JSX element, add the WhatsApp field + checkbox. Use this exact pattern (adjust the wrapping Grid `<Grid item xs={12} md={6}>` to match the surrounding layout — read the 10 lines before/after the phone field to confirm the wrapper):

```tsx
                {/* Phase 29 Wave C — WhatsApp 입력 + phone 동일 체크박스 */}
                <Grid item xs={12} md={6}>
                  <CustomTextField
                    fullWidth
                    label="WhatsApp"
                    value={form.whatsapp}
                    onChange={handleFormChange('whatsapp')}
                    disabled={waSameAsPhone}
                  />
                  <FormControlLabel
                    sx={{ mt: 0.5 }}
                    control={
                      <Checkbox
                        size="small"
                        checked={waSameAsPhone}
                        onChange={(e) => {
                          const checked = e.target.checked
                          setWaSameAsPhone(checked)
                          if (checked) {
                            setForm((prev: any) => ({ ...prev, whatsapp: prev.phone }))
                          }
                        }}
                      />
                    }
                    label="Igual que teléfono"
                  />
                </Grid>
```

- [ ] **Step 8: Wire the `waSameAsPhone` state + mirror effect**

Near the top of the component (after the existing `useState` calls), add:

```tsx
  const [waSameAsPhone, setWaSameAsPhone] = useState(false)
```

Then add a `useEffect` that mirrors `form.phone` into `form.whatsapp` while the checkbox is checked:

```tsx
  // Phase 29 Wave C — "Igual que teléfono" 체크 시 phone 입력 변경 → whatsapp 자동 미러
  useEffect(() => {
    if (waSameAsPhone) {
      setForm((prev: any) => ({ ...prev, whatsapp: prev.phone }))
    }
  }, [waSameAsPhone, form.phone])
```

When opening an existing customer for edit (Step 3 above), determine the initial checkbox state from the loaded row. Add this line where you populate `whatsapp` (right after Step 3's insertion):

```ts
      // checkbox 초기 상태: 기존 데이터에서 phone == whatsapp 이면 동일로 간주
      setWaSameAsPhone(
        Boolean(client.phone && client.whatsapp && client.phone === client.whatsapp),
      )
```

Also reset to `false` when opening the **create** (new) dialog. Locate the function that resets `form` for a new customer and add `setWaSameAsPhone(false)` after the `setForm({...})` call.

Required imports to add at the top of the file:

```ts
import { Checkbox, FormControlLabel } from '@mui/material'
import { useEffect, useState } from 'react' // confirm both are already imported; add the missing one
```

- [ ] **Step 9: ESLint check**

```bash
cd ventago-app && npx eslint src/views/cliente-vista/ClienteVistaView.tsx
```

Expected: 0 errors, 0 warnings. Fix any `newline-before-return` / `lines-around-comment` violations inline.

- [ ] **Step 10: Commit**

```bash
git add ventago-app/src/views/cliente-vista/ClienteVistaView.tsx
git commit -m "feat(app): ClienteVistaView — whatsapp column, form field, dialog gate

- WhatsApp column (default-visible) between Teléfono and Email
- Form: independent WhatsApp input + 'Igual que teléfono' checkbox
- Actions: WhatsApp button gates on row.whatsapp (was row.phone)
- Pass whatsapp into WhatsAppSendDialog client prop

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Frontend — `GlobalClientesView` (same pattern, narrower scope)

**Files:**
- Modify: `ventago-app/src/views/clientes-globales/GlobalClientesView.tsx`

- [ ] **Step 1: Add `whatsapp` to the local Client type + form state**

Find lines 20, 38, 50 (per the earlier grep results). At each `phone: string` interface field, add a sibling `whatsapp?: string | null` (use the same pattern as `ClienteVistaView`). At the empty form initializer `fullname: '', document: '', email: '', phone: '',`, add `whatsapp: '',`.

- [ ] **Step 2: Populate `whatsapp` on edit-dialog open (line 155)**

The existing line reads:

```ts
      phone: client.phone || '',
```

Insert immediately after:

```ts
      whatsapp: client.whatsapp || '',
```

- [ ] **Step 3: Add the `whatsapp` column to the DataGrid (after line 242)**

The current `phone` column (lines 238-242) follows the same shape. Insert **immediately after** the phone column's closing brace + comma:

```ts
    {
      field: 'whatsapp',
      headerName: 'WhatsApp',
      flex: 1,
      minWidth: 120,
      renderCell: (params) => (
        <Typography
          variant="body2"
          sx={{ color: params.value ? 'text.primary' : 'text.disabled' }}
        >
          {params.value || '—'}
        </Typography>
      ),
    },
```

- [ ] **Step 4: Add the form field + checkbox (after line 471)**

Locate the phone CustomTextField block (lines 470-471):

```tsx
                  fullWidth label="Teléfono" value={form.phone}
                  onChange={handleFormChange('phone')}
```

Following the same template from Task 8 Step 7, insert the WhatsApp Grid block immediately after the phone field's wrapping `</Grid>` close. Read the 10 lines around line 471 first to confirm the wrapper component (likely `<Grid item ...>`); reuse the exact wrapper shape.

- [ ] **Step 5: Add the state hook + mirror effect (top of component)**

Mirror Task 8 Step 8 — add `waSameAsPhone` `useState`, the `useEffect`, and the checkbox initial-state line when opening edit. Required imports: `Checkbox`, `FormControlLabel`, `useEffect`.

- [ ] **Step 6: ESLint check**

```bash
cd ventago-app && npx eslint src/views/clientes-globales/GlobalClientesView.tsx
```

Expected: 0 errors, 0 warnings.

- [ ] **Step 7: Commit**

```bash
git add ventago-app/src/views/clientes-globales/GlobalClientesView.tsx
git commit -m "feat(app): GlobalClientesView — whatsapp column + form field + mirror checkbox

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: ESLint sweep (project-wide gate)

**Files:** none modified — verification only.

- [ ] **Step 1: Run ESLint on the full ventago-app**

```bash
cd ventago-app && npm run lint
```

Expected: 0 errors. If any error surfaces from the new code, fix inline (typically `newline-before-return` or `lines-around-comment`). Per project memory `feedback_eslint_check.md`, this gate is mandatory before any frontend merge.

- [ ] **Step 2: Run the api-ventago build to verify backend compile**

```bash
cd api-ventago && npm run build
```

Expected: 0 errors.

- [ ] **Step 3: Run the full backend test suite**

```bash
cd api-ventago && npx jest
```

Expected: All PASS. If a pre-existing test seeded `phone` and triggered Click-to-Chat, update the fixture to seed `whatsapp` too (the strict-mode change is the cause).

- [ ] **Step 4: If any fixtures needed updates, commit them**

```bash
git add -A
git commit -m "test(api): backfill whatsapp in existing fixtures touching Click-to-Chat

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Manual UAT (local dev stack)

**Files:** none — execution + observation.

- [ ] **Step 1: Start the dev stack**

```bash
./dev.sh
```

Wait for both `api-ventago` (port 5002) and `ventago-app` (port 3050) to log "ready".

- [ ] **Step 2: UAT scenario A — backfilled customer still works**

1. Log into `http://localhost:3050` as a store admin whose data was created before Wave C.
2. Navigate to **Clientes** (or **Clientes Globales** depending on which view the user lands on).
3. Confirm the **WhatsApp** column appears between **Teléfono** and **Email** and shows the same value as Teléfono (backfilled).
4. Click the green WhatsApp icon → `WhatsAppSendDialog` opens.
5. Select a template, fill required variables, click **Enviar**.
6. A new tab opens to `https://wa.me/<number>?text=...` with the correct customer number.

Pass criteria: link generated successfully, no error toast.

- [ ] **Step 3: UAT scenario B — new customer without WhatsApp blocks send**

1. Click **Nuevo cliente** / **+**, fill required fields (fullname, document, address, provinceId, phone) but **leave WhatsApp empty**.
2. Save the customer.
3. From the list, click the green WhatsApp icon.
4. Dialog opens with a yellow Alert: *"Este cliente no tiene un número de WhatsApp registrado. Edite los datos del cliente para agregarlo."*
5. The **Enviar** button is disabled.

Pass criteria: Alert visible, button disabled, no link generated.

- [ ] **Step 4: UAT scenario C — add WhatsApp, send succeeds**

1. Edit the customer from Scenario B.
2. Enter a valid WhatsApp number (e.g. `+5491133333333`).
3. Save.
4. Reopen the WhatsApp dialog → Alert is gone, **Enviar** is enabled, link generates.

Pass criteria: end-to-end send works.

- [ ] **Step 5: UAT scenario D — "Igual que teléfono" checkbox**

1. Open the edit dialog for any customer.
2. Check **Igual que teléfono** → WhatsApp input becomes disabled and shows the phone value.
3. Edit the **Teléfono** field — WhatsApp mirrors live.
4. Uncheck → WhatsApp becomes editable again, last mirrored value retained.

Pass criteria: mirror behaviour matches description.

- [ ] **Step 6: Record UAT results**

If all four scenarios pass, proceed to Task 12. If any fail, fix the offending task and re-run the affected scenario.

---

## Task 12: Production rollout — checklist + user confirmation

**Files:** none — operational steps. Per CLAUDE.md, all DDL on production **requires user confirmation** before execution.

- [ ] **Step 1: Show the migration SQL to the user for explicit confirmation**

Display the contents of `api-ventago/migrations/phase29-wave-c-client-whatsapp.sql` and confirm with the user before running on production:

> "Production migration ready. This will:
> - ADD COLUMN `whatsapp varchar(255)` to `clients`
> - ADD COLUMN `whatsapp varchar(100)` to `global_clients`
> - UPDATE both tables: `SET whatsapp = phone WHERE phone IS NOT NULL`
>
> Estimated row impact: roughly `clients.phone NOT NULL` row count across all stores (CART, coolsistema, genius, ACE). Confirm to proceed?"

Wait for user "yes" / "proceed" before continuing.

- [ ] **Step 2: Run migration on production (after user confirms)**

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/phase29-wave-c-client-whatsapp.sql
```

Expected output: `BEGIN / ALTER TABLE x2 / UPDATE n rows x2 / COMMIT`.

- [ ] **Step 3: Verify on production**

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"
  SELECT
    (SELECT COUNT(*) FROM clients WHERE whatsapp IS NOT NULL) AS clients_with_whatsapp,
    (SELECT COUNT(*) FROM clients WHERE phone IS NOT NULL AND TRIM(phone) <> '') AS clients_with_phone,
    (SELECT COUNT(*) FROM global_clients WHERE whatsapp IS NOT NULL) AS global_with_whatsapp,
    (SELECT COUNT(*) FROM global_clients WHERE phone IS NOT NULL AND TRIM(phone) <> '') AS global_with_phone;
\""
```

Expected: `clients_with_whatsapp == clients_with_phone` and `global_with_whatsapp == global_with_phone`.

- [ ] **Step 4: Push code via the standard pipeline**

```bash
./push-both.sh
```

This pushes both `api-ventago` and `ventago-app` to GitHub, triggers Jenkins build (`api-coolsistema` + `front-coolsistema`), which deploys to srv803182:5002 / app.coolsistema.com.

- [ ] **Step 5: Smoke-test production**

1. Open `https://app.coolsistema.com`, log in as an existing store admin.
2. Go to Clientes → verify WhatsApp column visible.
3. Click the green WhatsApp icon on a customer with backfilled WhatsApp → `WhatsAppSendDialog` opens.
4. Cancel without sending.

Pass criteria: page renders without error, dialog opens, no console errors.

- [ ] **Step 6: Watch logs for 5 minutes**

```bash
ssh jhkim-server "sudo docker logs -f api_ventago --tail 50"
```

Expected: no new `WHATSAPP_NOT_REGISTERED` 422 spike beyond the rate naturally caused by customers without WhatsApp on file. If the spike is unexpectedly high, the backfill may have missed rows — investigate with a fresh `SELECT COUNT(*) WHERE whatsapp IS NULL AND phone IS NOT NULL` on production.

---

## Self-review notes (filed during plan authoring)

- **Spec coverage:**
  - DB migration → Task 1
  - clients/global_clients models → Task 2
  - DTOs → Task 3
  - ClientsSyncService → Task 4
  - ClickToChatService + tests → Task 5
  - existing sync spec → Task 6
  - WhatsAppSendDialog → Task 7
  - ClienteVistaView (form + list + actions + dialog payload) → Task 8
  - GlobalClientesView → Task 9
  - ESLint + build + tests gate → Task 10
  - Manual UAT scenarios A-D → Task 11
  - Production rollout → Task 12

- **Placeholders:** None. The wrapping `<Grid item>` for the new WhatsApp form field is described as "match the surrounding layout — read the 10 lines before/after the phone field to confirm" because the Grid container shape is short and trivially observable in the source; this is a 30-second confirmation, not a TBD.

- **Type consistency:**
  - Error codes: `WHATSAPP_NOT_REGISTERED` and `INVALID_WHATSAPP_NUMBER` used identically across Task 5 (service throw), Task 7 (frontend catch), and the spec.
  - Error body key: `errorCode` (matches the existing module pattern — verified at `click-to-chat.service.ts:108-112`). Spec earlier said `code`; this plan supersedes.
  - State name: `waSameAsPhone` used in Task 8 + Task 9 consistently.
  - Column header: `WhatsApp` (en-US capitalization) used everywhere; field name `whatsapp` (lowercase) in code + DB.

- **Exception class:** `UnprocessableEntityException` (HTTP 422) imported from `@nestjs/common` — deliberate divergence from neighbouring `BadRequestException` (400) usage. Approved at brainstorming.

- **Scope:** Single implementation. No decomposition needed.
