# W6-C3 1단계 FK 매니페스트 — codex 검토 수용 (2026-08-22)

원본: `.team/reviews/w6c3-manifest-codex.md` · 질문: `.planning/QUESTION-2026-08-22-c-복원매니페스트-구현.md`

codex 결론: **"구조는 맞지만 현재 상태로 엔진 구현에 들어가는 것은 반대."**
HIGH 3 + MEDIUM 1. **네 건 모두 근거까지 대조해 확인했고 전부 수용했다.**

| # | 지적 | 내 확인 | 결정 |
|---|---|---|---|
| HIGH | `restaurant_tables.current_sale_id` 를 DEFERRED 로 되살리면 복제 매장이 남의 영업 중간에서 시작한다 | **사실** (아래 ★) | 수용 — `CLEAR` + 상태 정규화 |
| HIGH | `requiresSameOwnerGroup?: boolean` 은 실행기가 안 읽어도 통과 — fail-open | 설계상 맞다 | 수용 — 판별 공용체 + 게이트 함수 |
| HIGH | 인벤토리가 `public` 만 본다 (`reseller` 3개 누락) | 내가 먼저 발견, codex 가 확인 | 수용 — 전 스키마로 확장 |
| MEDIUM | 같은 끝점 FK 제약 중복 3개가 숫자를 부풀린다 | **사실** — 354줄/351컬럼 | 수용 — `DISTINCT` + 별도 경고 |

---

## ★ HIGH 1 — 코드와 운영 데이터로 확인했다

내 원안은 이 컬럼을 "판매의 역참조" 로 보고 DEFERRED 로 뒀다. codex 가 반대했고,
**코드를 열어 보니 맞았다:**

```ts
// restaurant-tables.service.ts
async syncTableStatus(table, status, currentSaleId, options?) {
  await table.update({ status, currentSaleId }, options);   // ← 둘이 한 UPDATE
}

// restaurant-sale.service.ts — placeOrder
if (!table.currentSaleId) { /* 새 DRAFT 판매 생성 */ }
else { /* 기존 DRAFT 에 누적 */ }        // ← 이 컬럼이 분기를 정한다
```

즉 `current_sale_id` 는 **`status` 와 짝을 이루는 현재 영업 상태**다.

**운영 실측 (2026-08-22):**

| status | 테이블 | current_sale_id 있음 |
|---|---:|---:|
| libre | 14 | 0 |
| **ocupada** | **1** | **1** |

복제하면 새 매장이 그 테이블을 점유 상태로 열고, 누군가 **남의 진행 중 판매를 이어
마감**할 수 있다. 그리고 FK 만 `CLEAR` 해도 `status='ocupada'` 가 남아 둘이 어긋난다.

→ `OPERATIONAL_STATE_RESETS` 를 새로 두어 `current_sale_id=null` 과 `status='libre'` 를
**함께** 되돌린다. spec 이 두 선언의 일치를 양방향으로 강제한다.

★ 이건 내가 반복해 온 실수의 변형이다 — **"과거 사실" 과 "현재 상태" 를 같이 복원했다.**
  `active_sessions`·`terminal_devices` 를 EXCLUDED 로 뺀 것과 같은 판단인데,
  FK 어휘로 내려오니 그 구분이 안 보였다. **어휘가 컬럼 단위라 결합을 표현하지 못한다.**

## HIGH 2 — 선택 필드는 fail-open 이다

`requiresSameOwnerGroup?: boolean` 은 실행기가 **읽지 않아도** 타입 검사도 spec 도 통과한다.
그러면 다른 소유자 그룹의 `global_clients` 를 그대로 가리키게 되고, 그건 남의 고객 개인정보다.

→ `FkRule` 을 판별 공용체로 바꿔 `KEEP_GLOBAL` 에 `scope: 'PUBLIC' | 'OWNER_GROUP'` 를
**필수**로 만들고, 값을 얻는 유일한 경로를 `resolveKeepGlobalValue()` 로 두었다.
그 함수는 그룹을 **모르면 던진다** — "모르겠으니 해 보자" 가 남의 고객을 가리키는 행을 만든다.

## HIGH 3 — 기준선에 같은 구멍이 또 있었다

`categories.canonical_category_id → reseller.canonical_categories` 를 FK 카탈로그에서
발견했다. W6-C1 인벤토리는 `public` 만 훑으므로 `reseller` 스키마 6개가 통째로 안 보였고,
그중 **`store_id` 를 가진 3개**가 백업에도 제외 선언에도 없었다.

| 테이블 | 행 | 분류 | 근거 |
|---|---:|---|---|
| `reseller.province_product_stats` | 100 | **EXCLUDED** | `@Cron(EVERY_30_MINUTES)` 가 TRUNCATE+INSERT 로 전량 재생성 (코드 확인) |
| `reseller.reseller_tienda_link` | 0 | **CROSS_TENANT** | 재판매자↔매장 승인. `attendance.service.ts` 가 이 행으로 **판매권을 판정**한다 |
| `reseller.store_recommendations` | 0 | **CROSS_TENANT** | 재판매자↔매장 추천 + 처리 상태 |
| `reseller.canonical_categories` | 38 | GLOBAL | 전역 표준 카테고리 |
| `reseller.resellers` / `reseller_documents` | 0 | GLOBAL | 플랫폼 소속 |

→ `regen-store-backup-inventory.sh` 를 **모든 애플리케이션 스키마**로 넓혔다
(`pg_*`·`information_schema` 제외, public 이 아니면 `<스키마>.<테이블>`).
전체 216 → **222개**. public 쪽 분류는 **하나도 안 바뀌었다** — 재작성한 SQL 이
종전과 동치임이 그것으로 확인된다.

★ **"목록에 없으면 검사도 없다" 를 없애려고 만든 기준선에 같은 구멍이 있었다.**
  감시가 두 겹인데 두 겹이 같은 맹점을 공유한 것(W6-C1)과 같은 형태다.

## MEDIUM 4 — 숫자가 무엇을 세는지 흐렸다

같은 끝점에 FK 제약이 두 개 걸린 자리가 3개 있다:
`mes_material_movements.supplier_id` · `terminals.thermal_agent_id` · `terminals.zebra_agent_id`.
처리 규칙은 **컬럼 단위**이므로 스냅샷은 `DISTINCT` 로 뽑고(354 → **351**),
중복 제약은 재생성 시 **따로 경고**한다. 지우는 것은 DDL 이라 승인 대상이다(이월).

---

## 대조군 — 만든 검사가 실제로 무엇을 막는지 확인했다

**6종 전부 잡혔다.** 통과는 "검사 안 함" 과 구분되지 않는다.

| 대조군 | 결과 |
|---|---|
| DEFERRED 선언 하나 삭제 | 4 failed — 순환이 되살아나 순서를 못 정한다 |
| EXPLICIT 규칙 하나 삭제 | 2 failed — 처리 미정으로 잡힌다 |
| FK 카탈로그를 비운다 | 5 failed — "0건은 언제나 오류" |
| 정규화에서 `status` 를 뺀다 | 1 failed — 짝이 깨진 것을 잡는다 |
| `current_sale_id` 를 다시 DEFERRED 로 | 1 failed — CLEAR 일치 검사가 잡는다 |
| `global_clients` 범위를 PUBLIC 으로 낮춤 | 1 failed — 범위 축소가 잡힌다 |
| 커버리지: `reseller.*` 분류 삭제 (2종) | 각 1 failed — 새 스키마도 분류를 강제한다 |

★ 첫 판에서 순환 대조군이 **"Tests: 0 total"** 로 나왔다(종료코드는 1). `describe` 본문에서
  위상 정렬을 계산했기 때문이다. 빌드는 깨지지만 **무엇이 몇 개 남았는지 안 보인다** —
  지연 계산으로 바꿔 4개가 실패하고 23개는 그대로 돌게 했다.

---

## 남은 것 — 엔진 본체는 아직이다

**잠금(`RESTORE_ENGINE_STATUS='blocked'`)은 그대로다.** 선언이 있는 것과 엔진이 그 선언대로
넣는 것은 다른 일이고, 지금 `restoreStoreFromBackup()` 은 매니페스트를 **읽지도 않는다.**

- 모드별 실행기 2개 (`CLONE` / `IN_PLACE_RECOVERY`) + 입력 스키마 검증
- DEFERRED 원장 **집행** (지금은 타입과 판정 함수만 있다)
- 런타임 카탈로그 대조 — codex: **잠금·트랜잭션 획득 후 첫 쓰기 전에**, 정규화한 의미로 비교
- 매장별 advisory lock + 복원 중 쓰기 차단
- 커밋 전 역방향 소유 증명 (`check-tenant-ownership.sh` 의 논리를 엔진 안으로)
- ★ **목적지 `storeId` 는 서버가 확정한다** — 입력 파일의 매장 ID 로 대체 불가
