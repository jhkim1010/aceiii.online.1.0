# 판매 예측 및 생산 추천 기능 명세서

> 사용자 제공 원문(2026-10-19 phase 119 등록 시 그대로 보존). 상태: 초안.
> ★ 이 문서의 스키마(`tenant_id`·`variant_id`·`product_variants`)는 **Ventago 실제 구조와 다르다** —
>   discuss/plan 단계에서 `store_id`·`products(parent_id 자식 = 변형)`·`ProductBranch`·`stocks` 원장에 맞춰야 한다.

- 작성일: 2026-10-18
- 대상 제품: Ventago (의류 생산 관리 SaaS)
- 상태: 초안

---

## 1. 개요

고객사(중소 의류 제조업체)가 실제로 필요로 하는 것은 "얼마나 팔릴까"가 아니라 **"무엇을, 몇 장, 언제 만들까"**이다.
이 기능은 판매 예측을 재료로 삼아 아래 세 가지 추천을 하나의 흐름으로 제공한다.

1. **무엇을 만들까** — 잘 팔리는/안 팔리는 속성 조합 분석
2. **얼마나 만들까** — 기존 모델의 생산 수량 추천 + 신모델 초기 수량 추천
3. **언제 더 만들까** — 출시 후 판매 속도를 보고 재생산·원단 발주 시점 추천

### 차별화 포인트

경쟁 제품 조사(2026-10-18) 결과, 중소기업용 예측 도구(Prediko, Katana, Inventory Planner, Odoo 모듈 등)는 대부분 과거 판매·계절성·행사까지만 반영한다. 날씨를 자동 반영하는 제품은 대기업용(ToolsGroup + Planalytics, Pelmorex 등)뿐이고, 인플레이션 보정을 내장한 제품은 확인되지 않았다.

Ventago의 강점:
- 생산 관리 시스템이므로 **리드타임, 원단, 생산 진행 데이터를 이미 보유**
- 아르헨티나 시장 특화: **물가 보정 수량 예측**, 현지 행사 달력
- POS + 쇼핑몰(Tienda Nube, Mercado Libre 등) 판매 데이터를 한 곳에 모을 수 있음

---

## 2. 목표와 비목표

### 목표
- 카테고리·모델 단위 1개월 수요 예측을 **범위(시나리오)**로 제공
- 예측을 **사이즈·색상별 생산 수량**으로 환산하여 추천
- 판매 이력이 없는 **신모델의 초기 생산 수량** 추천
- **속성 조합별 성과 분석**으로 다음 시즌 기획 지원
- 출시 후 판매 속도 기반 **재생산 알림**

### 비목표 (1차 범위 제외)
- SKU 단위 일별 정밀 예측 (데이터 부족으로 오차가 큼)
- 자동 발주·자동 생산 지시 (추천만 하고 결정은 사람이)
- 실시간 예측 (야간 배치로 충분)
- 이미지 기반 디자인 추천 (향후 VTON 기능과 연계 검토)

---

## 3. 사용자 시나리오

| 사용자 | 상황 | 기대 결과 |
| --- | --- | --- |
| 생산 담당자 | 다음 달 생산 계획 수립 | 모델·사이즈·색상별 추천 수량과 근거 |
| 기획 담당자 | 다음 시즌 신모델 기획 | 판매 속도가 오르는 속성 조합과 재고로 남은 조합 |
| 생산 담당자 | 신모델 첫 생산 | 닮은 과거 모델 기반 1차 수량, 사이즈 비율 |
| 대표 | 출시 2주 후 | "예상보다 빠름, 재생산 추천" 알림과 원단 발주 마감일 |

---

## 4. 기능 상세

### 4.1 무엇을 만들까: 속성 조합 성과 분석

**입력**: 모델별 속성(카테고리, 원단, 색상군, 핏, 가격대, 시즌), 판매·생산·재고 데이터

**지표** (속성 조합별):
- 판매율(sell-through) = 판매 수량 ÷ 생산 수량
- 판매 속도 = 출시 후 첫 4주 일평균 판매량
- 마진율
- 잔여 재고율 = 시즌 종료 시 재고 ÷ 생산 수량

**출력 예시**:
- "린넨 + 베이지 + 오버핏 + 중가: 판매 속도 전년 대비 +40%"
- "폴리 + 원색 + 슬림핏: 잔여 재고율 35%, 2시즌 연속 부진"

**규칙**:
- 표본이 적은 조합(모델 3개 미만)은 "참고" 표시
- 실패 패턴(재고로 남은 조합)을 성공 패턴과 같은 비중으로 노출

**향후 확장**: Mercado Libre·Tienda Nube 판매·검색 동향을 외부 신호로 추가

### 4.2 얼마나 만들까 (기존 모델)

```
추천 생산량 = 예측 수요(리드타임 + 판매 기간)
            + 안전재고
            − 현재 재고
            − 생산 중 수량
```

- **예측 수요**: 기본 모델(계절성 + 추세 + 행사) × 시나리오 보정(기온, 물가)
- **안전재고**: 품절 손실과 재고 손실을 비교해 결정 (뉴스벤더 방식)
  - 마진이 크고 계속 판매되는 상품 → 넉넉히
  - 유행성·시즌 한정 상품 → 적게
- **사이즈·색상 분배**: 최근 판매 비율 기준
- **반올림**: 최소 생산 단위(MOQ), 원단 롤 단위에 맞춤
- **출력**: 3개 시나리오(기본 / 더운 달 / 추운 달 또는 경기 위축)별 수량 범위 + 근거 설명

### 4.3 얼마나 만들까 (신모델, 콜드 스타트)

1. 신모델 등록 시 속성 입력 (필수)
2. 속성 유사도로 과거 모델 3~5개 선정
3. 닮은 모델들의 **출시 후 첫 4~8주 판매** 평균으로 초기 수요 추정
4. **1차 생산 = 추정치의 50~60%** (고객사 설정 가능)
5. 사이즈·색상 비율도 닮은 모델 기준으로 분배
6. 화면에 "참고한 모델" 목록을 함께 표시해 사용자가 판단 근거를 확인

### 4.4 언제 더 만들까: 재생산 추천

- 출시 7일, 14일 시점에 실제 판매 속도 ÷ 예상 판매 속도 계산
- 비율 1.3 이상 → "재생산 추천" + 원단 발주 마감일(리드타임 역산)
- 비율 0.6 이하 → "판매 부진, 할인·추가 생산 중단 검토"
- 알림 채널: 앱 내 알림 (향후 이메일·WhatsApp)

---

## 5. 데이터 요구사항

| 데이터 | 출처 | 최소 기간 | 비고 |
| --- | --- | --- | --- |
| 일별 판매 (모델·사이즈·색상) | POS, 쇼핑몰 연동 | 1년 (권장 2년) | 수량 기준 필수 |
| 품절 기간 | 재고 이력 | 판매와 동일 | 수요 과소평가 방지 |
| 모델 속성 | 신규 입력 | — | 지금부터 축적 필요 |
| 생산 리드타임 | 기존 생산 데이터 | — | Ventago 보유 |
| 원단 소요량·재고 | 기존 생산 데이터 | — | Ventago 보유 |
| 행사 달력 | 내장 + 고객사 프로모션 입력 | — | Día de la Madre, Hot Sale, Black Friday, Navidad, 아기날도 |
| 기온 | Open-Meteo / SMN | 판매와 동일 | 평년 대비 편차로 변환 |
| 물가 | INDEC (IPC) | 판매와 동일 | 금액 보정용 |

---

## 6. DB 스키마 (PostgreSQL)

> 기존 테이블명(`products`, `product_variants`, `tenants` 등)은 실제 스키마 확인 후 맞출 것.
> 운영 서버 안전 원칙: 신규 테이블만 추가하고 기존 테이블은 변경하지 않는다. 인덱스는 `CONCURRENTLY`로 생성한다.

```sql
-- 모델 속성 (신모델 추천과 속성 분석의 기반)
CREATE TABLE IF NOT EXISTS product_attributes (
    product_id      BIGINT PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
    tenant_id       BIGINT NOT NULL,
    category        TEXT NOT NULL,          -- 예: remera, pantalón, vestido
    fabric          TEXT,                   -- 예: lino, algodón, poliéster
    color_family    TEXT,                   -- 예: beige, negro, estampado
    fit             TEXT,                   -- 예: oversize, slim, regular
    price_band      TEXT,                   -- 예: bajo, medio, alto
    season          TEXT,                   -- 예: PV2026, OI2026
    launch_date     DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 일별 판매 집계 (POS + 쇼핑몰 통합, 야간 배치로 채움)
CREATE TABLE IF NOT EXISTS daily_sales_agg (
    tenant_id       BIGINT NOT NULL,
    variant_id      BIGINT NOT NULL,        -- 사이즈·색상 단위
    sale_date       DATE NOT NULL,
    qty             INTEGER NOT NULL DEFAULT 0,
    revenue         NUMERIC(14,2) NOT NULL DEFAULT 0,
    revenue_real    NUMERIC(14,2),          -- 물가 보정 금액
    stockout        BOOLEAN NOT NULL DEFAULT false,  -- 품절 여부
    PRIMARY KEY (tenant_id, variant_id, sale_date)
);

-- 속성 조합 성과 요약 (화면은 이 테이블만 읽음)
CREATE TABLE IF NOT EXISTS attribute_performance (
    tenant_id       BIGINT NOT NULL,
    season          TEXT NOT NULL,
    attr_key        TEXT NOT NULL,          -- 예: 'lino|beige|oversize|medio'
    model_count     INTEGER NOT NULL,
    sell_through    NUMERIC(5,4),
    velocity_4w     NUMERIC(10,2),
    margin_rate     NUMERIC(5,4),
    leftover_rate   NUMERIC(5,4),
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, season, attr_key)
);

-- 생산 추천 결과
CREATE TABLE IF NOT EXISTS production_recommendations (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT NOT NULL,
    variant_id      BIGINT NOT NULL,
    rec_type        TEXT NOT NULL CHECK (rec_type IN ('regular','new_model','reorder','slow')),
    scenario        TEXT NOT NULL CHECK (scenario IN ('base','warm','cold','downturn')),
    qty_recommended INTEGER NOT NULL,
    qty_low         INTEGER,
    qty_high        INTEGER,
    fabric_order_by DATE,                   -- 원단 발주 마감일
    reference_models BIGINT[],              -- 신모델 추천 시 참고한 모델
    rationale       JSONB,                  -- 근거 (화면 설명용)
    run_id          BIGINT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 배치 실행 이력 (재현·검증용)
CREATE TABLE IF NOT EXISTS forecast_runs (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    status          TEXT NOT NULL DEFAULT 'running',
    model_version   TEXT,
    error_message   TEXT
);

-- 인덱스는 트랜잭션 밖에서 개별 실행
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_product_attributes_tenant
    ON product_attributes (tenant_id, category, season);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_prod_rec_tenant_created
    ON production_recommendations (tenant_id, created_at DESC);
```

---

## 7. 처리 구조와 커넥션 풀 관리

```
[야간 배치 (Python)]
  1. daily_sales_agg 갱신 (전날 판매)
  2. 외부 데이터 수집 (기온, IPC)
  3. 예측 모델 실행 (테넌트별)
  4. attribute_performance / production_recommendations 저장
  5. forecast_runs 기록

[API (Node.js)] → 요약 테이블만 조회
[앱 (Flutter, Riverpod)] → API 결과 표시
```

**커넥션 원칙**
- 배치는 **커넥션 1개**를 열어 테넌트를 순차 처리하고, 끝나면 반드시 닫는다 (`try/finally`).
- 대량 조회는 서버 사이드 커서로 나눠 읽어 메모리와 커넥션 점유 시간을 줄인다.
- 쓰기는 테넌트 단위 트랜잭션 + `COPY` 또는 배치 INSERT로 왕복 횟수를 줄인다.
- API 서버의 기존 pool은 공유하지 않는다. 배치 실행 시간은 트래픽이 적은 새벽(예: 03:00 ART)으로 한다.
- 화면은 계산하지 않고 요약 테이블만 읽는다 → 운영 DB 부하와 pool 낭비 방지.

---

## 8. 예측 모델

| 단계 | 방법 | 비고 |
| --- | --- | --- |
| 기본 | Prophet 또는 SARIMAX (카테고리 단위) | 계절성, 추세, 행사 |
| 외부 변수 | 기온 편차, 실질임금·IPC | 백테스트로 효과 확인된 변수만 사용 |
| 확장 | LightGBM (데이터 충분한 고객사) | 모델·사이즈 단위 |
| 신모델 | 속성 유사도 기반 유사 모델 평균 | k = 3~5 |

1개월 앞은 일기예보가 정확하지 않으므로, 기온은 **시나리오(평년 / 더운 달 / 추운 달)**로만 반영한다.

---

## 9. 검증 (백테스트)

출시 전 반드시 실시하며, 검증 전에는 "검증된 기능"이라고 홍보하지 않는다.

1. 과거 데이터 중 마지막 6개월을 숨긴다.
2. 그 이전 데이터만으로 매달 1개월 앞을 예측한다.
3. 실제 판매와 비교해 MAPE, 편향(bias)을 측정한다.
4. 기본 모델 vs 외부 변수 추가 모델을 비교하고, 개선되지 않은 변수는 제거한다.
5. 생산 추천 기준으로도 평가: "추천대로 만들었다면 잔여 재고와 품절이 얼마였을까"

참고 연구:
- 유럽 온라인 패션 리테일러에서 날씨 반영 시 예측 오차 평균 8.6~12.2% 감소 (Steinker 외, 2017, 단기 일별 예보 기준)
- 캐나다 리테일러에서 날씨 정보가 기본 모델 대비 추가 변동 설명 (Chan & Wahab, 2024)

---

## 10. 단계별 구현 계획

| 단계 | 기간(목표) | 내용 | 완료 기준 |
| --- | --- | --- | --- |
| 0 | 즉시 | 속성 입력 UI + `product_attributes` 테이블 | 신규 모델 100% 속성 입력 |
| 1 | 1개월 | `daily_sales_agg` 배치, 품절 표시 | 2년치 백필 완료 |
| 2 | 2개월 | 속성 조합 성과 분석 화면 | 파일럿 고객사 1곳 사용 |
| 3 | 3개월 | 기존 모델 생산 추천 (기본 모델) + 백테스트 | MAPE 측정 완료 |
| 4 | 4개월 | 신모델 초기 수량 추천 + 재생산 알림 | 파일럿 시즌 1회 운영 |
| 5 | 이후 | 기온·물가 시나리오, 외부 쇼핑몰 동향 | 백테스트에서 개선 확인 |

---

## 11. 주의할 함정

1. **변수 과잉**: 정세·분위기 변수를 많이 넣으면 과거에는 잘 맞고 미래는 나빠진다.
2. **인플레이션 착시**: 금액이 아니라 수량으로 예측해야 한다.
3. **품절 데이터 왜곡**: 못 판 날을 안 팔린 날로 학습하면 수요를 과소평가한다.
4. **속성 입력 누락**: 속성이 비면 신모델 추천과 분석이 모두 무력화된다. 등록 시 필수 입력으로 강제한다.
5. **추천 맹신**: 근거(참고 모델, 시나리오)를 항상 함께 보여주고 최종 결정은 사용자가 하도록 한다.

---

## 12. 점검 포인트

- **1주일 후**: 속성 항목(값 목록) 확정, 파일럿 고객사 선정, 기존 테이블 구조 확인
- **1개월 후**: 판매 집계 백필 완료, 품절 표시 정확도 확인
- **3개월 후**: 백테스트 결과로 외부 변수 유지 여부 결정, 파일럿 고객사 피드백 반영

---

## 13. 미결 질문

- 기존 판매 데이터가 모델·사이즈·색상 단위로 저장되어 있는가?
- 품절 이력을 재구성할 수 있는 재고 이력이 있는가?
- 속성 값 목록을 Ventago가 표준으로 제공할지, 고객사가 직접 정의할지?
- 신모델 1차 생산 비율(50~60%)을 고객사별로 설정 가능하게 할지?
- 파일럿 고객사는 누구로 할지?
