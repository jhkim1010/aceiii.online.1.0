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
| 01-T1 | 89-01 | 1 | REQ-03 | T-89-04, T-89-10 | 컬럼 기본값이 `false` (`DEFAULT true` 문자열 부재) | unit | `npx jest src/common/migrations --maxWorkers=1` | ✅ 기존 | ⬜ |
| 01-T2 | 89-01 | 1 | REQ-05 | T-89-11 | 신규 테이블 owner + **시퀀스 owner** + `notify_status`/`notified_at` | unit | 위와 동일 | ✅ 기존 | ⬜ |
| 01-T3 | 89-01 | 1 | REQ-03, REQ-05 | T-89-10 | **양쪽 DB 직접 조회**로 적용 확인 | manual+SQL | `psql -p 5432 …` / `ssh … -p 5434 …` | — | ⬜ |
| 02-T1 | 89-02 | 1 | REQ-06 | T-89-12, T-89-13 | 진단 스크립트에 쓰기 호출 0건 | static | `node --check` + `grep -c "putObject\|UPDATE "` = 0 | ❌ 신규 | ⬜ |
| 02-T2 | 89-02 | 1 | REQ-06 | T-89-03 | **실패 샘플의 DB 바이트 ↔ MinIO 실재 키를 먼저 대조**한 뒤 재현. 대조군(`ascii_ok`) 필수 | 조사 | `diagnose-image-names.js < img.tsv` | ❌ 신규 | ⬜ |
| 10-T1 | 89-10 | 1 | REQ-07 | T-89-35 | `CONCURRENTLY` + `NULLS NOT DISTINCT`, `BEGIN;` 없음 | unit | `npx jest src/common/migrations --maxWorkers=1` | ✅ 기존 | ⬜ |
| 10-T2 | 89-10 | 1 | REQ-07 | T-89-33, T-89-36 | `ON CONFLICT` + `transaction` 필수(대조군) · 낡은 주석 교정 | unit | `npx jest src/app/products --maxWorkers=1` | ❌ 신규 | ⬜ |
| 10-T3 | 89-10 | 1 | REQ-07 | T-89-34, T-89-42 | 양쪽 적용 + `NOT indisvalid` 빈 결과 | manual+SQL | `psql … pg_indexes` | — | ⬜ |
| 03-T1 | 89-03 | 2 | REQ-03 | T-89-04 | `@Column` 명시 `type` + `defaultValue: false` | static+tsc | `npx tsc --noEmit` | — | ⬜ |
| 03-T2 | 89-03 | 2 | REQ-03 | T-89-14 | 화이트리스트 통과/거부 **양방향** | unit | `npx jest src/app/store/config --maxWorkers=1` | ❌ 신규 | ⬜ |
| 03-T3 | 89-03 | 2 | REQ-03 | T-89-09, T-89-15 | 허브 탭 등록(도달 가능) · `?? false` · **문구가 「딥링크 허용」** | static+lint | `npx tsc --noEmit && npx eslint …` | — | ⬜ |
| 04-T1 | 89-04 | 2 | REQ-02, REQ-03 | T-89-05, T-89-51 | DTO 필드 나열 · 재고/원가/SKU 부재 · `storeApodo` 근거 주석 | static+tsc | `npx tsc --noEmit` + grep | — | ⬜ |
| 04-T2 | 89-04 | 2 | REQ-02, REQ-03, REQ-07 | T-89-01, T-89-04, T-89-37, T-89-39 | 자격식 단일 SQL · 3키 테넌트 · 3갈래 · `precioEtiqueta` · `labelMatch` | static+tsc | `npx tsc --noEmit` + grep | — | ⬜ |
| 04-T3 | 89-04 | 2 | REQ-02 | T-89-02, T-89-17 | `@Public()+@Throttle` · `b`/`pt` 에 `ParseIntPipe` 없음(하위호환) | unit | `npx jest src/app/print --maxWorkers=1` | ✅ 기존 | ⬜ |
| 05-T1 | 89-05 | 3 | REQ-05 | T-89-06, T-89-18, T-89-19 | `store_id` 신뢰수준 낮춤 · HTML escape · 통지는 커밋 뒤 | static+tsc | `npx tsc --noEmit` | — | ⬜ |
| 05-T2 | 89-05 | 3 | REQ-05 | T-89-02 | `LeadsModule` 이 `app.module.ts` 에 **실제로 등록** | static | `grep -c LeadsModule` = 2 | — | ⬜ |
| 05-T3 | 89-05 | 3 | REQ-05 | T-89-20 | 통지 1회 + **결과가 `notify_status` 에 기록** + `@Column type`(D-2) | unit + 부팅 | `npx jest src/app/leads --maxWorkers=1` · `nest build && node scripts/verify-models.js` | ❌ 신규 | ⬜ |
| 06-T1 | 89-06 | 3 | REQ-01 | T-89-22, T-89-23 | `authGuard=false` · `apiConnector` 0건 · `router.isReady` · `pt` 전달 | static+lint | `npx tsc --noEmit && npx eslint …` | — | ⬜ |
| 06-T2 | 89-06 | 3 | REQ-03, REQ-06 | T-89-03, T-89-21 | 사진 폴백 · `rel=noopener` · **세 문구에 `data-testid`**(D-1) | static+lint | 위와 동일 + grep | — | ⬜ |
| 06-T3 | 89-06 | 3 | REQ-01 | T-89-22 | 시크릿 창 비로그인 200 · 네 갈래 + **가격 병기 3갈래(「없음」 포함)** | manual + curl | `curl -sL …/m/stock?s=..&p=..` | — | ⬜ |
| 07-T1 | 89-07 | 3 | REQ-01 | T-89-24 | QR URL 조립이 `buildQrUrl` 한 곳 · `&b=`·`&pt=` | unit | `npx jest src/app/print --maxWorkers=1` | ✅ 기존 | ⬜ |
| 07-T2 | 89-07 | 3 | REQ-01 | T-89-24, T-89-25, T-89-38 | 하위호환 + 쓰레기 값 미인쇄(대조군) + 순서 유지 | unit | 위와 동일 | ✅ 기존(확장) | ⬜ |
| 11-T1 | 89-11 | 3 | REQ-02, REQ-03 | T-89-40, T-89-41 | **23개 분기·가격·필드 시험 + 대조군 4건** | unit | `npx jest src/app/print/qr-public.service.spec.ts --maxWorkers=1` | ❌ 신규 | ⬜ |
| 11-T2 | 89-11 | 3 | REQ-02 | T-89-01, T-89-40 | **실DB** 3키 격리 + 대조군 + 표본 부재 시 exit 2 | script(실DB) | `PGTARGET=local bash api-ventago/scripts/verificar-qr-public-tenant.sh` | ❌ 신규 | ⬜ |
| 11-T3 | 89-11 | 3 | REQ-03, REQ-05, REQ-07 | T-89-31, T-89-42 | **배포 게이트** 8항목(선후 호환 포함) | script(실DB) | `PGTARGET=prod bash api-ventago/scripts/verificar-esquema-phase89.sh` | ❌ 신규 | ⬜ |
| 12-T1 | 89-12 | 3 | REQ-08 | T-89-45, T-89-46, T-89-47, T-89-48 | `?ref=` 프리필이 **기존 blur 검증을 탄다** · 해석 실패 시 빈 값 | static+lint | `npx tsc --noEmit && npx eslint src/views/register/components/RegisterForm.tsx` | — | ⬜ |
| 12-T2 | 89-12 | 3 | REQ-08 | T-89-49, T-89-50 | A~E 실측(프리필·notfound·무영향·`@` 정규화·guestGuard) | manual + curl | `curl -sL …/register?ref=cool` | — | ⬜ |
| 08-T1 | 89-08 | 4 | REQ-04 | T-89-08, T-89-27, T-89-43, T-89-44 | storeIds 화이트리스트(업로드보다 앞) · limits/fileFilter/Throttle · 고아 보상 삭제 | unit + static | `npx jest src/app/reseller --maxWorkers=1` + grep 행번호 | ✅ 기존(확장) | ⬜ |
| 08-T2 | 89-08 | 4 | REQ-04, REQ-05, REQ-08 | T-89-28, T-89-52, T-89-54 | 매장 선택 UI 부재 · FormData Content-Type 미지정 · **CTA 3단 위계** · 보상 문구 0건 | static+lint | `npx tsc --noEmit && npx eslint src/views/m-stock` | — | ⬜ |
| 08-T3 | 89-08 | 4 | REQ-04, REQ-05, REQ-08 | T-89-29, T-89-53 | **막다른 CTA 방지** — 5개 도착지 양쪽 대조 + 실제 HTTP + 429 + 대조군 exit 2 | script | `bash scripts/check-cta-destinos.sh` · `API=… APP=… bash …` | ❌ 신규 | ⬜ |
| 09-T1 | 89-09 | 5 | 전체 | T-89-30, T-89-31, T-89-32, T-89-34 | **스키마 게이트 실패 시 배포 안 함** · CODEX 보고서 열람 | script + manual | `PGTARGET=prod bash …/verificar-esquema-phase89.sh` | ❌ 신규 | ⬜ |
| 09-T2 | 89-09 | 5 | REQ-01 | T-89-25, T-89-38 | **실물 라벨 스캔** — 옛 라벨 + 새 `&b=&pt=` 라벨 + 가격 병기 3갈래 | manual | 자동화 불가 | — | ⬜ |
| 09-T3 | 89-09 | 5 | REQ-04, REQ-05, REQ-08 | T-89-29, T-89-50 | 두 CTA 끝까지 + `/admin/revendedores` + `/register` 프리필 도달 | manual + SQL | `ssh … psql -p 5434 …` | — | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/print/qr-public.service.spec.ts` — REQ-02·03 (**89-11 T1**, 23개 시험)
- [ ] `api-ventago/scripts/verificar-qr-public-tenant.sh` — REQ-02 를 **실제 DB** 로 (**89-11 T2**)
      ★ VALIDATION 의 「테넌트 격리는 진짜 DB 로 확인한다」는 요구를 이것이 충족한다.
        jest 는 sequelize 를 가짜로 바꾸므로 SQL 이 한 글자도 실행되지 않는다.
- [ ] `api-ventago/src/app/leads/leads-public.controller.spec.ts` — REQ-05 (**89-05 T3**)
- [x] `reseller-auth.service.spec.ts` **존재 확인됨** (2026-09-16 planner 확인) →
      89-08 T1 이 그 파일에 케이스를 **더한다**(기존 시험을 지우지 않는다)
- [ ] 이미지 파일명 진단 스크립트 (REQ-06) — `api-ventago/scripts/diagnose-image-names.js`, 읽기 전용 (**89-02 T1**)
- [ ] `scripts/check-cta-destinos.sh` — 막다른 CTA 방지, **5개 도착지** (**89-08 T3**)
- [ ] `api-ventago/scripts/verificar-esquema-phase89.sh` — **배포 게이트** (**89-11 T3**)
- [ ] `api-ventago/src/app/products/prices-unique.spec.ts` — REQ-07 (**89-10 T2**)
- [x] `api-ventago/scripts/verify-models.js` **이미 존재**하고 `Dockerfile:23` 에서 돈다 →
      새 검사를 만들지 말고 **89-05 T3 에서 한 번 실행**한다(D-2)

★ **시험이 검증 대상을 부르는지 확인할 것.** 직전 세션에서 6라운드 중 세 번이
  「시험은 통과하는데 검증 대상이 호출되지 않은」 형태였다. mock 으로 DB 를 가리면
  SQL 은 한 글자도 실행되지 않는다 — 테넌트 격리(REQ-02)는 **진짜 DB** 로 확인한다.

★ **대조군을 둔다.** 방어를 지웠을 때 시험이 실제로 빨개지는지 확인하지 않으면
  그 시험은 아무것도 검증하지 않는다.

---

## Requirement IDs (이 phase 안에서의 정의)

| ID | 무엇 | 출처 |
|---|---|---|
| REQ-01 | `/m/stock` 이 비로그인 200 으로 열린다 (라벨 QR 도착지 복구) | ROADMAP 「라벨 QR 도착지 복구」 |
| REQ-02 | 공개 API 의 다중 테넌트 노출 통제 | ROADMAP 「다중 테넌트 노출 통제」 |
| REQ-03 | 설정 스위치 3갈래 — 꺼진 매장은 가격 미노출 | CONTEXT 결정 ④ |
| REQ-04 | reseller 신청 경로가 끝까지 돈다 | ROADMAP 「reseller 신청 경로」 |
| REQ-05 | 리드 수집(이탈 받이)이 저장되고 통지 결과가 남는다 | ROADMAP 「리드 수집」 + CODEX C-4 |
| REQ-06 | 이미지 파일명 모지바케 **진단** | 사용자 명시 요구 |
| REQ-07 | 「현재 가격」이 한 값으로 확정된다 (`prices` UNIQUE) | CONTEXT 결정 ① 개정본 「함께 확정된 것」 |
| REQ-08 | CTA② 가 `/register?ref={apodo}` 로 도달하고 프리필된다 | CONTEXT 결정 ⑤-개정 |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 실물 라벨 QR 스캔 → 페이지 도달 | REQ-01 | 인쇄물·카메라·실제 도메인이 얽혀 자동화 불가 | 매장에 붙은 라벨(운영 `qr_print_log` 5건, branch 6)을 폰으로 스캔 → 404 가 아닌 상품 페이지가 열리는지 |
| 두 CTA 의 도착지가 실제로 열리는가 | REQ-04 · REQ-05 · REQ-08 | 「막다른 CTA」 전례 — 없는 페이지로 보낸 적이 있다 | 각 CTA 를 눌러 200 이 뜨는지 + reseller 는 `/admin/revendedores` 까지, 가입은 **프리필까지**. **경로 존재를 검사로도 못 박을 것** |
| 라벨 종이 가격 ↔ 화면 가격 | 결정 ①(개정) | 실물 대조 | 주 표시가 현재 가격인지 · **같으면 병기가 없고**(「없음」이 판정) 다르면 `Precio en la etiqueta: $X` 가 종이 숫자와 같은지 |
| 새 `&b=&pt=` 라벨이 읽히는가 | REQ-01 | 인쇄물·카메라 | QR 이 12자 길어졌다. 안 읽히면 `&pt=` 부터 되돌린다 |
| 로그인 상태에서 CTA② 가 어디로 가는가 | REQ-08 | `guestGuard=true` 는 의도된 제약 | 튕기는 곳을 관측해 기록(바꾸지 않는다) |

---

## Validation Sign-Off

- [ ] 모든 task 에 `<automated>` verify 또는 Wave 0 의존성이 있다
- [ ] 표본 연속성: 자동 verify 없는 task 가 3개 연속되지 않는다
- [ ] Wave 0 가 MISSING 참조를 전부 덮는다
- [ ] watch 모드 플래그 없음
- [ ] 피드백 지연 < 15s (quick)
- [ ] `nyquist_compliant: true` 로 frontmatter 갱신

**Approval:** pending
