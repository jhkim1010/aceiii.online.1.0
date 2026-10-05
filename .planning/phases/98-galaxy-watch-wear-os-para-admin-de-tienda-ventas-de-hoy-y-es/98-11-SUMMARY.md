---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 11
subsystem: ui
tags: [wear-os, jetpack-compose, wear-compose-material3, wear-compose-navigation, kotlin, android, watch]

requires:
  - phase: 98-04
    provides: PairingViewModel, ResumenViewModel, ui/model (SeccionesUi, SelectorUi) display-model functions
  - phase: 98-06
    provides: AppGraph DI container, SurfaceUpdater, Tile/complication color constants
  - phase: 98-10
    provides: GET /watch/resumen deployed to production (newapi.coolsistema.com)
provides:
  - Compose for Wear OS screens for all D-08 sections (pairing, 6-section pager, branch selector)
  - SwipeDismissableNavHost navigation graph (pairing/secciones/selector routes)
  - VerticalPager (6 pages) with BackHandler (section→Hoy, Hoy→exit) and pull-to-refresh via nestedScroll
  - debug-only DemoResumen hook for screenshot/smoke-testing without a paired watch
  - round-screen-safe layout pattern (fixed-width breakdown rows, top inset for TimeText)
affects: [98-12, 98-13, 98-14]

tech-stack:
  added: ["androidx.wear.compose:compose-navigation:1.6.2", "androidx.lifecycle:lifecycle-runtime-ktx:2.9.4"]
  patterns:
    - "Per-branch breakdown lists use Modifier.width(130.dp) (170.dp for selector), not fillMaxWidth() — round bezel clips full-width rows below ~40dp off vertical center"
    - "SeccionFrame<T> generic wrapper renders Cabecera (label/alcance chip/aviso/pie) once; XScreen composables only draw the Lista body"
    - "DemoResumen.aplicar(intent, context): ResumenSource? — same name/signature in src/debug and src/release, release always returns null (no reflection, no runtime build-type branch in main sourceSet)"

key-files:
  created:
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/theme/VentagoWearTheme.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/WearApp.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/pairing/PairingScreen.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/selector/SelectorScreen.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/SeccionesPager.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/SeccionFrame.kt
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/{Hoy,Medios,GastosDesc,Ingresos,Facturacion,Cajas}Screen.kt
    - wear-admin-app/app/src/debug/java/com/coolsistema/wearadmin/DemoResumen.kt
    - wear-admin-app/app/src/release/java/com/coolsistema/wearadmin/DemoResumen.kt
  modified:
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/MainActivity.kt
    - wear-admin-app/app/build.gradle.kts
    - wear-admin-app/gradle/libs.versions.toml

key-decisions:
  - "DemoResumen.aplicar returns ResumenSource? (not Boolean) — ResumenViewModel's state is private/read-only from 98-04, so demo data is injected by constructing a separate ResumenSource instead of reaching into the view-model's internals"
  - "MainActivity determines startDestination synchronously via runBlocking{tokenStore.getToken()} at onCreate — avoids a flash of the wrong screen on cold start; acceptable one-time Keystore/DataStore read latency"
  - "Bezel 'list-first-then-page' priority (mockup C table, ②/⑥) deferred to 98-12 human verification — rotaryencoder adb input produced no visible effect on this AVD image (confirmed via before/after screenshot diff), so it cannot be exercised headlessly; VerticalPager's own bezel paging (sections ①→⑥) works correctly"

requirements-completed: [W98-04]

duration: ~45min
completed: 2026-10-04
---

# Phase 98 Plan 11: Pairing/Pager/Selector Screens Summary

**Compose for Wear OS screens for all six D-08 sections plus pairing and branch selector, verified end-to-end on the Wear emulator against the live production API (98-10).**

## Performance

- **Duration:** ~45 min
- **Completed:** 2026-10-04
- **Tasks:** 3 (shell/navigation, six section screens, emulator smoke test)
- **Files modified:** 14 created, 3 modified, 8 screenshot artifacts

## Accomplishments

- Pairing screen tested live against production (`newapi.coolsistema.com`) — real pairing code `6KGT-XMUC` generated and displayed with expiry countdown and phone instructions
- All six sections (Hoy/Medios/GastosDesc/Ingresos/Facturación/Cajas) render correctly from the 98-04 display models via a `debug`-only demo data injector, confirmed by uiautomator text dump + visual screenshot for each
- Branch selector (D3): tapping "TODAS ▾" opens the picker, tapping a branch updates the header chip to "ONCE ▾" and returns to Hoy
- Back button: from any section → Hoy; from Hoy → exits the app (confirmed via `dumpsys activity activities`)
- Pull-to-refresh at the top of Hoy triggers exactly one `refresh()` call, logged as a single debug-only `VentagoRefresh: refresh` line (no body, no token — D-14 ③)
- Release APK contains zero references to the demo golden JSON (`unzip -l ... | grep golden` → 0); debug APK contains it (sanity check)
- Zero `FATAL EXCEPTION` and zero `KeystoreTokenStore` errors across the whole smoke-test session

## Task Commits

1. **Task 1: shell — pairing/pager navigation, rotary pager, selector, demo injection** - `3a27aa2` (feat)
2. **Task 2: six section screens — draw display models only** - `165240c` (feat)
3. **Task 3: emulator smoke test + round-screen clipping fixes** - `61a4536` (fix)

## Files Created/Modified

- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/theme/VentagoWearTheme.kt` - color constants (VentagoColors) + thin MaterialTheme wrapper
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/WearApp.kt` - SwipeDismissableNavHost graph (pairing/secciones/selector), onUnpaired → pop to pairing
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/pairing/PairingScreen.kt` - code/expiry/instructions, transitions to Hoy on Paired
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/selector/SelectorScreen.kt` - D3 branch picker
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/SeccionesPager.kt` - VerticalPager(6), BackHandler, pull-to-refresh nestedScroll, page-dot indicator
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/SeccionFrame.kt` - common header/state/footer wrapper
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/ui/resumen/{Hoy,Medios,GastosDesc,Ingresos,Facturacion,Cajas}Screen.kt` - six section bodies (display-model-only, no formatting calls)
- `wear-admin-app/app/src/{debug,release}/java/com/coolsistema/wearadmin/DemoResumen.kt` - debug-only demo `ResumenSource`, release no-op
- `wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/MainActivity.kt` - wires AppGraph/DemoResumen/view-models, startDestination, onResume→refresh
- `wear-admin-app/app/build.gradle.kts` - `compose-navigation` dependency, debug-only golden-JSON asset copy task
- `wear-admin-app/gradle/libs.versions.toml` - added `wear-compose-navigation` (1.6.2, matches pinned foundation/material3) and `lifecycle-runtime-ktx`

## Decisions Made

- Added `androidx.wear.compose:compose-navigation:1.6.2` (not in the original 98-03 dependency set) — required for `SwipeDismissableNavHost`/`composable`/`rememberSwipeDismissableNavController`; pinned to the same 1.6.2 train as foundation/material3 (confirmed available on Google Maven, not a guess — fetched `maven-metadata.xml` directly)
- `DemoResumen.aplicar(intent, context): ResumenSource?` instead of the plan's literal `(intent, viewModel): Boolean` — see key-decisions above
- Breakdown rows (porSucursal lists, Medios legend) use `Modifier.width(130.dp)` instead of `fillMaxWidth()` — discovered via on-device testing that a round display's bezel clips full-width rows once they're far enough from vertical center (confirmed mathematically: chord width at the clipped y-offset was narrower than the rendered row)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `androidx.wear.compose:compose-navigation` dependency**
- **Found during:** Task 1 — `SwipeDismissableNavHost` was required by the plan but no navigation artifact existed in the project's dependency set or Gradle cache
- **Fix:** Verified 1.6.2 exists on Google Maven (`dl.google.com/dl/android/maven2/.../maven-metadata.xml`), added to `gradle/libs.versions.toml` and `app/build.gradle.kts`
- **Files modified:** `wear-admin-app/gradle/libs.versions.toml`, `wear-admin-app/app/build.gradle.kts`
- **Verification:** `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleRelease` passes
- **Committed in:** `3a27aa2`

**2. [Rule 1 - Bug] Fixed TimeText/header overlap and round-bezel text clipping**
- **Found during:** Task 3 emulator smoke test — first screenshots showed "VENTAS HOY" overlapping the system clock, and branch-breakdown rows ("Once", "$3,91 M") visibly cut at the left/right edges
- **Issue:** `SeccionFrame`/`SelectorScreen` had no top inset to clear the default `AppScaffold` TimeText; breakdown list rows used `fillMaxWidth()`, which on a round display extends past the visible circular area once the row is far enough below/above vertical center
- **Fix:** Added `padding(top = 22.dp)` to clear TimeText; changed breakdown-row containers from `fillMaxWidth()` to a centered fixed `width(130.dp)` (170.dp for the selector, which sits closer to vertical center)
- **Files modified:** `SeccionFrame.kt`, `SelectorScreen.kt`, `HoyScreen.kt`, `MediosScreen.kt`, `GastosDescScreen.kt`, `IngresosScreen.kt`, `FacturacionScreen.kt`, `CajasScreen.kt`
- **Verification:** Re-captured screenshots for every affected screen (98-11-s1..s6.png, 98-11-selector.png) — visually confirmed no clipping
- **Committed in:** `61a4536`

---

**Total deviations:** 2 auto-fixed (1 blocking dependency, 1 bug found during smoke test)
**Impact on plan:** Both necessary for the plan's own acceptance criteria (build must pass; sections must render without clipping). No scope creep — no new features added beyond what Task 1/2/3 specify.

## Issues Encountered

- **Rotary (bezel) input not testable headlessly:** `adb shell input rotaryencoder scroll -- N` returned exit 0 but produced byte-identical before/after screenshots on this AVD image (`ventago_wear`, Wear OS 6, arm64). Per the plan's own fallback instruction, this is documented here and deferred to 98-12 human verification on a real device. VerticalPager's touch-swipe bezel-equivalent paging (sections ①→⑥) was verified working.
- **Round-screen clipping (see Deviation 2 above):** not anticipated by the plan text, found and fixed during Task 3.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All six sections, pairing, selector, Back, and pull-to-refresh work end-to-end against the deployed production API and the debug demo path
- 98-12 (or later plans) should verify real bezel/rotary behavior on physical hardware — specifically the "list scrolls first, then page changes" priority inside Medios (②) and Cajas (⑥) described in the mockup's button table, which could not be exercised on this emulator image
- Release signing (98-07 scope) unaffected; `assembleRelease` compiles cleanly with debug keystore fallback

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All created files and screenshot artifacts verified present on disk; all 3 task commits (3a27aa2, 165240c, 61a4536) verified present in git log.
