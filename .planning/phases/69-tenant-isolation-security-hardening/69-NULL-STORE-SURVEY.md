# 69-08 실측 — `store_id` 가 NULL 인 사용자

**측정일**: 2026-08-01 · **대상**: 운영(5434) · 로컬(5432) · **방식**: SELECT 만

## 목적

`jwt-global.guard.ts` 를 fail-closed 로 바꾸면 두 종류의 요청이 403 이 된다:

1. `TenantContext` 확정 실패(예외 또는 ALS 스코프 없음)
2. `resolved=true` 지만 `storeId === null` + `isSuperAdmin === false` + `system === false`
   — `tenant-hooks.allowedStores()` 가 `null` 을 돌려줘 **격리가 전부 no-op** 이 되는 상태

2번을 막으면 실제로 누가 못 쓰게 되는지 먼저 센다.

## Q1 — `store_id` 가 NULL 인 사용자와 역할

```sql
SELECT u.id, u.email, u.username, u.store_id,
       string_agg(DISTINCT r.slug, ',') AS roles
  FROM users u
  LEFT JOIN user_roles ur ON ur.user_id = u.id
  LEFT JOIN roles r ON r.id = ur.role_id
 WHERE u.store_id IS NULL
 GROUP BY u.id, u.email, u.username, u.store_id
 ORDER BY u.id;
```

**운영(5434)**

| id | email | username | store_id | roles |
|---|---|---|---|---|
| 1 | superadmin@ventago.test | superadmin@app | NULL | superadmin |

**로컬(5432)** — 동일 1행 (같은 superadmin 계정)

## Q2 — superadmin 이 아닌 NULL 계정 (= fail-closed 로 막힐 후보)

**운영 0명 · 로컬 0명.**

## 판정

fail-closed 를 켜도 **막히는 정상 사용자가 없다**. NULL `store_id` 는 superadmin 전용이고,
가드는 `isSuperAdmin` 을 먼저 확인해 통과시킨다.

`users.store_id` 는 스키마상 nullable 이므로 앞으로 매장 미배정 계정이 생길 수 있다.
그 계정은 이제 로그인은 되지만 매장 데이터 요청에서 403 을 받는다 — 격리가 꺼진 채
전 매장을 훑는 것보다 안전한 실패다. 로그(`[TENANT-CTX] 매장 미배정 사용자`)로 즉시 식별된다.

## 배포 후 확인 (2026-08-01)

화면 8종 순회 + API 4종 호출에서 `TENANT-CTX` 차단 로그 **0건**, 신규 403 **0건**.
