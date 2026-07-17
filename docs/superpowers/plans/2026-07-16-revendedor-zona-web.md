# Revendedor 지역 추천 — Plan B (웹 포털 + 관리자 UI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** ventago-app(Next.js)에 ① revendedor 웹 포털(로그인 + 허가매장 TIPO 통합 카탈로그 + 자기 지방 베스트셀러 강조 + 추천 액션 + GPS 지역감지) ② 관리자 UI(매장 허가 승인 + canonical 매핑)를 구축한다.

**Architecture:** revendedor 포털은 별도 reseller JWT 로 인증(user auth 와 분리) — 전용 AuthContext + 토큰 저장 + apiConnector 변형. 관리자 UI 는 기존 user/admin auth 재사용. 데이터는 Plan A 의 `/reseller/*` API. 참조데이터(canonical-categories)는 SWR 캐시. 신규 페이지는 `next/dynamic(..., { ssr:false })` 코드 스플리팅.

**Tech Stack:** Next.js 13(Pages Router) + React 18 + MUI 5 + SWR + Axios(apiConnector) + React Hook Form.

**설계/의존:** `docs/superpowers/specs/2026-07-16-revendedor-zona-recomendacion-design.md`, Plan A(`/reseller/*` API 완료 전제). Mockup: `revendedor-zona-mockup.html`(다크 네이비+골드 테마).

## Global Constraints

- **apiConnector 사용**(`src/services/api.service.ts`): `.get/.post/.put/.remove`(`.delete()` 아님).
- **참조데이터는 SWR 훅**(`src/hooks/api/`), 5분 dedup. `useEffect+apiConnector.get` 참조데이터 금지.
- **신규 페이지 코드 스플리팅**: `next/dynamic(() => import('src/views/...'), { ssr: false })`.
- **Context value 는 `useMemo`**. 고트래픽 리스트는 `React.memo`. 이미지 `next/Image`. pageSize ≤ 50.
- **ESLint(빌드 차단)**: `return` 위 빈 줄(`newline-before-return`), 주석 위 빈 줄(`lines-around-comment`), 미사용 import 금지. **프론트 작업 후 `eslint-guardian` subagent 점검 필수**.
- **에러 가시성**: 인라인 Alert + 글로벌 prominent 토스트 (에러 전면 노출 규약).
- **테마**: 다크 네이비(#1a1a2e/#14142a) + 골드(#f5a623). `sketch-findings-ace-online` skill 참조.
- **사용자 노출 문자열 스페인어**, 주석 한국어.
- reseller JWT 는 user JWT 와 별개 저장키. `x-session-token` 세션가드는 reseller 엔 미적용.
- ventago-app 은 gitlink 서브모듈 → `cd ventago-app` 후 커밋.

---

### Task 1: 관리자 — 매장 허가 승인 + canonical 매핑 UI

**Files:**
- Create: `ventago-app/src/hooks/api/useResellerAdmin.ts` (SWR)
- Create: `ventago-app/src/views/admin/reseller/ResellerLinksView.tsx`
- Create: `ventago-app/src/views/admin/reseller/CanonicalMappingView.tsx`
- Create: `ventago-app/src/pages/admin/revendedores/index.tsx`
- Modify: `ventago-app/src/navigation/vertical/index.ts` (메뉴 + CASL 게이트)

**Interfaces:**
- Consumes: Plan A `GET /reseller/admin/links`, `PATCH /reseller/admin/links/:id/approve|revoke`, `GET /reseller/admin/unmapped-categories`, `POST /reseller/admin/map-category`, `GET /reseller/canonical-categories`(관리자용은 전체 — Plan A 확장 필요 시 별도).
- Produces: 관리자 페이지 `/admin/revendedores`.

- [ ] **Step 1: SWR 훅 작성**

Create `ventago-app/src/hooks/api/useResellerAdmin.ts`:

```ts
import useSWR from 'swr';
import { apiConnector } from 'src/services/api.service';

const fetcher = (url: string) => apiConnector.get(url).then((r) => r.data);

export function useResellerLinks(status?: string) {
  const key = status ? `/reseller/admin/links?status=${status}` : '/reseller/admin/links';
  const { data, error, isLoading, mutate } = useSWR(key, fetcher, { dedupingInterval: 300000 });

  return { links: data ?? [], error, isLoading, mutate };
}

export function useUnmappedCategories() {
  const { data, error, isLoading, mutate } = useSWR('/reseller/admin/unmapped-categories', fetcher, {
    dedupingInterval: 300000,
  });

  return { categories: data ?? [], error, isLoading, mutate };
}
```

> **주의:** `apiConnector.get` 반환 형태(`res.data` 언래핑 여부)를 기존 훅(`src/hooks/api/usePriceTypes` 등)에서 확인해 fetcher 를 정합화.

- [ ] **Step 2: 허가 승인 뷰**

Create `ventago-app/src/views/admin/reseller/ResellerLinksView.tsx`:

```tsx
import { useState } from 'react';
import { Box, Card, CardContent, Typography, Button, Chip, Alert, Stack } from '@mui/material';
import { apiConnector } from 'src/services/api.service';
import { useResellerLinks } from 'src/hooks/api/useResellerAdmin';

// 매장 허가(reseller_tienda_link) 승인/취소 관리
const ResellerLinksView = () => {
  const { links, isLoading, mutate } = useResellerLinks();
  const [error, setError] = useState<string | null>(null);

  const act = async (id: number, action: 'approve' | 'revoke') => {
    setError(null);
    try {
      await apiConnector.put(`/reseller/admin/links/${id}/${action}`, {});
      await mutate();
    } catch (e: any) {
      setError(e?.response?.data?.message || 'Error al actualizar la habilitación');
    }
  };

  return (
    <Card>
      <CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>
          Habilitaciones de tienda
        </Typography>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}
        {isLoading && <Typography>Cargando…</Typography>}
        <Stack spacing={1}>
          {links.map((l: any) => (
            <Box key={l.id} sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <Typography sx={{ flex: 1 }}>
                Reseller #{l.resellerId} · Tienda #{l.storeId}
              </Typography>
              <Chip
                label={l.status}
                color={l.status === 'approved' ? 'success' : l.status === 'revoked' ? 'default' : 'warning'}
                size="small"
              />
              {l.status !== 'approved' && (
                <Button size="small" variant="contained" onClick={() => act(l.id, 'approve')}>
                  Aprobar
                </Button>
              )}
              {l.status === 'approved' && (
                <Button size="small" color="error" onClick={() => act(l.id, 'revoke')}>
                  Revocar
                </Button>
              )}
            </Box>
          ))}
        </Stack>
      </CardContent>
    </Card>
  );
};

export default ResellerLinksView;
```

> **주의:** Plan A 컨트롤러는 `@Patch(...approve)`. apiConnector 에 patch 가 없으면 `apiConnector.put` 매핑을 확인하거나 컨트롤러를 `@Put` 로 맞춘다(백엔드/프론트 메서드 정합).

- [ ] **Step 3: canonical 매핑 뷰**

Create `ventago-app/src/views/admin/reseller/CanonicalMappingView.tsx`:

```tsx
import { useState } from 'react';
import { Card, CardContent, Typography, MenuItem, Select, Box, Alert } from '@mui/material';
import { apiConnector } from 'src/services/api.service';
import { useUnmappedCategories } from 'src/hooks/api/useResellerAdmin';
import { useCanonicalCategories } from 'src/hooks/api/useResellerCatalog';

// 미매핑 매장 카테고리 → canonical 카테고리 수동 매핑
const CanonicalMappingView = () => {
  const { categories, isLoading, mutate } = useUnmappedCategories();
  const { canonical } = useCanonicalCategories();
  const [error, setError] = useState<string | null>(null);

  const map = async (categoryId: number, canonicalId: number) => {
    setError(null);
    try {
      await apiConnector.post('/reseller/admin/map-category', { categoryId, canonicalId });
      await mutate();
    } catch (e: any) {
      setError(e?.response?.data?.message || 'Error al mapear la categoría');
    }
  };

  return (
    <Card sx={{ mt: 2 }}>
      <CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>
          Categorías sin mapear ({categories.length})
        </Typography>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}
        {isLoading && <Typography>Cargando…</Typography>}
        {categories.map((c: any) => (
          <Box key={c.id} sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 1 }}>
            <Typography sx={{ flex: 1 }}>
              {c.name} (Tienda #{c.storeId})
            </Typography>
            <Select
              size="small"
              defaultValue=""
              displayEmpty
              onChange={(e) => map(c.id, Number(e.target.value))}
              sx={{ minWidth: 200 }}
            >
              <MenuItem value="" disabled>
                Elegir TIPO…
              </MenuItem>
              {canonical.map((cc: any) => (
                <MenuItem key={cc.id} value={cc.id}>
                  {cc.name}
                </MenuItem>
              ))}
            </Select>
          </Box>
        ))}
      </CardContent>
    </Card>
  );
};

export default CanonicalMappingView;
```

- [ ] **Step 4: 페이지 + 코드 스플리팅 + 메뉴**

Create `ventago-app/src/pages/admin/revendedores/index.tsx`:

```tsx
import dynamic from 'next/dynamic';
import { Box } from '@mui/material';

const ResellerLinksView = dynamic(() => import('src/views/admin/reseller/ResellerLinksView'), { ssr: false });
const CanonicalMappingView = dynamic(() => import('src/views/admin/reseller/CanonicalMappingView'), { ssr: false });

const RevendedoresAdminPage = () => {
  return (
    <Box>
      <ResellerLinksView />
      <CanonicalMappingView />
    </Box>
  );
};

export default RevendedoresAdminPage;
```

`navigation/vertical/index.ts` 에 메뉴 항목 추가(기존 admin 섹션 패턴 따름, CASL `revendedor_admin` 게이트):
```ts
  {
    title: 'Revendedores',
    path: '/admin/revendedores',
    action: 'read',
    subject: 'revendedor_admin',
  },
```

- [ ] **Step 5: ESLint 점검 + 커밋**

`eslint-guardian` subagent 로 신규 파일 점검(newline-before-return, lines-around-comment, 미사용 import).

Run: `cd ventago-app && npx eslint src/views/admin/reseller/ src/pages/admin/revendedores/ src/hooks/api/useResellerAdmin.ts`
Expected: 0 error.

```bash
cd ventago-app
git add src/hooks/api/useResellerAdmin.ts src/views/admin/reseller/ src/pages/admin/revendedores/ src/navigation/vertical/index.ts
git commit -m "feat(revendedor-admin): 매장 허가 승인 + canonical 매핑 UI

/admin/revendedores — reseller_tienda_link 승인/취소 + 미매핑 카테고리 매핑.
CASL revendedor_admin 게이트. SWR 캐시."
```

---

### Task 2: revendedor 인증 컨텍스트 + 로그인 페이지

**Files:**
- Create: `ventago-app/src/services/reseller-api.service.ts` (reseller JWT apiConnector 변형)
- Create: `ventago-app/src/context/ResellerAuthContext.tsx`
- Create: `ventago-app/src/pages/revendedor/login.tsx`
- Create: `ventago-app/src/views/revendedor/ResellerLoginView.tsx`

**Interfaces:**
- Consumes: Plan A `POST /reseller/auth/login`, `GET /reseller/auth/me`.
- Produces: `useResellerAuth()` → `{ reseller, token, login, logout }`. `resellerApi`(토큰 자동주입). Task 3~5 사용.

- [ ] **Step 1: reseller apiConnector**

Create `ventago-app/src/services/reseller-api.service.ts`:

```ts
import axios from 'axios';

// reseller JWT 전용 axios 인스턴스 (user apiConnector 와 토큰 분리).
const API_HOST = process.env.NEXT_PUBLIC_API_HOST || 'http://localhost:5002/api';
const TOKEN_KEY = 'reseller_token';

const instance = axios.create({ baseURL: API_HOST });

instance.interceptors.request.use((config) => {
  const token = typeof window !== 'undefined' ? localStorage.getItem(TOKEN_KEY) : null;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }

  return config;
});

export const resellerApi = instance;
export const RESELLER_TOKEN_KEY = TOKEN_KEY;
```

> **주의:** `NEXT_PUBLIC_API_HOST` env 명칭을 기존 `api.service.ts` 와 동일하게 맞춘다(운영/개발 URL).

- [ ] **Step 2: AuthContext**

Create `ventago-app/src/context/ResellerAuthContext.tsx`:

```tsx
import { createContext, useContext, useEffect, useMemo, useState, ReactNode } from 'react';
import { resellerApi, RESELLER_TOKEN_KEY } from 'src/services/reseller-api.service';

interface ResellerUser {
  id: number;
  name: string;
  provinceId: number | null;
  provinceSource?: string;
}

interface Ctx {
  reseller: ResellerUser | null;
  loading: boolean;
  login: (emailOrDocument: string, password: string) => Promise<void>;
  logout: () => void;
  refresh: () => Promise<void>;
}

const ResellerAuthContext = createContext<Ctx | null>(null);

export const ResellerAuthProvider = ({ children }: { children: ReactNode }) => {
  const [reseller, setReseller] = useState<ResellerUser | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = async () => {
    try {
      const { data } = await resellerApi.get('/reseller/auth/me');
      setReseller(data);
    } catch {
      setReseller(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (typeof window !== 'undefined' && localStorage.getItem(RESELLER_TOKEN_KEY)) {
      refresh();
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (emailOrDocument: string, password: string) => {
    const { data } = await resellerApi.post('/reseller/auth/login', { emailOrDocument, password });
    localStorage.setItem(RESELLER_TOKEN_KEY, data.token);
    await refresh();
  };

  const logout = () => {
    localStorage.removeItem(RESELLER_TOKEN_KEY);
    setReseller(null);
  };

  const value = useMemo(() => ({ reseller, loading, login, logout, refresh }), [reseller, loading]);

  return <ResellerAuthContext.Provider value={value}>{children}</ResellerAuthContext.Provider>;
};

export const useResellerAuth = () => {
  const ctx = useContext(ResellerAuthContext);
  if (!ctx) {
    throw new Error('useResellerAuth must be used within ResellerAuthProvider');
  }

  return ctx;
};
```

- [ ] **Step 3: 로그인 뷰 + 페이지**

Create `ventago-app/src/views/revendedor/ResellerLoginView.tsx`:

```tsx
import { useState } from 'react';
import { useRouter } from 'next/router';
import { Box, Card, CardContent, TextField, Button, Typography, Alert } from '@mui/material';
import { useResellerAuth } from 'src/context/ResellerAuthContext';

const ResellerLoginView = () => {
  const { login } = useResellerAuth();
  const router = useRouter();
  const [emailOrDocument, setId] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await login(emailOrDocument, password);
      router.push('/revendedor');
    } catch (err: any) {
      setError(err?.response?.data?.message || 'Credenciales inválidas');
    }
  };

  return (
    <Box sx={{ display: 'grid', placeItems: 'center', minHeight: '100vh', bgcolor: '#14142a' }}>
      <Card sx={{ width: 360 }}>
        <CardContent component="form" onSubmit={submit}>
          <Typography variant="h6" sx={{ mb: 2 }}>
            Portal Revendedor
          </Typography>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}
          <TextField
            fullWidth
            label="Email o documento"
            value={emailOrDocument}
            onChange={(e) => setId(e.target.value)}
            sx={{ mb: 2 }}
          />
          <TextField
            fullWidth
            type="password"
            label="Contraseña"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            sx={{ mb: 2 }}
          />
          <Button fullWidth type="submit" variant="contained">
            Ingresar
          </Button>
        </CardContent>
      </Card>
    </Box>
  );
};

export default ResellerLoginView;
```

Create `ventago-app/src/pages/revendedor/login.tsx`:

```tsx
import dynamic from 'next/dynamic';
import { ResellerAuthProvider } from 'src/context/ResellerAuthContext';

const ResellerLoginView = dynamic(() => import('src/views/revendedor/ResellerLoginView'), { ssr: false });

const Page = () => (
  <ResellerAuthProvider>
    <ResellerLoginView />
  </ResellerAuthProvider>
);

// 관리자 레이아웃/가드 미적용 (독립 포털)
Page.getLayout = (page: React.ReactNode) => page;
Page.authGuard = false;

export default Page;

```

> **주의:** ventago-app 의 페이지 레이아웃/authGuard 우회 방식(`getLayout`, `authGuard`/`guestGuard` 정적 속성)을 기존 로그인 페이지(`pages/login` 등)에서 확인해 정확히 맞춘다. revendedor 포털은 admin auth 를 타면 안 됨.

- [ ] **Step 4: ESLint + 커밋**

`eslint-guardian` 점검 후:
```bash
cd ventago-app
git add src/services/reseller-api.service.ts src/context/ResellerAuthContext.tsx src/views/revendedor/ResellerLoginView.tsx src/pages/revendedor/login.tsx
git commit -m "feat(revendedor): 포털 인증 — reseller JWT 컨텍스트 + 로그인

user auth 와 분리된 reseller apiConnector + AuthContext(useMemo value) + 로그인 페이지."
```

---

### Task 3: revendedor 카탈로그 SWR 훅 + TIPO 탭 + 상품 그리드

**Files:**
- Create: `ventago-app/src/hooks/api/useResellerCatalog.ts`
- Create: `ventago-app/src/views/revendedor/ResellerCatalogView.tsx`
- Create: `ventago-app/src/pages/revendedor/index.tsx`

**Interfaces:**
- Consumes: Plan A `GET /reseller/catalog`, `GET /reseller/canonical-categories`. Task 2 auth.
- Produces: `useCanonicalCategories`, `useResellerCatalog(opts)`. 포털 메인 `/revendedor`.

- [ ] **Step 1: SWR 훅**

Create `ventago-app/src/hooks/api/useResellerCatalog.ts`:

```ts
import useSWR from 'swr';
import { resellerApi } from 'src/services/reseller-api.service';

const fetcher = (url: string) => resellerApi.get(url).then((r) => r.data);

export function useCanonicalCategories() {
  const { data, error, isLoading } = useSWR('/reseller/canonical-categories', fetcher, {
    dedupingInterval: 300000,
  });

  return { canonical: data ?? [], error, isLoading };
}

export function useResellerCatalog(opts: {
  canonicalCategoryId?: number;
  storeId?: number;
  search?: string;
  page?: number;
}) {
  const params = new URLSearchParams();
  if (opts.canonicalCategoryId) params.set('canonicalCategoryId', String(opts.canonicalCategoryId));
  if (opts.storeId) params.set('storeId', String(opts.storeId));
  if (opts.search) params.set('search', opts.search);
  params.set('page', String(opts.page ?? 1));
  const { data, error, isLoading } = useSWR(`/reseller/catalog?${params.toString()}`, fetcher);

  return { catalog: data?.items ?? [], page: data?.page ?? 1, error, isLoading };
}
```

- [ ] **Step 2: 카탈로그 뷰 (TIPO 탭 + 그리드)**

Create `ventago-app/src/views/revendedor/ResellerCatalogView.tsx` — mockup(다크 네이비+골드) 기준. TIPO 탭 + 매장칩 + 상품 그리드(zona 강조는 Task 4 에서 rail 추가). 핵심:

```tsx
import { useState } from 'react';
import { Box, Tabs, Tab, Grid, Card, CardContent, Typography, Chip, TextField } from '@mui/material';
import { useCanonicalCategories, useResellerCatalog } from 'src/hooks/api/useResellerCatalog';

const ResellerCatalogView = () => {
  const { canonical } = useCanonicalCategories();
  const [tipo, setTipo] = useState<number | undefined>(undefined);
  const [search, setSearch] = useState('');
  const { catalog, isLoading } = useResellerCatalog({ canonicalCategoryId: tipo, search, page: 1 });

  return (
    <Box sx={{ p: 2 }}>
      <TextField
        size="small"
        placeholder="Buscar producto…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        sx={{ mb: 2, width: 320 }}
      />
      <Tabs value={tipo ?? 'all'} onChange={(_, v) => setTipo(v === 'all' ? undefined : Number(v))} variant="scrollable">
        <Tab label="Todos" value="all" />
        {canonical.map((c: any) => (
          <Tab key={c.id} label={c.name} value={c.id} />
        ))}
      </Tabs>
      {isLoading && <Typography sx={{ mt: 2 }}>Cargando…</Typography>}
      <Grid container spacing={2} sx={{ mt: 1 }}>
        {catalog.map((p: any) => (
          <Grid item xs={6} sm={4} md={3} key={`${p.product_id}-${p.store_id}`}>
            <Card sx={{ height: '100%' }}>
              <CardContent>
                <Chip label={p.store_name} size="small" sx={{ mb: 1 }} />
                <Typography variant="subtitle2">{p.name}</Typography>
                <Typography variant="caption" color="text.secondary">
                  {p.sku}
                </Typography>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mt: 1 }}>
                  <Typography fontWeight={700}>${Number(p.price).toLocaleString('es-AR')}</Typography>
                  <Chip
                    label={p.in_stock ? 'En stock' : 'Sin stock'}
                    color={p.in_stock ? 'success' : 'default'}
                    size="small"
                  />
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Box>
  );
};

export default ResellerCatalogView;
```

- [ ] **Step 3: 포털 메인 페이지 (auth 가드)**

Create `ventago-app/src/pages/revendedor/index.tsx`:

```tsx
import dynamic from 'next/dynamic';
import { useEffect } from 'react';
import { useRouter } from 'next/router';
import { ResellerAuthProvider, useResellerAuth } from 'src/context/ResellerAuthContext';

const ResellerCatalogView = dynamic(() => import('src/views/revendedor/ResellerCatalogView'), { ssr: false });
const ResellerZonaRail = dynamic(() => import('src/views/revendedor/ResellerZonaRail'), { ssr: false });

const Inner = () => {
  const { reseller, loading } = useResellerAuth();
  const router = useRouter();
  useEffect(() => {
    if (!loading && !reseller) {
      router.replace('/revendedor/login');
    }
  }, [loading, reseller, router]);
  if (loading || !reseller) {
    return null;
  }

  return (
    <>
      <ResellerZonaRail />
      <ResellerCatalogView />
    </>
  );
};

const Page = () => (
  <ResellerAuthProvider>
    <Inner />
  </ResellerAuthProvider>
);

Page.getLayout = (page: React.ReactNode) => page;
Page.authGuard = false;

export default Page;

```

> **주의:** `ResellerZonaRail` 은 Task 4 에서 생성. Task 3 커밋 전에 임시 빈 컴포넌트 or Task 4 와 묶어 커밋. 여기선 Task 4 와 연속 실행 가정 — Step 4 커밋은 Task 4 완료 후.

- [ ] **Step 4: ESLint + 커밋 (Task 4 와 함께)**

Task 4 완료 후 통합 커밋. (카탈로그+rail 한 커밋)

---

### Task 4: zona 추천 rail + 강조 + GPS 지역감지 + 추천 액션

**Files:**
- Create: `ventago-app/src/hooks/api/useResellerRecommendations.ts`
- Create: `ventago-app/src/views/revendedor/ResellerZonaRail.tsx`
- Modify: `ventago-app/src/views/revendedor/ResellerCatalogView.tsx` (zona 강조 badge)

**Interfaces:**
- Consumes: Plan A `GET /reseller/recommendations`, `GET /reseller/recommendations/stock-gap`, `POST /reseller/recommendations`, `POST /reseller/detect-province`.
- Produces: 포털 상단 "Recomendado para {provincia}" 강조 레일 + Recomendar 액션 + GPS 감지.

- [ ] **Step 1: SWR 훅 + 액션**

Create `ventago-app/src/hooks/api/useResellerRecommendations.ts`:

```ts
import useSWR from 'swr';
import { resellerApi } from 'src/services/reseller-api.service';

const fetcher = (url: string) => resellerApi.get(url).then((r) => r.data);

export function useZoneTop(canonicalCategoryId?: number) {
  const key = canonicalCategoryId
    ? `/reseller/recommendations?canonicalCategoryId=${canonicalCategoryId}`
    : '/reseller/recommendations';
  const { data, error, isLoading, mutate } = useSWR(key, fetcher);

  return { items: data ?? [], error, isLoading, mutate };
}

export async function recommendToStore(payload: {
  storeId: number;
  productId: number;
  provinceId?: number;
  reason: string;
}) {
  return resellerApi.post('/reseller/recommendations', payload);
}

export async function detectProvince(lat: number, lng: number) {
  return resellerApi.post('/reseller/detect-province', { lat, lng });
}
```

- [ ] **Step 2: zona rail 뷰 (GPS 감지 포함)**

Create `ventago-app/src/views/revendedor/ResellerZonaRail.tsx`:

```tsx
import { useEffect, useState } from 'react';
import { Box, Typography, Card, Chip, Button, Alert, Snackbar } from '@mui/material';
import { useResellerAuth } from 'src/context/ResellerAuthContext';
import { useZoneTop, recommendToStore, detectProvince } from 'src/hooks/api/useResellerRecommendations';

// "Recomendado para tu zona" 강조 레일 + GPS 지역감지 + Recomendar 액션
const ResellerZonaRail = () => {
  const { reseller, refresh } = useResellerAuth();
  const { items, mutate } = useZoneTop();
  const [toast, setToast] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // GPS 지역감지 — provinceId 없을 때만 시도(권한 요청). 거부 시 수동 폴백 안내.
  useEffect(() => {
    if (reseller && !reseller.provinceId && typeof navigator !== 'undefined' && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        async (pos) => {
          try {
            await detectProvince(pos.coords.latitude, pos.coords.longitude);
            await refresh();
            await mutate();
          } catch {
            setError('No se pudo detectar tu provincia. Configurala manualmente en tu perfil.');
          }
        },
        () => setError('Activá la ubicación para ver recomendaciones de tu zona, o elegí tu provincia en el perfil.'),
      );
    }
  }, [reseller, refresh, mutate]);

  const recommend = async (it: any) => {
    setError(null);
    try {
      await recommendToStore({ storeId: it.storeId, productId: it.productId, provinceId: reseller?.provinceId ?? undefined, reason: 'zona_top' });
      setToast('Recomendado a la tienda');
    } catch (e: any) {
      setError(e?.response?.data?.message || 'Error al recomendar');
    }
  };

  return (
    <Box sx={{ p: 2 }}>
      {error && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}
      <Typography variant="h6" sx={{ mb: 1 }}>
        🔥 Recomendado para tu zona
      </Typography>
      <Box sx={{ display: 'flex', gap: 2, overflowX: 'auto', pb: 1 }}>
        {items.map((it: any) => (
          <Card key={`${it.productId}-${it.storeId}`} sx={{ minWidth: 240, p: 1.5, border: '1px solid #f5a62355' }}>
            <Chip label={`#${it.rank} · ${it.storeName}`} size="small" color="warning" sx={{ mb: 1 }} />
            <Typography variant="subtitle2">{it.name}</Typography>
            {it.trendPct != null && it.trendPct > 0 && (
              <Typography variant="caption" sx={{ color: '#ff7a45' }}>
                ▲ +{it.trendPct}% tendencia
              </Typography>
            )}
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mt: 1 }}>
              <Typography fontWeight={700}>${Number(it.price).toLocaleString('es-AR')}</Typography>
              <Button size="small" variant="contained" onClick={() => recommend(it)}>
                Recomendar
              </Button>
            </Box>
          </Card>
        ))}
      </Box>
      <Snackbar open={!!toast} autoHideDuration={3000} onClose={() => setToast(null)} message={toast ?? ''} />
    </Box>
  );
};

export default ResellerZonaRail;
```

- [ ] **Step 3: 카탈로그 그리드에 zona 강조**

`ResellerCatalogView.tsx` 에서 zoneTop 상품 id 집합으로 카드 강조(골드 보더 + 🔥). `useZoneTop` 의 productId 집합을 만들어 `catalog` 카드에 `if (hotIds.has(p.product_id)) sx.border='1px solid #f5a623'` 적용. (구현자: hotIds `Set` 을 `useMemo`.)

- [ ] **Step 4: ESLint + 통합 커밋 (Task 3+4)**

`eslint-guardian` 점검 후:
```bash
cd ventago-app
git add src/hooks/api/useResellerCatalog.ts src/hooks/api/useResellerRecommendations.ts src/views/revendedor/ src/pages/revendedor/index.tsx
git commit -m "feat(revendedor): 포털 카탈로그 + zona 추천 rail + GPS 감지

TIPO 탭 통합 카탈로그 + 'Recomendado para tu zona' 강조 레일 + GPS 지역감지
(권한거부 수동폴백) + Recomendar a tienda 액션. SWR 캐시, 코드 스플리팅."
```

---

## Self-Review

**커버리지:** Z-15(웹 포털 T2/T3/T4), 관리자 UI(허가 승인+매핑 T1), zona 강조(T4), GPS(T4), 추천 액션(T4), 통합 카탈로그 TIPO(T3). 에러 가시성(Alert+토스트 전반). 코드 스플리팅·SWR·useMemo value 준수.

**미해결/주의:** apiConnector patch/put 정합(백엔드 @Patch vs 프론트), 페이지 authGuard 우회 방식(기존 로그인 페이지 확인), fetcher 언래핑 형태. 전부 구현자 주의로 명시.

**후속:** Plan C(mobile-sales-app). revendedor 프로필 수동 provincia 설정 화면은 GPS 폴백 안내만 있고 별건(후속).
