---
phase: 99
slug: men-estructura-coherente-sin-hu-rfanos-ni-callejones-sin-sal
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-05
---

# Phase 99 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> 출처: `99-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest 29.7 + ts-jest (app·api) |
| **Config file** | `ventago-app/package.json` `"jest"` 블록 / api 는 NestJS 기본 |
| **Quick run command** | app: `cd ventago-app && npx jest src/__tests__/<파일>.spec.ts --runInBand` · api: `cd api-ventago && npx jest src/app/<모듈> --runInBand` |
| **Full suite command** | app: `cd ventago-app && npm test` · api: `cd api-ventago && npm test -- --maxWorkers=1` |
| **Estimated runtime** | quick ~10s · full 수 분 |

★ `--findRelatedTests` 금지 · api 전체는 `--maxWorkers=1` 필수 · app jest 는 `.tsx` 를 import 못 하므로 판정 로직은 `.ts` 로 뺀다.

---

## Sampling Rate

- **After every task commit:** 변경한 모듈 디렉터리만 quick run
- **After every plan wave:** app `npm test` + api `npm test -- --maxWorkers=1`
- **Before `/gsd:verify-work`:** 두 전체 스위트 그린 + 권한 실측용 더미 계정(admin·gerente·vendedor·cashier)으로 cmux browser 실측(운영 빌드)
- **Max feedback latency:** 30 seconds (quick)

---

## Per-Task Verification Map

> 플래너가 task ID 를 확정하면 채운다. 아래는 결정별 검증 대상.

| Decision | Behavior | Test Type | Automated Command / File | File Exists | Status |
|----------|----------|-----------|--------------------------|-------------|--------|
| D-04 | `/dashboards/ventas` 가 Venta 그룹 메뉴에 보인다 | unit(정적) | `src/__tests__/sidebar-module-contract.spec.ts` | ✅ | ⬜ pending |
| D-06 | legacyHref 3개(enviado·stock-vistas·season-turnover)가 없는 `/reportes/*` 를 가리키지 않는다 | unit | `src/__tests__/registry-legacyhref.spec.ts` | ❌ W0 | ⬜ pending |
| D-06 | `/reportes/asistencia` 가 reports-v2 목록에 있고 `permissionSlug:'reporte-asistencia'` | unit | 같은 파일 | ❌ W0 | ⬜ pending |
| D-09-1 | 허브 탭 게이트 = 단독 페이지 게이트 상수 | unit(정적) | 공유 상수 검사 spec | ❌ W0 | ⬜ pending |
| D-09-4 | 허브 「키→화면」 고정 | unit(정적) | `src/__tests__/hub-tab-contract.spec.ts` | ❌ W0 | ⬜ pending |
| D-09-4 | 라우트 진입점 등록 목록 + 대조군 | unit(정적) | `src/__tests__/route-reachability.spec.ts` | ❌ W0 | ⬜ pending |
| D-09-5 | `POST/PUT/DELETE /functions` 비-superadmin → 403 (T: EoP, 전역 카탈로그 변조) | integration(api) | `api-ventago/src/app/functions/functions.controller.spec.ts` | ❌ W0 | ⬜ pending |
| D-09-3 | support-token generate/usage 비-admin → 403 | integration(api) | `api-ventago/src/app/support-token/support-token.controller.spec.ts` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

★ 모든 신규 시험은 **대조군**(검사 대상을 지웠을 때 실패하는지) 또는 돌연변이로 한 번 확인한다.

---

## Wave 0 Requirements

- [ ] `ventago-app/src/__tests__/hub-tab-contract.spec.ts`
- [ ] `ventago-app/src/__tests__/route-reachability.spec.ts`
- [ ] `ventago-app/src/__tests__/registry-legacyhref.spec.ts` (또는 기존 reports-v2 spec 확장)
- [ ] `api-ventago/src/app/functions/functions.controller.spec.ts`
- [ ] `api-ventago/src/app/support-token/support-token.controller.spec.ts`
- [ ] 허브 게이트 상수 공유 정적 시험

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| Carpetas compartidas 실제 Drive 동작 | D-03 | `GOOGLE_SA_KEY_JSON` 이 로컬·운영 모두 미설정 — 서비스 계정 발급은 사람 작업 | 키 설정 후 Configuración 에서 폴더 연결 → Herramientas 에서 파일 목록 확인 |
| 역할별 메뉴 도달성 | D-02·D-04·D-06 | 정적 시험은 리다이렉트·렌더 예외를 못 잡는다 | 더미 계정 4개로 cmux browser 실측 |
| 사이드바 시드 → 코드 순서 | 전체 | 운영 DML 은 승인 필요 | structure 시드 적용 확인 후 프론트 배포 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
