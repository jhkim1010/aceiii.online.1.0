# Phase 45 CONTEXT — Legacy Bulk Import 설계 결정

## 배경
오프라인 ACE(레거시 의류 POS, PostgreSQL) 데이터를 VentaGO 신규 매장으로 이전. 기존엔
`tools/ace_to_ventago_excel.py` 로 Excel 변환 후 `code-import` 업로드. 본 Phase 는 변환을 서버로 흡수.

## 핵심 재사용 (중복 구현 금지)
- **`code-import` 모듈 (`CodeImportService.importBatch`)** — colors/parents/variants 의 단일 트랜잭션
  INSERT, 청크(500), 매장격리, 5가격슬롯(PriceType), 카테고리/색상/사이즈 findOrCreate, ProductBranch
  자동연결, code_imports audit 를 **이미 완비**. legacy-import 는 ACE rows → `CodeImportBatchDto` 로
  변환 후 `importBatch` 를 호출(위임)한다. 상품 로직을 다시 작성하지 않는다.
- **`Clients` 모델 AfterCreate 훅** — `Clients.create()` 만 하면 GlobalClient/StoreClient 자동 sync
  (caller transaction 존중). legacy-import 는 clientes 를 `Clients` 로만 INSERT 하면 됨.
- **`tools/ace_to_ventago_excel.py`** — ACE 스키마 컬럼 후보 목록(PARENT/VARIANT/REFERENCE_TABLES),
  색상 약어맵, 사이즈/색상 파싱 로직의 **권위 참조**. `ace-mapping.ts` 로 1:1 이식.

## 결정 (Decisions)

### D-1 — pg_dump 파싱: COPY 우선 + INSERT 보조
pg_dump 기본(plain) 포맷은 `COPY tbl (cols) FROM stdin;` … `\.` 블록(탭 구분, `\N`=NULL, `\t\n\r\\`
이스케이프). `--inserts` 옵션이면 `INSERT INTO tbl (cols) VALUES (...);`. 둘 다 파싱. 컬럼 없는
`INSERT INTO tbl VALUES` 는 선행 `CREATE TABLE` 컬럼 순서로 보강. custom/tar 포맷은 비범위(plain 만).

### D-2 — 트랜잭션 경계: 2개 (위임 + 자체)
`importBatch` 는 자체 트랜잭션을 commit 하고 code_imports 행을 만든다. legacy-import 는 (a) 상품/참조
데이터를 `importBatch` 로 위임(트랜잭션 A), (b) sellers/clients 를 자체 `SERIALIZABLE` 트랜잭션
(트랜잭션 B)으로 처리한다. 두 단위는 각각 원자적. 일회성 관리자 import 도구이므로 A 성공/B 실패 시
A 보존 + 리포트로 충분(재실행은 skip 정책으로 idempotent). 단일 거대 트랜잭션으로 묶으려고 상품 로직
~600줄을 복제하지 않는다(유지보수성 우선). legacy_imports 가 master audit, code_imports 는 위임 detail.

### D-3 — temporadas/origenes/empresas: import + FK 변환 (SUPERSEDED 2026-06-25)
~~1차 drop~~ → **사용자 요청으로 FK 처리 정식 구현.** temporadas/origenes/empresas 를 VentaGO
seasons/origins/suppliers 로 findOrCreate import 하고, `ACE id → VentaGO id` 메모리 Map 을 유지.
parent 상품(todocodigos) FK 를 이 Map 으로 변환하여 `products.season_id/origin_id/supplier_id/
category_id` 에 적용(SKU 기준 UPDATE). FK 대상 없으면 그 FK 만 NULL + `fkMappings.missing` 집계.

### D-7 — FK 변환 아키텍처 (2026-06-25 추가)
- 참조 테이블(seasons/origins/suppliers) import 는 트랜잭션 B 안에서 code-import(트랜잭션 A, 카테고리/
  색상 생성) 이후 실행 → category/color id-map 은 VentaGO 행을 name 으로 cross-ref 하여 빌드.
- color FK (codigos.ref_id_color) 통계는 buildCodeImportBatch(트랜잭션 A 경로)에서 집계. 실제
  color_id 연결은 code-import 가 colorName 기반으로 수행(동일 결과). FK 미싱 시 descripcion 괄호
  파싱 fallback 으로 색상 보강.
- parent FK UPDATE 는 SKU IN 청크(500) 조회 후 resolved FK 만 set(미싱은 NULL 유지). 미싱 상세
  에러는 타입별 최대 50건만 errors[] 적재(전수는 fkMappings.missing 카운트).
- clientes 담당 vendedor FK → Clients.seller_id: vendedores import 시 ACE id→Seller id Map 빌드 후
  clientes import 에서 변환.

### D-4 — 충돌 정책: skip(기본) / update
`code-import` 의 'link' 까지 노출하면 사용자 혼란. 신규 매장 import 시나리오라 기본 skip 으로 충분.
sellers/clients 는 (storeId, document) 또는 (storeId, name) 기준 중복 탐지 후 정책 적용.

### D-5 — 스키마 내성: 런타임 컬럼 탐지
ACE 스키마는 PC 마다 컬럼명이 다를 수 있음. 파서가 COPY/INSERT 의 실제 컬럼 리스트를 읽고,
`ace-mapping.ts` 의 후보 배열과 매칭하여 logical field 를 결정(Python `detect_column` 이식).

### D-6 — 권한: admin Configuración 하위
`navigation/vertical/index.ts` 의 `configChildrenBase` 에 메뉴 추가(admin 앱 그룹 → admin/superadmin
만 노출). 백엔드는 JWT + 매장 storeId 강제. (기존 manage-codigo-import 권한 슬러그 재사용 가능하나,
신규 슬러그 `manage-legacy-import` 도입은 functions seed 변경 필요 → 1차는 JWT+admin 게이트로 충분.)

## Pool 안전성
- 파서는 순수 문자열 처리(DB 무관, connection 0개).
- import 는 sequelize 모델 메서드 + 트랜잭션만 사용(`pool.connect()` 직접 호출 금지).
- 위임 `importBatch`(트랜잭션 A) → 자체 트랜잭션 B 순차 — 동시 2 connection 점유 안 함.
- 파일 크기 상한(기본 25MB) + 시트당 50000행 상한으로 메모리/pool 폭주 방지.

## 디버깅
- `sql-parser.service.ts`: 블록 감지·컬럼 매핑·행 카운트 Logger.debug.
- `legacy-import.service.ts`: 단계별(테이블별) 진행·매핑실패·skip 사유 Logger.debug + 요약 Logger.log.
- 환경변수 무관, NestJS Logger(winston 라우팅)로 운영에서도 추적 가능.

## 검증 계획 (UAT)
1. 실제 ACE pg_dump 샘플(또는 합성)으로 미리보기 카운트 확인
2. import 후 productos/precios/usuarios(판매원)/clientes 화면에서 데이터 확인
3. 다른 매장 데이터 불변 확인 (storeId 격리)
4. 중복 재업로드 시 skip 정책 idempotent 확인
5. 깨진 SQL/빈 파일/대용량 파일 에러 핸들링 확인
