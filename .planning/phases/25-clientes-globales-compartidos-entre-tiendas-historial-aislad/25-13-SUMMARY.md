---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 13
subsystem: client-import
tags: [build, eslint, integration, wave-4-close]

requires:
  - 25-10 (모듈 골격)
  - 25-11 (bucket 로직)
  - 25-12 (audit + error report)

duration: 5min
completed: 2026-04-26
---

# Plan 25-13: Wave 4 마무리 + 빌드 검증

## Verified

- ✅ TypeScript 컴파일 (`tsc --noEmit`) 에러 0
- ✅ ESLint (`src/app/client-import/`) 에러 0
- ✅ NestJS app.module.ts 에 ClientImportModule 등록 확인
- ✅ Wave 1-3 의존성 모두 충족 (모델/가드/validators/seed)

## API Contract (호스트 push 후 사용 가능)

**POST /clients/import**

Headers:
- `Authorization: Bearer <jwt>`

Body (ImportBatchDto):
```json
{
  "fileName": "clientes_2026.xlsx",
  "missingDocPolicy": "local",
  "defaultExistingHitPolicy": "skip",
  "rows": [
    {
      "document": "20111111112",
      "fullname": "Juan Pérez",
      "email": "juan@ejemplo.com",
      "phone": "1141112222",
      "address": "Av. Corrientes 1234",
      "provinceId": 2
    }
    // ... up to 50000 rows
  ]
}
```

Response (ImportResponse):
```json
{
  "clientImportId": 17,
  "totalRows": 1500,
  "createdCount": 1400,
  "updatedCount": 50,
  "skippedCount": 30,
  "errorCount": 20,
  "errors": [
    { "rowIndex": 13, "errorCode": "EMPTY_FULLNAME", "errorMessage": "fullname 비어있음" },
    { "rowIndex": 27, "errorCode": "GLOBAL_UPSERT_FAILED", "errorMessage": "...", "document": "..." }
  ]
}
```

Errors:
- `400` — empty rows / too many rows / no ownerGroupId
- `403` — manage-clientes-import 권한 없음 (vendedor)
- `401` — JWT 만료/없음

## Wave 5 연결 점검

프론트(`CargaMasivaClientesView`) 가 다음과 같이 변경되어야 함 (Wave 5 / Plan 25-14):

```typescript
// 현재 (구 모듈)
const result = await apiConnector.post('/global-clients/massive-upload', { clients: chunk })

// Wave 5 변경
const result = await apiConnector.post('/clients/import', {
  fileName: file.name,
  missingDocPolicy: 'local',
  defaultExistingHitPolicy: 'skip',
  rows: chunk.map(c => ({ ...c, bucket: undefined /* 자동 분류 */ })),
})
```

## Self-Check: PASSED

- [x] 모든 Wave 4 plan 파일 SUMMARY 작성 (25-10, 25-11, 25-12, 25-13)
- [x] tsc 컴파일 에러 0
- [x] ESLint client-import 깨끗
- [x] STATE.md 갱신 예정

---
*Completed: 2026-04-26*
