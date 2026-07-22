# SPEC: 셀프서비스 매장 가입 — DNI + 이메일/WhatsApp 이중 OTP 검증 게이트 + Telegram 승인 알림

생성일: 2026-07-21
작성: GSD Plan 단계 (Execute 미착수 — 승인 대기)

## 목표

공개 셀프서비스 매장 가입(`RegisterForm.tsx` → `POST /auth/register`)에 **DNI 사진 업로드 + 이메일·WhatsApp 각각 다른 6자리 OTP 이중 검증**을 추가하고, 세 가지(이메일·WhatsApp·DNI)가 모두 통과해야만 계정이 사용 가능해지는 **fail-closed 게이트**를 건다. 검증이 끝나 승인 대기 상태가 되면 **기존 `notifyTelegram`으로 Marcos에게 승인 요청 알림**을 보낸다. 데스크톱 사용자는 QR로 폰 카메라에 DNI 촬영을 이어받는다. **전 과정 DB pool 무부담(폴링 0, OTP는 인메모리 또는 소량 테이블), 신규 폴링 절대 금지.**

## 배경 및 컨텍스트 (코드 확인 결과 — 확정 사실)

### 대상 화면 / 엔드포인트
- 프론트: `ventago-app/src/views/register/RegisterForm.tsx` (+ `RegisterView.tsx`). 라이트 테마, MUI, `apiConnector.post('/auth/register', ...)`.
- 백엔드: `api-ventago/src/app/auth/auth.controller.ts:54` `@Post('register') signUp(dto)` → `AuthService.signUp` → `UserRegistrationService`(`createStore` / `createUser` / `assignAdminRole`).
- `RegisterDto`(`src/app/users/dto/register.dto.ts`): `name, lastName, username?, email(IsEmail), password, phone?, address?, companyName, aliasName?, companyCuit(number), companyAddress, acceptConditions?`. → **이메일·전화 이미 수집 중**(reseller 폼과 달리 플레이스홀더 아님).

### 현재 동작 (게이트 없음 — 이번 작업의 근거)
- `UserRegistrationService.createStore`: `Store.create({..., isActive:true})` **직접 호출** → `StoreService.create()`를 우회하므로 **기존 "Nueva Tienda" Telegram 알림이 안 울림**.
- `UserRegistrationService.createUser`: `status:'trial', isVerified:true` 로 즉시 생성 → **가입 즉시 사용 가능(검증 단계 전무)**.
- 로그인 게이트: `auth.service.ts:239` `if (user.status === 'inactive' || 'suspended') throw UnauthorizedException`. `Users.status` enum = `'active' | 'inactive' | 'trial' | 'suspended'`, `isVerified:boolean` 존재.

### 재사용할 기존 자산 (신규 개발 최소화)
- **Telegram**: `src/common/telegram/telegram.ts` `notifyTelegram(text, {dedupKey})` — fire-and-forget, 60초 중복방지, 순수 fetch(**DB 0회**), env `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID`(coolsistema_bot). `store.service.ts`·에러 필터에서 검증됨.
- **MemoryCacheService**(`src/common/cache/memory-cache.service.ts`): `get<T>(key)/set(key,value,ttlMs)/del(key)/delByPrefix(prefix)`, 인메모리 Map, 60초 cleanup. **DB 0회**. ⚠️ **인스턴스 로컬**(운영 2인스턴스 → 크로스 인스턴스 미공유) — 결정 D1 참조.
- **MinIO**: `src/common/minio/minio.service.ts` `uploadFile(file, fileName)` → putObject. reseller가 `dni_photo` 저장에 이미 사용(`ResellerDocument`, docType `dni_photo`).
- **WebSocket**: `WebsocketService`(`src/common/socket/websocket.service.ts`, `emitToApiKey` 등 room 매핑) + 게이트웨이 패턴 `print.gateway.ts`(`@WebSocketGateway({namespace, cors: wsCorsOptions})`, `SocketRateLimiter` 브루트포스 방어, Winston Logger). → `/onboarding` 네임스페이스로 미러링(폰↔데스크톱 실시간, **폴링 없음**).
- **reseller 승인 흐름**(`reseller/auth/reseller-auth.service.ts`): `pending_review → approve()(isActive:true,status:approved) / reject()`. 상태·승인 UX 참고.

### Pool 현황 (`database.module.ts` 확인)
- `min:2, max:80`(앱→pgbouncer 클라측 상한), **pgbouncer transaction pooling** 경유 PG18:5434, pgbouncer `pool_size=50` 캡, **운영 2인스턴스**, `acquire:15000, idle:10000`.

### ★ 로그 점검 결과 (반드시 반영)
- 마지막 로그 `combined-2026-07-20.log`: **`sync_outbox` 폴링 SELECT 이 278ms → 45,352ms 로 악화**(QID=670). `error-2026-07-20.log`: `[OnlineOrdersExpiryCron] Operation timeout`.
- 해석: **주기 폴링 크론이 이미 DB/pgbouncer 큐를 압박**하고 있음. → **본 기능은 어떤 형태의 폴링도 추가하지 않는다**(상태 전파는 Socket push, OTP는 인메모리/단발 쿼리). 이 원칙이 설계의 최우선 제약.

## 기술 스택
- 백엔드: NestJS 11 + Sequelize(`underscored:true`), PostgreSQL 18(로컬 5432 / 운영 5434 pgbouncer 경유).
- 프론트: Next.js 13 + MUI 5 + React Hook Form + Yup + `apiConnector`.
- 저장소: MinIO. 실시간: socket.io. 알림: Telegram(기존) + WhatsApp(신규) + 이메일(확인 필요).
- ESLint: 프로젝트 규칙(Warning=에러). `newline-before-return`, `lines-around-comment` 등 준수.

## 아키텍처 설계

### 상태 머신 (fail-closed)
```
draft(폼 작성)
  └─ submit → contact_pending      # 계정 생성 방식은 D2 참조
       ├─ email OTP  ✅ (email_verified_at)
       ├─ whatsapp OTP ✅ (phone_verified_at)
       └─ DNI front+back 업로드 ✅ (MinIO)
  └─ 3개 완료 → review_pending  ──▶ notifyTelegram(승인 요청)   # 사용 불가
  └─ Marcos approve → active/trial (isActive:true)               # 사용 허용
  └─ Marcos reject  → rejected (사유 저장)                        # 사용 불가
```
로그인 게이트: `auth.service.ts` 의 status 차단 목록에 신규 상태를 추가(사용 허용 전 로그인 차단).

### OTP 발급/검증 (핵심, pool-free)
- 채널별 **서로 다른 6자리 숫자**(요청 사항 — 두 채널 소유 증명). `crypto.randomInt(0, 1_000_000)` 6자리 zero-pad.
- 저장(코드·시도횟수·만료): **D1 결정에 따름**(MemoryCache TTL 또는 소량 `verification_codes` 테이블).
- 정책: 만료 10분 · 재전송 쿨다운 60초 · 시도 5회 초과 시 잠금 · 코드는 해시로만 보관(평문 저장 금지).
- 발송: 이메일(트랜스포트 D3) + WhatsApp(신규 채널, 아래).

### DNI (저장만, 수동 승인)
- 프론트: 앞/뒤 촬영(프레임 가이드·흐림 감지 재촬영 안내). 데스크톱은 QR로 폰 이어받기.
- 백엔드: `MinioService.uploadFile` 로 저장, 메타(minio key)만 DB 1~2행. **자동 OCR 없음**. Marcos 육안 대조 후 승인.

### 데스크톱→폰 이어받기 (QR nonce + Socket, 폴링 0)
- `/onboarding` 소켓 연결 → nonce 발급(**MemoryCache TTL 120s**) → 데스크톱에 QR 표시.
- 폰이 nonce 링크로 접속해 DNI 촬영/OTP 입력 → 서버가 데스크톱 소켓으로 **push**(상태 갱신). DB 폴링 없음.

### Telegram 알림 (기존 재사용)
- `review_pending` 진입 시 `notifyTelegram()` 1회 호출(`dedupKey: onboarding-<id>`):
  `🆕 Nuevo comercio verificado — esperando aprobación / Tienda·CUIT / ✅Correo ✅WhatsApp ✅DNI / 👉 Aprobar: <admin url>`.
- (옵션) 텔레그램 인라인 버튼으로 승인/거절 — 별도 webhook 필요(후속).

### WhatsApp 발송 (신규)
- 현재 코드에 실 WhatsApp 발신 인프라 없음. Meta WhatsApp Cloud API 또는 제공업체(360dialog/Gupshup). **OTP용 템플릿 사전승인 필요**(아르헨티나 번호 +54 9 정규화). 어댑터를 `notifyTelegram`처럼 fire-and-forget + 타임아웃으로 격리.

## 결정 필요 (Execute 전 확정)

- **D1 — OTP 저장소.** (a) **MemoryCacheService**(DB 0회) — 단, 2인스턴스라 sticky session 또는 단일 인스턴스 전제 필요. (b) **소량 `verification_codes` 테이블** — 인스턴스 무관·정확, 온보딩당 insert 1 + select 1~2회로 pool 영향 무시할 수준(폴링과 무관). → **권장: (b)** (2인스턴스 + 로그상 DB 폴링 압박 상황에서 정확성 우선, 추가 부하는 무시 가능). nonce(폰 이어받기)는 (a) MemoryCache 유지.
- **D2 — 계정 생성 시점.** (a) 지금처럼 submit 시 store+user 생성 후 상태만 미검증으로 → 최소 변경, 단 미완료 가입이 store row 로 남음(스팸). (b) **검증 완료 시점에 store+user 생성**, 그 전엔 `pending_registrations` 행(폼 데이터+해시 비번)만 보관 → 스팸 store 없음, 요청("검증해야 사용 허용")에 정합. → **권장: (b)**.
- **D3 — 이메일 발송 트랜스포트.** 현재 nodemailer/SMTP 미확인. 기존 발신 수단(있으면 재사용) 확인 후, 없으면 SMTP/제공업체 추가. → Execute 초입에 확정.

## 태스크 목록

### 마이그레이션 (5432·5434 동시, public 스키마)
- [ ] TASK-1: `store_onboarding_verifications` 테이블 — `id, store_id?(nullable), email, phone, email_verified_at?, phone_verified_at?, dni_front_key?, dni_back_key?, status, reviewed_by?, reject_reason?, telegram_notified_at?, created_at`. (+ D2(b) 채택 시 `pending_registrations` 폼 데이터 컬럼 통합) — 파일: `api-ventago/migrations/<날짜>-store-onboarding-verifications.sql` (owner/시퀀스 coolsistema 이전 DO 블록 포함)
- [ ] TASK-2: (D1(b) 채택 시) `verification_codes` 테이블 — `id, subject_key, channel, code_hash, attempts, expires_at, created_at`, 인덱스(subject_key,channel). — 같은 마이그레이션 파일
- [ ] TASK-3: `Users.status` enum 에 `pending_verification` 추가(또는 D3 결정) + `auth.service.ts` 로그인 차단 목록에 반영

### 백엔드 (api-ventago)
- [ ] TASK-4: `OnboardingVerificationService` — OTP 생성/발송/검증(MemoryCache 또는 테이블), 시도·쿨다운·만료. **평문 코드 미저장, 해시 비교.** try/catch 필수 — 파일: `src/app/onboarding/onboarding-verification.service.ts`
- [ ] TASK-5: `OnboardingController` — `POST /onboarding/start`(폼 접수·D2), `POST /onboarding/otp/send`(email|whatsapp), `POST /onboarding/otp/verify`, `POST /onboarding/dni`(multipart→MinIO), `GET /onboarding/status/:token` — 파일: `src/app/onboarding/onboarding.controller.ts`
- [ ] TASK-6: WhatsApp 발송 어댑터(fire-and-forget + 타임아웃) — 파일: `src/common/whatsapp/whatsapp.ts`
- [ ] TASK-7: 이메일 OTP 발송(D3 트랜스포트) — 파일: 기존 메일 유틸 또는 `src/common/mail/*`
- [ ] TASK-8: 검증 완료(3/3) → `review_pending` 전이 + `notifyTelegram(...)` 호출(dedupKey) — `OnboardingVerificationService`
- [ ] TASK-9: 승인/거절 관리자 엔드포인트 — `POST /admin/onboarding/:id/approve|reject` (reseller approve/reject 미러, store+user 활성화) — 파일: `src/app/onboarding/onboarding-admin.controller.ts`
- [ ] TASK-10: `OnboardingGateway`(`/onboarding` namespace) — nonce 발급·폰↔데스크톱 push. `print.gateway.ts` 패턴 + `SocketRateLimiter` — 파일: `src/app/onboarding/onboarding.gateway.ts`
- [ ] TASK-11: `signUp`/`UserRegistrationService` 를 D2 결정에 맞게 조정(즉시 활성 제거)

### 프론트엔드 (ventago-app)
- [ ] TASK-12: `RegisterForm.tsx` 를 마법사로 확장 — Paso 1 Datos(기존, "Registrarse"→"Continuar") → Paso 2 DNI(앞/뒤 + QR 이어받기) → Paso 3 이중 OTP(6칸, inputmode=numeric, autocomplete=one-time-code, 붙여넣기 분배, 재전송 타이머) → Paso 4 "en revisión" → Paso 5 활성. (목업 `coolsistema_signup_boost.html` 기준)
- [ ] TASK-13: 폰 이어받기 페이지(`/onboarding/[token]`) — DNI 카메라 촬영 전용. 소켓 상태 push 수신.
- [ ] TASK-14: 관리자 승인 화면 보강(`admin/registration`) — DNI 이미지 뷰 + Aprobar/Rechazar.

### 검증
- [ ] TASK-15: ESLint `npx eslint . --fix` (프론트·백 오류 0)
- [ ] TASK-16: PostgreSQL pool 점검 — 신규 폴링 0 확인, OTP 경로 쿼리 수 측정, `finally` release/트랜잭션 정합
- [ ] TASK-17: 로그 재점검 — 신규 slow query/에러 없는지 `combined-*.log`/`error-*.log` 확인
- [ ] TASK-18: 스모크 — 가입→OTP2건→DNI→review_pending→Telegram 수신→approve→로그인 허용 / 미검증 로그인 차단(fail-closed)

## 완료 기준
- ESLint 오류 0개(프론트·백).
- 이메일·WhatsApp 각각 다른 6자리 입력 + DNI 업로드 3/3 전까지 로그인/사용 차단(fail-closed) 확인.
- `review_pending` 진입 시 Marcos 텔레그램 알림 수신(승인 링크 포함).
- **신규 폴링 0**, OTP 경로 pool 사용 무시 수준, 로그에 신규 slow query/에러 없음.
- 마이그레이션 5432·5434 양쪽 적용 + 스키마 대조 일치, DDL 파일 `api-ventago/migrations/` 커밋.

## 금지사항 / 주의사항
- **폴링 절대 금지**(로그의 sync_outbox 45s 악화 재현 위험). 상태 전파는 Socket push.
- OTP 평문 저장 금지(해시만). 브루트포스 방어(5회 잠금·쿨다운·SocketRateLimiter).
- 마이그레이션 한쪽만 적용 금지(5432·5434 동시). 신규 테이블 owner/시퀀스 coolsistema 이전, **public 스키마**(로그의 `reseller` 스키마 참조 오류와 분리).
- Mac 작업트리 미커밋 WIP(`afip-issuer.service.ts`)는 건드리지 말 것.
- `apiConnector.remove()` 사용(`.delete()` 아님), 프론트 ESLint(빈 줄 규칙) 주의.
- 개인정보(DNI 이미지)는 MinIO 저장·접근권한 최소화, 로그에 코드/개인정보 미기록.
