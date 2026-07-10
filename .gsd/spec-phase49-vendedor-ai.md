# SPEC: Phase 49 B트랙 — 판매원 앱 AI (가상 피팅 + 스타일 추천)
생성일: 2026-07-10

> 상위 문서: `.planning/phases/49-ai-virtual-tryon/49-CONTEXT.md`(§5) + `49-SPEC.md`(Waves 49-02, 49-07~49-11)
> 제안서(비용·아키텍처 근거): `future proyect/49-vendedor-tryon-vto-proposal.md`
> **선행 조건**: ① FASHN 수동 품질검증 합격(TASK-0) ② vendedor 인증 전환(`spec-vendedor-app-device-operario-auth.md`) 머지 — TASK-4 이후 태스크가 의존

## 목표

판매원이 고객 동의하에 사진 1장을 찍으면 ①매장 옷 가상 피팅(FASHN) ②체형·무드 기반 재고 상품 추천(비전 LLM)을 제공한다. 고객 1명 풀코스 <$0.25, 추천 ≤10s·피팅 P95 ≤12s.

## 배경 및 컨텍스트

- 기존 코드: `api-ventago/src/app/tryon/` — TryOnProvider 포트 + StubTryOnProvider + ShopTryOnService(Product 조회 → MinIO garment → provider 호출). **DB 조회 완료 후 외부 호출하는 현 구조 유지.**
- 병목은 카탈로그 이미지(483중 22장) → flat-lay 업로드 경로 + 상품 이미지 등록 제안 루프로 우회.
- 인증: despacho 모델(x-device-key + x-seller-id). 무거운 세션 테이블 없음.
- Sellers 모델 `tableName 'Sellers'`(SQL 케이스민감), 재고는 `"ProductBranch"`(운영 PascalCase quoted — `.planning/intel/db-schema-tables.md` 먼저 확인, 추측 금지).

## 기술 스택

- 언어/프레임워크: NestJS 11 + TypeScript (api-ventago), Flutter (mobile-sales-app)
- DB: PostgreSQL (Sequelize) — pool 낭비 금지 규칙 적용, 신규 DDL 은 `ALTER OWNER TO coolsistema` + SERIAL
- 외부 API: FASHN.ai v1.6 (axios), Gemini 3 Flash (StylistProvider 어댑터 뒤 격리)
- ESLint: api-ventago 기존 설정 (`npx eslint <파일> --fix`)

## 태스크 목록

### 게이트 (코드 착수 전)
- [ ] TASK-0: FASHN 계정 + $7.50 충전 → 실물 매장 옷 2~3장 웹 플레이그라운드 수동 검증 — **불합격 시 여기서 멈추고 벤더 재선정** (사용자 수행, Mac)

### Stage 1 — FASHN 어댑터 (Wave 49-02)
- [ ] TASK-1: `FashnTryOnProvider` 구현 — 파일: `src/app/tryon/fashn-tryon.provider.ts` (POST /v1/run → 폴링, 타임아웃 30s·재시도 1, 키 마스킹 로그, try/catch 전 구간)
- [ ] TASK-2: env 토글 배선 — 파일: `src/app/tryon/tryon.module.ts` (`TRYON_PROVIDER=stub|fashn`, `FASHN_API_KEY`), `.env.example` 갱신
- [ ] TASK-3: 기존 PoC 폼으로 스모크(로컬, 실 API 1~2콜) + 결과 캐시(person+garment sha256 → 메모리 LRU, TTL 30분) — 파일: `src/app/tryon/tryon-cache.service.ts`

### Stage 2 — vendedor 백엔드 (Wave 49-07, 인증 전환 머지 후)
- [ ] TASK-4: `tryon_events` 마이그레이션 — 파일: `migrations/tryon-events.sql` (id SERIAL, store_id, branch_id, seller_id, product_id NULL 허용(flat-lay), mode, created_at / 사진·프로필 컬럼 없음 / 끝에 `ALTER TABLE ... OWNER TO coolsistema`) — 로컬 먼저, 운영은 승인 게이트
- [ ] TASK-5: `VendedorTryOnController` — 파일: `src/app/tryon/vendedor-tryon.controller.ts` (`POST /vendedor/tryon/from-product`, `POST /vendedor/tryon/from-upload`(flat-lay), device guard 재사용, 이벤트 INSERT 는 외부 호출 완료 후 pool.query 단건)
- [ ] TASK-6: 비용 가드 — 동시 2건/기기(인메모리 세마포어) + 일일 한도 env `TRYON_DAILY_LIMIT`(기본 100/지점) 초과 시 429 — 파일: `src/app/tryon/tryon-limit.guard.ts`
- [ ] TASK-7: flat-lay 사진 상품 이미지 등록 제안 — 파일: 기존 products 이미지 업로드 서비스 재사용, `POST /vendedor/tryon/register-garment-image`

### Stage 3 — AI 스타일리스트 (Waves 49-08/49-09)
- [ ] TASK-8: `products.ai_attributes` JSONB 마이그레이션(+ GIN 인덱스, ALTER OWNER) — 파일: `migrations/products-ai-attributes.sql`
- [ ] TASK-9: `StylistProvider` 포트 + Gemini 어댑터 — 파일: `src/app/stylist/stylist-provider.interface.ts`, `gemini-stylist.provider.ts` (프롬프트: 태그 JSON 강제, 체형 원문 출력 금지·긍정형 멘트만)
- [ ] TASK-10: `ai-catalog-tagger` 배치 — 파일: `src/app/stylist/catalog-tagger.service.ts` + 실행 스크립트 (20개 샘플 → 사용자 검수 → 전량. 이미지 없으면 텍스트만 부분 태깅. 배치 중 커넥션 장기 점유 금지 — 상품별 조회→반환→LLM→단건 UPDATE)
- [ ] TASK-11: 추천 엔드포인트 — 파일: `src/app/stylist/vendedor-stylist.controller.ts`, `stylist.service.ts` (`/analyze`: 사진→프로필, 응답만·저장 금지 / `/recommend`: branch 재고 필터 후보 20~30 → LLM 리랭크 5벌+ES 멘트. 재고 0 차단 금지, 타지점 표시만)
- [ ] TASK-12: ESLint 전체 검증 (`npx eslint src/app/tryon src/app/stylist --fix` → 오류 0)
- [ ] TASK-13: PostgreSQL pool 안전 점검 — 체크리스트: 외부 API 호출 중 커넥션/트랜잭션 보유 0건, 신규 쿼리 전부 자동반환 패턴, 배치의 N+1 커넥션 점유 없음

### Stage 4 — Flutter (Wave 49-10, 별도 세션 권장 — context 분리)
- [ ] TASK-14: 동의 화면(ES 고지 + 탭 타임스탬프) + 카메라 촬영 — mobile-sales-app
- [ ] TASK-15: 상품 선택(바코드/검색/flat-lay 촬영) → VTO 결과 화면(세션 사진 재사용)
- [ ] TASK-16: "Recomendar looks" 추천 카드 5개 → 탭 → 즉시 VTO, WhatsApp 공유(옵션, TTL 24h 링크)

### Stage 5 — 파일럿 (Wave 49-11)
- [ ] TASK-17: 파일럿 1지점 배포 + 전환율 측정 쿼리(tryon_events ↔ sales 시간창 조인) + 1주/1개월 점검(제안서 §6)

## 완료 기준

- ESLint 오류 0개
- 스텁이 아닌 실제 합성 이미지 반환(TASK-3 스모크), 추천 5벌 ≤10s·피팅 P95 ≤12s
- tryon_events 에 사진/체형 데이터 컬럼 자체가 없음(스키마로 보장)
- pool 체크리스트 전 항목 통과, 레이트리밋·일일 한도 동작 확인(429)
- 로컬 마이그레이션 적용 + 운영 적용 절차 문서화(승인 게이트)

## 금지사항 / 주의사항

- 고객 사진·체형 프로필 DB/디스크 저장 금지. 로그에도 이미지 바이트·분석 원문 금지.
- API 키 평문 로그 금지(마스킹). `.env` 커밋 금지.
- DB 커넥션/트랜잭션 보유 상태에서 FASHN/Gemini 호출 금지.
- 신규 DDL: SERIAL + `ALTER OWNER TO coolsistema` 필수, GENERATED IDENTITY 금지. 운영 DDL 승인 게이트.
- 재고 부족으로 기능 차단 금지(기존 정책). ProductBranch 네이밍은 intel 문서 확인 후 사용.
- Phase 37 mobile_sessions 등 구 인증 테이블 DROP 금지(롤백 여지 — 인증 전환 SPEC 규칙).
- 기존 A트랙 공개 엔드포인트(`/api/public/shop/tryon`) 시그니처 변경 금지(tienda-app 의존).
