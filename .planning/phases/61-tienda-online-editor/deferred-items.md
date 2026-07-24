# Phase 61 — Deferred Items (out of plan scope)

## 61-01

- `api-ventago/src/app/shop-public/store-slug.service.ts:11` — pre-existing prettier
  formatting error (import wrap), unrelated to this plan's file set. Discovered while
  running `npx eslint src/app/shop-public/` (directory-wide) during 61-01 verification.
  Not fixed (SCOPE BOUNDARY — file not in `files_modified` for this plan).

## 61-02

- Same `store-slug.service.ts:11` pre-existing prettier error re-confirmed during
  Task 2 verification (`npx eslint src/app/shop-public/` directory-wide run). Still
  unrelated to this plan's `files_modified` (`store-theme-asset.controller.ts`,
  `shop-public.module.ts`) — both pass individually with exit 0. Not fixed.

## 61-03

- Same `store-slug.service.ts:11` pre-existing prettier error re-confirmed during
  Task 2 verification (`npx eslint src/app/shop-public/` directory-wide run). Still
  unrelated to this plan's `files_modified` (`shop-catalog.service.ts`,
  `shop-catalog.controller.ts`) — both pass individually with exit 0. Not fixed.

## 61-04

- Same `store-slug.service.ts:11` pre-existing prettier error re-confirmed during
  Task 3 verification (`npx eslint src/app/shop-public/` directory-wide run). Still
  unrelated to this plan's `files_modified` (`store-theme.constants.ts`,
  `store-theme.constants.spec.ts`) — both pass individually with exit 0 (confirmed via
  `npx eslint src/app/shop-public/store-theme.constants.ts src/app/shop-public/store-theme.constants.spec.ts`). Not fixed.

## 61-15

- `.planning/phases/61-tienda-online-editor/61-09-SUMMARY.md` 가 아직 untracked 상태로
  발견됨(61-09 실행 시 SUMMARY 작성은 됐으나 git commit 누락, `docs(61-09): complete ...`
  플랜 메타데이터 커밋이 root 로그에 없음 — 61-10~14 는 전부 `docs(61-XX): complete` 커밋이
  존재). Phase 61 게이트 자체(회귀/pool/doc/DDL)에는 영향 없음(문서 파일일 뿐) — 61-15 의
  `files_modified` 범위(`61-UAT.md`) 밖이라 이 플랜에서 직접 커밋하지 않음. STATE/ROADMAP
  갱신 시 함께 커밋 권장(orchestrator 판단).

## 61-14

- `tienda-app/src/pages/[storeId]/index.tsx` — 공개 카탈로그 페이지가 URL 쿼리스트링
  (`categoryId`/`gender`/`minPrice`/`maxPrice`)을 전혀 읽지 않는다(순수 클라이언트 state,
  Plan 61-09/61-12 부터 존재하던 사전 구조). `QuizSection.tsx`의 `Ver catálogo completo →`
  버튼은 선택된 필터를 querystring 으로 정확히 인코딩해 `router.push()` 하지만(예:
  `/9?categoryId=3&minPrice=50000&maxPrice=90000`), `index.tsx` 가 마운트 시 이 값을 읽어
  `activeCat`/`minP`/`maxP` 초기 state 로 반영하는 로직이 없어 실제로는 필터 미적용 상태로
  카탈로그만 열린다. `files_modified`(QuizSection.tsx/SectionRenderer.tsx/SectionListEditor.tsx)
  범위 밖이라 이 플랜에서는 index.tsx 를 수정하지 않음(SCOPE BOUNDARY — 이 플랜이 만든 버그가
  아니라 사전 존재하던 구조 공백). 후속 플랜에서 `getServerSideProps`/`useRouter` 로 초기
  쿼리 읽기 배선 필요(성공 기준 "Ver catálogo completo 는 선택된 필터가 적용된 카탈로그로
  이동한다"를 완전히 충족하려면 필수).
