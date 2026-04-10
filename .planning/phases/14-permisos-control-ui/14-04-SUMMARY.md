---
phase: 14-permisos-control-ui
plan: "04"
subsystem: frontend-acl
tags: [permissions, acl, casl, navigation, user-override, crud-actions]
dependency_graph:
  requires: [14-03]
  provides: [user-permissions-drawer-crud, 401-page, system-wide-acl-abilities, nav-permission-hiding]
  affects: [ventago-app/src/pages/**, ventago-app/src/views/users/components/, ventago-app/src/navigation/]
tech_stack:
  added: []
  patterns: [CASL ability.can per-subject, page.acl static property, nav action/subject guard]
key_files:
  created: []
  modified:
    - ventago-app/src/views/users/components/UserPermissionsDrawer.tsx
    - ventago-app/src/pages/401.tsx
    - ventago-app/src/layouts/components/acl/CanViewNavLink.tsx
    - ventago-app/src/navigation/vertical/index.ts
    - ventago-app/src/pages/productos/index.tsx
    - "ventago-app/src/pages/[47 authenticated pages total — all with .acl = { action: 'read', subject: slug }]"
decisions:
  - "perfil/index.tsx has no .acl — intentional, all authenticated users must access profile"
  - "CanViewNavLink: if navLink.action/subject absent, show by default (backward compat for non-CASL menus)"
  - "UserPermissionsDrawer: userActionMap stores full ActionRecord per fn, not just overrides — simpler merge logic"
  - "401.tsx uses router.push('/') via onClick not Link href — matches UI-SPEC exactly"
metrics:
  duration: "~45min"
  completed: "2026-04-09"
  tasks: 2
  files: 60
---

# Phase 14 Plan 04: UserPermissionsDrawer CRUD + 401 Page + System-wide ACL Summary

One-liner: CRUD-action user permission override drawer with amber diff display + system-wide CASL page guards and nav hiding via granular action/subject per page.

## Tasks Completed

### Task 1: UserPermissionsDrawer CRUD 확장 + override 표시 + 리셋
**Commit:** `424ccbf`

Complete rewrite of `UserPermissionsDrawer.tsx`:
- Replaced checkbox tree with `CrudActionRow` components (one per function)
- `roleActionMap` loaded from `useRoleFunctions` hook (`roleFunctionData` array with `actions: string[]`)
- `userActionMap` loaded from `GET /user-functions/:userId` — supports both flat `{ functionId, action, allowed }` and nested `{ functionId, actions: [] }` response formats
- `getEffectiveAction()` merges: userActionMap override takes precedence, falls back to roleActionMap
- `variant='user-override'` on CrudActionRow triggers amber border when chip differs from role baseline
- Save: `PUT /user-functions/actions/:userId` with `{ data: [{ functionId, actions: [{ action, allowed }] }] }`
- Reset: `POST /user-functions/reset/:userId` after ConfirmDialog confirmation
  - Title: "Restablecer Permisos"
  - Confirm: "Si, restablecer" (color=error)
  - Cancel: "No, conservar permisos"
- Reset tooltip: "Restablecer permisos del rol"

### Task 2: 401 페이지 + AclGuard + 네비게이션 권한 숨김 + 전체 페이지 aclAbilities
**Commit:** `86838a7`

**401.tsx** — Complete redesign to UI-SPEC:
- `role='alert'` container, `tabler:shield-off` icon 64px, `"Sin Autorización"` h4
- `"No tenés permiso para acceder a esta sección."` body text
- `"Volver al inicio"` CTA button via `router.push('/')`

**AclGuard.tsx** — Already correct from Plan 03:
- `buildAbilityFor(auth.user.roles, aclAbilities.subject, auth.user.permissions)` with permissions arg
- `ability.can(aclAbilities.action, aclAbilities.subject)` check → `<NotAuthorized />` inline render

**acl.ts** — Already correct from Plan 03:
- `defaultACLObj = { action: 'read', subject: 'all' }`

**CanViewNavLink.tsx** — Safety guard added:
- If `navLink.auth === false` → show (existing)
- If `!navLink?.action || !navLink?.subject` → show (backward compat for menus without CASL)
- Otherwise → `ability.can(navLink.action, navLink.subject)`

**navigation/vertical/index.ts** — Added `action: 'read', subject: slug` to:
- Superadmin admin hardcoded items (admin-dashboard, admin-tiendas, admin-registros, admin-auditoria, admin-suscripcion, admin-permisos, admin-generar-token, admin-soporte-remoto)
- Dynamic module children via `mod.slug || mod.name.toLowerCase().replace(/\s+/g, '-')`
- Generar Token auto-append item

**47 page files** — `.acl = { action: 'read', subject: '...' }` added per D-02 mapping:

| Subject | Pages |
|---------|-------|
| `ventas` | nueva-venta, ventas/index, ventas/detalle, cliente-vista, codigo-vista |
| `productos` | productos/index |
| `gastos` | gastos/index |
| `caja` | caja/index, caja/detalle |
| `caja-fuerte` | caja-fuerte/index |
| `control-de-caja` | control-de-caja/index, control-de-caja/detalle |
| `sucursales` | sucursales/index, sucursales/[id]/impresora |
| `usuarios` | usuarios/index |
| `talleres` | talleres/vendors, talleres/pedidos, talleres/dashboard |
| `dashboards` | dashboards/index, dashboards/ventas, dashboards/producto, dashboards/stock, dashboards/fabrica, dashboards/talleres |
| `admin-dashboard` | dashboards/admin |
| `reportes` | reportes/index, reportes-v2, + 14 reportes sub-pages |
| `precios` | precios/index |
| `configuracion` | configuracion/productos, configuracion/ventas |
| `admin-tiendas` | admin/tiendas |
| `admin-registros` | admin/registros |
| `admin-auditoria` | admin/auditoria |
| `admin-suscripcion` | admin/suscripcion |
| `admin-permisos` | admin/permisos |
| `admin-generar-token` | admin/generar-token |
| `admin-soporte-remoto` | admin/soporte-remoto |
| `admin-ventas` | admin/ventas |
| `herramientas` | herramientas/print-agent |
| (none) | perfil/index — intentionally omitted |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] useRoleFunctions hook API mismatch**
- **Found during:** Task 1
- **Issue:** Existing `UserPermissionsDrawer.tsx` destructured `{ functions: roleFunctionIds }` from `useRoleFunctions`, but the hook (updated in Plan 03) returns `{ roleFunctionData }` with a different shape (`{ functionId, actions: string[] }[]`)
- **Fix:** Full rewrite used correct `roleFunctionData` with proper mapping to `ActionRecord`
- **Files modified:** `UserPermissionsDrawer.tsx`
- **Commit:** `424ccbf`

**2. [Rule 1 - Observation] AclGuard and acl.ts already correct**
- Plan 02 action items were already done in prior waves
- `buildAbilityFor(roles, subject, permissions)` — 3-arg form already in place
- `defaultACLObj = { action: 'read', subject: 'all' }` already set
- No changes needed

## Checkpoint: Task 3 — Human Verification Required

**Type:** checkpoint:human-verify  
**What was built:** Phase 14 complete — DB schema (Wave 1) + backend Guards + /me permissions (Wave 2) + CASL refactor + CrudActionRow + RolePermissionsDrawer (Wave 3) + UserPermissionsDrawer CRUD + 401 page + nav hiding + system-wide aclAbilities (this plan)

**How to verify (6 steps):**

1. **Start servers:** `npm run dev` (backend port 5002, frontend port 3000)

2. **superadmin login → role permissions edit:**
   - Usuarios → role card edit icon → RolePermissionsDrawer
   - Confirm C/R/U/D chips per function
   - On `vendedor` role: disable `productos` create/update/delete (keep read only) → save
   - Verify toast "Permisos actualizados correctamente"

3. **vendedor login → read-only check:**
   - Sidebar shows `productos` menu (read permission present)
   - `/productos` page accessible

4. **vendedor gastos blackout test:**
   - superadmin → vendedor role → disable all 4 `gastos` actions → save
   - vendedor login → `gastos` menu hidden from sidebar
   - Navigate to `/gastos` directly → 401 page shows "Sin Autorización" with shield-off icon
   - "Volver al inicio" button → redirects to /

5. **Backend FunctionPermissionGuard check (curl):**
   - vendedor JWT on protected endpoint → 403
   - superadmin JWT on same endpoint → 200

6. **UserPermissionsDrawer override test:**
   - Usuarios → vendedor user → open permissions drawer
   - Confirm CrudActionRow chips + amber border on overridden actions
   - Change override → save → toast
   - Restablecer icon → ConfirmDialog → "Si, restablecer" → role values restored

## Known Stubs

None — all data sources are wired to real API endpoints.

## Threat Flags

None — no new network endpoints or auth paths introduced in this plan. All security mitigations per threat register T-14-09, T-14-10, T-14-11 are implemented.

## Self-Check: PASSED

- commit `424ccbf` found: UserPermissionsDrawer CRUD
- commit `86838a7` found: 401 + nav + system-wide ACL
- UserPermissionsDrawer.tsx: FOUND
- 401.tsx: FOUND
- SUMMARY.md: FOUND
- Sample .acl pages verified: productos, gastos, reportes/ventas
