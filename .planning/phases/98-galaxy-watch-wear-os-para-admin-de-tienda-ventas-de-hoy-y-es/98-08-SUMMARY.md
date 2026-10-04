---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 08
subsystem: api
tags: [nestjs, sequelize, raw-sql, jest, watch-os, favor-ledger, tenant-isolation]

# Dependency graph
requires:
  - phase: 98-02
    provides: "WatchSource<K,R> 계약, VentasRow/PagosRow 타입, WatchStoreContext/StoreClock"
provides:
  - "VentasSource — ① Hoy 7개 지표(합계·건수·벌수·마지막판매·어제대비·할인건수·할인액)를 sales+sale_items 지점별 CTE 한 문장으로 계산"
  - "PagosSource — ② Medios de pago 다섯 칸(efectivo·bancarias·credito·favor·otros)을 sale_payment_methods+credit_ledger UNION ALL 한 문장으로 계산, D-15① favor 자동상계 재배분 포함"
  - "medioDePagoWatch(slug) — 결제수단 slug → 다섯 칸 순수 함수(import 없음)"
  - "VENTAS_BASE_WHERE/VENTAS_DIA_SQL — '오늘 판매'의 단일 정의, ventas·pagos 두 원천이 공유"
affects: [98-09, 98-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "두 원천이 같은 '대상 행' 정의를 쓸 때는 SQL 조각 문자열을 export 해서 공유한다(복제 금지) — VENTAS_BASE_WHERE/VENTAS_DIA_SQL"
    - "signedTxSql(alias) 같은 '뒤에 FILTER 를 붙일 수 있는 SUM(CASE...)' 문자열은 FILTER (WHERE ...) 를 텍스트로 이어붙여 재사용한다 — 새 CASE 문을 베끼지 않는다"
    - "원장의 '재배분'(favor_apply 자동상계)은 결제행 합계를 건드리지 않고 칸 사이에서만 이동시킨다 — 다섯 칸의 합이 항상 결제행 합과 같다는 불변식으로 검증"
    - "WatchSource 구현은 raw SQL 한 문장(sequelize.query 1회) + TS 매핑만, 모델 쿼리 금지(@Public 라우트 테넌트 훅 no-op 우회 방지)"

key-files:
  created:
    - api-ventago/src/app/watch/resumen/sources/ventas.source.ts
    - api-ventago/src/app/watch/resumen/sources/ventas.source.spec.ts
    - api-ventago/src/app/watch/resumen/sources/pagos.source.ts
    - api-ventago/src/app/watch/resumen/sources/pagos.source.spec.ts
    - api-ventago/src/app/watch/resumen/sources/medio-de-pago.ts
    - api-ventago/src/app/watch/resumen/sources/medio-de-pago.spec.ts
    - api-ventago/src/app/watch/resumen/sources/watch-sources-a.itest.ts
  modified: []

key-decisions:
  - "medioDePagoWatch 는 daily-summary.util.ts 의 classifyPayment/ledgerKeyFor 를 재사용하지 않고 새 순수 함수를 둔다 — 레거시 분류는 매장별 은행 수단 slug(pagos-dani 등)를 정규식으로 못 잡아 'otro' 로 흘리는데, 워치는 '아는 slug(efectivo/credito/favor/seña) 화이트리스트 + 나머지=은행' 규칙이 필요해서 의미가 다르다(파일 머리 주석에 근거 기록)"
  - "ventas·pagos 두 원천은 '오늘 판매' 정의(VENTAS_BASE_WHERE·VENTAS_DIA_SQL)를 ventas.source.ts 에서 export 해 pagos.source.ts 가 import 하는 형태로 공유한다 — 플랜이 명시한 공유 방식 그대로"
  - "api-ventago push 는 보류한다 — 98-02 의 동일 결정과 같은 이유(REPLAN-INPUT §3: 페어링과 resumen 은 함께 배포, 원천 6종이 모듈에 배선되는 98-10 에서 한 번에 push). CLAUDE.md의 '묻지 말고 push' 기본값보다 이 플랜의 명시적 지연 지시가 우선(메모리: executor-subagents-push-despite-instruction)"

requirements-completed: [W98-01]

# Metrics
duration: 70min
completed: 2026-10-04
---

# Phase 98 Plan 08: ventas·pagos 원천 — Favor 자동상계 포함 Summary

**VentasSource(① Hoy 7개 지표)와 PagosSource(② 결제수단 5칸, D-15① favor_apply 자동상계 재배분 포함)를 각각 raw SQL 한 문장으로 구현하고, 로컬 PG(5432) 에 실제 데이터를 넣어 27개 itest(취소 역분개·지점 상계·23:30 경계·favor 6종 경계)로 검증했다.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-10-04T21:10:00Z (추정)
- **Completed:** 2026-10-04T21:53:00Z
- **Tasks:** 2
- **Files modified:** 7 (전부 생성)

## Accomplishments

- `VentasSource` 가 ① Hoy 섹션의 7개 지표(판매 합계·건수·벌수·마지막 판매·어제 같은 시각 대비·할인 건수·할인 합계)를 지점별로 **한 문장**(`WITH base/items/agg`)에서 계산 — `sale-status.constants.ts` 의 `saleBranchSql`·`signedTxSql`·`ACCOUNTING_SALE_STATUSES`·`LIST_SALE_STATUSES`·`EXCLUDE_DEUDA_PAGO_SQL` 를 그대로 import(복제 없음)
- `PagosSource` 가 ② Medios de pago 다섯 칸을 `sale_payment_methods`(명시 결제) + `credit_ledger`(favor_apply 자동상계) 를 `UNION ALL` 한 **한 문장**에서 계산하고, TS 에서 `medioDePagoWatch(slug)` 로 칸을 정하고 자동상계분만큼 `favor += A, credito -= A` 로 재배분
- `medioDePagoWatch` 순수 함수(import 0) — 레거시 `tbanco`("현금·외상·Favor·seña 가 아닌 모든 것") 규칙을 복원해 매장별 은행 수단 slug 를 놓치지 않음
- `VENTAS_BASE_WHERE`/`VENTAS_DIA_SQL` 를 `ventas.source.ts` 에서 export 해 `pagos.source.ts` 가 import — 두 원천의 "오늘 판매" 정의가 갈라지지 않음(그렙으로 고정)
- 실제 로컬 PG(5432) 에 더미 매장 2개(지점 2개 + 대조 매장 1개) 를 만들어 **27개 itest** 통과: AR 23:30 경계, 같은 날/전일 취소 역분개, 역분개 지점 불일치 상계, 회수판매·Borrador·movido·devuelto 제외, 어제 같은 시각 컷오프, ultimaVenta, 할인, 테넌트 격리(ventas 9건) + 결제수단 분류, 같은날 취소 상계, 회수판매 제외, D-15① favor 6종(자동상계·명시favor구분·같은날취소·전일취소·나중회수제외·테넌트격리)(pagos 9건)
- `src/app/watch/resumen/sources` 전체 jest(단위 30건) + itest(27건) 통과, tsc exit 0, eslint 0

## Task Commits

Each task was committed atomically (api-ventago 저장소, push 안 함):

1. **Task 1: ventas 원천 — sales+sale_items 지점별 CTE 한 문장** - `aeb33648` (feat)
2. **Task 2: pagos 원천 + 결제수단 칸 분류(순수 함수)** - `dd142336` (feat)

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

_Note: 플랜은 `tdd="true"` 였고 각 태스크는 spec(RED 확인) 뒤 구현(GREEN)을 같은 커밋에 담았다 — 98-02 의 선례와 같은 이유(로컬 pre-commit 훅이 `src/app/watch` 전체 jest 를 디스크 상태로 돌리므로, 태스크를 쪼개 커밋해도 검증 시점엔 이미 완성된 코드가 있어야 게이트가 통과한다). SKIP_VERIFY 는 사용하지 않았다._

## Files Created/Modified

- `api-ventago/src/app/watch/resumen/sources/ventas.source.ts` - VentasSource, VENTAS_BASE_WHERE/VENTAS_DIA_SQL export
- `api-ventago/src/app/watch/resumen/sources/ventas.source.spec.ts` - 단위(쿼리 1회·바인드 리터럴·숫자 매핑)
- `api-ventago/src/app/watch/resumen/sources/pagos.source.ts` - PagosSource(UNION ALL 한 문장 + favor_auto 재배분)
- `api-ventago/src/app/watch/resumen/sources/pagos.source.spec.ts` - 단위(쿼리 1회·바인드·favor_auto 양/음수 재배분)
- `api-ventago/src/app/watch/resumen/sources/medio-de-pago.ts` - medioDePagoWatch(slug) 순수 함수
- `api-ventago/src/app/watch/resumen/sources/medio-de-pago.spec.ts` - 분류 13건
- `api-ventago/src/app/watch/resumen/sources/watch-sources-a.itest.ts` - 두 원천 공유 itest(ventas 9건 + pagos 9건), 더미 매장 2개(테넌트 격리 대조용)

## Decisions Made

- `medioDePagoWatch` 를 `daily-summary.util.ts` 분류 함수와 별개로 둠(key-decisions 참조)
- 두 원천의 "오늘 판매" 정의 공유 방식: export 상수(key-decisions 참조)
- api-ventago push 보류(key-decisions 참조)

## Deviations from Plan

None - 계획을 그대로 실행했다. `<action>` 이 제시한 SQL 구조(`WITH base/items/agg`, `pagos`/`favor_auto` UNION ALL)를 그대로 구현했고, 모든 behavior/itest 항목이 수정 없이 통과했다.

## Issues Encountered

None.

## User Setup Required

None - 외부 서비스 설정 필요 없음.

## Next Phase Readiness

- 98-09(나머지 원천 4종 — gastos/ingresos/facturacion/cajas)가 같은 `WatchSource` 패턴과 `VENTAS_BASE_WHERE`/`VENTAS_DIA_SQL` 공유 관례를 참고할 수 있음
- 98-10 이 `VentasSource`·`PagosSource` 를 `WATCH_SOURCES` 토큰에 주입하면 `WatchResumenService` 의 부팅 검사가 그 두 키를 즉시 받아들임(98-02 가 이미 요구하는 6개 중 2개 충족)
- **알려진 한계(98-02 에서 이어짐, 이번 플랜 범위 밖)**: D-15 ⑤ 지점 활성/비활성 구분이 아직 미구현 — `watch-resumen.service.ts` 상단 주석에 기록돼 있고, `ventas`/`pagos` 원천은 `branches` 테이블의 지점을 활성·비활성 구분 없이 전부 대상으로 한다(지점 필터는 98-02 의 합성기가 함). 이번 플랜의 두 태스크는 지점 활성 여부를 전혀 다루지 않으므로 이 한계는 그대로 열려 있다 — 98-09/98-10 중 처리 여부를 다시 판단할 것.

## Known Stubs

None - 이 플랜의 코드는 전부 실제 SQL + 실제 DB(itest) 로 검증된 원천 구현이다. 모듈 배선(98-10)이 아직 안 됐을 뿐 하드코딩된 빈 값은 없다.

## Threat Flags

None - 이 플랜이 추가한 표면(두 raw SQL 조회)은 계획의 threat_model(T-98-60~T-98-64)에 전부 등록돼 있다. 둘 다 `s.store_id = :storeId`/`cl.store_id = :storeId` 로 테넌트 경계를 걸고, itest 로 다른 매장 데이터가 섞이지 않음을 확인했다. 아직 컨트롤러/모듈에 배선되지 않아 운영 노출은 없다.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 7 referenced api-ventago files verified present (`ventas.source.ts`, `ventas.source.spec.ts`, `pagos.source.ts`, `pagos.source.spec.ts`, `medio-de-pago.ts`, `medio-de-pago.spec.ts`, `watch-sources-a.itest.ts`). Both task commit hashes (`aeb33648`, `dd142336`) verified in `git log --oneline --all` (api-ventago). No missing items.
