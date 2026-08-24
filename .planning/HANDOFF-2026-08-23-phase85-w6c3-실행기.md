# 핸드오프 — 2026-08-23 · Phase 85 W6-C3 ③④ 카탈로그 복원 실행기 ★

`HANDOFF-2026-08-22-f-phase85-w6c3-범위재조정.md` 에서 이어짐.
사용자 지시: **"handoff 읽고 phase 85에 해당된 작업만 하고, 더 없으면 phase 86을 시작하자"**

---

## ★★ 이 세션의 한 줄

**전 세션이 남긴 유일한 미결(충돌 정책)을 사용자가 정했고, 실행기를 지어 잠금을 풀었다.
그리고 처음으로 이 경로의 SQL 을 **실제 DB 에서 돌려 봤다** — 거기서만 나오는 결함 둘을 잡았다.**

---

## Phase 85 현황

| 웨이브 | 상태 |
|---|---|
| W1 캐시 봉인 · W2 소켓 · W3 pageSize · W4 규약 · W5 무중단 배포 | ✅ 완결 |
| **W6 논리 복구 (카탈로그/SKU)** | ✅ **이번 세션 완결 — 잠금 해제** |
| W4 파티셔닝 · W7 rollup · W8 p95 게이트 | ⏸ 착수 조건 미달 (근거 문서화됨) |

→ **Phase 85 는 착수 가능한 범위가 끝났다.** 다음은 Phase 86.

---

## 배포

```
api-ventago  cbce1cb  카탈로그(SKU) 복원 실행기 — 같은 매장 · 추가만    #800
superproj    5bd5e3f  + codex 검토 문서 4개
운영 DB      2026-08-23-w6c3-restore-plan-catalog-mode.sql  (5432 + 5434 양쪽 적용 ✓)
테스트       단위 321 (기존 272 → +49) · **실제 DB 통합 11 (신설)**
```

---

## ① 사용자 결정 — 충돌 정책은 **추가만**

이미 있는 상품은 판매가 참조하고 있을 수 있고, POS 검색에 서버 폴백이 없어
반쪽 복원이 판매를 막는다. 그래서 없는 것만 넣고 기존 행은 건드리지 않는다.

**예외 하나**: `sku_serials.last_serial` 은 단조 카운터라 **전진**시킨다.
기존 50 · 백업 80 인데 기존이 이기면 다음 발급 51 이 되살린 SKU 와 충돌한다.
정책 이름에 박아 뒀다 — `INSERT_ONLY_EXCEPT_MONOTONIC_COUNTER_ADVANCE`.

## ② ★ 원본 PK 를 그대로 되살린다 (CLONE 과 정반대)

CLONE 은 `id` 를 REGENERATE 했다. 여기서는 반대다:

1. `sale_items.product_id` 등 **범위 밖 참조**가 다시 이어져야 "되돌린" 것이다
2. `sku_serials.{supplier,category,subcategory}_id` 는 **FK 없는 참조** —
   id 를 바꾸면 조용히 남을 가리킨다. FK 카탈로그가 못 보는 자리라 검사도 안 걸린다
3. id 원장·2단계 UPDATE·DEFERRED 집행이 통째로 필요 없어진다

→ **id 를 못 되살리면 그 행은 막는다(BLOCKED).** 우회하면 위 근거가 무너진다.

## ③ codex 2라운드 — 6건 수용, 1건 미수용

### 1R (설계) — `w6c3-catalog-engine-{codex,resolution}.md`

| 지적 | 조치 |
|---|---|
| 자연키가 **다른 id** 에 있으면 SKIP | → **BLOCKED**. SKIP 이면 없는 id 를 가리킨 채 "성공" 반환 |
| `prices (product_id, price_type_id)` 자연키 | DB 가 강제 안 함 → **PK 판정만** |
| 계획/집행 경합 | 집행 트랜잭션 **안에서 전 판정 재수행** + advisory lock |
| `products.slug` UNIQUE 누락 | 카탈로그의 **UNIQUE 전부** 검사(부분 인덱스 포함) |

★ **내 선언이 실측으로 틀렸다**: `price_types (store_id, store_entity_id)` 를
  자연키로 뒀는데 운영 18행 **전부 NULL** 이고 4쌍이 겹친다.
  `store-restore-scopes.ts` 에 적어 둔 근거("1~5 가 code-import 가격 슬롯")도
  데이터로는 성립하지 않는다 — `code-import.service.ts:154` 가 그 컬럼으로
  정렬하지만 전부 NULL 이라 아무것도 정하지 않는다. **별건 결함(미해결)**.

### 2R (구현) — `w6c3-catalog-engine-implementation-{codex,resolution}.md`

| 지적 | 조치 |
|---|---|
| 시퀀스 보정이 동시 `nextval` 과 원자적이지 않다 | 아래 ★ |
| 복구 커밋 **뒤**의 기록 실패가 FAILED 로 적힌다 | 오류 경계 분리 · `recorded:false` |
| 백업 파일 **안**의 PK/UNIQUE 중복 미검사 | `findDuplicatesWithinBackup()` 신설 |
| fingerprint 가 판정 근거를 다 안 담는다 | UNIQUE·FK·판정규칙·엔진버전 포함 |

★★ **codex 처방이 PG 에 없었다.** "시퀀스를 ACCESS EXCLUSIVE 로 잠가라" →

```
LOCK TABLE products_id_seq IN ACCESS EXCLUSIVE MODE;
→ ERROR: cannot lock relation — This operation is not supported for sequences.
```

실측으로 대안을 찾았다:

```
BEGIN; ALTER SEQUENCE products_id_seq INCREMENT BY 1; SELECT pg_sleep(3); COMMIT;
  (동시) nextval  →  2,308ms 대기
```

내용상 no-op 인 `ALTER SEQUENCE` 가 `AccessExclusiveLock` 을 잡고 **실제로 막는다.**
올릴 필요가 있을 때만 잠그고, 집행의 **맨 끝**에 한다(창을 최소화).

### 미수용 — 감사 트리거 억제

범위 축소로 5,652행 → **약 100행**. 100행은 소음이 아니라 **증거**이고
`SET LOCAL ventago.actor_user_id` 로 이미 올바르게 귀속된다.
억제 플래그를 DB 함수에 넣으면 **영구적인 구멍**이 된다.

## ④ ★ 실제 DB 통합 테스트를 처음 만들었다 (`.itest.ts`)

`npm run test:itest` · `test/itest/jest-itest.json` · 로컬 PG(5432) 필요.
`testRegex` 가 `.spec.ts` 라 **일반 jest·CI 에서는 빠진다.**

**단위 spec 과 tsc 를 둘 다 통과한 뒤 여기서 두 결함이 나왔다:**

1. `pg_get_serial_sequence('public.ProductBranch','id')` → **relation does not exist**
   (인용 안 하면 소문자로 접힌다). 대소문자 섞인 테이블 하나가 조용히 죽었다
2. 위 시퀀스 잠금 방법 — 문서만 읽었으면 없는 API 를 썼을 것이다

## ⑤ 잠금은 엔진마다 하나씩

`RESTORE_ENGINE_STATUS`(전체 복제)는 **여전히 `blocked`**.
카탈로그만 `CATALOG_RESTORE_STATUS = 'enabled'`.
하나로 합치면 한쪽을 열려다 **고쳐진 적 없는 다른 쪽이 같이 열린다** —
`store-restore-contract.spec.ts` 가 그 시도를 막는다.

## ⑥ 엔드포인트

```
POST /store/restore/catalog/plan      { destinationStoreId, backup }  → 계획 + planId
POST /store/restore/catalog/execute   { planId }                      → 집행
```
둘 다 superadmin 전용. 계획을 만든 사람만 집행한다.

---

## ★ 남은 것 (다음 세션)

### 이 기능에 대해
- **프론트 화면이 없다.** 지금은 API 만 있다. superadmin 콘솔에 계획 미리보기
  (INSERT/SKIP/BLOCKED 건수 + BLOCKED 목록 + `recorded:false` 경고)가 필요하다
- `.itest` 는 **로컬에서만** 돈다. 손 절차로 남으면 안 돈다 — W8 부하 리그에
  얹거나 CI 에 PG 서비스를 붙이는 것이 정석
- `store_restore_plans` 만료 청소(EXPIRED + MinIO 객체) 크론이 없다

### 로컬 DB 를 복원했다 ★
`~/Dropbox/ventago_pg_backups/ventago_20260820_031701.dump` 로 복원(235 테이블).
★ 그냥 `pg_restore --role=coolsistema` 하면 **permission denied** 로 죽는다 —
  DB owner 가 `postgres` 였기 때문. `DROP DATABASE` → `CREATE DATABASE ventago
  OWNER coolsistema` 후 복원해야 한다.
복원 후 08-20~08-23 마이그레이션 8개를 순서대로 적용했다.

### 종전 이월 (그대로)
- `price_types.store_entity_id` 전부 NULL → code-import 가격 슬롯 정렬이 무의미 (신규)
- `mp_accounts` 를 `findByPk()` 로 직접 읽는 결제·웹훅 경로 전수검사
- `commerce_channels`/`wp_channels` 소비자 게이트
- sudoers mode 0440 · 프론트 blue/green 없음 · POS 카탈로그 P95 376ms ·
  소켓 한도 0 · `/me` 11쿼리 미캐시

---

# 이어서 — 2026-08-24 · 결제 경로 테넌트 경계 (Phase 86 과 **분리**) ★

사용자 지시: **"phase 86 은 이미 존재할 텐데... 결제 경로 테넌트 경계를 세우는 것은
phase 86과 혼합하지 말고 지금 해결해줘"**

★ Phase 86 = **레거시 임포트**다 (`feature/phase86-legacy-import-full` 브랜치의
  `31d38e7` + api-ventago `phase86-migrations` 의 `13d468e`). 섞지 않았다.

## 배포

```
api-ventago  12145e9  OAuth 매장 귀속을 서버가 정한다        #802
ventago-app  5da0b0e  수취 계정 교체를 명시적 승인으로        #681
superproj    09adba6
운영 DB      2026-08-23-mp-oauth-states.sql               (5432 + 5434 ✓)
             2026-08-23-mp-accounts-one-active-per-scope.sql (5432 + 5434 ✓)
테스트       566 (store+mercadopago+common) · OAuth 39 · 대조군 5종
```

## ★★ 뚫려 있던 것

```
GET /mercadopago/oauth/start?storeId=N   @Auth(admin, superadmin)
  → storeId 가 **호출자의 매장인지 확인 없음**
  → HMAC 서명된 state 에 실려 @Public() 콜백까지
  → 콜백이 그 값으로 mp_accounts 에 쓴다 (기존 행이면 덮는다)
```

A매장 admin 이 `start?storeId=B` → 자기 MP 계정으로 OAuth 완료 →
**B매장 QR 대금이 공격자에게** 간다. 운영 `mp_accounts` **0행** — 실피해 없음.

★ 왜 다른 방어가 다 통과했나: 전역 테넌트 가드(보호모델 122)가 다른 MP 라우트는
  덮는데 **콜백은 `@Public()` 이라 컨텍스트가 없어 no-op** 이다.

## ★ 내가 사용자에게 처음 보고한 것 중 틀린 것

`disconnect/:accountId` 도 구멍이라고 말했는데 **틀렸다.** 가드가 덮는다
(부팅 로그 `mode=enforce 보호모델=122` 가 근거). 근거 확인 전에 말한 것이 잘못이었다.

## 고친 방식 — "서명은 인가가 아니다"

인가를 인증된 `start` 에서 하고 결과를 **`mp_oauth_states` 행**에 적는다.
콜백은 payload 가 아니라 그 행에서 범위를 읽고 **원자적으로 1회 소비**한다.
평문 nonce 는 저장하지 않는다(해시만).

## codex 2라운드 — 총 7건 수용

1R: 안 C 채택 + 콜백 관계 검증. **codex 가 CRITICAL 을 하나 더 짚었다** —
재-OAuth 가 `mpUserId` 까지 갈아끼워 "토큰 갱신" 과 "**받는 사람 교체**" 가
같은 경로였다.

2R(구현 diff): HIGH 1 · MEDIUM 2
- `expectedMpUserId` 를 **저장만 하고 안 썼다** → 교체 승인이 "A 를 바꾼다" 가
  아니라 "콜백 시점의 무엇이든 바꾼다" 였다. `FOR UPDATE` + 기준선 대조 추가
- **인가 판정보다 외부 I/O 가 먼저** → 거부될 교체가 그 전에 남의 MP 계정에
  Store/POS 를 만들어 놨다
- 끊고 다른 계정으로 재연결할 길이 막혔다 → 연결 해제 자체를 승인으로 본다

## ★★★ codex 가정보다 나빴던 것 (실측으로 찾음)

codex: "`mp_accounts` 의 UNIQUE 는 활성 행에만 적용된다"
**실측: 그런 인덱스가 아예 없다.** `mp_accounts_pkey` 뿐.
→ 같은 (매장,지점)에 활성 행이 여러 개 가능 → resolver 가 **아무거나** 고른다
→ **어느 계정이 QR 대금을 받는지가 비결정적**이었다.
→ `uq_mp_accounts_active_scope` 추가 (`NULLS NOT DISTINCT` 가 핵심 —
  매장 단위는 `branch_id IS NULL` 이라 기본값이면 정작 막을 자리가 안 막힌다).

## ★ 범위 밖으로 남긴 것 — **후속 보안 부채** (조사 에이전트 전수 결과)

| Sev | 자리 | 문제 |
|---|---|---|
| ~~HIGH~~ ✅ | ~~`POST /mercadopago/refunds/:saleId/retry`~~ | **2026-08-24 해결** (`b932170`) — 아래 참조 |
| MED | `disconnect` · `qr` · `payment-intents` · `wallets/:id/movements` | 전역 가드에만 의존. `TENANT_GUARD_MODE=warn` 이면 전부 열린다 → 핸들러에 명시 검사 필요 |
| MED | `POST /mercadopago/qr` | 같은 매장 안 **다른 지점**의 MP 계정을 지목할 수 있다. `terminalId`/`pendingVentaId` 도 매장 소속 미검증 |
| LOW | webhook `findByPk(accountIdFromQuery)` | 재조회 토큰 검증이 교차 확정은 막지만, 유효하되 틀린 `accountId` 로 그 알림을 실패시키는 DoS |

★ `TENANT_GUARD_MODE=warn|off` / `TENANT_DERIVED_MODE=observe|off` 가
  **거의 모든 MP 라우트의 유일한 방어**를 환경변수로 끈다. 이것 자체가 항목이다.

## 그 밖에 확인한 것

- `price_types.store_entity_id` 운영 18행 **전부 NULL** → `code-import.service.ts:154`
  의 가격 슬롯 1~5 정렬이 아무것도 정하지 않는다 (별건, 미해결)
- 프론트: `Cambiar cuenta MP` 버튼 + 지점 스위치 확인 다이얼로그 신설.
  서버만 고쳤으면 **정상적인 계정 교체가 통째로 막혔을 것**이다


---

# 이어서 — 2026-08-24 · 환불 원장의 판매 귀속 (후속 부채 HIGH) ★

사용자 지시: **"HIGH 부터 이어서 해줘"**

## 배포

```
api-ventago  b932170  환불 원장은 그 결제의 판매에만 찍는다   #803
superproj    44fdc2b
DB 변경 없음 (코드만)
테스트       832 (mercadopago+sales+store+common) · 환불 18 · 대조군 6종
```

## 뚫려 있던 것

`retry` 의 `saleId` 가 `@Param` 에서 와서 `mp_refund_attempts`·`mp_refunds` 에
**그대로 INSERT** 됐다. 그 두 표에는 **`store_id` 가 없어** 전역 격리 훅이
파생 규칙(→ sale)만 걸고, `installDerivedForModel` 은 **읽기 훅만** 설치한다.
쓰기 검사(`assertDerivedParentsInScope`)는 `crud.service.ts` 에서만 불리는데
MP 모듈은 그걸 안 쓴다 → **쓰기 무방비.**

→ 자기 매장 결제로 **남의 매장 판매에 환불 원장**을 찍을 수 있었다.

## 고친 방식 — 네 축 (②③④ 는 훅과 무관)

① 판매 가시성(전역 훅) ② **관계** `pendingVentaId === saleId`
③ **정합성** `intent.storeId === sale.storeId` ④ **요청자 인가**(`TenantContext`)

거부는 attempt 생성·MP 호출 **전에** 한다.

## ★ codex 가 잡은 내 과장

③을 "훅이 꺼져도 남는 축" 이라 적었는데 **정합성 축에서만 맞다.**
`TENANT_GUARD_MODE=warn` 이면 남의 매장 `mpPaymentId` + **그 결제의 진짜 `saleId`**
조합이 ①②③ 을 전부 통과한다 → ④ 신설(모드 스위치를 안 탄다).

## ★★ 대조군이 통과하는 것을 찾았다

`superadmin 은 통과한다` 테스트가 **superadmin 우회를 지워도 안 죽었다** —
`storeId: null` 이라 `allowed === null` 분기로 빠지고 있었다.
그 형태는 **검사가 없는 것과 같다.** `storeId` 를 가진 superadmin 으로 고쳤다.

## 구조적으로 남은 것 ★

`mp_refunds`/`mp_refund_attempts` 에 `store_id` 가 없는 것, 그리고 파생 규칙이
**읽기만** 덮는 구조는 그대로다 — **이 두 표에 새 쓰기 경로가 생기면 같은 결함이
다시 난다.** 지금 쓰기 경로는 `mp-refund.service.ts` 두 곳뿐임을 전수 확인했다.
구조적 해결은 ⓐ `assertDerivedParentsInScope` 를 CRUD 밖에서도 강제하거나
ⓑ 두 표에 `store_id` 를 더하는 것이고, 별도 작업이다.

## 다음 (MED 3건, 같은 부류)

- `disconnect`·`qr`·`payment-intents`·`wallets/:id/movements` — 전역 가드에만 의존
- `POST /mercadopago/qr` — 같은 매장 안 **다른 지점** MP 계정 지목 가능.
  `terminalId`/`pendingVentaId` 도 매장 소속 미검증
- `TENANT_GUARD_MODE=warn|off` / `TENANT_DERIVED_MODE=observe|off` 가
  **거의 모든 MP 라우트의 유일한 방어**를 환경변수로 끈다 — 이것 자체가 항목이다
