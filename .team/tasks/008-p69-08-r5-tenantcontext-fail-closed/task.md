---
id: 008
title: P69-08 R5 TenantContext fail-closed 전환 + 보안 로그
priority: high
created_at: 2026-07-31T20:16:23.189Z
---

## Task
PLAN: .planning/phases/69-tenant-isolation-security-hardening/69-08-PLAN.md

repo: api-ventago(auth/guards, common/tenant).
빈 catch{} 로 인한 fail-open 제거. @Public/시스템 경로만 명시적 no-op 유지 — 무회귀 케이스를 반드시 함께 넣는다.
