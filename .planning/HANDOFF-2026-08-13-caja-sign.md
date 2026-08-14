# 핸드오프 — 2026-08-13 (gastos 잔여 정리 + 수표 지불 전면 정비)

성격 둘:
1. **`box_operations` 부호 규약 모순** — 이론이 아니라 이미 난 사고였다 (아래 첫 절)
2. **수표 gasto 를 쓸 수 있는 기능으로 만들었다** — 부분 충당 / 편집·삭제 / 감사 (§A)

`.planning/HANDOFF-2026-08-12.md` 의 「gasto 편집·삭제 › 남은 것」 5개 **전부 종료**.

## 배포 목록 (전부 SUCCESS + 컨테이너 재생성)

| 커밋 | 내용 | 빌드 |
|---|---|---|
| api `924736f` | box_operations 부호 규약 통일 + 마이그레이션 | #694 |
| api `f504523` | 편집 구멍 차단 + 목록 잠금 상태 + @Audit | #695 |
| app `a05bfcb` | 자물쇠 표시 + 금액 잠금 | #620 |
| app `d2d4a7b` | Banco 손입력 → 은행 목록 콤보박스(40곳) | #621 |
| api `6e304e9` / app `d2c1853` | 수표 부분 충당 — 차액을 현금·이체로 | #696 / #622 |
| api `52395aa` / app `558cd2e` | 수표 gasto 편집·삭제(되돌리기) | #697 / #623 |
| api `95f141a` | 수표 gasto 감사 로그(append-only) | #698 |

DB 마이그레이션 3건 전부 **로컬 5432 · 운영 5434 양쪽 적용·검증 완료**.
테스트 29/29, 뮤테이션 **12종 사멸**.

---

## ★ 핵심 — 지출이 카하 잔액을 **올리고** 있었다

`box_operations.amount` 는 **크기**만 담고 방향은 `type` 이 정하는 것이 규약인데,
쓰는 쪽과 읽는 쪽이 갈려 있었다.

| type | 운영 건수 | 저장 부호 | 쓰는 곳 |
|---|---|---|---|
| gasto | 5 | **전부 음수** | `expenses.service` → `-Math.abs` (2025-12-12부터) |
| retiro | 79 | 양수 | 자동마감 / 수동 모달 |
| venta·ingreso | 124 | 양수 | 판매 / 수동 모달 |

읽는 쪽은 **9곳 전부** 양수 크기를 가정한다:
- `saldo = initial + venta + ingreso - gasto - retiro` — `cashRegister.service.ts` 6곳
  (:248, :428, :525, :1015, :1105, :1190)
- `WHEN type IN ('gasto','retiro') THEN -o.amount` — `cashRegister.service.ts:636`, `box.service.ts:72`
- `dashboard-admin.service.ts:328` 의 대액 유출 경보는 gasto 에 **한 번도 안 걸렸다**(음수라서)

→ gasto −10,000 이면 `−(−10,000)` = **+10,000**. 부호가 두 번 뒤집힌다.

### 실제로 일어난 일 — 카하 125 (store 9 ACE / 지점 15 SALA)

```
06-04  gasto  -680,000  "Compra de PC"
06-04  gasto  -680,000  "Compra de PC"   ← 89초 간격. 08-12 핸드오프의 "중복 의심" 2건
06-16  venta   +20,000                    ← 이 카하에 들어온 현금은 이게 전부다
06-18  retiro 1,380,000  "Transferencia automática a Caja Fuerte"
```

`autoCloseAndReopen` 이 잔액을 `0 + 20,000 − (−1,360,000) = 1,380,000` 으로 계산해
**그 전액을 금고로 이체**했다 (`caja_fuerte_operations` #44, 금고 8). 이후 `admin_retiro` 로 빠졌다.
차액 **1,360,000 = 두 gasto 합계와 정확히 일치**.

★ 즉 08-12 핸드오프의 남은 항목 **1번(Compra de PC 중복 의심)과 5번(부호 규약 모순)은 같은 사건**이다.

카하 241(store 6, 열림)도 `485,000` 으로 표시되고 있었다 — 실제 `255,000`.

---

## 조치 (전부 배포 완료)

| 커밋 | 내용 | 빌드 |
|---|---|---|
| api `924736f` | 부호 규약 통일 + 마이그레이션 + spec 6건 | #694 SUCCESS |
| api `f504523` | 편집 구멍 차단 + 목록 잠금 상태 + @Audit | #695 |
| app `a05bfcb` | 자물쇠 표시 + 금액 잠금 | #620 |
| 루트 `d61e878` | 서브모듈 포인터(전 세션분) | — |

### 1. 쓰기 정규화
- `expenses.service` 생성·편집 → `Math.abs` (크기)
- `online-orders.service:1643` 현금 환불 `retiro` 도 **같은 결함**이었다 →`Math.abs`.
  운영에서 이 경로는 한 번도 안 탔다(retiro 79건 전부 양수) — 드러나지 않았을 뿐이다.
- `box-operation.service` — 음수는 **400 으로 거부**한다. 조용히 `Math.abs` 로 고치면
  호출부의 잘못된 의도가 숨는다.

### 2. DB 불변식 — `migrations/2026-08-13-box-operations-amount-magnitude.sql`
```sql
UPDATE box_operations SET amount = ABS(amount) WHERE amount < 0;   -- 운영 5행 / 로컬 2행
ALTER TABLE box_operations ADD CONSTRAINT chk_box_operations_amount_non_negative CHECK (amount >= 0);
```
★ `> 0` 이 아니라 `>= 0` 이다 — 운영에 `amount = 0` 인 venta 가 2건 있다(CODEX 는 `> 0` 을 권했으나 데이터가 반증).

**로컬 5432 · 운영 5434 양쪽 적용·검증 완료** (음수 0건, 제약 존재 확인).

**적용 후 잔액**: 카하 241 → `255,000`(정상). 카하 125 → `−2,720,000`.
★ 카하 125 가 음수로 드러나는 것은 **의도한 결과**다(사용자 결정). 과거 마감·이체는
재계산하지 않는다(CODEX 자문) — 유령 이체를 덮지 않고 장부에 보이게 두는 쪽을 택했다.

### 3. 같이 찾은 편집 구멍 (별건, 같은 형태)
`updateExpense` 는 링크된 조작이 없으면(`op === null`) **카하 열림 검사도 건너뛰고
금액도 조작에 반영하지 않았다.** 삭제는 이 경우를 400 으로 막는데 편집만 뚫려 있었다.
운영에 해당 gasto 실재 — **id 16** (100,000, 카하 241, 링크 없음).
- 링크가 없으면 gasto 자신의 `boxRegisterId` 로 카하 열림을 검사한다
- **금액 변경만** 400. 설명·날짜·카테고리는 돈에 영향이 없어 계속 허용

### 4. 목록에 잠금 상태 — `cashRegisterClosed` / `hasBoxLink`
`findFiltered` 가 두 계산 컬럼을 함께 싣는다. 로컬 실DB 로 4가지 경우 검증 후 롤백
(열림+링크 / 열림+링크없음 / 마감 / 카하무관 → 전부 기대값 일치).
프론트: 마감 → 자물쇠, 링크없음 → 삭제 비활성 + 금액 입력 잠금.

★ **금액이 잠긴 gasto 는 PUT 에서 `amount` 를 아예 뺀다.** 값이 그대로여도 실어 보내면
서버가 "금액 변경 시도"로 보고 400 을 내 **설명만 고쳐도 저장이 막힌다.**
input `disabled` 만 믿지 않는다 — RHF 는 폼 값을 내부 저장소에서 읽는다.

### 5. `@Audit` — create / edit / remove
`entity_type = 'Gasto'` (운영 기존 값이 `Venta`/`Producto` 형태라 규약 일치).

---

## 검증
- spec 6건 신규(`box-operation-amount-sign.spec.ts`) + 기존 6건 = 12/12
- **뮤테이션 3종 사멸 확인**: 생성 부호 되돌림(1 fail) / 편집 부호 되돌림(1 fail) /
  금액 가드 무력화(2 fail). 예외 타입만 단언하지 않고 **`create` 미호출**까지 본다 —
  안 그러면 다른 가드로 통과한다([[test-can-pass-on-the-wrong-guard]]).
- 프론트 eslint 0 error, `tsc --noEmit` 통과

---

# §A. 수표 지불 — 쓸 수 있는 기능으로 만들었다

사용자가 "수표를 gastos 에서 쓸 수 있는 줄 몰랐다"고 해서 화면을 보여준 데서 시작됐다.
운영 `cheques` **0행** — 만들어만 두고 아무도 못 쓰던 기능이었다.

## A-1. 은행명 손입력 → 목록 선택 (app `d2d4a7b` #621)

`Banco` 가 자유 입력이라 같은 은행이 `Galicia`/`Bco Galicia`/`Galica` 로 갈린다.
수표는 나중에 카르테라에서 골라 쓰는 물건이라 은행명이 갈리면 찾기도 집계도 깨진다.

- `src/configs/banks-ar.ts` — BCRA 기준 40곳(대형 23 + 주·지역 17). **손대는 곳은 여기 하나**
- 적용 2곳: nueva-venta `PaymentSummaryModal` / ventas-online `CobroModal`.
  한 곳만 고치면 나머지에서 다시 손입력이 된다
- ★ **`freeSolo` 다** — 목록에 없는 은행 수표를 받았을 때 막으면 **판매를 등록할 수 없다.**
  오타보다 판매 차단이 더 큰 사고. 엄격 선택으로 바꾸려면 `freeSolo` 만 빼면 된다
- 운영 화면에서 실물 확인(목록 펼침 + `gali` 타이핑 필터)

## A-2. 수표가 모자라면 차액을 현금·이체로 (api `6e304e9` #696 / app `d2c1853` #622)

20만 지출에 15만 수표를 쓰는 건 실무인데 **프론트·백엔드 양쪽이** 거부했다
(`cheques.service.ts:125` 하드 블록).

- `useForExpense` 가 부분 충당을 허용하고 `shortfall` 을 반환 — 루프가 이미
  `min(remaining, face)` 로 적용하므로 끝나고 남은 값이 부족액이다
- 부족액이 있으면 `remainderSource` 요구:
  · `efectivo` → 카하 조작 **부족액만큼** · `transferencia` → 카하 원장에 안 남긴다
- `payment_source='mixto'` + `remainder_source` / `remainder_amount`
  (`migrations/2026-08-13-expenses-remainder-source.sql`, CHECK 3개)

★ **부족액은 서버가 수표에서 계산한다.** 프론트 값을 믿으면 "수표 15만인데 부족액 0"으로
  낸 적 없는 돈이 지불로 남는다(CODEX).
★ **카하 조작을 전액으로 넣으면** 마감이 나간 적 없는 현금을 빼고, 결제수단별 보고서가
  같은 gasto 를 두 번 센다(CODEX).
★ `SUM(applied_amount) + remainder_amount == amount` 는 두 테이블에 걸쳐 CHECK 로 못 건다
  → `assertExpenseFullyCovered` 가 **같은 트랜잭션에서 커밋 전에** 대조한다.
★ 차액 **금액**도 컬럼에 저장한다 — 유도하면 나중에 적용분이 바뀔 때 과거 기록이
  따라 움직여 감사가 불가능해진다(CODEX).

spec 7건 + 뮤테이션 4종 사멸.

## A-3. 편집·삭제 되돌리기 (api `52395aa` #697 / app `558cd2e` #623)

★ **이 항목은 내가 처음에 "2차 과제"로 미루고 사후 통보했다가 사용자가 되물어 바로잡은 것이다.**
CODEX 는 차단을 제안한 적이 없다 — 내 자문 요청에 이미 써 넣은 안이었고, CODEX 는
"차단은 오염을 피하지만 되돌리는 흐름이 반드시 필요하다"고 단서를 달았다.
사용자 결정: **카하가 열려 있는 동안은 편집·삭제가 가능해야 한다.**
→ [[propose-dont-declare]] 로 메모리에 남김.

- `chequesService.releaseFromExpense` 신설 — USADO → EN_CARTERA 복원 + 링크 삭제,
  되돌린 수표 id 반환
- **삭제**: 수표 복원 + 차액분 카하 조작 제거 + gasto 삭제, 한 트랜잭션
- **편집**: 금액·수표 구성이 바뀌면 배분을 **처음부터 다시** 계산
  (release → useForExpense → 부족액에 맞춰 조작 생성/수정/삭제 → 커버리지 대조)
- `/cheques/available?expenseId=` — 그 gasto 의 USADO 수표도 함께 반환.
  없으면 편집 화면이 기존 수표를 못 그려 **교체가 불가능**하다
- 카하 게이트는 **카하가 얽힌 건에만**(사용자 결정). 전액 수표·이체 차액은 제약 없음

★ 수표 복원은 `confirmChequesInHand` 를 **서버에서도** 요구한다. 이미 공급자에게 건넨
  수표를 카르테라로 되돌리면 다시 쓸 수 있게 된다. 화면만 막으면 안 묻는 경로가 생긴다.

### ★ CODEX 가 잡은 실제 결함 2건 (내 코드의 진짜 버그였다)
1. **`expenses` 행을 안 잠갔다** → 동시 편집 시 lost update. 수표만 잠가서는 못 막는다.
   `FOR UPDATE` 추가
2. **수표 잠금 순서가 요청마다 달라 교착 위험** — release 는 옛 수표, useForExpense 는
   새 수표를 제각각 순서로 잠갔다 → **id 오름차순 고정**(CLAUDE.md 「락 순서 고정」)

spec 10건 + 뮤테이션 4종 사멸.

## A-4. 감사 로그 (api `95f141a` #698)

편집이 `expense_cheques` 를 **지우고 다시 만들고**, 삭제하면 gasto 행이 사라진다
→ "이 수표가 왜 카르테라로 돌아왔나"에 답할 근거가 DB 에 안 남는다.

`expense_cheque_events` — append-only.
이벤트: `CREATED` / `REALLOCATED` / `DELETED`(동작 단위) + `APPLIED` / `RELEASED`(수표 단위).
한 요청의 모든 행이 `operation_id` 를 공유한다 — 편집 하나가
[수표 3장 해제 + 2장 적용 + 조작 수정]을 만들 수 있다.

★★ **`expense_id`/`cheque_id` 에 FK 를 걸지 않는다 — 의도적이다.**
   CASCADE 면 gasto 를 지우는 순간 감사가 함께 사라져, **가장 필요한 순간에 증거가 없어진다.**
★ UPDATE/DELETE 를 **DB 트리거**가 막는다(`stocks` 원장과 같은 방식). 로컬 실증 완료.
★ 기록 실패를 **삼키지 않는다.** 같은 트랜잭션이라 잡아 봐야 다음 문장이
  "transaction is aborted" 로 죽어 진짜 원인만 가려진다. 조용히 넘어가면 "감사 없이
  돈만 움직인" 상태가 남는다.
  → 그래서 **마이그레이션을 코드보다 먼저** 적용했다(테이블이 없으면 수표 gasto 저장이
    통째로 실패한다). 배포 후 4워커 전부 `ExpenseChequeEvent` 등록 + 부팅 정상 확인.

## ★ A-5. 아직 사람 눈으로 못 본 것

운영 `cheques` 가 **0행**이라 수표 흐름 전체(부분 충당 → 차액 지불 → 편집 → 삭제 →
감사 기록)를 실물로 못 돌렸다. 판매에서 수표를 한 장 받으면 그때 끝까지 따라갈 것.
**특히 차액분 카하 조작이 부족액만큼만 잡히는지**가 실물로 봐야 할 지점이다.

---

## 남은 것

### 수표 (§A 후속)
1. **`Anular`** — 마감된 카하의 수표 gasto 는 여전히 손댈 수 없다. 반대 조작으로 상쇄하는
   흐름이 필요하다(행을 지우지 않고 역분개). CODEX 도 "이미 정산된 box_operation 은
   `destroy` 말고 보정 조작"을 권했다.
2. 감사 로그를 **보는 화면이 없다.** 테이블에 쌓이기만 한다 — 이 리포에서 반복된
   「기능은 있는데 문이 없다」 형태가 되지 않게 조회 경로가 필요하다.
3. `payment_source` 로 필터하는 보고서가 있으면 `'mixto'` 를 빠뜨린다(CODEX 지적). 미점검.

### gastos
1. **카하 125 의 유령 이체 1,360,000** — 장부에 드러난 상태로 두기로 했다.
   실물 대조가 필요하면 그때 보정 조작을 **추적 가능하게** 넣을 것(#44 를 조용히 수정하지 말 것 — CODEX).
3. `Compra de PC` 2건이 실제 지출이었는지 — 그 카하에 들어온 현금은 20,000 뿐이라
   1,360,000 현금 지출은 물리적으로 불가능하다. 입력 오류로 보이나 **사용자가 남기기로 결정**.

### 구조 (이번 사고의 근본)
★ **잔액 계산식이 리포에 9곳 중복**돼 있다. 이번 결함이 9곳에 동시에 퍼진 이유가 이것이다.
`computeSaldo(operations, initialAmount)` 하나로 모으는 것이 다음 정리 대상
([[edit-target-needs-single-source]]).

### 08-12 핸드오프에서 이월
- 로트 10 실물 처리(배너에 PENDING 으로 떠 있다)
- §5-4 `approveReturn` 부분 환불 ↔ 전량 재고 복원 불일치
- §5-5 미검토 쓰기 경로 — `code-import`, `stocks.service`, `suspended-sales`, `work-order`
- Trello 오류 카드 3건 — **두 세션 연속 "클라우드라 push 불가"로 보류**. 이제 로컬이라 가능.
  `06TCj16i`(Ventas suspendidas 지점간 누수 ★최우선) / `AkpJUsbI`(REingreso 수량 조용히 버려짐) /
  `OX5XFplw`(Cambiar sucursal 라벨 2중). 진단은 파일·라인까지 특정돼 있다
  (`.planning/trello-inbox/report-2026-08-12.md`).

---

## 작업 방식 — 이번에 걸린 것

- **부호 규약은 코드가 아니라 데이터에 물어봐야 한다.** 코드만 읽으면 `-Math.abs` 가
  "의도된 음수 규약"으로 읽힌다. `GROUP BY type` 한 줄로 gasto 만 음수라는 게 드러났다.
- **`git checkout <file>` 로 뮤테이션을 되돌리면 같은 파일의 다른 수정까지 날아간다.**
  이번 세션에 **두 번** 날렸다. 뮤테이션 전에 `cp <file> <bak>` 하고 `cp $BAK $F` 로 복원할 것.
- ★ **범위를 줄이는 결정은 통보하지 말고 물어볼 것.** 수표 gasto 편집·삭제를 "2차 과제"로
  미룬 것은 내 판단이었는데 CODEX 권고인 것처럼 적었다. 사용자가 "codex 도 그렇게
  제안하나?"로 되물어 바로잡혔다. **외부 자문이 실제로 말한 것과 내 안을 구분할 것.**
  → [[propose-dont-declare]]
- **CODEX 는 구현 후에도 걸어라.** 이번에 설계 검토(2회)뿐 아니라 **구현된 코드**에 대해
  물었더니 행 잠금 누락·잠금 순서 교착 두 건을 잡았다. 둘 다 테스트로는 안 잡히는 것들이다.
- `codex exec` 를 heredoc 과 같은 명령에서 실행하면 **stdin 대기로 멈춘다** → `< /dev/null`.
- macOS 에는 `timeout` 이 없다(`gtimeout`). 백그라운드 + 폴링으로 처리했다.
- 반복된 형태는 또 **「부재가 침묵한다」** — 대액 유출 경보가 gasto 에 한 번도 안 걸렸고,
  환불 retiro 결함은 그 경로가 실행된 적이 없어 숨어 있었고, 편집 구멍은 `op === null`
  분기가 조용히 통과했고, 수표 기능은 **cheques 0행이라 아무도 못 쓰는 채로** 있었다.
