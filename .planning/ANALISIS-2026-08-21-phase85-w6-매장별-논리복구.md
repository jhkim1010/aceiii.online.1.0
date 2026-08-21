# Phase 85 W6 — 매장별 논리 복구: 착수 전 대조

작성 2026-08-21 · 근거는 전부 **운영 DB(srv803182:5434) 와 현행 코드에서 직접 확인**했다.

> 이 Phase 에서 계획서 수치가 낡아 있던 것이 **다섯 번**이었다. 그래서 착수 전에 먼저 센다.

---

## 1. 가장 중요한 발견 — 지금의 "백업" 은 매장의 3분의 1만 담는다

| | 수 |
|---|---|
| 운영 테이블 | **216** |
| 그중 `store_id` 를 가진 것 | **146** |
| `getStoreBackupData()` 가 훑는 것 | **49** |
| **누락** (뷰·스냅샷 제외) | **91** |
| 그중 **지금도 데이터가 있는 것** | **35** |

누락 중 업무상 무거운 것:

| 테이블 | 행 | 왜 치명적인가 |
|---|---|---|
| `role_functions` | 11,790 | 권한 배선. 없으면 복원된 매장의 역할이 아무것도 못 한다 |
| `store_clients` | 3,791 | 매장 고객 + `favor_balance`(선수금). 고객 잔액이 통째로 사라진다 |
| `stock_balances` | 442 | ★ **재고 잔액의 권위 소스**. Phase 70-06 이후 `products.stock` 은 강등됐다 |
| `credit_ledger` | 2 | 외상 원장. 채권이 사라진다 |
| `box_settlements` | 5 | 카하 정산 구간의 권위 — 정산 단위가 여기서 정해진다 |
| `caja_fuertes` | 6 | 금고 |
| `online_orders` | 12 | 온라인 주문 ↔ sales 연결 |
| `Sellers` | 13 | 판매원 |
| `ventas_suspendidas` | 2 | 보류 판매 |

지금은 비었지만 **채워지면 같은 방식으로 사라질 것**: `cheques` · `billing_*` · `mp_*` ·
`afip_vouchers` · `sync_outbox` · `sale_senias` · `stock_adjust_batches` ·
`talleres_qc_items` / `_recepcion_items` / `_rework_orders` / `_settlement_lines` ·
`shared_folders` · `product_promotions` · `product_visibility`.

★ **이건 W6 의 전제가 아니라 지금 살아 있는 결함이다.** 누군가 오늘 이 버튼을 눌러
"백업" 을 받아 두면, 그 파일에는 고객 잔액도 재고 잔액도 권한도 없다. **그런데 파일은
정상으로 보이고 복원도 성공한다.** 조용히 틀리는 부류다.

## 2. 두 번째 발견 — 지금의 "복구" 는 제자리 복구가 아니라 복제다

`restoreStoreFromBackup()` (`store.service.ts:1453`) 의 첫 동작은 `Store.create(...)` 다.
**새 매장을 만들고** `branchMap` / `userMap` / `boxMap` / `terminalMap` 으로 ID 를 재매핑한다.

즉 지금 있는 것은 **"매장 복제"** 이고, W6 이 요구하는 것은
**"이 매장을 어제 상태로 되돌린다"(제자리 복구)** 다. 둘은 다른 동작이다:

| | 복제 (현행) | 제자리 복구 (W6 요건) |
|---|---|---|
| 대상 매장 | 새로 만든다 | 기존 매장 그대로 |
| ID | 재매핑 | **보존해야 한다** — 안 그러면 MinIO key·외부 연동·인쇄물 참조가 전부 끊긴다 |
| 기존 데이터 | 없음 | **지워야 한다.** 무엇을 어디까지 지우는가가 설계의 핵심 |
| 위험 | 낮다(새 행만 는다) | **높다 — 되돌릴 수 없다** |

★ SPEC 의 "이미 있는 것: `store.service.ts` 의 백업본 복원 경로" 는 **정확하지 않다.**
있는 것은 복제 경로이고, 요건은 제자리 복구다.

## 3. 세 번째 — 트랜잭션 하나로 전부 감싼다

`restoreStoreFromBackup` 은 함수 전체를 트랜잭션 하나로 감싼다.
운영은 `idle_in_transaction_session_timeout = 60s` · `statement_timeout = 30s` ·
pgbouncer transaction pooling(`pool_size=50`).

지금은 안 터진다 — **최대 매장이 sales 137 / stocks 1,634** 이라 금방 끝난다.
하지만 Phase 85 의 목표는 300매장이고, 그때는 이 구조가 그대로 60초 벽에 부딪힌다.

## 4. 네 번째 — `stocks` 와 `stock_balances` 는 같이 넣으면 안 된다

- `stocks` 는 append-only 원장이다(`trg_stocks_immutable` 이 UPDATE/DELETE 를 DB 에서 막는다).
- `stock_balances` 는 **파생**이다 — `trg_stock_balances_apply` 가 `stocks` INSERT 마다
  같은 트랜잭션에서 갱신한다.

따라서 복구 시 **원장만 넣으면 잔액은 트리거가 만든다.** 둘 다 넣으면 잔액이 두 번 계산돼
`v_stock_balance_drift` 가 깨진다. 반대로 지금처럼 `stocks` 만 백업하고 `stock_balances` 를
빼는 것은 — 복구 경로가 트리거를 타는 한 — **결과적으로는 맞다.**
★ 다만 그것이 **의도된 설계인지, 그냥 빠뜨린 것인지 코드에는 근거가 없다.**
누락 91개 중 `stock_balances` 만 정당한 누락이고 나머지 90개는 사고라면, 그 구분이
어디에도 적혀 있지 않다는 것 자체가 결함이다.

## 5. MinIO

DB 에는 key(문자열)만 있다. JSON 에 key 를 담는 것은 **백업이 아니다** — 객체가
삭제·덮어쓰기되면 복구 불가다. 최소한 객체 manifest(key + size + etag) + 복구 시
존재·해시 검증이 필요하고, 진짜 보존을 원하면 별도 버킷의 불변 사본이 필요하다.

---

## 제안하는 범위 (판단을 구함)

이 Phase 는 이미 **"규약을 테스트로 강제한다"** 는 형태를 두 번 썼다(W4 마이그레이션 규약,
W8 강제 지점). W6 도 같은 형태가 맞다고 본다.

### W6-A — 커버리지를 테스트로 강제 ★ 먼저

`store_id` 를 가진 테이블 146개를 스키마에서 읽어, **백업이 훑는 목록과 대조**하는 spec.
어느 쪽에도 없으면 **빌드를 깨뜨린다.** 제외하려면 **제외 목록에 이유와 함께** 적어야 한다.

- 제외가 정당한 부류(초안 — 판단 필요):
  - **파생/트리거 유지**: `stock_balances` (원장에서 재생성된다)
  - **운영 상태성**: `active_sessions` · `terminal_devices` · `branch_ip_registries` ·
    `support_tokens` · `sale_idempotency_keys` — 복구 대상이 아니라 **재취득 대상**이다
  - **큐/전송 이력**: `sync_outbox` — 복구하면 **이미 나간 알림이 다시 나간다**
  - **뷰 / 임시 스냅샷**: `v_*` · `*_bak_*` · `*_backup_*`
- 나머지는 전부 담아야 한다.

이게 먼저인 이유: 지금 91개가 빠져 있다는 사실이 **어디에도 기록되지 않아** 앞으로도
테이블이 늘 때마다 조용히 벌어진다. 담는 것보다 **안 담긴 것이 보이게 하는 것**이 먼저다.

### W6-B — 커버리지 확장
A 가 만든 목록을 근거로 실제로 담는다. FK 순서는 `.planning/intel/db-schema-fks.md`.

### W6-C — 제자리 복구는 **설계부터 다시**
복제(현행)와 제자리 복구는 다른 동작이다. 후자는 **기존 데이터를 지우는 단계**가 있어
되돌릴 수 없다. 스테이징 검증 통과를 전제로 하고, 운영 실행은 사용자 승인 필수.

### W6-D — MinIO manifest

---

## 이 문서로 codex 에 묻는 것

1. **부분 복구가 전체 복구보다 위험한가?** 지금의 49개짜리 백업으로 복원하면 실제로
   무슨 불변식이 깨지는가?
2. **W6-A 의 제외 목록 초안이 맞는가?** 특히 `sync_outbox` 와 `sale_idempotency_keys`.
3. **`stocks` 만 넣고 `stock_balances` 를 트리거에 맡기는 것**이 맞는가?
   복구 경로가 배치 INSERT 를 쓰면 트리거가 행마다 도는데, 그 비용과 정합성은?
4. **ID 보존 vs 재매핑** — 제자리 복구에서 원 ID 를 보존해야 한다는 판단이 맞는가?
   시퀀스는 어떻게 다뤄야 하는가?
5. 91개 중 **지금 당장 담지 않으면 실제 사고가 나는 것**의 우선순위는?
