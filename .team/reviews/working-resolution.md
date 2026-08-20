# working-resolution — 2026-08-20 · 006 정산 경로 마무리

대상 검토: [`working-codex.md`](working-codex.md) (codex, `scripts/codex-review.sh --working`)

## [P1] 인덱스를 CONCURRENTLY 로 생성하라 — `migrations/2026-08-20-settlements-one-draft-per-period.sql:21-23`

**판정: 반박 (코드 그대로 유지)**

codex 의 지적은 규칙 문언상 정확하다. `AGENTS.md:32` 가
`CREATE INDEX 에 CONCURRENTLY 누락 → 지적` 이라고 무조건형으로 적어 두었다.
그러나 이 건에는 적용하지 않는다. 근거는 셋이다.

### 1. 잠금 시간을 실측했다 — 6.7ms

```
CREATE UNIQUE INDEX idx_settlements_one_draft_per_period ...
Time: 6.658 ms
```
운영 `talleres_settlements` 는 **2행**이다. "인덱스 구축이 끝날 때까지 쓰기를 차단" 은
사실이지만 그 시간이 6.7ms 다. 같은 배포에서 컨테이너 재생성으로 발생하는 중단이
수십 초다 — 이 잠금은 그 안에 묻힌다.

### 2. CONCURRENTLY 는 여기서 **더 위험하다**

트랜잭션 안에서 실행할 수 없으므로 마이그레이션이 원자성을 잃는다. 그리고 실패하면
**INVALID 인덱스가 남는다** — 존재하지만 유일성을 강제하지 않는 인덱스다.

이 인덱스의 존재 이유가 "advisory lock 을 우회하는 경로가 생겨도 DB 가 막는다" 인데,
INVALID 상태는 **막는 것처럼 보이면서 안 막는다.** 강제 지점이 조용히 죽는 형태이며,
이 저장소가 반복해서 당한 실패 유형(Phase 85: "문서에만 있는 규약")과 같은 계열이다.
2행 테이블에서 6.7ms 를 아끼려고 그 위험을 사는 것은 교환이 성립하지 않는다.

### 3. 저장소의 실제 관행도 크기 비례다

309개 마이그레이션 중 CONCURRENTLY 는 12개. 대상 테이블을 보면 전부 크거나 뜨거운 쪽이다:

| 마이그레이션 | 대상 테이블 |
|---|---|
| 2026-07-25-fk-indexes | `sales` |
| 2026-07-13-sale-items-fk-indexes | `sale_items` |
| 2026-07-27-phase64-outbox-lease-index | `sync_outbox` |
| 2026-07-28-idx-functions-slug | `functions` |
| phase31-perf-add-missing-indexes | `prices` |

2행짜리 테이블에 쓴 전례는 없다.

### 후속 조치 — 규칙 문언을 실제 판단 기준에 맞춘다

★ 이 지적은 **어제도 나왔고 오늘도 나왔다.** 매번 같은 근거로 반박하는 것은 낭비이고,
반박이 기록에만 남으면 다음 사람은 규칙과 관행이 갈라진 이유를 모른다.
`AGENTS.md` 의 해당 줄을 **크기 조건부**로 고친다 — 바로 옆 형제 항목
(`대용량 테이블의 ALTER TABLE ... TYPE → 지적`)이 이미 그 형태다.

규칙을 현실에 맞추거나 현실을 규칙에 맞추거나 둘 중 하나여야 한다.
여기서는 **규칙 쪽이 과했다.**

---

## 검토 범위 밖이지만 이번 라운드에서 확인한 것

- `SHOP_DB_ISOLATED` — 운영 `SHOP_DB_HOST:PORT` 가 `DATABASE_HOST:PORT` 와 **같다**
  (`172.17.0.1:5432`, 동일 pgbouncer). 미선언이 **정확한 상태**이며 `true` 로 선언하면
  코드의 모순 검사가 잡아 무시한다. 조치 불필요 — 진짜 격리는 별도 인스턴스 인프라 작업.

---

# 라운드 2 (2026-08-20)

## [P2] 상한 초과 판별을 위해 한 행을 더 조회하라 — `subcon-settlement.service.ts:330`

**판정: 수용 (수정 완료)**

내가 넣은 경계값 오류가 맞다. `LIMIT 5000` 으로 읽고 `length >= 5000` 을 절단으로 보면
**정확히 5,000건인 정상 기간까지 거절**한다 — "잘렸다" 와 "딱 맞다" 를 구분할 수 없기 때문이다.

무음 절단을 없애려다 **정상 입력을 막는 새 결함**을 만든 셈이다. 5,001건째를 읽어
초과 여부를 판별하도록 고쳤다:

```ts
const RECEPCION_SCAN_PROBE = RECEPCION_SCAN_LIMIT + 1;   // limit 에 사용
if (recepciones.length > RECEPCION_SCAN_LIMIT) { ... }   // 초과일 때만 거절
```

★ 이 지적은 codex 자문의 값을 보여준다 — 절단을 소리나게 만드는 것 자체는 옳았는데
그 구현이 경계에서 틀렸다. 혼자였으면 5,000건짜리 기간이 나올 때까지 몰랐을 것이다.

## 그 외

라운드 2 에서 그 밖의 차단 결함은 보고되지 않았다. 라운드 상한(2회)에 도달했으므로 검토를 종료한다.

## 이번 태스크의 변경 목록

| 항목 | 출처 | 처리 |
|---|---|---|
| `req.user.branchId` 누락 (운영 403 986건) | 에이전트 A · 직접 실측 | 수정 + 회귀 spec |
| 정산 컨트롤러 상속 `PUT/DELETE /:id` 불변성 우회 | 에이전트 A [HIGH] | 차단 |
| DRAFT 중복 방지 (advisory lock + 부분 유니크 인덱스 + 멱등 23505) | CODEX 2026-08-19 | 구현 · 운영 적용 |
| 트랜잭션 안 `getRateAt` N+1 (최악 5,000왕복) | 에이전트 A [MEDIUM] | 메모이즈 |
| `limit 5000` 무음 절단 | 에이전트 A [MEDIUM] | 거절로 전환 → **경계값 오류** → codex [P2] 로 수정 |
| INV-1 조회 `storeId` 누락 | 에이전트 A [LOW] | 명시 |
| 캐시 무효화가 커밋 전 | 에이전트 A [LOW] | 4곳 커밋 뒤로 |
| advisory lock 키 공간 공유 | 에이전트 C [LOW] | **미조치** — 아래 |

### 미조치로 남기는 것

**advisory lock 키 공간 공유 [LOW]** — `pg_advisory_xact_lock(int, int)` 의 키 공간을 앱 전체가
공유하는데 `clients.service.ts`(ownerGroupId) · `subcon-settlement.service.ts`(storeId) ·
`productStock.service.ts`(storeId) · `daily-number.service.ts`(storeId) 가 첫 인자로 **도메인 id** 를
그대로 쓴다. `cashRegister.service.ts:38` 은 이미 전용 네임스페이스 상수
(`BOX_SETTLEMENT_LOCK_NS = 84201`)로 이 문제를 인지·대응해 두었다.

충돌 조건이 (동일 숫자 id) AND (32비트 `hashtext` 우연 일치) 라 확률이 매우 낮고, 충돌해도
데이터 오염이 아니라 **무관한 짧은 트랜잭션이 잠깐 대기**하는 정도다. 이번 변경이 만든 문제도
아니다(기존 패턴을 따랐을 뿐).

다만 **네 곳이 같은 관행을 공유하는데 한 곳만 네임스페이스를 쓰는 상태**는 언젠가 갈라진다.
별건으로 `cashRegister` 방식 통일을 제안하며, 이번 태스크 범위 밖으로 남긴다.
