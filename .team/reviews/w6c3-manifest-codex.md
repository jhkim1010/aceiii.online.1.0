# W6-C3 1단계 FK 매니페스트 검토 — codex (2026-08-22)

결론: **선언 22 / 유도 343이라는 구조는 맞다.** 다만 현재 상태로 엔진 구현에 들어가는 것은 반대한다. `restaurant_tables.current_sale_id`는 `DEFERRED`가 아니라 운영 상태 정규화 정책으로 빼야 하고, owner-group 제한은 실행기가 놓칠 수 없는 판별 공용체로 바꿔야 한다. 또한 `reseller` 스키마를 포함하는 전 스키마 인벤토리 게이트가 먼저 필요하다.

## 지적

[HIGH] `api-ventago/src/app/store/store-restore-manifest.ts:135` — 현재 영업 중인 식당 테이블 상태를 복제 매장에 되살린다

  문제: `restaurant_tables.current_sale_id`는 단순 역참조가 아니라 `status`와 원자적으로 유지되는 현재 운영 상태다. CLONE에서 과거의 진행 중 판매를 다시 연결하면 새 매장이 점유 상태로 시작하고, 사용자가 판매를 재개·마감하여 중복 영업 사실을 만들 수 있다. FK만 `CLEAR`해도 `status='ocupada'`가 남아 drift가 생긴다.

  근거: 매니페스트는 이 컬럼을 `DEFERRED`로 선언한다. 실제 서비스는 `syncTableStatus()`에서 `status`와 `current_sale_id`를 같은 트랜잭션으로 갱신하고, 첫 주문은 `current_sale_id` 유무로 새 DRAFT 판매 생성 여부를 결정한다.

  수정: CLONE에서는 `current_sale_id = NULL`과 비점유 `status`를 한 정책으로 정규화한다. 즉 이 컬럼을 단순 FK 어휘의 `CLEAR` 한 줄로 끝내지 말고, 테이블 단위 post-restore invariant로 선언한다. IN_PLACE_RECOVERY의 현재 상태 복원 여부는 별도 모드 정책으로 둔다.

[HIGH] `api-ventago/src/app/store/store-restore-manifest.ts:54` — owner-group 개인정보 경계가 선택 플래그라 실행기가 조용히 무시할 수 있다

  문제: `requiresSameOwnerGroup?: boolean`은 `KEEP_GLOBAL` 처리기가 이 필드를 읽지 않아도 타입 검사와 현재 spec을 모두 통과한다. 그러면 다른 owner group의 `global_clients`를 유지하여 타 그룹 고객 개인정보를 참조한다.

  근거: `FkRule`의 플래그는 optional이고, 현재 테스트에는 플래그가 붙은 모든 규칙이 실제 범위 검사를 요구한다는 구조적 강제가 없다. `store_clients.global_client_id`와 `client_merges.winner_global_client_id`만 수동으로 `true`를 둔다.

  수정: 어휘 문자열을 늘리기보다 `FkRule`을 판별 공용체로 만든다. 예: `KEEP_GLOBAL`은 `scope: 'PUBLIC' | 'OWNER_GROUP'`를 필수로 하고, `OWNER_GROUP` 처리기는 원본·목적지 그룹 검증 없이는 값을 반환할 수 없게 한다. 이 구조를 못 만들면 `KEEP_GLOBAL_SCOPED`가 현재 optional 플래그보다 안전하다.

[HIGH] `api-ventago/scripts/regen-restore-fk-catalog.sh:67` — 전 스키마 테넌트 인벤토리의 구멍이 이번 변경에도 남아 있다

  문제: FK 스냅샷이 다른 스키마의 부모는 보지만 자식은 의도적으로 `public`으로 제한한다. 따라서 `reseller`의 `store_id` 보유 테이블 3개는 백업·제외·교차 테넌트 어느 분류에도 없고, 이 매니페스트 테스트도 이를 검출하지 않는다.

  근거: SQL은 `n.nspname = 'public'`을 강제한다. 실제 `reseller.province_product_stats`, `reseller.store_recommendations`, `reseller.reseller_tienda_link`는 `store_id`를 갖지만 public 인벤토리 밖이다.

  수정: 엔진 전에 W6-C1 인벤토리를 애플리케이션 소유 스키마 전체로 확장하고 `(schema, table)`을 식별자로 사용한다. `province_product_stats`는 재생성 가능한 파생 데이터로 EXCLUDED, 나머지 두 테이블은 재판매자와 매장 사이의 승인·상호작용 레코드라 CROSS_TENANT로 분류한다. CLONE은 세 테이블 모두 복제하지 않는다.

[MEDIUM] `api-ventago/src/app/store/store-restore-manifest.spec.ts:125` — 스냅샷 중복 제약과 선언 대상의 정확한 간선을 구분하지 않는다

  문제: 매니페스트와 stale 검사가 `table.column`만 키로 사용해 동일 컬럼에 중복 FK 제약이 있어도 통과한다. 현재 354줄 중 `mes_material_movements.supplier_id` 2줄, `terminals.thermal_agent_id` 2줄, `terminals.zebra_agent_id` 2줄로 고유 컬럼은 351개다. 따라서 “FK 컬럼 354개”와 “REMAP 343개” 수치는 제약 중복을 포함한다.

  근거: `fkKey()`는 부모·제약명을 버리고, `keys = new Set(edges.map(fkKey))`도 중복을 제거한 뒤 존재 여부만 본다.

  수정: 먼저 중복 제약이 의도인지 정리한다. 처리 규칙이 컬럼 단위라면 생성 SQL에서 동일 endpoint를 `DISTINCT`하고 중복 제약 감사는 별도 실패 항목으로 둔다. 실물 대조를 제약 단위로 하려면 constraint name/OID가 아닌 안정적인 `(child schema/table/columns, parent schema/table/columns, deferrability)` 정규형을 스냅샷에 담는다.

## 질문별 답

1. **맞다.** 복원 집합은 백업 계약의 정의이므로 `SIMPLE ∪ CUSTOM` 재사용은 E4의 공통 원인 실패가 아니다. 단, 그 집합이 완전한지는 독립적인 전 스키마 인벤토리가 반증해야 한다. `선언 수 < 40`은 안전 불변식이 아니라 추세 경보다.

2. **5개 중 4개 선택은 타당하나 `restaurant_tables.current_sale_id`의 복원은 반대한다.** `online_orders.mirror_sale_id`와 talleres 두 컬럼, 대표 사용자는 DEFERRED가 자연스럽다. sales를 마지막에 두는 순서 자체는 맞다. 식당 현재 상태만 CLONE에서 `current_sale_id=NULL`과 비점유 status를 함께 강제한다.

3. **optional 플래그는 반대한다.** `KEEP_GLOBAL`에 필수 `scope`를 둔 판별 공용체가 가장 낫다. 별도 `KEEP_GLOBAL_SCOPED`도 optional boolean보다는 안전하지만, disposition과 scope를 분리한 타입이 의미가 더 정확하다.

4. **실행 직전 exact 대조는 과하지 않고 필수다.** 다만 파일 원문/생성시각이 아니라 정규화한 카탈로그 의미를 비교한다. 복원 트랜잭션과 복원 advisory lock을 획득한 뒤, 첫 쓰기 전에 비교하고 불일치 시 fail-closed한다. 배포 절차는 스키마 변경과 스냅샷 갱신을 같은 릴리스로 묶어야 한다.

5. **동의한다.** `province_product_stats=EXCLUDED(파생)`, `reseller_tienda_link=CROSS_TENANT(승인 관계)`, `store_recommendations=CROSS_TENANT(재판매자↔매장 상호작용/상태)`가 맞다. 단순히 `store_id`가 있다는 이유로 매장 소유로 보면 안 된다.

6. **놓친 것은 세 가지다.** 식당 상태-FK의 결합 불변식, optional scope의 fail-open 가능성, 그리고 스냅샷의 중복 FK 3개다. 추가로 런타임 대조는 TOCTOU를 줄이기 위해 잠금·트랜잭션 안에서 수행하고, 스냅샷 파일 갱신은 임시 파일 후 원자적 rename으로 바꾸는 편이 안전하다.

## 검증

- `npm test -- --runInBand src/app/store/store-restore-manifest.spec.ts`: 27/27 통과
- 운영 DB에는 연결하지 않았다.
