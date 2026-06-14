---
phase: 39-modo-restaurante-pos-mesas
plan: 04
type: execute
wave: 2
depends_on: [39-01]
files_modified:
  - api-ventago/src/app/store/config/storeConfig.controller.ts
  - api-ventago/src/app/store/config/storeConfig.service.ts
  - api-ventago/src/app/store/config/storeConfig.controller.spec.ts
autonomous: true
requirements: [REQ-1]
must_haves:
  truths:
    - "configuración 토글이 use_restaurant_mode 플래그를 저장한다 (BadRequestException 없이)"
    - "restaurant_category_ids 목록을 저장/조회할 수 있다"
    - "store_config 행이 없는 매장도 토글 저장이 안전하다 (findOrCreate)"
  artifacts:
    - path: "api-ventago/src/app/store/config/storeConfig.controller.ts"
      provides: "update-flag 화이트리스트에 useRestaurantMode + 카테고리 id 저장 라우트"
      contains: "useRestaurantMode"
  key_links:
    - from: "storeConfig.controller.ts update-flag"
      to: "allowedFields 배열"
      via: "useRestaurantMode 화이트리스트 추가"
      pattern: "useRestaurantMode"
---

<objective>
req1 백엔드: storeConfig.controller 의 update-flag 화이트리스트(@Patch + @Put 두 곳)에 `useRestaurantMode` 를 추가하고, 식당 카테고리 id 목록(restaurantCategoryIds) 저장/조회 경로를 마련한다. 화이트리스트 누락 시 토글이 BadRequestException 으로 막히는 흔한 누락을 방어.

Purpose: 39-06 configuración 토글 UI 가 호출할 백엔드. 화이트리스트 1줄 누락이 전체 기능을 막으므로 명시적 task.
Output: controller 화이트리스트 2곳 수정 + 카테고리 id 저장 라우트 + service findOrCreate 보강 + spec.
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/39-modo-restaurante-pos-mesas/39-RESEARCH.md
@CLAUDE.md

<interfaces>
<!-- storeConfig.controller.ts 기존 라우트 (코드베이스에서 추출) -->
```typescript
@Get(':storeId')           findByStoreId
@Post(':storeId')          create
@Put(':storeId')           update
@Patch(':storeId/update-flag')  updateFlagPatch  // allowedFields 배열 (line 54)
@Put(':storeId/update-flag')    updateFlagPut    // allowedFields 배열 (line 76) — 둘 다 수정 필요
@Patch(':storeId/update-digits') ...
@Put(':storeId/update-currency') ...
```
body: { field: string, value: any }. allowedFields.includes(body.field) 아니면 BadRequestException.
39-01 이 StoreConfig 모델에 useRestaurantMode(default false) + restaurantCategoryIds(JSONB) 추가 완료.
storeConfig.service.ts:14 findByStoreId 는 행 없으면 NotFoundException (Pitfall 2).
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: update-flag 화이트리스트에 useRestaurantMode 추가 + 카테고리 id 저장 라우트 + findOrCreate 보강 + spec</name>
  <read_first>
    - api-ventago/src/app/store/config/storeConfig.controller.ts (allowedFields 배열 2곳: line ~54 @Patch, line ~76 @Put — 정확한 위치 확인)
    - api-ventago/src/app/store/config/storeConfig.service.ts (findByStoreId line 14 — NotFoundException, findOrCreate 보강 대상)
    - api-ventago/src/app/store/config/storeConfig.model.ts (39-01 산출 — useRestaurantMode/restaurantCategoryIds 컬럼)
    - 39-RESEARCH.md Pattern 1 + Pitfall 2 (화이트리스트 누락 / store_config 행 부재)
  </read_first>
  <behavior>
    - update-flag 호출 field='useRestaurantMode' value=true → 200, DB use_restaurant_mode=true
    - update-flag field='useRestaurantMode' 가 allowedFields 에 없던 상태였으면 BadRequest → 추가 후 통과
    - restaurantCategoryIds 저장 라우트 호출 → JSONB 배열 저장
    - store_config 행 없는 storeId 토글 → findOrCreate 로 행 생성 후 저장 (500 아님)
  </behavior>
  <action>
**storeConfig.controller.ts — 두 allowedFields 배열에 'useRestaurantMode' 추가** (@Patch update-flag line ~54, @Put update-flag line ~76 둘 다):
```typescript
const allowedFields = [
  ...,                  // 기존 use* 필드들 유지
  'useRestaurantMode',  // Phase 39: 식당 모드 토글
];
```
주의: 두 곳 모두 수정 안 하면 PUT/PATCH 중 하나가 BadRequest (흔한 누락).

**식당 카테고리 id 목록 저장 라우트** — restaurantCategoryIds 는 BOOLEAN 토글이 아닌 배열이므로 별도 경량 라우트:
```typescript
// Phase 39: 식당 메뉴 카테고리 id 목록 저장
@Put(':storeId/restaurant-categories')
async updateRestaurantCategories(
  @Param('storeId') storeId: number,
  @Body() body: { categoryIds: number[] },
) {
  return this.service.updateRestaurantCategories(storeId, body.categoryIds);
}
```

**storeConfig.service.ts**:
- `updateRestaurantCategories(storeId, categoryIds)`: findOrCreate 로 행 확보 후 `restaurantCategoryIds` UPDATE. categoryIds 가 number[] 인지 방어(Array.isArray).
- update-flag 처리 메서드(또는 findByStoreId 사용처)가 행 부재 시 findOrCreate 폴백하도록 보강 (Pitfall 2 — 레거시 매장 store_config 누락 방어). 기존 NotFoundException 동작은 GET 에서는 유지하되, 토글 저장 경로는 findOrCreate.

**storeConfig.controller.spec.ts** (신규 또는 보강) — positional args + service mock:
- updateFlagPatch(field='useRestaurantMode') → service 호출 + BadRequest 안 남
- updateFlagPatch(field='badField') → BadRequestException
- updateRestaurantCategories → service.updateRestaurantCategories 호출

ESLint(return 위 빈 줄, // 위 빈 줄, 미사용 import 0). tsc 통과.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx jest storeConfig --silent 2>&1 | tail -20</automated>
  </verify>
  <acceptance_criteria>
    - grep -c "useRestaurantMode" api-ventago/src/app/store/config/storeConfig.controller.ts 결과 ≥ 2 (@Patch + @Put 화이트리스트 둘 다)
    - storeConfig.controller.ts 에 @Put(':storeId/restaurant-categories') 라우트 존재
    - storeConfig.service.ts 에 updateRestaurantCategories 메서드 + findOrCreate 호출 존재
    - `npx jest storeConfig` 전부 PASS — useRestaurantMode 통과 케이스 + badField BadRequest 케이스 포함
    - grep "Array.isArray" storeConfig.service.ts (categoryIds 방어)
  </acceptance_criteria>
  <done>화이트리스트 2곳에 useRestaurantMode 추가, 카테고리 id 저장 라우트 + findOrCreate 보강, jest green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| client → update-flag | 임의 컬럼 주입 시도 |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-08 | Tampering | update-flag body.field | mitigate | allowedFields 화이트리스트 — useRestaurantMode 외 임의 필드 BadRequest (기존 패턴 유지) |
| T-39-09 | Tampering | restaurantCategoryIds | mitigate | service Array.isArray 검증 + number[] 만 저장 |
</threat_model>

<verification>
- npx jest storeConfig green
- tsc 에러 0
</verification>

<success_criteria>
- use_restaurant_mode 토글 저장 동작 (화이트리스트 통과)
- 식당 카테고리 id 목록 저장/조회
- store_config 행 부재 매장 안전
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-04-SUMMARY.md` 작성.
</output>
