# Phase 27 — CONTEXT

**Phase**: 27 — Ventas Online (온라인 판매 관리)
**Created**: 2026-05-01
**Source**: 사용자 요청 (GSD Plan→Execute→Review 1회 연속 수행)

---

## 1. Phase Goal

Mercado Libre / Webshop / Instagram / WhatsApp 등 온라인 채널 주문을 한 곳에서 관리.
주문 라이프사이클 (pending→confirmed→preparing→shipped→delivered, cancelled, returned) 을 통합 추적, 채널별 KPI 제공.

기존 `sales` 와 별도 도메인 (`online_orders`) 으로 격리.

---

## 2. Locked Decisions

상세는 `.gsd/spec-ventas-online.md` 의 §2 참고.

핵심:
- 별도 테이블 (`online_orders` / `online_order_items` / `online_returns`)
- `order_number` 매장별 UNIQUE 카운터
- 재고 차감은 `confirmed` 시점, SERIALIZABLE 트랜잭션
- 사이드바 `venta` 앱에 children 하드코딩

---

## 3. Architecture

- 백엔드: NestJS 모듈 `api-ventago/src/app/online-orders/`
- DB: PostgreSQL (snake_case columns, BIGSERIAL)
- 프론트: Next.js Pages Router + MUI + SWR
- 번역: 한국어 주석, ES 사용자 노출 텍스트

---

## 4. Out of scope

- 실제 Mercado Libre / WhatsApp API 연동 (Phase 28+)
- 결제 게이트웨이 webhook
- 자동 송장 PDF 생성

---

## 5. Plans

- 27-01-PLAN.md — Wave 1: DB 마이그레이션 + Sequelize 모델 + 모듈 등록
- 27-02-PLAN.md — Wave 2: NestJS 서비스 + 컨트롤러 + DTO
- 27-03-PLAN.md — Wave 3: 프론트엔드 페이지 + 뷰 컴포넌트
- 27-04-PLAN.md — Wave 4: SWR 훅 + 사이드바 통합 + 최종 검증
