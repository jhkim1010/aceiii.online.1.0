# Phase 84 — 실측 (2026-08-18)

## 계기

사용자 보고: *"materia prima / talleres 컨트롤에서 작업이 잘 흐르지 않고, 개념이 명확하지 않다."*

목업: https://claude.ai/code/artifact/e6008879-c411-4dc1-866c-ee4583dc192a

## ★ 한 줄

**로트 10 은 한 달 전에 생산이 끝났는데 아직 팔 수 있는 재고가 아니다.**
화면이 복잡해서가 아니라, 시스템이 "그 25장이 어디 있나" 에 답할 구조가 없어서다.

## 운영 실측 (store 6, PG18:5434)

| 항목 | 실측 | 뜻 |
|---|---|---|
| `stocks` 중 `type='production'` | **0건** (전체 1,716건) | 생산품이 판매 재고가 된 적이 **한 번도 없다** |
| 로트 10 (LOT-2026-005, 25장) | 3공정 전부 COMPLETED · 수령 3건 전부 25/불량0 · 마지막 수령 **2026-07-15** | 그런데 `status=IN_PROGRESS`, `stocked_quantity=0` |
| 로트 10 마지막 수령 | `inventory_status=PENDING` · `target_branch_id=NULL` · `posted_at=NULL` | 입고 조건 둘 다 미충족 |
| 로트 8 (LOT-2026-003) | total 500 · available **400** · envío **0건** | **발송 없이 100 이 사라졌다** — 수량 변경 경로가 발송 말고 또 있다 |
| `talleres_recepcion_items` | **0건** (수령 3건) | 수령의 사이즈·색상 내역이 한 번도 기록된 적 없다 |
| `mes_material_movements` | 2건 / `mes_materials` 16건 | 잔액 있고 이력 0건인 자재 **7건** |
| `mes_bom` items 0개 | **3 / 4** | 레시피가 비어 Cut Ticket 이 차감할 대상이 없다 |
| store 6 `talleres_etapas.order` | planchero(5) · costurero(5) | **다음 공정이 데이터상 결정되지 않는다** |
| pin_hash 설정된 vendor | **0 / 7** | 벤더 포털에 아무도 로그인 못 한다 |
| `talleres_settlements.store_id` | **컬럼 없음** | 멀티테넌트 격리 구멍 (0건이라 아직 안 터짐) |

## 보고서가 낡았던 것 (대조 결과 정정)

착수 근거로 받은 탐색 보고서 중 **다음은 지금 사실이 아니다** — 그대로 믿고 계획하면 없는 문제를 고친다:

- ❌ "교차매장 오염 로트 #1, #9 존재" → **그 로트들은 지금 없다.** 현재 5개 로트 전부 store 6 이고
  product 도 store 6. 오염 0건.
- ❌ "`pin_hash` 마이그레이션 운영 미적용 → vendors 500" → **적용돼 있다.** 값이 안 채워졌을 뿐.
- ❌ "부모-자식 색상 자재 모델은 설계만, 미구현" → **구현돼 돌고 있다.** 자식이 재고를 들고
  부모는 0 (TEL-001 / TEL-001-NEGRO 등).

## 코드에서 확인한 것

`recepcion.service.ts` `postToStock()` — **서버는 이미 옳게 행동한다**:

```ts
// 변형 실적이 없거나 입고 지점을 안 골랐으면 아직 넣을 수 없다.
if (posting.length === 0 || !targetBranchId) {
  await recepcion.update({ inventoryStatus: PENDING }, { transaction });
  return;   // 조용히 넘어가지 않는다
}
```

문제는 방어가 아니라 **그 필수 입력을 업무 흐름의 맨 마지막까지 미뤄뒀다**는 것이다.
그래서 `PENDING` 이 예외가 아니라 정상 상태처럼 쌓인다.

## 근본 원인 둘

### ① 차원 손실
```
계획: size × color   (talleres_lotes.size_color_matrix jsonb — 있다)
실행: 총수량         (talleres_recepciones.received_quantity — 이것뿐)
재고: size × color   (trg_stocks_leaf_only 가 강제한다)
```
파이프라인 한가운데가 끝에서 반드시 필요한 차원을 버린다 → 마지막 단계가 **구조적으로 완료 불가**.

### ② 권위 있는 수량 원장 부재 ★ CODEX 가 더 근본이라고 지적
`available_quantity` 는 여러 경로가 직접 고치는 **저장값**이다. 로트 8의 100장은 그래서 사라졌다.
격자만 추가하고 이 식이 없으면 같은 증발이 반복된다:

```
재단 = 공정중 + 이동중 + 재고입고 + 불량 + 폐기 + 재작업중 + 승인된조정
```

이 식은 지금 **어느 화면에도 없다.** 그래서 로트 10 이 한 달 동안 아무에게도 안 보였다.

완제품 재고는 이미 append-only 원장(`stocks` → `stock_balances`)으로 옳게 돼 있다.
**생산 수량과 자재만 그 원리 밖에 있다.**

## CODEX 자문에서 교정된 것

1. ★ **"차원 손실" 도 증상이다.** 근본은 보존식과 상태 머신의 부재. → 이 phase 의 척추를 보존식으로.
2. ★ **모든 수령에서 격자를 강요하면 안 된다** — 현장이 계획값을 그대로 복사해 넣어 **더 나쁜 거짓말**이
   된다. 최종 공정만 필수, 중간은 총량. (목표 구조는 bundle/variant lineage, 1주 MVP 는 최종공정 격자)
3. ★ **계획 비율 자동 안분을 확인 없이 재고로 게시하면 안 된다.** 부족분이 특정 사이즈에 몰리면
   판매 가능 재고가 허위가 된다. 화면 **제안값**으로만.
4. ★ **자재를 완제품과 같은 테이블에 넣을 필요는 없지만 같은 원리여야 한다** — movement 가 진실,
   잔액은 projection. "자재는 성질이 다르니 가변 잔액만" 은 틀렸다.
5. ★ **상태를 셋으로 가른다** — `production` / `inventory` / `settlement`. 하나에 담으면 계속 모순.
6. ★ **과거 movement 를 추측해 만들지 않는다** — 감사 가능한 `OPENING_BALANCE` 이벤트로.
7. ★ **전역 `UNIQUE(store_id, order)` 를 넣지 마라** — 모든 제품이 같은 공정을 거치지 않는다.
   로트별 `UNIQUE(lot_id, sequence_no)` 가 맞다.
8. ★ **벤더 포털은 지금이 아니다** — 수량 원장이 불명확한 채로 외부 입력을 늘리면 오염만 빨라진다.

## 화면 구성 (현재)

Talleres 탭 11개 + 사이드바 Materia Prima 5페이지 = **16개**.
축이 "무엇인가"(Lote·Envío·Liquidación)지 "지금 뭘 해야 하나"가 아니다.

CODEX 제안 6축: Producción(작업 큐) · Lotes(워크스페이스) · Talleres · Inventario · Pagos · Configuración.

**단, 성공 기준은 "화면이 줄었다" 가 아니다** — 작업 큐에서 한 항목을 처리하면 다음 상태로 넘어가고
마지막에 판매 가능 SKU 재고와 지급 대상이 자동으로 생기는가.
