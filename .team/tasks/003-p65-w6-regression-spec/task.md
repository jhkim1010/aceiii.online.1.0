---
id: 003
title: P65-W6 6-5 — W6 회귀 spec 을 test:tenant 에 편입
priority: high
created_at: 2026-08-05T06:00:00.000Z
---

## Task
근거: `.planning/phases/65-stock-ledger-truth-and-boundary-hardening/65-W6-AUDIT.md` (6-5 OPEN)

repo: api-ventago. wave 1. **002 와 파일이 겹치지 않는다**(002=소스, 003=테스트). 병렬 가능.

`npm run test:tenant`(`test/tenant/cross-tenant.tenant-spec.ts`)는 Phase 69 R1~R7 만 커버한다.
**W6 케이스는 0건**이다. 6-1~6-4 가 코드로 닫혀 있어도 고정돼 있지 않아 리팩터 한 번에 조용히 풀린다 —
특히 6-2 의 fail-open 은 `if` 분기 하나를 되돌리면 재발한다.

추가할 케이스 (기존 describe 구조와 헬퍼를 그대로 따를 것):
1. `GET /audit-log/store` — **역할 배열이 빈 사용자**가 전 매장 로그를 받지 못한다 (403). ★ 최우선
2. `GET /audit-log/store` — 일반 사용자는 자기 매장만. superadmin + `?storeId=` 미지정일 때만 전체
3. `GET /auditlog/entity/:type/:id` — 타 매장 엔티티의 로그가 반환되지 않는다
4. `adminUpdateUser` — 타 매장 사용자 수정 시 403, `dto.storeId` 변경은 일반 admin 400 / superadmin 허용
5. `remove` — 타 매장 사용자 비활성화 시 403
6. `approve()` — `requestedBy === approverId` 면 403
7. (002 완료 후) threshold 등급 미달 승인자 → 403

주의:
- **구코드에서 실패하는 것을 확인**해야 의미가 있다. Phase 69 가 "구코드 17/20 실패" 를 증거로 남긴 것과 같은 방식으로,
  각 케이스가 `c23ab35` 이전 코드에서 실패함을 확인하고 기록한다. 지금 코드에서 통과만 시키는 테스트는 회귀를 못 잡는다.
- pre-existing 실패 33건(15 스위트)이 있다(`70-BASELINE.md`). 새로 만든 것과 섞이지 않게 구분해 보고한다.
