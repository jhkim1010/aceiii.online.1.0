---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 06
subsystem: mobile
tags: [wear-os, kotlin, protolayout, material3, tiles, complications, coroutines]

# Dependency graph
requires:
  - phase: 98-04
    provides: "AppGraph(ResumenRepository 공유), ResumenRepository.fetch()/setSucursal() 상태기계, format/AmountFormat·TimeFormat"
provides:
  - "surface/SurfaceTexts.kt — tileTexts/complicationShort/complicationLong 순수 함수 + MONTO_EN_CIRCULO=false(D-15 ⑦), 17 테스트"
  - "surface/DeviceLock.kt — isLocked(context), 요청 시점 잠금 판정(D-14 ②)"
  - "tile/ResumenTileService.kt — Material3TileService, ProtoLayout 수동 레이아웃(제목·금액·4칸·경과시간), freshness 15분"
  - "complication/VentasComplicationService.kt — SuspendingComplicationDataSourceService, SHORT_TEXT(건수)·LONG_TEXT, persistencePolicy DO_NOT_PERSIST"
  - "surface/SurfaceUpdater.kt — requestAll(context): Tile+컴플리케이션 동시 갱신 요청"
  - "ResumenRepository.onChanged 콜백 — fetch(notify)·setSucursal 이 앱/Tile/컴플리케이션 간 갱신을 전파(D-09)"
affects: [98-11, 98-12]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tile 은 androidx.wear.tiles.Material3TileService(ProtoLayout Material3 1.4) 를 상속하고 suspend fun MaterialScope.tileResponse(...) 를 확장함수로 override — 레이아웃 자체는 LayoutElementBuilders(Box/Column/Row/Text/FontStyle) 저수준 빌더로 조립(Material3 DSL인 primaryLayout/text() 는 다중 디폴트 파라미터 조합이 소스 jar 없이는 검증이 약해 위험을 낮췄다)"
    - "컴플리케이션은 SuspendingComplicationDataSourceService(watchface-complications-data-source-ktx) 를 상속 — ComplicationDataSourceUpdateRequester 는 비-ktx watchface-complications-data-source 아티팩트에 있지만 -ktx 의 API 의존성으로 전이돼 별도 선언 없이 바로 쓸 수 있음(확인: .module 메타데이터)"
    - "Tile/컴플리케이션 자신의 fetch 호출은 반드시 notify=false — 그 둘이 다시 SurfaceUpdater.requestAll 을 부르면 재귀(T-98-42)가 된다"
    - "표면 문구의 모든 분기(지점 선택·잠금·오프라인·미연결·부분실패)는 surface/SurfaceTexts.kt 한 파일에 몬다 — Tile·컴플리케이션 서비스는 그 결과만 ProtoLayout/ComplicationData 로 옮긴다"

key-files:
  created:
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/surface/SurfaceTexts.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/surface/SurfaceTextsTest.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/surface/DeviceLock.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/surface/SurfaceUpdater.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/tile/ResumenTileService.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/complication/VentasComplicationService.kt
    - wear-admin-app/app/src/main/res/drawable/tile_preview.xml
  modified:
    - wear-admin-app/app/src/main/AndroidManifest.xml
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/AppGraph.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/ResumenRepository.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/data/ResumenRepositoryTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/ui/PairingViewModelTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/ui/ResumenViewModelTest.kt

key-decisions:
  - "ProtoLayout Material3 의 primaryLayout()/text() DSL 대신 저수준 LayoutElementBuilders(Box/Column/Row/Text/FontStyle)로 직접 조립 — 두 DSL 함수는 다중 Kotlin 디폴트 파라미터(bitmask $default)를 쓰고 로컬 gradle 캐시에 sources jar 가 없어 정확한 호출 형태를 소스 없이 확신할 수 없었다. 저수준 빌더는 javap 로 직접 확인된 안정적 공개 API라 빌드 실패 반복 없이 1회에 통과했다. Material3TileService(suspend 지원)는 그대로 상속해 활용"
  - "Material3TileService.tileResponse 는 일반 메서드가 아니라 `suspend fun MaterialScope.tileResponse(...)` 확장함수 — override 시그니처도 `override suspend fun MaterialScope.tileResponse(requestParams)` 로 리시버를 맞춰야 한다(androidx.wear.tiles:tiles 1.6.2 실측, javap 로 확인)"
  - "ComplicationDisplayPolicies.DO_NOT_SHOW_WHEN_DEVICE_LOCKED 는 존재하지만 적용하지 않음 — SHORT_TEXT/LONG_TEXT 둘 다 건수뿐이라(D-15 ⑦) 가릴 금액이 없고, 숨기면 오히려 정보가 사라진다. ComplicationPersistencePolicies.DO_NOT_PERSIST 는 적용(재부팅 후 디스크에 옛 값이 남지 않게, D-14 ③)"
  - "ambient 전용 동적 값 소스(PlatformEventSources, protolayout-expression 1.4.2 실측)는 레이아웃 갱신 상태만 제공하고 ambient 여부를 직접 노출하는 dynamic boolean 이 없다 — Tile/컴플리케이션 레이어에서 ambient 진입 시 텍스트를 동적으로 가리는 플랫폼 수단은 이 버전에서 확인되지 않았다(조사 결과만 기록, D-15 ⑦ 의 건수 기본값 결정에는 영향 없음)"
  - "fetch() 에 notify: Boolean = true 파라미터 추가 — Fresh 저장 직후·401→Unpaired 직후에만 onChanged 호출(Stale/Error 는 표면이 이미 last-value 로 안정적이라 재전파 불필요). setSucursal() 은 notify 파라미터 없이 항상 onChanged 호출(D-09, 지점 변경은 항상 전파)"

requirements-completed: [W98-05]

# Metrics
duration: ~100min
completed: 2026-10-04
---

# Phase 98 Plan 06: Tile·컴플리케이션(원형·막대) + 지점/잠금 가림 + 표면 갱신 연결 Summary

**ProtoLayout Material3 Tile(「HOY · {지점}」·축약 금액·4칸·경과시간)과 SHORT_TEXT/LONG_TEXT 컴플리케이션(원형은 D-15 ⑦ 로 건수뿐)을 만들고, 앱·Tile·컴플리케이션 중 하나가 새 값/지점/회수를 받으면 나머지도 즉시 갱신 요청되도록 연결 — 34개 테스트(SurfaceTexts 17 + 신규 콜백 3 + 기존 전체 117개 회귀 없음) 전부 통과.**

## Performance

- **Duration:** ~100 min
- **Started:** 2026-10-04T22:00:00-03:00 (추정)
- **Completed:** 2026-10-04T23:40:00-03:00 (추정)
- **Tasks:** 3
- **Files modified:** 13 (7 생성, 6 수정)

## Accomplishments
- `SurfaceTexts.kt` — `tileTexts`/`complicationShort`/`complicationLong` 순수 함수, `MONTO_EN_CIRCULO = false`(D-15 ⑦ 리터럴 상수, 바꾸려면 새 사용자 결정 필요). 지점 선택(D-09)·잠금 가림(D-14 ②)·오프라인(Stale)·미연결(Unpaired)·부분실패(hoy error) 전부 커버(17 테스트)
- `ResumenTileService` — `Material3TileService` 를 상속해 suspend 로 8초 타임아웃 fetch, ProtoLayout 저수준 빌더로 제목(골드)·금액(흰색, 잠금 시 "•••")·2×2 칸·경과시간 레이아웃 조립, 전체 클릭 시 `MainActivity` 실행, `setFreshnessIntervalMillis(15분)`
- `VentasComplicationService` — `SuspendingComplicationDataSourceService` 상속, SHORT_TEXT 는 건수만(D-15 ⑦ 확정, `montoEnCirculo` 인자를 넘기지 않음), LONG_TEXT 는 "N ventas · M cajas"/"지점 · N ventas", `persistencePolicy=DO_NOT_PERSIST`, `getPreviewData` 고정 샘플("55"/"ventas", "55 ventas · 3 cajas")
- `SurfaceUpdater.requestAll()` + `ResumenRepository.onChanged` 콜백 — `AppGraph` 가 둘을 연결해 어떤 표면이 새 값을 받아도 나머지 전부 갱신 요청됨(Tile/컴플리케이션 자신의 fetch 는 `notify=false` 로 재귀 차단, T-98-42)
- 매니페스트에 Tile(`BIND_TILE_PROVIDER`)·컴플리케이션(`BIND_COMPLICATION_PROVIDER`) 서비스 선언 + `tile_preview.xml`

## Task Commits

Each task was committed atomically (root 저장소):

1. **Task 1 RED: SurfaceTexts 실패 테스트** - `54d5990` (test)
1. **Task 1 GREEN: SurfaceTexts 구현(D-15⑦ 건수 기본값)** - `270e0ae` (feat)
2. **Task 2: ResumenTileService + VentasComplicationService + DeviceLock + 매니페스트** - `6b16c1f` (feat)
3. **Task 3: SurfaceUpdater + ResumenRepository.onChanged + AppGraph 배선** - `5e6d0a1` (feat)

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

_Task 1 은 tdd="true" 라 RED→GREEN 을 별도 커밋으로 분리(98-03/98-04 와 같은 관례). Task 2·3 은 type="auto" 라 단일 feat 커밋._

## Files Created/Modified

- `wear-admin-app/app/src/main/java/.../surface/SurfaceTexts.kt` - Tile/컴플리케이션 문구 순수 함수 + `MONTO_EN_CIRCULO`
- `wear-admin-app/app/src/test/.../surface/SurfaceTextsTest.kt` - 17 테스트(골든 JSON + 지점/잠금/오프라인/에러 변형)
- `wear-admin-app/app/src/main/java/.../surface/DeviceLock.kt` - `isLocked(context)`(요청 시점 판정)
- `wear-admin-app/app/src/main/java/.../surface/SurfaceUpdater.kt` - `requestAll(context)`(Tile+컴플리케이션 동시 갱신 요청)
- `wear-admin-app/app/src/main/java/.../tile/ResumenTileService.kt` - Material3TileService, ProtoLayout 레이아웃 조립
- `wear-admin-app/app/src/main/java/.../complication/VentasComplicationService.kt` - SHORT_TEXT/LONG_TEXT, persistencePolicy
- `wear-admin-app/app/src/main/res/drawable/tile_preview.xml` - Tile 선택 화면 미리보기 벡터
- `wear-admin-app/app/src/main/AndroidManifest.xml` - Tile/컴플리케이션 서비스 선언(권한·인텐트필터·메타데이터)
- `wear-admin-app/app/src/main/java/.../AppGraph.kt` - `resumenRepository` 에 `onChanged = { SurfaceUpdater.requestAll(application) }` 배선
- `wear-admin-app/app/src/main/java/.../data/ResumenRepository.kt` - `fetch(notify)`·`setSucursal()` 에 `onChanged` 호출 추가
- `wear-admin-app/app/src/test/.../data/ResumenRepositoryTest.kt` - 콜백 시험 3건(Fresh→1회, 401→1회, notify=false→0회)
- `wear-admin-app/app/src/test/.../ui/PairingViewModelTest.kt`, `ResumenViewModelTest.kt` - Fake `fetch()` 를 새 `fetch(notify: Boolean)` 시그니처로 갱신(회귀 수정)

## Decisions Made

- ProtoLayout Material3 DSL(`primaryLayout`/`text`) 대신 저수준 `LayoutElementBuilders` 로 레이아웃 조립 — 근거는 위 key-decisions 참조. 시각 결과는 동일(골드 제목·흰 금액·4칸·회색 경과시간), 안정적인 공개 API만 사용해 빌드 위험을 낮췄다
- `Material3TileService.tileResponse` 는 `MaterialScope` 확장함수라 override 시그니처를 `override suspend fun MaterialScope.tileResponse(...)` 로 작성(최초 시도에서 "overrides nothing" 컴파일 에러로 발견·즉시 교정)
- `ComplicationDisplayPolicies.DO_NOT_SHOW_WHEN_DEVICE_LOCKED` 존재를 확인했으나 적용 안 함(건수만이라 가릴 금액이 없음) — `ComplicationPersistencePolicies.DO_NOT_PERSIST` 는 적용
- `fetch(notify: Boolean = true)` — Fresh/401 전환 시만 전파, Stale/Error 는 전파 안 함(표면이 이미 안정적인 last-value 상태)
- `setSucursal()` 은 항상 `onChanged` 호출(D-09, notify 파라미터 없음 — 지점 변경은 예외 없이 전파)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Material3TileService.tileResponse` override 시그니처 오류(확장함수 리시버 누락)**
- **Found during:** Task 2, 첫 `compileDebugKotlin` 시도
- **Issue:** `override suspend fun tileResponse(materialScope: MaterialScope, requestParams: TileRequest)` 로 작성했으나, 실제 추상 멤버는 `suspend fun MaterialScope.tileResponse(requestParams: TileRequest)`(MaterialScope 를 리시버로 받는 확장함수)였다 — "overrides nothing" 컴파일 에러
- **Fix:** `override suspend fun MaterialScope.tileResponse(requestParams: RequestBuilders.TileRequest)` 로 교정, 본문에서 `this.context` 로 리시버 접근
- **Files modified:** `tile/ResumenTileService.kt`
- **Verification:** `compileDebugKotlin`/`assembleDebug` 통과
- **Committed in:** `6b16c1f`

**2. [Rule 1 - Bug] acceptance_criteria grep("montoEnCirculo = true" 0건)이 설명 주석의 어휘를 결과물로 오인**
- **Found during:** Task 2, acceptance_criteria 자체 검증
- **Issue:** KDoc 설명 문구에 "montoEnCirculo=true" 가 리터럴로 들어가 "서비스가 금액 경로를 열지 않는다" 를 검증하는 grep(0건 요구)을 위반(코드는 실제로 그 값을 넘기지 않음 — 순수 문구 충돌, 98-03 의 동일 패턴 재발)
- **Fix:** 주석 문구를 의미는 그대로 두고 패턴과 안 겹치게("montoEnCirculo 를 true 로 넘기는 호출") 교정
- **Files modified:** `complication/VentasComplicationService.kt`
- **Verification:** grep 0건 확인 후 재빌드 통과
- **Committed in:** `6b16c1f`

**3. [Rule 3 - Blocking] `ResumenSource.fetch()` 시그니처 변경(Task 3)이 98-04 의 Fake 구현 2곳을 깨뜨림**
- **Found during:** Task 3, `fetch(notify: Boolean = true)` 추가 후 전체 테스트 빌드
- **Issue:** `PairingViewModelTest.FakePairingSource`·`ResumenViewModelTest.FakeResumenSource` 가 옛 `fetch()`(무인자) 시그니처로 override 하고 있어 "overrides nothing" 컴파일 에러(인터페이스 시그니처가 바뀌었으므로 구현도 따라가야 함)
- **Fix:** 두 Fake 의 `override suspend fun fetch()` 를 `override suspend fun fetch(notify: Boolean)` 로 갱신(동작은 그대로 — notify 인자 무시)
- **Files modified:** `ui/PairingViewModelTest.kt`, `ui/ResumenViewModelTest.kt`
- **Verification:** 전체 117 테스트 통과(98-04 분 포함, 회귀 없음)
- **Committed in:** `5e6d0a1`

---

**Total deviations:** 3 auto-fixed (2 bug — 확장함수 override·grep 오탐, 1 blocking — 인터페이스 시그니처 변경의 호출부 파급)
**Impact on plan:** 셋 다 계획이 요구한 빌드 가능성·테스트 통과·acceptance_criteria 를 충족시키기 위한 수정이며 동작 변경 없음. 3번은 98-04 가 만든 두 Fake 구현에 98-06 의 시그니처 확장이 전파된 정상적인 리팩터링 파급(새 선택적 파라미터라 호출부는 불변, 구현부만 갱신).

## Issues Encountered

- `androidx.wear.protolayout.material3` 의 `primaryLayout()`/`text()` DSL 은 로컬 gradle 캐시에 sources jar 가 없어 정확한 Kotlin 디폴트 파라미터 조합을 소스 없이 확신하기 어려웠다 — 대신 `javap` 로 안정적으로 확인 가능한 저수준 `LayoutElementBuilders`(Box/Column/Row/Text/FontStyle, protolayout 1.4.2) 를 썼다(위 key-decisions). 시각적 요구사항(골드 제목·흰 금액·4칸·경과시간·전체 클릭)은 동일하게 충족

## User Setup Required

None — 외부 서비스 설정 불필요.

## Next Phase Readiness

- 98-11(내비게이션·화면)이 이 플랜의 `surface/SurfaceTexts.kt`(문구 순수 함수)와 무관하게 `ui/model/SeccionesUi.kt`(98-04) 를 그대로 사용 — Tile/컴플리케이션과 앱 화면은 서로 다른 표시 모델을 쓴다(의도된 분리, 앱 화면은 6섹션 전체·Tile/컴플리케이션은 요약뿐)
- 98-12(휴대폰 APK·끝단 검증)가 확인해야 할 항목:
  - Tile 선택 화면에서 `tile_preview.xml` 미리보기와 실제 추가된 Tile 의 레이아웃이 기대대로 보이는지(에뮬레이터/실기기)
  - 원형·막대 컴플리케이션을 워치페이스에 실제로 추가해 SHORT_TEXT="46"/"ventas", LONG_TEXT="46 ventas · 3 cajas" 형태로 보이는지
  - **잠금 후 캐시된 Tile 이 남아 있는지**(요청 시점 판정의 한계 — plan 의 action 문구가 명시적으로 98-12 로 넘긴 항목)
  - 두 서비스 모두 `fetch()` 자체 8초/5초 타임아웃이 실제 저사양 Wear OS 기기에서 체감상 너무 길지 않은지(네트워크 느릴 때)

## Known Stubs

None — 모든 분기(지점 선택/Todas·잠금/미잠금·Fresh/Stale/Error/Unpaired)가 `SurfaceTextsTest`(17)로 커버되고, Tile/컴플리케이션 서비스는 실제 `AppGraph.resumenRepository` 를 호출한다(가짜 데이터 경로 없음). `getPreviewData()` 의 고정 샘플("55"/"ventas")은 Wear OS 플랫폼 계약상 필수인 디자인 전용 미리보기이고 실제 데이터 경로(`onComplicationRequest`)와는 분리되어 있다 — 스텁이 아니라 플랫폼 요구사항.

## Threat Flags

None — 이 플랜이 추가한 표면(Tile/컴플리케이션의 exported 서비스, PendingIntent 탭 동작, ComplicationPersistencePolicies)은 전부 plan 의 threat_model(T-98-40~T-98-44)에 이미 등록되어 있고 그대로 적용됐다(`BIND_TILE_PROVIDER`/`BIND_COMPLICATION_PROVIDER` 권한, `FLAG_IMMUTABLE` + 명시 컴포넌트, `notify=false` 재귀 차단, `DO_NOT_PERSIST`). 새로 열린 경계는 없다.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 8 referenced source/test/summary files verified present. All 4 task commit hashes (`54d5990`, `270e0ae`, `6b16c1f`, `5e6d0a1`) verified in `git log --oneline --all`. Full suite re-run (`./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks`): 117 tests, 0 failures, BUILD SUCCESSFUL. No missing items.
