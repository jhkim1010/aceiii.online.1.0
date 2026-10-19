# Phase 119: Predicción de ventas y recomendación de producción — Context

**Gathered:** 2026-10-19
**Status:** Ready for planning
**Source:** plan-phase 즉석 결정(사용자 답변 4건) + `119-RESEARCH.md` + `119-SPEC-BORRADOR.md`

<domain>
## Phase Boundary

이번 phase 는 연구 §6 의 **A~D2 단계만** 한다 — 「판매 근거 분석 + 기준 예측 + 백테스트 + 재고정책 시뮬레이션」.
**생산 수량 추천(E), 신모델 콜드스타트·재생산 알림(F), 외부 변수·Python 배치(G)는 이번 범위가 아니다.**

개발·시험 대상은 **store 6(coolsistema) 합성 데이터만**이다(`datos-sinteticos/`, `SINTÉTICO 119`).
실매장 파일럿(Shaple 26 등)은 이번에 하지 않는다 → **예측 정확도 결론은 내지 않는다.**
백테스트는 「하네스가 돈다 + 수치를 낸다」까지이며, 화면·문서 어디에도 「검증된 예측」이라 쓰지 않는다.
</domain>

<decisions>
## Implementation Decisions

### D-01 범위
- A(데이터 계약) → B(일별 집계 + 품절 3값) → C(분석 화면, 예측 없음) → D(기준 예측 + 백테스트) → D2(재고정책 시뮬레이션).
- E·F·G 는 Deferred.

### D-02 파일럿 = store 6 합성만
- 모든 산출물은 매장 무관하게 동작해야 한다(`store_id` 파라미터). 단 실행·검증은 store 6.
- 합성 판매 기간은 2025-11-15 ~ 2026-10-18(약 11개월) — **12개월 미만이라 계절 naive 는 성립하지 않는다.**
  백테스트는 계절 모델이 데이터 부족이면 「이력 부족」으로 표시하고 비계절 기준(naive·이동평균·최근 추세)으로 비교한다. 합성 이력을 늘리는 것은 하지 않는다(필요하면 사용자에게 제안만).
- 백테스트 결과 문구: 「합성 데이터 — 하네스 검증용, 정확도 근거 아님」 명시.

### D-03 생산 데이터 = talleres 모듈 + 매장 설정 폴백
- 리드타임·WIP(진행 중 로트)·입고(생산 수령)는 **기존 talleres/생산 테이블에서 도출**(store 6 합성 로트 34·수령·원단 이동이 있다).
- 도출 불가 시 매장 설정값(리드타임 일수, MOQ, CR)으로 폴백. 설정값 저장 위치는 Claude 재량(기존 `store_configs` 패턴 우선).
- 이번 범위에서 리드타임·WIP 는 **D2 시뮬레이션 입력**과 C 분석(판매율 분모 = 생산 입고)에 쓰인다. 추천 수량 산출은 E(다음 phase).

### D-04 데이터 계약 (A — CODEX HIGH 반영, 연구 §6-1)
- 판매 정의는 `api-ventago/src/app/reports/venta-universe.ts` 를 기반으로 하되 그대로 합산하지 않는다:
  ① 매장별 legacy·POS 중복 정책(레거시 종료일 이후 legacy 제외 등)을 코드로 명시 ② **signed 수량**(`itemsAggCte({ firmado: true })`) ③ 반품(`devuelto`)은 순판매와 분리 컬럼.
- 단위 = 자식 상품 `product_id`(madre 없는 단독 상품은 그 자신). `product_variants` 테이블(0행)은 쓰지 않는다.
- 날짜 = 매장 현지 날짜(DB 는 UTC).
- 지점 차원: 일별 집계는 `branch_id` 포함 PK 로 고정(`sales.branch_id` 권위).
- 출시일 = 첫 입고일(생산 수령/legacy_ingresos) → 없으면 첫 판매일.
- Shaple/NOIX/Cache 고유 위생 작업(색상 분리·NULL 재매핑)은 Deferred.

### D-05 품절 3값 (B)
- `stockout` 은 `con_stock | sin_stock | indeterminado`. 기본값 **indeterminado**.
- store 6 합성은 `stocks` 원장(+`stock_balances`)이 일별로 일관되므로 원장 기반 일말 재고로 판정 가능. 원장이 `legacy_opening` 으로 시작하는 매장은 개시 이전 구간을 indeterminado 로.
- 재고 읽기는 `stocks`/`stock_balances`/뷰만 — `products.stock` 금지, `product_id` 컬럼 없음(`product_branch_id` 기준).

### D-06 저장 구조
- 신규 테이블만 추가, 기존 테이블 변경 없음. 연구 §5 매핑 표를 따른다:
  `product_attributes(store_id, product_id=madre/단독, fabric, fit, price_band, launch_date …)` — 카테고리·시즌은 기존 `products.category_id/season_id` 재사용.
  `daily_sales_agg(store_id, branch_id, product_id, day_local, qty, qty_devuelto, revenue, stockout …)`.
  `forecast_runs`, 백테스트 결과·시뮬레이션 결과 테이블(이름 Claude 재량).
- `attribute_performance` 는 MV 또는 조회 시 계산(모델 수백 규모) — Claude 재량.
- 매장 무결성: 파생 테이블은 복합 FK `(store_id, id)` 또는 쓰기 시 소유권 검증. 조회는 보고서 관문(`resolveScopedStoreId`, 매장 없으면 400).

### D-07 속성 입력
- 원단·핏·가격대 속성은 **선택 입력**(필수 강제 안 함 — 전 매장 상품 등록 화면을 바꾸지 않는다).
- store 6 합성 10개 모델에는 속성을 채운다(합성 데이터로 표시).
- 표본 3개 모델 미만 조합은 「참고」 표시, 실패 조합을 성공 조합과 같은 비중으로 노출.

### D-08 배치·부하
- Python 없음. 집계·기준 예측·백테스트·시뮬레이션은 **SQL + NestJS** 로.
- 야간 증분: `store_id + 날짜` 워터마크, 청크별 짧은 트랜잭션, `statement_timeout`/`lock_timeout`, 멱등·재실행 가능, `cron-leader`/`CronLeaseService` 리더 전용(비리더 cron 삭제 함정), 시각은 03:00~03:45 혼잡대를 피한다.
- 화면은 계산하지 않고 집계·결과 테이블만 읽는다.

### D-09 지표
- MAPE 금지. 사용자용 **WAPE**, 방향 **Bias**, 모델 비교 **MASE**. 계층(카테고리·모델·사이즈)별, rolling-origin.

### D-10 D2 재고정책 시뮬레이션
- 「추천대로 만들었다면」 품절률·잔여재고를 rolling-origin 으로 재현, CR(임계비율)·MOQ 정책별 비교. 분위수는 백테스트 오차의 **경험분포**에서(정규 근사 금지), 안전재고를 따로 더하지 않는다.
- 출력은 수치 보고 + CR 기본값 후보. 사용자에게 추천 수량을 보여주는 화면은 E.

### D-11 UI compacta (directiva del usuario 2026-10-19: 「나는 공간 낭비를 매우 싫어해.. 최대한 compact」)
- Mismo criterio que se aplicó hoy a Configuración › Facturación: avisos informativos → texto chico en la fila del título (no cajas Alert info);
  input + botón en la misma fila (mitad/mitad); listas de un solo ítem se funden en la fila padre; padding ~py 0.5–1 / px 1.5, separación entre cards 1.5;
  cards lado a lado (flex '1 1 360px') que sólo se apilan en pantallas angostas.
- **Alert sólo para advertencias/errores reales** (severity warning/error). Nada de `severity='info'`.
- Pantallas 119: «SINTÉTICO» = Chip con tooltip que contiene el texto del descargo + fecha de datos en la fila del título (no banner a todo el ancho);
  «no habilitada» / «sin corrida» = texto o chip compacto; selectores + filtro + «Recalcular ahora» en una sola fila; Mejor/Peor lado a lado;
  notas largas bajo tablas → tooltip (ícono info) o una línea de caption.

### Claude's Discretion
- 분석 화면(C)의 메뉴 위치·구성(기존 Reportes/Producción 패턴, `sketch-findings-ace-online` 스킬, 표 밀도 규약 준수).
- 테이블·엔드포인트 이름, MV vs 테이블, 설정값 저장 위치.
- 백테스트 기준 모델 세트(naive·이동평균·최근 추세·계절 naive 가능 시).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 자료
- `.planning/phases/119-…/119-RESEARCH.md` — 실측·문헌·CODEX 반영 권고 (§5 스키마 매핑, §6 단계, §6-1 데이터 계약·부하)
- `.planning/phases/119-…/119-SPEC-BORRADOR.md` — 사용자 원 명세(스키마는 실제와 다름)
- `.planning/phases/119-…/datos-sinteticos/seed-coolsistema-produccion.sql`, `seed-coolsistema-ventas.sql` — store 6 합성 데이터가 어떤 테이블에 어떻게 들어갔는지
- `.planning/phases/119-…/consultas/` — 조사 SQL(읽기 전용)

### 코드
- `api-ventago/src/app/reports/venta-universe.ts` — 판매 정의 단일 원천
- `api-ventago/src/app/reports/reporte-medida/compiler.ts`, `size-order.ts` — 카테고리·시즌 COALESCE, 사이즈 순서
- `api-ventago/src/common/cron/cron-leader.ts` + `CronLeaseService` — 야간 작업
- `reportsSeasonTurnover`, `reportsCategoryColorPivot`, `reportsAlertas` — 원형

### 스키마·규약
- `.planning/intel/db-schema-tables.md`, `db-schema-fks.md` (낡을 수 있음 — 타입이 근거면 DB 직접 확인)
- `CLAUDE.md` — 무중단 마이그레이션 규약(CONCURRENTLY·lock_timeout·NOT VALID·`migration-conventions.spec.ts`), 로컬+운영 동시 적용, 낮 08–16시 운영 반영 금지(활동 사용자 ≤10 예외), 쓰기 경로 규약, ESLint 규칙
</canonical_refs>

<specifics>
## Specific Ideas
- store 6 합성: 모델 10(123·264·140·147·245·183·79·227·240·222), 로트 34(WIP 4), Depósito Central(25), 판매 2,020건, 판매율 32–85% — C 화면·D2 시뮬레이션의 시험 기대값으로 사용.
- 행사 달력은 연구 §3 의 확인된 날짜만 상수로(미확인 날짜 금지).
</specifics>

<deferred>
## Deferred Ideas
- E 생산 수량 추천(뉴스벤더·사이즈 커브·MOQ 기대손실) — 다음 phase
- F 신모델 k-NN 콜드스타트, 7/14일 재생산·부진 파생 큐
- G statsforecast(Python, 운용3/srv2), Open-Meteo 유료 기온 시나리오, IPC, 외부 쇼핑몰 신호
- 실매장 파일럿(Shaple 26) 및 고유 데이터 위생(색상 분리·product_id NULL 재매핑·legacy 중복 구간 판정)
- 상품 등록 시 속성 필수화
- 합성 판매 이력 12개월 이상으로 확장(필요 시 사용자에게 제안)
</deferred>

---

*Phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta*
*Context gathered: 2026-10-19 via plan-phase inline decisions*
