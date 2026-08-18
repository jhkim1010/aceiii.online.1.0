# 핸드오프 — 2026-08-18 (b) · Phase 84 W1·W2 — 생산이 재고가 되기까지

`HANDOFF-2026-08-18-entrega-confirmacion.md` 를 이어받았다.

한 줄 요약: **이 시스템에서 생산품이 처음으로 팔 수 있는 재고가 됐다.**
그리고 그 과정에서 계획이 두 번 틀렸다는 걸 확인했다 — 둘 다 **만들기 전에** 잡았다.

---

## ★ 오늘의 결과

```
stocks type='production'     0건  →  3건 (pb 651/652/653, branch 25)
Depósito Central             224 NEGRO 15 · 225 ROJO 5 · 226 CELESTE 5
LOT-2026-005                 IN_PROGRESS/34일 정체  →  COMPLETED
로트 8 의 사라진 100장        보이지 않음  →  unexplained_quantity = 100
```

---

## 배포 (전부 빌드 성공 + healthy)

| 커밋 | 내용 | 빌드 |
|---|---|---|
| app `e215fc8` | W1 — 재고 미입고 배너 딥링크 | #656 |
| api `7ecc7ec` | W2a — 입고가 로트를 닫고 disponible 을 줄인다 | #727 |
| api `a7e1e37` | W2b — 로트 상태 3분할 + 보존식 | #728 |

마이그레이션 1건 (운영·로컬 양쪽): `2026-08-18-phase84-lote-tri-status.sql`
운영 DML 2건(승인 후): 로트 10 입고 · 로트 10 카운터 정정

---

## ★ 계획이 틀린 지점 둘 — 착수 전 코드 대조가 잡았다

### 1. W1 원안("격자·지점 필수화")은 **이미 전부 구현돼 있었다**

`routing-position.ts` · `getVariantGrid()` · `RecepcionFormDialog` · `postToStock()` 의
PENDING 방어 · `PendingInventoryBanner` · `evaluateLoteCompletion()` · `ingresarAStock()`
— 전부 존재하고 배포돼 있었다. 배너 주석에는 **로트 10 이 이름으로 적혀 있기까지 했다.**

**그런데도 34일 방치됐다. 이유:** 배너가 *"수령을 detalle 와 sucursal 로 등록하라"* 고
하는데 그 수령은 이미 존재하고 envío 는 COMPLETED(pending 0)라 **다시 등록할 수 없다** —
시킨 대로 하면 `Cantidad excede pendiente` 로 거부된다. 실제로 되는 경로는
Lotes → 그 로트 → "Ingresar a stock" 인데 배너가 그걸 말하지 않았고 링크도 없었다.

→ W1 을 "**푸는 길 만들기**" 하나로 재정의. 배너 칩 → `?tab=lotes&lote=<id>&action=ingreso`.

### 2. `available_quantity` 진단이 절반 틀렸다

"입고했는데 25 그대로 = 거짓말" 이라고 했는데, 코드를 읽으니 그 값의 뜻은
**"지금 손에 있어 다음 공정으로 보낼 수 있는 수량"**(발송 −, 수령 +)이었다.
25장을 세 번 보내고 세 번 받아 25 로 돌아온 것은 **산수가 맞다.**

진짜 결함은 **재고로 나갈 때만 아무도 안 뺀다**는 것 — 그래서 이미 Depósito 에서
팔 수 있는 25장을 공방으로 다시 보낼 수 있었다. 정상 경로·수동 경로 **양쪽**에 있었다.

---

## W2 — 상태 3분할 (사용자 지시: "저비용보다 완벽하게")

싼 대안(완료 사유만 노출)을 제안했으나 사용자가 원안대로 지시 → 제대로 만들었다.

- **`lote-status.ts`** — 순수 함수, 회귀 13건. 세 축이 **서로를 안 본다**:
  `production` 은 재고를 아예 안 본다(그게 분리의 요점).
- **`inventory` 에 `BLOCKED`** — "안 들어감" 이 아니라 **"넣어야 하는데 못 넣고 있다"**.
  이게 W7 작업 큐의 원천이다. 부분 인덱스도 이 조회에 맞췄다.
- **보존식** `재단 = 손 + 공방 + 재고 + 불량` — **코드에 넣기 전에** 운영 SQL 로 검증했다.
  5개 중 4건 0, 로트 8 만 100. 공식이 맞다는 걸 확인하고 구현했다.
- **`LoteStatusService`** — 다섯 경로(수령·입고·발송·취소·SCRAP)가 판정을 공유해야 하는데
  `RecepcionService` ↔ `LoteService` 를 서로 주입하면 **DI 순환**이고, 그 실패는
  빌드가 아니라 **운영 부팅에서만** 드러난다(Phase 80 의 35분 중단과 같은 형태).
  → 모델만 쓰는 얇은 서비스. 배포 후 `(healthy)` 로 배선 확인.
- **마이그레이션이 공정·재고 축을 미리 안 채운다** — SQL 로는 routing 을 못 읽어 정확히
  계산할 수 없다. 틀린 값을 넣어두면 **그게 맞는 줄 알고 지나친다.**
  대신 `POST /talleres/lotes/recompute-status` 로 배포 후 한 번 (`5 / bloqueados 0 / descuadrados 1`).

---

## 다음 — W3 부터

### W3 (수량 변동 감사 원장) ★ 다음 세션 시작점
로트 8 의 100장은 지금 **보이기만 하고 설명할 방법이 없다.**
- `talleres_lote_quantity_events` — `SEND/RECEIVE/REJECT/REWORK/SCRAP/STOCK_POST/ADJUST`
  + before/after/사유/사용자/시각. `ADJUST` 는 **사유 필수**.
- `available_quantity` 직접 UPDATE 전수 차단 → 이벤트에서 계산·검증되는 projection.
- ★ 알려진 함정: QC `REWORK` 가 불량 수량을 **이중 계상**한다(기존 결함 D6).
- ★ SCRAP 은 지금 보존식에서 "설명되지 않음" 으로 잡힌다 — W3 에서 항으로 분리.

### 착수 전 반드시
★ **W1·W2 에서 두 번 다 계획이 틀렸다.** 코드를 먼저 읽어라.
`grep -rn "availableQuantity" src/app/subcon` 부터.

### 이후
W4(복구 큐, `autonomous:false`) · W5(자재 `OPENING_BALANCE`) ·
W6(`settlements.store_id` — **0건인 지금이 유일한 기회**) · W7(작업 큐 화면)

목업: https://claude.ai/code/artifact/e6008879-c411-4dc1-866c-ee4583dc192a

---

## 작업 방식 — 이번에 걸린 것

- ★ **"기능이 없다" 와 "기능에 닿을 수 없다" 는 다르다.** 운영 증상(재고 0건)만 보고
  기능 부재로 진단했는데, 전 경로가 구현돼 있고 **마지막 한 클릭으로 가는 길만** 없었다.
- ★ **화면이 시키는 대로 하면 거부당하는 상태**가 최악이다. 사용자는 시스템이 고장났다고
  결론내고 그 화면을 영영 안 본다. 지시문은 **실행 가능해야** 한다.
- ★ **공식은 코드에 넣기 전에 실데이터로 검증한다.** 보존식을 운영 SQL 로 먼저 돌려
  로트 8 만 걸리는 걸 보고 구현했다 — 반대 순서였으면 공식이 틀렸는지 알 방법이 없었다.
- ★ **판정 로직은 한 곳.** 수동 입고 경로에 종료 재평가가 없어 재고는 들어오는데 로트는
  영원히 진행 중이었다. 두 경로가 다른 "완료" 를 가지면 어느 화면이 맞는지 아무도 모른다.
