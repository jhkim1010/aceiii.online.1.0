# 핸드오프 — 2026-08-16 회계(취소 상계) + 운영 버그 4건

`HANDOFF-2026-08-14-d-sales-modify-front.md` 를 이어받았다.

한 줄 요약: **취소는 "행을 빼는 것" 이 아니라 "반대 부호 행을 더하는 것" 으로 바뀌었다.
어제 판매를 오늘 고쳐도 어제 매출이 그대로 남는다.** 그 과정에서 사용자가 신고한
운영 버그 3건(카하 개시금 유실 · Gastos 카테고리 · 매출 안 보임)을 처리했다.

---

## 배포

| 커밋 | 내용 | 빌드 |
|---|---|---|
| api `4bceadc` | 판매 수정 preview + expectedMode/expectedOriginalState | #709 |
| app `f457815` | Historial 수정 버튼 · POS 편집 모드 · 확인 다이얼로그 | #630 |
| api `f3fcf22` | MP 환불 실패를 응답에 실음 | #710 |
| app `d1e4f47` | 닫히지 않는 MP 경고 + 프로모션 경고 상시화 | #631 |
| api `5089917` | **카하 개시금이 0 으로 저장되던 문제** | #711 |
| api `7e2feaa` | **Gastos 가 전부 "Sin categoría" 로 나오던 문제** | #712 |
| app `5989eaf` | 사이드바 "UI/UX Nuevo" 토글 제거 | #632 |
| api `d33a266` | **회계 — 취소를 부호로 상계** | #713 |

전부 SUCCESS · 컨테이너 재생성 확인. **마이그레이션 없음**(스키마 변경 없음).
운영 DML 1건 실행 — §F 참조.

---

# §A. 회계 — 취소는 부호로 상계한다 ★ 이번의 본체

## 사용자 사양 (내가 처음에 잘못 옮겼다)

> "어제 판매를 고치면 **어제 매출은 건드리지 마라.** negativa venta 와 새 venta 를
>  **둘 다 오늘 날짜로** 만들어라. 원본은 총 금액과 가져간 옷의 장수를 유지하고
>  `Anulado` 는 **그냥 tag** 만 붙어야지."

★ 나는 이걸 codex 말을 옮겨 "업무 결정 필요" 로 보고했다. **틀렸다** — 이미 정해져
있던 사양이고 구현이 어긋난 것이었다. 외부 점검 결과를 그대로 전달하기 전에
"이게 정말 미결인가" 를 먼저 확인해야 했다.

## 쓰기 경로는 이미 맞았다 — 보고서가 문제였다

DB 는 사양대로다: 원본은 금액·수량 **양수 그대로 원래 날짜**에 남고 `Anulado` 는
태그일 뿐이며, 역분개(음수)와 새 판매는 오늘 날짜로 생긴다.

문제는 **6곳에 복붙된 상태 목록**이 `Anulado`/`Anulación` 을 통째로 제외한 것이다.

```
어제 100.000 판매 → 오늘 90.000 으로 수정
  종전: 어제 0,       오늘 +90.000   ← 마감한 날의 장부가 바뀐다
  이후: 어제 100.000, 오늘 -10.000   ← 차액만 오늘에
```

## 규칙 — `src/app/reports/sale-status.constants.ts` 한 곳에서만 정한다

- `ACCOUNTING_SALE_STATUSES` — 합계용. 취소 두 상태 **포함**, `Borrador` 만 제외.
  금액·장수·결제행이 역분개 쪽에서 이미 음수라 **넣기만 하면 저절로 상계된다.**
- `LIST_SALE_STATUSES` — 목록용. 취소 행 제외.
  ★ 그냥 넓히면 `/reports/*/ventas` **목록**에 음수 행과 `Anulado` 원본이 나타나
  행 수·페이지가 늘고 "재출력·수정" 액션이 취소된 판매에 붙는다.
  **이 API 는 Flutter 앱도 쓴다**(메모리 `reports-api-has-flutter-consumers`).
- `signedTxSql()` — 건수는 역분개만 −1.
  ★ 부호를 **금액이 아니라 `status` 로** 판정한다. 프로모션 무료 라인은 금액이 0 일 수 있다.

적용: cockpit 5개(Sales/Products/Items/Vendedor/BreveVenta) + `salesDimensions` +
`sales.service` 의 `getDailyStats`·`getDailySummary`.

부호를 **주지 않은 것**: 취소 건수 · 페이지 수 · 고유 고객수 · 상품 종류수,
그리고 `reseller-stats`(수요 신호) · `store.service` 활동지표(취소돼도 활동은 했다) ·
`dashboard-admin.qPulso`(`status='Pagado'` 만 세는 **이미 더 좁은** 별개 정의).

## 곁다리로 나온 것 — `'Paid'` 오타

`reportsBreveVentaCockpit` 의 상수가 `'Paid'` 였다. 운영 실제 값은 `'Pagado'` 라
**매칭 행 0건**, 즉 그 보고서는 아무것도 안 보여주고 있었다(Pagado 144건 전부 누락).
정의가 6벌로 흩어져 있으면 이렇게 조용히 갈라진다 — 그래서 공용 파일로 모았다.

---

# §B. codex 가 세 라운드에 걸쳐 막았다

**매 라운드가 실제 결함이었고, 2·3라운드는 내가 방금 고친 것이 만든 결함이었다.**

## 1라운드 — 내 버그
`getDailySummary` 에서 `normalizeStatus(status) === 'Anulación'` 으로 부호를 판정했는데,
`normalizeStatus` 는 두 취소 상태를 한 덩어리로 보여주려고 **`Anulación` 을 `Anulado` 로
합친다.** 그래서 조건이 **항상 false** — 상계가 조용히 안 일어났다.
→ 원본 `r.status` 로 판정. 테스트 308건이 못 잡아서 그 함정을 고정하는 spec 을 넣었다.

또 `salesDimensions` 누락 지적(cockpit 상수만 고치면 차원 집계는 계속 제외),
`getDailyStats.ventas_count` unsigned, `COUNT(DISTINCT)` 처리.

## 2라운드 — **배포 차단**
★ 온라인 주문 취소(`nullifyMirror`)가 **금액만** 되돌리고 `sale_items` 를 안 만들었다.
내가 "장수 +1" 로 축소해서 본 것이 실제로는 **상품·카테고리·색상·사이즈 차원 집계
전반**이 취소마다 부풀어나는 문제였다. POS 취소(`nullifySale`)는 원래부터 음수 품목
행을 만든다 — 이 경로만 빠져 있었다.
→ 전액 취소면 원본 품목의 음수 사본을 같은 트랜잭션에 생성.

## 3라운드 — 그 수정의 구멍
★ 전체/부분을 `refundAmount == null` 로 갈랐는데, `approveReturn` 은 **전액 반품이어도
계산된 금액을 항상 넘긴다.** 그래서 그 경로만 안 고쳐진 채 남았다.
→ **금액 비교**(`|refundQty| >= |original.totalAmount|`)로 판정.

---

# §C. 카하 개시금이 조용히 0 으로 저장되던 문제 (api `5089917`)

사용자 신고: "12.000 으로 시작한다고 했는데 Monto inicial $0". 로그에 4초가 그대로 있었다.

```
13:26:11  POST /cash-register/auto-open   ← POS 가 0원짜리로 먼저 연다
13:26:15  POST /cash-register/open        ← 12.000 이 4초 뒤 도착
```

`/nueva-venta` 는 카하가 없으면 `auto-open` 으로 **0원 자리표시자**를 먼저 연다.
그 뒤 모달의 금액이 도착해도 "이미 열려 있음" 분기가 기존 행을 그대로 돌려주고
**선언한 금액을 버렸다.** 응답이 201 이라 화면엔 성공 메시지가 뜬다.

★ **오늘만의 일이 아니었다** — 그 시점 최근 개시 **8건이 전부 `initial_amount=0`**
(다른 카하·다른 매장 포함). POS 를 먼저 여는 습관이면 개시금은 **항상** 유실됐다.

★ 돈이 어긋나는 방식이 하나 더: 개시금 0 이면 `withdrawOpeningFromCajaFuerte` 가
`amount <= 0` 에서 빠져나가 **금고 출금이 아예 안 일어난다.** 서랍에 넣은 현금이
장부 어디에도 안 잡혔다.

수정: 이미 열린 세션이어도 **0 → 양수** 선언은 받아들이고 금고 출금도 남긴다.
이미 선언된 금액은 덮지 않는다(개시 후 몰래 바꾸는 우회로 방지).
같은 날 기존 세션의 **0 은 승계하지 않는다**(자리표시자를 물려받으면 하루 종일 0).

**검증됨** — 사용자가 다시 열자 금고 이력에
`Retiro -$15,000 apertura_caja "Monto inicial de caja del 2026-08-16"` 이 찍혔다.
전에는 이 줄이 아예 생기지 않았다.

---

# §D. Gastos 가 전부 "Sin categoría" 로 나오던 문제 (api `7e2feaa`)

같은 화면인데 위쪽 rollup 은 "Honorarios > contador" 를 제대로 보여주고 아래
"Por Categoría" 위젯과 "Lista de gastos" 만 전부 Sin categoría 였다.

```
rollup(정상) : expenses.category_id            → expense_categories  (단수·트리)
위젯(고장)   : expenses.expenses_subcategory_id → expenses_subcategories
                                               → expenses_categories (복수)
```

| | 행 수 |
|---|---|
| `expense_categories` (신·트리) | **60** |
| `expenses_categories` (구) | **0** |
| `expenses_subcategories` (구) | **0** |
| `expenses.expenses_subcategory_id` 채워진 행 | **0** |
| `expenses.category_id` 채워진 행 | **4** |

**빈 테이블 두 개를 항상 NULL 인 컬럼으로 조인**하고 있었다 — 데이터 문제가 아니라
구조적으로 그 값밖에 못 나오는 쿼리였다. Phase 26 Wave 4 에서 카테고리가 트리로
이관될 때 남은 backward-compat 조인이 죽은 채 남아 있었다.

---

# §E. "어제 판매가 안 보인다" — 버그 아님 (조사 기록)

사용자 신고를 받고 조사했으나 **데이터가 맞았다.** 근거 셋이 일치:

1. 08-15 에 만들어진 판매는 DB 전체에 2건뿐, 둘 다 **Sager(store 15)·user 32**
2. API 로그 30시간 동안 `POST /api/sales` 는 그 2건뿐 — user 7 의 시도 자체가 없음
3. 금고의 `Cierre de caja del 2026-08-14 +104.000` 이 곧 그 08-14 판매다

기억하신 판매는 **08-14**, 조회한 날짜는 **08-15**(새벽이라 `AYER` 가 08-15 를 잡음).

★ 날짜 필터는 정상이다 — `DATE(sale_date AT TIME ZONE 매장타임존)` 으로 **현지 날짜**를
쓴다. 실제로 판매 164 는 UTC `08-14 00:15` 지만 BA 기준 `08-13 21:15` 이라 08-13 으로
올바르게 잡힌다. (메모리 `db-is-utc-so-today-needs-store-timezone` 의 함정을 여기선 피했다.)

---

# §F. 운영 데이터 정정 1건 (승인 후 실행)

온라인 미러 역분개 `sale 142` 에 품목 행이 **0개**여서 원본 141 의 +1 장이 상계되지
않았다. 배포된 코드는 앞으로만 적용되므로 이 행만 소급 보충했다.

```
INSERT 0 1  →  142: quantity -1, subtotal -1000 (141 의 price·custom_name 보존)
NOTICE: 검증 통과: store 6 장수 차이 = 0
COMMIT
```

안전장치 둘: 커밋 전 검증이 0 이 아니면 `RAISE EXCEPTION` 으로 **자동 롤백**,
`NOT EXISTS` 가드로 **두 번 실행해도 중복 없음**.

**최종 대조 — 전 매장(6·9·11·15·16) 금액·건수·장수 차이 전부 0.**

---

# §G. 남은 것

## 결정이 필요한 것
1. ★ **부분 환불의 품목 역분개** — 어느 품목이 돌아왔는지 알 수 없어 만들지 않고
   `warn` 만 남긴다. codex 는 "품목별 반품 모델이 생기기 전까지 부분 환불 승인을
   차단하자" 고 했으나 **돌아가는 업무를 멈추는 것이라 하지 않았다.**
   이 경로(`approveReturn`)는 아래 이월 항목과 **같은 함수**라 손볼 때 함께 볼 것.
2. **판매 수정 중 프로모션** — 사용자 결정 완료: "카트를 건드리면 전체 카트로 재평가",
   "평가를 productId 단위 합산으로". ★ **아직 구현 안 함.**
   막힌 지점: `sale_items` 에 priceType 컬럼이 없어 복원 줄은 `priceType: undefined` 인데
   병합 조건이 `priceType?.id` 일치를 요구해 **복원 줄과 새 줄이 안 합쳐진다.**
   지금은 수정 모드에서 프로모션을 통째로 끄고 경고만 띄운다(과다청구 가능).

## 이월 (앞 핸드오프에서 그대로)
- ★ **`approveReturn` 은 C-1 과 같은 구멍** — 환불액 역분개를 만들면서 카하를 전혀
  조정하지 않는다. **아직 안 고쳤다** (위 §G-1 과 같은 함수)
- **§E-4 미착수** — Historial 에서 ①원본 ②역분개 ③새 판매를 한 묶음으로 (`replaces_sale_id`)
- **판매 158 유령 현금 52.000** / **seña·favor 역기입 의미** / **실사 큐 13개 서랍**
- `provinceId` 비우기 미지원 / MP 환불 HTTP 멱등키 없음 / `Pendiente por pagar` 수정 불가
  (POS 확정 버튼이 `totalPagos === totalFactura` 를 요구 — 생성 경로와 공유하는 규칙)
- `/suspended-sales` 403 / 수표 `Anular` / 감사 로그 조회 화면 / `payment_source='mixto'` 보고서
- 사이드바 토글 제거로 `UiModeContext`·`UiModeProvider`·`sidebar_ui_new` 문구가 **죽은 코드**로
  남았다(동작 무해). 각 사용자의 `users.uiMode` 는 현재 값으로 고정된다.

---

## 작업 방식 — 이번에 걸린 것

- ★ **외부 점검 결과를 그대로 옮기지 말 것.** codex 가 "업무 결정 필요" 라고 한 항목을
  그대로 보고했는데, 사용자에게는 **이미 정해둔 사양**이었다. 전달 전에 "이게 정말
  미결인가" 를 먼저 확인해야 했다. (메모리 `external-audit-findings-need-verification`)
- ★ **내가 축소해서 본 것을 codex 가 넓혔다.** "장수 +1" 로 보고 후속으로 미루려 했는데
  실제로는 차원 집계 전반이었다. 숫자가 작다고 영향 범위까지 작은 게 아니다.
- ★ **"고쳤다" 의 경계를 확인할 것.** 품목 역분개를 `refundAmount == null` 로 갈랐는데
  실제 호출부는 전액이어도 금액을 넘겼다 — 호출부를 안 보고 시그니처만 보고 판단했다.
- ★ **테스트가 통과해도 안 잡히는 것이 있다.** `normalizeStatus` 함정은 308건이 전부
  통과하는 채로 숨어 있었다. 그래서 그 함정 자체를 고정하는 spec 을 따로 넣었다.
- **운영 DML 은 검증을 트랜잭션 안에 넣을 것.** 커밋 전에 계산해서 어긋나면 예외로
  롤백시키면, "반쯤 들어간 상태" 가 구조적으로 생길 수 없다.
- **한 화면의 두 부분이 다르게 보이면 데이터가 아니라 출처를 의심할 것.** Gastos 도
  판매 수정 확인 화면도 같은 모양이었다 — 같은 것을 두 경로로 구하면 갈라진다.
