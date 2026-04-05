---
phase: 01-ui-ux
plan: "01"
subsystem: api
tags: [nestjs, sequelize, postgresql, users, auth]

# Dependency graph
requires: []
provides:
  - "Users 모델에 uiMode ENUM 컬럼 (classic|new, default: classic)"
  - "PUT /users/ui-mode 엔드포인트 (admin/superadmin 전용)"
  - "/auth/me 응답에 uiMode 필드 포함"
affects:
  - "02: 프론트엔드에서 uiMode 토글 UI 구현 시 이 API 사용"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sequelize ENUM 컬럼 선언 패턴 (DataType.ENUM + underscored: true)"
    - "NestJS 라우트 우선순위 관리 — 정적 경로를 :param 경로 위에 배치"

key-files:
  created: []
  modified:
    - api-ventago/src/app/users/users.model.ts
    - api-ventago/src/app/auth/auth.service.ts
    - api-ventago/src/app/users/users.controller.ts
    - api-ventago/src/app/users/users.service.ts

key-decisions:
  - "PUT /users/ui-mode 엔드포인트를 @Get(':id') 라우트보다 위에 배치하여 NestJS 라우트 우선순위 문제 방지"
  - "uiMode 유효성 검증을 컨트롤러에서 수행 (BadRequestException) — DB 에러 전 사전 차단"

patterns-established:
  - "ENUM 컬럼 추가 시 Sequelize underscored 자동 변환 활용 (uiMode → ui_mode)"

requirements-completed:
  - TOGGLE-01

# Metrics
duration: 8min
completed: 2026-04-05
---

# Phase 01 Plan 01: UI Mode Backend API Summary

**Users 테이블에 ui_mode ENUM 컬럼 추가 + PUT /users/ui-mode 엔드포인트(admin/superadmin 전용) + /auth/me 응답에 uiMode 포함**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-05T23:03:07Z
- **Completed:** 2026-04-05T23:11:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Users 모델에 uiMode ENUM 컬럼 정의 (Sequelize underscored: true → DB 컬럼명 `ui_mode`)
- /auth/me 응답에 uiMode 필드 포함 — 프론트엔드에서 현재 UI 모드 즉시 확인 가능
- PUT /users/ui-mode 엔드포인트 구현 — admin/superadmin만 접근 허용, 유효성 검증 포함

## Task Commits

1. **Task 1: Users 모델에 uiMode 컬럼 추가 + /me 응답 포함** - `9a38596` (feat)
2. **Task 2: PUT /users/ui-mode 엔드포인트 추가** - `b1078bd` (feat)

## Files Created/Modified

- `api-ventago/src/app/users/users.model.ts` - uiMode ENUM 컬럼 추가 (classic|new, default: classic)
- `api-ventago/src/app/auth/auth.service.ts` - /me 응답 result 객체에 uiMode 필드 추가
- `api-ventago/src/app/users/users.service.ts` - updateUiMode 메서드 추가
- `api-ventago/src/app/users/users.controller.ts` - PUT ui-mode 엔드포인트 추가 + BadRequestException import

## Decisions Made

- PUT /users/ui-mode 엔드포인트를 `@Get(':id')` 라우트보다 위에 배치 — NestJS 라우트 매칭에서 정적 경로가 동적 경로(:param)보다 먼저 처리되어야 함
- 유효성 검증을 컨트롤러에서 수행 — DB 레이어 도달 전 사전 차단으로 명확한 에러 메시지 제공

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None — 모든 기능이 실제 DB와 연동되어 동작함.

## User Setup Required

운영 서버에서 DB 마이그레이션 필요:
```sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='ui_mode') THEN
    CREATE TYPE ui_mode_enum AS ENUM ('classic', 'new');
    ALTER TABLE users ADD COLUMN ui_mode ui_mode_enum DEFAULT 'classic';
  END IF;
END $$;
```
로컬 개발 환경에서는 Sequelize sync가 자동으로 처리.

## Next Phase Readiness

- uiMode 백엔드 인프라 완료 → 프론트엔드 토글 UI 구현 가능
- /auth/me 응답에 uiMode 포함 → AuthContext에서 바로 접근 가능
- PUT /users/ui-mode API 준비 완료 → 설정 화면에서 즉시 연동 가능

---
*Phase: 01-ui-ux*
*Completed: 2026-04-05*
