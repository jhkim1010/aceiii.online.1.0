# Phase 49 — AI Virtual Try-On (CONTEXT)

> **유형**: 신규 기능 (확장 로드맵 방향 ②)
> **선행**: 공개몰 카탈로그/체크아웃 API (spec-shop-mvp) ✅, tienda-app 프론트(진행중)
> **관련 문서**: `future proyect/00-expansion-strategy-roadmap.md`(방향 ②), `.gsd/spec-tienda-app.md`(T8)
> **작성일**: 2026-06-29 · **갱신**: 2026-07-10 (B트랙 vendedor 추가)
> **번호 주의**: Phase 46(Shopify)/47(Empretienda)/48(WC 통일)은 멀티플랫폼 싱크 마스터플랜에 예약됨 → 본 기능은 **49**.

---

## 1. 왜 이 phase 인가

사용자가 사진을 올리면 옷을 가상으로 입어보고, 상황(파티/회사/데이트/산책)에 맞는 옷을 추천·구매까지 잇는 기능. 로드맵 방향 ②. 결제(MP)보다 먼저 검증하기로 결정(사용자, 2026-06-29).

**핵심 통찰(검증됨):** AI 모델 자체는 어렵지 않다 — 상용 API(FASHN.ai 등)를 호출만 한다. **진짜 병목은 "옷 이미지"** 다. 현재 카탈로그 이미지가 거의 없음(store 25 = 0장, 전체 483 중 22장). 즉 이 phase 의 난이도는 AI 가 아니라 *데이터(상품 사진·태깅)* 와 *비용/프라이버시* 에 있다.

## 2. 이미 구현된 것 (Wave 49-01 = PoC, ✅ 완료)

위치: `api-ventago/src/app/tryon/`
- `TryOnProvider` 추상화(`tryon-provider.interface.ts`) — 결제(PaymentProvider)와 동일 패턴. 실제 API 는 어댑터 교체만.
- `StubTryOnProvider` — 비용 0, 외부호출 0. 배관 검증용(사람 사진 그대로 반환).
- 독립 PoC: `GET /api/public/shop/tryon`(업로드 폼 HTML) + `POST`(person+garment → 결과).
- 카탈로그 연결: `POST /api/public/shop/tryon/from-product/:storeId/:productId`(person 사진 + 상품 MinIO 이미지). 이미지 없으면 `NO_PRODUCT_IMAGE` 가드.
- **프라이버시**: 사람 사진 미저장(메모리 처리 후 폐기).
- tienda-app(T8)에서 상품 카드 "Probar" 로 연결 예정.

## 3. 외부 API 현황 (조사 완료, 2026)

- **FASHN.ai** — API-first, 1,800만 학습 예제, 이미지당 ~$0.04–0.075. 개발자 통합 최적(권장 1순위).
- 대안: Pixelforge VTON(풀바디 <800ms, 동기/비동기), Perfect Corp Fashion API(엔터프라이즈), Google Vertex AI try-on 계열.
- 공통: 입력은 사람 이미지 + 옷 이미지(URL 또는 base64). 직접 모델 학습 불필요.
- **2026-07-10 재조사(제안서)**: FASHN v1.6 = 1크레딧/장, on-demand $0.075(최소 $7.50), Tier I $19/282cr·Tier II $249/4,150cr. **flat-lay(펼침 사진) 입력 지원** — 카탈로그 이미지 부재를 현장 촬영으로 우회 가능. 스타일 추천용 비전 LLM 은 Gemini 3 Flash(입력 ~$0.50/1M) — 483개 전체 태깅 <$1, 고객 1명 분석 <$0.01.

## 4. 제약 / 주의

- **옷 이미지 품질**이 결과 정확도에 직결 — 누끼(배경제거)/정면컷 표준화 필요.
- **단가 과금** — 호출당 비용. 캐싱(같은 person+garment 재사용), 미리보기 저해상도 단계화 필요.
- **프라이버시** — 사람 얼굴/신체는 민감정보. 저장 최소화·동의 고지·처리 후 폐기(현재 미저장 유지). 아르헨티나 Ley 25.326.
- 상품 이미지 업로드는 이미 존재(`CodigoVistaView`/`BasicDataCard` 다중 갤러리 → MinIO). 신규 개발 불필요.

## 5. B트랙 — 판매원(vendedor) 앱 매장 내 판매촉진 (2026-07-10 추가)

> 제안서: `future proyect/49-vendedor-tryon-vto-proposal.md` (비용·아키텍처·함정·점검 포인트 상세)

A트랙(tienda-app 공개몰 고객 셀프 피팅)과 별도로, **매장 판매원이 고객 동의하에 사진 1장을 찍어** 두 기능을 제공한다:

- **B-1 가상 피팅**: 고객 사진 + 매장 옷 → 착용 모습 렌더 (FASHN, 기존 TryOnProvider 재사용). 사진 1회 촬영으로 여러 벌 반복 — 시착의 한계비용을 0으로.
- **B-2 AI 스타일리스트**: 같은 사진 1장 → 비전 LLM 이 체형/퍼스널컬러/무드 프로필 추출(세션 메모리만, DB 저장 금지) → 지점 재고 상품의 `ai_attributes`(JSONB, 사전 배치 태깅)와 매칭 → 상위 5벌 + 스페인어 판매 멘트. **VTO 가 아니라 비전 LLM+매칭으로 푼다** — 추천(선별)과 피팅(시각화)의 2단 파이프라인.

**선순환 루프**: 이미지 없는 상품은 판매원 flat-lay 촬영으로 즉석 피팅 → 잘 찍힌 사진은 원탭으로 상품 이미지 등록 → 카탈로그(Phase 51 자산)가 현장에서 채워짐. `tryon_events`(사진 X, seller+product 만) = 구매 의도 데이터 → 향후 추천 랭킹 학습.

**의존성**: vendedor 인증 전환(`spec-vendedor-app-device-operario-auth.md`, 기기키+Seller PIN) **선행 머지** → 그 위에 `/vendedor/tryon`·`/vendedor/stylist` (x-device-key + x-seller-id 가드).

**B트랙 고유 주의**:
- 체형/피부톤 분석 결과 노출 금지 — 출력은 긍정형 추천 멘트만(프롬프트에서 형식 강제).
- 지점(branch) 재고 필터 1순위. 단 재고 0 차단 금지(기존 정책) — "다른 지점 재고" 표시만.
- 레이트리밋(기기당 동시 2건) + 일일 한도 — 비용 폭주 방지.
- pool 안전: DB 조회(커넥션 반환) 완료 후 외부 HTTP 호출. 현 ShopTryOnService 구조가 이미 올바름 — 유지.
