# SPEC: Phase 25 Wave 4 (Plan 25-10 → 13)
생성일: 2026-04-26

## 목표
client-import 모듈 신규 구축 — `POST /clients/import` 엔드포인트로 CSV/Excel 일괄 업로드를 처리.
프론트(`CargaMasivaClientesView`)가 백엔드와 실제 통신해서 동작 가능 상태로 만든다.

## 배경
- 프론트는 이미 CSV/Excel 파싱 + 컬럼 매핑 UI 완성
- 현재 프론트는 `/global-clients/massive-upload`(구 모듈) 호출 — Wave 5에서 `/clients/import`로 교체 예정
- Wave 1-3 인프라 모두 사용 가능: ClientImport audit 모델, OwnerScopeGuard, validators

## 태스크 목록

### Plan 25-10 (모듈 + DTO + 기본 service)
- [ ] TASK-1: `dto/import-row.dto.ts` (class-validator) — bucket Global/Local/Skip
- [ ] TASK-2: `dto/import-batch.dto.ts` — fileName, missingDocPolicy, rows[]
- [ ] TASK-3: `client-import.service.ts` — importBatch (chunked transaction)
- [ ] TASK-4: `client-import.controller.ts` — POST /clients/import (FunctionGuard manage-clientes-import)
- [ ] TASK-5: `client-import.module.ts` 등록 + app.module.ts 등록

### Plan 25-11 (bucket 분류 + upsert 로직)
- [ ] TASK-6: ImportRow → bucket 분류 (document 유효성 + missingDocPolicy)
- [ ] TASK-7: Global bucket: findAll IN(...) → upsert + StoreClient findOrCreate
- [ ] TASK-8: Local bucket: legacy clients 에 bulkCreate
- [ ] TASK-9: Skip bucket: count 만 (no DB write)

### Plan 25-12 (per-row error report + audit)
- [ ] TASK-10: rowIndex 별 error 수집 (errorCode + errorMessage)
- [ ] TASK-11: ClientImport.create audit 1행 (트랜잭션 종료 후)
- [ ] TASK-12: response shape (totalRows / created / updated / skipped / errorCount / errors[])

### Plan 25-13 (마무리)
- [ ] TASK-13: TypeScript 컴파일 + ESLint
- [ ] TASK-14: 25-10/11/12/13 SUMMARY 작성
- [ ] TASK-15: STATE.md 갱신 (55→59 plans)

## 완료 기준
- POST /clients/import 엔드포인트 존재 + JWT/FunctionGuard 보호
- chunkSize=500 트랜잭션 처리
- Global/Local/Skip bucket 라우팅
- per-row 에러 수집
- ClientImport audit row 생성
- TypeScript 컴파일 에러 0
- 호스트 nest build 성공

## 금지사항
- pool 새 인스턴스 생성 금지 — sequelize.transaction 1회만
- 트랜잭션 외부 INSERT/UPDATE 금지
- 기존 `/global-clients/massive-upload` 엔드포인트 건드리지 않음 (프론트 호환 유지, Wave 5에서 교체)
- 새 의존성 추가 금지 (papaparse/xlsx는 프론트만)
