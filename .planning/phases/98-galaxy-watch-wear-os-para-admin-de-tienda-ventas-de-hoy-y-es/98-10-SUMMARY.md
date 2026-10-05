---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 10
subsystem: api
tags: [nestjs, sequelize, postgres, wear-os, mutation-testing, codex-review]

# Dependency graph
requires:
  - phase: 98-02
    provides: "WatchResumenService(부팅 검사)·WatchResumenController(미등록)·WatchTokenGuard·build-secciones·계약 v2"
  - phase: 98-08
    provides: "VentasSource·PagosSource(D-15① favor 자동상계)"
  - phase: 98-09
    provides: "GastosSource·IngresosSource·FacturacionSource·CajasSource, D-15⑤ 이월 항목"
provides:
  - "watch.module.ts — WatchResumenController·WatchTokenGuard·원천 6개·WATCH_SOURCES 배선, CashRegisterModule import"
  - "D-15⑤ 지점 활성/비활성 구분 해소 — 선택기만 좁히고 porSucursal·총계는 활성 여부와 무관하게 전부 집계"
  - "scripts/watch-resumen-spotcheck.sql — 독립 SQL(서비스 상수·헬퍼 비사용) 지점별+TOTAL 전 지표"
  - "watch-resumen-reconcile.itest.ts — 고정 fixture 서비스·spotcheck·손계산 3자 일치(84 assertions)"
  - "scripts/mutantes-watch.sh + test/mutantes/watch.json — 38개 돌연변이, 죽음 38/생존 0"
  - "CODEX P1(TenantContext storeId 명시검증)·P2(ingresos eventos 순수량) 수정"
  - "운영 배포: Jenkins api-new-coolsistema #1080 SUCCESS, api_ventago 컨테이너 재생성, 스모크 통과"
affects: [98-13]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Nest DI 부팅 검사를 TestingModule 로 실제 모듈 그래프에서 검증(가짜 전역 Sequelize/MemoryCacheModule 커넥션 + overrideGuard) — DB 없이도 provider 배선 누락을 잡는다"
    - "독립 SQL(spotcheck) 은 GROUPING SETS ((branch_id),()) 로 지점별+TOTAL 을 한 패스에 내고, COUNT(DISTINCT) 계열만 UNION ALL 로 '지점별 합'을 재현(서비스가 porSucursal 을 그냥 더하는 것과 같은 산수를 쓴다)"
    - "선택기(sucursales) 노출과 porSucursal/총계 집계를 분리 — 활성 플래그는 선택기만 좁히고 돈 집계는 절대 좁히지 않는다"

key-files:
  created:
    - api-ventago/scripts/watch-resumen-spotcheck.sql
    - api-ventago/src/app/watch/resumen/watch-resumen-reconcile.itest.ts
    - api-ventago/src/app/watch/watch-module-boot.spec.ts
    - api-ventago/scripts/mutantes-watch.sh
    - api-ventago/test/mutantes/watch.json
  modified:
    - api-ventago/src/app/watch/watch.module.ts
    - api-ventago/src/app/watch/watch-guard-scope.spec.ts
    - api-ventago/src/app/watch/watch-token.guard.ts
    - api-ventago/src/app/watch/watch-token.guard.spec.ts
    - api-ventago/src/app/watch/resumen/watch-resumen.service.ts
    - api-ventago/src/app/watch/resumen/watch-resumen.service.spec.ts
    - api-ventago/src/app/watch/resumen/build-secciones.ts
    - api-ventago/src/app/watch/resumen/build-secciones.spec.ts
    - api-ventago/src/app/watch/resumen/sources/ingresos.source.ts
    - api-ventago/src/app/watch/resumen/sources/watch-sources-a.itest.ts
    - api-ventago/src/app/watch/resumen/sources/watch-sources-b.itest.ts

key-decisions:
  - "D-15⑤(98-02/08/09 이월) 해소 방식: BranchRef.isActive 를 선택적 필드로 추가(기존 호출부 하위호환, undefined=활성 취급) — build-secciones.ts 의 sucursales 계산만 'isActive===false && 그날 ventas 행 없음' 일 때 숨기고, porSucursal·총계·parseSucursal 은 전혀 건드리지 않는다(돈을 숨기지 않는다는 지시를 구조적으로 만족)"
  - "watch-resumen-reconcile.itest.ts 의 전표(afip_vouchers) FK 판매는 ventas/pagos 집계 범위(±2일) 밖(2020년)에 둔다 — 전표가 가리키는 판매의 날짜는 facturacion 집계와 무관(voucher 의 created_at/cbte_fch 만 본다)이므로, 오늘 날짜로 두면 ventas/pagos 총계가 전표용 판매까지 세어 하이집계된다(실제로 처음 그렇게 작성해 total 15490≠3850 로 걸렸다)"
  - "CODEX P1(TenantContext storeId 불일치 미검증)은 코드 검증 결과 현재 구현에서 재현되지 않음(resolve() 가 항상 동기 덮어쓰기) — 그래도 방어적 명시 검사 + 회귀 테스트 추가(비용 0, 미래 구현 변경에 대한 안전망)"
  - "CODEX P2 중 2건은 이월: favor_auto 의 credito 음수 가능성(쓰기 경로 sales-create.service.ts 의 불변식에 의존하는 리포팅 레이어 밖의 문제) · ingresos '수동 매입' source allowlist 부재(현재 재현 안 되는 가상의 미래 위험, product 결정 필요) — 범위를 넓히지 않음"
  - "운영 EXPLAIN 대상 매장(26, 14일 판매 최다)은 레거시 이관 더미라 '오늘'(2026-10-04) 실데이터가 0건 — 문자 그대로 '오늘' 로 측정하고, 추가로 그 매장의 역대 최다 하루(2017-10-10, 163건)로도 재측정해 실제 부하 하에서도 예산 안임을 확인(둘 다 기록)"

requirements-completed: [W98-01, W98-02]

# Metrics
duration: ~3h (추정 — PLAN_START_TIME 미기록, 첫 커밋 20:55 ~ 마지막 커밋 21:54 + 선행 조사/설계 시간)
completed: 2026-10-04
---

# Phase 98 Plan 10: Watch resumen 모듈 배선 + 전체 대조 + 운영 배포 Summary

**98-02 합성기와 98-08/09 원천 6개를 watch.module.ts 에 배선하고, 독립 SQL(spotcheck.sql)·고정 fixture itest(84 assertions)·돌연변이 38개(생존 0)로 전체를 대조한 뒤, CODEX 가 잡은 P1/P2 2건을 고치고 페어링(98-01)과 resumen 을 한 번에 운영 배포(Jenkins #1080 SUCCESS)했다. D-15⑤ 지점 활성/비활성 구분(98-02/08/09 이월 항목)도 이번에 해소했다.**

## Performance

- **Duration:** ~3h (추정)
- **Started:** 2026-10-04 (추정, PLAN_START_TIME 미기록)
- **Completed:** 2026-10-04T21:54:33-03:00
- **Tasks:** 3
- **Files modified:** 16 (5 생성 + 11 수정, api-ventago) + 1 생성(root, CODEX 리뷰 기록)

## Accomplishments

- `watch.module.ts` 가 `WatchResumenController`·`WatchTokenGuard`·원천 6개 클래스·`WATCH_SOURCES` useFactory 를 전부 등록(`CashRegisterModule` import) — `GET /watch/resumen` 이 운영에서 응답
- D-15⑤(지점 활성/비활성 구분) 해소 — 선택기(sucursales)는 활성 지점만(비활성+그날 매출 없음→숨김), `porSucursal`·총계는 활성 여부와 무관하게 전부 집계(비활성 지점에 매출이 있으면 절대 안 사라짐). 단위 시험 7건 추가
- `watch-module-boot.spec.ts` — 실제 `watch.module.ts` 를 Nest `TestingModule` 로 컴파일해 98-02 의 부팅 검사(원천 하나라도 빠지면 서버가 안 뜬다)가 실제 모듈 그래프에서도 동작함을 확인(가짜 전역 Sequelize 커넥션 + `overrideGuard` 로 DB 없이)
- `scripts/watch-resumen-spotcheck.sql` — 서비스의 TS 상수·헬퍼를 전혀 쓰지 않는 독립 SQL 로 지점별+TOTAL 행에 전 지표(ventas·pagos·favor 재배분·gastos·ingresos·facturacion·cajas) 계산. DML 없음·금지 식별자(saleBranchSql 등) 0건 자가 검증 통과
- `watch-resumen-reconcile.itest.ts` — 고정 fixture(favor 자동상계+나중 회수 제외·같은날/전날 취소·회수판매 제외·23:30 경계·지점 2곳)에서 서비스·spotcheck·손계산 3자 일치(84 assertions), D-15② 웹 대조식(`getDailySummary` 등가 쿼리)·다섯 칸 합==hoy.total 불변식 포함
- `scripts/mutantes-watch.sh` + `test/mutantes/watch.json` — 가드·페어링·역할필터·합성기(W1 asOf·W2 정렬키 통일)·원천 6개(D-15① favor 재배분 4종 포함)·cajas 돌연변이 38개 — **죽음 38·생존 0·적용안됨 0·컴파일오류 0**(실측, 2차 반복 끝에 전부 해결)
- 운영 최대 매장(store 26) EXPLAIN ANALYZE — 원천 6개 전부 steady-state 수 ms, 100ms 예산 안(아래 표)
- CODEX 자문 2회 — P1(TenantContext storeId 명시검증 누락, 검증 결과 현재 미재현이나 방어적으로 수정)·P2(ingresos eventos 가 같은날 취소로 순량 0 인 모델도 세던 결함, 수정) 반영, 나머지 P2 2건은 이유와 함께 이월
- 페어링(98-01)+resumen(98-02/08/09/10) 한 번의 배포 — Jenkins `api-new-coolsistema` #1080 SUCCESS, `api_ventago` 컨테이너 재생성(healthy), 운영 스모크(무토큰 401·pairing-codes 201+no-store·poll 202) 통과

## Task Commits

Each task was committed atomically (api-ventago 저장소):

1. **Task 1: 모듈 배선 + D-15⑤ 해소 + spotcheck SQL + reconcile itest** - `3d9aee7a` (feat)
2. **Task 2: 돌연변이 스위트 + ayerMismaHora 타임존 경계 시험** - `69e0d162` (test)
3. **Task 3: CODEX P1/P2 수정 → 커밋 → push → Jenkins/컨테이너 확인 → 스모크** - `db358b3e` (fix, CODEX 수정분) + push + 운영 확인(코드 변경 없는 단계)

**Plan metadata:** `ad55cb1`(root 저장소 — api-ventago 포인터 갱신 + CODEX 리뷰 기록 `.team/reviews/manual-98-10-api.md`, push 완료)

_Note: 플랜은 `tdd="true"` 였고 Task 1 은 spec(RED 확인) 뒤 구현(GREEN)을 한 커밋에 담았다(98-02/08/09 의 선례와 같은 이유 — 로컬 pre-commit 훅이 `src/app/watch` 전체 jest 를 디스크 상태로 돌리므로, 태스크를 쪼개 커밋해도 검증 시점엔 이미 완성된 코드가 있어야 게이트가 통과한다). Task 2 는 플랜이 "커밋·push 하지 않는다" 고 명시했으므로 Task 1 커밋 뒤 측정만 하고 별도 시점에 커밋했다. Task 3 의 CODEX 수정은 별도 fix 커밋으로 분리했다(SKIP_VERIFY 미사용)._

## Files Created/Modified

- `api-ventago/src/app/watch/watch.module.ts` - WatchResumenController·WatchTokenGuard·원천 6개·WATCH_SOURCES 배선, CashRegisterModule import
- `api-ventago/src/app/watch/watch-guard-scope.spec.ts` - 기대 집합에 watch.module.ts 추가 + SRC_ROOT 2단계 버그 수정(dist/ 훑던 결함) + dist/node_modules 방어적 제외
- `api-ventago/src/app/watch/watch-module-boot.spec.ts` - (신규) 실제 모듈 Nest DI 컴파일 부팅 검사
- `api-ventago/src/app/watch/watch-token.guard.ts` - [CODEX P1] fail-closed 사후 확인에 `ctx.storeId === device.storeId` 명시 검사 추가
- `api-ventago/src/app/watch/watch-token.guard.spec.ts` - storeId 불일치 → 403 시험 추가
- `api-ventago/src/app/watch/resumen/watch-resumen.service.ts` - D-15⑤ `loadStoreContext()` 가 `is_active` 읽어 전달
- `api-ventago/src/app/watch/resumen/watch-resumen.service.spec.ts` - D-15⑤ 시험 3건 추가
- `api-ventago/src/app/watch/resumen/build-secciones.ts` - D-15⑤ `branchesParaSelector` 필터(선택기만 좁힘)
- `api-ventago/src/app/watch/resumen/build-secciones.spec.ts` - D-15⑤ 시험 4건 추가
- `api-ventago/src/app/watch/resumen/sources/ingresos.source.ts` - [CODEX P2] eventos 를 모델별 순수량(modelo_net) 기준으로 재구성
- `api-ventago/src/app/watch/resumen/sources/watch-sources-a.itest.ts` - ayerMismaHora 타임존 경계(돌연변이 생존 방지) 시험 추가
- `api-ventago/src/app/watch/resumen/sources/watch-sources-b.itest.ts` - ingresos eventos 순수량(같은날 취소) 회귀 방지 단언 추가
- `api-ventago/scripts/watch-resumen-spotcheck.sql` - (신규) 독립 SQL 지점별+TOTAL 전 지표
- `api-ventago/src/app/watch/resumen/watch-resumen-reconcile.itest.ts` - (신규) 3자 대조 itest(84 assertions)
- `api-ventago/scripts/mutantes-watch.sh` - (신규) mutantes-wp.sh 형식 그대로
- `api-ventago/test/mutantes/watch.json` - (신규) 돌연변이 38개
- `.team/reviews/manual-98-10-api.md` - (신규, root) CODEX 수동 자문 기록 2회

## Decisions Made

- D-15⑤·fixture 날짜 분리·CODEX P1 검증 결과·CODEX P2 이월 2건·EXPLAIN 측정 대상 보강 — 전부 key-decisions 참조

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] watch-guard-scope.spec.ts 의 SRC_ROOT 가 `../../..`(3단계)로 api-ventago/ 까지 올라가 `npm run build` 후 `dist/*.d.ts` 까지 훑던 결함**
- **Found during:** Task 1, `npm run build` 뒤 재검증(jest) 에서 발견(dist 가 없을 땐 숨어 있던 결함)
- **Issue:** 주석은 "api-ventago/src" 라고 적혀 있으나 실제 계산은 한 단계 더 올라가 `api-ventago/` 루트가 됐고, 이 플랜의 verify 순서(jest → build)와 달리 내가 jest → build → jest 순으로 재검증하자 `dist/app/watch/watch-token.guard.d.ts` 가 "WatchTokenGuard" 를 참조하는 파일로 잡혀 정적 스캔 기대 집합이 깨졌다
- **Fix:** `../../..` → `../..`(2단계, 실제로 `src/`)로 교정 + `dist`/`node_modules`/`.git` 디렉터리를 방어적으로 건너뛰게 추가
- **Files modified:** `api-ventago/src/app/watch/watch-guard-scope.spec.ts`
- **Verification:** `dist/` 가 있는 상태에서도 `src/app/watch` 전체 jest 177/177 통과 확인
- **Committed in:** `3d9aee7a`

**2. [Rule 1 - Bug] CODEX P1 — TenantContext 재판정 사후 확인이 storeId 일치를 명시로 안 봄**
- **Found during:** Task 3, CODEX 자문 1회차
- **Issue:** `ctx?.resolved && typeof ctx.storeId === 'number'` 만 확인하고 `ctx.storeId === device.storeId` 는 검사하지 않음. **검증 결과**: `TenantContext.resolve()` 는 컨텍스트가 있으면 항상 동기적으로 덮어쓰므로(이미 다른 매장으로 확정됐어도 "무시"하는 분기가 없음) 현재 구현에서는 재현되지 않는다 — 그래도 구현이 바뀌어도 조용히 안 깨지도록 방어적으로 추가
- **Fix:** `ctx.storeId !== device.storeId` 조건 추가(403)
- **Files modified:** `api-ventago/src/app/watch/watch-token.guard.ts`, `watch-token.guard.spec.ts`
- **Verification:** 신규 시험(storeId 9 vs device 6 → 403) 통과, CODEX 2차 자문에서 "수정됨" 확인
- **Committed in:** `db358b3e`

**3. [Rule 1 - Bug] CODEX P2 — ingresos eventos 가 같은 날 수령+취소(순량 0)로도 모델을 센다**
- **Found during:** Task 3, CODEX 자문 1회차
- **Issue:** `COUNT(DISTINCT ...) FILTER (WHERE ... AND s.stock > 0)` 가 행 단위라, 같은 날 `+20`(수령)과 `-20`(취소)이 있으면 원본 수령 행(`stock>0`) 때문에 eventos=1 로 남는다(prendas 는 올바르게 0)
- **Fix:** `modelo_net` CTE 로 모델별 그날 순수량을 먼저 합산하고, 순수량이 양수인 모델만 eventos 로 센다
- **Files modified:** `api-ventago/src/app/watch/resumen/sources/ingresos.source.ts`, `watch-sources-b.itest.ts`(회귀 방지 단언 추가)
- **Verification:** 기존 16개 itest 전부 통과(신규 단언 포함), 유닛 4건 통과, CODEX 2차 자문에서 "수정됨" 확인
- **Committed in:** `db358b3e`

---

**Total deviations:** 3 auto-fixed (1 blocking/pre-existing test fragility, 2 CODEX P1/P2 bugs)
**Impact on plan:** 셋 다 계획이 요구한 검증(정적 스캔·CODEX 자문 반영)을 실제로 충족시키기 위한 수정이다. 범위 확장 없음.

### Deferred (CODEX P2, 이유와 함께 이월)

- **favor_auto 재배분이 대응 Crédito 금액을 확인하지 않아 이론상 credito<0 가능** — `pagos.source.ts`. 이 불변식(결제 시점 credito 전액 기록 ↔ 이후 favor_apply 로 상계)은 **쓰기 경로**(sales-create.service.ts 4285-4337행)가 지켜야 하는 것이고, 이 리포팅 레이어가 clamp 하면 실제 데이터 불일치를 숨기게 된다. 범위 밖으로 판단해 이월.
- **ingresos "수동 매입" 판정이 `type IS NULL` 전체를 허용하고 `legacy_opening` 만 제외 — 다른 시스템이 같은 패턴으로 쓰면 섞일 수 있음** — 현재 재현되는 사고가 아니라 가상의 미래 위험이고, "허용 source 화이트리스트" 로 바꾸려면 그 집합을 제품 결정으로 정해야 한다. 범위를 넓히지 않고 이월.

## Issues Encountered

- `watch-resumen-reconcile.itest.ts` 초안에서 전표(facturacion) 용 판매를 "오늘" 날짜로 둬서 ventas/pagos 총계가 그 판매들까지 세어 15490(기대 3850) 으로 깨졌다 — 전표가 가리키는 판매의 날짜는 facturacion 집계와 무관(voucher 자체의 `created_at`/`cbte_fch` 만 본다)하다는 점을 놓쳤다. 전표용 판매의 `sale_date` 를 ventas/pagos 의 거친 범위(±2일) 밖(2020년)으로 옮겨 해결(key-decisions 참조).
- `afip_vouchers.cae` 가 `varchar(20)` 인데 처음 만든 CAE 문자열(`ITEST-CAE-RECONCILE-${storeId}-${n}`)이 20자를 넘어 FK insert 가 실패했다 — 짧은 접두어(`ITEST-R-`)로 교체.
- Nest `TestingModule` 로 실제 `watch.module.ts` 를 컴파일하려다 `CashRegisterController` 의 `@FunctionGuard` → `FunctionPermissionGuard` → `FunctionPermissionService`(권한 모델 7개 @InjectModel) 체인을 만났다 — 실제 `MemoryCacheModule`(@Global) 을 가져오고 `FunctionPermissionService`/`FunctionPermissionGuard` 를 각각 `useValue`/`overrideGuard` 로 치환해 DB 없이 해결.
- 운영 EXPLAIN 대상(store 26, 최근 14일 판매 최다)이 실제로는 2017-2018년 레거시 이관 더미였다 — "오늘"(2026-10-04) 에 그 매장 데이터가 0건이라 측정이 공허했다. 문자 그대로 "오늘" 로도 측정하고, 추가로 그 매장의 역대 최다 하루(2017-10-10)로도 재측정해 실제 부하 하에서 예산 안임을 확인했다(아래 표 둘 다 기록).

## User Setup Required

None - 외부 서비스 설정 필요 없음.

## Next Phase Readiness

- W98-01·W98-02 완료 — `/watch/resumen` 이 운영에서 섹션 6개를 반환하고, 페어링과 함께 배포됨
- 레거시 화면과의 사람 대조(D-08)는 98-13 으로 분리된 그대로 — 이 플랜은 독립 SQL·웹 대조식·돌연변이로 "서비스가 정의대로 계산하는가" 만 닫았다
- 이월 항목(CODEX P2 2건)은 98-13 또는 별도 phase 에서 재검토할 수 있음

## Known Stubs

None - 이 플랜의 코드는 전부 실제 SQL + 실제 DB(itest) + 운영 스모크로 검증됐다. 하드코딩된 빈 값이 화면에 노출되는 경로는 없다.

## Threat Flags

None - 이 플랜이 추가한 표면(모듈 등록으로 실제 라우팅되는 `GET /watch/resumen`)은 계획의 threat_model(T-98-70~T-98-73)에 전부 등록돼 있다. 운영 스모크로 무토큰 401 을 확인했다.

## 운영 EXPLAIN ANALYZE (steady-state, store 26)

| 원천 | "오늘"(2026-10-04, 0행) | 역대 최다 1일(2017-10-10, 163건) |
|---|---|---|
| ventas | 2.6 ms | 3.6 ms |
| pagos | 0.5 ms | 2.2 ms |
| gastos | 2.7 ms (1차 110ms 는 JIT/캐시 warm-up 1회성) | — |
| ingresos | 2.5 ms | — |
| facturacion | 0.2 ms | — |
| cajas(getTesoreriaOverview) | 0.8 ms (1차 planning 260ms 는 1회성) | — |

전부 100ms 예산 안(합계도 300ms 예산에 훨씬 못 미침). store 26 은 "오늘" 실데이터가 0행인 레거시 이관 더미라(Issues Encountered 참조) 최다 1일로도 재측정했다.

## 돌연변이 측정 결과

`bash scripts/mutantes-watch.sh` — **죽음 38 · 생존 0 · 적용안됨 0 · 컴파일오류 0**. D-15① favor 재배분 4종(`payment_id IS NULL`·`parent_ledger_id IS NOT NULL` 포함) · W1(asOf) · W2(정렬키 통일) 전부 포함.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 16 created/modified key files (api-ventago) + `.team/reviews/manual-98-10-api.md`(root) + this SUMMARY verified present via `[ -f ... ]`. All 4 commit hashes (`3d9aee7a`, `69e0d162`, `db358b3e` in api-ventago; `ad55cb1` in root) verified in `git log --oneline --all`. No missing items.
