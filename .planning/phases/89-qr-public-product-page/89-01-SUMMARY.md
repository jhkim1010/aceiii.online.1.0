---
phase: 89-qr-public-product-page
plan: 01
subsystem: database
tags: [postgres, sequelize, migrations, store_configs, ventago_leads]

# Dependency graph
requires: []
provides:
  - "store_configs.qr_precio_publico BOOLEAN NOT NULL DEFAULT false (로컬 5432 + 운영 5434 적용 완료)"
  - "ventago_leads 신규 테이블 (로컬 5432 + 운영 5434 적용 완료, owner/sequence coolsistema)"
affects: [89-03, 89-04, 89-05, 89-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "무중단 마이그레이션 규약(lock_timeout, w4-exempt, owner DO 블록) — analog 파일 그대로 재사용"

key-files:
  created:
    - api-ventago/migrations/2026-09-16-phase89-store-configs-qr-precio-publico.sql
    - api-ventago/migrations/2026-09-16-phase89-ventago-leads.sql
  modified: []

key-decisions:
  - "운영 DDL 적용 승인(apply) — 사용자 확정 2026-09-16, 영향 없음(기존 값 변화 없음·신규 빈 테이블)"
  - "Task 1 주석 문구를 'commerce_auto_sync(DEFAULT true)' → 'commerce_auto_sync(기본값이 켜짐인 컬럼)'으로 수정 — plan 자체의 acceptance 기준과 지시된 SQL 원문이 상충했던 것을 해소(SQL 값·이름은 불변)"

patterns-established:
  - "2026-08-28/2026-08-25 analog 마이그레이션 골격을 그대로 재사용 — lock_timeout + owner DO 블록 + w4-exempt 주석"

requirements-completed: [REQ-03, REQ-05]

# Metrics
duration: 25min
completed: 2026-09-16
---

# Phase 89 Plan 01: DB 마이그레이션 (qr_precio_publico + ventago_leads) Summary

**`store_configs.qr_precio_publico`(기본 꺼짐) 컬럼과 `ventago_leads` 리드 수집 테이블을 로컬(5432)·운영(5434) 양쪽에 적용 완료**

## Performance

- **Duration:** 약 25분
- **Started:** 2026-09-16 (checkpoint 승인 대기 시간 제외)
- **Completed:** 2026-09-16T21:09:45-03:00
- **Tasks:** 3/3 완료 (Task 3 은 checkpoint:decision — 사용자 `apply` 승인 후 재개해 완료)
- **Files modified:** 2 (신규 마이그레이션 파일)

## Accomplishments
- `store_configs.qr_precio_publico BOOLEAN NOT NULL DEFAULT false` — 로컬·운영 양쪽 적용, 기존 전 행이 `false`
- `ventago_leads` 신규 테이블 — 로컬·운영 양쪽 생성, `notify_status`/`notified_at` 로 알림 실패 흔적 보존
- 운영 테이블/시퀀스 owner 를 `coolsistema` 로 확인(둘 다 조회로 직접 확인)
- 마이그레이션 규약 spec(`migration-conventions.spec.ts`) 통과 확인
- 89-03·89-04·89-05 코드 배포의 전제 조건 해소 — 이 plan 이 phase 89 의 wave 1 게이트였음

## Task Commits

Each task was committed atomically (서브모듈 `api-ventago` 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순):

1. **Task 1: store_configs 에 qr_precio_publico 추가** - `45dc623a` (api-ventago, feat) + `cf058ef` (root, chore: submodule pointer)
2. **Task 2: ventago_leads 신규 테이블 마이그레이션** - `0cb2193f` (api-ventago, feat) + `2e8b90b` (root, chore: submodule pointer)
3. **Task 3: 로컬 적용 → 운영 승인 → 양쪽 확인** - DB 변경 (소스 파일 커밋 없음). 사용자 승인(`apply`) 후 운영 5434 에 두 마이그레이션 실행, 아래 「적용 확인」 참고.

**Plan metadata:** (final commit — 이 SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/migrations/2026-09-16-phase89-store-configs-qr-precio-publico.sql` - `store_configs.qr_precio_publico` 컬럼 추가 (DEFAULT false) + owner 이전
- `api-ventago/migrations/2026-09-16-phase89-ventago-leads.sql` - `ventago_leads` 신규 테이블 + 인덱스 + owner/sequence 이전

## 적용 확인 (직접 조회 원문)

### 로컬 (5432)
```
$ psql -p 5432 -d ventago -tAc "SELECT count(*) FILTER (WHERE qr_precio_publico), count(*) FROM store_configs;"
0|11

$ psql -p 5432 -d ventago -tAc "SELECT column_name FROM information_schema.columns WHERE table_name='ventago_leads' ORDER BY ordinal_position;"
id
store_id
source_product_id
contact_name
contact_phone
contact_email
message
notify_status
notified_at
created_at
updated_at

$ psql -p 5432 -d ventago -tAc "SELECT count(*) FROM ventago_leads;"
0
```

### 운영 (5434, srv803182)
```
$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \"SELECT count(*) FILTER (WHERE qr_precio_publico) AS on_count, count(*) AS total FROM store_configs;\""
0|13

$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \"SELECT tableowner FROM pg_tables WHERE tablename='ventago_leads';\""
coolsistema

$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \"SELECT sequenceowner FROM pg_sequences WHERE sequencename='ventago_leads_id_seq';\""
coolsistema
```

운영 `store_configs` 전 13행이 `qr_precio_publico=false` — 기존 값·동작에 아무 변화가 없음을 직접 조회로 확인. `ventago_leads` 테이블/시퀀스 owner 모두 `coolsistema` — 앱 계정의 permission denied 위험 없음.

## Decisions Made
- **운영 DDL 적용 승인**: 사용자가 checkpoint 에서 `apply` 를 선택. 예상 영향(기존 값 변화 없음 + 빈 테이블 1개 생성)대로 적용됨.
- **Task 1 주석 문구 수정**: plan 이 지시한 SQL 원문 주석에 `commerce_auto_sync(DEFAULT true)` 라는 문자열이 있었는데, 같은 Task 의 acceptance 기준은 "`DEFAULT true` 문자열이 없어야 한다"였다. SQL 값·컬럼명·구조는 전혀 바꾸지 않고 주석 표현만 `commerce_auto_sync(기본값이 켜짐인 컬럼)`으로 바꿔 두 요구를 동시에 만족시켰다 (사용자 승인 완료).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] plan 자체의 acceptance 기준과 지시된 SQL 원문 텍스트가 상충**
- **Found during:** Task 1 (store_configs 마이그레이션 작성 직후 acceptance 검증)
- **Issue:** plan 의 `<action>` 이 지시한 정확한 SQL 파일 내용에 주석으로 `commerce_auto_sync`(DEFAULT true) 문구가 포함돼 있었으나, 같은 Task 의 `<acceptance_criteria>` 는 "그 파일에 `DEFAULT true` 라는 문자열이 없다"를 요구해 지시된 원문 그대로 쓰면 acceptance 가 실패하는 모순이었다.
- **Fix:** SQL 값·컬럼명·기본값(`DEFAULT false`)·구조는 그대로 두고, 주석 문구만 `commerce_auto_sync(기본값이 켜짐인 컬럼)`으로 바꿔 의미를 유지하면서 리터럴 문자열 충돌을 없앴다.
- **Files modified:** `api-ventago/migrations/2026-09-16-phase89-store-configs-qr-precio-publico.sql`
- **Verification:** `grep -c "DEFAULT true"` → 0, `npx jest src/common/migrations --maxWorkers=1` 통과(5/5)
- **Committed in:** `45dc623a` (Task 1 커밋 — 편집 후 커밋했으므로 최종본에 반영됨)

---

**Total deviations:** 1 auto-fixed (Rule 1 — plan 내부 모순 해소, 사용자 승인 완료)
**Impact on plan:** SQL 의 실제 동작(컬럼명·타입·기본값·owner 이전)은 전혀 바뀌지 않았다. 사람이 읽는 주석 표현만 조정. 스코프 확장 없음.

## Issues Encountered
None - 두 마이그레이션 모두 로컬·운영에서 오류 없이 한 번에 적용됨.

## User Setup Required
None - 외부 서비스 설정 불필요.

## Next Phase Readiness
- 89-03·89-04·89-05(코드 배포 대상)가 이제 `store_configs.qr_precio_publico`·`ventago_leads` 를 안전하게 읽고 쓸 수 있다 — 양쪽 DB 스키마가 일치한다.
- ★ 세 번째 마이그레이션(`prices` UNIQUE, `CONCURRENTLY`)은 89-10 에서 별도로 처리 예정 — 이 plan 의 범위 밖.
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-16*

## Self-Check: PASSED

- FOUND: api-ventago/migrations/2026-09-16-phase89-store-configs-qr-precio-publico.sql
- FOUND: api-ventago/migrations/2026-09-16-phase89-ventago-leads.sql
- FOUND: .planning/phases/89-qr-public-product-page/89-01-SUMMARY.md
- FOUND commit 45dc623a (api-ventago submodule)
- FOUND commit 0cb2193f (api-ventago submodule)
- FOUND commit cf058ef (root)
- FOUND commit 2e8b90b (root)
