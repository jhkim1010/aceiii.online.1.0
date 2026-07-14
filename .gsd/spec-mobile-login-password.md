# SPEC: 판매원 앱 로그인 PIN → 일반 암호 전환
생성일: 2026-07-14

## 목표
모바일 판매원 앱 로그인을 users.mobile_pin(PIN) 대신 웹과 동일한 users.password(bcrypt)로 인증. PIN·set-pin 경로 제거(암호 단일 — 사용자 확정).

## 배경
- loginMobile 3단계에서 dto.pin vs user.mobilePin 대조 → dto.password vs user.password 로 변경
- set-pin 은 Phase 37 베타 세팅용 관리자 API — 제거
- users.mobile_pin 컬럼은 DB에 남김(마이그레이션 불필요, 무해)
- 배포 주의: API 배포 시 구버전 앱(pin 전송)은 로그인 불가 — 베타 2명뿐이라 앱 재배포와 동시 진행

## 기술 스택
- NestJS(api-ventago/src/app/mobile) + Flutter(mobile-sales-app). DB 변경 없음(pool 영향 없음)
- 검증: agent-runner `api-verify`(tsc+jest mobile 포함), flutter 빌드

## 태스크
- [ ] T1 mobile-login.dto.ts: pin → password
- [ ] T2 mobile-auth.service.ts: 암호 대조·에러문구·setMobilePin 제거
- [ ] T3 mobile-auth.controller.ts: set-pin 엔드포인트·잔여 import 제거
- [ ] T4 mobile-auth.service.spec.ts: password 기준으로 테스트 갱신(mobile_pin NULL·setMobilePin 테스트 삭제)
- [ ] T5 mobile-set-pin.dto.ts: 사용중지 스텁으로 대체(브리지 삭제 불가)
- [ ] T6 Flutter: auth_dto/auth_repository/scope_provider/login_screen 암호 필드 전환
- [ ] T7 api-verify(러너) 통과 + flutter macOS/APK 재빌드·재배포
- [ ] T8 pool 점검(해당 없음 확인) / 로그 확인

## 완료 기준
- api-verify(tsc+jest) 통과, 앱에서 이메일+웹 암호 로그인 성공
