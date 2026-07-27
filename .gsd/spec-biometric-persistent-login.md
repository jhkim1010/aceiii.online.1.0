# SPEC: admin 앱 잦은 로그아웃 수정 — 지문 자격증명 보존
생성일: 2026-07-26

## 목표
superadmin(ventago-admin-app)·매장 admin(tienda-admin-app) 앱에서 토큰 만료(6h) 후에도
지문 한 번으로 재진입 가능하게 한다. (한 번 로그인 → 이후 지문만)

## 배경 및 컨텍스트
- 지문 로그인(biometric_service + savedUser/savedPass 저장)은 이미 양 앱에 구현·커밋됨.
- 근본 원인: `dio_client.dart` 401 인터셉터가 `storage.deleteAll()` 호출 →
  지문용 자격증명(admin_saved_user/pass)까지 삭제 → canUseBiometric()=false → 비밀번호 재입력 강제.
- 부수 버그: 비밀번호 오입력으로 /auth/login 이 401 을 반환해도 같은 핸들러가
  "Sesión expirada" 스낵바 + 전체 삭제 수행.
- 백엔드 JWT 6h 만료는 웹 POS 와 공유 정책 → 변경하지 않음 (지문 게이트로 UX 해결).
- DB/pool 영향 없음. 마이그레이션 없음.

## 기술 스택
- Flutter (Riverpod, dio, flutter_secure_storage, local_auth)
- ESLint 해당 없음 → dart analyze 로 검증

## 태스크 목록
- [x] TASK-1: ventago-admin-app dio_client.dart — 401 시 토큰만 삭제, /auth/login 요청은 제외
- [x] TASK-2: tienda-admin-app dio_client.dart — 동일 수정
- [x] TASK-2b: 양 앱 auth_controller — sessionExpiredSignal 리스너 배선 (401 → 로그인 화면 → 자동 지문 프롬프트)
- [x] TASK-3: dart analyze 양 앱 통과 (러너: tienda=No issues, admin=기존 info 10건만·이번 변경 무관)
- [x] TASK-4: APK 빌드 + Dropbox 복사 (superadmin→Personal de m. Marcos, tienda→app herramientas download)
- [ ] TASK-5: 커밋/push — 루트 .git/index.lock stale 로 보류, 사용자 Mac 에서 실행 필요

## 완료 기준
- 401 후에도 secure storage 에 saved_user/saved_pass 잔존 → 로그인 화면 자동 지문 프롬프트 동작
- 로그인 실패 시 "Sesión expirada" 스낵바 미출현
- dart analyze 오류 0

## 금지사항 / 주의사항
- 백엔드 expiresIn 변경 금지 (웹 공유 정책)
- SessionGuard / x-session-token 추가 금지 (양 앱 JWT-only 확정)
- 실기기 반영은 APK 재빌드 + 재설치 필요 (Mac flutter build)
