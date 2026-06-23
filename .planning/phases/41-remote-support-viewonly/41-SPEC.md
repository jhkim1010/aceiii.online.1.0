# Phase 41: Soporte Remoto Embebido — Visor de Solo Lectura (rrweb) — Specification

**Created:** 2026-06-18
**Status:** 🔵 draft — 사용자 보안 결정 승인 대기 (not-planned → /gsd-discuss-phase 41 또는 /gsd-plan-phase 41)
**Origin:** 사용자 자유형식 SPEC 초안(2026-06-18)을 repo 실제 스택(NestJS + Sequelize 싱글턴 pool + Socket.io)에 맞춰 정식화

## Goal

고객(매장 운영자)이 Ventago 웹 화면에서 "지원 요청" 시 서버가 **세션 UUID**를 발급하고, 고객이 그 UUID를 지원팀에 전달하면, 지원팀이 인증된 뷰어에서 해당 UUID로 **고객의 웹 화면(DOM)을 실시간·보기 전용으로** 재생한다. rrweb 기반 DOM 미러링(영상 코덱 없음)으로 대역폭이 작고 지연이 거의 없으며, 지원팀→고객 방향 제어 채널은 **존재하지 않는다(보안상 의도된 제약)**.

## Background

코드 현황(2026-06-18 scout):
- **실시간 인프라 = Socket.io 게이트웨이 패턴** (생 `ws` 아님). 기존: `api-ventago/src/common/socket/websocket.gateway.ts`(전역), `app/print/print.gateway.ts`(`@WebSocketGateway({ namespace: '/print-agent' })`), `app/restaurant-delivery/restaurant-delivery.gateway.ts`(`/restaurant`). → 신규 `/support` 네임스페이스 게이트웨이로 통일하는 것이 설계 방향. **별도 standalone `ws` 서버 추가 금지**(인프라 이원화·배포 복잡도·인증 우회 위험).
- **DB pool = Sequelize 싱글턴** (`api-ventago/src/database/database.module.ts`, min=10/max=80/idle=10s). 운영 로그 기준 `size=10 using=0` 안정. **신규 `pg` Pool 인스턴스 생성 금지** — 세션 메타는 Sequelize 모델 + 짧은 쿼리만 사용 → pool 낭비 0.
- **인증 인프라**: `auth/guards/`(JWT), `session/guards/session.guard.ts`(sessionToken), `permissions/guards/permission.guard.ts`(RBAC, Phase 33). 뷰어 페이지/소켓 인증은 기존 JWT + permission 게이트 재사용.
- **멀티테넌트**: 거의 모든 테이블에 `store_id` FK. support_sessions 도 store-scoped.
- **프론트**: Next.js 13 Pages Router. 뷰어는 신규 페이지, 고객 측 rrweb record 는 `_app` 또는 전역 레이아웃에 조건부 마운트.

신규 = `support_sessions` 테이블 + `/support` Socket.io 게이트웨이 + 고객 rrweb record 통합 + 지원팀 replay 뷰어 페이지. 모두 아직 존재하지 않음 — 이 phase 1차 산출물.

## 기술 스택 (repo 실제 — 초안과의 차이 반영)

| 항목 | 초안 (standalone) | **Phase 41 정식 (repo 적합)** |
|------|-------------------|-------------------------------|
| 서버 | Node.js + 생 `ws` 별도 서버 | **NestJS `@WebSocketGateway({ namespace: '/support' })`** (기존 Socket.io 서버 재사용) |
| DB | 별도 `pg` Pool | **Sequelize 싱글턴 pool + 신규 `SupportSession` 모델** (`pool.connect()` 미사용, 짧은 쿼리만) |
| 인증 | UUID만 | **JWT + permission 게이트 뒤 뷰어** + UUID 는 세션 식별자 |
| 프론트 record | 바닐라 | rrweb `record` — Next.js `_app` 조건부 마운트 |
| 프론트 replay | 단일 html | rrweb `Replayer` — Next.js 인증 페이지(`pages/soporte/visor.tsx`) |
| ESLint | 후속 | **각 파일 후 `npx eslint --fix`** (Warning=빌드차단 규칙) |

## 보안 설계 (⚠ 사용자 승인 필요 — R-결정)

핵심 주의점: UUID 는 사실상 **"화면 열람 권한 토큰"**. 아래를 기본값(default)으로 제안하며, 변경 원하시면 승인 단계에서 조정.

- **R-1 뷰어 인증** *(LOCKED 2026-06-18)*: 지원팀 뷰어 페이지는 JWT 로그인 + **신규 `support.view` permission_slug** 게이트 뒤에 둔다. Phase 33 RBAC 에 슬러그 신설, 해당 권한 부여 role 만 뷰어 접근. (UUID 유출돼도 외부인/무권한자 접속 불가) → Q1 해소됨.
- **R-2 세션 만료** *(LOCKED 2026-06-18)*: 생성 후 **15분** 또는 고객 연결 종료 시 자동 종료(`status=expired/closed`).
- **R-3 고객 가시성**: 고객 화면에 "지원 세션 진행 중" 배너 + [종료] 버튼 상시 노출.
- **R-4 민감정보 마스킹**: rrweb `maskAllInputs:true` + 결제·암호키 화면(MercadoPago QR / AES 키 / 비밀번호)에 `.rr-block` 차단 클래스.
- **R-5 동시 뷰어 수**: 기본 **1명**.
- **R-6 store-scope**: 세션은 발급 store 의 지원 권한자만 열람(크로스 테넌트 차단).

## Requirements (초안 TASK → 정식 REQ)

1. **REQ-1 — `support_sessions` 모델 + 마이그레이션** *(초안 TASK-1)*
   - Target: `support_sessions`(`id UUID PK, store_id FK, requested_by_user_id FK, status[pending|active|closed|expired], viewer_user_id nullable, created_at, expires_at, closed_at, metadata JSONB`). Sequelize 모델(`underscored:true`). 마이그레이션은 PG10/PG15 호환(`api-ventago/migrations/`).
   - Acceptance: 세션 생성 시 UUID PK + `expires_at = now()+15m` + `store_id` 스코프 기록. 짧은 쿼리만(`pool.connect()` 0회).

2. **REQ-2 — 세션 생성 API + `/support` Socket.io 게이트웨이** *(초안 TASK-2)*
   - Target: `POST /support/sessions`(고객 → UUID 발급), `@WebSocketGateway({ namespace: '/support' })` — 고객 emit `rrweb-event` 릴레이 → 뷰어 room 브로드캐스트. 모든 핸들러 try/catch + async/await. JWT 인증(socket auth.token).
   - Acceptance: 고객 연결→이벤트 송신→뷰어 수신 릴레이 동작. 동시 뷰어 R-5 강제. 만료 세션 연결 거부.

3. **REQ-3 — 고객 측 rrweb record 통합** *(초안 TASK-3)*
   - Target: rrweb `record({ maskAllInputs:true, blockClass:'rr-block' })` → 소켓 emit. "지원 요청" 버튼 + 진행 배너 + [종료]. 명시적 요청 없이는 record 시작 안 됨.
   - Acceptance: 요청 시에만 기록 시작, 종료 버튼/만료 시 즉시 중단, 마스킹 적용.

4. **REQ-4 — 지원팀 라이브 뷰어 페이지** *(초안 TASK-4)*
   - Target: `pages/soporte/visor.tsx` — JWT+permission 게이트, UUID 입력 → `/support` 소켓 join room → rrweb `Replayer` 실시간 재생. **역방향 입력 경로 없음(보기 전용)**.
   - Acceptance: 인증된 지원자만 접근, UUID 로 실시간 DOM 재생, 외부인/타 store 차단(R-1/R-6).

5. **REQ-5 — 배포·보안 체크리스트 문서** *(초안 TASK-5)*
   - Target: `41-RUNBOOK.md`(설치/배포/보안 체크/롤백). 운영 PG10 마이그레이션 적용 순서 포함.
   - Acceptance: 사용자 검토 가능한 단계별 체크리스트.

## 완료 기준

- 고객 UUID 발급 → 지원팀이 그 UUID 로 실시간 화면 확인 가능
- 보기 전용 동작(역방향 입력 경로 0)
- **`pool.connect()` 미사용 → pool 고갈 위험 0** (운영 로그 pool 경고/대기 0건 유지)
- 모든 async 에 try/catch 적용
- ESLint 오류 0개 (`npx eslint . --fix` — `newline-before-return`/`lines-around-comment`/`no-unused-vars` 준수)
- 작업 시작 전 **마지막 로그 파일 확인** (프로젝트 필수 규칙)

## 금지 / 주의사항

- **별도 standalone `ws` 서버 / 신규 `pg` Pool 생성 금지** — 기존 Socket.io 게이트웨이 + Sequelize 싱글턴 pool 재사용 (인프라 이원화·pool 낭비 차단)
- Flutter POS 화면은 범위 밖 (웹 Ventago 만, 후순위)
- `getDisplayMedia`(픽셀 영상) 미사용 — DOM 미러링만
- 고객의 명시적 요청 없이 세션 시작 금지
- 결제·암호키 화면 마스킹 누락 금지 (R-4)
- DB 컬럼은 snake_case (Sequelize `underscored:true`)

## Open Questions

- ~~Q1: 뷰어 권한 매핑~~ → **RESOLVED 2026-06-18: 신규 `support.view` permission_slug 신설 (R-1 LOCKED)**
- Q2: rrweb 이벤트 릴레이를 DB 에 영속화할 것인가(감사 로그) vs 휘발성 릴레이만? (영속화 시 pool/스토리지 영향 검토) — plan-phase 전 결정
- Q3: 운영 배포 시 Socket.io `/support` 네임스페이스 CORS/방화벽 (newapi.coolsistema.com) — RUNBOOK 에서 다룸
