# Phase 12 — Reportajes Cockpit (통일 UI/UX + 보고서별 특화 시각화)

## Goal

Phase 8에서 구축한 보고서 셸(`/reportes-v2`)을 한 단계 더 발전시켜, **모든 16개 보고서가 동일한 통일된 레이아웃 패턴**을 따르고, 동시에 각 보고서가 사장이 한눈에 의사결정할 수 있는 **특화된 시각화(Cockpit)**를 제공한다.

핵심 원칙:

1. **단일 56px Topbar에 모든 컨트롤 압축** — 별도 FilterBar 띠 제거. 제목·breadcrumb·Sucursal·검색·날짜2개·액션버튼이 한 줄에 들어간다.
2. **좌측 200px 보조 사이드바 유지** — Phase 8 Wave 3 사이드바 그대로.
3. **나머지 100% 영역은 결과 시각화** — KPI 띠 + 카드 그리드 + 상세 패널 + 우측 드로워 패턴.
4. **Vendedor 보고서가 표준 사례 (Reference Implementation)** — Phase 12 Wave 2에서 완성된 형태가 나머지 14개 보고서의 템플릿이 된다.
5. **schema-driven** — `registry.ts`의 entry에 `filterSchema`, `cockpitLayout` 필드를 추가하여 셸이 자동으로 필터/레이아웃을 렌더한다.
6. **Pool 절약** — 단일 API 호출에서 KPI·랭킹·차트 데이터를 모두 응답하도록 백엔드 통합 (불필요한 N+1 차단).

## Depends on

- Phase 8 (Reportajes UX Redesign) — 셸, 사이드바, registry, controlled hooks 완성됨
- Phase 6 (15개 보고서 백엔드 API) — 데이터 소스

## Reference Mockups

- `reports-topbar-mockup.html` — 56px 단일 Topbar 패턴
- `vendor-cockpit-mockup.html` — Vendedor Cockpit 표준 디자인 (Wave 2의 구현 목표)

## Waves

| Wave | 제목 | 보고서 | 의존 |
|------|------|--------|------|
| 12-01 | 셸 인프라 통일 — 56px Topbar + Filter Schema + Cockpit Layout 시스템 | (전체) | Phase 8 Wave 4 |
| 12-02 | Vendedor Cockpit (표준 사례) — 카드 그리드 + KPI 띠 + 상세 탭 + 드로워 | vendedor | 12-01 |
| 12-03 | Ventas + Items 보고서 — 시계열 + 상품 믹스 cockpit | ventas, items | 12-02 |
| 12-04 | Finanzas 보고서 — Facturación + Gastos + Cheque Estado | facturacion, gastos, cheque-estado | 12-01 |
| 12-05 | Inventario 보고서 — Stocks + Corregido + Movidos + Fallados + Ingreso | stocks, corregido, movidos, fallados, ingreso | 12-01 |
| 12-06 | Clientes & Control 보고서 — Clientes-Crédito + Breve Venta + Reservado + Alertas | clientes-credito, breve-venta, reservado, alertas | 12-01 |
| 12-07 | Comparison Mode + Personalización — 비교 토글, Meta(목표) 입력 UI, 배지 시스템 | (전체) | 12-02 ~ 12-06 |
| 12-08 | 백엔드 통합 API + Performance — KPI/랭킹/차트를 단일 응답으로 합치고 pool 사용 최적화 | (전체) | 12-02 ~ 12-06 |

## Cockpit Layout 패턴 (전체 보고서 공통 구조)

```
┌───────────────────────────────────────────────────────────────┐
│ Topbar 56px: 제목 | Sucursal · Buscar · 📅→📅 | ★ 📊 📄 ▶  │
├───────────────────────────────────────────────────────────────┤
│ KPI Strip 80px: 4~5개 KPI + 옵션 위젯 (예: 🥇 Top)              │
├───────────────────────────────────────────────────────────────┤
│ Primary Area (resizable, 보고서별 특화)                        │
│   - 카드 그리드 (vendedor) / 시계열 차트 (ventas) /             │
│     히트맵 (items) / 막대 (stocks) ...                         │
├─────────────── (resize handle) ────────────────────────────────┤
│ Detail Area (탭 3종)                                           │
│   - Tendencia / Mix / Lista (기본 탭 셋)                       │
│   - 보고서별로 탭 이름과 콘텐츠가 다를 수 있음                   │
└───────────────────────────────────────────────────────────────┘
   + 우측 드로워 (380px, on-demand) — 단일 venta/transaction 상세
```

## Pool 절약 원칙 (Phase 12 전반)

- **단일 엔드포인트당 단일 connection** — KPI·랭킹·차트를 한 번의 API 호출로 묶어 응답한다.
- **N+1 금지** — 판매원 카드 8개를 위해 8번 호출하지 않고, 한 번의 GROUP BY 쿼리로 처리.
- **Sequelize raw query 활용** — 복합 집계는 raw SQL이 ORM hydration보다 가벼움.
- **결과는 프론트에서 캐시** — 같은 params로 재요청 시 5분간 memoize (React Query 또는 SWR).
- **`pool.max` 변경 금지** — 기존 pool 설정을 늘리지 않고 쿼리 효율로 해결.

## 마지막 로그 확인 원칙

각 Wave 시작 전 가장 최근 Jenkins 빌드 로그(`#NNN.txt`)를 읽어 회귀가 없는지 확인한다. Wave 종료 후 빌드를 트리거하고 새 로그를 다시 확인한다.
