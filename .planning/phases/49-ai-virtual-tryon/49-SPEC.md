# SPEC: Phase 49 — AI Virtual Try-On
생성일: 2026-06-29

## 목표

사용자 사진으로 카탈로그 옷을 가상 착용해보고, 상황(파티/회사/데이트/산책)에 맞는 옷을 추천하고 구매로 잇는다. AI 합성은 외부 API(FASHN.ai 등)를 `TryOnProvider` 추상화 뒤에 두고, 비용·프라이버시·옷 이미지 품질을 관리한다.

## 배경 및 컨텍스트

상세는 `49-CONTEXT.md`. 핵심:
- 코드 위치: `api-ventago/src/app/tryon/` (추상화 + 스텁 + 컨트롤러)
- 추상화 계약: `TryOnProvider.tryOn({ personImage, garmentImage }) → { resultImageDataUrl, isStub, ... }`
- 옷 이미지: 상품 MinIO 이미지(`image_url`/`image_urls`), 업로드는 기존 CodigoVista 갤러리 사용
- 프론트: tienda-app 상품 카드/상세의 "Probar"
- 병목: 카탈로그 옷 이미지 부재(데이터 작업) — AI 아님

## 기술 스택

- NestJS 11 + TypeScript. 업로드 multer(FileInterceptor). MinIO `getObjectStream`.
- 외부 API: FASHN.ai(1순위) — axios, per-call key, 이미지 URL/base64 입력.
- 추천(후속): occasion 태깅 + 규칙기반 → 임베딩(pgvector) 고도화.

## 태스크 목록 (Waves)

### Wave 49-01 — PoC (추상화 + 스텁) ✅ 완료
- [x] `TryOnProvider` 인터페이스 + `StubTryOnProvider`
- [x] 독립 PoC: `GET/POST /api/public/shop/tryon` (업로드 폼 + 합성)
- [x] 카탈로그 연결: `POST /tryon/from-product/:storeId/:productId` (+ NO_PRODUCT_IMAGE 가드)
- [x] 사람 사진 미저장(프라이버시), 이미지 타입/크기(≤12MB) 검증
- [x] tienda-app(T8) "Probar" 모달 연결 (단일 HTML 스토어프론트엔 구현됨)

### Wave 49-02 — 실제 합성 어댑터 (FASHN.ai) ⬜
- [ ] `FashnTryOnProvider implements TryOnProvider` — `/v1/run` 호출(person+garment), 폴링/결과 수신
- [ ] env: `FASHN_API_KEY`, 타임아웃/재시도, 토큰 마스킹 로그
- [ ] `TRYON_PROVIDER` 바인딩을 stub→fashn 으로 교체(또는 env 토글)
- [ ] 비용 가드레일: 결과 캐싱(person+garment 해시), 미리보기 저해상도/구매전 고해상도

### Wave 49-03 — 옷 이미지 품질 파이프라인 ⬜ (데이터 의존)
- [ ] 누끼/배경제거 권장 가이드 + (선택) 자동 처리
- [ ] try-on 적합 이미지 플래그(상품별 "가상착용 가능" 표시)
- [ ] 베타 매장 상품 N개에 정면컷 확보(운영 작업)

### Wave 49-04 — 상황별 추천 ⬜
- [ ] 상품 occasion 태그(파티/캐주얼/포멀/데이트) — 스키마 + 입력 UI
- [ ] 규칙기반 추천 v0: occasion 필터 + 색 조화 + 재고 → 후보 3벌
- [ ] (후속) 임베딩 유사도(pgvector)

### Wave 49-05 — 프라이버시 & 컴플라이언스 ⬜
- [ ] 사진 미저장 정책 명문화 + 업로드 동의 고지(프론트)
- [ ] (실제 API 전송 시) 외부 전송 고지 + 처리 후 폐기 보장

### Wave 49-06 — tienda-app 정식 통합 ⬜
- [ ] tienda-app 상품 상세/카드 "Probar" 컴포넌트(T8) — from-product 호출
- [ ] 결과 표시 + "장바구니 담기" 연결

## 완료 기준

- (49-02) 실제 옷 이미지가 있는 상품에서 person 업로드 → **실제 합성 이미지** 반환(스텁 아님)
- 비용/지연/품질 수치 측정 + 캐싱으로 호출 절감
- 사람 사진 미저장 보장(코드 + 고지)
- tienda-app 에서 상품 → Probar → 결과 → 구매 흐름 완주

## 금지사항 / 주의사항

- 사람 사진 저장 금지(메모리 처리 후 폐기) — 실제 API 전송도 최소·고지.
- API 키 평문 로그 금지(마스킹).
- 옷 이미지 없는 상품에 try-on 강요 금지(가드 유지).
- 추천은 occasion 태그 데이터 없이는 작동 안 함 — 데이터부터.
