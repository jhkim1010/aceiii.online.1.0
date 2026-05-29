# Carpetas Compartidas — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a NestJS module that lets each store register Google Drive folders (Shared Drives required for write), gate per-folder access by role × read/write, and expose user-facing + admin REST endpoints that proxy Drive operations through a single service account.

**Architecture:** Three new Sequelize models (`shared_folders`, `shared_folder_role_access`, `shared_folder_access_logs`); a singleton `GoogleDriveService` wrapping the `googleapis` SDK with a service-account auth; a `FolderAccessResolverService` + `SharedFolderAccessGuard` enforcing the per-folder OR-aggregated read/write matrix; user + admin controllers under `/carpetas-compartidas`. Tenant isolation by `store_id`; cross-tenant access returns 404. CASL gates feature visibility via four new functions seeded through the existing TS seed scripts.

**Tech Stack:** NestJS 11 + TypeScript, Sequelize + sequelize-typescript (`underscored: true`), PostgreSQL (PG10 prod / PG15 dev), `googleapis@171.4.0` (already installed), Jest for unit/integration tests, Winston for logging, existing `MemoryCacheService` for caching, multipart via existing busboy/multer infrastructure.

**Spec:** [`docs/superpowers/specs/2026-05-29-shared-folders-google-drive-design.md`](../specs/2026-05-29-shared-folders-google-drive-design.md)

---

## Pre-flight (one-time, manual — do before Task 1)

You need a Google service account with a JSON key and a Drive folder it can access.

- [ ] **Create a GCP project** (or use an existing Ventago-owned one) and enable the Google Drive API for it (https://console.cloud.google.com/apis/library/drive.googleapis.com).
- [ ] **Create a service account** under IAM & Admin → Service Accounts; download a JSON key. Save to `~/secrets/google-sa-dev.json` (chmod 600).
- [ ] **Create a test Shared Drive** in Google Drive (My Drive → New → More → Shared Drive). Add the SA email as a **Content Manager**.
- [ ] **Note the Shared Drive ID** from its URL (`drive.google.com/drive/folders/<DRIVE_ID>`) — you'll use it during smoke tests.
- [ ] **Add env to `api-ventago/.env.local`**:
  ```
  GOOGLE_SA_KEY_JSON=/Users/<you>/secrets/google-sa-dev.json
  SHARED_FOLDERS_MAX_UPLOAD_MB=50
  SHARED_FOLDERS_CACHE_TTL_SEC=60
  SHARED_FOLDERS_LIST_TTL_SEC=30
  SHARED_FOLDERS_LOG_LIST=false
  ```
- [ ] **Verify `.gitignore` excludes `.env.local`** (`git check-ignore .env.local` should print the file path).

---

## File Structure (locked at plan time)

**Created:**
```
api-ventago/migrations/shared-folders-create.sql
api-ventago/src/app/shared-folders/shared-folders.module.ts
api-ventago/src/app/shared-folders/models/shared-folder.model.ts
api-ventago/src/app/shared-folders/models/shared-folder-role-access.model.ts
api-ventago/src/app/shared-folders/models/shared-folder-access-log.model.ts
api-ventago/src/app/shared-folders/services/google-drive.service.ts
api-ventago/src/app/shared-folders/services/folder-access-resolver.service.ts
api-ventago/src/app/shared-folders/services/shared-folders.service.ts
api-ventago/src/app/shared-folders/services/shared-folders-admin.service.ts
api-ventago/src/app/shared-folders/guards/shared-folder-access.guard.ts
api-ventago/src/app/shared-folders/decorators/require-folder-access.decorator.ts
api-ventago/src/app/shared-folders/dto/register-folder.dto.ts
api-ventago/src/app/shared-folders/dto/list-files.dto.ts
api-ventago/src/app/shared-folders/dto/update-role-access.dto.ts
api-ventago/src/app/shared-folders/dto/rename-file.dto.ts
api-ventago/src/app/shared-folders/controllers/shared-folders.controller.ts
api-ventago/src/app/shared-folders/controllers/shared-folders-admin.controller.ts
api-ventago/src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
api-ventago/src/app/shared-folders/services/__tests__/folder-access-resolver.service.spec.ts
api-ventago/src/app/shared-folders/services/__tests__/shared-folders.service.spec.ts
api-ventago/src/app/shared-folders/services/__tests__/shared-folders-admin.service.spec.ts
api-ventago/src/app/shared-folders/guards/__tests__/shared-folder-access.guard.spec.ts
api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders.controller.spec.ts
api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders-admin.controller.spec.ts
```

**Modified:**
```
api-ventago/src/app.module.ts                             # register SharedFoldersModule
api-ventago/src/app/modules/seed/modules.seed.ts          # 2 new module entries
api-ventago/src/app/functions/seed/functions.seed.ts      # 4 new function entries
api-ventago/src/common/logger/logger.config.ts            # mask private_key
.planning/intel/db-schema-tables.md                       # regenerated
.planning/intel/db-schema-fks.md                          # regenerated
```

---

### Task 1: SQL migration — three new tables

**Files:**
- Create: `api-ventago/migrations/shared-folders-create.sql`
- Modify: `.planning/intel/db-schema-tables.md`, `.planning/intel/db-schema-fks.md` (auto-regenerated)

- [ ] **Step 1: Write the migration file**

Create `api-ventago/migrations/shared-folders-create.sql` with:

```sql
-- ============================================================================
-- Carpetas Compartidas (Google Drive integration)
-- 매장이 등록한 Drive 폴더 + 역할 기반 read/write 매트릭스 + 감사 로그
-- PG10/PG15 호환 (SERIAL/nextval, no GENERATED AS IDENTITY)
-- ============================================================================

-- ───── shared_folders ─────
CREATE TABLE IF NOT EXISTS shared_folders (
  id                  SERIAL PRIMARY KEY,
  store_id            INTEGER       NOT NULL REFERENCES stores(id),
  google_folder_id    VARCHAR(128)  NOT NULL,
  is_shared_drive     BOOLEAN       NOT NULL DEFAULT FALSE,
  shared_drive_id     VARCHAR(128),
  name                VARCHAR(255)  NOT NULL,
  description         TEXT,
  sort_order          INTEGER       NOT NULL DEFAULT 0,
  is_active           BOOLEAN       NOT NULL DEFAULT TRUE,
  user_id             INTEGER       NOT NULL REFERENCES users(id),
  created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at          TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT shared_folders_store_folder_uniq UNIQUE (store_id, google_folder_id),
  CONSTRAINT shared_folders_shared_drive_chk
    CHECK (is_shared_drive = FALSE OR shared_drive_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS shared_folders_store_active_sort_idx
  ON shared_folders (store_id, is_active, sort_order);

-- ───── shared_folder_role_access ─────
CREATE TABLE IF NOT EXISTS shared_folder_role_access (
  id                  SERIAL PRIMARY KEY,
  shared_folder_id    INTEGER       NOT NULL REFERENCES shared_folders(id) ON DELETE CASCADE,
  role_id             INTEGER       NOT NULL REFERENCES roles(id)          ON DELETE CASCADE,
  can_read            BOOLEAN       NOT NULL DEFAULT TRUE,
  can_write           BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at          TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT shared_folder_role_access_folder_role_uniq UNIQUE (shared_folder_id, role_id),
  CONSTRAINT shared_folder_role_access_nonempty_chk CHECK (can_read OR can_write)
);
CREATE INDEX IF NOT EXISTS shared_folder_role_access_role_idx
  ON shared_folder_role_access (role_id);

-- ───── shared_folder_access_logs ─────
CREATE TABLE IF NOT EXISTS shared_folder_access_logs (
  id                  BIGSERIAL PRIMARY KEY,
  store_id            INTEGER       NOT NULL REFERENCES stores(id),
  user_id             INTEGER       NOT NULL REFERENCES users(id),
  shared_folder_id    INTEGER       NOT NULL REFERENCES shared_folders(id),
  action              VARCHAR(20)   NOT NULL,        -- list|download|preview|upload|delete|rename
  google_file_id      VARCHAR(128),
  file_name           VARCHAR(500),
  bytes               BIGINT,
  ip_address          INET,
  user_agent          TEXT,
  created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at          TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE INDEX IF NOT EXISTS shared_folder_access_logs_store_at_idx
  ON shared_folder_access_logs (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS shared_folder_access_logs_user_at_idx
  ON shared_folder_access_logs (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS shared_folder_access_logs_folder_at_idx
  ON shared_folder_access_logs (shared_folder_id, created_at DESC);
```

- [ ] **Step 2: Apply migration to local dev DB**

Run:
```bash
docker exec -i api_ventago_db psql -U coolsistema -d ventago < api-ventago/migrations/shared-folders-create.sql
```
Expected output: a series of `CREATE TABLE` / `CREATE INDEX` notices. No errors.

Verify:
```bash
docker exec api_ventago_db psql -U coolsistema -d ventago -c "\dt shared_folder*"
```
Expected: three tables listed.

- [ ] **Step 3: Regenerate intel schema docs**

Run:
```bash
./.planning/intel/db-schema.regen.sh
```
Expected: `db-schema-tables.md` and `db-schema-fks.md` updated. Confirm with:
```bash
grep -c "shared_folder" .planning/intel/db-schema-tables.md
```
Expected: ≥ 3 (one per new table).

- [ ] **Step 4: Commit**

```bash
git add api-ventago/migrations/shared-folders-create.sql .planning/intel/
git commit -m "feat(shared-folders): migration for 3 new tables (folders, role_access, access_logs)

PG10/PG15-compatible DDL: SERIAL PKs, CHECK constraints (shared_drive
required when is_shared_drive=true; access rows must grant at least
one of read/write), CASCADE on folder/role delete, audit log with
inet/text/bigint columns and triple time-desc indexes for the three
common filter dimensions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Sequelize models (3 files)

**Files:**
- Create: `api-ventago/src/app/shared-folders/models/shared-folder.model.ts`
- Create: `api-ventago/src/app/shared-folders/models/shared-folder-role-access.model.ts`
- Create: `api-ventago/src/app/shared-folders/models/shared-folder-access-log.model.ts`

- [ ] **Step 1: Create `shared-folder.model.ts`**

```typescript
import {
  BelongsTo,
  Column,
  DataType,
  ForeignKey,
  HasMany,
  Model,
  Table,
} from 'sequelize-typescript';
import { Store } from '../../store/store.model';
import { Users } from '../../users/users.model';
import { SharedFolderRoleAccess } from './shared-folder-role-access.model';

// 매장이 등록한 Google Drive 폴더 (또는 Shared Drive)
@Table({ tableName: 'shared_folders', timestamps: true })
export class SharedFolder extends Model {
  @ForeignKey(() => Store)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare storeId: number;

  @Column({ type: DataType.STRING(128), allowNull: false })
  declare googleFolderId: string;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: false })
  declare isSharedDrive: boolean;

  @Column({ type: DataType.STRING(128), allowNull: true })
  declare sharedDriveId: string | null;

  @Column({ type: DataType.STRING(255), allowNull: false })
  declare name: string;

  @Column({ type: DataType.TEXT, allowNull: true })
  declare description: string | null;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  declare sortOrder: number;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  declare isActive: boolean;

  @ForeignKey(() => Users)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare userId: number;

  @BelongsTo(() => Store)
  declare store: Store;

  @BelongsTo(() => Users)
  declare registrar: Users;

  @HasMany(() => SharedFolderRoleAccess)
  declare roleAccess: SharedFolderRoleAccess[];
}
```

- [ ] **Step 2: Create `shared-folder-role-access.model.ts`**

```typescript
import {
  BelongsTo,
  Column,
  DataType,
  ForeignKey,
  Model,
  Table,
} from 'sequelize-typescript';
import { SharedFolder } from './shared-folder.model';
import { Role } from '../../role/role.model';

// 폴더 × 역할 read/write 매핑. UNIQUE(shared_folder_id, role_id)
@Table({ tableName: 'shared_folder_role_access', timestamps: true })
export class SharedFolderRoleAccess extends Model {
  @ForeignKey(() => SharedFolder)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare sharedFolderId: number;

  @ForeignKey(() => Role)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare roleId: number;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  declare canRead: boolean;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: false })
  declare canWrite: boolean;

  @BelongsTo(() => SharedFolder)
  declare folder: SharedFolder;

  @BelongsTo(() => Role)
  declare role: Role;
}
```

- [ ] **Step 3: Create `shared-folder-access-log.model.ts`**

```typescript
import {
  BelongsTo,
  Column,
  DataType,
  ForeignKey,
  Model,
  Table,
} from 'sequelize-typescript';
import { Store } from '../../store/store.model';
import { Users } from '../../users/users.model';
import { SharedFolder } from './shared-folder.model';

// audit: 다운로드/업로드/삭제/리네임/프리뷰 이벤트 기록
export type SharedFolderAction =
  | 'list'
  | 'download'
  | 'preview'
  | 'upload'
  | 'delete'
  | 'rename';

@Table({ tableName: 'shared_folder_access_logs', timestamps: true })
export class SharedFolderAccessLog extends Model {
  @ForeignKey(() => Store)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare storeId: number;

  @ForeignKey(() => Users)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare userId: number;

  @ForeignKey(() => SharedFolder)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare sharedFolderId: number;

  @Column({ type: DataType.STRING(20), allowNull: false })
  declare action: SharedFolderAction;

  @Column({ type: DataType.STRING(128), allowNull: true })
  declare googleFileId: string | null;

  @Column({ type: DataType.STRING(500), allowNull: true })
  declare fileName: string | null;

  @Column({ type: DataType.BIGINT, allowNull: true })
  declare bytes: number | null;

  @Column({ type: 'INET' as any, allowNull: true })
  declare ipAddress: string | null;

  @Column({ type: DataType.TEXT, allowNull: true })
  declare userAgent: string | null;

  @BelongsTo(() => Store)
  declare store: Store;

  @BelongsTo(() => Users)
  declare user: Users;

  @BelongsTo(() => SharedFolder)
  declare folder: SharedFolder;
}
```

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/shared-folders/models/
git commit -m "feat(shared-folders): Sequelize models (folder, role_access, access_log)

3 models with full type-safe FK associations. underscored:true (global)
maps camelCase props to snake_case columns automatically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: NestJS module skeleton + register in app.module

**Files:**
- Create: `api-ventago/src/app/shared-folders/shared-folders.module.ts`
- Modify: `api-ventago/src/app.module.ts`

- [ ] **Step 1: Create `shared-folders.module.ts` skeleton**

```typescript
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { SharedFolder } from './models/shared-folder.model';
import { SharedFolderRoleAccess } from './models/shared-folder-role-access.model';
import { SharedFolderAccessLog } from './models/shared-folder-access-log.model';

// Services / controllers / guards added in later tasks.
@Module({
  imports: [
    SequelizeModule.forFeature([
      SharedFolder,
      SharedFolderRoleAccess,
      SharedFolderAccessLog,
    ]),
  ],
  providers: [],
  controllers: [],
  exports: [],
})
export class SharedFoldersModule {}
```

- [ ] **Step 2: Register in `app.module.ts`**

Edit `api-ventago/src/app.module.ts`. Add import line near the other module imports (alphabetical order — between `SessionModule` and `StoreModule`, but use the location that matches the project's existing ordering):

```typescript
import { SharedFoldersModule } from './app/shared-folders/shared-folders.module';
```

Add to the `imports` array in `@Module({...})`:

```typescript
    SharedFoldersModule,
```

- [ ] **Step 3: Verify the app boots**

Run:
```bash
cd api-ventago && npm run build
```
Expected: build succeeds, no TypeScript errors.

Then start dev briefly:
```bash
npm run start:dev
```
Expected: Nest log shows `SharedFoldersModule dependencies initialized`. Stop with Ctrl+C.

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/shared-folders/shared-folders.module.ts api-ventago/src/app.module.ts
git commit -m "feat(shared-folders): module skeleton registered in app.module

Empty module wires the 3 models via SequelizeModule.forFeature so Sequelize
sync sees them. Services/controllers added in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: GoogleDriveService — SA client init + verifyAccess (TDD)

**Files:**
- Create: `api-ventago/src/app/shared-folders/services/google-drive.service.ts`
- Create: `api-ventago/src/app/shared-folders/services/__tests__/google-drive.service.spec.ts`

- [ ] **Step 1: Write the failing test**

Create `api-ventago/src/app/shared-folders/services/__tests__/google-drive.service.spec.ts`:

```typescript
jest.mock('googleapis', () => {
  const filesGet = jest.fn();
  const drivesGet = jest.fn();
  return {
    google: {
      auth: { GoogleAuth: jest.fn().mockImplementation(() => ({})) },
      drive: jest.fn().mockReturnValue({
        files: { get: filesGet },
        drives: { get: drivesGet },
      }),
    },
    __mocks__: { filesGet, drivesGet },
  };
});

import { GoogleDriveService } from '../google-drive.service';
import * as googleapis from 'googleapis';

const mocks = (googleapis as any).__mocks__;

describe('GoogleDriveService.verifyAccess', () => {
  let service: GoogleDriveService;

  beforeEach(() => {
    process.env.GOOGLE_SA_KEY_JSON = '/tmp/fake-sa.json';
    mocks.filesGet.mockReset();
    mocks.drivesGet.mockReset();
    service = new GoogleDriveService();
  });

  it('returns ok=true when SA can read folder metadata', async () => {
    mocks.filesGet.mockResolvedValue({ data: { id: 'F1', name: 'Test' } });
    const result = await service.verifyAccess('F1', { isSharedDrive: false });
    expect(result.ok).toBe(true);
    expect(mocks.filesGet).toHaveBeenCalledWith(expect.objectContaining({
      fileId: 'F1',
      supportsAllDrives: true,
    }));
  });

  it('returns ok=false with reason="not_shared" on Drive 404', async () => {
    const err: any = new Error('Not Found'); err.code = 404;
    mocks.filesGet.mockRejectedValue(err);
    const result = await service.verifyAccess('F1', { isSharedDrive: false });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('not_shared');
  });

  it('also verifies Shared Drive when isSharedDrive=true', async () => {
    mocks.filesGet.mockResolvedValue({ data: { id: 'F1' } });
    mocks.drivesGet.mockResolvedValue({ data: { id: 'D1', name: 'Drive' } });
    const result = await service.verifyAccess('F1', {
      isSharedDrive: true,
      sharedDriveId: 'D1',
    });
    expect(result.ok).toBe(true);
    expect(mocks.drivesGet).toHaveBeenCalledWith({ driveId: 'D1' });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
```
Expected: FAIL — `Cannot find module '../google-drive.service'`.

- [ ] **Step 3: Implement `google-drive.service.ts`**

```typescript
import { Injectable, OnModuleInit, Logger } from '@nestjs/common';
import { google, drive_v3 } from 'googleapis';
import { Readable } from 'stream';
import * as fs from 'fs';

export interface VerifyAccessResult {
  ok: boolean;
  reason?: 'not_shared' | 'auth_failed' | 'shared_drive_missing' | 'unknown';
  detail?: string;
}

// 서비스 계정 단일 인스턴스로 Drive API 호출 래핑.
// 토큰 갱신은 googleapis 라이브러리가 내부 처리.
@Injectable()
export class GoogleDriveService implements OnModuleInit {
  private readonly logger = new Logger(GoogleDriveService.name);
  private drive!: drive_v3.Drive;
  private saEmail!: string;

  constructor() {
    this.initClient();
  }

  onModuleInit() {
    // booting log so 운영 진단 시 SA 이메일이 즉시 확인됨
    this.logger.log(`Google Drive SA initialized: ${this.saEmail}`);
  }

  private initClient(): void {
    const keyPath = process.env.GOOGLE_SA_KEY_JSON;
    if (!keyPath) {
      throw new Error('GOOGLE_SA_KEY_JSON env var is required');
    }
    // 이메일 추출 (admin UI 안내용). 키 자체는 절대 로깅 X.
    try {
      const raw = fs.readFileSync(keyPath, 'utf8');
      const parsed = JSON.parse(raw);
      this.saEmail = parsed.client_email;
    } catch (e) {
      throw new Error(`Cannot read SA key at ${keyPath}: ${(e as Error).message}`);
    }
    const auth = new google.auth.GoogleAuth({
      keyFile: keyPath,
      scopes: ['https://www.googleapis.com/auth/drive'],
    });
    this.drive = google.drive({ version: 'v3', auth: auth as any });
  }

  getServiceAccountEmail(): string {
    return this.saEmail;
  }

  // 폴더 등록 시 호출 — SA가 실제로 접근 가능한지 즉시 검증.
  async verifyAccess(
    folderId: string,
    opts: { isSharedDrive: boolean; sharedDriveId?: string },
  ): Promise<VerifyAccessResult> {
    try {
      await this.drive.files.get({
        fileId: folderId,
        fields: 'id, name, mimeType',
        supportsAllDrives: true,
      });
      if (opts.isSharedDrive) {
        if (!opts.sharedDriveId) {
          return { ok: false, reason: 'shared_drive_missing' };
        }
        await this.drive.drives.get({ driveId: opts.sharedDriveId });
      }

      return { ok: true };
    } catch (err: any) {
      if (err?.code === 404 || err?.code === 403) {
        return { ok: false, reason: 'not_shared', detail: err.message };
      }

      return { ok: false, reason: 'unknown', detail: err.message };
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
```
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/app/shared-folders/services/google-drive.service.ts api-ventago/src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
git commit -m "feat(shared-folders): GoogleDriveService — SA init + verifyAccess

Loads service account key, exposes SA email for admin UI, verifies
SA can reach a Drive folder (and Shared Drive when applicable).
Tested with mocked googleapis client.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: GoogleDriveService — list/getStream/upload/trash/rename (TDD)

**Files:**
- Modify: `api-ventago/src/app/shared-folders/services/google-drive.service.ts`
- Modify: `api-ventago/src/app/shared-folders/services/__tests__/google-drive.service.spec.ts`

- [ ] **Step 1: Extend mock + add failing tests**

Append to the `jest.mock('googleapis', ...)` block in `google-drive.service.spec.ts`. Replace the existing mock block with this expanded version:

```typescript
jest.mock('googleapis', () => {
  const filesGet = jest.fn();
  const filesList = jest.fn();
  const filesCreate = jest.fn();
  const filesUpdate = jest.fn();
  const filesExport = jest.fn();
  const drivesGet = jest.fn();
  return {
    google: {
      auth: { GoogleAuth: jest.fn().mockImplementation(() => ({})) },
      drive: jest.fn().mockReturnValue({
        files: { get: filesGet, list: filesList, create: filesCreate, update: filesUpdate, export: filesExport },
        drives: { get: drivesGet },
      }),
    },
    __mocks__: { filesGet, filesList, filesCreate, filesUpdate, filesExport, drivesGet },
  };
});
```

Add new tests at the end of the file (after the existing `describe('GoogleDriveService.verifyAccess', ...)`):

```typescript
describe('GoogleDriveService listing & file ops', () => {
  let service: GoogleDriveService;
  beforeEach(() => {
    process.env.GOOGLE_SA_KEY_JSON = '/tmp/fake-sa.json';
    Object.values(mocks).forEach((m: any) => m.mockReset?.());
    service = new GoogleDriveService();
  });

  it('listFiles passes supportsAllDrives + includeItemsFromAllDrives', async () => {
    mocks.filesList.mockResolvedValue({ data: { files: [{ id: 'a' }], nextPageToken: 'tk' } });
    const res = await service.listFiles('F1', { pageSize: 25 });
    expect(res.files).toEqual([{ id: 'a' }]);
    expect(res.nextPageToken).toBe('tk');
    expect(mocks.filesList).toHaveBeenCalledWith(expect.objectContaining({
      q: "'F1' in parents and trashed = false",
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      pageSize: 25,
    }));
  });

  it('listFiles appends name search clause when q given', async () => {
    mocks.filesList.mockResolvedValue({ data: { files: [] } });
    await service.listFiles('F1', { q: 'menu' });
    expect(mocks.filesList).toHaveBeenCalledWith(expect.objectContaining({
      q: "'F1' in parents and trashed = false and name contains 'menu'",
    }));
  });

  it('trashFile sets trashed:true', async () => {
    mocks.filesUpdate.mockResolvedValue({ data: { id: 'X' } });
    await service.trashFile('X');
    expect(mocks.filesUpdate).toHaveBeenCalledWith(expect.objectContaining({
      fileId: 'X',
      requestBody: { trashed: true },
      supportsAllDrives: true,
    }));
  });

  it('renameFile patches name', async () => {
    mocks.filesUpdate.mockResolvedValue({ data: { id: 'X', name: 'new' } });
    await service.renameFile('X', 'new');
    expect(mocks.filesUpdate).toHaveBeenCalledWith(expect.objectContaining({
      fileId: 'X',
      requestBody: { name: 'new' },
    }));
  });
});
```

- [ ] **Step 2: Run tests, watch them fail**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
```
Expected: 4 new tests FAIL (`service.listFiles is not a function` etc.). Previous 3 still pass.

- [ ] **Step 3: Add methods to `google-drive.service.ts`**

Append to the class (before the closing `}`):

```typescript
  // ──── list ────
  async listFiles(
    folderId: string,
    opts: {
      q?: string;
      pageToken?: string;
      pageSize?: number;
      sharedDriveId?: string;
    } = {},
  ): Promise<{ files: drive_v3.Schema$File[]; nextPageToken?: string }> {
    let q = `'${folderId}' in parents and trashed = false`;
    if (opts.q) {
      // escape single quotes in user input
      const safe = opts.q.replace(/'/g, "\\'");
      q += ` and name contains '${safe}'`;
    }
    const params: any = {
      q,
      pageSize: Math.min(opts.pageSize ?? 25, 50),
      fields:
        'nextPageToken, files(id, name, mimeType, size, modifiedTime, thumbnailLink, iconLink, webViewLink)',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      orderBy: 'folder, name',
      pageToken: opts.pageToken,
    };
    if (opts.sharedDriveId) {
      params.driveId = opts.sharedDriveId;
      params.corpora = 'drive';
    }
    const res = await this.drive.files.list(params);

    return {
      files: res.data.files ?? [],
      nextPageToken: res.data.nextPageToken ?? undefined,
    };
  }

  // ──── stream get ────
  async getFileStream(fileId: string): Promise<{ stream: Readable; meta: drive_v3.Schema$File }> {
    const meta = await this.drive.files.get({
      fileId,
      fields: 'id, name, mimeType, size',
      supportsAllDrives: true,
    });
    const res = await this.drive.files.get(
      { fileId, alt: 'media', supportsAllDrives: true },
      { responseType: 'stream' },
    );

    return { stream: res.data as Readable, meta: meta.data };
  }

  // ──── upload stream → resumable ────
  async uploadStream(
    folderId: string,
    name: string,
    mimeType: string,
    stream: Readable,
    sharedDriveId?: string,
  ): Promise<drive_v3.Schema$File> {
    const params: any = {
      requestBody: { name, parents: [folderId] },
      media: { mimeType, body: stream },
      fields: 'id, name, mimeType, size, modifiedTime',
      supportsAllDrives: true,
    };
    if (sharedDriveId) params.driveId = sharedDriveId;
    const res = await this.drive.files.create(params);

    return res.data;
  }

  // ──── soft delete (papelera) ────
  async trashFile(fileId: string): Promise<void> {
    await this.drive.files.update({
      fileId,
      requestBody: { trashed: true },
      supportsAllDrives: true,
    });
  }

  // ──── rename ────
  async renameFile(fileId: string, newName: string): Promise<drive_v3.Schema$File> {
    const res = await this.drive.files.update({
      fileId,
      requestBody: { name: newName },
      fields: 'id, name, mimeType',
      supportsAllDrives: true,
    });

    return res.data;
  }

  // ──── Google Docs PDF export (preview용) ────
  async exportGoogleDocAsPdf(fileId: string): Promise<Readable> {
    const res = await this.drive.files.export(
      { fileId, mimeType: 'application/pdf' },
      { responseType: 'stream' },
    );

    return res.data as Readable;
  }

  // ──── folder metadata (이름/타입 확인용) ────
  async getFolderMeta(folderId: string): Promise<drive_v3.Schema$File> {
    const res = await this.drive.files.get({
      fileId: folderId,
      fields: 'id, name, mimeType, driveId',
      supportsAllDrives: true,
    });

    return res.data;
  }

  // ──── thumbnail proxy ────
  // Drive returns a signed thumbnailLink per file. We fetch it server-side
  // and stream it back so end-users (who have no Google session) can render
  // thumbnails. 30-min cache header on the wrapper endpoint amortizes
  // repeated grid views.
  async getThumbnailStream(fileId: string): Promise<Readable | null> {
    const meta = await this.drive.files.get({
      fileId,
      fields: 'thumbnailLink',
      supportsAllDrives: true,
    });
    const link = (meta.data as any).thumbnailLink;
    if (!link) return null;
    // 노드 18+ 글로벌 fetch 사용 (이 프로젝트 node 18+)
    const resp = await fetch(link);
    if (!resp.ok || !resp.body) return null;
    const { Readable } = await import('stream');

    return Readable.fromWeb(resp.body as any);
  }
```

- [ ] **Step 4: Run tests, all green**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
```
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/app/shared-folders/services/google-drive.service.ts api-ventago/src/app/shared-folders/services/__tests__/google-drive.service.spec.ts
git commit -m "feat(shared-folders): GoogleDriveService file ops (list/stream/upload/trash/rename)

All methods include supportsAllDrives/includeItemsFromAllDrives so
Shared Drive contents are returned. listFiles escapes user search
input. Upload accepts a Readable so multipart can pipe straight
through without buffering.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: FolderAccessResolverService (TDD)

**Files:**
- Create: `api-ventago/src/app/shared-folders/services/folder-access-resolver.service.ts`
- Create: `api-ventago/src/app/shared-folders/services/__tests__/folder-access-resolver.service.spec.ts`

This service answers "given (userId, folderId), what's the OR-aggregated (canRead, canWrite)?" by joining `user_roles` against `shared_folder_role_access`.

- [ ] **Step 1: Write failing tests**

Create `api-ventago/src/app/shared-folders/services/__tests__/folder-access-resolver.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getModelToken } from '@nestjs/sequelize';
import { FolderAccessResolverService } from '../folder-access-resolver.service';
import { SharedFolderRoleAccess } from '../../models/shared-folder-role-access.model';

describe('FolderAccessResolverService.resolve', () => {
  let service: FolderAccessResolverService;
  let roleAccessFindAll: jest.Mock;

  beforeEach(async () => {
    roleAccessFindAll = jest.fn();
    const module = await Test.createTestingModule({
      providers: [
        FolderAccessResolverService,
        {
          provide: getModelToken(SharedFolderRoleAccess),
          useValue: { findAll: roleAccessFindAll },
        },
      ],
    }).compile();
    service = module.get(FolderAccessResolverService);
  });

  it('returns canRead+canWrite=false when no row matches', async () => {
    roleAccessFindAll.mockResolvedValue([]);
    const r = await service.resolve(1, 10);
    expect(r).toEqual({ canRead: false, canWrite: false });
  });

  it('OR-aggregates across multiple role rows', async () => {
    roleAccessFindAll.mockResolvedValue([
      { canRead: true, canWrite: false },
      { canRead: false, canWrite: true },
    ]);
    const r = await service.resolve(1, 10);
    expect(r).toEqual({ canRead: true, canWrite: true });
  });

  it('caches the second call for the same (user, folder)', async () => {
    roleAccessFindAll.mockResolvedValue([{ canRead: true, canWrite: false }]);
    await service.resolve(7, 99);
    await service.resolve(7, 99);
    expect(roleAccessFindAll).toHaveBeenCalledTimes(1);
  });

  it('invalidate(userId) clears that user only', async () => {
    roleAccessFindAll.mockResolvedValue([{ canRead: true, canWrite: true }]);
    await service.resolve(1, 1);
    await service.resolve(2, 1);
    service.invalidateUser(1);
    await service.resolve(1, 1);
    await service.resolve(2, 1);
    // user 1 → 2 calls, user 2 → 1 call → total 3
    expect(roleAccessFindAll).toHaveBeenCalledTimes(3);
  });
});
```

- [ ] **Step 2: Run, fail**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/folder-access-resolver.service.spec.ts
```
Expected: FAIL — `Cannot find module '../folder-access-resolver.service'`.

- [ ] **Step 3: Implement service**

Create `api-ventago/src/app/shared-folders/services/folder-access-resolver.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { SharedFolderRoleAccess } from '../models/shared-folder-role-access.model';
import { UserRole } from '../../users/user-role/user-role.model';

interface CacheEntry {
  value: { canRead: boolean; canWrite: boolean };
  expiresAt: number;
}

const TTL_MS = 60 * 1000;

// 60s in-memory cache keyed by `${userId}:${folderId}`.
// invalidateUser / invalidateFolder hooks are wired from
// SharedFoldersAdminService when role/mapping changes happen.
@Injectable()
export class FolderAccessResolverService {
  private cache = new Map<string, CacheEntry>();

  constructor(
    @InjectModel(SharedFolderRoleAccess)
    private readonly roleAccess: typeof SharedFolderRoleAccess,
  ) {}

  async resolve(
    userId: number,
    folderId: number,
  ): Promise<{ canRead: boolean; canWrite: boolean }> {
    const key = `${userId}:${folderId}`;
    const now = Date.now();
    const hit = this.cache.get(key);
    if (hit && hit.expiresAt > now) return hit.value;

    const rows = await this.roleAccess.findAll({
      where: { sharedFolderId: folderId },
      include: [
        {
          association: 'role',
          required: true,
          include: [
            {
              model: UserRole,
              required: true,
              where: { userId },
              attributes: [],
            },
          ],
          attributes: [],
        },
      ],
      attributes: ['canRead', 'canWrite'],
    });

    const value = rows.reduce(
      (acc, r) => ({
        canRead: acc.canRead || r.canRead,
        canWrite: acc.canWrite || r.canWrite,
      }),
      { canRead: false, canWrite: false },
    );

    this.cache.set(key, { value, expiresAt: now + TTL_MS });

    return value;
  }

  invalidateUser(userId: number): void {
    for (const key of this.cache.keys()) {
      if (key.startsWith(`${userId}:`)) this.cache.delete(key);
    }
  }

  invalidateFolder(folderId: number): void {
    const suffix = `:${folderId}`;
    for (const key of this.cache.keys()) {
      if (key.endsWith(suffix)) this.cache.delete(key);
    }
  }
}
```

NOTE: the test does not import `UserRole` model and uses a simplified mock that returns rows directly without the include. Adjust the test if the model `Role` association name differs — verify the actual association alias is `role` by reading `api-ventago/src/app/role/role.model.ts` and the `user-role.model.ts` file (look for `@BelongsToMany`/`@HasMany`). If the alias differs, update both the test mock expectations and the service code's `association: 'role'` string.

- [ ] **Step 4: Run tests, green**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/folder-access-resolver.service.spec.ts
```
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/app/shared-folders/services/folder-access-resolver.service.ts api-ventago/src/app/shared-folders/services/__tests__/folder-access-resolver.service.spec.ts
git commit -m "feat(shared-folders): FolderAccessResolverService with 60s cache + invalidation

OR-aggregates can_read/can_write across user's roles via JOIN
shared_folder_role_access × user_roles. invalidateUser/invalidateFolder
hooks let the admin service evict cache when role mappings change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: @RequireFolderAccess decorator + SharedFolderAccessGuard (TDD)

**Files:**
- Create: `api-ventago/src/app/shared-folders/decorators/require-folder-access.decorator.ts`
- Create: `api-ventago/src/app/shared-folders/guards/shared-folder-access.guard.ts`
- Create: `api-ventago/src/app/shared-folders/guards/__tests__/shared-folder-access.guard.spec.ts`

- [ ] **Step 1: Create the decorator (no test — trivial)**

Create `api-ventago/src/app/shared-folders/decorators/require-folder-access.decorator.ts`:

```typescript
import { SetMetadata } from '@nestjs/common';

export type FolderAccessMode = 'read' | 'write';
export const REQUIRE_FOLDER_ACCESS_KEY = 'requireFolderAccess';

// 컨트롤러 핸들러 위에 @RequireFolderAccess('read'|'write') 부착 →
// SharedFolderAccessGuard 가 metadata 읽어서 권한 강제.
export const RequireFolderAccess = (mode: FolderAccessMode) =>
  SetMetadata(REQUIRE_FOLDER_ACCESS_KEY, mode);
```

- [ ] **Step 2: Write failing guard tests**

Create `api-ventago/src/app/shared-folders/guards/__tests__/shared-folder-access.guard.spec.ts`:

```typescript
import { ExecutionContext, NotFoundException, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { SharedFolderAccessGuard } from '../shared-folder-access.guard';

function makeCtx(opts: { user: any; params: any }): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => ({ user: opts.user, params: opts.params }),
    }),
    getHandler: () => ({}),
    getClass: () => ({}),
  } as any;
}

describe('SharedFolderAccessGuard', () => {
  let guard: SharedFolderAccessGuard;
  let folderFindByPk: jest.Mock;
  let resolverResolve: jest.Mock;
  let reflector: Reflector;

  beforeEach(() => {
    folderFindByPk = jest.fn();
    resolverResolve = jest.fn();
    reflector = new Reflector();
    jest.spyOn(reflector, 'get').mockReturnValue('read');
    guard = new SharedFolderAccessGuard(
      reflector,
      { findByPk: folderFindByPk } as any,
      { resolve: resolverResolve } as any,
    );
  });

  it('returns true when access mode not required (no decorator)', async () => {
    (reflector.get as jest.Mock).mockReturnValue(undefined);
    const ctx = makeCtx({ user: { sub: 1, storeId: 5 }, params: { folderId: '10' } });
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
  });

  it('throws 404 when folder not found', async () => {
    folderFindByPk.mockResolvedValue(null);
    const ctx = makeCtx({ user: { sub: 1, storeId: 5 }, params: { folderId: '10' } });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws 404 when folder belongs to another store', async () => {
    folderFindByPk.mockResolvedValue({ id: 10, storeId: 999, isActive: true });
    const ctx = makeCtx({ user: { sub: 1, storeId: 5 }, params: { folderId: '10' } });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws 403 when user lacks read on the folder', async () => {
    folderFindByPk.mockResolvedValue({ id: 10, storeId: 5, isActive: true });
    resolverResolve.mockResolvedValue({ canRead: false, canWrite: false });
    const ctx = makeCtx({ user: { sub: 1, storeId: 5 }, params: { folderId: '10' } });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('throws 403 on write when only read granted', async () => {
    (reflector.get as jest.Mock).mockReturnValue('write');
    folderFindByPk.mockResolvedValue({ id: 10, storeId: 5, isActive: true });
    resolverResolve.mockResolvedValue({ canRead: true, canWrite: false });
    const ctx = makeCtx({ user: { sub: 1, storeId: 5 }, params: { folderId: '10' } });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('returns true on read with read+write grant', async () => {
    folderFindByPk.mockResolvedValue({ id: 10, storeId: 5, isActive: true });
    resolverResolve.mockResolvedValue({ canRead: true, canWrite: true });
    const ctx = makeCtx({ user: { sub: 1, storeId: 5 }, params: { folderId: '10' } });
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
  });
});
```

- [ ] **Step 3: Run, fail**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/guards/__tests__/shared-folder-access.guard.spec.ts
```
Expected: FAIL — `Cannot find module '../shared-folder-access.guard'`.

- [ ] **Step 4: Implement the guard**

Create `api-ventago/src/app/shared-folders/guards/shared-folder-access.guard.ts`:

```typescript
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { InjectModel } from '@nestjs/sequelize';
import { SharedFolder } from '../models/shared-folder.model';
import { FolderAccessResolverService } from '../services/folder-access-resolver.service';
import {
  FolderAccessMode,
  REQUIRE_FOLDER_ACCESS_KEY,
} from '../decorators/require-folder-access.decorator';

// 404 if folder not in store (테넌트 격리 — 존재 자체를 숨김).
// 403 if user lacks the required mode on this folder.
@Injectable()
export class SharedFolderAccessGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    @InjectModel(SharedFolder)
    private readonly folderModel: typeof SharedFolder,
    private readonly resolver: FolderAccessResolverService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const required = this.reflector.get<FolderAccessMode | undefined>(
      REQUIRE_FOLDER_ACCESS_KEY,
      ctx.getHandler(),
    );
    if (!required) return true;

    const req = ctx.switchToHttp().getRequest();
    const folderId = Number(req.params?.folderId);
    if (!Number.isFinite(folderId)) {
      throw new NotFoundException('Folder not found');
    }

    const folder = await this.folderModel.findByPk(folderId);
    if (!folder || folder.storeId !== req.user.storeId || !folder.isActive) {
      throw new NotFoundException('Folder not found');
    }

    const { canRead, canWrite } = await this.resolver.resolve(
      req.user.sub,
      folderId,
    );
    const ok = required === 'read' ? canRead : canWrite;
    if (!ok) {
      throw new ForbiddenException(
        required === 'read'
          ? 'No tenés permiso de lectura en esta carpeta'
          : 'No tenés permiso de escritura en esta carpeta',
      );
    }

    return true;
  }
}
```

- [ ] **Step 5: Run, green**

Run:
```bash
cd api-ventago && npx jest src/app/shared-folders/guards/__tests__/shared-folder-access.guard.spec.ts
```
Expected: 6 passed.

- [ ] **Step 6: Commit**

```bash
git add api-ventago/src/app/shared-folders/decorators/ api-ventago/src/app/shared-folders/guards/
git commit -m "feat(shared-folders): @RequireFolderAccess + SharedFolderAccessGuard

Decorator-driven per-route enforcement. Returns 404 (not 403) for
cross-tenant folder access so existence is hidden. Distinguishes read
vs write modes; pulls effective grants from FolderAccessResolverService.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: DTOs (4 files)

**Files:**
- Create: `api-ventago/src/app/shared-folders/dto/register-folder.dto.ts`
- Create: `api-ventago/src/app/shared-folders/dto/list-files.dto.ts`
- Create: `api-ventago/src/app/shared-folders/dto/update-role-access.dto.ts`
- Create: `api-ventago/src/app/shared-folders/dto/rename-file.dto.ts`

- [ ] **Step 1: Create all four DTOs**

`register-folder.dto.ts`:
```typescript
import {
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Length,
  MaxLength,
  ValidateIf,
} from 'class-validator';

// 신규 폴더 등록 입력. googleFolderId는 URL/순수 ID 둘 다 허용 (백엔드에서 파싱).
export class RegisterFolderDto {
  @IsString()
  @Length(1, 512)
  googleFolderIdOrUrl!: string;

  @IsString()
  @Length(1, 255)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  description?: string;

  @IsBoolean()
  isSharedDrive!: boolean;

  @ValidateIf((o) => o.isSharedDrive === true)
  @IsString()
  @Length(1, 128)
  sharedDriveId?: string;

  @IsOptional()
  @IsInt()
  sortOrder?: number;
}
```

`list-files.dto.ts`:
```typescript
import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class ListFilesDto {
  @IsOptional()
  @IsString()
  q?: string;

  @IsOptional()
  @IsString()
  pageToken?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  pageSize?: number;

  @IsOptional()
  @IsString()
  mimeTypeFilter?: string;
}
```

`update-role-access.dto.ts`:
```typescript
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsInt,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

export class RoleAccessEntryDto {
  @IsInt()
  @Min(1)
  roleId!: number;

  @IsBoolean()
  canRead!: boolean;

  @IsBoolean()
  canWrite!: boolean;
}

// PUT body: replaces the entire access matrix for the folder in a tx.
export class UpdateRoleAccessDto {
  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => RoleAccessEntryDto)
  entries!: RoleAccessEntryDto[];
}
```

`rename-file.dto.ts`:
```typescript
import { IsString, Length, Matches } from 'class-validator';

// Drive 파일명 — 슬래시·제어문자 차단
export class RenameFileDto {
  @IsString()
  @Length(1, 255)
  @Matches(/^[^\/\x00-\x1F]+$/, {
    message: 'name contains invalid characters',
  })
  name!: string;
}
```

- [ ] **Step 2: Commit**

```bash
git add api-ventago/src/app/shared-folders/dto/
git commit -m "feat(shared-folders): request DTOs with class-validator constraints

Includes conditional validation (shared_drive_id required when
isSharedDrive=true), pageSize ceiling 50, and filename character
allowlist matching Drive's own rules.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: SharedFoldersService (user-facing business logic, TDD)

**Files:**
- Create: `api-ventago/src/app/shared-folders/services/shared-folders.service.ts`
- Create: `api-ventago/src/app/shared-folders/services/__tests__/shared-folders.service.spec.ts`

This service composes models + GoogleDriveService + resolver. It handles: list folders for a user, list files in a folder, get/stream a file, upload, rename, trash, and write audit log rows.

- [ ] **Step 1: Write failing tests for `listFoldersForUser`**

Create `api-ventago/src/app/shared-folders/services/__tests__/shared-folders.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getModelToken } from '@nestjs/sequelize';
import { SharedFoldersService } from '../shared-folders.service';
import { SharedFolder } from '../../models/shared-folder.model';
import { SharedFolderRoleAccess } from '../../models/shared-folder-role-access.model';
import { SharedFolderAccessLog } from '../../models/shared-folder-access-log.model';
import { GoogleDriveService } from '../google-drive.service';
import { FolderAccessResolverService } from '../folder-access-resolver.service';

describe('SharedFoldersService', () => {
  let service: SharedFoldersService;
  let folderModel: any;
  let logModel: any;
  let resolver: jest.Mocked<FolderAccessResolverService>;
  let drive: jest.Mocked<GoogleDriveService>;

  beforeEach(async () => {
    folderModel = { findAll: jest.fn(), findByPk: jest.fn() };
    logModel = { create: jest.fn() };
    resolver = { resolve: jest.fn() } as any;
    drive = { listFiles: jest.fn() } as any;
    const module = await Test.createTestingModule({
      providers: [
        SharedFoldersService,
        { provide: getModelToken(SharedFolder), useValue: folderModel },
        { provide: getModelToken(SharedFolderRoleAccess), useValue: {} },
        { provide: getModelToken(SharedFolderAccessLog), useValue: logModel },
        { provide: GoogleDriveService, useValue: drive },
        { provide: FolderAccessResolverService, useValue: resolver },
      ],
    }).compile();
    service = module.get(SharedFoldersService);
  });

  it('listFoldersForUser returns only folders user can read', async () => {
    folderModel.findAll.mockResolvedValue([
      { id: 1, storeId: 5, name: 'A', description: null, sortOrder: 0, isActive: true, isSharedDrive: true, sharedDriveId: 'D1' },
      { id: 2, storeId: 5, name: 'B', description: null, sortOrder: 1, isActive: true, isSharedDrive: false, sharedDriveId: null },
    ]);
    resolver.resolve
      .mockResolvedValueOnce({ canRead: true, canWrite: true })
      .mockResolvedValueOnce({ canRead: false, canWrite: false });
    const out = await service.listFoldersForUser(7, 5);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ id: 1, name: 'A', canRead: true, canWrite: true });
  });

  it('listFilesInFolder calls Drive with stored sharedDriveId', async () => {
    folderModel.findByPk.mockResolvedValue({
      id: 1, storeId: 5, googleFolderId: 'F1', isSharedDrive: true, sharedDriveId: 'D1',
    });
    drive.listFiles.mockResolvedValue({ files: [], nextPageToken: undefined });
    await service.listFilesInFolder(7, 5, 1, { pageSize: 10 });
    expect(drive.listFiles).toHaveBeenCalledWith('F1', expect.objectContaining({
      pageSize: 10,
      sharedDriveId: 'D1',
    }));
  });

  it('recordAccess writes a log row', async () => {
    await service.recordAccess({
      storeId: 5, userId: 7, sharedFolderId: 1, action: 'download',
      googleFileId: 'X', fileName: 'a.pdf', bytes: 1024,
      ipAddress: '1.2.3.4', userAgent: 'UA',
    });
    expect(logModel.create).toHaveBeenCalledWith(expect.objectContaining({
      storeId: 5, userId: 7, sharedFolderId: 1, action: 'download',
      googleFileId: 'X', fileName: 'a.pdf', bytes: 1024,
    }));
  });
});
```

- [ ] **Step 2: Run, fail**

```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/shared-folders.service.spec.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement service**

Create `api-ventago/src/app/shared-folders/services/shared-folders.service.ts`:

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { Readable } from 'stream';
import { SharedFolder } from '../models/shared-folder.model';
import {
  SharedFolderAccessLog,
  SharedFolderAction,
} from '../models/shared-folder-access-log.model';
import { GoogleDriveService } from './google-drive.service';
import { FolderAccessResolverService } from './folder-access-resolver.service';

export interface SharedFolderListItem {
  id: number;
  name: string;
  description: string | null;
  isSharedDrive: boolean;
  canRead: boolean;
  canWrite: boolean;
}

export interface AccessLogInput {
  storeId: number;
  userId: number;
  sharedFolderId: number;
  action: SharedFolderAction;
  googleFileId?: string | null;
  fileName?: string | null;
  bytes?: number | null;
  ipAddress?: string | null;
  userAgent?: string | null;
}

@Injectable()
export class SharedFoldersService {
  constructor(
    @InjectModel(SharedFolder)
    private readonly folderModel: typeof SharedFolder,
    @InjectModel(SharedFolderAccessLog)
    private readonly logModel: typeof SharedFolderAccessLog,
    private readonly drive: GoogleDriveService,
    private readonly resolver: FolderAccessResolverService,
  ) {}

  // 사용자에게 보이는 폴더 = (store_id 일치) ∧ (is_active) ∧ (사용자에 read 권한 있음)
  async listFoldersForUser(
    userId: number,
    storeId: number,
  ): Promise<SharedFolderListItem[]> {
    const folders = await this.folderModel.findAll({
      where: { storeId, isActive: true },
      order: [['sortOrder', 'ASC'], ['id', 'ASC']],
    });
    const out: SharedFolderListItem[] = [];
    for (const f of folders) {
      const { canRead, canWrite } = await this.resolver.resolve(userId, f.id);
      if (!canRead && !canWrite) continue;
      out.push({
        id: f.id,
        name: f.name,
        description: f.description,
        isSharedDrive: f.isSharedDrive,
        canRead,
        canWrite,
      });
    }

    return out;
  }

  // 폴더 메타 (가드를 통과한 다음 호출 — 다시 store 체크 안 함)
  async getFolderOrThrow(folderId: number, storeId: number): Promise<SharedFolder> {
    const folder = await this.folderModel.findByPk(folderId);
    if (!folder || folder.storeId !== storeId || !folder.isActive) {
      throw new NotFoundException('Folder not found');
    }

    return folder;
  }

  async listFilesInFolder(
    userId: number,
    storeId: number,
    folderId: number,
    opts: { q?: string; pageToken?: string; pageSize?: number },
  ) {
    const folder = await this.getFolderOrThrow(folderId, storeId);

    return this.drive.listFiles(folder.googleFolderId, {
      ...opts,
      sharedDriveId: folder.sharedDriveId ?? undefined,
    });
  }

  async getFileStream(folderId: number, storeId: number, fileId: string) {
    await this.getFolderOrThrow(folderId, storeId);

    return this.drive.getFileStream(fileId);
  }

  async getThumbnailStream(folderId: number, storeId: number, fileId: string) {
    await this.getFolderOrThrow(folderId, storeId);

    return this.drive.getThumbnailStream(fileId);
  }

  async upload(
    folderId: number,
    storeId: number,
    name: string,
    mimeType: string,
    stream: Readable,
  ) {
    const folder = await this.getFolderOrThrow(folderId, storeId);

    return this.drive.uploadStream(
      folder.googleFolderId,
      name,
      mimeType,
      stream,
      folder.sharedDriveId ?? undefined,
    );
  }

  async trash(folderId: number, storeId: number, fileId: string) {
    await this.getFolderOrThrow(folderId, storeId);
    await this.drive.trashFile(fileId);
  }

  async rename(folderId: number, storeId: number, fileId: string, newName: string) {
    await this.getFolderOrThrow(folderId, storeId);

    return this.drive.renameFile(fileId, newName);
  }

  async recordAccess(input: AccessLogInput): Promise<void> {
    await this.logModel.create(input as any);
  }
}
```

- [ ] **Step 4: Run, green**

```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/shared-folders.service.spec.ts
```
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/app/shared-folders/services/shared-folders.service.ts api-ventago/src/app/shared-folders/services/__tests__/shared-folders.service.spec.ts
git commit -m "feat(shared-folders): user-facing SharedFoldersService

Tenant-isolated folder listing with per-folder access filtering,
proxy methods to GoogleDriveService for list/stream/upload/trash/rename,
audit log write helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: SharedFoldersAdminService (admin business logic, TDD)

**Files:**
- Create: `api-ventago/src/app/shared-folders/services/shared-folders-admin.service.ts`
- Create: `api-ventago/src/app/shared-folders/services/__tests__/shared-folders-admin.service.spec.ts`

- [ ] **Step 1: Write failing tests**

Create `api-ventago/src/app/shared-folders/services/__tests__/shared-folders-admin.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getModelToken } from '@nestjs/sequelize';
import { BadRequestException } from '@nestjs/common';
import { SharedFoldersAdminService } from '../shared-folders-admin.service';
import { SharedFolder } from '../../models/shared-folder.model';
import { SharedFolderRoleAccess } from '../../models/shared-folder-role-access.model';
import { SharedFolderAccessLog } from '../../models/shared-folder-access-log.model';
import { GoogleDriveService } from '../google-drive.service';
import { FolderAccessResolverService } from '../folder-access-resolver.service';

describe('SharedFoldersAdminService', () => {
  let service: SharedFoldersAdminService;
  let folderModel: any, roleAccessModel: any, sequelize: any;
  let drive: jest.Mocked<GoogleDriveService>;
  let resolver: jest.Mocked<FolderAccessResolverService>;

  beforeEach(async () => {
    folderModel = { findAll: jest.fn(), findByPk: jest.fn(), create: jest.fn(), update: jest.fn() };
    roleAccessModel = { destroy: jest.fn(), bulkCreate: jest.fn(), findAll: jest.fn() };
    sequelize = { transaction: jest.fn().mockImplementation((cb: any) => cb({})) };
    drive = { verifyAccess: jest.fn(), getServiceAccountEmail: jest.fn().mockReturnValue('sa@x.iam') } as any;
    resolver = { invalidateFolder: jest.fn(), invalidateUser: jest.fn() } as any;
    const module = await Test.createTestingModule({
      providers: [
        SharedFoldersAdminService,
        { provide: getModelToken(SharedFolder), useValue: folderModel },
        { provide: getModelToken(SharedFolderRoleAccess), useValue: roleAccessModel },
        { provide: getModelToken(SharedFolderAccessLog), useValue: {} },
        { provide: GoogleDriveService, useValue: drive },
        { provide: FolderAccessResolverService, useValue: resolver },
        { provide: 'SEQUELIZE', useValue: sequelize },
      ],
    }).compile();
    service = module.get(SharedFoldersAdminService);
  });

  describe('extractFolderId', () => {
    it('parses ID from URL', () => {
      expect(service.extractFolderId('https://drive.google.com/drive/folders/1abc-XYZ_0')).toBe('1abc-XYZ_0');
    });
    it('returns raw ID unchanged', () => {
      expect(service.extractFolderId('abc-XYZ_0')).toBe('abc-XYZ_0');
    });
  });

  it('registerFolder verifies SA access then creates row', async () => {
    drive.verifyAccess.mockResolvedValue({ ok: true });
    folderModel.create.mockResolvedValue({ id: 99 });
    const dto = {
      googleFolderIdOrUrl: 'F1', name: 'X', isSharedDrive: true, sharedDriveId: 'D1',
    };
    const out = await service.registerFolder(7, 5, dto as any);
    expect(drive.verifyAccess).toHaveBeenCalledWith('F1', { isSharedDrive: true, sharedDriveId: 'D1' });
    expect(folderModel.create).toHaveBeenCalledWith(expect.objectContaining({
      storeId: 5, userId: 7, googleFolderId: 'F1', name: 'X',
    }));
    expect(out).toEqual({ id: 99 });
  });

  it('registerFolder throws 400 when SA cannot access', async () => {
    drive.verifyAccess.mockResolvedValue({ ok: false, reason: 'not_shared' });
    await expect(service.registerFolder(7, 5, {
      googleFolderIdOrUrl: 'F', name: 'x', isSharedDrive: false,
    } as any)).rejects.toBeInstanceOf(BadRequestException);
    expect(folderModel.create).not.toHaveBeenCalled();
  });

  it('replaceRoleAccess wipes-then-inserts in a transaction', async () => {
    folderModel.findByPk.mockResolvedValue({ id: 10, storeId: 5 });
    await service.replaceRoleAccess(10, 5, {
      entries: [
        { roleId: 1, canRead: true, canWrite: false },
        { roleId: 2, canRead: false, canWrite: true },
      ],
    });
    expect(sequelize.transaction).toHaveBeenCalled();
    expect(roleAccessModel.destroy).toHaveBeenCalledWith(expect.objectContaining({
      where: { sharedFolderId: 10 },
    }));
    expect(roleAccessModel.bulkCreate).toHaveBeenCalledWith([
      expect.objectContaining({ sharedFolderId: 10, roleId: 1, canRead: true, canWrite: false }),
      expect.objectContaining({ sharedFolderId: 10, roleId: 2, canRead: false, canWrite: true }),
    ], expect.anything());
    expect(resolver.invalidateFolder).toHaveBeenCalledWith(10);
  });

  it('replaceRoleAccess rejects rows with no read and no write', async () => {
    folderModel.findByPk.mockResolvedValue({ id: 10, storeId: 5 });
    await expect(service.replaceRoleAccess(10, 5, {
      entries: [{ roleId: 1, canRead: false, canWrite: false }],
    })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('getSaInfo returns the SA email', () => {
    expect(service.getSaInfo()).toEqual(expect.objectContaining({ email: 'sa@x.iam' }));
  });
});
```

- [ ] **Step 2: Run, fail**

```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/shared-folders-admin.service.spec.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement service**

Create `api-ventago/src/app/shared-folders/services/shared-folders-admin.service.ts`:

```typescript
import {
  BadRequestException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { Sequelize } from 'sequelize-typescript';
import { SharedFolder } from '../models/shared-folder.model';
import { SharedFolderRoleAccess } from '../models/shared-folder-role-access.model';
import { SharedFolderAccessLog } from '../models/shared-folder-access-log.model';
import { GoogleDriveService } from './google-drive.service';
import { FolderAccessResolverService } from './folder-access-resolver.service';
import { RegisterFolderDto } from '../dto/register-folder.dto';
import { UpdateRoleAccessDto } from '../dto/update-role-access.dto';

@Injectable()
export class SharedFoldersAdminService {
  constructor(
    @InjectModel(SharedFolder)
    private readonly folderModel: typeof SharedFolder,
    @InjectModel(SharedFolderRoleAccess)
    private readonly roleAccessModel: typeof SharedFolderRoleAccess,
    @InjectModel(SharedFolderAccessLog)
    private readonly logModel: typeof SharedFolderAccessLog,
    private readonly drive: GoogleDriveService,
    private readonly resolver: FolderAccessResolverService,
    @Inject('SEQUELIZE') private readonly sequelize: Sequelize,
  ) {}

  // Drive URL 또는 순수 ID 둘 다 허용 — URL은 .../folders/<ID> 패턴 추출.
  extractFolderId(input: string): string {
    const m = input.match(/\/folders\/([A-Za-z0-9_-]+)/);

    return m ? m[1] : input.trim();
  }

  getSaInfo() {
    return {
      email: this.drive.getServiceAccountEmail(),
      instructions:
        'Compartí la carpeta o Shared Drive con esta cuenta como Editor para que Ventago pueda acceder.',
    };
  }

  async listForStore(storeId: number) {
    return this.folderModel.findAll({
      where: { storeId },
      order: [['sortOrder', 'ASC'], ['id', 'ASC']],
    });
  }

  async registerFolder(
    userId: number,
    storeId: number,
    dto: RegisterFolderDto,
  ): Promise<{ id: number }> {
    const googleFolderId = this.extractFolderId(dto.googleFolderIdOrUrl);
    const verify = await this.drive.verifyAccess(googleFolderId, {
      isSharedDrive: dto.isSharedDrive,
      sharedDriveId: dto.sharedDriveId,
    });
    if (!verify.ok) {
      throw new BadRequestException(
        verify.reason === 'not_shared'
          ? `La cuenta de servicio aún no tiene acceso. Compartí la carpeta con ${this.drive.getServiceAccountEmail()} e intentá de nuevo.`
          : `No se pudo verificar el acceso (${verify.reason ?? 'unknown'}).`,
      );
    }
    const created = await this.folderModel.create({
      storeId,
      userId,
      googleFolderId,
      isSharedDrive: dto.isSharedDrive,
      sharedDriveId: dto.sharedDriveId ?? null,
      name: dto.name,
      description: dto.description ?? null,
      sortOrder: dto.sortOrder ?? 0,
      isActive: true,
    } as any);

    return { id: created.id };
  }

  async updateFolder(
    folderId: number,
    storeId: number,
    patch: Partial<Pick<SharedFolder, 'name' | 'description' | 'sortOrder' | 'isActive'>>,
  ): Promise<void> {
    const folder = await this.folderModel.findByPk(folderId);
    if (!folder || folder.storeId !== storeId) {
      throw new NotFoundException('Folder not found');
    }
    await folder.update(patch);
    this.resolver.invalidateFolder(folderId);
  }

  async deleteFolder(folderId: number, storeId: number): Promise<void> {
    const folder = await this.folderModel.findByPk(folderId);
    if (!folder || folder.storeId !== storeId) {
      throw new NotFoundException('Folder not found');
    }
    await folder.destroy();
    this.resolver.invalidateFolder(folderId);
  }

  async getRoleAccess(folderId: number, storeId: number) {
    const folder = await this.folderModel.findByPk(folderId);
    if (!folder || folder.storeId !== storeId) {
      throw new NotFoundException('Folder not found');
    }

    return this.roleAccessModel.findAll({
      where: { sharedFolderId: folderId },
      order: [['roleId', 'ASC']],
    });
  }

  async replaceRoleAccess(
    folderId: number,
    storeId: number,
    dto: UpdateRoleAccessDto,
  ): Promise<void> {
    const folder = await this.folderModel.findByPk(folderId);
    if (!folder || folder.storeId !== storeId) {
      throw new NotFoundException('Folder not found');
    }
    for (const e of dto.entries) {
      if (!e.canRead && !e.canWrite) {
        throw new BadRequestException(
          `Role ${e.roleId} must have at least one of read/write granted`,
        );
      }
    }
    await this.sequelize.transaction(async (t) => {
      await this.roleAccessModel.destroy({
        where: { sharedFolderId: folderId },
        transaction: t,
      });
      if (dto.entries.length) {
        await this.roleAccessModel.bulkCreate(
          dto.entries.map((e) => ({
            sharedFolderId: folderId,
            roleId: e.roleId,
            canRead: e.canRead,
            canWrite: e.canWrite,
          })) as any,
          { transaction: t },
        );
      }
    });
    this.resolver.invalidateFolder(folderId);
  }

  async listAccessLogs(
    storeId: number,
    opts: {
      folderId?: number;
      userId?: number;
      action?: string;
      from?: Date;
      to?: Date;
      pageSize?: number;
      offset?: number;
    },
  ) {
    const where: any = { storeId };
    if (opts.folderId) where.sharedFolderId = opts.folderId;
    if (opts.userId) where.userId = opts.userId;
    if (opts.action) where.action = opts.action;
    if (opts.from || opts.to) {
      where.createdAt = {};
      if (opts.from) where.createdAt['$gte'] = opts.from;
      if (opts.to) where.createdAt['$lte'] = opts.to;
    }

    return this.logModel.findAndCountAll({
      where,
      order: [['createdAt', 'DESC']],
      limit: Math.min(opts.pageSize ?? 50, 200),
      offset: opts.offset ?? 0,
    });
  }
}
```

NOTE: the `'SEQUELIZE'` token is the project's existing convention — verify by `grep -rn "'SEQUELIZE'" api-ventago/src/database/`. If the actual provider token differs (e.g. an exported `Sequelize` class), update the `@Inject('SEQUELIZE')` line and the test's provider registration to match.

- [ ] **Step 4: Run, green**

```bash
cd api-ventago && npx jest src/app/shared-folders/services/__tests__/shared-folders-admin.service.spec.ts
```
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/app/shared-folders/services/shared-folders-admin.service.ts api-ventago/src/app/shared-folders/services/__tests__/shared-folders-admin.service.spec.ts
git commit -m "feat(shared-folders): SharedFoldersAdminService

CRUD for folder registrations, transactional role-access replacement
with permission-resolver cache invalidation, audit log paging, SA
email surfacing for the admin UI's onboarding dialog.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: SharedFoldersController + integration tests

**Files:**
- Create: `api-ventago/src/app/shared-folders/controllers/shared-folders.controller.ts`
- Create: `api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders.controller.spec.ts`
- Modify: `api-ventago/src/app/shared-folders/shared-folders.module.ts` — wire services + guard + controller

- [ ] **Step 1: Check the existing CASL guard/decorator pattern**

Run:
```bash
grep -rn "CheckPolicies\|AbilitiesGuard\|PoliciesGuard" api-ventago/src/app/permissions/ | head -10
```
Note the actual decorator+guard names used in the project (they're invoked here only via "TODO" comments — the implementation plan should USE them but **not** modify the CASL system). The user CASL gate (`ver-carpetas-compartidas`) is enforced by decorating the controller; the per-folder access uses our new guard. If your project's CASL setup uses `@CheckPolicies(...)`, replace the `// CASL:` comments below with that decorator.

- [ ] **Step 2: Write failing controller tests**

Create `api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders.controller.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { SharedFoldersController } from '../shared-folders.controller';
import { SharedFoldersService } from '../../services/shared-folders.service';

describe('SharedFoldersController', () => {
  let controller: SharedFoldersController;
  let svc: jest.Mocked<SharedFoldersService>;

  beforeEach(async () => {
    svc = {
      listFoldersForUser: jest.fn(),
      listFilesInFolder: jest.fn(),
      getFileStream: jest.fn(),
      upload: jest.fn(),
      trash: jest.fn(),
      rename: jest.fn(),
      recordAccess: jest.fn(),
    } as any;
    const module = await Test.createTestingModule({
      controllers: [SharedFoldersController],
      providers: [{ provide: SharedFoldersService, useValue: svc }],
    }).compile();
    controller = module.get(SharedFoldersController);
  });

  it('GET / returns folder list for the auth user', async () => {
    svc.listFoldersForUser.mockResolvedValue([
      { id: 1, name: 'A', description: null, isSharedDrive: true, canRead: true, canWrite: false },
    ]);
    const req: any = { user: { sub: 7, storeId: 5 } };
    const out = await controller.listMine(req);
    expect(out).toHaveLength(1);
    expect(svc.listFoldersForUser).toHaveBeenCalledWith(7, 5);
  });

  it('GET /:folderId/files passes query through and records list event when enabled', async () => {
    process.env.SHARED_FOLDERS_LOG_LIST = 'true';
    svc.listFilesInFolder.mockResolvedValue({ files: [], nextPageToken: undefined });
    const req: any = { user: { sub: 7, storeId: 5 }, ip: '1.2.3.4', headers: { 'user-agent': 'UA' } };
    await controller.listFiles(req, 10, { pageSize: 25 } as any);
    expect(svc.listFilesInFolder).toHaveBeenCalledWith(7, 5, 10, { pageSize: 25 });
    expect(svc.recordAccess).toHaveBeenCalledWith(expect.objectContaining({
      action: 'list', userId: 7, sharedFolderId: 10,
    }));
  });

  it('PATCH rename writes audit log', async () => {
    svc.rename.mockResolvedValue({ id: 'X', name: 'new' } as any);
    const req: any = { user: { sub: 7, storeId: 5 }, ip: '1.2.3.4', headers: { 'user-agent': 'UA' } };
    await controller.rename(req, 10, 'X', { name: 'new' });
    expect(svc.recordAccess).toHaveBeenCalledWith(expect.objectContaining({
      action: 'rename', googleFileId: 'X', fileName: 'new',
    }));
  });
});
```

- [ ] **Step 3: Run, fail**

```bash
cd api-ventago && npx jest src/app/shared-folders/controllers/__tests__/shared-folders.controller.spec.ts
```
Expected: FAIL — module not found.

- [ ] **Step 4: Implement controller**

Create `api-ventago/src/app/shared-folders/controllers/shared-folders.controller.ts`:

```typescript
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
  PayloadTooLargeException,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SessionGuard } from '../../session/guards/session.guard';
import { SharedFolderAccessGuard } from '../guards/shared-folder-access.guard';
import { RequireFolderAccess } from '../decorators/require-folder-access.decorator';
import { SharedFoldersService } from '../services/shared-folders.service';
import { ListFilesDto } from '../dto/list-files.dto';
import { RenameFileDto } from '../dto/rename-file.dto';
import { Response } from 'express';

const BLOCKED_MIME = new Set([
  'application/x-msdownload',
  'application/x-msdos-program',
]);
const BLOCKED_EXT = /\.(exe|bat|cmd|scr)$/i;

@Controller('carpetas-compartidas')
@UseGuards(JwtAuthGuard, SessionGuard)
// CASL: 사용자 메뉴 게이트 — function `ver-carpetas-compartidas` (action read)
// 프로젝트의 CASL 데코레이터 (e.g. @CheckPolicies({ action: 'read', subject: 'ver-carpetas-compartidas' })) 추가
export class SharedFoldersController {
  constructor(private readonly svc: SharedFoldersService) {}

  @Get()
  async listMine(@Req() req: any) {
    return this.svc.listFoldersForUser(req.user.sub, req.user.storeId);
  }

  @Get(':folderId/files')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('read')
  async listFiles(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @Query() dto: ListFilesDto,
  ) {
    const result = await this.svc.listFilesInFolder(
      req.user.sub,
      req.user.storeId,
      folderId,
      dto,
    );
    if (process.env.SHARED_FOLDERS_LOG_LIST === 'true') {
      await this.svc.recordAccess({
        storeId: req.user.storeId,
        userId: req.user.sub,
        sharedFolderId: folderId,
        action: 'list',
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] ?? null,
      });
    }

    return result;
  }

  @Get(':folderId/files/:fileId/preview')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('read')
  async preview(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @Param('fileId') fileId: string,
    @Res() res: Response,
  ) {
    const { stream, meta } = await this.svc.getFileStream(folderId, req.user.storeId, fileId);
    res.setHeader('Content-Type', meta.mimeType ?? 'application/octet-stream');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${encodeURIComponent(meta.name ?? 'file')}"`,
    );
    await this.svc.recordAccess({
      storeId: req.user.storeId, userId: req.user.sub, sharedFolderId: folderId,
      action: 'preview', googleFileId: fileId, fileName: meta.name,
      bytes: meta.size ? Number(meta.size) : null,
      ipAddress: req.ip, userAgent: req.headers['user-agent'] ?? null,
    });
    stream.pipe(res);
  }

  @Get(':folderId/files/:fileId/download')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('read')
  async download(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @Param('fileId') fileId: string,
    @Res() res: Response,
  ) {
    const { stream, meta } = await this.svc.getFileStream(folderId, req.user.storeId, fileId);
    res.setHeader('Content-Type', meta.mimeType ?? 'application/octet-stream');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${encodeURIComponent(meta.name ?? 'file')}"`,
    );
    await this.svc.recordAccess({
      storeId: req.user.storeId, userId: req.user.sub, sharedFolderId: folderId,
      action: 'download', googleFileId: fileId, fileName: meta.name,
      bytes: meta.size ? Number(meta.size) : null,
      ipAddress: req.ip, userAgent: req.headers['user-agent'] ?? null,
    });
    stream.pipe(res);
  }

  @Get(':folderId/files/:fileId/thumbnail')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('read')
  async thumbnail(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @Param('fileId') fileId: string,
    @Res() res: Response,
  ) {
    const stream = await this.svc.getThumbnailStream(
      folderId, req.user.storeId, fileId,
    );
    if (!stream) {
      res.status(404).end();

      return;
    }
    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Cache-Control', 'private, max-age=1800');  // 30분 브라우저 캐시
    stream.pipe(res);
  }

  @Post(':folderId/files')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('write')
  @UseInterceptors(FileInterceptor('file'))
  async upload(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @UploadedFile() file: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('No file uploaded');
    const limitMb = Number(process.env.SHARED_FOLDERS_MAX_UPLOAD_MB ?? 50);
    if (file.size > limitMb * 1024 * 1024) {
      throw new PayloadTooLargeException(`Max ${limitMb}MB`);
    }
    if (BLOCKED_MIME.has(file.mimetype) || BLOCKED_EXT.test(file.originalname)) {
      throw new BadRequestException('Tipo de archivo no permitido');
    }
    // 파일명 sanitize — 슬래시·제어문자 제거
    const name = file.originalname.replace(/[\/\x00-\x1F]/g, '_');
    const { Readable } = await import('stream');
    const result = await this.svc.upload(
      folderId, req.user.storeId, name, file.mimetype, Readable.from(file.buffer),
    );
    await this.svc.recordAccess({
      storeId: req.user.storeId, userId: req.user.sub, sharedFolderId: folderId,
      action: 'upload', googleFileId: result.id, fileName: result.name,
      bytes: file.size,
      ipAddress: req.ip, userAgent: req.headers['user-agent'] ?? null,
    });

    return result;
  }

  @Patch(':folderId/files/:fileId')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('write')
  async rename(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @Param('fileId') fileId: string,
    @Body() dto: RenameFileDto,
  ) {
    const result = await this.svc.rename(folderId, req.user.storeId, fileId, dto.name);
    await this.svc.recordAccess({
      storeId: req.user.storeId, userId: req.user.sub, sharedFolderId: folderId,
      action: 'rename', googleFileId: fileId, fileName: dto.name,
      ipAddress: req.ip, userAgent: req.headers['user-agent'] ?? null,
    });

    return result;
  }

  @Delete(':folderId/files/:fileId')
  @UseGuards(SharedFolderAccessGuard)
  @RequireFolderAccess('write')
  async trash(
    @Req() req: any,
    @Param('folderId', ParseIntPipe) folderId: number,
    @Param('fileId') fileId: string,
  ) {
    await this.svc.trash(folderId, req.user.storeId, fileId);
    await this.svc.recordAccess({
      storeId: req.user.storeId, userId: req.user.sub, sharedFolderId: folderId,
      action: 'delete', googleFileId: fileId,
      ipAddress: req.ip, userAgent: req.headers['user-agent'] ?? null,
    });

    return { ok: true };
  }
}
```

NOTE: file streaming uses `Readable.from(file.buffer)` because `FileInterceptor` uses memoryStorage by default. For production-scale large uploads, swap this for the `streamStorage` pattern (out of scope for v1 — `SHARED_FOLDERS_MAX_UPLOAD_MB=50` keeps memory bounded). Verify `JwtAuthGuard` path: `grep -rn "export class JwtAuthGuard" api-ventago/src/app/auth/`. Verify `SessionGuard` path matches `api-ventago/src/app/session/guards/session.guard.ts`.

- [ ] **Step 5: Wire into module**

Edit `api-ventago/src/app/shared-folders/shared-folders.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { SharedFolder } from './models/shared-folder.model';
import { SharedFolderRoleAccess } from './models/shared-folder-role-access.model';
import { SharedFolderAccessLog } from './models/shared-folder-access-log.model';
import { GoogleDriveService } from './services/google-drive.service';
import { FolderAccessResolverService } from './services/folder-access-resolver.service';
import { SharedFoldersService } from './services/shared-folders.service';
import { SharedFolderAccessGuard } from './guards/shared-folder-access.guard';
import { SharedFoldersController } from './controllers/shared-folders.controller';

@Module({
  imports: [
    SequelizeModule.forFeature([
      SharedFolder,
      SharedFolderRoleAccess,
      SharedFolderAccessLog,
    ]),
  ],
  providers: [
    GoogleDriveService,
    FolderAccessResolverService,
    SharedFoldersService,
    SharedFolderAccessGuard,
  ],
  controllers: [SharedFoldersController],
  exports: [GoogleDriveService, FolderAccessResolverService],
})
export class SharedFoldersModule {}
```

- [ ] **Step 6: Run tests, green**

```bash
cd api-ventago && npx jest src/app/shared-folders/controllers/__tests__/shared-folders.controller.spec.ts
```
Expected: 3 passed.

Then full build:
```bash
npm run build
```
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add api-ventago/src/app/shared-folders/controllers/shared-folders.controller.ts api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders.controller.spec.ts api-ventago/src/app/shared-folders/shared-folders.module.ts
git commit -m "feat(shared-folders): user-facing controller wired into module

8 endpoints (list folders / list files / preview / download / upload /
rename / trash) gated by JwtAuthGuard + SessionGuard + per-folder
access guard. Audit log row written for every state-changing or
content-reading operation. File-type blocklist + 50MB cap on upload.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: SharedFoldersAdminController + module wiring

**Files:**
- Create: `api-ventago/src/app/shared-folders/controllers/shared-folders-admin.controller.ts`
- Create: `api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders-admin.controller.spec.ts`
- Modify: `api-ventago/src/app/shared-folders/shared-folders.module.ts`

- [ ] **Step 1: Write failing test**

Create `api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders-admin.controller.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { SharedFoldersAdminController } from '../shared-folders-admin.controller';
import { SharedFoldersAdminService } from '../../services/shared-folders-admin.service';

describe('SharedFoldersAdminController', () => {
  let controller: SharedFoldersAdminController;
  let svc: jest.Mocked<SharedFoldersAdminService>;
  beforeEach(async () => {
    svc = {
      getSaInfo: jest.fn().mockReturnValue({ email: 'sa@x', instructions: 'i' }),
      listForStore: jest.fn(),
      registerFolder: jest.fn(),
      updateFolder: jest.fn(),
      deleteFolder: jest.fn(),
      getRoleAccess: jest.fn(),
      replaceRoleAccess: jest.fn(),
      listAccessLogs: jest.fn(),
    } as any;
    const m = await Test.createTestingModule({
      controllers: [SharedFoldersAdminController],
      providers: [{ provide: SharedFoldersAdminService, useValue: svc }],
    }).compile();
    controller = m.get(SharedFoldersAdminController);
  });

  it('GET /admin/sa-info returns SA info', () => {
    expect(controller.saInfo()).toEqual({ email: 'sa@x', instructions: 'i' });
  });

  it('POST /admin/folders forwards to service', async () => {
    svc.registerFolder.mockResolvedValue({ id: 42 });
    const req: any = { user: { sub: 7, storeId: 5 } };
    const out = await controller.create(req, { googleFolderIdOrUrl: 'F', name: 'n', isSharedDrive: false } as any);
    expect(out).toEqual({ id: 42 });
    expect(svc.registerFolder).toHaveBeenCalledWith(7, 5, expect.objectContaining({ name: 'n' }));
  });

  it('PUT /admin/folders/:id/role-access forwards entries', async () => {
    const req: any = { user: { storeId: 5 } };
    await controller.putRoleAccess(req, 10, { entries: [] });
    expect(svc.replaceRoleAccess).toHaveBeenCalledWith(10, 5, { entries: [] });
  });
});
```

- [ ] **Step 2: Run, fail**

```bash
cd api-ventago && npx jest src/app/shared-folders/controllers/__tests__/shared-folders-admin.controller.spec.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement controller**

Create `api-ventago/src/app/shared-folders/controllers/shared-folders-admin.controller.ts`:

```typescript
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SessionGuard } from '../../session/guards/session.guard';
import { SharedFoldersAdminService } from '../services/shared-folders-admin.service';
import { RegisterFolderDto } from '../dto/register-folder.dto';
import { UpdateRoleAccessDto } from '../dto/update-role-access.dto';

@Controller('carpetas-compartidas/admin')
@UseGuards(JwtAuthGuard, SessionGuard)
// CASL: function `administrar-carpetas-compartidas` action `manage` (folders & matrix);
// logs endpoint uses `ver-logs-de-carpetas` action `read`.
export class SharedFoldersAdminController {
  constructor(private readonly svc: SharedFoldersAdminService) {}

  @Get('sa-info')
  saInfo() {
    return this.svc.getSaInfo();
  }

  @Get('folders')
  async list(@Req() req: any) {
    return this.svc.listForStore(req.user.storeId);
  }

  @Post('folders')
  async create(@Req() req: any, @Body() dto: RegisterFolderDto) {
    return this.svc.registerFolder(req.user.sub, req.user.storeId, dto);
  }

  @Patch('folders/:id')
  async update(
    @Req() req: any,
    @Param('id', ParseIntPipe) id: number,
    @Body() patch: { name?: string; description?: string; sortOrder?: number; isActive?: boolean },
  ) {
    await this.svc.updateFolder(id, req.user.storeId, patch);

    return { ok: true };
  }

  @Delete('folders/:id')
  async remove(@Req() req: any, @Param('id', ParseIntPipe) id: number) {
    await this.svc.deleteFolder(id, req.user.storeId);

    return { ok: true };
  }

  @Get('folders/:id/role-access')
  async getRoleAccess(@Req() req: any, @Param('id', ParseIntPipe) id: number) {
    return this.svc.getRoleAccess(id, req.user.storeId);
  }

  @Put('folders/:id/role-access')
  async putRoleAccess(
    @Req() req: any,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateRoleAccessDto,
  ) {
    await this.svc.replaceRoleAccess(id, req.user.storeId, dto);

    return { ok: true };
  }

  @Get('logs')
  async logs(
    @Req() req: any,
    @Query('folderId') folderId?: string,
    @Query('userId') userId?: string,
    @Query('action') action?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('pageSize') pageSize?: string,
    @Query('offset') offset?: string,
  ) {
    return this.svc.listAccessLogs(req.user.storeId, {
      folderId: folderId ? Number(folderId) : undefined,
      userId: userId ? Number(userId) : undefined,
      action,
      from: from ? new Date(from) : undefined,
      to: to ? new Date(to) : undefined,
      pageSize: pageSize ? Number(pageSize) : undefined,
      offset: offset ? Number(offset) : undefined,
    });
  }
}
```

- [ ] **Step 4: Update module to register admin service + controller**

Edit `api-ventago/src/app/shared-folders/shared-folders.module.ts` to add:

```typescript
import { SharedFoldersAdminService } from './services/shared-folders-admin.service';
import { SharedFoldersAdminController } from './controllers/shared-folders-admin.controller';
```

In the `providers` array add `SharedFoldersAdminService`; in `controllers` add `SharedFoldersAdminController`.

- [ ] **Step 5: Run tests + build**

```bash
cd api-ventago
npx jest src/app/shared-folders/controllers/__tests__/shared-folders-admin.controller.spec.ts
npm run build
```
Expected: 3 passed, build clean.

- [ ] **Step 6: Commit**

```bash
git add api-ventago/src/app/shared-folders/controllers/shared-folders-admin.controller.ts api-ventago/src/app/shared-folders/controllers/__tests__/shared-folders-admin.controller.spec.ts api-ventago/src/app/shared-folders/shared-folders.module.ts
git commit -m "feat(shared-folders): admin controller (folders CRUD + role-access matrix + logs)

8 admin endpoints under /carpetas-compartidas/admin. PUT role-access
replaces the entire matrix in a single transaction; CASCADE handles
role/folder deletion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Modules + Functions seed updates

**Files:**
- Modify: `api-ventago/src/app/modules/seed/modules.seed.ts`
- Modify: `api-ventago/src/app/functions/seed/functions.seed.ts`

- [ ] **Step 1: Add module entries**

Open `api-ventago/src/app/modules/seed/modules.seed.ts` and locate the array under `appSlug: 'admin'`. Append these two entries to that admin app's `modules` array (preserve existing ordering and trailing commas):

```typescript
        {
          name: 'Carpetas Compartidas',
          slug: 'carpetas-compartidas',
          description: 'Acceso a carpetas de Google Drive compartidas con la tienda',
          icon: 'tabler:cloud-share',
          url: '/carpetas-compartidas',
          isMain: false,
          isAuxiliary: true,
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

If the seed file's modules type doesn't have an `isAuxiliary` field on the literal type (TS will error), check `modules.model.ts` for the column. The existing seed already uses `isAuxiliary` based on the schema; if the seed function shape differs, mirror the existing pattern from auxiliary entries elsewhere (`grep -n "isAuxiliary" api-ventago/src/app/modules/seed/modules.seed.ts`).

- [ ] **Step 2: Add function entries**

Open `api-ventago/src/app/functions/seed/functions.seed.ts`. Following the `logsAuditoriaModule` block precedent (lines ~15-44 in the existing file), append at the end of the `functionsSeed` async function:

```typescript
  // ─── App: Admin › Módulo: Carpetas Compartidas ───
  const carpetasCompartidasFunctions = [
    {
      name: 'Ver carpetas compartidas',
      description:
        '[Admin › Carpetas Compartidas] Ver listado de carpetas asignadas y abrir archivos',
    },
    {
      name: 'Subir y editar archivos',
      description:
        '[Admin › Carpetas Compartidas] Subir, renombrar y mover a papelera archivos en carpetas con permiso de escritura',
    },
  ];
  const carpetasCompartidasModule = await Modules.findOne({
    where: { slug: 'carpetas-compartidas' },
  });
  if (carpetasCompartidasModule) {
    for (const func of carpetasCompartidasFunctions) {
      await Functions.findOrCreate({
        where: { name: func.name, moduleId: carpetasCompartidasModule.id },
        defaults: {
          name: func.name,
          description: func.description,
          slug: generateSlug(func.name),
          moduleId: carpetasCompartidasModule.id,
        },
      });
    }
  }

  // ─── App: Admin › Módulo: Configurar Carpetas Compartidas ───
  const configurarCarpetasFunctions = [
    {
      name: 'Administrar carpetas compartidas',
      description:
        '[Admin › Configurar Carpetas] Registrar/editar/eliminar carpetas y definir matriz de permisos por rol',
    },
    {
      name: 'Ver logs de carpetas',
      description:
        '[Admin › Configurar Carpetas] Consultar historial de acceso, descargas y subidas a carpetas compartidas',
    },
  ];
  const configurarCarpetasModule = await Modules.findOne({
    where: { slug: 'configurar-carpetas-compartidas' },
  });
  if (configurarCarpetasModule) {
    for (const func of configurarCarpetasFunctions) {
      await Functions.findOrCreate({
        where: { name: func.name, moduleId: configurarCarpetasModule.id },
        defaults: {
          name: func.name,
          description: func.description,
          slug: generateSlug(func.name),
          moduleId: configurarCarpetasModule.id,
        },
      });
    }
  }
```

- [ ] **Step 3: Trigger seed via boot**

Start the dev server (it runs `modulesSeed()` then `functionsSeed()` on first boot via `user-registration.service.ts`):
```bash
cd api-ventago && npm run start:dev
```
Watch for `modulesSeed` / `functionsSeed` log lines without errors. Stop with Ctrl+C after ~30 sec.

Verify rows landed:
```bash
docker exec api_ventago_db psql -U coolsistema -d ventago -c "
SELECT m.slug, m.is_auxiliary FROM modules m WHERE m.slug LIKE 'carpetas-compartidas%' OR m.slug = 'configurar-carpetas-compartidas';
SELECT f.slug FROM functions f JOIN modules m ON f.module_id = m.id
  WHERE m.slug IN ('carpetas-compartidas', 'configurar-carpetas-compartidas');
"
```
Expected: 2 module rows + 4 function rows (`ver-carpetas-compartidas`, `subir-y-editar-archivos`, `administrar-carpetas-compartidas`, `ver-logs-de-carpetas`).

- [ ] **Step 4: Commit**

```bash
git add api-ventago/src/app/modules/seed/modules.seed.ts api-ventago/src/app/functions/seed/functions.seed.ts
git commit -m "feat(shared-folders): seed 2 modules + 4 functions for CASL

Modules (auxiliary, Herramientas section):
- carpetas-compartidas (user-facing)
- configurar-carpetas-compartidas (admin)
Functions (CASL subjects):
- ver-carpetas-compartidas, subir-y-editar-archivos
- administrar-carpetas-compartidas, ver-logs-de-carpetas

Per-store role assignment via existing /configuracion/permisos UI.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Winston key masking + env documentation

**Files:**
- Modify: `api-ventago/src/common/logger/logger.config.ts`
- Create: `api-ventago/.env.example` (add lines; create section if file doesn't exist)

- [ ] **Step 1: Inspect existing logger config**

```bash
cat api-ventago/src/common/logger/logger.config.ts
```
Note the formatter chain used.

- [ ] **Step 2: Add masking format**

Add a Winston format helper that scrubs SA-key-like fields. Insert near the top of `logger.config.ts`:

```typescript
import { format as winstonFormat } from 'winston';

// SA 키/시크릿이 실수로 로그에 포함되어도 마스킹.
// JSON.stringify된 객체에 `private_key` 같은 키가 보이면 ***로 치환.
const SECRET_KEYS = ['private_key', 'privateKey', 'GOOGLE_SA_KEY_JSON'];
const maskSecrets = winstonFormat((info) => {
  const walk = (obj: any): any => {
    if (!obj || typeof obj !== 'object') return obj;
    for (const k of Object.keys(obj)) {
      if (SECRET_KEYS.includes(k)) obj[k] = '***';
      else if (typeof obj[k] === 'object') walk(obj[k]);
    }

    return obj;
  };

  return walk(info);
});
```

Then in the format chain (likely `format.combine(...)`), add `maskSecrets()` as the FIRST format so subsequent stages see masked data:

```typescript
format: format.combine(maskSecrets(), /* existing formats */),
```

- [ ] **Step 3: Update `.env.example`**

Append to `api-ventago/.env.example`:

```
# ── Carpetas Compartidas (Google Drive) ────────────────────────────
# Path to the GCP service account JSON key (chmod 600).
# Create the SA in Cloud Console → IAM → Service Accounts.
# Enable Drive API on the project. Share each target folder (or a Shared Drive)
# with the SA email as Editor before registering it in the admin UI.
GOOGLE_SA_KEY_JSON=/run/secrets/google-sa.json
SHARED_FOLDERS_MAX_UPLOAD_MB=50
SHARED_FOLDERS_CACHE_TTL_SEC=60
SHARED_FOLDERS_LIST_TTL_SEC=30
SHARED_FOLDERS_LOG_LIST=false
```

- [ ] **Step 4: Manual log-leak smoke test**

Boot:
```bash
cd api-ventago && npm run start:dev
```
Hit any route that triggers Drive init logging. In the log output, the SA email should appear but no `private_key` value. Stop with Ctrl+C.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/common/logger/logger.config.ts api-ventago/.env.example
git commit -m "feat(shared-folders): mask private_key in Winston + document env vars

Defense-in-depth: even if a stray log call ever serializes the SA key
JSON, private_key fields are scrubbed to *** before formatting.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: End-to-end backend smoke test (manual)

This task verifies the whole backend integrates with a real Drive account. Run AFTER pre-flight (SA + test Shared Drive).

**Files:** none modified. Output goes to a checklist + a screenshot of working Postman/curl.

- [ ] **Step 1: Boot the backend**

```bash
cd api-ventago && npm run start:dev
```
Wait for `Nest application successfully started`.

- [ ] **Step 2: Grab a JWT**

POST to your usual `/auth/login` with a test user that has `store_id` matching a real store. Copy the access token + sessionToken.

- [ ] **Step 3: Manually grant the user the new functions**

Either via the existing `/configuracion/permisos` UI, or directly via DB:
```bash
docker exec api_ventago_db psql -U coolsistema -d ventago <<'SQL'
WITH r AS (SELECT id, store_id FROM roles WHERE name = '<role-of-test-user>'),
     fc AS (SELECT id FROM functions WHERE slug = 'ver-carpetas-compartidas'),
     fw AS (SELECT id FROM functions WHERE slug = 'subir-y-editar-archivos'),
     fa AS (SELECT id FROM functions WHERE slug = 'administrar-carpetas-compartidas')
INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
SELECT r.id, f.id, r.store_id, NOW(), NOW()
FROM r CROSS JOIN (
  SELECT id FROM functions WHERE slug IN
    ('ver-carpetas-compartidas','subir-y-editar-archivos','administrar-carpetas-compartidas')
) f
ON CONFLICT DO NOTHING;

-- 가장 단순하게 read action 부여 (운영 시에는 행위별 분리)
INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
SELECT rf.id, 'read', NOW(), NOW() FROM role_functions rf
JOIN functions f ON rf.function_id = f.id
WHERE f.slug IN ('ver-carpetas-compartidas','subir-y-editar-archivos','administrar-carpetas-compartidas')
ON CONFLICT DO NOTHING;
SQL
```

- [ ] **Step 4: Register your test Shared Drive root folder**

```bash
TOKEN="<jwt>"
SESS="<sessionToken>"
DRIVE_ID="<your-shared-drive-id-from-preflight>"

curl -sX POST http://localhost:5002/api/carpetas-compartidas/admin/folders \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-session-token: $SESS" \
  -H "Content-Type: application/json" \
  -d "{
    \"googleFolderIdOrUrl\": \"$DRIVE_ID\",
    \"name\": \"Test Shared Drive\",
    \"isSharedDrive\": true,
    \"sharedDriveId\": \"$DRIVE_ID\"
  }"
```
Expected: `{"id":1}` (or similar). If you get a 400 about SA access, double-check the SA email is a member of the Shared Drive.

- [ ] **Step 5: Assign your role to the folder**

```bash
ROLE_ID="<id-of-your-test-role>"
FOLDER_ID=1
curl -sX PUT http://localhost:5002/api/carpetas-compartidas/admin/folders/$FOLDER_ID/role-access \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-session-token: $SESS" \
  -H "Content-Type: application/json" \
  -d "{\"entries\":[{\"roleId\":$ROLE_ID,\"canRead\":true,\"canWrite\":true}]}"
```
Expected: `{"ok":true}`.

- [ ] **Step 6: List folders + files**

```bash
curl -sH "Authorization: Bearer $TOKEN" -H "x-session-token: $SESS" \
  http://localhost:5002/api/carpetas-compartidas
# → should include id=1 with canRead/canWrite true

curl -sH "Authorization: Bearer $TOKEN" -H "x-session-token: $SESS" \
  "http://localhost:5002/api/carpetas-compartidas/1/files?pageSize=5"
# → file list from the Shared Drive
```

- [ ] **Step 7: Upload + download round trip**

```bash
echo "hello world" > /tmp/sf-test.txt
curl -sX POST http://localhost:5002/api/carpetas-compartidas/1/files \
  -H "Authorization: Bearer $TOKEN" -H "x-session-token: $SESS" \
  -F "file=@/tmp/sf-test.txt"
# → returns { id: "<google-file-id>", name: "sf-test.txt", ... }

FILE_ID="<id-from-above>"
curl -sH "Authorization: Bearer $TOKEN" -H "x-session-token: $SESS" \
  "http://localhost:5002/api/carpetas-compartidas/1/files/$FILE_ID/download" -o /tmp/sf-roundtrip.txt
diff /tmp/sf-test.txt /tmp/sf-roundtrip.txt
# → no output (files match)
```

- [ ] **Step 8: Verify tenant isolation**

Login as a user from a DIFFERENT store. Try:
```bash
curl -i -H "Authorization: Bearer $OTHER_TOKEN" -H "x-session-token: $OTHER_SESS" \
  http://localhost:5002/api/carpetas-compartidas/1/files
```
Expected: HTTP 404 (not 403 — existence hidden).

- [ ] **Step 9: Verify access logs**

```bash
curl -sH "Authorization: Bearer $TOKEN" -H "x-session-token: $SESS" \
  http://localhost:5002/api/carpetas-compartidas/admin/logs | head -50
```
Expected: rows for `upload`, `download` from your round trip.

- [ ] **Step 10: Run the full unit test suite**

```bash
cd api-ventago && npx jest src/app/shared-folders
```
Expected: all suites pass, no failures.

- [ ] **Step 11: Commit any tweaks discovered during smoke testing**

If smoke testing revealed fixes (auth header name mismatch, JSON parsing quirks, etc.), commit them now with a single follow-up commit. If none — note "no follow-up needed" in your work log and skip this step.

---

### Task 16 (optional polish — do if traffic justifies it)

The spec lists two extra hardening layers beyond the resolver's 60s cache. Both are pure additions — feature behavior is unchanged whether they're on or off. Add them once smoke testing passes if you expect heavy concurrent use (≥50 simultaneous file-browser users) or want to bound Drive API quota usage.

**16a. MemoryCacheService wrapping for list endpoints**

- [ ] Wrap `SharedFoldersService.listFoldersForUser` with the existing `MemoryCacheService`. Key: `sf:list:store:${storeId}:user:${userId}`, TTL: 60s.
- [ ] Wrap `SharedFoldersService.listFilesInFolder` with `MemoryCacheService`. Key: `sf:files:${folderId}:${pageToken ?? '_'}:${q ?? '_'}`, TTL: 30s.
- [ ] In `upload`/`trash`/`rename`, after a successful Drive op, invalidate the `sf:files:${folderId}:*` keys (use a prefix-delete helper or store keys per folder for invalidation).
- [ ] In `SharedFoldersAdminService.replaceRoleAccess`, after invalidating the resolver, also delete `sf:list:store:${storeId}:user:*` keys (per-store sweep).
- [ ] Commit:
  ```bash
  git commit -am "perf(shared-folders): MemoryCacheService wrapping for list + files endpoints"
  ```

**16b. Per-route rate limit (project's existing throttler)**

- [ ] Decorate user controller routes with `@Throttle` from the project's existing throttler module (confirm import via `grep -rn "@Throttle" api-ventago/src --include="*.ts" | head -5`):
  - General GET routes: 60/min
  - Upload (`POST .../files`): 10/min
  - Download/preview/thumbnail: 100/min
- [ ] If the project doesn't have a per-route throttler yet, this becomes a Phase-level decision rather than a v1 task — note in the work log and skip.
- [ ] Commit:
  ```bash
  git commit -am "feat(shared-folders): per-route rate limits"
  ```

---

## Self-Review

After completing all 15 tasks, run this checklist before declaring the backend done:

- [ ] All Jest tests pass: `cd api-ventago && npx jest src/app/shared-folders`
- [ ] TypeScript builds clean: `cd api-ventago && npm run build`
- [ ] Migration applied to dev DB; intel docs committed
- [ ] Manual smoke test (Task 15) — every step green
- [ ] No SA private key in any log line (grep recent dev log for `BEGIN PRIVATE KEY` — must be 0)
- [ ] Cross-tenant folder access returns 404 (not 403)
- [ ] All commits authored with the project's required Co-Authored-By trailer
- [ ] `git log --oneline` since plan start shows ~15 commits, one per task

---

## What's NOT in this plan (intentional)

The spec covers a frontend layer too. That ships in a follow-up plan after this backend is verified working:
- Sidebar entries (modules already seeded — they'll appear once the frontend page routes exist)
- i18n keys (es + ko)
- SWR hooks
- 4 frontend pages + view components (list, browser, admin folders, admin logs)
- Dark-navy + gold MUI styling per `sketch-findings-ace-online`

Trigger the follow-up plan with:
> "Backend verified. Continue with the frontend plan for shared folders."
