# SPEC: Phase 49 — AI Virtual Try-On
생성일: 2026-06-29 · 갱신: 2026-07-10 (B트랙 vendedor waves 49-07~49-11 추가)

## 목표

사용자 사진으로 카탈로그 옷을 가상 착용해보고, 상황(파티/회사/데이트/산책)에 맞는 옷을 추천하고 구매로 잇는다. AI 합성은 외부 API(FASHN.ai 등)를 `TryOnProvider` 추상화 뒤에 두고, 비용·프라이버시·옷 이미지 품질을 관리한다.
**B트랙(2026-07-10)**: 매장 판매원이 고객 동의하에 사진 1장으로 ①가상 피팅 ②AI 스타일 추천을 제공하는 매장 내 판매촉진 시스템 (`future proyect/49-vendedor-tryon-vto-proposal.md`).

## 배경 및 컨텍스트

상세는 `49-CONTEXT.md`. 핵심:
- 코드 위치: `api-ventago/src/app/tryon/` (추상화 + 스텁 + 컨트롤러)
- 추상화 계약: `TryOnProvider.tryOn({ personImage, garmentImage }) → { resultImageDataUrl, isStub, ... }`
- 옷 이미지: 상품 MinIO 이미지(`image_url`/`image_urls`), 업로드는 기존 CodigoVista 갤러리 사용
- 프론트: A트랙 tienda-app "Probar" / B트랙 mobile-sales-app(Flutter) "Prueba Virtual"
- 병목: 카탈로그 옷 이미지 부재(데이터 작업) — AI 아님. B트랙 flat-lay 촬영이 우회+축적 루프.

## 기술 스택

- NestJS 11 + TypeScript. 업로드 multer(FileInterceptor). MinIO `getObjectStream`.
- 외부 API: FASHN.ai v1.6(합성, 1순위) + Gemini 3 Flash(비전 분석/태깅, StylistProvider 뒤에 격리) — axios, per-call key.
- 추천: LLM 배치 태깅(`products.ai_attributes` JSONB) + SQL 재고 필터 + LLM 리랭크. (pgvector 는 수천 SKU 부터 — 후속)
- 모바일: Flutter mobile-sales-app (despacho-app 패턴: config.dart, api_service x-device-key).

## 태스크 목록 (Waves)

### A트랙 — 공개몰(tienda-app) 고객 셀프 피팅

#### Wave 49-01 — PoC (추상화 + 스텁) ✅ 완료
- [x] `TryOnProvider` 인터페이스 + `StubTryOnProvider`
- [x] 독립 PoC: `GET/POST /api/public/shop/tryon` (업로드 폼 + 합성)
- [x] 카탈로그 연결: `POST /tryon/from-product/:storeId/:productId` (+ NO_PRODUCT_IMAGE 가드)
- [x] 사람 사진 미저장(프라이버시), 이미지 타입/크기(≤12MB) 검증
- [x] tienda-app(T8) "Probar" 모달 연결 (단일 HTML 스토어프론트엔 구현됨)

#### Wave 49-02 — 실제 합성 어댑터 (FASHN.ai) ⬜ ← A/B트랙 공통 선행
- [ ] (선행, 코드 전) FASHN 계정 + $7.50 충전 → 실물 매장 옷 2~3장 수동 품질검증. 불합격 시 어댑터 방향 전환(Kling/Gemini) — 여기서 멈춤
- [ ] `FashnTryOnProvider implements TryOnProvider` — `/v1/run` 호출(person+garment), 폴링/결과 수신
- [ ] env: `FASHN_API_KEY`, `TRYON_PROVIDER=stub|fashn` 토글, 타임아웃/재시도, 토큰 마스킹 로그
- [ ] 비용 가드레일: 결과 캐싱(person+garment 해시), 미리보기 저해상도/구매전 고해상도

#### Wave 49-03 — 옷 이미지 품질 파이프라인 ⬜ (데이터 의존)
- [ ] 누끼/배경제거 권장 가이드 + (선택) 자동 처리
- [ ] try-on 적합 이미지 플래그(상품별 "가상착용 가능" 표시)
- [ ] 베타 매장 상품 N개에 정면컷 확보(운영 작업) — B트랙 flat-lay 등록 루프(49-07)가 대체 공급원

#### Wave 49-04 — 상황별 추천 → **49-08/49-09 로 흡수** (LLM 태깅이 occasion 포함)
- ~~규칙기반 occasion 추천 v0~~ → B트랙 스타일리스트(49-08 태깅 + 49-09 리랭크)로 통합 구현, tienda-app 은 49-06 에서 재사용

#### Wave 49-05 — 프라이버시 & 컴플라이언스 ⬜
- [ ] 사진 미저장 정책 명문화 + 업로드 동의 고지(프론트, ES) — B트랙 동의 화면(49-10)과 문구 공유
- [ ] (실제 API 전송 시) 외부 전송 고지 + 처리 후 폐기 보장. FASHN/Google 데이터 보존 정책 확인

#### Wave 49-06 — tienda-app 정식 통합 ⬜
- [ ] tienda-app 상품 상세/카드 "Probar" 컴포넌트(T8) — from-product 호출
- [ ] 결과 표시 + "장바구니 담기" 연결 + (후속) "Te recomendamos" 49-09 재사용

### B트랙 — 판매원(vendedor) 앱 매장 판매촉진 (2026-07-10 추가)

> 실행용 GSD SPEC: `.gsd/spec-phase49-vendedor-ai.md` · 선행: 49-02 + vendedor 인증 전환 머지

#### Wave 49-07 — vendedor 피팅 엔드포인트 🔶 착수(2026-07-14)
- 인증 정합 변경: 판매원 앱이 x-device-key 대신 **mobile JWT(email+password)** 로 전환됨 → 엔드포인트도 `POST /mobile/tryon/*` + AuthGuard('jwt') 로 구현(commit api af95e8a).
- [x] `POST /mobile/tryon/from-product/:productId`(multipart 'person', JWT, storeId=req.user, stub 백엔드) — ShopTryOnService 재사용
- [ ] `POST /mobile/tryon/from-upload`(flat-lay) — 미구현
- [ ] tryon_events 마이그레이션 / 레이트리밋 / 일일한도 — 미구현
- [ ] 앱 UI(image_picker + "Prueba Virtual" 버튼 + result 화면) — 미착수(image_picker 의존성+권한 필요)
- 잔여 블로커: 49-02 FASHN 실합성(계정+$), 카탈로그 이미지 22/483, tryOnFromProduct 의 isPublishedShop=true 제약(vendedor 는 미공개 상품도 필요할 수 있음)
- [ ] (구계획) x-device-key+x-seller-id 가드 — 인증 전환으로 폐기
- [ ] `tryon_events` 마이그레이션(SERIAL, `ALTER OWNER TO coolsistema`) — 사진 저장 X, seller/product/모드만
- [ ] 레이트리밋(기기당 동시 2) + 일일 한도(env) + flat-lay 사진 상품 이미지 등록 제안 API
- [ ] (옵션) WhatsApp 공유용 MinIO TTL 24h 임시 저장 + 자동 삭제 스케줄러

#### Wave 49-08 — 카탈로그 AI 태깅 ⬜
- [ ] `products.ai_attributes` JSONB 마이그레이션(ALTER OWNER 포함)
- [ ] 태깅 프롬프트 설계 + 20개 수동 검증 → `ai-catalog-tagger` 배치(전 상품 <$1) + 신규상품 저장 훅
- [ ] 이미지 없는 상품은 텍스트(이름/카테고리)만 부분 태깅

#### Wave 49-09 — AI 스타일리스트 엔드포인트 ⬜
- [ ] `StylistProvider` 추상화(비전 LLM 벤더 격리, Gemini 어댑터)
- [ ] `POST /vendedor/stylist/analyze` — 고객 사진 → 프로필(세션 응답만, DB 저장 금지)
- [ ] `POST /vendedor/stylist/recommend` — 지점 재고 SQL 필터(20~30 후보) → LLM 리랭크 5벌 + ES 판매 멘트(긍정형 강제)

#### Wave 49-10 — Flutter 화면 (mobile-sales-app) ⬜
- [ ] 동의 화면(ES 고지+탭 기록) → 촬영 → 상품 선택(바코드/검색/flat-lay 촬영) → VTO 결과
- [ ] "Recomendar looks" 버튼 → 추천 카드 5개 → 탭 → 즉시 VTO
- [ ] 같은 세션 사진 재사용(재촬영 없이 N벌), WhatsApp 공유(옵션)

#### Wave 49-11 — 파일럿 & 측정 ⬜
- [ ] 1개 지점 파일럿(판매원 1~2명), tryon_events ↔ 판매 전환율 측정 쿼리
- [ ] 1주/1개월 점검(제안서 §6): 품질 합격률, P95 지연 ≤12s, 월 비용 실측 → 확대/Tier 약정 판단

## 완료 기준

- (49-02) 실제 옷 이미지 상품에서 person 업로드 → **실제 합성 이미지** 반환(스텁 아님)
- (B트랙) 판매원이 사진 1장 촬영 → 추천 5벌 ≤10s → 탭 → 피팅 렌더 ≤12s, 고객 1명 풀코스 <$0.25
- 비용/지연/품질 수치 측정 + 캐싱·한도로 호출 절감. ESLint 오류 0.
- 사람 사진 미저장 보장(코드 + 고지). 체형 분석 원문 미노출.
- tienda-app 상품 → Probar → 결과 → 구매 흐름 완주(A트랙)

## 금지사항 / 주의사항

- 사람 사진·체형 프로필 저장 금지(메모리 처리 후 폐기) — 실제 API 전송도 최소·고지.
- API 키 평문 로그 금지(마스킹).
- 옷 이미지 없는 상품에 try-on 강요 금지(가드 유지) — 단 B트랙은 flat-lay 로 우회 제공.
- 재고 0 상품 차단 금지(기존 정책) — 추천은 지점 재고 우선, 타지점은 표시만.
- 신규 테이블/컬럼 마이그레이션 끝에 `ALTER OWNER TO coolsistema` 필수(운영 500 방지). PG SERIAL.
- 운영 DDL 은 승인 게이트 — 로컬 먼저.
- DB 커넥션/트랜잭션 보유 상태에서 외부 API 호출 금지(pool 낭비).
