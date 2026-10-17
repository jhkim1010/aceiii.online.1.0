# Phase 117 — Reportaje abierto: 외부 조사 (2026-10-17)

> 범위: 의류 소매 점주·매니저가 실제로 보는 보고서/KPI, 경쟁 제품의 사용자 정의 보고서 기능,
> 아르헨티나 인플레이션 하에서 매출 읽는 법, 실제 질문 문구, 그리고 (추가 범위) Gastos·Facturación 보고서.
> 원칙: **출처가 말한 것만** 적는다. 출처에서 확인 못 한 것은 `[불확실]` 또는 `[내 판단]` 으로 표시.
> 웹 검색 결과 중 일부 기사(iProfesional 등)는 페이지 날짜와 본문 날짜가 어긋났다 — 수치 인용은 피했다.

---

## 요약 (핵심 10줄)

1. 의류 소매의 표준 KPI 는 **sell-through, weeks of supply, GMROI, markdown rate, AUR, 반품률**이며, 출처들은 공통적으로 **스타일·색·사이즈·주(週) 단위로 쪼개 보라**고 한다 — 전체 평균은 사이즈별 품절/과잉을 숨긴다(SPS Commerce, Increff).
2. 그중 **POS 판매 데이터만으로 되는 것**: 판매액·수량·티켓 수·ATV(ticket promedio)·UPT·반품률·결제수단 믹스·판매원/지점 비교·색/사이즈 판매 분포. **재고가 필요한 것**: sell-through, weeks of supply, 재고 연령(aged inventory), 품절 사이즈. **원가가 필요한 것**: 마진, GMROI. **방문자 수가 필요한 것**: conversion — Ventago 에는 없다.
3. Shopify 의 탐색(exploration)은 우리 설계와 거의 같은 골격이다: **지표(≥1) + 차원(여러 개, 순서가 중첩을 결정) + 필터(기본 최근 30일) + 비교(직전 기간 / 전년 동기 / 목표) + Top N + 저장**(Shopify 공식 도움말).
4. Lightspeed X-Series 는 고급 플랜에서 **비교 기간·저장 보고서·예약 발송**을 제공하고, 보고서 축으로 Outlet·User(판매원)·Product·SKU·Brand·Supplier·Category·Tag·**Variant Attribute**·Payment 를 둔다. Odoo 는 Group By(사용자·직원·POS·상품·카테고리·주문일) + Measures + Favorites 저장.
5. 아르헨티나 경쟁 제품(Dux·Tango·Contabilium)의 **색/사이즈 축 판매 보고서는 확인되지 않았다**. Dux 도움말은 판매 상세 보고서의 talle/color 필터가 "por el momento" 비활성이라고 적는다 — 의류 매장에 **차별점이 될 수 있는 빈칸**이다 `[불확실: 최신 상태 미확인]`.
6. 인플레이션: CAME(소매 pyme 지수)는 매출을 **"a precios constantes"(실질)**로만 발표하고, 의류는 과거 **수량(cantidades) 기준 감소율**도 따로 냈다. 즉 업계 표준 읽기는 **명목 대신 실질 또는 수량**.
7. 실질화 방법은 "명목 ÷ 물가지수"(CEPAL/INDEC 계열 설명). 다만 IPC 는 소비자 바스켓이라 업종 가격과 다를 수 있다는 주의가 있다. **USD 기준 비교를 권하는 출처는 찾지 못했다**.
8. → Reportaje abierto 의 비교 기능에서 **pesos 증감만 보여 주면 오독**된다. 최소한 **unidades·tickets 를 같이** 보여 주고, IPC 보정은 선택(2단계) — 매장 자체 가격 변화(AUR 증감)를 함께 보여 주는 편이 IPC 보다 매장 실정에 가깝다 `[내 판단]`.
9. Gastos·Facturación 은 **판매 행과 섞을 수 없는 별도 원장**이다: 비용은 `expenses`, 전자세금계산서는 comprobante(punto de venta·tipo·IVA) 단위. 회계사가 매달 원하는 것은 **Libro IVA Ventas(전자 Libro IVA Digital)**, 모노트리부토는 **최근 12개월 누적 발행액 vs 카테고리 한도**(재분류 연 2회: 1월·7월).
10. 템플릿 Top 우선순위: ①이번 주 베스트셀러(수량) ②지점 비교 ③판매원별 매출 ④결제수단별 입금 ⑤사이즈 커브(talle 분포) ⑥색 성과 ⑦전년 동기 대비(수량 병기) ⑧시즌별 판매 ⑨반품 ⑩요일/시간대. 갭: sell-through·품절 사이즈·재고 커버·재고 연령(재고 데이터 필요), 마진/GMROI(원가 필요).

---

## 1) 주기별 보고서 목록

범례 — **1단계 가능?**: ✅ 지표·차원 조합으로 표현됨 / ⚠️ 부분적(근사) / ❌ 재고·원가·트래픽 등 1단계 카탈로그 밖 데이터 필요.

| 보고서 | 누가 | 주기 | 필요한 데이터 | Reportaje abierto 1단계로 가능? (표현) | 근거 URL |
|---|---|---|---|---|---|
| 일 매출 요약 (venta neta, tickets, ticket promedio) | 점주·지점장 | 일 | POS 판매 | ✅ 지표 venta neta+tickets+ticket promedio / 차원 día (·sucursal) | Square 비교 기능: https://squareup.com/help/gb/article/5618 |
| 지점(sucursal) 비교 | 점주 | 일·주·월 | POS 판매 | ✅ 차원 sucursal, 비교=직전기간 | Lightspeed "Outlet" 보고서: https://product-info.lightspeedhq.com/lightspeed-retail-x-series-reporting-comparison-global · Shopify "Retail sales by POS location": https://help.shopify.com/manual/reports-and-analytics/shopify-reports/report-types/retail-sales-reports |
| 베스트셀러 / 워스트셀러 (상품) | 점주·구매담당 | 주 | POS 판매 | ✅ 지표 unidades / 차원 producto / Top N (오름차순이면 워스트) | Tiendanube "Productos" (más vendidos / menor rendimiento): https://ayuda.tiendanube.com/es_AR/123489-estadisticas/como-ver-las-estadisticas-de-mi-tiendanube |
| 판매원(vendedora)별 매출 | 점주 | 주·월(커미션) | POS 판매 + 판매원 | ✅ 차원 vendedor, 지표 venta neta·tickets·UPT | Shopify "sales by staff at register / staff attributed": https://help.shopify.com/manual/reports-and-analytics/shopify-reports/report-types/retail-sales-reports · Loyverse 직원별: https://Loyverse.com/back-office |
| 판매원 비교 시 주의 | — | — | — | 매장 크기·시즌 주차가 성과를 좌우한다는 연구 → 같은 지점·같은 기간끼리 비교 권장 | IESE: https://www.iese.edu/es/insight/articulos/tamano-tiendas-ventas-moda/ |
| 결제수단 믹스 (efectivo / transferencia / tarjeta / MercadoPago) | 점주·경리 | 일(마감)·월 | POS 결제 | ✅ 차원 medio de pago, 지표 venta neta | Square Payment methods: https://squareup.com/help/ca/en/article/5200 · Loyverse Sales by Payment Type: https://help.loyverse.com/help/reports |
| 카테고리(rubro) 매출 | 점주 | 주·월 | POS 판매+상품 분류 | ✅ 차원 categoría | Dux "Analizar ventas por rubro": https://intercom.help/duxsoftware/es/articles/7884756-analizar-ventas-por-rubro · Square category: https://squareup.com/help/gb/article/5618 |
| **사이즈 커브 (curva de talles)** — 판매 분포 | 구매담당·점주 | 주·시즌 | POS 판매 + 변형(talle) | ✅ 차원 talle (·categoría), 지표 unidades, % 표시 | base.com (커브 잘못 사면 끝 사이즈에 자본 묶이고 중간 사이즈 품절): https://base.com/es-AR/blog/?p=18540 · SPS(사이즈별): https://www.spscommerce.com/community/articles/key-metrics-to-track-in-fashion-apparel-and-footwear |
| 사이즈별 **품절/재고 대비** 판매 ("qué talle me falta") | 구매담당 | 주 | 판매 + **재고** | ❌ 재고 필요 (판매 분포만으론 "팔린 것"만 보이고 "없어서 못 판 것"은 안 보임) | Increff(변형별 누적 은폐): https://www.increff.com/blog/10-inventory-aging-reports-every-retailer-needs |
| 색(color) 성과 | 구매담당 | 주·시즌 | POS 판매 + 변형(color) | ✅ 차원 color (·producto) | SPS(스타일·색·사이즈·주): https://www.spscommerce.com/community/articles/key-metrics-to-track-in-fashion-apparel-and-footwear |
| 시즌(temporada)별 판매 | 점주·구매 | 시즌 중 주간, 시즌 말 | 판매 + 시즌 속성 | ✅ 차원 temporada × semana | 동상 |
| **Sell-through** (판매÷입고) | 구매·점주 | 시즌 중 주간 | 판매 + **입고 수량** | ❌ 재고/입고 필요 | Nextail: https://help.nextail.co/en/what-is-the-difference-between-sell-out-and-sell-through · SPS 위 링크 |
| Weeks of supply / stock cover | 구매 | 주(시즌 중) | 판매 + **현재고** | ❌ | Cleverence: https://www.cleverence.com/articles/for-business/inventory-metrics-for-retail-4827/ |
| 재고 연령 (0–30/31–60/61–90/91–120/120+일) | 구매·점주 | 월 | **재고 + 입고일** | ❌ | Increff 위 링크 · 마크다운 플레이북: https://www.theuniformsolution.com/resource/the-markdown-playbook |
| Markdown 효과 (할인 판매 비중, 정가 sell-through) | 점주 | 주(할인 중)·월 | 판매 + 할인액 (+입고) | ⚠️ 할인액·할인 판매 비중은 판매만으로 가능, 정가 sell-through 는 입고 필요 | SPS 위 링크 · Racklify: https://racklify.com/encyclopedia/how-to-calculate-and-report-inventory-markdowns/ |
| AUR (평균 판매 단가) | 점주 | 주·월 | 판매 | ✅ 파생지표 venta neta ÷ unidades `[1단계 카탈로그에 없으면 추가 후보]` | SPS 위 링크 |
| UPT (티켓당 수량) | 지점장 | 일·주 | 판매 | ✅ unidades ÷ tickets `[카탈로그 추가 후보]` | https://todosloshechos.es/que-es-atv-y-upt · ShippyPro: https://www.shippypro.com/blog/es/kpi-retail |
| Conversion (방문→구매) | 지점장 | 일 | **방문자 수(트래픽 카운터)** | ❌ Ventago 에 트래픽 데이터 없음 | ShippyPro 위 링크 |
| 반품률 (devoluciones) | 점주 | 월 | 판매 + 반품/NC | ✅ 지표 devoluciones (금액·수량) ÷ 매출 | SPS 위 링크 · Lightspeed "Returns (%)" 측정치 |
| 마진 (margen bruto) | 점주 | 월 | 판매 + **원가** | ⚠️ 원가가 입력된 상품만 신뢰 가능 | Lightspeed Gross Profit/Margin 측정치 위 링크 · Odoo Margin: https://www.cybrosys.com/odoo/odoo-books/v17/pos/reporting |
| GMROI | 점주·구매 | 월·시즌 | 마진 + **평균 재고 원가** | ❌ | SPS 위 링크 · Cleverence: https://www.cleverence.com/amp/articles/for-business/retail-metrics-7391/ |
| 요일·시간대 패턴 | 지점장(인력 배치) | 월 | 판매 시각 | ✅ 차원 día de semana / hora `[카탈로그에 hora 없으면 갭]` | Odoo 애드온 hourly/weekly 수요 존재: https://apps.odoo.com/apps/modules/17.0/oe_pos_report_by_hourly_weekly |
| 전년 동기·직전 기간 비교 | 점주 | 월·시즌 | 판매 2기간 | ✅ 비교 옵션 (단 pesos 는 인플레이션 왜곡 — §3) | Shopify 비교: https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/new-analytics/new-reports |
| 외상(cuenta corriente) 매출·회수 | 점주·경리 | 주·월 | 외상 원장 | ❌ 판매 행이 아니라 별도 원장(잔액·입금) — 별도 타입 | YoFacturo 보고서 분류에 "Cuentas Corrientes" 별도: https://yo-facturo.com/blog/reportes-automaticos-negocio/ |

---

## 2) 경쟁 제품의 사용자 정의 보고서 기능 비교

✔ = 출처에서 확인 / ? = 확인 못 함·간접 / ✘ = 출처가 "없음"이라고 함

| 제품 | 지표+차원 자유 조합 | 비교(직전/전년) | 필터 | Top N | 저장·재실행 | 변형(색/사이즈) 축 | 판매원 축 | 결제수단 축 | 비고 / 출처 |
|---|---|---|---|---|---|---|---|---|---|
| **Shopify** (Explorations / ShopifyQL) | ✔ 지표≥1, 차원 여러 개(순서=중첩) | ✔ 직전 기간·전년 동기·목표 | ✔ 기본 최근 30일 | ✔ "number of top items" | ✔ 기본 보고서 수정은 임시, "custom report"로 저장. 플랜 무관 저장 가능(공식) | ✔ "Retail sales by product variant SKU" | ✔ staff at register / staff attributed | ? | ShopifyQL 직접 작성·Sidekick(AI) 생성, 시간축 주석. https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/new-analytics/new-reports · https://help.shopify.com/manual/reports-and-analytics/shopify-reports/report-types/retail-sales-reports |
| **Lightspeed Retail X-Series** | ✔ (Advanced) 측정치·필터·표 형식 | ✔ Advanced "comparison periods" | ✔ | ? | ✔ saved reports + **scheduled reports** (Advanced/Plus) | ✔ "Variant Attribute" 보고서 | ✔ "User", "Individual performance" | ✔ Payment Reports(Basic) | 측정치에 Avg Sale Value·Items Sold·Return %·COGS·Margin. https://product-info.lightspeedhq.com/lightspeed-retail-x-series-reporting-comparison-global · https://x-series-support.lightspeedhq.com/hc/articles/25534172721819 |
| **Lightspeed Retail (R-Series) Analytics** | ✔ 기존 보고서 또는 빈 템플릿에서 차원·측정치·필터 추가 | ? | ✔ | ? | ✔ "Save as new report" + 즐겨찾기 | ? | ✔ Employee performance 섹션 | ? | 일부 차원·측정치는 특정 보고서 유형에서만 사용 가능. 종료일이 exclusive(POS 와 다름) — **날짜 경계 혼란 사례**. https://retail-support.lightspeedhq.com/hc/en-us/articles/4410659754139 |
| **Square** | ? (custom report 존재는 언급, 구성법 미확인) | ✔ 오늘 vs 과거 1주~1년 | ✔ 기간·시간대·지점·판매채널 | ? | ? | ? | ✔ Team member sales (플랜 조건 출처마다 상이) | ✔ Payment methods 보고서 | 품목×결제수단 조합 보고서는 없어 CSV 로 우회한다는 커뮤니티 질문 다수. https://squareup.com/help/gb/article/5618 · https://community.squareup.com/t5/Questions-How-To/create-a-report-that-shows-individual-items-by-payment-type-cash/m-p/59359 |
| **Odoo** (POS Orders analysis) | ✔ pivot: Group By(사용자·직원·POS·상품·카테고리·주문일) + Measures(수량·총액·할인·마진 등), 커스텀 Group By 추가 | ✔ (Odoo 일반 기능으로 알려졌으나 이번 조사 출처에선 미확인 → ?) | ✔ | ? | ✔ **Favorites**(검색 저장, 기본값 지정 가능) | ? (커스텀 group by 로 속성 가능할 수 있음) | ✔ | ✘ 표준 POS 주문 분석 출처엔 결제수단 축 언급 없음 | 표준은 **주문 단위** 집계라 라인 단위 분석은 서드파티 애드온. https://www.cybrosys.com/odoo/odoo-books/v17/pos/reporting · https://www.odoo.com/documentation/18.0/applications/essentials/search.html · https://apps.odoo.com/apps/modules/17.0/aminitech_pos_product_sales_report |
| **Loyverse** | ✘ 고정 보고서 | ? | ✔ 기간·매장·직원 | ? | ? | ? | ✔ | ✔ Sales by Payment Type | 무료판은 31일 제한·내보내기 불가. 조합은 CSV 내보내기 후 스프레드시트. https://help.loyverse.com/help/reports · https://help.loyverse.com/help/sales-item-report-back-office |
| **Vend** | — | — | — | — | — | — | — | — | Vend 는 Lightspeed X-Series 로 리브랜딩된 제품 `[일반 지식, 이번 조사에서 별도 출처 미확보]` |
| **Tiendanube / Nuvemshop** | ✘ 고정 패널 | ✔ "variación" 표시 | ✔ 결제수단·배송 필터 | ✔ 상품 패널(최다/최저) | ? | ? | — (온라인) | ✔ 결제수단/제공자 필터 | 상품 패널 최대 120일, 개요 365일, 플랜별 제공 상이. https://ayuda.tiendanube.com/es_AR/123489-estadisticas/preguntas-frecuentes-sobre-las-estadisticas-de-tiendanube |
| **Dux Software** (AR) | ✘ 고정 보고서(판매 상세·rubro별) | ? | ✔ 코드·상품·판매원·고객·지점·rubro | ? | ? | ✘ **talle/color 필터 "por el momento" 비활성** | ✔ | ? | Excel 내보내기. https://intercom.help/duxsoftware/es/articles/7879997-analizar-el-detalle-de-ventas · https://intercom.help/duxsoftware/es/articles/7884756-analizar-ventas-por-rubro |
| **Tango Gestión / Punto de Venta** (Axoft, AR) | ? "Tango Reportes" 앱: 지표·그리드·**pivot** 형식 | ? | ? | ? | ? | ? | ? | ? | 판매·급여·재고 모듈 보고서. 색/사이즈 축 미확인. https://apps.apple.com/us/app/id1590148578 |
| **Contabilium / Bejerman** (AR) | ? | ? | ? | ? | ? | ? | ? | ? | 이번 조사에서 공식 보고서 문서를 찾지 못함 — **미확인** |
| 참고: Alegra / YoFacturo (LatAm SaaS) | ✘ 고정 | ? | ✔ 날짜·고객·상품·지점 | ? | ? | ? | ✔ 판매원별 | ? | 분류: Ventas·Gastos·Inventario·Fiscal·Cuentas Corrientes·Rentabilidad. https://yo-facturo.com/blog/reportes-automaticos-negocio/ |

**관찰**
- "자유 조합 + 비교 + 저장"까지 갖춘 것은 Shopify·Lightspeed(고급 플랜)·Odoo 정도. 소상공인용(Loyverse·Tiendanube·Dux)은 **고정 보고서 + 필터 + CSV**.
- 반복 등장하는 불만/우회: 「품목 × 결제수단」을 한 표로 못 봄(Square), 「직원 × 결제 × 카테고리」 결합 내보내기 없음(Loyverse) → **두 차원 교차**가 실제 수요.
- Shopify·Lightspeed 모두 **"기존(기본) 보고서를 열어 고친 뒤 이름 붙여 저장"**이 1순위 진입로 → 템플릿 출발이 빈 캔버스보다 주 경로.

---

## 3) 인플레이션 대응 권고

**출처에서 확인된 것**
- CAME 의 소매 pyme 매출 지수는 **전년 동월 대비, 실질(a precios constantes)**로만 발표한다(1,273개 매장 표본). https://www.forbesargentina.com/money/alerta-inflacion-pymes-advierten-ventas-minoristas-cayeron-septimo-mes-consecutivo-n38479
- CAME 는 과거 의류 부문에서 **수량(unidades) 기준 감소율(−11.5%)**을 따로 보고한 적이 있다 → 의류 업계에서 "수량으로 읽기"는 낯선 방식이 아니다. https://blogdelcontador.com.ar/ventas-minoristas-pyme-caen-un-73-en-mayo-marcando-el-decimocuarto-mes-de-baja-consecutiva (출처 날짜 표기가 일관되지 않음 — 수치는 인용만, 근거로 쓰지 않는다)
- 실질화 = **명목 ÷ 물가지수** (CEPAL/INDEC 자료). 스페인 Cepyme 사례: 명목 +14.3% 인데 수량 −1.2% — "명목 매출 증가가 실제 판매 감소를 숨긴다"의 전형. https://www.cepal.org/sites/default/files/presentations/impacto-inflacion-cuentas-nacionales-argentina_indec-oct2023.pdf · https://theobjective.com/economia/2023-01-10/volumen-ventas-desciende/ · https://yirepa.es/deflactar.html
- IPC 는 소비자 바스켓이므로 **해당 업종 가격과 다를 수 있다** — 가능하면 업종 지수를 쓰라는 주의. (위 Yirepa/일반 설명)
- 전년 비교는 **기저효과**를 조심: 2025년 초 높은 전년비는 낮은 기저 때문이었다(El Cronista). https://www.cronista.com/economia-politica/entre-la-desaceleracion-de-precios-y-un-consumo-que-no-reacciona-como-cerro-agosto-para-el-comercio-pyme/
- INDEC 는 「¿Cómo usar un índice de precios?」 안내서를 공개한다(PDF, 이번에 본문 추출 실패 — 내용은 미확인). https://www.indec.gob.ar/ftp/cuadros/economia/como_usar_indice_precios_2022.pdf

**찾지 못한 것**
- 소매점에 **USD 환산 비교를 권장**하는 출처는 찾지 못했다. Once/Avellaneda 관련 기사도 가격을 pesos 로만 다룬다. → USD 는 "있으면 좋은" 옵션이지 근거 있는 표준이 아니다.

**Reportaje abierto 설계 권고** `[내 판단 — 출처 사실에서 도출]`
1. 기간 비교가 켜지면 **pesos 와 함께 unidades·tickets 의 증감을 항상 병기**한다(최소 경고 배지: "variación en pesos incluye inflación").
2. **AUR(precio promedio por unidad) 증감**을 같이 보여 주면 "가격 효과 vs 수량 효과"가 매장 자체 데이터로 분해된다 — IPC 보다 매장 실정에 맞다(IPC ≠ 업종 가격 주의와 일치).
3. IPC 보정(실질 pesos)은 2단계 옵션: 월별 IPC 테이블(INDEC)을 시스템이 보관하고, 비교 기간을 **기준월 pesos** 로 환산. 일 단위 비교에는 쓰지 않는다(IPC 는 월간).
4. 전년 동기 비교에는 **기저효과 주석**(작년 해당 기간이 비정상적으로 낮았는지)을 띄울 여지를 둔다.
5. USD 환산은 근거가 약하므로 기본값으로 두지 않는다. 요청이 있으면 환율 출처(공식/MEP)를 명시해야 해서 정책 결정이 먼저 필요.

---

## 4) 실제 질문 문구 예시

**정직한 한계**: 스페인어 포럼/블로그에서 점주의 **원문 질문**을 직접 수집하지는 못했다(검색이 소비자 측 "talle 못 찾음" 기사만 돌려줬다). 아래 중 출처가 붙은 것은 실제 문구, 나머지는 위 보고서 수요를 아르헨티나 구어(voseo)로 옮긴 **가설 문구**다 — Pedidos 텔레그램·현장 인터뷰로 검증 필요.

**출처 있는 실제 문구 (영어·스페인어)**
- "create a report that shows individual items by payment type (cash or credit)" — Square 커뮤니티 https://community.squareup.com/t5/Questions-How-To/create-a-report-that-shows-individual-items-by-payment-type-cash/m-p/59359
- "How to get a report of gross sales by payment type" — Square 커뮤니티 https://community.squareup.com/t5/Archived-Discussions-Read-Only/How-to-get-a-report-of-gross-sales-by-payment-type/m-p/341673
- "Reports: see whether a payment is card or cash in reports" — Square 커뮤니티 https://community.squareup.com/t5/Questions-How-to/Reports-see-whether-a-payment-is-card-or-cash-in-reports/td-p/800281
- Tiendanube 도움말의 표현: "identificar los productos más vendidos y los de menor rendimiento" https://ayuda.tiendanube.com/es_AR/123489-estadisticas/como-ver-las-estadisticas-de-mi-tiendanube

**가설 문구 (스페인어, 검증 필요) → 대응 조합**
| 문구 | 지표 | 차원 | 필터/옵션 |
|---|---|---|---|
| ¿Qué se vendió más esta semana? | unidades | producto | esta semana, Top 10 |
| ¿Qué es lo que no sale? / ¿Qué tengo clavado? | unidades | producto | temporada actual, Top N ascendente (※"clavado"=재고 개념 → 재고 없으면 부분 답) |
| ¿Cuánto vendió cada vendedora este mes? | venta neta, tickets | vendedor | este mes, sucursal |
| ¿Cuánto entró por MercadoPago y cuánto en efectivo? | venta neta | medio de pago | hoy / este mes |
| ¿Qué talle se vende más de este modelo? | unidades | talle | producto=X |
| ¿Qué talle me falta? | (재고 필요) | talle | — → **갭** |
| ¿Qué color pegó más esta temporada? | unidades | color | temporada |
| ¿Cómo vamos contra el año pasado? | venta neta + unidades | mes | comparación = mismo período año anterior |
| ¿Qué sucursal vende más? | venta neta, ticket promedio | sucursal | este mes |
| ¿A qué hora/qué día se vende más? | tickets | día de semana / hora | últimos 3 meses |
| ¿Cuánto me devolvieron? | devoluciones | producto / vendedor | este mes |
| ¿Cuánto gané este mes? | margen (원가 필요) / resultado (gastos 필요) | — | → §6 |
| ¿Cuánto facturé (en blanco) este mes? / ¿Me paso de categoría? | → Facturación 원장 | — | → §6 |

---

## 5) Reportaje abierto 템플릿 후보 Top 15

우선순위 기준: (a) 여러 출처에서 반복 (b) POS 판매만으로 정확히 계산 (c) 의류 특화 (d) 아르헨티나 경쟁 제품의 빈칸.

| # | 템플릿 (es) | 지표 | 차원 | 기본 필터·옵션 | 우선 이유 |
|---|---|---|---|---|---|
| 1 | Lo más vendido de la semana | unidades, venta neta | producto | esta semana, Top 20 | 모든 제품에 존재(Tiendanube·Shopify·Loyverse), 매주 구매 결정 |
| 2 | Ventas por sucursal | venta neta, tickets, ticket promedio | sucursal | este mes, vs mes anterior | 다지점이 Ventago 의 기본 구조, Lightspeed Outlet·Shopify location |
| 3 | Ventas por vendedora | venta neta, tickets, UPT | vendedor | este mes, por sucursal | 커미션·관리. Shopify/Lightspeed/Dux/Loyverse 공통. ※같은 지점 내 비교 권장(IESE) |
| 4 | Cobros por medio de pago | venta neta | medio de pago | hoy / este mes | 마감·자금 관리, Square·Loyverse 별도 보고서 존재 |
| 5 | Curva de talles | unidades (%) | talle (× categoría) | temporada actual | 의류 핵심, **Dux 에선 talle 필터 비활성** → 차별점 |
| 6 | Colores que más se venden | unidades | color (× producto) | temporada actual, Top 10 | SPS "style·color·size" 분해 권고 |
| 7 | Este año vs el año pasado | venta neta **+ unidades + tickets** | mes | comparación año anterior | 점주 질문 1순위 유형, 인플레이션 병기 필수(§3) |
| 8 | Ventas por temporada | unidades, venta neta | temporada × semana | — | 시즌 단위 의사결정 |
| 9 | Ventas por categoría (rubro) | venta neta, unidades | categoría | este mes vs anterior | Dux·Square·Odoo 공통 |
| 10 | Día y hora de mayor venta | tickets, venta neta | día de semana (× hora) | últimos 90 días | 인력 배치, Odoo 애드온 수요 |
| 11 | Devoluciones | devoluciones ($, u), % s/ventas | producto / vendedor | este mes | 반품률 표준 KPI (SPS·Lightspeed) |
| 12 | Lo que menos se vende | unidades | producto | temporada, Top N ascendente | Tiendanube "menor rendimiento". 재고 없이도 근사 가능(판매 0 은 표시 불가 → 주석) |
| 13 | Ticket promedio y unidades por ticket | ticket promedio, UPT | semana (× sucursal) | últimas 8 semanas | 교차판매 지표 |
| 14 | Margen por categoría | margen, % | categoría | este mes | 원가 입력된 매장만 — 커버리지 표시 필요 |
| 15 | Precio promedio (AUR) por mes | AUR | mes | 12 meses | 인플레이션 하 가격효과 분리(§3) |

### 1단계 카탈로그에 없는데 자주 요구되는 것 (갭)
| 갭 | 왜 안 되나 | 출처 |
|---|---|---|
| Sell-through (판매÷입고), 정가 sell-through | 입고/재고 필요 | SPS, Nextail |
| ¿Qué talle me falta? (품절 사이즈, 재고 대비 판매) | 현재고 필요 — 판매 분포는 "없어서 못 판" 수요를 못 본다 | Increff, base.com |
| Weeks of supply / stock cover | 현재고 필요 | Cleverence |
| 재고 연령 / 시즌 잔재고 | 재고 + 입고일 필요 | Increff, Uniform playbook |
| GMROI, 재고회전 | 평균 재고 원가 필요 | SPS |
| Conversion | 방문자 수 없음(영구 갭) | ShippyPro |
| 판매 0 상품("안 팔린 것") | 판매 행 기반 집계는 0 행을 만들지 못함 — 상품 마스터와 left join 필요 | `[내 판단]` |
| 외상(cuenta corriente) 잔액·회수 | 별도 원장 | YoFacturo 분류 |
| 실질(IPC) 비교 | IPC 테이블 필요 | §3 |
| 예약 발송(scheduled reports, 이메일/텔레그램) | 1단계 범위 밖, Lightspeed Advanced 에 있음 | Lightspeed |
| AI/자연어로 보고서 만들기 | Shopify Sidekick 이 ShopifyQL 생성 | Shopify |

---

## 6) Gastos y Facturación

**핵심 원칙**: 둘 다 **판매 행(sale_items)과 섞을 수 없는 별도 원장**이다.
- Gastos = 비용 원장(카테고리·지점·일자·금액). 판매와는 **같은 기간·같은 지점 키로 나란히 놓는 것만** 가능(조인 아님, 병렬 집계).
- Facturación = comprobante 원장(tipo A/B/C·NC·ND, punto de venta, 번호, neto gravado/no gravado/exento, IVA). 한 판매가 미발행일 수도, NC 로 상쇄될 수도 있어 **판매 수와 comprobante 수는 1:1 이 아니다.** 세무 수치는 **판매가 아니라 comprobante 에서** 읽어야 한다.

### 6-1) 보고서 표

| 보고서 | 누가 | 주기 | 필요한 데이터 | 하나의 pedido 로? 아니면 별도 타입 | 출처 |
|---|---|---|---|---|---|
| Gastos por categoría (월별 피벗) | 점주·경리 | 월 | expenses(카테고리·금액·일자) | ✅ Gastos 원장 위의 pedido (지표 monto, 차원 categoría × mes) — **판매 지표와 혼합 불가** | OnBalance "gastos anuales por categoría, total por mes": https://www.thomsonreuters.com/es-ar/help/onbalance/reports/reports-ar.html |
| Gastos por sucursal | 점주 | 월 | expenses + 지점 | ✅ Gastos pedido, 차원 sucursal | OnBalance 는 지점 축 언급 없음 → Ventago 차별 여지 |
| Gastos fijos vs variables | 점주 | 월 | expenses + 카테고리의 고정/변동 속성 | ⚠️ 카테고리에 fijo/variable 속성 필요 (없으면 갭) | Mercado Pago blog(고정: 임대·급여·보험 / 변동: 원재료·배송·수수료): https://www.mercadopago.com.mx/blog/control-de-costos-negocio · ayudaT: https://ayudatpymes.com/gestron/cuanto-debe-facturar-tiene-ser-rentable/ |
| Gastos / ventas (%) | 점주 | 월 | 판매 합계 + 비용 합계 (같은 기간·지점) | **별도 타입** — 두 원장을 같은 키로 나란히 집계하는 "합성 보고서" | 공식 업종 벤치마크는 찾지 못함 |
| Resultado simple (ventas − costo − gastos) | 점주 | 월 | 판매(IVA 제외 순매출) + 원가 + 비용 | **별도 타입** (손익). 원가 커버리지·IVA 제외 여부 명시 필요 | YoFacturo 손익 구조(매출−매출원가=총이익, −영업비=영업이익, 매출은 IVA 제외): https://yo-facturo.com/blog/estado-de-resultados/ |
| Punto de equilibrio | 점주 | 월 | 고정비 + 공헌이익률 | 별도 타입(2단계) | 공식 = 고정비 ÷ 공헌이익률: https://beancount.io/es/blog/2026/03/19/break-even-analysis-how-to-calculate-break-even-point · Mar del Plata 사례(급여 민감): https://www.lacapitalmdp.com/para-no-perder-un-comercio-en-mar-del-plata-necesita-facturar-mas-de-16-millones-por-mes/ |
| Comprobantes emitidos por tipo (A/B/C, NC, ND) | 경리·회계사 | 월 | comprobantes | ✅ Facturación 원장 위의 pedido (지표 cantidad·total·IVA, 차원 tipo × punto de venta) | ARCA Mis Comprobantes 필터: 기간(최대 31일)·tipo·punto de venta·번호·CUIT, 열: neto gravado/no gravado/exento/IVA/total: https://www.consejosalta.org.ar/wp-content/uploads/INFO.-GRAL.-MIS-COMPROBANTES.pdf |
| **Libro IVA Ventas** (월 시간순 + débito fiscal 요약) | 회계사(Responsable Inscripto) | 월 | comprobantes (alícuota 별) | **별도 타입(고정 서식)** — 자유 조합이 아니라 법정 서식. 소비자 미식별 판매는 일 합계(Venta Global Diaria, 코드 99) 처리 가능 | OnBalance Libro IVA Ventas: https://www.thomsonreuters.com/es-ar/help/onbalance/reports/tax-reports-ar.html · Libro IVA Digital 특수 기록: https://www.consejosalta.org.ar/wp-content/uploads/libro-iva-digital-modalidades-especiales-de-registracion.pdf · PV 일치 검증: https://contadoresenred.com/espacio-de-dialogo-particular-libro-de-iva-digital-acta-nro-17-06-ago-2020/ |
| IVA débito por alícuota / actividad | 회계사 | 월 | comprobantes | 별도 타입 또는 Facturación pedido (차원 alícuota) | ARCA DJ IVA 사전 채움(Libro IVA Digital 기반): https://servicioscf.afip.gob.ar/publico/sitio/contenido/novedad/ver.aspx?id=4354 · IVA Simple: https://www.iprofesional.com/impuestos/432081-iva-simple-arca-lanza-un-nuevo-micrositio-donde-explica-las-claves-del-sistema |
| % ventas facturadas vs no facturadas | 점주 (내부용) | 일·월 | 판매 + 판매↔comprobante 연결 | **별도 타입** (두 원장 대조). 민감 정보 — 권한 제한 필요 `[내 판단]` | 공개 출처 없음(관행상 공개 논의가 드묾) |
| **Monotributo: 12개월 누적 발행 vs 카테고리 한도** | 점주(모노트리부토) | 월·재분류 전(1월·7월) | comprobantes 12개월 + 매장 카테고리·한도표 | **별도 타입(경보 카드)** — 누적은 미수금이어도 발행 기준. 면적·전력·임대도 기준이지만 시스템 밖 | Cronista(발행 기준·미수 포함): https://www.cronista.com/economia-politica/monotributo-2026-cual-es-el-monto-maximo-que-podes-facturar-por-mes-sin-cambiar-de-categoria/ · 연 2회 재분류: https://www.diariodecuyo.com.ar/argentina/primera-recategorizacion-del-monotributo-2026-que-tener-en-cuenta-y-como-hacerla-1817772.html · 한도표 2026-08 개정(+16.8%): https://www.conclusion.com.ar/?p=1439839 · 간이 재분류는 12개월 전자발행 기반: https://web.cpcecba.org.ar/?p=62834 |
| IIBB base por jurisdicción | 회계사 | 월 | comprobantes/판매 × 지점 소재지 | 별도 타입(2단계). Convenio Multilateral 은 회계사 영역 — 시스템은 **지점(관할)별 매출 합계**만 제공하는 편이 안전 | Convenio 일반: https://www.consejosalta.org.ar/wp-content/uploads/CA-1-ANEXO.pdf · CM05 연차: https://www.iprofesional.com/impuestos/401908-como-hacer-la-declaracion-anual-del-convenio-multilateral-de-ingresos-brutos |
| MercadoPago 입금 대사 | 경리 | 일·월 | POS 결제(MP) + MP Liquidaciones 보고서 | 별도 타입(외부 대사), 1단계 밖 | MP Liquidaciones / Dinero en cuenta: https://www.mercadopago.com.ar/developers/es/docs/reports/released-money/panel |

### 6-2) 템플릿 후보

**Gastos (Gastos 원장 pedido)**
1. Gastos del mes por categoría (vs mes anterior) — monto × categoría
2. Gastos por sucursal — monto × sucursal (× categoría)
3. Evolución de gastos 12 meses — monto × mes (인플레이션: 비용도 pesos 왜곡 — 매출 대비 % 가 더 안정적)
4. Gastos fijos vs variables — **카테고리 속성 필요(갭)**

**합성 (별도 타입 — 두 원장 병렬)**
5. Gastos sobre ventas (%) por sucursal y mes — 인플레이션 하에서 **비율은 명목 왜곡이 상쇄**되어 비교 가능성이 높다 `[내 판단]`
6. Resultado simple del mes: ventas netas (sin IVA) − costo − gastos — 원가 커버리지 % 를 같이 표시

**Facturación (comprobante 원장 pedido / 고정 서식)**
7. Comprobantes emitidos por tipo y punto de venta (A/B/C/NC) — cantidad, neto, IVA, total
8. Libro IVA Ventas del mes (고정 서식, CSV/Excel 내보내기) — 회계사 송부용
9. Monotributo: facturado últimos 12 meses vs tope de categoría (경보: 80%/100%) — 모노트리부토 매장 전용
10. Notas de crédito del mes (반품·취소의 세무측 반영) — tipo NC × motivo/vendedor
11. Facturado por sucursal (IIBB 준비용 관할 합계)
12. Ventas facturadas vs no facturadas (%) — 점주 전용 권한

**갭 / 주의**
- 판매 지표(venta neta)와 comprobante 금액을 **한 pedido 에서 같은 열로 합치지 말 것** — NC·미발행·부분 발행 때문에 숫자가 맞지 않는 것이 정상이다.
- 비용 카테고리의 fijo/variable 속성, 매장 모노트리부토 카테고리·한도표(연 2회 개정)는 **현재 데이터에 있는지 확인 필요**(이번 조사는 외부 조사라 Ventago 스키마는 보지 않았다).
- Convenio Multilateral 배분 계산, Libro IVA Digital 제출은 회계사 업무 — 시스템은 원자료 제공까지로 범위를 둔다 `[내 판단]`.

---

## 출처 신뢰도 메모
- 공식 도움말(Shopify·Lightspeed·Loyverse·Tiendanube·Dux·Mercado Pago·ARCA/AFIP)은 기능 존재 근거로 사용. 단 플랜별 제공 범위는 출처마다 달랐다(Shopify 저장 기능 플랜, Square Team member sales 플랜).
- Report Pundit 등 경쟁 앱 벤더 글은 기능 주장 근거로 쓰지 않았다.
- 마크다운 주차·WOS 12–20주 등 수치는 **예시/벤더 기준**이지 업계 표준이 아니다 — 본 문서에서 벤치마크로 채택하지 않았다.
- Contabilium·Bejerman·Tango 의 보고서 상세는 **미확인**.
