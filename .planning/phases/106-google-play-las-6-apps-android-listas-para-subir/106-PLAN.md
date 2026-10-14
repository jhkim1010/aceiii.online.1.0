# Phase 106 — Google Play: 6개 Android 앱 등록 준비

작성 2026-10-13 · 요청: 「모든 소속된 안드로이드 앱을 구글 플레이 스토어에 등록할 수 있도록 파일을 준비해줘」

## 0. 대상 (실측)

| 앱 | applicationId | 버전 | 성격 | Play 공개 범위(기본안) |
|---|---|---|---|---|
| mobile-sales-app (서브모듈) | com.ventago.mobile_sales_app | 1.1.0+9 | 판매원·재판매자 POS | 공개(무료) |
| tienda-admin-app | com.coolsistema.tienda_admin_app | 1.0.1+3 | 매장 관리자 | 공개(무료) |
| wear-admin-app (Wear OS) | **같은** com.coolsistema.tienda_admin_app | 1.0.0 (1) | 워치 — 위 앱의 Wear 폼팩터 | 위 앱의 Wear 트랙 (Phase 98-07) |
| despacho-app | com.coolsistema.despacho_app | 0.1.0+1 | 창고 피킹·배송 | 공개(무료) |
| talleres-vendor-app | com.coolsistema.talleres_vendor_app | 1.0.0+1 | 외주 공방 포털 | 공개(무료) |
| ventago-admin-app | com.coolsistema.ventago_admin_app | 1.1.2+5 | **superadmin 전용** | **내부 테스트만**(공개 안 함) |

`mobile-sales-app.bak` 은 대상 아님. 업로드 키: `~/android-keys/upload-keystore.jks`(저장소 밖, c8f4ad6 에서 5개 앱에 배선됨).

## 1. Play 가 거절하는 것 — 먼저 고친다

| # | 문제 | 앱 | 조치 |
|---|---|---|---|
| B1 | `REQUEST_INSTALL_PACKAGES` + 앱 자체 APK 업데이트(`core/update/actualizacion.dart`) — Play 정책상 스토어 밖 자기 업데이트 금지 | mobile-sales · tienda-admin · ventago-admin | **Play 채널 빌드**만 권한 제거(`-Pplay=true` → release 매니페스트 `tools:node="remove"`) + 업데이트 확인 꺼짐(`--dart-define=CANAL_PLAY=true`). 직접 배포 APK 는 지금 그대로 |
| B2 | 개인정보처리방침 URL 없음 — 로그인·위치(판매앱) 수집 앱은 필수 | 전부 | 공개 페이지 초안 `play-store/politica-de-privacidad.md` → 호스팅 위치는 사용자 결정 |
| B3 | 기기 표시 이름이 `despacho_app` 등 개발용 | 4개 | `android:label` 정리 |
| B4 | 워치 AAB 서명 없음 · versionCode 가 휴대폰과 겹칠 수 있음 | wear | 같은 업로드 키 블록 + versionCode 대역 분리 |

targetSdk 36 / minSdk 24 (Flutter 기본) — 2026 Play 요건 충족.

## 2. 산출물 (`play-store/`)

```
play-store/
  README.md                     업로드 순서·체크리스트
  politica-de-privacidad.md     공개 페이지 초안 (es)
  build-aab.sh                  Play 채널 AAB 일괄 빌드 + 서명·권한 검사
  <app>/ficha-es-419.md         이름(≤30) · 짧은 설명(≤80) · 전체 설명(≤4000)
  <app>/data-safety.md          데이터 보안 양식 답안
  <app>/clasificacion.md        콘텐츠 등급 설문 답안
  <app>/icono-512.png           고해상도 아이콘
  <app>/grafico-1024x500.png    그래픽 이미지
  out/<app>-<versión>.aab       서명된 번들 (커밋 안 함)
```

## 3. 사람이 해야 하는 것 (Claude 가 못 하는 것)
- Play 개발자 계정(US$25·본인 확인), 앱 생성, Play App Signing 동의
- 스크린샷(휴대폰 2장 이상) — 실기기/에뮬레이터에서 실제 매장 데이터로
- 개인정보처리방침 공개 URL 결정
- 테스터 이메일 목록(내부 테스트)

## 4. 검증
- 각 AAB: `jarsigner -verify` 로 업로드 키 서명 확인, bundletool 로 매니페스트에 `REQUEST_INSTALL_PACKAGES` **없음** 확인
- 대조군: Play 플래그 없이 빌드하면 권한이 **있다**(검사가 실제로 보는지)
- 기존 직접 배포 경로(APK + 자체 업데이트)는 바뀌지 않는다
