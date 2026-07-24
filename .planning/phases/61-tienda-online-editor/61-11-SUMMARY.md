---
phase: 61-tienda-online-editor
plan: 11
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, storefront, video, panel-editor]

# Dependency graph
requires:
  - phase: 61-06
    provides: "SectionRenderer.tsx section.type switch 단일 분기점 + TODO(Plan 61-11) 자리"
  - phase: 61-08
    provides: "SectionListEditor.tsx 타입별 인라인 서브폼 패턴 + AssetUploadField(kind=reelVideo/reelPoster 업로드 지원 사전 배선) + PanelPrimitives(TextField/SelectField/NumberField/WarnBanner)"
provides:
  - "tienda-app/src/components/sections/ReelsSection.tsx — 세로 9:16 영상 카드 가로 스크롤, preload=none+poster, 탭 재생(동시재생 방지), 상품 오버레이 pill"
  - "SectionRenderer.tsx case 'reels' 연결"
  - "SectionListEditor.tsx reels 편집 서브폼(영상/poster 업로드 + 상품 셀렉터 + durationLabel + poster 누락 경고)"
affects: [61-14]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "<video muted playsInline preload=\"none\" poster> — 초기 바이트 0, 커스텀 탭 토글로만 재생/정지(controls 미사용)"
    - "document.querySelectorAll('video').forEach(pause) — 다중 video 동시재생 방지에 전역 상태 없이 DOM 순회로 충분"
    - "id 목록 조회 공개 API 부재 시 listProducts(storeId,{pageSize:48}) 1회 조회 + Map 매칭 — ReelsSection(공개몰)과 SectionListEditor(에디터) 양쪽에서 동일 패턴 재사용"

key-files:
  created:
    - tienda-app/src/components/sections/ReelsSection.tsx
  modified:
    - tienda-app/src/components/sections/SectionRenderer.tsx
    - tienda-app/src/components/panel/SectionListEditor.tsx

key-decisions:
  - "상품 오버레이 매칭 실패(productId 있으나 목록 48개에 없음) 시 오버레이 자체를 미렌더 — 가짜 이름/가격 표시 금지(UI-SPEC 명시 요구)"
  - "reels 카드 폭은 .sf-rail(globals.css) 클래스를 재사용하되 gap/카드폭을 인라인 스타일로 덮어씀 — 인라인 스타일이 클래스보다 우선순위가 높다는 CSS 규칙을 이용해 신규 CSS 클래스 추가 없이 반응형 근사치(min(192px, 60vw)) 구현"
  - "durationLabel 필드는 TextField 라벨에 힌트 문구를 병기(\"Duración — opcional, se muestra como etiqueta\") — PanelPrimitives.TextField 가 별도 hint prop 을 지원하지 않아 공용 컴포넌트 확장 없이 라벨 문구로 UI-SPEC 힌트 의도를 충족"

requirements-completed: [R10, R8]

# Metrics
duration: ~15min
completed: 2026-07-24
---

# Phase 61 Plan 11: reels 섹션 — ReelsSection.tsx 세로 영상 카드 + 에디터 편집 UI Summary

**세로 9:16 영상 카드 가로 스크롤 컴포넌트(preload=none, 탭 재생, 동시재생 방지, 상품 담기 오버레이) + SectionRenderer 연결 + 에디터 reels 편집 서브폼(영상/poster 업로드 + 상품 연결 + poster 누락 경고) 신규 구현**

## Performance

- **Duration:** ~15 min
- **Tasks:** 3/3 완료
- **Files modified:** 3 (신규 1 + 수정 2)

## Accomplishments
- `ReelsSection.tsx` — `section.items.length === 0` 이면 `null`(섹션 미노출), 각 카드는 `<video muted playsInline preload="none" poster={...}>` 로 초기 바이트 0 유지. `autoplay`/`controls` 속성 0건. 탭 핸들러가 `document.querySelectorAll('video')` 로 다른 모든 video 를 pause 해 동시 재생을 방지
- `productId` 매칭된 item 만 하단 상품 pill 오버레이(썸네일 32×40 + 이름 + `money()` 가격 + `aria-label="Agregar al carrito"` 담기 버튼, `stopPropagation` 으로 카드 탭과 분리)를 렌더 — 매칭 실패/미연결은 오버레이 자체를 렌더하지 않음(가짜 상품 카드 금지)
- 상품 매칭용 `listProducts(storeId, {pageSize:48})` 를 `productId` 연결된 item 이 있을 때만 1회 호출해 `Map<id, ShopProduct>` 구성
- `SectionRenderer.tsx` — `case 'reels': return <ReelsSection storeId={storeId} section={section} />;` 연결, `TODO(Plan 61-11)` 주석 해제, `quiz` TODO 는 그대로 유지
- `SectionListEditor.tsx` — reels 타입 펼침 시 서브폼: 섹션 제목(80자) + 영상 목록(최대 12개, 각 행에 `AssetUploadField kind="reelVideo"`(mp4/webm) + `kind="reelPoster"`(png/jpg/webp, "obligatorio" 명시) + 상품 셀렉터(`listProducts` 1회 조회 결과로 `<select>` 구성, 실패 시 ID 직접입력 폴백) + `durationLabel`(8자) + `✕ Quitar reel`) + `+ Agregar reel` dashed 버튼(12개 도달 시 숨김) + poster 없이 영상만 있는 행에 `WarnBanner` 저장 전 경고

## Task Commits

Each task was committed atomically:

1. **Task 1: ReelsSection.tsx — 영상 카드 + 탭 재생 + 상품 오버레이** - `28445b7` (feat)
2. **Task 2: SectionRenderer 에 case 'reels' 추가** - `090294e` (feat)
3. **Task 3: SectionListEditor reels 편집 서브폼** - `c536e63` (feat)

_이 플랜은 tienda-app 을 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/components/sections/ReelsSection.tsx` (신규) - 세로 영상 카드 가로 스크롤 + 탭 재생 + 상품 오버레이
- `tienda-app/src/components/sections/SectionRenderer.tsx` - `case 'reels'` 분기 추가
- `tienda-app/src/components/panel/SectionListEditor.tsx` - reels 편집 서브폼 + 상품 목록 조회 state 추가

## Decisions Made
- 상품 오버레이 매칭 실패 시 오버레이 미렌더(가짜 데이터 금지, UI-SPEC 명시)
- `.sf-rail` 클래스 재사용 + 인라인 스타일로 gap/카드폭 덮어쓰기(신규 CSS 클래스 없음)
- `durationLabel` 힌트는 라벨 문구에 병기(공용 `TextField` 컴포넌트 확장 없이)

## Deviations from Plan

None - plan executed exactly as written. 모든 태스크가 acceptance criteria grep 을 1회 통과했고 Rule 1~3 대상 이슈가 발생하지 않았다.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 61-14(quiz)이 `SectionRenderer.tsx`/`SectionListEditor.tsx` 의 남은 `TODO(Plan 61-14)` 표시 지점에 동일한 패턴(case 분기 + 인라인 서브폼)으로 이어서 작업 가능
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` exit 0 확인
- `grep -rn "autoplay" src/components/` 0건, `grep -rn "dangerouslySetInnerHTML" src/` 0건 확인
- 실제 영상 업로드 스모크 테스트(발행 후 공개 HTML `preload="none"` 확인)는 이 플랜 범위 밖(자동화 실행 환경에 dev 서버/실제 영상 파일 없음) — 브라우저 UAT 대기

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/sections/ReelsSection.tsx
- FOUND: tienda-app/src/components/sections/SectionRenderer.tsx
- FOUND: tienda-app/src/components/panel/SectionListEditor.tsx
- FOUND: .planning/phases/61-tienda-online-editor/61-11-SUMMARY.md
- FOUND commit: 28445b7
- FOUND commit: 090294e
- FOUND commit: c536e63
