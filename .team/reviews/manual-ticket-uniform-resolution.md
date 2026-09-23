# 판단 기록 — 티켓 통일 (2026-09-23)

검토 보고서: `.team/reviews/manual-ticket-uniform-codex.md`
대상: `print-agent/src/formatter.js`, `print-agent/test/*.smoke.js`

| # | 심각도 | 지적 | 판단 |
|---|---|---|---|
| 1 | **HIGH** | F2 는 `invoice.date`+`invoice.time` 을 **따로** 보내는데 date 만 파싱해 `Hora 00:00:00` 이 된다 | **수용 — 고침** |
| 2 | MEDIUM | `SaleReviewPanel`·`EnvioTimeline` 은 `invoice.date` 를 안 보내 여전히 인쇄일이 찍힌다 | **일부 수용** — 주석 정정, 수정은 보류(프론트 변경 필요) |
| 3 | LOW | 시험 fixture 가 실제 F2 계약과 달라 그 회귀를 못 잡는다 | **수용 — 고침** |
| 4 | LOW | phone 부재·F2 의 `footer.extra`·행 단위 label/value 를 안 묶는다 | **수용 — 고침** |

---

## 1 (HIGH) — 수용. 내가 만든 회귀였다.

`renderTicketDate(data.invoice?.date)` 로 바꾼 것이 원인이다. F2(`ProductList.tsx`
`autoImpTiq`)는 `date: '23/9/2026'` 와 `time: '12:21:29'` 를 **따로** 싣는다 →
날짜만 파싱하면 그 날 **자정**이 된다.

**실측으로 재현했다**(고치기 전):
```
Venta # 6 / Fecha / 23/09/2026 / Hora / 00:00:00 / Vendedor / V
```

고침: `renderTicketDate(raw, rawTime)` — `rawTime` 이 `HH:MM(:SS)` 모양이면 그것을 쓴다.
클라이언트 payload 이므로 **정규식으로 모양을 확인**하고, 아니면 무시한다(마크업이
종이에 섞이지 않게). 두 formatter 모두 같은 계약으로 부른다 — 한쪽만 고치면 또 갈라진다.

★ 이 결함은 **내 시험이 통과하는 채로** 있었다. fixture 를 ISO 한 필드로 합성했기
  때문이다. 돌연변이 4건을 죽였는데도 못 잡았다 — **돌연변이는 시험이 무엇을 지키는지
  재지, fixture 가 실제 계약과 같은지는 재지 않는다.**

## 2 (MEDIUM) — 주석만 정정. 코드는 그대로.

지적이 맞다. 내가 쓴 주석이 「SaleReviewPanel·EnvioTimeline 의 며칠 전 판매 날짜를
바로잡는다」고 **주장했는데, 두 payload 는 `invoice.date` 를 아예 안 보낸다** →
`renderTicketDate(undefined)` 가 지금 시각으로 폴백한다. 종전과 같은 동작이라 회귀는
아니지만, **주장이 사실이 아니었다.** 주석을 사실대로 고치고 미해결로 남겼다.

고치려면 **프론트에서 판매 시각을 실어 보내야** 한다 — print-agent 단독으로는 불가능하고
app 배포와 짝이 된다. 사용자 지시 범위 밖이라 **제안만 하고 손대지 않았다.**

## 3·4 (LOW) — 수용.

- 실제 F2 payload(`date`+`time`) 케이스 추가 → 돌연변이 5(=지적 1의 결함)를 죽인다
- `time` 에 마크업이 오는 케이스 추가 → 돌연변이 6 을 죽인다
- `STORE.phone` 부재 단언 추가
- `footer.extra` 를 **두 경로 모두** 확인 → 돌연변이 7 을 죽인다
- `Fecha`/`Hora` 를 **같은 `.meta-row` 안에서** label↔value 로 묶어 읽는다
  (종전에는 문서 아무 데서나 따로 찾아 행이 끊겨도 통과했다)

## 레이아웃

codex 도 「헤더 제거로 인한 파손 없음」으로 봤다 — 고정 높이·절대 위치가 없고
`.ticket-meta` 가 정상적으로 당겨진다. 남은 `.store-header` CSS 는 죽은 규칙이며
출력 공간을 차지하지 않는다. **실물 출력 확인은 사용자 몫으로 남는다.**

---

## 최종 상태

돌연변이 7건 전부 사망, 스모크 5개 전부 통과.

```
REIMPRESIÓN                     | F2
DOCUMENTO NO VÁLIDO COMO FACTURA| Venta # 6
Copia (1) : # Ticket-000006     | Fecha / 23/09/2026
Fecha / 23/09/2026              | Hora / 12:21:29
Hora / 12:21:29                 | (이하 동일)
```

남은 차이 **두 줄** — 사용자 판단 대기:
1. 배너 `DOCUMENTO NO VÁLIDO COMO FACTURA` 가 재인쇄에만 있다
2. 제목이 `Copia (n) : # Ticket-000006` vs `Venta # 6`
   (번호 형식 차이는 formatter 가 아니라 **보내는 쪽 데이터**다)
