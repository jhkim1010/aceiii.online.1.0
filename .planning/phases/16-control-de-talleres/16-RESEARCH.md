# Phase 16: Control de Talleres — Research

**Researched:** 2026-04-13
**Domain:** UI 리팩토링 — NestJS subcon 백엔드 + Next.js/MUI 프론트엔드 탭 통합 리디자인
**Confidence:** HIGH (기존 코드베이스 직접 분석, 외부 라이브러리 없음)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** 단일 진입점 + 상단 탭 네비게이션으로 7개 화면 통합 (Dashboard, Pipeline, Talleres, Lotes, Envíos, Liquidaciones, Etapas)
- **D-02:** 기존 pages/talleres/ 라우트는 유지하되 메인 탭 페이지에서 shallow routing으로 전환
- **D-03:** UI 토글 ON 시에만 새 탭 UI 활성화, OFF 시 기존 페이지 유지
- **D-04:** Pipeline(Kanban)은 읽기 전용 시각화 — 드래그&드롭 없음
- **D-05:** 공정 단계별 컬럼에 현재 진행 중인 로트/발송 카드 표시
- **D-06:** 개별 로트 선택 시 공정 진행도(원형 노드 플로우) 시각화
- **D-07:** 테이블 + 확장 행 패턴 — 행 클릭 시 확장되어 상세 통계(보유량, 채무, 이행률, 평점, 용량) 표시
- **D-08:** 필터: 상태(활성/비활성), 담당 공정별
- **D-09:** 우측 420px 드로어 — 수량 분포(가용/재고/완료) + 공정 진행도 + 타임라인
- **D-10:** 테이블에서 행 클릭 시 드로어 오픈
- **D-11:** 새 `/talleres/dashboard/stats` 통합 API 추가 — KPI(총 보유량, 활성 업체, 오픈 로트, 지연건) + 업체별 분포 + 채무 요약 + 최근 이동을 한 번에 응답
- **D-12:** 기존 CRUD API 변경 없음
- **D-13:** Wave 1: Dashboard + Pipeline 우선 구현
- **D-14:** Wave 2: Talleres(테이블+확장행) + Lotes(드로어) + Envíos
- **D-15:** Wave 3: Liquidaciones + Etapas(단가 매트릭스)

### Claude's Discretion
- 컴포넌트 분리 세부 구조 (Phase 15 패턴 따라 components/ 활용)
- 탭 상태 관리 방식 (URL query vs local state)
- 테이블 확장 행 애니메이션/트랜지션
- Dashboard 통합 API 내부 쿼리 최적화 (CTE/JOIN 구조)

### Deferred Ideas (OUT OF SCOPE)
- 드래그&드롭 Pipeline (Phase 17 Portal에서 검토)
- 업체별 성과 리포트/그래프 (Reportajes 확장으로)
- 자재 연동 입출고 (Phase 15 materia-prima와 cross-link)
</user_constraints>

---

## Summary

Phase 16은 기존 talleres 7개 분리 페이지를 단일 탭 UI로 통합하는 UI 리팩토링 작업이다. 백엔드 CRUD는 그대로 유지하고 Dashboard용 통합 API 1개만 추가한다. 기술적으로 새 라이브러리가 거의 불필요하며, 이미 코드베이스에 존재하는 MUI 컴포넌트(Tabs, Drawer, Collapse, Box)와 Phase 15의 KpiCard 패턴을 재활용한다.

핵심 복잡도는 세 가지다: (1) 7개 탭 통합 + UI 토글 D-03 로직, (2) Dashboard 통합 API가 5개 테이블을 단일 쿼리 묶음으로 집계하는 구조, (3) Pipeline Kanban을 순수 CSS flexbox로 구현하고 etapa-flow 원형 노드를 렌더링하는 프론트엔드 레이아웃. 드래그&드롭이나 외부 차트 라이브러리는 없으므로 위험 요소가 낮다.

**Primary recommendation:** Phase 15 컴포넌트 패턴(KpiCard, CSS 바 차트, components/ 분리)을 그대로 복제하되, 탭 상태는 `?tab=dashboard` URL query로 관리하여 페이지 새로고침/북마크를 지원한다. 통합 API는 Sequelize의 개별 쿼리 4~5개를 `Promise.all()`로 병렬 실행하는 방식이 CTE보다 단순하고 안전하다.

---

## Standard Stack

### Core (이미 프로젝트에 설치됨)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MUI (`@mui/material`) | 5.x | Tabs, Drawer, Collapse, Box | 프로젝트 표준 UI 라이브러리 [VERIFIED: 코드베이스 직접 확인] |
| `@iconify/react` | 최신 | 탭 아이콘, KPI 아이콘 | 기존 코드 전체에서 사용 [VERIFIED: 코드베이스] |
| `apiConnector` | — | GET/POST API 호출 | 프로젝트 표준 (`src/services/api.service.ts`) [VERIFIED] |
| `useAuth()` | — | storeId 접근 | 프로젝트 표준 훅 [VERIFIED] |
| Sequelize + sequelize-typescript | — | 백엔드 ORM | `underscored: true` 전역 설정 주의 [VERIFIED] |
| `react-hot-toast` | — | 사용자 피드백 | 프로젝트 표준 [VERIFIED: CONVENTIONS.md] |

### 새로 필요한 라이브러리
없음. 모든 UI 컴포넌트가 MUI에 이미 존재한다. Pipeline과 etapa-flow는 순수 CSS로 구현 (D-04, D-06 결정).

---

## Architecture Patterns

### 권장 파일 구조

```
ventago-app/src/
├── pages/talleres/
│   └── index.tsx                    # 단일 진입점 (탭 라우터 역할, UI 토글 감지)
│
├── views/talleres/
│   ├── TalleresMainView.tsx          # 탭 컨테이너 (7개 탭 조립)
│   ├── components/                   # Phase 15 패턴 복제
│   │   ├── KpiCard.tsx               # Phase 15 KpiCard 동일 패턴 (색상 확장)
│   │   ├── CssBarChart.tsx           # CSS-only 바 차트 (mockup .bar-chart)
│   │   ├── EtapaFlowVisual.tsx       # 원형 노드 플로우 (mockup .etapa-flow)
│   │   ├── PipelineKanban.tsx        # 읽기 전용 Kanban (mockup .pipeline)
│   │   └── OverdueAlertList.tsx      # 지연 알림 목록 (mockup .overdue-item)
│   │
│   ├── tabs/
│   │   ├── DashboardTab.tsx          # Wave 1
│   │   ├── PipelineTab.tsx           # Wave 1
│   │   ├── TalleresTab.tsx           # Wave 2 (확장 행 테이블)
│   │   ├── LotesTab.tsx              # Wave 2 (420px Drawer)
│   │   ├── EnviosTab.tsx             # Wave 2
│   │   ├── LiquidacionesTab.tsx      # Wave 3
│   │   └── EtapasTab.tsx             # Wave 3 (단가 매트릭스)
│   │
│   └── drawers/
│       ├── LoteDetailDrawer.tsx      # 420px 우측 Drawer (D-09)
│       └── VendorExpandedRow.tsx     # 확장 행 내용 (D-07)

api-ventago/src/app/subcon/
└── dashboard/                        # 신규 (D-11)
    ├── dashboard.controller.ts
    └── dashboard.service.ts
    (subcon.module.ts에 등록 필요)
```

### Pattern 1: 탭 통합 — URL Query 기반 상태 관리

**What:** Next.js Pages Router의 `router.query.tab`으로 현재 탭을 관리한다.
**When to use:** shallow routing으로 URL을 갱신하여 북마크와 새로고침을 지원.

```typescript
// Source: [VERIFIED: Next.js Pages Router 패턴, 프로젝트 전반 사용]
import { useRouter } from 'next/router'

const TalleresMainView = () => {
  const router = useRouter()
  const activeTab = (router.query.tab as string) || 'dashboard'

  const handleTabChange = (_: React.SyntheticEvent, newTab: string) => {
    router.push({ query: { ...router.query, tab: newTab } }, undefined, { shallow: true })
  }

  return (
    <Box>
      <Tabs value={activeTab} onChange={handleTabChange}>
        <Tab label='Dashboard' value='dashboard' icon={<Icon icon='tabler:chart-bar' />} iconPosition='start' />
        <Tab label='Pipeline' value='pipeline' icon={<Icon icon='tabler:layout-kanban' />} iconPosition='start' />
        {/* ... 7개 탭 */}
      </Tabs>
      {activeTab === 'dashboard' && <DashboardTab />}
      {activeTab === 'pipeline' && <PipelineTab />}
      {/* ... */}
    </Box>
  )
}
```

### Pattern 2: UI 토글 (D-03) — 기존 패턴 재사용

**What:** Phase 01에서 구축한 `UiModeProvider` + `useUiMode()` 훅을 활용한다.
**When to use:** 각 talleres 페이지에서 uiMode를 확인하고 조건부 렌더링.

```typescript
// Source: [VERIFIED: Phase 01-ui-ux 패턴, pages/talleres/control/index.tsx 참조]
// pages/talleres/index.tsx (신규 통합 진입점)
import { useUiMode } from 'src/context/UiModeContext'
import TalleresMainView from 'src/views/talleres/TalleresMainView'
import Talleres_ControlPanel from 'src/views/talleres/control/talleres_ControlPanel'

const TalleresPage = () => {
  const { uiMode } = useUiMode()

  if (uiMode === 'new') {
    return <TalleresMainView />
  }

  return <Talleres_ControlPanel />
}
```

**주의:** 기존 7개 pages/talleres/{subpage}/index.tsx 파일은 유지되어야 한다 (D-02). 신규 `pages/talleres/index.tsx`만 추가한다.

### Pattern 3: MUI Collapse — 확장 행 (D-07)

**What:** FullTable의 DataGrid를 사용하지 않고, MUI의 기본 Table + Collapse를 조합한다. DataGrid는 행 내부 Collapse를 지원하지 않는다.
**When to use:** Talleres 탭에서 vendor 행 클릭 시 상세 통계 표시.

```typescript
// Source: [VERIFIED: MUI 5 Table + Collapse 패턴]
import { Table, TableRow, TableCell, Collapse, Box } from '@mui/material'

const TalleresTab = () => {
  const [expandedId, setExpandedId] = useState<number | null>(null)

  const handleRowClick = (id: number) => {
    setExpandedId(prev => prev === id ? null : id)
  }

  return (
    <Table>
      <TableBody>
        {vendors.map(vendor => (
          <React.Fragment key={vendor.id}>
            <TableRow hover onClick={() => handleRowClick(vendor.id)} sx={{ cursor: 'pointer' }}>
              {/* 기본 컬럼들 */}
            </TableRow>
            <TableRow>
              <TableCell colSpan={7} sx={{ py: 0 }}>
                <Collapse in={expandedId === vendor.id} timeout='auto' unmountOnExit>
                  <VendorExpandedRow vendor={vendor} />
                </Collapse>
              </TableCell>
            </TableRow>
          </React.Fragment>
        ))}
      </TableBody>
    </Table>
  )
}
```

**주의:** `expandedId === vendor.id ? null : id` 토글 로직으로 하나만 열리게 한다. 여러 행 동시 확장은 사용자가 요구하지 않았다.

### Pattern 4: 420px Drawer — Lote 상세 (D-09)

**What:** 기존 LotesListView에 이미 Drawer가 구현되어 있다 (width 600px). 이를 420px로 변경하고 mockup 디자인을 적용한다.

```typescript
// Source: [VERIFIED: 기존 talleres_LotesListView.tsx 내 Drawer 구현]
<Drawer
  anchor='right'
  open={openDetail}
  onClose={() => setOpenDetail(false)}
  sx={{ '& .MuiDrawer-paper': { width: { xs: '100%', md: 420 } } }}
>
  <LoteDetailDrawer loteStatus={loteStatus} onClose={() => setOpenDetail(false)} />
</Drawer>
```

### Pattern 5: Dashboard 통합 API — 서비스 구조 (D-11)

**What:** `/talleres/dashboard/stats` 단일 엔드포인트로 5개 데이터셋을 반환.
**Why:** 기존 Dashboard는 2개 API를 호출하지만, 목업은 4개 섹션(KPI, 분포, 채무, 최근 이동)을 요구한다.

```typescript
// Source: [VERIFIED: 기존 EnvioService.getVendorPendingSummary 패턴 + 코드베이스 분석]
// dashboard.service.ts
async getDashboardStats(storeId: number) {
  // Promise.all로 병렬 실행 — CTE보다 단순하고 Sequelize와 호환성 우수
  const [kpi, vendorDistribution, debtSummary, recentMovements] = await Promise.all([
    this.getKpiStats(storeId),           // 총 보유량, 활성 업체, 오픈 로트, 지연건
    this.getVendorDistribution(storeId), // 업체별 보유 수량 (Bar chart용)
    this.getDebtSummary(storeId),        // 업체별 미정산 채무
    this.getRecentMovements(storeId),    // 최근 envios + recepciones (날짜순 혼합)
  ])

  return { kpi, vendorDistribution, debtSummary, recentMovements }
}
```

**응답 구조 (프론트엔드 인터페이스):**
```typescript
interface DashboardStats {
  kpi: {
    totalUnitsInTalleres: number    // 활성 envios의 pendingQuantity 합계
    activeTalleres: number          // isActive=true 업체 수
    openLotes: number               // status=OPEN|IN_PROGRESS 로트 수
    overdueEnvios: number           // dueDate < today && status=PENDING|PARTIAL 수
  }
  vendorDistribution: Array<{
    vendorId: number
    vendorName: string
    pendingQuantity: number
    percentage: number
  }>
  debtSummary: Array<{
    vendorId: number
    vendorName: string
    totalDebt: number               // 미정산 settlements의 netAmount 합계
  }>
  recentMovements: Array<{
    date: string
    type: 'ENVIO' | 'RECEPCION'
    loteNumber: string
    vendorName: string
    etapaName: string
    quantity: number
  }>
}
```

### Pattern 6: Pipeline Kanban — 순수 CSS Flexbox (D-04, D-05)

**What:** 목업의 `.pipeline` + `.pipeline-stage` + `.pipeline-item` CSS를 MUI Box/sx로 변환.
**When to use:** MUI Kanban 라이브러리 없이 구현 (라이브러리 없음 결정).

```typescript
// Source: [VERIFIED: 목업 talleres-mockup.html .pipeline 섹션]
const PipelineKanban = ({ stages }: { stages: PipelineStage[] }) => (
  <Box sx={{ display: 'flex', gap: 2, overflowX: 'auto', pb: 1 }}>
    {stages.map(stage => (
      <Box
        key={stage.etapaId}
        sx={{
          minWidth: 200,
          flex: 1,
          borderRadius: '10px',
          border: '1px solid #e0e0e0',
          borderTop: `3px solid ${stage.color}`,
          bgcolor: 'background.paper',
          boxShadow: '0 2px 8px rgba(0,0,0,0.06)'
        }}
      >
        {/* stage header + items */}
      </Box>
    ))}
  </Box>
)
```

### Anti-Patterns to Avoid

- **DataGrid로 확장 행 구현:** MUI DataGrid는 행 내부 Collapse를 공식 지원하지 않는다. Talleres 탭은 기본 MUI Table을 사용해야 한다.
- **별도 Kanban 라이브러리 설치 (`react-beautiful-dnd` 등):** D-04에서 드래그&드롭 없음으로 결정됨. 순수 CSS flexbox로 충분하다.
- **Dashboard API에서 N+1 쿼리:** `getVendorDistribution`은 업체별 루프 대신 GROUP BY 집계 쿼리 사용.
- **탭 상태를 로컬 state로만 관리:** 페이지 새로고침 시 탭이 리셋된다. URL query(`?tab=dashboard`) 사용.
- **프론트엔드 ESLint 위반:** `no-unused-vars`, `newline-before-return`, `lines-around-comment` 규칙 준수 필수 — 빌드 블로킹 에러.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 탭 UI | 커스텀 탭 컴포넌트 | `MUI Tabs + Tab` | 접근성(aria), 키보드 탐색 자동 처리 |
| 오른쪽 패널 Drawer | CSS position:fixed | `MUI Drawer anchor='right'` | 스크롤 잠금, 오버레이, 애니메이션 내장 |
| 확장 행 애니메이션 | CSS max-height 트릭 | `MUI Collapse` | height 애니메이션 자동 처리 |
| 상태 칩 (Chip) | `<span style>` | `MUI Chip color=...` | 기존 statusConfig 패턴과 일관성 |
| KPI 카드 | 새 컴포넌트 | `Phase 15 KpiCard` 복제 | 상단 3px 컬러바 패턴 이미 구현됨 |
| 바 차트 | Chart.js / ApexCharts | CSS-only `.bar-chart` | 목업 지시사항, 라이브러리 불필요 |
| 진행도 플로우 | react-flow 등 라이브러리 | CSS `.etapa-flow` 노드 | 읽기 전용 단순 시각화, 오버엔지니어링 방지 |

**Key insight:** 이 Phase는 외부 라이브러리 추가 없이 MUI 기본 컴포넌트 + CSS-only 시각화로 완전 구현 가능하다. 목업이 이미 CSS-first 접근을 보여준다.

---

## Common Pitfalls

### Pitfall 1: FullTable(DataGrid) vs MUI Table 선택 오류
**What goes wrong:** Talleres 탭 확장 행을 FullTable(DataGrid 래퍼)로 구현하려다 실패.
**Why it happens:** 기존 VendorsListView가 FullTable을 사용하므로 동일하게 쓰려 한다.
**How to avoid:** MUI DataGrid는 행 내부에 Collapse를 렌더링하는 공식 API가 없다. `<Table>` + `<Collapse>` 패턴으로 전환.
**Warning signs:** expandedRow prop이 없는 DataGrid를 사용하려 할 때.

### Pitfall 2: 기존 pages 라우트와 신규 통합 페이지 충돌
**What goes wrong:** `pages/talleres/index.tsx`를 추가하면 `/talleres/control`, `/talleres/vendors` 등 기존 라우트가 사라지거나 충돌.
**Why it happens:** Next.js Pages Router에서 `pages/talleres/index.tsx`는 `/talleres`만 담당하고 `pages/talleres/control/index.tsx`는 `/talleres/control`을 계속 담당한다 — 충돌 없음.
**How to avoid:** 신규 진입점은 `pages/talleres/index.tsx` (새 파일)만 추가. 기존 7개 페이지 파일은 수정하지 않는다.
**Warning signs:** 기존 `/talleres/control` URL이 404를 반환하면 파일 경로 충돌.

### Pitfall 3: Dashboard API — 채무(Debt) 데이터 출처 오해
**What goes wrong:** 채무 요약을 `talleres_envios.pendingQuantity × vendorEtapa.unitPrice`로 계산하려 한다.
**Why it happens:** 직관적으로 보이지만, 실제 채무는 `talleres_settlements` 테이블의 `netAmount`(미결 정산)이다.
**How to avoid:** `SubconSettlement`의 `status='OPEN'`이고 `netAmount - 지불금액`이 실제 채무다. `SubconPayment`로 기지불액을 차감.
**Warning signs:** 채무 숫자가 단가 데이터 없는 업체에서 0으로 나타날 때.

### Pitfall 4: ESLint 빌드 에러 (프론트엔드)
**What goes wrong:** 로컬 개발에서 문제 없지만 Jenkins 빌드 실패.
**Why it happens:** `no-unused-vars`, `newline-before-return`, `lines-around-comment` 규칙이 warning이 아닌 error.
**How to avoid:** import한 모든 변수 사용, return 위 빈 줄, 주석 위 빈 줄 확인. 작업 후 ESLint subagent 점검 필수.
**Warning signs:** `error  'XXX' is defined but never used` 메시지.

### Pitfall 5: Sequelize underscored 컬럼 — Dashboard 집계 쿼리
**What goes wrong:** 원시 SQL 집계에서 `vendorId` 대신 `vendor_id`를 사용하지 않아 쿼리 실패.
**Why it happens:** `underscored: true` 전역 설정으로 DB 컬럼은 snake_case.
**How to avoid:** Sequelize `findAll` + `group` 옵션 사용 시 모델 속성명(camelCase) 사용. 원시 SQL 시 snake_case 명시.

### Pitfall 6: UI 토글 — UiModeContext 없이 접근
**What goes wrong:** `useUiMode()` 훅이 undefined를 반환.
**Why it happens:** `UiModeProvider`는 `AuthProvider` 내부에 있어야 한다 (Phase 01 결정).
**How to avoid:** Phase 01 결정 준수 — `UiModeProvider`는 이미 AuthProvider 내부에 위치. 별도 Provider 추가 불필요.

---

## Code Examples

### 1. KpiCard — Phase 15 패턴 (talleres 색상 추가)
```typescript
// Source: [VERIFIED: ventago-app/src/views/materia-prima/components/KpiCard.tsx]
// talleres용 colors 확장 예시
const TALLER_KPI_COLORS = {
  purple: '#7C4DFF',  // 보유량 (mockup .kpi-card.purple)
  blue:   '#2196F3',  // 활성 업체
  green:  '#4CAF50',  // 오픈 로트
  red:    '#F44336',  // 지연건
  orange: '#FF9800',  // 추가 지표
  teal:   '#009688',  // 추가 지표
} as const
```

### 2. CSS 바 차트 — MUI Box 구현
```typescript
// Source: [VERIFIED: 목업 .bar-chart + Phase 15 CategoryDistributionChart.tsx 패턴]
const CssBarChart = ({ items, maxValue }: { items: BarItem[], maxValue: number }) => (
  <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
    {items.map(item => (
      <Box key={item.label} sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Typography sx={{ width: 100, fontSize: 12, textAlign: 'right', flexShrink: 0 }}>
          {item.label}
        </Typography>
        <Box sx={{ flex: 1, height: 20, bgcolor: '#f0f0f0', borderRadius: '4px', overflow: 'hidden', position: 'relative' }}>
          <Box
            sx={{
              width: `${(item.value / maxValue) * 100}%`,
              height: '100%',
              bgcolor: item.color,
              borderRadius: '4px',
              display: 'flex', alignItems: 'center', pl: 1
            }}
          >
            <Typography sx={{ fontSize: 10, fontWeight: 600, color: '#fff', whiteSpace: 'nowrap' }}>
              {item.valueLabel}
            </Typography>
          </Box>
        </Box>
        <Typography sx={{ width: 50, fontSize: 12, fontWeight: 600, textAlign: 'right', flexShrink: 0 }}>
          {item.pctLabel}
        </Typography>
      </Box>
    ))}
  </Box>
)
```

### 3. Etapa Flow Visual (원형 노드)
```typescript
// Source: [VERIFIED: 목업 .etapa-flow + .etapa-circle 섹션]
const EtapaFlowVisual = ({ etapas, loteEnvios }: EtapaFlowProps) => (
  <Box sx={{ display: 'flex', alignItems: 'center', overflowX: 'auto', py: 1.5 }}>
    {etapas.map((etapa, idx) => {
      const enviosForEtapa = loteEnvios.filter(e => e.etapaId === etapa.id)
      const inTaller = enviosForEtapa.reduce((s, e) => s + e.pendingQuantity, 0)
      const isDone = enviosForEtapa.some(e => e.status === 'COMPLETED') && inTaller === 0
      const isActive = inTaller > 0

      return (
        <React.Fragment key={etapa.id}>
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', minWidth: 100 }}>
            <Box
              sx={{
                width: 48, height: 48, borderRadius: '50%',
                border: `3px solid ${isDone ? '#4CAF50' : isActive ? '#7C4DFF' : '#e0e0e0'}`,
                bgcolor: isDone ? '#4CAF50' : isActive ? '#ede7f6' : '#fff',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: isDone ? 18 : 14, fontWeight: 700,
                color: isDone ? '#fff' : isActive ? '#7C4DFF' : '#9e9e9e'
              }}
            >
              {isDone ? '✓' : inTaller || ''}
            </Box>
            <Typography sx={{ fontSize: 11, mt: 0.75, fontWeight: 500, color: 'text.secondary', textAlign: 'center' }}>
              {etapa.name}
            </Typography>
          </Box>
          {idx < etapas.length - 1 && (
            <Typography sx={{ fontSize: 18, color: '#e0e0e0', mx: 0.5, mb: 2.25 }}>→</Typography>
          )}
        </React.Fragment>
      )
    })}
  </Box>
)
```

### 4. 백엔드 Dashboard Controller
```typescript
// Source: [VERIFIED: 기존 EnvioController 패턴]
// dashboard.controller.ts
@Controller('talleres/dashboard')
@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.vendedor, ValidRoles.gerente)
export class TalleresDashboardController {
  constructor(private readonly dashboardService: TalleresDashboardService) {}

  @Get('stats')
  async getStats(@GetUser() user: Users) {
    return this.dashboardService.getDashboardStats(user.storeId!);
  }
}
```

### 5. Dashboard KPI 쿼리 — Sequelize 집계
```typescript
// Source: [VERIFIED: 기존 EnvioService.getVendorPendingSummary 패턴]
// getKpiStats 구현 예시
private async getKpiStats(storeId: number) {
  const [totalUnits, activeVendors, openLotes, overdueCount] = await Promise.all([
    // pendingQuantity 합계 (PENDING|PARTIAL 발송만)
    this.envioModel.sum('pendingQuantity', {
      where: { storeId, status: { [Op.in]: ['PENDING', 'PARTIAL'] } }
    }),
    this.vendorModel.count({ where: { storeId, isActive: true } }),
    this.loteModel.count({
      where: { storeId, status: { [Op.in]: ['OPEN', 'IN_PROGRESS'] } }
    }),
    this.envioModel.count({
      where: {
        storeId,
        status: { [Op.in]: ['PENDING', 'PARTIAL'] },
        dueDate: { [Op.lt]: new Date() }
      }
    }),
  ]);

  return {
    totalUnitsInTalleres: totalUnits || 0,
    activeTalleres: activeVendors,
    openLotes,
    overdueEnvios: overdueCount,
  };
}
```

---

## Existing Code Reuse Map

| 기존 파일 | 재사용 방식 |
|-----------|------------|
| `talleres_ControlPanel.tsx` | DashboardTab의 기반. 로직 참조, UI 교체 |
| `talleres_VendorsListView.tsx` | TalleresTab 기반. FullTable → MUI Table로 전환 |
| `talleres_LotesListView.tsx` | LotesTab 기반. Drawer width 600→420, 디자인 교체 |
| `talleres_EnviosListView.tsx` | EnviosTab 기반. 필터 추가 |
| `materia-prima/components/KpiCard.tsx` | 직접 복제 또는 import (색상 확장) |
| `envio.controller.ts` (dashboard/vendor-pending, dashboard/overdue) | 신규 dashboard/stats로 통합 — 기존 유지 |
| `SubconModule` | dashboard controller/service 추가 등록 |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 분리된 7개 페이지 | 단일 탭 통합 | Phase 16 | 탭 진입점 1개, 기존 URL 유지 |
| 2개 Dashboard API | 1개 통합 stats API | Phase 16 | 네트워크 요청 감소, 캐시 용이 |
| 600px Drawer (Lotes) | 420px Drawer | Phase 16 | 목업 지시사항 |
| Dashboard 카드 중심 | KPI + 바 차트 + 타임라인 | Phase 16 | 정보 밀도 향상 |

---

## Integration Points

### 기존 API (변경 없음, D-12)
| Endpoint | Controller | 용도 |
|----------|-----------|------|
| `GET /talleres/vendors/all` | VendorController | TalleresTab 목록 |
| `GET /talleres/lotes/all` | LoteController | LotesTab 목록 |
| `GET /talleres/lotes/:id/status` | LoteController | LoteDetailDrawer 데이터 |
| `GET /talleres/envios/all` | EnvioController | EnviosTab 목록 |
| `GET /talleres/etapas/all` | EtapaController | Pipeline용 etapa 목록 |
| `GET /talleres/envios/dashboard/vendor-pending` | EnvioController | (신규 stats API에 통합) |
| `GET /talleres/envios/dashboard/overdue` | EnvioController | (신규 stats API에 통합) |

### 신규 API (D-11)
| Endpoint | Controller | 용도 |
|----------|-----------|------|
| `GET /talleres/dashboard/stats` | TalleresDashboardController (신규) | Dashboard 통합 데이터 |

### Pipeline Kanban 데이터 흐름
Pipeline은 기존 API 조합으로 구성된다:
1. `GET /talleres/etapas/all` → 컬럼(etapa) 목록
2. `GET /talleres/envios/all?status=PENDING,PARTIAL` → 각 컬럼의 카드(envio) 목록
- 별도 Pipeline API 불필요 (클라이언트에서 etapaId 기준으로 그룹핑)

---

## Open Questions

1. **Talleres 탭 디자인: 카드 그리드 vs 테이블 확장 행**
   - 목업(talleres-mockup.html PAGE 3)은 카드 그리드 레이아웃을 보여준다 (`.vendor-card` CSS)
   - D-07 결정은 "테이블 + 확장 행"이다
   - **해석:** 두 스타일이 충돌한다. D-07이 locked decision이므로 테이블 확장 행을 우선 구현한다. 목업 카드 스타일의 통계 섹션(보유량, 채무, 이행률, 평점)을 확장 행 내부에 표시하는 방식으로 조화.

2. **Pipeline 데이터 — 선택된 로트 vs 전체 뷰**
   - D-06: "개별 로트 선택 시 공정 진행도 시각화"
   - 목업 PAGE 2: 상단에 선택된 로트의 etapa-flow, 하단에 전체 Pipeline Kanban
   - **해석:** Pipeline 탭은 두 섹션을 가진다 — (a) 선택 로트 etapa-flow, (b) 전체 kanban. 기본값은 첫 번째 IN_PROGRESS 로트를 선택.

3. **채무(Deuda) 계산 출처**
   - `SubconSettlement.netAmount` (정산 기록)으로 집계하는 것이 정확하다
   - 하지만 `SubconOrder`를 거치지 않은 envio/recepcion 방식의 새 워크플로우(Phase 15 이후)는 settlement와 연결이 다를 수 있다
   - **권고:** `talleres_settlements` 테이블에서 `status='OPEN'` 레코드의 `netAmount` 합계를 vendor별로 GROUP BY. 데이터 없으면 0 반환.

---

## Environment Availability

Step 2.6: SKIPPED — 이 Phase는 코드/UI 변경만이며, 새로운 외부 도구/서비스 의존성이 없다. 기존 PostgreSQL, Docker, Next.js, NestJS 환경 그대로 사용.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | 없음 (프로젝트에 자동화 테스트 미구축) |
| Quick run | ESLint: `cd ventago-app && npx next lint` |
| Build check | `cd ventago-app && npm run build` |
| API check | Docker exec 직접 쿼리 검증 |

### Phase 요구사항 → 검증 매핑
| 검증 항목 | 방법 | 자동화 |
|----------|------|--------|
| Dashboard KPI 숫자 정확성 | DB 직접 쿼리와 API 응답 비교 | 수동 |
| 탭 URL 라우팅 (`?tab=pipeline`) | 브라우저 새로고침 후 탭 유지 확인 | 수동 |
| UI 토글 ON/OFF 전환 | 사이드바 토글 클릭 후 구 UI / 신 UI 확인 | 수동 |
| ESLint 통과 | `npx next lint` | 자동 (CI) |
| 프로덕션 빌드 | `npm run build` | 자동 (CI) |

---

## Project Constraints (from CLAUDE.md)

| 제약 | 내용 |
|------|------|
| ESLint build-blocking rules | `no-unused-vars`, `newline-before-return`, `lines-around-comment` — 위반 시 빌드 실패 |
| apiConnector | `.delete()` 아닌 `.remove()` 사용 |
| 주석 언어 | 한국어 |
| 변수/함수명 | 영어 |
| DB 컬럼 | Sequelize underscored:true → 원시 SQL 시 snake_case |
| 파일 경로 alias | `src/` prefix 사용, `@/` 없음 |
| 프론트엔드 상태 | Redux 최소, 대부분 로컬 state + apiConnector |
| 에러 핸들링 | try/catch 항상 포함, toast.error() |
| ESLint subagent | 프론트 작업 후 반드시 ESLint 점검 |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `useUiMode()` 훅이 이미 존재하고 `uiMode === 'new'` 값을 반환한다 | Integration Points | 훅 미존재 시 D-03 구현 방식 변경 필요 |
| A2 | `SubconSettlement`의 `status='OPEN'` 레코드가 채무 집계에 충분하다 | Pitfall 3 | 정산 데이터가 거의 없다면 Dashboard 채무 섹션이 빈 상태 |
| A3 | Pipeline 탭은 `/talleres/envios/all` API를 클라이언트에서 etapaId로 그룹핑하여 구성 가능하다 | Integration Points | 데이터 양이 많을 때 서버사이드 집계 필요 가능성 |

[ASSUMED] A1 — `useUiMode` 훅 API 시그니처를 Phase 01 코드에서 직접 확인하지 않음. Phase 01 작업 기록에서 존재가 언급됨.

---

## Sources

### Primary (HIGH confidence — 코드베이스 직접 확인)
- `ventago-app/src/views/talleres/control/talleres_ControlPanel.tsx` — 현재 Dashboard 구현
- `ventago-app/src/views/talleres/vendors/talleres_VendorsListView.tsx` — 현재 Vendors 구현
- `ventago-app/src/views/talleres/lotes/talleres_LotesListView.tsx` — 현재 Lotes + Drawer 구현
- `api-ventago/src/app/subcon/subcon.module.ts` — 모듈 전체 구조
- `api-ventago/src/app/subcon/envios/envio.controller.ts` — 기존 dashboard API 2개
- `api-ventago/src/app/subcon/envios/envio.service.ts` — createEnvio, getVendorPendingSummary 패턴
- `api-ventago/src/app/subcon/lotes/lote.model.ts` — LoteStatus enum
- `api-ventago/src/app/subcon/envios/envio.model.ts` — EnvioStatus enum
- `api-ventago/src/app/subcon/vendors/vendor.model.ts` — Vendor 필드
- `api-ventago/src/app/subcon/etapas/etapa.model.ts` — Etapa 구조
- `api-ventago/src/app/subcon/vendor-etapas/vendor-etapa.model.ts` — VendorEtapa (단가)
- `api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.model.ts` — Settlement 구조
- `.planning/phases/16-control-de-talleres/talleres-mockup.html` — 전체 UI 목업 직접 분석
- `ventago-app/src/views/materia-prima/components/KpiCard.tsx` — Phase 15 KpiCard 패턴
- `ventago-app/src/views/materia-prima/components/constants.ts` — KPI_COLORS 패턴
- `.planning/codebase/CONVENTIONS.md` — 프로젝트 코딩 컨벤션

### Secondary (MEDIUM confidence)
- `.planning/phases/16-control-de-talleres/16-CONTEXT.md` — 사용자 결정사항
- `.planning/STATE.md` — Phase 01 UI 토글 시스템 확인

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 기존 코드베이스 전체 분석
- Architecture patterns: HIGH — 목업 HTML 직접 분석 + 기존 코드 참조
- Pitfalls: HIGH — 코드베이스에서 실제 패턴/제약 확인
- Dashboard API 집계: MEDIUM — SubconSettlement 데이터 실제 존재 여부 미확인

**Research date:** 2026-04-13
**Valid until:** 2026-05-13 (안정적 스택, 30일 유효)
