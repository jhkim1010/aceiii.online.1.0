# Phase 40: Restaurante Delivery — Despacho y Cobro - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-16
**Phase:** 40-restaurante-delivery-despacho-cobro
**Areas discussed:** Sale 결제상태 동기화, 배차 보드 실시간 채널, 라이더 정산→caja 매핑, 배달앱 CSV 업로드/파싱

---

## Sale 결제상태 ↔ 배달 라이프사이클 동기화

| Option | Description | Selected |
|--------|-------------|----------|
| 배달완료(Entregado) 시 PAID — 수금축 분리 | 음식 나가면 PAID + SalePaymentMethod 기록, 매출 즉시 인식. 수금은 RestaurantDelivery.status+RiderSettlement 별도 추적 | ✓ |
| 돈 확인 시 PAID — 수금축 일치 | 현금=정산/QR=webhook/앱=conciliación 시 PAID. 현금 매출 인식 지연 | |
| Claude 재량 | plan 단계 결정 | |

**User's choice:** 배달완료(Entregado) 시 PAID — 수금축 분리 (D-01)

| Option | Description | Selected |
|--------|-------------|----------|
| DRAFT면 삭제/무효, PAID 이후면 기존 nullify | 배달완료 전 소프트삭제+재고복원+cancelado, PAID면 anular 역분개 | ✓ |
| 취소는 범위 밖 (수동) | 기존 sale 무효화로 수동 처리 | |

**User's choice:** DRAFT 상태면 삭제/무효, PAID 이후면 기존 nullify (D-02)

---

## 배차 보드 실시간 채널 (Socket.io)

| Option | Description | Selected |
|--------|-------------|----------|
| 신규 namespace + branch room | 신규 게이트웨이(/restaurant) + branch:{id} room, 브라우저 보드 vs print-agent 관심사 분리 | ✓ |
| 기존 /print-agent 게이트웨이 확장 | 연결 재사용하나 에이전트/브라우저 혼재 | |
| Claude 재량 | plan 단계 결정 | |

**User's choice:** 신규 namespace + branch room (D-03)

| Option | Description | Selected |
|--------|-------------|----------|
| 변경된 주문 payload 푸시 (card-level) | 변경 카드 payload emit, 클라이언트 병합. 추가 쿼리 0 (pool 친화) | ✓ |
| 신호만 푸시 → 클라이언트 재조회 | 단순하나 쿼리 더 많음 | |

**User's choice:** 변경된 주문 payload 푸시 (card-level) (D-04)

---

## 라이더 정산 → caja(box) 매핑

| Option | Description | Selected |
|--------|-------------|----------|
| 정산 마감당 1건 (집계) | RiderSettlement close 시 receivedCash 합계를 box movement 1건 입금. 교대 마감 모델 | ✓ |
| rendido 주문당 1건 | 주문마다 movement, 세밀하나 소액 다수 | |

**User's choice:** 정산 마감당 1건 (집계) (D-05)

| Option | Description | Selected |
|--------|-------------|----------|
| 정산 차단 — 먼저 caja 오픈 요구 | 열린 cashRegister 없으면 정산 불가. caja 마감 일치 보장 | ✓ |
| Liquidado 허용 + boxSessionId=null 플래그 | 미오픈이면 box-op 스킵하되 Liquidado 허용 (Phase 39 스킵 일관) | |

**User's choice:** 정산 차단 — 먼저 caja 오픈 요구 (D-06, Phase 39 보다 엄격)

---

## 배달앱 CSV 업로드/파싱 + 매칭 키

| Option | Description | Selected |
|--------|-------------|----------|
| 인메모리 파싱 (저장 안 함) | multipart 업로드→서버 파싱, 파일 미저장 | |
| MinIO 저장 + 파싱 | payout 파일 보관 + 파싱, 감사 추적 | ✓ |

**User's choice:** MinIO 저장 + 파싱 (D-07)

| Option | Description | Selected |
|--------|-------------|----------|
| 업로드 시 컬럼 매핑 | 사용자가 externalRef/금액 컬럼 매핑 (Phase 25 선례) | |
| 플랫폼별 고정 파서 | PedidosYa/Rappi 하드코딩 | |
| 단일 고정 스키마 (템플릿) | 운영자가 템플릿 형식으로 정규화 업로드 | ✓ |

**User's choice:** 단일 고정 스키마 (템플릿) (D-08, 매칭=externalRef+금액 정확 일치)

---

## Claude's Discretion

- 프론트 Delivery 진입점 (SalonView 옆 DeliveryBoard 탭/세그먼트, next/dynamic ssr:false)
- 주문번호 식별 (Sale dailyNumber 재사용 우선, 부족 시 자체 sequence)
- RestaurantDelivery.status enum 명칭/CHECK 동기화 (sales.model.ts 선례)
- 타이밍 타임스탬프 기록 (상태 전이 트랜잭션, Phase 39 패턴)

## Deferred Ideas

- 고객용 공개 추적 링크, 배달앱 L2 API 동기화, 라이더 모바일 화면, GPS 추적, 외상 배달, 금액 tolerance 매칭, 플랫폼별 자동 파서, item 단위 split
