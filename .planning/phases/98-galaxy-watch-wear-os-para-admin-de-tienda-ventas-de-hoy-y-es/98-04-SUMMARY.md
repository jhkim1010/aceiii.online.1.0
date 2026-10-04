---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 04
subsystem: mobile
tags: [wear-os, kotlin, jetpack-compose, coroutines, kotlinx-coroutines-test]

# Dependency graph
requires:
  - phase: 98-03
    provides: "wear-admin-app 골격, format/AmountFormat·TimeFormat, data/ResumenDto·WatchApi·TokenStore·WatchPrefs·ResumenRepository, 골든 JSON systemProperty 경로"
provides:
  - "ui/pairing/PairingViewModel.kt — 페어링 상태기계(코드 표시→interval 폴링→연결/만료), 네트워크오류 10s·429 60s 백오프"
  - "ui/resumen/ResumenViewModel.kt — 요약 새로고침(진행 중 합침)·지점 선택·D-15⑥ 단일 지점 narrowing-fix"
  - "ui/model/SeccionesUi.kt·SelectorUi.kt — 응답 v2 → 섹션 6종 표시 모델 + 지점 선택기, 순수 함수"
  - "data/ResumenRepository.kt — ResumenSource 인터페이스 추출, PairingHttpException(429 구분)"
  - "AppGraph.kt — 수동 DI 싱글턴(앱·Tile·컴플리케이션 공유 진입점)"
affects: [98-06, 98-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "뷰모델은 CoroutineScope 를 생성자로 주입받는다(자체 루트 스코프 생성 금지) — 시험에서 backgroundScope 를 주입해 가상 시간으로 결정적으로 시험"
    - "ResumenSource 인터페이스 + Fake 구현(FakePairingSource/FakeResumenSource)으로 ViewModel 시험은 실제 네트워크 없이 가상 시간만으로 폴링 간격·백오프를 고정"
    - "섹션 표시 모델은 Cabecera(label/alcance/alcanceTocable/aviso/pie/tono) 공통 구조로 D-09 범위 칩과 D-10 연결 상태를 한 곳에서 판정"

key-files:
  created:
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/AppGraph.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/pairing/PairingViewModel.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/ResumenViewModel.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/model/SeccionesUi.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/model/SelectorUi.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/ui/PairingViewModelTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/ui/ResumenViewModelTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/ui/model/SeccionesUiTest.kt
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/ui/model/SelectorUiTest.kt
  modified:
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/ResumenRepository.kt

key-decisions:
  - "ResumenRepository 를 ResumenSource 인터페이스로 뽑아 뷰모델이 인터페이스에만 의존 — 가상 시간 폴링 시험(4.9s/5.0s 경계)은 실제 네트워크 I/O 와 섞이면 결정적이지 않아 plan 이 명시적으로 허용한 변경"
  - "requestCode 실패를 PairingHttpException(code) 로 타입화(429 구분) — 기존엔 IllegalStateException 하나로 뭉쳐 있어 백오프 분기가 불가능했다"
  - "뷰모델 생성자는 CoroutineScope 를 직접 주입받는다(자체 SupervisorJob+Dispatcher 스코프 생성 금지) — TDD 로 드러난 설계 결함: 뷰모델이 루트 스코프를 만들면 그 Job 이 시험 생애주기와 분리돼 runTest 종료 시 암묵적 advanceUntilIdle 이 무한 폴링 루프를 코드 소진까지 돌려버린다"
  - "ViewModel 시험은 backgroundScope 를 주입하고 advanceUntilIdle() 대신 runCurrent()+advanceTimeBy() 를 쓴다 — 이 kotlinx-coroutines-test(1.11.0) 조합에서 advanceUntilIdle() 혼자서는 backgroundScope 코루틴을 디스패치하지 않는 것을 실측(최소 재현 시험 3종으로 확인)"
  - "Cabecera.label 은 고정 섹션명이거나 월/카운트가 섞인 동적 제목(FACTURADO · OCT 2026, CAJAS · 3/4 ABIERTAS)이고, alcance 는 별도 필드(D-09 범위 칩) — 화면이 둘을 조합해 그린다(목업의 ' · ' 는 UI 레이어 관심사)"
  - "Facturación Tipo A·B 는 응답에 없어도 항상 $0 행으로 합성, 그 밖의 타입(C 등)은 porTipo 에 존재할 때만 추가"

requirements-completed: [W98-04]

# Metrics
duration: ~95min
completed: 2026-10-04
---

# Phase 98 Plan 04: 워치 상태·표시 모델(페어링/요약 뷰모델 + 섹션 6종) Summary

**페어링·요약 뷰모델(가상 시간 폴링/백오프/새로고침 합침/지점 선택)과, 응답 v2 를 목업 v2 의 여섯 섹션 화면 문구로 바꾸는 순수 함수(SeccionesUi·SelectorUi)를 97개 JVM 테스트로 고정 — Compose 화면(98-11)은 이 모델을 그리기만 하면 된다.**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-10-04T20:15:00-03:00 (추정)
- **Completed:** 2026-10-04T21:50:00-03:00 (추정)
- **Tasks:** 2
- **Files modified:** 10 (9 생성, 1 수정)

## Accomplishments
- `PairingViewModel` — `requestCode()` → `ShowCode` → `interval` 초마다 `poll()`(RFC 8628 §3.5, 4.9s 0회/5.0s 1회 실측 고정), `Paired` 시 정지, `Expired`/`secondsLeft` 0 시 새 코드 자동 재발급, 네트워크 오류 10초·429 60초 백오프 — 9 테스트
- `ResumenViewModel` — `refresh()`/`onResume()`/`selectSucursal()`, 진행 중 refresh 합침(dedup), `refreshing` 플래그, `onUnpaired` 이벤트, D-15⑥ 단일 지점 narrowing-fix(낡은 선택을 지우고 `?sucursal` 없이 재요청) — 7 테스트
- `SeccionesUi.kt` — 여섯 섹션(Hoy·Medios de pago·Gastos y descuentos·Ingresos·Facturación del mes·Cajas) 표시 모델 순수 함수, 골든 JSON 기반 21 테스트(상태 error/Stale/Fresh, 단일 지점 2건, 카하 그룹/서랍, 리플렉션으로 `usuario` 필드 부재 확인)
- `SelectorUi.kt` — Todas+지점별 선택기, 지점 1개 매장은 빈 목록 — 3 테스트
- `data/ResumenRepository.kt` — `ResumenSource` 인터페이스 추출(테스트 결정성), `PairingHttpException`(429 구분) — 기존 17 테스트 그대로 통과(회귀 없음)
- TDD 중 **설계 결함 1건 발견·수정**: 뷰모델이 자체 루트 `CoroutineScope`를 만들면 시험 종료 시 orphan job 이 가상 시간을 코드 소진까지 소진 — 생성자 주입 방식으로 교정(아래 Deviations)

## Task Commits

Each task was committed atomically (root 저장소):

1. **Task 1 RED: PairingViewModel/ResumenViewModel 실패 테스트** - `a2bed37` (test)
1. **Task 1 GREEN: AppGraph/PairingViewModel/ResumenViewModel 구현** - `43bf8d6` (feat)
2. **Task 2 RED: SeccionesUi/SelectorUi + D-15⑥ narrowing-fix 실패 테스트** - `075ccdc` (test)
2. **Task 2 GREEN: SeccionesUi/SelectorUi + D-15⑥ narrowing-fix 구현** - `7eff67e` (feat)

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

_TDD 태스크(1, 2) 는 RED→GREEN 을 별도 커밋으로 분리했다(98-03 과 같은 관례)._

## Files Created/Modified

- `wear-admin-app/app/src/main/java/.../AppGraph.kt` - 수동 DI 싱글턴(토큰저장소·DataStore·WatchApi·ResumenRepository)
- `wear-admin-app/app/src/main/java/.../ui/pairing/PairingViewModel.kt` - 페어링 상태기계 + PairingUi sealed class
- `wear-admin-app/app/src/main/java/.../ui/resumen/ResumenViewModel.kt` - 요약 새로고침/선택/narrowing-fix
- `wear-admin-app/app/src/main/java/.../ui/model/SeccionesUi.kt` - 섹션 6종 표시 모델 + Cabecera/Tono/SeccionUi
- `wear-admin-app/app/src/main/java/.../ui/model/SelectorUi.kt` - 지점 선택기 옵션 목록
- `wear-admin-app/app/src/main/java/.../data/ResumenRepository.kt` - ResumenSource 인터페이스, PairingHttpException
- `wear-admin-app/app/src/test/.../ui/PairingViewModelTest.kt` - 9 테스트(FakePairingSource)
- `wear-admin-app/app/src/test/.../ui/ResumenViewModelTest.kt` - 7 테스트(FakeResumenSource, delay(1) 로 refreshing 중간 상태 관찰)
- `wear-admin-app/app/src/test/.../ui/model/SeccionesUiTest.kt` - 21 테스트(골든 JSON + `.copy()` 변형)
- `wear-admin-app/app/src/test/.../ui/model/SelectorUiTest.kt` - 3 테스트

## Decisions Made

- `ResumenRepository` → `ResumenSource` 인터페이스 추출(plan 이 명시적으로 허용) — 뷰모델 시험이 실제 네트워크 없이 가상 시간만으로 폴링 간격을 결정적으로 고정하게 함
- `requestCode` 실패를 `PairingHttpException(code)` 로 타입화해 429(rate limit)와 그 외 실패를 구분 — 백오프 시간이 다르다(10s vs 60s)
- 뷰모델 생성자는 `CoroutineScope` 를 주입받는다(자체 스코프 생성 금지) — 실제 앱에서는 Compose 의 `rememberCoroutineScope()`/`viewModelScope` 를 넘긴다(98-11 범위)
- `Cabecera.label` 은 고정 또는 동적 제목, `alcance` 는 별도 필드 — 화면이 조합해서 그린다(목업의 "VENTAS HOY · NOIX" 같은 결합 표기는 UI 레이어 책임)
- Facturación Tipo A·B 는 응답에 없어도 항상 $0 행으로 합성(D-15 interfaces 문구 "A·B 는 항상")

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `ResumenRepository.kt` 수정 — `ResumenSource` 인터페이스 추출 + `PairingHttpException`**
- **Found during:** Task 1, 뷰모델 설계 단계(plan 의 action 문구가 명시적으로 이 변경을 예견·허용)
- **Issue:** `PairingViewModel`/`ResumenViewModel` 을 가상 시간으로 결정적으로 시험하려면 실제 네트워크(MockWebServer)가 아닌 완전 제어 가능한 Fake 가 필요한데, `ResumenRepository` 는 구체 클래스였다. 또한 `requestCode` 의 429 실패가 `IllegalStateException` 문자열에 코드만 묻혀 있어 백오프 분기가 불가능했다
- **Fix:** `ResumenSource` 인터페이스(fetch/setSucursal/requestCode/poll) 추출, `ResumenRepository` 가 구현. `requestCode` 는 `!response.isSuccessful` 시 `PairingHttpException(code)` 를 던지도록 교정
- **Files modified:** `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/data/ResumenRepository.kt`
- **Verification:** 98-03 의 `ResumenRepositoryTest` 17 테스트 전부 회귀 없이 통과
- **Committed in:** `a2bed37`(인터페이스 선언), `43bf8d6`(실 사용)

**2. [Rule 1 - Bug] 뷰모델이 자체 루트 CoroutineScope 를 만들면 시험 종료 시 무한 폴링이 가상 시간을 끝까지 소진**
- **Found during:** Task 1, 첫 GREEN 구현(`CoroutineScope(SupervisorJob() + dispatcher)` 를 뷰모델 내부에서 생성)
- **Issue:** 가장 단순한 테스트("start 하면 ShowCode 가 뜬다")조차 `IllegalStateException: no hay más códigos configurados` 로 실패. 원인: `runTest` 가 테스트 본문 종료 후 암묵적으로 `advanceUntilIdle()` 를 수행하는데, 뷰모델의 polling 루프(delay(interval) → poll → 반복)가 테스트의 생애주기와 무관한 별도 루트 스코프에서 돌고 있어 끝없이(코드가 바닥날 때까지) 진행됨
- **Fix:** 두 뷰모델 모두 생성자에서 `CoroutineScope` 를 직접 주입받도록 변경(자체 스코프 생성 제거). 시험에서는 `backgroundScope`(테스트 종료 시 자동 취소)를 주입
- **Files modified:** `PairingViewModel.kt`, `ResumenViewModel.kt`, 두 테스트 파일의 생성자 호출부
- **Verification:** 전체 15 테스트(Task 1) 통과
- **Committed in:** `43bf8d6`

**3. [Rule 1 - Bug] `advanceUntilIdle()` 가 `backgroundScope` 코루틴을 디스패치하지 않음(이 kotlinx-coroutines-test 버전 실측)**
- **Found during:** Task 1, Rule 2 수정 이후에도 `ResumenViewModelTest` 6건·`PairingViewModelTest` 1건이 "fetch 가 0회"로 실패
- **Issue:** `backgroundScope.launch { ... }` 코루틴이 `advanceUntilIdle()` 단독 호출로는 전혀 디스패치되지 않음을 최소 재현 시험 3종(`println` 디버그 + 격리된 스크래치 테스트)으로 실측. `runCurrent()`/`advanceTimeBy()` 조합은 정상 동작
- **Fix:** 모든 ViewModel 테스트의 `advanceUntilIdle()` 호출을 `runCurrent()`(+필요 시 `advanceTimeBy()`)로 교체. `FakeResumenSource.fetch()` 에 `delay(1)` 을 추가해 `refreshing` 플래그의 중간 상태를 관찰 가능하게 함(기존엔 즉시완료라 중간 상태 단언이 타이밍에 의존적이었음)
- **Files modified:** `PairingViewModelTest.kt`, `ResumenViewModelTest.kt`
- **Verification:** 15/15 테스트 통과(이전 7건 실패 → 0건)
- **Committed in:** `43bf8d6`

---

**Total deviations:** 3 auto-fixed (1 blocking — 인터페이스 추출, 2 bug — 뷰모델 스코프 생애주기·테스트 하네스 디스패치)
**Impact on plan:** 셋 다 TDD 사이클(RED→GREEN) 안에서 테스트가 직접 잡아낸 결함이다. 2번은 실제 프로덕션에서도 재현 가능한 설계 결함(뷰모델이 자기 자신의 생애주기를 소유하면 호출부가 취소할 방법이 없다)이었고, 생성자 주입으로 교정한 것은 98-11 화면 통합 시에도 올바른 패턴이다. 동작 변경 없음(순수 테스트 하네스 교정 + 설계 교정).

## Issues Encountered

없음 — 위 Deviations 가 발생한 문제와 해결을 모두 포함.

## User Setup Required

None — 외부 서비스 설정 불필요.

## Next Phase Readiness

- 98-06(Tile+컴플리케이션)이 `AppGraph`(같은 `ResumenRepository` 공유)와 `SeccionesUi`/`SelectorUi` 순수 함수를 재사용 가능
- 98-11(내비게이션·화면)이 `PairingViewModel`/`ResumenViewModel` 을 Compose 화면에 배선 — `CoroutineScope` 는 `rememberCoroutineScope()` 또는 `viewModelScope` 로 공급해야 함(생성자가 요구)
- 여섯 섹션의 문구·정렬·상태 규칙이 전부 JVM 테스트로 고정돼, 98-11 은 이 모델을 그리기만 하면 됨 — 화면 레벨 로직 추가 금지(표시 로직은 이미 테스트로 봉인됨)

## Known Stubs

None — 이 플랜은 화면 없이 상태/표시 모델만 만들었고(목업 v2 의 ①–⑥ 전 섹션), 모든 분기(error/Stale/Fresh·단일지점/다지점·선택/Todas)가 테스트로 커버된다.

## Threat Flags

None — 이 플랜이 추가한 표면(ResumenSource 인터페이스, PairingHttpException)은 98-03 의 threat_model(T-98-20~T-98-25)이 다루는 동일 네트워크 호출의 재구조화일 뿐 새 경계를 열지 않는다. T-98-26~T-98-29(이 플랜의 threat_model)는 전부 시험으로 고정됨: 폴링 백오프(T-98-26), 새로고침 합침(T-98-27), 범위 칩(T-98-28), 담당자 이름 없음(T-98-29, 리플렉션 시험 포함).

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 10 referenced source/test files + this SUMMARY.md verified present. All 4 task commit hashes (`a2bed37`, `43bf8d6`, `075ccdc`, `7eff67e`) verified in `git log --oneline --all` (root 저장소). Full suite re-run (`./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks`): 97 tests, 0 failures, BUILD SUCCESSFUL. No missing items.
