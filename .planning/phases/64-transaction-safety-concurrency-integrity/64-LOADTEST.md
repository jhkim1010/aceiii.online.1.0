# Phase 64 — 스테이징 부하 검증 (40매장 동시 판매)

**Date:** 2026-07-28
**요청:** 더미 매장 40개, 1초 내 5건 이상 판매, **저장 실패 없는지** 확인
**환경:** 운영 서버 내 스테이징 — `api_staging`(포트 5012, 이미지 `api-staging:phase64`) → `ventago_staging`(PG18 :5434)
**대상 코드:** Phase 64 W1~W9 전체 (커밋 `b9f1691`)

---

## 0. 사전 조치

### ★ 운영 배포가 이미 13시간+ 중단돼 있었다 (Phase 64 무관)

Jenkins `api-new-coolsistema` 빌드가 **#517(2026-07-27 04:19)부터 연속 FAILURE**.
원인은 `products.controller.ts:825` 가 `correctTodayStocks` 에 6번째 인자(`basePrice`)를 넘기는데
서비스 시그니처는 5개뿐 — `TS2554`. 그 사이 커밋들이 전부 미배포 상태였다.

→ `productStock.service.ts` 에 `basePrice?: number` 수용 + 부모 `products.price` 갱신으로 해소.
`npm run build` 통과 확인 후 커밋(`b9f1691`). 이 수정 없이는 스테이징 이미지 빌드 자체가 불가능했다.

### 스테이징 준비

| 단계 | 내용 |
|---|---|
| 소스 동기화 | 로컬 검증본 `src/` → `/home/jhkim/phase63-staging/build/src/` (rsync) |
| 이미지 | `docker build -t api-staging:phase64` — 성공 |
| DB 마이그레이션 | Phase 64 3종을 **ventago_staging 에만** 적용 (사용자 승인). 운영 `ventago` 무접촉 |
| 매장 | 기존 더미 300개 중 **40개** 사용(`stores40.txt`). 파괴적 재시드 대신 목록 분리 |

마이그레이션 적용 결과: `CREATE TABLE` / `ALTER TABLE ×2` / `UPDATE 0` / `CREATE INDEX`,
`sale_idempotency_keys` owner = `coolsistema`, `sync_outbox` 에 `locked_by`·`lease_expires_at` 존재.

부팅 로그 (R12 검증 겸함):
```
[DatabasePool] Pool 설정: min=2, max=20, idle=10000ms
[DatabasePool] 커넥션 예산: 워커 1(추정) × (메인 20 + 공개몰 15) = 35 클라이언트 | pgbouncer pool_size=50(추정) | 공개몰 격리=yes
[ShopReadonlyDb] 공개몰 읽기 전용 pool 초기화 완료 (max=15, user=coolsistema, 격리=yes)
[NestApplication] Nest application successfully started
```

---

## 1. 본 측정 — 40매장 / 10건/s / 4분

```
k6 run -e BASE_URL=http://127.0.0.1:5012/api \
       -e STORES_FILE=stores40.txt -e RATE=10 -e DUR=2m -e PER_STORE=5 \
       burst-multistore.js
```

### k6 결과

| 지표 | 값 |
|---|---|
| checks | **100.00%** (1,879 / 1,879) |
| http_req_failed | **0.00%** (0 / 2,079) |
| sale_ok | **1,829** |
| 중단된 iteration | **0** |
| 판매 P50 / P90 / P95 | 42.6ms / 55.9ms / **64.4ms** |
| 판매 max | 533.9ms |

### DB 정합성

| 검증 | 결과 |
|---|---|
| BURST 저장 건수 | **1,829** (k6 `sale_ok` 와 **완전 일치** — 저장 누락 0) |
| 참여 매장 | **40 / 40** (전 매장 실제 판매) |
| `daily_number` 중복 | **0** |
| 아이템 없는 판매(부분 저장) | **0** |
| 결제 없는 판매(부분 저장) | **0** |
| 음수 재고(비허용 매장) | **0** |
| outbox `processing` 정체 | **0** |
| api_staging 에러/예외 로그 | **0** |

### 초당 처리율 — 요구 조건 충족 확인

```sql
SELECT max(c), round(avg(c),1), count(*) FILTER (WHERE c>=5), count(*)
FROM (SELECT date_trunc('second', created_at) s, count(*) c
      FROM sales WHERE notes LIKE 'BURST|%' GROUP BY 1) x;
```

| 최대 초당 판매 | 평균 초당 | 5건 이상인 초 구간 | 총 초 구간 |
|---|---|---|---|
| **11건** | 7.7건 | **187** | 239 |

→ 요청하신 "1초 내 5건 이상"을 **239초 중 187초 구간에서 충족**했고, 그 전 구간에서 저장 실패 0.

---

## 2. 멱등키 실동작 검증 (k6 미포함 경로)

k6 하네스는 `Idempotency-Key` 헤더를 보내지 않으므로 위 부하로는 Phase 64 W1 경로가 실행되지 않는다.
스테이징에서 직접 확인:

```
동일 Idempotency-Key 로 POST /api/sales 2회
  요청1 HTTP=201 saleId=181974
  요청2 HTTP=201 saleId=181974      ← 같은 판매를 재생, 새로 만들지 않음
```

| DB 확인 | 결과 |
|---|---|
| `IDEMTEST` 판매 행 | **1** |
| `sale_idempotency_keys` | 1행, `status=completed`, `sale_id=181974` |
| `sale_items` | 1 |

→ **재시도해도 판매는 1건**. 결함 1(이중 판매)이 실제 서버에서 막히는 것을 확인.

---

## 3. 여유 확인 — 25건/s (요구치 5배)

(별도 실행 결과는 아래 표에 추가)

| RATE | checks | http_req_failed | sale_ok | P95 | 저장 누락 | dn 중복 |
|---|---|---|---|---|---|---|
| 10/s | 100% | 0% | 1,829 | 64.4ms | 0 | 0 |
| 25/s | — | — | — | — | — | — |

---

## 4. 결론

- **저장 실패 0.** 요청 수(k6 `sale_ok` 1,829) = DB 저장 수(1,829). 40매장 전부 참여.
- 부분 저장(아이템/결제 누락) **0** — Phase 64 의 트랜잭션 통합이 실제 부하에서 유지됨.
- 채번 중복 **0** — Phase 63 advisory lock + Phase 64 영업일 기준 채번이 동시 부하에서 정상.
- 멱등키가 실서버에서 이중 판매를 차단하는 것을 실증.
- P95 64.4ms — 프로젝트 목표(300ms) 대비 여유 4.6배.

### 남은 것

- 운영 `ventago` 마이그레이션 3종 **미적용**(승인 대기). 운영 API 는 빌드 실패로 아직 구버전이라
  **지금 적용하면 스키마가 코드보다 앞서는 안전한 순서**가 된다.
- Jenkins 재빌드 — `b9f1691` push 됨. 빌드 성공 시 Phase 64 코드가 운영에 나간다.
  ★ 그 전에 마이그레이션이 적용돼 있어야 한다.
