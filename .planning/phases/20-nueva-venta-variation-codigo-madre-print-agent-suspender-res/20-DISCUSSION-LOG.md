# Phase 20: Nueva Venta Variation/CodigoMadre 디버깅 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-17
**Phase:** 20-nueva-venta-variation-codigo-madre-print-agent-suspender-res
**Areas discussed:** 1 (Log Routing), 2 (Trace ID)
**Areas deferred:** 3 (Suspender data integrity), 4 (Print-agent ticket output), 5 (Root cause fix), 6 (Activation toggle)

---

## Area 1 — 로그 경로 & 지속성 (Log Routing)

| Option | Description | Selected |
|--------|-------------|----------|
| A. 콘솔 only | 브라우저/서버 콘솔에만 남김, 파일 없음 | |
| B. 서버 winston only | 백엔드 winston 파일만 사용, 프론트 콘솔 유지 | |
| C. 프론트·백 모두 winston+콘솔 | 실행 위치(로컬/서버)에 맞춰 해당 환경의 winston 파일 + 콘솔 양쪽에 기록 | ✓ |
| D. 별도 debug.log | variation 전용 별도 파일만 | |

**User's choice:** C — "로컬에서 실행하면 로컬에서 winston log와 콘솔에, 서버에서 실행하면 서버에서 역시 winston log와 콘솔에서 로그를 뽀려주게 해 줘"

**Notes:**
- api-ventago 는 이미 winston(Console + DailyRotateFile) 셋업되어 있어 실행 위치 자동 분기 (docker 든 로컬이든 동일 코드).
- ventago-app 은 Next.js 서버 측에 winston 없음 → 추가 필요.
- 브라우저 측 로그는 Next.js API route `/api/debug/variation-log` 로 POST → 서버측 winston 기록.

---

## Area 2 — Trace ID (추적 상관관계)

| Option | Description | Selected |
|--------|-------------|----------|
| A. UUID v4 per session | crypto.randomUUID() 로 판매 세션당 하나 발급 | ✓ |
| B. timestamp + userId | traceId 없이 조합 키로 상관관계 | |
| C. incrementing counter | DB sequence / redis counter | |

**User's choice:** A — "UUID로 하는 것이 좋을 것 같아"

**Notes:**
- 발급 시점: nueva-venta 페이지 mount 시 SaleProductsContext 에 저장.
- 수명: 결제 완료 또는 resetSale() 호출 시 회전.
- 전파: 모든 관련 HTTP 요청 `X-Trace-Id` 헤더 + print-agent emit payload 의 `traceId` 필드.
- suspender/restore: 원 traceId 복구 안 함, 새 UUID 발급하고 `restoredFromSuspendedSaleId` 상관관계로 연결.

---

## Claude's Discretion

- 프론트 로그 배치 전송 전략(immediate vs debounced)
- ventago-app 측 winston 설정 세부사항 (api-ventago 의 logger.config.ts 를 복제)
- `/api/debug/variation-log` rate-limit / payload cap
- print-agent 에서 electron-log vs console 선택

## Deferred Ideas

User declared "우선 이 2가지만 완벽하게 하자" — Areas 3~6 은 이 phase 범위 밖.

- **Area 3** Suspender/restore 데이터 무결성 수정 → 다음 phase 후보
- **Area 4** Print-agent 티켓 디버그 출력 (payload traceId 전달은 유지, 출력물은 건드리지 않음)
- **Area 5** 근본 원인 수정 (이 phase 로그로 수집된 증거 기반으로 다음 phase)
- **Area 6** 활성화 스위치/토글 (현재는 항상 on, 용량 문제 발생 시 추가)
