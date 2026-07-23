# SPEC: 고객 대량 발송 캠페인 (Campañas) — v2 (결정 반영)
생성일: 2026-07-22 · 개정: 2026-07-22 (D1~D4 확정)
작성: GSD Plan (코드베이스 실측 기반)

## 확정된 결정
- **D1 채널**: WhatsApp Cloud API를 **Phase 1 주 채널**로 지금 착수. Email은 mail.ts 재사용해 **보조 채널**로 함께 구현(저비용).
- **D2 스코프**: **매장별** — 각 사장님이 자기 매장 고객에게만 발송(store_id 격리).
- **D3 이메일 provider**: **Resend 권장**(아래 근거). 코드는 provider-agnostic 유지.
- **D4 opt-out 저장**: 별 테이블 `client_contact_prefs` — 단 WhatsApp은 **opt-in**(수신동의)까지 추적(Meta 정책 필수).

## 목표
ClienteVista 고객 연락처를 세그먼트로 필터링해 팜플렛/프로모를 대량 발송. WhatsApp Cloud API(주) + Email(보조). 비동기 outbox로 pool 무낭비, opt-in/opt-out 준수.

---

## ★ WhatsApp Cloud API 현실 — 코드 vs Meta 온보딩 분리

**내가(코드) 만드는 것:** WABA 연동 서비스, Cloud API 발송 어댑터(Graph API), 배송/읽음 webhook, 템플릿 레지스트리, opt-in/out, outbox 워커, 세그먼트 빌더, 프론트 전체. → env에 자격증명 넣으면 즉시 발송 가능한 상태로 완성.

**사장님(Meta 쪽)이 하는 것 — 리드타임 있음, 지금 병렬 시작 권장:**
1. **Meta Business Manager** 계정 + **WhatsApp Business Account(WABA)** 생성
2. **전용 전화번호** 등록 (등록 후 일반 WhatsApp 앱에선 사용 불가 — 신규 번호 권장)
3. **비즈니스 인증**(Business Verification) — 수 일 소요 가능
4. **결제수단 등록** — WhatsApp은 **건당 과금**(2026년 대화당→메시지당 전환, MARKETING이 최고가)
5. **MARKETING 템플릿 제출 → Meta 승인** — 프로모 문구/변수 구조를 템플릿으로 미리 승인받아야 발송 가능(자유 텍스트 대량발송 불가)
6. **System User 액세스 토큰** 발급 → 우리 서버 env/DB에 주입

### WABA 아키텍처 결정 (매장별 스코프 대응)
- **권장 = 하이브리드**: `store_whatsapp_config` 테이블로 매장별 WABA 자격증명 저장(장래 Meta **Embedded Signup**으로 각 매장이 자기 번호 연결) + 미연결 매장은 **중앙 기본 WABA(env)** 로 폴백. → 초기엔 중앙 번호 1개로 시작, 매장별 번호는 점진 온보딩. 스키마는 둘 다 지원.
- 이유: 사장님들이 gmail 수준 사용자 → 매장별 Meta 온보딩을 전부 강제하면 도입 실패. 중앙 번호로 시작하되 브랜딩 원하는 매장은 자기 번호 연결 가능하게.

### Email provider 권장 = Resend (근거)
수신자가 주로 Gmail → **인박스 도달률**과 도메인 인증(SPF/DKIM/DMARC) 간편함이 핵심. Resend는 AWS SES 기반 도달률 우수 + 도메인 인증 셋업이 가장 단순 + 무료 3k/월. mail.ts가 이미 provider-agnostic이라 `EMAIL_API_URL`/`KEY`만 주입. (Mailgun도 mail.ts 첨부 코드에 이미 참조돼 있어 폴백 용이.) ※개인 Gmail SMTP 직발송은 일 500건 한도·마케팅 부적합이라 제외.

---

## 배경 / 재사용 자산 (실측)
- **Outbox** `sync_outbox`(Phase 43): status/attempts/next_retry_at/dedupe_key/partial-unique, 외부 I/O 중 커넥션 미점유. → `campaign_recipients` 큐에 복제.
- **Pool**(database.module.ts): 앱 min2/max80 → pgbouncer(pool_size=50) → PG max_connections=100, acquire=15s, 사용률 80%↑ warn. → 워커 배치 SELECT 후 즉시 반환, 발송(HTTP) 중 커넥션 0 점유.
- **clients.model**: email/whatsapp/resIva/provinceId/province/provinceText/isActive/sellerId. `fecha_nacimiento` 없음 → 나이/생일 필터 후속.
- **whatsapp 모듈**(Click-to-Chat): `phone-normalizer.service`(E.164), `template-registry`, `whatsapp_messages` 로그 → 재사용/확장.
- **MinIO**: 팜플렛 업로드 기존 재사용. **Sequelize underscored**, 마이그레이션 로컬5432+운영5434 동시 + owner→coolsistema.

---

## 데이터 모델 — `migrations/2026-07-22-campanas.sql`
1. **campaigns** — store_id, name, channel(`whatsapp`|`email`), status(`draft`|`scheduled`|`queued`|`sending`|`sent`|`failed`), wa_template_name(승인 템플릿), wa_template_lang, subject(email), body_template, flyer_url(MinIO), audience_json(JSONB), scheduled_at, total_recipients, sent_count, failed_count, created_by, ts.
2. **campaign_recipients**(발송 큐) — campaign_id, client_id, channel, to_address(E.164/email), rendered_body, wa_message_id(webhook 상관), status(`pending|processing|sent|delivered|read|failed|skipped`), attempts, max_attempts=5, next_retry_at, last_error, processed_at. UNIQUE(campaign_id,client_id). idx `(status,next_retry_at) WHERE status='pending'`.
3. **client_contact_prefs**(opt-in/out) — client_id UNIQUE, whatsapp_opt_in bool, whatsapp_opt_out bool, email_opt_out bool, opt_in_source, updated_at.
4. **client_segments**(RFM 사전집계) — client_id PK, store_id, last_purchase_at, purchase_count, total_spent, bought_via_envio, last_branch_id, cta_cte_balance, refreshed_at. 필터/미리보기는 이 테이블만.
5. **store_whatsapp_config** — store_id UNIQUE, waba_id, phone_number_id, display_phone, access_token(암호화 저장 or env ref), quality_rating, is_active. 미설정 매장은 env 중앙 WABA 폴백.
6. **whatsapp_templates** — store_id(nullable=공용), name, category('MARKETING'/'UTILITY'), language, status(`pending|approved|rejected`), body, header_type, meta_template_id, ts.

모두 owner→coolsistema DO블록.

---

## 백엔드 태스크
- [ ] TASK-1: 마이그레이션 SQL(6테이블+인덱스+owner DO) — `migrations/2026-07-22-campanas.sql`
- [ ] TASK-2: 모델 6개 (`src/app/campaigns/`)
- [ ] TASK-3: campaigns 모듈 — CRUD, `POST /:id/enqueue`(트랜잭션 내 recipients 벌크 INSERT만, 발송 안 함), opt-out/미동의/무연락처/비활성 자동 제외.
- [ ] TASK-4: 세그먼트 쿼리 빌더 — audience_json→SQL WHERE(**whitelist만**, injection 차단), `GET /campaigns/preview-count`(client_segments만).
- [ ] TASK-5: `CampaignSenderWorker`(@Cron 30s) — pending 배치50 SELECT→커넥션 반환→어댑터 발송→status UPDATE. 백오프/max_attempts. ★발송 중 커넥션 미점유.
- [ ] TASK-6: `ChannelSender` 인터페이스 + `WhatsAppCloudSender`(Graph API `POST /{phone_number_id}/messages`, 승인 템플릿+파라미터, rate-limit 준수) + `EmailSender`(mail.ts, 팜플렛 img, opt-out 링크).
- [ ] TASK-7: WhatsApp **webhook** 엔드포인트(`POST /webhooks/whatsapp`, Meta 검증) → 배송/읽음 상태를 campaign_recipients에 반영(wa_message_id 매칭).
- [ ] TASK-8: `WabaConfigService` — 매장별 config 조회 + env 중앙 폴백. 토큰 안전 취급.
- [ ] TASK-9: `client_segments` refresh 크론(일1회 off-peak, 배치 UPSERT).
- [ ] TASK-10: opt-in 수집(가입/판매 시 동의 체크) + opt-out 공개 엔드포인트(email baja 링크/서명토큰, WhatsApp STOP 수신 처리) → prefs UPDATE.
- [ ] TASK-11: 권한 시드 — function slug `enviar-campana`, CASL subject `campana`.

## 프론트 태스크
- [ ] TASK-12: `/clientes-globales/campanas` + `hiddenModuleUrls`. ClienteVista "Enviar Campaña" 버튼(게이트).
- [ ] TASK-13: 마법사(채널→내용→오디언스→검토). WhatsApp: 승인 템플릿 선택+변수 매핑. Email: 제목+본문. 팜플렛 업로드(MinIO)+미리보기.
- [ ] TASK-14: 세그먼트 빌더 UI(mockup 3-b) — 조건 add/remove, 실시간 count(디바운스), 세그먼트 저장.
- [ ] TASK-15: 발송 이력(SWR, 상태/진척/배송·읽음).
- [ ] TASK-16: ClienteVista 체크박스 선택→오디언스 전달.
- [ ] TASK-17: 매장 WhatsApp 설정 화면(configuracion) — WABA 연결/템플릿 상태(장래 Embedded Signup 진입점).

## 검증
- [ ] TASK-18: ESLint --fix (front warning=error 주의)
- [ ] TASK-19: pool 안전 점검(워커 발송 중 커넥션 미점유, 배치 후 반환, 미리보기는 segments만)
- [ ] TASK-20: 마이그레이션 로컬5432+운영5434 동시 적용, 스키마 대조, owner 확인
- [ ] TASK-21: 마지막 로그 재확인(발송 부하 시 신규 에러/slow query 0)

## 완료 기준
- ESLint 0
- WhatsApp E2E(env 자격증명 주입 상태): 세그먼트→미리보기→enqueue→워커 템플릿 발송→webhook 배송/읽음 갱신
- Email E2E 동일 흐름
- pool 발송 중 사용률 급증 없음
- opt-in 없는 대상 자동 제외, opt-out 재발송 제외

## 금지 / 주의
- 워커 발송 HTTP 동안 커넥션 점유 금지
- audience_json→SQL whitelist만
- WhatsApp 자유텍스트 대량발송 금지(승인 템플릿만), Click-to-Chat 루프 금지
- 마이그레이션 한쪽만 적용 금지
- opt-in 없는 번호에 MARKETING 발송 금지(Meta 정책·번호 품질 하락 위험)
- pageSize ≤ 50
