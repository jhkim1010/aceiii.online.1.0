---
id: 002
title: P65-W6 6-4 잔여 — approver_role_slug 집행 (승인 등급 SoD)
priority: high
created_at: 2026-08-05T06:00:00.000Z
---

## Task
근거: `.planning/phases/65-stock-ledger-truth-and-boundary-hardening/65-W6-AUDIT.md` (6-4 PARTIAL)

repo: api-ventago. wave 1. **코드 수정 태스크 — 완료 전 codex 검토 필수(.team/REVIEW-PROTOCOL.md).**

`approval_thresholds.approver_role_slug` 는 모델에 있고(`approval-threshold.model.ts:65`) 매장 생성 시
`branch_manager`/`store_admin`/`store_owner` 로 시드되는데(`storeTemplate.service.ts:785-833`)
**읽는 곳이 코드에 0곳**이다. `approve()` 는 자가승인만 막고(`approval.service.ts:190-196`),
컨트롤러는 `@Permission('approval.approve','update')` 하나뿐(`approval.controller.ts:116-128`).

결과: `approval.approve` 권한만 있으면 `store_owner` 승인이 필요한 요청을 `branch_manager` 가 승인할 수 있다.
maker-checker 는 성립하나 **승인 등급(SoD)이 미성립**이다.

해야 할 것: 승인 시 해당 요청에 적용되는 threshold 의 `approverRoleSlug` 를 찾아 승인자 역할과 대조하고,
미달이면 403. 요청→threshold 해석 경로(매장 + functionSlug + 금액 구간)를 먼저 코드에서 확인할 것 —
추측으로 매칭 규칙을 만들지 마라.

주의:
- threshold 가 없는 요청(시드 안 된 매장)에서 **fail-open 금지**. 없으면 어떻게 할지 결정하고 근거를 남긴다.
  Phase 65 W6 6-2 가 정확히 "판정 실패 시 더 주는" 결함이었다.
- superadmin 예외는 기존 `isSuperAdminUser()` 유틸을 쓴다(`tenant-user.util`). 새로 판정 로직을 만들지 마라.
- 무회귀: 정상 승인 흐름이 막히면 운영 승인 큐가 정지한다. 기존 사용 매장의 threshold 시드 상태를 먼저 확인.
