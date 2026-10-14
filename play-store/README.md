# Google Play 등록 패키지 (Phase 106)

`.planning/phases/106-google-play-las-6-apps-android-listas-para-subir/106-PLAN.md`

## 무엇이 준비됐나

| 앱 (Play 이름) | AAB | 아이콘 512 | 그래픽 1024×500 | 설명 | Play 트랙(권장) |
|---|---|---|---|---|---|
| Ventago Ventas · `com.ventago.mobile_sales_app` | ✓ | ✓ | ✓ | ✓ | 내부 → 공개 |
| Ventago Admin · `com.coolsistema.tienda_admin_app` | ✓ 휴대폰 + ✓ Wear | ✓ | ✓ | ✓ | 내부 → 공개 (Wear 는 98-07 실기기 확인 후) |
| Ventago Despacho · `com.coolsistema.despacho_app` | ✓ | ✓ (새 아이콘) | ✓ | ✓ | 내부 → 공개 |
| Ventago Talleres · `com.coolsistema.talleres_vendor_app` | ✓ | ✓ (새 아이콘) | ✓ | ✓ | 내부 → 공개 |
| Ventago Superadmin · `com.coolsistema.ventago_admin_app` | ✓ | ✓ | ✓ | ✓ | **내부 테스트만** |

- `build-aab.sh` — Play 채널 AAB 를 만들고 **업로드 키 서명**과 **`REQUEST_INSTALL_PACKAGES` 없음**을 검사한다
  (대조군: 플래그 없이 빌드하면 권한이 있다 — 검사가 실제로 본다, 2026-10-13 확인).
- `out/` — 서명된 AAB (커밋하지 않는다, 다시 만들 수 있다)
- `<앱>/ficha-es-419.md` — 이름·짧은 설명·전체 설명 (Play 언어: Español (Latinoamérica))
- `<앱>/icono-512.png`, `<앱>/grafico-1024x500.png` — `fuentes/generar-imagenes.py` 로 다시 만든다
- `data-safety.md` — 데이터 보안·콘텐츠 등급·권한 설명 답안
- `politica-de-privacidad.md` — 공개 페이지 초안

## Play 빌드는 무엇이 다른가
| | 직접 배포 APK (지금처럼) | Play AAB |
|---|---|---|
| 앱 자체 업데이트(version.json → APK 설치) | 켜짐 | **꺼짐** (`--dart-define=CANAL_PLAY=true`) — 업데이트는 Play 가 한다 |
| `REQUEST_INSTALL_PACKAGES` | 있음 | **없음** (`-Pplay=true` → `android/app/src/play/AndroidManifest.xml`) |
| 서명 | 업로드 키 | 업로드 키 → Play App Signing 이 다시 서명 |

★ Play 로 설치한 앱은 **Google 키**로 서명된다. 그래서 같은 기기에 직접 배포 APK 를 덮어쓸 수 없다
  (서명이 달라 Android 가 거부). 한 기기는 한 경로로만 받게 할 것.

## 업로드 순서 (앱마다)
1. Play Console → 앱 만들기 → 이름·언어(es-419)·앱/무료
2. Play App Signing 동의 → `out/<앱>.aab` 를 **내부 테스트**에 올림
3. 스토어 등록정보: `ficha-es-419.md`, 아이콘, 그래픽, **휴대폰 스크린샷 2장 이상**
4. 앱 콘텐츠: 개인정보처리방침 URL · 데이터 보안(`data-safety.md`) · 등급 설문 · 대상 연령 18+ · 앱 액세스(심사 계정)
5. 내부 테스터로 설치·확인 → 프로덕션 검토 제출

## 사람이 결정·처리해야 하는 것 (막힘)
| # | 내용 | 왜 |
|---|---|---|
| B2 | 개인정보처리방침 **공개 URL** (예: `app.coolsistema.com/privacidad`) + 회사 정보 기입 | 로그인 앱은 필수 |
| B5 | **계정 삭제 경로** — Ventago Ventas 는 앱에서 재판매자 계정을 **만들 수 있다** | Play 정책: 앱에서 계정 생성 가능하면 앱 안 + 웹에서 삭제 요청 경로 필수. 지금 없음 |
| B6 | **심사용 계정** (비 superadmin, 데이터 있는 시험 매장) 앱별 1개 | 전 앱이 로그인 필수 — 없으면 심사 거절 |
| — | Play 개발자 계정 (US$25 · 본인 확인) | |
| — | 휴대폰 스크린샷 (앱당 2~8장) | 실제 화면이 필요 |
| — | 지원 이메일 | 등록정보 필수 항목 |

## 버전 올리기
Play 는 같은 versionCode 를 두 번 받지 않는다. 다시 올릴 때는 `pubspec.yaml` 의 `+N` 을 올리고
`./play-store/build-aab.sh <앱>`. Wear 는 `wear-admin-app/app/build.gradle.kts` 의 `versionCode`
(2_000_000 대역 — 휴대폰과 겹치면 거절).
