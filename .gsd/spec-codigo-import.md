# SPEC: CodigoView Excel Import (Massive Mode)

생성일: 2026-04-28
작성자: GSD workflow

---

## 목표

CodigoVistaView (`/precios`, `/codigo-vista`) 화면에 엑셀(.xlsx/.xls) 일괄 import 기능을 추가합니다.
대상 데이터: **colors / codigoMadres(부모 제품) / codigoHijitos(자식·변형 제품)**.
ClientImport 패턴을 따르되, **Global 공유 개념 없이** 오직 1개 매장(여러 지점 포함)에만 데이터가 등록되도록 `storeId`로 완전 격리합니다.

---

## 배경 및 컨텍스트

### 현재 상태
- `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` 가 부모/자식 제품의 가격 관리를 담당.
- `apiConnector.get('/products/by-store')` 로 데이터 로드 → NestJS `Product`/`Color` 모델 사용 (Sequelize, `underscored: true`).
- 백엔드 `api-ventago/src/app/import/import.service.ts` 에 이미 **categories/colors/sizes/parents(todocodigos)/variants(codigos)** 를 트랜잭션으로 일괄 등록하는 `ImportService.migrate()` 로직이 존재. ProductBranch 자동 연결 포함.
- ClientImport (`api-ventago/src/app/client-import/`) 가 chunk 처리, audit trail, `skip|update|link` 정책의 정석 패턴.

### 사용자 결정사항 (확정됨)
1. **시트 구성**: 3개 시트 분리 — `Sheet1=Colors`, `Sheet2=CodigoMadres`, `Sheet3=CodigoHijitos`.
2. **중복 처리 정책**: `skip / update / link` 모두 제공. 다이얼로그에서 사용자가 선택. 기본값 = `skip`.
3. **이력 저장 (audit trail)**: 신설 테이블 `code_imports` 에 누가/언제/파일명/카운트/에러 보관.
4. **부모 식별 키**: 엑셀의 자식 행에 들어 있는 레거시 `ref_id_todocodigo` 는 사용하지 않음. 새 시스템은 `parentSku` (혹은 `id_madre` 별칭) 컬럼으로 같은 매장 내 부모 SKU lookup.

### 핵심 제약
- **storeId 완전 격리** — 모든 INSERT/UPDATE 에 `storeId = ctx.user.storeId` 필수. 다른 매장 데이터에는 절대 영향 없음.
- **PostgreSQL pool 절약** — 단일 `sequelize.transaction()` 내부에서 chunk(500행) 단위 처리. `pool.connect()` 직접 호출 금지. 모델 메서드만 사용해서 connection 자동 반환되게.
- **ESLint 빌드 차단 회피** — `newline-before-return`, `lines-around-comment`, `no-unused-vars` 엄격 준수.

---

## 기술 스택

- **백엔드**: NestJS 11 + Sequelize-typescript + PostgreSQL 15 (Docker `dbpostgres`)
- **프론트**: Next.js 13 Pages Router + MUI 5 + Redux Toolkit + SWR
- **엑셀 파싱**: `xlsx` (sheetjs) — 이미 설치됨 (CargaMasivaClientesView 에서 사용 중)
- **인증/권한**: JWT + CASL ACL (`subject: 'ventas'`, `action: 'manage'`)
- **ESLint 설정**: `ventago-app/.eslintrc.js`, `api-ventago/.eslintrc.js`

---

## 엑셀 파일 포맷 (Template)

### Sheet1: Colors
| 컬럼 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | 색상명 (매장 내 unique). 대문자 정규화. |
| `hex` |   | 16진수 색상코드 (예: `#FF0000`). |

### Sheet2: CodigoMadres (부모 제품)
| 컬럼 | 필수 | 설명 |
|------|------|------|
| `sku` | ✅ | 부모 SKU (매장 내 unique). |
| `name` | ✅ | 제품명. |
| `price` |   | 가격 (숫자). 비어있으면 0. |
| `priceOrig` |   | 원가. |
| `description` |   | 설명. |
| `categoryName` |   | 카테고리명. 없으면 자동 생성. |

### Sheet3: CodigoHijitos (자식·변형 제품)
| 컬럼 | 필수 | 설명 |
|------|------|------|
| `parentSku` | ✅ | 동일 매장 내 부모 SKU. lookup 실패 시 에러. |
| `sku` | ✅ | 자식 SKU (매장 내 unique). |
| `name` |   | 변형 제품명. 비어있으면 부모 + 색/사이즈로 자동 생성. |
| `colorName` |   | Sheet1 의 색상명 또는 신규. |
| `size` |   | 사이즈 문자열 (예: `M`, `38`). |
| `price` |   | 가격. |
| `stock` |   | 초기 재고. (현 ImportService 와 동일하게 0 으로 시작 가능 — 별 옵션) |

> 참고: 사용자의 기존 엑셀에 `ref_id_todocodigo` 컬럼이 있더라도 **무시**합니다. 새 시스템 lookup 키는 `parentSku` 입니다. 사용자가 안내된 템플릿에 SKU를 채워서 import 해야 합니다.

---

## 백엔드 변경

### 신규 모듈: `api-ventago/src/app/code-import/`

```
code-import/
├── code-import.module.ts
├── code-import.controller.ts
├── code-import.service.ts
├── models/
│   └── code-import.model.ts        # audit trail
└── dto/
    ├── code-import-batch.dto.ts
    ├── color-row.dto.ts
    ├── parent-row.dto.ts
    └── variant-row.dto.ts
```

### 신규 테이블: `code_imports` (audit)
```sql
CREATE TABLE code_imports (
  id           SERIAL PRIMARY KEY,
  store_id     INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  user_id      INTEGER NOT NULL,
  file_name    VARCHAR(255),
  total_rows   INTEGER NOT NULL DEFAULT 0,
  colors_created  INTEGER DEFAULT 0,
  colors_updated  INTEGER DEFAULT 0,
  colors_skipped  INTEGER DEFAULT 0,
  parents_created INTEGER DEFAULT 0,
  parents_updated INTEGER DEFAULT 0,
  parents_skipped INTEGER DEFAULT 0,
  variants_created INTEGER DEFAULT 0,
  variants_updated INTEGER DEFAULT 0,
  variants_skipped INTEGER DEFAULT 0,
  error_count  INTEGER DEFAULT 0,
  errors_json  JSONB,
  status       VARCHAR(32) NOT NULL DEFAULT 'COMPLETED',
  default_existing_hit_policy VARCHAR(16) NOT NULL DEFAULT 'skip',
  duration_ms  INTEGER,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_code_imports_store_created ON code_imports(store_id, created_at DESC);
```
SQL 파일: `api-ventago/migrations/2026-04-28-code-imports.sql`

### 엔드포인트
- `POST /code-import` — body: `{ fileName, defaultExistingHitPolicy, colors, parents, variants }`. JWT user 의 `storeId` 사용. 반환: `{ codeImportId, summary, errors[] }`.
- `GET /code-import/history?page=0&pageSize=20` — 매장 import 이력 페이지네이션.
- `GET /code-import/template` — 빈 엑셀 템플릿 (3 시트, 헤더만) 다운로드.

### 서비스 핵심 로직 (`code-import.service.ts`)
1. 단일 `sequelize.transaction()` 시작.
2. **Colors**: chunk 500. 각 행 → `(name, storeId)` 로 `findOne`. 충돌 시 정책 적용 (`skip`/`update`/`link`). 신규는 `Color.create` (`storeEntityId` 자동 증가).
3. **Parents (codigoMadres)**: chunk 500. `(sku, storeId)` 로 `findOne`. 신규 시 `isParent=true` + `Category.findOrCreate(by name + storeId)`. ProductBranch 는 매장 기본 지점에 자동 연결 (또는 옵션). 정책 분기 동일.
4. **Variants (codigoHijitos)**: chunk 500. 먼저 `parentSku → parentId` 매핑(이번 import 의 신규 부모 + DB 기존 부모 동일 매장 lookup). 자식은 `(sku, storeId)` unique. `colorName` 은 이번 import 의 신규 컬러 + DB 기존 컬러 동일 매장 lookup. 정책 분기 동일.
5. 행별 에러는 `errors[]` 누적, 트랜잭션은 끝까지 진행 (행 단위 실패가 전체 롤백 X).
6. **`code_imports` audit row INSERT** → `transaction.commit()`.
7. 서비스 호출 끝, NestJS DI 가 sequelize pool 자동 관리 (수동 `pool.connect` 없음).

### Pool 안전성
- `sequelize.transaction()` 한 번만 사용 — chunk 사이에 새 connection 획득 없음.
- 모델 메서드 (`findOne`, `findAll`, `create`, `update`)만 사용 → Sequelize 가 transaction connection 자동 재사용.
- 호출당 connection 1개만 점유, 끝에서 자동 반환.

### 권한
- `@FunctionGuard('manage-codigo-import', 'create')` — `POST /code-import`
- `@FunctionGuard('view-codigo-import-history', 'read')` — `GET /code-import/history`
- `manage-codigo-import` 와 `view-codigo-import-history` function 을 admin/superadmin/gerente 역할에 매핑하는 마이그레이션도 함께.

---

## 프론트엔드 변경

### 신규 파일
- `ventago-app/src/views/codigo-vista/CodeImportDialog.tsx` — 4-step 다이얼로그 (Upload → Preview → Confirm → Result).
- `ventago-app/src/views/codigo-vista/CodeImportHistoryView.tsx` — 이력 테이블.
- `ventago-app/src/hooks/api/useCodeImportHistory.ts` — SWR hook.
- `ventago-app/src/pages/codigo-vista/historial/index.tsx` — 이력 페이지.

### 수정 파일
- `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` — 상단 액션 바에 두 개 버튼 추가:
  - `<Button startIcon=cloud-upload>Importar Excel</Button>` → 다이얼로그 오픈
  - `<Button startIcon=download>Descargar template</Button>` → `GET /code-import/template`

### CodeImportDialog 플로우
- **Step 0 — Upload**: `.xlsx/.xls` 파일 받기. `XLSX.read` 로 3 시트 파싱. 시트명 검증 (Colors/CodigoMadres/CodigoHijitos). 누락 시 경고. 정책 라디오 (`skip/update/link`).
- **Step 1 — Preview**: 시트별 미리보기 테이블 (각 최대 50행 + 총 행수). 누락 필수 컬럼 / parentSku 미존재 행 빨갛게. "X 행 처리 예정 / Y 행 에러 가능" 요약.
- **Step 2 — Confirm & Upload**: chunk 단위 진행 표시. 단일 POST 권장 (3 시트가 같은 트랜잭션에 묶여야 함). 큰 파일이면 5000행 분할 호출.
- **Step 3 — Result**: 색상/부모/자식 별 created/updated/skipped/errors 카운트 + 행별 에러 (rowIndex, sheetName, errorCode, message). "Cerrar" 시 `mutate` 로 SWR 캐시 invalidate.

### 권한 가드
- 페이지 ACL: `{ action: 'manage', subject: 'ventas' }` (현재 `read` 보다 강한 권한 필요)
- 다이얼로그 진입 버튼은 `useCan('manage', 'ventas')` 로 조건 표시.

### 엑셀 라이브러리
- `import * as XLSX from 'xlsx'` — 이미 의존성에 존재(CargaMasivaClientesView 사용). 추가 설치 불필요.

---

## 태스크 목록

- [ ] **TASK-1** SPEC 작성 + 사용자 승인 (이 문서) — 파일: `.gsd/spec-codigo-import.md`
- [ ] **TASK-2** Migration SQL 작성 — 파일: `api-ventago/migrations/2026-04-28-code-imports.sql`
- [ ] **TASK-3** Sequelize 모델 — 파일: `api-ventago/src/app/code-import/models/code-import.model.ts`
- [ ] **TASK-4** DTO 작성 — 파일: `api-ventago/src/app/code-import/dto/{code-import-batch,color-row,parent-row,variant-row}.dto.ts`
- [ ] **TASK-5** Service: chunk 처리 + 정책 분기 + audit insert — 파일: `api-ventago/src/app/code-import/code-import.service.ts`
- [ ] **TASK-6** Controller + Module + AppModule 등록 — 파일: `api-ventago/src/app/code-import/{controller,module}.ts`, `app.module.ts`
- [ ] **TASK-7** Template export 엔드포인트 (xlsx 빈 템플릿) — Service `generateTemplate()` 추가
- [ ] **TASK-8** Function-permission 시드: `manage-codigo-import`, `view-codigo-import-history` 등록 SQL — 파일: `api-ventago/migrations/2026-04-28-code-import-permissions.sql`
- [ ] **TASK-9** 프론트 SWR hook — 파일: `ventago-app/src/hooks/api/useCodeImportHistory.ts`
- [ ] **TASK-10** CodeImportDialog 컴포넌트 (4 step) — 파일: `ventago-app/src/views/codigo-vista/CodeImportDialog.tsx`
- [ ] **TASK-11** CodigoVistaView 상단 버튼 통합 — 파일: `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx`
- [ ] **TASK-12** 이력 페이지 + 메뉴 등록 — 파일: `ventago-app/src/pages/codigo-vista/historial/index.tsx`, `ventago-app/src/views/codigo-vista/CodeImportHistoryView.tsx`
- [ ] **TASK-13** 백엔드 ESLint 검증: `npx eslint api-ventago/src/app/code-import --fix`
- [ ] **TASK-14** 프론트 ESLint 검증: `npx eslint ventago-app/src/views/codigo-vista ventago-app/src/hooks/api/useCodeImportHistory.ts ventago-app/src/pages/codigo-vista --fix`
- [ ] **TASK-15** PostgreSQL pool 안전 점검 — `pool.connect()` 직접 호출 없음, transaction 단일, 모델 메서드만 사용 확인
- [ ] **TASK-16** 통합 리뷰 + 변경 요약

---

## 완료 기준

- ESLint 오류 0개 (백엔드/프론트 양쪽)
- `code_imports` 테이블이 로컬 dev DB 에 정상 생성됨 (PG15)
- 운영 PG10 호환성 SQL (운영 적용 전 사용자 확인 — 별도 단계)
- 동일 매장(같은 storeId) 데이터만 영향 받음 — 다른 매장 격리 확인
- 트랜잭션 내 한 행 실패가 다른 행을 막지 않음 (per-row 에러 누적)
- 다이얼로그가 1000행 미만 엑셀에서 5초 내 응답 (목표)
- 이력 화면에서 import 결과 재확인 가능

---

## 금지사항 / 주의사항

- 운영 DB 직접 변경 절대 금지. 마이그레이션 SQL 파일만 작성. 실행은 사용자 확인 후 별도 단계.
- 다른 매장(다른 storeId) 의 색상/제품에 영향을 주는 코드 작성 금지. 모든 쿼리에 `where: { storeId }` 강제.
- `pool.connect()` 직접 호출 금지. NestJS Sequelize DI 사용.
- 기존 `ImportService.migrate()` (`api-ventago/src/app/import/`) 은 건드리지 않음 — 레거시 마이그레이션 전용.
- CodigoVistaView 의 가격 일괄수정 로직(`bulk-update-explicit-prices`) 은 건드리지 않음.
- ESLint `newline-before-return`, `lines-around-comment` 빌드 차단 — 모든 신규 파일에서 준수.
- 프론트 신규 페이지는 `next/dynamic({ ssr: false })` 로 동적 import.
- `apiConnector.remove()` 사용 (`.delete()` 아님).
