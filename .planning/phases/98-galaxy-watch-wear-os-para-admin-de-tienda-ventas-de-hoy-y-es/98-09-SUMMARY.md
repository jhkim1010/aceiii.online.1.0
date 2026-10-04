---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 09
subsystem: api
tags: [nestjs, sequelize, raw-sql, jest, watch-os, afip, stocks-ledger, tenant-isolation]

# Dependency graph
requires:
  - phase: 98-02
    provides: "WatchSource<K,R> 계약, GastosRow/IngresosRow/FacturacionRow/CajasRow 타입, WatchStoreContext/StoreClock"
  - phase: 98-08
    provides: "WatchSource raw-SQL 1문장 패턴, VENTAS_BASE_WHERE/VENTAS_DIA_SQL 공유 관례"
provides:
  - "GastosSource — ③ 지출(건수·합계)을 expenses 지점별 raw SQL 1문장으로(매장 타임존 오늘)"
  - "CajasSource — ⑥ 카하를 CashRegisterService.getTesoreriaOverview 위임으로(잔액 공식 복제 없음), D-14① userName 제거"
  - "IngresosSource — ④ 입고(매입+공방 수령만)를 stocks 원장 raw SQL 1문장으로, TALLER_NOTE_PREFIXES 단일 출처 export"
  - "FacturacionSource — ⑤ 이번 달 전표(CAE·NC 차감 순액·종류별·저장 IVA)를 afip_vouchers+sales raw SQL 1문장 + letraOf 재그룹으로"
  - "taller-notes.spec.ts — 공방 수령 note 접두어의 쓰는 쪽 소스 문구를 fs 로 고정(대조군 포함)"
affects: [98-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WatchSource 구현은 raw SQL 1문장(sequelize.query 1회) + TS 매핑 — 모델 쿼리 금지 관례를 facturacion/ingresos/gastos 에도 그대로 적용"
    - "쓰는 쪽 note 문구를 fs.readFileSync 로 읽어 상수와 리터럴 대조(taller-notes.spec.ts) — 대조군 포함(work-order.service.ts) 하여 '검사가 아무것도 안 지킨다' 사고를 막음"
    - "월 단위(periodo='mes') 원천의 itest 는 시나리오마다 다른 달을 써서 BETWEEN 범위가 안 섞이게 한다 — ±1일 범위(ventas/pagos)와 달리 월 범위는 같은 달 안 여러 시나리오가 누적된다"

key-files:
  created:
    - api-ventago/src/app/watch/resumen/sources/gastos.source.ts
    - api-ventago/src/app/watch/resumen/sources/gastos.source.spec.ts
    - api-ventago/src/app/watch/resumen/sources/cajas.source.ts
    - api-ventago/src/app/watch/resumen/sources/cajas.source.spec.ts
    - api-ventago/src/app/watch/resumen/sources/ingresos.source.ts
    - api-ventago/src/app/watch/resumen/sources/ingresos.source.spec.ts
    - api-ventago/src/app/watch/resumen/sources/taller-notes.spec.ts
    - api-ventago/src/app/watch/resumen/sources/facturacion.source.ts
    - api-ventago/src/app/watch/resumen/sources/facturacion.source.spec.ts
    - api-ventago/src/app/watch/resumen/sources/watch-sources-b.itest.ts
  modified: []

key-decisions:
  - "cajas.source.ts 는 CashRegisterService.getTesoreriaOverview 를 그대로 호출만 한다 — 잔액 공식을 9번째로 복제하지 않는다(memory: caja-balance-formula-duplicated-9-places). abierta/desde/saldo 는 isOpen 기준으로 명시적으로 null 처리하고, userName 은 매핑에서 완전히 빼서 D-14① 을 충족한다"
  - "ingresos.source.ts 의 TALLER_NOTE_PREFIXES 를 export 하고 taller-notes.spec.ts 가 recepcion.service.ts/lote.service.ts 소스 문자열을 fs 로 직접 읽어 대조한다 — import 가 아니라 소스 그렙으로, 쓰는 쪽 문구가 바뀌면 이 시험이 먼저 죽는다(work-order.service.ts 를 대조군으로 포함)"
  - "facturacion.source.ts 는 entornoProduccion/letraOf 를 그대로 import 한다 — Libro IVA 서비스 자체는 import 하지 않는다. reportes-arca.service.ts 를 재사용하면 afip_comprobantes_externos(외부 전표) 까지 합쳐지는데, D-15③ 사용자 확정에 따라 워치는 'Ventago 가 발급한 것'만 본다"
  - "facturacion itest 의 6개 시나리오는 서로 다른 달(2026-10/12, 2027-02/04/06/08)을 쓴다 — 처음엔 전부 2026-10 로 뒀다가 월 단위 BETWEEN 범위가 겹쳐 뒤 시나리오가 앞 시나리오의 전표까지 합산해 3개 테스트가 실패했다. 월 범위는 ventas/pagos 의 ±1일 거친 범위보다 훨씬 넓다는 점을 실측으로 확인"

requirements-completed: [W98-01]

# Metrics
duration: ~50min
completed: 2026-10-04
---

# Phase 98 Plan 09: gastos·ingresos·facturacion·cajas 원천 Summary

**나머지 원천 4개(gastos·ingresos·facturacion·cajas)를 WatchSource 계약으로 구현 — gastos/ingresos/facturacion 은 raw SQL 1문장 + 로컬 PG 경계시험 20건, cajas 는 getTesoreriaOverview 위임 + 단위 매핑 6건으로 D-14① 담당자 이름 제거를 확인했다.**

## Performance

- **Duration:** ~50 min (추정 — PLAN_START_TIME 기록 없이 시작, 커밋 3건은 19:37~19:40 KST-03 에 몰려 있으나 실제 작업(읍기·설계·itest 디버깅)은 그 전부터 진행)
- **Started:** 2026-10-04 (추정)
- **Completed:** 2026-10-04T22:40:00Z (추정)
- **Tasks:** 3
- **Files modified:** 10 (전부 생성)

## Accomplishments

- `GastosSource` 가 ③ 지출(건수·합계)을 `expenses` 지점별 **raw SQL 1문장**으로, 매장 타임존 기준 "오늘"(`AT TIME ZONE :tz`)로 계산 — payment_source 구분 없이 전부(레거시 gastos 전부) 집계
- `CajasSource` 가 ⑥ 카하를 **새 SQL 없이** `CashRegisterService.getTesoreriaOverview` 호출 결과를 `WatchSource` 모양으로만 옮긴다 — D-14① 담당자 이름(`userName`)을 매핑에서 완전히 제거(JSON 직렬화 시험으로 확인)
- `IngresosSource` 가 ④ 입고(매입 + 공방 수령만)를 `stocks` 원장 **raw SQL 1문장**으로 계산 — 매입 = 수동 재고 입고(레거시 이관 제외) + 시스템 입고 정정/취소, 공방 수령 = production 행 중 쓰는 쪽 note 접두어 매치만. `TALLER_NOTE_PREFIXES` export + `taller-notes.spec.ts` 가 쓰는 쪽(recepcion.service.ts·lote.service.ts) 소스 문자열을 **fs 로 직접 읽어** 리터럴로 고정(대조군: work-order.service.ts 의 `ingreso OT#`)
- `FacturacionSource` 가 ⑤ 이번 달 전표(CAE 있는 것만·NC 차감 순액·종류별·저장 `iva_liquidado`)를 `store_configs` 환경 판정 + `afip_vouchers`+`sales` **raw SQL 1문장**으로 계산, TS 에서 `letraOf` 로 종류 재그룹. D-15③ 확정대로 `afip_comprobantes_externos`(외부 전표)는 넣지 않음
- 로컬 PG(5432) 에 실제 데이터를 넣어 `watch-sources-b.itest.ts` 로 20건 경계 시험(gastos 4·ingresos 6·facturacion 6, 나머지는 unit) — AR 23:30/자정 경계, 입고 취소·정정 순량, 공방 수령/취소/수동보정, 자체생산 OT 제외, NC/ND 순액, 월 경계(발행일 폴백), homo/null 환경 격리, 테넌트 격리
- `src/app/watch` 전체 jest 168/168 통과, itest(watch-sources-a+b) 34/34 통과, tsc exit 0, eslint 0

## Task Commits

Each task was committed atomically (api-ventago 저장소, push 안 함):

1. **Task 1: gastos 원천 + cajas 원천(getTesoreriaOverview 위임, 이름 제거)** - `b1cf9173` (feat)
2. **Task 2: ingresos 원천 — 매입 + 공방 수령만(stocks 원장 1문장) + 공방 note 접두어 고정 시험** - `e82ccf40` (feat)
3. **Task 3: facturacion 원천 — 이번 달 CAE 전표 순액·종류별·저장 IVA** - `68f66e9d` (feat)

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

_Note: 플랜은 `tdd="true"` 였고 각 태스크는 spec(RED 확인) 뒤 구현(GREEN)을 같은 커밋에 담았다 — 98-02/98-08 의 선례와 같은 이유(로컬 pre-commit 훅이 `src/app/watch` 전체 jest 를 디스크 상태로 돌리므로, 태스크를 쪼개 커밋해도 검증 시점엔 이미 완성된 코드가 있어야 게이트가 통과한다). `watch-sources-b.itest.ts` 는 세 태스크가 공유하는 단일 파일이라, 각 태스크 커밋에는 그 시점까지의 describe 블록만(gastos → +ingresos → +facturacion) 들어가도록 **단계별로 내용을 되감아 스테이징**했다 — git 히스토리가 실제 작업 순서를 반영한다. SKIP_VERIFY 는 사용하지 않았다._

## Files Created/Modified

- `api-ventago/src/app/watch/resumen/sources/gastos.source.ts` - GastosSource, expenses raw SQL 1문장
- `api-ventago/src/app/watch/resumen/sources/gastos.source.spec.ts` - 단위(바인드·숫자 매핑)
- `api-ventago/src/app/watch/resumen/sources/cajas.source.ts` - CajasSource(getTesoreriaOverview 위임), D-14① 매핑
- `api-ventago/src/app/watch/resumen/sources/cajas.source.spec.ts` - 단위(열림/닫힘/세션없음·abiertaDesdeDiaAnterior·JSON 직렬화 이름 없음)
- `api-ventago/src/app/watch/resumen/sources/ingresos.source.ts` - IngresosSource, TALLER_NOTE_PREFIXES export, stocks raw SQL 1문장
- `api-ventago/src/app/watch/resumen/sources/ingresos.source.spec.ts` - 단위(바인드·숫자 매핑)
- `api-ventago/src/app/watch/resumen/sources/taller-notes.spec.ts` - 쓰는 쪽 소스 문구 fs 고정(대조군 포함)
- `api-ventago/src/app/watch/resumen/sources/facturacion.source.ts` - FacturacionSource, entorno 판정 + afip_vouchers raw SQL 1문장 + letraOf 재그룹
- `api-ventago/src/app/watch/resumen/sources/facturacion.source.spec.ts` - 단위(entorno 판정 4건·letraOf 재그룹 3건)
- `api-ventago/src/app/watch/resumen/sources/watch-sources-b.itest.ts` - gastos·ingresos·facturacion 공유 itest(20건)

## Decisions Made

- cajas/ingresos/facturacion 원천의 설계 근거는 key-decisions 참조(getTesoreriaOverview 위임, note 접두어 소스 그렙, Libro IVA 서비스 비재사용, itest 월 분리)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] facturacion.source.ts 주석 문구가 자신의 acceptance grep 과 충돌**
- **Found during:** Task 3, acceptance_criteria 그렙 자가 검증
- **Issue:** `grep -n "21 */ *121\|/ 1.21\|\* 21"` 0건을 요구하는데, 내가 쓴 주석 "IVA 는 ... 낸다(21/121 일괄 계산 없음)" 의 리터럴 "21/121" 이 그 정규식에 그대로 매치됐다. 같은 이유로 `entornoProduccion(null)` 처럼 코드를 그대로 인용한 주석이 `entornoProduccion(` 그렙 1건 제한을 2건으로 넘겼다
- **Fix:** 두 주석을 "비율로 역산하는 일괄 계산이 없다" / "config 인자에 null 을 준 경우의 동작" 으로 바꿔 같은 의미를 유지하되 정규식이 매치할 리터럴을 없앴다
- **Files modified:** `api-ventago/src/app/watch/resumen/sources/facturacion.source.ts`
- **Verification:** 두 그렙 모두 요구 건수로 복귀(21/121 패턴 0건, entornoProduccion( 1건), tsc/eslint/jest 재확인 통과
- **Committed in:** `68f66e9d`

**2. [Rule 1 - Bug] facturacion itest 3건이 같은 달 데이터 누적으로 실패**
- **Found during:** Task 3, watch-sources-b itest 1차 실행
- **Issue:** facturacion 은 월 단위(`periodo='mes'`) 원천이라 쿼리 범위가 `mesInicio`~`hoy` 전체 달이다. 처음에는 6개 시나리오를 전부 2026-10 월에 날짜만 ±2일씩 떨어뜨려 뒀는데(ventas/pagos itest 의 ±1일 분리 관례를 그대로 따름), 월 범위는 그보다 훨씬 넓어 뒤 시나리오가 앞 시나리오의 전표까지 합산해 entorno/iva_liquidado/테넌트 시험 3건이 기대값과 다른 숫자로 실패했다
- **Fix:** 6개 시나리오를 서로 다른 달(2026-10·12, 2027-02·04·06·08)로 재배치해 월 범위가 겹치지 않게 했다
- **Files modified:** `api-ventago/src/app/watch/resumen/sources/watch-sources-b.itest.ts`
- **Verification:** 16/16(이후 20/20) itest 통과
- **Committed in:** `68f66e9d`

---

**Total deviations:** 2 auto-fixed (둘 다 Rule 1 — 주석 리터럴 충돌, itest 날짜 분리 버그)
**Impact on plan:** 둘 다 계획이 요구한 검증(acceptance grep·itest 격리)을 실제로 충족시키기 위한 수정이다. 범위 확장 없음 — 동작·SQL 로직 변경 없이 주석 문구와 시험 데이터 날짜만 조정했다.

## Issues Encountered

- `store_configs` 테이블에 `store_id` 유니크 제약이 없어(PK 만 있음) itest 에서 `ON CONFLICT (store_id)` 를 쓸 수 없었다 — 더미 매장은 아직 그 테이블에 행이 없다는 것을 확인한 뒤 평범한 `INSERT` 로 바꿨다. 동작에는 영향 없음(시험 코드만의 문제).

## User Setup Required

None - 외부 서비스 설정 필요 없음.

## Next Phase Readiness

- 98-10 이 원천 6개(`VentasSource`·`PagosSource`·`GastosSource`·`IngresosSource`·`FacturacionSource`·`CajasSource`) 를 `WATCH_SOURCES` 토큰에 전부 주입하면 `WatchResumenService` 의 부팅 검사가 통과하고 `WatchResumenController` 를 모듈에 등록할 수 있다
- **열린 항목 — 지점 활성/비활성 구분 (98-02/98-08 에서 이어짐, 이번 플랜도 다루지 않음):** `watch-resumen.service.ts` 의 `loadStoreContext()` 는 여전히 `branches` 테이블의 지점을 활성/비활성 구분 없이 전부 선택기·투영에 쓴다(상단 주석에 기록됨). 이번 플랜의 네 원천(gastos/ingresos/facturacion/cajas) 은 지점 활성 여부를 전혀 다루지 않는다 — `cajas` 조차 `getTesoreriaOverview` → `resolveAllowedBranchIds` 경로가 역할 기반 접근권만 보고 `branches.is_active`(존재한다면) 는 안 본다. D-15⑤ 가 요구하는 "선택기는 활성 지점만, 비활성은 그날 값이 있을 때만 노출"은 **98-10 이 모듈을 배선할 때 다시 판단**해야 한다 — 그 시점에 build-secciones/watch-resumen.service 를 건드릴 범위가 확정되므로, 이 구분도 같은 파일들을 손대는 작업이라 거기서 함께 처리하는 것이 자연스럽다.

## Known Stubs

None - 이 플랜의 코드는 전부 실제 SQL + 실제 DB(itest) 로 검증된 원천 구현이다. 모듈 배선(98-10)이 아직 안 됐을 뿐 하드코딩된 빈 값은 없다.

## Threat Flags

None - 이 플랜이 추가한 표면(raw SQL 조회 3개 + getTesoreriaOverview 위임 1개)은 계획의 threat_model(T-98-64~T-98-68)에 전부 등록돼 있다. 전부 `:storeId` 바인드로 테넌트 경계를 걸고, itest 로 다른 매장 데이터가 섞이지 않음을 확인했다. 아직 컨트롤러/모듈에 배선되지 않아 운영 노출은 없다.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 10 referenced api-ventago files verified present (gastos/cajas/ingresos/facturacion source+spec ×4, taller-notes.spec.ts, watch-sources-b.itest.ts). All 3 task commit hashes (`b1cf9173`, `e82ccf40`, `68f66e9d`) verified in `git log --oneline --all` (api-ventago). No missing items.
