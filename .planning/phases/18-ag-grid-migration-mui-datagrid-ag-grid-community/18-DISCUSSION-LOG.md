# Phase 18: AG Grid Migration - Discussion Log

> **Audit trail only.**

**Date:** 2026-04-13
**Phase:** 18-ag-grid-migration
**Areas discussed:** AG Grid 기능 선택

---

## AG Grid 기능

| Option | Description | Selected |
|--------|-------------|----------|
| 컬럼 리사이즈만 (추천) | 기본 드래그 리사이즈 | ✓ |
| 컬럼 고정(Pin) | 좌/우 고정 | ✓ |
| 행 드래그 정렬 | 순서 변경 | |
| 필터 UI | 헤더 필터 아이콘 | ✓ |

**User's choice:** 컬럼 리사이즈 + 컬럼 고정 + 필터 UI
**Notes:** 행 드래그는 제외

## Claude's Discretion

- FullTable 내부 AG Grid API 활용
- defaultColDef 세부 설정
- 테마/스타일 매핑
- 회귀 테스트 범위

## Deferred Ideas

- 행 드래그 정렬
- Excel 내보내기 (Enterprise)
- 그룹핑/피벗 (Enterprise)
