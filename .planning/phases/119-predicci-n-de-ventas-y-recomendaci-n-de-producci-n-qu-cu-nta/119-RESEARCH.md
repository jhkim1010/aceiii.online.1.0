# Phase 119 — 연구 결과 (2026-10-19)

> 입력: `119-SPEC-BORRADOR.md`(사용자 초안 2026-10-18).
> 방법: 운영 DB(5434) **SELECT 만**으로 실측 + 코드 조사 + 외부 문헌·API 조사 + CODEX 검토(HIGH 3·MEDIUM 3·LOW 1, 전부 반영).
> 조사 쿼리: `consultas/`(전부 SELECT · read-only `run.sh` · 재고 역산 검증 `q13.sql`).

## 0. 한 줄 결론

**판매 이력은 쓸 만하지만, 명세서의 핵심 전제 「Ventago 가 리드타임·원단·생산 데이터를 이미 보유」는 운영 데이터로는 거짓이다**
(실제 매장의 talleres/mes 사용 0건, 원가 사실상 0). 그래서 1차 범위는 「생산 추천」이 아니라
**「판매 근거의 분석 + 기준 예측 + 백테스트」를 파일럿 1곳(Shaple)에서** 여는 것이 현실적이다.

---

## 1. 명세서 미결 질문에 대한 답 (실측)

| 미결 질문 | 답 |
|---|---|
| 판매가 모델·사이즈·색상 단위로 저장되나? | **매장마다 다르다.** Shaple(26) 최근 24개월 수량의 96.9% 가 자식(사이즈) 단위, ohmydenim(28) 83.6%. **Cache(30) 0.1%, NOIX(19) 0%, Charo(25) 자식 없음** — madre 단위로만 팔린다. Shaple 은 색상이 전부 `UNICO` 이고 색 이름이 `sizes` 에 섞여 있다(47종) |
| 품절 이력을 재구성할 수 있나? | `stocks` 원장은 전 매장이 2026-10 `legacy_opening` 으로 시작 → 원장만으론 불가. `legacy_ingresos`(레거시 입고)로 Σ입고 − Σ판매 = 개시재고 가 Shaple 80.6%·Charo 84% 일치(Cache 65%) — **그러나 종점이 맞는다고 일별 경로가 맞는 것은 아니다**(CODEX HIGH: 반품·이동·조정·폐기가 빠져 상쇄될 수 있다). → **기본값은 「판정 불가」**, 일별 표본 검증(예: 레거시 실사·재고 조사일)을 통과한 상품·기간만 품절 판정에 쓴다. **ohmydenim·NOIX 는 입고 이력 0** |
| 속성 값 목록을 표준 제공? 매장 정의? | 지금은 카테고리·시즌이 사실상 비어 있다(General/NONE). 실제로 쓰는 곳은 NOIX(카테고리 12종)뿐. 원단·핏 컬럼 없음, `material`·`gender` 컬럼은 있으나 0건. 모델 정보는 **이름·코드 안에** 있다(Cache 「 - 」 뒤가 원단) |
| 신모델 1차 비율 50–60% 매장별 설정? | 문헌 근거 없음(업계 관행). 이론적으로는 「재생산 전까지 기간의 뉴스벤더 분위수」로 유도 → **매장 설정값 + 백테스트로 조정**이 맞다 |
| 파일럿은? | **Shaple(26)** 이 유일하게 조건 충족(142개월, 월 ~9,700장, 사이즈 단위 96.9%, 입고 이력 2019~, 재고 역산 80.6%). 단 색상 축 오염·원가 0·카테고리 없음·리드타임 없음 |

## 2. 명세서와 어긋나는 점

1. **생산 데이터 없음** — 리드타임(발주→수령), 원단 소요·재고, WIP 를 도출할 매장이 없다(전부 store 6 시험 데이터). → 4.2 원단 롤 반올림, 4.4 원단 발주 마감일은 **입력값이 없다.**
2. **원가 없음** — `products.cost`·`sale_items.unit_cost` 사실상 0 → 마진율·뉴스벤더 Cu/Co 계산 불가.
3. **쇼핑몰 데이터 없음** — 온라인 판매 10건(store 6).
4. **판매의 99.6% 가 레거시**(`source='legacy'`, 2014~2026-10, 아직 동기화 중). 레거시와 POS 가 같은 날 겹치는 매장이 있다 → **중복 계상 확인 필요**(`venta-universe.ts` 는 출처 구분 없이 합산).
5. **출시일** — `products.created_at` 은 임포트 날짜. 첫 입고일(legacy_ingresos) 또는 첫 판매일로 대체.
6. **판매율 분모** — 생산 테이블이 아니라 `legacy_ingresos` 입고량. 레거시 종료 후엔 POS 입고(stocks ingreso)로 이어야 한다. 단 입고가 생산인지 구매인지 구분 필드가 없다.
7. **스키마** — `tenant_id`→`store_id`, `variant_id`→`products` 자식 `id`(또는 madre 없는 단독 상품). **`product_variants` 테이블이 실제로 존재(0행)** → 명세서 이름과 충돌, 쓰지 않는다.
8. **Python 배치** — 앱 스택에 Python 없음. 운영 호스트는 RAM 32GB 중 가용 15.5GB, **swap 0**, Jenkins·ollama·coolify 동거 → Prophet/LightGBM 상주 부적합.

## 3. 외부 연구 요약

- **방법:** Prophet 은 기본값으로 부적합(ETS 대비 M3 에서 16–44% 나쁨, 느림). 월 단위 카테고리·모델은 **AutoETS / Theta / Seasonal Naive**, 간헐 수요는 **TSB/SBA**, 사이즈·색상은 **하향식 커브**(사이즈별 개별 예측 금지). LightGBM 글로벌 모델은 시계열 수만 개 규모에서 이점 → 2단계 후보.
- **지표:** MAPE 금지(판매 0 기간 폭주). 사용자용 **WAPE = Σ|오차| / Σ|실제|**, 방향 **Bias = Σ오차 / Σ실제**, 모델 비교 **MASE/RMSSE**. 평가 계층(카테고리·모델·사이즈)별로 따로, rolling-origin 으로 집계 — 대량 상품이 소량 상품의 실패를 가리지 않게. SKU 단위는 MAE 가 「항상 0」 을 최적으로 만들어 bias 와 함께 본다.
- **라이브러리:** 필요해지면 Python **statsforecast** 하나(Croston/SBA/TSB/AutoETS/Theta). Node 쪽엔 쓸 만한 것이 없다.
- **수량:** 단일 기간 **뉴스벤더**, CR = Cu/(Cu+Co). 정규 근사 μ + z(CR)·σ 는 간헐·비대칭 의류 수요에 부적합할 수 있어(CODEX) **백테스트 예측오차의 경험분포에서 CR 분위수를 직접** 구한다. 분위수가 곧 안전재고이므로 **안전재고를 따로 더하지 않는다**(이중 반영). 원가가 없어 CR 은 매장 설정값 — 기본값은 D2 시뮬레이션으로 정한다(0.5–0.6 은 근거 없는 출발점). 리드타임+검토기간 수요·입고 예정·WIP 를 같은 기준 시점으로. MOQ·롤은 올림 vs 내림 기대비용 비교.
- **콜드스타트:** 속성 유사 k=3–5 모델의 첫 8주 곡선 평균(k-NN analog) — 학계·실무 표준(Singh 2019, Ferreira 2016, Fisher-Raman 1996). 7/14일차 속도비 r 로 재예측(축소 적용 0.5·r+0.5). 1.3/0.6 임계는 백테스트로 조정.
- **품절 보정:** 데이터가 적으면 단순 규칙 — 재고 0 일자 제외/대체, 사이즈 품절은 커브로 역산. EM 은 과함.
- **외부 데이터:**
  - Open-Meteo **무료 등급은 비상업 전용** → SaaS 기능엔 유료 계약 필요(라이선스 CC BY 4.0). 계절예보 SEAS5 7개월 제공.
  - SMN 공식 API 없음.
  - INDEC IPC: `apis.datos.gob.ar/series/api/series/?ids=148.3_INIVELNAL_DICI_M_26`(전국)·`148.3_INIVELGBA_DICI_M_21`(GBA) — 직접 호출해 2026-08 값까지 확인. 다음 달 중순 공표. **수량으로 예측하면 디플레이트 불필요.**
  - 월 단위 기온 효과는 대부분 상쇄 → **회귀변수 말고 시나리오 폭에만.**
- **행사 달력:** Hot Sale(5월 중순 월–수: 2024 5/13–15, 2025 5/12–14, 2026 5/11–13), CyberMonday(11월 초, 2025 11/3–5), Día del Niño(2025년부터 8월 셋째 일요일, Decreto 562/2025), Día de la Madre(10월 셋째 일요일), 아기날도(6/30·12/18 + 영업일 4일), Navidad/Reyes. 미확인 날짜는 상수로 넣지 않는다.
- **경쟁:** Prediko·Inventory Planner·Katana·Odoo 모두 「점 예측 + 커버일수 + 재주문」. **신모델 유사모델 콜드스타트·7/14일 재생산 판정·속성 조합 성과**를 내세우는 곳은 없다 → 차별점.

## 4. 재사용할 수 있는 것 (코드)

- 판매 정의 단일 원천: `api-ventago/src/app/reports/venta-universe.ts` (활동 유형·취소 부호·매장 현지 날짜).
- `reporte-medida/compiler.ts` D-30(카테고리·시즌 = COALESCE(자식, madre), NONE/General = 값 없음), `size-order.ts`(사이즈 순서).
- 원형: `reportsSeasonTurnover`(시즌 회전율), `reportsCategoryColorPivot`(카테고리×색상).
- 야간 작업: `common/cron/cron-leader.ts` + `CronLeaseService`(비리더는 cron 전부 삭제). 3시대 혼잡(3:00 manual-sync·mp-reconcile, 3:30 drift, 3:45 credit) → 다른 시각.
- 알림: 매장 사용자용 알림 테이블 없음 → 재생산 알림은 **파생 큐**(읽음 상태 없음, `reportsAlertas` 패턴).
- Phase 114 Power BI 는 미착수.

## 5. 실제 스키마로 옮긴 테이블

| 명세서 | 실제 |
|---|---|
| `product_attributes` | `(store_id, product_id = madre 또는 단독)`. 카테고리·시즌은 **기존 `products.category_id`/`season_id` 재사용**, 새로 필요한 것은 `fabric`/`fit`/`price_band`(가격은 `price` 에서 파생 가능), `launch_date` = 첫 입고일 백필 |
| `daily_sales_agg` | `(store_id, branch_id, product_id = 자식 또는 단독, day_local)`, `sales.branch_id` 권위, venta-universe 위의 MV 또는 야간 테이블. `stockout` 은 3값(재고 있음/없음/판정 불가) |
| `attribute_performance` | `(store_id, season_id, attr_key)`, 모델 수백 규모 → MV 로 충분. `margin_rate` NULL 허용 + 원가 커버리지 표시 |
| `production_recommendations` | `variant_id`→자식 `product_id`, `store_id`, `branch_id` NULL 허용(생산이 지점 공통인지 확인) |
| `forecast_runs` | 신규, `store_id` |

## 6. 권고 단계 (명세서 10장 대체안)

| 단계 | 내용 | 완료 기준 |
|---|---|---|
| **A. 데이터 위생** (선행) | ① 레거시·POS 중복 구간 매장별 확인 ② NOIX·Cache 의 product_id NULL 실상품 재매핑 ③ Shaple 색상(sizes 에 섞임) 분리 ④ 출시일 = 첫 입고일 백필 ⑤ 카테고리·시즌 입력(또는 이름 파싱 제안) | Shaple 기준 판매 귀속률·속성 채움률 수치로 보고 |
| **B. 일별 집계 + 품절 3값** | `daily_sales_agg`(야간 증분) + legacy_ingresos 역산 재고 → 품절일(기본 「판정 불가」) | Shaple 2년 백필 + **일별 표본 검증**(종점 일치율만으론 완료가 아니다) |
| **C. 분석 화면 (예측 없이)** | 사이즈 커브, 첫 4주 판매 속도, 판매율(÷입고), 잔여율, 카테고리/속성 조합 — 모델 3개 미만 「참고」 | 파일럿이 실제로 사용 |
| **D. 기준 예측 + 백테스트** | Seasonal Naive / 전년 동월×최근 추세 (SQL+Nest) → 6개월 hold-out WAPE·Bias | 수치 보고. 이걸 이겨야 다음 모델 |
| **D2. 재고정책 시뮬레이션** (CODEX) | 예측이 좋다고 추천이 좋은 것은 아니다 — rolling-origin 으로 「추천대로 만들었다면」 품절률·잔여재고·비용을 재고 CR·MOQ 정책을 보정 | 시뮬레이션 수치로 CR 기본값 결정 |
| **E. 생산 수량 추천** | 뉴스벤더 − 보유 − WIP(**수동 입력**) → 사이즈 커브 분배, MOQ 는 올림/내림 **기대손실 비교**. 리드타임 **매장 설정값** | 근거(시나리오·참고 모델) 함께 표시 |
| **F. 신모델·재생산** | k-NN analog(속성 필요), 7/14일 속도비 파생 큐 | 파일럿 시즌 1회 |
| **G. 선택** | statsforecast 배치(**운영 서버 말고** 운용3/srv2), 기온 시나리오(Open-Meteo 유료 시), 외부 쇼핑몰 | 백테스트 개선 확인 시에만 |

## 6-1. 데이터 계약·격리·부하 (CODEX HIGH/MEDIUM 반영)

- **판매 정의를 그대로 쓰지 않는다.** `venta-universe.ts` 는 legacy·POS 중복을 **의도적으로 합산**하고(중복은 모니터링만), 수량 취소 부호는 `itemsAggCte({ firmado: true })` 일 때만 붙는다. 예측 집계는 ① 매장별 중복 판정 정책(레거시 종료일 이후 legacy 제외 등)을 먼저 정하고 ② **signed 수량**만 쓰고 ③ 반품(`devuelto`, 판매 우주 밖)을 순판매에서 뺄지 따로 둘지 데이터 계약으로 정한다.
- **지점 차원:** `daily_sales_agg` 는 지점별이면 PK 에 `branch_id` 포함, 전점 합산이면 `branch_id` 를 두지 않는다 — 둘 중 하나로 고정. 추천의 `branch_id NULL` 은 「전점 공통」 으로 명시하고 별도 유일성 규칙.
- **매장 무결성:** `store_id` 와 `product_id`/`branch_id`/`run_id` 의 단일 FK 로는 **다른 매장 id 참조를 못 막는다.** 복합 FK(`(store_id, id)`) 또는 쓰기 시 소유권 검증을 모든 파생 테이블에. 화면 조회는 보고서 관문(`resolveScopedStoreId`, 매장 없으면 400)과 같은 규칙.
- **운영 DB 부하:** 커넥션 하나로 전 매장을 오래 잡지 않는다. `store_id + 날짜` 증분 워터마크, 제한된 청크, 청크별 짧은 트랜잭션, `statement_timeout`/`lock_timeout`, 재시도·멱등, 동시 실행 lease, 부하 상한과 중단 기준. MV 전체 갱신은 피한다. 3시대 혼잡 회피는 필요조건일 뿐.

## 7. 사용자 결정이 필요한 것

1. **파일럿 = Shaple(26)** 로 할지, 그 매장 동의.
2. 생산 데이터가 없으니 **리드타임·WIP·MOQ·CR 을 매장 설정/수동 입력**으로 받을지 — 아니면 talleres 모듈 사용을 먼저 정착시킬지.
3. **상품 등록 시 속성 필수**(카테고리·원단·핏·가격대) — POS 전체 상품 등록 화면이 바뀐다.
4. 기온: Open-Meteo **유료** 계약 vs 기온 제외.
5. Python 이 필요해질 때 실행 위치(운용3/srv2).

## 8. 외부 근거 (출처)

- M5: https://ideas.repec.org/a/eee/intfor/v38y2022i4p1346-1364.html · 자동예측 벤치마크(Prophet 시간초과): https://arxiv.org/pdf/2407.16445 — Prophet 열위 수치(M3, ETS 대비 16–44%)는 2차 인용이라 **「확인 필요」**
- 간헐 수요 지표: https://ideas.repec.org/a/eee/intfor/v22y2006i4p679-688.html · https://arxiv.org/pdf/2204.08283 · 「0 예측」 문제 https://arxiv.org/pdf/2103.13812
- statsforecast: https://nixtlaverse.nixtla.io/statsforecast/index.html
- 뉴스벤더·Quick Response: Fisher & Raman 1996 https://ideas.repec.org/a/inm/oropre/v44y1996i1p87-99.html
- 신상품: Singh 2019 https://arxiv.org/pdf/1907.01960 · Ferreira 2016 https://ideas.repec.org/a/inm/ormsom/v18y2016i1p69-88.html · Caro & Gallien 2010 https://ideas.repec.org/a/inm/oropre/v58y2010i2p257-273.html — 「표준」 은 후보 방법으로 읽을 것
- 품절 보정: https://pubsonline.informs.org/doi/fpi/10.1287/mksc.17.4.406
- Open-Meteo 약관·요금: https://open-meteo.com/en/terms · https://open-meteo.com/en/pricing · 계절예보 https://open-meteo.com/en/docs/seasonal-forecast-api
- IPC: https://apis.datos.gob.ar/series/api/series/?ids=148.3_INIVELNAL_DICI_M_26 (2026-10-19 직접 호출 확인)
- 기상 효과: Steinker 2017 https://kups.ub.uni-koeln.de/21594/ · SF Fed 2022 https://www.frbsf.org/research-and-insights/publications/economic-letter/2022/08/impact-of-weather-on-retail-sales/
- 경쟁: Prediko https://www.prediko.io/blog/demand-forecasting-software · Inventory Planner https://www.inventory-planner.com/size-curve-forecasting/ · Katana https://support.katanamrp.com/en/articles/8937030-basics-of-planning-and-forecasting — 「동일 기능이 없다」 는 공개 자료 기준 관찰

## 9. 위험

- 레거시 동기화가 진행 중 → 전환 구간 이중 계상.
- ohmydenim·NOIX 입고 이력 0 이 원본 부재인지 임포트 누락인지 미확인.
- Shaple 2025–26 「신규 모델」 상당수가 코드 재부여일 수 있다(콜드스타트 학습을 오염).
- NOIX 2025년 판매 줄 71%·Cache 실상품 줄이 product_id NULL → 재매핑 없이는 수요 과소.
- 운영 `pg_stat` 통계 미수집 → 대량 집계는 실측으로 설계.
- 「검증된 예측」 이라는 표현은 D 단계 백테스트 수치 전에는 쓰지 않는다(명세서 9장과 동일).
