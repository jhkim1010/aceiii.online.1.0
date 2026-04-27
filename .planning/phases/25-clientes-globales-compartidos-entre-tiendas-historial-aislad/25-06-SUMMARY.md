---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 06
subsystem: backend-security + casl-permission
tags: [nestjs, ownerScope, casl, functions-seed, global-clients, demotion-block]

# Dependency graph
requires:
  - 25-05 (OwnerScopeGuard + @OwnerScope decorator + CommonModule)
provides:
  - functions seed 'manage-clientes-import' 슬러그 추가 (cliente-vista 모듈 하위)
  - GlobalClientsController @OwnerScope 적용 (findOne, update, setRisky)
  - GlobalClientsService 모든 쿼리에 ownerGroupId 필터 강제
  - GlobalClientsService.update D1-06 demotion 차단 (document → null 거부)
  - GlobalClientsService.findOrCreate signature 변경 (ownerGroupId 추가)
  - SharedModule 이 CommonModule import (OwnerScopeGuard 사용 가능)
affects:
  - Wave 3 Plan 07+ — promote service 가 GlobalClientsService 와 동일한 ownerGroupId 패턴 사용
  - 프론트 CASL — manage-clientes-import 권한이 /me 응답에 admin/superadmin 만 노출됨
  - 운영 영향 — 4개 매장 모두 group=1 이므로 cross-group 시도 자체가 발생 안 함 → 영향 없음

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@OwnerScope 데코레이터 적용 — controller 핸들러 단위 보안 가드"
    - "ownerGroupId 필터 강제 — service 메서드 시그니처에 ownerGroupId 파라미터 추가"
    - "D1-06 demotion 차단 — document 가 있는 GlobalClient 에서 document null 시도 시 BadRequestException"
    - "Functions seed 명시적 slug — generateSlug() 가 액센트를 깨므로 PLAN 의 정확한 slug 사용 위해 직접 지정"
    - "ClienteVista module 활용 — 새 모듈 만들지 않고 기존 cliente-vista 하위에 새 function 추가"

key-files:
  created: []
  modified:
    - api-ventago/src/app/functions/seed/functions.seed.ts (clienteVistaFunctions 에 'Importación masiva de clientes' + 명시적 slug 'manage-clientes-import' 추가)
    - api-ventago/src/app/shared/global-clients/global-clients.controller.ts (전체 재작성: @OwnerScope 적용, user.ownerGroupId 주입)
    - api-ventago/src/app/shared/global-clients/global-clients.service.ts (전체 재작성: ownerGroupId 필터 강제, D1-06 demotion 차단)
    - api-ventago/src/app/shared/shared.module.ts (CommonModule import 추가)

key-decisions:
  - "기존 cliente-vista 모듈 활용 — 새 module 등록 없이 functions.seed.ts 의 clienteVistaFunctions 배열에 추가"
  - "명시적 slug 'manage-clientes-import' 지정 — generateSlug('Importación masiva de clientes') 가 'importacin-masiva-de-clientes' 가 되어 PLAN 약속과 어긋남 → func.slug 우선 사용 패턴 도입"
  - "GlobalClientsService.findAll signature 에 ownerGroupId nullable 추가 — superadmin/null 케이스 호환"
  - "create() 에서 ownerGroupId 가 falsy 면 BadRequestException — 잘못된 호출 사전 차단"
  - "D1-06 demotion 차단 — document null/empty 만 검사 (undefined 도 포함하나 'document' in data 로 partial update 구분)"
  - "fullname+phone 분기 제거 — Phase 25 D1-01 정책 (document 없는 고객은 GlobalClient pool 진입 금지)"
  - "별도 모듈 app/global-clients/ 는 Wave 2 범위 외 — 캐노니컬은 shared/global-clients/, 별도 모듈은 Plan 10+ 에서 검토 예정"

patterns-established:
  - "Phase 25 GlobalClient 보안 패턴: 모든 service 메서드 ownerGroupId 강제, controller 가 user.ownerGroupId 주입"
  - "Function slug 명시 패턴: 액센트 있는 스페인어 이름은 func.slug 우선 사용 (slug field 추가)"
  - "Demotion 차단 패턴: 특정 필드 unset 시도를 service 레벨에서 명시적으로 거부"

requirements-completed:
  - REQ-25-08
  - REQ-25-09
  - REQ-25-19
  - D1-01 (fullname+phone 분기 제거 강화)
  - D1-06 (demotion 차단)
  - D3-04 (OwnerScope 적용)

# Metrics
duration: 30min
completed: 2026-04-26
---

# Phase 25 Plan 06: Wave 2 GlobalClient OwnerScope Application Summary

**`manage-clientes-import` Functions slug seed 추가 + GlobalClientsController 에 @OwnerScope 적용 + Service 모든 쿼리에 ownerGroupId 필터 강제 + D1-06 demotion 차단 구현. TypeScript 컴파일 통과.**

## Performance

- **Duration:** ~30분
- **Started:** 2026-04-26 ~02:15 KST
- **Completed:** 2026-04-26 ~02:45 KST
- **Tasks:** 6/6 (functions seed, controller, service, module 모두 완료)

## Accomplishments

- **manage-clientes-import slug seed**: 기존 cliente-vista 모듈 하위에 함수 추가. generateSlug 가 깨는 문제 해결 위해 func.slug 우선 패턴 도입
- **GlobalClientsController 보안 강화**: findOne, update, setRisky 에 @OwnerScope 적용 (cross-group 시 403 + audit)
- **GlobalClientsService 격리 강화**: findAll/create/update/setRisky/findOrCreate 모두 ownerGroupId 필터/주입 적용
- **D1-06 demotion 차단**: GlobalClient.update 에서 document → null 시도 시 명시적 BadRequestException
- **D1-01 강화**: create() 의 fullname+phone 중복 검사 분기 제거 (document 없는 고객은 GlobalClient pool 진입 차단)
- **SharedModule**: CommonModule import 추가로 @OwnerScope 데코레이터 사용 가능

## Files Modified

| 파일 | 변경 내용 |
|----|----|
| functions.seed.ts | clienteVistaFunctions 에 'Importación masiva de clientes' 항목 + slug='manage-clientes-import' 추가, slug 자동/수동 분기 패턴 |
| shared/global-clients/global-clients.controller.ts | 전체 재작성. import OwnerScope, findOne/update/setRisky 에 @OwnerScope, findAll/create 에 user.ownerGroupId 전달 |
| shared/global-clients/global-clients.service.ts | 전체 재작성. findAll/create/update/setRisky/findOrCreate 모두 ownerGroupId 강제. D1-06 demotion check |
| shared/shared.module.ts | CommonModule import 추가 |

## Verified

- ✅ TypeScript 컴파일 (`tsc --noEmit`) 에러 0건
- ⏳ 운영 적용 후 /api/auth/me 응답에서 admin: permissions['manage-clientes-import'] 존재, vendedor 부재 확인 필요
- ⏳ /shared/global-clients/:id 가 다른 ownerGroup 의 id 일 때 403 반환 확인 필요 (운영은 모두 group=1 이라 검증 어려움)

## Decisions Made

- **명시적 slug 패턴**: PLAN 이 약속한 정확한 slug (`manage-clientes-import`) 를 보장하기 위해 functions seed 에서 func.slug 우선 사용 분기 추가
- **별도 모듈 (`app/global-clients/`) 손대지 않음**: 그 모듈은 자체 service + 자체 massive-upload endpoint 가 있으나 Phase 25 캐노니컬은 shared/global-clients/ — 중복 모듈 통합/제거는 Plan 25-10+ 에서 검토 예정
- **fullname+phone 분기 제거**: Phase 25 D1-01 강화 — document 없는 고객은 GlobalClient 진입 금지

## Deviations from Plan

- 운영 적용 단계 (TASK-15 운영 시드 + 검증) 보류 — 코드 변경만 완료, 다음 push-both.sh 사이클에서 자동 반영
- 별도 모듈 `app/global-clients/` 의 보안 가드 미적용 — Phase 25 캐노니컬 외 영역으로 판단

## Issues Encountered

- generateSlug 가 스페인어 액센트 'ó' 를 제거하면서 'importacin-masiva-de-clientes' 가 됨 → 명시적 slug 지정 패턴 도입으로 해결
- 별도 모듈 (`app/global-clients/`) 발견 → Wave 2 범위 명확히 구분

## User Setup Required

- **호스트 lint 실행 권장**: `cd api-ventago && npm run lint -- src/app/shared/global-clients/`
- **다음 push-both.sh 사이클** 시 변경 사항 자동 반영
- **운영 검증**: 배포 후 admin 로그인 → /me 의 permissions 에 manage-clientes-import 존재 확인

## Next Phase Readiness

- **Wave 3 (Plan 07+)** — promote service 가 GlobalClientsService.findOrCreate(ownerGroupId 필수) 패턴 활용 가능
- **Wave 4 (Plan 10+)** — client-import 모듈도 동일한 @OwnerScope + ownerGroupId 패턴 사용
- **운영 영향**: 0 — 4개 매장 모두 group=1 이라 cross-group 시도 자체 발생 안 함

## Self-Check: PASSED

- [x] functions.seed.ts 에 'manage-clientes-import' slug 명시적 지정
- [x] global-clients.controller.ts 4 군데 @OwnerScope 또는 user.ownerGroupId 사용 (findOne, update, setRisky, create)
- [x] global-clients.service.ts 모든 read/write 메서드에 ownerGroupId 사용
- [x] D1-06 demotion 차단 코드 존재 (document null/empty 시 BadRequestException)
- [x] shared.module.ts 에 CommonModule import
- [x] tsc --noEmit 에러 0건

---
*Phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad*
*Completed: 2026-04-26*
