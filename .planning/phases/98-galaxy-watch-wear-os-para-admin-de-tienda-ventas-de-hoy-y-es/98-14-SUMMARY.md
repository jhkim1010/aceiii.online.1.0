---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 14
subsystem: testing
tags: [codex, wear-os, kotlin, flutter, dio, security-review, fail-closed]

# Dependency graph
requires:
  - phase: 98-05
    provides: "tienda-admin-app Relojes 화면(RelojesRepository/RelojesScreen) — 이번 plan 의 검토 B 대상"
  - phase: 98-06
    provides: "wear-admin-app Tile/컴플리케이션/DeviceLock/SurfaceUpdater — 이번 plan 의 검토 A·C 대상"
  - phase: 98-11
    provides: "wear-admin-app PairingScreen/MainActivity/WearApp — 이번 plan 의 검토 C 대상"
provides:
  - "클라이언트 두 앱(wear-admin-app·tienda-admin-app)에 대한 CODEX 검토 A/B/C 보고서 3건 + 사실확인·분류표"
  - "DeviceLock.kt — KeyguardManager 조회 실패/예외 시 fail-open(미잠금→금액 노출)이던 것을 fail-closed(잠금→금액 가림)로 교정, isLockedFrom() 순수 함수로 분리해 JVM 단위 시험 4건"
  - "tienda-admin-app revoke() 경로 — DioException 미처리로 화면까지 새던 예외를 RelojesException 으로 감싸고 화면에서 SnackBar 로 안내"
  - "CODEX 재검토 1회(r2) — 두 수정 확인, 새 P1 0건"
affects: [98-12]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "isLocked(context) 를 isLockedFrom(query: () -> Boolean?) 순수 함수로 감싸 Robolectric/Mockito 없이 JVM 시험 — null/예외는 항상 fail-closed(true)"
    - "Flutter repository 의 모든 쓰기 경로(claimCode/listDevices/revoke)가 동일하게 DioException → RelojesException 매핑을 거치도록 통일 — 화면은 RelojesException 만 잡으면 된다"

key-files:
  created:
    - wear-admin-app/app/src/test/java/com/coolsistema/wearadmin/surface/DeviceLockTest.kt
  modified:
    - wear-admin-app/app/src/main/java/com/coolsistema/wearadmin/surface/DeviceLock.kt
    - tienda-admin-app/lib/features/relojes/relojes_repository.dart
    - tienda-admin-app/lib/features/relojes/relojes_screen.dart
    - tienda-admin-app/test/features/relojes/relojes_repository_test.dart
    - tienda-admin-app/test/features/relojes/relojes_screen_test.dart

key-decisions:
  - "SurfaceTexts.kt:91(montoEnCirculo 파라미터 존재)은 기각 — 프로덕션 호출부(VentasComplicationService.kt:55) 는 그레프로 0건 확인, true 는 시험에서만 쓰인다. D-15⑦ 이 의도적으로 남겨둔 '미래 허용 스위치' 이고 완화 제안이 아니므로 손대지 않았다"
  - "ResumenRepository.kt 의 네트워크 타임아웃 지적 2건(A2·A3)은 기각 — WatchApi.kt:48-50 의 단일 공유 OkHttpClient(AppGraph.kt:18) 가 connectTimeout 8s/readTimeout 10s 로 resumen·requestCode·poll 전체에 이미 적용돼 있다(검토 A 의 4개 파일만 본 CODEX 는 이 설정이 안 보였다)"
  - "relojes_repository.dart 의 401→network 오분류(B2·B3)는 P3 로 하향 — dio_client.dart 의 전역 인터셉터가 401 을 먼저 가로채 토큰 삭제+'Sesión expirada' 스낵바+go_router 리다이렉트를 수행하므로 로컬 오분류는 실사용자에게 거의 노출되지 않는다"
  - "MainActivity.kt:33(토큰 존재만으로 페어링 판정, 401 분기 없음)은 P3 로 하향 — WearApp.kt:32-36 의 onUnpaired 리스너가 fetch() 가 401 을 받는 순간 pairing 으로 되돌리므로, 콜드스타트 지연은 한 번의 fetch 사이클뿐이다"
  - "DeviceLock.kt:7(잠금 후 캐시된 Tile 잔존)은 기각(이월) — 98-06-SUMMARY 에서 이미 조사(ambient 동적 값 소스 미확인)·98-12 사람 검증으로 명시 이월된 플랫폼 제약, 이번 phase 의 새 결함 아님"
  - "PairingScreen.kt:86(원문 오류 노출 가능성)은 기각 — PairingViewModel.kt 전수 확인 결과 PairingUi.Error.message 는 항상 'Sin conexión'/'Demasiados intentos' 하드코딩 상수뿐, 토큰·코드·서버 원문이 들어갈 경로가 없다"

requirements-completed: [W98-03, W98-04, W98-05]

# Metrics
duration: ~55min
completed: 2026-10-05
---

# Phase 98 Plan 14: CODEX 클라이언트 보안 검토 A·B·C + P1/P2 수정 Summary

**wear-admin-app·tienda-admin-app 12개 핵심 파일에 CODEX 검토 3건(A/B/C) 실행 → 지적 12건 전부 사실확인 → 실제 결함 2건(잠금판정 fail-open, revoke() 미처리 예외) 시험 우선으로 수정, 나머지 10건은 기각/이월(근거 기록) — 재검토로 새 P1 0건 확인.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-10-05
- **Tasks:** 2/2
- **Files modified:** 8 (1 생성 — DeviceLockTest.kt, 7 수정 — DeviceLock.kt·relojes_repository.dart·relojes_screen.dart·4개 테스트 파일, 3개 CODEX 보고서는 `.team/reviews/`에 생성(저장소 미추적 관례))

## Accomplishments

- CODEX 검토 A(토큰·데이터·표면 4파일)·B(API·Tile·휴대폰 Relojes 4파일)·C(잠금·표면갱신·페어링·진입액티비티 4파일) 실행 — 지적 12건(A3+B4+C5) 전부 생성되어 비어 있지 않음, `test -s` + P1/P2/P3 형식 확인 통과(재시도 불필요, 1차 실행 모두 성공)
- 지적 12건 전부 파일:행을 직접 읽어 사실확인 — 실제 결함 3건(합치면 2개 수정 단위), 설계상 이미 처리됨/영향 미미 7건(기각·이월), D-15⑦ 의도된 설계 1건(기각)
- **P1 수정**: `DeviceLock.kt` 가 `KeyguardManager` 조회 실패나 `isDeviceLocked` 예외 시 `false`(미잠금→금액 노출)로 떨어지던 fail-open 을 `isLockedFrom()` 순수 함수로 분리해 fail-closed(판정 불가=잠금 취급)로 교정 — JVM 단위 시험 4건(잠김/미잠금/null/예외)
- **P2 수정**: `relojes_screen.dart` 의 `_confirmRevoke` 가 `revoke()` 실패(DioException)를 처리하지 않아 미처리 예외로 새고 목록도 그대로 남던 것을 `relojes_repository.dart` 의 `revoke()` 를 다른 두 메서드처럼 `RelojesException` 으로 감싸고 화면에서 SnackBar 로 안내하도록 교정
- 모든 수정은 RED(실패 확인)→GREEN(통과) 순서로 진행 — 수정 전 새 시험 5건(Kotlin 4 + Dart 1 위젯 + Dart 2 repository = 실제 7건) 전부 의도한 이유로 실패 확인 후 수정, 전부 통과
- 수정한 3개 파일로 CODEX 재검토 1회(`.team/reviews/manual-98-14-r2.md`) — 두 수정 모두 "수정됨" 확인, 새 P1 0건
- `wear-admin-app` 전체 단위 시험 + `assembleDebug`, `tienda-admin-app` `flutter test test/features/relojes` + `flutter analyze`(수정 파일) 전부 통과, `MONTO_EN_CIRCULO = false` 유지 확인

## Task Commits

Each task was committed atomically:

1. **Task 1: CODEX 검토 A·B·C 실행 + 지적 사실확인·분류** — 보고서만 생성(`.team/reviews/` 는 이 저장소 미추적 관례라 커밋 대상 아님, 아래 "보고서 경로" 참조)
2. **Task 2 RED: 실패 테스트(DeviceLockTest.kt 신규 + revoke 실패 테스트 2파일)** - `c1c4e62` (test)
2. **Task 2 GREEN: DeviceLock fail-closed + revoke() 예외 처리 + CODEX 재검토** - `5589ee9` (fix)

**Plan metadata:** (본 커밋 — SUMMARY + STATE/ROADMAP, root 저장소)

_Task 2 는 `tdd="true"` 라 RED→GREEN 을 별도 커밋으로 분리(98-06 Task 1 과 같은 관례). 고칠 지적이 0건이 아니었으므로 action(1)의 "0건이면 (4)만" 분기는 해당 없음._

## 보고서 경로 (git 미추적, `.team/reviews/`)

- `.team/reviews/manual-98-14-a.md` — 검토 A(토큰·데이터·표면), 지적 3건
- `.team/reviews/manual-98-14-b.md` — 검토 B(API·Tile·휴대폰 Relojes), 지적 4건
- `.team/reviews/manual-98-14-c.md` — 검토 C(잠금·표면갱신·페어링·진입액티비티), 지적 5건
- `.team/reviews/manual-98-14-r2.md` — 수정 3파일 재검토, 새 P1 0건

## 지적 분류표 (12건 전체)

| # | 보고서 | CODEX 등급 | 파일:행 | 사실 확인(근거) | 최종 등급 | 처리 |
|---|--------|-----------|---------|------------------|-----------|------|
| A1 | A | P2 | SurfaceTexts.kt:91 | TRUE(파라미터 존재) — 단 프로덕션 호출부 `VentasComplicationService.kt:55` 는 `complicationShort(state, now, bloqueado)` 로 `montoEnCirculo` 미전달(기본값 false). `grep -rn complicationShort`(main) 결과 호출부 1곳뿐, `true` 는 테스트 파일에서만 사용 | P3 | 기각 — D-15⑦ 의도된 '미래 허용 스위치'(98-06 key-decision), 완화 제안 아님 |
| A2 | A | P2 | ResumenRepository.kt:57 | FALSE — `WatchApi.kt:48-50` `OkHttpClient.Builder().connectTimeout(8,SECONDS).readTimeout(10,SECONDS)`, `AppGraph.kt:18` `val watchApi by lazy { WatchApi.create() }` 단일 공유 인스턴스로 `api.resumen()` 호출 전체에 적용 | — | 기각(사실 아님) — 검토 A 의 4파일에 WatchApi.kt 가 없어 CODEX 가 이 설정을 못 봄 |
| A3 | A | P2 | ResumenRepository.kt:108 | FALSE — 동일 근거(A2), `requestCode()`/`poll()` 도 같은 공유 클라이언트 사용 | — | 기각(사실 아님) |
| B1 | B | P2 | relojes_screen.dart:98 | TRUE — `_confirmRevoke` 에 try/catch 없이 `await ...revoke(d.id)` 직후 `ref.invalidate(...)`, 실패 시 예외가 그대로 새고 목록도 안 갱신 | P2 | **고침** — `5589ee9`, 시험 `relojes_screen_test.dart`("Quitar falla(red)...") |
| B2 | B | P2 | relojes_repository.dart:68 | TRUE(사실)이나 영향 미미 — `tienda-admin-app/lib/core/network/dio_client.dart` 의 전역 `onError` 인터셉터가 401 을 먼저 가로채 토큰 삭제+"Sesión expirada" 스낵바+`SessionExpiredSignal`(go_router redirect)을 수행(코드 확인) — 로컬 'network' 오분류가 보일 틈이 거의 없음 | P3 | 이월 — 전역 세션만료 처리가 선행, 범위(P1/P2 고침)밖 |
| B3 | B | P2 | relojes_repository.dart:84 | TRUE(사실), 동일 근거(B2) | P3 | 이월(B2 와 같은 이유) |
| B4 | B | P3 | relojes_screen.dart:38 | TRUE(사실, CODEX 자체도 P3) — `_normalized` 가 비영숫자 제거 후 길이만 검사, `_K7Q429XM`도 8자로 통과 | P3 | 이월 — plan 범위는 P1/P2 만 |
| C1 | C | P1 | DeviceLock.kt:11 | TRUE — `context.getSystemService(KeyguardManager::class.java) ?: return false` (서비스 null → 미잠금 취급) | P1 | **고침** — `5589ee9`, `isLockedFrom` 시험 2건(null/예외) |
| C2 | C | P1 | DeviceLock.kt:7 | TRUE(사실, 주석 내용) — 요청 시점 판정의 구조적 한계(잠금 후 캐시된 Tile 잔존) | P2(하향) | 이월 — 98-06-SUMMARY 가 이미 조사(ambient 동적 값 소스 미확인, protolayout-expression 1.4.2)·98-12 사람 검증으로 명시 이월. 이번 phase 의 새 결함 아님, 플랫폼 수단 부재(아키텍처 변경은 Rule 4 영역, 사용자 결정 없이 손대지 않음) |
| C3 | C | P2 | DeviceLock.kt:12 | TRUE — `keyguardManager.isDeviceLocked` 예외 시 fail-closed 보장 없음(C1 과 같은 근본원인) | P2 | **고침** — C1 과 동일 커밋/시험(`isLockedFrom` 의 예외 시험) |
| C4 | C | P2 | MainActivity.kt:33 | TRUE(국소적으론 사실) — 단 `WearApp.kt:32-36` 의 `resumenViewModel.onUnpaired.collectLatest { navController.navigate(ROUTE_PAIRING)... }` 가 fetch() 401 즉시 pairing 으로 되돌림(코드 확인) — 콜드스타트 한 번의 fetch 사이클만 지연 | P3 | 이월 — 전체 흐름(WearApp.kt)에서 이미 처리, MainActivity 단독 결함 아님 |
| C5 | C | P2 | PairingScreen.kt:86 | FALSE — `PairingViewModel.kt` 전수 확인, `PairingUi.Error.message` 는 `"Sin conexión"`/`"Demasiados intentos"` 하드코딩 상수뿐(`requestCodeWithRetry`), 토큰·코드·서버 원문이 들어갈 경로 없음 | — | 기각(사실 아님) |

**사실확인 결과 요약:** 12건 중 사실 TRUE 7건(A1·B1·B2·B3·B4·C1·C2·C3·C4 — 9건) / FALSE 3건(A2·A3·C5). 고침 2곳(B1, C1+C3 묶음) · 기각(사실 아님) 3건 · 기각(의도된 설계) 1건 · 이월(영향 미미/이미 처리됨/플랫폼 제약) 5건.

## Files Created/Modified

- `wear-admin-app/app/src/main/java/.../surface/DeviceLock.kt` - `isLocked()` 를 `isLockedFrom(query: () -> Boolean?)` 순수 함수로 감싸 null/예외 시 fail-closed(true)
- `wear-admin-app/app/src/test/.../surface/DeviceLockTest.kt`(신규) - 잠김/미잠금/null/예외 4건
- `tienda-admin-app/lib/features/relojes/relojes_repository.dart` - `revoke()` 를 `DioException`→`RelojesException`(`_mapClaimError` 재사용)으로 감쌈
- `tienda-admin-app/lib/features/relojes/relojes_screen.dart` - `_confirmRevoke` try/catch + `_revokeErrorMessage()` 신규(안내 SnackBar)
- `tienda-admin-app/test/features/relojes/relojes_repository_test.dart` - revoke 403/네트워크오류 → RelojesException 시험 2건
- `tienda-admin-app/test/features/relojes/relojes_screen_test.dart` - `_FakeRelojesRepository.revokeError` 추가 + "Quitar falla" 위젯 시험 1건

## Decisions Made

위 `key-decisions` frontmatter 참조 — 기각/이월 6건 모두 코드 근거(file:line, grep 결과)와 함께 분류표에 기록. D-14/D-15 를 완화하자는 제안은 없었음(A1 은 오히려 D-15⑦ 이 이미 허용해 둔 전환 지점이 있다는 확인이었을 뿐, 완화 요청이 아님).

## Deviations from Plan

None - plan 이 명시한 순서(검토 3건 → 사실확인·분류 → 처리=고침인 것만 시험 선행 수정 → 재검토 1회 → 검증 → 커밋)대로 실행. Task 2 action(1)의 "0건이면" 분기는 해당 없었다(2곳 수정 필요).

## Issues Encountered

- Gradle 실행 시 `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home`(hard_rules 지정 경로)의 JDK 가 25.0.2 로 업데이트되어 Gradle 8.14 와 호환되지 않아 즉시 빌드 실패(`What went wrong: 25.0.2`). plan 자체의 `<verify>` 블록이 쓰는 `JAVA_HOME=/opt/homebrew/opt/openjdk@21/...`(98-06 에서 실측 검증된 경로)로 전환해 해결 — 98-03/98-06 SUMMARY 에 기록된 실측값이 더 최신이고 신뢰할 수 있었다.

## User Setup Required

None - 외부 서비스 설정 불필요. push 완료(5589ee9), Jenkins/GitHub Actions 트리거 대상 아님(wear-admin-app·tienda-admin-app 은 api-ventago/ventago-app/print-agent/zebra-agent CI 대상에 포함되지 않음 — CLAUDE.md 배포 파이프라인 참조).

## Next Phase Readiness

- 98-12(사람 검증)가 이어서 확인할 항목: 이월된 5건(B2·B3·B4·C2·C4) 은 코드 변경 없이 이유만 기록됐으므로 사람 검증에서 재차 체감 문제로 드러나면 재평가 대상
- C2(잠금 후 캐시된 Tile 잔존)는 98-06 부터 이미 알려진 플랫폼 제약 — 98-12 실기기 확인에서 실제로 문제가 되면 사용자 결정(허용 스위치 신설 등)이 필요
- `MONTO_EN_CIRCULO = false` 그대로 유지, D-14/D-15 변경 없음

## Known Stubs

None - 이번 plan 은 검토·수정만 수행했고 새 UI/데이터 경로를 추가하지 않았다.

## Threat Flags

None - 이번 plan 이 수정한 두 지점(DeviceLock fail-closed, revoke() 예외 처리)은 모두 `threat_model`(T-98-80~83)이 이미 다루는 경계 안의 수정이며 새 표면을 열지 않았다. 오히려 T-98-80(워치 토큰/민감정보 노출 — 잠금 시 금액 가림)의 안전마진을 넓혔다.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-05*

## Self-Check: PASSED

All 10 created/referenced source/test/report files verified present on disk; both task commits (`c1c4e62`, `5589ee9`) verified in `git log --oneline --all`. No missing items.
