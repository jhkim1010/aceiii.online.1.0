---
phase: 39-modo-restaurante-pos-mesas
plan: 06
type: execute
wave: 3
depends_on: [39-02, 39-04]
files_modified:
  - ventago-app/src/context/StoreConfigContext.tsx
  - ventago-app/src/pages/configuracion/restaurante.tsx
  - ventago-app/src/views/configuracion/restaurante/RestauranteConfigView.tsx
  - ventago-app/src/views/configuracion/restaurante/SalonEditor.tsx
  - ventago-app/src/hooks/api/useRestaurantTables.ts
autonomous: false
requirements: [REQ-1, REQ-4, REQ-5]
must_haves:
  truths:
    - "StoreConfigContext 가 useRestaurantMode 플래그를 노출한다 (분기 메커니즘)"
    - "configuración 에서 식당 모드 토글이 동작한다"
    - "관리자가 configuración 배치도 편집기에서 테이블을 추가/드래그(x/y 정규화 0~1)/삭제하면 저장되고 SalonView 에 반영된다"
    - "판매 화면(SalonView)에는 배치 편집 진입점이 없다 (권한 분리)"
  artifacts:
    - path: "ventago-app/src/context/StoreConfigContext.tsx"
      provides: "useRestaurantMode + restaurantCategoryIds context 노출"
      contains: "useRestaurantMode"
    - path: "ventago-app/src/views/configuracion/restaurante/SalonEditor.tsx"
      provides: "자유 드래그 배치도 편집기 (정규화 좌표)"
      contains: "getBoundingClientRect"
    - path: "ventago-app/src/hooks/api/useRestaurantTables.ts"
      provides: "테이블 목록 SWR 훅"
      contains: "useRestaurantTables"
  key_links:
    - from: "SalonEditor 드래그"
      to: "PUT /restaurant-tables/:id/position"
      via: "apiConnector.put 정규화 좌표"
      pattern: "restaurant-tables.*position"
---

<objective>
req1/4/5 프론트 절반: (1) StoreConfigContext 에 useRestaurantMode + restaurantCategoryIds 추가(분기 메커니즘), (2) configuración 식당 모드 토글 페이지, (3) configuración 전용 배치도 편집기 SalonEditor(자유 드래그, 정규화 0~1 좌표), (4) 테이블 목록 SWR 훅. SalonView 판매 화면에는 편집 진입점 없음(권한 분리).

Purpose: 39-07 SalonView 가 useRestaurantMode 로 분기하고 useRestaurantTables 로 렌더하려면 이 context+훅이 선행. 편집기는 configuración 에만.
Output: StoreConfigContext 확장 + 토글 페이지 + SalonEditor + SWR 훅.
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/39-modo-restaurante-pos-mesas/39-SPEC.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-CONTEXT.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-RESEARCH.md
@CLAUDE.md
@.claude/skills/sketch-findings-ace-online/SKILL.md

<interfaces>
<!-- 재사용 컨트랙트 -->
StoreConfigContext (ventago-app/src/context/StoreConfigContext.tsx):
  interface/defaultState/fetchConfig 3곳에 use* 노출 — useRestaurantMode 한 줄씩 추가.
  catch 폴백 default(false) 이미 처리 (Pitfall 2).
백엔드 라우트 (39-02/39-04):
  GET  /restaurant-tables/by-branch/:branchId   → 테이블 배열
  POST /restaurant-tables                        → 생성
  PUT  /restaurant-tables/:id/position           → { posX, posY } 정규화 0~1
  PUT  /restaurant-tables/:id                     → 수정
  DELETE /restaurant-tables/:id                   → 삭제 (apiConnector.remove)
  PATCH/PUT /store-config/:storeId/update-flag    → { field:'useRestaurantMode', value }
  PUT  /store-config/:storeId/restaurant-categories → { categoryIds }
apiConnector (src/services/api.service.ts): get/post/put/remove (NOT delete).
useApi/useSWR (src/hooks/useApi.ts): 5분 dedup SWR 패턴.
정규화 드래그(39-RESEARCH Code Examples): getBoundingClientRect → (clientX-left)/width 클램프 0~1.
테마: 다크 네이비 #0f0f1e bg / #1a1a2e surface / #f5a623 gold. 상태 색: libre/ocupada/por_cobrar 3단계.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: StoreConfigContext 확장 + useRestaurantTables SWR 훅 + 토글 페이지</name>
  <read_first>
    - ventago-app/src/context/StoreConfigContext.tsx (interface/defaultState/fetchConfig 3곳 — use* 추가 위치)
    - ventago-app/src/hooks/api/useCategoriesByStore.ts (SWR 훅 패턴 — 5분 dedup, apiConnector.get)
    - ventago-app/src/pages/configuracion/ (기존 configuración 페이지 구조 + next/dynamic + WithAccess 권한 게이트)
    - .claude/skills/sketch-findings-ace-online/references/configuracion-page.md (configuración 3-section 구조, 토글 테이블, info alert)
    - 39-RESEARCH.md Pattern 5 (StoreConfigContext 분기)
  </read_first>
  <action>
**StoreConfigContext.tsx** — 3곳 추가(미러 패턴):
```typescript
// interface
useRestaurantMode: boolean;
restaurantCategoryIds: number[] | null;
// defaultState
useRestaurantMode: false,
restaurantCategoryIds: null,
// fetchConfig (res 매핑)
useRestaurantMode: res?.useRestaurantMode ?? false,
restaurantCategoryIds: res?.restaurantCategoryIds ?? null,
```
기존 catch 폴백(false) 유지 — store_config 행 부재 매장 안전.

**hooks/api/useRestaurantTables.ts** — SWR 훅 (useCategoriesByStore 미러):
```typescript
export interface RestaurantTableRow {
  id: number; name: string; shape: string; seats: number;
  posX: number; posY: number; status: string; currentSaleId: number | null;
}

export const useRestaurantTables = (branchId?: number) => {
  const { data, error, isLoading, mutate } = useSWR(
    branchId ? `/restaurant-tables/by-branch/${branchId}` : null,
    fetcher, { dedupingInterval: 300000 },
  );

  return { tables: (data ?? []) as RestaurantTableRow[], error, isLoading, mutate };
};
```
RestaurantTableRow export — 39-07 재사용.

**pages/configuracion/restaurante.tsx** — next/dynamic(ssr:false) + WithAccess(admin/configuración 권한). RestauranteConfigView 로드.

**views/configuracion/restaurante/RestauranteConfigView.tsx** — sketch-findings configuracion-page 3-section:
- 식당 모드 토글(Switch) → apiConnector.put(`/store-config/${storeId}/update-flag`, { field:'useRestaurantMode', value }). 에러 시 인라인 Alert + 글로벌 토스트(더블, feedback_error_visibility).
- 식당 카테고리 선택(다중 select, useCategoriesByStore) → apiConnector.put(`/store-config/${storeId}/restaurant-categories`, { categoryIds }).
- 토글 ON 일 때만 SalonEditor(Task 2) 섹션/탭 노출.
다크 네이비+골드 테마. ESLint(return 위 빈 줄, // 위 빈 줄, 미사용 import 0). apiConnector.remove() (delete 아님).
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npx eslint src/context/StoreConfigContext.tsx src/hooks/api/useRestaurantTables.ts src/views/configuracion/restaurante/RestauranteConfigView.tsx src/pages/configuracion/restaurante.tsx 2>&1 | tail -20; echo "LINT_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - grep "useRestaurantMode" ventago-app/src/context/StoreConfigContext.tsx 결과 ≥ 3 (interface + defaultState + fetchConfig)
    - hooks/api/useRestaurantTables.ts 에 `useRestaurantTables` + `RestaurantTableRow` export + `dedupingInterval: 300000`
    - RestauranteConfigView.tsx 에 update-flag PUT(field:'useRestaurantMode') + restaurant-categories PUT 호출
    - RestauranteConfigView.tsx 에 인라인 Alert + 토스트 더블 에러 노출
    - grep ".delete(" 결과 0 (apiConnector.remove 사용)
    - npx eslint 위 4파일 에러 0 (newline-before-return / lines-around-comment / no-unused-vars 통과)
  </acceptance_criteria>
  <done>StoreConfigContext 3곳 확장 + SWR 훅 + 토글/카테고리 설정 페이지 완성, ESLint 0.</done>
</task>

<task type="auto">
  <name>Task 2: SalonEditor 자유 드래그 배치도 편집기 (정규화 좌표)</name>
  <read_first>
    - ventago-app/src/views/configuracion/restaurante/RestauranteConfigView.tsx (Task 1 — 진입점/storeId/branchId 컨텍스트)
    - ventago-app/src/hooks/api/useRestaurantTables.ts (Task 1 — 테이블 목록 + mutate)
    - .claude/skills/sketch-findings-ace-online/references/theme.md (색상/spacing 변수, 다크 네이비+골드)
    - 39-RESEARCH.md Code Examples (정규화 드래그 onPointerMove + 형태+좌석수 비례 크기) + Pattern 4 (D-08 정규화 좌표)
    - 39-CONTEXT.md D-08/D-10 (정규화 0~1, 형태+좌석수 파생 크기, w/h 미저장)
  </read_first>
  <action>
**views/configuracion/restaurante/SalonEditor.tsx** — 평면 캔버스 편집기 (configuración 전용):
- branch selector(useBranchByStore) → useRestaurantTables(branchId) 로 테이블 로드.
- 캔버스: containerRef div (position:relative, 다크 네이비 bg). 각 테이블 = 절대 배치 카드.
- 좌표→픽셀: `left = posX * containerW, top = posY * containerH` (정규화 0~1 → 픽셀).
- 형태+좌석수 비례 크기(39-RESEARCH): `BASE={circle:56,oval:72,square:56,rect:80}; scale=0.8+min(seats,12)/12*0.6; w=BASE[shape]*scale`.
- **순수 pointer 드래그**(dnd-kit 미사용, 권장):
```typescript
const onPointerMove = (e) => {
  const rect = containerRef.current.getBoundingClientRect();
  const nx = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
  const ny = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height));
  setDragPos({ x: nx, y: ny });
};
// onPointerUp: apiConnector.put(`/restaurant-tables/${id}/position`, { posX: nx, posY: ny }) → mutate()
```
- 추가: "테이블 추가" 버튼 → 형태 선택 + 좌석수 입력 → apiConnector.post('/restaurant-tables', { branchId, name, shape, seats, posX:0.5, posY:0.5 }) → mutate().
- 삭제: 테이블 선택 후 삭제 → apiConnector.remove(`/restaurant-tables/${id}`) → mutate(). (remove, NOT delete)
- 상태 색상: libre(중립)/ocupada(골드)/por_cobrar(경고 골드) — 편집기는 주로 libre.
- 에러: 인라인 Alert + 토스트 더블.
주의: 좌표는 반드시 정규화 0~1 저장(픽셀 금지 — D-08, anti-pattern). ESLint 준수. 한국어 주석.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npx eslint src/views/configuracion/restaurante/SalonEditor.tsx 2>&1 | tail -15; echo "LINT_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - SalonEditor.tsx 에 getBoundingClientRect + Math.min(1, Math.max(0, ...)) 정규화 클램프 존재
    - 드래그 종료 시 apiConnector.put 으로 `/restaurant-tables/${id}/position` { posX, posY } 호출
    - 테이블 추가(apiConnector.post '/restaurant-tables') + 삭제(apiConnector.remove) 존재
    - grep ".delete(" SalonEditor.tsx 결과 0
    - 형태+좌석수 비례 크기 파생(BASE 매핑 + scale) 존재, w/h 직접 저장 0
    - npx eslint SalonEditor.tsx 에러 0
  </acceptance_criteria>
  <done>SalonEditor 자유 드래그 편집기 완성 — 정규화 좌표 저장, 추가/삭제, 비례 크기, ESLint 0.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: configuración 토글 + 배치도 편집기 브라우저 검증 (사용자)</name>
  <action>dev 브라우저에서 식당 모드 토글 저장 / 카테고리 선택 / SalonEditor 테이블 추가·드래그·삭제 / 권한 분리를 확인한다.</action>
  <what-built>configuración 식당 모드 토글 + 카테고리 설정 + SalonEditor 배치도 편집기 완성. StoreConfigContext 가 useRestaurantMode 노출.</what-built>
  <how-to-verify>
    1. `./dev.sh` (또는 npm run dev:app + dev:api) 실행
    2. 식당 매장 admin 로그인 → configuración → 식당(restaurante) 페이지 진입
    3. 식당 모드 토글 ON → 저장 확인 (BadRequest 없음)
    4. 식당 카테고리 다중 선택 → 저장 확인
    5. SalonEditor 에서 "테이블 추가" → 형태/좌석수 선택 → 캔버스에 표시
    6. 테이블 드래그 → 위치 이동 → 새로고침 후에도 위치 유지 (정규화 좌표 저장 확인)
    7. 테이블 삭제 동작 확인
    8. 일반 seller(판매 권한만) 로그인 시 configuración 편집기 진입점 없음 확인 (권한 분리)
  </how-to-verify>
  <resume-signal>토글/카테고리/드래그/추가/삭제/권한분리 모두 정상이면 "approved", 문제 시 화면 설명.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| seller → 배치 편집 | 판매 권한 사용자가 배치 편집 시도 |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-14 | Elevation | SalonEditor 진입점 | mitigate | configuración 페이지 WithAccess(admin) 게이트 + SalonView 에는 편집 진입점 미배치 (req5) |
| T-39-15 | Tampering | 드래그 좌표 | mitigate | 클라이언트 0~1 클램프 + 백엔드 DTO @Min(0)@Max(1) 이중 검증 (39-02) |
</threat_model>

<verification>
- npx eslint 5파일 에러 0
- dev 브라우저: 토글/카테고리/드래그/추가/삭제/권한분리 manual
</verification>

<success_criteria>
- useRestaurantMode context 노출, 토글 동작
- 배치도 편집기 정규화 좌표 저장 → SalonView 반영
- 판매 화면 편집 진입점 없음
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-06-SUMMARY.md` 작성.
</output>
