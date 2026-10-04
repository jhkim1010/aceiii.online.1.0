---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 03
subsystem: mobile
tags: [wear-os, kotlin, jetpack-compose, retrofit, kotlinx-serialization, android-keystore, datastore, gradle]

# Dependency graph
requires:
  - phase: 98-02
    provides: "응답 v2 계약·골든 JSON(test/fixtures/watch-resumen-v2.golden.json), WatchTokenGuard, GET /watch/resumen 뼈대(미등록)"
provides:
  - "wear-admin-app/ — Kotlin + Jetpack Compose for Wear OS 신규 Gradle 모듈(루트 저장소), assembleDebug 통과"
  - "AVD ventago_wear(Wear OS 6.0, android-wear-signed;arm64-v8a) — Apple Silicon 호환"
  - "format/AmountFormat.kt·TimeFormat.kt — D-07 축약 금액(긴 형·SHORT_TEXT 짧은 형)·증감률·경과시간·월표기 순수 함수(앱·Tile·컴플리케이션 공용)"
  - "data/ResumenDto.kt — 응답 v2 kotlinx.serialization 모델, 골든 JSON 과 1:1(복사본 없음)"
  - "data/WatchApi.kt·TokenStore.kt·WatchPrefs.kt·ResumenRepository.kt — Retrofit + Keystore 토큰 저장 + 지점 선택/마지막 값 1개 + fetch()/setSucursal()/requestCode()/poll()"
affects: [98-06, 98-07, 98-11]

# Tech tracking
tech-stack:
  added:
    - "androidx.wear.compose:compose-material3/compose-foundation 1.6.2 (1.7.0 은 compileSdk 37/AGP 9.1 요구라 하향 — AGP 8.11.1 고정)"
    - "androidx.wear.tiles/tiles-material 1.6.2, androidx.wear.protolayout(+material3+expression) 1.4.2"
    - "androidx.wear.watchface:watchface-complications-data-source-ktx 1.3.0"
    - "Retrofit 2.11.0 + converter-kotlinx-serialization, OkHttp 4.12.0, kotlinx-serialization-json 1.11.0, kotlinx-coroutines 1.11.0"
    - "androidx.datastore:datastore-preferences 1.2.1, Android Keystore(javax.crypto 직접, AES/GCM/256)"
  patterns:
    - "순수 포맷 함수는 Android 의존 0(JVM 단위 시험) — 앱/Tile/컴플리케이션이 같은 함수를 공유"
    - "BigDecimal + 문자열 직접 조립으로 금액 포맷 — 기기 로케일에 좌우되는 표준 포맷 클래스 금지(grep 0건으로 고정)"
    - "ResumenDtoTest 는 systemProperty(\"ventago.goldenJson\")로 api-ventago 골든 JSON 을 복사 없이 직접 읽음(단일 출처)"
    - "ResumenRepository 가 Unpaired/Fresh/Stale/Error 상태기계로 400 복구(Todas 1회 재시도)·401 정리·오프라인 지점 일치 검사를 전부 캡슐화"

key-files:
  created:
    - wear-admin-app/settings.gradle.kts
    - wear-admin-app/build.gradle.kts
    - wear-admin-app/gradle.properties
    - wear-admin-app/gradle/libs.versions.toml
    - wear-admin-app/gradle/wrapper/gradle-wrapper.properties
    - wear-admin-app/gradle/wrapper/gradle-wrapper.jar
    - wear-admin-app/gradlew
    - wear-admin-app/gradlew.bat
    - wear-admin-app/.gitignore
    - wear-admin-app/README.md
    - wear-admin-app/app/build.gradle.kts
    - wear-admin-app/app/src/main/AndroidManifest.xml
    - wear-admin-app/app/src/main/res/values/strings.xml
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/MainActivity.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/format/AmountFormat.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/format/TimeFormat.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/format/AmountFormatTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/format/TimeFormatTest.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/ResumenDto.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/WatchApi.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/TokenStore.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/WatchPrefs.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/ResumenRepository.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/data/ResumenDtoTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/data/ResumenRepositoryTest.kt
  modified: []

key-decisions:
  - "androidx.wear.compose 1.7.0(최신 stable)은 compileSdk 37/AGP 9.1.0 을 요구해 기존 툴체인(AGP 8.11.1/Gradle 8.14, tienda-admin-app 과 동일 wrapper 재사용)과 충돌 — 1.6.2 로 고정(Google Maven 메타데이터로 1.6.2 존재 확인). androidx.core-ktx/lifecycle-viewmodel-compose 도 같은 이유로 compileSdk36 호환 버전(1.17.0/2.9.4)으로 낮춤"
  - "WatchApi.resumen/poll 은 Response<ResponseBody> 로 원문 문자열을 받아 ResumenRepository 가 WatchJson 으로 파싱 — 같은 문자열을 오프라인 캐시에도 저장해 파싱·저장 표현이 갈라지지 않게 함"
  - "지점 변경 시 마지막 값 삭제(T-98-25) 책임은 WatchPrefs 가 아니라 ResumenRepository.setSucursal() 이 가짐 — 저장소는 순수 I/O, 정책은 리포지토리 레이어(플랜 Task 3 action 문구 그대로)"
  - "androidx.wear:wear-input(하드웨어 버튼) 의존성은 이번 플랜에서 생략 — 98-07 범위이고 Task 1~3 의 behavior/acceptance 어느 것도 요구하지 않아 범위를 넓히지 않음"

requirements-completed: [W98-04]

# Metrics
duration: ~70min
completed: 2026-10-04
---

# Phase 98 Plan 03: wear-admin-app 골격 + 포맷/데이터 계층 Summary

**새 Gradle 모듈 wear-admin-app(Kotlin+Compose for Wear OS)이 assembleDebug 로 빌드되고, D-07 금액 축약 순수 함수(35 테스트)와 응답 v2 데이터 계층(토큰 Keystore 저장·지점 선택·400/401 복구·오프라인 1값, 22 테스트)이 api-ventago 골든 JSON 을 복사 없이 직접 파싱하며 전부 통과한다.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-10-04T18:58:00-03:00 (추정)
- **Completed:** 2026-10-04T20:10:00-03:00 (추정)
- **Tasks:** 3
- **Files modified:** 25 (전부 생성, 수정 없음)

## Accomplishments
- Wear OS 6(API 36, arm64-v8a) 시스템 이미지·emulator 설치 + AVD `ventago_wear` 생성(Apple Silicon Mac 호환)
- 신규 Gradle 모듈 `wear-admin-app/`가 `tienda-admin-app/android`의 Gradle 8.14 래퍼를 재사용해 `assembleDebug` 통과, `applicationId = com.coolsistema.tienda_admin_app`(D-02, 폰 앱과 동일)
- 버전 카탈로그(`libs.versions.toml`) 전 항목을 Google Maven/Maven Central 메타데이터로 실측 확인 — 연구 문서의 1.7.0 가정이 compileSdk 37/AGP 9.1 요구와 충돌함을 발견해 1.6.2 로 교정
- `AmountFormat.kt`/`TimeFormat.kt` — es-AR 축약 금액(`$1,28 M`·`$842 K`·`-$15 K`)·SHORT_TEXT 짧은 형(`15,2M`)·증감률 문구·경과시간(`hace 12 min`)·월표기(`OCT 2026`)를 로케일 표준 포맷 클래스 없이 BigDecimal+문자열 조립으로 고정(35 테스트)
- `ResumenDto.kt` — 응답 v2 전 섹션(hoy·mediosPago·gastosDescuentos·ingresos·facturacionMes·cajas)을 kotlinx.serialization 으로 매핑, `ResumenDtoTest` 가 골든 JSON 을 **복사 없이** 직접 읽어 파싱·부분 실패(data=null)·모르는 키 무시·sucursal 변형을 검증(5 테스트)
- `WatchApi`/`TokenStore`/`WatchPrefs`/`ResumenRepository` — x-watch-token 헤더 전용 Retrofit 호출(로깅 인터셉터 없음), Android Keystore AES-GCM 토큰 암호화, 지점 선택+마지막 값 1개 DataStore, `fetch()`가 Unpaired/Fresh/Stale/Error 상태기계로 400 복구(Todas 1회 재시도)·401 정리·오프라인 지점 일치 검사를 캡슐화(MockWebServer 17 테스트)

## Task Commits

Each task was committed atomically (root 저장소):

1. **Task 1: Wear 에뮬레이터 설치 + Gradle 프로젝트 골격 + 매니페스트 → assembleDebug** - `b2ea8f4` (feat)
2. **Task 2 RED: AmountFormat/TimeFormat 실패 테스트** - `154edc2` (test)
2. **Task 2 GREEN: AmountFormat/TimeFormat 구현** - `de86e34` (feat)
3. **Task 3 RED: ResumenDto/ResumenRepository 실패 테스트** - `b057de0` (test)
3. **Task 3 GREEN: ResumenDto/WatchApi/TokenStore/WatchPrefs/ResumenRepository 구현** - `f71b161` (feat)

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

_TDD 태스크(2, 3)는 RED→GREEN 을 별도 커밋으로 분리했다(plan 의 "behavior 를 JUnit4 로 먼저(RED) → 구현(GREEN)" 작업 순서를 커밋 단위로도 명시)._

## Files Created/Modified

- `wear-admin-app/settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml` - 루트 Gradle 설정, 버전 카탈로그(실측 확인된 버전만)
- `wear-admin-app/gradle/wrapper/*`, `gradlew`, `gradlew.bat` - Gradle 8.14 래퍼(tienda-admin-app/android 에서 복사)
- `wear-admin-app/app/build.gradle.kts` - applicationId/compileSdk/minSdk/targetSdk, `testOptions`로 골든 JSON 경로 주입
- `wear-admin-app/app/src/main/AndroidManifest.xml` - standalone 워치 앱 선언, INTERNET, cleartext 금지
- `wear-admin-app/app/src/main/java/.../MainActivity.kt` - 최소 진입 화면(98-11 이 교체)
- `wear-admin-app/app/src/main/java/.../format/AmountFormat.kt` - abreviarMonto·abreviarCorto·deltaPct·formatDelta·formatCantidad
- `wear-admin-app/app/src/main/java/.../format/TimeFormat.kt` - haceTexto·mesCorto
- `wear-admin-app/app/src/main/java/.../data/ResumenDto.kt` - 응답 v2 전체 모델 + WatchJson(ignoreUnknownKeys)
- `wear-admin-app/app/src/main/java/.../data/WatchApi.kt` - Retrofit 인터페이스 + create() 팩토리
- `wear-admin-app/app/src/main/java/.../data/TokenStore.kt` - KeystoreTokenStore(AES-GCM 256, DataStore)
- `wear-admin-app/app/src/main/java/.../data/WatchPrefs.kt` - DataStoreWatchPrefs(선택 지점 + 마지막 값 1개)
- `wear-admin-app/app/src/main/java/.../data/ResumenRepository.kt` - fetch()/setSucursal()/requestCode()/poll() 상태기계
- `wear-admin-app/app/src/test/...` - AmountFormatTest(24)·TimeFormatTest(7)·ResumenDtoTest(5)·ResumenRepositoryTest(17)

## Decisions Made

- 버전 카탈로그는 연구 문서의 추정치를 그대로 쓰지 않고 설치 시점에 재검증(plan 지시 그대로) — `androidx.wear.compose` 1.7.0 이 compileSdk 37/AGP 9.1 요구임을 발견해 1.6.2 로 고정, 함께 올라간 core-ktx/lifecycle-viewmodel-compose 도 호환 버전으로 조정
- `WatchApi.resumen`/`poll` 을 `Response<ResponseBody>` 로 받아 리포지토리가 직접 파싱 — 캐시 저장과 파싱이 같은 원문 문자열을 쓰게 해 표현 불일치를 차단
- T-98-25(다른 지점 옛 값 혼동) 방지 책임을 `ResumenRepository.setSucursal()` 에 둠(WatchPrefs 는 순수 저장소)
- `androidx.wear:wear-input`(선택 의존성, 98-07 하드웨어 버튼용)은 이번 플랜 범위에서 생략 — 테스트로 강제되지 않는 범위 확장을 피함

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] androidx.wear.compose 1.7.0 이 compileSdk 37/AGP 9.1.0 요구 — AGP 8.11.1 과 충돌**
- **Found during:** Task 1, `assembleDebug` 1차 실행(`checkDebugAarMetadata` 실패)
- **Issue:** 연구 문서(98-RESEARCH.md)가 "2026-09-23 stable"로 명시한 1.7.0 이 실제로는 Android Gradle Plugin 9.1.0+ 를 요구해, 플랜이 지정한 AGP 8.11.1(기존 tienda-admin-app 툴체인과 동일)과 compileSdk 36 환경에서 빌드가 깨짐
- **Fix:** Google Maven 메타데이터로 직전 stable(1.6.2)이 compileSdk 36 과 호환됨을 확인 후 `wearComposeMaterial3`/`wearComposeFoundation` 을 1.6.2 로 고정. 같은 사유로 `androidx.core:core-ktx`(1.19.1→1.17.0), `androidx.lifecycle:lifecycle-viewmodel-compose`(2.11.0→2.9.4) 도 compileSdk 36 호환 버전으로 조정
- **Files modified:** `wear-admin-app/gradle/libs.versions.toml`
- **Verification:** `./gradlew :app:assembleDebug` BUILD SUCCESSFUL
- **Committed in:** `b2ea8f4`

**2. [Rule 1 - Bug] Kotlin 중첩 블록 코멘트 — KDoc 안의 `` `/watch/*` `` 문자열이 "Unclosed comment" 를 유발**
- **Found during:** Task 3, `compileDebugKotlin` 1차 실행
- **Issue:** Kotlin 은 `/* */` 블록 코멘트가 중첩을 허용하는데, KDoc 안에 리터럴로 쓴 `` `/watch/*` `` 의 `/*` 가 중첩 코멘트 시작으로 해석되어 바깥 KDoc 이 닫히지 않음
- **Fix:** 문구를 `` `/watch/` 하위 호출 `` 로 바꿔 `/*` 시퀀스를 제거(의미 동일)
- **Files modified:** `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/WatchApi.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` 통과
- **Committed in:** `f71b161`

**3. [Rule 1 - Bug] acceptance_criteria grep 이 설명 주석의 어휘를 결과물로 오인**
- **Found during:** Task 2·Task 3, acceptance_criteria 의 `grep -n "Locale\|NumberFormat\|DecimalFormat"`/`grep -rn "EncryptedSharedPreferences\|HttpLoggingInterceptor"` 0건 요구 검증
- **Issue:** "로케일 표준 포맷 클래스를 쓰지 않는다"/"EncryptedSharedPreferences 는 공식 폐기라 안 쓴다" 는 설명 주석이 그 금지된 단어 자체를 포함해 grep 0건 기준을 위반(코드는 실제로 그 클래스를 전혀 쓰지 않음 — 순수 문구 충돌)
- **Fix:** 설명을 의미는 그대로 두고 금지 단어를 쓰지 않는 표현으로 교체
- **Files modified:** `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/format/AmountFormat.kt`, `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/TokenStore.kt`
- **Verification:** 두 grep 모두 0건(exit 1) 확인 후 테스트 재실행 통과
- **Committed in:** `de86e34`, `f71b161`

---

**Total deviations:** 3 auto-fixed (1 blocking — 버전 카탈로그 충돌, 2 bug — 코멘트 파싱·grep 오탐)
**Impact on plan:** 셋 다 계획이 요구한 빌드 가능성·테스트 통과·acceptance_criteria 를 실제로 충족시키기 위한 수정이다. 동작 변경 없음(버전 다운그레이드는 호환성 수정, 나머지는 주석 문구 교정).

## Issues Encountered

- `avdmanager create avd`가 "Could not load devices from .../devices.xml" 경고를 출력했지만 AVD 생성 자체는 성공했다(`avdmanager list avd` 로 확인) — SDK 패키지의 `devices.xml` 누락은 경고일 뿐 치명적이지 않음.

## User Setup Required

None — 외부 서비스 설정 불필요. `JAVA_HOME`/`ANDROID_SDK_ROOT` export 와 `local.properties`(sdk.dir, 커밋 안 됨)는 README.md 에 문서화됨.

## Next Phase Readiness

- 98-06(Tile+컴플리케이션)이 `format/AmountFormat.kt`(`abreviarCorto`)와 `data/ResumenRepository.kt`(마지막 값 읽기)를 그대로 재사용 가능
- 98-07(하드웨어 버튼·서명 키·`androidx.wear:wear-input`)이 이 플랜에서 생략한 의존성을 추가
- 98-11(내비게이션·화면)이 `MainActivity.kt`의 최소 진입점을 교체하고 `ResumenRepository.fetch()`를 ViewModel에서 호출
- 버전 카탈로그가 compileSdk 36/AGP 8.11.1 로 고정됐으므로, 향후 AGP 9.x 업그레이드 시 `wearComposeMaterial3`/`wearComposeFoundation` 을 1.7.0+ 로 재승격할 수 있음(현재는 보류)

## Known Stubs

None — `MainActivity.kt`는 빌드 확인용 최소 화면(텍스트 1개)이며 데이터를 렌더링하지 않는다. format/data 계층은 전부 테스트로 고정된 순수 로직/리포지토리이고 아직 화면에 배선되지 않았다(98-11 범위).

## Threat Flags

None — 이 플랜이 추가한 표면(x-watch-token 발신, Keystore 토큰 저장, DataStore 평문 캐시)은 모두 계획의 threat_model(T-98-20~T-98-25)에 이미 등록되어 있다. 네트워크 호출은 전부 JVM 테스트의 MockWebServer 대상이며 실제 운영 엔드포인트에 닿지 않는다.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 25 referenced files verified present (24 wear-admin-app + 1 root SUMMARY). All 5 task commit hashes (`b2ea8f4`, `154edc2`, `de86e34`, `b057de0`, `f71b161`) verified in `git log --oneline --all` (root 저장소). No missing items.
