# Phase 95 — 멀티테넌트 격리 완성 (raw SQL 까지)

작성 2026-09-26. 근거는 전부 이 날 직접 측정했다(운영 로그 14일 · 운영 PG18 5434 ·
소스 전수 · 로컬 API E2E · pgbouncer/pm2 실측).

사용자 지시 (절대 규칙):
> 「멀티 태넌트에서 태넌트 간의 데이터는 절대로 혼동되거나 오염되어서는 안 돼.
>  그건 이 시스템의 죽음을 의미하는거야.」
> 「`store=undefined` 에 대해서도 절대로 허용해서는 안 되.」
> 「10월부터 더 많은 사용자가 시스템을 사용하게 될거야.」

사용자 결정 2026-09-26 (일정):
> 「지금 상태가 위험한 것은 아니라면 좀 더 시간을 두고 차근차근 하는 식으로 하는 것이 낫겠지」

⤷ **급하게 몰아치지 않는다.** 근거는 §2 — 감시가 이제 실제로 작동하므로
  오염이 시작되면 즉시 보인다. 그 사실이 「천천히」를 정당화한다.

---

## 1. 오염의 증거는 없다 (운영 로그 14일 전수, 2026-09-13 ~ 09-26)

| | |
|---|---|
| 「격리 누수 감지」 경보 총계 | **776건** |
| 그중 `store=<다른 매장 숫자>` = **진짜 오염** | **0건** |
| `store=undefined` = 가드가 **확인 불가** | **776건** |

★ 「확인 불가」는 **「안전」이 아니다.** 776번 못 봤다는 뜻이고, 그 자리에서는
  안전을 *증명*할 수 없다. 그래서 2026-09-26 에 그것부터 없앴다(§2).

---

## 2. 2026-09-26 에 배포한 것 — **감시가 작동하기 시작했다**

| # | 내용 | 배포 |
|---|---|---|
| 1 | 「검증 불가」를 「누수」에서 **분리**. `GLOBAL_ROW_TABLES`(users·roles·payment_methods 등 8개)에서 미선택 행이 **전역행으로 조용히 통과**하던 것 차단 | api `5c2034a6` · #966 |
| 2 | 경보에 **`파일:줄` 3단 사슬 + 매장 + user**. throttle 키도 **위치별**(모델별이면 시끄러운 경로가 나머지를 60초 가려 개수를 못 센다) | api `5c2034a6` · #966 |
| 3 | `beforeFind` 가 **`storeId` 를 SELECT 에 강제**하고 `afterFind` 가 검증 후 도로 뺌 → `store=undefined` 가 **구조적으로 소멸**. 응답은 그대로 | api `bec38dad` · #966 |
| 4 | 소스맵을 **`NODE_OPTIONS`** 로 (→ §4-b) — 줄 번호가 `dist/*.js` → **`src/*.ts`** | api `85f0d4f6` · #967 |

**실 트래픽 결과:**

| | 2026-09-25 (배포 전) | 2026-09-26 (배포 후) |
|---|---|---|
| 요청 수 | 31,752 | 5,737 (토요일 · 평일의 약 18%) |
| 격리 누수 감지 | **113건** | **0건** |
| 격리 검증 불가 | — (분리 전) | **0건** |
| api error 로그 | — | **0 bytes** |

★ **감시가 작동한다는 것이 Phase 95 를 여유 있게 진행해도 되는 근거다.**
  오염이 시작되면 `store=<숫자>` + `파일:줄` + 매장 + user 로 즉시 보인다.
  2026-09-25 까지는 그렇지 않았다 — 776건 소음에 묻혔다.

---

## 3. 남은 구멍 — Phase 95 의 본체

### 3-a. ★★ raw SQL 은 훅을 **아예 안 탄다**

```
sequelize.query 호출:  219곳
그중 store 조건 없음:   204곳
```

Sequelize 훅(`beforeFind`/`afterFind`)은 **모델 경유 조회에만** 붙는다.
`sequelize.query` 는 그 위를 지나가므로 **좁혀지지도, 검증되지도 않는다.**
⤷ 204곳 대부분은 이미 인가된 **기본키**로 좁혀 무해해 보이지만 **전수 판정은 안 했다.**

### 3-b. 가드가 **완전히 no-op** 인 경로

`allowedStores()` 가 `null` 을 돌려주는 조건 — 컨텍스트 없음(**크론·워커**) ·
`ctx.system` · **`ctx.isSuperAdmin`**.

★ 매장 대행(`X-Store-Id`)은 `TenantContext.resolve({ isSuperAdmin: false })` 로 세우므로
  **가드가 산다.** 그래서 아래 3-c 가 구조된다 — 하지만 그것은 **가드가 구해 주는 것**이고
  코드 자체가 안전한 것이 아니다.

### 3-c. 매장 인자가 **선택적**인 함수 35곳

```ts
// products.service.ts:550
if (storeId) where.storeId = storeId;        // storeId 가 없으면 전 매장으로 열린다
// products.controller.ts:103
storeId: isSuperAdmin ? undefined : (user?.storeId ?? undefined)
```

이 형태가 저장소에 **35곳**. 보고서류는 「전 매장」이 의도라 **전부가 결함은 아니다.**
**위협은 셋이 겹칠 때다: ①매장 소유 행을 ②필터 없이 읽어 ③특정 매장의 거래에 쓴다.**

### 3-d. 겹치는 값의 실측 — 위험의 «정의»

DB `pg_constraint` 로 확인: **매장별로만 유일한** 업무 키가 **14개 테이블**에 있다
(`products.sku` · `credit_payments.receipt_no` · `online_orders.order_number` ·
`talleres_lotes.cut_ticket_number` · `mes_materials.code` 등).

실제로 **매장 간에 값이 겹치는 것은 단 하나**:

```
sku = 'GEN-0001'  →  14개 매장 (6,9,11,13,14,15,16,17,18,19,20,21,22,23)
```

⤷ `Producto Genérico`(빠른판매용). 그래서 3-c 의 `findGenericProduct` 가 하필 위험하다.
  관련: `is-generic-is-a-per-store-singleton` 메모리.

---

## 4. RLS 는 왜 «지금» 안 하는가 — 실측 근거

사용자에게 「RLS + 세션 GUC」를 제안했다가 **측정 후 철회했다.** 비싸다.

| 사실 (실측) | 함의 |
|---|---|
| pgbouncer **`pool_mode = transaction`**, 앱은 pgbouncer(5432) 경유 | 세션 `SET` 이 **쿼리 사이에 안 살아남는다** |
| 기존 GUC 는 전부 **트랜잭션 안의 `SET LOCAL`** (`productsPrice.service.ts:478` 주석이 「트랜잭션 밖에선 안 통한다」를 이미 적어 둠) | **읽기는 대부분 트랜잭션이 없어** 그대로는 적용 불가 |
| Sequelize **CLS 미사용** (AsyncLocalStorage 는 TenantContext 전용) | 요청 전체를 트랜잭션으로 감싸는 **구조 변경** 필요 |
| 앱 유저 `coolsistema` 가 **218개 테이블의 소유자** | **소유자에게 RLS 는 기본 미적용** → 테이블마다 `FORCE ROW LEVEL SECURITY` 필수. 하나 빠뜨리면 **조용히 무방비** |
| `store_id` 보유 테이블 **171개** · 현재 RLS **0개** | 정책·FORCE·검증을 171벌 |

★★★ 가장 위험한 함정: **Sequelize 풀 커넥션은 요청 간에 재사용된다.**
  트랜잭션 없이 평범한 `SET` 을 쓰면 **앞 요청의 매장 id 가 다음 요청에 남는다** —
  **지금보다 나빠진다.** 요청마다 트랜잭션으로 감싸면 커넥션을 요청 전체 시간 동안
  붙잡아 pgbouncer `pool_size=50` 을 압박하고, 이 저장소 규약(「트랜잭션 안 외부 I/O 금지」)과
  정면으로 부딪친다.

**견적: 약 2~3주** (정책 1~2일 + CLS 3~5일 + 부하회귀 2~3일 + 전수검증 2~3일 + 단계롤아웃 3~5일).
⤷ **주말에 끝나는 일이 아니다.** 별도 프로젝트로 둔다.

### 4-b. ★ 곁다리로 배운 것 — 설정 파일에 줄이 있는 것 ≠ 적용된 것

`node_args: ['--enable-source-maps']` 를 배포했는데 **워커 4개 전부 플래그가 없었다**
(`node /app/dist/main.js`). pm2 **cluster 모드는 `node_args` 를 포크된 워커에 안 붙인다.**
워커 수를 세어(6개 중 2개) 발견했고 **`NODE_OPTIONS`** 로 옮겨 4/4 적용을 확인했다.
대조군으로 증명:

```
플래그 없음: /app/dist/app/products/historial-del-dia-orden.js:5:16
플래그 있음: /app/src/app/products/historial-del-dia-orden.ts:29:14   ← 실제 소스 줄
```

---

## 5. 참고

- 감사 문서: `.planning/AUDIT-2026-09-26-servidor-seguridad-y-300ms.md` §9
- 메모리: `tenant-isolation-is-absolute` · `tenant-guard-blind-vs-leak` ·
  `is-generic-is-a-per-store-singleton`
