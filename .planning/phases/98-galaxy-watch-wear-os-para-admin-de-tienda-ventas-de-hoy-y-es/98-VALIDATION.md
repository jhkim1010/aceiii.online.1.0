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
| **Full suite command** | api: jest del módulo + `src/common/migrations/migration-conventions.spec.ts` · wear: `./gradlew :app:testDebugUnitTest` (JAVA_HOME = JBR de Android Studio) · flutter: `flutter test test/features/relojes` |
| **Estimated runtime** | ~30 s api · ~90 s wear (primer build más) · ~20 s flutter |

---

## Sampling Rate

- **After every task commit:** el quick command del subproyecto tocado (el commit gate sólo cubre api/app — Kotlin y Flutter se corren a mano)
- **After every plan wave:** full suite del subproyecto + mutación de guardas en W1
- **Before `/gsd:verify-work`:** todo verde + checklist manual de Tile/complicación
- **Max feedback latency:** 120 s

---

## Per-Task Verification Map

(El planner completa los Task IDs; requisitos y comandos base:)

| Task ID | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 98-01-T1 | W98-02 | hash/código/usable + roles filtrados por tienda; migración local | unit | `npx jest src/app/watch/watch-token.util src/app/auth/store-filtered-roles src/common/migrations/migration-conventions --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-01-T2 | W98-02 | userCode 5 min, claim sólo admin (roles filtrados), poll no revela existencia, deviceCode 32 B, una sola emisión | unit | `npx jest src/app/watch --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-01-T3 | W98-02 | DDL prod 5434 aprobado, owner coolsistema, esquema igual a local | manual+SQL | `ssh jhkim-server ... pg_tables like 'watch_%'` | — | ⬜ |
| 98-02-T1 | W98-02 | token sólo por header; revocado/vencido/inactivo/no-admin/otra tienda → 401; storeId del token | unit | `npx jest src/app/watch/watch-token.guard --maxWorkers=1` | ❌ W0 | ⬜ |
| 98-02-T2 | W98-01 | hoy en zona de la tienda (AR 21–24 h), anulaciones netas, dpago excluido, cajas = getTesoreriaOverview | unit+itest | `npx jest src/app/watch --maxWorkers=1 && npx jest --config ./test/itest/jest-itest.json --runInBand src/app/watch` | ❌ W0 | ⬜ |
| 98-02-T3 | W98-01/02 | mutación: 0 sobrevivientes; prod /watch/resumen 401 sin token | mutation+smoke | `bash scripts/mutantes-watch.sh` | ❌ W0 | ⬜ |
| 98-03-T1 | W98-04 | build Wear + AVD | build | `./gradlew :app:assembleDebug` | ❌ W0 | ⬜ |
| 98-03-T2 | W98-04 | `$1,28 M` / `$842 K` / `$999`, delta %, «hace N min» | unit (Kotlin) | `./gradlew :app:testDebugUnitTest --tests "*AmountFormatTest" --tests "*TimeFormatTest"` | ❌ W0 | ⬜ |
| 98-03-T3 | W98-04 | parseo resumen, 401 → desvincula, offline → último valor, token sólo en header | unit (Kotlin) | `./gradlew :app:testDebugUnitTest` | ❌ W0 | ⬜ |
| 98-04-T1 | W98-04 | polling respeta interval, código vencido se renueva | unit (Kotlin) | `./gradlew :app:testDebugUnitTest --tests "*ViewModelTest"` | ❌ W0 | ⬜ |
| 98-04-T2 | W98-04 | pantallas sin crash en emulador, montos vía abreviarMonto | build+smoke | `./gradlew :app:assembleDebug` + logcat FATAL 0 | — | ⬜ |
| 98-05-T1 | W98-03 | claim por body, mapeo de errores | unit (flutter) | `flutter test test/features/relojes/relojes_repository_test.dart` | ❌ W0 | ⬜ |
| 98-05-T2 | W98-03 | ingresar código → claim; listar; quitar; ícono sólo admin | widget | `flutter test test/features/relojes` | ❌ W0 | ⬜ |
| 98-06-T1/T2 | W98-05 | textos de Tile/complicación, permisos BIND_* | unit+build | `./gradlew :app:testDebugUnitTest :app:assembleDebug` | ❌ W0 | ⬜ |
| 98-06-T4 | W98-05/03 | Tile y complicación muestran el último resumen; revocar limpia superficies | manual | emulador + capturas 98-06-step*.png | — | ⬜ |
| 98-07-T3 | W98-06 | AAB firmado con clave de subida (no debug), secretos fuera del repo | build | `./gradlew :app:bundleRelease` + jarsigner sin «Android Debug» | — | ⬜ |
| 98-07-T4 | W98-06/01 | instalación desde Play internal testing, valores reales vs DB | manual | — | — | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/watch/watch-resumen.spec.ts`
- [ ] `api-ventago/src/app/watch/watch-token.guard.spec.ts`
- [ ] `api-ventago/src/app/watch/watch-pairing.spec.ts`
- [ ] `tienda-admin-app/test/features/relojes/`
- [ ] `wear-admin-app/` Gradle project + `app/src/test/`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tile / complicación se actualizan | W98-05 | el sistema decide cuándo llama a TileService / ComplicationDataSourceService | emulador Wear OS 6 + Galaxy Watch real: agregar tile y complicación, vender en POS, esperar ≤ 20 min |
| Sin conexión muestra último valor + antigüedad | W98-04 | depende de red real | modo avión en el reloj |
| Publicación en Play internal testing | W98-06 | consola de Play | subir AAB, instalar desde Play en el reloj |
| Valores reales | W98-01 | datos de producción | comparar `/watch/resumen` de una tienda con Tesorería y listado de ventas del día |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
