---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 11
subsystem: client-import
tags: [bucket, classify, upsert, transaction, chunked, atomic]

requires:
  - 25-10 (ClientImport 모듈/DTO 골격)
  - 25-09 (validators)
provides:
  - ClientImportService.importBatch — bucket 분류 + chunked transaction + Global/Local/Skip 라우팅
  - 행 단위 bucket 자동 분류 (document validity + missingDocPolicy)
  - Global bucket: findAll IN(...) → upsert + StoreClient findOrCreate
  - Local bucket: legacy clients bulkCreate (storeId 격리)
  - Skip bucket: count only

tech-stack:
  patterns:
    - "Chunked transaction (CHUNK_SIZE=500): 한 트랜잭션 내에서 chunk 마다 일괄 조회 + 분기 INSERT/UPDATE"
    - "findAll IN(...) → existingMap: 충돌 행 1회 조회로 N개 검사 (n+1 회피)"
    - "StoreClient.findOrCreate: 캐시된 globalClient + caller storeId 매핑 — idempotent"
    - "bulkCreate Local + ignoreDuplicates: legacy clients 빠른 INSERT, 중복 건 silently skip"
    - "MAX_ROWS=50000 제한 — 단일 batch 너무 커지면 BadRequest"
    - "in-memory existingMap 갱신: 같은 batch 안에서 신규 created 도 캐시에 추가 (동일 doc 중복 방지)"

key-decisions:
  - "Default existing-hit policy = 'skip' — 가장 보수적. 사용자가 update/link 명시해야 변경됨"
  - "row.bucket 우선 → 자동 분류 fallback. 프론트가 미리 분류해서 보내도 OK"
  - "fullname 비어있으면 강제 Skip + EMPTY_FULLNAME 에러 (필수 필드 검증)"
  - "bulkCreate 실패 시 행마다 개별 INSERT fallback — 어느 행이 실패했는지 식별 가능"
  - "Local note → store_clients.note (Global 케이스), legacy clients.note (Local 케이스)"

requirements-completed:
  - REQ-25-13
  - REQ-25-15
  - D4-04
  - D4-05

duration: 30min
completed: 2026-04-26
---

# Plan 25-11: Bucket 분류 + Upsert 로직

`importBatch` 본체 구현. 행마다 bucket(Global/Local/Skip) 자동 분류 후 chunked transaction 으로 처리.

## 핵심 로직 (importBatch 흐름)

1. **검증**: ownerGroupId 필수, totalRows 1~50000 제한
2. **chunkSize=500 loop**: rows 를 500개씩 슬라이싱
3. **classify (chunk-local)**: 행마다 normalizedDoc + bucket 결정
   - row.bucket 우선
   - 자동 분류: valid DNI/CUIT → Global, 없으면 missingDocPolicy 따라
   - fullname 비어있으면 강제 Skip + 에러 추가
4. **Global bucket 처리**:
   - chunk 내 모든 normalizedDoc 모아 findAll IN(...) 1회 조회
   - existingMap 으로 충돌 행 분기 (skip/update/link)
   - skip → skippedCount++
   - update → buildNonEmptyPatch 로 빈 값 보호 + winner.update + StoreClient.findOrCreate
   - link → StoreClient.findOrCreate 만 (winner 보존)
   - 신규 → GlobalClient.create + StoreClient.create + existingMap 캐시 추가
5. **Local bucket 처리**: clients.bulkCreate (실패 시 개별 INSERT fallback)
6. **Skip bucket 처리**: skippedCount += skipRows.length (no DB write)
7. **에러 수집**: rowIndex + errorCode + errorMessage + document/fullname

## Verified

- ✅ TypeScript 컴파일 통과
- ✅ ESLint 깨끗
- ⏳ 호스트 jest 단위 테스트는 별도 작성 필요 (Wave 5 통합 테스트로 대체 가능)

## Self-Check: PASSED

- [x] CHUNK_SIZE=500 + MAX_ROWS=50000 상수
- [x] classifyRow 자동 분류 + missingDocPolicy 분기
- [x] Global bucket: findAll IN + existingMap + 3가지 정책
- [x] Local bucket: bulkCreate + 개별 fallback
- [x] Skip bucket: count 만
- [x] in-memory existingMap 캐시 갱신 (같은 batch 동일 doc 처리)

---
*Completed: 2026-04-26*
