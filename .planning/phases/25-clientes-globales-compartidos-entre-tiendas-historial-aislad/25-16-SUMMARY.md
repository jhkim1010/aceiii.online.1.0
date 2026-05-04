---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 16
status: code-complete
deployed: false
date: 2026-05-05
---

# Plan 25-16 SUMMARY — Wave 8 (Hot Fix A): ClientsSyncService 추출 + 4 path 통합

## 목적

운영 진단(2026-05-05)에서 발견된 누수 차단:
- `clients` 50 row 중 거의 전부가 `global_clients` 미매핑 (LEFT JOIN unmatched)
- 자동 sync 가 작동하던 path 는 POS `createWithStoreLink` 1개뿐
- import / legacy CRUD / 매장 신규생성 / storeTemplate 등 다른 path 우회

## 변경 내역

### 신규 파일

| 파일 | 역할 |
|------|------|
| [api-ventago/src/app/shared/clients-sync/clients-sync.service.ts](../../../api-ventago/src/app/shared/clients-sync/clients-sync.service.ts) | 단일 sync 진입점 `ClientsSyncService.syncFromLegacy()` + Plan 18 용 bridge 함수 (`attachClientsHook` / `getClientsSyncSingleton`) |
| api-ventago/src/app/shared/clients-sync/clients-sync.module.ts | DI 모듈 |
| api-ventago/src/app/shared/clients-sync/clients-sync.service.spec.ts | 단위 spec (9 cases) |
| api-ventago/src/app/clients/clients-create-with-store-link.spec.ts | smoke test spec — 사용자 시나리오 (`document=20950928434`) 검증 |

### 수정 파일

| 파일 | 변경 |
|------|------|
| api-ventago/src/app/client-import/client-import.service.ts | `ClientsSyncService` 주입 + local bucket dedupe 를 `normalizeCuit` 기준으로 변경 + INSERT 직후 sync 호출 (같은 트랜잭션) |
| api-ventago/src/app/client-import/client-import.module.ts | `ClientsSyncModule` import 추가 |
| api-ventago/src/app/clients/clients.service.ts | `ClientsSyncService` 주입 + legacy `create()` → `createWithStoreLink` 위임 + `existingClient` 분기에서 GC 없으면 즉석 sync 호출 (lazy backfill) |
| api-ventago/src/app/clients/clients.module.ts | `ClientsSyncModule` import 추가 |
| api-ventago/src/app/clients/clients-merge.service.spec.ts | 기존 mock 에 `ClientsSyncService` provider 추가 |
| api-ventago/src/app/clients/clients-promote.service.spec.ts | 동일 |

### Plan 16 범위에서 제외된 path

| Path | 이유 |
|------|------|
| `storeTemplate.service.ts:213` (Consumidor Final default client, document='00000000') | 매장 placeholder. 8 자리 숫자라 `isValidDni` 통과하지만 실제 인물 아님. 향후 정책 결정 필요 |
| `store.service.ts:1184` (백업 복원 loop) | 매장 백업 복원 (admin 작업, 드물게 발생). Plan 17 백필 또는 후속 plan 에서 일괄 처리 |

## 핵심 설계 결정

1. **단일 진입점 `ClientsSyncService.syncFromLegacy(legacy, ctx, transaction?)`**
   - `findOrCreate` 기반 → idempotent (Plan 18 hook + service-layer 동시 호출 안전)
   - `normalizeCuit` + `isValidCuit/isValidDni` gate 가 module 진입 직후 적용 → invalid/temp document 즉시 null
   - `ownerGroupId` 가 ctx 에 없으면 `Store.findByPk(storeId)` 로 보강

2. **import dedupe 정규화**
   - 기존: `(c.row.document || '').trim()` 직접 비교 → "20-12345678-9" 와 "20123456789" 가 다른 row 로 처리됨
   - 변경: `normalizeCuit(...)` 기준 set 비교, 조회는 raw + normalized 양쪽으로
   - partial UNIQUE 인덱스 (raw 기준) 는 backstop 으로 유지

3. **lazy backfill (Plan 17 백필 전 단계 효과)**
   - `createWithStoreLink` 의 `existingClient` 분기에서 GC 가 없으면 `syncFromLegacy` 호출
   - 같은 document 로 다시 POST 만 해도 GC/SC 매핑 즉석 생성 → 호출되는 만큼 매핑 복구
   - Plan 17 (전수 백필) 미적용 환경에서도 사용자 smoke test 가 정상 동작

4. **module 의존성**
   - 신규 `ClientsSyncModule` 이 `clients` + `client-import` 모듈에 import
   - `clients-sync` 자체는 `GlobalClient` / `StoreClient` / `Store` 모델만 직접 의존 — 결합도 최소화

## 테스트 결과

| Spec | Cases | Status |
|------|-------|--------|
| `clients-sync.service.spec.ts` | 9 | ✅ all green |
| `clients-create-with-store-link.spec.ts` (smoke) | 3 | ✅ all green |
| `clients-promote.service.spec.ts` (회귀) | 14 | ✅ all green |
| `clients-merge.service.spec.ts` (회귀) | 18 | ✅ all green |
| `cuit.validator.spec.ts` (회귀) | 6 | ✅ all green |
| `dni.validator.spec.ts` (회귀) | 6 | ✅ all green |
| **합계 (clients|client-import 전체)** | **56** | **✅ 56 passed** |

빌드: `npm run build` green.

## Smoke Test 시뮬레이션 — `document=20950928434`

운영 데이터 (Plan 16 미배포 시):
```
clients id=23826 (store 6 "Kim, jung ho",   document=20950928434)
clients id=23827 (store 9 "kim jung ho",    document=20950928434)
global_clients: 0 row
store 6, 9 모두 owner_group=1
```

Plan 16 배포 후 기대 동작 (mock 검증 완료):
```
POST /clients
  body: { storeId: 6, document: '20950928434', fullname: 'Kim, jung ho', phone: '1130123113' }

응답:
  {
    id: 23826,                  ✓ 기존 id 반환
    fullname: 'Kim, jung ho',   ✓ 모든 정보 다시 출력
    document: '20950928434',
    phone: '1130123113',
    storeClientId: <new>,       ✓ lazy backfill 즉석 생성
    globalClientId: <new>,
    alreadyExisted: true        ✓ 멱등 응답
  }

DB 후속 조회 검증:
  SELECT id, owner_group_id, document, fullname FROM global_clients WHERE document='20950928434';
  → 1 row (owner_group_id=1)
  SELECT id, store_id, global_client_id FROM store_clients WHERE global_client_id=<위 id>;
  → store 6 호출 후 1 row
  → store 9 에서 동일 document 호출 후 2 row 누적 (같은 GC, 다른 SC)
```

## 운영 검증 방법 (배포 후)

1. Jenkins `api-coolsistema` job 빌드 → 운영 적용
2. cURL 또는 Postman 으로 위 POST 호출 (auth 토큰 + sessionToken 헤더 포함)
3. SSH 로 운영 DB 검증:
   ```bash
   ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT id, owner_group_id, document, fullname FROM global_clients WHERE document='20950928434';\""
   ```
4. lazy backfill 효과: 시간이 지남에 따라 호출되는 client 들이 점차 `global_clients` 로 매핑됨

## Plan 17 / 18 연결점

- **Plan 17 (Backfill B):** 호출되지 않는 50 건 미매핑 row 일괄 처리. `ClientsSyncService.syncFromLegacy` 그대로 재사용 — 별도 구현 없이 backfill 스크립트 가 호출. **운영 DB write 사용자 명시 승인 필수**
- **Plan 18 (Safety Net C):** Sequelize `@AfterCreate` / `@AfterBulkCreate` hook + bridge 함수 (`attachClientsHook` / `getClientsSyncSingleton`) — 본 plan 의 service.ts 하단에 이미 배치 완료. 모델 hook 만 추가하면 됨

## Follow-up

- [ ] Plan 16 운영 배포 후 smoke test (사용자 검증)
- [ ] Plan 17 운영 백필 사용자 승인
- [ ] Plan 18 hook 추가
- [ ] storeTemplate Consumidor Final placeholder 정책 결정 (글로벌 풀 진입 여부)
- [ ] store.service backup restore loop sync 추가 검토
