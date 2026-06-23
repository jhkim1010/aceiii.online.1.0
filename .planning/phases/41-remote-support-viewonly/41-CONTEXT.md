# Phase 41 — Context (scout 2026-06-18)

## 마지막 로그 확인 (프로젝트 필수 규칙)
- `api-ventago/logs/error-2026-06-18.log` — **0 bytes (에러 0건)**
- `combined-2026-06-18.log` 마지막: `[DatabasePool] size=10 using=0(0%) available=10 waiting=0 max=80` — pool 안정, 경고/대기 0
- OnlineOrdersExpiryCron 정상 동작 중 (대상 0건)

## 실시간 인프라 (재사용 대상)
- `api-ventago/src/common/socket/websocket.gateway.ts` — 전역 게이트웨이
- `api-ventago/src/app/print/print.gateway.ts` — `@WebSocketGateway({ namespace: '/print-agent', cors: { origin: '*' } })`
- `api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts` — `/restaurant`
- → 신규 `/support` 네임스페이스 게이트웨이로 추가 (생 ws 금지)

## DB pool (재사용 대상)
- `api-ventago/src/database/database.module.ts` — Sequelize 싱글턴, pool min=10 / max=80 / idle=10s, retry max=3
- slow query 로깅 100ms+ / 500ms+ 경고 내장
- → 신규 `SupportSession` Sequelize 모델, `pool.connect()` 미사용, `Model.query` 짧은 쿼리만

## 인증/권한 (재사용 대상)
- `auth/guards/` (JWT), `auth/guards/function-permission.guard.ts`
- `session/guards/session.guard.ts` (sessionToken)
- `permissions/guards/permission.guard.ts` + `permissions/decorators/permission.decorator.ts` (Phase 33 RBAC)
- `permissions/permission-resolver.service.ts`, `permission-cache.service.ts`

## 멀티테넌트
- 거의 모든 테이블 `store_id` FK. support_sessions store-scoped 필수.

## 초안 vs repo 스택 차이 (정식화에서 조정한 부분)
- standalone `ws` 서버 → NestJS Socket.io 게이트웨이
- 별도 `pg` Pool → Sequelize 싱글턴 모델
- UUID-only 인증 → JWT + permission 게이트 뒤 뷰어 (R-1)

## 미해결 (discuss-phase 대상)
- 뷰어 permission_slug 매핑 (Q1)
- rrweb 이벤트 DB 영속화 여부 (Q2 — pool/스토리지 영향)
- 운영 `/support` 네임스페이스 CORS/방화벽 (Q3)
