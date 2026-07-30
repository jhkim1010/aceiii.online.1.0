# Phase 66 W5-5 / W6-3 — 부하 재측정 결과

**측정일:** 2026-07-29 23:0x~23:2x ART (서버 UTC 02:0x~02:2x, 2026-07-30)
**환경:** 운영 서버 내 스테이징 — `api_staging`(5012, pm2 4워커, 운영 이미지 = W5/W6 코드 포함) + `ventago_staging`(전용 pgbouncer 6432 → PG18 5434) + `ventago_redis_staging`
**활성 매장:** 6 / 9 / 13 (3, 8, 11, 13 중 3·8·11 은 2026-07-23 소프트삭제 → 로그인 시 `Tienda no disponible` 401. STORES 파라미터를 6,9,13 으로 교정)
**운영 상태:** 측정 전 load 0.02, api_ventago CPU 0.8% — 실사용 0. watchdog 가동, 개입 없음.

---

## 0. 측정 전 복구 작업 (기록)

| 문제 | 원인 | 조치 |
|---|---|---|
| 스테이징 DB 인증 실패 (`password authentication failed for user "coolsistema"`) | ① 스테이징 전용 pgbouncer(PID 223145)가 7/27부터 가동 중이라 갱신된 auth 파일을 캐시하고 있었음 ② `.env.staging` 의 `DATABASE_PASSWORD` 가 오늘 "shop pool 인증 복구" 이전 값 | ① pgbouncer-staging 재기동 ② 운영 `.env` 의 `DATABASE_PASSWORD` 를 `.env.staging` 에 동기화 후 컨테이너 재생성 |
| ※ 함정 | 앱이 읽는 변수는 `DATABASE_PASSWORD` (`src/config/env.config.ts:25-29`). `DB_PASSWORD` 는 별개(compose/psql 용) — 이것만 맞춰도 부팅 실패 | 다음 측정 시 `DATABASE_*` 우선 확인 |

---

## 1. W5-2 /me 응답 크기 — 목표 <10KB

| 항목 | 슬림화 전 (Phase 63 실측) | 슬림화 후 (실측) | 감소 |
|---|---|---|---|
| **전체 /me** | 약 55,000 B | **21,260 B** (1회차) / 21,352 B (2회차) | **−61%** |
| `structure` | 약 47,000 B | **10,718 B** | **−77%** |
| `permissions` | 약 8,000 B | 11,974 B | (구성 동일, all-false 제거만) |
| 앱 수 / 응답시간 | — | 6 apps / 139ms·129ms | — |

**판정: 목표(<10KB) 미달 — 21KB.** structure 는 목표를 초과 달성했으나, 이제 최대 항목이 `permissions`(12KB)로 바뀌었다.

`permissions` 는 항목마다 4개 boolean 을 모두 담는다(`{"create":false,"read":true,"update":false,"delete":false}` = 62 B/항목). 소비처(웹 reports-v2 2개 파일)는 `?.read === true` 처럼 truthy 검사만 하므로 **false 필드를 생략하면**(`{"read":true}` = 13 B) 프론트 무변경으로 12KB → 약 3KB, 전체 **21KB → 약 13KB** 가 된다. 그래도 10KB 미달이며, 남은 축소는 `structure.functions` 를 `[{slug}]` → `["slug"]` 문자열 배열로 바꾸는 것(웹 `fn.slug` 수정 필요)이 다음 후보다.

**단 아래 §3 결론상 /me 크기는 로그인 병목의 지배 항이 아니다** — 추가 축소의 실익은 대역폭·직렬화 절감에 한정된다.

## 1-b. W5-3 권한맵 캐시 — 내부 처리시간

부하 중 `[ME]` 계측 로그 (실측):

```
[ME] storeId=9 | total=12ms | user=2ms parallel_main=7ms parallel_perms=1ms perms_build=0ms
[ME] storeId=6 | total=13ms | user=2ms parallel_main=8ms parallel_perms=1ms perms_build=0ms
```

`perms_build=0ms`, `parallel_perms=1~2ms` — 캐시 적중으로 권한 조립이 사실상 0 비용. **/me 서버 내부 처리는 10~13ms** 로 매우 건강하다.

## 1-c. W6-1 health 필드

```json
{"ok":true,"db":"up","schema":"ok","redisAdapter":"on","uptimeSec":62,"worker":"3"}
```

`redisAdapter:"on"` 정상 노출(스테이징·운영 양쪽). 멀티워커 + 어댑터 미장착 조합이 아니므로 degraded 미발생 — 의도된 동작.

---

## 2. 판매 25건/s — Phase 65 무회귀 게이트 ★통과

`burst-multistore.js`, STORES=6,9,13, RATE=25, DUR=2m (실측 4분 완주)

| 지표 | 값 | 합격선 | 판정 |
|---|---|---|---|
| sale_ok | 4,619 (19.24/s 완주 25 iters/s) | — | — |
| http_req_failed | **0.00%** (0 / 4,769) | <0.1% | ✅ |
| checks | **100.00%** (4,649/4,649) | — | ✅ |
| sale_ms p95 | **64.4ms** (avg 47.9 / med 43.2) | ≤300ms | ✅ |
| DB 저장 건수 | **4,619** (= sale_ok, 차이 0) | 일치 | ✅ |
| daily_number 중복 | **0** 그룹 | 0 | ✅ |
| 항목 누락(sale_items 없는 판매) | **0** | 0 | ✅ |

**Phase 64/65 의 쓰기 경로 규약(단일 트랜잭션·멱등·outbox)이 25건/s 에서 무회귀임을 확인.**

---

## 3. 로그인 용량 — 목표 100건/s ★미달, 병목 재정의

`login-capacity.js`, STORES=6,9,13, PER_STORE=10 (유저 30명)

| RATE | 실제 처리 | login p95 | me p95 | 실패 | api_staging CPU | 판정 |
|---|---|---|---|---|---|---|
| **30/s** | 29.7/s | **629ms** | 207ms | 0% | 422% | ✅ 안정 |
| **45/s** | 40.4/s (dropped 96) | **6,139ms** | 1,283ms | 0% | 416% | ❌ 붕괴 |
| **60/s** | 47.5/s (dropped 395) | **8,188ms** | 2,057ms | 0% | (포화) | ❌ 붕괴 |

### 원인: bcrypt CPU 상한 (pool 은 증상, /me 크기는 무관)

1. **CPU 천장이 명확하다.** RATE 30 → 45 로 올려도 CPU 는 422% → 416% 로 **더 오르지 않고**, 처리량만 29.7 → 40.4/s 에서 멈추고 p95 가 10배 뛴다. pm2 4워커 = **4 코어가 상한**이고 그 상한에 이미 닿아 있다(8코어 서버지만 워커 4개).
2. **로그인 1건의 CPU 비용 ≈ 100~140ms** (4 CPU-초/초 ÷ 30~40건/s). 지배 항은 `bcrypt.compare`(cost factor 10, `auth.service.ts:293`) — 설계상 CPU 를 태우도록 만들어진 연산이라 캐시가 통하지 않는다.
3. **pool 경고(`waiting=400`, size=20 using=20)는 원인이 아니라 결과다.** 같은 시각 `[ME] total=12ms` 로 DB 작업 자체는 빠르다. CPU 포화로 이벤트 루프가 밀려 커넥션 반환이 늦어진 2차 현상이다.
4. **따라서 W5 다이어트로는 로그인 100건/s 에 도달할 수 없다.** /me 는 이미 12ms·21KB 로 충분히 가볍고, 남은 벽은 순수 암호 연산 비용이다.

### Phase 63 기록(60~70/s)과의 차이

Phase 63 F-4 는 더미 매장(19~23, 데이터 거의 없음) 기준이었고, 이번은 실매장(6/9/13, 앱·권한·터미널 데이터 실제)이라 로그인당 CPU 가 더 크다. **동일 조건 비교가 아니므로 "회귀"가 아니다.** 실사용 조건의 지속 한도는 **약 30건/s (4워커 기준)** 로 갱신 기록한다.

### 3,000 터미널 개점 관점 재계산

30건/s 지속 → 3,000 터미널 전원 로그인에 **약 100초**. W5-4 로 넣은 부팅 지터(0~30초) + 재접속 상한 30초가 이 100초를 자연히 덮으므로, **개점·정전복구 시나리오는 현재 용량으로 충족**한다. 문제가 되는 것은 "30초 안에 전원 로그인" 같은 요구뿐이며, 그런 요구는 없다.

---

## 4. 다음 후보 (착수 조건 명시, 이번 phase 밖)

| # | 조치 | 기대 | 리스크/조건 |
|---|---|---|---|
| A | **pm2 instances 4 → 6** | 로그인 상한 30 → 약 45/s (선형) | 8코어 중 PG·nginx 여유 축소. pool 예산 6×20=120 vs pgbouncer 50 재산정 필요. `WEB_CONCURRENCY` 도 함께 갱신(W6-2 에서 추가한 값) |
| B | `permissions` false 필드 생략 | /me 21KB → 약 13KB | 프론트 무변경(truthy 검사만) — 저위험, 다음 배포에 편승 가능 |
| C | bcrypt cost 10 → 9 | 로그인 CPU 절반, 상한 약 60/s | **보안 트레이드오프 — 사용자 결정 필요.** 기존 해시는 그대로 검증되고 재설정 시에만 새 cost 적용 |
| D | 세션 토큰 재사용(재접속 시 bcrypt 우회) | 재접속 폭주 비용 제거 | 설계 변경 규모 큼. 정전 복구 시나리오에만 유효 |

**권고 순서: B(무위험) → A(측정 후) → C/D 는 실제 요구가 30건/s 를 넘을 때.**

---

## 5. 파일

- 서버: `/home/jhkim/phase63-staging/results/2026-07-30-phase66/` — `login-30.log`, `login-45.log`, `login-60.log`, `sales-25.log`, `watchdog.log`
- 검증 SQL: `loadtest/verify-burst.sql`
