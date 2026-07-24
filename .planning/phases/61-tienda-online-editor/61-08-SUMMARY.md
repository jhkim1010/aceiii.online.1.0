---
phase: 61-tienda-online-editor
plan: 08
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, panel-editor, accordion]

# Dependency graph
requires:
  - phase: 61-05
    provides: "StoreThemeContent 전체 타입 미러, ThemeContentProvider/useThemeContent(), uploadThemeAsset(), diseno.tsx의 content state 배선(통과용)"
  - phase: 61-06
    provides: "SectionRenderer.tsx + Hero/Benefits/Carousel/DuoBanners/Newsletter 섹션 컴포넌트"
provides:
  - "tienda-app/src/components/panel/PanelPrimitives.tsx — AccordionGroup/TextField/NumberField/SelectField/SwitchField/HintBanner/WarnBanner (표면 A 고정 팔레트)"
  - "tienda-app/src/components/panel/AssetUploadField.tsx — 업로드 필드(fileName 콜백 + 고정 스페인어 오류 카피)"
  - "tienda-app/src/components/panel/SectionListEditor.tsx — 섹션 순서(▲▼)/표시(👁) 편집 + 타입별 인라인 서브폼"
  - "diseno.tsx 아코디언 셸(5그룹: Identidad de marca/Barra de anuncio/Secciones del inicio/Colores y tipografía/Contacto & redes) — 나머지 7그룹은 Plan 61-10/61-13/61-15가 이어서 추가"
affects: [61-09, 61-10, 61-11, 61-13, 61-14, 61-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "표면 A 부품은 PanelPrimitives.tsx 단일 파일에 모아 재사용 — var(--*) 없이 리터럴 hex(#20203c/#32325a/#f5a623 등) 고정"
    - "SectionListEditor 의 섹션별 update() 클로저 패턴 — updateAt<T>() 제네릭 헬퍼로 discriminated union 캐스팅을 한 곳에만 국한"
    - "diseno.tsx 미리보기는 ThemeContentProvider + content.sections.map(SectionRenderer) 로 실제 발행 렌더 트리를 그대로 재사용(에디터 전용 스키매틱 렌더러 없음)"

key-files:
  created:
    - tienda-app/src/components/panel/PanelPrimitives.tsx
    - tienda-app/src/components/panel/AssetUploadField.tsx
    - tienda-app/src/components/panel/SectionListEditor.tsx
  modified:
    - tienda-app/src/pages/[storeId]/panel/diseno.tsx
    - tienda-app/src/lib/theme-preset.ts

key-decisions:
  - "GENRE_LABELS(theme-preset.ts)를 한국어→스페인어로 수정 — 이 플랜의 files_modified 목록 밖이지만, '🎨 Colores y tipografía' 아코디언 안에 그대로 노출되는 한국어 잔여 카피라 Rule 1(버그)로 즉시 수정"
  - "duoBanners 서브폼에 배너 추가/제거 버튼을 자체 추가(플랜 텍스트가 '최대 2개'만 명시하고 채우는 방법을 명시하지 않음) — DEFAULT_CONTENT.sections의 duoBanners.banners가 빈 배열로 시작하므로 추가 수단이 없으면 이 섹션은 영원히 편집 불가능해짐(Rule 2)"

patterns-established:
  - "AssetUploadField는 kind==='reelVideo'일 때만 미리보기를 파일명 텍스트로, 그 외에는 항상 <img src={minioImageUrl(...)}>로 렌더 — dangerouslySetInnerHTML 경로 자체가 존재하지 않음(T-61-40)"

requirements-completed: [R3, R2, R8]

# Metrics
duration: ~30min
completed: 2026-07-24
---

# Phase 61 Plan 08: 에디터 패널 셸 — 아코디언 레이아웃 전환 + SectionListEditor 기반 Summary

**diseno.tsx를 단일 패널에서 5개 아코디언 그룹(브랜드/공지바/섹션리스트/색상·타이포/연락처)으로 전환하고, 신규 SectionListEditor.tsx로 홈 섹션 순서·표시·인라인 편집을 구현하며, 미리보기를 실제 SectionRenderer 렌더 트리로 교체**

## Performance

- **Duration:** ~30 min (추정)
- **Started:** 2026-07-24T12:24:00Z (추정)
- **Completed:** 2026-07-24T12:54:19Z
- **Tasks:** 3/3 완료
- **Files modified:** 5 (신규 3 + 수정 2)

## Accomplishments
- `PanelPrimitives.tsx` — `AccordionGroup`(open state + `aria-expanded` + 90도 셰브론 회전) / `TextField` / `NumberField` / `SelectField` / `SwitchField`(숨긴 네이티브 checkbox + `<label>` 감싸기로 키보드 접근성 유지) / `HintBanner` / `WarnBanner`를 UI-SPEC 표면 A 고정 팔레트로 신설
- `AssetUploadField.tsx` — `uploadThemeAsset()` 업로드 + 실패 시 UI-SPEC 고정 스페인어 오류 카피(이미지 2MB/영상 20MB), SVG는 `<img src>`로만 렌더(T-61-40)
- `SectionListEditor.tsx` — `onMove()`(배열 swap) ▲▼ 순서 이동 + 👁 표시 토글 + 펼침 시 타입별 인라인 서브폼(hero/benefits/carousel/duoBanners/newsletter). reels/quiz는 `TODO(Plan 61-11)`/`TODO(Plan 61-14)` 주석만 남기고 가짜 UI를 만들지 않음. `disabledTypes`는 opacity+line-through로만 표시하고 토글/이동은 계속 허용(구조 전환 시 값 보존)
- `diseno.tsx` — 단일 패널을 5개 `AccordionGroup`으로 전환(Identidad de marca/Barra de anuncio/Secciones del inicio/Colores y tipografía/Contacto & redes), `patchContent()` 신설, 미리보기를 `ThemeContentProvider`+`content.sections.map(SectionRenderer)`로 교체(하드코딩 히어로 제거), carousel은 `initialItems={DUMMY}`로 편집 중 API 미호출(T-61-43), 에디터 노출 카피 전부 스페인어로 통일, 팔레트를 UI-SPEC 표면 A 값(#15152a/#1a1a2e/#20203c/#f5a623)으로 통일
- `theme-preset.ts` — `GENRE_LABELS` 한국어→스페인어 (Rule 1, 아래 참조)

## Task Commits

Each task was committed atomically:

1. **Task 1: PanelPrimitives.tsx + AssetUploadField.tsx** - `f1de42d` (feat)
2. **Task 2: SectionListEditor.tsx** - `b6ac5e6` (feat)
3. **Task 3: diseno.tsx 아코디언 전환 + content state + 스페인어 카피** - `d893310` (feat, theme-preset.ts 동반 수정)

## Files Created/Modified
- `tienda-app/src/components/panel/PanelPrimitives.tsx` (신규) - 아코디언/필드/배너 부품 7종
- `tienda-app/src/components/panel/AssetUploadField.tsx` (신규) - 업로드 필드
- `tienda-app/src/components/panel/SectionListEditor.tsx` (신규) - 섹션 리스트 편집기
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` - 아코디언 셸 전환, content 편집 UI 배선, 미리보기 SectionRenderer화, 팔레트/카피 통일
- `tienda-app/src/lib/theme-preset.ts` - `GENRE_LABELS` 스페인어 통일

## Decisions Made
- `duoBanners` 서브폼에 배너 추가(`+ Agregar banner`, 최대 2개)/제거(`✕ Quitar banner`) 버튼을 자체 추가 — 플랜은 "최대 2개, 각 = AssetUploadField+title+subtitle+href"만 명시했고, `DEFAULT_CONTENT.sections`의 `duoBanners.banners`가 빈 배열로 시작하므로 추가 수단 없이는 이 섹션이 영원히 빈 상태로 남는 Rule 2(누락된 핵심 기능) 이슈였음. UI-SPEC의 "리스트 편집 UI 공통 패턴"(bento 타일/rails 선반의 `+ Agregar {...}` dashed 버튼) 관례를 그대로 이식
- `GENRE_LABELS`(theme-preset.ts) 한국어→스페인어 — 파일이 이 플랜의 `files_modified` 선언 밖이지만, 새로 만든 "🎨 Colores y tipografía" 아코디언 안에서 그대로 렌더되는 한국어 잔여 카피를 발견해 Rule 1로 즉시 수정(성공 기준 "에디터 한국어 UI 카피 0건"과 직결)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GENRE_LABELS(theme-preset.ts) 한국어 카피 스페인어 통일**
- **Found during:** Task 3 (diseno.tsx의 "Colores y tipografía" 그룹에 기존 프리셋 피커를 이식하며 `GENRE_LABELS[g]`가 그대로 렌더되는 것을 확인)
- **Issue:** `theme-preset.ts`의 `GENRE_LABELS`(에디토리얼/모던 미니멀/분위기/플레이풀)가 한국어로 남아 있었음 — 이 플랜의 목표(에디터 노출 카피 전부 스페인어)를 이 파일을 고치지 않으면 달성 불가능
- **Fix:** `editorial→Editorial`, `modern-minimal→Moderno minimalista`, `atmospheric→Atmosférico`, `playful→Lúdico`로 교체, 발견 경위를 한국어 주석으로 명시
- **Files modified:** tienda-app/src/lib/theme-preset.ts
- **Verification:** `npx tsc --noEmit`/`npx eslint src/` exit 0, 렌더 텍스트 육안 확인(코드 리뷰)
- **Committed in:** `d893310` (Task 3 commit)

**2. [Rule 2 - Missing Critical] duoBanners 서브폼에 추가/제거 버튼 신설**
- **Found during:** Task 2 (SectionListEditor의 duoBanners 케이스 작성 중, `DEFAULT_CONTENT.sections`의 `duoBanners.banners: []`를 확인)
- **Issue:** 플랜 텍스트가 duoBanners 필드 구성(이미지/제목/부제/링크)만 명시하고 "빈 배열에서 항목을 어떻게 채우는지"는 명시하지 않음. 이대로면 admin이 이 섹션을 절대 채울 수 없는 기능 누락
- **Fix:** UI-SPEC의 "리스트 편집 UI 공통 패턴"(`+ Agregar {...}` dashed 버튼) 관례를 재사용해 최대 2개까지 추가/제거하는 버튼 추가
- **Files modified:** tienda-app/src/components/panel/SectionListEditor.tsx
- **Verification:** `npx tsc --noEmit`/`npx eslint` exit 0
- **Committed in:** `b6ac5e6` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 1 잔여 한국어 카피, 1 Rule 2 누락된 편집 진입점)
**Impact on plan:** 둘 다 이 플랜 자체의 성공 기준(카피 스페인어 통일 / 섹션 편집 가능)을 충족하기 위한 최소 수정. 스코프 크립 없음(theme-preset.ts 1줄 상수 교체 + SectionListEditor 내부 버튼 2종 추가).

## Issues Encountered
- Acceptance criteria 문구 3건이 실제 코드베이스 정상 상태와 문자열 카운트 방식 차이로 어긋남(모두 기능적 영향 없음, 61-05 SUMMARY에서도 동일 유형 발생):
  1. `AssetUploadField.tsx`의 `grep -c "uploadThemeAsset"` 기대값 `==1` — 실제 `2`(import 줄 1 + 호출 줄 1). `grep -c`는 매칭된 줄 수를 세므로 import+사용이 분리된 이상 최소 2가 불가피함(기존 코드베이스 관례 — `shop-api.ts`의 다른 함수들도 전부 이 패턴).
  2. `diseno.tsx`의 `grep -c "ThemeContentProvider"` 기대값 `==2` — 실제 `3`(import 1 + JSX 여는 태그 1 + 닫는 태그 1). Provider가 자식을 감싸는 이상 여는/닫는 태그가 분리돼 자연히 3이 됨.
  3. `diseno.tsx`의 한국어 잔여 카피 정규식(`초안 저장|발행하기|...`)이 `1`건 매칭 — 실제로는 코드 주석 `// 발행 전 최신 초안 저장 후 발행`(CLAUDE.md 규약상 코드 주석은 한국어 유지) 안의 부분 문자열 "초안 저장"이 우연히 일치한 것. 사용자 노출 UI 텍스트에는 한국어가 0건(육안 확인 + 정규식이 노리는 실제 버튼/메시지 문자열은 전부 스페인어로 교체됨).
  모두 계획 작성 시점의 문자열 카운트 오차이며 실제 기능/의도는 충족됨.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 61-09(index.tsx 공개몰 렌더 게이팅)가 이 플랜과 같은 `ThemeContentProvider`+`SectionRenderer` 패턴을 재사용 가능
- Plan 61-10(구조 선택 UI)이 "🎨 Colores y tipografía" 그룹 위에 그룹 1~3(`🧱 Estructura de la home`/`⚙️ Ajustes de {Estructura}`/`🧩 Secciones disponibles`)을 추가하고, `TODO(Plan 61-10)` 주석 위치에서 macro 선택 UI를 이식하면 됨(diseno.tsx의 macro state/patch 로직은 이미 준비돼 있고 UI만 없는 상태)
- Plan 61-11(reels)/61-14(quiz)이 SectionListEditor.tsx의 `TODO(Plan 61-11)`/`TODO(Plan 61-14)` 표시 지점에 서브폼을 추가하면 됨(switch-case 구조 그대로 재사용)
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` 모두 exit 0 — 이후 플랜이 컴파일 실패 없는 상태에서 시작 가능
- `Header.tsx`는 무변경 확인됨(`git diff` 0줄) — Plan 61-09가 로고/공지바 반영을 위해 이 파일을 소유권대로 확장하면 됨

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/panel/PanelPrimitives.tsx
- FOUND: tienda-app/src/components/panel/AssetUploadField.tsx
- FOUND: tienda-app/src/components/panel/SectionListEditor.tsx
- FOUND: tienda-app/src/pages/[storeId]/panel/diseno.tsx
- FOUND: tienda-app/src/lib/theme-preset.ts
- FOUND commit: f1de42d
- FOUND commit: b6ac5e6
- FOUND commit: d893310
