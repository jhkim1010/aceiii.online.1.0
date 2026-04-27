# SPEC: Phase 25 Wave 3 (Plan 25-07 + 25-08 + 25-09)
생성일: 2026-04-26

## 목표
clientes legacy → global 승격(promote) 흐름 백엔드 완성. Wave 3 핵심 기능:
1. **Plan 25-09**: AR DNI / CUIT (mod 11 + AFIP Pitfall 5) validator 분리 모듈
2. **Plan 25-07**: ClientsService.promote(legacyClientId, ctx) — 검증 + 충돌 감지 + atomic transaction
3. **Plan 25-08**: ClientsService.merge(payload, ctx) — opt-lock + field-pick 적용 + audit + remap

## 배경 및 컨텍스트

**Wave 1+2 완료 (2026-04-26):**
- DB 스키마 + audit 테이블 운영 적용 완료
- OwnerScopeGuard + GlobalClientsController @OwnerScope 적용
- ClientImport / ClientMerge / ClientAccessAudit Sequelize 모델 존재

**현재 ClientsService 상태 (`api-ventago/src/app/clients/clients.service.ts`):**
- `extends CrudService<Clients>` 상속 — generic CRUD 베이스
- 기존 메서드: findAllByStore, create, findAllQuerys, findSalesWithClientData
- 신규 추가 필요: promote, merge

**현재 ClientsModule:**
- SequelizeModule.forFeature([Clients]) 만 등록 → 추가 필요: GlobalClient, StoreClient, Sale, ClientMerge

**Wave 3 변경 범위 외:**
- Frontend MergeResolutionDialog (Plan 25-14)
- ClientImport 모듈 (Plan 25-10~13)

## 기술 스택
- NestJS 11 + TypeScript + Sequelize-typescript
- DB: PostgreSQL — atomic transaction 사용 (sequelize.transaction)
- 테스트 검증: tsc --noEmit (jest 단위 테스트는 호스트에서)

## 태스크 목록

### Plan 25-09 (Validators — 먼저 작성)
- [ ] TASK-1: `validators/cuit.validator.ts` (isValidCuit + normalizeCuit, AFIP Pitfall 5)
- [ ] TASK-2: `validators/dni.validator.ts` (isValidDni + normalizeDni, 7-8 자리)
- [ ] TASK-3: `validators/cuit.validator.spec.ts` 작성 (테스트는 호스트 실행)
- [ ] TASK-4: `validators/dni.validator.spec.ts` 작성 (테스트는 호스트 실행)

### Plan 25-07 (Promote Service)
- [ ] TASK-5: `clients.module.ts` 에 GlobalClient, StoreClient, Sale, ClientMerge 모델 추가
- [ ] TASK-6: `clients.service.ts` constructor 확장 + promote 메서드 추가 (validators import)
- [ ] TASK-7: `clients.controller.ts` 에 POST /clients/:id/promote 엔드포인트
- [ ] TASK-8: `clients-promote.service.spec.ts` (호스트 실행)

### Plan 25-08 (Merge Service)
- [ ] TASK-9: `clients.service.ts` 에 merge 메서드 추가 (opt-lock + audit)
- [ ] TASK-10: `clients.controller.ts` 에 POST /clients/merge 엔드포인트
- [ ] TASK-11: `clients-merge.service.spec.ts` (호스트 실행)

### 검증 + 문서
- [ ] TASK-12: TypeScript 컴파일 (`tsc --noEmit`) 에러 0
- [ ] TASK-13: ESLint (Phase 25 영역 단독) 에러 0
- [ ] TASK-14: 25-07-SUMMARY, 25-08-SUMMARY, 25-09-SUMMARY 작성
- [ ] TASK-15: STATE.md 갱신 (52 → 55 plans)

## 완료 기준
- TypeScript 컴파일 에러 0
- 신규 파일 ESLint 에러 0
- POST /clients/:id/promote, POST /clients/merge 엔드포인트 존재
- 충돌 시 409 / merge_required 응답
- D1-04 demotion 차단 (document 가 fieldPicks 에 들어오면 BadRequestException)
- D1-06 옵티미스틱 락 (winnerUpdatedAt mismatch 시 ConflictException 'STALE_MERGE')

## 금지사항 / 주의사항

**PostgreSQL Pool 안전:**
- promote/merge 모두 sequelize.transaction 1회 사용 — 새 Pool 인스턴스 생성 금지
- catch 블록에서 반드시 transaction.rollback() 호출
- pool.connect() 직접 사용 금지 (Sequelize 가 알아서 관리)

**원자성:**
- promote 트랜잭션: GlobalClient.create + StoreClient.create + sales.update — 셋 중 하나라도 실패하면 전체 롤백
- merge 트랜잭션: winner.update + StoreClient.findOrCreate + sales.update + ClientMerge.create — 마찬가지

**보안:**
- promote: caller storeId 로 legacy client 조회 (cross-store 차단)
- merge: caller ownerGroupId 로 winner 조회 (cross-group 차단)
- merge fieldPicks: 'document' 키 명시적 거부 (D1-04)
- merge fieldPicks: whitelist 외 키 거부

**호환성:**
- 기존 ClientsService.create / update / findAllByStore 등은 그대로 유지
- CrudService 상속 유지 — 새 method 만 추가
- 컨테이너는 sync: false 라 모델 추가가 ALTER 트리거 안 함

**ESLint:**
- 새 파일 모두 lines-around-comment, newline-before-return 준수
- 한국어 주석, 영어 변수/함수명
- 모든 async 메서드 try/catch 또는 명시적 throw
