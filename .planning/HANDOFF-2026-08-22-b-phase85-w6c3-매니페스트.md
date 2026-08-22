# 핸드오프 — 2026-08-22 (b) · Phase 85 W6-C3 1단계 (FK 매니페스트)

`HANDOFF-2026-08-22-phase85-w6-복원과-테넌트경계.md` 에서 이어짐.
사용자 지시: **"phase 85만 해라"**

---

## ★ 이 세션의 한 줄

**복원 대상 152개 테이블의 FK 컬럼 351개 전부에 처리를 정했다.**
그리고 그 카탈로그를 뽑다가 **기준선이 `public` 스키마만 보고 있었다는 것**을 발견했다 —
`reseller` 스키마의 테넌트 테이블 3개가 백업에도 제외 선언에도 없었다.

---

## Phase 85 진행률

| 웨이브 | 상태 |
|---|---|
| W1 캐시 · W2 소켓 · W3 pageSize · W4 규약 · W5 무중단배포 · W8 강제지점 | ✅ 완결 |
| W4 파티셔닝 / W7 rollup / W8 p95 게이트 | ⏸ 보류 (조건 미달) |
| **W6** | 🔴 **C3 엔진 본체만 남음** |

### W6 세부
| | 상태 |
|---|---|
| W6-A·B 내보내기 · C0 fail-closed · C1 매니페스트 · C2 33개 담기 · D MinIO | ✅ 배포 |
| **W6-C3 ① FK 매니페스트** | ✅ **이번 세션 배포** |
| **W6-C3 ② 엔진 본체** | 🔴 다음 |
| W6-C4 DB 복합 FK | ⬜ 3회 배포·판매 쓰기 경로 |

---

## 배포

```
api-ventago  4824678  W6-C3 ① FK 매니페스트 + 전 스키마 인벤토리   #788 SUCCESS
             (blue/green 5002→5003 전환, smoke 5종 통과)
superproject 29c8716
DB 변경 없음 — 마이그레이션 없음 (선언·검사만)
```

---

## 만든 것

| 파일 | 무엇 |
|---|---|
| `store-restore-manifest.ts` | 처리 어휘 5종 · 순환 끊는 자리 10 · 대상 밖 부모 12 · 위상 정렬 · DEFERRED 원장 · `resolveKeepGlobalValue()` |
| `store-restore-manifest.spec.ts` | **39개.** 미정 FK 가 하나라도 생기면 빌드 실패 |
| `store-restore-fk-catalog.txt` | 운영에서 뽑은 FK 기준선 **351줄** |
| `scripts/regen-restore-fk-catalog.sh` | 재생성 (DISTINCT · 중복 제약 경고 · 원자적 rename) |
| `regen-store-backup-inventory.sh` | **전 애플리케이션 스키마로 확장** (216→222) |

### 선언과 유도의 경계 (codex E1)

```
유도한다 (카탈로그가 권위)  삽입 순서 · 부모가 복원 대상인 FK 의 REMAP 343개
선언한다 (사람이 판단)      순환 끊는 자리 10 · 복원 대상 밖 부모 12
```

152개 순서를 손으로 적으면 스키마보다 먼저 낡고 **낡은 줄도 모른다.**
spec 이 "선언 수 < 40" 을 본다 — 넘으면 사실을 베끼기 시작했다는 **추세 경보**다.

### 순환 (운영 실측)

| 묶음 | 끊은 자리 |
|---|---|
| `{stores, branches, users}` | `stores.representative_user_id` |
| `{sales, online_orders, restaurant_tables}` | `online_orders.mirror_sale_id` (★ 아래) |
| `{talleres_envios, recepciones, rework_orders}` | `envios.rework_order_id` · `envios.source_recepcion_id` |
| 자기참조 6개 | `products.parent_id` 등 — 전부 nullable |

---

## ★★ codex 검토 — HIGH 3 + MEDIUM 1, 전부 근거 대조 후 수용

전문: `.team/reviews/w6c3-manifest-resolution.md`

### HIGH — `restaurant_tables.current_sale_id` 는 역참조가 아니라 **현재 상태**다

내가 DEFERRED 로 뒀는데 codex 가 반대했고, **코드를 열어 보니 맞았다:**
`syncTableStatus()` 가 `status` 와 `currentSaleId` 를 **한 UPDATE 로** 바꾸고,
`placeOrder()` 는 이 값으로 "새 DRAFT 판매 / 기존에 누적" 을 가른다.

**운영 실측: 테이블 15개 중 1개가 `ocupada` 이고 진행 중 판매를 물고 있다.**
복제하면 새 매장이 그 자리에서 열리고 누군가 **남의 판매를 이어 마감**할 수 있다.
FK 만 `CLEAR` 해도 `status='ocupada'` 가 남아 어긋난다.
→ `OPERATIONAL_STATE_RESETS` 로 **둘을 함께** 되돌린다.

★ 이건 내 반복 실수의 변형이다 — **"과거 사실" 과 "현재 상태" 를 같이 복원했다.**
  `active_sessions`·`terminal_devices` 를 EXCLUDED 로 뺀 것과 같은 판단인데,
  **FK 어휘가 컬럼 단위라 그 결합이 안 보였다.**

### HIGH — 선택 플래그는 fail-open 이다

`requiresSameOwnerGroup?: boolean` 은 실행기가 **안 읽어도** 타입 검사와 spec 이 통과한다.
→ 판별 공용체로 `KEEP_GLOBAL.scope` 를 **필수화**하고, 값을 얻는 유일 경로를
`resolveKeepGlobalValue()` 로 만들었다. **그룹을 모르면 던진다.**

### HIGH — 기준선이 `public` 만 봤다 ★ 이번 발견

`categories.canonical_category_id → reseller.canonical_categories` 를 카탈로그에서 발견.
`reseller` 스키마 6개가 통째로 안 보였고, `store_id` 를 가진 **3개**가 백업에도
제외 선언에도 없었다.

| 테이블 | 행 | 분류 | 근거 |
|---|---:|---|---|
| `reseller.province_product_stats` | 100 | EXCLUDED | `@Cron(EVERY_30_MINUTES)` TRUNCATE+INSERT 전량 재생성 |
| `reseller.reseller_tienda_link` | 0 | CROSS_TENANT | `attendance.service.ts` 가 이 행으로 **판매권을 판정** |
| `reseller.store_recommendations` | 0 | CROSS_TENANT | 재판매자↔매장 추천 + 처리 상태 |
| `canonical_categories`·`resellers`·`reseller_documents` | 38/0/0 | GLOBAL | 플랫폼 소속 |

★ public 쪽 분류는 **하나도 안 바뀌었다** — 재작성한 SQL 이 종전과 동치임의 근거다.

### MEDIUM — 같은 끝점 FK 제약이 3개 중복

`mes_material_movements.supplier_id` · `terminals.thermal_agent_id` · `terminals.zebra_agent_id`.
스냅샷은 `DISTINCT`(354→**351**), 중복은 재생성 시 **따로 경고**한다.
지우는 것은 DDL 이라 승인 대상 — **이월**.

---

## 대조군 8종 — 전부 잡혔다

DEFERRED 삭제 / EXPLICIT 삭제 / 카탈로그 비움 / 정규화에서 status 뺌 /
current_sale_id 를 DEFERRED 로 되돌림 / global_clients 범위 낮춤 /
`reseller.*` 분류 삭제 2종.

★ 첫 판에서 순환 대조군이 **"Tests: 0 total"** 로 나왔다(종료코드는 1).
  `describe` 본문에서 정렬을 계산했기 때문 — 지연 계산으로 바꿔
  4개가 실패하고 23개는 그대로 돌게 했다. **빌드가 깨지는 것과 원인이 보이는 것은 다르다.**

---

## ★ 다음 세션 — W6-C3 ② 엔진 본체

**잠금은 그대로다.** 선언이 있는 것과 엔진이 그 선언대로 넣는 것은 다른 일이고,
지금 `restoreStoreFromBackup()` 은 매니페스트를 **읽지도 않는다.**

- 모드별 실행기 2개 (`CLONE` / `IN_PLACE_RECOVERY`) + 입력 스키마 검증
  (`backupData: any` + `...fields` 를 없앤다)
- DEFERRED 원장 **집행** — 지금은 타입과 판정 함수만 있다
- 런타임 카탈로그 대조 — codex: **advisory lock·트랜잭션 획득 후 첫 쓰기 전에**,
  파일 원문이 아니라 **정규화한 의미**로 비교, 불일치면 fail-closed
- 매장별 advisory lock + 복원 중 쓰기 차단
- 커밋 전 역방향 소유 증명 (`check-tenant-ownership.sh` 논리를 엔진 안으로)
- ★ **목적지 `storeId` 는 서버가 확정한다** — 입력 파일의 매장 ID 로 대체 불가
- `IN_PLACE_RECOVERY` 경계: "T 이후 사실이 참조했는가" — 참조된 것은 안 되돌린다

---

## 이월

- **오염 4행 정리** (사용자 보류) — `migrations/2026-08-22-w6-limpiar-filas-cruzadas.sql`
  미적용. 구멍은 막혔으므로 새로 생기지 않는다. 감사기는 이 4행으로 종료코드 1 이며
  **그것이 현재의 정확한 상태다.**
- **중복 FK 제약 3개 정리** — DDL 이라 승인 필요. 기능상 무해하나 플래너·잠금·오류가
  두 벌이 된다.
- W6-C4 DB 복합 FK: `sale_items` 등에 `store_id` → 3회 배포. nullable 인 동안
  복합 FK 는 검사되지 않으므로 `NOT NULL` 까지 가야 효력이 생긴다
- **로컬 DB(5432) 0테이블** — 이번 세션도 운영에서만 카탈로그를 뽑았다.
  복원 시 `2026-08-22-w6-talleres-missing-fks.sql` 함께 적용할 것
- `products.image_url` UTF-8 모지바케("RiÃ±onera") — 별건
- 종전 이월 유지: sudoers mode 0440 · 프론트 blue/green 없음 ·
  POS 카탈로그 P95 376ms · 소켓 한도 0 · `/me` 11쿼리 미캐시
