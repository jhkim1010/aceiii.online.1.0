---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 07
subsystem: backend-promote
tags: [promote, transaction, cuit, dni, owner-group, atomic]

requires:
  - 25-01 (DB owner_group_id)
  - 25-02 (sales.store_client_id)
  - 25-03 (legacy data migration)
  - 25-04 (ClientMerge model)
  - 25-09 (CUIT/DNI validators)
provides:
  - ClientsService.promote(localClientId, ctx) — atomic transaction
  - POST /clients/:id/promote endpoint (FunctionGuard manage-clients update)
  - clients.module.ts 에 GlobalClient/StoreClient/Sale/ClientMerge 모델 등록
  - clients-promote.service.spec.ts (호스트 실행 보류)
affects:
  - Wave 3 Plan 08 — merge 서비스가 동일 ClientsService 에 추가됨
  - Wave 5 Frontend (Plan 14) — promote 응답의 status/conflictFields 처리

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic transaction (sequelize.transaction) — try/commit/catch/rollback"
    - "validators 모듈 import (Plan 09 작성) — CUIT mod11 + AFIP Pitfall 5"
    - "Conflict detection: same (ownerGroupId, document) GlobalClient 검색 → 있으면 status='merge_required' (no writes)"
    - "sales.store_client_id IS NULL guard — 멱등 backfill"
    - "Cross-store 차단: legacy client 조회 시 storeId=ctx.storeId 강제"

key-files:
  modified:
    - api-ventago/src/app/clients/clients.module.ts (GlobalClient + StoreClient + Sale + ClientMerge 등록)
    - api-ventago/src/app/clients/clients.service.ts (promote 메서드 + constructor 확장)
    - api-ventago/src/app/clients/clients.controller.ts (POST /clients/:id/promote)
  created:
    - api-ventago/src/app/clients/clients-promote.service.spec.ts (6 시나리오)

key-decisions:
  - "promote 는 conflict 발생 시 DB 변경 없이 status='merge_required' + conflictFields payload 반환 — 사용자 결정 후 merge 엔드포인트로 별도 호출"
  - "CrudService 상속 유지 — 기존 generic CRUD 깨지 않음. 새 메서드만 추가."
  - "clients.note 는 store_clients.note 로 이관 (매장 비공개 데이터 보존, GlobalClient 에 없는 컬럼)"
  - "promote 시 isActive: true 강제 (D1-03 — 활성화된 글로벌만 노출)"
  - "salesRemappedCount 반환 — 프론트 토스트에 '2 ventas remapped' 표시 가능"

patterns-established:
  - "Phase 25 promote 패턴: 검증 → conflict 검색 → atomic transaction (3 writes) → rollback on error"
  - "Conflict payload 구성: existingGlobalClient + localClient + conflictFields[] (field, localValue, globalValue)"

requirements-completed:
  - REQ-25-05
  - REQ-25-06
  - D1-02
  - D1-03

# Metrics
duration: 30min
completed: 2026-04-26
---

# Phase 25 Plan 07: Promote Service Summary

레거시 clients → GlobalClient 승격 atomic 트랜잭션 + 충돌 감지 + cross-store/cross-group 차단 구현. Plan 25-09 validators 사용. TypeScript 컴파일 통과.

## API Shape

**Request**:
```http
POST /clients/10/promote
Authorization: Bearer <jwt>
```

**Response (Success)**:
```json
{
  "status": "promoted",
  "globalClientId": 100,
  "storeClientId": 200,
  "salesRemappedCount": 3
}
```

**Response (Conflict)**:
```json
{
  "status": "merge_required",
  "existingGlobalClient": { "id": 99, "fullname": "Juan B", "email": "b@b.com", "ownerGroupId": 1, "updatedAt": "2026-04-26T..." },
  "localClient": { "id": 10, "fullname": "Juan A", "email": "a@a.com" },
  "conflictFields": [
    { "field": "fullname", "localValue": "Juan A", "globalValue": "Juan B" },
    { "field": "email", "localValue": "a@a.com", "globalValue": "b@b.com" }
  ]
}
```

**Errors**:
- `400` — document missing / invalid CUIT (Pitfall 5: calc==10) / DNI 길이 잘못
- `404` — client not found in caller storeId (cross-store 차단)
- `403` — FunctionGuard 'manage-clients' 'update' 권한 없음

## Verified

- ✅ `tsc --noEmit` 에러 0건
- ✅ ESLint (Phase 25 validators 단독) 에러 0건
- ⏳ Jest spec (clients-promote.service.spec.ts) 6 시나리오 — 호스트 실행 보류

## Self-Check: PASSED

- [x] async promote 메서드 ClientsService 에 존재
- [x] CUIT/DNI validator import (validators/{cuit,dni}.validator.ts)
- [x] conflict 시 status='merge_required' 반환, no writes
- [x] sequelize.transaction + commit/rollback
- [x] sales.update WHERE storeClientId IS NULL guard
- [x] POST /clients/:id/promote 엔드포인트
- [x] @FunctionGuard('manage-clients', 'update') 적용
- [x] 6-scenario spec 파일 작성

---
*Completed: 2026-04-26*
