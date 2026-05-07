# Phase 32: stocks-historial-drawer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves alternatives considered.

**Date:** 2026-05-08
**Phase:** 32-stocks-historial-drawer
**Mode:** --auto --chain (Claude picked recommended defaults; chains to plan+execute)
**Areas discussed (auto-resolved):** Endpoint design, Trigger, Display range, Type encoding, Audit info, Sucursal name display, Keyboard/UX, Header summary, Caching

---

## Backend Endpoint Design

| Option | Description | Selected |
|--------|-------------|----------|
| 신규 통합 endpoint `/reports/stocks-cockpit/historial` | 1 connection으로 4 type timeline | ✓ (recommended) |
| 4개 type별 endpoint | 정렬 어렵고 4 connections | |
| 기존 movidos report 확장 | 다른 type 통합 어색 | |

**Auto reasoning:** Phase 12 cockpit 패턴 일관성 + pool 1 connection.

---

## Drawer Trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Row 클릭 | Vendedor cockpit과 동일 UX | ✓ (recommended) |
| 별도 "Historial" 버튼 컬럼 | 화면 가로 좁아짐, 우발 클릭 가능 | |
| Context menu (우클릭) | 발견성 낮음 | |

**Auto reasoning:** 이미 익숙한 cockpit drawer 패턴.

---

## Display Range

| Option | Description | Selected |
|--------|-------------|----------|
| 30일 + "더 로드" 30일씩 누적 | 90% 케이스 1 fetch | ✓ (recommended) |
| 7/30/90 날 selector | UI 복잡도 추가 | |
| Pagination (page 단위) | timeline은 chronological이라 어색 | |
| All time, no limit | 큰 매장에서 N+1 문제 | |

**Auto reasoning:** 평균 사용 시 최근만 보면 충분.

---

## Type 인코딩

| Option | Description | Selected |
|--------|-------------|----------|
| 아이콘 + 색상 (Ventago 테마) | 즉시 인지, sketch-findings 일관 | ✓ (recommended) |
| 색상만 (아이콘 없음) | 미니멀하지만 텍스트 의존 | |
| 텍스트 라벨만 | 가독성 떨어짐 | |

**Auto reasoning:** sketch-findings-ace-online 테마 (cyan/green/red/gold) 즉시 매핑.

---

## Audit / 사용자 정보

| Option | Description | Selected |
|--------|-------------|----------|
| `audit_logs` LEFT JOIN | 기존 audit 시스템 활용 | ✓ (recommended) |
| Stocks에 user_id 컬럼 추가 | 마이그레이션 비용 | |
| 사용자 정보 미표시 | 정보 부족 | |

**Auto reasoning:** 기존 @Audit 데코레이터가 이미 stock CRUD에 적용 중.

---

## Sucursal 이름 표시

| Option | Description | Selected |
|--------|-------------|----------|
| `note` 컬럼 패턴 파싱 + branches JOIN | 기존 데이터 재사용, 비용 0 | ✓ (recommended) |
| 새 `counterparty_branch_id` 컬럼 추가 | 정합성 ↑, 마이그레이션 필요 | |

**Auto reasoning:** note 패턴(`movido(out→X)`) 안정적, parsing 비용 적음.

---

## Keyboard / UX

| Option | Description | Selected |
|--------|-------------|----------|
| ESC 닫기 + 외부 클릭 닫기 + row 재클릭 toggle | 다중 dismissal 옵션 | ✓ (recommended) |
| ESC만 | 단일 채널 | |
| 명시적 X 버튼만 | 불편 | |

**Auto reasoning:** Vendedor drawer와 동일 패턴 (다중 dismissal).

---

## Header 요약

| Option | Description | Selected |
|--------|-------------|----------|
| Sticky 헤더 + 현재 stock + 30일 net + 식별 정보 | 컨텍스트 즉시 노출 | ✓ (recommended) |
| 헤더 없이 timeline만 | 간결하지만 컨텍스트 부족 | |

**Auto reasoning:** 사용자가 "지금 12개 있고 30일간 +5 변동" 같은 스냅샷을 즉시 보고 싶어할 것.

---

## Cache 전략

| Option | Description | Selected |
|--------|-------------|----------|
| `useCockpitCache` 5분 TTL LRU | Phase 12 Plan 08 자산 재사용 | ✓ (recommended) |
| SWR 별도 hook | 의존성 추가 | |
| 캐시 없음 (매번 fetch) | 사용자 반복 클릭 시 pool 부담 | |

**Auto reasoning:** 기존 캐시 인프라 재사용.

---

## Claude's Discretion (planner에게 위임)

- Drawer 내부 row 컴포넌트 구조 (FlatList vs grouped by date)
- 빈 ledger 일러스트/메시지 카피
- SQL 인덱스 추천 (`stocks(product_branch_id, created_at DESC)` 가능성 높음 — planner가 EXPLAIN으로 검증)
- Stocks 보고서 row의 정확한 click target (row 전체 vs 특정 cell — DataGrid 컨벤션 따름)

## Deferred Ideas

- Stock 변동 인라인 편집 (보기만, 편집은 별도 phase)
- CSV/Excel export
- 다중 variant 비교 drawer
- 변동 트렌드 차트 in-drawer
- 알림 통합 (fallado 임계치)
- 과거 잘못된 parent-productId movido row audit (Phase 22 후속)
