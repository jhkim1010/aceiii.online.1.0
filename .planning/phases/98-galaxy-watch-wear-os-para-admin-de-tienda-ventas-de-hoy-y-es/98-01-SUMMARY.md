---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 01
subsystem: auth
tags: [nestjs, sequelize, postgres, rfc8628, jwt, device-pairing]

# Dependency graph
requires:
  - phase: admin-device-token (auth)
    provides: "토큰 해시·isUsable 패턴, listDevices/revokeById 모양"
provides:
  - "watch_devices + watch_pairing_codes 테이블 (로컬 5432 + 운영 5434, owner coolsistema)"
  - "RFC 8628 분리 코드 페어링 5개 엔드포인트 (발급·claim·poll·목록·회수)"
  - "watch-token.util.ts 순수 함수 (코드/시크릿 생성·해시·usable 판정)"
  - "storeFilteredRoleSlugs/loadUserWithStoreRoles 공유 유틸 — issueAccessToken 과 워치 claim 이 같은 매장 필터 로직 사용"
affects: [98-02, 98-03, 98-04, 98-05, 98-06, 98-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "RFC 8628 분리 코드(userCode 사람 입력 / deviceCode 워치 폴링) 페어링"
    - "원자적 조건부 UPDATE ... WHERE x IS NULL RETURNING 으로 경합 방지 (claim/poll)"
    - "권한 판정은 서버에서 역할을 다시 읽어 재검증 (UserRoleGuard 만 믿지 않음)"

key-files:
  created:
    - api-ventago/migrations/2026-10-04-watch-devices.sql
    - api-ventago/src/app/watch/watch-device.model.ts
    - api-ventago/src/app/watch/watch-pairing-code.model.ts
    - api-ventago/src/app/watch/watch-token.util.ts
    - api-ventago/src/app/watch/dto/watch-pairing.dto.ts
    - api-ventago/src/app/watch/watch-pairing.service.ts
    - api-ventago/src/app/watch/watch-pairing.controller.ts
    - api-ventago/src/app/watch/watch.module.ts
    - api-ventago/src/app/auth/store-filtered-roles.ts
  modified:
    - api-ventago/src/app/auth/auth.service.ts
    - api-ventago/src/app/store/store-backup-coverage.ts
    - api-ventago/src/app/store/store-backup-inventory.txt
    - api-ventago/src/app.module.ts
    - .planning/intel/db-schema-tables.md
    - .planning/intel/db-schema-fks.md

key-decisions:
  - "운영 DDL 적용 전 SQL 전문 + 예상 영향(기존 행 0, 새 테이블 2)을 사용자에게 제시 후 '승인' 받고서 실행 — CLAUDE.md 운영 DML/DDL 승인 규칙 그대로 따름"
  - "운영 push 는 이 계획에서 하지 않음 — 98-02(resumen 가드)가 재설계 대상이라 서버 코드가 아직 운영에 나갈 준비가 안 됨. 테이블만 운영에 존재하고 아무 코드도 안 읽는 상태(w4-exempt 근거와 일치)"
  - "claim 의 역할 판정은 UserRoleGuard 에 의존하지 않고 loadUserWithStoreRoles 로 서버에서 재조회 — 메모리 user-roles-need-store-filter 적용"

requirements-completed: [W98-02]

# Metrics
duration: 64min
completed: 2026-10-04
---

# Phase 98 Plan 01: 워치 페어링 서버 (테이블 + 코드 유틸 + 페어링 엔드포인트) Summary

**RFC 8628 분리 코드로 Galaxy Watch 를 admin 휴대폰과 결속하는 서버 측 전부 — watch_devices/watch_pairing_codes 테이블(로컬+운영 동시 적용, owner coolsistema), 해시 기반 토큰·코드 유틸, 그리고 발급/claim/poll/목록/회수 5개 엔드포인트.**

## Performance

- **Duration:** 64 min (Task 1 시작 ~17:43 UTC → Task 3 운영 적용·대조 완료 ~18:47 UTC)
- **Started:** 2026-10-04T17:43:41Z
- **Completed:** 2026-10-04T18:47:40Z
- **Tasks:** 3 (Task 1, 2 는 이전 세션에 완료·커밋됨; 본 세션은 Task 3 재개부터)
- **Files modified:** 16 (api-ventago 15개 + root intel 2개 — 일부 중복 집계)

## Accomplishments
- `watch_devices`·`watch_pairing_codes` 테이블이 로컬 5432 와 운영 5434 양쪽에 동일한 스키마(컬럼·인덱스·owner)로 존재
- 워치 토큰은 DB 에 sha256 해시만 저장, 원문은 claim/poll 응답에 한 번만 노출
- claim 경로는 UserRoleGuard 외에 서버에서 역할을 재조회해 'admin' + storeId 를 확인(T-98-03 완화)
- claim/poll 경합은 조건부 UPDATE ... RETURNING 으로 단일 행만 성공하도록 보장(T-98-01/T-98-05 완화)
- `issueAccessToken`과 워치 claim 이 `storeFilteredRoleSlugs` 하나를 공유 — 매장 필터 로직 중복 제거

## Task Commits

Each task was committed atomically (api-ventago 저장소):

1. **Task 1: 마이그레이션 + 모델 + 유틸 + 공유 역할 유틸 (로컬 적용까지)**
   - `d2856d06` feat: watch_devices + watch_pairing_codes migration y modelos
   - `258aefd6` test: RED — watch-token.util behavior spec
   - `4d5e95c1` feat: implement watch-token.util
   - `1e41e405` test: store-filtered-roles.spec
   - `7b5fe510` feat: extract storeFilteredRoleSlugs/loadUserWithStoreRoles
   - `a391a21c` refactor: auth.service.ts usa el filtro de roles compartido
   - `a1864a09` chore: declarar watch_devices/watch_pairing_codes excluidas del backup
   - root: `7732430` docs(98-01): regen db schema intel tras migración watch_devices
2. **Task 2: 페어링 서비스·컨트롤러 (발급·claim·poll·목록·회수)**
   - `d4cf7a82` test: watch-pairing.spec — 5 endpoints
   - `e2a9b64d` feat: DTOs de pairing
   - `99e92f70` feat: WatchPairingService
   - `50324446` feat: WatchPairingController + WatchModule — registrado en AppModule
3. **Task 3: 운영(5434) DDL 적용 → 양쪽 스키마 대조** — 코드 커밋 없음(DDL 실행 + 검증만). 사용자 승인("승인") 후 `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/2026-10-04-watch-devices.sql` 실행, BEGIN...COMMIT 정상 종료.

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP)

_Note: Task 1·2 는 TDD(RED→GREEN) 커밋 분리가 되어 있다._

## Files Created/Modified
- `api-ventago/migrations/2026-10-04-watch-devices.sql` - 두 테이블 DDL, owner/시퀀스 coolsistema 이전, w4-exempt 헤더
- `api-ventago/src/app/watch/watch-device.model.ts` / `watch-pairing-code.model.ts` - sequelize-typescript 모델, 명시적 DataType
- `api-ventago/src/app/watch/watch-token.util.ts` - generateUserCode/normalizeUserCode/formatUserCode/generateWatchSecret/hashWatchSecret/isWatchDeviceUsable
- `api-ventago/src/app/auth/store-filtered-roles.ts` - storeFilteredRoleSlugs/loadUserWithStoreRoles, auth.service.ts 가 이를 호출
- `api-ventago/src/app/watch/watch-pairing.service.ts` / `watch-pairing.controller.ts` / `dto/watch-pairing.dto.ts` / `watch.module.ts` - 5개 엔드포인트
- `api-ventago/src/app/store/store-backup-coverage.ts` - EXCLUDED_TABLES 에 두 테이블 등록(이유 포함)
- `.planning/intel/db-schema-tables.md` / `db-schema-fks.md` - 로컬 재생성 반영

## Decisions Made
- 운영 DDL 적용은 CLAUDE.md 「운영 서버 직접 접근 규칙」대로 SQL 전문 + 예상 영향(기존 행 0)을 먼저 제시하고 사용자 승인("승인") 후 실행
- 이 계획에서는 push 하지 않음 — api-ventago 변경은 로컬 커밋에만 머물러 있고, 다음 플랜(98-02 등)에서 resumen 가드가 재설계된 뒤 함께 배포 여부를 orchestrator 가 결정
- claim 의 권한 판정은 가드에만 맡기지 않고 서비스 내부에서 역할을 재조회(T-98-03)

## Deviations from Plan

None - 이번 세션(Task 3 재개)은 계획대로 운영 승인 → 적용 → 대조만 수행했다. Task 1·2 의 편차는 이전 세션 완료분에 포함(해당 커밋 메시지 참조).

## Issues Encountered
None - 운영 마이그레이션은 BEGIN...COMMIT 정상 종료, 양쪽 대조(테이블 owner·시퀀스 owner·컬럼·인덱스) 전부 diff 없음.

## User Setup Required

None - 외부 서비스 설정 필요 없음. (운영 DB 변경은 이 플랜 안에서 완료됨.)

## Next Phase Readiness

- 98-02(워치 토큰 가드 + `/watch/resumen`)가 이 플랜의 테이블·유틸을 바로 쓸 수 있음
- **범위 변경 공지:** 이 플랜 완료 후 Phase 98 전체 범위가 98-CONTEXT(D-08~D-11, mockup v2)로 확장됨. 98-01(페어링)은 이 확장과 무관하게 완결 상태이나, 98-02 이후 플랜은 재계획(replan) 대상이다.
- push 보류 상태 — orchestrator 가 98-02 재설계 완료 시점에 api-ventago push/배포 여부를 결정해야 함

## Known Stubs

None - 이 플랜의 코드는 전부 실제 DB 를 거치며, placeholder/하드코딩 빈 값 없음.

## Threat Flags

None - 이 플랜이 추가한 표면(5개 엔드포인트, 2개 테이블)은 모두 계획의 threat_model(T-98-01~T-98-09)에 등록되어 있으며 새로 발견된 미등록 표면 없음.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 10 created files verified present; all 12 referenced commits (11 api-ventago + 1 root) verified in `git log --oneline --all`. No missing items.
