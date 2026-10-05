---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 13
subsystem: testing
tags: [postgres, spotcheck, reconciliation, watch-resumen]

# Dependency graph
requires:
  - phase: 98-10
    provides: "api-ventago/scripts/watch-resumen-spotcheck.sql (독립 SQL, 서비스 상수/헬퍼 미사용) — 운영 배포된 /watch/resumen"
provides:
  - "운영 매장 2곳(store 26 Shaple, store 19 NOIX)·날짜 2026-10-02 의 spotcheck 값 재확인(읽기 전용 재실행, 이전 세션 표와 완전 일치)"
  - "「결제행 합 vs Ventas」 행 — 두 매장 모두 0건/0차액(읽기 전용 SELECT로 재확인)"
  - "favor_apply 가 두 매장 최근 21일간 0건임을 확인 — D-15① 자동상계는 이 spotcheck 로 실측 대조가 불가능했던 이유를 근거로 기록"
  - "레거시 「Resumen del día」 화면 대조는 **수행되지 않음** — 사용자가 체크포인트에서 「진행」만 응답, 레거시 화면 값을 제공하지 않음"
affects: [98-12]
---

# Phase 98 Plan 13: 레거시 대조 체크포인트 — 미수행으로 종료 Summary

**운영 DB spotcheck 값(store 26/19, 2026-10-02)은 읽기 전용으로 재확인해 이전 세션 표와 정확히 일치했지만, 레거시 앱 「Resumen del día」 화면과의 실제 대조는 사용자가 수행하지 않았다. 이 SUMMARY 는 그 상태를 숨기지 않고 기록한다.**

## Status

**레거시 대조 미수행 (사용자 지시로 건너뜀).** 2026-10-05, 이 체크포인트에서 사용자는 「진행」이라고만 답했다 — 레거시 앱을 열어 값을 비교했다는 언급이 없다. 이전 세션에서 Claude 가 준비해 둔 비교표(아래)의 **레거시 열은 비워 둔다.** D-08(「웹/레거시와 숫자가 갈라지면 안 된다」를 사람이 실제 운영 데이터로 닫는다)는 **이 plan 으로는 닫히지 않았다.**

이 plan 은 사용자의 명시적 지시(「진행」)에 따라 다음 plan(98-12)으로 넘어가기 위해 종료하지만, W98-01 의 "레거시 화면과 사람이 대조" 부분은 **미해결로 남는다.**

## 레거시 대조 표

매장·날짜: **store 26 (Shaple)**, 2026-10-02 / 보조 매장: **store 19 (NOIX)**, 2026-10-02

(값은 2026-10-05 `watch-resumen-spotcheck.sql` 을 운영 5434 에 읽기 전용으로 재실행해 재확인 — 이전 세션 표와 1원 단위까지 일치)

| 지표 | Ventago (store 26) | 레거시 (store 26) | Ventago (store 19, 보조) | 레거시 (store 19) | 분류 |
|---|---|---|---|---|---|
| 판매 건수 | 54 | **대조 안 됨** | 44 | **대조 안 됨** | 대조 안 됨 |
| 판매 합계 | $25.843.900 | **대조 안 됨** | $7.950.850 | **대조 안 됨** | 대조 안 됨 |
| 벌수(prendas) | 825 | **대조 안 됨** | 919 | **대조 안 됨** | 대조 안 됨 |
| 마지막 판매 | 16:05 | **대조 안 됨** | 16:24 | **대조 안 됨** | 대조 안 됨 |
| 현금(efectivo) | $15.548.500 | **대조 안 됨** | $2.919.500 | **대조 안 됨** | 대조 안 됨 |
| 은행(bancarias) | $7.897.900 | **대조 안 됨** | $3.663.350 | **대조 안 됨** | 대조 안 됨 |
| 외상(crédito) | $2.397.500 | **대조 안 됨** | $1.368.000 | **대조 안 됨** | 대조 안 됨 |
| Favor | $0 | **대조 안 됨** | $0 | **대조 안 됨** | 대조 안 됨 (아래 「알려진 한계」 참조) |
| 지출(gastos) | $189.000 / 7건 | **대조 안 됨** | $4.933.550 / 11건 | **대조 안 됨** | 대조 안 됨 |
| 할인(descuentos) | $0 / 0건 | **대조 안 됨** | $0 / 0건 | **대조 안 됨** | 대조 안 됨 |
| 입고(ingresos) | 0건 | **대조 안 됨** | 0건(+공방 1건) | **대조 안 됨** | 대조 안 됨 |
| 전표(이번 달, facturación) | $0 / 0건(CAE 전표 0건) | **대조 안 됨** | $0 / 0건(CAE 전표 0건) | **대조 안 됨** | n/a — 두 매장 모두 CAE 있는 전표가 0건이라 D-12④ 정의(CAE 있는 전표만) 자체가 공집합. 레거시와 갈라질 여지가 구조적으로 없음 |
| **결제행 합 vs Ventas**(Pagado, 결제행 합 ≠ total 건수/차액) | **0건 / $0** (읽기 전용 SELECT 재확인) | n/a (레거시엔 이 개념 없음, Ventago 내부 정합성 지표) | **0건 / $0** (읽기 전용 SELECT 재확인) | n/a | 정의 차이 아님 — Ventago 전용 내부 정합성 검사. 결함 아님(두 매장 모두 0건) |

## 알려진 한계

1. **카하(cajas)는 과거 날짜로 재현 불가능.** `cash_registers`/`box_operations` 는 "지금 열려 있는 서랍" 상태를 반영하는 현재 시점 조회이므로, 2026-10-02 당시의 카하 상태를 지금 다시 조회해도 그날의 실제 상태(열림/닫힘/담당자)와 같지 않다. `spotcheck.sql` 의 `cajas_*` 컬럼은 그래서 대조표에서 제외했다(98-10 의 reconcile itest 는 고정 fixture 로 이 부분을 이미 검증했음 — 여기서는 운영 과거 데이터로 재현할 수 없다는 뜻).
2. **favor_apply(D-15① 자동 상계)는 이 두 매장에서 최근 21일간 0건이다.** 읽기 전용 확인:
   ```
   SELECT store_id, movement_type, count(*) FROM credit_ledger
   WHERE store_id IN (19,26) AND created_at > now() - interval '21 days'
   GROUP BY store_id, movement_type ORDER BY 1,2;
   -- 19|payment_in|9   19|sale_credit|9
   -- 26|payment_in|25  26|sale_credit|16
   -- (favor_apply 행 자체가 0건)
   ```
   즉 Favor 칸이 두 매장 모두 $0 인 것은 "자동 상계 재배분이 맞게 계산됐다"는 증거가 아니라 **그 경로가 이 표본 기간에 아예 발생하지 않았다는 것**이다. D-15① 은 이 spotcheck 로는 검증되지 않고, 98-10 의 고정 fixture itest(84 assertions, favor_apply 포함)와 돌연변이 38개(생존 0)로만 검증된 상태다.
3. **레거시 비교 자체가 0건.** 사용자가 레거시 앱(`flutter_aguila` 「Resumen del día」)을 열어 같은 매장·날짜 값을 읽어주지 않았으므로, 위 표의 "대조 안 됨" 행들은 **Ventago 쪽 계산이 올바르다는 뜻도, 틀렸다는 뜻도 아니다** — 그냥 비교 대상이 없는 상태다.

## 나중에 대조하는 법

누군가 이 비교를 마치고 싶으면:

1. 레거시 앱(`flutter_aguila`)에서 **store 26 (Shaple)** 또는 **store 19 (NOIX)**, 날짜 **2026-10-02** 로 「Resumen del día」를 연다(과거 날짜 선택 가능 여부는 레거시 앱 UI 확인 필요).
2. Ventago 쪽 값은 아래 명령으로 **언제든 다시** 뽑을 수 있다(읽기 전용, 운영 영향 없음):
   ```bash
   ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago \
     -v store_id=26 -v dia=2026-10-02 -v tz=America/Argentina/Buenos_Aires \
     -v hora=23:59:59 -f -" < api-ventago/scripts/watch-resumen-spotcheck.sql
   ```
   (store_id=19 로 바꾸면 NOIX.)
3. 「결제행 합 vs Ventas」 재확인:
   ```sql
   SELECT count(*), COALESCE(SUM(ABS(s.total_amount - spm.sum_amount)),0)
   FROM sales s
   JOIN LATERAL (SELECT COALESCE(SUM(amount),0) AS sum_amount
                 FROM sale_payment_methods WHERE sale_id = s.id) spm ON true
   WHERE s.store_id = 26 AND s.status = 'Pagado' AND s.sale_day_local = '2026-10-02'
     AND ROUND(s.total_amount::numeric,2) <> ROUND(spm.sum_amount::numeric,2);
   ```
4. 차이가 나는 지표마다 `98-REPLAN-INPUT.md §1`(레거시 SQL 요지·알려진 레거시 결함)과 `98-CONTEXT.md` D-12/D-15 를 대입해 「정의 차이」인지 「결함」인지 분류한다 — 대입이 안 되면 「원인 미상」으로 둔다(근거 없이 지목하지 않는다).

## Task Commits

이 plan 은 `files_modified: []`(검증 전용 plan)이고, 수행된 유일한 작업(체크포인트 자체)은 종전 세션에서 이미 실행됐다. 이번 세션은 재확인 SELECT 3종(spotcheck ×2, 결제행 대조 ×2, favor_apply 집계 ×1 — 전부 읽기 전용, 커밋 대상 코드 변경 없음)과 이 SUMMARY 작성만 수행했다.

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

## Decisions Made

- **레거시 대조를 강제하지 않고 사용자의 「진행」을 「이 단계를 건너뛰고 다음으로 간다」로 해석했다** — plan 의 `resume-signal` 은 "aprobado" 또는 결함 목록이었으나, 사용자가 둘 다 주지 않았다. 이를 묵시적 승인으로 간주해 가짜로 "aprobado" 라고 SUMMARY 에 적지 않고, 미수행 상태를 그대로 기록했다(memory: dont-attribute-without-evidence, propose-dont-declare).
- **운영 값은 재확인 후 재사용** — 이전 세션의 표를 그대로 베끼지 않고 2026-10-05 에 동일 SQL 을 다시 실행해 1원 단위까지 일치함을 확인했다(memory: external-audit-findings-need-verification).

## Deviations from Plan

None — plan 의 Task 1 자체(사람 레거시 대조)는 사용자가 수행하지 않았다는 사실을 그대로 보고하는 것이 이 세션의 작업이다. 코드/스키마 변경 없음.

## Issues Encountered

- 체크포인트의 `resume-signal`("aprobado" 또는 결함 목록)과 실제 사용자 응답("진행")이 일치하지 않았다. 레거시 앱에 접근할 수 있는 것은 사용자뿐이므로 Claude 가 대신 수행할 수 없는 단계였다.

## User Setup Required

**사용자가 직접 해야 하는 일(남음):** 레거시 앱(`flutter_aguila`)에서 store 26 또는 19, 2026-10-02 「Resumen del día」를 열어 위 표의 "대조 안 됨" 값들과 비교하고 차이를 알려주는 것. 「나중에 대조하는 법」 섹션에 재현 명령을 남겼다.

## Next Phase Readiness

- **98-12 로 진행 가능** — 98-12 는 `depends_on: ["98-13"]` 이지만 98-12 자신의 끝단 검증(Task 2)은 웹 화면(VentaVista/Tesorería) 대조이고 레거시 화면 대조가 아니므로, 이 plan 의 미해결 상태가 98-12 를 구조적으로 막지는 않는다.
- **열린 항목(해결 안 됨):** W98-01 의 "레거시 화면과 사람이 실제로 대조" 요구는 여전히 미해결이다. D-08 은 98-10 의 독립 SQL·itest·돌연변이로 "서비스가 정의대로 계산하는가"만 닫혔고, "그 정의가 레거시와 같은가"는 사람 확인이 없어 닫히지 않았다.
- **D-15① (favor_apply 자동상계)** 는 운영 실데이터로 단 한 번도 관찰되지 않았다(두 매장 21일간 0건) — 이 plan 으로도, 추후 레거시 대조로도 이 매장들로는 검증할 수 없다. 검증은 계속 98-10 의 fixture itest/돌연변이에 의존한다.

## Known Stubs

None.

## Threat Flags

None — 이번 세션은 읽기 전용 SELECT 만 실행했다(T-98-75 에서 요구하는 `grep -ci "insert\|update\|delete"` 재확인 결과 0).

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-05 (미수행 상태로 종료)*

## Self-Check: PASSED

이 plan 은 코드 파일을 생성/수정하지 않았다(`files_modified: []`). 확인 대상은 이 SUMMARY 파일 자체(`[ -f ... ]` 로 존재 확인 예정, 커밋 후)와 인용한 SQL 파일(`api-ventago/scripts/watch-resumen-spotcheck.sql` — 존재 확인됨, DML 동사 0건 재확인됨)뿐이다. 재확인 SELECT 5건의 결과는 위 표/섹션에 그대로 인용했고 모두 이전 세션 값과 일치했다.
