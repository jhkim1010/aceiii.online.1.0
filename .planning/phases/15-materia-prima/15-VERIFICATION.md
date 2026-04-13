---
phase: 15-materia-prima
verified: 2026-04-12T14:00:00Z
status: human_needed
score: 11/13 must-haves verified
overrides_applied: 0
gaps: []
deferred:
  - truth: "BOM과 연동하여 제품별 원자재 소요량 기반 원가 계산 (SC9)"
    addressed_in: "Phase 7 (Fábrica)"
    evidence: "15-CONTEXT.md deferred section: 'BOM 연동 원가 계산 (별도 phase 또는 Phase 7 Fabrica에서)'"
human_verification:
  - test: "Open Inventario page and filter by Tela category — verify extra attributes (color, origin) appear in card subtitle"
    expected: "Cards in the Tela category show 'COD · Tela · Color: X · Origen: Y' format under material name"
    why_human: "MaterialCard.getCodeLine shows correct pattern in code but requires real backend data with color/origin fields populated to confirm display"
  - test: "Open Dashboard and confirm CategoryDistributionChart and DebtSummaryChart render with data"
    expected: "Category distribution shows colored vertical bars per category; debt summary shows horizontal red bars per supplier"
    why_human: "These charts use optional fields (distribucionCategoria, deudaPorProveedor) with empty-array fallback — backend may not return them yet, resulting in empty charts. Needs runtime verification."
  - test: "Open MovimientosView, click Salida, select a WorkOrder from the dropdown, verify reference auto-fills"
    expected: "Reference field shows 'OT-{workOrderId}' after selecting a work order, but can still be edited manually"
    why_human: "WorkOrder state and handleWorkOrderSelect logic exists in code, but requires /mes/work-orders to return data"
---

# Phase 15: Materia Prima Control — Verification Report

**Phase Goal:** 의류 소형 생산업자를 위한 원자재(Materia Prima) 입고·사용·잔고 관리 + 공급자 대금 관리 시스템. 카드형 대시보드 + 카테고리 필터(tela/boton/cierre/hilo/accesorio + 커스텀) + 간단 장부형 대금 관리. 사이드바에 독립 앱 메뉴로 추가, 허가된 사용자만 접근 가능.
**Context:** UI REFACTORING phase — plans 15-05, 15-06, 15-07. Backend already existed. Goal: refactor 5 frontend views to match HTML mockup, extract shared components, improve UX.
**Verified:** 2026-04-12
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from Roadmap Success Criteria + Plan must-haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Dashboard KPI cards (Total Materiales, Stock Bajo, Valor Inventario, Deuda Proveedores) use shared KpiCard with 3px top indicators | VERIFIED | MateriaPrimaDashboardView.tsx imports KpiCard, renders 4 instances with color='blue/orange/green/red'. KpiCard.tsx has `height: '3px'` absolute Box. |
| 2 | Category filter chips are color-coded and toggle filled/outlined style | VERIFIED | CategoryChips.tsx imports CATEGORY_COLORS, renders Todos (purple #7C3AED when selected) + per-category chips with filled style using CATEGORY_COLORS when selected. |
| 3 | Inventario card has a 4px color bar on top matching its category color | VERIFIED | MaterialCard.tsx line 46: `<Box sx={{ height: 4, backgroundColor: categoryColor }} />`. InventarioView passes `CATEGORY_COLORS[material.categoria]`. |
| 4 | Tela materials show extra attributes (color, origin) in code line | VERIFIED (code) | MaterialCard.getCodeLine: if categoria === 'Tela', returns `${codigo} · Tela · Color: ${color} · Origen: ${origin}`. Human check needed for actual data. |
| 5 | Stock status shows colored progress bar + badge (Normal/Bajo/Agotado) + numeric text | VERIFIED | StockBar.tsx: Box-based 6px bar (not LinearProgress), Chip badge with three states, numeric `{stock} / {minStock} min.` |
| 6 | Dashboard has 2-column grid layout with charts and alerts | VERIFIED | MateriaPrimaDashboardView.tsx: two `gridTemplateColumns: { xs: '1fr', md: '1fr 1fr' }` grids with alerts+chart row, then debt+movements row. |
| 7 | Category distribution shown as CSS-only vertical bar chart | VERIFIED | CategoryDistributionChart.tsx: no chart library imports, uses Box elements with proportional heights. Container `height: '120px'`. |
| 8 | Supplier debt shown as horizontal bar chart with amounts | VERIFIED | DebtSummaryChart.tsx: horizontal Box bars with `#DC2626` color and `toLocaleString('es-CO')` formatting. |
| 9 | Dashboard alerts distinguish critical (stock=0) vs warning (stock>0 but low) | VERIFIED | MateriaPrimaDashboardView.tsx: `borderLeft: isCritical ? '4px solid #DC2626' : '4px solid #F59E0B'`, background `#FEF2F2` for critical. |
| 10 | Entrada modal includes supplier + quantity + unit price + payment status | VERIFIED | MovimientosView.tsx: Supplier Select, Cantidad, Precio Unitario, and EstadoPago (Pendiente/Pagado/Parcial) all in dialogType==='entrada' conditional blocks. |
| 11 | Salida modal supports WorkOrder dropdown OR manual reference | VERIFIED | MovimientosView.tsx: `workOrders` state, `fetchWorkOrders` from `/mes/work-orders`, `handleWorkOrderSelect` auto-fills `OT-{id}`, Reference TextField with manual placeholder. |
| 12 | ProveedoresView and PagosView use KpiCard with colored indicators | VERIFIED | ProveedoresView.tsx: 3 KpiCard instances (blue/red/green). PagosView.tsx: 3 KpiCard instances (red/green/blue). Both import from `./components/KpiCard`. |
| 13 | Supplier cards match mockup design with financial section grid and styled pay button | VERIFIED | ProveedoresView.tsx: `#DC2626` debt, `#16A34A` paid, `gridTemplateColumns: '1fr 1fr'` financials, `#7C3AED` Registrar Pago button. |

**Score:** 11/13 truths verified (2 require human verification — Tela runtime data, WorkOrder data)

---

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | BOM integration for product-level raw material cost calculation (SC9) | Phase 7 (Fábrica) | 15-CONTEXT.md deferred section: "BOM 연동 원가 계산 (별도 phase 또는 Phase 7 Fabrica에서)" |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `components/constants.ts` | CATEGORY_COLORS + KPI_COLORS exports | VERIFIED | Exports both maps with all required keys (Tela/Boton/Cierre/Hilo/Accesorio; blue/orange/green/red) |
| `components/KpiCard.tsx` | KpiCard with 3px top indicator | VERIFIED | Named export, props: label/value/color/subtitle, 3px absolute Box |
| `components/StockBar.tsx` | StockBar with bar + badge + numbers | VERIFIED | Named export, Box-based bar (no LinearProgress), three badge states |
| `components/MaterialCard.tsx` | MaterialCard with 4px color bar + Material interface | VERIFIED | Named export + Material interface export, 4px top Box, getCodeLine for Tela |
| `components/CategoryChips.tsx` | Color-coded category chips with Todos | VERIFIED | Named export, CATEGORY_COLORS import, 'Todos' chip with #7C3AED |
| `components/CategoryDistributionChart.tsx` | CSS-only vertical bar chart | VERIFIED | Named export, no chart library, CATEGORY_COLORS import, height 120px container |
| `components/DebtSummaryChart.tsx` | Horizontal bar chart with amounts | VERIFIED | Named export, #DC2626, toLocaleString |
| `MateriaPrimaDashboardView.tsx` | Refactored with 2-col grid, KpiCard, charts | VERIFIED | Imports KpiCard, CategoryDistributionChart, DebtSummaryChart; two 2-col grids |
| `InventarioView.tsx` | Uses MaterialCard, CategoryChips, CATEGORY_COLORS | VERIFIED | All three imported and used; no LinearProgress import |
| `ProveedoresView.tsx` | KpiCard + mockup supplier cards | VERIFIED | KpiCard imported, 3 instances; supplier card matches mockup spec |
| `MovimientosView.tsx` | Styled chips, D-09/D-10 modals | VERIFIED | Box inline type chips, WorkOrder dropdown, Entrada with supplier+estadoPago |
| `PagosView.tsx` | KpiCard + styled table | VERIFIED | KpiCard imported, 3 instances, table borderRadius 12px |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| MaterialCard.tsx | constants.ts | import StockBar (StockBar indirectly uses constant colors) | VERIFIED | StockBar imported on line 4 |
| InventarioView.tsx | components/MaterialCard | import MaterialCard | VERIFIED | Line 16 |
| InventarioView.tsx | components/CategoryChips | import CategoryChips | VERIFIED | Line 17 |
| InventarioView.tsx | components/constants | import CATEGORY_COLORS | VERIFIED | Line 18 |
| MateriaPrimaDashboardView.tsx | components/KpiCard | import KpiCard | VERIFIED | Line 18 |
| MateriaPrimaDashboardView.tsx | components/CategoryDistributionChart | import CategoryDistributionChart | VERIFIED | Line 19 |
| MateriaPrimaDashboardView.tsx | components/DebtSummaryChart | import DebtSummaryChart | VERIFIED | Line 20 |
| ProveedoresView.tsx | components/KpiCard | import KpiCard | VERIFIED | Line 18 |
| MovimientosView.tsx | API /materia-prima/movements | apiConnector.post | VERIFIED | Line 174 |
| PagosView.tsx | components/KpiCard | import KpiCard | VERIFIED | Line 29 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| MateriaPrimaDashboardView.tsx | `data` (DashboardData) | `apiConnector.get('/materia-prima/dashboard')` | Yes — real API fetch with storeId | FLOWING |
| InventarioView.tsx | `materials` (Material[]) | `apiConnector.get('/mes/materials')` | Yes — real API fetch | FLOWING |
| InventarioView.tsx | `categories` (Category[]) | `apiConnector.get('/materia-prima/categories/store')` | Yes — real API fetch | FLOWING |
| ProveedoresView.tsx | `suppliers` (Supplier[]) | `apiConnector.get('/suppliers')` | Yes — real API fetch | FLOWING |
| MovimientosView.tsx | `movements` (Movement[]) | `apiConnector.get('/materia-prima/movements')` | Yes — real API fetch with pagination | FLOWING |
| MovimientosView.tsx | `workOrders` (WorkOrder[]) | `apiConnector.get('/mes/work-orders')` | Yes — real API fetch (may return empty array) | FLOWING |
| PagosView.tsx | `payments` (Payment[]) | `apiConnector.get('/materia-prima/payments/store')` | Yes — real API fetch with pagination | FLOWING |
| CategoryDistributionChart.tsx | `distribution` prop | `data.distribucionCategoria \|\| []` | Conditional — depends on backend returning this optional field | PARTIAL |
| DebtSummaryChart.tsx | `debts` prop | `data.deudaPorProveedor \|\| []` | Conditional — depends on backend returning this optional field | PARTIAL |

**Note:** The two chart components (CategoryDistributionChart, DebtSummaryChart) use optional fields that fall back to `[]` if the backend doesn't return them. The SUMMARY documents this as intentional design — the backend integration for these aggregate fields was a separate concern. This does not block the UI — the components render empty state gracefully.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| MaterialCard renders 4px top color bar | Grep `height: 4` in MaterialCard.tsx | Found on line 46 | PASS |
| StockBar uses Box-based bar, not LinearProgress | Grep `LinearProgress` in StockBar.tsx | Not found | PASS |
| CategoryChips uses CATEGORY_COLORS | Grep `CATEGORY_COLORS` in CategoryChips.tsx | Found on line 3 (import) and line 34 (usage) | PASS |
| InventarioView no longer imports LinearProgress | Grep `LinearProgress` in InventarioView.tsx | Not found | PASS |
| WorkOrder fetch in MovimientosView | Grep `mes/work-orders` | Found line 135 | PASS |
| Movimientos Salida dialog has `Orden de Trabajo` | Grep `Orden de Trabajo` | Found line 481 | PASS |
| Dashboard imports all 3 shared chart/kpi components | Grep imports in MateriaPrimaDashboardView.tsx | KpiCard (18), CategoryDistributionChart (19), DebtSummaryChart (20) | PASS |
| ESLint passes for all 12 files | `npx eslint ... 2>&1` | No errors (only npm workspace warning) | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|------------|------------|-------------|--------|----------|
| MPRIMA-01 | 15-05 | Inventario card category color bar (D-01) | SATISFIED | MaterialCard.tsx 4px top color bar |
| MPRIMA-02 | 15-05 | Tela extra attributes (D-02) | SATISFIED | MaterialCard.getCodeLine Tela branch |
| MPRIMA-03 | 15-07 | ProveedoresView KpiCard + mockup supplier cards | SATISFIED | KpiCard in ProveedoresView, mockup card styling |
| MPRIMA-04 | 15-07 | MovimientosView improved modals D-09/D-10 | SATISFIED | Entrada with supplier+estadoPago, Salida with WorkOrder |
| MPRIMA-05 | 15-05, 15-06 | KpiCard component with 3px indicator (D-08) | SATISFIED | KpiCard.tsx, used in all 3 view-level files |
| MPRIMA-06 | 15-07 | PagosView KpiCard + styled table | SATISFIED | PagosView KpiCard 3 instances, borderRadius 12px table |
| MPRIMA-07 | 15-06 | Dashboard 2-col grid + CSS charts (D-05, D-06, D-07) | SATISFIED | 2-col grids, CategoryDistributionChart, DebtSummaryChart |

**Orphaned Requirements Note:** MPRIMA-01 through MPRIMA-07 are referenced in ROADMAP.md and PLAN frontmatter files but are NOT defined in `.planning/REQUIREMENTS.md`. The REQUIREMENTS.md has no MPRIMA section. These identifiers exist only in the phase planning documents. This is a traceability gap — not a functional gap.

**SC1 and SC10 (sidebar + access control):** These success criteria were addressed in earlier plans (15-01 to 15-04) and are outside the scope of the UI refactoring plans (15-05 to 15-07) being verified here. The refactoring plans explicitly state they do not change backend or auth.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| MateriaPrimaDashboardView.tsx | 203 | `data.distribucionCategoria \|\| []` fallback | Info | Chart renders empty if backend field absent — intentional design per SUMMARY Known Stubs section |
| MateriaPrimaDashboardView.tsx | 221 | `data.deudaPorProveedor \|\| []` fallback | Info | Chart renders empty if backend field absent — intentional design |

No blockers or warnings found. Empty-array fallbacks are intentional, not stubs — the components render gracefully without data.

---

### Human Verification Required

#### 1. Tela Extra Attributes at Runtime

**Test:** Go to Inventario, filter by "Tela" category. Open or view a Tela material card.
**Expected:** The code subtitle line shows "COD · Tela · Color: [value] · Origen: [value]" format under the material name.
**Why human:** MaterialCard.getCodeLine has the correct conditional logic, but the `color` and `origin` fields are optional. If the backend does not populate them for existing Tela records, the display shows `"-"` which may be acceptable. Needs confirmation against real data.

#### 2. CategoryDistributionChart and DebtSummaryChart Data

**Test:** Open Dashboard and observe the two bottom-section charts: "Distribucion por Categoria" and "Deuda por Proveedor".
**Expected:** Charts render with colored bars showing real data (not empty).
**Why human:** These charts use `distribucionCategoria` and `deudaPorProveedor` which are optional fields added to the `DashboardData` interface. If the backend `/materia-prima/dashboard` endpoint does not return these aggregated fields, the charts will show empty state. Backend integration for these fields was noted as a separate concern.

#### 3. WorkOrder Dropdown Auto-fill

**Test:** Open MovimientosView, click "Salida" button, observe the "Orden de Trabajo" dropdown. Select a work order and verify reference field auto-fills.
**Expected:** Selecting a work order from the dropdown auto-fills the Reference field with `OT-{id}`. The reference field remains editable for manual entry.
**Why human:** The `handleWorkOrderSelect` function is wired correctly, but requires `/mes/work-orders` to return actual data. If no work orders exist, the dropdown shows only "Sin orden de trabajo" and the auto-fill behavior cannot be tested.

---

### Gaps Summary

No blocking gaps found. All 13 must-have truths are verified at the code level. Three items require human/runtime verification to confirm behavior against live backend data, which is expected for UI features that depend on dynamic API responses.

The MPRIMA-01 to MPRIMA-07 requirement IDs are not formally defined in REQUIREMENTS.md — this is a documentation traceability gap (not a functional gap) that should be addressed separately.

---

_Verified: 2026-04-12T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
