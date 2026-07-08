# Ventago Despacho App (창고 준비 앱)

venta online 주문이 **preparing** 상태로 오면 창고에서 picking → **"Listo para despacho"** 로 넘기는 소형 앱.
Flutter 단일 코드베이스로 **Android + Windows** 지원. Mac에서는 Android 에뮬레이터로 검증.

## 현재 상태 (Phase 1 — MVP 스캐폴드)

- 로그인(서버 URL + 토큰) → preparing 목록 → 상세 picking 체크리스트 → **Listo para despacho**(mark-ready)
- 백엔드는 기존 엔드포인트 재사용: `GET /online-orders/board`, `GET /online-orders/:id`, `PATCH /online-orders/:id/mark-ready`
- 다음 단계(Phase 2~4): 기기 토큰 인증, 준비 사진(MinIO), 실시간 알림(Socket.io), CI 빌드 + Herramientas Download 배포. → `.gsd/spec-despacho-app.md`

## Mac에서 처음 실행하기

이 폴더에는 `lib/` 소스와 `pubspec.yaml` 만 있습니다. 플랫폼 폴더(android/windows)는 아래로 생성합니다.

```bash
cd despacho-app

# 1) 플랫폼 스캐폴드 생성 (기존 lib/ 는 유지됨)
flutter create . --platforms=android,windows --project-name despacho_app

# 2) 의존성 설치
flutter pub get

# 3) Android 에뮬레이터 실행 (Android Studio > Device Manager 에서 하나 부팅)
flutter emulators --launch <emulator_id>
#   또는 이미 부팅돼 있으면 바로:
flutter devices

# 4) 에뮬레이터로 실행
flutter run -d emulator-5554
```

## 로그인 값 (Phase 2 — 기기 토큰)

- **Servidor (API)**:
  - macOS 데스크톱 → 로컬 API: `http://localhost:5002/api`
  - Android 에뮬레이터 → Mac 로컬 API: `http://10.0.2.2:5002/api`
  - 운영: `https://newapi.coolsistema.com/api`
- **Token de dispositivo**: 웹 **Ventas Online > (상단) Dispositivos** 에서
  "Generar" 로 기기 토큰(`dsp_...`)을 만들고 **복사** 버튼으로 복사 → 앱에 붙여넣기.
  개인 계정/JWT 만료와 무관하며 매장 전체 preparing 주문을 보여줍니다.

> 백엔드 사전 준비: `api-ventago/migrations/despacho-devices.sql` 을 DB 에 적용하고 API 를 재시작해야
> `/despacho/*` 엔드포인트가 동작합니다. (운영 적용은 별도 SSH 단계 — ALTER OWNER 포함됨)

## 품질 체크

```bash
flutter analyze      # 정적 분석 0 이슈 목표
dart format .        # 포맷
```

## Windows 빌드 (검증 후)

```bash
flutter build windows   # build/windows/runner/Release/ 에 exe
flutter build apk       # build/app/outputs/flutter-apk/app-release.apk
```

> 운영 배포는 Phase 4 에서 GitHub Actions(`build-warehouse-agent.yml`)로 자동화하고,
> Herramientas > Download 페이지 카드에서 내려받게 연결합니다.
