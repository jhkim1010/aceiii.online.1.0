---
phase: 39-modo-restaurante-pos-mesas
plan: 02
type: execute
wave: 2
depends_on: [39-01]
files_modified:
  - api-ventago/src/app/restaurant-tables/restaurant-tables.service.ts
  - api-ventago/src/app/restaurant-tables/restaurant-tables.controller.ts
  - api-ventago/src/app/restaurant-tables/restaurant-tables.module.ts
  - api-ventago/src/app/restaurant-tables/dto/restaurant-table.dto.ts
  - api-ventago/src/app/restaurant-tables/restaurant-tables.service.spec.ts
  - api-ventago/src/app.module.ts
autonomous: true
requirements: [REQ-2, REQ-5]
must_haves:
  truths:
    - "branch 별 테이블 목록을 위치/형태/상태와 함께 단일 SELECT 로 조회할 수 있다"
    - "관리자가 테이블을 추가/이동(x/y)/삭제할 수 있다 (CRUD API)"
    - "테이블 좌표는 정규화 0~1 범위로 검증되어 저장된다"
  artifacts:
    - path: "api-ventago/src/app/restaurant-tables/restaurant-tables.service.ts"
      provides: "테이블 CRUD + store/branch 스코프 + 상태 동기화 헬퍼"
      contains: "class RestaurantTablesService"
    - path: "api-ventago/src/app/restaurant-tables/restaurant-tables.controller.ts"
      provides: "GET by-branch / POST / PUT / PUT 좌표 / DELETE 라우트"
      exports: ["RestaurantTablesController"]
    - path: "api-ventago/src/app/restaurant-tables/dto/restaurant-table.dto.ts"
      provides: "class-validator DTO (shape enum, seats>0, posX/Y 0~1, status enum)"
      contains: "class CreateRestaurantTableDto"
  key_links:
    - from: "api-ventago/src/app.module.ts"
      to: "RestaurantTablesModule"
      via: "imports 배열 등록"
      pattern: "RestaurantTablesModule"
---

<objective>
restaurant_tables CRUD 백엔드 모듈을 신규 생성한다: service(store/branch 스코프 강제 + 좌표/상태 동기화 헬퍼) + controller(by-branch 조회, 생성/이동/삭제) + class-validator DTO + app.module 등록 + 유닛 스펙. 배치도 편집기(req5)와 SalonView 렌더(req4)가 소비하는 데이터 소스.

Purpose: salon 렌더가 sales JOIN 없이 단일 SELECT 로 끝나도록(pool 절약, 300ms) restaurant_tables 가 진실의 원천. 상태 동기화 헬퍼는 39-03 sale lifecycle 이 트랜잭션 안에서 호출.
Output: RestaurantTablesModule (model 제외 4파일) + app.module 등록 + spec.
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

<interfaces>
<!-- 39-01 이 만든 모델 컨트랙트 — 이걸 직접 사용, 코드베이스 재탐색 불필요 -->
RestaurantTable (api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts):
```typescript
export enum TableShape { CIRCLE='circle', OVAL='oval', SQUARE='square', RECT='rect' }
export enum TableStatus { LIBRE='libre', OCUPADA='ocupada', POR_COBRAR='por_cobrar' }
class RestaurantTable: { storeId, branchId, name, shape, seats, posX, posY, zone?, status, currentSaleId? }
```
패턴 참조 — Phase 29 mp 모듈이 독립 모듈 + app.module 등록 선례.
멀티테넌트: 모든 쿼리 WHERE store_id/branch_id 스코프 강제 (IDOR 방지).
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: DTO + Service (CRUD + 스코프 + 상태 동기화 헬퍼) + spec</name>
  <read_first>
    - api-ventago/src/app/restaurant-tables/restaurant-tables.model.ts (39-01 산출 — 컬럼/enum)
    - api-ventago/src/app/sellers/sellers.service.ts 또는 유사 단순 CRUD service (Sequelize @InjectModel + findAll/create/update/destroy 패턴)
    - 39-RESEARCH.md Security Domain (IDOR: storeId/branchId WHERE 강제) + Pitfall 3 (상태↔sale drift 트랜잭션)
    - api-ventago/src/app/mercadopago/ 임의 모듈 (NestJS 모듈/spec 구조 — positional constructor args 로 spec 작성한 Phase 29 선례)
  </read_first>
  <behavior>
    - findByBranch(storeId, branchId): 해당 branch 테이블 배열 단일 SELECT 반환 (sales JOIN 없음)
    - create: posX/posY 0~1 범위 밖이면 클램프 또는 거부, shape/status enum 검증
    - update: 타 store 테이블 수정 시 NotFound (스코프 WHERE)
    - updatePosition(id, storeId, posX, posY): 좌표만 UPDATE
    - syncTableStatus(tx, tableId, status, currentSaleId): 트랜잭션 인자 받아 status+current_sale_id 원자 UPDATE (39-03 이 호출)
    - delete: ocupada(current_sale_id 있음) 테이블 삭제 거부 (BadRequest)
  </behavior>
  <action>
**dto/restaurant-table.dto.ts** — class-validator:
```typescript
import { IsEnum, IsInt, IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { TableShape, TableStatus } from '../restaurant-tables.model';

export class CreateRestaurantTableDto {
  @IsInt() branchId: number;
  @IsString() @MaxLength(64) name: string;
  @IsEnum(TableShape) shape: TableShape;
  @IsInt() @Min(1) @Max(20) seats: number;
  @IsNumber() @Min(0) @Max(1) posX: number;
  @IsNumber() @Min(0) @Max(1) posY: number;
  @IsOptional() @IsString() @MaxLength(64) zone?: string;
}

export class UpdateRestaurantTableDto {
  @IsOptional() @IsString() @MaxLength(64) name?: string;
  @IsOptional() @IsEnum(TableShape) shape?: TableShape;
  @IsOptional() @IsInt() @Min(1) @Max(20) seats?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(1) posX?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(1) posY?: number;
  @IsOptional() @IsEnum(TableStatus) status?: TableStatus;
  @IsOptional() @IsString() @MaxLength(64) zone?: string;
}

export class UpdatePositionDto {
  @IsNumber() @Min(0) @Max(1) posX: number;
  @IsNumber() @Min(0) @Max(1) posY: number;
}
```

**restaurant-tables.service.ts** — @InjectModel(RestaurantTable). 메서드:
- `findByBranch(storeId: number, branchId: number)`: `this.model.findAll({ where: { storeId, branchId }, order: [['id','ASC']] })`. 단일 SELECT, sales JOIN 금지.
- `create(storeId, dto)`: `this.model.create({ ...dto, storeId, status: 'libre' })`.
- `update(id, storeId, dto)`: `findOne({where:{id, storeId}})` → 없으면 NotFoundException, 있으면 `row.update(dto)`. (스코프 = IDOR 방지)
- `updatePosition(id, storeId, posX, posY)`: 동일 스코프 조회 후 `update({posX, posY})`.
- `remove(id, storeId)`: 스코프 조회 후 `currentSaleId != null` 이면 BadRequestException('점유 중 테이블 삭제 불가'), 아니면 destroy. apiConnector 무관(백엔드).
- `syncTableStatus(table, status, currentSaleId, options)`: `table.update({ status, currentSaleId }, options)` — options 에 transaction 전달받아 39-03 트랜잭션 안에서 호출.

**restaurant-tables.service.spec.ts** — Phase 29 선례대로 positional constructor args 로 service 인스턴스화 + model mock(findAll/findOne/create/update/destroy jest.fn). 케이스:
- findByBranch 가 where:{storeId,branchId} 로 findAll 호출 + JOIN 미사용 검증
- update(타 store) → NotFoundException
- create 가 status:'libre' 강제
- remove(currentSaleId 있음) → BadRequestException

한국어 주석, ESLint(return 위 빈 줄, 미사용 import 0).
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx jest restaurant-tables.service --silent 2>&1 | tail -20</automated>
  </verify>
  <acceptance_criteria>
    - api-ventago/src/app/restaurant-tables/restaurant-tables.service.ts 에 `class RestaurantTablesService` + 메서드 findByBranch/create/update/updatePosition/remove/syncTableStatus 전부 존재
    - grep "where: { storeId, branchId }" 또는 동등 스코프 WHERE 가 findByBranch 에 존재 (멀티테넌트 격리)
    - grep "transaction" restaurant-tables.service.ts 에서 syncTableStatus 가 options/transaction 인자 수용
    - DTO 에 `@Min(0) @Max(1) posX` + `@IsEnum(TableShape)` + `@IsEnum(TableStatus)` 존재
    - `npx jest restaurant-tables.service` 전부 PASS (최소 4 케이스)
    - restaurant-tables.service.ts grep "JOIN\|include:" 결과 0 (findByBranch sales JOIN 금지 — pool 절약)
  </acceptance_criteria>
  <done>Service + DTO + spec 완성, jest green. 모든 CRUD 가 store/branch 스코프 강제, findByBranch 단일 SELECT.</done>
</task>

<task type="auto">
  <name>Task 2: Controller (by-branch/POST/PUT/PUT 좌표/DELETE) + Module + app.module 등록</name>
  <read_first>
    - api-ventago/src/app/store/config/storeConfig.controller.ts (라우트 순서 — 구체 경로가 :id 위, @Auth/@Put/@Patch 데코레이터 + user.storeId 추출 패턴)
    - api-ventago/src/app.module.ts (모듈 imports 배열 위치 — Phase 29 MercadopagoModule 등록 선례)
    - api-ventago/src/app/restaurant-tables/restaurant-tables.service.ts (Task 1 산출 — 메서드 시그니처)
    - 39-RESEARCH.md Open Q1 (타이밍 API 는 39-03 sales 쪽 — 여기선 테이블 CRUD 만)
  </read_first>
  <action>
**restaurant-tables.controller.ts** — @Controller('restaurant-tables') + 인증 가드(@Auth() 또는 프로젝트 표준). user.storeId 로 스코프. 라우트 순서: 구체 경로를 `:id` 위에 배치(NestJS 우선순위, Phase 01-ui-ux 선례).
```
@Get('by-branch/:branchId')  findByBranch  → service.findByBranch(user.storeId, branchId)
@Post()                       create        → service.create(user.storeId, dto)        // CreateRestaurantTableDto
@Put(':id/position')          updatePosition→ service.updatePosition(id, user.storeId, dto.posX, dto.posY) // 구체 경로 먼저
@Put(':id')                   update        → service.update(id, user.storeId, dto)    // UpdateRestaurantTableDto
@Delete(':id')                remove        → service.remove(id, user.storeId)
```
user.storeId! non-null assertion (Phase 26 ExpenseCategoryController 선례 — @Auth() 가 storeId 보장).

**restaurant-tables.module.ts**:
```typescript
@Module({
  imports: [SequelizeModule.forFeature([RestaurantTable])],
  controllers: [RestaurantTablesController],
  providers: [RestaurantTablesService],
  exports: [RestaurantTablesService],  // 39-03 sales-create 가 syncTableStatus 사용
})
export class RestaurantTablesModule {}
```
exports 필수 — 39-03 SalesModule(또는 restaurant-sale service)이 RestaurantTablesService.syncTableStatus 호출.

**app.module.ts**: imports 배열에 `RestaurantTablesModule` 추가 (MercadopagoModule 인근). import 문 추가.

ESLint: 미사용 import 0, return 위 빈 줄. apiConnector 무관. tsc + nest 부팅 통과.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx tsc --noEmit 2>&1 | grep -i "restaurant-tables" | head; echo "TSC_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - restaurant-tables.controller.ts 에 @Get('by-branch/:branchId'), @Post(), @Put(':id/position'), @Put(':id'), @Delete(':id') 5 라우트 존재
    - @Put(':id/position') 가 @Put(':id') 보다 위(파일 라인 순서)에 위치 (라우트 우선순위)
    - restaurant-tables.module.ts 의 exports 배열에 RestaurantTablesService 포함
    - grep "RestaurantTablesModule" api-ventago/src/app.module.ts 결과 2건 (import 문 + imports 배열)
    - `npx tsc --noEmit` 에서 restaurant-tables 관련 에러 0
  </acceptance_criteria>
  <done>Controller 5 라우트 + Module + app.module 등록 완료. syncTableStatus 가 exports 로 39-03 에 노출됨. tsc 통과.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| client → restaurant-tables API | 다른 매장 테이블 CRUD 시도(IDOR), 비정상 좌표/좌석 주입 |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-03 | Tampering/Info | findByBranch/update | mitigate | service 모든 쿼리 WHERE storeId(+branchId) 강제 — user.storeId 출처는 JWT |
| T-39-04 | Tampering | create/update DTO | mitigate | class-validator posX/Y @Min(0)@Max(1), seats @Min(1), shape/status @IsEnum + DB CHECK 이중 방어 |
| T-39-05 | Elevation | 배치 편집 라우트 | mitigate | 편집 진입점은 configuración 프론트(39-06)에만, 라우트도 @Auth 스코프 (req5 권한 분리) |
</threat_model>

<verification>
- npx jest restaurant-tables.service green
- npx tsc --noEmit 에러 0
- nest 부팅(선택): RestaurantTablesModule DI 해결
</verification>

<success_criteria>
- 테이블 CRUD API 존재, by-branch 조회가 위치/형태/상태 정확 반환
- 좌표 0~1 검증, 스코프 격리
- syncTableStatus exports 로 39-03 에 제공
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-02-SUMMARY.md` 작성.
</output>
