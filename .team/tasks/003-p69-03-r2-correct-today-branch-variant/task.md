---
id: 003
title: P69-03 R2 correct-today branch/variant 소유권 검증 + 단일 트랜잭션
priority: high
created_at: 2026-07-31T20:16:20.447Z
---

## Task
PLAN: .planning/phases/69-tenant-isolation-security-hardening/69-03-PLAN.md

repo: api-ventago. wave 1.
branchIds(Branch.storeId)와 variantId(parentId 자식 + 동일 storeId) 둘 다 검증해야 사슬이 닫힌다. 한쪽만 하면 미완이다.
stocks 는 append-only — UPDATE/DELETE 금지, product_branch_id 기준(product_id 컬럼 없음).
