# VentaGO 프론트엔드 성능 최적화 Phase 1 — 작업 정리

**작업일:** 2026-04-15  
**브랜치:** `perf/phase1-frontend` → `main` 머지 완료  
**PR:** https://github.com/jhkim1010/aceiii.online.1.0/pull/1  
**대상:** `ventago-app` (Next.js 13 프론트엔드)  
**목표:** 사이드바 메뉴 클릭 → 콘텐츠 렌더링 P95 ≤ 300ms

---

## 목차

1. [배경 및 진단](#1-배경-및-진단)
2. [Task 1 — 측정 인프라 구축](#2-task-1--측정-인프라-구축)
3. [Task 2 — 라이브러리 중복 제거](#3-task-2--라이브러리-중복-제거-date-fns--luxon)
4. [Task 3 — 사이드바 최적화 + 페이지 전환 스켈레톤](#4-task-3--사이드바-최적화--페이지-전환-스켈레톤)
5. [Task 4 — 라우트 레벨 코드 스플리팅](#5-task-4--라우트-레벨-코드-스플리팅)
6. [Task 5 — SWR 데이터 캐시 레이어](#6-task-5--swr-데이터-캐시-레이어)
7. [Task 6 — 기타 Quick Wins](#7-task-6--기타-quick-wins)
8. [커밋 이력](#8-커밋-이력)
9. [예상 효과](#9-예상-효과)
10. [다음 단계 (Phase 2 권장)](#10-다음-단계-phase-2-권장)

---

## 1. 배경 및 진단

PRD `ACE_III_Performance_Optimization_Phase_2026.docx` 기반으로 다음 병목 요소가 식별됨:

| 문제 | 원인 |
|---|---|
| 사이드바 전환 후 콘텐츠 표시 2초+ | React Query/SWR 미사용 → 304 응답임에도 매번 렌더링 |
| 초기 번들 비대 | ag-grid, fullcalendar, apexcharts, draft-js 전부 초기 로드 |
| 날짜 라이브러리 중복 | `date-fns 2.30.0` + `luxon ^3.3.0` 동시 사용 |
| 측정 불가 | bundle-analyzer 미설정, 라우트 타이밍 로그 없음 |
| 폰트 외부 요청 | Google Fonts CDN 사용 → 외부 네트워크 레이턴시 |

---

## 2. Task 1 — 측정 인프라 구축

### 생성된 파일

| 파일 | 설명 |
|---|---|
| `src/utils/dev-logger.ts` | `devLog(category, msg, data?)` — 개발 환경 전용 로거, 프로덕션 no-op |
| `src/hooks/useRouteTimingLogger.ts` | `router.events` 기반 라우트 전환 시간 측정. P50/P95 통계(`getStats()`) 반환. 마지막 50건 유지 |
| `src/hooks/usePageLifecycleLogger.ts` | 페이지 mount/unmount 타이밍 로그. `pageName` 파라미터 |
| `src/pages/api/web-vitals.ts` | Web Vitals POST 수신 엔드포인트 (서버 콘솔 로깅) |

### 수정된 파일

**`next.config.js`**  
```js
const withBundleAnalyzer = require('@next/bundle-analyzer')({ enabled: process.env.ANALYZE === 'true' })
module.exports = withBundleAnalyzer({ ... })
```
→ `ANALYZE=true npm run build` 실행 시 번들 분석 리포트 생성

**`src/pages/_app.tsx`**  
- `useRouteTimingLogger()` 초기화
- `export function reportWebVitals(metric)` 추가:
  - 개발: `console` 출력
  - 프로덕션: `navigator.sendBeacon('/api/web-vitals', ...)` 비차단 전송

### 사용법

```bash
# 번들 분석
ANALYZE=true npm run build

# 개발 서버에서 라우트 타이밍 확인
# 브라우저 콘솔 → [ROUTE] /ventas → /productos | 214ms
```

---

## 3. Task 2 — 라이브러리 중복 제거 (date-fns → luxon)

### 결정 근거

| 라이브러리 | 사용 파일 수 | 결정 |
|---|---|---|
| `luxon` | 30+ 파일 | **유지** |
| `date-fns` | 4 파일 | **제거** |

### 교체된 파일 및 변환 내역

| 파일 | 변환 |
|---|---|
| `src/@core/utils/get-daterange.ts` | `differenceInDays` → `.diff('days').days`, `addDays` → `.plus({days})`, `format` → `.toFormat()` |
| `src/components/forms/DateRange.tsx` | `format(date, fmt)` → `DateTime.fromJSDate(date).toFormat(fmt)` |
| `src/views/products/hook/ProductContext.tsx` | `format(new Date(), 'yyyy-MM-dd')` → `DateTime.now().toFormat('yyyy-MM-dd')` |
| `src/views/products/list/components/ProductsList.tsx` | 동일 패턴 교체 |

> **예외:** `DateRange.tsx`의 `import es from 'date-fns/locale/es'`는 `react-datepicker` peer dependency로 유지 (react-datepicker가 내부적으로 date-fns locale을 요구)

### package.json 변경

```diff
- "date-fns": "2.30.0",
```

---

## 4. Task 3 — 사이드바 최적화 + 페이지 전환 스켈레톤

### 사이드바 현황

이전 작업(2026-03-31)에서 이미 적용됨:
- `Navigation` 컴포넌트: `React.memo` + `useMemo` (darkTheme)
- `UserLayout`: `useCallback`/`useMemo`로 콜백 메모이제이션

### 추가 작업

**`src/components/layout/PageTransitionSkeleton.tsx`** (신규)  
라우트 전환 중 MUI `Skeleton` 기반 콘텐츠 영역 즉각 표시:
```tsx
<Box sx={{ p: 2 }}>
  {/* 상단 필터 영역 */}
  <Skeleton variant="rectangular" width={120} height={40} />
  ...
  {/* 테이블/콘텐츠 영역 */}
  <Skeleton variant="rectangular" width="100%" height={400} />
</Box>
```

**`src/pages/_app.tsx`** 수정  
- `isRouteChanging` state 추가
- `useEffect` + `router.events`로 상태 관리
- 전환 중: `<PageTransitionSkeleton>` 표시 / 완료 후: 실제 페이지 표시

**`src/context/AuthContext.tsx`** — TODO 주석 추가  
```tsx
// TODO: [성능 최적화] AuthContext가 너무 많은 값을 제공하여 하위 컴포넌트 전체 리렌더 발생.
// 향후 빈번히 변경되는 값(selectedBranchId 등)과 정적 값(user 프로필, logout 함수)을
// 별도 Context로 분리하면 불필요한 리렌더를 줄일 수 있음.
```

---

## 5. Task 4 — 라우트 레벨 코드 스플리팅

### 전략

- `react-apexcharts`는 이미 `@core/components/react-apexcharts/index.tsx`에서 `next/dynamic` 처리됨 ✅
- ag-grid를 포함하는 뷰를 사용하는 **페이지 파일**에 `next/dynamic + ssr:false` 적용

### 적용된 11개 페이지

| 페이지 | 적용된 뷰 컴포넌트 | 이유 |
|---|---|---|
| `pages/ventas/index.tsx` | `SalesListView` | ag-grid (FullTable) |
| `pages/productos/index.tsx` | `ProductsView` | ag-grid (FullTable) |
| `pages/caja/index.tsx` | `BoxResume` | ag-grid (BoxOperationCard) |
| `pages/gastos/index.tsx` | `ExpensesView` | ag-grid |
| `pages/usuarios/index.tsx` | `UsersListView` | ag-grid |
| `pages/sucursales/index.tsx` | `BranchList` | ag-grid |
| `pages/configuracion/productos/index.tsx` | `ConfigurationView` | ag-grid (transitive) |
| `pages/configuracion/ventas/index.tsx` | `ConfigurationSalesView` | ag-grid (transitive) |
| `pages/dashboards/ventas/index.tsx` | `DashboardsSalesView` | apexcharts |
| `pages/dashboards/admin/index.tsx` | `DashboardsView` | apexcharts |
| `pages/dashboards/producto/index.tsx` | `DashboardsProductsView` | apexcharts |

### 패턴

```tsx
// 이전
import SalesListView from 'src/views/sales/list/SalesListView'

// 이후
import dynamic from 'next/dynamic'

// 판매 내역 뷰 — ag-grid 포함, 해당 라우트 진입 시에만 로드
const SalesListView = dynamic(() => import('src/views/sales/list/SalesListView'), { ssr: false })
```

---

## 6. Task 5 — SWR 데이터 캐시 레이어

### 설치

```json
"swr": "^2.4.1"
```

### 생성된 파일

| 파일 | 설명 |
|---|---|
| `src/lib/swr-config.tsx` | `SwrConfigProvider` — 전역 SWR 설정 (fetcher=apiConnector.get, dedupingInterval=5분, revalidateOnFocus=false) |
| `src/hooks/useApi.ts` | 범용 SWR 래핑 훅 `useApi<T>(url, options?)` |
| `src/hooks/api/usePriceTypes.ts` | `/price-types` 캐시 훅 |
| `src/hooks/api/useCategoriesByStore.ts` | `/categories/by-store` 캐시 훅 |
| `src/hooks/api/useBranchByStore.ts` | `/branch/store/:storeId` 캐시 훅 |

### SWR 전역 설정

```tsx
<SWRConfig value={{
  fetcher: (url) => apiConnector.get(url),
  dedupingInterval: 5 * 60 * 1000,  // 5분간 동일 요청 중복 차단
  revalidateOnFocus: false,           // 탭 전환 시 불필요한 재호출 방지
  revalidateOnMount: true,            // 첫 로드는 항상 최신 데이터
}}>
```

### API 타이밍 로그 (`api.service.ts` 수정)

```typescript
// 요청 인터셉터: 시작 시각 기록
(config as any).__startTime = performance.now()

// 응답 인터셉터: 개발 환경에서 소요 시간 출력
// [API] GET /price-types | 200 | 47ms
devLog('API', `${method} ${url} | ${status} | ${duration}ms`)
```

### 사용 예시

```tsx
// 기존 패턴 (매 마운트마다 API 호출)
useEffect(() => {
  apiConnector.get('/price-types').then(setTypes)
}, [])

// SWR 패턴 (5분간 캐시, 중복 호출 차단)
const { data: types, isLoading } = usePriceTypes()
```

---

## 7. Task 6 — 기타 Quick Wins

### Google Fonts → next/font/google

**`src/styles/fonts.ts`** (신규)
```typescript
import { Public_Sans } from 'next/font/google'

export const publicSans = Public_Sans({
  weight: ['300', '400', '500', '600', '700'],
  style: ['normal', 'italic'],
  subsets: ['latin'],
  display: 'swap',
})
```

**`src/pages/_document.tsx`** 수정
- Google Fonts 외부 `<link>` 태그 3개 제거
- `<Html className={publicSans.className}>` 적용
- 효과: 외부 fonts.googleapis.com 네트워크 요청 제거 → TTFB 단축, 레이아웃 시프트 방지

### next/image 적용

`src/@core/layouts/components/blank-layout-with-appBar/index.tsx`:
```tsx
// 이전
<img src='/logo.svg' alt='logo' style={{height: 50}} />

// 이후
<Image src='/logo.svg' alt='logo' height={50} width={120} />
```

### console.log → devLog

`src/context/AuthContext.tsx`: 4개 `console.log` → `devLog('AUTH', ...)` 교체  
프로덕션 번들에서 로그 코드 트리쉐이킹 가능

---

## 8. 커밋 이력

`ventago-app` 서브모듈 (`jhkim1010/ventago-app`):

| 커밋 SHA | 메시지 |
|---|---|
| `548c65e` | fix: usePageLifecycleLogger Rules of Hooks 위반 수정 |
| `bf4072d` | perf: Google Fonts를 next/font로 전환 + 로고 next/image 적용 + 콘솔 로그 최적화 |
| `0ef8ae3` | perf: SWR 캐시 레이어 도입 + API 타이밍 로그 추가 |
| `7839136` | perf: 라우트 레벨 코드 스플리팅 적용 (ag-grid 지연 로딩) |
| `6a42196` | perf: 페이지 전환 스켈레톤 추가 + Context 분리 TODO |
| `b2bb596` | perf: date-fns 제거 후 luxon으로 통일 (번들 크기 감소) |
| `3edc4b6` | perf: Task 1 측정 인프라 구축 완료 - bundle analyzer, route timing, Web Vitals |
| `3de3c6c` | feat(perf): 성능 측정 인프라 구축 (Phase 1) |

---

## 9. 예상 효과

| 항목 | 개선 내용 |
|---|---|
| **초기 번들 크기** | ag-grid(~600KB), apexcharts 등 필요 시에만 로드 → 초기 JS 대폭 감소 |
| **중복 API 호출** | SWR dedup 5분 → 동일 엔드포인트 여러 컴포넌트에서 사용해도 요청 1건 |
| **라우트 전환 UX** | 스켈레톤 즉각 표시 → 빈 화면 대기 없음 |
| **폰트 로드** | 외부 CDN 요청 제거 → TTFB 단축, CLS 방지 |
| **번들 측정** | `ANALYZE=true npm run build` → 청크별 크기 가시화 |
| **성능 모니터링** | Web Vitals 자동 수집 + 라우트 P95 측정 → 데이터 기반 추가 최적화 가능 |

---

## 10. 다음 단계 (Phase 2 권장)

| 우선순위 | 작업 |
|---|---|
| P0 | 기존 `useEffect + apiConnector.get` 패턴을 `useApi` SWR 훅으로 교체 (ProductsView, SalesListView 등) |
| P0 | `AuthContext` 분리 — `selectedBranchId` 등 빈번 변경값 / 정적값(user 프로필, logout) 별도 Context |
| P1 | `ANALYZE=true npm run build` 실행 → Top 10 청크 분석 → 추가 스플리팅 대상 선정 |
| P1 | Next.js 13.3.2 → 14.x 업그레이드 검토 (App Router, Server Components 도입) |
| P2 | PostgreSQL slow query 분석 (목록 API ≤ 100ms 목표) |
| P2 | Docker 이미지 multi-stage build 최적화 |

---

*작성: Claude Sonnet 4.6 | 2026-04-15*
