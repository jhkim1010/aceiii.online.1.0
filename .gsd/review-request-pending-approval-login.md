# 자문 요청 — 승인 대기 중인 신청자에게 로그인 시 "승인 대기" 를 알리기

## 요구사항 (사용자)

새 매장을 신청한 사람이 **바로 로그인하려 하면**, "SUPERADMIN 승인을 기다리라"는 뜻의
안내(`Aprobación de sistema` 대기)가 떠야 한다. 지금은 그런 안내가 없다.

## 실측한 현재 동작

### 가입 흐름
`POST /onboarding/start` → `pending_registrations` 행 생성.
status 전이: `contact_pending → review_pending → approved | rejected | expired`
(`pending-registration.model.ts:92`)

**Store 와 Users 는 승인 시점에야 만들어진다** — `onboarding-approval.service.ts:196`
의 `approve()` 안에서 `authService.provisionStoreAndOwner(...)` 로 생성.
즉 **승인 전에는 `users` 행이 존재하지 않는다.**

### 로그인
`auth.service.ts:275` `signIn()`:
- `findOneByEmailOrUsername` 이 NotFound → `UnauthorizedException(INVALID_CREDENTIALS_MSG)`
- **Phase 63 이 의도적으로 "아이디 없음"과 "비밀번호 틀림"을 같은 401 로 통일했다**
  (계정 열거 차단). 실제 사유는 서버 로그와 `store_error_log` 에만 남긴다.
- 참고로 다른 두 거부 메시지도 안내가 아니라 차단처럼 읽힌다:
  - `'Tienda no disponible'` (매장 비활성, :392)
  - `'Usuario inactivo o suspendido'` (:411)

### 결과
승인 대기 중인 신청자는 **오타를 냈을 때와 똑같은 메시지**를 본다.
"내 신청이 접수되긴 한 건가?" 를 알 방법이 화면에 없다.

## 내가 제안하는 설계

`signIn` 에서 사용자를 못 찾았을 때, `pending_registrations` 를 email/username 으로 조회한다.
**단, 그 사실을 바로 알리지 않는다.** `pending.passwordHash` 는 이미 저장돼 있으므로
(`approve()` 가 그대로 재사용한다) **비밀번호를 대조해 일치할 때만** 상태를 알린다.

- 비밀번호 일치 → status 별 안내:
  - `review_pending` → "심사 중입니다. 시스템 승인을 기다려 주세요"
  - `contact_pending` → "이메일/전화 인증을 먼저 완료해 주세요"
  - `rejected` / `expired` → ?(아래 질문 3)
- 비밀번호 불일치 → 기존 `INVALID_CREDENTIALS_MSG` 그대로

이러면 **열거 방지가 깨지지 않는다** — 올바른 비밀번호를 아는 사람은 본인뿐이므로,
그에게만 상태를 알린다. 공격자가 이메일만으로 "신청 존재 여부"를 알아낼 수 없다.

## 묻고 싶은 것

1. **이 방식이 Phase 63 의 열거 방지 의도를 실제로 지키는가?** 놓친 누출 경로가 있는가?
   특히 **타이밍 차이** — 신청이 있는 이메일은 bcrypt 비교를 한 번 더 하므로 응답이
   느려진다. 이것만으로 신청 존재를 구분할 수 있는가? 있다면 어떻게 막아야 하는가
   (더미 bcrypt 비교? 고정 지연? 무시해도 되는 수준인가)?

2. **실패 로그인마다 쿼리와 bcrypt 가 하나씩 늘어난다.** 현재 rate-limit 은
   IP 150/분 + 계정 15/분이다. 이 정도면 DoS 관점에서 충분한가?
   `pending_registrations` 조회를 **users 조회 실패 시에만** 하는 지금 설계면 되는가,
   아니면 순서를 바꿔야 하는가?

3. **`rejected` / `expired` 를 본인에게 알려야 하는가?** 거절 사유를 화면에 노출하면
   재신청 시 회피 학습에 쓰일 수 있다. 그렇다고 "승인 대기"라고 거짓말할 수도 없다.
   어떤 문구·수준이 맞는가?

4. **다른 경로도 고쳐야 하는가?** superadmin 이 `/admin/tiendas` 에서 매장을 직접
   만들거나 활성화하는 경로가 따로 있다. 거기서는 users 행이 존재하고 status 가
   inactive 라 `'Usuario inactivo o suspendido'` 가 뜬다. 같은 "승인 대기" 상황인데
   메시지가 다르다. 통일해야 하는가?
   ※ 관련 기존 결함: `auth.service.ts:332` 의 `[DEBUG-ACTIVATE]` 주석이
     "tiendas 페이지에서 매장 활성화 시 `user.status` 가 갱신되지 않는다" 고 적고 있다.

5. **프론트 처리** — 이 메시지를 단순 토스트로 띄우면 충분한가, 아니면 전용 화면
   (신청 상태 조회)이 필요한가? 신청자는 자기 상태를 다시 확인할 방법이 없다.

6. 내가 놓친 더 단순한 해법이 있는가? (예: 신청 시점에 users 를 inactive 로 미리 만들고
   승인 때 활성화 — 그러면 로그인 경로가 하나로 합쳐진다. 대신 미승인 계정이 users 에
   쌓이고 email UNIQUE 를 선점한다는 부작용이 있다)

---

# CODEX 자문 결과 (2026-08-11)

## 결론
제안 방향은 채택. **"기존 pending 모델 유지 + user miss 일 때만 pending 조회 +
모든 경로 bcrypt 정확히 1회 + 구조화된 상태 코드 + 지속형 상태 UI"**.
내 대안(신청 시 inactive user 선생성)은 **비권장** — email UNIQUE 장기 선점,
`inactive` 가 정지·소프트삭제·승인대기를 동시에 뜻하게 됨.

## 내가 틀렸거나 놓친 것

| # | 지적 | 근거 |
|---|---|---|
| 1 | **타이밍 열거는 이미 존재하고 내 제안으로 안 없어진다.** 미존재=bcrypt 0회 / 존재=1회 라 반복 측정으로 구분된다. 고정 지연 말고 **더미 bcrypt**(미리 만든 cost-10 상수)로 **모든 시도에서 정확히 1회** | auth.service.ts:287-300, :316-329 |
| 2 | **email 정규화 불일치 — 기능 버그다.** 온보딩은 email 을 소문자·trim 저장하는데 로그인 조회는 정규화하지 않는다 → 실제 신청이 있어도 **못 찾는다** | onboarding-verification.service.ts:182-192 vs users.service.ts:165-199 |
| 3 | **"rate-limit 충분"이라는 내 전제 기각.** 계정 키가 입력 문자열이라 식별자를 바꾸면 매번 새 버킷. 한 IP 에서 150 email → bcrypt 150회 | throttle.constants.ts:22-48, proxy-throttler.guard.ts:48-63 |
| 4 | ★ **X-Forwarded-For 첫 값을 그대로 tracker 로 쓴다.** 프록시가 외부 헤더를 지운다는 보장이 코드에 없다 → **IP 제한 우회 가능** (별건 보안 이슈) | proxy-throttler.guard.ts:80-92 |
| 5 | **[HIGH] pending 에 email/username 중복이 가능하다.** `start()` 는 CUIT 로만 중복 검사 → `findOne({email})` 이 비결정적. **정책을 먼저 정해야 한다** | onboarding-verification.service.ts:160-171 |
| 6 | **`expired` 는 실제로 기록되지 않는다.** 전이가 없고 만료 시 예외만 던진다 → `status==='expired'` 분기는 대부분을 놓친다. `expiresAt < now()` 를 같이 봐야 함 | onboarding-verification.service.ts:543-559, :423-441 |
| 7 | **[MEDIUM] `contact_pending` 문구 부정확.** review 전이는 email+phone+**주소 확인**까지 요구 → "이메일/전화 인증" 만 안내하면 빠진다 | onboarding-verification.service.ts:481-505 |
| 8 | **Q4 메시지 통일 금지.** pending(계정 없음)과 inactive/suspended(운영상 정지)는 의미가 다르다. 통일하면 정지 계정에 거짓 안내를 준다 | — |
| 9 | ★ **진짜 문제는 상태 불일치 버그다.** `/store/:id` 는 Store 만 갱신하고 Users 를 안 건드린다. 올바른 경로가 따로 있다 → **활성화 명령을 하나로 통합해 원자적으로** | store.controller.ts:254-266 vs users.service.ts:432-474 |
| 10 | `/onboarding/status/:token` 은 **이미 있다.** 문제는 로그인 화면에서 토큰을 복구할 수 없다는 것. 토스트 말고 **지속형 상태 카드** | onboarding.controller.ts:135-140 |
| 11 | **모듈 순환 주의** — OnboardingModule 이 AuthModule 을 import 한다. 역방향 import 금지, 조회 전용 provider 분리 | onboarding.module.ts:18-28, auth.module.ts:23-35 |

## 권장 상태 코드 (거절 사유 원문은 로그인 응답에 넣지 않는다)
- `ONBOARDING_REVIEW_PENDING` — "Tu solicitud está en revisión. Esperá la aprobación del sistema."
- `ONBOARDING_CONTACT_PENDING` — "Completá la verificación de correo y WhatsApp para continuar."
- `ONBOARDING_REJECTED` — "No pudimos aprobar tu solicitud. Contactá a soporte."
- `ONBOARDING_EXPIRED` — "Tu solicitud venció. Iniciá un nuevo registro."
