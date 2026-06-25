# Phase 45: Legacy Bulk Import — pg_dump SQL 1파일 업로드 → 신규 매장 전체 데이터 일괄 import

## Goal
오프라인 ACE 레거시 시스템의 PostgreSQL `pg_dump` SQL 백업 파일 **1개**를 VentaGO 관리자 화면에서
업로드하면, 로그인한 매장(tienda)으로 ACE 의 전체 비즈니스 데이터(색상·카테고리·시즌·원산지·공급자·
판매원·고객·부모상품·자식상품·가격)를 **일괄 import** 한다.

기존 워크플로우(오프라인 PC 에서 `tools/ace_to_ventago_excel.py` 실행 → Excel 생성 → "Importar
códigos" 업로드)는 Python 환경 설치·CLI 실행이 필요해 비기술 사용자에게 진입 장벽이 높았다. Phase 45 는
**SQL 파일 1개만 드래그&드롭** 하면 끝나도록 변환 로직을 백엔드로 흡수한다.

## Depends on
- Phase 05 (Data Import — `code-import` 모듈: Colors/CodigoMadres/CodigoHijitos 일괄 INSERT 인프라, 단일 트랜잭션·청크·매장격리·5가격슬롯·audit)
- Phase 25 (Clientes Globales — `Clients` 모델 AfterCreate 훅이 GlobalClient/StoreClient 자동 sync)
- 기존 `sellers`(Seller), `tools/ace_to_ventago_excel.py`(ACE→VentaGO 매핑 권위 참조)

## Requirements
- LBI-01: pg_dump `.sql` 파일 멀티파트 업로드 (COPY 포맷 + INSERT 포맷 모두 파싱)
- LBI-02: 업로드 전 미리보기 — 감지된 ACE 테이블별 행 수 + 매핑 대상 표시 (import 미수행)
- LBI-03: ACE 스키마 변형 내성 — 컬럼명 후보 자동 탐지(Python 스크립트 로직 이식)
- LBI-04: 참조 무결성 보장 순서로 import (tipos→categories, color→colors, …, todocodigos→parents, codigos→variants)
- LBI-05: vendedores → Sellers, clientes → Clients(→GlobalClient/StoreClient 자동 sync)
- LBI-06: 모든 INSERT 에 로그인 사용자 storeId 강제 — 다른 매장 영향 0 (멀티테넌트 격리)
- LBI-07: 중복 처리 정책 선택 (skip / update) — 행 단위 격리, 한 행 실패가 전체를 막지 않음
- LBI-08: 결과 리포트 — 엔티티별 created/updated/skipped/errors + 행별 에러 상세
- LBI-09: import 이력 조회 (legacy_imports audit 테이블, 매장별 격리)
- LBI-10: admin 권한 사용자만 접근 (사이드바 Configuración 하위 메뉴)

## Success Criteria
1. ACE `pg_dump -d ace_db > backup.sql` 결과 파일을 그대로 업로드 가능 (별도 전처리 불필요)
2. 미리보기에서 `todocodigos: 1200행`, `codigos: 8500행`, `vendedores: 12행` 등 테이블별 카운트 표시
3. import 실행 후 신규 매장에 부모/자식 상품 + 5가격 + 색상/카테고리/사이즈 + 판매원 + 고객이 생성됨
4. 자식 상품의 `parentId` 가 부모(todocodigos→codigos.codigoproducto)로 정확히 연결됨
5. 색상은 `color` 테이블 FK lookup, 실패 시 descripcion `(ROJ)` 괄호 파싱으로 보강
6. 사이즈는 `str_talle` 컬럼, 없으면 SKU 끝자리 파싱
7. 다른 매장의 데이터는 전혀 변경되지 않음 (storeId 격리 검증)
8. 중복 SKU 충돌 시 선택한 정책(skip/update)대로 동작
9. 결과 화면에 엔티티별 카운트 + 에러 테이블 표시, legacy_imports 에 1행 audit 기록
10. 파싱 불가 행·orphan 자식·매핑 실패는 errors[] 에 누적되고 전체 import 는 계속 진행

## DB Schema Changes

### 새 테이블
- `legacy_imports` — 업로드 1건당 1행 audit (store_id 격리)
  - id, store_id(FK stores), user_id, file_name, file_size_bytes, status
  - tables_summary JSONB (테이블별 detected/created/updated/skipped)
  - code_import_id (FK code_imports, nullable — 상품 import 위임 결과)
  - errors JSONB, error_count, duration_ms, created_at, updated_at
  - index: (store_id, created_at DESC)

기존 테이블 스키마 변경 없음 — 모든 데이터는 기존 모델(Product/Color/Category/Size/Price/Seller/Clients)로 흡수.

## ACE → VentaGO 매핑 (tools/ace_to_ventago_excel.py 권위 참조 + 확장)

| 순서 | ACE 테이블 | → VentaGO | 매핑 핵심 |
|---|---|---|---|
| 1 | `tipos` | categories | tipos.tpdesc → category.name (findOrCreate) + ACE id→category id 맵 |
| 2 | `color` | colors | color.descripcioncolor → color.name + ACE id→color id 맵 |
| 3 | `temporadas` | seasons | temporada_nombre → season.name (findOrCreate) + ACE id→season id 맵 |
| 4 | `origenes` | origins | origen_nombre → origin.name + ACE id→origin id 맵 |
| 5 | `empresas` | suppliers | empdesc → supplier.name + ACE id→supplier id 맵 |
| 6 | `vendedores` | Sellers | name/lastName/document/phone, branchId=NULL + ACE id→seller id 맵 |
| 7 | `clientes` | Clients | fullname/document/phone/email/address/location + **vendedor FK→seller_id** (→GC/SC 자동 sync) |
| 8 | `todocodigos` | products(isParent=true) | tcodigo→sku, tdesc→name, tpre1→price + **FK 변환**(아래) |
| 9 | `codigos` | products(isParent=false) | codigo→sku, codigoproducto→parentSku, pre1..pre5, str_talle/SKU 파싱 + **color FK 변환** |

### FK 변환 (ACE 원래 id → VentaGO 새 id, 메모리 Map 유지)
참조 테이블을 먼저 import 하며 `ACE id → VentaGO id` Map 을 만들고, 후속 테이블에서 자동 변환:
1. `todocodigos.ref_id_tipo` → tipos.id → `products.category_id`
2. `todocodigos.ref_id_temporada` → temporadas.id → `products.season_id`
3. `todocodigos.ref_id_origen` → origenes.id → `products.origin_id`
4. `todocodigos.ref_id_empresa` → empresas.id → `products.supplier_id`
5. `codigos.codigoproducto` → todocodigos.tcodigo → `products.parent_id` (SKU lookup, code-import)
6. `codigos.ref_id_color` → color.id → `products.color_id`
7. `clientes.vendedor` → vendedores.id → `Clients.seller_id`

> FK 참조 대상이 없으면 해당 행은 **skip 하지 않고** 그 FK 만 NULL 로 두고, 실패 건수를 결과 리포트(`fkMappings.missing`)에 집계.
> store_id 미지정 — 로그인 매장으로 자동 할당 (멀티테넌트 격리).

## 비범위 (Out of Scope)
- ACE 의 판매내역(ventas)·재무·금전함 이력 import (상품/마스터데이터만)
- 운영 PG10 적용은 마이그레이션 SQL 커밋 + 수동 실행 (RUNBOOK)
- pg_dump custom/tar 포맷(`-Fc`/`-Ft`) — plain SQL(`-Fp`, 기본) 만 지원

## LBI 요구사항 보강 (FK)
- LBI-11: 참조 테이블 우선 import + ACE id→VentaGO id 메모리 Map 으로 후속 FK 자동 변환
- LBI-12: FK 대상 없으면 행 보존 + FK NULL + `fkMappings.missing` 집계/리포트
- LBI-13: clientes 의 담당 vendedor FK → Clients.seller_id 변환 (있을 때)
