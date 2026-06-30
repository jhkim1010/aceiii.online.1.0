# Shop 디자인·기능 제안서 — TiendaNube 벤치마크 (Phase 51)

작성일: 2026-06-29
대상: `shop.coolsistema.com`(공개몰, tienda-app)
방법: 아르헨티나 1위 이커머스 **TiendaNube(Nuvemshop)** 의 스토어프론트 구조·기능 연구 → Ventago shop 적용 제안 + 기능별 예상 개발시간

---

## 1. TiendaNube 연구 요약 (스토어프론트 관점)

**전체 구조 (스토어프론트):**
- **홈**: 이미지 캐러셀 배너(히어로/프로모/카테고리 배너) + 카테고리 이미지 + 추천/컬렉션 섹션. 캠페인용 랜딩페이지를 코드 없이 생성.
- **내비**: 카테고리 트리(메뉴/서브메뉴), 브레드크럼.
- **카탈로그/카테고리 페이지**: 상품 그리드 + 필터(가격/색/사이즈/재고) + 정렬.
- **상품 상세**: 갤러리, **variants를 버튼으로**(색/사이즈, 최대 1000 변형), **할부(cuotas) 표시**(무이자/이자/은행 프로모, 변형 변경 시 갱신), 프로모가·**할인% 배지**, 관련 상품, **빠른구매 팝업**, **WhatsApp 버튼**, **JSON-LD 구조화 데이터**(SEO).
- **체크아웃**: 고승인 "가속 체크아웃", 결제수단 순서 지정, 할부, MercadoPago 등.
- **테마**: **Mobile-first** 후 데스크탑 적응, 작은 컴포넌트 단위.
- **전환/마케팅**: ChatNube(WhatsApp AI 챗), TikTok Shop 등 소셜커머스 연동, 프로모션 엔진, 쿠폰, AI 디자인 에디터.

**핵심 시사점:** TiendaNube의 강점은 (a) **mobile-first 테마**, (b) **variant·할부·프로모를 상품 페이지에서 명확히**, (c) **전환 장치(WhatsApp·빠른구매·할인배지)**, (d) **SEO(JSON-LD·카테고리 트리·브레드크럼)** 입니다. 이 4가지가 Ventago shop이 따라가야 할 기준선입니다.

> 우리의 **차별화**: TiendaNube에 없는 **AI 가상 피팅(Phase 49)**. 이게 우리 shop의 "한 방"입니다.

---

## 2. Ventago shop 현재 상태 매핑

| 영역 | 현재 (Phase 51) | TiendaNube 대비 격차 |
|---|---|---|
| 카탈로그 API | ✅ 목록/상세/검색(ILIKE)/카테고리 | 필터(색·사이즈·가격), 정렬 부족 |
| 카테고리 | ✅ 글로벌 통일(매장무관) | 트리/서브메뉴·브레드크럼 부족 |
| 상품 상세 | ⬜ (tienda-app T5 대기) | variants·할부·관련상품·갤러리 |
| 체크아웃 | ✅ 주문+재고+MP preference | 할부 표시, 쿠폰, 가속 UX |
| 결제 확정 | ⬜ MP 웹훅 | 승인→주문 paid |
| 프론트 | 단일 HTML + tienda-app 스캐폴드 | mobile-first 정식 테마 |
| 차별화 | ✅ AI 피팅(from-product) | (TiendaNube에 없음 — 우위) |

---

## 3. 기능 제안 + 예상 개발시간

> 전제: 1인 개발, tienda-app(Next.js 13) + 기존 공개 API 재사용. "백" = api-ventago 추가 작업 포함. 시간은 설계·구현·기본 검증 포함(1일=6작업시간 가정).

### A. 홈 / 내비게이션
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| A1 | Header + 카테고리 메뉴/서브메뉴(글로벌 카테고리 기반) | MVP | 6–10h |
| A2 | 히어로/프로모 배너 캐러셀 + 배너 설정(작은 backend config) | P2 | 10–16h |
| A3 | 브레드크럼(홈>카테고리>상품) | MVP | 2–3h |
| A4 | 홈 추천/컬렉션 섹션(신상·인기) | P2 | 6–10h |

### B. 카탈로그 / 필터
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| B1 | 상품 그리드 + 페이지네이션(반응형 정리) | MVP | 4–6h |
| B2 | 필터 UI(가격/색/사이즈/성별/카테고리) | MVP | 10–16h |
| B2-백 | 카탈로그 API 필터 확장(color/size/price range) | MVP | 6–10h |
| B3 | 정렬(가격↑↓/신상) | MVP | 3–5h |
| B4 | 무한스크롤 또는 "더 보기" | P2 | 3–5h |

### C. 상품 상세 (핵심 전환)
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| C1 | SSR 상세 + 이미지 갤러리(imageUrls) + 메타/OG | MVP | 8–12h |
| C2 | **Variants 버튼**(색/사이즈 선택→변형 해석) | MVP | 12–20h |
| C2-백 | 상품 variants API 노출(parent/variants·stock) | MVP | 8–12h |
| C3 | **할인% 배지 + 프로모가**(price_orig 활용) | MVP | 3–5h |
| C4 | **할부(cuotas) 표시**(MP 할부정보 or 설정 기반) | P2 | 6–10h |
| C5 | 관련 상품(같은 카테고리) | P2 | 4–6h |
| C6 | **AI 가상 피팅 "Probar"**(from-product 연결) ⭐차별화 | MVP | 6–10h |
| C7 | WhatsApp 문의 버튼(딥링크) | MVP | 2–3h |
| C8 | JSON-LD 구조화 데이터(Product) | P2 | 3–5h |

### D. 장바구니 / 체크아웃
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| D1 | 장바구니(Context, 드로어/페이지) | MVP | 8–12h |
| D2 | 체크아웃 폼 + MP init_point 리디렉션 | MVP | 8–12h |
| D3 | 결제 결과 라우트(success/failure/pending) | MVP | 4–6h |
| D4 | **MP 웹훅(승인→주문 paid + mirror)** [백] | MVP | 6–10h |
| D5 | 쿠폰/할인코드 | P3 | 8–12h |
| D6 | 게스트/회원 + 주문조회 | P2 | 12–18h |

### E. 검색
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| E1 | 검색창 + 결과(현 ILIKE 활용) | MVP | 4–6h |
| E2 | 자동완성/추천어(suggest 엔드포인트) | P2 | 8–14h |
| E3 | tsvector+GIN 전문검색 [백] | P2 | 4–6h |

### F. 전환 / 마케팅
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| F1 | 빠른구매 팝업 | P2 | 5–8h |
| F2 | 프로모션 표시(기존 discounts 모듈 연계) | P2 | 10–16h |
| F3 | 장바구니 이탈/리마케팅(픽셀·이벤트) | P3 | 6–10h |
| F4 | 소셜커머스(인스타/TikTok 피드 export) | P3 | 12–20h |

### G. SEO / 성능 / 디자인
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| G1 | sitemap.xml + robots + 메타 표준화 | MVP | 4–6h |
| G2 | next/Image 최적화 | MVP | 3–5h |
| G3 | Lighthouse 성능/접근성 패스 | P2 | 4–8h |
| G4 | **Mobile-first 테마/디자인 시스템**(반응형·토큰) | MVP | 8–14h |

### H. 인프라 / 배포
| # | 기능 | 우선 | 예상시간 |
|---|---|---|---|
| H1 | tienda-app Dockerfile/compose + shop 서브도메인 | MVP | 6–10h |
| H2 | CI(Jenkins/Actions) | MVP | 4–8h |
| H3 | 공개 트래픽 pool 격리 부하검증 | MVP | 3–5h |

---

## 4. 합계 (대략, 1인 기준)

| 묶음 | 시간 합 | 환산(1일=6h) |
|---|---|---|
| **MVP** (TiendaNube 동급 핵심 + AI 차별화) | **약 130–200h** | **약 4.5–7주** |
| **P2** (할부·자동완성·프로모·배너·회원) | 약 90–150h | 약 3–5주 |
| **P3** (쿠폰·리마케팅·소셜커머스) | 약 30–55h | 약 1–2주 |

> 이미 만들어진 것(카탈로그 API·체크아웃·카테고리·격리 pool·tienda-app 스캐폴드·AI from-product)은 위에서 제외했거나 "연결" 시간만 반영했습니다. 풀 MVP가 4.5~7주인 이유는 상품 상세(특히 variants)와 정식 mobile-first 테마가 큰 덩어리이기 때문입니다.

---

## 5. 디자인 방향 제안

- **Mobile-first** (TiendaNube 표준). 핸드폰에서 그리드 2열, 큰 썸네일, 하단 고정 장바구니.
- **이미지 중심·밝은 톤 검토**: 현재 단일 HTML은 다크 네이비+골드(앱/관리자 느낌). 공개 B2C는 보통 **밝고 상품 이미지가 주인공**인 톤이 전환에 유리. → 브랜드 골드는 액센트로 유지하되, 배경은 밝게/중립으로 가는 안을 A/B 검토 권장.
- **전환 장치 표준 탑재**: 할인 배지, 할부 안내, WhatsApp 버튼, 빠른구매 — TiendaNube가 검증한 패턴.
- **차별화 강조**: 상품 상세·카드에서 **"Probar(가상 피팅)"** 를 1급 액션으로 노출(우리만의 무기).

---

## 6. Phase 51 Wave 매핑 (권장 순서)

1. **Wave 51-06 정식 프론트(MVP)**: C1·C2·C6·D1·D2·D3·B1·B2·A1·A3·G1·G2·G4 — TiendaNube 동급 + AI.
2. **Wave 51-05 결제 루프**: D4(MP 웹훅).
3. **Wave 51-07 배포**: H1·H2·H3 + 운영 마이그레이션.
4. **P2 이후**: 할부(C4)·자동완성(E2)·프로모(F2)·배너(A2)·회원(D6).

---

## 부록 — 출처

- TiendaNube 공식: [tiendanube.com](https://www.tiendanube.com/), [체크아웃 도움말](https://ayuda.tiendanube.com/es_ES/123367-opciones-del-checkout), [디자이너 문서(Store)](https://docs.tiendanube.com/help/store)
- 상품/변형/할부 디자이너 문서: [Product](https://docs.tiendanube.com/help/product), [Product variant](https://docs.tiendanube.com/help/product-variant), [Variantes como botones](https://docs.tiendanube.com/help/variantes-como-botones-jq-nuvem), [Cuotas](https://docs.tiendanube.com/help/informacin-de-medios-de-pago-y-cuotas-jq-nuvem), [JSON-LD](https://docs.tiendanube.com/help/data-estructurada-json-ld), [Promociones](https://docs.tiendanube.com/help/promociones)
- 테마/구조: [base-theme (GitHub)](https://github.com/TiendaNube/base-theme), [API Resources](https://tiendanube.github.io/api-documentation/resources)
- UX 베스트프랙티스: [Baymard — Navigation](https://baymard.com/blog/ecommerce-navigation-best-practice), [The Good — Product Filters](https://thegood.com/insights/ecommerce-product-filters/)
