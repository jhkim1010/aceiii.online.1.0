---
phase: 05-data-import
plan: "01"
subsystem: api
tags: [nestjs, sequelize, postgresql, products, import, migration]

requires: []
provides:
  - "Product 모델에 storeId FK 추가 + UNIQUE(sku, store_id) 제약"
  - "POST /import/migrate 엔드포인트 (admin/superadmin 전용)"
  - "extract-legacy-data.sql 추출 쿼리"
  - "운영 서버 마이그레이션 스크립트 (add-store-id-to-products.sh)"
affects:
  - "05-02: 추출 스크립트 테스트 + API 통합 테스트"
  - "05-03: 프론트엔드 임포트 UI"

tech-stack:
  added: []
  patterns:
    - "Product storeId 격리 — 매장별 SKU 유니크 제약"
    - "findOrCreate 패턴으로 참조 데이터 중복 방지"
    - "트랜잭션 기반 임포트 (실패 시 전체 롤백)"

key-files:
  created:
    - api-ventago/src/app/import/import.module.ts
    - api-ventago/src/app/import/import.controller.ts
    - api-ventago/src/app/import/import.service.ts
    - api-ventago/src/app/import/dto/import-migrate.dto.ts
    - api-ventago/migrations/extract-legacy-data.sql
    - api-ventago/migrations/add-store-id-to-products.sh
  modified:
    - api-ventago/src/app/products/products.model.ts
    - api-ventago/src/app/products/products.service.ts
    - api-ventago/src/app.module.ts

key-decisions:
  - "Product에 storeId 추가 (방법 C) — 매장 간 SKU 충돌 방지"
  - "임포트 시 storeId는 JWT user.storeId에서 자동 주입"
  - "findOrCreate로 Category/Color/Size 중복 방지"

requirements-completed:
  - FEAT-04

duration: 45min
completed: 2026-04-06
---

# Phase 05 Plan 01: Product storeId + Import Backend API Summary

## Accomplishments

- Product 모델에 storeId FK 추가 + UNIQUE(sku, store_id) 제약
- findAll, findFiltered, findGenericProduct에 storeId 필터 추가
- SKU 중복 체크에 storeId 범위 적용
- 운영 서버 마이그레이션 완료 (30개 상품 store_id 할당)
- ImportModule/Controller/Service 생성 (POST /import/migrate)
- 트랜잭션 기반 임포트 (실패 시 전체 롤백)
- extract-legacy-data.sql 추출 쿼리 작성

## Files Created/Modified

- `api-ventago/src/app/import/*` — Import 모듈 전체
- `api-ventago/src/app/products/products.model.ts` — storeId 추가
- `api-ventago/src/app/products/products.service.ts` — storeId 필터
- `api-ventago/src/app.module.ts` — ImportModule 등록
- `api-ventago/migrations/*` — 마이그레이션 + 추출 스크립트

## Issues Encountered

- 운영 서버에 store id=1이 없어서 기본값 할당 실패 → id=6(coolsistema)으로 변경

---
*Phase: 05-data-import*
*Completed: 2026-04-06*
