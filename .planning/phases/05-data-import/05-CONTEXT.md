# Phase 5: 레거시 데이터 임포트 - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

기존 POS 시스템(PostgreSQL: todocodigos, codigos, tipos, color 테이블)의 상품 데이터를 Ventago로 임포트하는 기능.
JSON 파일 기반 업로드 → 백엔드 트랜잭션 처리 → 매장별 격리.

</domain>

<decisions>
## Implementation Decisions

### 데이터 매핑
- **D-01:** todocodigos → Product (isParent=true), codigos → Product variant (parentId 연결)
- **D-02:** tipos → Category, color → Color, str_talle 문자열 → Size (findOrCreate)
- **D-03:** tpre1 → price, tpre2~5 → 별도 가격 유형 (향후 Price 모델 연동)
- **D-04:** tcodigo → sku, codigo → sku (매장별 unique)

### 매장 격리
- **D-05:** Product 모델에 storeId 추가 완료. UNIQUE(sku, store_id) 제약 적용
- **D-06:** 임포트 시 storeId는 JWT 토큰의 user.storeId에서 자동 주입. 프론트에서 전송하지 않음
- **D-07:** Category, Color, Size도 storeId로 격리 (기존 unique 제약: name + store_id)

### 임포트 방식
- **D-08:** JSON 파일 업로드 방식 (Excel은 향후 확장 가능)
- **D-09:** 단일 엔드포인트 POST /import/migrate에 전체 데이터 전송
- **D-10:** 트랜잭션 기반 — 실패 시 전체 롤백
- **D-11:** legacyId 매핑으로 부모-자식 관계 유지

### 추출
- **D-12:** 기존 DB에서 SQL 쿼리로 JSON 추출 (extract-legacy-data.sql 제공)
- **D-13:** borrado = false 조건으로 삭제된 데이터 제외

</decisions>

<canonical_refs>
## Canonical References

### 기존 시스템 테이블 구조
- 대화 내에서 사용자가 제공한 DDL (todocodigos, codigos, tipos, color)

### Ventago 모델
- `api-ventago/src/app/products/products.model.ts` — Product 모델 (storeId 추가됨)
- `api-ventago/src/app/category/category.model.ts` — Category (name + storeId unique)
- `api-ventago/src/app/colors/colors.model.ts` — Color (name + storeId unique)
- `api-ventago/src/app/sizes/sizes.model.ts` — Size (name + storeId unique)
- `api-ventago/src/app/products/branch/products-branch.model.ts` — ProductBranch

### 임포트 모듈
- `api-ventago/src/app/import/import.service.ts` — 마이그레이션 서비스
- `api-ventago/src/app/import/import.controller.ts` — POST /import/migrate
- `api-ventago/src/app/import/dto/import-migrate.dto.ts` — 요청 DTO
- `api-ventago/migrations/extract-legacy-data.sql` — 기존 DB 추출 쿼리

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Product bulk create 패턴: `productStock.service.ts`의 `createVariantsBatch()`
- findOrCreate 패턴: Category/Color/Size 모두 동일 구조

### Established Patterns
- 모든 엔티티는 storeId로 격리
- @Auth 데코레이터 + @GetUser()로 인증/유저 정보 추출
- Sequelize 트랜잭션으로 데이터 무결성 보장

### Integration Points
- `app.module.ts`에 ImportModule 등록 완료
- `api.service.ts`의 apiConnector로 프론트엔드 연동

</code_context>

<specifics>
## Specific Ideas

- 사용자가 기존 시스템의 정확한 DDL을 제공함 — 매핑이 확정됨
- 테스트 기간이므로 기존 데이터 손실 우려 없음
- 매장 간 SKU 충돌 가능성 높음 → storeId 격리 필수 (완료)

</specifics>

<deferred>
## Deferred Ideas

- Excel 파일 임포트 지원 (xlsx 파싱 라이브러리 필요)
- 재고 수량 임포트 (현재는 stock=0으로 생성)
- 가격 유형(PriceType) 매핑 — tpre2~5를 Ventago의 Price 모델로 연동
- 임포트 히스토리/로그 테이블

</deferred>

---

*Phase: 05-data-import*
*Context gathered: 2026-04-06*
