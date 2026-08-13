# 핸드오프 — 2026-08-13 (gastos 잔여 정리)

성격: **`box_operations` 부호 규약 모순을 고쳤다 — 이론이 아니라 이미 난 사고였다.**
`.planning/HANDOFF-2026-08-12.md` 의 「gasto 편집·삭제 › 남은 것」 5개 중 4개 종료.

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

## 남은 것

### gastos
1. **수표 gasto 취소** — 상태 머신 필요. 지금은 편집·삭제 둘 다 400 으로 막아 뒀다
   (지우면 `cheques.status` 가 USADO 로 남는다). `Anular`(마감 후 반대 조작)도 미착수.
2. **카하 125 의 유령 이체 1,360,000** — 장부에 드러난 상태로 두기로 했다.
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
  실제로 한 번 날렸다 — 역패치(`perl -0pi`)로 되돌릴 것.
- 반복된 형태는 또 **「부재가 침묵한다」** — 대액 유출 경보가 gasto 에 한 번도 안 걸렸고,
  환불 retiro 결함은 그 경로가 실행된 적이 없어 숨어 있었고, 편집 구멍은 `op === null`
  분기가 조용히 통과했다.
