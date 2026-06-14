# Phase 39: Modo Restaurante — POS por mesas - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-14
**Phase:** 39-modo-restaurante-pos-mesas
**Areas discussed:** split/merge 정산 모델, 테이블 상태↔DRAFT sale, 배치도 좌표 스키마

> SPEC.md (11 requirements) locked the WHAT. Discussion covered HOW only.

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| split/merge 정산 모델 | sale 행으로 split·merge 표현, 매출 무오염 | ✓ |
| 테이블상태↔DRAFT | status 저장 방식, 상태 종류, merge 표시 | ✓ |
| comanda 증분 주문 | 새 품목만 vs 전체 재출력, 라운드 추적 | (Claude's Discretion) |
| 배치도 좌표 스키마 | 좌표계, 다중 salón, 테이블 크기 | ✓ |
| 메뉴 카테고리 필터 지정 | (4-option 제한으로 미제시 → Claude's Discretion) | (Claude's Discretion) |

---

## split/merge 정산 모델

### Q1 — split 표현
| Option | Description | Selected |
|--------|-------------|----------|
| 단일 sale + 복수 결제행 | 1 DRAFT sale, sale_payment_methods에 금액 분할 행. 매출 무오염 | ✓ |
| 자식 sale per-person | 인원만큼 자식 sale, item 귀속. 통계/재고 복잡 | |

### Q2 — merge 표현
| Option | Description | Selected |
|--------|-------------|----------|
| 각 테이블 sale 유지 + 동시 결제 | N DRAFT sale 동시 PAID, 금액 배분. 테이블별 매출 귀속 보존 | ✓ |
| 1 sale로 이관 통합 | reparent 후 빈 sale 삭제. 단순하나 테이블별 매출 귀속 소실 | |

### Q3 — split 분할 기준
| Option | Description | Selected |
|--------|-------------|----------|
| 균등 + 임의금액 | N등분 + 결제수단별 임의 금액 | ✓ |
| 균등분만 | N등분만, 최소 구현 | |
| item 귀속 분할 | 손님별 item 선택, 자식-sale 필요 | |

**Notes:** 단일-sale 모델 + 매출 무오염 + 재고 영향 0이 SPEC '확장 only · 단순' 제약과 일치. item 단위 split은 후속 Phase로 연기.

---

## 테이블 상태 ↔ DRAFT sale

### Q1 — 상태 저장 방식
| Option | Description | Selected |
|--------|-------------|----------|
| 명시 status 컬럼 + current_sale_id | 둘 다 저장, 트랜잭션 동기화. salon 단일 조회 렌더 | ✓ |
| current_sale_id로 파생 | status 컬럼 없음, drift 불가하나 중간상태/JOIN 필요 | |

### Q2 — 상태 종류
| Option | Description | Selected |
|--------|-------------|----------|
| libre / ocupada / por_cobrar | 3단계, cuenta 요청/결제 직전 색 구분 | ✓ |
| libre / ocupada 둘만 | 2단계, cuenta는 일회성 액션 | |

### Q3 — merge 시각화
| Option | Description | Selected |
|--------|-------------|----------|
| 결제 시점에만 묶음 | 영속 group 컬럼 불필요, 스키마 단순 | ✓ |
| 영속 merge 그룹 | group_id 컬럼, 사전 묶음 표시. MVP 과잉 | |

**Notes:** salon 렌더를 restaurant_tables 단일 조회로(pool 절약/300ms), drift는 서비스 트랜잭션으로 방지.

---

## 배치도 좌표 스키마

### Q1 — 좌표계
| Option | Description | Selected |
|--------|-------------|----------|
| 정규화 0~1 float | 비율 배치, 반응형, 편집기↔런타임 일관 | ✓ |
| 가상 캔버스 정수 px | 고정 캔버스 + CSS scale, 정수 디버그 용이 | |
| 화면 절대 px | 반응형 약함 | |

### Q2 — 다중 salón
| Option | Description | Selected |
|--------|-------------|----------|
| 1 branch = 1 평면 | MVP 최단순 | |
| zone 컬럼으로 다중 (저비용 대비) | nullable zone 컬럼만 추가, UI는 1평면 | ✓ |

### Q3 — 테이블 크기
| Option | Description | Selected |
|--------|-------------|----------|
| 형태별 고정 크기 + 좌석수 라벨 | w/h 미저장, 최단순 | |
| 좌석수 비례 크기 | 좌석수에 따라 크기 자동 조절 | ✓ |

**Notes:** 정규화 좌표 + zone 컬럼 확보 + 좌석수 비례 크기. 리사이즈는 req5 out-of-scope.

---

## Claude's Discretion

- **comanda 증분 주문:** 새로 추가된 sale_items만 출력, 라운드는 created_at 묶음 추적(신규 컬럼 없음), emitPrintTemp 재사용
- **메뉴 카테고리 필터:** store_config에 식당 카테고리 id 목록 저장 (categories 스키마 무변경)
- **useRestaurantMode default = false** (소매 무영향)

## Deferred Ideas

- KDS · 상세 타이밍 리포트 · item 단위 split · 영속 merge 그룹 · 다층 salón UI · 테이블 회전/리사이즈 · 예약/대기자
