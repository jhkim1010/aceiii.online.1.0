# GSD 리뷰 리포트: 고객 대량 발송 캠페인 (Campañas)
완료일: 2026-07-22 · SPEC: .gsd/spec-campanas.md (v2)

## 완료된 태스크
- [x] 마이그레이션 SQL 6테이블 (미적용 — 사용자 apply 대기)
- [x] 백엔드 모델 6 + campaigns 모듈/컨트롤러/서비스 + 세그먼트 빌더 + WABA 설정
- [x] outbox 발송 워커(@Cron 30s) + WhatsApp Cloud/Email 어댑터 + Meta webhook + opt-out
- [x] client_segments RFM 사전집계 refresh 크론(일1회 04:00)
- [x] 프론트: /clientes-globales/campanas 페이지·이력·4단계 마법사·세그먼트 빌더·ClienteVista 통합(버튼+체크박스)
- [x] app.module.ts 등록, Prettier 검증(양 레포)

## 변경 파일 요약
### api-ventago (백엔드)
- `migrations/2026-07-22-campanas.sql` — 6테이블(campaigns, campaign_recipients, client_contact_prefs, client_segments, store_whatsapp_config, whatsapp_templates) + 인덱스 + owner→coolsistema DO블록
- `src/app/campaigns/` — models 6, campaigns.service/controller/module, dto 3, services(segment-query, waba-config, campaign-sender, contact-prefs, senders 2, segment-refresh.cron, campaign-sender.cron), webhooks/whatsapp-webhook.controller, unsubscribe.controller, util/unsubscribe-token
- `src/app.module.ts` — CampaignsModule 등록
### ventago-app (프론트)
- `src/pages/clientes-globales/campanas/index.tsx`, `src/views/campanas/{CampanasView,CampaignWizard,SegmentBuilder}.tsx`
- `src/views/cliente-vista/ClienteVistaView.tsx` — "Enviar Campaña" 버튼 + checkbox 선택(+29줄, 최소 변경)

## 품질 검증
- [x] Pool 안전: 워커는 FOR UPDATE SKIP LOCKED 로 배치 claim(짧은 tx)→커밋(커넥션 반환)→발송(fetch) 중 **DB 커넥션 미점유**→개별 UPDATE. 세그먼트 미리보기/필터는 client_segments(사전집계)만 조회. raw pool.connect/new Pool 없음(전부 @InjectConnection/모델). 지수 백오프+max_attempts.
- [x] SQL injection: audience_json→SQL 은 whitelist 필드 + 파라미터 바인딩만(문자열 보간 0).
- [x] Prettier: 양 레포 신규 파일 전부 통과(구문 정상).
- [~] 타입기반 ESLint/tsc: device VM 메모리 한계(OOM)로 미실행 — **사용자 환경 `npm run lint` + 빌드 필요**(아래 잔여).
- [x] 임포트 경로/데코레이터: 실제 레퍼런스 파일과 대조 확인(Store/Users/Clients/Branch 모델, @Auth/@GetUser, FullTable setRowSelected).

## 완료 기준 대비
- [x] 세그먼트→미리보기→enqueue→워커 발송→이력 흐름 코드 완비(채널 공용)
- [x] opt-in 없는 WhatsApp 대상 자동 제외, opt-out 재발송 제외(SQL 강제)
- [~] E2E 실동작: env 자격증명(아래) 주입 + 마이그레이션 적용 후 검증 필요

## 남은 작업 (사용자)
### 즉시
1. **마이그레이션 적용** — 로컬 5432 + 운영 5434 동시 (SQL 파일 제공됨)
2. **전체 lint + 빌드** — `npm run lint` (api-ventago/ventago-app), 서버/메모리 여유 환경에서
3. **env 설정** — `WA_PHONE_NUMBER_ID`, `WA_ACCESS_TOKEN`, `WA_WEBHOOK_VERIFY_TOKEN`, `CAMPAIGN_UNSUB_SECRET`, `EMAIL_API_URL`/`KEY`, `API_HOST`
4. **권한 시드** — function slug `enviar-campana`(관리자 role) — 버튼 노출/서버 게이트용
### 병렬 (리드타임)
5. **Meta 온보딩** — WABA 생성·전용번호·비즈인증·결제·**MARKETING 템플릿 승인**·System User 토큰
### 확인 필요(TODO 주석 표기됨)
6. **팜플렛 업로드 엔드포인트** — 프론트가 `POST /campaigns/flyer`(가정, MinIO) 호출. 실제 이미지 업로드 엔드포인트로 연결 필요(업로드 실패는 비치명적, 캠페인 진행 가능). MinIO 팜플렛은 **공개 접근** 가능해야 Meta가 헤더 이미지 fetch 가능.
7. **provincia/sucursal 옵션 엔드포인트** — 세그먼트 빌더가 `GET /province`, `GET /branch` 시도, 실패 시 숫자 입력 fallback. 실제 store-scoped 엔드포인트로 조정 권장.
8. **WhatsApp 템플릿 변수 매핑** — 현재 `{{1}}=손님이름` 단일. 승인 템플릿 변수 개수와 일치시켜야 함(불일치 시 Meta 에러).

## 주의
- WhatsApp 자유텍스트 대량발송 불가 — 승인 템플릿만. Click-to-Chat(wa.me) 루프 금지.
- 마이그레이션 한쪽만 적용 금지(dev/운영 스키마 분기).
