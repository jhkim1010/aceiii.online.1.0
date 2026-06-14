---
phase: 39-modo-restaurante-pos-mesas
plan: 02
subsystem: tables-crud
tags: [restaurant, nestjs, crud, sequelize, multitenant, dto]
requires:
  - "RestaurantTable Sequelize 모델 (39-01)"
  - "restaurant_tables 테이블 + sales.table_id FK (39-01)"
provides:
  - "RestaurantTablesModule (service + controller + module + dto)"
  - "RestaurantTablesService.findByBranch — 단일 SELECT 테이블 목록 (salón 렌더 소스)"
  - "RestaurantTablesService.syncTableStatus — 상태↔sale 트랜잭션 동기화 헬퍼 (39-03 소비)"
  - "REST CRUD: GET by-branch / POST / PUT :id/position / PUT :id / DELETE"
  - "RestaurantTable 모델 DI 등록 (SequelizeModule.forFeature)"
affects:
  - api-ventago/src/app.module.ts
tech-stack:
  added: []
  patterns:
    - "멀티테넌트 IDOR 방지: 모든 쿼리 WHERE store_id(+branch_id) 강제, 스코프 미스→NotFound"
    - "class-validator 정규화 좌표 검증 @Min(0)@Max(1) + DB CHECK 이중 방어"
    - "findByBranch 단일 SELECT (sales JOIN 금지) — pool 절약 300ms 타겟"
    - "라우트 우선순위: 구체 경로(:id/position)를 :id 위에 배치"
    - "spec positional constructor args (NestJS DI 우회, @InjectModel 메타데이터)"
key-files:
  created:
    - api-ventago/src/app/restaurant-tables/restaurant-tables.service.ts
    - api-ventago/src/app/restaurant-tables/restaurant-tables.controller.ts
    - api-ventago/src/app/restaurant-tables/restaurant-tables.module.ts
    - api-ventago/src/app/restaurant-tables/dto/restaurant-table.dto.ts
    - api-ventago/src/app/restaurant-tables/restaurant-tables.service.spec.ts
  modified:
    - api-ventago/src/app.module.ts
decisions:
  - "findScoped() private 헬퍼로 update/updatePosition/remove 스코프 조회 통일 (IDOR 방지 단일 지점)"
  - "syncTableStatus 가 RestaurantTable 인스턴스 + options.transaction 수용 — 39-03 이 이미 로드한 row 를 재사용(중복 SELECT 회피)"
  - "remove 는 currentSaleId != null 이면 BadRequest (점유 중 삭제 거부, 데이터 정합성)"
  - "module exports 에 SequelizeModule 추가 (Sellers 선례) — 39-03 가 모델 직접 @InjectModel 시 재사용 가능"
metrics:
  duration: ~4min
  tasks: 2
  files: 6
  completed: 2026-06-14
---

# Phase 39 Plan 02: Tables CRUD Summary

restaurant_tables CRUD 백엔드 모듈 신규 생성 — store/branch 멀티테넌트 스코프를 강제하는 RestaurantTablesService(findByBranch 단일 SELECT + create/update/updatePosition/remove + syncTableStatus 트랜잭션 동기화 헬퍼) + 5 라우트 컨트롤러(@Auth) + 정규화 좌표 검증 class-validator DTO 3종 + 모델 DI 등록(SequelizeModule.forFeature) + app.module 등록 + 6 케이스 유닛 스펙. salón 렌더(39-07)와 배치도 편집기(39-06)의 데이터 소스이자, 39-03 sale lifecycle 이 트랜잭션 안에서 호출할 상태 동기화 헬퍼를 exports 로 제공.

## What Was Built

### Task 1: DTO + Service + spec (TDD)
- **dto/restaurant-table.dto.ts**: `CreateRestaurantTableDto`(branchId, name≤64, shape `@IsEnum(TableShape)`, seats `@Min(1)@Max(20)`, posX/posY `@Min(0)@Max(1)`, zone? optional) + `UpdateRestaurantTableDto`(전부 optional + status `@IsEnum(TableStatus)`) + `UpdatePositionDto`(posX/posY 0~1).
- **restaurant-tables.service.ts**: `@InjectModel(RestaurantTable)` 주입. 메서드:
  - `findByBranch(storeId, branchId)`: `findAll({ where: { storeId, branchId }, order: [['id','ASC']] })` — sales JOIN/include 없는 단일 SELECT (pool 절약).
  - `create(storeId, dto)`: status `TableStatus.LIBRE` 강제 + storeId 주입.
  - `update / updatePosition / remove`: 공통 private `findScoped(id, storeId)` 로 `findOne({ where: { id, storeId } })` 후 미스 시 `NotFoundException` (IDOR 방지).
  - `remove`: `currentSaleId != null` 이면 `BadRequestException`(점유 중 삭제 거부), 아니면 `destroy()`.
  - `syncTableStatus(table, status, currentSaleId, options?)`: `table.update({ status, currentSaleId }, options)` — options.transaction 으로 39-03 트랜잭션 안에서 원자 동기화 (상태↔sale drift 방지).
- **restaurant-tables.service.spec.ts**: positional constructor args 로 service 인스턴스화 + model mock(findAll/findOne/create jest.fn). 6 케이스: findByBranch where+include미사용 / create status=libre / update 타store→NotFound / remove 점유중→BadRequest / remove 빈테이블→destroy / syncTableStatus transaction 전달. **jest 6/6 PASS.**

### Task 2: Controller + Module + app.module 등록
- **restaurant-tables.controller.ts**: `@Controller('restaurant-tables')` 전 라우트 `@Auth()`. `user.storeId` 로 스코프. 5 라우트 — `@Get('by-branch/:branchId')` / `@Post()` / `@Put(':id/position')` / `@Put(':id')` / `@Delete(':id')`. `:id/position`(line 49)을 `:id`(line 65) 위에 배치(라우트 우선순위).
- **restaurant-tables.module.ts**: `SequelizeModule.forFeature([RestaurantTable])` (39-01 모델 DI 등록) + controllers/providers + `exports: [RestaurantTablesService, SequelizeModule]` (39-03 소비).
- **app.module.ts**: import 문 + imports 배열에 `RestaurantTablesModule` 추가 (MercadopagoModule 인근). **tsc --noEmit 전체 0 에러.**

## Acceptance Criteria Verification

| 기준 | 결과 |
|------|------|
| class RestaurantTablesService + findByBranch/create/update/updatePosition/remove/syncTableStatus | PASS (6 메서드 전부) |
| findByBranch 에 `where: { storeId, branchId }` 스코프 WHERE | PASS |
| syncTableStatus 가 options/transaction 인자 수용 | PASS (`table.update(..., options)`) |
| DTO @Min(0)@Max(1) posX + @IsEnum(TableShape) + @IsEnum(TableStatus) | PASS |
| jest restaurant-tables.service 최소 4 케이스 PASS | PASS (6/6) |
| findByBranch sales JOIN/include 코드 0 (pool 절약) | PASS (코드 0, 주석 2건만 "JOIN 없음" 명시) |
| 5 라우트 (by-branch/POST/:id/position/:id/DELETE) | PASS |
| :id/position 이 :id 보다 위 | PASS (49 < 65) |
| module exports 에 RestaurantTablesService | PASS |
| app.module RestaurantTablesModule 2건 (import + imports) | PASS |
| tsc --noEmit restaurant-tables 에러 0 | PASS (전체 0) |

## Deviations from Plan

플랜과 동일하게 구현. 소소한 구현 결정 2건:
1. **findScoped() private 헬퍼 도입** — 플랜은 update/updatePosition/remove 각각 인라인 스코프 조회를 제시했으나, IDOR 방지 스코프 WHERE 를 단일 지점으로 통일하기 위해 private 헬퍼로 추출 (중복 제거 + 일관성). 동작·acceptance 동일.
2. **module exports 에 SequelizeModule 추가** — 플랜은 `exports: [RestaurantTablesService]` 만 명시했으나 Sellers 선례대로 SequelizeModule 도 export (39-03 가 RestaurantTable 모델을 직접 @InjectModel 할 경우 재사용). 추가일 뿐 영향 없음.

모델 필드는 39-01 실제 모델과 일치 확인 (storeId/branchId/name/shape/seats/posX/posY/zone?/status/currentSaleId?). 환경 블로커 없음 — jest/tsc 로컬 정상 실행.

## Known Stubs

없음 — 이 플랜은 백엔드 CRUD API 완성. 프론트 wiring(배치도 편집기 39-06, salón 렌더 39-07)은 후속 플랜.

## Commits

| Task | Submodule(api-ventago) | Parent(main) |
|------|------------------------|--------------|
| 1 (DTO + Service + spec) | 588f206 | d7960c4 |
| 2 (Controller + Module + app.module) | b2ad63d | 013d144 |

## Follow-ups (후속 플랜 입력)

- **39-03 (lifecycle)**: `RestaurantTablesService.syncTableStatus(table, status, currentSaleId, { transaction })` 를 sale 생성/결제 트랜잭션 안에서 호출 — 점유(ocupada+currentSaleId) / 결제완료(libre+null) 동기화. exports 로 노출됨.
- **39-06 (config-editor)**: POST/PUT :id/position/DELETE 라우트 소비 — 배치도 드래그 이동은 `PUT :id/position` 사용.
- **39-07 (salonview)**: `GET /restaurant-tables/by-branch/:branchId` 로 위치/형태/상태 단일 SELECT 조회 → 캔버스 렌더(posX/posY 0~1 → 픽셀 변환).

## Self-Check: PASSED

- 생성 파일 5종 (service/controller/module/dto/spec) 전부 FOUND
- 서브모듈 커밋 588f206 / b2ad63d FOUND
- 부모 포인터 커밋 d7960c4 / 013d144 FOUND
- SUMMARY FOUND
