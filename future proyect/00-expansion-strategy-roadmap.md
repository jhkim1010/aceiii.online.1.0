# Ventago 확장 전략 & 기술 로드맵

> **세 가지 확장 방향**
> ① `shop.coolsistema.com` — 공개 B2C 쇼핑몰
> ② AI 가상 피팅 + 상황별 코디 추천 + 구매 연결
> ③ **CoolPay** — MercadoPago 처럼 자금을 직접 관리하는 자체 결제 시스템
>
> 작성일: 2026-06-29 · 성격: 전략 + 기술 로드맵 · 대상 시스템: Ventago (NestJS 11 / Next.js 13 / PostgreSQL)

---

## 0. 한눈에 보는 결론

| 방향 | 실현 가능성 | 난이도 | 핵심 병목 | 권장 착수 시점 |
|---|---|---|---|---|
| ① 공개 쇼핑몰 | **매우 높음** (백엔드 70% 무장됨) | 중 | 카탈로그 메타데이터 빈약, 공개 트래픽용 pool 격리 | **지금 (Phase 1)** |
| ② AI 가상 피팅·추천 | **높음** (외부 API 성숙) | 중상 | 제품 이미지 품질, 단가/지연, 추천 데이터 | 쇼핑몰 MVP 직후 |
| ③ CoolPay 자체 결제 | **조건부** — 기술은 가능, **규제가 본질** | 매우 높음 | 아르헨티나 BCRA PSP 등록·자본·컴플라이언스 | 장기 (외부 PSP 우회 먼저) |

**한 줄 요약:** ①은 거의 다 만들어져 있어 "지금 시작"이 맞습니다. ②는 기술이 아니라 *데이터(제품 사진·태그)* 싸움입니다. ③은 코드가 아니라 *라이선스·자본·법무*가 핵심이라 단계적 우회(MP Split → 외부 PSP → 자체 PSP) 전략이 필수입니다.

---

## 0.5 등록된 Phase 현황 (2026-06-29 갱신)

확장 작업을 프로젝트 phase 체계(`.planning/phases/`)에 정식 등록함. **Phase 46~48 은 멀티플랫폼 싱크 마스터플랜(Shopify/Empretienda/WC)에 예약**되어 있어 충돌을 피해 49부터 사용.

| Phase | 이름 | 방향 | 상태 | 위치 |
|---|---|---|---|---|
| **49** | AI Virtual Try-On | ② | Wave 49-01 PoC ✅ / 49-02~06 ⬜ | `.planning/phases/49-ai-virtual-tryon/` |
| **50** | CoolPay (자체 결제) | ③ | 기획만 ⬜ (착수 전 G0 법무 게이트, 그 전 코드 금지) | `.planning/phases/50-coolpay/` |
| **51** | Public Storefront (shop) | ① | 카탈로그·체크아웃·카테고리·단일HTML·tienda-app 스캐폴드 ✅ / 웹훅·정식프론트·배포 ⬜ | `.planning/phases/51-public-storefront/` |
| **52** | Store Manager Mobile App | ④ (신규 트랙) | 기획만 ⬜ | `.planning/phases/52-manager-mobile-app/` |

- 각 phase 는 `NN-CONTEXT.md` + `NN-SPEC.md` + `.gsd/spec-phaseNN-*.md`(포인터) 로 구성.
- **Phase 52(관리자 핸드폰·태블릿 앱)는 원래 3방향 외 추가 트랙** — Phase 37(판매자 vendedor/revendedor 앱)과 구분되는 *관리자/오너* 관제·승인 앱.
- reseller(revendedor) 앱은 **Phase 37 의 revendedor 모드**(토대 Phase 24) — 본 로드맵 트랙과 별개.
- shop 디자인·기능 제안서(TiendaNube 벤치마크 + 기능별 개발시간 추정): `.planning/phases/51-public-storefront/51-tiendanube-proposal.md`.

---

## 1. 이미 무장된 자산 (맨땅이 아님)

코드베이스를 점검한 결과, 세 방향 모두 토대가 상당히 깔려 있습니다.

- **`online_orders` / `online_order_items` 테이블 + Phase 28 파이프라인**: `channel`, `payment_status`, `payment_reference`, `mirror_sale_id`, `stock_held_at`/`stock_released_at`, `shipping_carrier`, `tracking_code` 등 공개 쇼핑몰 주문에 필요한 컬럼이 **이미 존재**합니다. POS 재고·회계와 연결되는 *pending hold + deliver mirror* 패턴까지 구현돼 있습니다 (메모리 `project_phase28_online_integration`).
- **MercadoPago 풀스택 연동**: `mercadopago/` 모듈에 OAuth(**마켓플레이스/split 결제용**), QR, Wallet, Webhook, Refund, Payment Intents 가 모두 구현돼 있습니다. → CoolPay 의 자금흐름 모델(에스크로·정산)을 **MP Split 위에서 먼저 시뮬레이션**할 수 있는 결정적 자산입니다.
- **`marketplace` + `revendedor` 모듈**: 외부 노출·재판매 개념이 이미 도메인에 존재.
- **`products` 카탈로그**: `image_urls`(jsonb 다중 이미지), `publish_marketplace` 플래그, store/category/color/size/season 분류 보유.
- **멀티테넌트(`store_id`) + MinIO 이미지 저장 + 인메모리 캐시 규약** — 공개 트래픽 확장의 기반.

> **반대로 비어 있는 것:** `products.description` 이 `varchar(255)` 로 너무 짧고, 공개몰에 필요한 **slug·SEO·소재·성별·핏·모델착용컷·재고 가시성 정책**이 없습니다. ②의 AI 추천도 이 메타데이터 공백이 가장 큰 적입니다.

---

## 방향 ① — 공개 쇼핑몰 `shop.coolsistema.com`

### 다층 분석 (빌 게이츠식)

- **표면 문제:** "서버에 있는 모든 제품을 방문자가 검색·구매하게 하고 싶다."
- **구조적 원인:** 현재 Ventago 는 *내부 운영자(POS/ERP)* 를 위한 인증 기반 시스템입니다. 모든 데이터 접근이 로그인·세션·`store_id` 격리를 전제로 설계돼 있어, **익명 공개 트래픽**이라는 정반대 접근 패턴이 들어설 자리가 없습니다. 또한 운영 DB pool(min10/max80)은 *내부 동시접속 500명* 기준으로 잡혀 있어, 공개몰의 예측 불가 트래픽이 같은 pool 을 쓰면 POS 가 멈추는 사고로 직결됩니다.
- **근본 본질:** 이것은 "페이지를 하나 더 만드는 일"이 아니라 **읽기 위주·고트래픽·익명·SEO·캐시 친화적**인 *두 번째 종(種)의 시스템*을 *같은 데이터* 위에 얹는 일입니다. 본질은 **읽기 경로(공개)와 쓰기 경로(운영)의 물리적 분리**입니다.

### 실현 가능성: 매우 높음
주문 백엔드가 이미 있으므로, 공개 프론트엔드 + 카탈로그 읽기 API + 결제 연결만 추가하면 MVP 가 섭니다.

### 지금 무장해야 할 것
1. **읽기 전용 공개 API 게이트웨이 분리** — 공개 카탈로그/검색은 별도 NestJS 인스턴스 또는 별도 pool(예: 읽기 전용 replica, pgbouncer transaction 모드)로 격리. *운영 pool 을 절대 공유하지 않습니다.* (CLAUDE.md 의 pool 규약과 직결)
2. **카탈로그 메타데이터 확장** — `products` 에 `slug`, `long_description(text)`, `gender`, `material`, `fit`, `seo_title/seo_desc`, `is_published_shop`, 모델 착용컷 필드 추가(마이그레이션은 PG10/PG15 호환 주의).
3. **검색 인프라** — 초기엔 Postgres `tsvector` + GIN(추가 비용 0), 트래픽 증가 시 Meilisearch/Typesense 도입.
4. **공개 캐시 계층** — CDN(이미지/정적) + Redis(카탈로그 60초 TTL). 이미 인메모리 캐시 규약이 있으니 확장.
5. **결제·배송** — 결제는 기존 MP Checkout 재사용(체크아웃 prefer), 배송은 `online_orders.shipping_carrier`/`tracking_code` 활용.

### 기술 로드맵
- **P1 (MVP, ~4주):** 공개 카탈로그 API(읽기 격리) → Next.js 공개 스토어프론트(SSR/SEO) → 장바구니 → MP Checkout → `online_orders` 기입(기존 파이프라인 재사용).
- **P2 (~4주):** 검색/필터 고도화, 재고 가시성 정책, 회원/게스트 체크아웃, 배송 추적, 리뷰.
- **P3:** 멀티스토어 공개(각 `store_id` 별 서브도메인/테넌트 몰), 프로모션, 장바구니 이탈 리마케팅.

---

## 방향 ② — AI 가상 피팅 + 상황별 추천 + 구매

### 다층 분석 (빌 게이츠식)

- **표면 문제:** "사진 2~3장 올리면 옷 입은 모습을 가상으로 보여주고, 상황(파티/산책/회사/데이트)에 맞는 옷을 추천하고 구매까지."
- **구조적 원인:** 이 기능은 사실 **세 개의 독립 시스템**입니다 — (a) *가상 피팅*(이미지 생성 AI), (b) *상황별 추천*(룰/임베딩 기반 추천 엔진), (c) *구매 연결*(①의 카탈로그·주문). 사람들은 (a)의 화려함에 끌리지만, 실제 사업 가치는 (b)+(c)에서 나오고, (b)는 **제품에 붙은 구조화된 속성 데이터가 없으면 작동하지 않습니다.**
- **근본 본질:** AI 모델은 이미 상품화돼 있어 *살 수 있습니다*. 진짜 자산은 **"이 옷은 파티용/캐주얼/포멀이고, 색·핏·계절·소재는 무엇"이라는 라벨링된 카탈로그**입니다. 즉 본질은 AI 가 아니라 **데이터 정제와 태깅 파이프라인**입니다. AI 는 빌려오고, 데이터는 직접 무장해야 합니다.

### 실현 가능성: 높음
가상 피팅 API 는 2026년 기준 성숙·저렴합니다. 예: **FASHN.ai**(API-first, 1,800만 학습 예제, 이미지당 ~$0.075, 대량 시 $0.04↓), **Pixelforge VTON**(풀바디 800ms 미만, 동기/비동기), **Perfect Corp Fashion API**(엔터프라이즈/800+ 브랜드), **Google Vertex AI** 의 try-on 계열. 직접 모델 학습은 불필요합니다.

### 지금 무장해야 할 것
1. **제품 속성 스키마** — `occasion`(파티/캐주얼/포멀/데이트), `style_tags`, `season_id`(보유), `gender`, `body_fit`, 임베딩 벡터 컬럼(`pgvector` 확장). → ②의 핵심.
2. **고품질 평면/누끼 제품 이미지** — VTON 정확도는 입력 이미지 품질에 정비례. 누끼(배경제거) 파이프라인 표준화.
3. **사용자 사진 처리·프라이버시** — 업로드 2~3장은 **민감정보(얼굴/신체)**. 저장 최소화, 동의 고지, 처리 후 즉시 폐기 정책, MinIO 별도 버킷·암호화.
4. **추천 엔진 v0** — 규칙 기반(occasion 필터 + 색 조화 + 재고)으로 시작 → 이후 임베딩 유사도/협업필터로 고도화.
5. **비용 가드레일** — 피팅 호출당 과금이므로 캐싱(같은 의상+사용자 조합 재사용), 미리보기 저해상도/구매전 고해상도 단계화.

### 기술 로드맵
- **P1 (PoC):** 1개 외부 VTON API 연동 → 사용자 사진 1장 + 상품 1개 합성 → 결과 표시. 비용·지연·품질 측정.
- **P2:** occasion 태깅된 카탈로그 위에 규칙 기반 추천 → "상황 선택 → 후보 3벌 → 가상 피팅 → 장바구니".
- **P3:** 임베딩 추천(pgvector), 사용자 체형·선호 학습, 멀티아이템 코디(상의+하의 동시 피팅).

> **현실 경고:** "사진 2~3장으로 360° 정확한 가상착용"은 아직 마케팅과 실제 사이 간극이 있습니다. **단일 정면 합성 미리보기**로 기대치를 잡고, 환불·사이즈 안내로 보완하는 것이 안전합니다.

---

## 방향 ③ — CoolPay (자체 결제·자금관리 시스템)

### 다층 분석 (빌 게이츠식)

- **표면 문제:** "MercadoPago 가 돈을 직접 굴리듯, 나도 CoolPay 로 자금을 관리하고 싶다."
- **구조적 원인:** MP 가 자금을 "직접 관리"할 수 있는 이유는 코드가 아니라 **규제 자격(BCRA 등록 PSP/PSPCP)** 때문입니다. 타인의 자금을 보관·정산·이체하는 순간, 그것은 소프트웨어 문제가 아니라 **금융 라이선스·자본금·자금세탁방지(AML/KYC)·감사·정보보고 의무**의 문제로 바뀝니다.
- **근본 본질:** CoolPay 의 본질은 "결제 화면"이 아니라 **신뢰를 법적으로 보증하는 라이선스드 금융기관이 되는 것**입니다. 기술 난이도(★★)보다 규제·컴플라이언스·자본 난이도(★★★★★)가 압도적으로 높습니다. 따라서 전략의 핵심은 **"라이선스 없이 갈 수 있는 데까지 먼저 가고, 가치가 검증되면 라이선스로 진입"**하는 단계적 우회입니다.

### 규제 현실 (아르헨티나, 2026)
- BCRA 는 2026-05-06 **Comunicación "A" 8432** 로 PSP 체계를 강화하고 **"PSPCP como Servicio"**(타사 인터페이스를 통해 결제계좌를 제공하는 형태) 범주를 신설했습니다 — 이는 정확히 CoolPay 같은 모델을 겨냥합니다.
- 등록 시 **지분 10%↑ 보유자·실질지배자·임원 전원**의 범죄경력·진술서 제출, 자금세탁방지 체계, 정보보고(régimen informativo) 의무가 부과됩니다.
- 등록 후 영업개시 기한 6→12개월로 연장, 기등록 PSP 는 90일 내 적응 의무.
- 즉 **"자금을 직접 보관·정산"하려면 PSP/PSPCP 등록은 회피 불가**입니다.

### 실현 가능성: 조건부 (기술 가능 / 규제가 관문)
자체적으로 *결제 오케스트레이션·지갑 잔액·정산 원장*을 만드는 것은 기술적으로 가능하고, 이미 MP Split/Wallet 코드가 있어 유리합니다. 그러나 **타인 자금의 직접 커스터디는 법적 자격 없이는 불법 소지**가 있습니다.

### 단계적 우회 전략 (핵심 권장)
1. **Stage 0 — Split/Marketplace (지금 가능, 라이선스 0):** 이미 구현된 MP OAuth Split 으로 *판매자별 자동 분할정산*. 자금은 MP 가 보관, CoolPay 는 *오케스트레이션 레이어*만. → "자금관리"의 80% 경험을 무자격으로 제공.
2. **Stage 1 — 멀티 PSP 어그리게이터:** MP + 타 PSP(예: 카드 게이트웨이)를 추상화한 *CoolPay 결제 라우터*. 원장(ledger)·정산·수수료 관리 로직을 자체 보유하되 *자금은 라이선스드 PSP 가 커스터디*.
3. **Stage 2 — 자체 지갑/잔액(PSPCP):** 거래량·가치 검증 후 BCRA PSPCP 등록 추진 → 진짜 자체 자금관리. **법무·회계·자본 파트너 선결.**

### 지금 무장해야 할 것
1. **이중기입 원장(double-entry ledger) 설계** — 어떤 단계든 필요. 모든 자금 이동을 차변/대변으로 불변 기록(append-only). `payments`, `ledger_entries`, `settlements`, `payouts` 테이블.
2. **PSP 추상화 인터페이스** — MP 를 첫 어댑터로, 이후 교체·추가 가능한 `PaymentProvider` 포트.
3. **멱등성·정합성** — webhook 재처리, 분산 트랜잭션 실패 복구, *돈 관련 코드의 에러핸들링은 무관용*(사용자 규약과 일치).
4. **법무·규제 사전 자문** — Stage 2 진입 전 *반드시* BCRA PSP 전문 로펌(검색된 Marval / Allende & Brea 등) 자문. 자본·임원요건 사전 점검.
5. **AML/KYC 데이터 모델** — 향후 의무화 대비 거래·고객 식별 데이터 구조 미리 설계.

### 기술 로드맵
- **P1:** Stage 0 Split 정산 + 자체 원장 v1(읽기 리포트). 라이선스 불필요.
- **P2:** PSP 라우터 추상화 + 정산/수수료 엔진 + 가맹점 대시보드.
- **P3:** (규제 검토 통과 시) PSPCP 등록 절차 + 자체 잔액/지갑.

---

## 2. 공통 인프라·아키텍처 결정 (세 방향 공통)

- **pool 격리가 1순위 규약:** 공개몰·AI·결제 트래픽은 **운영 POS pool(min10/max80)과 절대 분리.** 읽기는 replica + pgbouncer(transaction pooling), 공개 API 는 별도 인스턴스. (CLAUDE.md 성능규약 준수)
- **Phase 43 commerce-connector 코어 재사용:** 이미 멀티플랫폼 싱크를 추상화 중이므로, 공개몰을 *또 하나의 채널*(`commerce_channels`)로 흡수하면 중복 최소화.
- **이미지·CDN:** MinIO + CDN 프록시. AI 피팅 결과·모델컷도 동일 파이프라인.
- **이벤트 기반:** 주문/결제/재고는 Socket.io + 이벤트로 느슨하게 결합(이미 보유).
- **GSD 워크플로우로 각 Phase 스펙화:** 각 방향을 `gsd` 스킬 Plan→Execute→Review 로 분리 진행(프로젝트 규약).

---

## 3. 지금 당장 실행할 단계별 액션 플랜

1. **(이번 주) 카탈로그 메타데이터 갭 확정** — `products` 에 부족한 공개몰/AI 필드 목록을 `db-schema-tables.md` 대조로 확정하고 마이그레이션 초안(PG10/15 호환) 작성.
2. **(이번 주) 공개 읽기 경로 격리 PoC** — 읽기 전용 DB 사용자 + pgbouncer 또는 별도 인스턴스로 카탈로그 1개 엔드포인트를 운영 pool 밖에서 서빙.
3. **(2주) 쇼핑몰 MVP 스펙** — `gsd` 로 Phase 스펙: 공개 카탈로그 API + Next.js 스토어프론트 + MP Checkout + `online_orders` 연결.
4. **(2주) AI 피팅 PoC** — FASHN.ai 등 1개 API 키 발급 → 사진1+상품1 합성 비용/지연/품질 측정 보고서.
5. **(병행) CoolPay Stage 0** — 기존 MP Split 으로 분할정산 1건 + 자체 원장 테이블 설계 리뷰.
6. **(병행) 규제 자문 미팅 잡기** — BCRA PSP 전문 로펌 1차 상담(자본·임원요건 파악만이라도).
7. **(상시) 마지막 로그파일 확인 후 작업** — 각 변경 전 최신 `#NNN.txt`/Winston 로그 점검(개인 규약).

---

## 4. 빠지기 쉬운 함정 3가지

1. **"공개몰을 운영 시스템에 그냥 끼워넣기"** — 익명 트래픽이 운영 POS pool 을 잠식해 매장 영업이 멈추는 사고. → *읽기 경로 물리적 격리*를 타협하지 말 것. (가장 치명적)
2. **"AI 가 알아서 추천해줄 것"이라는 착각** — occasion·스타일 태그가 없는 카탈로그 위에서는 추천이 작동하지 않습니다. AI 부터 사지 말고 **데이터 태깅부터** 무장. 또 사용자 얼굴/신체 사진을 안일하게 저장하면 프라이버시·법적 리스크.
3. **"CoolPay = 결제 화면 만들기"라는 과소평가** — 타인 자금 커스터디는 라이선스·자본·AML 문제입니다. 라이선스 없이 잔액을 보관하면 규제 위반. → 반드시 *Stage 0 우회 → 가치 검증 → 라이선스* 순서. 코드부터 짜고 법무를 나중에 보는 순서가 최대 함정.

---

## 5. 점검 포인트

### 1주일 후
- 카탈로그 메타데이터 갭 목록 + 마이그레이션 초안 완료?
- 읽기 경로 격리 PoC 가 운영 pool 을 건드리지 않음을 `pg_stat_activity` 로 검증?
- AI 피팅 API 후보 1~2개 선정 + 견적 확보?

### 1개월 후
- 쇼핑몰 MVP: 카탈로그 검색 → 장바구니 → MP 결제 → `online_orders` 기입까지 end-to-end 동작?
- AI 피팅 PoC 합성 1건 성공 + 단가/지연/품질 수치 확보?
- CoolPay 자체 원장 테이블 설계 리뷰 통과? 규제 1차 상담 완료?

### 3개월 후
- `shop.coolsistema.com` 실 트래픽 베타(1개 매장)에서 P95 응답·결제 성공률·운영 pool 무영향 입증?
- occasion 태깅 카탈로그 + 규칙 기반 추천 → 피팅 → 구매 흐름 베타?
- CoolPay Stage 0(MP Split 분할정산) 실거래 + 라이선스 진입 여부 의사결정(go/no-go)?

---

## 부록 — 참고 출처

- Virtual try-on API 현황(2026): [Pixazo — Best Virtual Try-On APIs 2026](https://www.pixazo.ai/blog/best-virtual-try-on-api), [Claid — VTON tools 2026](https://claid.ai/blog/article/virtual-try-on-tools), [Perfect Corp Fashion API](https://yce.perfectcorp.com/ai-api/contents/fashion-api)
- 아르헨티나 BCRA PSP 규제(2026): [BCRA — Registro de PSP](https://www.bcra.gob.ar/en/registry-of-payment-service-providers-psps/), [BCRA Texto ordenado PSP (A 8287)](https://www.bcra.gob.ar/archivos/Pdfs/Texord/t-snp-psp.pdf), [Allende & Brea — Nuevas regulaciones PSP (2026-05)](https://allende.com/fintech/el-banco-central-introduce-nuevas-regulaciones-sobre-proveedores-de-servicios-de-pago-05-14-2026/), [Abogados.com.ar — PSPCP como Servicio](https://abogados.com.ar/index.php/el-bcra-sumo-exigencias-al-regimen-de-proveedores-de-servicios-de-pago-e-incorporo-la-figura-de-pspcp-como-servicio/39246)
- 내부 baseline: `online_orders`/`online_order_items` 테이블, `mercadopago/`(OAuth·QR·Wallet·Webhook·Refund) 모듈, `products`(image_urls·publish_marketplace), 메모리 `project_phase28_online_integration` · `project_phase43_commerce_core`
