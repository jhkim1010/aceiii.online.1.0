---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 10
subsystem: client-import
tags: [client-import, dto, controller, module, batch, transaction]

requires:
  - 25-04 (ClientImport audit model + table)
  - 25-05 (CommonModule for OwnerScope plumbing)
  - 25-06 (manage-clientes-import slug seed)
  - 25-09 (CUIT/DNI validators)
provides:
  - api-ventago/src/app/client-import/dto/import-row.dto.ts (ImportRowDto + bucket types)
  - api-ventago/src/app/client-import/dto/import-batch.dto.ts (ImportBatchDto)
  - api-ventago/src/app/client-import/client-import.service.ts (importBatch method)
  - api-ventago/src/app/client-import/client-import.controller.ts (POST /clients/import)
  - api-ventago/src/app/client-import/client-import.module.ts (ClientImportModule)
  - app.module.ts 에 ClientImportModule 등록
affects:
  - Wave 5 frontend (Plan 25-14): CargaMasivaClientesView 가 /global-clients/massive-upload → /clients/import 로 교체
  - 운영 배포 시 admin/superadmin 권한이 manage-clientes-import slug 자동 backfill

tech-stack:
  patterns:
    - "Controller + Service + 2 DTO + Module 분리 — NestJS 표준 구조"
    - "JWT + FunctionGuard('manage-clientes-import', 'create') 통합 가드"
    - "class-validator + class-transformer (Type) — ValidateNested 로 nested DTO 자동 검증"

key-decisions:
  - "Controller path: /clients/import (구 /global-clients/massive-upload 와 분리 — 새 캐노니컬 endpoint)"
  - "Service: importBatch(batch, ctx) 단일 메서드 — chunked transaction 내장"
  - "DTO 두 개로 분리 — ImportRowDto (행 단위) + ImportBatchDto (전체 batch + 정책)"
  - "Module 의 forFeature 4개 모델: Clients, GlobalClient, StoreClient, ClientImport"

requirements-completed:
  - REQ-25-10
  - REQ-25-11
  - REQ-25-19

duration: 25min
completed: 2026-04-26
---

# Plan 25-10: ClientImport 모듈 + DTO + Controller 골격

`/clients/import` 엔드포인트가 ImportBatchDto 를 받아 service.importBatch 로 위임. JWT + FunctionGuard 보호.

## Files Created

| 파일 | 책임 |
|---|---|
| `dto/import-row.dto.ts` | 행 단위 DTO + bucket types (Global/Local/Skip) + override (skip/update/link) |
| `dto/import-batch.dto.ts` | 전체 batch DTO — fileName, missingDocPolicy, defaultExistingHitPolicy, rows[] |
| `client-import.service.ts` | importBatch 메서드 (Plan 25-11/12 에서 본체 채움) |
| `client-import.controller.ts` | POST /clients/import + 가드 적용 |
| `client-import.module.ts` | SequelizeModule.forFeature + provider/controller 등록 |

## Verified

- ✅ TypeScript 컴파일 (`tsc --noEmit`) 에러 0건
- ✅ ESLint (client-import 전체) 에러 0건

## Self-Check: PASSED

- [x] ImportRowDto, ImportBatchDto class-validator 적용
- [x] POST /clients/import endpoint 존재
- [x] @FunctionGuard('manage-clientes-import', 'create') 적용
- [x] ClientImportModule 4개 모델 등록
- [x] app.module.ts 에 등록

---
*Completed: 2026-04-26*
