# SPEC: 판매원 앱(mobile-sales-app) 배포 — OS별 설치 파일 + 운용서버 전용
생성일: 2026-07-10

## 목표
판매원 앱을 각 OS 설치 파일(Android/Windows/macOS/iOS)로 배포하고, 배포본은 운영 API 를 바라보게 한다.
로컬 개발은 localhost 기본값을 그대로 유지한다(배포본만 prod — 사용자 확정, 2026-07-10).

## 배경
- 기존 패턴: `.github/workflows/build-admin-app.yml`(admin-app-v* 태그 → Android/Win/macOS 빌드, `--dart-define=BASE_URL=<prod>`, `jhkim1010/ventago-downloads` 릴리스 업로드)를 미러링.
- 다운로드 UI: `ventago-app/src/pages/herramientas/print-agent/index.tsx`(이름과 달리 통합 "Descargas" 페이지). `programs[]` 에 프로그램별 `downloads[]`(os/icon/fileName). GitHub 릴리스 자동 연동 + 폴백.
- 발견: mobile-sales-app 카드는 **이미 존재했으나 Android 만** 있었고, 정작 **빌드 워크플로우가 없어** 링크가 죽어 있었음(git 전체 이력에도 build-mobile-sales-app.yml 없음 — 기존 메모리와 불일치).
- 앱 기본 BASE_URL: `mobile-sales-app/lib/core/config/api_config.dart` = `http://localhost:5002/api`(String.fromEnvironment, 빌드시 override 가능).

## 태스크
- [x] TASK-1: `.github/workflows/build-mobile-sales-app.yml` 신규 — mobile-sales-app-v* 태그 트리거.
      Android APK / Windows zip / macOS zip 모두 `--dart-define=BASE_URL=https://newapi.coolsistema.com/api`.
      산출물명 `VentaGO-Ventas.apk` / `-Windows.zip` / `-macOS.zip` (프론트 카드 규칙과 일치).
      macOS 잡은 macos 스캐폴드 없을 때 자동 생성 + network.client entitlement 패치 포함.
      iOS 는 `--no-codesign` 컴파일 검증 잡만(릴리스 업로드 X — 미서명 설치 불가).
- [x] TASK-2: 다운로드 카드 확장 — `herramientas/print-agent/index.tsx` mobile-sales-app 섹션에
      Windows/macOS/iOS 추가. `DownloadItem.href?`(외부링크) 추가 → iOS 는 TestFlight 링크 방식,
      `IOS_TESTFLIGHT_URL` 미설정 시 "Próximamente" 비활성 버튼.
- [ ] TASK-3: (사용자) ESLint 검증 — 샌드박스가 Mac 툴체인에 못 닿아 원격 실행 불가.
      `cd ventago-app && npx eslint src/pages/herramientas/print-agent/index.tsx --fix`
- [ ] TASK-4: (사용자) iOS TestFlight — Apple Developer 계정에서 TestFlight 그룹 공개 초대 링크 생성 →
      `IOS_TESTFLIGHT_URL` 교체. (미설정이면 iOS 카드는 "Próximamente" 로 안전하게 표시됨)
- [ ] TASK-5: 릴리스 트리거 — `git tag mobile-sales-app-v1.0.0 && git push origin mobile-sales-app-v1.0.0`.
      단, 기존 메모리상 이 태그는 **vendedor 인증 전환 이후로 보류** 결정됨 → 순서 확인 후 진행.
- [ ] TASK-6: RELEASE_REPO_TOKEN secret 이 GitHub 에 설정돼 있는지 확인(admin/despacho 와 공유).

## 완료 기준
- 태그 push 시 3-OS 바이너리가 ventago-downloads 릴리스에 올라가고, Descargas 페이지에서 자동 링크됨.
- 배포 바이너리는 운영 API 접속(로컬 dev 는 localhost 유지).
- ESLint 오류 0.

## 주의 / 함정
- 브랜치: 현재 feat/factura-electronica. Admin 메뉴/Integraciones·다운로드 관련 작업이 다른 브랜치에 있을 수 있음(메모리) → 머지 충돌 주의, 카드 중복 정의 확인.
- iOS 는 단순 다운로드 설치 불가(서명/TestFlight 필수) — 자동화는 Apple Developer secret 준비 후 별도.
- macOS 배포본은 미서명 → Gatekeeper 경고(우클릭 열기 안내 필요). 정식 배포는 서명/notarize.
- pool: 이 작업은 DB 무관(빌드/프론트만).
