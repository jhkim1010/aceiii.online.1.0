# Phase 25: Clientes globales compartidos entre tiendas + Importación masiva — Pattern Map

**Mapped:** 2026-04-23
**Files analyzed:** 37 (backend 16 · frontend 10 · SQL 6 · specs 5)
**Analogs found:** 34 / 37 (92% — only 3 genuinely new surfaces with no existing analog)

---

## Summary

| Bucket | New | Modified | Total | Notes |
|--------|----:|---------:|------:|-------|
| Backend (NestJS) | 10 | 11 | 21 | Major reuse of `shared/global-clients/*` + `FunctionPermissionGuard` pattern |
| Frontend (Next.js) | 3 | 5 | 8 | `CargaMasivaClientesView.tsx` (570 lines) is the dominant reuse target |
| Migrations (SQL) | 6 | 0 | 6 | All follow `20260422-cost-sheet-step1-schema.sql` pattern |
| Tests | 5 | 2 | 7 | Follow `function-permission.guard.spec.ts` mocking style |
| **Grand total** | **24** | **18** | **42** | |

**Biggest reuse targets (planner: point every task here first):**
1. `CargaMasivaClientesView.tsx` (570 lines, Stepper + papaparse + xlsx + chunked POST) — Wave 5 extends, never rewrites
2. `public-purchase.service.ts:264-306` `findOrCreateGlobalClient` — Wave 3 promote/merge service copies this pattern, dropping the `fullname+phone` branch per D1-01
3. `function-permission.guard.ts` + `function-guard.decorator.ts` — Wave 2 `OwnerScopeGuard` + `@OwnerScope` decorator mirror this structure 1:1
4. `20260422-cost-sheet-step1-schema.sql` — all 6 Wave 1 migration SQL files mimic the BEGIN / DO-block / GRANT / COMMIT layout
5. `global-clients.controller.ts` + `clients.controller.ts` CRUD surface — Wave 3/4 new endpoints (`/clients/import`, `/clients/:id/promote`, `/clients/merge`)

---

## Backend (NestJS)

### Models & schema

| File | Role | Data Flow | Status | Analog | Wave |
|------|------|-----------|--------|--------|------|
| `api-ventago/src/app/shared/global-clients/global-clients.model.ts` | backend-model | CRUD | MODIFY | self (add `ownerGroupId` + drop `idx_global_clients_name_phone`) | 1 |
| `api-ventago/src/app/shared/store-clients/store-clients.model.ts` | backend-model | CRUD | unchanged | — | — |
| `api-ventago/src/app/clients/clients.model.ts` | backend-model | CRUD | unchanged (D2-03) | — | — |
| `api-ventago/src/app/store/store.model.ts` | backend-model | CRUD | MODIFY | self (add `ownerGroupId`) | 1 |
| `api-ventago/src/app/sales/sales.model.ts` | backend-model | CRUD | MODIFY | self (add `storeClientId` nullable FK) | 1 |
| `api-ventago/src/app/client-import/client-import.model.ts` | backend-model | CRUD | NEW | `api-ventago/src/app/shared/global-clients/global-clients.model.ts` | 4 |
| `api-ventago/src/app/clients/models/client-merge.model.ts` | backend-model | CRUD | NEW | same (audit-table mapping) | 3 |
| `api-ventago/src/app/common/models/client-access-audit.model.ts` | backend-model | CRUD | NEW | same | 2 |

### Services & controllers

| File | Role | Data Flow | Status | Analog | Wave |
|------|------|-----------|--------|--------|------|
| `api-ventago/src/app/shared/global-clients/global-clients.service.ts` | backend-service | CRUD | MODIFY | self — add `ownerGroupId` filter on every query | 2 |
| `api-ventago/src/app/shared/global-clients/global-clients.controller.ts` | backend-controller | request-response | MODIFY | self — attach `@OwnerScope` | 2 |
| `api-ventago/src/app/clients/clients.service.ts` | backend-service | CRUD | EXTEND | `public-purchase.service.ts:264-306` for `promote()` + `merge()` | 3 |
| `api-ventago/src/app/clients/clients.controller.ts` | backend-controller | request-response | EXTEND | `global-clients.controller.ts:40-90` for `POST /clients/:id/promote`, `POST /clients/merge` | 3 |
| `api-ventago/src/app/client-import/client-import.service.ts` | backend-service | batch + transform | NEW | `public-purchase.service.ts:264-306` (chunked transactional upsert) | 4 |
| `api-ventago/src/app/client-import/client-import.controller.ts` | backend-controller | request-response | NEW | `clients.controller.ts:24-50` (`@Auth` + `@Audit`) + the slug-based guard (`'manage-clientes-import'`, `'create'`) | 4 |
| `api-ventago/src/app/store/store.service.ts` | backend-service | CRUD | MODIFY | self — auto-allocate `ownerGroupId` on create (D3-03) | 2 |
| `api-ventago/src/app/auth/auth.service.ts` (`/me` handler) | backend-service | request-response | MODIFY | self — include caller `ownerGroupId` in user payload | 2 |
| `api-ventago/src/app/sales/sales-create.service.ts` | backend-service | CRUD | MODIFY | self — set `storeClientId` alongside legacy `clientId` | 3 |
| `api-ventago/src/app/sales/sales.service.ts` | backend-service | CRUD | MODIFY | self — read precedence `storeClientId → clientId` fallback | 3/7 |

### Guards, decorators, DTOs, validators

| File | Role | Data Flow | Status | Analog | Wave |
|------|------|-----------|--------|--------|------|
| `api-ventago/src/app/common/guards/owner-scope.guard.ts` | backend-guard | request-response | NEW | `api-ventago/src/app/auth/guards/function-permission.guard.ts:11-79` | 2 |
| `api-ventago/src/app/common/decorators/owner-scope.decorator.ts` | backend-decorator | request-response | NEW | `api-ventago/src/app/auth/decorators/function-guard.decorator.ts:1-19` | 2 |
| `api-ventago/src/app/client-import/dto/import-row.dto.ts` | backend-dto | validation | NEW | `api-ventago/src/app/shared/global-clients/dto/create-global-client.dto.ts` | 4 |
| `api-ventago/src/app/client-import/validators/cuit.validator.ts` | backend-utility | validation | NEW | none (green-field AR CUIT logic — use RESEARCH.md Example 2 as canonical source) | 4 |
| `api-ventago/src/app/client-import/validators/dni.validator.ts` | backend-utility | validation | NEW | none (7-8 digit check) | 4 |

### Module registration

| File | Role | Status | Note |
|------|------|--------|------|
| `api-ventago/src/app/client-import/client-import.module.ts` | backend-module | NEW | Standard NestJS module skeleton; register in `app.module.ts` alongside `shared/global-clients` |
| `api-ventago/src/app.module.ts` | backend-module | MODIFY | Add `ClientImportModule` + `ClientsMergeModule` imports (legacy `app/global-clients/*` stays registered for cut-over overlap) |

---

## Frontend (Next.js)

| File | Role | Data Flow | Status | Analog | Wave |
|------|------|-----------|--------|--------|------|
| `ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx` | frontend-view | event-driven + batch-upload | MODIFY | self (570 lines — Stepper, drop-zone, chunked `apiConnector.post`) | 5 |
| `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx` | frontend-view | CRUD + request-response | MODIFY | self (CardHeader `action` slot at line 309) — insert button before "Nuevo Cliente" | 6 |
| `ventago-app/src/views/cliente-vista/PromoteMergeDialog.tsx` | frontend-component | request-response | NEW | `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx:402+` (existing edit Dialog + DialogActions) — for `mode='promote-confirm'` and `mode='merge-resolve'` | 6 |
| `ventago-app/src/views/clientes-globales/GlobalClientesView.tsx` | frontend-view | CRUD | MODIFY (minimal) | self — add ownerGroup filter Select + 8px promotion-status dot | 6 |
| `ventago-app/src/utils/cuit-validator.ts` | frontend-utility | validation | NEW | RESEARCH.md Example 2 (copy exactly from backend `cuit.validator.ts` — deliberate cross-package duplication per A-risk log) | 5 |
| `ventago-app/src/utils/dni-validator.ts` | frontend-utility | validation | NEW | same | 5 |
| `ventago-app/src/hooks/api/useClientsImportRuns.ts` | frontend-hook | request-response | NEW (optional) | `ventago-app/src/hooks/api/usePriceTypes.ts` (3-line SWR wrapper over `useApi`) | 5 |
| `ventago-app/public/locales/es.json` | frontend-i18n | static | MODIFY | self — add 40+ `cliente_import_*` / `cliente_promote_*` / `cliente_merge_*` / `owner_group_*` keys from UI-SPEC.md copywriting table | 5/6 |
| `ventago-app/public/locales/ko.json` | frontend-i18n | static | MODIFY | same | 5/6 |
| `ventago-app/public/locales/en.json` | frontend-i18n | static | MODIFY (English fallback — optional) | same | 5/6 |

**Notes:**
- Superadmin store form extension (S9) likely lives under `ventago-app/src/views/admin/tiendas/` — analog to be confirmed by planner via `ls` in Wave 6 (not in canonical_refs). If the form does not exist yet, the ownerGroupId field is deferred per CONTEXT.md "Claude's Discretion".
- `ventago-app/src/services/api.service.ts` needs NO change (already forwards JWT + x-session-token).
- `ventago-app/src/configs/acl.ts` needs NO change (CASL is function-slug-driven; slug is created on the backend seed side).

---

## Migrations (SQL)

All files follow `20260422-cost-sheet-step1-schema.sql` structure: BEGIN / DO-block for ADD CONSTRAINT / GRANT / COMMIT with `DROP INDEX IF EXISTS` / `ADD COLUMN IF NOT EXISTS` idempotence.

| File | Role | Data Flow | Status | Analog | Wave |
|------|------|-----------|--------|--------|------|
| `api-ventago/migrations/20260424-phase25-step1-owner-group.sql` | db-migration-sql | DDL | NEW | `20260422-cost-sheet-step1-schema.sql` (BEGIN/COMMIT + DO block for ADD CONSTRAINT) | 1 |
| `api-ventago/migrations/20260424-phase25-step2-global-owner.sql` | db-migration-sql | DDL + data backfill | NEW | same | 1 |
| `api-ventago/migrations/20260424-phase25-step3-sales-store-client.sql` | db-migration-sql | DDL | NEW | same | 1 |
| `api-ventago/migrations/20260424-phase25-step4-audit-tables.sql` | db-migration-sql | DDL | NEW | same | 1 |
| `api-ventago/migrations/20260424-phase25-step5-data-migration.sql` | db-migration-sql | DML | NEW | same (INSERT ... ON CONFLICT DO NOTHING) | 1 |
| `api-ventago/migrations/20260424-phase25-step6-verify.sql` | db-migration-sql | SELECT assertions | NEW | same (read-only `SELECT COUNT(*) ...` block) | 1 |

**PG10 compatibility rules the planner must enforce in each SQL task:**
- No `GENERATED AS IDENTITY` — use `SERIAL`
- `ADD CONSTRAINT ... UNIQUE` must sit inside a `DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL; END $$;` block
- Partial unique indexes use `CREATE UNIQUE INDEX IF NOT EXISTS ... WHERE document IS NOT NULL` (NOT `ADD CONSTRAINT` with WHERE — PG10 disallows)
- Every new table gets `GRANT ALL PRIVILEGES ON TABLE ... TO coolsistema;` + `GRANT USAGE, SELECT ON SEQUENCE <tbl>_id_seq TO coolsistema;`

---

## Tests

| File | Role | Data Flow | Status | Analog | Wave |
|------|------|-----------|--------|--------|------|
| `api-ventago/src/app/common/guards/owner-scope.guard.spec.ts` | test | unit+integration | NEW | `api-ventago/src/app/auth/guards/function-permission.guard.spec.ts:1-80` (jest.mock + createMockContext helper) | 2 |
| `api-ventago/src/app/client-import/validators/cuit.validator.spec.ts` | test | unit | NEW | function-permission.guard.spec.ts (jest describe/it structure) | 4 |
| `api-ventago/src/app/client-import/client-import.service.spec.ts` | test | integration | NEW | same — Sequelize-model-mock pattern | 4 |
| `api-ventago/src/app/client-import/client-import.controller.spec.ts` | test | integration | NEW | same | 4 |
| `api-ventago/src/app/clients/clients-promote.service.spec.ts` | test | integration | NEW | same | 3 |
| `api-ventago/src/app/sales/sales.service.spec.ts` | test | integration | EXTEND | self (extend with storeClientId read-precedence cases) | 3/7 |
| `api-ventago/src/app/clients/clients.service.spec.ts` | test | integration | EXTEND (if exists) | self | 3 |

---

## Shared patterns (cross-cutting)

### Sequelize `underscored: true` ⇒ DB snake_case

`ownerGroupId` model property → `owner_group_id` DB column (automatic — project global `underscored: true` setting, see CLAUDE.md "DB 컬럼 네이밍"). Applies to every `@Column` decorator and every SQL migration.

### JWT + Session + Function + OwnerScope guard chain

For every endpoint that touches client/sales/report data, stack guards in this order (bottom-up — last decorator runs first in NestJS):

- `@UseGuards(AuthGuard('jwt'), SessionGuard, FunctionPermissionGuard, OwnerScopeGuard)`
- `@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.vendedor, ValidRoles.gerente)`
- `@RequireFunction('manage-clientes-import', 'create')` when CASL-gated
- `@OwnerScope({ storeIdParam: 'storeId' })` when scope-checked

Order matters: `OwnerScope` runs last and can rely on `req.user` populated by the JWT guard.

### Audit pattern (three tables, NOT `audit_logs`)

Per Pitfall 2 in RESEARCH.md: extending `audit_logs.action` ENUM on PG10 is unsafe inside transactions. Phase 25 uses three dedicated tables: `client_imports`, `client_merges`, `client_access_audits`. Each is written via a service method (not via `@Audit` decorator). The `@Audit` decorator on `clients.controller.ts:26-30` stays as-is for the legacy create/edit endpoints.

### i18n key convention

All user-visible strings go through `useTranslation()` with `t(key, fallback)` call. Keys are `snake_case`, prefixed with feature area:
- `cliente_import_*` (all S2-S5 surfaces)
- `cliente_promote_*` / `cliente_merge_*` (S6/S7)
- `owner_group_*` (S8/S9)
- `common_*` (reused from existing dictionary)

40+ keys enumerated in UI-SPEC.md "Copywriting Contract" table. Primary language ES, secondary KO. EN optional (check existing dictionary completeness before adding).

### ESLint build-blocking rules (CLAUDE.md)

Every new/modified `.ts` / `.tsx` file:
- Blank line before every `return`
- Blank line before every `//` comment
- No unused imports
- `apiConnector.remove()` (never `.delete()`)

---

## Code Excerpts

### Excerpt A — PG10-safe migration SQL skeleton (Wave 1 all six files)

**Source:** `api-ventago/migrations/20260422-cost-sheet-step1-schema.sql:1-65`

```sql
-- ===========================================================================
-- Phase 25 Wave 1 Step N: <purpose> (PG10 호환, coolsistema GRANT 포함)
-- 실행: sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1 -1 -f <file>.sql
-- ===========================================================================

BEGIN;

-- (A) 컬럼/테이블 추가 — IF NOT EXISTS 로 idempotent
ALTER TABLE stores
  ADD COLUMN IF NOT EXISTS owner_group_id INTEGER;

UPDATE stores SET owner_group_id = 1 WHERE owner_group_id IS NULL;

ALTER TABLE stores
  ALTER COLUMN owner_group_id SET NOT NULL;

-- (B) UNIQUE 제약은 DO block + EXCEPTION 으로 idempotent
DO $$
BEGIN
  ALTER TABLE global_clients
    ADD CONSTRAINT uq_global_clients_owner_document
    UNIQUE (owner_group_id, document);
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- (C) 부분 unique index (PG10 에서는 ADD CONSTRAINT ... WHERE 불가)
CREATE UNIQUE INDEX IF NOT EXISTS uq_global_clients_owner_doc_partial
  ON global_clients (owner_group_id, document)
  WHERE document IS NOT NULL;

-- (D) 구 index 제거 (D1-01)
DROP INDEX IF EXISTS idx_global_clients_name_phone;

-- (E) 운영 GRANT — 반복 교훈
GRANT ALL PRIVILEGES ON TABLE <new_table> TO coolsistema;
GRANT USAGE, SELECT ON SEQUENCE <new_table>_id_seq TO coolsistema;

COMMIT;
```

---

### Excerpt B — OwnerScopeGuard structure (copy FunctionPermissionGuard)

**Source:** `api-ventago/src/app/auth/guards/function-permission.guard.ts:11-46`

```typescript
@Injectable()
export class FunctionPermissionGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.get<{ functionSlug: string; action: string }>(
      FUNCTION_METADATA_KEY,
      context.getHandler(),
    );

    if (!required) return true;

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (user?.roles?.some((r: any) => r.slug === 'superadmin')) return true;

    const fn = await Functions.findOne({ where: { slug: required.functionSlug }, attributes: ['id'] });

    if (!fn) return true;

    // ... role + user override checks ...
    if (/* denied */) throw new ForbiddenException('Sin permisos para esta acción');

    return true;
  }
}
```

**How to adapt (Wave 2):**

1. Swap metadata key to `'owner_scope'` and interface to `OwnerScopeMeta { storeIdParam?: string; globalClientIdField?: string }`.
2. Resolve caller `ownerGroupId` via `Store.findByPk(user.storeId, { attributes: ['ownerGroupId'] })`.
3. Resolve target by reading `req.params[cfg.storeIdParam]` or `req.body[cfg.globalClientIdField]` (via `GlobalClient.findByPk`).
4. On mismatch: `await ClientAccessAudit.create({ userId, callerStoreId, targetStoreId, endpoint: req.originalUrl, ip: req.ip })` then `throw new ForbiddenException('CROSS_OWNER_GROUP_FORBIDDEN')`.
5. Keep the lightweight `attributes` projection — mirrors the existing pool-saving comment "경량 쿼리로 권한 확인 — pool 낭비 방지".

---

### Excerpt C — OwnerScope decorator (copy FunctionGuard decorator)

**Source:** `api-ventago/src/app/auth/decorators/function-guard.decorator.ts:1-19`

```typescript
import { applyDecorators, SetMetadata, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FunctionPermissionGuard } from '../guards/function-permission.guard';

export const FUNCTION_METADATA_KEY = 'required_function';

export const RequireFunction = (functionSlug: string, action: string) =>
  SetMetadata(FUNCTION_METADATA_KEY, { functionSlug, action });

export function FunctionGuard(functionSlug: string, action: string) {
  return applyDecorators(
    RequireFunction(functionSlug, action),
    UseGuards(AuthGuard('jwt'), FunctionPermissionGuard),
  );
}
```

**Adapt (Wave 2):** replace `FUNCTION_METADATA_KEY='required_function'` with `OWNER_SCOPE_KEY='owner_scope'`; signature becomes `@OwnerScope({ storeIdParam: 'storeId' })` or `@OwnerScope({ globalClientIdField: 'loserId' })`.

---

### Excerpt D — Chunked transactional upsert (for ClientImportService)

**Source:** `api-ventago/src/app/marketplace/public-purchase/public-purchase.service.ts:264-306`

```typescript
private async findOrCreateGlobalClient(
  buyerInfo: BuyerInfoDto,
  createdByStoreId: number,
  transaction: any,
): Promise<GlobalClient> {
  // 1순위: document(DNI/CUIT)가 있으면 document로 검색
  if (buyerInfo.document) {
    const existing = await this.globalClientModel.findOne({
      where: { document: buyerInfo.document },
      transaction,
    });

    if (existing) return existing;
  }

  // 2순위: fullname + phone 조합으로 검색 (document 없는 고객끼리 매칭)
  if (buyerInfo.fullname && buyerInfo.phone) {
    const existing = await this.globalClientModel.findOne({
      where: {
        fullname: buyerInfo.fullname,
        phone: buyerInfo.phone,
        document: null,
      },
      transaction,
    });

    if (existing) return existing;
  }

  // 3순위: 매칭 실패 → 새 전역 고객 생성
  return this.globalClientModel.create(
    {
      document: buyerInfo.document || null,
      fullname: buyerInfo.fullname,
      phone: buyerInfo.phone || null,
      createdByStoreId,
      isActive: true,
    },
    { transaction },
  );
}
```

**Critical adaptations for Phase 25 (per D1-01):**
1. **DROP the `fullname + phone` branch entirely** — policy now rejects document-less rows from entering global pool.
2. **ADD `ownerGroupId` to the where clause:** `where: { ownerGroupId, document: buyerInfo.document }`.
3. **Expand to chunked bulk:** wrap in `for (let i = 0; i < rows.length; i += 500)` with a single outer `sequelize.transaction()` (chunkSize=500 matches existing CargaMasivaClientesView:193).
4. **Use `findAll WHERE document IN (...)`** (not N `findOne` calls) then build a `Map<document, GlobalClient>` for O(1) per-row lookup — Pitfall 7 mitigation (stay under pool max=50).
5. **Audit row write** at end of each batch: `await ClientImport.create({ userId, storeId, fileName, totalRows, createdCount, updatedCount, skippedCount, errorCount, executedAt: new Date() }, { transaction })`.

Full reference implementation in RESEARCH.md "Example 1" (lines 491-548).

---

### Excerpt E — Test mocking pattern

**Source:** `api-ventago/src/app/auth/guards/function-permission.guard.spec.ts:1-50`

Pattern summary (no raw code excerpt):

- Top-of-file imports: `ExecutionContext`, `ForbiddenException`, `Reflector`, the guard under test, plus every Sequelize model it touches.
- `jest.mock('src/app/.../model')` for each model so `findOne` / `findByPk` become `jest.fn()`.
- Helper `createMockContext(user)` returns an `ExecutionContext`-shaped object with `getHandler()` and `switchToHttp().getRequest()` stubbed.
- `beforeEach` instantiates a fresh `Reflector`, wraps it in the guard, then `jest.clearAllMocks()`.
- Each `it(...)` uses `jest.spyOn(reflector, 'get').mockReturnValue(...)` to drive the metadata branch and asserts either `result === true` or `ForbiddenException` via `await expect(guard.canActivate(ctx)).rejects.toThrow(ForbiddenException)`.

**Adapt (Wave 2 `owner-scope.guard.spec.ts`):** mock `Store` + `GlobalClient` + `ClientAccessAudit`; test scenarios: (1) metadata absent — pass; (2) same ownerGroupId — pass; (3) different ownerGroupId — 403 + `ClientAccessAudit.create` called once; (4) superadmin bypass — pass.

---

### Excerpt F — ClienteVistaView CardHeader action slot (S1 insertion point)

**Source:** `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx:309-361`

```tsx
action={
  <Box display="flex" gap={2} alignItems="center" flexWrap="wrap">
    <Box display="flex" gap={0.5}>
      {/* existing status filter chips */}
    </Box>
    <TextField size="small" placeholder="Buscar cliente..." />
    <WithFunctionAccess functionSlug="crear-cliente">
      <Button
        variant="contained"
        startIcon={<Icon icon="mdi:plus" />}
        onClick={openCreateDialog}
      >
        Nuevo Cliente
      </Button>
    </WithFunctionAccess>
  </Box>
}
```

**Wave 6 insertion (UI-SPEC S1):** add before `<WithFunctionAccess functionSlug="crear-cliente">`:

```tsx
<WithFunctionAccess functionSlug="manage-clientes-import">
  <Button
    variant="outlined"
    color="primary"
    startIcon={<Icon icon="mdi:file-upload-outline" />}
    onClick={() => router.push('/clientes-globales/carga-masiva')}
  >
    {t('cliente_import_button', 'Importación masiva')}
  </Button>
</WithFunctionAccess>
```

`variant="outlined"` (not `contained`) — "Nuevo Cliente" stays the sole contained primary CTA (UI-SPEC rationale).

---

### Excerpt G — CargaMasivaClientesView chunked upload (Wave 5 extension point)

**Source:** `ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx:188-228`

```tsx
const handleUpload = async () => {
  if (parsedClients.length === 0) return
  setUploading(true)

  try {
    const chunkSize = 500
    let totalCreated = 0
    let totalUpdated = 0
    let totalSkipped = 0
    const allErrors: Array<{ row: number; message: string }> = []

    for (let i = 0; i < parsedClients.length; i += chunkSize) {
      const chunk = parsedClients.slice(i, i + chunkSize)
      const result: any = await apiConnector.post('/global-clients/massive-upload', { clients: chunk })

      totalCreated += result.created || 0
      totalUpdated += result.updated || 0
      totalSkipped += result.skipped || 0
      if (result.errors) {
        allErrors.push(...result.errors.map((err: any, idx: number) => ({
          row: i + idx + 2,
          message: err.message || 'Error desconocido'
        })))
      }
    }

    setUploadResult({ created: totalCreated, updated: totalUpdated, skipped: totalSkipped, errors: allErrors })
    setStep(2)
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('Error uploading clients:', err)
    alert('Error al cargar clientes')
  } finally {
    setUploading(false)
  }
}
```

**Wave 5 adaptations:**
1. Change endpoint: `'/global-clients/massive-upload'` — `'/clients/import'`.
2. Payload: `{ clients: chunk }` — `{ rows: chunk.map(r => ({ ...r, bucket: r.override ?? r.bucket, missingDocPolicy })), defaultNoDoc: missingDocPolicy }`.
3. Extend `UploadResult` shape with `createdCount`, `updatedCount`, `skippedCount`, `errorCount`, `errors: [{ row_index, error_code, error_message, fullname, document }]` — feeds UI-SPEC S5 stat cards + failure-row CSV.
4. Replace `alert(...)` with Snackbar (`react-toastify`, per themeConfig.toastPosition='top-right').
5. Run `classifyRow` on every parsed row after column mapping (RESEARCH.md Example 4) and store `{ bucket, errors, override? }`.
6. Use `papaparse.unparse()` for the failure-CSV download button (per UI-SPEC S5).

Preserve the 3-step Stepper shape ("Subir Archivo" — "Mapear Columnas" — "Resultados") — do not add a 4th step.

---

## No Analog Found

Three files have no close analog in the codebase and rely on RESEARCH.md / UI-SPEC.md alone:

| File | Role | Reason | Source of truth |
|------|------|--------|-----------------|
| `api-ventago/src/app/client-import/validators/cuit.validator.ts` | backend-utility | No existing AR tax-ID validator in codebase | RESEARCH.md Example 2 (CUIT mod-11 with `check==10 → invalid` special case) |
| `api-ventago/src/app/client-import/validators/dni.validator.ts` | backend-utility | No existing DNI validator | RESEARCH.md Example 2 (7-8 digit regex) |
| `ventago-app/src/views/cliente-vista/PromoteMergeDialog.tsx` | frontend-component | No existing field-by-field merge conflict resolver in project | UI-SPEC.md S6 (`mode: 'promote-confirm' | 'merge-resolve'` + 9 field-pair grid) |

For all three: planner's `read_first` list should include RESEARCH.md Example 2 (for validators) and UI-SPEC.md Component Contracts S6 + S7 (for the dialog). The dialog can structurally borrow from MUI Dialog patterns already used in `ClienteVistaView.tsx:400+` (edit dialog) + `DialogActions` two-button shape.

---

## Metadata

**Analog search scope:**
- `api-ventago/src/app/shared/global-clients/*`
- `api-ventago/src/app/shared/store-clients/*`
- `api-ventago/src/app/clients/*`
- `api-ventago/src/app/marketplace/public-purchase/*`
- `api-ventago/src/app/auth/guards/*`, `api-ventago/src/app/auth/decorators/*`
- `api-ventago/src/app/session/guards/*`
- `api-ventago/src/app/sales/*`, `api-ventago/src/app/store/*`
- `api-ventago/migrations/20260422-cost-sheet-*.sql`
- `ventago-app/src/views/clientes-globales/*`
- `ventago-app/src/views/cliente-vista/*`
- `ventago-app/src/hooks/api/*`
- `ventago-app/src/configs/withFunctionAccess.tsx`, `acl.ts`
- `ventago-app/public/locales/{es,ko,en}.json`

**Files scanned:** 28 direct reads, ~90 listed via `ls`/`grep`.
**Pattern extraction date:** 2026-04-23.

---

## PATTERN MAPPING COMPLETE
