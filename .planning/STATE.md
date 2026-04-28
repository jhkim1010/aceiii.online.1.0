---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: 개선
status: executing
stopped_at: "Checkpoint 26-03-05: awaiting manual UI verification of /configuracion/categorias-gastos"
last_updated: "2026-04-28T13:07:46.958Z"
last_activity: 2026-04-28
progress:
  total_phases: 26
  completed_phases: 9
  total_plans: 78
  completed_plans: 63
  percent: 81
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** 매장 운영자가 POS 판매부터 재고/재무/외주까지 하나의 플랫폼에서 관리
**Current focus:** Phase 26 — gastos-categoria-tree-n-niveles

## Current Position

Phase: 26 (gastos-categoria-tree-n-niveles) — EXECUTING
Plan: 3 of 5
Status: Ready to execute
Last activity: 2026-04-28

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 20
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 14 | 4 | - | - |
| 16 | 4 | - | - |
| 17 | 5 | - | - |
| 18 | 1 | - | - |
| 12 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01-ui-ux P01 | 8 | 2 tasks | 4 files |
| Phase 06-reportajes P01 | 25min | 2 tasks | 26 files |
| Phase 06-reportajes P02 | 15min | 2 tasks | 22 files |
| Phase 06-reportajes P03 | 10min | 2 tasks | 21 files |
| Phase 06-reportajes P04 | 10min | 2 tasks | 16 files |
| Phase 08-reportajes-ux P01 | 15min | 2 tasks | 15 files |
| Phase 08-reportajes-ux P02 | 20min | 2 tasks | 30 files |
| Phase 08-reportajes-ux P03 | 45min | 3 tasks | 9 files |
| Phase 08-reportajes-ux P04 | 35min | 3 tasks | 5 files |
| Phase 11-thermal-printing P01 | reconciled | 3 tasks | 5 files |
| Phase 11-thermal-printing P02 | 25min | 2 tasks | 4 files |
| Phase 11-thermal-printing P03 | 15min | 3 tasks | 3 files |
| Phase 11-thermal-printing P04 | 20min | 5 tasks | 9 files |
| Phase 11-thermal-printing P05 | 12min | 5 tasks | 5 files |
| Phase 16-control-de-talleres P06 | 90 | 3 tasks | 23 files |
| Phase 25 P01 | 30min | 3 tasks | 4 files |
| Phase 25 P02 | 5min  | 1 task  | 1 file (운영 적용만) |
| Phase 25 P03 | 30min | 3 tasks | 2 files (step5+step6 SQL) |
| Phase 25 P04 | 25min | 3 tasks | 4 files (step4 SQL + 3 models) |
| Phase 25 P05 | 25min | 7 tasks | 7 files (CommonModule + 가드 + auth/store 수정) |
| Phase 25 P06 | 30min | 6 tasks | 4 files (slug seed + controller/service @OwnerScope) |
| Phase 25 P09 | 10min | 4 tasks | 4 files (CUIT/DNI validators + spec) |
| Phase 25 P07 | 30min | 4 tasks | 4 files (promote service + module + controller + spec) |
| Phase 25 P08 | 25min | 3 tasks | 3 files (merge service + endpoint + spec) |
| Phase 25 P10 | 25min | 5 tasks | 5 files (DTO + service skel + controller + module + app.module 등록) |
| Phase 25 P11 | 30min | 4 tasks | 1 file (importBatch 본체 + bucket 분류 + chunked transaction) |
| Phase 25 P12 | 15min | 3 tasks | 1 file (per-row error + ClientImport audit + response shape) |
| Phase 25 P13 | 5min  | 2 tasks | 0 files (빌드/lint 검증 + SUMMARY 작성) |
| Phase 25 P14 | 25min | 4 tasks | 1 file (CargaMasivaClientesView frontend wiring) |
| Phase 26 P01 | 45min | 7 tasks | 8 files |
| Phase 26 P02 | 13min | 5 tasks | 12 files |
| Phase 26-gastos-categoria-tree-n-niveles P03 | ~9min | 4 tasks | 13 files |

## Accumulated Context

### Roadmap Evolution

- Phase 14 added: Permisos Control — 역할별 권한 관리 UI
- Phase 15 added: Materia Prima Control — 원자재 관리 시스템 (의류업 특화)
- Phase 16 added: Control de Talleres — 중간 생산 과정 담당자 관리 및 컨트롤
- Phase 17 added: Portal de Talleres — 외주업자용 보조 프로그램 (aviso/알림, 진행현황, 수령 확인)
- Phase 18 added: AG Grid Migration — MUI DataGrid를 AG Grid Community로 교체 (컬럼 리사이즈/고정)
- Phase 20 added: Nueva Venta variation/codigo madre 디버깅 — 콘솔·서버·print-agent 로그 추가 및 suspender/restore 오류 추적
- Phase 21 added: Store Baseline Invariant System — store 단위 필수 설정(payment_methods, sellers 등)의 자동 생성·자가 치료·slug 기반 식별
- Phase 22 added: Suspender Restore Fidelity & Variant Stock Integrity — Reserved stock hold/release, restore UX 정합성, nullifySale variant 재고 복원, multi-branch 지원 완성
- Phase 25 added: Clientes globales compartidos entre tiendas (historial aislado) + Importación masiva CSV/Excel en ClienteView — 같은 그룹/소유자 매장 간 고객 기본정보 공유(이름/DNI/email/전화/주소), 구입이력은 storeId 격리. ClienteView에 CSV/Excel 업로드 + 컬럼 매핑 + DNI/email 중복 검증 + preview 커밋 + 실패행 리포트
- Phase 26 added: Gastos N차 카테고리 트리 — 무한 깊이(최대 5단계) 카테고리 계층 구조. 자기참조 트리(adjacency list + materialized path)로 사용자가 N차 sub category 자유 생성/이동/삭제. Reports 는 recursive CTE 롤업, 사용자가 depth 선택 가능

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 1]: 로그인 화면에 primary→secondary 그라데이션 적용
- [Phase 01-ui-ux]: PUT /users/ui-mode 엔드포인트를 @Get(':id') 라우트보다 위에 배치하여 NestJS 라우트 우선순위 문제 방지
- [Phase 01-ui-ux]: uiMode 유효성 검증을 컨트롤러에서 수행 (BadRequestException)
- [Phase 01-ui-ux]: UiModeProvider placed inside AuthProvider because it calls useAuth() hook
- [Phase 06-reportajes]: QuerysDto startDate/endDate를 optional로 변경 (잔액 보고서 호환)
- [Phase 06-reportajes]: MUI Chip은 'tonal' variant 미지원 — 'filled' 사용 + color로 시각 구분
- [Phase 06-reportajes]: Alertas: SReal<=0 Sin Stock / SReal<=5 Bajo Stock 임계값
- [Phase 06-reportajes]: Cheque Estado: PaymentMethod.slug=cheque 1차 필터, 없으면 전체 fallback
- [Phase 08-reportajes-ux]: Variant A helper props optional — shell 은 자체 Topbar 로 대체
- [Phase 11-thermal-printing]: electron-store defaults 사용 (schema 검증 보류) — 기존 config.json과 호환
- [Phase 16-control-de-talleres]: Wave 6: forwardRef() for QcItemService-EnvioService circular dep; crypto.randomUUID() over uuid package; uiId void pattern for ESLint; route ordering admin/all before :id
- [Phase 25]: PG10 partial UNIQUE 호환을 위해 ADD CONSTRAINT 대신 CREATE UNIQUE INDEX ... WHERE 사용 (PG10/PG15 양쪽 호환)
- [Phase 25]: Sequelize 모델에 unique:true 컬럼 선언 제거 — 부분 UNIQUE는 인덱스 레벨에서만 관리 (D1-01 정합성)
- [Phase 25]: owner_groups_seq START 2 — 기존 4개 매장이 group=1 이므로 신규는 2부터 (D3-02/D3-03)
- [Phase 25]: global_clients 누적 UNIQUE 제약을 DO 블록 LOOP 로 일괄 제거 (Sequelize sync 누적 정리)
- [Phase 25 P02]: sales dual-FK 전략 — store_client_id 신규/clientId 레거시 (D2-01)
- [Phase 25 P03]: 4 매장 동일 document='00000000' → global_clients 1개로 통합, store_clients 4개 매핑 (owner_group UNIQUE 격리 정상 동작 검증)
- [Phase 25 P03]: PLAN 의 birthdate/city/notes 컬럼은 실제 GlobalClient 모델에 없음 → name_fantasy/transport/res_iva/location 으로 매핑, note 는 store_clients 로 이관
- [Phase 25 P04]: audit 테이블 3개 분리 (audit_logs ENUM 확장 회피, PG10 호환)
- [Phase 25 P04]: client_merges.field_picks JSONB 사용 (PG10 도 JSONB 지원, 인덱스 불필요)
- [Phase 25 P05]: OwnerScopeService in-memory 캐시 5분 TTL — DB pool 절약 (CLAUDE.md 성능 규약)
- [Phase 25 P05]: store.service.ts 에서 owner_groups_seq nextval try/catch fallback=1 — sequence 부재 시에도 안전
- [Phase 25 P05]: CommonModule import alias `Phase25CommonModule` — 기존 common/cache 등과 충돌 회피
- [Phase 25 P06]: 명시적 slug 'manage-clientes-import' — 스페인어 액센트가 generateSlug 에서 깨지므로 func.slug 우선 패턴
- [Phase 25 P06]: GlobalClientsService.findOrCreate signature 변경 (ownerGroupId 추가) — 모든 호출자가 그룹 명시 필수
- [Phase 25 P06]: 별도 모듈 app/global-clients/ 는 Wave 2 범위 외 — 자체 massive-upload 가 있으나 캐노니컬 아님 (Plan 25-10+ 에서 통합 검토)
- [Phase 25 P09]: CUIT validators 명시적 export (isValidCuit + normalizeCuit) — 알고리즘 + 정규화 분리해서 import-side 활용성 높임
- [Phase 25 P09]: AFIP Pitfall 5 (calc==10 거부) 케이스 spec 으로 명시 검증 — 입력 '20000000012'
- [Phase 25 P07]: ClientsService.promote 가 conflict 시 DB 변경 0건 — status='merge_required' + conflictFields 반환 (사용자 결정 후 merge 별도 호출)
- [Phase 25 P07]: clients.note 를 store_clients.note 로 이관 (매장 비공개 정보 보존, GlobalClient 에 note 컬럼 없음)
- [Phase 25 P08]: MERGE_ALLOWED_FIELDS 화이트리스트는 GlobalClient 실제 컬럼만 — birthdate/city/notes 제외 (Plan 25-03 매핑 일관성)
- [Phase 25 P08]: 옵티미스틱 락 winnerUpdatedAt 비교 — Date 면 toISOString(), 아니면 String() 변환 (Sequelize timestamp 호환)
- [Phase 25 P08]: STALE_MERGE 응답 시 프론트가 GET /shared/global-clients/:id 재조회로 새 updatedAt 받아 재시도
- [Phase 25 P10]: 새 endpoint /clients/import 신설 (구 /global-clients/massive-upload 와 분리, 캐노니컬)
- [Phase 25 P10]: ImportRowDto + ImportBatchDto 분리 — class-validator + ValidateNested + Type
- [Phase 25 P11]: chunkSize=500 + MAX_ROWS=50000 + in-memory existingMap 캐시 (같은 batch 동일 doc 처리)
- [Phase 25 P11]: Default existing-hit policy='skip' — 가장 보수적. 사용자가 update/link 명시 필요
- [Phase 25 P11]: bulkCreate Local 실패 시 행마다 개별 INSERT fallback (어느 행이 실패했는지 식별 가능)
- [Phase 25 P12]: errorCode enum (EMPTY_FULLNAME / GLOBAL_UPSERT_FAILED / LOCAL_INSERT_FAILED) — 행 진단 일관성
- [Phase 25 P12]: per-row 에러는 트랜잭션 rollback 트리거 안 함 — 일부 실패해도 batch 는 성공 (격리)
- [Phase 25 P13]: Wave 5 frontend (Plan 14) 가 /global-clients/massive-upload → /clients/import 로 교체 예정
- [Phase 25 P14]: CargaMasivaClientesView 핵심 wiring 만 수행 — PromoteMergeDialog (cliente-vista 통합) 는 별도 phase
- [Phase 25 P14]: chunkSize=5000 — backend MAX_ROWS=50000 의 1/10, 큰 파일도 client-side 자동 분할
- [Phase 25 P14]: toImportRow 헬퍼 — 빈 문자열 → undefined 변환으로 백엔드 IsOptional + IsEmail 검증 호환
- [Phase 25 P15-deferred]: sales/reports scope audit (Wave 7) 는 큰 별도 phase 로 연기 — 4개 매장 모두 group=1 이라 운영 영향 없음
- [Phase 26]: PG10/PG15 호환: EXECUTE PROCEDURE (not EXECUTE FUNCTION), SERIAL (not GENERATED AS IDENTITY), ltree 미사용
- [Phase 26]: _phase26_cat_map 정식 테이블 (TEMP 아님) — 2주 롤백 윈도우 동안 보존, Wave 5 cleanup 시 DROP
- [Phase 26]: expenses_subcategory_id Wave 5 까지 유지 (두 컬럼 공존, 롤백 가능 윈도우 확보)
- [Phase 26]: subcategory 없던 expenses 행은 category_id = NULL (Sin categoría — 기존 동작 유지)
- [Phase 26]: Audit action enum: 'move'/'restore' mapped to 'edit' — AuditOptions.action union does not include those values
- [Phase 26]: ExpenseCategoryController: user.storeId! non-null assertion — @Auth() guarantees storeId for authenticated users
- [Phase 26]: Unit tests use jest mocks (not real DB) — DB trigger behavior covered by Wave 1 manual tests + DB-level guards
- [Phase 26]: apiConnector is a default export (not named) — all imports must use default import pattern
- [Phase 26]: Wave 3 nav for categorias-gastos: hardcoded in both superadmin block and admin append (navigation is DB-driven, admin extras are hardcoded)

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260420-qet | useVariants 토글 — 신상품 등록 화면 단순화 (VariantsStock 조건부 숨김 + cantidad TextField) | 2026-04-20 | 89184d0 | [260420-qet-tienda-admin-usevariants-false-variantss](./quick/260420-qet-tienda-admin-usevariants-false-variantss/) |

## Session Continuity

Last session: 2026-04-28T13:07:34.469Z
Stopped at: Checkpoint 26-03-05: awaiting manual UI verification of /configuracion/categorias-gastos
Resume file: None
Next: Wave 6 (QC 구조화 + Rework 자동화) planning
