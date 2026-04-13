# Phase 15: Materia Prima Control - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 15-materia-prima
**Areas discussed:** Inventario 카드 디자인, Dashboard 레이아웃, 입출고/결제 워크플로우

---

## Inventario 카드 디자인

### 카테고리 구분 방식

| Option | Description | Selected |
|--------|-------------|----------|
| 상단 컬러바 (목업 방식) | 카드 상단 4px 컬러바로 카테고리 식별 | ✓ |
| 카드 전체 배경색 은은하게 | 카드 배경색을 카테고리별 연한 색으로 적용 | |
| 카테고리 칩만 | 카드 내부에 카테고리명 Chip만 표시 | |

**User's choice:** 상단 컬러바 (목업 방식)

### Tela 추가 속성 표시

| Option | Description | Selected |
|--------|-------------|----------|
| 코드 아래 한 줄 (목업 방식) | COD-T001 · Tela · Color: Blanco · Origen: Nacional | ✓ |
| 카드 하단 태그 | 색상/원산지/품질을 각각 작은 Chip 태그로 표시 | |
| 확장 영역 | 카드 클릭 시 상세 패널에서만 표시 | |

**User's choice:** 코드 아래 한 줄 (목업 방식)

### 재고 상태 표시

| Option | Description | Selected |
|--------|-------------|----------|
| Progress bar + 배지 (목업 방식) | 초록/주황/빨강 progress bar + 상태 배지 + 수치 텍스트 | ✓ |
| 원형 게이지 | 재고 레벨을 원형 게이지로 표시 | |

**User's choice:** Progress bar + 배지 (목업 방식)

---

## Dashboard 레이아웃

### 레이아웃 구성

| Option | Description | Selected |
|--------|-------------|----------|
| 2칸 그리드 (목업 방식) | KPI → [알림|차트] → [채무|최근이동] | ✓ |
| 단일 칸 | 세로 순서대로 배치 | |
| 현재 유지 | KPI + 알림 + 최근이동만 | |

**User's choice:** 2칸 그리드 (목업 방식)

### 차트 구현

| Option | Description | Selected |
|--------|-------------|----------|
| CSS 바 차트 (목업 방식) | 라이브러리 없이 순수 CSS | ✓ |
| Recharts/ApexCharts | 프로젝트에 이미 apexcharts-clevision 있음 | |
| Claude 재량 | 구현 난이도와 시각적 효과 균형을 Claude가 판단 | |

**User's choice:** CSS 바 차트 (목업 방식)

---

## 입출고/결제 워크플로우

### 입고 대금 처리

| Option | Description | Selected |
|--------|-------------|----------|
| 모달 내 통합 (현재+목업) | 공급자+수량+단가+대금상태 한 모달에서 처리 | ✓ |
| 2단계 마법사 | Step 1: 재료+수량 → Step 2: 대금 처리 | |
| 빠른 입고 모드 | 자주 쓰는 조합 저장 후 한 클릭 입고 | |

**User's choice:** 모달 내 통합

### 출고 연결 방식

| Option | Description | Selected |
|--------|-------------|----------|
| 작업지시(OT) 선택식 | WorkOrder 목록에서 선택하여 연결 | |
| 참조번호 입력식 (현재) | 자유 텍스트로 참조번호 입력 | |
| 둘 다 지원 | WorkOrder 선택 OR 수동 참조번호 | ✓ |

**User's choice:** 둘 다 지원

### 결제 후 채무 업데이트

| Option | Description | Selected |
|--------|-------------|----------|
| 자동 차감 (권장) | 결제 등록 시 공급자 채무에서 자동 차감 | ✓ |
| 수동 매칭 | 관리자가 어떤 입고 건에 대한 결제인지 수동 매칭 | |

**User's choice:** 자동 차감

---

## Claude's Discretion

- 컴포넌트 분리 세부 구조
- 반응형 처리
- 알림 섹션 세부 UX
- Dialog 폼 validation 패턴

## Deferred Ideas

- BOM 연동 원가 계산 → Phase 7 또는 별도 phase
- 바코드 스캔 입고 → Phase 13 이후
- 입출고 이력 Excel 내보내기
