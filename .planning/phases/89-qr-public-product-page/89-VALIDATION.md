---
phase: 89
slug: qr-public-product-page
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-16
---

# Phase 89 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> 출처: `89-RESEARCH.md` › Validation Architecture (2026-09-16 실측).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Jest 29.7 (api-ventago). 프론트는 전용 테스트 스크립트 없음 — 레포 관례상 `tsc` + `eslint` + 수동 검증 |
| **Config file** | `api-ventago/package.json` 의 `jest` 필드 (별도 `jest.config.js` 없음) |
| **Quick run command** | `cd api-ventago && npx jest src/app/print --maxWorkers=1` (변경 모듈 디렉터리만) |
| **Full suite command** | `cd api-ventago && npx jest --maxWorkers=1` (전수 — 커밋 게이트 범위 밖) |
| **Estimated runtime** | quick ~10s / full ~수십 분 (CI 45분 상한) |

★ `--maxWorkers=1` 은 **필수**다. 기본 옵션이면 메모리가 20GB 를 넘고, 2 워커면
  랜덤 suite 가 SIGTERM 으로 죽는다. `--findRelatedTests` 는 쓰지 않는다
  (널리 import 되는 파일 하나가 17 suites/91초를 끌어온다).

★ `NODE_OPTIONS` 가 설정돼 있으면 jest 가 **조용히 안 돈다.** 출력이 비면 「통과」가
  아니라 「안 돈 것」이다.

---

## Sampling Rate

- **After every task commit:** `npx jest <변경 모듈 디렉터리> --maxWorkers=1`
- **After every plan wave:** api-ventago 전수 (`--maxWorkers=1`, 로컬)
- **Before `/gsd-verify-work`:** 전수 green
- **Max feedback latency:** ~15초 (quick)
- **Phase gate (자동화 불가):** 실물 라벨을 폰으로 스캔해 페이지가 열리는지 1회 확인

---

## Per-Task Verification Map

> 계획(PLAN.md) 작성 시 planner 가 Task ID · Wave · Threat Ref 를 채운다.
> 아래는 RESEARCH 가 확정한 요구사항 → 시험 대응이다.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-T1 | 89-01 | 1 | REQ-03 | T-89-04, T-89-10 | 컬럼 기본값이 `false` 다 (`DEFAULT true` 문자열 부재) | unit | `npx jest src/common/migrations --maxWorkers=1` | ✅ 기존 | ⬜ pending |
| 01-T2 | 89-01 | 1 | REQ-05 | T-89-11 | 신규 테이블 owner + **시퀀스 owner** 이전 | unit | 위와 동일 | ✅ 기존 | ⬜ pending |
| 01-T3 | 89-01 | 1 | REQ-03, REQ-05 | T-89-10 | **양쪽 DB 에서 직접 조회**로 적용 확인 | manual+SQL | `psql -p 5432 …` / `ssh … -p 5434 …` | — | ⬜ pending |
| 02-T1 | 89-02 | 1 | REQ-06 | T-89-12, T-89-13 | 진단 스크립트에 쓰기 호출 0건 | static | `node --check` + `grep -c "putObject\|UPDATE "` = 0 | ❌ 신규 | ⬜ pending |
| 02-T2 | 89-02 | 1 | REQ-06 | T-89-03 | 판정 ⓐ/ⓑ/ⓒ 가 **대조군(`ascii_ok`)과 함께** 기록됨 | 조사 | `diagnose-image-names.js < img.tsv` | ❌ 신규 | ⬜ pending |
| 03-T1 | 89-03 | 2 | REQ-03 | T-89-04 | `@Column` 에 명시적 `type` + `defaultValue: false` | static+tsc | `npx tsc --noEmit` | — | ⬜ pending |
| 03-T2 | 89-03 | 2 | REQ-03 | T-89-14 | 화이트리스트 통과/거부 **양방향** | unit | `npx jest src/app/store/config --maxWorkers=1` | ❌ 신규 | ⬜ pending |
| 03-T3 | 89-03 | 2 | REQ-03 | T-89-09, T-89-15 | 허브 탭 등록(도달 가능) + `?? false` 폴백 | static+lint | `npx tsc --noEmit && npx eslint …` | — | ⬜ pending |
| 04-T1 | 89-04 | 2 | REQ-02, REQ-03 | T-89-01, T-89-04, T-89-05 | SQL 에 `AND p.store_id = $2` · row 스프레드 0건 · 수량 필드 부재 | static+tsc | `npx tsc --noEmit` + grep | — | ⬜ pending |
| 04-T2 | 89-04 | 2 | REQ-02 | T-89-02 | `@Public()` + `@Throttle` · `b` 에 `ParseIntPipe` 없음(하위호환) | unit | `npx jest src/app/print --maxWorkers=1` | ✅ 기존 | ⬜ pending |
| 04-T3 | 89-04 | 2 | REQ-02, REQ-03 | T-89-01, T-89-16, T-89-17 | 격리를 **jest + 실DB** 두 독립 근거로. 대조군 필수 | unit + 실DB | `npx jest src/app/print --maxWorkers=1` · `PGTARGET=local scripts/check-qr-public-tenant.sh` | ❌ 신규 | ⬜ pending |
| 05-T1 | 89-05 | 3 | REQ-05 | T-89-06, T-89-18, T-89-19 | `store_id` 서버 재검증 · 알림은 커밋 뒤 fire-and-forget | static+tsc | `npx tsc --noEmit` | — | ⬜ pending |
| 05-T2 | 89-05 | 3 | REQ-05 | T-89-02 | `LeadsModule` 이 `app.module.ts` 에 **실제로 등록**됨 | static | `grep -c LeadsModule src/app.module.ts` = 2 | — | ⬜ pending |
| 05-T3 | 89-05 | 3 | REQ-05 | T-89-20 | 저장 시 `notifyTelegram` 1회 · 라우트 경로 메타데이터 | unit | `npx jest src/app/leads --maxWorkers=1` | ❌ 신규 | ⬜ pending |
| 06-T1 | 89-06 | 3 | REQ-01 | T-89-22, T-89-23 | `authGuard=false` · `apiConnector` 0건 · `router.isReady` | static+lint | `npx tsc --noEmit && npx eslint …` | — | ⬜ pending |
| 06-T2 | 89-06 | 3 | REQ-03, REQ-06 | T-89-03, T-89-21 | 사진 없음/로드 실패 폴백 · `rel="noopener noreferrer"` · fallback 문구 | static+lint | 위와 동일 + grep | — | ⬜ pending |
| 06-T3 | 89-06 | 3 | REQ-01 | T-89-22 | **시크릿 창**에서 비로그인 200 · 네 갈래 실제 관측 | manual + curl | `curl -sL http://localhost:3050/m/stock?s=..&p=..` | — | ⬜ pending |
| 07-T1 | 89-07 | 3 | REQ-01 | T-89-24 | QR URL 조립이 한 곳(`buildQrUrl`)으로 모임 | unit | `npx jest src/app/print --maxWorkers=1` | ✅ 기존 | ⬜ pending |
| 07-T2 | 89-07 | 3 | REQ-01 | T-89-24, T-89-25 | `b` 없어도 동작 · 쓰레기 값이 인쇄되지 않음(대조군) | unit | 위와 동일 | ✅ 기존(확장) | ⬜ pending |
| 08-T1 | 89-08 | 4 | REQ-04 | T-89-08 | `storeIds` 를 `publicStores()` 로 검증, **업로드보다 먼저** | unit | `npx jest src/app/reseller --maxWorkers=1` | ✅ 기존(확장) | ⬜ pending |
| 08-T2 | 89-08 | 4 | REQ-04, REQ-05 | T-89-27, T-89-28 | 매장 선택 UI 부재 · FormData 에 Content-Type 미지정 · `/revendedor/` 미사용 | static+lint | `npx tsc --noEmit && npx eslint src/views/m-stock` | — | ⬜ pending |
| 08-T3 | 89-08 | 4 | REQ-04, REQ-05 | T-89-29 | **막다른 CTA 방지** — 프론트/서버 양쪽 문자열 대조 + 실제 HTTP(404 아님) + 대조군 | script | `bash scripts/check-cta-destinos.sh` · `API=… bash …` | ❌ 신규 | ⬜ pending |
| 09-T1 | 89-09 | 5 | 전체 | T-89-30, T-89-31, T-89-32 | 배포 승인 · 운영 마이그레이션 적용 확인 · CODEX 보고서 열람 | manual + curl | `curl -sL https://app.coolsistema.com/m/stock?s=6&p=1` | — | ⬜ pending |
| 09-T2 | 89-09 | 5 | REQ-01 | T-89-25 | **실물 라벨 스캔** — 옛 라벨 + 새 `&b=` 라벨 | manual | 자동화 불가 | — | ⬜ pending |
| 09-T3 | 89-09 | 5 | REQ-04, REQ-05 | T-89-29 | 두 CTA 를 끝까지 + `/admin/revendedores` 까지 도달 | manual + SQL | `ssh … psql -p 5434 …` | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/print/qr-public.service.spec.ts` — REQ-02·03 (**89-04 T3**)
- [ ] `api-ventago/scripts/check-qr-public-tenant.sh` — REQ-02 를 **실제 DB** 로 (**89-04 T3**)
      ★ VALIDATION 의 「테넌트 격리는 진짜 DB 로 확인한다」는 요구를 이것이 충족한다.
        jest 는 sequelize 를 가짜로 바꾸므로 SQL 이 한 글자도 실행되지 않는다.
- [ ] `api-ventago/src/app/leads/leads-public.controller.spec.ts` — REQ-05 (**89-05 T3**)
- [x] `reseller-auth.service.spec.ts` **존재 확인됨** (2026-09-16 planner 확인) →
      89-08 T1 이 그 파일에 케이스를 **더한다**(기존 시험을 지우지 않는다)
- [ ] 이미지 파일명 진단 스크립트 (REQ-06) — `api-ventago/scripts/diagnose-image-names.js`, 읽기 전용 (**89-02 T1**)
- [ ] `scripts/check-cta-destinos.sh` — 막다른 CTA 방지 (**89-08 T3**)

★ **시험이 검증 대상을 부르는지 확인할 것.** 직전 세션에서 6라운드 중 세 번이
  「시험은 통과하는데 검증 대상이 호출되지 않은」 형태였다. mock 으로 DB 를 가리면
  SQL 은 한 글자도 실행되지 않는다 — 테넌트 격리(REQ-02)는 **진짜 DB** 로 확인한다.

★ **대조군을 둔다.** 방어를 지웠을 때 시험이 실제로 빨개지는지 확인하지 않으면
  그 시험은 아무것도 검증하지 않는다.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 실물 라벨 QR 스캔 → 페이지 도달 | REQ-01 | 인쇄물·카메라·실제 도메인이 얽혀 자동화 불가 | 매장에 붙은 라벨(운영 `qr_print_log` 5건, branch 6)을 폰으로 스캔 → 404 가 아닌 상품 페이지가 열리는지 |
| 두 CTA 의 도착지가 실제로 열리는가 | REQ-04 · REQ-05 | 「막다른 CTA」 전례 — 없는 페이지로 보낸 적이 있다 | 각 CTA 를 눌러 200 이 뜨는지. **경로 존재를 검사로도 못 박을 것** |
| 라벨 종이 가격 ↔ 화면 가격 일치 | 결정 ① | 실물 대조 | 인쇄된 라벨의 가격과 페이지 가격이 같은지 |

---

## Validation Sign-Off

- [ ] 모든 task 에 `<automated>` verify 또는 Wave 0 의존성이 있다
- [ ] 표본 연속성: 자동 verify 없는 task 가 3개 연속되지 않는다
- [ ] Wave 0 가 MISSING 참조를 전부 덮는다
- [ ] watch 모드 플래그 없음
- [ ] 피드백 지연 < 15s (quick)
- [ ] `nyquist_compliant: true` 로 frontmatter 갱신

**Approval:** pending
