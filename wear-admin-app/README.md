# wear-admin-app

Galaxy Watch(Wear OS) 매장 admin 앱 — Kotlin + Jetpack Compose for Wear OS.
`applicationId = com.coolsistema.tienda_admin_app`(D-02 — 휴대폰 앱과 동일).

## 빌드 환경

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
```

`local.properties` 는 `sdk.dir`만 담고 커밋하지 않는다(`.gitignore`).

```properties
sdk.dir=/opt/homebrew/share/android-commandlinetools
```

## 빌드 / 테스트

```bash
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest   # api-ventago 서브모듈이 체크아웃돼 있어야 골든 JSON 시험이 돈다
```

JVM 단위 시험(`ResumenDtoTest`)은 `api-ventago/test/fixtures/watch-resumen-v2.golden.json` 을
복사본 없이 직접 읽는다(Gradle `systemProperty("ventago.goldenJson", ...)`).

## Wear 에뮬레이터

```bash
$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/emulator -avd ventago_wear
```

AVD 이름: `ventago_wear` (Wear OS 6 / API 36, arm64-v8a, Apple Silicon 호환).

## CI

GitHub Actions 는 결제 문제로 이 저장소에서 돌지 않는다(메모리: github-actions-not-running-billing).
검증은 로컬 Gradle 명령으로 한다.
