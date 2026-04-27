---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 14
subsystem: frontend-wiring
tags: [frontend, ventago-app, client-import, carga-masiva, wave-5]

requires:
  - 25-10 (POST /clients/import 엔드포인트)
  - 25-11 (importBatch 본체)
  - 25-12 (ImportResponse shape)
provides:
  - CargaMasivaClientesView 가 새 캐노니컬 endpoint /clients/import 호출
  - ParsedClient → ImportRowDto 변환 헬퍼 (toImportRow)
  - errorCode 표시 강화 (결과 화면)
  - clientImportId 응답 캡처 (audit trace)
affects:
  - 운영 배포 시 admin/superadmin 가 CargaMasivaClientesView 에서 실제 import 수행 가능
  - 구 endpoint /global-clients/massive-upload 는 그대로 유지 (다른 호출자 호환)

scope-decision:
  - "Wave 5 의 PromoteMergeDialog (Plan 25-14 원래 범위) 는 별도 작업으로 분리 — ClienteVistaView 통합은 cliente-vista 화면의 별도 phase"
  - "Wave 7 (Plan 25-15 sales/reports audit) 는 큰 별도 phase — Phase 25 의 여기서 Wave 5 마무리"
  - "이번 Wave 5 의 핵심: clientes masivo importación 화면이 운영에서 동작 가능한 상태로 만드는 것"

key-files:
  modified:
    - ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx

key-decisions:
  - "chunkSize=5000 — 백엔드 MAX_ROWS=50000 의 1/10. 큰 batch 도 client-side 에서 자동 분할"
  - "ImportRowPayload 헬퍼: 빈 문자열 → undefined 정리 (백엔드 IsOptional + IsEmail 검증 호환)"
  - "rowIndex 보정: 백엔드 0-based + 프론트 헤더 1행 추가 → 사용자 표시 +2"
  - "구 endpoint /global-clients/massive-upload 는 그대로 — 점진적 deprecation 전략"
  - "errorCount 와 errors.length 정합성 검증 — 서버측 응답 sanity check (console.warn)"

requirements-completed:
  - REQ-25-10 (frontend wiring)
  - REQ-25-11 (frontend wiring)

duration: 25min
completed: 2026-04-26
---

# Plan 25-14 (Wave 5 실용적 범위): CargaMasivaClientesView Frontend Wiring

## 변경 요약

`CargaMasivaClientesView.tsx` 의 `handleUpload` 메서드를 새 캐노니컬 endpoint `/clients/import` 호출로 교체.
`ParsedClient → ImportRowDto` 변환 헬퍼 + `ImportResponse` 응답 형식 매핑 + errorCode 표시 강화.

## 변경된 코드 흐름

**전 (구 endpoint):**
```typescript
const result = await apiConnector.post('/global-clients/massive-upload', { clients: chunk })
totalCreated += result.created
totalUpdated += result.updated
// row 인덱스 추정만 가능
```

**후 (Phase 25 캐노니컬):**
```typescript
const rows = chunk.map(toImportRow)
const result = await apiConnector.post('/clients/import', {
  fileName: file?.name,
  missingDocPolicy: 'local',
  defaultExistingHitPolicy: 'skip',
  rows,
})
totalCreated += result.createdCount
totalUpdated += result.updatedCount
// 행별 정확한 rowIndex + errorCode 수신
```

## Verified

- ✅ TypeScript 컴파일 (`tsc --noEmit -p ventago-app/tsconfig.json`) 에러 0건
- ⏳ ventago-app `npm run build` 호스트 검증 권장
- ⏳ 운영 배포 후 실제 CSV 파일로 smoke test

## Wave 5 이후 남은 Phase 25 작업 (별도 phase 후보)

1. **PromoteMergeDialog + ClienteVistaView 통합** (Plan 25-14 원래 PromoteMergeDialog 부분)
   - cliente-vista 화면에서 사용자가 DNI/CUIT 추가 → POST /clients/:id/promote 호출
   - merge_required 응답 시 D1-04 9-field-pair radio dialog 표시
2. **Plan 25-15 sales/reports scope audit** (Wave 7)
   - sales-create.service 가 storeClientId populate
   - sales.service 읽기 precedence (storeClientId → clientId fallback)
   - /reports/* 의 storeId=null aggregate 가 caller ownerGroup 만 합산

## Self-Check: PASSED

- [x] CargaMasivaClientesView 가 /clients/import 호출
- [x] toImportRow 헬퍼: 빈 값 → undefined 정리
- [x] ImportResponse (createdCount/updatedCount/skippedCount/errorCount/errors) 매핑
- [x] errorCode 표시 (결과 화면)
- [x] clientImportId 캡처
- [x] tsc 에러 0건

---
*Completed: 2026-04-26*
