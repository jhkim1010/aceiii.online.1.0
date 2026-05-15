# 가이드 — Phase 29 Frontend ACL 어휘 마이그레이션

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
관련 결정: TASK-7.4 (Day 8) — 일괄 치환 보류, 점진 마이그레이션 채택

## 결정 요약

기존 frontend 의 ACL `subject` 어휘 (스페인어/영어 혼합 30+ 종) 를
신규 `PermissionKey` enum (영어 dot notation, BE 와 통일) 으로
**즉시 일괄 치환하지 않고 점진 마이그레이션**.

## 배경

**일괄 치환의 위험**:
- 영향 범위: WithAccess 사용처 72개 + acl 정의 82개 = 약 100+ 위치
- 30+ 고유 subject 가 BE 의 18 permission_slug 와 1:1 매핑 안 됨 (1:N 또는 N:1)
- 한 번의 PR 에서 100+ 컴포넌트 수정 → 회귀 위험
- 운영 사용자 0명이라도 신규 사용자 진입 시 즉시 영향

**점진 마이그레이션의 장점**:
- 신규 컴포넌트는 처음부터 신규 어휘 사용 (자연스러운 흐름)
- 기존 컴포넌트는 라우트별로 1주씩 검증 후 교체
- `mapLegacySubject()` helper 가 두 어휘 사이 호환

## 어휘 매핑 표 (legacy → new)

| Legacy subject | 신규 PermissionKey | 비고 |
|---|---|---|
| `'venta'` | `PermissionKey.SALES_CREATE` | 핵심 |
| `'ventas'` | `PermissionKey.SALES_READ` | 조회 화면 |
| `'productos'` | `PermissionKey.PRODUCTS_UPDATE` | 상품 관리 |
| `'precios'` | `PermissionKey.PRODUCTS_PRICE_MASTER` | 가격 |
| `'gastos'` | `PermissionKey.EXPENSES_CREATE` | 비용 |
| `'usuarios'` | `PermissionKey.USERS_MANAGE` | 사용자 관리 |
| `'admin-permisos'` | `PermissionKey.USERS_MANAGE` | 권한 화면 |
| `'configuracion-permisos'` | `PermissionKey.USERS_MANAGE` | 권한 설정 |
| `'admin-auditoria'` | `PermissionKey.AUDIT_READ` | 감사 |
| `'logs-auditoria'` | `PermissionKey.AUDIT_READ` | 감사 로그 |

매핑 안 된 기존 subject 는 그대로 유지 (`mapLegacySubject` 가 원본 반환).

## 신규 컴포넌트 작성 패턴

```tsx
// 권장 — 신규 PermissionKey 직접 사용
import { PermissionKey } from 'src/configs/permission-keys'
import WithAccess from 'src/configs/withAccess'

function MyNewView() {
  return (
    <WithAccess subject={PermissionKey.SALES_REFUND} action='create'>
      <RefundButton />
    </WithAccess>
  )
}

// 페이지 ACL 정의
MyNewPage.acl = {
  action: 'create',
  subject: PermissionKey.SALES_REFUND,
}
```

## 기존 컴포넌트 마이그레이션 패턴

```tsx
// Before (legacy)
import WithAccess from 'src/configs/withAccess'
;<WithAccess subject='venta' action='create'>...</WithAccess>

// After (new) — 한 줄만 변경
import { PermissionKey } from 'src/configs/permission-keys'
;<WithAccess subject={PermissionKey.SALES_CREATE} action='create'>...</WithAccess>

// 또는 fallback 헬퍼 (legacy / new 어느쪽이든 받음)
import { unifiedSubject } from 'src/configs/permission-keys'
;<WithAccess subject={unifiedSubject('venta')} action='create'>...</WithAccess>
```

## 마이그레이션 일정 (권장)

### Sprint 2 Day 8 — 기반 구축 (완료)
- [x] BE: `GET /api/permissions/permissions/keys` 엔드포인트
- [x] Generator: `npm run gen:permissions`
- [x] Helper: `PermissionKey` enum + `mapLegacySubject` + `unifiedSubject`
- [x] 신규 권한 페이지 (Day 6-7) — 신규 어휘 사용 가능 (현재는 'configuracion-permisos' legacy)

### Sprint 2 Day 9-10 — 우선 영역 마이그레이션
- [ ] 신규 컴포넌트: 무조건 PermissionKey 사용
- [ ] 권한 페이지 (Day 6-7) 의 'configuracion-permisos' → `PermissionKey.USERS_MANAGE` 로 변경

### Phase 30 (별도 SPEC) — 점진 일괄 마이그레이션
주별 1-2 라우트씩 마이그레이션:
1. **주 1**: 매장 운영 핵심 (ventas, nueva-venta, productos)
2. **주 2**: 재고·금전 (caja, caja-fuerte, precios)
3. **주 3**: 회계·생산 (gastos, talleres)
4. **주 4**: 관리·설정 (usuarios, configuracion)
5. **주 5**: 검증 — `mapLegacySubject` 적중률 확인 후 helper 자체 deprecate

각 마이그레이션 후 검증:
- `npm run lint && npm run build`
- 권한 페이지에서 매장의 모든 role 로 로그인 → 메뉴/버튼 접근성 확인
- audit_logs 의 deny 로그 추적

## 빌드 시 자동 갱신

`package.json` 의 `prebuild` 훅에 추가 권장 (사용자 결정):

```json
"scripts": {
  "prebuild": "npm run gen:permissions",
  "build": "next build"
}
```

단점: build 시 BE 가 떠있어야 함 → CI 에서는 BE 도 같이 띄우거나 placeholder 파일을 commit.

**현 상태**: `permissions.gen.ts` 가 placeholder 로 commit 되어 있어서 BE 없이도 build 가능.
실제 운영 적용 직전에 한 번 `npm run gen:permissions` 실행으로 갱신.

## 사용 예 (권한 페이지 자체)

Day 6-7 의 `pages/configuracion/permisos/index.tsx` 의 acl 을 신규 어휘로 변경:

```tsx
// Before
PermissionsPage.acl = {
  action: 'manage',
  subject: 'configuracion-permisos',
}

// After
import { PermissionKey } from 'src/configs/permission-keys'
PermissionsPage.acl = {
  action: 'manage',
  subject: PermissionKey.USERS_MANAGE,
}
```

(이 변경은 후속 task 로 분리 — 신규 어휘 적용은 안전한 시점에)
