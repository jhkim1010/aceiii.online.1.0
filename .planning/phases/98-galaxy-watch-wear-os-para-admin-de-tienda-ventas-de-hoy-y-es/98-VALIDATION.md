---
phase: 98
slug: galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-10-04
---

# Phase 98 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Fuente: `98-RESEARCH.md` §Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | api: jest 29.7 · wear: JUnit + Gradle (módulo nuevo) · flutter: flutter_test |
| **Config file** | api: `api-ventago/package.json` (jest) · wear: Wave 0 crea `wear-admin-app/` · flutter: existente |
| **Quick run command** | `cd api-ventago && npx jest src/app/watch --maxWorkers=1` |
| **Full suite command** | api: `npx jest src/app/watch --maxWorkers=1` + `npx jest --config ./test/itest/jest-itest.json --runInBand src/app/watch` · wear: `./gradlew :app:testDebugUnitTest` (JAVA_HOME = openjdk@21 de Homebrew) · flutter: `flutter test test/features/relojes` |
| **Estimated runtime** | ~30 s api · ~90 s wear (primer build más) · ~20 s flutter |

---

## Sampling Rate

- **After every task commit:** el quick command del subproyecto tocado (el commit gate sólo cubre api/app — Kotlin y Flutter se corren a mano)
- **After every plan wave:** full suite del subproyecto + mutación de guardas en W1
- **Before `/gsd:verify-work`:** todo verde + checklist manual de Tile/complicación
- **Max feedback latency:** 120 s

---

## Per-Task Verification Map

> 2026-10-04 재계획(목업 v2, D-08~D-14) 반영. 98-01 은 완료. 웨이브: W1 98-05 · W2 98-02 · W3 98-03/98-08/98-09 · W4 98-04/98-10 · W5 98-06/98-11 · W6 98-12 · W7 98-07.

| Task ID | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 98-01-T1..T3 | W98-02 | 페어링 테이블·코드·claim/poll (완료) | unit+SQL | `npx jest src/app/watch --maxWorkers=1` | ✅ | ✅ |
| 98-02-T1 | W98-02 | header 만 · revocado/vencido/inactivo/no-admin/otra tienda → 401 · **poll 직후 권한 회수 → 첫 요청 401** · listDevices 403 · 사용처 정적 범위(대조군) | unit | `npx jest src/app/watch/watch-token.guard src/app/watch/watch-pairing --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-02-T2 | W98-01 | 계약 v2 골든(이름 키 0) · 매장 시계(자정 직전/직후·월 경계) | unit | `npx jest src/app/watch/resumen/watch-clock --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-02-T3 | W98-01/02 | 섹션 합성·지점 투영 · 부분 실패 격리 · 원천별 캐시 키(store+branch+tz+v2, 오늘/월 분리) · ok 만 캐시 · ?sucursal 검증 · 응답 키 == 골든 · no-store | unit | `npx jest src/app/watch --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-08-T1 | W98-01 | 판매 합계/건수/벌수/마지막/어제 같은 시각/할인 — AR 23:30 · 같은 날/다음 날 취소 · 역분개 원본 지점 · dpago/Borrador 제외 · 테넌트 | unit+itest | `npx jest --config ./test/itest/jest-itest.json --runInBand src/app/watch/resumen/sources -t ventas` | ❌ W0 | ⬜ |
| 98-08-T2 | W98-01 | 결제수단 5칸(saldo-a-favor=favor, reservado=otros, 나머지 은행) · 칸 합 == 결제행 합 | unit+itest | `npx jest src/app/watch/resumen/sources --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-09-T1 | W98-01 | 지출 매장 TZ · 카하 = getTesoreriaOverview, 이름 없음 | unit+itest | `npx jest src/app/watch/resumen/sources/gastos src/app/watch/resumen/sources/cajas --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-09-T2 | W98-01 | 입고 = 매입+공방만(legacy_opening·transfer·adjust·OT 제외) · 쓰는 쪽 note 고정(대조군) | unit+itest | `npx jest src/app/watch/resumen/sources/ingresos src/app/watch/resumen/sources/taller-notes --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-09-T3 | W98-01 | 이번 달 CAE 전표 · NC 차감·ND 가산 · 저장 IVA(21/121 금지) · homo 제외 · 발행일 기준 | unit+itest | `npx jest --config ./test/itest/jest-itest.json --runInBand src/app/watch/resumen/sources/watch-sources-b` | ❌ W0 | ⬜ |
| 98-10-T1 | W98-01 | 배선(원천 6 강제) · 고정 fixture 서비스 == spotcheck.sql == 손 계산 == 웹 대조식 · npm run build | itest+build | `npx jest --config ./test/itest/jest-itest.json --runInBand src/app/watch && npm run build` | ❌ W0 | ⬜ |
| 98-10-T2 | W98-01/02 | 돌연변이 생존 0 · 운영 EXPLAIN < 100ms/원천 · 운영 401/201/202 · Jenkins SHA | mutation+smoke | `bash scripts/mutantes-watch.sh` | ❌ W0 | ⬜ |
| 98-10-T3 | W98-01 | 레거시 「Resumen del día」 한 매장·한 날짜 대조표 | manual | spotcheck.sql (읽기 전용) | — | ⬜ |
| 98-03-T1 | W98-04 | build Wear + AVD + 골든 경로 systemProperty | build | `./gradlew :app:assembleDebug` | ❌ W0 | ⬜ |
| 98-03-T2 | W98-04 | `$1,28 M`/`$842 K`/`$999`/`15,2M`, delta, 1.398, hace N, OCT 2026 | unit (Kotlin) | `./gradlew :app:testDebugUnitTest --tests "*AmountFormatTest" --tests "*TimeFormatTest"` | ❌ W0 | ⬜ |
| 98-03-T3 | W98-04 | API 골든 직접 파싱 · error 섹션 · ?sucursal · 400→Todas · 401→토큰·캐시 삭제 · 마지막 값 1개·같은 지점일 때만 Stale · 헤더만 | unit (Kotlin) | `./gradlew :app:testDebugUnitTest` | ❌ W0 | ⬜ |
| 98-04-T1 | W98-04 | 폴링 interval · 새로고침 합침 · 열 때 갱신 · 지점 선택 | unit (Kotlin) | `./gradlew :app:testDebugUnitTest --tests "*ViewModelTest"` | ❌ W0 | ⬜ |
| 98-04-T2 | W98-04 | 섹션 6종·선택기 표시 모델(범위 칩, 내림차순, No disponible, Sin conexión, 이름 없음) | unit (Kotlin) | `./gradlew :app:testDebugUnitTest` | ❌ W0 | ⬜ |
| 98-11-T1/T2 | W98-04 | 셸·페이저·Back·새로고침·선택기·화면 6종(포맷 호출 0) · release 에 데모 없음 | build | `./gradlew :app:assembleDebug :app:assembleRelease` | — | ⬜ |
| 98-11-T3 | W98-04 | 에뮬레이터: 6섹션 라벨·Back(⑥→Hoy, Hoy→종료)·선택기 칩 · FATAL 0 | smoke | adb + uiautomator dump | — | ⬜ |
| 98-05-T1 | W98-03 | claim body · 오류 매핑 · listDevices 403 → notAdmin | unit (flutter) | `flutter test test/features/relojes/relojes_repository_test.dart` | ❌ W0 | ⬜ |
| 98-05-T2 | W98-03 | 코드 입력·목록·회수·아이콘 admin 만 · Doble pulsación 안내 · 403 안내 | widget | `flutter test test/features/relojes` | ❌ W0 | ⬜ |
| 98-06-T1 | W98-05 | Tile/컴플리케이션 문구 · 지점 · 잠금 시 ••• · 오프라인·미연결 | unit (Kotlin) | `./gradlew :app:testDebugUnitTest --tests "*SurfaceTextsTest"` | ❌ W0 | ⬜ |
| 98-06-T2/T3 | W98-05 | BIND_* 권한 · SHORT+LONG · 900 · displayPolicy · notify=false · requestAll | unit+build | `./gradlew :app:testDebugUnitTest :app:assembleDebug` | — | ⬜ |
| 98-12-T1/T2 | W98-03/05 | 운영 API + 휴대폰 APK + 에뮬레이터 끝단 · 웹 대조 · 잠금/ambient · APK 배포는 사용자 확인 뒤 | manual | 에뮬레이터 + 98-12-step*.png | — | ⬜ |
| 98-07-T1 | W98-06 | 업로드 키 서명(휴대폰과 같은 인증서) · 키 없으면 bundle 실패(대조군) · 비밀 저장소 밖 | build | `./gradlew :app:bundleRelease` + keytool/apksigner | — | ⬜ |
| 98-07-T2/T3 | W98-06/01 | Play 내부 테스트 설치 · 실데이터 대조 · 베젤·Back·위 버튼 · 잠금 가림 | manual | — | — | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/test/fixtures/watch-resumen-v2.golden.json` (98-02 — API·워치 공용 계약)
- [ ] `api-ventago/src/app/watch/watch-token.guard.spec.ts`, `watch-guard-scope.spec.ts`
- [ ] `api-ventago/src/app/watch/resumen/*.spec.ts`, `sources/*.spec.ts`, `sources/watch-sources-{a,b}.itest.ts`, `watch-resumen-reconcile.itest.ts`
- [ ] `api-ventago/scripts/watch-resumen-spotcheck.sql`, `scripts/mutantes-watch.sh`, `test/mutantes/watch.json`
- [ ] `tienda-admin-app/test/features/relojes/`
- [ ] `wear-admin-app/` Gradle project + `app/src/test/`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tile / complicación se actualizan | W98-05 | el sistema decide cuándo llama a TileService / ComplicationDataSourceService | 98-12 (emulador) y 98-07 (Galaxy Watch): agregar tile y complicación, vender en POS, esperar ≤ 20 min |
| Bloqueo/ambient ocultan montos | W98-05 (D-14 ②) | depende de la esfera y del estado del dispositivo | 98-12 paso 7 · 98-07 paso 6 |
| Sin conexión muestra último valor + antigüedad | W98-04 | depende de red real | modo avión en el reloj |
| Bisel / botón Atrás / doble pulsación del botón superior | W98-04 (D-10) | hardware real | 98-07 pasos 3–5 (getevent para KEYCODE_STEM) |
| Publicación en Play internal testing | W98-06 | consola de Play | subir AAB, instalar desde Play en el reloj |
| Valores reales vs legado | W98-01 (D-08/D-12) | datos de producción + pantalla legada | 98-10 T3: spotcheck.sql vs «Resumen del día» de flutter_aguila |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
