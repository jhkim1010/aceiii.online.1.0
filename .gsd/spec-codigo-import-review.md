# GSD 리뷰 리포트: CodigoView Excel Import

작성일: 2026-04-28

## 완료된 태스크

- [x] TASK-1 SPEC 작성
- [x] TASK-2 Migration SQL (`2026-04-28-code-imports.sql`)
- [x] TASK-3 백엔드 모듈 (model, dto×4, service, controller, module)
- [x] TASK-4 프론트엔드 (CodeImportDialog, SWR hook, CodigoVistaView 통합)
- [x] TASK-5 검증 + 리뷰

## 신규/수정 파일 (총 14개)

### 백엔드 신규 (9)
- `api-ventago/migrations/2026-04-28-code-imports.sql` — code_imports 테이블
- `api-ventago/src/app/code-import/models/code-import.model.ts` — audit 모델
- `api-ventago/src/app/code-import/dto/code-import-batch.dto.ts` — batch DTO + PricePolicies
- `api-ventago/src/app/code-import/dto/color-row.dto.ts`
- `api-ventago/src/app/code-import/dto/parent-row.dto.ts`
- `api-ventago/src/app/code-import/dto/variant-row.dto.ts` — price1..price5 5가지 가격
- `api-ventago/src/app/code-import/code-import.service.ts` — 단일 트랜잭션, chunk 500
- `api-ventago/src/app/code-import/code-import.controller.ts` — POST/GET, 템플릿
- `api-ventago/src/app/code-import/code-import.module.ts`

### 백엔드 수정 (2)
- `api-ventago/src/app.module.ts` — CodeImportModule 등록
- `api-ventago/src/app/functions/seed/functions.seed.ts` — manage-codigo-import / view-codigo-import-history slug

### 프론트 신규 (2)
- `ventago-app/src/hooks/api/useCodeImportHistory.ts`
- `ventago-app/src/views/codigo-vista/CodeImportDialog.tsx` — 4-step

### 프론트 수정 (1)
- `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` — 상단 액션바 + 다이얼로그 통합

## 품질 검증

- [x] **ESLint** 백엔드 신규 파일 6개 + app.module.ts + functions.seed.ts → 오류 0
- [x] **ESLint** 프론트 신규 파일 2개 + CodigoVistaView.tsx → 오류 0
- [x] **PostgreSQL pool**: `pool.connect()` 직접 호출 0건. 단일 `sequelize.transaction()` 1회 호출. 모델 메서드(findOne/findAll/create/update/findOrCreate)만 사용.
- [x] **storeId 격리**: 모든 read/write 쿼리에 `storeId: ctx.storeId` 강제. 라인 단위 검증 완료. priceModel 쿼리는 productId 가 이미 caller storeId 자식이므로 안전.
- [x] **에러 핸들링**: 모든 async 메서드에 try/catch. 행 단위 실패는 errors[] 누적 후 다음 행 진행 — 트랜잭션 전체 rollback 안 함.
- [x] **주석**: 한국어로 작성. 함수/변수명: 영어.

## 주요 기능 요약

1. **3 시트 구조**: `Colors` / `CodigoMadres` / `CodigoHijitos`
2. **5가지 가격**: 매장의 PriceType 을 storeEntityId ASC 로 1~5번 슬롯에 매핑. 엑셀 `price1..price5` 컬럼이 각 슬롯에 들어감. `price` 컬럼은 fallback (price1 미지정 시 base).
3. **충돌 정책**:
   - 자식/부모/색상: `skip` / `update` / `link` (사용자 선택, 기본 skip)
   - 가격(5개 각각): `skip` / `update` / `fill_if_empty` (사용자 선택, 기본 skip)
4. **신규 자식**: 정책 무관, 값 있는 슬롯 자동 INSERT (5가지 가격 자동 생성)
5. **기존 자식**: 사용자가 선택한 정책에 따라 가격별로 분기
6. **Audit**: 1회 import = code_imports 1행. 카운트 + 행별 에러 jsonb 저장.

## 운영 적용 가이드 (사용자 승인 필요)

### 1단계 — 로컬 dev DB 마이그레이션
```bash
docker exec api_ventago bash -c "node -e \"
  const fs=require('fs');
  const {Client}=require('pg');
  const sql=fs.readFileSync('/app/migrations/2026-04-28-code-imports.sql','utf8');
  const c=new Client({host:'dbpostgres',user:'coolsistema',password:'<REDACTED>',database:'ventago'});
  c.connect().then(()=>c.query(sql)).then(()=>{console.log('OK');c.end();}).catch(e=>{console.error(e);c.end();});
\""
```

### 2단계 — 백엔드 재기동
- `npm run dev:api` 또는 docker compose restart api_ventago
- functions seed 가 `manage-codigo-import`, `view-codigo-import-history` 자동 등록
- admin/superadmin/gerente 역할에 두 권한 매핑 확인 (role-function 시드 또는 admin UI)

### 3단계 — 운영 적용 (사용자 확인 후)
- 운영 DB는 PG10 + pgbouncer. SQL 호환성 확인됨 (TIMESTAMP WITH TIME ZONE, JSONB 모두 PG10 지원).
- 운영 적용 SQL:
  ```bash
  ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/2026-04-28-code-imports.sql
  ```
- Jenkins 빌드 → docker compose up -d 로 신 모듈 배포

## Pool 안전 체크리스트

- [x] 모든 `pool.connect()`에 대응하는 `client.release()`가 `finally`에 있는가? — N/A, pool.connect 직접 호출 안 함
- [x] Pool 인스턴스가 싱글턴(모듈 레벨)으로 생성되어 있는가? — Sequelize DI 단일 인스턴스
- [x] `idleTimeoutMillis` 설정이 있는가? — 기존 sequelize 설정 그대로 사용
- [x] 트랜잭션 롤백 시에도 `release()`가 호출되는가? — sequelize.transaction() 자동 처리

## 후속 작업 / 주의사항

- **권한 매핑**: `manage-codigo-import` / `view-codigo-import-history` 를 admin/superadmin/gerente 역할에 매핑하는 별도 admin UI 작업이 필요할 수 있음 (role-function 매핑 시드가 있다면 자동, 없으면 수동).
- **History 페이지**: 현재 SWR hook (`useCodeImportHistory`) 만 만들어 둠. 별도 페이지가 필요하면 `ventago-app/src/pages/codigo-vista/historial/index.tsx` 추가 (5분 작업).
- **PriceType 부족 시**: 매장에 PriceType 이 5개 미만이면 부족한 슬롯의 price2~5 는 무시됨. 다이얼로그에 경고 표시 추가는 추후 확장.
- **운영 매장 PriceType 확인**: 본 기능 활성화 전 매장별 PriceType 5개가 storeEntityId ASC 로 정렬되어 있는지 확인 권장.
- **레거시 ref_id_todocodigo**: 사용자의 기존 엑셀에 이 컬럼이 있어도 무시됨. 사용자가 새 시스템의 부모 SKU 를 `parentSku` 컬럼에 채워서 import 해야 함.
