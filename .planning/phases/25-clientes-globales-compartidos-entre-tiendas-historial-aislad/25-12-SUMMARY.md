---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 12
subsystem: client-import
tags: [audit, error-report, response, client-import-table]

requires:
  - 25-04 (client_imports table)
  - 25-11 (ClientImportService.importBatch 본체)
provides:
  - per-row error 수집 (ImportRowError 타입)
  - ClientImport audit row 트랜잭션 내 INSERT
  - ImportResponse shape (clientImportId + counts + errors[])

tech-stack:
  patterns:
    - "Per-row error 수집 + 트랜잭션 외부에 노출 — 행별 진단 정보 보존"
    - "errorCode enum: EMPTY_FULLNAME / GLOBAL_UPSERT_FAILED / LOCAL_INSERT_FAILED"
    - "ClientImport.create — 모든 행 처리 후 audit 1행 INSERT (트랜잭션 내)"
    - "트랜잭션 rollback 시 audit 도 함께 되돌림 (atomicity 보장)"

key-decisions:
  - "에러는 트랜잭션 rollback 트리거하지 않음 — 일부 행 에러도 batch 는 성공 (per-row 격리)"
  - "에러 행도 totalRows 에 포함 (audit 정확도)"
  - "errorCount = errors.length (계산은 audit insert 시점)"
  - "executedAt = new Date() — Sequelize defaultValue 보다 명시적 (트랜잭션 시간 기록)"

requirements-completed:
  - REQ-25-16
  - REQ-25-17
  - REQ-25-18
  - REQ-25-21
  - D4-06

duration: 15min
completed: 2026-04-26
---

# Plan 25-12: Per-row Error Report + ClientImport Audit

배치 처리 결과를 ClientImport 테이블에 audit 1행으로 기록. 행 단위 에러는 별도 errors 배열로 응답.

## ImportResponse Shape

```typescript
interface ImportResponse {
  clientImportId: number;        // ClientImport audit row id
  totalRows: number;             // 입력된 모든 rows 수
  createdCount: number;          // 신규 생성 (Global+Local 합계)
  updatedCount: number;          // Global update + link 합계
  skippedCount: number;          // 명시적 Skip + skip policy 적용
  errorCount: number;            // 처리 중 실패한 행 수
  errors: ImportRowError[];      // 실패한 행별 진단
}

interface ImportRowError {
  rowIndex: number;              // 0-based
  errorCode: string;             // EMPTY_FULLNAME | GLOBAL_UPSERT_FAILED | LOCAL_INSERT_FAILED
  errorMessage: string;
  document?: string | null;
  fullname?: string | null;
}
```

## Audit Row 매핑

ClientImport 테이블에 1 batch = 1 row:
- userId: caller (FK users)
- storeId: caller (FK stores)
- fileName: 사용자 업로드 파일명
- totalRows / createdCount / updatedCount / skippedCount / errorCount
- executedAt: 명시적 new Date()
- missingDocPolicy: 'local' | 'skip'

## Verified

- ✅ TypeScript 컴파일
- ✅ ESLint 깨끗

## Self-Check: PASSED

- [x] ImportRowError 타입 정의
- [x] ImportResponse 타입 정의 + export
- [x] ClientImport.create 트랜잭션 내 호출
- [x] errors[] 배열 응답에 포함
- [x] errorCount 계산 정확

---
*Completed: 2026-04-26*
