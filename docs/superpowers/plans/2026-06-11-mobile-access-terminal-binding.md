# Mobile Access 권한 + 판매원-터미널 바인딩 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 판매원의 모바일 사용 권한을 Phase 33 권한 매트릭스에서 통제하고, 관리자가 판매원을 1개 지점의 지정 터미널(N:1)에 명시 배정하는 기반(권한·DB·배정 API·관리자 UI)을 구축한다.

**Architecture:** `mobile.access`를 Phase 33 functions에 추가(role 단위 토글). `user_branches.mobile_terminal_id` 컬럼으로 유저→터미널 배정 저장(N:1). 배정은 permissions 모듈의 신규 엔드포인트가 처리하며, terminal→box→branch 정합성을 서비스 레이어에서 검증(불일치 403 `TERMINAL_BRANCH_MISMATCH`). 관리자 UI는 Phase 33 `configuracion/permisos/UserDetail.tsx`에 셀렉터 추가.

**Tech Stack:** NestJS 11 + Sequelize(sequelize-typescript, `underscored:true`) + PostgreSQL 10(운영)/15·18(dev). Jest. Next.js 13(Pages) + MUI 5 + SWR + apiConnector. 마이그레이션은 `api-ventago/migrations/*.sql`.

**선행 설계:** [docs/superpowers/specs/2026-06-11-mobile-access-terminal-binding-design.md](../specs/2026-06-11-mobile-access-terminal-binding-design.md)

---

## 범위 (Scope)

이 계획은 **지금 독립적으로 구축·테스트 가능한 기반 슬라이스**만 다룬다. 모바일 런타임 강제(로그인 게이트, 판매 귀속)는 Phase 37 Wave 1(미착수, `mobile_sessions`/`MobileAuthService` 부재)에 얹힌다 — 아래 "Phase 37 Wave 1 인계" 참조.

**이 계획에 포함:**
1. `user_branches.mobile_terminal_id` DDL + 모델 컬럼
2. `mobile.access` function 추가(매트릭스 토글 가능)
3. terminal→branch 정합성 검증 헬퍼
4. 유저-터미널 배정/해제 엔드포인트 (`TERMINAL_BRANCH_MISMATCH` 강제)
5. 지점 터미널 목록 조회(배정 셀렉터용)
6. 관리자 UI 셀렉터 (UserDetail.tsx)
7. 베타 데이터 DML (vendedor role mobile.access ON + 2명 터미널 배정) — 사용자 확인 후

**Phase 37 Wave 1 인계 (이 계획 범위 외, 설계 doc에 매핑):**
- `mobile_sessions.terminal_id/box_id` 컬럼 (MOBILE-A-01)
- 로그인 권한 게이트 `MOBILE_ACCESS_DENIED` + 터미널 게이트 `MOBILE_TERMINAL_NOT_ASSIGNED` (MOBILE-A-04)
- `GET /mobile/me` terminalId/terminalName/boxId (MOBILE-A-06)
- `POST /mobile/sales` 세션 배정 터미널 강제 (MOBILE-B-04)

---

## File Structure

**Backend (api-ventago):**
- Create: `migrations/phase37-user-branches-mobile-terminal.sql` — user_branches 컬럼 DDL
- Create: `migrations/phase37-mobile-access-function.sql` — mobile.access function INSERT
- Create: `migrations/phase37-beta-mobile-access-data.sql` — 베타 role_function ON + 2명 터미널 배정
- Modify: `src/app/permissions/models/user-branch.model.ts` — mobileTerminalId 컬럼
- Modify: `src/app/terminal/terminal.service.ts` — `findByBranch` + `assertTerminalInBranch`
- Modify: `src/app/permissions/permissions.service.ts` — `assignMobileTerminal`
- Modify: `src/app/permissions/permissions.controller.ts` — PUT/DELETE mobile-terminal 엔드포인트
- Modify: `src/app/functions/seed/functions-seed-admin.ts` — mobile.access 콜드스타트 시드
- Test: `src/app/terminal/terminal.service.spec.ts` (확장 또는 신규)
- Test: `src/app/permissions/permissions.service.spec.ts` (확장 또는 신규)

**Frontend (ventago-app):**
- Create: `src/hooks/api/useBranchTerminals.ts` — 지점 터미널 SWR 훅
- Modify: `src/views/configuracion/permisos/UserDetail.tsx` — 모바일 터미널 셀렉터

---

## Task 1: user_branches.mobile_terminal_id DDL + 모델

**Files:**
- Create: `api-ventago/migrations/phase37-user-branches-mobile-terminal.sql`
- Modify: `api-ventago/src/app/permissions/models/user-branch.model.ts`

- [ ] **Step 1: 마이그레이션 SQL 작성 (PG10/PG15 호환, idempotent)**

Create `api-ventago/migrations/phase37-user-branches-mobile-terminal.sql`:

```sql
-- Phase 37 — user_branches 에 모바일 지정 터미널 바인딩 추가 (N:1)
-- PG10/PG15 호환. idempotent (IF NOT EXISTS).
BEGIN;

ALTER TABLE user_branches
  ADD COLUMN IF NOT EXISTS mobile_terminal_id INT NULL
  REFERENCES terminals(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_user_branches_mobile_terminal
  ON user_branches(mobile_terminal_id);

COMMENT ON COLUMN user_branches.mobile_terminal_id IS
  'Phase 37 — 이 유저가 이 지점에서 모바일 판매 시 사용할 지정 터미널 (N:1 공용 가능). NULL=미배정.';

COMMIT;
```

- [ ] **Step 2: dev DB(PG18)에 적용 + 검증**

Run:
```bash
docker exec api_ventago node -e "const {Client}=require('pg');const c=new Client({host:'dbpostgres',user:'coolsistema',password:'Coo1s1stem4Adm1nPg',database:'ventago'});c.connect().then(()=>c.query(\"SELECT column_name FROM information_schema.columns WHERE table_name='user_branches' AND column_name='mobile_terminal_id'\")).then(r=>{console.log(r.rows);c.end();});"
```
(dev가 docker가 아닌 로컬 PG18이면: `psql -d ventago -f api-ventago/migrations/phase37-user-branches-mobile-terminal.sql` 후 `\d user_branches`)
Expected: `mobile_terminal_id` 행 1개 출력.

- [ ] **Step 3: 모델에 컬럼 추가**

In `api-ventago/src/app/permissions/models/user-branch.model.ts`, `reason` 컬럼 선언 뒤에 추가 (snake_case 자동 매핑 `mobile_terminal_id`):

```typescript
  @Column({ type: DataType.INTEGER, allowNull: true })
  mobileTerminalId: number | null;
```

- [ ] **Step 4: 빌드 확인**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json`
Expected: 컴파일 에러 0 (mobileTerminalId 인식).

- [ ] **Step 5: Commit**

```bash
git add api-ventago/migrations/phase37-user-branches-mobile-terminal.sql api-ventago/src/app/permissions/models/user-branch.model.ts
git commit -m "feat(37): user_branches.mobile_terminal_id 컬럼 + 모델 (모바일 터미널 바인딩)"
```

---

## Task 2: mobile.access function 추가

**Files:**
- Create: `api-ventago/migrations/phase37-mobile-access-function.sql`
- Modify: `api-ventago/src/app/functions/seed/functions-seed-admin.ts`

- [ ] **Step 1: 마이그레이션 SQL 작성 (idempotent)**

Create `api-ventago/migrations/phase37-mobile-access-function.sql`:

```sql
-- Phase 37 — mobile.access 권한 함수 추가 (Phase 33 매트릭스 role 단위 토글용)
-- configuracion-ventas 모듈에 배치. idempotent.
BEGIN;

INSERT INTO functions (name, slug, permission_slug, description, module_id, created_at, updated_at)
SELECT 'Acceso movil', 'acceso-movil', 'mobile.access',
       'Permite al usuario iniciar sesion en la app movil de ventas',
       m.id, NOW(), NOW()
FROM modules m
WHERE m.slug = 'configuracion-ventas'
  AND NOT EXISTS (
    SELECT 1 FROM functions f WHERE f.permission_slug = 'mobile.access'
  );

COMMIT;
```

- [ ] **Step 2: dev DB 적용 + 검증**

Run (docker dev 기준; 로컬이면 psql -f):
```bash
docker exec api_ventago node -e "const {Client}=require('pg');const c=new Client({host:'dbpostgres',user:'coolsistema',password:'Coo1s1stem4Adm1nPg',database:'ventago'});c.connect().then(()=>c.query(\"SELECT id, name, permission_slug, module_id FROM functions WHERE permission_slug='mobile.access'\")).then(r=>{console.log(r.rows);c.end();});"
```
Expected: 1 행 (permission_slug='mobile.access').

- [ ] **Step 3: 콜드스타트 시드에 추가 (idempotent findOrCreate)**

In `api-ventago/src/app/functions/seed/functions-seed-admin.ts`, `seedAdminFunctions` 안에서 usuarios 시드 블록 뒤에 추가 (모듈은 configuracion-ventas):

```typescript
  // Phase 37 — mobile.access (모바일 앱 로그인 허용 권한)
  const configVentasModule = await Modules.findOne({
    where: { slug: 'configuracion-ventas' },
  });

  if (configVentasModule) {
    await Functions.findOrCreate({
      where: { permissionSlug: 'mobile.access' },
      defaults: {
        name: 'Acceso movil',
        slug: 'acceso-movil',
        permissionSlug: 'mobile.access',
        description: 'Permite al usuario iniciar sesion en la app movil de ventas',
        moduleId: configVentasModule.id,
      },
    });
  }
```

- [ ] **Step 4: 빌드 확인**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json`
Expected: 컴파일 에러 0.

- [ ] **Step 5: Commit**

```bash
git add api-ventago/migrations/phase37-mobile-access-function.sql api-ventago/src/app/functions/seed/functions-seed-admin.ts
git commit -m "feat(37): mobile.access 권한 함수 추가 (매트릭스 토글 + 콜드스타트 시드)"
```

---

## Task 3: terminal→branch 정합성 검증 (terminal.service)

**Files:**
- Modify: `api-ventago/src/app/terminal/terminal.service.ts`
- Test: `api-ventago/src/app/terminal/terminal.service.spec.ts`

- [ ] **Step 1: 실패하는 테스트 작성**

Create/extend `api-ventago/src/app/terminal/terminal.service.spec.ts`:

```typescript
import { TerminalService } from './terminal.service';

describe('TerminalService — assertTerminalInBranch (Phase 37)', () => {
  const makeService = (terminalRow: any) => {
    const terminalModel = {
      findOne: jest.fn().mockResolvedValue(terminalRow),
    } as any;

    return new TerminalService(terminalModel);
  };

  it('터미널의 box.branch_id 가 인자 branchId 와 일치하면 terminal 반환', async () => {
    const svc = makeService({ id: 33, boxId: 12, box: { branchId: 5 } });
    const result = await svc.assertTerminalInBranch(33, 5);
    expect(result.id).toBe(33);
  });

  it('불일치하면 TERMINAL_BRANCH_MISMATCH 예외', async () => {
    const svc = makeService({ id: 33, boxId: 12, box: { branchId: 99 } });
    await expect(svc.assertTerminalInBranch(33, 5)).rejects.toThrow('TERMINAL_BRANCH_MISMATCH');
  });

  it('터미널 없으면 TERMINAL_NOT_FOUND 예외', async () => {
    const svc = makeService(null);
    await expect(svc.assertTerminalInBranch(404, 5)).rejects.toThrow('TERMINAL_NOT_FOUND');
  });
});
```

> 참고: `new TerminalService(terminalModel)` 인자는 실제 생성자 시그니처에 맞춘다. terminal.service.ts 생성자가 `@InjectModel(Terminal) terminalModel` 단일 인자인지 Step 3 전에 파일을 열어 확인하고, 다르면 mock 인자를 맞춘다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest terminal.service.spec --silent`
Expected: FAIL — `assertTerminalInBranch is not a function`.

- [ ] **Step 3: 구현 추가**

In `api-ventago/src/app/terminal/terminal.service.ts`, 클래스 메서드로 추가 (`Box` import는 이미 존재):

```typescript
  // Phase 37 — 터미널이 지정 지점에 속하는지 검증 (terminal → box → branch).
  // terminals 에 직접 branch_id 가 없어 box.branchId 경유로 확인.
  async assertTerminalInBranch(terminalId: number, branchId: number): Promise<Terminal> {
    const terminal = await this.terminalModel.findOne({
      where: { id: terminalId },
      include: [{ model: Box, as: 'box' }],
    });

    if (!terminal) {
      throw new Error('TERMINAL_NOT_FOUND');
    }

    if (!terminal.box || terminal.box.branchId !== branchId) {
      throw new Error('TERMINAL_BRANCH_MISMATCH');
    }

    return terminal;
  }

  // Phase 37 — 지점에 속한 터미널 목록 (배정 셀렉터용)
  async findByBranch(branchId: number): Promise<Terminal[]> {
    return this.terminalModel.findAll({
      include: [{ model: Box, as: 'box', where: { branchId }, required: true }],
    });
  }
```

> `terminal.box.branchId` 속성명은 Box 모델의 컬럼 매핑(`branch_id` → `branchId`)을 따른다. Step 3 전 `box.model.ts`에서 속성명 확인.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest terminal.service.spec --silent`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add api-ventago/src/app/terminal/terminal.service.ts api-ventago/src/app/terminal/terminal.service.spec.ts
git commit -m "feat(37): terminal assertTerminalInBranch + findByBranch (정합성 검증)"
```

---

## Task 4: 유저-터미널 배정 서비스 + 엔드포인트

**Files:**
- Modify: `api-ventago/src/app/permissions/permissions.service.ts`
- Modify: `api-ventago/src/app/permissions/permissions.controller.ts`
- Modify: `api-ventago/src/app/permissions/permissions.module.ts` (TerminalModule import 필요 시)
- Test: `api-ventago/src/app/permissions/permissions.service.spec.ts`

- [ ] **Step 1: 실패하는 테스트 작성**

Extend/create `api-ventago/src/app/permissions/permissions.service.spec.ts` — `assignMobileTerminal`:

```typescript
describe('PermissionsService — assignMobileTerminal (Phase 37)', () => {
  const makeService = (opts: { userBranch: any; assertImpl?: any }) => {
    const userBranchModel = {
      findOne: jest.fn().mockResolvedValue(opts.userBranch),
    } as any;
    const terminalService = {
      assertTerminalInBranch: opts.assertImpl
        ?? jest.fn().mockResolvedValue({ id: 33 }),
    } as any;
    const cacheService = { invalidateUser: jest.fn().mockResolvedValue(undefined) } as any;

    // 생성자 인자 순서는 permissions.service.ts 실제 시그니처에 맞춘다.
    const svc: any = Object.create(PermissionsService.prototype);
    svc.userBranchModel = userBranchModel;
    svc.terminalService = terminalService;
    svc.cacheService = cacheService;
    svc.logger = { error: jest.fn(), log: jest.fn() };

    return { svc, userBranchModel, terminalService, cacheService };
  };

  it('정상 배정 → user_branch.mobile_terminal_id 저장 + cache invalidate', async () => {
    const save = jest.fn().mockResolvedValue(undefined);
    const userBranch = { userId: 19, branchId: 5, mobileTerminalId: null, save };
    const { svc, terminalService, cacheService } = makeService({ userBranch });

    await svc.assignMobileTerminal({ userId: 19, branchId: 5, terminalId: 33 });

    expect(terminalService.assertTerminalInBranch).toHaveBeenCalledWith(33, 5);
    expect(userBranch.mobileTerminalId).toBe(33);
    expect(save).toHaveBeenCalled();
    expect(cacheService.invalidateUser).toHaveBeenCalledWith(19);
  });

  it('user_branch 없으면 USER_BRANCH_NOT_FOUND', async () => {
    const { svc } = makeService({ userBranch: null });
    await expect(
      svc.assignMobileTerminal({ userId: 19, branchId: 5, terminalId: 33 }),
    ).rejects.toThrow('USER_BRANCH_NOT_FOUND');
  });

  it('terminalId=null 이면 배정 해제 (assert 미호출)', async () => {
    const save = jest.fn().mockResolvedValue(undefined);
    const userBranch = { userId: 19, branchId: 5, mobileTerminalId: 33, save };
    const { svc, terminalService } = makeService({ userBranch });

    await svc.assignMobileTerminal({ userId: 19, branchId: 5, terminalId: null });

    expect(terminalService.assertTerminalInBranch).not.toHaveBeenCalled();
    expect(userBranch.mobileTerminalId).toBeNull();
    expect(save).toHaveBeenCalled();
  });
});
```

> 생성자 주입 방식이 위 `Object.create` 우회와 다르면, permissions.service.ts 생성자에 맞춰 정상 `new PermissionsService(...)` 로 교체한다. 핵심은 동작 검증(assert 호출/저장/cache invalidate)이다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest permissions.service.spec --silent`
Expected: FAIL — `assignMobileTerminal is not a function`.

- [ ] **Step 3: 서비스 구현**

In `api-ventago/src/app/permissions/permissions.service.ts`:

(a) 생성자에 TerminalService 주입 (기존 주입 목록 끝에 추가):
```typescript
    private readonly terminalService: TerminalService,
```
상단 import 추가:
```typescript
import { TerminalService } from '../terminal/terminal.service';
```

(b) `revokeUserBranch` 메서드 뒤에 추가:
```typescript
  /**
   * Phase 37 — 유저의 특정 지점 모바일 터미널 배정/해제.
   * terminalId=null 이면 해제. 불일치 시 TERMINAL_BRANCH_MISMATCH (terminalService).
   */
  async assignMobileTerminal(params: {
    userId: number;
    branchId: number;
    terminalId: number | null;
  }): Promise<void> {
    const userBranch = await this.userBranchModel.findOne({
      where: { userId: params.userId, branchId: params.branchId },
    });

    if (!userBranch) {
      throw new Error('USER_BRANCH_NOT_FOUND');
    }

    if (params.terminalId !== null) {
      await this.terminalService.assertTerminalInBranch(params.terminalId, params.branchId);
    }

    userBranch.mobileTerminalId = params.terminalId;
    await userBranch.save();

    await this.cacheService.invalidateUser(params.userId);
  }
```

(c) `permissions.module.ts`에 TerminalModule import (없으면). TerminalModule이 TerminalService를 export하는지 확인 후, 안 하면 export 추가:
```typescript
import { TerminalModule } from '../terminal/terminal.module';
// @Module imports 배열에 TerminalModule 추가
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest permissions.service.spec --silent`
Expected: PASS (3 tests).

- [ ] **Step 5: 컨트롤러 엔드포인트 추가**

In `api-ventago/src/app/permissions/permissions.controller.ts`, `assignUserBranch` (PUT users/:userId/branches/:branchId) 뒤에 추가:

```typescript
  // Phase 37 — 모바일 지정 터미널 배정/해제
  @Put('users/:userId/branches/:branchId/mobile-terminal')
  async assignMobileTerminal(
    @Param('userId') userId: string,
    @Param('branchId') branchId: string,
    @Body() body: { terminalId: number | null },
  ) {
    try {
      await this.permissionsService.assignMobileTerminal({
        userId: Number(userId),
        branchId: Number(branchId),
        terminalId: body.terminalId ?? null,
      });

      return { success: true };
    } catch (error) {
      this.logger.error('assignMobileTerminal 실패:', error);
      const code = error instanceof Error ? error.message : 'UNKNOWN';
      const status =
        code === 'TERMINAL_BRANCH_MISMATCH' ? 403
        : code === 'USER_BRANCH_NOT_FOUND' || code === 'TERMINAL_NOT_FOUND' ? 404
        : 400;

      throw new HttpException({ code, message: code }, status);
    }
  }
```

상단에 `HttpException`이 import 안 되어 있으면 추가:
```typescript
import { HttpException } from '@nestjs/common';
```

- [ ] **Step 6: 지점 터미널 목록 엔드포인트 (셀렉터용)**

In `api-ventago/src/app/terminal/terminal.controller.ts`, 기존 패턴(`@Get('by-box/:boxId')`) 뒤에 추가:

```typescript
  @Get('by-branch/:branchId')
  async findByBranch(@Param('branchId') branchId: string) {
    return this.terminalService.findByBranch(Number(branchId));
  }
```

- [ ] **Step 7: 빌드 + 전체 권한/터미널 테스트**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npx jest permissions terminal --silent`
Expected: 컴파일 에러 0, 모든 테스트 PASS.

- [ ] **Step 8: Commit**

```bash
git add api-ventago/src/app/permissions/ api-ventago/src/app/terminal/terminal.controller.ts
git commit -m "feat(37): 유저-터미널 배정 서비스/엔드포인트 + by-branch 조회 (TERMINAL_BRANCH_MISMATCH 강제)"
```

---

## Task 5: 프론트 — 지점 터미널 SWR 훅

**Files:**
- Create: `ventago-app/src/hooks/api/useBranchTerminals.ts`

- [ ] **Step 1: SWR 훅 작성 (5분 dedup, 기존 훅 패턴 따름)**

먼저 기존 훅 1개를 열어 패턴 확인:
Run: `cat ventago-app/src/hooks/api/useBranchByStore.ts`

그 패턴에 맞춰 Create `ventago-app/src/hooks/api/useBranchTerminals.ts` (apiConnector + useSWR, branchId 없으면 fetch 안 함):

```typescript
import useSWR from 'swr'

import { apiConnector } from 'src/services/api.service'

const fetcher = (path: string) => apiConnector.get(path)

export const useBranchTerminals = (branchId: number | null) => {
  const { data, error, isLoading, mutate } = useSWR(
    branchId ? `/terminal/by-branch/${branchId}` : null,
    fetcher,
    { dedupingInterval: 300000 }
  )

  return {
    terminals: data ?? [],
    isLoading,
    isError: !!error,
    mutate
  }
}
```

> `apiConnector.get` 반환 형태(응답 .data 언랩 여부)는 `useBranchByStore.ts`와 동일하게 맞춘다. SWR key 패턴/`dedupingInterval`도 기존 훅과 일치시킨다.

- [ ] **Step 2: 타입 체크**

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 에러 0.

- [ ] **Step 3: Commit**

```bash
git add ventago-app/src/hooks/api/useBranchTerminals.ts
git commit -m "feat(37): useBranchTerminals SWR 훅 (지점 터미널 목록)"
```

---

## Task 6: 프론트 — UserDetail 모바일 터미널 셀렉터

**Files:**
- Modify: `ventago-app/src/views/configuracion/permisos/UserDetail.tsx`

- [ ] **Step 1: 현재 컴포넌트 구조 파악**

Run: `sed -n '1,80p' ventago-app/src/views/configuracion/permisos/UserDetail.tsx`
확인 사항: user/branch 정보를 어떻게 받는지(props/SWR), 지점(branchId) 접근 경로, MUI import 방식, 저장 핸들러 패턴.

- [ ] **Step 2: 셀렉터 + 저장 핸들러 추가**

UserDetail.tsx에 다음을 통합 (실제 변수명은 Step 1에서 확인한 컴포넌트의 user/branch 변수에 맞춤). ESLint 규칙 준수: 주석 위 빈 줄, return 위 빈 줄.

import 추가 (파일 상단 import 블록):
```typescript
import { MenuItem, Select, FormControl, InputLabel } from '@mui/material'

import { useBranchTerminals } from 'src/hooks/api/useBranchTerminals'
import { apiConnector } from 'src/services/api.service'
```

컴포넌트 본문 (user의 현재 branchId를 `branchId`, userId를 `userId`로 가정 — Step 1에서 실제 변수에 매핑):
```typescript
  const { terminals } = useBranchTerminals(branchId ?? null)

  const handleMobileTerminalChange = async (terminalId: number | null) => {
    try {
      await apiConnector.put(
        `/permissions/users/${userId}/branches/${branchId}/mobile-terminal`,
        { terminalId }
      )
    } catch (error) {
      // 에러는 인라인 Alert + 글로벌 토스트로 노출 (프로젝트 에러 가시성 규약)
      console.error('mobile terminal 배정 실패', error)
      throw error
    }
  }
```

렌더(권한/지점 섹션 근처에 배치). `currentMobileTerminalId`는 user_branch 응답의 `mobileTerminalId`에서 가져온다 (해당 응답에 필드가 없으면 Step 1에서 사용한 user-detail SWR 응답에 백엔드가 mobileTerminalId를 포함하는지 확인하고, 없으면 GET users/:id 응답 매핑에 추가 — 아래 Step 3):
```tsx
        <FormControl fullWidth size="small" sx={{ mt: 2 }}>
          <InputLabel id="mobile-terminal-label">Terminal movil</InputLabel>
          <Select
            labelId="mobile-terminal-label"
            label="Terminal movil"
            value={currentMobileTerminalId ?? ''}
            onChange={e =>
              handleMobileTerminalChange(
                e.target.value === '' ? null : Number(e.target.value)
              )
            }
          >
            <MenuItem value="">Sin asignar</MenuItem>
            {terminals.map((t: any) => (
              <MenuItem key={t.id} value={t.id}>
                {t.name}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
```

- [ ] **Step 3: user-detail 응답에 mobileTerminalId 노출 확인**

`GET /permissions/users/:id` (permissions.controller.ts `getUserDetail` / permissions.service.ts) 응답의 branches 항목에 `mobileTerminalId`가 포함되는지 확인.
Run: `grep -n "mobileTerminalId\|mobile_terminal\|branches" api-ventago/src/app/permissions/permissions.service.ts | head`
없으면 user-detail 빌더에서 userBranch row의 `mobileTerminalId`를 응답 DTO에 추가 (그 항목 1줄 추가 후 별도 commit).

- [ ] **Step 4: ESLint 점검 (빌드 차단 방지)**

Run: `cd ventago-app && npx eslint src/views/configuracion/permisos/UserDetail.tsx src/hooks/api/useBranchTerminals.ts`
Expected: 에러 0 (newline-before-return / lines-around-comment / no-unused-vars 위반 없음).

> 이 시점에 eslint-guardian subagent로 추가 점검 권장 (프로젝트 규약).

- [ ] **Step 5: 타입 체크 + Commit**

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 에러 0.

```bash
git add ventago-app/src/views/configuracion/permisos/UserDetail.tsx
git commit -m "feat(37): UserDetail 모바일 터미널 셀렉터 (지점 터미널 배정 UI)"
```

---

## Task 7: 베타 데이터 DML (사용자 확인 후)

**Files:**
- Create: `api-ventago/migrations/phase37-beta-mobile-access-data.sql`

> ⚠️ DML — CLAUDE.md 규칙상 운영 적용 전 **SQL 내용 + 예상 영향 row 수**를 사용자에게 보이고 동의받는다. dev에서 먼저 검증.

- [ ] **Step 1: 베타 DML SQL 작성 (idempotent)**

Create `api-ventago/migrations/phase37-beta-mobile-access-data.sql`:

```sql
-- Phase 37 — coolsistema(store_id=6) vendedor role(21) 에 mobile.access ON.
-- role_functions + role_function_actions 구조는 Phase 33 패턴 사용.
-- 터미널 배정(mobile_terminal_id)은 지점-터미널 확인 후 별도 UPDATE 로 수행(아래 주석 참조).
BEGIN;

-- 1) mobile.access function 을 vendedor role(21) 에 부여 (role_functions)
INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
SELECT 21, f.id, 6, NOW(), NOW()
FROM functions f
WHERE f.permission_slug = 'mobile.access'
  AND NOT EXISTS (
    SELECT 1 FROM role_functions rf
    WHERE rf.role_id = 21 AND rf.function_id = f.id AND rf.store_id = 6
  );

COMMIT;

-- 2) 터미널 배정은 지점별 터미널 id 확인 후 수동 UPDATE (사용자 확인):
--    SELECT ub.user_id, ub.branch_id, t.id AS terminal_id, t.name
--    FROM user_branches ub
--    JOIN user_roles ur ON ur.user_id = ub.user_id AND ur.role_id = ub.role_id
--    JOIN roles r ON r.id = ur.role_id AND r.slug = 'vendedor'
--    JOIN boxes b ON b.branch_id = ub.branch_id
--    JOIN terminals t ON t.box_id = b.id
--    WHERE ub.user_id IN (<vendedor user ids>);
--  결과 확인 후:
--    UPDATE user_branches SET mobile_terminal_id = <terminal_id>
--    WHERE user_id = <uid> AND branch_id = <bid>;
```

- [ ] **Step 2: role_function actions 구조 확인 (Phase 33 정합)**

Run: `grep -n "role_function_actions\|roleFunctionAction\|bulkUpdateRoleFunctionActions" api-ventago/src/app/role/role-function/role-function.service.ts | head`
mobile.access가 매트릭스에 boolean 토글로 표현되려면 role_function_actions 행도 필요한지 확인. 단일 access 권한이면 role_functions 행만으로 충분한지 PermissionResolver 로직으로 판단 후, 필요 시 actions INSERT 추가.

- [ ] **Step 3: dev 적용 + 검증**

dev DB에 적용 후:
```bash
# vendedor role 에 mobile.access 부여 확인
docker exec api_ventago node -e "const {Client}=require('pg');const c=new Client({host:'dbpostgres',user:'coolsistema',password:'Coo1s1stem4Adm1nPg',database:'ventago'});c.connect().then(()=>c.query(\"SELECT rf.role_id, f.permission_slug FROM role_functions rf JOIN functions f ON f.id=rf.function_id WHERE f.permission_slug='mobile.access'\")).then(r=>{console.log(r.rows);c.end();});"
```
Expected: vendedor role 행 출력.

- [ ] **Step 4: Commit (운영 적용은 별도, 사용자 확인 후)**

```bash
git add api-ventago/migrations/phase37-beta-mobile-access-data.sql
git commit -m "feat(37): 베타 mobile.access 부여 DML + 터미널 배정 가이드 (운영 적용 전 확인 필요)"
```

> 운영 적용: Phase 35/36 운영 잠금 해제 후 (SPEC L185). 세 마이그레이션 순서 = user-branches-mobile-terminal → mobile-access-function → beta-mobile-access-data. 각 단계 사용자 확인.

---

## Self-Review (작성자 체크 완료)

- **Spec coverage:** 설계 doc의 데이터모델(a/b)=Task1·2, 정합성 규칙=Task3, 배정 엔드포인트=Task4, 관리자 UI=Task5·6, 베타 DML=Task7. 로그인 게이트·판매 귀속·mobile_sessions 컬럼은 "Phase 37 Wave 1 인계"로 명시 분리(범위 외).
- **Placeholder scan:** 각 코드 스텝에 실제 코드 포함. "실제 변수명 확인" 지시는 기존 코드 의존 부분으로, 확인 명령(Run)을 동반함.
- **Type consistency:** `mobileTerminalId`(모델/서비스/응답), `assertTerminalInBranch(terminalId, branchId)`, `findByBranch(branchId)`, 엔드포인트 `PUT /permissions/users/:userId/branches/:branchId/mobile-terminal` + `GET /terminal/by-branch/:branchId` — 전 태스크 일관.

---

## 알려진 검증 의존 항목 (실행 중 확인)

각 태스크의 `>` 주석에 명시 — 실제 코드 구조에 맞춰 미세 조정:
- terminal.service / permissions.service 생성자 시그니처 (mock/주입)
- Box 모델 속성명(`branchId`)
- permissions getUserDetail 응답의 branches DTO에 mobileTerminalId 포함 여부
- role_function_actions 필요 여부(단일 access 토글)
- apiConnector.get 응답 언랩 패턴(기존 SWR 훅과 일치)
