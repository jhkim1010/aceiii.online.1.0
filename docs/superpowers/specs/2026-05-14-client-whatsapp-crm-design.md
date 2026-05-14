# Customer WhatsApp + CRM Routing — Design

**Status:** Draft for implementation
**Date:** 2026-05-14
**Author:** brainstorming session (junghokim10@gmail.com)
**Phase target:** Phase 29 Wave C (follows Wave B Click-to-Chat)

## Goal

Add a dedicated WhatsApp phone field to each customer (Clients) so that when a store
operator triggers the existing Click-to-Chat flow, the resulting `wa.me` link points to
the customer's **WhatsApp** number — independent of their regular `phone`.

## Why

Today the WhatsApp Phase 29 Wave B Click-to-Chat service routes through `clients.phone`.
For many stores the customer's WhatsApp and landline/voice numbers diverge, leading to
either (a) failed deliveries (wa.me to a non-WhatsApp number) or (b) reluctance to use
the CRM channel at all. Storing the WhatsApp number explicitly solves both.

## User-visible behavior

### Customer create / edit form
- New `WhatsApp` text field rendered immediately after the existing `Phone` field.
- Adjacent checkbox: **`Igual que teléfono`**. When checked:
  - The WhatsApp input mirrors the phone value live (one-way bind).
  - The WhatsApp input is visually disabled.
  - Unchecking releases the bind and clears nothing (last mirrored value remains, edit-able).
- The field is **optional** at the data layer (nullable column).

### Customer list (`clientes-globales`)
- A `WhatsApp` column is shown **by default** between `Phone` and `Email`.
- Empty values render as a muted "—".
- Filter / search treats this as a regular text column (no special phone normalization).

### Cliente 360 (`cliente-vista`)
- Displays the WhatsApp number under the contact summary, with the green `tabler:brand-whatsapp` icon (mirrors `ProveedoresView` precedent at `ProveedoresView.tsx:425-428`).

### CRM messaging (Click-to-Chat)
- When the operator opens `WhatsAppSendDialog`:
  - If `client.whatsapp` is **non-empty and normalizes successfully** → "Enviar" button enabled, recipient shown.
  - If `client.whatsapp` is **null or blank** → "Enviar" button disabled; inline warning:
    > "Este cliente no tiene un número de WhatsApp registrado. Edite los datos del cliente para agregarlo."
  - If `client.whatsapp` is **non-empty but normalizes to invalid** → existing invalid-phone error path reused, with text adjusted to mention WhatsApp.
- **No fallback to `client.phone`** under any circumstance — strict mode.

## Architecture

### Data model

#### `clients` (legacy / per-tenant)
Add column:
```
whatsapp varchar(255) NULL
```
Position: logically after `phone` (no constraint impact; Sequelize model field order
controls the canonical reading order, not DB).

#### `global_clients` (multi-tenant canonical)
Add column:
```
whatsapp varchar(100) NULL
```
Width matches existing `global_clients.phone` (100). Legacy `clients.phone` is 255 but
phoneNormalizer accepts the same input range — width difference is harmless.

`store_clients` is unchanged — it stores per-tenant overlays only (no contact info).

#### `whatsapp_messages` (log)
No new column. The existing `recipient_phone` column continues to record the actual
number used for the wa.me link — now sourced from `clients.whatsapp`, so historical
accuracy improves automatically.

### Sequelize models

`api-ventago/src/app/clients/clients.model.ts`
```ts
@Column
phone: string;

// CRM (Click-to-Chat) 의 wa.me 대상 번호. phone 과 별개로 관리.
// 비어 있으면 WhatsApp 발송 버튼이 비활성화됨 (fallback 없음).
@Column
whatsapp: string;
```

`api-ventago/src/app/global-clients/global-clients.model.ts` — mirror the column.

### DTO

`api-ventago/src/app/clients/dto/create-clients.dto.ts`
```ts
@IsOptional()
@IsString()
@MaxLength(255)
readonly whatsapp?: string;
```

(The same DTO is reused by update — confirmed by service usage; no separate
update-clients.dto.ts to touch.)

### Sync to global_clients

`api-ventago/src/app/shared/clients-sync/clients-sync.service.ts`

Extend `SyncableClient`:
```ts
export interface SyncableClient {
  ...
  phone?: string | null;
  whatsapp?: string | null;
}
```

In `syncFromLegacy`, propagate the new field to the `global_clients` upsert:
```ts
{
  ...
  phone: legacy.phone ?? null,
  whatsapp: legacy.whatsapp ?? null,
}
```

### Click-to-Chat service

`api-ventago/src/app/whatsapp/services/click-to-chat.service.ts`

Lines ~105-111 today (using NestJS `BadRequestException`, HTTP 400):
```ts
const client = await this.fetchClient(input.clientId, input.storeId);
const normalized = this.phoneNormalizer.normalize(client.phone);
if (!normalized.valid) {
  throw new BadRequestException({
    code: 'INVALID_CLIENT_PHONE',
    message: `손님 (${client.fullname}) 의 전화번호가 유효하지 않습니다.`,
  });
}
```

Change to (using NestJS `UnprocessableEntityException`, HTTP 422 — validation rule
violation rather than malformed request):
```ts
const client = await this.fetchClient(input.clientId, input.storeId);

if (!client.whatsapp || client.whatsapp.trim() === '') {
  throw new UnprocessableEntityException({
    code: 'WHATSAPP_NOT_REGISTERED',
    message: `손님 (${client.fullname}) 에 WhatsApp 번호가 등록되어 있지 않습니다.`,
  });
}

const normalized = this.phoneNormalizer.normalize(client.whatsapp);
if (!normalized.valid) {
  throw new UnprocessableEntityException({
    code: 'INVALID_WHATSAPP_NUMBER',
    message: `손님 (${client.fullname}) 의 WhatsApp 번호 형식이 유효하지 않습니다.`,
  });
}
```

The existing `INVALID_CLIENT_PHONE` error code is removed (the service is its only
producer — confirm by grep before merge). Add the import:
```ts
import { UnprocessableEntityException } from '@nestjs/common';
```

Note: existing errors in the whatsapp module use `BadRequestException` (400). The two
new errors deliberately use 422 for stricter HTTP semantics, as approved during
brainstorming. The error body shape (`{ code, message }`) is identical, so the
frontend error-mapping reads `error.response.code` regardless of HTTP status.

### Migration SQL

`api-ventago/migrations/phase29-wave-c-client-whatsapp.sql`

```sql
-- Phase 29 Wave C — clients.whatsapp + global_clients.whatsapp
-- Idempotent (uses IF NOT EXISTS / WHERE filter on backfill).

BEGIN;

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS whatsapp varchar(255);

ALTER TABLE global_clients
  ADD COLUMN IF NOT EXISTS whatsapp varchar(100);

-- One-time backfill: existing phone → whatsapp, only where phone is meaningful
-- and whatsapp is still null (so re-running this migration is a no-op).
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

After applying locally, regenerate the schema intel files:
```
./.planning/intel/db-schema.regen.sh
```
…and commit the resulting diff to `db-schema-tables.md` / `db-schema-fks.md`.

PG10/PG15 compatibility: `IF NOT EXISTS` on `ADD COLUMN`, plain `varchar`, plain
`UPDATE` — all supported on both engines. No `GENERATED` / `MERGE` / PG12+ features used.

### Frontend

#### Customer form
View file: `ventago-app/src/views/clientes-globales/...` (component containing the
existing Phone field — locate the exact component during planning).

Add:
- `<CustomTextField label="WhatsApp" {...register('whatsapp')} />` after the Phone
  field.
- `<Checkbox>` "Igual que teléfono" wired to a local `sameAsPhone` boolean. While true,
  `useEffect` mirrors `watch('phone')` into `setValue('whatsapp', ...)` and the input
  becomes `disabled`.
- ESLint: ensure `newline-before-return` and `lines-around-comment` rules respected;
  run the eslint-guardian subagent after edits per project standard.

#### Customer list grid
File: `ventago-app/src/views/clientes-globales/...` list/grid component.

Add a column definition between Phone and Email:
```ts
{
  field: 'whatsapp',
  headerName: 'WhatsApp',
  width: 140,
  valueFormatter: ({ value }) => value || '—',
}
```
Visible by default; column toggle state respected via existing column chooser.

#### Cliente 360
File: `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx`

Below the existing Phone row, render WhatsApp following the `ProveedoresView.tsx:425-428`
pattern (icon + monospace number + click opens the existing `WhatsAppSendDialog`).

#### WhatsAppSendDialog
File: `ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx`

- Change all references that read `client.phone` (for recipient display) to
  `client.whatsapp` (existing line 240, 263, etc.). The header subtitle
  ` · ${client.phone}` becomes ` · ${client.whatsapp}`.
- Empty-state gate at line 263 changes:
  - Was: `{!client.phone && (...)}`
  - Becomes: `{!client.whatsapp && (...)}`
  - Empty-state Spanish text changes from phone-missing to WhatsApp-missing wording
    (see User-visible behavior above).
- `isReadyToSend` computation: replace `client.phone` check with `client.whatsapp`.
- API call payload (`POST /whatsapp/click-to-chat`) is unchanged — the server resolves
  the number from `clientId`. Frontend only owns the disabled-state gate + display.
- Error handling: add a case for `WHATSAPP_NOT_REGISTERED` (server may still return it
  if the client was edited to clear whatsapp between page load and click); surface the
  same friendly Spanish message and keep the dialog open.

### TypeScript types (frontend)

Search `ventago-app/src/types` and `ventago-app/src/hooks/api` for an existing `Client`
interface; add `whatsapp?: string | null`. Update any inline interface in
`WhatsAppSendDialog.tsx` (line ~57 shows a local `phone?: string | null` member) to
include `whatsapp?: string | null`.

## Error handling

| Condition | Server | Client UX |
|---|---|---|
| `client.whatsapp` null/blank at request time | 422 `WHATSAPP_NOT_REGISTERED` | Dialog shows "Edite los datos del cliente para agregarlo" + button disabled |
| `client.whatsapp` present but unnormalizable | 422 `INVALID_WHATSAPP_NUMBER` | Toast + inline error: "Formato de WhatsApp inválido" |
| `client.whatsapp` valid → wa.me success | 200 with link | Existing flow (existing 발송 로그 INSERT) |
| Network / unknown 5xx | 500 | Existing prominent error overlay |

The frontend continues to use the project-wide error-visibility rule (inline Alert +
prominent toast) per `feedback_error_visibility.md`.

## Testing

Required spec updates:
- `api-ventago/src/app/whatsapp/services/click-to-chat.service.spec.ts` — add cases:
  - whatsapp null → `WHATSAPP_NOT_REGISTERED` thrown, log row NOT inserted.
  - whatsapp blank string → same.
  - whatsapp present but invalid → `INVALID_WHATSAPP_NUMBER` thrown.
  - whatsapp valid → wa.me link generated, recipient_phone logs the WhatsApp value.
- `api-ventago/src/app/clients/clients-create-with-store-link.spec.ts` — extend to
  cover that `whatsapp` propagates from `Clients.create` to `global_clients` row via
  the existing AfterCreate hook (no behavior change in the hook itself, just field
  pass-through).
- Any seed fixtures that build `Clients` with `phone` and rely on Click-to-Chat must
  also set `whatsapp` — sweep `*.spec.ts` files for `phone:` literal in clients
  fixtures.

Manual UAT:
1. Open existing client (whose `phone` was backfilled to `whatsapp` by the migration)
   → Click-to-Chat still works end-to-end.
2. Create new client without WhatsApp → "Send WhatsApp" disabled with the Spanish
   guidance message.
3. Add WhatsApp to that client → button enables; sending generates a valid wa.me link.
4. Edit client, check "Igual que teléfono", change phone → WhatsApp mirror updates
   live; uncheck → field becomes free-edit, last value retained.

## Out of scope (YAGNI)

- Bulk CSV import column for `whatsapp` — deferred to a later `client-import` phase
  (the import pipeline at `api-ventago/src/app/client-import` is not touched).
- E.164 strict validation beyond the existing `phoneNormalizer`.
- Auto-detection of WhatsApp number from sales / online-orders records (the existing
  `online_orders.channel = 'whatsapp'` flow does not save the chat number to the
  customer; out of scope here).
- Multiple WhatsApp numbers per customer (single column).
- WhatsApp **Business API** (server-initiated messages). This change continues to use
  the wa.me Click-to-Chat pattern, which requires the operator to click and send from
  their own WhatsApp Web session — unchanged from Wave B.

## Rollout

1. Run migration on local dev (PG15 Docker `dbpostgres`).
2. Verify intel diff is clean; commit `db-schema-tables.md` update.
3. Deploy backend + frontend through standard Jenkins CI.
4. On production, run the same migration SQL via the documented
   `sudo -u postgres psql -d ventago < migration.sql` path **with explicit user
   confirmation** (DDL — per CLAUDE.md operational rules).
5. Verify backfill row counts on production by reading `clients` whatsapp NOT NULL
   count before/after.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Migration backfill copies a non-WhatsApp `phone` into `whatsapp` for some clients, causing wa.me links to fail | Acceptable — strict-mode UX makes the failure obvious (operator sees wa.me open without a registered WhatsApp account on the destination) and they can edit the customer to fix. No silent data corruption — `phone` is preserved. |
| Concurrent client edit between page load and Click-to-Chat click | Server-side `WHATSAPP_NOT_REGISTERED` is the safety net; dialog reopens with the empty-state UI. |
| Frontend `Igual que teléfono` checkbox bug → stale mirror | Local state only, no persistence; unchecking releases the bind. Tested via UAT step 4. |
| ESLint `newline-before-return` / `lines-around-comment` violations | Run eslint-guardian subagent after edits per project standard. |

## File-touch checklist (informational — final plan will be authoritative)

Backend:
- `api-ventago/migrations/phase29-wave-c-client-whatsapp.sql` (new)
- `api-ventago/src/app/clients/clients.model.ts`
- `api-ventago/src/app/clients/dto/create-clients.dto.ts`
- `api-ventago/src/app/global-clients/global-clients.model.ts`
- `api-ventago/src/app/shared/clients-sync/clients-sync.service.ts`
- `api-ventago/src/app/whatsapp/services/click-to-chat.service.ts`
- spec files listed under Testing above

Frontend:
- `ventago-app/src/views/clientes-globales/...` (form + list — exact files to be
  identified during plan-phase exploration)
- `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx`
- `ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx`
- `ventago-app/src/types/...` Client interface (or equivalent)

Intel:
- `.planning/intel/db-schema-tables.md` (regenerated)
