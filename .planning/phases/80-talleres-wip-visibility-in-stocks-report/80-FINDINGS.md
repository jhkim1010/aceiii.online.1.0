# Phase 80 — 실측 (2026-08-17)

계획 전에 코드와 **운영 DB** 에서 직접 확인한 것. 추측 없음.

## F1. 생산 중인 물건에는 지점이 없다 ★

| 테이블 | 지점 컬럼 |
|---|---|
| `talleres_lotes` (생산 로트) | **없음** |
| `talleres_envios` (공정 발송) | **없음** |
| `talleres_recepciones` (수령) | `target_branch_id` — **여기서 처음 정해진다** |

지점은 **완성품을 받는 시점**에 결정된다. 그러므로 "이 지점에 생산 중 N장" 이라는 값은
DB 에 존재하지 않는다.

★ **사용자 결정 (2026-08-17)**: 그래도 **지점 수로 균등 분배해서 보여준다**.
제안 단계에서 "전 지점 합계만 표시" 를 권했으나 사용자가 균등 분배를 선택했다.
→ 그렇다면 화면이 **추정치임을 스스로 말해야 한다**(§ 계획 80-02 의 표시 규약).
근거 없는 숫자가 확정 재고처럼 읽히면 발주 판단이 틀어진다.

## F2. ETA 의 원본은 이미 두 개가 있다 — 새 테이블 불필요

- **`talleres_envios.due_date`** (date) — 공정별 납기. **운영 3건 중 3건 채워져 있다.**
- **`talleres_lotes.routing_path`** (jsonb) — 공정 순서 전체. 운영 로트 5건 **전부** 있다.

실제 값 예 (`LOT-2026-002`):
```json
[{"order":1,"etapaId":1,"etapaName":"corte","vendorName":"lee"},
 {"order":2,"etapaId":2,"etapaName":"lavadero"},
 {"order":3,"etapaId":3,"etapaName":"costura"},
 {"order":4,"etapaId":4,"etapaName":"estampadero"},
 {"order":5,"etapaId":5,"etapaName":"planchero"}]
```
→ "남은 공정 수" 를 조회만으로 계산할 수 있다 = 사용자가 말한
**"마지막 or penúltima 공정이면 ETA, 아니면 미정"** 규칙이 새 스키마 없이 구현된다.

## F3. 운영 데이터 규모 (2026-08-17)

| | 값 |
|---|---|
| `talleres_lotes` | 5건 (총 760장), `routing_path` 5/5 |
| `talleres_envios` | 3건, `due_date` 3/3, 상태 전부 `COMPLETED` |
| envío 상태 enum | `PENDING` · `PARTIAL` · `COMPLETED` · `CANCELLED` |
| `talleres_etapas` | 공정 정의에 **소요시간 컬럼 없음** |

★ **표준 리드타임(공정별 평균 소요일)을 지금 만들면 안 된다** — 완료 로트가 3건뿐이라
평균의 표본이 없다. 실적이 쌓인 뒤 별도 wave.

## F4. "생산 중 수량" 의 정의가 둘이다 — 먼저 고정해야 한다

- **A. 공정에 나가 있는 것** = 열린 envío(`PENDING`/`PARTIAL`) 의 `pending_quantity` 합
- **B. 아직 입고 안 된 것** = `lote.total_quantity − lote.stocked_quantity`
  (재단만 하고 아직 발송 안 한 것 포함)

두 값은 다르다. 한 칸에 합치면 "왜 안 오는지" 를 화면이 설명하지 못한다.
→ **A 를 주 숫자로, `B − A` 를 "미착수" 로 분리**한다.

## F5. 권한은 기존 구조 그대로

`functions.seed.ts` 에 항목을 추가하면 slug 가 생기고
(`Reporte Reservado` → `reporte-reservado` 식), 컨트롤러는
`@FunctionGuard('<slug>', 'read')` 로 막는다. 매장 admin 이 Permisos 화면에서 사용자별 부여.
`reports.controller.ts` 가 이미 `reporte-stocks` · `reporte-items` 등으로 같은 패턴을 쓴다.

★ 권한 없는 사용자에게는 **열 자체를 숨긴다.** 값만 `—` 로 가리면 합계·CSV·PDF 로 샌다.

## F6. 붙일 자리와 성능 제약

- 화면: `views/reports/stocks/panels/PanelB_ItemTable.tsx` (제품 목록) — 마지막 열
- 서버: `reportsStocksCockpit.service.ts` 의 `getItems()` — **제품 목록 raw SQL 한 방**
  (정렬 화이트리스트 `sortWhitelist` 로 정렬 컬럼을 관리한다)
- ★ 제품마다 서브쿼리를 돌리면 N+1 → `product_id → (wip_qty, no_iniciado, eta, etapas_restantes)`
  를 **집계 CTE 한 번**으로 만들어 LEFT JOIN
- ★ `/api/reports/*` 는 **Flutter 앱도 쓴다**(메모리 `reports-api-has-flutter-consumers`) →
  기존 필드는 건드리지 않고 **추가만** 한다

---

# CODEX 교정 (2026-08-17) — 전문: `.gsd/review-codex-phase80-talleres-wip.md`

내 초안(§F4·F6)이 **여섯 군데 틀렸다**. 요약과 채택 결과:

## C1. WIP 정의가 틀렸다 ★ 내가 못 본 것
`열린 envío 의 pending_quantity 합` 은 **한 공정에서 수령했지만 다음 공정으로 아직 발송하지
않은 수량을 놓친다**(발송 시 `available_quantity` 감소, 수령 시 `pending_quantity` 감소).
그 수량도 이미 생산에 들어간 WIP 이다. `no_iniciado` 라는 이름도 실제로는 네 가지 상태가
섞이므로 쓰면 안 된다.
→ **채택**: `estimatedWipTotalQty = max(total_quantity − stocked_quantity, 0)` 를 총량으로,
`inWorkshopQty`(열린 envío pending 합)를 그 안의 부분집합으로. 차이는 `unassignedInProcessQty`.
최종 수령했지만 `inventory_status='PENDING'` 인 것은 **별도 상태로 분리**.

## C2. 로트당 "현재 공정" 하나는 성립하지 않는다 ★
분할 발송이면 같은 로트의 서로 다른 수량이 **동시에 여러 공정**에 있고, rework 는 되돌아간다.
`MIN/MAX(order)` 나 최근 envío 하나로 잡으면 일부 수량의 상태가 전체에 적용된다.
→ **채택**: 열린 envío 각각을 `(lote_id, etapa_id, pending_quantity)` **cohort** 로 다룬다.
`routing_path` 는 기존 `checkRoutingCanonical()` 과 같은 조건으로 검증하고, 경로에 없는
etapa 는 그 cohort 만 `UNKNOWN`. 제품 단위 응답은 `etaKnownQty`/`etaUnknownQty`/
`etaStatus: KNOWN|PARTIAL|UNKNOWN|OVERDUE` 로 **상태를 보존**한다.

## C3. `max(due_date)` 는 완성 예정일이 아니다
`due_date` 는 **그 공정의 반환 예정일**이다. penúltima 의 due_date 는 마지막 공정 *시작 전*
날짜일 뿐이고, 마지막 공정 소요시간 데이터가 없으므로 완성일을 계산할 근거가 없다.
→ **채택**: `estimatedReadyDate` 는 **최종 공정 cohort 에만**. penúltima 는 `Próximo hito`
로 이름을 달리한다(`etaBasis: FINAL_STAGE_DUE | PENULTIMATE_STAGE_DUE`).
과거 날짜는 미래 ETA 처럼 출력하지 않고 `OVERDUE` + 원래 날짜(`Atrasado desde …`).

## C4. 권한을 기존 엔드포인트의 `@FunctionGuard` 하나로 처리할 수 없다 ★
지금 items 엔드포인트는 `reporte-stocks` 사용자 전원이 쓴다. 여기 WIP 필드를 무조건 실으면
**프론트에서 열을 숨겨도 네트워크 응답에 그대로 보인다**. 반대로 엔드포인트 전체에 새 guard 를
걸면 기존 사용자가 기본 표까지 잃는다.
→ **채택**: 서버가 **필드 단위로** 판정한다. 권한 없으면 필드 자체를 빼고, WIP **정렬 요청 거부**,
export 컬럼도 제외. 캐시가 있으면 키에 권한 여부를 포함.

## C5. 균등 분배는 결정적 규칙이어야 한다
→ **채택**: `base = floor(total/N)`, `remainder = total % N`, **`branch_id ASC` 앞쪽 remainder 개에
+1**. 대상 지점 = 해당 store 의 **활성 지점**(Panel A 와 같은 정의). superadmin 전 매장 뷰는
**매장별로 나눈 뒤 합산**(매장 경계를 넘어 나누지 않는다). TOTAL 행은 **원본 합계**를 쓰고
분배값을 다시 더하지 않는다. 필드명은 `estimatedBranchWipQty` + `allocationMethod`
`allocationBranchCount` `allocationAsOf` `isEstimated:true`.
UI 는 값마다 `≈` 를 붙이고 툴팁에 "Distribución estimada en partes iguales; no es una
asignación confirmada". ★ 활성 지점 0개면 0으로 나누지 말고 `UNALLOCATABLE`.

## C6. CodigoMadre/variant 모집단과 `product_id` 를 그대로 조인하면 안 된다 ★
Panel B 의 한 행은 뷰에 따라 leaf 이거나 family 이고, 모집단은 `v_product_hijo` 가 정한다.
로트는 단일 `product_id` 라 `wip.product_id = p.id` 로 조인하면 CodigoMadre 뷰에서 자식 로트가
빠지거나 중복된다.
→ **채택**: 기존 `groupLeafIds` 와 **같은 모집단**을 WIP 에도 적용. variante 뷰는 leaf 기준,
CodigoMadre 뷰는 family 로 정규화 후 집계.

## C7 (Should). stocks 원장 조인으로 CTE 가 복제된다
메인 쿼리는 stocks 원장 행 때문에 제품당 여러 행으로 확장된다. WIP CTE 를 그대로 JOIN 하고
`SUM` 하면 **원장 행 수만큼 중복**된다.
→ **채택**: WIP CTE 를 표시 grain 당 1행으로 **미리 집계**하고 메인에서는 `MAX(...)` 로 읽는다.
회귀 테스트: stocks 원장 100행인 제품과 0행인 제품의 WIP 값이 같아야 한다.

## C8 (Should). 무결성 조건·진단
집계 조건에 `pending_quantity > 0` 를 추가하고, 다음 불일치는 **별도 진단 지표**로 센다 —
열린 상태인데 pending ≤ 0 / 완료·취소인데 pending > 0 / pending > quantity /
envío 와 lote 의 `store_id` 불일치. rework envío 는 WIP 에 포함하되
`estimatedReworkQuantity` 로 분리 반환.

## C9 (Should). 인덱스는 EXPLAIN 후에
운영 3건 규모에선 불필요. export 가 커지면
`(store_id, lote_id, etapa_id) WHERE status IN ('PENDING','PARTIAL') AND pending_quantity > 0`
부분 인덱스를 `CONCURRENTLY` 로. **실측 100ms 초과 시에만.**
