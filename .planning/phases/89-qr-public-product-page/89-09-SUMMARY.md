---
phase: 89-qr-public-product-page
plan: 09
subsystem: deployment
tags: [nestjs, nextjs, jenkins, docker, codex-review, minio, reseller]

# Dependency graph
requires:
  - phase: 89-01
    provides: "store_configs.qr_precio_publico · ventago_leads (로컬+운영 적용 완료)"
  - phase: 89-02
    provides: "이미지 모지바케 판정 ⓑ (35건, DB 쓰기 0건)"
  - phase: 89-03
    provides: "Configuración › QR del producto 토글 배선"
  - phase: 89-04
    provides: "GET /public/qr-stock/:storeId/:productId — 3갈래 공개 조회 API"
  - phase: 89-05
    provides: "POST /public/ventago-leads — CTA③ 이탈 받이"
  - phase: 89-06
    provides: "/m/stock — QR 도착지 공개 페이지"
  - phase: 89-07
    provides: "QR URL 에 &b=&pt= — 라벨 확정"
  - phase: 89-08
    provides: "CTA① reseller 신청 · CTA② 가입 링크 · 막다른 CTA 방지 검사"
  - phase: 89-10
    provides: "prices UNIQUE + ON CONFLICT 업서트 (로컬+운영 적용 완료)"
  - phase: 89-11
    provides: "verificar-esquema-phase89.sh 배포 게이트 · verificar-qr-public-tenant.sh"
  - phase: 89-12
    provides: "RegisterForm.tsx ?ref= 프리필"
provides:
  - "Phase 89 전체(api-ventago 89b3f70d · ventago-app 5931ca9) 운영 배포 완료 — Jenkins api-new-coolsistema #905 · front-coolsistema #741 둘 다 SUCCESS, 컨테이너 재생성 확인"
  - "reseller-auth.service.ts KYC 업로드 보상 범위 확장 — 업로드·해싱·DB 트랜잭션 전체를 하나의 실패 경로로 묶음(CODEX P1 수정)"
  - "89-UAT.md — 성공 판정 3건의 사용자 확인 절차 + 자동 확인 결과(스모크 4건) + 운영 DB 기준선"
  - "CODEX 자동 훅이 phase 89 40개 커밋을 전부 건너뛴 사실 기록 + 수동 대체 검토 1건(.team/reviews/auto-manual-89-*.md)"
affects: [90]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "다단계 실패 경로(업로드→해싱→DB트랜잭션)의 보상 삭제는 전체를 하나의 outer try/catch 로 묶어야 부분 성공이 고아를 안 남긴다 — DB 트랜잭션만 감싸는 것으로는 부족"
    - "보상 삭제 실패는 Promise.allSettled 결과를 순회해 개별 로그로 남긴다(원 예외는 그대로 throw, 삭제 실패로 원인을 덮지 않음)"
    - "Jenkins job 실제 이름은 api-new-coolsistema(CLAUDE.md 의 api-coolsistema 표기와 다름) — 빌드 확인 시 실제 jobs 디렉터리로 먼저 확인할 것"

key-files:
  created:
    - .planning/phases/89-qr-public-product-page/89-UAT.md
  modified:
    - api-ventago/src/app/reseller/auth/reseller-auth.service.ts
    - api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts
    - .planning/phases/89-qr-public-product-page/deferred-items.md

key-decisions:
  - "CODEX P1(KYC 업로드 고아 파일)은 배포 전에 즉시 수정 — 이 경로가 이번 배포로 처음 익명 인터넷에 열리기 때문(사용자 결정)"
  - "CODEX P2 3건(리드 통지 pending 영구정지 가능성 · ventago_leads FK CASCADE · check-cta-destinos.sh 404-only 게이트)은 배포를 막지 않는다고 판단해 지금 고치지 않고 deferred-items.md 에 위협으로만 기록 — 범위를 넓히면 검증 표면도 넓어진다는 원칙"
  - "CODEX 자동 훅이 phase 89 전체를 건너뛴 사실을 발견 → 자동 훅과 동일한 방식(diff 를 직접 만들어 codex exec --sandbox read-only 에 넘김)으로 수동 대체 검토를 받음. .auto-codex.heads 는 건드리지 않음(자동화 상태를 임의로 전진시키지 않음)"
  - "실물 라벨 스캔·화면 확인(성공 판정 3건)은 사람만 할 수 있어 89-UAT.md 에 관측을 지어내지 않고 '사용자 확인 필요' + 따라 하기 쉬운 절차로 남김"

patterns-established:
  - "다단계 I/O(업로드+해싱+DB) 보상 삭제는 최외곽에서 try/catch 하나로 묶는다"

requirements-completed: [REQ-01, REQ-02, REQ-03, REQ-04, REQ-05, REQ-06]

# Metrics
duration: 약 2시간(사용자 승인 대기 시간 제외 — CODEX 검토 준비 ~1h, P1 수정 ~15min, 배포+UAT 문서 ~35min)
completed: 2026-09-17
---

# Phase 89 Plan 09: 실물 UAT + 운영 배포 승인 Summary

**Phase 89(QR 공개 상품 페이지) 전체를 운영에 배포 완료 — api-ventago `89b3f70d`(Jenkins #905 SUCCESS) · ventago-app `5931ca9`(Jenkins #741 SUCCESS), 배포 전 CODEX 가 처음 발견한 KYC 업로드 고아 파일 결함(P1)을 즉시 수정, 스모크 4건 확인. 실물 라벨 스캔이 필요한 성공 판정 3건은 89-UAT.md 에 사용자 확인 절차로 남김**

## Performance

- **Duration:** 약 2시간(사용자 승인 대기 시간 제외) — Task 1 준비(CODEX 자문 수동 재현·스키마 게이트·로컬 게이트) 약 1시간, P1 수정 약 15분, 배포+스모크+UAT 문서 약 35분
- **Started:** 2026-09-17 (Task 1 준비 착수)
- **Completed:** 2026-09-17T13:03:29Z
- **Tasks:** Task 1(배포 승인) 완료 — hold→P1 수정→push 승인 전 과정. Task 2·3(실물 UAT)는 문서·절차 준비까지 완료, **실물 확인 자체는 사용자 대기**
- **Files modified:** 4 (신규 1 · 수정 3)

## Accomplishments

### Task 1 — 배포 승인
- CODEX 자동 훅이 phase 89 의 40개 커밋을 **단 하나도 검토하지 않은 사실**을 발견
  (`.team/reviews/.auto-codex.heads` 가 phase 89 시작 전 기준선에 멈춰 있었고, 실행 중인
  codex 프로세스도 없었음 — 원인은 미확인으로 기록, 추측하지 않음)
- 자동 훅과 동일한 방식으로 root+api-ventago+ventago-app 전체 diff(약 792KB)를 직접 만들어
  `codex exec --sandbox read-only` 에 넘겨 수동 검토를 받음 — CODEX 가 실제로
  `git diff`/`nl`/`rg` 를 서브모듈 소스에 직접 실행하는 것을 확인(서브모듈 건너뛰기 전례 재발 아님)
- 지적 4건(P1 1 · P2 3) 확보, 전부 코드를 직접 읽어 재확인. 같은 형태가 다른 자리에도
  있는지 전수 확인(둘 다 1건씩, 확산 없음)
- 스키마 게이트(`verificar-esquema-phase89.sh`, PGTARGET=prod) **8/8 [OK], 배포 가능: 예**
- 로컬 게이트 전부 통과: api tsc 0 · api jest(6개 대상 디렉터리) 37 suites/366 tests ·
  app tsc 0 · check-cta-destinos.sh 정적 대조 통과 · 테넌트 격리 스크립트(local+prod) 통과 ·
  `nest build && verify-models.js` (모델 199개)
- **사용자 결정 hold** → CODEX P1(KYC 업로드 중 실패 시 이미 올라간 파일이 MinIO 에
  고아로 영구히 남는 결함) 즉시 수정. `reseller-auth.service.ts` 의 업로드 루프·bcrypt.hash·
  DB 트랜잭션 전체를 하나의 outer try/catch 로 묶어 보상 범위를 확장, 회귀 시험 2건 추가
  (2번째 업로드 실패 / 해싱 실패 각각), 대조군으로 구 구조를 재현해 두 시험이 실제로
  빨개지는 것을 확인 후 원복
- CODEX P2 3건은 위협 그대로 `deferred-items.md` 에 기록(처방 아님), 각각 어디서
  다뤄야 하는지 명시
- **사용자 결정 push** → api-ventago(23 커밋) → ventago-app(5 커밋) → root(42 커밋) 순서로
  push, Jenkins 빌드 2건(api-new-coolsistema #905, front-coolsistema #741) 전부 SUCCESS,
  컨테이너 재생성 확인, 운영 스모크 4건 실측

### Task 2·3 — 실물 UAT (부분 완료)
- 운영 스모크 자동 확인: `/m/stock?s=6&p=1` 이 `-L` 기준 **200**(배포 전 404), `qr-stock`
  API 가 200 + `mode:"shop_redirect"`(store 6 기본값과 정확히 일치), 리드 POST 가 **400**
  (검증, 404 아님), 운영 로그 `does not exist` **0건**
- 운영 DB 기준선 기록: `reseller.resellers`=0, `ventago_leads`=0(제출 전/후 대조용),
  store 6 현재 설정(`qr_precio_publico=false`, `slug=cool`) 재확인
- 지금 매장에 붙어 있는 실물 라벨 5개(전부 지점 6)의 상품·가격·인쇄일을 표로 정리해
  사용자가 바로 스캔할 수 있게 제시
- ★ **성공 판정 3건은 실물 라벨을 폰 카메라로 찍는 것과 화면을 사람이 눈으로 확인하는
  것이 필요해, 이 세션에서 관측을 지어내지 않고 「사용자 확인 필요」로 남김.**
  `89-UAT.md` 에 A~E 단계별 절차(무엇을 누르고 무엇이 보이면 통과인지)를
  따라 하기 쉽게 기록

## Task Commits

1. **Task 1 준비 — CODEX 수동 검토 + 스키마/로컬 게이트** — 코드 변경 없음(검증 전용),
   보고서: `.team/reviews/auto-manual-89-root-bcc975f..694041e_api-ventago-1152e1f6..2c7201a2_ventago-app-fe69bdc..5931ca9.md`
2. **P1 수정 — KYC 업로드 보상 범위 확장** - `89b3f70d` (api-ventago, fix) +
   `551af8a` (root, chore: submodule pointer)
3. **deferred-items 갱신 — CODEX 훅 건너뜀 사실 + P2 3건 위협 기록** - `80fba2e` (root, docs)
4. **운영 배포** — `git -C api-ventago push`(1152e1f6..89b3f70d) →
   Jenkins api-new-coolsistema #905 SUCCESS → `git -C ventago-app push`(fe69bdc..5931ca9) →
   Jenkins front-coolsistema #741 SUCCESS → `git push`(root, 9666ac2..80fba2e)
5. **UAT 문서 + 배포 증거** - `d56a05f` (root, docs)

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified

- `api-ventago/src/app/reseller/auth/reseller-auth.service.ts` - `register()` 의 업로드·해싱·
  DB 트랜잭션을 하나의 outer try/catch 로 묶어 보상 범위 확장, 삭제 실패 로깅 추가
- `api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts` - 회귀 시험 2건 추가
  (2번째 업로드 실패 / bcrypt.hash 실패 시 각각 삭제 확인)
- `.planning/phases/89-qr-public-product-page/deferred-items.md` - CODEX 훅 건너뜀 사실 +
  P2 3건 위협 기록 추가
- `.planning/phases/89-qr-public-product-page/89-UAT.md` - 신규. 성공 판정 3건의 자동
  확인 결과 + 사용자 확인 절차 + 운영 DB 기준선

## Decisions Made

- **CODEX P1 즉시 수정, P2 3건은 보류**: 사용자 결정. P1(KYC 업로드 고아 파일)은 이번
  배포로 처음 익명 인터넷에 열리는 경로의 결함이라 즉시 수정. P2 3건은 배포를 막지
  않는다고 판단해 위협만 기록하고 범위를 넓히지 않음.
- **CODEX 자동 훅 미실행을 수동으로 대체**: `.auto-codex.heads` 가 phase 89 시작 전
  기준선에 멈춰 있어 40개 커밋이 전부 미검토였다. 원인은 규명하지 않고(추측 금지),
  자동 훅과 동일한 diff 생성 방식으로 수동 재현해 검토를 받았다. 자동화 상태 파일은
  건드리지 않았다.
- **실물 확인은 지어내지 않는다**: Task 2·3 의 성공 판정은 물리적 라벨 스캔과 사람의
  화면 판단이 필요하다. 이 세션은 "사용자 확인 필요"로 정직하게 남기고, 자동으로
  확인 가능한 부분(URL 동작·API 응답·DB 기준선)만 실측으로 채웠다.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - 미싱 크리티컬, 사용자 승인 완료] KYC 업로드 부분 실패 시 MinIO 고아 파일**
- **Found during:** Task 1 준비 — CODEX 수동 검토
- **Issue:** `reseller-auth.service.ts` 의 3개 파일 업로드 루프와 `bcrypt.hash` 가 DB
  트랜잭션 try 블록 밖에 있어, 2·3번째 업로드나 해싱이 실패하면 이미 올라간 파일이
  보상 삭제 대상에서 빠져 MinIO 에 개인정보(신분증·거주증명·셀피)가 영구히 남았다.
  이 경로는 89-08 이 storeIds 멀티파트 버그를 고치기 전까지 한 번도 성공한 적이
  없었고, 이번 배포로 처음 익명 인터넷에 열린다.
- **Fix:** 업로드·해싱·DB 트랜잭션 전체를 하나의 outer try/catch 로 묶어 보상 범위 확장.
  삭제 실패는 개별 로그로 남김(원 예외는 덮지 않음).
- **Files modified:** `api-ventago/src/app/reseller/auth/reseller-auth.service.ts`,
  `reseller-auth.service.spec.ts`
- **Verification:** 신규 회귀 시험 2건 + 대조군(구 구조 재현 → 두 시험 실제로 빨개짐
  확인 → 원복). `npx tsc --noEmit` 0, `npx jest src/app/reseller --maxWorkers=1`
  10 suites/53 tests 통과
- **Committed in:** `89b3f70d` (api-ventago) + `551af8a` (root)

---

**Total deviations:** 1 auto-fixed (Rule 2, 사용자 명시적 승인 하에 진행)
**Impact on plan:** plan 이 지시한 범위(배포 승인 + UAT 준비) 밖의 코드 수정이었으나,
CODEX 가 배포 전에 발견한 결함이라 사용자가 직접 승인한 예외적 개입이었다. 스코프
확장 없음 — 이 파일 하나의 보상 로직만 수정.

## Issues Encountered

- **이 세션의 `NODE_OPTIONS` 환경변수가 존재하지 않는 restore 파일을 가리켜 node 가
  즉시 죽음** — `env -u NODE_OPTIONS` 로 우회해 tsc/jest 를 정상 실행. 커밋 게이트
  훅(`verify-before-commit.sh`) 자체는 `git commit` 내부에서 정상 통과함(우회 불필요).
- **Jenkins job 실제 이름이 CLAUDE.md 표기와 다름**: `api-coolsistema` 가 아니라
  `api-new-coolsistema` — 실제 `/var/lib/jenkins/jobs/` 디렉터리를 먼저 확인해 바로잡음.
- **front-coolsistema 최근 빌드(#740)가 옛 커밋을 가리켜 혼동 가능성** — `Checking out
  Revision` 로그 라인으로 실제 커밋 SHA 를 대조해 우리 빌드(#741)를 정확히 특정함.

## User Setup Required

None - 외부 서비스 설정 불필요.

## 운영 배포 확인 (실측 원문)

```
$ git -C api-ventago push origin main
   1152e1f6..89b3f70d  main -> main

$ (Jenkins api-new-coolsistema #905) Checking out ... 89b3f70d ... 결과: SUCCESS
$ ssh jhkim-server "docker ps --filter name=api_ventago ..."
api_ventago   Up 55 seconds (healthy)   2026-09-17 12:54:32 +0000 UTC

$ git -C ventago-app push origin main
   fe69bdc..5931ca9  main -> main

$ (Jenkins front-coolsistema #741) Checking out Revision 5931ca96c6cfc430bfaf4232eea04d2e638f13ce (origin/main) ... 결과: SUCCESS
$ ssh jhkim-server "docker ps --filter name=ventagoapp ..."
ventagoapp   Up 8 seconds   2026-09-17 13:00:35 +0000 UTC

$ git push origin main
   9666ac2..80fba2e  main -> main
```

운영 스모크 4건은 `89-UAT.md` § 「자동 확인 결과」에 원문 그대로 있음.

## Known Stubs

없음 — 배포된 코드는 전부 실제 엔드포인트에 배선돼 있고 실제로 동작한다(스모크로 확인).

## Threat Flags

없음 — 이 plan 은 새 네트워크 표면을 추가하지 않았다(89-04·89-05·89-08 이 이미 열었고
이번엔 그것들을 배포했을 뿐). P1 수정은 기존 위협을 닫는 방향이었다.

## Next Phase Readiness

- **89-UAT.md 의 성공 판정 3건이 아직 PENDING이다** — 사용자가 실물 라벨을 폰으로
  찍고 화면을 확인해야 한다. 절차는 문서에 단계별로 정리돼 있다. 사용자 확인이
  끝나면 이 SUMMARY 와 `89-UAT.md` 의 판정 테이블을 PASS/FAIL 로 갱신해야 한다
  (다음 세션 또는 오케스트레이터가 사용자 응답을 받는 대로).
- CODEX P2 3건(리드 pending 영구정지 가능성 · ventago_leads FK CASCADE · 막다른 CTA
  검사 게이트 구멍)은 `deferred-items.md` 에 남아 있다 — 후속 plan 후보.
- CODEX 자동 훅이 왜 phase 89 를 건너뛰었는지는 미확인 상태다. 다음 정상 커밋에서
  훅이 다시 도는지 확인 필요.
- Phase 90(공개몰 재고 수량 노출 문제)은 이 phase 와 독립적으로 착수 가능.
- 블로커 없음 — 배포는 완료됐고, 남은 것은 사람의 실물 확인뿐이다.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/reseller/auth/reseller-auth.service.ts
- FOUND: api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts
- FOUND: .planning/phases/89-qr-public-product-page/deferred-items.md
- FOUND: .planning/phases/89-qr-public-product-page/89-UAT.md
- FOUND: .planning/phases/89-qr-public-product-page/89-09-SUMMARY.md
- FOUND commit 89b3f70d (api-ventago submodule)
- FOUND commit 551af8a (root)
- FOUND commit 80fba2e (root)
- FOUND commit d56a05f (root)
