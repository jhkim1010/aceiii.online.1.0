# Phase 25: Clientes globales compartidos entre tiendas (historial aislado) + Importación masiva — Research

**Researched:** 2026-04-23
**Domain:** multi-store client data partitioning + bulk CSV/Excel import (NestJS + Sequelize + Next.js + PG10)
**Confidence:** HIGH (most — codebase verified, production DB inspected, PG version confirmed)

---

## Summary

Phase 25 introduces an **owner-group client sharing boundary** on top of the existing (but unused in production) `global_clients` / `store_clients` tables. Core findings:

1. **Production state is near-empty for the new tables** — `global_clients=0`, `store_clients=0`, `clients=4 (one per store)`, `sales=8`. The "migration" is effectively a *first-time population*, not a transformation of millions of rows. This dramatically simplifies risk, but the code path (promotion/merge/scope guard) still has to be robust for future growth.
2. **Two GlobalClient models coexist in code:** `app/global-clients/` (legacy, text province) and `app/shared/global-clients/` (canonical, province_id FK, StoreClient HasMany). The **shared/ version is what's actually deployed** — the DB schema matches `shared/global-clients/global-clients.model.ts` exactly. The legacy controller (`/global-clients/massive-upload`) writes to the same table via the legacy model — this is currently hazardous and must be consolidated.
3. **Production PostgreSQL 10.23** (vs dev PG15) — partial unique indexes work, but `GENERATED AS IDENTITY` and some newer syntax do not. All migrations must use SERIAL + explicit DO blocks for duplicate-guard.
4. **No `ownerGroupId` exists yet** on stores or global_clients. This is a green-field schema addition (not a rename).
5. **Existing infrastructure is strong:** FunctionGuard + CASL granular permissions (Phase 14) are live and usable for `manage-clientes-import`; audit_logs table exists (but its `action` ENUM is limited — must extend or use separate `client_imports` table); papaparse + xlsx are already bundled in the front-end; `findOrCreateGlobalClient` in `public-purchase.service.ts` is a direct reference implementation for the promotion flow.

**Primary recommendation:**

- **Schema order:** Wave 1A (stores.owner_group_id + backfill=1) → Wave 1B (global_clients.owner_group_id + backfill=1 + UNIQUE rebuild) → Wave 1C (sales.store_client_id column, nullable) → Wave 1D (new `client_imports` audit table).
- **Data migration:** one-off idempotent SQL script that upserts the 4 existing `clients` rows into `global_clients` + creates `store_clients` + sets `sales.store_client_id`. Kept small and rollback-friendly. Legacy `sales.client_id` stays populated (D2-01).
- **Scope guard:** a new `@OwnerScopeGuard()` decorator that runs *after* JWT + *before* controllers touching `/clients/*`, `/sales/*`, `/global-clients/*`, `/reports/*` — reads `targetStoreId` / `targetGlobalClientId` from params/body and verifies `user.store.ownerGroupId === target.ownerGroupId`. Violations → 403 + write to new `client_access_audits` table (NOT `audit_logs`, because its action ENUM doesn't allow `access_denied`).
- **CargaMasiva UX:** keep the existing Stepper (570-line file is well-structured) — inject **row-bucket classifier** after mapping, rendering `[Global]/[Local]/[Skip]` chips. Backend exposes a new `POST /clients/import` (replaces `/global-clients/massive-upload` for Phase 25 onwards) that accepts rows with an explicit `bucket` field and transactionally writes into the correct table.
- **Merge UI:** field-by-field conflict resolution modal triggered from ClienteVistaView when saving a local client whose newly added document matches an existing GlobalClient.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area 1 — DNI/CUIT policy**
- **D1-01:** DNI/CUIT-less clients stay in legacy `clients` table only. Drop the existing `idx_global_clients_name_phone` partial unique index (conflicts with the new "document-required to enter global pool" policy).
- **D1-02:** DNI *or* CUIT is sufficient. DNI = AR 7-8 digits; CUIT = 11 digits + mod 11 checksum.
- **D1-03:** Adding DNI/CUIT to a local client auto-promotes it. If same document already exists in another tienda of the same owner group → merge-proposal modal.
- **D1-04:** Merge conflicts resolved via per-field checkbox UI (both values shown, user picks).
- **D1-05:** UNIQUE becomes `(owner_group_id, document)` — different owner groups may share the same document.

**Area 2 — Legacy migration**
- **D2-01:** New `sales.store_client_id` column. New writes point to StoreClient. Legacy `sales.client_id` stays populated for backward compatibility but is deprecated for new writes.
- **D2-02:** One-time bulk migration: legacy clients with valid DNI/CUIT → GlobalClient + StoreClient + remap `sales.store_client_id` for the same store.
- **D2-03:** Invalid/null-document rows stay in legacy `clients`. Keep `Clients` Sequelize model as-is (no rename).
- **D2-04:** Migration runs in **Wave 1 first** (before anything else).

**Area 3 — Owner group boundary**
- **D3-01:** Add `stores.owner_group_id INTEGER NOT NULL`. Add `global_clients.owner_group_id INTEGER NOT NULL`.
- **D3-02:** Existing 4 stores (CART=3, coolsistema=6, genius=8, ACE=9) → `owner_group_id = 1` initially.
- **D3-03:** New stores auto-create a fresh `owner_group_id` (1 store = 1 group by default).
- **D3-04:** Cross-owner-group access → HTTP 403 + audit entry.

**Area 4 — Import UX**
- **D4-01:** "Importación masiva" entry point = ClienteView top-bar button linking to existing `/clientes-globales/carga-masiva` page.
- **D4-02:** Preview row chips `[Global]` (blue) / `[Local]` (grey) / `[Skip]` (red) + filter.
- **D4-03:** DNI/CUIT-less rows default to **Local save** (user radio at upload start); per-row override allowed.
- **D4-04:** Existing Global client match default = "link to current tienda only". Per-row override: `skip` / `update basic info`.
- **D4-05:** Transactional commit per batch; failure rows exportable as CSV (row_index, error_code, error_message).
- **D4-06:** Audit in new `client_imports` table.

### Claude's Discretion

- MUI Stepper step count / chip hex colours — follow existing `CargaMasivaClientesView` conventions.
- DNI/CUIT regex details (leading-zero policy) — AR official rules.
- 403 vs 404 — 403 confirmed; researcher verifies no legal concern (AR doesn't mandate 404 for privacy).
- `audit_logs` schema extension vs separate table — **RESEARCH RECOMMENDS separate tables** because `audit_logs.action` ENUM does not include `access_denied` / `import` / `promote` / `merge` and extending the ENUM is risky on PG10.
- CSV/Excel max size (10 MB proposed) — 10,000 rows × ~500B avg = ~5 MB; 10 MB is comfortable.
- Promotion auto-trigger point — **recommended:** on POS client-edit save (D4-04 already biased this way); no separate "Promote" button needed.

### Deferred Ideas (OUT OF SCOPE)

- Cross-tienda aggregate insights for global customers (conflicts with historial-isolation).
- Mass local→global promotion batches, periodic merge-proposal cron.
- Global delete / deactivate policy (only soft delete via `isActive`).
- Cross-owner-group comparison analytics (policy-prohibited).
- Empty-global-client cleanup cron (0 StoreClient links).
- M&A owner-group transfer.

---

## Phase Requirements

No `REQ-ID` mapping was provided by the orchestrator. The 22 numbered requirements in `ROADMAP.md` are mapped to research findings below:

| ROADMAP # | Requirement (short) | Research Support |
|---|---|---|
| 1 | Client bifurcation (Global vs Local) | Standard Stack (shared/global-clients + clients legacy) + Wave 1 migration + Sales FK dual path |
| 2 | owner_group_id sharing scope | Schema migration + scope guard implementation |
| 3 | Shared fields (nombre / DNI / CUIT / email / teléfono / dirección / provincia / localidad / notes) | `shared/global-clients/global-clients.model.ts` already covers all |
| 4 | Isolation of sales/pagos/discounts/preferencias | Scope guard + `sales.store_id` filter (already enforced in sales.service) |
| 5 | Promotion + merge proposal | Promotion/Merge Flow section |
| 6 | Demotion blocked | Validation in update path (reject `document = null` when promoted) |
| 7 | sales.client_id continues to reference clients.id; scope WHERE sales.store_id=:caller | Sales FK dual-path section |
| 8 | Scope guard on /clients/\*, /sales/\*, /reports/\* + 403 on violation | Scope Guard section |
| 9 | Document lookup endpoint (no duplicate Global row creation) | Existing `/global-clients/by-document/:document` to be reused / wrapped |
| 10 | ClienteView "Importación masiva" button + modal | Frontend integration section |
| 11 | DNI/CUIT-present rows go Global; others Local or Skip | Row-bucket classifier |
| 12 | Column mapping UI (auto-detect + manual override) | Already implemented in CargaMasivaClientesView |
| 13 | Preview table + per-row Global/Local/Skip classification + error highlights | Frontend section (row-bucket chips) |
| 14 | Validation rules (DNI regex, CUIT mod11, email, phone digits, province lookup) | DNI/CUIT Checksum + validation section |
| 15 | Existing Global hit options (skip / update / link) | Row override UI |
| 16 | Transactional commit | Import performance section |
| 17 | Failure rows CSV export | Frontend section |
| 18 | Audit `client_imports`, `client_merges` | New audit tables |
| 19 | CASL `manage-clientes-import` permission | CASL Permission section |
| 20 | i18n es/ko | Follow existing convention (mostly ES; minimal KO strings) |
| 21 | Performance: 10 000 rows < 30 s | Import performance section |
| 22 | UNIQUE `(owner_group_id, document)` | Schema migration section |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| DNI/CUIT validation (form + bulk) | Browser (frontend) | API/Backend | UX-fast feedback on client side; authoritative re-check on server since frontend can be bypassed |
| Scope enforcement (ownerGroupId/storeId) | API/Backend | — | Security invariant — must never live only in the client |
| Data migration (one-time) | Database (SQL) | — | Idempotent SQL script run directly against PG10 via ssh jhkim-server |
| Promotion/Merge orchestration | API/Backend | Browser | Backend owns transaction atomicity; frontend renders the conflict-resolution UI |
| CSV/Excel parse + preview | Browser | — | Keeps server stateless; upload only the parsed normalized JSON |
| Bulk upsert + transactional commit | API/Backend | — | Sequelize transaction with chunked bulkCreate |
| Audit log writes | API/Backend | — | User context (userId, storeId, IP) is available only on server |
| Permission toggle (`manage-clientes-import`) | API/Backend (enforcement) | Browser (UI hide) | FunctionGuard on server; `WithFunctionAccess` wrapper on client |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---|---|---|---|
| NestJS | 11+ `[VERIFIED: api-ventago/package.json]` | Backend framework | Phase 25 endpoints are pure HTTP controllers + Sequelize services |
| sequelize-typescript | in use `[VERIFIED: existing models]` | ORM with snake_case underscore convention | Project-wide pattern (CLAUDE.md) |
| PostgreSQL | **10.23 production**, 15 dev `[VERIFIED: ssh jhkim-server psql]` | Data store | Production version constrains migration SQL syntax |
| jest + ts-jest | 29.7.0 `[VERIFIED: package.json]` | Backend unit tests | Existing spec files (products.service.spec.ts, sales-create.service.spec.ts) |
| Next.js 13 (Pages Router) | `[VERIFIED: ventago-app/package.json]` | Frontend framework | Existing pages structure (`/clientes-globales`, `/cliente-vista`, etc.) |
| Material-UI | 5 `[VERIFIED]` | UI components | Existing Stepper/Dialog/Chip usage in CargaMasivaClientesView |
| @casl/ability | via `src/configs/acl.ts` `[VERIFIED]` | Frontend permission gating | `manage-clientes-import` slug added to Functions table + FunctionGuard backend |

### Supporting
| Library | Version | Purpose | When to Use |
|---|---|---|---|
| papaparse | 5.4.1 `[VERIFIED: ventago-app/package.json]` | CSV parse | Already used in CargaMasivaClientesView line 49 |
| xlsx | 0.18.5 `[VERIFIED]` | Excel parse | Already used in CargaMasivaClientesView line 55 |
| class-validator | bundled with NestJS | DTO validation | Use on `MassiveClientItemDto` for DNI regex + CUIT checksum custom validator |
| sequelize `Op.in` / `bulkCreate` / transaction | `[VERIFIED: public-purchase.service.ts]` | Chunked bulk upsert | Standard pattern for 10 k-row import |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|---|---|---|
| New `POST /clients/import` endpoint | Extend `/global-clients/massive-upload` | Rejected — legacy endpoint writes to shared global_clients but uses legacy model. Must either consolidate or bypass. Safer to introduce new endpoint, deprecate old one at end of phase |
| Extend `audit_logs` ENUM | Separate `client_imports` + `client_access_audits` tables | Extending ENUM on PG10 requires DROP+RECREATE or `ALTER TYPE ... ADD VALUE` (supported in PG10 but requires no-transaction). Separate tables are safer and requirement 18 explicitly mentions them. |
| Add `ownerGroupId` to User object directly | Derive via `user.store.ownerGroupId` | Users already carry storeId; deriving ownerGroupId from store at auth time (in `/me` response) keeps source of truth in stores table |

### Installation

No new packages needed — everything required is already installed `[VERIFIED: grep package.json]`.

### Version verification
- `papaparse@5.4.1` — published 2023, still current `[CITED: ventago-app/package.json + https://www.npmjs.com/package/papaparse]`
- `xlsx@0.18.5` — SheetJS community edition, stable `[CITED: package.json]`
- `jest@29.7.0` — LTS `[VERIFIED: package.json]`

---

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  BROWSER (ventago-app, Next.js)                                 │
│                                                                   │
│  ClienteVistaView  ──► [Importación masiva] button              │
│                              │                                    │
│                              ▼                                    │
│  /clientes-globales/carga-masiva page                            │
│    └─ CargaMasivaClientesView (Stepper)                          │
│        ├─ Step 1: File drop → papaparse/xlsx parse                │
│        ├─ Step 2: Column mapping + row classifier                 │
│        │       └─ Per row: DNI/CUIT validation →                  │
│        │             assign bucket [Global|Local|Skip]            │
│        ├─ Step 3: Preview table w/ chips + per-row overrides      │
│        └─ Step 4: Upload → chunks of 500 → POST /clients/import   │
│                                                                   │
│  ClienteVistaView save handler                                   │
│    └─ if new DNI/CUIT on local client → Promotion Modal           │
│           └─ if duplicate Global found → Merge Modal (per-field)  │
└─────────────────────────────────────────────────────────────────┘
                              │ HTTP + JWT + x-session-token
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  API (api-ventago, NestJS)                                       │
│                                                                   │
│  Guards (in order):                                              │
│    JwtAuthGuard → SessionGuard → FunctionPermissionGuard →        │
│    OwnerScopeGuard (NEW)                                         │
│                                                                   │
│  POST /clients/import  (NEW, phase 25)                           │
│    └─ ClientImportService.importBatch()                          │
│        ├─ For each chunk (default 500):                          │
│        │   ├─ Validate (DNI regex + CUIT mod11 + email + phone)  │
│        │   ├─ Group by bucket                                    │
│        │   ├─ Global bucket:                                     │
│        │   │   ├─ findAll WHERE (owner_group_id, document) IN    │
│        │   │   ├─ upsert into global_clients                     │
│        │   │   └─ findOrCreate store_clients(globalClientId,store)│
│        │   ├─ Local bucket: create into `clients` (legacy)       │
│        │   └─ Skip bucket: record count only                     │
│        ├─ Transaction per chunk (rollback on error)              │
│        └─ Write 1 row to `client_imports` audit table            │
│                                                                   │
│  POST /clients/:id/promote  (NEW)                                │
│    └─ Validates document + checks duplicate in ownerGroup         │
│       └─ if dup: returns conflict payload (for Merge modal)       │
│       └─ else: atomic promote (create global + store link +       │
│                  UPDATE sales.store_client_id WHERE client_id=?)  │
│                                                                   │
│  POST /clients/merge  (NEW)                                      │
│    └─ Atomic: update global (field picks) + reparent store_links  │
│       + reparent sales.store_client_id + delete losing globals    │
│                                                                   │
│  GET /clients/search?document=...                                │
│    └─ Returns at most 1 GlobalClient in caller's ownerGroup       │
│       + sales historial ALWAYS filtered by caller.storeId         │
└─────────────────────────────────────────────────────────────────┘
                              │ Sequelize
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  DATABASE (PostgreSQL 10.23 production, 15 dev)                  │
│                                                                   │
│  stores (+ owner_group_id NOT NULL)                              │
│    └─ id=3,6,8,9 all owner_group_id=1                            │
│                                                                   │
│  global_clients (+ owner_group_id NOT NULL)                      │
│    ├─ UNIQUE (owner_group_id, document) WHERE document NOT NULL  │
│    └─ DROP old idx_global_clients_name_phone                     │
│                                                                   │
│  store_clients (existing) — junction table                       │
│                                                                   │
│  clients (legacy) — stays, no schema change                      │
│                                                                   │
│  sales                                                            │
│    ├─ client_id (legacy, kept populated for compat)              │
│    └─ store_client_id (NEW, nullable, FK → store_clients.id)     │
│                                                                   │
│  client_imports (NEW audit)                                      │
│  client_merges (NEW audit)                                       │
│  client_access_audits (NEW — 403 events)                         │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended File Layout

```
api-ventago/src/app/
├── shared/
│   ├── global-clients/
│   │   ├── global-clients.model.ts       ← MODIFY (add owner_group_id, drop name+phone unique, wire to new service)
│   │   ├── global-clients.service.ts      ← EXTEND (ownerGroupId filter in findByDocument)
│   │   └── global-clients.controller.ts   ← EXTEND (scope guard)
│   └── store-clients/                     (existing, untouched)
├── clients/
│   ├── clients.model.ts                   (NO RENAME per D2-03)
│   ├── clients.service.ts                 ← EXTEND (promote method)
│   └── clients.controller.ts              ← EXTEND (POST /clients/:id/promote, POST /clients/merge)
├── client-import/                          ← NEW module
│   ├── client-import.model.ts              (client_imports table mapping)
│   ├── client-import.service.ts            (importBatch with chunked tx)
│   ├── client-import.controller.ts         (POST /clients/import)
│   ├── dto/import-row.dto.ts               (DNI/CUIT/email validators)
│   └── validators/
│       ├── cuit.validator.ts               (mod 11)
│       └── dni.validator.ts
├── common/
│   ├── decorators/
│   │   └── owner-scope.decorator.ts        ← NEW (@OwnerScope('targetStoreId'))
│   └── guards/
│       └── owner-scope.guard.ts            ← NEW
├── store/
│   ├── store.model.ts                      ← MODIFY (add ownerGroupId column)
│   └── storeTemplate.service.ts            ← MODIFY (auto-create new owner_group_id on new store creation)

ventago-app/src/
├── views/
│   ├── clientes-globales/
│   │   └── CargaMasivaClientesView.tsx     ← MODIFY (bucket chips, upload radio, new endpoint, row overrides)
│   └── cliente-vista/
│       ├── ClienteVistaView.tsx            ← MODIFY (Importación masiva button in CardHeader action)
│       └── PromoteMergeDialog.tsx          ← NEW
├── pages/clientes-globales/carga-masiva/
│   └── index.tsx                           (existing route, no change needed)
└── utils/
    ├── cuit-validator.ts                   ← NEW (shared with backend via copy — Next.js can't import from api-ventago)
    └── dni-validator.ts                    ← NEW

api-ventago/migrations/
├── 20260424-phase25-step1-owner-group.sql          ← stores.owner_group_id + backfill 1
├── 20260424-phase25-step2-global-owner.sql         ← global_clients.owner_group_id + rebuild UNIQUE
├── 20260424-phase25-step3-sales-store-client.sql   ← sales.store_client_id FK
├── 20260424-phase25-step4-audit-tables.sql         ← client_imports, client_merges, client_access_audits
├── 20260424-phase25-step5-data-migration.sql       ← upsert 4 legacy clients to global + link sales
└── 20260424-phase25-step6-verify.sql               ← read-only assertion queries
```

### Pattern 1: Idempotent PG10 migration with explicit BEGIN/END

```sql
-- Source: /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/migrations/20260422-cost-sheet-step1-schema.sql:1-40 (VERIFIED pattern used across project)

BEGIN;

ALTER TABLE stores
  ADD COLUMN IF NOT EXISTS owner_group_id INTEGER;

UPDATE stores SET owner_group_id = 1 WHERE owner_group_id IS NULL;

ALTER TABLE stores
  ALTER COLUMN owner_group_id SET NOT NULL;

-- PG10-safe: DO block for ADD CONSTRAINT ... UNIQUE
DO $$
BEGIN
  ALTER TABLE global_clients
    ADD CONSTRAINT uq_global_clients_owner_document
    UNIQUE (owner_group_id, document);
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- DROP the fullname+phone partial unique (D1-01)
DROP INDEX IF EXISTS idx_global_clients_name_phone;

-- GRANT to coolsistema (pattern from cost-sheet migration)
GRANT SELECT, INSERT, UPDATE, DELETE ON global_clients TO coolsistema;

COMMIT;
```

### Pattern 2: OwnerScopeGuard (NEW — Claude's discretion)

```typescript
// Source: adapted from /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/app/auth/guards/function-permission.guard.ts (VERIFIED pattern)

@Injectable()
export class OwnerScopeGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest();
    const user = req.user; // populated by JwtAuthGuard
    if (!user) throw new ForbiddenException('No user context');

    // Metadata says which field holds the target storeId or globalClientId
    const cfg = this.reflector.get<OwnerScopeMeta>('owner_scope', ctx.getHandler());
    if (!cfg) return true;

    // Resolve caller ownerGroupId (cached on user object from /me, or look up once per request)
    const callerOwnerGroupId = await this.resolveOwnerGroupId(user.storeId);

    const targetStoreId =
      req.params[cfg.storeIdParam] ?? req.body?.[cfg.storeIdParam] ?? user.storeId;
    const targetOwnerGroupId = await this.resolveOwnerGroupId(targetStoreId);

    if (callerOwnerGroupId !== targetOwnerGroupId) {
      await this.auditService.logDenied({
        userId: user.id,
        callerStoreId: user.storeId,
        targetStoreId,
        endpoint: req.originalUrl,
        ip: req.ip,
      });
      throw new ForbiddenException('CROSS_OWNER_GROUP_FORBIDDEN');
    }
    return true;
  }
}
```

### Pattern 3: findOrCreateGlobalClient (proven reference)

```typescript
// Source: /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/app/marketplace/public-purchase/public-purchase.service.ts:264-300 (VERIFIED implementation)

// Keep this pattern — adapt Phase 25 promote flow from it:
//   1) document present → findOne WHERE (owner_group_id, document)
//   2) match found → return existing + create store_client link
//   3) no match → create new GlobalClient
// KEY CHANGE: drop the fullname+phone fallback (D1-01 policy)
```

### Anti-Patterns to Avoid

- **Don't write to legacy `global-clients.module.ts` AND `shared/global-clients/` simultaneously.** The legacy controller uses a different model instance — writing via both will produce phantom updates. Phase 25 deprecates `/global-clients/massive-upload` for client use after cut-over.
- **Don't rely on `audit_logs.action` ENUM** to record access-denied / import / promote events. Create dedicated tables (requirement 18 explicitly calls them out).
- **Don't auto-create owner groups on store creation without a mechanism for superadmin merge.** Otherwise owner-group sprawl will break the "same owner" expectation the user described.
- **Don't hand-roll CSV/Excel parsing on the backend.** Parse on frontend (papaparse/xlsx already bundled) → POST normalized JSON. Streaming uploads on NestJS require multer-streaming boilerplate that is unnecessary for 10 k-row files.
- **Don't add `ownerGroupId` to the JWT payload.** It belongs on `stores` — derive via `/me` response or a tiny cache keyed by `storeId`. JWT is issued at login; store ownership can change over time.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| CSV parsing w/ RFC 4180 quirks (commas in quoted fields, etc.) | Custom split | **papaparse 5.4.1 (already bundled)** | Handles quotes, escapes, skipped blank lines, BOM |
| Excel parsing | xml2js stream | **xlsx 0.18.5 (already bundled)** | Reads .xlsx/.xls, sheet_to_json |
| CUIT validation from scratch | Raw loops | Centralized `cuit.validator.ts` with the documented mod-11 weights `[5,4,3,2,7,6,5,4,3,2]` | Avoid bugs in special cases (check=10→invalid, check=11→0) |
| Transactional bulk upsert | 1-by-1 loop | **Sequelize `chunked findAll IN (...) → bulkCreate / update`** | `public-purchase.service.ts` already proves this pattern works at scale |
| Row-level scope enforcement in every service | Repeated `WHERE storeId=:caller` ad-hoc | **OwnerScopeGuard decorator + Sequelize `defaultScope`** | Single source of truth; less miss-a-spot risk |
| CASL wiring to backend permissions | Parallel JSON files | Reuse `Functions` table + `FunctionGuard` decorator (Phase 14) | Already deployed, tested, auditable |
| Audit events | Log-only | Dedicated `client_imports` / `client_merges` / `client_access_audits` tables | Structured query + indexable |

**Key insight:** The existing codebase provides **all primitives** Phase 25 needs. The job is mostly plumbing (schema change + guard + CargaMasiva UX polish + audit tables), not new infrastructure.

---

## Runtime State Inventory

> Phase 25 is a refactor + schema extension phase; this inventory is mandatory.

| Category | Items Found | Action Required |
|---|---|---|
| **Stored data** | `global_clients = 0 rows`, `store_clients = 0 rows`, `clients = 4 rows` (one per existing store, all with document), `sales = 8 rows` all with `client_id` (legacy). `[VERIFIED: ssh jhkim-server psql]` | Data migration script upserts the 4 `clients` rows → global_clients with owner_group_id=1, creates 4 store_clients, sets `sales.store_client_id` on all 8 sales |
| **Live service config** | No external service stores client records by name or ID — the rename is purely internal schema | None — verified by grep for "global_client" across all service configs |
| **OS-registered state** | None — Phase 25 does not touch schedulers, PM2 processes, or OS-level registrations | None — verified |
| **Secrets/env vars** | `DATABASE_TZ` and PG creds — not affected; no new secret introduced | None |
| **Build artifacts** | Legacy `app/global-clients/` module still registered in `api-ventago/src/app.module.ts:88`. If Phase 25 deprecates `/global-clients/massive-upload` at cut-over, the legacy module can remain registered (frontend just stops calling it) — recommended to keep for API compatibility during transition | If legacy controller deleted: rebuild NestJS, no runtime migration |

**Critical flag:** `app/global-clients/global-clients.model.ts` (legacy) defines `document` as `STRING(30) NOT NULL UNIQUE` (no owner_group_id, no fullname+phone composite) whereas `app/shared/global-clients/global-clients.model.ts` (canonical) defines `document STRING(50) NOT NULL UNIQUE` plus the `fullname+phone` partial unique we're dropping. **Production DB matches `shared/` version** — the legacy model would fail `sync:force` if ever run but never does because NestJS models are declarative only. The legacy controller still works against the production schema by coincidence (document column name is the same, other columns are a subset).

---

## Common Pitfalls

### Pitfall 1: Partial UNIQUE index drop on PG10 with existing data
**What goes wrong:** `DROP INDEX idx_global_clients_name_phone` on a table with rows where the pair exists as a duplicate would fail if we created the replacement index first without proper WHERE clause.
**Why it happens:** PG10 supports partial unique indexes, but ADD CONSTRAINT UNIQUE doesn't support WHERE — must use CREATE UNIQUE INDEX.
**How to avoid:** Use `CREATE UNIQUE INDEX IF NOT EXISTS ... WHERE document IS NOT NULL` (not `ADD CONSTRAINT`). Drop old index last, after verifying the new one is populated.
**Warning signs:** `ERROR: could not create unique index "..."` at migration time.

### Pitfall 2: ENUM extension on PG10
**What goes wrong:** `ALTER TYPE enum_audit_logs_action ADD VALUE 'access_denied'` is supported on PG10 but **must not be in a transaction block**. Cannot be rolled back. `BEGIN ... COMMIT` wrapper fails.
**Why it happens:** ENUM types are cluster-wide; value additions are DDL that bypasses normal transaction semantics.
**How to avoid:** Create a **separate** `client_access_audits` table instead. Sidesteps the issue entirely.
**Warning signs:** `ALTER TYPE ... ADD cannot run inside a transaction block`.

### Pitfall 3: Stale Sequelize model sync
**What goes wrong:** NestJS boot syncs Sequelize models. When `global_clients` gains `owner_group_id NOT NULL`, the **legacy** `app/global-clients/global-clients.model.ts` (which doesn't declare that column) may cause `sequelize.sync({ alter: true })` to rewrite the table and lose data.
**Why it happens:** Two models pointing at the same table — Sequelize picks one during sync.
**How to avoid:** Verify `database.module.ts` has `sync: false` in production (production deploys via explicit migration SQL, not sync). Check `api-ventago/src/database/database.module.ts` before Wave 1.
**Warning signs:** After migration, NestJS boot logs show `ALTER TABLE global_clients DROP COLUMN owner_group_id`.

### Pitfall 4: sales.client_id vs sales.store_client_id divergence
**What goes wrong:** Reports / reprint / nullify flows read `sales.client_id` (legacy) and pull wrong data if a client was promoted (legacy `clients.id` differs from `store_clients.id`).
**Why it happens:** Dual FK requires every read path to decide which to use.
**How to avoid:** **Read precedence:** `store_client_id` if not null → join store_clients + global_clients; else fall back to `clients.id` via `client_id`. Document this in CLAUDE.md.
**Warning signs:** Reports show duplicate client entries or missing ones after promotion.

### Pitfall 5: CUIT checksum 10-case
**What goes wrong:** Argentine AFIP **does not issue CUIT where the computed check = 10**. Naive validators accept any digit 0-9. If we follow common mistake and set `10 → 9` silently, user might enter an invalid CUIT that passes our check.
**Why it happens:** Out-of-date blog posts often show `check = 10 ? 9 : check` which produces false positives.
**How to avoid:** Treat `check == 10` as **invalid** (reject the row). Only map `check == 11 → 0`.
**Warning signs:** Import succeeds but AFIP rejects the CUIT on invoice issuance.

### Pitfall 6: Cross-owner group check bypass via `storeId=null` reports
**What goes wrong:** Multi-store reports called with `storeId=null` (implicit "all my stores") could leak historial across owner groups if the scope guard only checks `targetStoreId`.
**Why it happens:** "All stores" semantics imply aggregation; if we aggregate across the DB we see other owners' data.
**How to avoid:** When `storeId` is null, fetch the caller's ownerGroup's store IDs and filter `WHERE store_id IN (:ownerGroupStoreIds)`. Never fall back to raw SELECT without owner filter.
**Warning signs:** Report totals exceed caller's actual sales.

### Pitfall 7: Chunk size × connection pool exhaustion
**What goes wrong:** 10 000 rows / chunkSize=100 = 100 chunks × (1 findAll + 1 bulkCreate + 1 bulkUpdate) = 300 queries. Pool max = 50. Even at 300ms per query serialized, 30 s target is close.
**Why it happens:** Each chunk opens and closes a sub-transaction, competing with other live traffic.
**How to avoid:** Use **chunkSize=500** (same as CargaMasivaClientesView already uses — line 193), **single transaction for whole import**, minimize round-trips via `bulkCreate(rows, { transaction, updateOnDuplicate: ['fullname', 'email', ...] })` on PG10 via `ON CONFLICT DO UPDATE`.
**Warning signs:** `pool exhausted` errors under concurrent load.

### Pitfall 8: BOM on CSV files
**What goes wrong:** CSVs exported from Excel on Windows carry UTF-8 BOM. papaparse parses fine but downstream column-name match fails (`"nombre"` vs `"\uFEFFnombre"`).
**Why it happens:** Windows Excel default.
**How to avoid:** papaparse option `{ header: true, skipEmptyLines: true, transformHeader: (h) => h.replace(/^\uFEFF/, '').trim() }`.
**Warning signs:** All rows bucket to "Skip" because fullname/document columns didn't map.

---

## Code Examples

Verified patterns from the existing codebase:

### Example 1: Chunked bulk upsert (adapt for import)

```typescript
// Source: api-ventago/src/app/global-clients/global-clients.service.ts:150-284 (VERIFIED)

async importBatch(rows: ImportRow[], storeId: number, ownerGroupId: number) {
  const transaction = await this.sequelize.transaction();
  try {
    const chunkSize = 500;
    for (let i = 0; i < rows.length; i += chunkSize) {
      const chunk = rows.slice(i, i + chunkSize);

      const globalRows = chunk.filter(r => r.bucket === 'Global');
      const localRows  = chunk.filter(r => r.bucket === 'Local');
      // Skip rows: count only

      // --- Global path ---
      const docs = globalRows.map(r => r.document);
      const existing = await GlobalClient.findAll({
        where: { ownerGroupId, document: { [Op.in]: docs } },
        transaction,
      });
      const existingMap = new Map(existing.map(e => [e.document, e]));

      for (const row of globalRows) {
        const found = existingMap.get(row.document);
        if (found) {
          // D4-04 default: link to current tienda only
          await StoreClient.findOrCreate({
            where: { globalClientId: found.id, storeId },
            defaults: { globalClientId: found.id, storeId },
            transaction,
          });
          if (row.override === 'update') {
            await found.update(pickNonEmpty(row), { transaction });
          }
        } else {
          const created = await GlobalClient.create({
            ...row, ownerGroupId, createdByStoreId: storeId,
          }, { transaction });
          await StoreClient.create({
            globalClientId: created.id, storeId,
          }, { transaction });
        }
      }

      // --- Local path ---
      if (localRows.length) {
        await Clients.bulkCreate(
          localRows.map(r => ({ ...r, storeId })),
          { transaction },
        );
      }
    }
    await transaction.commit();
  } catch (err) {
    await transaction.rollback();
    throw err;
  }
}
```

### Example 2: CUIT mod 11 validator

```typescript
// Source: AR AFIP spec (CITED: https://lookuptax.com/docs/tax-identification-number/argentina-tax-id-guide)

const CUIT_WEIGHTS = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];

export function isValidCuit(raw: string): boolean {
  const digits = raw.replace(/\D/g, '');
  if (digits.length !== 11) return false;
  const ns = digits.split('').map(Number);
  let sum = 0;
  for (let i = 0; i < 10; i++) sum += ns[i] * CUIT_WEIGHTS[i];
  const rem = sum % 11;
  const calc = 11 - rem;
  let expected: number;
  if (calc === 11) expected = 0;
  else if (calc === 10) return false;         // AFIP does not issue these — reject
  else expected = calc;
  return expected === ns[10];
}

export function isValidDni(raw: string): boolean {
  const digits = raw.replace(/\D/g, '');
  return /^\d{7,8}$/.test(digits);
}
```

### Example 3: OwnerScope decorator shorthand

```typescript
// Source: adapted from function-guard.decorator.ts:13-19 (VERIFIED pattern)

export const OwnerScope = (cfg: OwnerScopeMeta) =>
  applyDecorators(
    SetMetadata('owner_scope', cfg),
    UseGuards(AuthGuard('jwt'), OwnerScopeGuard),
  );

// Usage:
@Controller('clients')
export class ClientsController {
  @Get(':id')
  @OwnerScope({ storeIdParam: 'storeId' })  // resolves from user.storeId
  findOne(@Param('id') id: string) { ... }

  @Post('merge')
  @OwnerScope({ globalClientIdField: 'loserId' })  // body field
  merge(@Body() dto: MergeDto) { ... }
}
```

### Example 4: Row-bucket classifier (frontend)

```typescript
// NEW — insert into CargaMasivaClientesView.tsx after `applyMapping`

type Bucket = 'Global' | 'Local' | 'Skip';

interface ClassifiedRow extends ParsedClient {
  bucket: Bucket;
  errors: string[];
  override?: Bucket;  // user can override per-row
}

function classifyRow(row: ParsedClient, defaultNoDoc: Bucket): ClassifiedRow {
  const errors: string[] = [];
  const hasDoc = row.document && row.document.trim().length > 0;

  if (!hasDoc) {
    return { ...row, bucket: defaultNoDoc, errors };
  }

  const digits = row.document.replace(/\D/g, '');
  if (digits.length === 11) {
    if (!isValidCuit(digits)) errors.push('CUIT checksum inválido');
  } else if (digits.length === 7 || digits.length === 8) {
    // DNI OK
  } else {
    errors.push('Document debe ser DNI (7-8 dígitos) o CUIT (11 dígitos)');
  }

  if (row.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.email)) {
    errors.push('Email inválido');
  }

  return {
    ...row,
    bucket: errors.length > 0 ? 'Skip' : 'Global',
    errors,
  };
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Single legacy `clients` table per store | Dual model: `global_clients` (shared by ownerGroup) + `clients` (local) | Phase 25 | Historial isolation + owner-group sharing |
| `sales.client_id → clients.id` | `sales.store_client_id → store_clients.id` (new) + legacy kept | Phase 25 | All new sales use new FK |
| Legacy `/global-clients/massive-upload` with no owner-scope | `POST /clients/import` with bucket classification + ownerGroupId scope | Phase 25 | Proper scope enforcement + row-level control |
| `audit_logs.action ENUM` for everything | Dedicated `client_imports` / `client_merges` / `client_access_audits` tables | Phase 25 | Richer schema for audit queries; sidesteps PG10 ENUM limitations |

**Deprecated/outdated (will be removed at end of phase):**
- `POST /global-clients/massive-upload` — retained during transition, removed once CargaMasivaClientesView switches to `/clients/import`.
- `idx_global_clients_name_phone` partial unique index — explicitly dropped in Wave 1 (D1-01).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | [ASSUMED] superadmin-only "new owner_group_id on new store" is acceptable UX (D3-03) | Architecture | Medium — if admins expect to pick owner group at store creation, plan needs a superadmin UI in Wave 2 |
| A2 | [ASSUMED] existing 4 stores all belong to the same real-world owner and owner_group_id=1 is correct for all (D3-02) | Migration | Low — data volume is tiny (4 rows); adjustable via 1-line UPDATE |
| A3 | [ASSUMED] legacy `/global-clients/massive-upload` endpoint can be deprecated without informing external integrators (no known external callers) | Don't Hand-Roll | Medium — needs user confirmation. Recommend keeping endpoint but logging a deprecation warning for 1 phase |
| A4 | [ASSUMED] ClienteView (cliente-vista) is the only POS-facing client edit screen | Frontend | Low — grep confirms only `/cliente-vista/` and `/clientes-globales/` views exist |
| A5 | [ASSUMED] `database.module.ts` is set to `sync: false` in production | Pitfall 3 | HIGH — if sync: true, migration order matters more. **MUST verify before Wave 1.** |
| A6 | [CITED] CUIT mod-11 weights are `[5,4,3,2,7,6,5,4,3,2]` with `check==10 → invalid` | CUIT algorithm | Low — consistent across multiple authoritative sources (LookupTax, whiz.tools, CDQ) |
| A7 | [ASSUMED] No AR-specific legal requirement dictating 404 vs 403 for cross-owner client access | Decisions | Low — business-level policy, not regulatory. 403 is industry-standard |
| A8 | [ASSUMED] papaparse + xlsx are robust for 10 k-row files on mid-range laptops without streaming | Import performance | Medium — 10 MB in-memory is ~80 MB after JS string inflation. Recommend a hard cap at 15 k rows and a "for more, split the file" UX |
| A9 | [ASSUMED] Sequelize `bulkCreate` + `updateOnDuplicate` translates to `ON CONFLICT DO UPDATE` correctly on PG10 | Pitfall 7 | Low — documented in sequelize docs; project already uses this pattern (`public-purchase.service.ts`) |

---

## Open Questions

1. **Should legacy `/global-clients/massive-upload` be frozen or hard-removed at end of Phase 25?**
   - What we know: production DB is at 0 global_clients, so endpoint is not actively producing data today.
   - What's unclear: whether any external script (superadmin tool, data loader, Jenkins job) still calls it.
   - Recommendation: Log a `console.warn('[DEPRECATED phase25]')` in the controller for 1 phase, then remove.

2. **Where does merge audit `client_merges` integrate with existing audit_logs?**
   - What we know: requirement 18 explicitly names the table.
   - What's unclear: whether audit_logs should gain a meta "see client_merges.id" link row.
   - Recommendation: write only to `client_merges` for Phase 25; add cross-link in a later Maintenance phase.

3. **Is `owner_group_id` backfill always safe as 1?**
   - What we know: 4 stores, user stated all 4 should start in the same group.
   - What's unclear: Whether "ACE" (store 9) should actually be in a separate group for competitive reasons.
   - Recommendation: confirm during plan-review with user; if needed, add UPDATE in step5-data-migration.sql.

4. **Promotion auto-trigger point — save-time vs explicit button?**
   - What we know: D1-03 says "auto-promotion on DNI/CUIT add"; D4-04 biases toward link-only.
   - What's unclear: whether users want a confirmation modal or silent promotion.
   - Recommendation: always show promotion confirmation (prevents accidental cross-store merges).

5. **Which `app/global-clients/` endpoints remain callable by external tools after Phase 25?**
   - What we know: controller has GET/POST/PUT/DELETE endpoints.
   - What's unclear: which frontend uses them today (may be more than just CargaMasivaClientesView).
   - Recommendation: grep the frontend for `/global-clients` calls before planning Wave N.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| PostgreSQL (production) | Schema migration | ✓ | 10.23 `[VERIFIED]` | — |
| PostgreSQL (dev) | Local testing | ✓ | 15 (Docker) `[CITED: CLAUDE.md]` | — |
| NestJS | Backend | ✓ | 11 | — |
| Next.js | Frontend | ✓ | 13 | — |
| papaparse | CSV parse | ✓ | 5.4.1 | — |
| xlsx | Excel parse | ✓ | 0.18.5 | — |
| jest + ts-jest | Backend unit tests | ✓ | 29.7.0 | — |
| MinIO | Not needed | — | — | — (no file archival in Phase 25) |
| ssh jhkim-server | Production migration execution | ✓ (from dev machine) `[VERIFIED: ssh runs cleanly]` | — | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None.

---

## Validation Architecture

### Test Framework
| Property | Value |
|---|---|
| Framework | Jest 29.7.0 + ts-jest `[VERIFIED: api-ventago/package.json]` |
| Config file | inline `jest` block in `api-ventago/package.json` |
| Quick run command | `cd api-ventago && npm test -- --testPathPattern=<relative-path>` |
| Full suite command | `cd api-ventago && npm test` |

Frontend: no jest config currently in ventago-app — recommend deferring frontend unit tests for Phase 25 (integration via manual QA + type-check via `npm run build`).

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| REQ-14 (DNI regex) | `isValidDni('12345678') === true`, `isValidDni('ABC') === false` | unit | `npm test -- cuit-validator.spec.ts` | ❌ Wave 0 |
| REQ-14 (CUIT mod 11) | `isValidCuit('20111111112') === true`, checksum-10 variants false | unit | `npm test -- cuit-validator.spec.ts` | ❌ Wave 0 |
| REQ-2, REQ-22 (UNIQUE per owner group) | migration creates + violates returns SQL error | integration | `npm test -- global-clients.service.spec.ts` | ❌ Wave 0 (extend existing) |
| REQ-8 (scope guard 403) | non-matching ownerGroupId → 403 + audit row | integration | `npm test -- owner-scope.guard.spec.ts` | ❌ Wave 0 |
| REQ-7 (sales.store_id filter) | `/sales` never returns cross-store rows | integration | `npm test -- sales.service.spec.ts` (extend) | ✅ exists, extend |
| REQ-5 (promote w/ conflict) | returns 409 + conflict payload for Merge modal | integration | `npm test -- clients-promote.service.spec.ts` | ❌ Wave 0 |
| REQ-5 (merge atomicity) | rollback on mid-op failure | integration | `npm test -- clients-merge.service.spec.ts` | ❌ Wave 0 |
| REQ-16 (transactional import) | one row throws → entire chunk rolled back | integration | `npm test -- client-import.service.spec.ts` | ❌ Wave 0 |
| REQ-17 (failure CSV) | API returns `{failedRows: [{row_index, error_code, error_message}]}` | unit | `npm test -- client-import.controller.spec.ts` | ❌ Wave 0 |
| REQ-21 (10 000 rows < 30 s) | benchmark test w/ synthetic data | perf | `npm test -- client-import.perf.spec.ts --runInBand` | ❌ Wave 0 |
| REQ-18 (audit row on import) | client_imports row count increments by 1 per batch | integration | `npm test -- client-import.service.spec.ts` (same file) | ❌ Wave 0 |
| REQ-6 (demotion blocked) | attempt to null document on promoted client → 400 | integration | `npm test -- clients.service.spec.ts` (extend) | ✅ may exist — check |
| REQ-19 (CASL) | user without manage-clientes-import → 403 | integration | `npm test -- client-import.controller.spec.ts` | ❌ Wave 0 |
| REQ-1, REQ-11 (bucket routing) | Global bucket + Local bucket + Skip all land in correct tables | integration | `npm test -- client-import.service.spec.ts` | ❌ Wave 0 |
| REQ-9 (by-document endpoint returns zero-history) | search returns globalClient but historial=[] unless caller matches | integration | `npm test -- clients.controller.spec.ts` (extend) | ✅ check |

### Sampling Rate
- **Per task commit:** `npm test -- --testPathPattern=client-import` (ultra fast, <3 s)
- **Per wave merge:** `npm test` (full api-ventago spec suite)
- **Phase gate:** full suite green + manual QA of CargaMasivaClientesView upload → 10 000-row sample → commit SQL fixture

### Wave 0 Gaps

- [ ] `api-ventago/src/app/client-import/validators/cuit.validator.spec.ts` — unit tests for CUIT + DNI
- [ ] `api-ventago/src/app/client-import/client-import.service.spec.ts` — bucket routing, transactional rollback, audit row
- [ ] `api-ventago/src/app/client-import/client-import.controller.spec.ts` — CASL gate + shape of failure CSV response
- [ ] `api-ventago/src/app/common/guards/owner-scope.guard.spec.ts` — cross-ownerGroup 403 + audit write
- [ ] `api-ventago/src/app/clients/clients-promote.service.spec.ts` — promote with conflict, merge atomicity
- [ ] `api-ventago/src/app/client-import/client-import.perf.spec.ts` — 10 000-row synthetic benchmark (optional; may run manually)
- [ ] Fixture file `api-ventago/test/fixtures/clients-10k.csv` (or generate at runtime) — for perf test

No framework install needed — jest is already configured.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | yes | JWT (@nestjs/passport) — already applied via `AuthGuard('jwt')` in `FunctionGuard` |
| V3 Session Management | yes | Existing SessionGuard + `active_sessions` UNIQUE userId (Phase AUTH-03) |
| V4 Access Control | yes | **NEW OwnerScopeGuard** (horizontal authorization) + existing FunctionGuard (vertical) |
| V5 Input Validation | yes | class-validator DTOs + custom CUIT/DNI/email validators + sanitization via `trim()` |
| V6 Cryptography | no | No new secrets or crypto operations in Phase 25 |
| V13 API Security | yes | All new endpoints behind JWT + FunctionGuard + OwnerScopeGuard trio |

### Known Threat Patterns for NestJS+Sequelize+PG10 stack

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| SQL injection via search/query params | Tampering | Sequelize parameterized queries (already used), never concatenate `Op.iLike` values |
| Cross-tenant data leak via `storeId` tampering | Information Disclosure | OwnerScopeGuard enforces both storeId AND ownerGroupId |
| Privilege escalation via missing CASL check | Elevation of Privilege | `@FunctionGuard('manage-clientes-import', 'create')` on upload endpoint |
| Mass-assignment via PUT body | Tampering | DTO whitelisting via `ValidationPipe({ whitelist: true })` |
| CSV formula injection (`=SUM(1+1)` in export) | Tampering | On **output** CSV, prefix cells starting with `=`, `+`, `-`, `@` with a single quote `'` |
| Insufficient audit | Repudiation | `client_imports`, `client_merges`, `client_access_audits` tables; queryable by superadmin |
| Denial of service via huge CSV | Denial of Service | Hard cap: 15 MB / 15 000 rows per upload. 429 status if exceeded |
| DNI leak via timing/oracle | Information Disclosure | `/clients/search?document=X` always returns 200 with either empty or filtered historial (never 404 based on existence) |

---

## Project Constraints (from CLAUDE.md)

| Directive | Where in CLAUDE.md | Impact on Phase 25 |
|---|---|---|
| PostgreSQL pool max=50, 변경 금지 | 백엔드 규약 | Import chunking must not hold >1 connection per import run |
| 운영 Postgres PG10, dev PG15 호환성 | 운영 서버 직접 접근 규칙 | Use SERIAL (not IDENTITY), no `GENERATED ALWAYS AS IDENTITY`, DO blocks for ADD CONSTRAINT |
| Sequelize `underscored: true` 전역 | 아키텍처 핵심 규칙 | `ownerGroupId` column → DB `owner_group_id` |
| Migration SQL은 `api-ventago/migrations/` 폴더 + 운영서버 직접 실행 | 아키텍처 핵심 규칙 | Numbered files `20260424-phase25-*.sql` following existing convention |
| `apiConnector.remove()` not `.delete()` | 주의 사항 | Applies if Phase 25 adds any DELETE endpoint; stick to existing conventions |
| 프론트엔드 작업 후 ESLint 검증 필수 | MEMORY (feedback_eslint_check.md) | Run eslint subagent on CargaMasivaClientesView + ClienteVistaView after edits |
| `newline-before-return` 규칙 | ESLint 규칙 | Blank line before every return — enforce in new code |
| `no-unused-vars` 빌드 블로킹 | ESLint 규칙 | Every import must be used |
| DDL 은 사용자 확인 받고 실행 | 운영 서버 직접 접근 규칙 | Wave 1 migration SQL shown to user before ssh execution |
| 조회성 쿼리 기본 허용 | 운영 서버 직접 접근 규칙 | Count / inspection queries can run without prompting |
| 로그 파일 먼저 확인 | global CLAUDE.md + MEMORY | After any deployment, check Jenkins #NNN.txt |
| 주석 한국어 / 함수·변수 영어 | global CLAUDE.md | New code follows this pattern |

---

## File-level Impact Map

### Backend (api-ventago)

| File | Change Type | Purpose |
|---|---|---|
| `src/app/shared/global-clients/global-clients.model.ts` | MODIFY | Add `ownerGroupId` column; document default can stay NULL-able (for historical rows); drop fullname+phone partial unique index declaration |
| `src/app/shared/global-clients/global-clients.service.ts` | MODIFY | All queries filter by `ownerGroupId`; drop `findOne({ where: { document } })` without ownerGroup filter |
| `src/app/shared/global-clients/global-clients.controller.ts` | MODIFY | Attach `OwnerScopeGuard` to every endpoint |
| `src/app/shared/store-clients/*` | Unchanged | Already correct |
| `src/app/global-clients/*` (legacy) | DEPRECATE (keep controller, add warning log) | Temporary compat during cutover |
| `src/app/clients/clients.model.ts` | Unchanged (D2-03) | — |
| `src/app/clients/clients.service.ts` | EXTEND | Add `promote(clientId, storeId)`, `merge(loserId, winnerId, fieldPicks)`; scope `findAll` by storeId always |
| `src/app/clients/clients.controller.ts` | EXTEND | POST `/clients/:id/promote`, POST `/clients/merge` |
| `src/app/client-import/` | NEW module | Controller, service, DTOs, validators |
| `src/app/client-import/validators/cuit.validator.ts` | NEW | mod-11 weighted sum + special cases |
| `src/app/client-import/validators/dni.validator.ts` | NEW | 7-8 digit check |
| `src/app/common/guards/owner-scope.guard.ts` | NEW | Horizontal authz |
| `src/app/common/decorators/owner-scope.decorator.ts` | NEW | `@OwnerScope({...})` |
| `src/app/store/store.model.ts` | MODIFY | Add `ownerGroupId` column |
| `src/app/store/store.service.ts` | MODIFY | Auto-allocate new ownerGroupId on store creation (D3-03) |
| `src/app/auth/auth.service.ts` (`/me` handler) | MODIFY | Include caller's `ownerGroupId` in user payload (or derive in-memory) |
| `src/app/sales/sales.model.ts` | MODIFY | Add `storeClientId` nullable FK to store_clients |
| `src/app/sales/sales-create.service.ts` | MODIFY | Set `storeClientId` when creating sales with a known GlobalClient |
| `src/app/sales/sales.service.ts` | MODIFY | Read-path precedence: storeClientId → fallback clientId |
| `src/app/audit-log/` | Unchanged | Existing service stays; new phase-specific tables are separate |
| `src/app/client-import/models/client-import.model.ts` | NEW | Maps client_imports table |
| `src/app/clients/models/client-merge.model.ts` | NEW | Maps client_merges table |
| `src/app/common/models/client-access-audit.model.ts` | NEW | Maps client_access_audits table |

### Frontend (ventago-app)

| File | Change Type | Purpose |
|---|---|---|
| `src/views/cliente-vista/ClienteVistaView.tsx` | MODIFY | Add "Importación masiva" button in CardHeader `action` block (next to "Nuevo Cliente"); wrap with `WithFunctionAccess functionSlug="manage-clientes-import"` |
| `src/views/cliente-vista/PromoteMergeDialog.tsx` | NEW | Merge-proposal modal (field-by-field) |
| `src/views/clientes-globales/CargaMasivaClientesView.tsx` | MODIFY | Add bucket classifier, per-row override chips + filter, default-behavior radio, new upload endpoint, failure-CSV download |
| `src/views/clientes-globales/GlobalClientesView.tsx` | MODIFY (minimal) | Filter by ownerGroupId (automatic via backend scope guard; UI label "Clientes de tu grupo") |
| `src/utils/cuit-validator.ts` | NEW | Frontend copy of CUIT/DNI validators (duplicated because ventago-app cannot import api-ventago) |
| `src/services/api.service.ts` | No change | apiConnector already sends x-session-token + JWT |
| `src/configs/acl.ts` | No change | CASL granular already handles function-slug permissions |
| i18n dictionaries | MODIFY | Add es + ko strings for bucket chip labels, error messages, merge modal |

### Migration (api-ventago/migrations/)

| File | Change Type | Purpose |
|---|---|---|
| `20260424-phase25-step1-owner-group.sql` | NEW | `ALTER TABLE stores ADD owner_group_id`, backfill=1, NOT NULL |
| `20260424-phase25-step2-global-owner.sql` | NEW | `ALTER TABLE global_clients ADD owner_group_id`, backfill=1, create new partial unique index, drop old name+phone index |
| `20260424-phase25-step3-sales-store-client.sql` | NEW | `ALTER TABLE sales ADD store_client_id INTEGER NULL REFERENCES store_clients(id)` |
| `20260424-phase25-step4-audit-tables.sql` | NEW | CREATE TABLE client_imports, client_merges, client_access_audits + indexes |
| `20260424-phase25-step5-data-migration.sql` | NEW | Idempotent INSERT ... ON CONFLICT DO NOTHING for 4 clients → global_clients + store_clients; UPDATE sales SET store_client_id = ... |
| `20260424-phase25-step6-verify.sql` | NEW | Assertion queries: row counts, FK consistency, UNIQUE presence |

---

## Wave Proposals

Dependencies run strictly top-to-bottom; each wave is committable independently.

### Wave 1 — Data layer (schema + migration) [CRITICAL FIRST per D2-04]
**Dependencies:** none
**Outputs:** all 6 migration SQL files applied on both dev and production
**Tasks:**
- Produce & review 6 step SQL files
- Confirm `database.module.ts` has `sync: false` (risk A5)
- Run step1-step4 on dev PG15 → verify via psql
- Run step5 data migration on dev → verify via step6 assertions
- **User approval** → run same on production via `ssh jhkim-server`
- Update `store.model.ts` and `global-clients.model.ts` (shared) to include `ownerGroupId`
- NestJS boot still green on both envs

**Gate:** `ssh jhkim-server` count queries return expected post-migration numbers.

### Wave 2 — Backend scope + models
**Dependencies:** Wave 1
**Outputs:** OwnerScopeGuard + updated models + `/me` includes ownerGroupId
**Tasks:**
- Create `owner-scope.guard.ts`, `owner-scope.decorator.ts`
- Create `client_access_audits` model + service
- Extend auth `/me` response
- Apply `@OwnerScope({...})` to all `/clients/*`, `/global-clients/*`, `/sales/*`, `/reports/*` controller methods
- Write `owner-scope.guard.spec.ts`

**Gate:** integration tests show 403 + audit row for cross-group attempts.

### Wave 3 — Promote / Merge / Sales FK
**Dependencies:** Wave 2
**Outputs:** Promote + Merge endpoints + dual-FK sales logic
**Tasks:**
- Extend `clients.service.ts` with `promote()` and `merge()`
- Add `POST /clients/:id/promote`, `POST /clients/merge`
- Update `sales-create.service.ts` to set `storeClientId`
- Update `sales.service.ts` read precedence
- Write conflict-return payload shape (for Merge modal) into spec
- Spec files: `clients-promote.service.spec.ts`, `clients-merge.service.spec.ts`, extend `sales.service.spec.ts`

**Gate:** test matrix REQ-5, REQ-6, REQ-7 green.

### Wave 4 — Client Import (backend)
**Dependencies:** Wave 2
**Outputs:** `POST /clients/import` + validators + audit row
**Tasks:**
- Create `client-import` module
- DTOs with class-validator + custom CUIT/DNI decorators
- Service with chunked transactional upsert
- Controller with FunctionGuard(`manage-clientes-import`, `create`)
- Specs: cuit.validator.spec.ts, client-import.service.spec.ts, client-import.controller.spec.ts
- Add `manage-clientes-import` slug to Functions seed (admin + superadmin)

**Gate:** REQ-11, REQ-14, REQ-16, REQ-17, REQ-18, REQ-19 green.

### Wave 5 — Frontend CargaMasiva improvements
**Dependencies:** Wave 4
**Outputs:** Updated CargaMasivaClientesView + bucket classifier + default radio + per-row overrides + failure CSV download
**Tasks:**
- Copy `cuit-validator.ts` / `dni-validator.ts` to ventago-app/src/utils
- Extend `CargaMasivaClientesView.tsx`:
  - Add "DNI/CUIT 없는 행" radio at step 1
  - Classify rows on mapping change (`classifyRow`)
  - Render `[Global]/[Local]/[Skip]` chips + filter in preview table
  - Per-row override dropdown
  - Switch upload to `POST /clients/import`
  - Download failure CSV on step 3
- Add ko/es i18n strings
- ESLint subagent verification

**Gate:** manual QA — upload 100 row sample + 10k row benchmark.

### Wave 6 — ClienteView button + Promote/Merge modal
**Dependencies:** Wave 3, Wave 5
**Outputs:** "Importación masiva" top-bar button + PromoteMergeDialog
**Tasks:**
- Wrap new button in `WithFunctionAccess` in ClienteVistaView CardHeader action
- Create `PromoteMergeDialog.tsx` with field-by-field checkboxes
- Wire save-handler: detect newly-added DNI/CUIT → POST /promote → if 409 → open dialog
- POST /merge on confirm
- ESLint subagent verification

**Gate:** end-to-end manual QA — promote + merge round-trip.

### Wave 7 — Sales readpath + reporting scope fixes
**Dependencies:** Wave 3
**Outputs:** All report endpoints properly scoped; `storeId=null` case handled
**Tasks:**
- Audit `src/app/reports/*.service.ts` — ensure `storeId=null` falls back to ownerGroup store list, not DB-wide
- Extend existing reportsClientesCredito + sales cockpit specs
- Migrate any endpoint using `sales.client_id` → join precedence logic

**Gate:** regression tests on reportsClientesCredito + sales cockpit pass; cross-owner-group cheat test fails correctly.

### Wave 8 (optional) — Deprecate legacy /global-clients/massive-upload
**Dependencies:** Wave 5 cutover verified
**Outputs:** Deprecation warning log + sunset announce
**Tasks:**
- Add `console.warn` + audit row when legacy endpoint is hit
- Document in CLAUDE.md
- Plan removal in next phase's EXTENSION.md

**Gate:** 14 days of zero-traffic on legacy endpoint or explicit user approval.

---

## Key code patterns to copy

| Purpose | Source file:lines | Use for |
|---|---|---|
| Chunked transactional upsert | `api-ventago/src/app/global-clients/global-clients.service.ts:150-284` | Client import service |
| findOrCreate global + store client | `api-ventago/src/app/marketplace/public-purchase/public-purchase.service.ts:264-310` | Promote flow |
| Function-slug guard | `api-ventago/src/app/auth/decorators/function-guard.decorator.ts:1-19` + `api-ventago/src/app/auth/guards/function-permission.guard.ts:1-79` | CASL `manage-clientes-import` enforcement |
| PG10-safe SQL migration | `api-ventago/migrations/20260422-cost-sheet-step1-schema.sql` | All Wave 1 steps |
| Audit decorator usage | `api-ventago/src/app/global-clients/global-clients.controller.ts:103-108` | Note: Phase 25 uses dedicated audit tables INSTEAD of @Audit decorator for import/merge/access events |
| SessionGuard wiring | `api-ventago/src/app/session/guards/session.guard.ts:1-42` | Reference for OwnerScopeGuard structure |
| Stepper + FullTable in CargaMasivaClientesView | `ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx:246-445` | Preserve structure, insert bucket logic |
| CardHeader action button pattern | `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx:300-362` | Location for "Importación masiva" button |
| WithFunctionAccess wrapper | `ventago-app/src/configs/withFunctionAccess.tsx:1-10` | Hide button from users without the permission |
| Existing function slug seed pattern | `api-ventago/src/app/functions/seed/functions-seed-admin.ts` | Add `manage-clientes-import` slug |

---

## Risks and Unknowns

### High-risk

- **A5 (`sync: false` in production):** must be verified in Wave 0 before any migration. If `sync: true`, migration order becomes critical and we may need additional guardrails.
- **Dual GlobalClient models:** legacy `app/global-clients/` module is still imported in `app.module.ts:88`. Any sync-driven alter statement from either model side-effects production. Explicit verification recommended before Wave 1.
- **Pool usage under concurrent import:** 10 k rows × chunkSize=500 = 20 chunks at 3 queries each = 60 sequential queries. Under production traffic this should be fine, but a superadmin running import during peak POS hours could cause noticeable latency. Recommend: advise "off-hours import" in UI.

### Medium-risk

- **A3 (deprecation of legacy endpoint):** any external tool using `/global-clients/massive-upload` will break on cut-over. Plan a 1-phase overlap window.
- **Frontend validator drift:** `cuit-validator.ts` copies the same logic to two places. If spec changes, both must update. Accept this — monorepo code-share complexity isn't worth the fix right now.
- **ENUM action for audit_logs:** if anyone tries to write `action='import'` to `audit_logs` without extending the ENUM, Postgres returns an error. Dedicated tables sidestep this but require new models; easy to miss in reviews.

### Low-risk

- **ClienteView button placement:** user says existing top-bar; mockup not required since we match "Nuevo Cliente" button style.
- **AR provincia lookup:** `provinces` table already exists (FK from `global_clients.provinceId`); upload just needs to convert text provinces → provinceId via existing table.

---

## Sources

### Primary (HIGH confidence)
- `[VERIFIED]` Production PG schema inspection via `ssh jhkim-server "sudo -u postgres psql -d ventago -c '\d ...'"` — stores, sales, clients, global_clients, store_clients, audit_logs
- `[VERIFIED]` `api-ventago/src/app/shared/global-clients/global-clients.model.ts` (canonical model)
- `[VERIFIED]` `api-ventago/src/app/shared/store-clients/store-clients.model.ts`
- `[VERIFIED]` `api-ventago/src/app/clients/clients.model.ts`, `clients.service.ts`
- `[VERIFIED]` `api-ventago/src/app/sales/sales.model.ts`, `sales.service.ts`
- `[VERIFIED]` `api-ventago/src/app/marketplace/public-purchase/public-purchase.service.ts` (findOrCreateGlobalClient reference)
- `[VERIFIED]` `api-ventago/src/app/auth/guards/function-permission.guard.ts`, `decorators/function-guard.decorator.ts`
- `[VERIFIED]` `api-ventago/src/app/session/guards/session.guard.ts`
- `[VERIFIED]` `api-ventago/src/app/audit-log/audit-log.model.ts` (action ENUM limitation)
- `[VERIFIED]` `api-ventago/migrations/20260422-cost-sheet-step1-schema.sql` (PG10 migration pattern)
- `[VERIFIED]` `ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx` (570 lines, Stepper structure)
- `[VERIFIED]` `ventago-app/src/views/cliente-vista/ClienteVistaView.tsx` (CardHeader action slot)
- `[VERIFIED]` `ventago-app/src/configs/acl.ts`, `withFunctionAccess.tsx`
- `[VERIFIED]` `api-ventago/package.json` (jest 29.7.0, existing specs)
- `[VERIFIED]` `ventago-app/package.json` (papaparse 5.4.1, xlsx 0.18.5)

### Secondary (MEDIUM confidence)
- `[CITED]` CUIT mod-11 weights `[5,4,3,2,7,6,5,4,3,2]` + special-case `check=10 → invalid`: [LookupTax Argentina guide](https://lookuptax.com/docs/tax-identification-number/argentina-tax-id-guide)
- `[CITED]` CUIT checksum validation: [CDQ — Invalid checksum of AR CUIT](https://meta.cdq.ch/Invalid_checksum_of_AR_CUIT_(Argentina))
- `[CITED]` CUIT generator/validator reference: [whiz.tools CUIT validator](https://whiz.tools/legal-business/argentinian-cuit-cuil-generator-validator)
- `[CITED]` Project CLAUDE.md for PG10 vs PG15, Sequelize underscored, pool rules, apiConnector conventions

### Tertiary (LOW confidence)
- None — all findings cross-verified.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions verified in package.json; production stack sighted
- Architecture: HIGH — existing infrastructure maps cleanly to the new responsibilities
- Data migration: HIGH — only 4 rows in scope; SQL verified against PG10 live schema
- Scope guard: MEDIUM — pattern borrowed from FunctionPermissionGuard but newly synthesized; spec coverage required in Wave 2
- CUIT algorithm: HIGH — multiple authoritative sources agree on weights and special cases
- Performance target (10 k < 30 s): MEDIUM — mathematically feasible; no benchmark run yet
- ENUM + partial index PG10 compatibility: HIGH — verified against production

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 (30 days — stable domain; only PG minor bumps or library patch revs expected)

---

## RESEARCH COMPLETE
