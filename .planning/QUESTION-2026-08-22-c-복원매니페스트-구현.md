# W6-C3 1단계 구현 — FK 매니페스트 (codex 검토 요청, 2026-08-22)

앞선 설계 자문(`.team/reviews/w6c3-design-codex.md`)에서 네가 정한 선을 그대로 지어봤다.
**엔진 본체 전에 매니페스트만** 만들었다. 복원은 여전히 `RESTORE_ENGINE_STATUS='blocked'` 다.

## 무엇을 만들었나

1. `scripts/regen-restore-fk-catalog.sh` — 복원 대상 152개 테이블의 **모든 FK 컬럼**을
   DB 카탈로그에서 뽑아 `store-restore-fk-catalog.txt` 로 커밋한다(354줄).
   CI 가 운영 DB 에 못 닿아서 스냅샷을 둔다. 엔진은 실행 직전 실물과 대조할 예정.
2. `store-restore-manifest.ts` — 처리 어휘(REMAP/KEEP_GLOBAL/CLEAR/REJECT/DEFERRED),
   순환 끊는 자리 선언 11개, 복원 대상 밖 부모 선언 11개, 위상 정렬, DEFERRED 원장.
3. `store-restore-manifest.spec.ts` — 27개. 대조군 3종을 실제로 돌려 전부 잡히는 것을 확인.

## 네 지적을 어떻게 반영했나

- **E1(순서는 제약이지 의미가 아니다)**: 152개 순서를 손으로 안 적는다.
  카탈로그에서 위상 정렬하고, **순환 끊는 자리만** 선언한다. 같은 레벨은 이름순 고정.
  그리고 **부모가 복원 대상인 FK 343개의 `REMAP` 도 유도**한다 — 사실을 손으로 안 베낀다.
  선언은 22줄뿐이고, spec 이 "선언 수 < 40" 을 지킨다(늘면 베끼기 시작했다는 신호).
- **E3(NULL 은 정상값이라 못 잡는다)**: `DeferredFkEntry` 에
  `originalValue / resolvedValue / applied` 를 남기고 `unresolvedDeferred()` 가
  **원본 non-NULL 인데 미해결**만 센다. 원본 NULL 은 안 센다.
  그리고 spec 이 **DEFERRED 컬럼은 전부 nullable** 임을 강제한다(NOT NULL 이면 1단계가 죽는다).
- **E4(공통 원인 실패)**: 위상 정렬 결과를 검증할 때 **같은 함수를 다시 부르지 않는다.**
  결과 배열의 인덱스를 놓고 카탈로그 조건을 직접 센다.

## 실측 (운영 2026-08-22)

| 항목 | 값 |
|---|---:|
| 복원 대상 테이블 | 152 |
| 그 테이블들의 FK 컬럼 | 354 |
| REMAP 으로 유도 | 343 |
| 선언(DEFERRED) | 11 |
| 선언(EXPLICIT) | 11 |
| 순환 묶음(SCC>1) | 3 |
| 자기참조 컬럼 | 6 |

순환 3묶음과 끊은 자리:
- `{stores, branches, users}` → `stores.representative_user_id` 를 끊음
- `{sales, online_orders, restaurant_tables}` → `online_orders.mirror_sale_id`,
  `restaurant_tables.current_sale_id` 를 끊음
- `{talleres_envios, talleres_recepciones, talleres_rework_orders}` →
  `talleres_envios.rework_order_id`, `talleres_envios.source_recepcion_id` 를 끊음
  (들어오는 `recepciones.envio_id`·`rework_orders.source_envio_id` 가 **NOT NULL** 이라 못 끊는다)

## ★ 이번에 발견한 것 — 인벤토리가 `public` 만 본다

`categories.canonical_category_id` 가 **`reseller.canonical_categories`** 를 가리킨다.
W6-C1 인벤토리는 `public` 스키마만 훑으므로 `reseller` 스키마 6개 테이블이 통째로 안 보인다:

| 테이블 | 행 | store_id |
|---|---:|---|
| reseller.canonical_categories | 38 | 없음 |
| reseller.province_product_stats | 100 | **있음** (FK 제약은 없음) |
| reseller.store_recommendations | 0 | **있음** |
| reseller.reseller_tienda_link | 0 | **있음** |
| reseller.resellers | 0 | 없음 |
| reseller.reseller_documents | 0 | 없음 |

즉 `store_id` 를 가진 테넌트 테이블 3개가 백업에도 제외 선언에도 없다.
"목록에 없으면 검사도 없다" 를 없애려고 만든 기준선에 같은 구멍이 있었다.

## 묻는 것

1. **매니페스트가 "선언 22 / 유도 343" 으로 갈린 것이 맞나?**
   `REMAP` 유도의 근거는 `store-backup-coverage.ts` 의 테이블 분류다. 이건 E4 가 경고한
   "백업 선언을 검증에 재사용" 과 같은 공통 원인 실패인가, 아니면 다른 것인가?
   (내 판단: 분류는 "무엇을 복원하는가" 의 **정의 자체**라 중복해 둘 이유가 없다.
    반면 소유권 검증은 별개 근거가 필요하다 — 그건 `check-tenant-ownership.sh` 가 카탈로그에서만 유도한다.)
2. **순환 끊는 자리 5개의 선택이 맞나?** 특히 묶음 2 에서 `sales` 를 마지막에 두는 것.
   `restaurant_tables.current_sale_id` 는 "지금 이 테이블에 앉은 판매" 라는 **현재 상태**인데,
   복제 매장에서 이 값을 되살리는 게 옳은가 아니면 `CLEAR` 가 옳은가?
3. **`KEEP_GLOBAL` + `requiresSameOwnerGroup` 을 규칙의 플래그로 둔 것**이 맞나,
   아니면 별도 처리(`KEEP_GLOBAL_SCOPED`)로 어휘를 늘리는 게 맞나?
4. **스냅샷 대조를 언제 하나.** 엔진이 실행 직전에 실물 카탈로그와 스냅샷을 비교해
   다르면 거부하려 한다. 이게 과한가(스키마가 바뀔 때마다 복원이 막힌다),
   아니면 이 정도가 맞나?
5. **`reseller` 스키마 3개 테넌트 테이블**을 어떻게 분류해야 하나?
   `province_product_stats` 는 크론이 재생성하는 파생 집계로 보여 EXCLUDED 가 맞을 것 같고,
   `reseller_tienda_link`·`store_recommendations` 는 재판매자와 매장 **둘에 걸쳐** 있어
   `referral_credits` 처럼 CROSS_TENANT 로 보인다. 동의하나?
6. 내가 놓친 것.

한국어. 결론 먼저. 반대할 것은 분명히 반대하라. **6개 전부 답하는 것을 우선하라.**
