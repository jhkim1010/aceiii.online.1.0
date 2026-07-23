# SPEC: WhatsApp 대량 발송 (Campañas)
생성일: 2026-07-23

## 목표
매장이 자기 WhatsApp Cloud API(WABA)로 고객에게 마케팅 메시지를 대량 발송하는 기능.
발송 비용은 Meta가 매장에 직접 청구(중앙 폴백 금지) → 플랫폼 오너는 정산 제외.
발송 직전 예상비용 확인(¿Acepta?), opt-in 존중, pool 안전 outbox 워커로 발송.

## 배경 및 컨텍스트
- 스키마 이미 설계됨: `api-ventago/migrations/2026-07-22-campanas.sql`
  (campaigns, campaign_recipients, client_contact_prefs, client_segments, store_whatsapp_config, whatsapp_templates)
- 참조 패턴:
  - 매장별 암호화 설정: 방금 배포한 이메일 설정(store_configs + src/common/crypto/email-secret.ts + toJSON redact + 전용 PUT).
  - pool 안전 outbox 워커: `src/app/integrations/core/outbox.cron.ts`(@Cron EVERY_10_SECONDS) + `outbox.service.ts`
    (findAll status='pending' limit BATCH → job.update 'processing' → 외부 I/O → 'done'/'failed'(재시도), Sequelize 메서드만 = raw pool 미사용).
- 매뉴얼: whatsapp-bulk-setup-manual(한/서) 이미 작성 — 앱 내 도움말로 연결.
- 배포: Mac 러너 push-*.sh + Jenkins(웹훅 불안정 → 수동 빌드). 마이그레이션은 러너/SSH psql(5432+5434).

## 기술 스택
- 언어/프레임워크: NestJS(api-ventago) + Next.js/MUI(ventago-app)
- DB: PostgreSQL (Sequelize ORM — raw pool 미사용이 원칙; 워커는 모델 메서드만)
- 외부: WhatsApp Cloud API (graph.facebook.com/v20.0/{phone_number_id}/messages, Bearer access_token)
- ESLint: 각 저장소 자체 설정(배포 스크립트에서 tsc 게이트 + eslint --fix)

## 확정 정책 (변경 금지)
- 캠페인은 매장 자기 WABA로만 발송. WABA(store_whatsapp_config.is_active + 필수값) 없으면 발송 버튼 비활성.
- 중앙 WABA 폴백은 캠페인에 대해 금지(비용 귀속 명확화). 영수증 wa.me(무료)는 무관하게 유지.
- 발송 전 비용 확인 필수: 대상 수 × 마케팅 단가 = 예상 USD 표시 → ¿Acepta? 후에만 확정.
- opt-in(client_contact_prefs.whatsapp_opt_in=true, whatsapp_opt_out=false)만 마케팅 대상.
- access_token 은 AES-256-GCM 암호화 저장(email-secret 유틸 재사용) + 응답 redact(공개/조회 유출 금지).

## Phase 분할

### Phase A — 매장 WhatsApp(WABA) 설정 + 매뉴얼 링크  [먼저 착수, 독립 배포 가능]
- [x] A-1: 마이그레이션 적용 — campanas.sql 6테이블 로컬 5432 + 운영 5434(멱등). 파일: migrations/2026-07-22-campanas.sql
- [x] A-2: StoreWhatsappConfig 모델(store_whatsapp_config) + toJSON redact(access_token → whatsappTokenSet). 파일: src/app/store/whatsapp-config/store-whatsapp-config.model.ts
- [x] A-3: 서비스(findByStoreId, upsert(토큰 암호화, 빈 값 미변경), resolveWabaConfig(발송용 복호화), isReady). 파일: .../store-whatsapp-config.service.ts
- [x] A-4: 컨트롤러 GET/PUT /store-whatsapp-config/:storeId (@Auth admin/superadmin, assertOwnership). 파일: .../store-whatsapp-config.controller.ts + module.ts
- [x] A-5: 프론트 카드 "WhatsApp — Envío masivo": WABA ID/Phone Number ID/Access Token(write-only)/발신번호/활성 토글 + 매뉴얼 링크. 파일: ventago-app Configuración 하위 신규 뷰/카드
- [x] A-6: 앱 내 도움말 페이지(스페인어 매뉴얼) 라우트 + 카드에서 링크. 파일: ventago-app help 라우트
- [x] A-7: ESLint --fix + api tsc + front tsc
- [x] A-8: 배포(push-campanas-a.sh) + 운영 검증(GET redact, PUT 401, 암호화 round-trip)

### Phase B — 캠페인 작성 + 세그먼트 + 비용 확인
- [x] B-1: Campaign/WhatsappTemplate/ClientContactPref/ClientSegment 모델
- [ ] B-2: client_segments 사전집계 refresh(크론 일1회) — sales 통집계 금지, 가벼운 UPSERT
- [x] B-3: 캠페인 CRUD + 대상 미리보기(세그먼트 필터 → opt-in 교집합 → count)
- [x] B-4: 비용 견적 엔드포인트: count × 마케팅 단가(설정값, 국가 기본 AR≈0.06) = USD
- [x] B-5: 프론트 캠페인 작성 화면(세그먼트 선택 → 템플릿 → 미리보기 수 → 비용 표시 → ¿Acepta?)
- [x] B-6: WABA 미설정 시 발송 비활성 + 안내
- [x] B-7: ESLint + tsc + 배포 + 검증

### Phase C — outbox 워커 + Cloud API 발송 + 상태
- [x] C-1: 캠페인 확정 시 대상 전개 → campaign_recipients INSERT(pending, dedup uniq, opt-in 필터, to_address 스냅샷)
- [x] C-2: WhatsappCloudSender(매장 WABA로 template 메시지 POST, 복호화 토큰 Bearer, 에러 매핑)
- [x] C-3: CampaignOutboxCron(@Cron 10초) — 배치 pull(status=pending, next_retry<=now, limit) → processing → 발송 → sent/failed(attempts++, 지수 백오프 next_retry) — outbox.cron 패턴 복제, pool 안전
- [x] C-4: 카운터(sent_count/failed_count) + 캠페인 상태(queued→sending→sent) 갱신
- [ ] C-5: (옵션) Meta webhook 로 delivered/read 상태 상관(wa_message_id)
- [x] C-6: ESLint + tsc + 배포 + 실발송 검증(테스트 WABA + 소수 대상)

## 완료 기준
- ESLint 오류 0 / api tsc + front tsc 통과
- access_token 공개/조회 응답에 절대 미노출(redact) + 암호화 저장
- 워커: 모든 발송 경로에 pool 안전(모델 메서드만, 외부 HTTP 중 커넥션 미점유) + 재시도/실패 격리
- 캠페인 발송 전 비용 확인 없이는 발송 불가 + WABA 없으면 발송 불가
- opt-out 손님에게 발송 안 됨

## 금지사항 / 주의사항
- 이미 배포된 wa.me 영수증(Click-to-Chat)·이메일 설정 코드 건드리지 말 것.
- 운영 마이그레이션은 멱등(IF NOT EXISTS)만, 파괴적 DDL 금지. 5432+5434 동시.
- 프론트 진행 중 WIP 없음(이메일 배포로 정리됨) — 그래도 커밋 시 파일 특정.
- raw pool.connect 사용 금지(Sequelize 메서드). 요청/워커당 새 Pool 생성 금지.
- 실제 마케팅 단가는 Meta 공식값 — 설정값은 예상치용이며 청구는 Meta가 매장에 직접.


## 완료 (2026-07-23) — 기존 campaigns 구현 채택(Option A) + 정책 reconcile
- 중앙 WABA 폴백 제거 → 매장 자기 WABA 전용(암호화 resolveWabaConfig), enqueue/워커 게이트.
- 중복 store_whatsapp_config 모델/waba-config 제거 → Phase A 암호화 설정 통일.
- 프론트 캠페인 빌더(대상수→비용→¿Acepta?→발송) 배포. 실서버 api#465/front#466 SUCCESS, cron 정상 기동.
- 미착수(후속): B-2 segment-refresh 검증, C-5 webhook 상태상관 실사용, opt-in 수집 UI, 세그먼트 필터 고도화.
