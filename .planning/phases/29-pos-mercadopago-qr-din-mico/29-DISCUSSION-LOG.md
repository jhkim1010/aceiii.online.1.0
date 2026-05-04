# Phase 29: POS Mercadopago — QR Dinámico - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 29-pos-mercadopago-qr-din-mico
**Areas discussed:** OAuth + 토큰 인프라, Webhook 보안 + 알림 wiring, Caja MP 데이터 모델, UI 세부 (QR/Sandbox/환불)

---

## Pre-discussion (spec-phase 직전 채팅)

이 영역은 spec-phase 직전 사용자와의 채팅에서 lock 됨:
- MP 제품: QR Dinámico only (Phase 30 = Point, Phase 31 = Online 분리)
- 계정 단위: store_id 단위 기본 (discuss-phase 에서 branch-level 옵션 추가됨)
- 환불: Phase 29 마지막 plan 에 포함
- 만료/취소: 3분 timeout + 수동 취소 + webhook 실패 expired
- Split payment: 부분금액 MP 허용
- Reconciliation: 가상 Caja MP
- Sandbox toggle: store 별 (discuss-phase 에서 mp_account 별로 확장)

---

## OAuth + 토큰 인프라

### Q1 — MP Developer App 등록 전략

| Option | Description | Selected |
|--------|-------------|----------|
| 통합 1개 App (sandbox+production) | MP App 1개에서 환경별 키 분리, 운영 단순 | ✓ |
| Sandbox/Production 2개 App | 완전 격리, 관리 포인트 2배 | |

**User's choice:** 통합 1개 App
**Notes:** Recommended 옵션 채택

### Q2 — OAuth callback URL 위치

| Option | Description | Selected |
|--------|-------------|----------|
| 공용 endpoint | newapi.coolsistema.com/api/mercadopago/oauth/callback 단일, state 서명 | (재해석됨) |
| Store 별 subdomain/path | 각 store 별 path | |

**User's choice:** "각 시스템에 존재하는 store 마다 1개씩.. 지점이 여러개 존재할 때 같이 사용할지 다른 mercadolibre 계정을 사용할지를 내 시스템 사용자가 정할 수 있게"
**Notes:** **SCOPE 확장**. 단순한 callback URL 질문이 아니라 계정 소유 구조 자체에 대한 답변. → store-level + branch-level 둘 다 지원하는 모델로 SPEC MP-POS-01 업데이트 (Q5 에서 재확인). callback URL 자체는 공용 endpoint + state 파라미터에 (storeId, branchId|null, nonce) 서명으로 라우팅.

### Q3 — Refresh 토큰 만료 처리

| Option | Description | Selected |
|--------|-------------|----------|
| Lazy + 사전 알림 (D-7) | API 호출 시 갱신, D-7 알림 + email | ✓ |
| Cron 자동 갱신 | proactive 새벽 cron | |

**User's choice:** Lazy + 사전 알림
**Notes:** Recommended 채택

### Q4 — 토큰 암호화 key 관리

| Option | Description | Selected |
|--------|-------------|----------|
| 단일 env MP_TOKEN_ENCRYPTION_KEY | Docker secret 1개 master key | (재해석됨) |
| Key versioning (V1/V2) | 로테이션 지원, 복잡 | |

**User's choice:** "각 store, sucursal 마다 고유의 토큰을 사용하게 하고 싶어. admin 페이지에서 정할 수 있게"
**Notes:** Q2 답변과 같은 맥락 (계정 단위 = store 또는 branch). encryption key 자체는 묻지 않음 → Q5 에서 분리 확인.

### Q5 (clarification) — 계정 소유 구조 확인

| Option | Description | Selected |
|--------|-------------|----------|
| store 또는 branch 설정 가능 | mp_accounts(store_id, branch_id NULLABLE) | ✓ |
| 다른 의도 | 사용자 설명 필요 | |

**User's choice:** store 또는 branch 설정 가능
**Notes:** SPEC.md MP-POS-01 업데이트 확정.

### Q6 (clarification) — Encryption master key

| Option | Description | Selected |
|--------|-------------|----------|
| 단일 env MP_TOKEN_ENCRYPTION_KEY | 1개 master key | ✓ |
| Key versioning | 로테이션 지원 | |

**User's choice:** 단일 env (Recommended)
**Notes:** master key 1개 + 모든 mp_account 토큰 암호화.

---

## Webhook 보안 + 알림 wiring

### Q7 — Webhook signature secret scope

| Option | Description | Selected |
|--------|-------------|----------|
| 글로벌 1개 (MP_WEBHOOK_SECRET) | App 단위 secret, 단순 | ✓ |
| Account 별 분리 | mp_accounts.webhook_secret 컬럼 | |

**User's choice:** 글로벌 1개

### Q8 — Socket.io emit 패턴

| Option | Description | Selected |
|--------|-------------|----------|
| 신규 emitToTerminal(terminalId) | 정확 타깃, 새 메서드 | ✓ |
| emitToStore + 프론트 필터링 | 단순, 대역폭 ↑ | |

**User's choice:** 신규 emitToTerminal

### Q9 — Polling 구현

| Option | Description | Selected |
|--------|-------------|----------|
| SWR refreshInterval=5000 | 모달 unmount 시 자동 stop | ✓ |
| Custom useEffect+setInterval | 세밀한 제어 | |

**User's choice:** SWR

### Q10 — 멱등성 보장 메커니즘

| Option | Description | Selected |
|--------|-------------|----------|
| DB UNIQUE(payment_id) + transaction | 인프라 추가 없음 | ✓ |
| Redis lock | 분산 락, 신규 인프라 | |

**User's choice:** DB UNIQUE + transaction

---

## Caja MP 데이터 모델

### Q11 — 가상 Caja 저장 위치

| Option | Description | Selected |
|--------|-------------|----------|
| 신규 mp_wallets 테이블 | 깔끔 분리, store/branch scope 일치 | ✓ |
| box.type 컬럼 추가 | 기존 box 활용, branch_id NOT NULL 충돌 | |

**User's choice:** 신규 mp_wallets

### Q12 — MP 입금 기록 테이블

| Option | Description | Selected |
|--------|-------------|----------|
| 신규 mp_movements | 분리, MP 전용 스키마 | ✓ |
| 기존 movements 재사용 | 기존 box_id 의존 변경 필요 | |

**User's choice:** 신규 mp_movements

### Q13 — Caja MP→현금 이체 UI 위치

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 29 포함 — 수동 이체 버튼 | control-de-caja 통합 | ✓ |
| Phase 32+ 로 미루기 | Phase 29 단순화 | |

**User's choice:** Phase 29 포함

### Q14 — control-de-caja 표시 방식

| Option | Description | Selected |
|--------|-------------|----------|
| 별도 행 + Caja MP 잔고 표시 | 기존 표 통합, UX 일치 | ✓ |
| 신규 reports/mercadopago 페이지 | 도메인 분리 | |

**User's choice:** 별도 행 + Caja MP 잔고

---

## UI 세부 (QR / Sandbox / 환불)

### Q15 — QR 이미지 렌더링 방식

| Option | Description | Selected |
|--------|-------------|----------|
| Backend qr_data string + 프론트 qrcode.react | 유연, 백엔드 깔끔 | ✓ |
| Backend base64 PNG | 프론트 무패키지 | |

**User's choice:** 프론트 qrcode.react

### Q16 — Sandbox 시각 구분

| Option | Description | Selected |
|--------|-------------|----------|
| Header 주황 배너 + QR 모달 주황 테두리 | 명확한 경고 | ✓ |
| QR 모달 내부에만 작은 칩 | 미니멀 | |

**User's choice:** Header 주황 배너 + 모달 테두리

### Q17 — 환불 실패 UX

| Option | Description | Selected |
|--------|-------------|----------|
| 인라인 Alert + Toast + 재시도 + 링크 + 시도 기록 | 완전한 추적 | ✓ |
| Toast 만 + sale nullified | 단순, 추적 부족 | |

**User's choice:** 인라인 Alert + Toast + 재시도 + 링크 + mp_refund_attempts 기록
**Notes:** memory feedback_error_visibility 규칙 준수.

### Q18 — OAuth 연결 admin 페이지 위치

| Option | Description | Selected |
|--------|-------------|----------|
| configuracion/mercadopago 신규 | 사이드바 통합 | ✓ |
| sucursales/[id]/mercadopago 분산 | branch 별 | |

**User's choice:** configuracion/mercadopago

---

## Gate Confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Context 작성 진행 | SPEC 업데이트 + CONTEXT.md + commit | ✓ |
| 더 논의 | 추가 round | |

**User's choice:** Context 작성 진행

---

## Claude's Discretion (CONTEXT.md 의 "Claude's Discretion" 섹션과 동일)

- mp_payment_intents 컬럼 세부 (status enum 값, expires_at 정확 타입 등)
- websocket room 명명 규칙
- qrcode.react size/level 시각 디테일
- configuracion/mercadopago 페이지 정확한 MUI 레이아웃
- mp_transfers status 컬럼 추가 여부
- API endpoint 정확한 path 구조

## Deferred Ideas (CONTEXT.md 의 "Deferred Ideas" 섹션과 동일)

- MP 수수료 자동 추적 → Phase 32+
- MP Cuenta Empresa 자동 KYC → out of scope
- 이력 sales 마이그레이션 → 안 함
- Point Smart 단말기 → Phase 30
- Online Checkout Pro/Bricks → Phase 31
- 마켓플레이스 split payment → Phase 24
- Multi-currency → out of scope, ARS only
