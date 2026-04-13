# Phase 16: Control de Talleres - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-13
**Phase:** 16-control-de-talleres
**Areas discussed:** 페이지 구조, Pipeline, 백엔드, 우선순위, 드로어, Taller 목록

---

## 페이지 구조

| Option | Description | Selected |
|--------|-------------|----------|
| 탭 네비게이션 (추천) | 단일 페이지에 상단 탭으로 전환. 목업과 동일한 UX | ✓ |
| 기존 페이지 유지 | 별도 페이지 7개 유지하고 각 페이지 UI만 목업 스타일로 리디자인 | |
| 하이브리드 | Dashboard+Pipeline은 탭 통합, 나머지는 개별 페이지 | |

**User's choice:** 탭 네비게이션
**Notes:** 목업과 동일한 UX 선호

---

## Pipeline

| Option | Description | Selected |
|--------|-------------|----------|
| 읽기 전용 (추천) | 시각화만 제공. 발송/수령은 기존 버튼 워크플로우 유지 | ✓ |
| 드래그 & 드롭 | 카드를 다음 단계로 드래그하면 자동으로 envío/recepción 생성 | |

**User's choice:** 읽기 전용
**Notes:** 구현 간단하고 기존 워크플로우 유지

---

## 백엔드

| Option | Description | Selected |
|--------|-------------|----------|
| 프론트만 리팩토링 (추천) | 기존 API 그대로 사용. Dashboard 통계는 프론트에서 집계 | |
| Dashboard 통합 API 추가 | 새 /talleres/dashboard/stats 엔드포인트 추가 | ✓ |

**User's choice:** Dashboard 통합 API 추가
**Notes:** KPI + 분포 + 채무 + 최근이동을 한 번에 응답하는 통합 API 선호

---

## 우선순위

| Option | Description | Selected |
|--------|-------------|----------|
| Dashboard + Pipeline 우선 | 시각적 임팩트 큰 2개 먼저 | ✓ |
| 전체 동시 진행 | 7개 화면 한번에 리팩토링 | |

**User's choice:** Dashboard + Pipeline 우선
**Notes:** Wave별 구현

---

## 드로어

| Option | Description | Selected |
|--------|-------------|----------|
| 우측 드로어 (추천) | 420px 드로어. 타임라인 + 공정 진행도 + 수량 분포 | ✓ |
| 별도 상세 페이지 | Lote 클릭 시 전체 페이지로 이동 | |

**User's choice:** 우측 드로어
**Notes:** 목업과 동일

---

## Taller 목록

| Option | Description | Selected |
|--------|-------------|----------|
| 카드형 (추천) | 2칸 그리드 카드. 아바타+통계+용량 게이지 | |
| 테이블+확장 행 | 테이블 목록에서 행 클릭 시 확장되어 상세 표시 | ✓ |

**User's choice:** 테이블+확장 행
**Notes:** 많은 업체 시 스크롤 효율 선호

---

## Claude's Discretion

- 컴포넌트 분리 세부 구조
- 탭 상태 관리 방식
- 테이블 확장 행 애니메이션
- Dashboard 통합 API 쿼리 최적화

## Deferred Ideas

- 드래그&드롭 Pipeline (Phase 17)
- 업체별 성과 리포트 (Reportajes 확장)
- 자재 연동 입출고 (Phase 15 cross-link)
