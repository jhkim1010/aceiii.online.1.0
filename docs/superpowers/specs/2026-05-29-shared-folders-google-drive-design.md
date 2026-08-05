# Carpetas Compartidas (Google Drive Integration) — Design

**Status:** Draft for implementation
**Date:** 2026-05-29
**Author:** brainstorming session (junghokim10@gmail.com)
**Phase target:** To be assigned at planning time via `/gsd-add-phase` (end of
current milestone) or `/gsd-insert-phase` (decimal between existing phases).

## Goal

Surface a configurable set of Google Drive folders inside Ventago as a sidebar entry
**"Carpetas Compartidas"** (Herramientas section), gated by CASL permissions and a
per-folder × per-role read/write access matrix. Each store registers its own folders
and assigns role-based access. Files are listed, previewed, downloaded, uploaded,
renamed and trashed via the Ventago backend (no end-user Google session required).

## Why

Stores routinely keep operational documents (menús, catálogos, políticas, fichas
técnicas, fotos de campañas) in Google Drive and want a single in-app surface to
distribute them to staff with controlled access. Today operators have to be sent
Drive links one by one, with permissions managed manually outside the system —
fragile, easy to leak, and impossible to audit.

This feature gives:
- A discoverable in-app entry point (sidebar).
- Per-store admin self-service to register folders and grant role-based access.
- Read/write distinction so most staff can only consume, while specific roles can
  contribute (e.g., uploading shift photos).
- Auditability of who accessed / downloaded / uploaded what.

## Non-goals (v1, YAGNI)

- ❌ Recursive subfolder navigation — v1 lists the contents of each registered
  folder as a flat view; subfolder browsing is a v2 follow-up.
- ❌ Version history UI — Drive's own version tracking continues to exist; we
  don't surface it.
- ❌ Comments / collaboration on files.
- ❌ Issuing shareable links to external parties.
- ❌ Per-user OAuth — the service-account model covers the "shared folders" intent.
- ❌ Full-text content indexing — Drive API's `q=fullText contains '...'` covers
  basic name/content search.
- ❌ Two-way sync / backup.

## Integration model

**Service account + Shared Drive (chosen).** A single Google service account
(per Ventago deployment) is configured at the platform level. Store admins share
their Drive folders or Shared Drives with the service account's email; the
Ventago backend uses the SA credentials server-side to list, stream and modify
content. End users never authenticate with Google.

**Implication — Shared Drive required for write operations.** A service account
has no storage quota of its own, so files it creates inside a non-Shared-Drive
folder fail. The UI explicitly flags this: registering a non-Shared-Drive folder
is allowed for **read-only** access; write access requires a Shared Drive.

**Why not the alternatives.**
- Per-store OAuth would force the admin through a Google consent flow and add
  refresh-token plumbing for marginal benefit.
- Per-user OAuth doesn't match the "shared folders" mental model.
- Generating temporary public links breaks the per-role permission model since
  links are effectively public while active.

## User-visible behavior

### Sidebar

- New auxiliary module **"Carpetas Compartidas"** (`/carpetas-compartidas`) under
  the existing **Herramientas** section. Icon: `tabler:cloud-share`.
- New auxiliary module **"Configurar Carpetas Compartidas"**
  (`/configuracion/carpetas-compartidas`) under Herramientas, visible only to
  users holding the `administrar-carpetas-compartidas` function. Icon: `tabler:settings`.
- Both items are sourced from the `modules` table seed (no hardcoded entries),
  so visibility is automatically driven by CASL.

### Folder list page (`/carpetas-compartidas`)

- Card grid of all folders the current user can access (read or write).
- Each card: icon, name, description, badge `Editor` if `canWrite`, badge
  `Solo lectura` otherwise. Click navigates into the folder.
- Loading state: skeleton grid.
- Empty state: "Aún no hay carpetas asignadas a tu usuario. Contactá al
  administrador."

### Folder browser page (`/carpetas-compartidas/[folderId]`)

- Breadcrumb: `Carpetas Compartidas › {folder name}`.
- Toolbar: search input (Drive `q=name contains '...'`), sort selector,
  **Subir archivo** button (only if `canWrite`).
- File table (AG Grid, pageSize 50): icon | name | type | size | modified |
  actions. Action column hides write actions when `canWrite=false`.
- Click row → inline preview modal:
  - PDF: rendered via pdf.js, served by `/preview` proxy stream.
  - Images: rendered via `next/Image` pointing at `/preview`.
  - Google Docs/Sheets/Slides: server exports to PDF, rendered as PDF.
  - Other types: download-only fallback with "No se puede previsualizar este
    tipo de archivo" notice + Download button.
- Upload (drag-drop + click): single or multiple files, progress bar per file,
  413 handling for over-limit files.
- Delete: moves to Drive Trash (`trashed: true`) with explicit "Mover a
  papelera de Google Drive" confirm copy. No permanent delete in v1.
- Rename: dialog with name validation (no `/`, no control chars).

### Admin pages (`/configuracion/carpetas-compartidas`)

#### Folders tab
- Table of registered folders for this store: name, Drive folder ID, type
  (Shared Drive / Folder), state (active/inactive), role mappings count, actions.
- **Registrar carpeta** button → dialog:
  - Inline guide showing the SA email and instructions to share the folder.
  - SA email displayed as `<code>` with copy-to-clipboard button.
  - Inputs: `googleFolderId` (paste URL or ID — backend parses both), `name`,
    `description?`, `isSharedDrive` toggle, `sharedDriveId` (when enabled).
  - **Verificar** button → backend calls Drive API to confirm SA access; on
    failure shows "La cuenta de servicio aún no tiene acceso. Agregá
    `{SA_EMAIL}` como miembro de la carpeta y reintentá."
- Edit / activate / deactivate / delete actions on each row.
- Delete only removes the Ventago registration row — Drive contents are not
  touched.

#### Permisos tab (per folder)
- Matrix view: rows = roles in this store, columns = `Lectura` and
  `Escritura` checkboxes.
- Save button writes the full mapping atomically (delete-then-insert in a
  transaction).
- Helper text: "Solo los roles con al menos una marca aparecerán como
  autorizados."

#### Logs tab (`/configuracion/carpetas-compartidas/logs`)
- AG Grid of access log entries with filters: folder, user, action, date range.
- Default view: last 7 days, all folders this store owns.
- CSV export of current filter result.

### Permission semantics

- Sidebar visibility: holding the CASL function `ver-carpetas-compartidas`
  (action `read`) controls whether the user-facing entry appears. Without it
  the user-facing feature is invisible.
- Folder-level access: enforced at the API layer via the
  `shared_folder_role_access` table. The CASL function alone is intentionally
  coarse so the permissions seed does not balloon as folders are added.
- A user "can read" a folder iff any of their roles has a row with
  `can_read=true` for that folder; same for write. Permissions are OR-aggregated
  across roles.
- Admin actions on folder configuration require the CASL function
  `administrar-carpetas-compartidas` (action `manage`) plus tenant match
  (`folder.store_id === user.storeId`).
- Log-viewing requires the CASL function `ver-logs-de-carpetas` (action `read`).

### Error visibility (per project memory `feedback_error_visibility`)

Every error surfaces both:
1. Inline `<Alert severity="error">` directly above the affected action area.
2. Global prominent toast (notistack, auto-close OFF, action buttons).

Specific messages:
- SA access verification failed → "Esta carpeta aún no está compartida con
  `{SA_EMAIL}`. Agregalo como editor y reintentá." + copy button.
- Drive 429 → "Demasiadas solicitudes a Google Drive. Reintentá en unos
  segundos."
- File too large → "El archivo supera el límite de {N} MB."
- Per-folder 403 → "No tenés permiso para esta acción en esta carpeta."

## Architecture

### Data model

Three new tables. All follow project conventions verified against
`.planning/intel/db-schema-tables.md`:
- PK: `integer NOT NULL DEFAULT nextval('<table>_id_seq'::regclass)` (SERIAL,
  PG10-compatible).
- Timestamps: `created_at` / `updated_at` as `timestamp with time zone NOT
  NULL`, no DEFAULT (Sequelize hooks fill them — matches existing tables).
- FK naming: `store_id → stores(id)`, `user_id → users(id)`,
  `role_id → roles(id)`.
- Booleans use `is_*` prefix.

#### `shared_folders`
```
id                  integer       NOT NULL  nextval('shared_folders_id_seq')
store_id            integer       NOT NULL  → stores(id)
google_folder_id    varchar(128)  NOT NULL
is_shared_drive     boolean       NOT NULL  DEFAULT false
shared_drive_id     varchar(128)  NULL
name                varchar(255)  NOT NULL
description         text          NULL
sort_order          integer       NOT NULL  DEFAULT 0
is_active           boolean       NOT NULL  DEFAULT true
user_id             integer       NOT NULL  → users(id)   -- registrar
created_at          timestamptz   NOT NULL
updated_at          timestamptz   NOT NULL

UNIQUE (store_id, google_folder_id)
INDEX  (store_id, is_active, sort_order)
CHECK  (is_shared_drive = false OR shared_drive_id IS NOT NULL)
```

#### `shared_folder_role_access`
```
id                  integer       NOT NULL  nextval('shared_folder_role_access_id_seq')
shared_folder_id    integer       NOT NULL  → shared_folders(id) ON DELETE CASCADE
role_id             integer       NOT NULL  → roles(id)          ON DELETE CASCADE
can_read            boolean       NOT NULL  DEFAULT true
can_write           boolean       NOT NULL  DEFAULT false
created_at          timestamptz   NOT NULL
updated_at          timestamptz   NOT NULL

UNIQUE (shared_folder_id, role_id)
INDEX  (role_id)
CHECK  (can_read OR can_write)           -- empty rows are not persisted
```

#### `shared_folder_access_logs`
```
id                  bigint        NOT NULL  nextval('shared_folder_access_logs_id_seq') -- bigserial
store_id            integer       NOT NULL  → stores(id)
user_id             integer       NOT NULL  → users(id)
shared_folder_id    integer       NOT NULL  → shared_folders(id)
action              varchar(20)   NOT NULL  -- 'list'|'download'|'preview'|'upload'|'delete'|'rename'
google_file_id      varchar(128)  NULL                  -- external Drive id, no FK
file_name           varchar(500)  NULL
bytes               bigint        NULL
ip_address          inet          NULL
user_agent          text          NULL
created_at          timestamptz   NOT NULL
updated_at          timestamptz   NOT NULL

INDEX (store_id, created_at DESC)
INDEX (user_id, created_at DESC)
INDEX (shared_folder_id, created_at DESC)
```
Event time uses `created_at` (no separate `*_at` column — matches `audit_logs`).

#### Modules + Functions seed (CASL)

The project's CASL model is `modules → functions → role_function_actions`
(no separate `subjects` table). CASL "subjects" surface in the frontend as
function slugs; CASL "actions" are rows in `role_function_actions`. Seed
updates go to two existing files (see existing seed precedents in
`functions.seed.ts` such as the `logsAuditoriaModule` block):

**1. `api-ventago/src/app/modules/seed/modules.seed.ts`** — two new entries
under `appSlug: 'admin'` (the `app_id` is resolved from this slug; sidebar
placement is driven by `isAuxiliary`, not by app group):

```typescript
{
  name: 'Carpetas Compartidas',
  slug: 'carpetas-compartidas',
  description: 'Acceso a carpetas de Google Drive compartidas con la tienda',
  icon: 'tabler:cloud-share',
  url: '/carpetas-compartidas',
  isMain: false,
  isAuxiliary: true,            // → rendered under "Herramientas" section
},
{
  name: 'Configurar Carpetas Compartidas',
  slug: 'configurar-carpetas-compartidas',
  description: 'Registrar carpetas de Drive y asignar permisos por rol',
  icon: 'tabler:settings',
  url: '/configuracion/carpetas-compartidas',
  isMain: false,
  isAuxiliary: true,
},
```

**2. `api-ventago/src/app/functions/seed/functions.seed.ts`** — add functions
keyed to the new modules. Each function name follows the
`[App › Módulo] Acción` convention used in existing seeds:

```typescript
// ─── Carpetas Compartidas (user-facing) ───
const carpetasCompartidasFunctions = [
  { name: 'Ver carpetas compartidas',
    description: '[Admin › Carpetas Compartidas] Ver listado de carpetas y archivos' },
  { name: 'Subir y editar archivos',
    description: '[Admin › Carpetas Compartidas] Subir, renombrar y mover a papelera archivos en carpetas autorizadas' },
];
// findOrCreate against module slug 'carpetas-compartidas'

// ─── Configurar Carpetas Compartidas (admin) ───
const configurarCarpetasFunctions = [
  { name: 'Administrar carpetas compartidas',
    description: '[Admin › Configurar Carpetas] Registrar/editar/eliminar carpetas y definir matriz de permisos' },
  { name: 'Ver logs de carpetas',
    description: '[Admin › Configurar Carpetas] Consultar historial de acceso, descargas y subidas' },
];
// findOrCreate against module slug 'configurar-carpetas-compartidas'
```

`generateSlug()` (already in the seed file) produces the CASL subject slug
from each function name (e.g., `ver-carpetas-compartidas`,
`administrar-carpetas-compartidas`). These slugs become the `subject` values
the frontend nav consumes (`{ ..., action: 'read', subject:
'ver-carpetas-compartidas' }`).

Per-store role assignment (which roles get which functions+actions) is done
through the existing permissions UI (`/configuracion/permisos`), not through
seed — same pattern as every other module.

**Independence from per-folder access matrix.** The CASL functions above only
gate **feature visibility** (sidebar entries, page access). Per-folder
`can_read`/`can_write` is a separate, finer-grained layer enforced by the
`shared_folder_role_access` table and the `SharedFolderAccessGuard`. A user
must clear *both* layers to perform a per-folder action.

#### Migration

Single file `api-ventago/migrations/<NN>-create-shared-folders.sql` containing
the three new tables, their indexes, and CHECK constraints. PG10-compatible
syntax only (uses `SERIAL`/`nextval`, no `GENERATED AS IDENTITY`; uses
`inet`, `CHECK`, `UNIQUE`).

`modules` and `functions` rows are **not** added in this SQL file — they go
in the TypeScript seed scripts (`modules.seed.ts`, `functions.seed.ts`) shown
above, which are idempotent (`findOrCreate`) and run during backend
bootstrap. This matches the precedent for every other module in the project.

After deployment, regenerate the intel files:
```bash
./.planning/intel/db-schema.regen.sh
```
and commit the updates.

### Backend module

Located at `api-ventago/src/app/shared-folders/`:
```
shared-folders.module.ts
models/
  shared-folder.model.ts
  shared-folder-role-access.model.ts
  shared-folder-access-log.model.ts
services/
  google-drive.service.ts            # SA client singleton + Drive API wrapper
  shared-folders.service.ts          # User-facing operations + audit
  shared-folders-admin.service.ts    # Folder registration + role-access management
  folder-access-resolver.service.ts  # user → roles → can_read/can_write resolver
guards/
  shared-folder-access.guard.ts      # Reads @RequireFolderAccess metadata
decorators/
  require-folder-access.decorator.ts
dto/
  list-files.dto.ts
  register-folder.dto.ts
  update-role-access.dto.ts
  upload-file.dto.ts
controllers/
  shared-folders.controller.ts            # /carpetas-compartidas/*
  shared-folders-admin.controller.ts      # /carpetas-compartidas/admin/*
```

#### `google-drive.service.ts`

Singleton built at module init. Uses official `googleapis` SDK; the library
handles token caching and refresh internally.

```typescript
private readonly drive: drive_v3.Drive
private readonly saEmail: string
constructor() {
  const auth = new google.auth.GoogleAuth({
    keyFile: process.env.GOOGLE_SA_KEY_JSON,
    scopes: ['https://www.googleapis.com/auth/drive'],
  })
  this.drive = google.drive({ version: 'v3', auth })
  // saEmail extracted from key file at boot for /admin/sa-info
}
```

All Drive calls automatically include `supportsAllDrives: true` and
`includeItemsFromAllDrives: true`; when registering a Shared Drive,
`driveId` and `corpora: 'drive'` are added.

Methods: `listFiles(folderId, opts)`, `getFileStream(fileId)`,
`uploadStream(folderId, name, mime, stream)`, `trashFile(fileId)`,
`renameFile(fileId, name)`, `getFolderMeta(folderId)`, `verifyAccess(folderId)`,
`exportGoogleDocAsPdf(fileId)`.

#### `folder-access-resolver.service.ts`

```typescript
async resolve(userId: number, folderId: number):
  Promise<{ canRead: boolean; canWrite: boolean }>
```
Single JOIN: `user_roles ⨝ shared_folder_role_access` for the given
`(userId, folderId)`. Result is `OR`-aggregated across the user's roles.
Cached 60s under key `sf:perm:{userId}:{folderId}`; invalidated by role or
mapping updates.

#### `shared-folder-access.guard.ts`

Reads `@RequireFolderAccess('read' | 'write')` metadata, extracts the
`:folderId` route param, calls the resolver, and:
- 404 if folder not found or `store_id !== user.storeId` (existence hidden).
- 403 if required access bit is false.
- 200 otherwise.

### Endpoints

All user-facing endpoints behind `JwtAuthGuard → SessionGuard → CASL('read',
'ver-carpetas-compartidas')`. Admin endpoints swap the final CASL check to
`('manage', 'administrar-carpetas-compartidas')`. The log endpoint uses
`('read', 'ver-logs-de-carpetas')`. Write operations additionally require
`@RequireFolderAccess('write')` (checked by `SharedFolderAccessGuard`); read
operations require `@RequireFolderAccess('read')`.

| Method | Path | Folder access | Description |
|---|---|---|---|
| GET | `/carpetas-compartidas` | none (lists accessible) | Returns folders visible to the current user with `canRead`/`canWrite` precomputed |
| GET | `/carpetas-compartidas/:folderId/files` | `read` | Drive file list. Query: `q`, `pageToken`, `pageSize` (≤50), `mimeTypeFilter` |
| GET | `/carpetas-compartidas/:folderId/files/:fileId/preview` | `read` | Inline stream (`Content-Disposition: inline`). Google Docs exported to PDF |
| GET | `/carpetas-compartidas/:folderId/files/:fileId/download` | `read` | Attachment stream |
| GET | `/carpetas-compartidas/:folderId/files/:fileId/thumbnail` | `read` | Thumbnail proxy with 1h HTTP cache |
| POST | `/carpetas-compartidas/:folderId/files` | `write` | multipart upload, Drive resumable upload |
| PATCH | `/carpetas-compartidas/:folderId/files/:fileId` | `write` | Rename: body `{ name }` |
| DELETE | `/carpetas-compartidas/:folderId/files/:fileId` | `write` | Trash (`trashed: true`) — not permanent delete |

Admin:

| Method | Path | Description |
|---|---|---|
| GET | `/carpetas-compartidas/admin/sa-info` | `{ email, instructions }` |
| GET | `/carpetas-compartidas/admin/folders` | All folders for the store (active+inactive) |
| POST | `/carpetas-compartidas/admin/folders` | Register a folder; backend verifies SA access immediately |
| PATCH | `/carpetas-compartidas/admin/folders/:id` | Edit name / description / sortOrder / isActive |
| DELETE | `/carpetas-compartidas/admin/folders/:id` | Deregister (Drive contents untouched); CASCADE removes role_access rows |
| GET | `/carpetas-compartidas/admin/folders/:id/role-access` | Current mappings |
| PUT | `/carpetas-compartidas/admin/folders/:id/role-access` | Bulk replace mappings in a transaction |
| GET | `/carpetas-compartidas/admin/logs` | Filtered access logs |

### Caching (uses existing `MemoryCacheService`)

| Data | TTL | Key | Invalidation |
|---|---|---|---|
| User → folder list | 60s | `sf:list:store:{storeId}:user:{userId}` | Folder/mapping change |
| Folder file listing | 30s | `sf:files:{folderId}:{pageToken}:{q}` | upload/delete/rename |
| Folder metadata | 5m | `sf:meta:{folderId}` | Folder edit |
| Permission resolution | 60s | `sf:perm:{userId}:{folderId}` | Role / mapping change |
| Thumbnails | 1h (HTTP) | `Cache-Control: private, max-age=3600` | — |

After a write operation succeeds, the corresponding file-listing cache is
invalidated before responding.

### Frontend module

Pages (`ventago-app/src/pages/`):
```
carpetas-compartidas/
  index.tsx                        # dynamic import → SharedFoldersListView
  [folderId]/index.tsx             # dynamic import → FolderBrowserView
configuracion/carpetas-compartidas/
  index.tsx                        # dynamic import → AdminFoldersView
  logs.tsx                         # dynamic import → AccessLogsView
```

Views (`ventago-app/src/views/carpetas-compartidas/`):
```
SharedFoldersListView.tsx
  FolderCard.tsx
FolderBrowserView.tsx
  FolderBreadcrumb.tsx
  FolderToolbar.tsx
  FileTable.tsx              # AG Grid (ensureAgGridInit + pageSize 50)
  FilePreviewModal.tsx       # PDF.js, next/Image, fallback
  FileUploadDropzone.tsx     # XHR progress
  FileRenameDialog.tsx
  FileDeleteConfirm.tsx
admin/
  AdminFoldersView.tsx
  RegisterFolderDialog.tsx
  RoleAccessMatrix.tsx
  AccessLogsView.tsx
```

SWR hooks (`ventago-app/src/hooks/api/`):

| Hook | Endpoint | TTL/dedup | Used by |
|---|---|---|---|
| `useSharedFolders` | `/carpetas-compartidas` | 60s | SharedFoldersListView |
| `useFolderMeta` | `/carpetas-compartidas/:id` | 5m | FolderBrowserView header |
| `useFolderFiles` | `/carpetas-compartidas/:id/files?...` | 30s | FileTable |
| `useSharedFoldersAdmin` | `/carpetas-compartidas/admin/folders` | 30s | AdminFoldersView |
| `useFolderRoleAccess` | `/carpetas-compartidas/admin/folders/:id/role-access` | 60s | RoleAccessMatrix |
| `useSaInfo` | `/carpetas-compartidas/admin/sa-info` | 1h | RegisterFolderDialog |

Mutations call `mutate()` on the relevant key after success.

Theme — follows `sketch-findings-ace-online`:
- Background `#1a1a2e`, cards `#22223b`.
- Primary accent gold `#f5a623` (upload button, write badge).
- Folder card hover: `transform: translateY(-2px)`, gold border transition.
- File icons from Tabler (`tabler:file-text`, `tabler:photo`, etc.).
- Users without `canWrite` simply don't see the write buttons (no disabled state — visually cleaner).

Performance checklist (CLAUDE.md):
- ✅ `next/dynamic` for all four pages (`ssr: false`)
- ✅ SWR for all listing data (no `useEffect + apiConnector.get`)
- ✅ `Promise.all` for parallel meta+first-page fetch
- ✅ `useMemo` Context value; `React.memo` on FileTable rows
- ✅ `pageSize` 50 ceiling
- ✅ `ensureAgGridInit()` called once
- ✅ `next/Image` for thumbnails, with 1h backend HTTP cache

## Security

### Auth chain

```
JwtAuthGuard → SessionGuard → CASL(action, subject) → SharedFolderAccessGuard
```

CASL `(action, subject)` per endpoint group (exact action values follow the
existing seed convention — typically `read` for "user holds this function"):

| Endpoint group | Subject (function slug) | Action | Folder guard |
|---|---|---|---|
| User read (list, files, preview, download, thumbnail) | `ver-carpetas-compartidas` | `read` | `@RequireFolderAccess('read')` |
| User write (upload, rename, trash) | `subir-y-editar-archivos` | `read` | `@RequireFolderAccess('write')` |
| Admin folder config (CRUD, mappings, sa-info) | `administrar-carpetas-compartidas` | `manage` | none |
| Admin logs | `ver-logs-de-carpetas` | `read` | none |

Write operations check the user-write CASL function **before** the per-folder
guard runs — so a user without the feature-level write function gets a
clean 403 regardless of per-folder mapping. Admin operations target folder
*configuration*, not folder *contents*, so they don't need the folder guard.

### Tenant isolation (double-checked)

1. All folder queries are `WHERE store_id = user.storeId`.
2. Direct folder ID access by a wrong-store user returns **404, not 403** — the
   existence of cross-tenant folders is hidden.

### Service account key handling

- Production: Docker secret or read-only volume mount at
  `/run/secrets/google-sa.json`.
- Development: file path in `.env.local` (verify `.gitignore`).
- Key bytes are never logged or returned in any API response. Winston masking
  filter for any field matching `private_key`.
- Module bootstrap validates that the key loads and the SDK initializes; if
  not, the module fails to register (boot 500 — feature is unusable rather
  than silently degraded).

### Upload validation

- Max size: `SHARED_FOLDERS_MAX_UPLOAD_MB` (default 50). Enforced via
  `Content-Length` precheck → 413 before streaming begins, and again by limit
  in busboy/multer config.
- MIME / extension blocklist: `application/x-msdownload`,
  `application/x-msdos-program`, extensions `.exe`/`.bat`/`.cmd`/`.scr`.
- Filename sanitization: strip control chars and `../` traversal segments.
- Files are uploaded as **streams** (busboy or multer streamStorage). No
  in-memory buffering — large files cannot exhaust backend RAM.

### Rate limits (per user, reuse existing throttler module)

- General: 60 req/min.
- Upload: 10 req/min.
- Download: 100 req/min.
- 429 surfaces as an Alert + toast.

### Audit logging

- `download` / `upload` / `delete` / `rename` / `preview` are recorded in
  `shared_folder_access_logs` within the same transaction as the action's DB
  side effects (where any).
- `list` is opt-in (env `SHARED_FOLDERS_LOG_LIST=true`, default false) to keep
  traffic manageable.
- Admin log view filters by `store_id` automatically — users only see their
  store's logs.

### Secret exposure prevention

- `/admin/sa-info` returns the SA **email only**, never the key.
- Drive API error messages are translated to user-friendly text before
  surfacing — raw stack traces and JSON error bodies stay in Winston logs.

## Performance

### DB connection pool impact (CLAUDE.md `max=80` budget)

| Operation | DB queries | Avg ms | Pool hold |
|---|---|---|---|
| Folder list (cache hit) | 0 | <5 | 0 |
| Folder list (cold) | 1 JOIN | ~20 | ~20ms |
| File list | 0 DB + 1 Drive | ~150 (Drive) | 0 |
| Download / preview | 1 (audit insert) | ~10 + stream | ~10ms |
| Upload | 1 (audit) | ~10 + stream | ~10ms |

At 500 concurrent users the pool pressure is negligible; streams do not hold
DB connections.

### Drive API quota strategy

- Per-user limit: 1,000 queries / 100s → caches target ≥100× reduction.
- Per-project limit: 10,000 / 100s → TTLs sized so that worst-case traffic
  (all stores active, many users) stays well under.
- `googleapis` SDK retries with exponential backoff up to 3× before surfacing
  429 to the user.

### Streaming behavior

- Downloads: `drive.files.get({alt:'media'}, {responseType:'stream'})` piped
  into the Express response. Constant memory regardless of file size.
- Uploads: streamed through the backend straight into Drive's resumable
  upload session. **Multer memoryStorage is explicitly forbidden**; busboy
  streaming or multer streamStorage is used.

### 300ms route-render target (CLAUDE.md SLO)

- Folder list page: dynamic import + skeleton; LCP target ~250ms with hot
  cache.
- Folder entry: `Promise.all([meta, firstPage])` — Drive ~150ms + DB ~20ms in
  parallel → first paint near 200ms when uncached.

## Environment configuration

`.env`:
- `GOOGLE_SA_KEY_JSON` — absolute path to the SA JSON key file (mounted secret).
- `SHARED_FOLDERS_MAX_UPLOAD_MB` — default `50`.
- `SHARED_FOLDERS_CACHE_TTL_SEC` — default `60`.
- `SHARED_FOLDERS_LIST_TTL_SEC` — default `30`.
- `SHARED_FOLDERS_LOG_LIST` — default `false`.

## Deployment & operations

### Migration order

1. **Local PG15 (Docker dev):**
   ```bash
   docker exec api_ventago node -e "
     const { Client } = require('pg');
     const fs = require('fs');
     const c = new Client({host:'dbpostgres',user:'coolsistema',password:'<REDACTED>',database:'ventago'});
     c.connect()
       .then(() => c.query(fs.readFileSync('/app/migrations/<NN>-create-shared-folders.sql','utf8')))
       .then(() => c.end());
   "
   ```
2. **Production PG10:** requires explicit user approval per CLAUDE.md SSH/DDL rule.
   ```bash
   ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/<NN>-create-shared-folders.sql
   ```
3. Regenerate schema docs: `./.planning/intel/db-schema.regen.sh` and commit.

### SA key rollout

1. Generate SA JSON key in GCP console (project owned by Ventago).
2. Copy to production server: `~/secrets/google-sa.json`, `chmod 600`.
3. Add volume mount + env var to `api-ventago/docker-compose.yml`.
4. `docker compose up -d --force-recreate api`.
5. Verify `/carpetas-compartidas/admin/sa-info` returns the expected email.

### In-app onboarding copy

The folder-register dialog renders this guide inline:

> 1. En Google Drive, hacé clic derecho sobre la carpeta o Shared Drive → **Compartir**.
> 2. Agregá el siguiente correo con permiso de **Editor**:
>    `[SA_EMAIL] [📋 Copiar]`
> 3. Pegá la URL o el ID de la carpeta abajo.
> 4. Hacé clic en **Verificar** y luego en **Registrar**.

### Monitoring

- Winston: every Drive API call logs `{folder_id, op, ms, bytes?}` at `info`,
  429 at `warn`, 4xx/5xx at `error`.
- Admin "Logs" page exposes a 24h error-rate summary derived from
  `shared_folder_access_logs` joined with Winston error counts (or just from
  the log table if Winston aggregation is out of scope for v1).

## Testing strategy

**Backend (Jest):**
- Unit: `folder-access-resolver.service.spec.ts` — full role × permission
  matrix, including overlap and OR aggregation.
- Unit: `google-drive.service.spec.ts` — `googleapis` mocked, verifies
  `supportsAllDrives: true` flags and Shared Drive handling.
- Integration: full HTTP coverage of both controllers, with the `googleapis`
  client mocked at the service boundary.
- Regression: cross-tenant `folderId` returns 404 (not 403); upload without
  `can_write` returns 403; verification of SA blocklist for executables.

**Frontend:** no existing component test pattern in the project; covered via
manual UAT during `/gsd-verify-work`.

**E2E (optional, v2):** Playwright flow — register folder → upload → download
→ change role-access → verify denial — runs against a Drive test Shared Drive.

## Open questions

None blocking. The following are deferred to v2:
- Subfolder navigation UX.
- Multi-SA setup (separate SA per store) if a single SA hits per-project quota.

## Out of scope (recap)

See **Non-goals** at the top. Anything not explicitly listed in this document
is not part of the v1 implementation plan.
