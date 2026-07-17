# Revendedor 온보딩 + 읽기 MVP (Path B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 외부 가입자(`reseller.resellers`)가 앱에서 가입·서류제출 → superadmin 승인 → 매장 판매권을 얻고 `{id}@app` 로그인 후 승인매장 카탈로그/추천/GPS 를 열람하는 읽기 MVP 를 구현한다.

**Architecture:** 병합된 `reseller` 백엔드 모듈(auth/catalog/recommendation/geo) 확장. 신규 = 서류 심사 온보딩(register + 관리자 승인) + reseller session 기반 Flutter 화면. vendedor `/mobile/*` realm 무변경. 판매/견적(pedido)은 범위 밖.

**Tech Stack:** NestJS 11 + Sequelize(schema `reseller`, underscored), PostgreSQL 18, MinIO, JWT(`reseller-jwt`); Next.js 13 Pages Router + MUI5 + SWR(ventago-app superadmin); Flutter + Riverpod + Dio + secure storage + image_picker(mobile-sales-app).

## Global Constraints

- DB 컬럼 snake_case (Sequelize `underscored: true`). 모델 camelCase = DB snake_case.
- 마이그레이션은 로컬(Mac PG18 5432) + 운영(PG18 5434) **동시 적용**. 신규 테이블 owner→coolsistema DO 블록(테이블+시퀀스) 필수.
- Pool 낭비 금지: 전역 Sequelize pool 재사용, raw SQL release 보장. MinIO 업로드(외부 I/O)는 DB 커넥션 점유 밖에서.
- ESLint(ventago-app): `newline-before-return`, `lines-around-comment` (return/주석 위 빈 줄). `apiConnector.remove()` (`.delete()` 아님). 에러 = 인라인 Alert + 글로벌 토스트.
- reseller 로그인 식별자 email = `{document}@app`. status 게이트 `approved` 만 로그인 허용.
- superadmin 전용 엔드포인트 = `@Auth(ValidRoles.superadmin)` (admin-console 패턴).
- vendedor(`/mobile/*`) 경로/식당/소매 회귀 절대 금지.

---

## Wave 1 — 백엔드 온보딩 (api-ventago)

### Task 1.1: 마이그레이션 — resellers.status + reseller_documents

**Files:**
- Create: `api-ventago/migrations/2026-07-17-reseller-onboarding.sql`

**Interfaces:**
- Produces: 컬럼 `reseller.resellers.status/reviewed_by/reviewed_at/reject_reason`; 테이블 `reseller.reseller_documents(id, reseller_id, doc_type, file_name, created_at)`.

- [ ] **Step 1: 마이그레이션 SQL 작성**

```sql
-- 2026-07-17 Revendedor 온보딩: 심사상태 + 서류
BEGIN;

ALTER TABLE reseller.resellers
  ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'pending_review',
  ADD COLUMN IF NOT EXISTS reviewed_by INTEGER,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reject_reason VARCHAR(300);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_reseller_status') THEN
    ALTER TABLE reseller.resellers
      ADD CONSTRAINT chk_reseller_status
      CHECK (status IN ('pending_review','approved','rejected'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS reseller.reseller_documents (
  id           SERIAL PRIMARY KEY,
  reseller_id  INTEGER NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
  doc_type     VARCHAR(24) NOT NULL,
  file_name    VARCHAR(255) NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_doc_type CHECK (doc_type IN ('dni_photo','residence_cert','selfie'))
);
CREATE INDEX IF NOT EXISTS idx_reseller_docs_reseller
  ON reseller.reseller_documents(reseller_id);

-- owner → coolsistema (role 존재 시)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE reseller.reseller_documents OWNER TO coolsistema;
    ALTER SEQUENCE reseller.reseller_documents_id_seq OWNER TO coolsistema;
  END IF;
END $$;

COMMIT;
```

- [ ] **Step 2: 운영(5434) dry-run 검증 (트랜잭션 롤백)**

Run (SSH): `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 -c 'BEGIN; \i /tmp/2026-07-17-reseller-onboarding.sql ; ROLLBACK;'"` — 사전 `uploadFile` 로 /tmp 전송.
Expected: 에러 없이 ROLLBACK. (실제 적용은 Task 1.7 배포 게이트.)

- [ ] **Step 3: 로컬(5432) 적용 명령 사용자 전달**

사용자에게: `psql -p 5432 -d ventago -f api-ventago/migrations/2026-07-17-reseller-onboarding.sql` (샌드박스는 Mac localhost 직접 불가).

- [ ] **Step 4: 커밋**

```bash
git add api-ventago/migrations/2026-07-17-reseller-onboarding.sql
git commit -m "feat(reseller): 온보딩 마이그레이션 — resellers.status + reseller_documents"
```

---

### Task 1.2: 모델 — Reseller.status 필드 + ResellerDocument 모델

**Files:**
- Modify: `api-ventago/src/app/reseller/reseller.model.ts`
- Create: `api-ventago/src/app/reseller/reseller-document.model.ts`

**Interfaces:**
- Produces: `Reseller.status: 'pending_review'|'approved'|'rejected'`, `Reseller.reviewedBy/reviewedAt/rejectReason`; `ResellerDocument{ id, resellerId, docType, fileName, createdAt }`.

- [ ] **Step 1: Reseller 모델에 필드 추가**

`reseller.model.ts` 의 `isActive` 컬럼 아래에 추가:

```typescript
  @Column({ type: DataType.STRING(16), allowNull: false, defaultValue: 'pending_review' })
  declare status: 'pending_review' | 'approved' | 'rejected';

  @Column({ type: DataType.INTEGER, allowNull: true })
  declare reviewedBy: number | null;

  @Column({ type: DataType.DATE, allowNull: true })
  declare reviewedAt: Date | null;

  @Column({ type: DataType.STRING(300), allowNull: true })
  declare rejectReason: string | null;
```

- [ ] **Step 2: ResellerDocument 모델 작성**

```typescript
import { Column, DataType, Model, Table } from 'sequelize-typescript';

@Table({ tableName: 'reseller_documents', schema: 'reseller', timestamps: false })
export class ResellerDocument extends Model {
  @Column({ type: DataType.INTEGER, primaryKey: true, autoIncrement: true })
  declare id: number;

  @Column({ type: DataType.INTEGER, allowNull: false })
  declare resellerId: number;

  // 'dni_photo' | 'residence_cert' | 'selfie'
  @Column({ type: DataType.STRING(24), allowNull: false })
  declare docType: 'dni_photo' | 'residence_cert' | 'selfie';

  @Column({ type: DataType.STRING(255), allowNull: false })
  declare fileName: string;

  @Column({ type: DataType.DATE, allowNull: false, defaultValue: DataType.NOW })
  declare createdAt: Date;
}
```

- [ ] **Step 3: 모듈에 모델 등록**

`reseller.module.ts` 의 `SequelizeModule.forFeature([...])` 에 `ResellerDocument` 추가 + import.

- [ ] **Step 4: 빌드 확인**

Run: `cd api-ventago && npx tsc --noEmit`
Expected: 에러 없음.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/reseller/reseller.model.ts api-ventago/src/app/reseller/reseller-document.model.ts api-ventago/src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): status 필드 + ResellerDocument 모델"
```

---

### Task 1.3: 로그인 status 게이트

**Files:**
- Modify: `api-ventago/src/app/reseller/auth/reseller-auth.service.ts`
- Test: `api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts`

**Interfaces:**
- Consumes: `Reseller.status` (Task 1.2).
- Produces: `login()` 이 `status !== 'approved'` 이면 401 `RESELLER_NOT_APPROVED`.

- [ ] **Step 1: 실패 테스트 작성**

`reseller-auth.service.spec.ts` 에 추가:

```typescript
it('pending_review reseller 로그인 → 401 RESELLER_NOT_APPROVED', async () => {
  resellerModel.findOne.mockResolvedValue({
    id: 1, isActive: true, status: 'pending_review',
    password: await bcrypt.hash('pw', 10),
  } as any);
  await expect(
    service.login({ emailOrDocument: '111@app', password: 'pw' }),
  ).rejects.toMatchObject({ response: { code: 'RESELLER_NOT_APPROVED' } });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest reseller-auth.service -t RESELLER_NOT_APPROVED`
Expected: FAIL (게이트 없음 → 통과해버림).

- [ ] **Step 3: 게이트 구현**

`login()` 의 `if (!reseller || !reseller.isActive || !reseller.password)` 직후에:

```typescript
    if (reseller.status !== 'approved') {
      throw new UnauthorizedException({
        code: 'RESELLER_NOT_APPROVED',
        message: 'Cuenta en revisión o rechazada',
        status: reseller.status,
      });
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest reseller-auth.service`
Expected: PASS (기존 테스트 포함).

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/reseller/auth/
git commit -m "feat(reseller): 로그인 status=approved 게이트 (RESELLER_NOT_APPROVED)"
```

---

### Task 1.4: 가입 register (multipart + MinIO 트랜잭션)

**Files:**
- Create: `api-ventago/src/app/reseller/auth/dto/reseller-register.dto.ts`
- Modify: `api-ventago/src/app/reseller/auth/reseller-auth.controller.ts`, `reseller-auth.service.ts`, `reseller.module.ts`
- Test: `api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts`

**Interfaces:**
- Consumes: `MinioService.uploadFile(file, fileName) → { fileName }` (`src/common/minio`), `ResellerDocument`, `ResellerTiendaLink`.
- Produces: `register(dto, files) → { id, email }`. `POST /reseller/auth/register` multipart 3 파일(`dniPhoto`,`residenceCert`,`selfie`).

- [ ] **Step 1: DTO 작성**

```typescript
import { IsArray, IsNotEmpty, IsString, MinLength } from 'class-validator';
import { Type } from 'class-transformer';

export class ResellerRegisterDto {
  @IsString() @IsNotEmpty() readonly name: string;
  @IsString() @IsNotEmpty() readonly phone: string;
  @IsString() @IsNotEmpty() readonly document: string;
  @IsString() @MinLength(6) readonly password: string;

  // 판매 희망 매장 id[] (multipart 라 문자열로 옴 → number 변환)
  @IsArray() @Type(() => Number) readonly storeIds: number[];
}
```

- [ ] **Step 2: 실패 테스트 (중복 document → 409, 이미지 실패 → 롤백)**

```typescript
it('중복 document 가입 → 409', async () => {
  resellerModel.findOne.mockResolvedValue({ id: 9 } as any);
  await expect(
    service.register({ name:'A', phone:'1', document:'111', password:'secret', storeIds:[6] }, fakeFiles()),
  ).rejects.toMatchObject({ status: 409 });
});

it('MinIO 업로드 실패 → reseller 롤백(생성 안 됨)', async () => {
  resellerModel.findOne.mockResolvedValue(null);
  const tx = { commit: jest.fn(), rollback: jest.fn() };
  sequelize.transaction.mockResolvedValue(tx);
  minio.uploadFile.mockRejectedValue(new Error('minio down'));
  await expect(
    service.register({ name:'A', phone:'1', document:'111', password:'secret', storeIds:[6] }, fakeFiles()),
  ).rejects.toThrow();
  expect(tx.rollback).toHaveBeenCalled();
});
```

`fakeFiles()` 헬퍼: `{ dniPhoto:[{originalname:'d.jpg',buffer:Buffer.from('x')}], residenceCert:[...], selfie:[...] }`.

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd api-ventago && npx jest reseller-auth.service -t 가입`
Expected: FAIL (`register` 미정의).

- [ ] **Step 4: register 서비스 구현**

`reseller-auth.service.ts` 에 (생성자에 `@InjectModel(ResellerDocument)`, `@InjectModel(ResellerTiendaLink)`, `MinioService`, `Sequelize` 주입):

```typescript
async register(
  dto: ResellerRegisterDto,
  files: { dniPhoto?: Express.Multer.File[]; residenceCert?: Express.Multer.File[]; selfie?: Express.Multer.File[] },
): Promise<{ id: number; email: string }> {
  const email = `${dto.document}@app`;
  const dup = await this.resellerModel.findOne({ where: { document: dto.document } });
  if (dup) {
    throw new ConflictException({ code: 'RESELLER_DUPLICATE', message: 'Documento ya registrado' });
  }

  const docSpecs: Array<[ 'dni_photo'|'residence_cert'|'selfie', Express.Multer.File | undefined ]> = [
    ['dni_photo', files.dniPhoto?.[0]],
    ['residence_cert', files.residenceCert?.[0]],
    ['selfie', files.selfie?.[0]],
  ];
  for (const [, f] of docSpecs) {
    if (!f) throw new BadRequestException({ code: 'RESELLER_DOCS_REQUIRED', message: 'Faltan documentos' });
  }

  // 1) MinIO 업로드 (DB 트랜잭션 밖 — 커넥션 점유 최소화)
  const uploaded: Array<{ docType: 'dni_photo'|'residence_cert'|'selfie'; fileName: string }> = [];
  for (const [docType, f] of docSpecs) {
    const fileName = `reseller/${dto.document}/${docType}-${Date.now()}-${f!.originalname}`;
    const res = await this.minio.uploadFile(f!, fileName);
    uploaded.push({ docType, fileName: res.fileName });
  }

  // 2) DB 트랜잭션
  const tx = await this.sequelize.transaction();
  try {
    const reseller = await this.resellerModel.create({
      document: dto.document, name: dto.name, email, phone: dto.phone,
      password: await bcrypt.hash(dto.password, 10),
      status: 'pending_review', isActive: false,
    } as any, { transaction: tx });

    await this.resellerDocModel.bulkCreate(
      uploaded.map((u) => ({ resellerId: reseller.id, docType: u.docType, fileName: u.fileName })),
      { transaction: tx },
    );
    await this.linkModel.bulkCreate(
      dto.storeIds.map((storeId) => ({ resellerId: reseller.id, storeId, status: 'pending' })),
      { transaction: tx, ignoreDuplicates: true },
    );

    await tx.commit();

    return { id: reseller.id, email };
  } catch (e) {
    await tx.rollback();
    throw e;
  }
}
```

import 추가: `BadRequestException, ConflictException`.

- [ ] **Step 5: 컨트롤러 엔드포인트 추가**

`reseller-auth.controller.ts` 에:

```typescript
  @Post('register')
  @UseInterceptors(FileFieldsInterceptor([
    { name: 'dniPhoto', maxCount: 1 },
    { name: 'residenceCert', maxCount: 1 },
    { name: 'selfie', maxCount: 1 },
  ]))
  register(
    @Body() dto: ResellerRegisterDto,
    @UploadedFiles() files: {
      dniPhoto?: Express.Multer.File[];
      residenceCert?: Express.Multer.File[];
      selfie?: Express.Multer.File[];
    },
  ) {
    return this.authService.register(dto, files);
  }
```

import: `Post, Body, UseInterceptors, UploadedFiles` (@nestjs/common), `FileFieldsInterceptor` (@nestjs/platform-express). `reseller.module.ts` imports 에 `MinioModule` 추가.

- [ ] **Step 6: 테스트 통과 확인**

Run: `cd api-ventago && npx jest reseller-auth.service`
Expected: PASS.

- [ ] **Step 7: 커밋**

```bash
git add api-ventago/src/app/reseller/auth/ api-ventago/src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): 가입 register — multipart 서류3종 MinIO + pending 링크(트랜잭션)"
```

---

### Task 1.5: `/reseller/auth/me` 승인매장 반환

**Files:**
- Modify: `api-ventago/src/app/reseller/auth/reseller-auth.service.ts`, `reseller-auth.controller.ts`
- Test: `reseller-auth.service.spec.ts`

**Interfaces:**
- Consumes: `ResellerTiendaLink(status='approved')` + `stores`.
- Produces: `me(resellerId) → { id, name, email, provinceId, stores: {storeId, storeName}[] }`.

- [ ] **Step 1: 실패 테스트**

```typescript
it('me → status=approved 매장만 반환', async () => {
  sequelize.query.mockResolvedValue([{ store_id: 6, store_name: 'ACE' }]);
  resellerModel.findByPk.mockResolvedValue({ id:1, name:'A', email:'1@app', provinceId:24 } as any);
  const r = await service.me(1);
  expect(r.stores).toEqual([{ storeId: 6, storeName: 'ACE' }]);
});
```

- [ ] **Step 2: 실패 확인** — `cd api-ventago && npx jest reseller-auth.service -t "me →"` → FAIL.

- [ ] **Step 3: me() 구현**

```typescript
async me(resellerId: number) {
  const reseller = await this.resellerModel.findByPk(resellerId);
  if (!reseller) throw new UnauthorizedException({ code: 'RESELLER_NOT_FOUND' });
  const rows = await this.sequelize.query<{ store_id: number; store_name: string }>(
    `SELECT l.store_id, s.name AS store_name
       FROM reseller.reseller_tienda_link l
       JOIN stores s ON s.id = l.store_id
      WHERE l.reseller_id = :rid AND l.status = 'approved'
      ORDER BY s.name`,
    { replacements: { rid: resellerId }, type: QueryTypes.SELECT },
  );

  return {
    id: reseller.id, name: reseller.name, email: reseller.email,
    provinceId: reseller.provinceId,
    stores: rows.map((r) => ({ storeId: r.store_id, storeName: r.store_name })),
  };
}
```

컨트롤러 `@Get('me')` 를 `this.authService.me(reseller.id)` 로 교체(기존 me 반환 확장).

- [ ] **Step 4: 통과 확인** — `npx jest reseller-auth.service` → PASS.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/reseller/auth/
git commit -m "feat(reseller): /me 승인매장 목록 반환 (store selector 소스)"
```

---

### Task 1.6: catalog approved 스코프 확인/보강

**Files:**
- Modify: `api-ventago/src/app/reseller/catalog/reseller-catalog.service.ts`
- Test: `api-ventago/src/app/reseller/catalog/reseller-catalog.service.spec.ts` (없으면 생성)

**Interfaces:**
- Produces: `catalog()` 이 `reseller_tienda_link.status='approved'` 매장만 노출.

- [ ] **Step 1: 실패 테스트 (pending 매장 상품 제외)**

```typescript
it('pending 링크 매장 상품은 카탈로그에서 제외', async () => {
  // approved 매장(6)만, pending 매장(7) 상품은 안 나와야 함
  const rows = await service.catalog(1, {});
  expect(rows.items.every((i) => i.storeId === 6)).toBe(true);
});
```

- [ ] **Step 2: 실패/현상 확인** — `npx jest reseller-catalog.service` (현재 SQL 이 status 필터 하는지 검증).

- [ ] **Step 3: SQL 에 status='approved' 조인 조건 추가(누락 시)**

catalog 쿼리의 `reseller_tienda_link` 조인/서브쿼리에 `AND l.status = 'approved'` 강제.

- [ ] **Step 4: 통과 확인** — `npx jest reseller-catalog.service` → PASS.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/reseller/catalog/
git commit -m "fix(reseller): catalog 는 approved 링크 매장만 노출"
```

---

### Task 1.7: 관리자 승인 API (superadmin)

**Files:**
- Create: `api-ventago/src/app/reseller/admin/reseller-admin.controller.ts`, `reseller-admin.service.ts`
- Modify: `reseller.module.ts`
- Test: `reseller-admin.service.spec.ts`

**Interfaces:**
- Consumes: `Reseller`, `ResellerDocument`, `ResellerTiendaLink`, `MinioService` (URL은 프론트 조합).
- Produces:
  - `GET /reseller/admin/pending → { id, name, document, phone, submittedAt, docs:{docType,fileName}[], stores:{storeId,storeName,status}[] }[]`
  - `PATCH /reseller/admin/:id/approve  body {storeIds:number[]} → { ok:true }`
  - `PATCH /reseller/admin/:id/reject   body {reason:string} → { ok:true }`

- [ ] **Step 1: 실패 테스트 (approve → status/links 갱신)**

```typescript
it('approve → reseller.approved + 지정 매장 link approved', async () => {
  const reseller = { id:1, update: jest.fn() };
  resellerModel.findByPk.mockResolvedValue(reseller as any);
  await service.approve(1, { storeIds: [6] }, /*superadminId*/ 99);
  expect(reseller.update).toHaveBeenCalledWith(
    expect.objectContaining({ status: 'approved', isActive: true, reviewedBy: 99 }),
  );
  expect(linkModel.update).toHaveBeenCalledWith(
    { status: 'approved' },
    expect.objectContaining({ where: expect.objectContaining({ resellerId: 1, storeId: [6] }) }),
  );
});
```

- [ ] **Step 2: 실패 확인** — `npx jest reseller-admin.service` → FAIL.

- [ ] **Step 3: 서비스 구현**

```typescript
async pending() {
  const resellers = await this.resellerModel.findAll({
    where: { status: 'pending_review' }, order: [['createdAt', 'DESC']],
  });
  const ids = resellers.map((r) => r.id);
  const docs = await this.docModel.findAll({ where: { resellerId: ids } });
  const links = await this.sequelize.query<{ reseller_id:number; store_id:number; store_name:string; status:string }>(
    `SELECT l.reseller_id, l.store_id, s.name AS store_name, l.status
       FROM reseller.reseller_tienda_link l JOIN stores s ON s.id=l.store_id
      WHERE l.reseller_id IN (:ids)`,
    { replacements: { ids: ids.length ? ids : [0] }, type: QueryTypes.SELECT },
  );

  return resellers.map((r) => ({
    id: r.id, name: r.name, document: r.document, phone: r.phone, submittedAt: r.createdAt,
    docs: docs.filter((d) => d.resellerId === r.id).map((d) => ({ docType: d.docType, fileName: d.fileName })),
    stores: links.filter((l) => l.reseller_id === r.id)
      .map((l) => ({ storeId: l.store_id, storeName: l.store_name, status: l.status })),
  }));
}

async approve(id: number, dto: { storeIds: number[] }, superadminId: number) {
  const reseller = await this.resellerModel.findByPk(id);
  if (!reseller) throw new NotFoundException({ code: 'RESELLER_NOT_FOUND' });
  await reseller.update({ status: 'approved', isActive: true, reviewedBy: superadminId, reviewedAt: new Date() });
  await this.linkModel.update(
    { status: 'approved' },
    { where: { resellerId: id, storeId: dto.storeIds } },
  );

  return { ok: true };
}

async reject(id: number, reason: string, superadminId: number) {
  const reseller = await this.resellerModel.findByPk(id);
  if (!reseller) throw new NotFoundException({ code: 'RESELLER_NOT_FOUND' });
  await reseller.update({ status: 'rejected', reviewedBy: superadminId, reviewedAt: new Date(), rejectReason: reason });

  return { ok: true };
}
```

- [ ] **Step 4: 컨트롤러 (superadmin 가드)**

```typescript
@Controller('reseller/admin')
export class ResellerAdminController {
  constructor(private readonly service: ResellerAdminService) {}

  @Get('pending') @Auth(ValidRoles.superadmin)
  pending() { return this.service.pending(); }

  @Patch(':id/approve') @Auth(ValidRoles.superadmin)
  approve(@Param('id') id: string, @Body() dto: { storeIds: number[] }, @GetUser() user: User) {
    return this.service.approve(Number(id), dto, user.id);
  }

  @Patch(':id/reject') @Auth(ValidRoles.superadmin)
  reject(@Param('id') id: string, @Body() dto: { reason: string }, @GetUser() user: User) {
    return this.service.reject(Number(id), dto.reason, user.id);
  }
}
```

`@Auth(ValidRoles.superadmin)`, `@GetUser()` = admin-console 와 동일 import 경로. `reseller.module.ts` 에 컨트롤러/서비스 등록.

- [ ] **Step 5: 통과 확인** — `npx jest reseller-admin.service` → PASS.

- [ ] **Step 6: 운영/로컬 마이그레이션 실제 적용 (배포 게이트)**

운영(5434): `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f -" < api-ventago/migrations/2026-07-17-reseller-onboarding.sql` (**사용자 확인 후**). 로컬(5432): 사용자에게 명령 전달. 양쪽 스키마 대조.

- [ ] **Step 7: 커밋**

```bash
git add api-ventago/src/app/reseller/admin/ api-ventago/src/app/reseller/reseller.module.ts
git commit -m "feat(reseller): superadmin 승인 API — pending/approve/reject"
```

---

## Wave 2 — 웹 승인 콘솔 (ventago-app, superadmin)

### Task 2.1: SWR 훅 + API 서비스

**Files:**
- Create: `ventago-app/src/hooks/api/useResellersPending.ts`

**Interfaces:**
- Produces: `useResellersPending() → { data: PendingReseller[], isLoading, mutate }`; 타입 `PendingReseller { id, name, document, phone, submittedAt, docs:{docType,fileName}[], stores:{storeId,storeName,status}[] }`.

- [ ] **Step 1: 훅 작성**

```typescript
import useSWR from 'swr'
import { apiConnector } from 'src/services/api.service'

export interface PendingReseller {
  id: number
  name: string
  document: string
  phone: string
  submittedAt: string
  docs: { docType: 'dni_photo' | 'residence_cert' | 'selfie'; fileName: string }[]
  stores: { storeId: number; storeName: string; status: string }[]
}

const fetcher = (path: string) => apiConnector.get(path)

export const useResellersPending = () => {
  const { data, isLoading, mutate } = useSWR<PendingReseller[]>('/reseller/admin/pending', fetcher, {
    dedupingInterval: 5 * 60 * 1000,
  })

  return { data: data ?? [], isLoading, mutate }
}
```

- [ ] **Step 2: 커밋**

```bash
git add ventago-app/src/hooks/api/useResellersPending.ts
git commit -m "feat(web): useResellersPending SWR 훅"
```

---

### Task 2.2: 승인 콘솔 페이지 + 서류 프리뷰

**Files:**
- Create: `ventago-app/src/pages/admin/revendedores.tsx`, `ventago-app/src/views/admin/revendedores/RevendedoresView.tsx`, `.../RevendedorReviewDrawer.tsx`

**Interfaces:**
- Consumes: `useResellersPending`, `apiConnector`.
- Produces: superadmin 승인 UI.

- [ ] **Step 1: 페이지 (코드 스플리팅 + superadmin 게이트)**

```tsx
import dynamic from 'next/dynamic'

const RevendedoresView = dynamic(() => import('src/views/admin/revendedores/RevendedoresView'), { ssr: false })

const RevendedoresPage = () => <RevendedoresView />

RevendedoresPage.acl = { action: 'manage', subject: 'admin' }

export default RevendedoresPage
```

- [ ] **Step 2: View — 목록 테이블**

`RevendedoresView.tsx`: `useResellersPending()` → MUI Table (nombre/document/phone/매장수/제출일 + "Revisar" 버튼 → drawer). pageSize ≤ 50. 로딩 스켈레톤.

- [ ] **Step 3: Drawer — 서류 3종 프리뷰 + 승인/거부**

`RevendedorReviewDrawer.tsx`:

```tsx
const API_HOST = process.env.NEXT_PUBLIC_API_HOST // 예: https://newapi.coolsistema.com/api
const imgUrl = (fileName: string) => `${API_HOST}/minio/${fileName}`

// 서류 3종 next/Image 프리뷰 + 매장별 체크박스(승인 대상 storeIds) + 거부사유 TextField
const approve = async () => {
  try {
    await apiConnector.put(`/reseller/admin/${reseller.id}/approve`, { storeIds: checkedStoreIds })
    toast.success('Revendedor aprobado')
    mutate()
    onClose()
  } catch (e: any) {
    setError(e?.message || 'Error al aprobar')
  }
}

const reject = async () => {
  try {
    await apiConnector.put(`/reseller/admin/${reseller.id}/reject`, { reason })
    toast.success('Revendedor rechazado')
    mutate()
    onClose()
  } catch (e: any) {
    setError(e?.message || 'Error al rechazar')
  }
}
```

에러 = 인라인 `<Alert>` + 글로벌 토스트. `newline-before-return`/`lines-around-comment` 준수.

- [ ] **Step 4: ESLint 게이트**

Run: `cd ventago-app && npx next lint --file src/pages/admin/revendedores.tsx --file src/views/admin/revendedores/RevendedoresView.tsx --file src/views/admin/revendedores/RevendedorReviewDrawer.tsx`
Expected: No errors. (eslint-guardian 서브에이전트 병행 점검.)

- [ ] **Step 5: 사이드바 메뉴 추가**

superadmin 메뉴(admin 섹션)에 "Revendedores" 항목 추가 — 기존 admin 메뉴 레지스트리 패턴 따름.

- [ ] **Step 6: 커밋**

```bash
git add ventago-app/src/pages/admin/revendedores.tsx ventago-app/src/views/admin/revendedores/
git commit -m "feat(web): superadmin Revendedores 승인 콘솔 (서류 프리뷰 + 승인/거부/매장권)"
```

---

## Wave 3 — 앱 온보딩 (mobile-sales-app)

### Task 3.1: reseller session/auth 인프라

**Files:**
- Create: `mobile-sales-app/lib/features/revendedor/data/reseller_auth_repository.dart`, `.../providers/reseller_session_provider.dart`, `.../data/reseller_dto.dart`

**Interfaces:**
- Produces: `ResellerSession { token, resellerId, name, stores: List<ResellerStore> }`; `ResellerAuthRepository.login(idAtApp, password)`, `.register(...)`, `.me()`.

- [ ] **Step 1: DTO + repository (Dio + secure storage)**

```dart
class ResellerStore {
  final int storeId; final String storeName;
  const ResellerStore(this.storeId, this.storeName);
  factory ResellerStore.fromJson(Map<String, dynamic> j) =>
      ResellerStore(j['storeId'] as int, j['storeName'] as String);
}

class ResellerAuthRepository {
  final Dio _dio; final FlutterSecureStorage _storage;
  ResellerAuthRepository(this._dio, this._storage);

  Future<String> login(String idAtApp, String password) async {
    final r = await _dio.post('/reseller/auth/login',
        data: {'emailOrDocument': idAtApp, 'password': password});
    final token = r.data['token'] as String;
    await _storage.write(key: 'reseller_token', value: token);

    return token;
  }

  Future<void> register({
    required String name, required String phone, required String document,
    required String password, required List<int> storeIds,
    required XFile dniPhoto, required XFile residenceCert, required XFile selfie,
  }) async {
    final form = FormData.fromMap({
      'name': name, 'phone': phone, 'document': document, 'password': password,
      'storeIds': storeIds,
      'dniPhoto': await MultipartFile.fromFile(dniPhoto.path),
      'residenceCert': await MultipartFile.fromFile(residenceCert.path),
      'selfie': await MultipartFile.fromFile(selfie.path),
    });
    await _dio.post('/reseller/auth/register', data: form);
  }

  Future<Map<String, dynamic>> me() async {
    final r = await _dio.get('/reseller/auth/me');

    return r.data as Map<String, dynamic>;
  }
}
```

- [ ] **Step 2: session provider (Riverpod)** — 토큰 로드/로그인/로그아웃 + `me()` 로 stores 채움. Dio 인터셉터가 `reseller_token` 있으면 `Authorization: Bearer` 주입(vendedor 토큰과 분리 키).

- [ ] **Step 3: flutter analyze** — `cd mobile-sales-app && flutter analyze lib/features/revendedor` → clean.

- [ ] **Step 4: 커밋**

```bash
git add mobile-sales-app/lib/features/revendedor/data/ mobile-sales-app/lib/features/revendedor/providers/
git commit -m "feat(app): reseller auth repository + session provider (Dio/secure storage)"
```

---

### Task 3.2: 로그인 진입 + 가입 화면 + 심사중 화면

**Files:**
- Modify: `mobile-sales-app/lib/features/auth/views/login_screen.dart` (진입 버튼)
- Create: `.../revendedor/views/reseller_register_screen.dart`, `.../reseller_pending_screen.dart`
- Modify: `mobile-sales-app/lib/router/app_router.dart`

**Interfaces:**
- Consumes: `ResellerAuthRepository.register`, `image_picker`.
- Produces: 라우트 `/revendedor/register`, `/revendedor/pending`.

- [ ] **Step 1: 로그인 화면 진입 버튼** — "hacer nueva tienda" 옆에 `TextButton("Quiero registrarme como revendedor")` → `context.push('/revendedor/register')`.

- [ ] **Step 2: 가입 화면** — 폼(nombre/teléfono/id(DNI)/암호) + 판매 희망 매장 멀티선택(공개 매장 목록; Task 3.3 API) + 이미지 3종 `image_picker`(카메라/갤러리) 미리보기 + 제출.

```dart
Future<void> _submit() async {
  setState(() => _loading = true);
  try {
    await ref.read(resellerAuthRepositoryProvider).register(
      name: _name, phone: _phone, document: _dni, password: _pw,
      storeIds: _selectedStoreIds,
      dniPhoto: _dniPhoto!, residenceCert: _residence!, selfie: _selfie!,
    );
    if (mounted) context.go('/revendedor/pending');
  } on DioException catch (e) {
    setState(() => _error = e.response?.data?['message'] ?? 'Error al registrarse');
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}
```

- [ ] **Step 3: 심사중 화면** — "Tu solicitud está en revisión. Te avisaremos." + 로그인 복귀 버튼.

- [ ] **Step 4: 라우터 등록 + flutter analyze clean.**

- [ ] **Step 5: 커밋**

```bash
git add mobile-sales-app/lib/features/auth/views/login_screen.dart mobile-sales-app/lib/features/revendedor/views/ mobile-sales-app/lib/router/app_router.dart
git commit -m "feat(app): revendedor 가입 진입/폼(서류3종)/심사중 화면"
```

---

### Task 3.3: 공개 매장 목록 (가입 매장 선택 소스)

**Files:**
- 확인: 기존 공개 매장 엔드포인트 재사용 가능?(`marketplace/public-*`). 없으면 Create: `api-ventago/src/app/reseller/auth/` 에 `GET /reseller/public/stores` (공개, 최소 `{id,name}[]`).
- App: 가입 화면 매장 선택 위젯이 이 API 소비.

- [ ] **Step 1: 기존 공개 매장 API 조사** — `grep -rnE "public.*stores|@Public|stores.*public" api-ventago/src/app/marketplace`. 재사용 가능하면 그걸 사용(신규 불필요).

- [ ] **Step 2: (필요 시) 최소 공개 엔드포인트 추가** — ACTIVE 매장만 `{id,name}` 반환. 인증 없음.

- [ ] **Step 3: 앱 매장 선택 위젯 연결 + analyze clean.**

- [ ] **Step 4: 커밋**

```bash
git commit -am "feat(reseller): 가입용 공개 매장 목록 + 앱 선택 위젯"
```

---

## Wave 4 — 앱 읽기 MVP (mobile-sales-app)

### Task 4.1: revendedor_home — 지역 추천 + GPS

**Files:**
- Modify: `mobile-sales-app/lib/features/revendedor/views/revendedor_home.dart`
- Create: `.../data/reseller_catalog_repository.dart`

**Interfaces:**
- Consumes: `GET /reseller/recommendations`, `POST /reseller/detect-province`.
- Produces: `ResellerCatalogRepository.recommendations()`, `.detectProvince(lat,lng)`, `.catalog(...)`, `.canonicalCategories()`.

- [ ] **Step 1: repository 메서드**

```dart
Future<List<RecoProduct>> recommendations() async {
  final r = await _dio.get('/reseller/recommendations');

  return (r.data as List).map((e) => RecoProduct.fromJson(e)).toList();
}

Future<int?> detectProvince(double lat, double lng) async {
  final r = await _dio.post('/reseller/detect-province', data: {'lat': lat, 'lng': lng});

  return r.data['provinceId'] as int?;
}
```

- [ ] **Step 2: home UI** — 스텁 대체. 상단 GPS 지역감지(위치 권한 → detectProvince, 거부 시 수동 provincia) + 추천제품 리스트(카드 탭 → catalog 상세). 로딩/빈 상태 처리.

- [ ] **Step 3: flutter analyze clean + 위젯 테스트(추천 리스트 렌더).**

- [ ] **Step 4: 커밋**

```bash
git add mobile-sales-app/lib/features/revendedor/views/revendedor_home.dart mobile-sales-app/lib/features/revendedor/data/reseller_catalog_repository.dart
git commit -m "feat(app): revendedor_home 지역추천 + GPS 지역감지"
```

---

### Task 4.2: store_selector — 승인매장 선택

**Files:**
- Modify: `mobile-sales-app/lib/features/revendedor/views/store_selector_screen.dart`

**Interfaces:**
- Consumes: `resellerSessionProvider.stores` (`/reseller/auth/me`).

- [ ] **Step 1: 스텁 대체** — `resellerSessionProvider` 의 stores 리스트 → 매장 카드/칩 선택(전체/개별). 선택 매장 = catalog 필터 상태.

- [ ] **Step 2: analyze clean + 커밋**

```bash
git commit -am "feat(app): revendedor store selector — 승인매장 목록"
```

---

### Task 4.3: catalog — 검색-리스트 + 카테고리 필터

**Files:**
- Create: `mobile-sales-app/lib/features/revendedor/views/reseller_catalog_screen.dart`
- Modify: `.../data/reseller_catalog_repository.dart` (catalog/categories)

**Interfaces:**
- Consumes: `GET /reseller/catalog?search=&canonicalCategoryId=&storeId=&page=`, `GET /reseller/canonical-categories`.

- [ ] **Step 1: repository catalog/categories 메서드**

```dart
Future<CatalogPage> catalog({String? search, int? canonicalCategoryId, int? storeId, int page = 1}) async {
  final r = await _dio.get('/reseller/catalog', queryParameters: {
    if (search != null) 'search': search,
    if (canonicalCategoryId != null) 'canonicalCategoryId': canonicalCategoryId,
    if (storeId != null) 'storeId': storeId,
    'page': page,
  });

  return CatalogPage.fromJson(r.data);
}
```

- [ ] **Step 2: catalog 화면** — 검색바(디바운스) + canonical category 칩 필터 + 상품 리스트(name/sku/price/storeName/inStock) + 무한스크롤 페이지네이션(D-14, QR 아님).

- [ ] **Step 3: analyze clean + 위젯 테스트(검색 결과 렌더/빈 상태).**

- [ ] **Step 4: 라우터 `/revendedor/catalog` 등록 + home/store_selector 에서 진입.**

- [ ] **Step 5: 커밋**

```bash
git add mobile-sales-app/lib/features/revendedor/views/reseller_catalog_screen.dart mobile-sales-app/lib/features/revendedor/data/reseller_catalog_repository.dart mobile-sales-app/lib/router/app_router.dart
git commit -m "feat(app): revendedor 카탈로그 검색-리스트 + 카테고리 필터"
```

---

## Self-Review (spec 대조)

- **spec §3.1 마이그레이션** → Task 1.1 ✓
- **§3.2 register/login게이트/me/catalog/approve/reject** → Task 1.3(login) 1.4(register) 1.5(me) 1.6(catalog) 1.7(approve/reject) ✓
- **§3.1 reseller_documents 모델** → Task 1.2 ✓
- **§4 웹 승인 콘솔** → Task 2.1, 2.2 ✓
- **§5.1 앱 온보딩(진입/폼/심사중)** → Task 3.2, 매장선택 3.3 ✓
- **§5.2 읽기 MVP(home/selector/catalog)** → Task 4.1, 4.2, 4.3 ✓
- **§5.3 라우팅(reseller session)** → Task 3.1 ✓
- **§7 에러(RESELLER_NOT_APPROVED/409/부분승인/재제출/MinIO롤백/위치거부)** → 1.3/1.4/1.7/3.2/4.1 ✓
- **§8 테스트** → 각 백엔드 Task jest + 앱 analyze/위젯테스트 ✓
- **§9 마이그레이션 5432+5434 동시** → Task 1.1 + 1.7 Step 6 ✓
- **§D-B7 vendedor 무변경** → reseller realm 분리, `/mobile/*` 미수정 ✓

**Placeholder scan:** 미해결 지점 = Task 1.6(catalog 현재 status 필터 여부 코드 확인 후 보강), Task 3.3(공개 매장 API 재사용 조사) — 둘 다 "조사 후 분기" 액션으로 명시(placeholder 아님).

**Type consistency:** `stores:{storeId,storeName}` (BE me / 앱 ResellerStore / 웹 훅) 일치. `docType` enum 3값 BE/앱/웹 동일. `storeIds:number[]` register/approve 동일.

## 미해결 (실행 중 확인)
- reseller-catalog 반환이 `{items:[...]}` 인지 배열인지 — Task 1.6 에서 실제 확인 후 앱 `CatalogPage.fromJson` 정합.
- 공개 매장 목록: 기존 marketplace 공개 API 재사용 우선(Task 3.3 Step 1).
