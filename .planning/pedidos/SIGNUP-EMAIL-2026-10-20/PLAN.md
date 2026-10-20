# 가입 코드 단계 — 이메일 정정 · 재신청 막힘 (2026-10-20)

> 계획만. 코드·DB 변경 없음. 운영 DB 는 조회만 했다.

## 1. 현재 흐름 (근거)

| 단계 | 위치 |
|---|---|
| 폼 제출 → `POST /onboarding/start` | `ventago-app/src/views/register/components/RegisterForm.tsx:225-260` (`onStart`) |
| 서버 접수 | `api-ventago/src/app/onboarding/onboarding-verification.service.ts:204-280` (`start`) |
| 만료된 진행중 신청만 정리 | 같은 파일 `:169-200` (`expireStaleFor`, `expires_at < now()` 인 것만) |
| **중복 검사** | `:226-245` — `status IN (contact_pending, review_pending)` 이고 **CUIT · lower(email) · lower(username) 중 하나라도** 같으면 `409 ONBOARDING_IN_PROGRESS` «Ya hay un registro en curso con estos datos» |
| DB 강제 | 부분 UNIQUE `uq_pending_reg_active_email`, `uq_pending_reg_active_username` (CUIT 는 일반 인덱스, 앱 검사만) |
| 코드 발송 | `:285-347` (`sendOtp`) — `verification_codes(subject=token, channel)` 1행을 덮어씀, 쿨다운 60초, 유효 10분 |
| 코드 검증 | `:350-410` — 5회 초과 잠금 |
| 코드 화면 | `RegisterForm.tsx:606-645` (`OtpChannelCard` ×2, `:648-707`) — 「Reenviar código」 뿐. **이메일 변경·뒤로가기 없음** |
| token 보관 | React state 만(`RegisterForm.tsx:98`). 새로고침/뒤로가기 = token 소실 |

## 2. 「ya existe」 가 나는 이유

1. 첫 제출로 `pending_registrations` 행이 `contact_pending`, `expires_at = +24h` 로 생긴다.
2. 코드 화면에는 이메일을 고칠 방법이 없다 → 사용자가 페이지를 다시 연다 → **token 이 사라진다.**
3. 다시 제출하면 이메일을 고쳤어도 **CUIT 와 username 이 그대로** 이므로 `:226` 의 OR 조건에 걸린다
   → 409 (화면 문구 «Ya hay un registro en curso con estos datos»). 이메일까지 그대로면 UNIQUE 인덱스도 걸린다.
4. `expireStaleFor` 는 24시간이 지나야 정리하므로 **본인이 하루 동안 막힌다.**

(같은 화면에서 다시 누르는 경우는 `RegisterForm.tsx:235` 가 token 을 재사용해 409 가 나지 않는다 — 대신
 **고친 데이터가 서버에 안 간다.** 「뒤로 가서 고치기」 버튼만 붙이면 이 함정에 빠진다.)

운영 실측(2026-10-20): «dox» 행은 `pending_registrations`·`stores`·스테이징 어디에도 없다(전체 25행, max id 58 —
이미 지워진 것으로 보임). 남아 있는 `contact_pending` 4행(id 3·4·6·12)은 전부 기한이 지난 시험 행.
★ id 6·12 는 `phone_verified_at` 만 찍혀 있다 — WhatsApp 발송 미설정이면 서버가 **자동 통과**시킨다(`:290-298`).
  → **`phone_verified_at` 은 본인 증명이 아니다.** (b) 의 판단 근거로 쓰면 안 된다.

## 3. 제안

### (a) 코드 화면의 「Cambiar email」 (권장, 핵심)
- API `POST /onboarding/contact/change` `{ token, channel: 'email'|'whatsapp', value }` (@Public, token 이 권한).
  - `loadActivePending(token)` (contact_pending·미만료) + 해당 채널 **미검증일 때만**(`email_verified_at IS NULL`). 검증됐으면 400.
  - 새 값 정규화(trim/lower) → `@IsEmail` · 다른 진행중 신청과 중복이면 **같은 일반 409**(어느 항목인지 안 알림).
    UNIQUE 위반(경합)도 같은 409 로 변환.
  - 한 트랜잭션: `pending.email` 갱신 + `verification_codes(subject=token, channel)` 행 **삭제**(이전 코드 즉시 무효).
  - 커밋 후 `sendOtp` 재사용(쿨다운 검사는 삭제로 리셋되므로 아래 상한으로 대체).
  - 상한: 신청당 채널 변경 **3회**. 새 nullable 컬럼 `contact_changes smallint DEFAULT 0` (expand-only, W4 규약상
    작은 테이블 additive). 컬럼을 피하려면 Redis/메모리 카운터도 가능하나 워커별이라 부정확 — 컬럼 권장.
  - 반환 `{ emailMasked }`. 다른 데이터(회사·비밀번호·추천인)는 그대로.
- 프론트: `OtpChannelCard` 「Enviado a ad••@gmail.com · **Cambiar**」 → 인라인 입력 + 「Enviar código」/「Cancelar」.
  성공 시 마스킹 갱신·코드 입력칸 비움·쿨다운 60초.

### (b) 재신청 시 막지 않기
안전성 기준: 미검증 신청은 아무것도 증명하지 않은 상태 → **대체해도 탈취가 생기지 않는다**(새 행도 자기 코드를 다시 받아야 한다).

- **B1 (권장·서버 무변경)**: token 을 `sessionStorage` 에 보관 → 새로고침/뒤로가기 후에도 코드 화면으로 복귀
  (`GET /onboarding/status/:token` 이 이미 있다). 「Volver a editar datos」 는 (a) 와 같은 원리로 서버에 **PATCH** 해야
  하므로 1차는 이메일·전화 정정만 제공.
- **B2 (권장·서버)**: `start` 의 중복이 **오직** `status='contact_pending' AND email_verified_at IS NULL AND
  created_store_id IS NULL` 인 행들뿐이면, 같은 트랜잭션에서 그 행들을 `expired` 로 내리고 새로 만든다
  (새 status 값을 만들지 않는다 — `pending-login-status` 등 소비처가 이미 `expired` 를 안다). 로그 + `superseded_by` 없이 logger 만.
  - 이메일이 검증된 신청이 걸리면 지금처럼 409 유지.
  - 응답은 신규와 **완전히 동일**(대체 여부 노출 금지 → 열거 방지).
- 남용: 제3자가 남의 미검증 신청을 밀어낼 수 있다 = 피해는 «처음부터 다시» 뿐. 오히려 지금은 제3자가 남의 CUIT 로
  24시간 **점거**할 수 있는데 B2 가 그것을 푼다. 대량 시도는 전역 600/분/IP 뿐이므로 `start`·`contact/change`
  ·`otp/send` 에 `@Throttle`(예: 10/분/IP) 추가 권장.
- **B3 (보류)**: 이메일까지 검증된 신청의 이어하기 = 기존 이메일로 «continuar» 링크 발송. 범위가 커서 2차.

### (c) 엣지 케이스
- 전화 오입력도 똑같다 → 같은 엔드포인트의 `channel:'whatsapp'`. 단 서버에 WhatsApp 발송이 미설정이면 이미 자동 검증돼
  변경 불가(검증 후 변경 금지 규칙) — 미설정 상태에서는 전화 변경 버튼을 숨기거나 「verificado」 로 둔다.
- 이메일이 이미 `users.email` 에 있으면 지금도 `provisionarAhora` 가 개통을 **조용히 보류**(`onboarding-alta.service.ts:74-83`).
  변경 시점에 막을지(열거 위험) 여부는 결정 필요 — 권장: 막지 않고 지금처럼 보류.
- 코드 발송 도중 변경: 이전 코드 행 삭제 후라 옛 메일의 코드는 `OTP_NOT_FOUND`.
- 두 탭: 한쪽이 B2 로 대체되면 다른 탭은 `ONBOARDING_NOT_EDITABLE` — 문구를 «Este registro fue reemplazado. Recargá» 로.

## 4. 변경 파일
- api: `onboarding-verification.service.ts`(changeContact, start B2), `onboarding.controller.ts`(라우트·@Throttle),
  `dto/otp.dto.ts`(ChangeContactDto), `pending-registration.model.ts`(contactChanges, `type` 명시)
- migration: `api-ventago/migrations/2026-10-2x-pending-registrations-contact-changes.sql` (ADD COLUMN nullable/default, `SET lock_timeout`)
  — **모델에 컬럼을 넣으므로 마이그레이션(로컬+운영) 먼저, push 나중.**
- app: `RegisterForm.tsx` (OtpChannelCard 변경 UI, sessionStorage token 복귀)

## 5. 테스트 (신규 `onboarding-verification.service.spec.ts` — 하네스 사용)
1. 미검증 이메일 변경 → email 갱신, 이전 코드 행 삭제, 새 코드 발송 1회.
2. 검증된 채널 변경 → 400. 3. 다른 진행중 신청의 이메일로 변경 → 일반 409(필드 미노출).
4. 4번째 변경 → 거부. 5. 만료/approved token → 거부.
6. B2: 미검증 행과 CUIT 충돌 → 옛 행 expired, 새 token. 7. 이메일 검증된 행과 충돌 → 409 유지.
8. B2: `created_store_id` 있는 행은 절대 대체 안 함. 9. 대체/신규 응답 형태 동일(키 집합 비교).
대조군: 변경 로직을 제거한 돌연변이에서 1·6 이 실패하는지 확인.

## 6. 위험
- 열거: 409 는 지금도 «존재» 를 알려준다. B2 로 409 가 줄어 오히려 감소. 변경 API 의 409 도 필드 비노출 유지.
- 스팸: 변경 3회 + 쿨다운 + IP throttle. 메일 폭탄 표면은 `start` 와 같은 수준.
- B2 오판: 조건에 `created_store_id IS NULL` 누락 시 개통 매장이 심사에서 빠진다(`expireStaleFor` 주석의 사고와 동형) — 테스트 8 로 고정.

## 7. 규모
api 반나절(서비스 ~120줄 + spec) · app 2~3시간 · 마이그레이션 1개. 합계 약 1일.

## 사용자 결정 필요
1. B2(미검증 신청 자동 대체) 채택 여부 — 아니면 B1(토큰 보관)만.
2. 변경 상한 3회 · 컬럼 추가 OK?
3. 전화번호 변경도 같이 넣을지.
