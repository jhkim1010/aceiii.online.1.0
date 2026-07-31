---
id: 006
title: P69-06 R4 파생 모델 전수 감사 + ProductBranch 양쪽 부모 검증
priority: high
created_at: 2026-07-31T20:16:22.126Z
---

## Task
PLAN: .planning/phases/69-tenant-isolation-security-hardening/69-06-PLAN.md

repo: api-ventago(common/tenant). 
69-03 이 productStock.service.ts 를 먼저 고친 뒤 시작 — 같은 호출부를 건드린다.
.planning/intel/db-schema-fks.md 의 FK 그래프를 근거로 파생 대상을 열거한다(추측 금지).
