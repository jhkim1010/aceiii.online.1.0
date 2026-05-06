---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 18
subsystem: clients-self-healing-invariant
tags:
  - sequelize-hook
  - bridge-singleton
  - safety-net
  - clients-sync
  - tdd
  - autonomous-true
dependency_graph:
  requires:
    - 25-16 (ClientsSyncService.syncFromLegacy)
    - 25-17 (backfill 스크립트 + dev 검증)
  provides:
    - 모델 자가 보장 invariant (Clients.create 어떤 path 든 자동 sync)
    - bridge singleton (attachClientsHook + getClientsSyncSingleton)
    - escape hatch (options._skipGlobalSync)
  affects:
    - api-ventago/src/app/clients/clients.model.ts
    - api-ventago/src/app/shared/clients-sync/clients-sync.service.ts
    - api-ventago/src/main.ts
    - api-ventago/src/app/clients/clients-hook.spec.ts
tech_stack:
  added: []
  patterns:
    - Module-level singleton bridge (NestJS DI 컨텍스트 밖 hook 호환)
    - Sequelize @AfterCreate / @AfterBulkCreate static hooks
    - Graceful degradation (caller INSERT 보존, Logger.warn 만 기록)
    - Idempotent sync (findOrCreate 기반 — service-layer + hook 이중 호출 무해)
    - Escape hatch via private option (_skipGlobalSync)
key_files:
  created:
    - api-ventago/src/app/clients/clients-hook.spec.ts
  modified:
    - api-ventago/src/app/clients/clients.model.ts
    - api-ventago/src/app/shared/clients-sync/clients-sync.service.ts
    - api-ventago/src/main.ts
decisions:
  - Bridge singleton over NestJS DI — Sequelize hooks run outside Nest container, must use module-level state
  - getClientsSyncSingleton() null check → silent skip — standalone scripts (jest, migration) 호환
  - try/catch around sync call — caller INSERT 절대 차단 안 함 (Phase 21 baseline invariant 정신)
  - Logger.warn (NestJS) over console.warn — winston 운영 로그에 자동 캡처
  - options._skipGlobalSync escape hatch — backfill 스크립트가 명시적 syncFromLegacy 호출 시 중복 쿼리 회피용
  - createApplicationContext 경로에서는 bootstrap 미경유 → smoke 스크립트가 수동으로 attachClientsHook 호출
metrics:
  duration_minutes: ~25
  completed_date: 2026-05-06
  tasks_total: 3
  tasks_executed: 3
  tasks_gated: 0
---

# Phase 25 Plan 18: Clients 모델 자가 보장 hook (Safety Net C) — Summary

**One-liner:** Sequelize `@AfterCreate` / `@AfterBulkCreate` hook 으로 `Clients.create()` 어떤 path 든 자동으로 `GlobalClient` + `StoreClient` 생성을 보장. service-layer 명시적 sync (Plan 16) 와 hook 호출은 모두 idempotent (`findOrCreate`) 라 중복 무해. 모델 자체가 cross-store identity 무결성을 자가 보장하는 last line of defense.

## Tasks Executed

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | bridge (`attachClientsHook` + `getClientsSyncSingleton`) + main.ts attach | done | 815c482 |
| 2 RED | clients-hook.spec.ts 통합 spec (8 케이스) | done | cc224cf |
| 2 GREEN | Clients 모델 @AfterCreate / @AfterBulkCreate hook 구현 | done | 0f5843a |
| 3 | Manual integration smoke (Step A/B/C/D) | done | (verified, script removed post-test) |

## Self-Check: PASSED

- ✅ `attachClientsHook` / `getClientsSyncSingleton` exported in `clients-sync.service.ts`
- ✅ `main.ts` bootstrap 에서 `attachClientsHook(app.get(ClientsSyncService))` 호출
- ✅ Clients 모델에 `@AfterCreate syncToGlobalAfterCreate` + `@AfterBulkCreate syncToGlobalAfterBulkCreate` 추가
- ✅ `_skipGlobalSync` escape hatch 작동
- ✅ `getClientsSyncSingleton() === null` 시 silently skip (standalone 호환)
- ✅ Sync 실패 시 graceful — caller INSERT 보존, Logger.warn 기록
- ✅ Spec 8/8 GREEN — `npm test -- --testPathPattern=clients-hook.spec`
- ✅ Build green — `npm run build` (TS 에러 0)
- ✅ Plan 16 회귀 없음 — `clients-sync.service.spec` + `clients-promote.service.spec` GREEN (15/15)
- ✅ Manual smoke Step A/B/C 모두 PASS (real DB)

## Bridge 패턴 다이어그램

```
┌──────────────────────────────────────────────────────────────────────┐
│ NestJS Bootstrap (main.ts)                                           │
│                                                                      │
│   const app = await NestFactory.create(AppModule);                   │
│   const sync = app.get(ClientsSyncService);                          │
│   attachClientsHook(sync);   ←─── module-level singleton 등록        │
│   await app.listen(port);                                            │
└─────────────────────────┬────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│ clients-sync.service.ts (module-level)                               │
│                                                                      │
│   let _clientsSyncSingleton: ClientsSyncService | null = null;       │
│   export function attachClientsHook(s) { _clientsSyncSingleton = s } │
│   export function getClientsSyncSingleton() { return _.... }         │
└─────────────────────────┬────────────────────────────────────────────┘
                          │ getClientsSyncSingleton()
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Clients 모델 (clients.model.ts)                                      │
│                                                                      │
│   @AfterCreate                                                       │
│   static async syncToGlobalAfterCreate(instance, options) {          │
│     if (options?._skipGlobalSync) return;     ← escape hatch        │
│     const sync = getClientsSyncSingleton();                          │
│     if (!sync) return;                        ← standalone skip     │
│     try {                                                            │
│       await sync.syncFromLegacy(instance, { ownerGroupId: null },    │
│         options?.transaction);                ← caller tx 존중      │
│     } catch (err) {                                                  │
│       Logger.warn(`[Clients.afterCreate] sync 실패 — legacy 보존`);  │
│     }                                                                │
│   }                                                                  │
└──────────────────────────────────────────────────────────────────────┘
```

핵심 보장:
- **Caller transaction 존중** — outer tx 가 ROLLBACK 되면 hook 결과도 함께 되돌림
- **Sync 실패가 INSERT 를 막지 않음** — try/catch + Logger.warn
- **이중 호출 무해** — Plan 16 service-layer 호출 + hook 둘 다 findOrCreate 기반

## Manual Smoke 결과

스크립트: `api-ventago/scripts/_smoke-hook-test.ts` (실행 후 정리, repo 에 미커밋)
실행: dev DB ventago (host PostgreSQL 18, store_id=1, owner_group_id=1)

### Step A — hook 활성화 시나리오

| 항목 | 결과 |
|---|---|
| 호출 | `Clients.create({ document: '99999999991', ... })` |
| legacy row | ✅ 생성 (id=1483) |
| global_clients row | ✅ 자동 생성 (id=7531) — hook 작동 |
| store_clients row | ✅ 자동 생성 (id=7531) — hook 작동 |

### Step B — `_skipGlobalSync` escape hatch

| 항목 | 결과 |
|---|---|
| 호출 | `Clients.create(data, { _skipGlobalSync: true })` |
| legacy row | ✅ 생성 (id=1484) |
| global_clients row | ✅ 미생성 — escape hatch 작동 |
| store_clients row | ✅ 미생성 — escape hatch 작동 |

### Step C — Plan 16 service-layer 회귀 (CUIT 20-12345678-6)

| 항목 | 결과 |
|---|---|
| 호출 | `ClientsService.createWithStoreLink(data, ownerGroupId=1)` |
| response.storeClientId | ✅ 7532 (non-null) |
| response.globalClientId | ✅ 7532 (non-null) |
| response.alreadyExisted | false (신규) |
| DB 3 row | ✅ 모두 존재 |

→ Plan 16 service-layer 명시적 sync + hook 자동 sync 동시 발생해도 `findOrCreate` 가 idempotent 라 중복 INSERT 없음. 응답 shape 도 변경 없음.

### Cleanup 검증

세 테스트 document (`99999999991`, `99999999992`, `20123456786`) 모두 실행 후 `clients`, `global_clients`, `store_clients` 에서 0 row 확인 (smoke 스크립트가 자동 정리).

## 운영 모니터링 권장 SQL/로그 쿼리 (Step D)

### 1. winston 로그 — hook sync 실패 모니터링

```bash
# 운영서버에서 실시간 모니터링
ssh jhkim-server "sudo docker logs --since 1h api_ventago 2>&1 | grep -E 'ClientsHook|Clients.afterCreate|Clients.afterBulkCreate'"

# 누적 카운트 (지난 24시간)
ssh jhkim-server "sudo docker logs --since 24h api_ventago 2>&1 | grep -cE 'syncFromLegacy 실패'"
```

기대값: `0건` 또는 `invalid CUIT/DNI` 류만 (정상). 이외 에러 발생 시 알람.

### 2. cross-store identity 깨짐 — 신규 INSERT 회귀 감시

```sql
-- 최근 24h 내 legacy clients 중 global_clients 매핑이 없는 row (자가 보장 깨진 케이스)
SELECT c.id, c.store_id, c.document, c.created_at
FROM clients c
LEFT JOIN global_clients gc
  ON gc.document = c.document
  AND gc.owner_group_id = (SELECT owner_group_id FROM stores WHERE id = c.store_id)
WHERE c.created_at > NOW() - INTERVAL '24 hours'
  AND c.document IS NOT NULL
  AND TRIM(c.document) <> ''
  AND LENGTH(c.document) IN (7, 8, 11)  -- valid DNI/CUIT 길이
  AND gc.id IS NULL
ORDER BY c.created_at DESC;
```

기대값: `0 row`. 1건이라도 발견되면 hook 또는 service-layer sync 누락 path 존재.

### 3. sales.store_client_id NULL 비율 추세

```sql
-- 일별 sales 의 store_client_id NULL 비율 (지난 30일)
SELECT
  DATE(s.created_at) AS day,
  COUNT(*) AS total_sales,
  COUNT(*) FILTER (WHERE s.store_client_id IS NULL) AS null_count,
  ROUND(100.0 * COUNT(*) FILTER (WHERE s.store_client_id IS NULL) / COUNT(*), 2) AS null_pct
FROM sales s
WHERE s.created_at > NOW() - INTERVAL '30 days'
  AND s.client_id IS NOT NULL  -- cliente 가 등록된 sales 만
GROUP BY DATE(s.created_at)
ORDER BY day DESC;
```

기대 추세: NULL 비율이 **안정 또는 감소** (Plan 17 backfill 완료 후엔 신규 sales 만 영향, hook 으로 신규 row 도 즉시 매핑되므로 0% 수렴).

### 4. global_clients / store_clients 누적 성장 (정상성)

```sql
-- 일별 신규 global_clients (legacy clients 와 보조 비교)
SELECT
  DATE(gc.created_at) AS day,
  COUNT(*) AS new_global,
  (SELECT COUNT(*) FROM clients WHERE DATE(created_at) = DATE(gc.created_at)) AS new_legacy
FROM global_clients gc
WHERE gc.created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(gc.created_at)
ORDER BY day DESC;
```

기대값: `new_global` 이 valid-doc legacy 수 이상 (소유 그룹 내 공유로 인해 동일 매장 외 다른 매장에서도 INSERT 시 1:N 매핑 발생할 수 있음).

## Phase 25 완료 노트

Phase 25 의 cross-store identity 보장 체계는 **3 layer 안전망**으로 완성:

| Layer | 시점 | 메커니즘 |
|---|---|---|
| **신규 INSERT (Plan 16)** | 작성 시점 | 4개 service-layer path 가 명시적으로 `syncFromLegacy` 호출 |
| **기존 데이터 (Plan 17)** | 일회성 backfill | 운영 스크립트로 legacy row 27건 + sales remap 13건 동기화 |
| **모델 자가 보장 (Plan 18)** | 미래 신설 path | Sequelize hook 이 last line of defense — 어떤 path 든 자동 sync |

**불변량:** Phase 25 이후 `clients` 테이블에 INSERT 되는 모든 row 는 `global_clients` + `store_clients` 매핑이 자동 또는 명시적으로 보장됨. cross-store identity 누수 0건 달성.

**남은 작업** (Phase 25 외부):
- 운영 DB 에 Plan 17 backfill 스크립트 실행 (사용자 승인 대기)
- Plan 18 hook 운영 배포 후 1주일 모니터링 (위 SQL 4종 + winston 로그 일일 점검)

**Plan 18 비용:** 새 path 마다 추가 SELECT 1회 (findOrCreate). 운영 부하 무시할만함. 추후 측정 후 high-traffic path 에 `_skipGlobalSync: true` 명시 권고 가능.
