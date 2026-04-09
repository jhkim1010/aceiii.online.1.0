# Phase 14: Permisos Control UI — Research

**Researched:** 2026-04-09
**Domain:** Full-stack permissions system — CASL granular enforcement, NestJS Guards, DB schema extension, React UI
**Confidence:** HIGH (codebase verified directly)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Full stack 적용 — 관리 UI + 프론트엔드 CASL granular enforcement + 백엔드 API 엔드포인트별 Guard
- **D-02:** 현재 CASL의 `can('manage', 'all')` → 실제 Function+Action 기반 granular 체크로 변경
- **D-03:** 권한 관리 UI 접근 3단계:
  - superadmin: 전체 시스템 권한 관리 (모든 매장, 모든 역할)
  - admin: 자기 매장(store) 내 역할/유저 권한만 관리
  - gerente: 자기 지점(branch) 소속 유저 권한 조회/수정만 가능
- **D-04:** 권한 없는 기능 접근 시: 사이드바 메뉴 숨김 + URL 직접 접근 시 401 Not Authorized 페이지 표시
- **D-05:** Function 단위 + CRUD Action 분리:
  - 기존: Apps → Modules → Functions (ON/OFF)
  - 변경: Apps → Modules → Functions → Actions (create/read/update/delete)
  - 각 Function에 대해 CRUD 액션별 개별 허용/차단 가능

### Claude's Discretion
- 기존 UI(RoleCards, RolePermissionsDrawer, UserPermissionsDrawer) 개선/통합 방식
- DB 스키마 변경 방식 (RoleFunction/UserFunction에 action 컬럼 추가 vs 별도 테이블)
- 백엔드 Guard 구현 패턴 (데코레이터 기반, 미들웨어 등)
- CASL ability 빌딩 로직 리팩토링 방식

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 14 adds CRUD-action granularity to the existing Apps→Modules→Functions permission tree. The current system already has `RoleFunction` (role-to-function mapping) and `UserFunction` (per-user overrides with `allowed: boolean`) tables and working UI drawers. The core change is adding 4 CRUD action dimensions (create/read/update/delete) to these existing ON/OFF flags.

The frontend CASL system currently grants `can('manage', 'all')` to every logged-in user — this must be replaced with ability rules built from the user's actual Function+Action permissions returned by `/me`. The backend `@Auth()` decorator pattern already works well; a new `@FunctionGuard()` decorator following the same `applyDecorators` pattern is the natural extension.

The largest complexity is the DB schema change and migration. Two viable approaches exist: (A) add an `actions` JSON/array column to existing tables, or (B) introduce separate `role_function_actions` and `user_function_actions` tables. The analysis below explains why approach B is recommended.

**Primary recommendation:** Use separate action junction tables (B), extend the `/me` response to include Function+Action maps, and rebuild CASL `buildAbilityFor()` from that map. Extend existing drawer UIs by replacing `Checkbox` with the new `CrudActionRow` component as specified in the UI-SPEC.

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 14 |
|-----------|-------------------|
| Sequelize `underscored: true` — DB snake_case, model camelCase | All new columns/tables use snake_case in DB (`role_function_actions`, `action_create`) |
| `newline-before-return` ESLint rule | Every `return` in new TS/TSX must have blank line before it |
| `lines-around-comment` ESLint rule | Every `//` comment must have blank line above it |
| `no-unused-vars` ESLint rule | All imports in new files must be used |
| MUI `Chip` does not support `tonal` variant | Use `variant="filled"` or `variant="outlined"` for CrudActionRow chips |
| `apiConnector.remove()` not `.delete()` | Any new frontend DELETE calls use `.remove()` |
| Sequelize pool — avoid waste | New Guard queries should use lightweight `findOne`, not full includes |
| 주석은 한국어, 함수/변수명은 영어 | Comments in Korean, all identifiers in English |

---

## Standard Stack

### Core (already installed, no new installs needed)

| Library | Version | Purpose | Source |
|---------|---------|---------|--------|
| `@casl/ability` | existing | Define and check permissions | [VERIFIED: codebase grep] |
| `@casl/react` | existing | `createContextualCan`, `AbilityContext` | [VERIFIED: Can.tsx] |
| `sequelize-typescript` | existing | ORM for new tables | [VERIFIED: codebase] |
| `@nestjs/common` | existing | Guards, Decorators | [VERIFIED: codebase] |
| `@mui/material` | 5.x existing | UI components | [VERIFIED: CLAUDE.md] |
| `@mui/lab` | existing | `TreeView`, `TreeItem` | [VERIFIED: RolePermissionsDrawer.tsx] |

**Installation:** No new packages required. All dependencies are already in the monorepo.

---

## Architecture Patterns

### DB Schema Decision: Separate Action Tables (Recommended B)

**Option A — Add `actions` column to existing tables:**
```sql
-- role_functions: add actions column
ALTER TABLE role_functions ADD COLUMN actions TEXT[] DEFAULT '{create,read,update,delete}';
-- user_functions: add actions column  
ALTER TABLE user_functions ADD COLUMN actions TEXT[] DEFAULT '{}';
```
Problems: PostgreSQL array in Sequelize requires custom DataType handling; the `allowed: boolean` on `user_functions` semantics conflicts with per-action arrays; querying "does user have create on function X" becomes complex.

**Option B — Separate action join tables (RECOMMENDED):**
```sql
-- role_function_actions: one row per (roleFunction, action)
CREATE TABLE role_function_actions (
  id SERIAL PRIMARY KEY,
  role_function_id INTEGER NOT NULL REFERENCES role_functions(id) ON DELETE CASCADE,
  action VARCHAR(20) NOT NULL CHECK (action IN ('create','read','update','delete')),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(role_function_id, action)
);

-- user_function_actions: one row per (userFunction, action, override)
CREATE TABLE user_function_actions (
  id SERIAL PRIMARY KEY,
  user_function_id INTEGER NOT NULL REFERENCES user_functions(id) ON DELETE CASCADE,
  action VARCHAR(20) NOT NULL CHECK (action IN ('create','read','update','delete')),
  allowed BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_function_id, action)
);
```
Rationale: Clean relational design; each action is individually queryable; cascade deletes from parent; preserves existing `RoleFunction` and `UserFunction` rows (no data loss); Sequelize `HasMany` works naturally.

[VERIFIED: existing models use this junction table pattern]

### Sequelize Models (New)

```typescript
// api-ventago/src/app/role/role-function/role-function-action.model.ts
@Table({ timestamps: true })
export class RoleFunctionAction extends Model {
  @PrimaryKey @AutoIncrement @Column(DataType.INTEGER) id: number;

  @ForeignKey(() => RoleFunction)
  @Column(DataType.INTEGER) roleFunctionId: number;

  @Column(DataType.STRING) action: string; // 'create'|'read'|'update'|'delete'

  @BelongsTo(() => RoleFunction) roleFunction: RoleFunction;
}
```

```typescript
// api-ventago/src/app/users/user-function/user-function-action.model.ts
@Table({ timestamps: true })
export class UserFunctionAction extends Model {
  @PrimaryKey @AutoIncrement @Column(DataType.INTEGER) id: number;

  @ForeignKey(() => UserFunction)
  @Column(DataType.INTEGER) userFunctionId: number;

  @Column(DataType.STRING) action: string;

  @Column({ type: DataType.BOOLEAN, defaultValue: true }) allowed: boolean;

  @BelongsTo(() => UserFunction) userFunction: UserFunction;
}
```

### `/me` Response Extension

The current `/me` endpoint returns `structure` (Apps→Modules→Functions tree filtered by allowed functions). It must also return a flat permission map for CASL:

```typescript
// 추가할 구조 — /me 응답에 permissions 필드 추가
permissions: {
  [functionSlug: string]: {
    create: boolean;
    read: boolean;
    update: boolean;
    delete: boolean;
  }
}

// 예시
permissions: {
  'ventas': { create: true, read: true, update: false, delete: false },
  'productos': { create: false, read: true, update: false, delete: false },
}
```

This map is built in `auth.service.ts` `me()` method: load `RoleFunctionActions` for the user's role, apply `UserFunctionAction` overrides, return flat map keyed by function slug.

[VERIFIED: current me() already loads RoleFunction + UserFunction via UserFunctionService.getEffectiveFunctions()]

### CASL `buildAbilityFor()` Refactor

**Current (broken):**
```typescript
// acl.ts — 현재: 모든 로그인 유저에게 manage:all 부여
if (roles && rolesISEquals) {
  can('manage', 'all')
}
```

**New pattern:**
```typescript
// acl.ts — 변경: permissions 맵으로 granular 권한 빌딩
export const buildAbilityFor = (
  roles: string[],
  subject: string,
  permissions?: Record<string, { create: boolean; read: boolean; update: boolean; delete: boolean }>
): AppAbility => {
  const { can, rules } = new AbilityBuilder(AppAbility);

  // superadmin은 여전히 manage:all
  if (roles.includes('superadmin')) {
    can('manage', 'all');
  } else if (permissions) {
    Object.entries(permissions).forEach(([fnSlug, actions]) => {
      if (actions.create) can('create', fnSlug);
      if (actions.read)   can('read', fnSlug);
      if (actions.update) can('update', fnSlug);
      if (actions.delete) can('delete', fnSlug);
    });
  } else {
    // permissions 없으면 기본 read only
    can('read', subject);
  }

  return new AppAbility(rules, { detectSubjectType: (o: any) => o!.type });
};
```

The `AclGuard.tsx` already calls `buildAbilityFor(auth.user.roles, aclAbilities.subject)` — update signature to also pass `auth.user.permissions`.

### Backend Function Guard Pattern

Following the existing `@Auth()` pattern (which uses `applyDecorators` + `UseGuards`):

```typescript
// api-ventago/src/app/auth/decorators/function-guard.decorator.ts
// 사용법: @FunctionGuard('ventas', 'create')
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

```typescript
// api-ventago/src/app/auth/guards/function-permission.guard.ts
@Injectable()
export class FunctionPermissionGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.get<{functionSlug: string; action: string}>(
      FUNCTION_METADATA_KEY, context.getHandler()
    );

    // 메타데이터 없으면 통과 (Guard 미적용 엔드포인트)
    if (!required) return true;

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    // superadmin은 항상 통과
    if (user?.roles?.includes('superadmin')) return true;

    // DB에서 실제 권한 조회 (경량 쿼리)
    const hasPermission = await checkUserFunctionAction(
      user.id, user.storeId, required.functionSlug, required.action
    );

    if (!hasPermission) throw new ForbiddenException('Sin permisos para esta acción');

    return true;
  }
}
```

[VERIFIED: SessionGuard pattern in session/guards/session.guard.ts used as reference]

### Navigation Menu Hiding

Current navigation in `useNavigation()` (vertical/index.ts) already builds menus from `user.structure`. The structure is already filtered in `/me` to only include functions the user can access.

For CRUD-granular hiding: the navigation items currently show/hide at Module level based on whether any functions in that module are accessible. With actions added, the same structure filtering is sufficient — if a user has only `read` on `ventas`, the `ventas` menu item appears (structure still includes it), but the create/edit buttons within the page check CASL ability directly.

For the `CanViewNavLink` / `CanViewNavGroup` components: these check `ability.can(navLink.action, navLink.subject)`. Nav items need to set `action: 'read'` and `subject: functionSlug` to use the new granular ability.

[VERIFIED: CanViewNavLink.tsx line 25: `ability.can(navLink?.action, navLink?.subject)`]

### Page-Level ACL Guard

Each page's `getDefaultProps` exports:
```typescript
export const getDefaultProps = () => ({
  aclAbilities: { action: 'read', subject: 'ventas' }  // functionSlug
})
```

`AclGuard.tsx` checks `ability.can(aclAbilities.action, aclAbilities.subject)`. Currently all pages use `manage:all` or similar. Each page needs its `aclAbilities` updated to reference the correct function slug and action.

### Gerente Scope Enforcement

Gerente sees only users in their `branchId`. Backend endpoints for user permission editing need to check:
```typescript
// gerente는 자기 branch 소속 유저만 수정 가능
if (user.roles.includes('gerente') && targetUser.branchId !== user.branchId) {
  throw new ForbiddenException('Solo podés gestionar usuarios de tu sucursal');
}
```

The `Users` model has `branchId`. [VERIFIED: auth.service.ts line 339: `branchId: user?.branchId || null`]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Permission checking in components | Custom `hasPermission()` function | CASL `ability.can(action, subject)` via `useContext(AbilityContext)` | Already wired in AclGuard, CanViewNavLink |
| Cascading checkbox state (indeterminate) | Custom recursion | Existing `isAppIndeterminate`, `isModIndeterminate` in RolePermissionsDrawer | Already implemented, tested |
| Tree UI | Custom nested lists | `@mui/lab TreeView + TreeItem` | Already used in both drawers |
| Toast notifications | Custom alerts | `react-hot-toast` (already imported in UserPermissionsDrawer) | Consistent with existing pattern |
| Confirmation dialogs | Custom modal | `ConfirmDialog` at `src/components/forms/ConfirmDialog.tsx` | Specified in UI-SPEC |
| Bulk permission save | Custom diff logic | Extend existing `bulkUpdateUserFunctions` service method | Already handles add/remove/clean semantics |

---

## Current State of Existing Code

### What Already Works (DO NOT REPLACE)

| Component | Current State | Phase 14 Change |
|-----------|--------------|-----------------|
| `RolePermissionsDrawer` | Function ON/OFF via Checkbox | Replace single Checkbox per Function with `CrudActionRow` (4 chips) |
| `UserPermissionsDrawer` | Function ON/OFF with role baseline | Replace Checkbox with `CrudActionRow` + override indicator |
| `useRoleFunctions(roleId)` | Returns `number[]` of functionIds | Extend to return `{functionId, actions: string[]}[]` |
| `useFunctionsStructure()` | Returns full Apps→Modules→Functions tree | No change (tree structure unchanged) |
| `UserFunctionService.bulkUpdateUserFunctions` | Handles add/remove/clean by functionId | Extend to accept per-action data |
| `RoleFunctionService.updateFunctionsForRole` | Replace all functionIds for role | Extend to handle action-level data |
| `/me` endpoint | Returns `structure` filtered by allowed functions | Add `permissions` map (functionSlug → CRUD booleans) |

### What Must Be Replaced (CASL Core)

| File | Current (Wrong) | Target |
|------|-----------------|--------|
| `src/configs/acl.ts` `buildAbilityFor()` | `can('manage', 'all')` for all logged-in users | Build from `user.permissions` map |
| `AclGuard.tsx` | Calls `buildAbilityFor(roles, subject)` | Call `buildAbilityFor(roles, subject, user.permissions)` |
| Each page's `aclAbilities` export | `{ action: 'manage', subject: 'all' }` | `{ action: 'read', subject: '{functionSlug}' }` |

---

## Common Pitfalls

### Pitfall 1: RoleFunction deletion on updateFunctionsForRole
**What goes wrong:** `RoleFunctionService.updateFunctionsForRole` currently does `destroy({ where: { roleId, storeId } })` then recreates. If `RoleFunctionAction` records cascade from `RoleFunction`, this is safe. But if actions are stored directly on `RoleFunction` rows via a JSON column, the destroy wipes them.
**Why it happens:** Current service uses delete-then-insert pattern for simplicity.
**How to avoid:** With separate action tables + `ON DELETE CASCADE`, the cascade handles cleanup. Verify migration creates FK with CASCADE before writing service logic.
**Warning signs:** Saving role permissions loses action data — actions revert to empty.

### Pitfall 2: CASL ability rebuilt on every render
**What goes wrong:** `AclGuard.tsx` calls `buildAbilityFor()` on every render inside the component body (not in `useEffect` or `useMemo`). Adding `permissions` as a parameter won't cause new issues, but the ability must not change reference unnecessarily or it triggers re-renders in all `Can` consumers.
**How to avoid:** Keep `buildAbilityFor` pure and stable — ability is rebuilt only when `auth.user` changes (already gated by `if (auth.user && !ability)`). The `AbilityContext.Provider value={ability}` pattern is fine.

### Pitfall 3: Gerente sees all users via UserFunction endpoint
**What goes wrong:** `UserFunctionController` `/user-functions/:userId` has `@Auth()` with no role restriction — any authenticated user can query/update any user's functions.
**How to avoid:** Add scope check in controller: gerente can only modify users in same `branchId`. Admin can only modify users in same `storeId`. Superadmin unrestricted.

### Pitfall 4: `user.structure` vs `user.permissions` timing
**What goes wrong:** `/me` is cached in `AuthContext`. If `permissions` is added to the `/me` response but the frontend TypeScript `AuthValuesType` type isn't updated, TypeScript errors block the build.
**How to avoid:** Update `src/context/types.ts` (or wherever `AuthValuesType` is defined) to include `permissions?: Record<string, {...}>` before implementing CASL changes.

### Pitfall 5: ESLint `newline-before-return` in new TSX
**What goes wrong:** Every `return` statement in new React components must have a blank line directly before it — this is enforced as a build error.
**How to avoid:** Always add blank line before `return` in all new files.

### Pitfall 6: Superadmin `manage:all` must be preserved
**What goes wrong:** Replacing `buildAbilityFor` with permissions-map logic breaks superadmin if the special case is not handled first.
**How to avoid:** Check `roles.includes('superadmin')` before checking permissions map. Superadmin bypasses function guards at both frontend and backend.

---

## Code Examples

### CrudActionRow Component Pattern (new component)
```tsx
// Source: UI-SPEC + existing RolePermissionsDrawer pattern [VERIFIED: codebase]
// 컴포넌트: 하나의 Function에 대한 CRUD 액션 토글 행
interface CrudActionRowProps {
  functionId: number;
  actions: { create: boolean; read: boolean; update: boolean; delete: boolean };
  roleActions?: { create: boolean; read: boolean; update: boolean; delete: boolean };
  onChange: (functionId: number, action: string, value: boolean) => void;
  variant?: 'role' | 'user-override';
}

const ACTION_COLORS: Record<string, any> = {
  create: 'success',
  read: 'primary',
  update: 'warning',
  delete: 'error',
};
const ACTION_LABELS: Record<string, string> = {
  create: 'C', read: 'R', update: 'U', delete: 'D',
};
```

### Effective Permissions Query (backend)
```typescript
// auth.service.ts me() 내부 — permissions 맵 빌딩
// [VERIFIED: existing getEffectiveFunctions() pattern]
const buildPermissionsMap = async (userId: number, roleId: number, storeId: number) => {
  const roleFunctions = await RoleFunction.findAll({
    where: { roleId, storeId },
    include: [{ model: RoleFunctionAction }]
  });

  const userFunctions = await UserFunction.findAll({
    where: { userId, storeId },
    include: [{ model: UserFunctionAction }]
  });

  // role baseline → user overrides 적용
  const permMap: Record<string, Record<string, boolean>> = {};

  for (const rf of roleFunctions) {
    const slug = rf.function?.slug;
    if (!slug) continue;
    permMap[slug] = { create: false, read: false, update: false, delete: false };
    for (const rfa of rf.roleFunctionActions || []) {
      permMap[slug][rfa.action] = true;
    }
  }

  for (const uf of userFunctions) {
    const slug = uf.function?.slug;
    if (!slug) continue;
    if (!permMap[slug]) permMap[slug] = { create: false, read: false, update: false, delete: false };
    for (const ufa of uf.userFunctionActions || []) {
      permMap[slug][ufa.action] = ufa.allowed;
    }
  }

  return permMap;
};
```

### NestJS Guard: Functional Permission Check
```typescript
// [VERIFIED: SessionGuard pattern in session/guards/session.guard.ts]
// 경량 쿼리 — pool 낭비 방지를 위해 include 최소화
const hasPermission = async (userId, storeId, fnSlug, action) => {
  const fn = await Functions.findOne({ where: { slug: fnSlug }, attributes: ['id'] });
  if (!fn) return false;

  const userRole = await UserRole.findOne({ where: { userId } });
  if (!userRole) return false;

  // role 기반 권한 확인
  const rf = await RoleFunction.findOne({ where: { roleId: userRole.roleId, functionId: fn.id, storeId } });
  if (!rf) return false;

  const rfa = await RoleFunctionAction.findOne({ where: { roleFunctionId: rf.id, action } });
  const baseAllowed = !!rfa;

  // user override 확인
  const uf = await UserFunction.findOne({ where: { userId, functionId: fn.id, storeId } });
  if (!uf) return baseAllowed;

  const ufa = await UserFunctionAction.findOne({ where: { userFunctionId: uf.id, action } });
  if (!ufa) return baseAllowed;

  return ufa.allowed;
};
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Function ON/OFF binary permission | Function × Action (4 dimensions) | More granular; existing `RoleFunction`/`UserFunction` rows preserved as foreign keys |
| `can('manage', 'all')` CASL | `can(action, functionSlug)` per permission | Pages must update their `aclAbilities` export |
| Role-only permission check (`@Auth()`) | Role + Function guard (`@FunctionGuard()`) | New decorator following existing `applyDecorators` pattern |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Each `Functions` record has a unique `slug` that can serve as CASL subject | Architecture Patterns | If slugs are not unique across stores, CASL subjects would collide — verify with DB query |
| A2 | `UserFunction` records currently have `storeId` populated correctly for existing users | DB Schema | Migration data integrity — if storeId is null, getEffectiveFunctions fails silently |
| A3 | `@mui/lab` TreeView is the version that accepts `TreeItem` as children (v5 lab) | Standard Stack | MUI lab v6 moved TreeView to `@mui/x-tree-view` — current codebase uses lab version [VERIFIED: imports in RolePermissionsDrawer.tsx] |

---

## Open Questions

1. **Default actions when migrating existing RoleFunction rows**
   - What we know: Existing `role_functions` rows record that a role has access to a function (binary)
   - What's unclear: When we add the action tables, should existing rows get all 4 actions (create/read/update/delete) by default, or just `read`?
   - Recommendation: Default to all 4 actions for existing roles — preserves current behavior (which was effectively "manage all" anyway). Admin can restrict afterward.

2. **Gerente's page access to Permisos Management UI**
   - What we know: D-03 says gerente can only view/modify users in their branch
   - What's unclear: Does gerente see the same `/usuarios` page with a filtered view, or a separate page?
   - Recommendation: Same `/usuarios` page, but the `UserPermissionsDrawer` only shows/allows editing for users where `targetUser.branchId === currentUser.branchId`. This is simpler and avoids a new page.

3. **Superadmin permissions map**
   - What we know: Superadmin gets `can('manage', 'all')` — no function-level restrictions
   - What's unclear: Should `/me` still return `permissions` map for superadmin (all true), or empty/null?
   - Recommendation: Return `null` for permissions when superadmin — `buildAbilityFor` handles the `manage:all` case before checking the map.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 14 is a code/DB change with no new external service dependencies. All tools (NestJS, Next.js, Sequelize, PostgreSQL, MUI) are already running.

---

## Validation Architecture

`workflow.nyquist_validation` key is absent from `.planning/config.json` — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected in codebase |
| Config file | None found |
| Quick run command | N/A |
| Full suite command | N/A |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PERM-01 | CRUD actions saved for role functions | manual | Verify via Permisos UI | N/A |
| PERM-02 | User function overrides apply correct CRUD | manual | Verify via UserPermissionsDrawer | N/A |
| PERM-03 | /me returns correct permissions map | manual | POST /auth/me with valid token | N/A |
| PERM-04 | CASL blocks unauthorized page access | manual | Direct URL access to restricted page | N/A |
| PERM-05 | Sidebar hides restricted menu items | manual | Log in as user with limited perms | N/A |

### Wave 0 Gaps

No automated test infrastructure exists in this project. All verification is manual end-to-end.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | handled (JWT + SessionGuard already complete) |
| V3 Session Management | no | handled (Phase 13 complete) |
| V4 Access Control | yes | `FunctionPermissionGuard` — server-side check on every protected endpoint |
| V5 Input Validation | yes | Validate `action` strings are in enum `['create','read','update','delete']` |
| V6 Cryptography | no | not applicable |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Client-side CASL bypass (modify ability in browser) | Elevation of Privilege | Backend `FunctionPermissionGuard` is authoritative — frontend CASL is UI-only |
| Gerente editing users outside their branch | Elevation of Privilege | Branch scope check in UserFunction controller |
| Horizontal privilege escalation (admin edits other store's roles) | Elevation of Privilege | `storeId` FK on all permission queries — already enforced in `RoleFunctionController` |
| Mass assignment via bulk-update endpoint | Tampering | Validate that target userId belongs to requester's storeId before updating |

---

## Sources

### Primary (HIGH confidence — verified in codebase)
- `api-ventago/src/app/functions/functions.model.ts` — Functions model structure
- `api-ventago/src/app/role/role-function/role-function.model.ts` — RoleFunction model (no actions column)
- `api-ventago/src/app/users/user-function/user-function.model.ts` — UserFunction model (allowed: boolean only)
- `api-ventago/src/app/auth/auth.service.ts` — /me endpoint structure
- `ventago-app/src/configs/acl.ts` — CASL buildAbilityFor current state
- `ventago-app/src/@core/components/auth/AclGuard.tsx` — page guard pattern
- `ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx` — existing drawer pattern
- `ventago-app/src/views/users/components/UserPermissionsDrawer.tsx` — existing user drawer
- `api-ventago/src/app/session/guards/session.guard.ts` — Guard pattern reference
- `api-ventago/src/app/auth/decorators/auth.decorator.ts` — applyDecorators pattern
- `.planning/phases/14-permisos-control-ui/14-UI-SPEC.md` — UI design contract

### Secondary (MEDIUM confidence)
- CASL docs [ASSUMED] — `buildAbilityFor` with dynamic subjects is a documented pattern

---

## Metadata

**Confidence breakdown:**
- DB schema recommendation: HIGH — based on direct model inspection
- CASL refactor pattern: HIGH — existing acl.ts + AclGuard.tsx fully read
- Backend Guard pattern: HIGH — SessionGuard and Auth decorator verified
- Navigation hiding: HIGH — CanViewNavLink and useNavigation verified
- Gerente scope: HIGH — branchId field confirmed in Users model
- Default action migration strategy: MEDIUM — business logic assumption (A1 above)

**Research date:** 2026-04-09
**Valid until:** 2026-05-09 (stable codebase, no fast-moving dependencies)
