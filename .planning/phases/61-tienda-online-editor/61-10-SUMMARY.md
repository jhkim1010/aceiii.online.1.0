---
phase: 61-tienda-online-editor
plan: 10
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, panel-editor, macrostructure]

# Dependency graph
requires:
  - phase: 61-05
    provides: "MACRO_OPTIONS 4종 + GATED_BY_MACRO SSOT + MacroSettings/RailShelf 타입 (lib/theme-preset.ts, types/shop.ts)"
  - phase: 61-07
    provides: "RailsLayout.tsx/MasonryLayout.tsx 실제 렌더 컴포넌트"
  - phase: 61-08
    provides: "AccordionGroup/필드 primitives(PanelPrimitives.tsx), SectionListEditor.tsx, diseno.tsx 아코디언 셸 + content state"
provides:
  - "tienda-app/src/components/panel/MacroSelector.tsx — 구조 선택 카드 4장(인라인 SVG 46×34 와이어프레임 + EDITANDO 배지)"
  - "tienda-app/src/components/panel/StructureFieldsEditor.tsx — 구조별 설정 필드(rails/masonry만 실필드, marquee/bento는 hint/warn 배너만)"
  - "tienda-app/src/components/panel/SectionGatingChips.tsx — 구조별 섹션 게이팅 읽기 전용 칩"
  - "diseno.tsx 아코디언 그룹 1·2·3(Estructura de la home/Ajustes de {구조}/Secciones disponibles) + 미리보기 구조 연동(실제 RailsLayout/MasonryLayout 재사용, previewItems로 네트워크 0)"
  - "RailsLayout.tsx의 previewItems? 옵셔널 prop — 에디터 미리보기 전용 fetch 우회"
affects: [61-16]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "diseno.tsx 미리보기의 macro 분기는 index.tsx(Plan 61-09)의 gated/visibleSections/heroSection 패턴을 그대로 재사용 — 에디터 전용 스키매틱 렌더러를 새로 만들지 않고 실제 RailsLayout/MasonryLayout을 재사용(플랜 예시 코드는 최소 예시였고, 다른 섹션(hero/benefits/newsletter 등)이 사라지지 않도록 index.tsx와 동일한 필터링 로직을 채택)"
    - "RailsLayout의 previewItems 우회 경로: useState 초기값에 previewItems를 주입하고, lazy-load useEffect 최상단에서 previewItems가 있으면 즉시 return — fetch 자체가 호출되지 않음"
    - "GATED_BY_MACRO는 theme-preset.ts 단일 소유지 유지 — SectionGatingChips.tsx는 재정의 없이 import만(로컬 재export도 하지 않음, T-61-52)"

key-files:
  created:
    - tienda-app/src/components/panel/MacroSelector.tsx
    - tienda-app/src/components/panel/StructureFieldsEditor.tsx
    - tienda-app/src/components/panel/SectionGatingChips.tsx
  modified:
    - tienda-app/src/pages/[storeId]/panel/diseno.tsx
    - tienda-app/src/components/macro/RailsLayout.tsx

key-decisions:
  - "미리보기 macro 분기를 plan의 최소 예시 코드(단일 <section> 그리드로 상품 영역만 교체) 대신 index.tsx(61-09)의 gated/visibleSections 전체 패턴으로 구현 — plan 자체가 '표면 B 절에서 이미 확정한 실제 컴포넌트를 그대로 재사용... 중복 재정의 금지'를 명시했고, 최소 예시 그대로 구현하면 hero/benefits/newsletter 등 다른 섹션이 미리보기에서 사라지는 회귀가 발생하므로 index.tsx와 동일한 필터링 로직을 택함"
  - "SectionGatingChips.tsx에 export const GATED_BY_MACRO를 추가하지 않음 — Task 2 acceptance criteria 문구(export const 존재 요구)가 플랜 본문의 명시적 설계('여기서 재정의하지 않고 import')·T-61-52 위협 완화·플랜 최종 <verification> 블록(grep -rn \"const GATED_BY_MACRO\" src/ == 1, 이미 theme-preset.ts 1건으로 충족)과 정면으로 모순됨. 설계 의도·threat model·최종 verification 3곳이 일치하는 쪽(import-only)을 따르고 개별 grep 문구 오류로 판단 — 아래 Issues Encountered 참조"

patterns-established:
  - "구조별 설정 필드(StructureFieldsEditor)는 macro 값에 따라 return 을 조기 분기 — 다른 구조의 JSX는 아예 함수 스코프에 존재하지 않아 DOM 스왑이 자동 보장됨(별도 display:none 불필요)"

requirements-completed: [R9, R3, R8]

# Metrics
duration: ~10min
completed: 2026-07-24
---

# Phase 61 Plan 10: 에디터 구조 선택 UI Summary

**MacroSelector(구조 선택 카드 4장) + StructureFieldsEditor(rails/masonry 전용 실필드, marquee/bento는 hint/warn만) + SectionGatingChips(읽기 전용 게이팅 칩)를 신설하고, diseno.tsx에 아코디언 그룹 1·2·3을 추가하며 미리보기를 실제 RailsLayout/MasonryLayout으로 즉시 교체(네트워크 요청 0)**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-07-24T11:10:00-03:00 (추정)
- **Completed:** 2026-07-24T11:19:01-03:00
- **Tasks:** 3/3 완료
- **Files modified:** 5 (신규 3 + 수정 2)

## Accomplishments
- `MacroSelector.tsx` — `MACRO_OPTIONS` 4종을 세로 카드로 렌더. 카드는 `<button type="button" aria-pressed>` (div onClick 0건, 키보드 접근성), 46×34 인라인 SVG 와이어프레임 4종(목업 마크업 그대로 이식), 선택 시 gold 테두리+박스섀도+`EDITANDO` 배지, `YA EXISTE`/`NUEVO` 상태 태그
- `StructureFieldsEditor.tsx` — `macro` 값으로 조기 분기(다른 구조 JSX는 렌더 트리에 존재 자체를 안 함). marquee/bento는 SPEC이 명시한 "가짜 UI 금지" 원칙에 따라 hint/warn 배너만 렌더(실제 렌더러를 바꾸지 않는 캐러셀 속도·타일 목록 등 필드는 만들지 않음). rails는 선반 목록(▲▼/펼침편집/✕, 최대 6개, `+ Agregar estante`) + 화살표/lazy 스위치 + warn/hint. masonry는 열수/첫로드/원비율/필터바고정/오버레이 6필드 + warn/hint×2
- `SectionGatingChips.tsx` — `GATED_BY_MACRO`(theme-preset.ts 단일 소유지)를 import만 하고 재정의하지 않음. 7종 섹션 칩을 렌더하되 비활성은 `opacity:.45`+`line-through`. `sections[].enabled`를 절대 변경하지 않는 순수 읽기 전용 컴포넌트(주석으로 명시)
- `diseno.tsx` — 그룹 1(`🧱 Estructura de la home`)/2(`⚙️ Ajustes de {구조}`)/3(`🧩 Secciones disponibles en esta estructura`)를 그룹 4(`🏷 Identidad de marca`) 앞에 신설, 최초 로드 시 1·2·3만 open(그룹 4/6의 `defaultOpen` 해제), `SectionListEditor`에 `disabledTypes={GATED_BY_MACRO[macro]}` 배선, `🎨 Colores y tipografía` 그룹의 `TODO(Plan 61-10)` 주석 삭제. 미리보기 상단에 `Vista previa en vivo — {구조명}` 바(좌측 초록 점 + 우측 구조별 hint) 신설. 미리보기 상품 영역을 macro 분기로 교체: rails=`RailsLayout`(+ hero 제외 나머지 섹션), masonry=`MasonryLayout`(+ carousel 제외 나머지 섹션), marquee/bento=기존 `SectionRenderer` 순회 그대로 유지
- `RailsLayout.tsx` — `previewItems?: ShopProduct[]` 옵셔널 prop 추가. 값이 있으면 `useState` 초기값으로 즉시 채우고 lazy-load `useEffect`가 최상단에서 조기 return — fetch 자체가 발생하지 않음(편집 중 카탈로그 조회 0회, T-61-53)

## Task Commits

Each task was committed atomically:

1. **Task 1: MacroSelector.tsx** - `d321891` (feat)
2. **Task 2: StructureFieldsEditor.tsx + SectionGatingChips.tsx** - `5a134e1` (feat)
3. **Task 3: diseno.tsx 아코디언 그룹 1·2·3 + 미리보기 구조 연동 + RailsLayout.tsx previewItems** - `b7a752a` (feat)

_이 플랜은 tienda-app을 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/components/panel/MacroSelector.tsx` (신규) — 구조 선택 카드 4장
- `tienda-app/src/components/panel/StructureFieldsEditor.tsx` (신규) — 구조별 설정 필드
- `tienda-app/src/components/panel/SectionGatingChips.tsx` (신규) — 섹션 게이팅 읽기 전용 칩
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` — 아코디언 그룹 1·2·3, 미리보기 상단 바, 미리보기 macro 분기
- `tienda-app/src/components/macro/RailsLayout.tsx` — `previewItems?` prop 추가(Rail/RailsLayout 양쪽)

## Decisions Made
- 미리보기 macro 분기를 plan 텍스트의 최소 예시(단일 `<section>` 그리드) 대신 `index.tsx`(61-09)의 `gated`/`visibleSections`/`heroSection` 전체 패턴으로 구현 — 근거는 위 key-decisions 참조. 최소 예시 그대로였다면 hero/benefits/newsletter 등 다른 섹션이 rails/masonry 미리보기에서 사라지는 회귀가 됐을 것
- `SectionGatingChips.tsx`에 `export const GATED_BY_MACRO`를 추가하지 않음(Task 2 acceptance criteria 문구와 상충 — 아래 Issues Encountered 참조)

## Deviations from Plan

None — 두 결정 모두 plan 본문의 명시적 설계 의도(실제 컴포넌트 재사용/중복 재정의 금지, GATED_BY_MACRO 단일 소유지)를 그대로 따른 것이며 Rule 1~3의 "버그 자동수정/누락 기능 추가/차단 이슈 해결" 범주에 해당하는 코드 변경은 없었다.

## Issues Encountered
- Task 2 acceptance criteria 문구 1건이 plan 본문의 설계 의도·threat model·최종 `<verification>` 블록과 상충: `grep -c "export const GATED_BY_MACRO" tienda-app/src/components/panel/SectionGatingChips.tsx == 1`을 요구하지만, 같은 태스크의 action 텍스트("게이팅 규칙 단일 소유지 = @/lib/theme-preset. 여기서 재정의하지 않고 import"), threat register(T-61-52: "GATED_BY_MACRO를 @/lib/theme-preset 단일 export로 통일... 로컬 재정의 0건 acceptance"), 플랜 최종 `<verification>` 블록(`grep -rn "const GATED_BY_MACRO" tienda-app/src/ | wc -l` 기대값 `1`, 주석 "(SectionGatingChips.tsx 만)")이 모두 서로 다른 것을 요구한다. 실제로 `theme-preset.ts`에 이미 `export const GATED_BY_MACRO`가 1건 존재하므로, `SectionGatingChips.tsx`에도 같은 이름의 `export const`를 추가하면 총 2건이 되어 플랜 자신의 최종 verification과 T-61-52 acceptance("로컬 재정의 0건")를 동시에 위반한다. import-only로 구현해 `grep -rn "const GATED_BY_MACRO" tienda-app/src/` 총 1건(검증 완료)을 충족시켰고, 이 acceptance 문구 1건만 계획 작성 시점의 오타로 판단했다(61-05/61-08 SUMMARY에도 유사한 acceptance 문구 오차 전례 있음).
- `Ajustes de ${MACRO_LABEL[macro]}` acceptance grep은 정규식 이스케이프(`\$`) 없이 리터럴로 매칭했는데, 실제 코드가 JSX 표현식(`title={\`Ajustes de ${MACRO_LABEL[macro]}\`}`)이라 문자열 그대로 일치함을 확인(문제 없음).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` 모두 exit 0 확인
- `grep -rn "const GATED_BY_MACRO" tienda-app/src/` 총 1건(theme-preset.ts만) — 단일 소유지 유지 확인
- `git diff tienda-app/package.json` 0줄 — 의존성 3개 고정 유지 확인
- Plan 61-16(브라우저 UAT)이 이 플랜의 "구조 카드 4장 클릭 → 미리보기 즉시 교체 → rails/masonry publish → 공개 페이지 반영" 흐름을 검증할 수 있는 상태
- `SectionListEditor.tsx`의 `TODO(Plan 61-11)`/`TODO(Plan 61-14)`(reels/quiz 서브폼)는 이 플랜 범위 밖으로 그대로 유지됨

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/panel/MacroSelector.tsx
- FOUND: tienda-app/src/components/panel/StructureFieldsEditor.tsx
- FOUND: tienda-app/src/components/panel/SectionGatingChips.tsx
- FOUND: tienda-app/src/pages/[storeId]/panel/diseno.tsx
- FOUND: tienda-app/src/components/macro/RailsLayout.tsx
- FOUND commit: d321891
- FOUND commit: 5a134e1
- FOUND commit: b7a752a
