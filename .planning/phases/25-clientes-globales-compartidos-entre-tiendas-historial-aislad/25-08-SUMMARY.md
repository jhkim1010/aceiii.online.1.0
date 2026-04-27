---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 08
subsystem: backend-merge
tags: [merge, optimistic-lock, audit, jsonb, field-pick, d1-04]

requires:
  - 25-04 (ClientMerge audit table + model)
  - 25-07 (promote method + clients.module 모델 등록)
provides:
  - ClientsService.merge(payload, ctx) — opt-lock + field-pick + audit
  - POST /clients/merge endpoint (FunctionGuard manage-clients update)
  - clients-merge.service.spec.ts (6 시나리오)
affects:
  - Wave 5 Frontend (Plan 14) — MergeResolutionDialog 가 winnerUpdatedAt 캡처해서 보내야 함

tech-stack:
  added: []
  patterns:
    - "Optimistic lock via winner.updatedAt timestamp 비교 (T-25-05 race condition 차단)"
    - "Field-pick whitelist: MERGE_ALLOWED_FIELDS = [fullname, nameFantasy, email, phone, address, location, provinceId, transport, resIva]"
    - "Document explicit reject in fieldPicks (D1-04 — winner authoritative)"
    - "ClientMerge audit row 트랜잭션 내 INSERT (mergeReason='promote_conflict' or 'manual_merge')"
    - "StoreClient.findOrCreate (idempotent across retries)"

key-files:
  modified:
    - api-ventago/src/app/clients/clients.service.ts (merge 메서드 추가, MERGE_ALLOWED_FIELDS 상수)
    - api-ventago/src/app/clients/clients.controller.ts (POST /clients/merge)
  created:
    - api-ventago/src/app/clients/clients-merge.service.spec.ts (6 시나리오)

key-decisions:
  - "MERGE_ALLOWED_FIELDS 에 GlobalClient 모델의 실제 컬럼만 포함 — birthdate/notes/city 는 GlobalClient 에 없으므로 제외 (Plan 25-03 의 컬럼 매핑과 일치)"
  - "winnerUpdatedAt 비교 방식: Date 객체면 toISOString(), 그 외엔 String() — Sequelize timestamp 변환 호환"
  - "loserGlobalClientId 는 promote 시나리오에서 null — promote-from-local 은 별도 GlobalClient 가 사라지지 않음 (legacy clients 만 남음)"
  - "audit 실패 시 트랜잭션 rollback — winner.update 도 되돌림 (atomicity 우선)"

patterns-established:
  - "Phase 25 merge 패턴: validation → opt-lock → atomic transaction (4 writes: winner.update + StoreClient.findOrCreate + sales.update + audit.create)"
  - "Stale lock 응답 패턴: ConflictException('STALE_MERGE') — 프론트가 다시 GET /global-clients/:id 호출해 새 winnerUpdatedAt 받아야 함"

requirements-completed:
  - REQ-25-05
  - D1-04

duration: 25min
completed: 2026-04-26
---

# Phase 25 Plan 08: Merge Commit Service Summary

D1-04 field-by-field merge 커밋 구현. 옵티미스틱 락 (winnerUpdatedAt) + whitelist 검증 + ClientMerge audit + atomic transaction.

## API Shape

**Request**:
```http
POST /clients/merge
Authorization: Bearer <jwt>
Content-Type: application/json

{
  "localClientId": 10,
  "winnerGlobalClientId": 99,
  "fieldPicks": {
    "fullname": "local",
    "email": "global",
    "phone": "local"
  },
  "winnerUpdatedAt": "2026-04-23T12:00:00.000Z"
}
```

**Response (Success)**:
```json
{
  "status": "merged",
  "globalClientId": 99,
  "storeClientId": 200,
  "salesRemappedCount": 2,
  "clientMergeAuditId": 1000
}
```

**Errors**:
- `400` — fieldPicks 에 'document' 또는 화이트리스트 외 필드 (D1-04)
- `400` — pick value 가 'local'/'global' 아님
- `404` — winner GlobalClient 가 caller ownerGroup 에 없음
- `404` — localClientId 가 caller storeId 에 없음
- `409` — `STALE_MERGE` (winner 가 다른 사용자에 의해 수정됨 — 프론트가 재시도)

## Verified

- ✅ `tsc --noEmit` 에러 0건
- ✅ ESLint Phase 25 validators 깨끗 (clients/ 는 OOM 으로 호스트 검증 권장)
- ⏳ Jest spec 6 시나리오 — 호스트 실행 보류

## Frontend Coordination Note

**Plan 25-14 MergeResolutionDialog 구현 시:**
1. promote 응답 (`status='merge_required'`) 받으면 `existingGlobalClient.updatedAt` 을 dialog state 에 저장
2. 사용자 선택 완료 후 POST /clients/merge body 에 `winnerUpdatedAt` 으로 전달
3. 409 STALE_MERGE 응답 시 다이얼로그 갱신 (GET /shared/global-clients/:id 재조회 → 새 updatedAt)

## Self-Check: PASSED

- [x] async merge 메서드 ClientsService 에 존재
- [x] MERGE_ALLOWED_FIELDS 화이트리스트 + document 거부 분기
- [x] winner.updatedAt 비교 + ConflictException('STALE_MERGE')
- [x] sequelize.transaction + commit/rollback
- [x] ClientMerge.create with mergeReason 분기 (promote_conflict / manual_merge)
- [x] POST /clients/merge 엔드포인트 + @FunctionGuard
- [x] 6-scenario spec (happy / stale / invalid field / document blocked / rollback / not found)

---
*Completed: 2026-04-26*
