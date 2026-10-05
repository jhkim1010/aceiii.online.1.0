# Phase 99: 메뉴 — 구조 일관성 — Pattern Map

**Mapped:** 2026-10-05
**Files analyzed:** 21 (신규 8 · 수정 13)
**Analogs found:** 21 / 21 (전부 기존 코드 안에 직접 대조 가능한 선례가 있음 — 이 Phase 는 새 메커니즘을 만들지 않는다)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `ventago-app/src/pages/configuracion/index.tsx` (MODIFY) | hub-page / route | request-response | 자기 자신 — 기존 `HUB_TABS` 항목 패턴 | exact |
| `ventago-app/src/views/configuracion/conexiones/DispositivosView.tsx` (NEW) | component | request-response(딥링크만, API 없음) | `src/views/relojes/RelojesCard.tsx` (자립 카드) | role-match |
| `ventago-app/src/views/soporte/AccesoParaSoporteView.tsx` (NEW) | component(합성) | request-response | `configuracion/index.tsx` 탭 콘텐츠 Grid 영역 + 기존 `TokenSoporteView`/`AccesoVentagoView` 임베드 | exact |
| `ventago-app/src/navigation/menuRegistry.ts` (MODIFY) | config/registry | transform | 자기 자신 — `exclude` 배열(278행), `RegistryNavItem` 인터페이스(16-26행) | exact |
| `ventago-app/src/navigation/vertical/index.ts` (MODIFY) | provider/renderer | transform | 자기 자신 — `visibleByRole`(66-67행), `vis()`/`tieneModulo()`(76-90행) | exact |
| `ventago-app/src/pages/admin/permisos/index.tsx` (MODIFY) | route-guard | request-response | `ventago-app/src/pages/admin/vto.tsx` (`WithAccess superadminOnly`) | exact |
| `ventago-app/src/views/reports-v2/registry.ts` (MODIFY) | config/registry(데이터) | CRUD(read)/transform | 자기 자신 — `enviado`/`stock-vistas`/`season-turnover` 엔트리, `ReportEntry` 인터페이스 | exact |
| `ventago-app/src/views/tesoreria/tesoreriaTabs.ts` (MODIFY) | utility(순수 로직) | transform | 자기 자신 — `has('/caja')` 재사용 패턴(Cheques 탭) | exact |
| `ventago-app/src/pages/tesoreria/index.tsx` (MODIFY) | page/component | request-response | 자기 자신 — `activeKey === 'xxx' && <Component/>` 조건 렌더 | exact |
| `ventago-app/src/views/talleres/components/constants.ts` (MODIFY) | config | transform | 자기 자신 — `TALLERES_TABS` 배열 항목 | exact |
| `ventago-app/src/pages/talleres/defect-codes/index.tsx` (MODIFY) | route-guard | request-response | `ventago-app/src/pages/admin/revendedores.tsx` (`WithAccess allowedApps`) | role-match |
| `ventago-app/src/views/carpetas-compartidas/SharedFoldersListView.tsx` (MODIFY) | component | request-response(에러 상태 분기) | `ventago-app/src/views/relojes/RelojesCard.tsx` (403 vs 빈 목록 분기) | role-match |
| `ventago-app/src/views/carpetas-compartidas/admin/AdminFoldersView.tsx` (MODIFY) | component | request-response(에러 상태 분기) | 위와 동일 + 자기 자신의 기존 `error`/`Alert` 블록 | role-match |
| `ventago-app/src/__tests__/hub-tab-contract.spec.ts` (NEW) | test | transform(정적 분석) | `ventago-app/src/__tests__/menu-paths-exist.spec.ts` | exact |
| `ventago-app/src/__tests__/route-reachability.spec.ts` (NEW) | test | transform(정적 분석) | `ventago-app/src/__tests__/sidebar-module-contract.spec.ts` | exact |
| `ventago-app/src/__tests__/registry-legacyhref.spec.ts` (NEW) | test | transform | `ventago-app/src/views/reports-v2/registry.ts` 직접 import(순수 `.ts`) | exact |
| `api-ventago/src/app/support-token/support-token.controller.ts` (MODIFY) | controller | request-response | `api-ventago/src/app/agente/agente.controller.ts` (`AccesoVentagoController`) | exact |
| `api-ventago/src/app/functions/functions.controller.ts` (MODIFY) | controller | CRUD | `api-ventago/src/app/prices/types/priceType.controller.ts` (메서드 레벨 `@Auth` 오버라이드로 같은 결함을 이미 고친 전례) | exact |
| `api-ventago/src/app/auth/crud-inherited-routes.spec.ts` (MODIFY — 항목 추가) | test | request-response(가드 단위) | 자기 자신(기존 16개 케이스 패턴) | exact |
| `api-ventago/src/app/support-token/support-token.controller.spec.ts` (NEW) | test | request-response(가드 단위) | `api-ventago/src/app/auth/crud-inherited-routes.spec.ts` (같은 `UserRoleGuard` 단위시험 기법) | exact |
| `api-ventago/migrations/2026-10-0X-phase99-seed-reporte-asistencia.sql` (NEW) | migration | batch | `api-ventago/migrations/2026-09-29-c-permiso-reporte-precios-fuera-de-lista.sql` | exact |

---

## Pattern Assignments

### 1. `ventago-app/src/pages/configuracion/index.tsx` (hub-page, request-response)

**Analog:** 자기 자신 — 이 파일은 이미 완성된 게이트·탭·딥링크 메커니즘을 갖고 있다. 이 Phase 는 **새 메커니즘을 추가하지 않고 배열/타입만 확장**한다.

**타입 확장 (기존 54행 부근)**:
```ts
type HubTab = {
  key: string
  label: string
  icon: string
  section: 'General' | 'Operación' | 'Avanzado'   // → 'Conexiones' | 'Soporte' 추가 (UI-SPEC D-02/D-01)
  requiredApps?: string[]
  requiredModules?: string[]
  requiredPrivileged?: boolean   // 이미 존재 — datos-tienda·qr 가 쓰는 것과 동일한 필드, 새로 만들지 않는다
  render: () => JSX.Element
}
```

**신규 탭 추가 패턴 (기존 `relojes`/`qr` 항목과 동일한 1-liner 스타일)**:
```ts
// (configuracion/index.tsx:95-96 — 기존, 참고용)
{ key: 'token-soporte', label: 'Token de soporte', icon: 'tabler:lifebuoy', section: 'Avanzado', requiredApps: ['admin'], render: () => <TokenSoporteView embedded /> },
{ key: 'generar-token', label: 'Acceso de Ventago', icon: 'tabler:key', section: 'Avanzado', requiredApps: ['admin'], render: () => <AccesoVentagoView /> },
```
위 두 줄 + `relojes` 키를 **제거**하고 아래로 교체(UI-SPEC "공통 — HUB_TABS 섹션 구조 변경" 참조):
```ts
{ key: 'dispositivos', label: 'Dispositivos', icon: 'tabler:devices', section: 'Conexiones', requiredApps: ['admin'], render: () => <DispositivosView /> },
{ key: 'acceso-soporte', label: 'Acceso para soporte', icon: 'tabler:lifebuoy', section: 'Soporte', requiredApps: ['admin'], requiredPrivileged: true, render: () => <AccesoParaSoporteView /> },
```
`requiredPrivileged: true` 는 **반드시** 붙인다 — `token-soporte`/`generar-token` 은 지금 없지만, 서버 쪽 수정(§17)이 `support-token generate/usage` 를 `@Auth(admin)` 으로 좁히면 허브 게이트가 서버 게이트와 같은 집합이어야 한다(연구 §9-1 Pitfall 2).

**`canSeeTab`/`SECTIONS` 는 수정하지 않는다** — 이미 `requiredPrivileged`·`requiredApps`·`requiredModules` 전부 처리한다(기존 100-112행). `SECTIONS` 배열에 `'Conexiones', 'Soporte'` 를 `GENERAL → OPERACIÓN` 사이/뒤에 추가하는 것만 바뀐다:
```ts
const SECTIONS: HubTab['section'][] = ['General', 'Operación', 'Conexiones', 'Soporte', 'Avanzado']
```

**딥링크 — `?tab=dispositivos` 는 이미 동작한다**(기존 `queryTab` 로직, 수정 불필요). UI-SPEC 의 "Abrir Vendedores →" 버튼은 `/configuracion?tab=ventas` 로 가는 평범한 Next `<Link>`/`router.push` 면 된다 — 새 라우팅 코드 불필요.

---

### 2. `ventago-app/src/views/configuracion/conexiones/DispositivosView.tsx` (NEW, component)

**Analog:** `ventago-app/src/views/relojes/RelojesCard.tsx` (자립 카드 — fetch/상태를 자기 안에 둔다)

이 신규 컴포넌트는 **3-카드 그리드**(UI-SPEC §1)이고, 카드 1·2 는 자체 API 호출이 없다(딥링크 버튼뿐). 카드 3 만 기존 `RelojesCard` 를 그대로 import 해 임베드한다 — **재구현하지 않는다**.

```tsx
// 구조 패턴 (UI-SPEC §1 표 그대로)
import { Grid, Card, CardContent, Typography, Button, Stack } from '@mui/material'
import { Icon } from '@iconify/react'
import { useRouter } from 'next/router'
import dynamic from 'next/dynamic'

const RelojesCard = dynamic(() => import('src/views/relojes/RelojesCard'), { ssr: false })

const DispositivosView = () => {
  const router = useRouter()
  return (
    <Stack spacing={1}>
      <Typography variant='body2' color='text.secondary'>
        Cada canal de venta tiene su propio token de dispositivo. Elegí dónde conectarlo.
      </Typography>
      <Grid container spacing={3}>
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Icon icon='tabler:device-mobile' fontSize={28} />
              <Typography variant='h6'>App de vendedores</Typography>
              <Typography variant='body2' color='text.secondary'>
                Cada vendedor necesita un token de dispositivo para vender desde el celular.
              </Typography>
              <Button onClick={() => router.push('/configuracion?tab=ventas')}>Abrir Vendedores →</Button>
            </CardContent>
          </Card>
        </Grid>
        {/* 카드 2: 동일 구조, router.push('/ventas-online') */}
        <Grid item xs={12} md={4}><RelojesCard /></Grid>
      </Grid>
    </Stack>
  )
}
export default DispositivosView
```

★ 기존 `VendedorDispositivosModal.tsx`(`src/views/config/ventas/sellers/list/components/`)·`DispositivosModal.tsx`(`src/views/ventas-online/components/`)는 **그대로 둔다** — 이 신규 카드는 그 화면으로 보내는 딥링크일 뿐, 재작성이 아니다(연구 D-02 결론).

---

### 3. `ventago-app/src/views/soporte/AccesoParaSoporteView.tsx` (NEW, component 합성)

**Analog:** `configuracion/index.tsx` 탭 콘텐츠 Grid 구조 + 기존 `TokenSoporteView embedded`/`AccesoVentagoView` 임베드 호출(둘 다 configuracion/index.tsx 26·31행에서 이미 dynamic import 돼 있음)

```tsx
import { Grid, Divider, Typography, Stack } from '@mui/material'
import dynamic from 'next/dynamic'

const TokenSoporteView = dynamic(() => import('src/views/soporte/TokenSoporteView'), { ssr: false })
const AccesoVentagoView = dynamic(() => import('src/views/acceso-ventago/AccesoVentagoView'), { ssr: false })

const AccesoParaSoporteView = () => (
  <Stack spacing={1}>
    <Typography variant='body2' color='text.secondary'>
      Dos formas de darle acceso temporal a tu tienda. Elegí según quién lo va a usar.
    </Typography>
    <Grid container spacing={3}>
      <Grid item xs={12} md={6}>
        {/* 헤더: "Para el equipo de soporte de CoolSistema · dura 5 minutos · puede ver y modificar los datos de tu tienda." */}
        <TokenSoporteView embedded />
      </Grid>
      <Divider orientation='vertical' flexItem sx={{ display: { xs: 'none', md: 'block' } }} />
      <Grid item xs={12} md={6}>
        {/* 헤더: "Para un agente de Ventago · elegís 30 min o 2 h · acceso acotado a certificado AFIP, cierre de sesión de terminal o importación legacy." */}
        <AccesoVentagoView />
      </Grid>
    </Grid>
  </Stack>
)
export default AccesoParaSoporteView
```

내부 컴포넌트(`TokenSoporteView`, `AccesoVentagoView`)는 **카피·동작 변경 없음** — UI-SPEC §2 가 명시한 대로 탭 바깥 레이아웃만 이 Phase 범위다.

---

### 4. `ventago-app/src/navigation/menuRegistry.ts` (config/registry, transform)

**Analog:** 자기 자신

**D-04 — Dashboard ventas 재노출 (정확히 1줄, 278행)**:
```ts
// 수정 전
exclude: ['/dashboards/ventas', '/configuracion/ventas'],
// 수정 후
exclude: ['/configuracion/ventas'],
```

**D-09-2 — `RegistryNavItem` 에 권한 필터 필드 추가 (16-26행)**:
```ts
export interface RegistryNavItem {
  title?: string
  titleKey?: string
  icon: string
  path?: string
  children?: RegistryNavItem[]
  action?: string   // Phase 65 이후 장식만 — 지우지 않는다(하위 호환)
  subject?: string
  roles?: string[]           // 기존 — 역할 게이트, visibleByRole 이 소비
  requiredModules?: string[]  // ★ 신규 — 모듈 slug 게이트 (Mi suscripción/Biblioteca de fotos)
  requiredFunctions?: string[] // ★ 신규 — 기능 slug 게이트(더 좁음, allowedFunctions 와 동격)
}
```

`Mi suscripción`(261행)·`Biblioteca de fotos`(304행) 수정:
```ts
{ title: 'Mi suscripción', icon: 'tabler:receipt-2', path: '/mi-suscripcion', action: 'read', subject: 'admin', requiredFunctions: ['ver-mi-suscripcion'] },
{ title: 'Biblioteca de fotos', icon: 'tabler:photo', path: '/productos/biblioteca', action: 'read', subject: 'productos', requiredModules: ['productos'] },
```
(정확한 slug 는 실행 단계에서 `/admin/permisos` 카탈로그 대조로 확정 — 연구 §9-2 가 "페이지가 요구하는 모듈/기능"을 이미 특정함: `ver-mi-suscripcion` function, `productos` module)

---

### 5. `ventago-app/src/navigation/vertical/index.ts` (provider/renderer, transform)

**Analog:** 자기 자신 — `visibleByRole`(66-67행)과 `tieneModulo`(76-90행)이 이미 "구조에서 파생한 가시성 판정"의 정확한 선례다.

```ts
// 기존 (66-67행)
const visibleByRole = (item: RegistryNavItem) =>
  !item.roles || (user?.roles || []).some(r => item.roles!.includes(r));

// ★ 확장 — 같은 함수에 모듈/기능 축 추가 (tieneModulo 패턴 재사용)
const userModuleSlugs = (user?.structure || []).flatMap(app => (app.modules || []).map((m: any) => String(m.slug || '')));
const userFunctionSlugs = (user?.structure || []).flatMap(app => (app.modules || []).flatMap((m: any) => (m.functions || []).map((f: any) => String(f.slug || ''))));

const visibleByAccess = (item: RegistryNavItem) => {
  if (!visibleByRole(item)) return false;
  if (item.requiredModules && !item.requiredModules.some(s => userModuleSlugs.includes(s))) return false;
  if (item.requiredFunctions && !item.requiredFunctions.some(s => userFunctionSlugs.includes(s))) return false;
  return true;
};
```
그리고 202·203행·216·217행의 `.filter(visibleByRole)` 호출을 `.filter(visibleByAccess)` 로 교체(두 지점 모두 — `injectStart`/`injectEnd`). `function.slug` 가 실제로 `/me` 응답에 실리는지는 `withAccess.tsx` 의 주석(`allowedFunctions` 섹션)이 이미 "2026-09-24 실측" 으로 확인해 둔 사실이므로 새로 검증할 필요 없음.

---

### 6. `ventago-app/src/pages/admin/permisos/index.tsx` (route-guard, request-response)

**Analog:** `ventago-app/src/pages/admin/vto.tsx` — **superadmin 전용**(매장 admin 제외) 화면에 쓰는 정확한 기존 패턴.

```tsx
// 수정 전
import dynamic from 'next/dynamic'
const PermissionsListView = dynamic(() => import('src/views/admin/permissions/PermissionsListView'), { ssr: false })
const PermissionsPage = () => <PermissionsListView/>
export default PermissionsPage

// 수정 후 — vto.tsx(11행) 패턴 그대로
import WithAccess from 'src/configs/withAccess'
const PermissionsPage = () => (
  <WithAccess superadminOnly>
    <PermissionsListView />
  </WithAccess>
)
```

★★★ **`allowedRoles={['superadmin']}` 을 쓰지 않는다** — `withAccess.tsx` 의 `isPrivileged` 우회가 매장 `admin` 을 먼저 통과시켜 아무것도 못 막는다(연구 §9-5, MEMORY `withaccess-admin-bypasses-all-gates.md`). `superadminOnly` prop 만이 `esOperadorSaaS()` 로 그 우회를 받지 않는다 — `withAccess.tsx` 48-62행에 이미 구현돼 있다.

---

### 7. `ventago-app/src/views/reports-v2/registry.ts` (config/registry, read/transform)

**Analog:** 자기 자신 — `ReportEntry` 인터페이스와 기존 엔트리들.

**D-06-a — legacyHref 3개 수정**. `ReportEntry.legacyHref`(77행)를 선택적으로 바꾼다:
```ts
export interface ReportEntry {
  // ...
  legacyHref?: string   // 수정 전: legacyHref: string — enviado/stock-vistas/season-turnover 는 레거시가 없다
  // ...
}
```
세 엔트리(`enviado` 246행, `stock-vistas` 435행, `season-turnover` 499행)에서 `legacyHref` 줄을 **삭제**(값을 넣지 않음) — `ReportsPreviewPanel.tsx` 가 `bodyComponent` 있으면 그 버튼을 아예 안 그리므로(53행 조건 `!Body` 일 때만), 지금은 죽은 코드지만 미래 대비로 정직하게 고친다.

**D-06-b — `/reportes/asistencia` 신규 엔트리** (기존 `enviado` 엔트리 구조를 그대로 복제):
```ts
{
  slug: 'asistencia',
  title: 'Asistencia y adelantos',
  categories: ['finanzas'],  // 'equipo' 신규 카테고리 추가 여부는 플랜 단계 확정(UI-SPEC §6)
  icon: 'tabler:calendar-check',
  description: 'Asistencia, horas trabajadas y adelantos a vendedores aprobados.',
  paramsSchema: variantB,   // 기존 import 된 스키마 재사용 — 신규 스키마 불필요
  filterSchema: ['sucursal', 'rangeDate'],
  cockpitLayout: { hasKpiStrip: true, hasDetail: false, hasDrawer: false },
  defaultParams: reservadoDefaultParams,  // 또는 asistencia 전용 — 실행 단계 확정
  // bodyComponent 지정하지 않음 — "Ver versión clásica" 버튼으로 기존 화면 연결
  legacyHref: '/reportes/asistencia',
  permissionSlug: 'reporte-asistencia',  // ★ §21 migration 선행 필요
},
```

---

### 8-9. `ventago-app/src/views/tesoreria/tesoreriaTabs.ts` + `ventago-app/src/pages/tesoreria/index.tsx` (A5, Caja fuerte)

**Analog:** 자기 자신 — `Cheques` 탭이 `/caja` 권한을 재사용하는 바로 그 패턴(55-56행).

```ts
// tesoreriaTabs.ts
export type TesoreriaTabKey = 'estado' | 'registros' | 'cheques' | 'gastos' | 'caja-fuerte'
// ...
if (has('/caja')) list.push({ label: 'Caja fuerte', key: 'caja-fuerte' })  // Estado 와 같은 기준 재사용(주석 필수 — "왜 caja 권한을 다시 쓰는지")
```
```tsx
// pages/tesoreria/index.tsx — 기존 dynamic import 블록과 같은 자리에 추가
const CajaFuerteView = dynamic(() => import('src/views/caja-fuerte/...'), { ssr: false })
// ...
{activeKey === 'caja-fuerte' && <CajaFuerteView />}
```
아이콘은 `tabler:building-bank`(UI-SPEC §5 — 기존 Estado/Cheques 의 `tabler:cash` 계열과 중복 없는 값으로 이미 지정됨).

---

### 10-11. `ventago-app/src/views/talleres/components/constants.ts` + `ventago-app/src/pages/talleres/defect-codes/index.tsx` (A6)

**Analog:** 자기 자신(`TALLERES_TABS` 배열 — 39-55행) + `revendedores.tsx`(게이트 패턴)

```ts
// TALLERES_TABS 에 추가 (UI-SPEC §4)
{ value: 'defect-codes', label: 'Códigos de defecto', icon: 'tabler:alert-triangle' },
```

페이지 게이트(현재 전혀 없음, 연구 A6 확정)는 `revendedores.tsx` 패턴을 따르되 **talleres 모듈**로 좁힌다:
```tsx
// pages/talleres/defect-codes/index.tsx
import WithAccess from 'src/configs/withAccess'
const DefectCodesPage = () => (
  <WithAccess allowedApps={['talleres']}>
    <DefectCodesAdminView />
  </WithAccess>
)
```
정확한 `allowedModules` 값(talleres 소속 모듈 slug)은 실행 단계에서 DB 확인 후 확정(이 UI-SPEC/연구는 게이트 "추가 필요"만 못박았지 slug 를 안 줬다).

---

### 12-13. Carpetas compartidas — 503 vs 빈 상태 분기 (D-03)

**Analog:** `ventago-app/src/views/relojes/RelojesCard.tsx` 의 **403 vs 빈 목록 분기**(30-44행) — 이미 이 저장소에 "에러 코드로 상태를 구분"하는 정확한 선례가 있다.

```tsx
// RelojesCard.tsx 패턴 (analog, 그대로 인용)
try {
  const r = await apiConnector.get<WatchDeviceDto[]>('/watch/devices')
  setDevices(Array.isArray(r) ? r : [])
  setNotAdmin(false)
} catch (e: any) {
  if (e?.response?.status === 403) {
    setNotAdmin(true)
    setDevices([])
  }
}
```

**적용 — `SharedFoldersListView.tsx`**(현재 단순 `error` 불리언, 24-27행·40-41행)를 503 전용 분기로 확장:
```tsx
// 수정 전 (기존 24-27행)
{error && <Alert severity='error'>{t('sf_err_load_folders')}</Alert>}
{!isLoading && !error && data && data.length === 0 && <Alert severity='info'>{t('sf_empty_user')}</Alert>}

// 수정 후 — RelojesCard 의 상태코드 분기 기법 적용
const isNotConfigured = (error as any)?.response?.status === 503
// ...
{isNotConfigured && <Alert severity='info'>Carpetas compartidas no está disponible todavía — Tu administrador todavía no activó esta función. Si la necesitás, avisale.</Alert>}
{error && !isNotConfigured && <Alert severity='error'>{t('sf_err_load_folders')}</Alert>}
{!isLoading && !error && data && data.length === 0 && <Alert severity='info'>{t('sf_empty_user')}</Alert>}
```

**적용 — `AdminFoldersView.tsx`**(기존 91-95행, 같은 `error` 패턴) — 동일 분기 + UI-SPEC §3 관리 화면 표의 "Registrar carpeta"(빈 상태) vs "Escribir a soporte"(503, **Reintentar 버튼 금지**) CTA 차이를 반영. 환경변수명(`GOOGLE_SA_KEY_JSON`)은 화면에 노출하지 않는다 — 서버 원문 메시지는 로그용으로만 남긴다(UI-SPEC §3 마지막 문단).

---

### 14. `ventago-app/src/__tests__/hub-tab-contract.spec.ts` (NEW, test)

**Analog:** `ventago-app/src/__tests__/menu-paths-exist.spec.ts` — `.tsx` 를 import 하지 않고 `fs.readFileSync` + 정규식으로 소스 텍스트를 읽는 기법(이 저장소의 유일하게 가능한 방법, `app jest` 는 JSX transform 이 없음).

연구(§D-09 9-4)가 완성된 코드를 이미 제공했다 — 그대로 사용:
```ts
import fs from 'fs'
import path from 'path'
const HUB = path.join(__dirname, '..', 'pages', 'configuracion', 'index.tsx')
const extraerPares = (): Array<[string, string]> => {
  const src = fs.readFileSync(HUB, 'utf8')
  const bloque = src.slice(src.indexOf('HUB_TABS'), src.indexOf('const SECTIONS'))
  const entradas = [...bloque.matchAll(/key:\s*'([^']+)'[\s\S]*?render:\s*\(\)\s*=>\s*<(\w+)/g)]
  return entradas.map(m => [m[1], m[2]])
}
describe('허브 키↔화면 계약', () => {
  it('★ 대조군 — 실제로 여러 쌍을 읽어온다', () => {
    expect(extraerPares().length).toBeGreaterThan(10)
  })
  it('키가 가리키는 컴포넌트가 고정값과 같다', () => {
    expect(Object.fromEntries(extraerPares())).toEqual({
      /* 신규 키 포함 — 'dispositivos': 'DispositivosView', 'acceso-soporte': 'AccesoParaSoporteView', ... */
    })
  })
})
```
(기존 `menu-paths-exist.spec.ts` 서두 주석 — "파일이 있다"와 "사람이 갈 수 있다는 다르다", "못 잡는 것을 알고 쓴다" — 두 문단을 신규 spec 헤더에도 그대로 따를 것, 과장 금지.)

---

### 15. `ventago-app/src/__tests__/route-reachability.spec.ts` (NEW, test)

**Analog:** `ventago-app/src/__tests__/sidebar-module-contract.spec.ts` — `routeExists()`(19-33행) 같은 파일 존재 확인 헬퍼와 `flattenPaths()`(35-36행) 재사용 가능. 이번 시험은 **반대 방향**(페이지 전수 스캔 → 등록 여부 확인)이라 새 `SIN_MENU` 화이트리스트가 필요하다(연구 §9-4 코드 예시 그대로). **대조군 필수**(화이트리스트에서 하나를 지우면 반드시 실패) — MEMORY `control-group-can-pass-too.md`.

---

### 16. `ventago-app/src/__tests__/registry-legacyhref.spec.ts` (NEW, test)

**Analog:** `registry.ts` 자체가 순수 `.ts`(JSX 없음)이므로 **직접 import 가능** — `sidebar-module-contract.spec.ts` 가 `menuRegistry.ts` 를 직접 import 하는 것과 같은 자유도.
```ts
import { REPORTS_BY_SLUG } from 'src/views/reports-v2/registry'
describe('reports-v2 legacyHref 정합', () => {
  it.each(['enviado', 'stock-vistas', 'season-turnover'])('%s 는 존재하지 않는 /reportes/* 를 가리키지 않는다', slug => {
    expect(REPORTS_BY_SLUG[slug].legacyHref).toBeUndefined()
  })
  it('asistencia 가 목록에 있고 permissionSlug 가 맞다', () => {
    expect(REPORTS_BY_SLUG['asistencia']?.permissionSlug).toBe('reporte-asistencia')
  })
})
```

---

### 17. `api-ventago/src/app/support-token/support-token.controller.ts` (controller, request-response)

**Analog:** `api-ventago/src/app/agente/agente.controller.ts` — `AccesoVentagoController.generar`(38행 부근) 가 똑같은 "매장 관리자 전용" 의도를 `@Auth(ValidRoles.admin)` 으로 정확히 구현한 바로 옆 동네 컨트롤러.

```ts
// 수정 전 (support-token.controller.ts:18-23, 32-38)
@Post('generate')
@HttpCode(HttpStatus.OK)
@Auth()
async generate(@GetUser() user: any) { ... }

@Get('usage')
@Auth()
async usage(@GetUser() user: any) { ... }

// 수정 후 — agente.controller.ts 의 @Auth(ValidRoles.admin) 패턴 그대로
import { ValidRoles } from '../auth/interfaces/valid-roles';

@Post('generate')
@HttpCode(HttpStatus.OK)
@Auth(ValidRoles.admin)
async generate(@GetUser() user: any) { ... }

@Get('usage')
@Auth(ValidRoles.admin)
async usage(@GetUser() user: any) { ... }

// validate() 는 손대지 않는다 — 호출자가 CoolSistema 내부 포털(이 저장소 밖)로 추정되며
// 좁히면 외부 연동이 끊길 위험이 있다(연구 §9-3, LOW confidence 항목)
```

---

### 18. `api-ventago/src/app/functions/functions.controller.ts` (controller, CRUD)

**Analog:** `api-ventago/src/app/prices/types/priceType.controller.ts` — **같은 결함**(CrudController 상속 쓰기 라우트에 가드 없음, 2026-09-22 실측 역할 0개 계정이 실제로 행을 만듦)을 이미 메서드 레벨 `@Auth` 오버라이드로 고친 전례. `functions` 는 전역 테이블이므로 역할 집합은 `priceType`(admin/superadmin/gerente) 보다 **더 좁게** `superadmin` 만.

```ts
// functions.controller.ts — 수정 후 (priceType.controller.ts 패턴, 역할만 좁힘)
import { Body, Controller, Delete, Get, Param, Post, Put, Query, ValidationPipe } from '@nestjs/common';
import { Auth } from 'src/app/auth/decorators/auth.decorator';
import { ValidRoles } from 'src/app/auth/interfaces/valid-roles';
import { Functions } from './functions.model';
// ... 기존 import 유지

@Controller('functions')
export class FunctionsController extends CrudController<Functions> {
  constructor(private readonly functionsService: FunctionsService) {
    super(functionsService);
  }

  // 읽기(GET structure/acciones-de-guardia/full-structure, 상속 getAll/getById)는 손대지 않는다 —
  // PermissionsView 등 기존 호출부가 admin/gerente 로 읽는 경로를 깨지 않기 위해
  // (연구 §9-5 Pitfall 1 — 클래스 레벨 @Auth 금지, 메서드 레벨만).

  @Post('')
  @Auth(ValidRoles.superadmin)
  async create(@Body() body: any): Promise<any> {
    return this.functionsService.create(body);
  }

  @Put(':id')
  @Auth(ValidRoles.superadmin)
  async update(@Param('id') id: number, @Body() body: Partial<Functions>) {
    return this.functionsService.update(Number(id), body);
  }

  @Delete(':id')
  @Auth(ValidRoles.superadmin)
  async remove(@Param('id') id: string): Promise<any> {
    await this.functionsService.delete(Number(id));
    return { success: true };
  }

  // getStructure / accionesDeGuardia / findAllFunctionsPaginated — 기존 그대로
}
```

---

### 19. `api-ventago/src/app/auth/crud-inherited-routes.spec.ts` (MODIFY — 항목 추가, test)

**Analog:** 자기 자신 — 이 파일은 **정확히 이 Phase 가 고치는 결함 패턴**(상속 라우트에 가드 없음)을 16개 기존 케이스로 이미 고정해 두고 있다. `FunctionsController` 를 17번째 케이스로 추가하는 것이 가장 정확한 패턴 재사용이다(새 파일을 만들지 않는다).

```ts
import { FunctionsController } from '../functions/functions.controller';
// casos 배열에 추가:
['functions create', FunctionsController.prototype.create, FunctionsController, null],
['functions update', FunctionsController.prototype.update, FunctionsController, null],
['functions remove', FunctionsController.prototype.remove, FunctionsController, null],
```
기존 `it.each(casos)('%s — 역할 0개 계정은 막힌다', ...)` / `'판매원은 막힌다'` / `'★ 대조군: admin 은 통과한다'` 세 시험이 **자동으로** 새 케이스를 커버한다. 단 `functions` 는 `superadmin` 전용이므로 "admin 은 통과한다" 대조군은 **이 3개 케이스에는 적용하면 안 된다** — 별도 `it.each` 블록으로 분리하거나(admin 거부/superadmin 통과), 파일 구조를 "역할 집합이 다른 그룹"으로 나눠야 한다(기존 파일은 전부 admin 통과 전제라 그대로 넣으면 거짓 실패).

---

### 20. `api-ventago/src/app/support-token/support-token.controller.spec.ts` (NEW, test)

**Analog:** `crud-inherited-routes.spec.ts` 의 `UserRoleGuard` 단위 시험 기법 — `SupportTokenController` 는 `CrudController` 를 상속하지 않지만(§17), 같은 `Reflector`+`contexto()` 헬퍼로 `@Auth(ValidRoles.admin)` 데코레이터가 실제로 메타데이터를 남기는지 검증 가능.

```ts
import { Reflector } from '@nestjs/core';
import { UserRoleGuard } from '../auth/guards/user-role.guard';
import { SupportTokenController } from './support-token.controller';

const contexto = (roles: string[], handler: any, clase: any) => ({
  getHandler: () => handler,
  getClass: () => clase,
  switchToHttp: () => ({ getRequest: () => ({ user: { roles, storeId: 1 } }) }),
}) as any;
const guard = () => new UserRoleGuard(new Reflector());

describe('support-token — generate/usage 는 admin 전용', () => {
  it.each([
    ['generate', SupportTokenController.prototype.generate],
    ['usage', SupportTokenController.prototype.usage],
  ])('%s — vendedor 는 막힌다', (_n, handler) => {
    expect(guard().canActivate(contexto(['vendedor'], handler, SupportTokenController))).toBe(false);
  });
  it('generate — ★ 대조군: admin 은 통과한다', () => {
    expect(guard().canActivate(contexto(['admin'], SupportTokenController.prototype.generate, SupportTokenController))).toBe(true);
  });
});
```

---

### 21. `api-ventago/migrations/2026-10-0X-phase99-seed-reporte-asistencia.sql` (NEW, migration)

**Analog:** `api-ventago/migrations/2026-09-29-c-permiso-reporte-precios-fuera-de-lista.sql` — 가장 최근의 `reporte-*` function 시드이자 CLAUDE.md 의 `-- perm-cache:`/`-- w4-exempt:`/`SET lock_timeout` 규약을 전부 지킨 완성형 템플릿.

```sql
-- Permiso «Asistencia y adelantos» (reporte-asistencia) — Phase 99 D-06.
--
-- perm-cache: sólo agrega (función nueva + concesiones); nada viejo queda más permisivo.
-- w4-exempt: sin DDL — INSERTs sobre tablas de permisos.

SET lock_timeout = '5s';

INSERT INTO functions (name, slug, description, module_id, created_at, updated_at)
SELECT 'Asistencia y adelantos',
       'reporte-asistencia',
       '[Reportes] Asistencia, horas trabajadas y adelantos a vendedores aprobados',
       (SELECT id FROM modules WHERE slug = 'dashboard-reportes' LIMIT 1),
       now(), now()
WHERE NOT EXISTS (SELECT 1 FROM functions WHERE slug = 'reporte-asistencia');

INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
SELECT r.id, f.id, r.store_id, now(), now()
FROM roles r CROSS JOIN functions f
WHERE r.slug IN ('admin', 'store_admin', 'store_owner', 'gerente')
  AND r.store_id IS NOT NULL AND f.slug = 'reporte-asistencia'
ON CONFLICT (role_id, function_id, store_id) DO NOTHING;

INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
SELECT rf.id, 'read', now(), now()
FROM role_functions rf
JOIN functions f ON f.id = rf.function_id
JOIN roles r ON r.id = rf.role_id
WHERE f.slug = 'reporte-asistencia'
  AND r.slug IN ('admin', 'store_admin', 'store_owner', 'gerente')
  AND r.store_id IS NOT NULL
ON CONFLICT (role_function_id, action) DO NOTHING;

SELECT f.slug, f.module_id, count(DISTINCT rf.store_id) AS tiendas, count(rfa.id) AS acciones
FROM functions f
LEFT JOIN role_functions rf ON rf.function_id = f.id
LEFT JOIN role_function_actions rfa ON rfa.role_function_id = rf.id
WHERE f.slug = 'reporte-asistencia'
GROUP BY f.slug, f.module_id;
```
**양쪽(로컬 5432 + 운영 5434) 동시 적용 필수**(CLAUDE.md DB 마이그레이션 규칙) — 밤 배포, DML 영향 행 사전 제시 후 승인.

---

## Shared Patterns

### A. 허브/사이드바 가시성 게이트 — "구조에서 파생, privileged 가 먼저 bypass"
**Source:** `ventago-app/src/pages/configuracion/index.tsx:100-112` (`canSeeTab`), `ventago-app/src/configs/withAccess.tsx:38-62`
**Apply to:** `DispositivosView`/`AccesoParaSoporteView` 를 가리키는 HUB_TABS 항목, `menuRegistry.ts` 의 신규 `requiredModules`/`requiredFunctions` 필드
```ts
if (isSuperadmin) return true
if (tab.requiredPrivileged) return false   // privileged 는 이미 위에서 true 를 받았다
if (tab.requiredApps && !tab.requiredApps.some(slug => userApps.includes(slug))) return false
if (tab.requiredModules && !tab.requiredModules.some(slug => userModules.includes(slug))) return false
return true
```

### B. 서버 쓰기 라우트 가드 — "CrudController 상속은 가드를 안 준다, 메서드 레벨로 좁힌다"
**Source:** `api-ventago/src/app/prices/types/priceType.controller.ts:63-216`, `api-ventago/src/app/auth/crud-inherited-routes.spec.ts` 전체
**Apply to:** `functions.controller.ts`(§18), 향후 전역 테이블 컨트롤러 전수조사(이 Phase 범위 밖이나 같은 패턴)
```ts
@Post() @Auth(ValidRoles.X) async create(...) { return this.service.create(...) }
@Put(':id') @Auth(ValidRoles.X) async update(...) { ... }
@Delete(':id') @Auth(ValidRoles.X) async remove(...) { ... }
```
클래스 레벨 `@Auth` 는 쓰지 않는다(읽기 라우트까지 같이 잠겨 기존 호출부가 깨짐 — Pitfall 1).

### C. superadmin-only 프런트 게이트 — "allowedRoles 로는 admin 을 못 뺀다"
**Source:** `ventago-app/src/configs/withAccess.tsx:33-62`, `ventago-app/src/pages/admin/vto.tsx`
**Apply to:** `admin/permisos/index.tsx`(§6)
```tsx
<WithAccess superadminOnly>
  <Component />
</WithAccess>
```

### D. 상태코드로 "고장"과 "빈 것"을 구분
**Source:** `ventago-app/src/views/relojes/RelojesCard.tsx:30-44`
**Apply to:** `SharedFoldersListView.tsx`/`AdminFoldersView.tsx`(§12-13)
```ts
catch (e: any) {
  if (e?.response?.status === 503) { /* "설정 안 됨" 카피 */ }
  else { /* 일반 에러 카피 */ }
}
```

### E. 정적 텍스트 분석 시험 (`.tsx` import 불가 우회)
**Source:** `ventago-app/src/__tests__/menu-paths-exist.spec.ts`, `sidebar-module-contract.spec.ts`
**Apply to:** `hub-tab-contract.spec.ts`, `route-reachability.spec.ts`(§14-15)
```ts
const src = fs.readFileSync(TARGET_TSX, 'utf8')
const matches = [...src.matchAll(/key:\s*'([^']+)'/g)]
```
대조군 필수(화이트리스트/매칭 결과가 0 이 아님을 먼저 단언) — MEMORY `control-group-can-pass-too.md`.

### F. `reporte-*` function 시드 템플릿
**Source:** `api-ventago/migrations/2026-09-29-c-permiso-reporte-precios-fuera-de-lista.sql`
**Apply to:** `2026-10-0X-phase99-seed-reporte-asistencia.sql`(§21)
`-- perm-cache:` + `-- w4-exempt:` + `SET lock_timeout` + `INSERT ... WHERE NOT EXISTS` + `role_functions`/`role_function_actions` 3단 INSERT + 말미 검증 `SELECT`.

---

## No Analog Found

없음 — 이 Phase 의 21개 파일 전부 기존 코드 안에 직접 대조 가능한 선례(대부분 "같은 결함을 이미 한 번 고친 자리")가 있다. 이는 이 Phase 의 성격(새 기능 없음, 기존 다섯 출처의 불일치를 기존 패턴으로 메움)과 일치한다.

## Metadata

**Analog search scope:** `ventago-app/src/{pages,views,navigation,configs,__tests__}`, `api-ventago/src/app/{support-token,agente,functions,prices,auth,common/crud}`, `api-ventago/migrations`
**Files scanned:** 약 40개 직접 Read, grep 전수(controllers extends CrudController 11개, HUB_TABS 전문, menuRegistry.ts 전문 관련 구간)
**Pattern extraction date:** 2026-10-05
