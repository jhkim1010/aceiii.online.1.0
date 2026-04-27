# SPEC: Phase 25 Wave 2 (Plan 05 + Plan 06)
생성일: 2026-04-26

## 목표
OwnerScopeGuard 보안 가드 인프라를 도입하고, 기존 GlobalClient 컨트롤러를 그 가드로 보호한다. clientes masivo importación 권한 slug `manage-clientes-import` 도 함께 시드.

## 배경 및 컨텍스트

**Wave 1 완료 현황 (2026-04-26):**
- DB: stores/global_clients.owner_group_id, sales.store_client_id, 3 audit 테이블 모두 운영 적용 완료
- Sequelize: ClientImport, ClientMerge, ClientAccessAudit 모델 작성 완료
- 데이터: 4 stores=group1, global_clients 1 row (Consumidor Final), store_clients 4 rows

**Wave 2 책임:**
- Plan 05: OwnerScopeGuard + Decorator + Service + CommonModule + auth.service.ts /me 응답에 ownerGroupId 추가 + StoreService.create 자동 그룹 할당
- Plan 06: manage-clientes-import slug seed + GlobalClientsController 에 @OwnerScope 적용 + Service 의 모든 쿼리에 ownerGroupId 필터

**현재 코드베이스 핵심 사실:**
- GlobalClientsController 위치: `api-ventago/src/app/shared/global-clients/global-clients.controller.ts`
- GlobalClientsController 등록 모듈: `api-ventago/src/app/shared/shared.module.ts`
- 중복 모듈 (`app/global-clients/`): 사용되지 않으나 컴파일됨 — Wave 2 작업과 무관
- /me 응답은 `Store.findOne({ where: { id: user.storeId } })` 결과로 storeName/aliasName/logoUrl 만 추출 → ownerGroupId 추가 필요
- Functions seed 패턴: `Modules.findOne({ slug })` 후 `Functions.findOrCreate({ where: { name, moduleId }, defaults: { slug, ... } })`
- 기존 가드 패턴: `FunctionPermissionGuard` (function-permission.guard.ts) — Reflector + req.user.roles superadmin 바이패스
- 기존 데코레이터 패턴: `FunctionGuard(slug, action) = applyDecorators(SetMetadata, UseGuards(AuthGuard('jwt'), FunctionPermissionGuard))`

## 기술 스택
- Framework: NestJS 11 + TypeScript + Sequelize-typescript
- DB: PostgreSQL 운영 PG10 + dev PG15
- 새 의존성: 없음 (기존 NestJS / Sequelize / Passport 만 사용)
- 테스트: Jest

## 태스크 목록

### Plan 25-05 (OwnerScope 인프라)
- [ ] TASK-1: `api-ventago/src/app/common/services/owner-scope.service.ts` 생성 (in-memory 캐시 5분)
- [ ] TASK-2: `api-ventago/src/app/common/decorators/owner-scope.decorator.ts` 생성 (OWNER_SCOPE_KEY + @OwnerScope)
- [ ] TASK-3: `api-ventago/src/app/common/guards/owner-scope.guard.ts` 생성 (canActivate + audit.create on 403)
- [ ] TASK-4: `api-ventago/src/app/common/common.module.ts` 생성 (Sequelize forFeature + providers + exports)
- [ ] TASK-5: `app.module.ts` 에 CommonModule 등록
- [ ] TASK-6: `auth.service.ts` me() 응답에 ownerGroupId 추가 (Store.findOne attributes 추가)
- [ ] TASK-7: `store.service.ts` create() 에 owner_groups_seq nextval 자동 할당
- [ ] TASK-8: TypeScript 컴파일 검증 (tsc --noEmit)

### Plan 25-06 (CASL slug + GlobalClient 가드 적용)
- [ ] TASK-9: Modules 테이블에 'clientes' 슬러그 존재 확인 (없으면 추가하지 않고 sharedModule 위치 활용)
- [ ] TASK-10: Functions seed 에 'manage-clientes-import' 추가 (어떤 모듈 하위인지 결정)
- [ ] TASK-11: shared/global-clients/global-clients.controller.ts 에 @OwnerScope 적용 (findOne, update, setRisky)
- [ ] TASK-12: shared/global-clients/global-clients.service.ts 의 모든 쿼리에 ownerGroupId 필터 추가
- [ ] TASK-13: SharedModule 에 CommonModule import 추가
- [ ] TASK-14: TypeScript 컴파일 + 운영 영향 검토

### 검증 + 운영 영향
- [ ] TASK-15: SUMMARY 25-05/25-06 작성
- [ ] TASK-16: STATE.md 갱신

## 완료 기준
- TypeScript 컴파일 에러 0개
- /me 응답에 `ownerGroupId` 포함됨 (호스트에서 검증 권장)
- GlobalClientsController 의 단일 조회/수정 엔드포인트가 다른 ownerGroup 접근 시 403 반환
- ClientAccessAudit 테이블에 403 이벤트 INSERT
- 기존 4개 매장 모두 ownerGroupId=1 이므로 운영 영향 없음 (cross-group 접근 시도 자체가 발생 안 함)

## 금지사항 / 주의사항

**PostgreSQL Pool 안전:**
- OwnerScopeService 가 in-memory cache 사용 (5분 TTL) — DB 조회 최소화
- ClientAccessAudit.create 는 await 하되 트랜잭션 외부에서 호출 (1 row insert, light)
- 새 Pool 인스턴스 생성 절대 금지

**운영 영향 최소화:**
- @OwnerScope 데코레이터는 신규 endpoint 만 보호하지 않고 기존 GlobalClient endpoint 도 보호 → 모든 매장이 같은 ownerGroupId=1 이므로 실제 영향 없음
- 단, vendedor 가 PATCH /shared/global-clients/:id/risky 호출 시 기존 @Auth 와 새 @OwnerScope 가 모두 통과해야 함 → 기존 @Auth 데코레이터는 그대로 유지
- 프론트는 변경 없음 (API 동일)

**ESLint:**
- 새 파일 모두 `lines-around-comment`, `newline-before-return` 규칙 준수
- 한국어 주석, 영어 변수/함수명
- 모든 async 메서드 try/catch 또는 throw 명시

**컨테이너 영향:**
- sync: false 유지
- 새 모델 (Wave 1 의 ClientImport/Merge/AccessAudit) 은 컨테이너에 반영되어 있지 않음 — Wave 2 의 OwnerScopeGuard 가 ClientAccessAudit 에 INSERT 하려면 모델이 컨테이너에 등록되어야 함
- 따라서 Wave 2 완료 후에는 push-both.sh / 수동 배포 필요 (운영 적용 시)

## 운영 적용 전략
1. 코드 변경만 완료 → push-both.sh 로 배포 (Jenkins CI)
2. 배포 후 /me 응답에 ownerGroupId 확인
3. cross-group 시나리오는 dev 환경에서만 검증 가능 (운영은 모두 group=1)
