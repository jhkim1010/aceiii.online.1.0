---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: 개선
status: verifying
stopped_at: Phase 33 (Permissions v2) — VERIFIED 2026-06-11 (휴면 인정 종결). 인프라+33.1 D1/D2 hotfix 운영 배포 확인 (deployed dist). 신규 RBAC 기능 휴면(영향 유저 0명) → active-feature UAT N/A. Phase 34/35 verifying 여전히 대기.
last_updated: "2026-06-11T00:00:00.000Z"
last_activity: 2026-06-11
progress:
  total_phases: 33
  completed_phases: 14
  total_plans: 104
  completed_plans: 85
  percent: 82
  # 주의: Phase 33/34 는 retroactively 등록된 phase 로 implementation 은 완료되었으나
  # verifying 상태이므로 completed_plans 에서 제외. 운영 적용 + UAT 완료 시 +4 plans 가산.
  # 정확한 재계수는 next /gsd-stats 실행 시 갱신 권장.
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** 매장 운영자가 POS 판매부터 재고/재무/외주까지 하나의 플랫폼에서 관리
**Current focus:** Phase 33 (Permissions v2) **VERIFIED 2026-06-11** 종결. 다음 verifying 대상: Phase 34 (Client WhatsApp+CRM), Phase 35 (Activity Ledger UAT).

## Current Position

Phase 33 (Permissions v2 — RBAC + Branch Scope + Approval) — **VERIFIED 2026-06-11 ✅ (휴면 인정 종결)**
- 인프라: 마이그레이션(4 테이블/ENUM 13값/컬럼/인덱스) + 백엔드/프론트 배포 + 7 표준 role 시드 — Test 0~10 PASS (5/18~19)
- 33.1 D1/D2 hotfix 운영 배포 확인 (deployed dist 검증: D1 ensureRoleFunctions read-only ✅ / D2 bulkUpdate→invalidateRole ✅)
- Test 16 (pool) PASS — 경고/대기 0건, 4/400 연결. Test 18 (cold start) PASS — 6/9 재빌드 부팅 ERROR 0
- Test 12/13/14/15/17 N/A — 신규 RBAC 기능(branch scope/approval/cache/8-role) 운영 휴면, 영향 유저 0명
- Test 11 deferred — 프론트 배포 완료(#352), UI 렌더는 optional manual check
- 휴면 데이터(빈 role_functions/user_branches=0/permission_slug 131 null)는 acceptable artifact
- 상세: [.planning/phases/33-permissions-v2/33-UAT.md](phases/33-permissions-v2/33-UAT.md)
- 미적용(deferred, 사용자 confirm 필요): cleanup SQL `33.1-cleanup-orphan-role-functions.sql` — 운영 휴면이라 비긴급

Phase 33.1 (Permissions v2 D1/D2 Hotfix) — VERIFIED 2026-05-26 ✅ → 운영 배포 확인됨 (2026-06-11)
Plans: 3/3 (33.1-01 D1 95c2484 + 33.1-02 D2 0181056 + 33.1-03 REG e09376c) — Jest 11 PASS

Phase 35 (Activity Ledger — Movidos/Fallados Trace in ventaVista) — IMPLEMENTATION 완료 / ready-for-prod-deploy
Plans: 8/9 (35-01..35-08) + 35-09 UAT scaffold. UAT verified_with_gaps (22/22, 2026-05-23).
Status: 🟡 ready-for-prod-deploy — 운영 적용 차단 blocker 2건 해소됨 (Phase 36):
  - ✅ U9 권한 매핑: phase36-stock-movement-actions-backfill.sql (8c7ba1d, dev 멱등 검증) — role_function_actions 보강
  - ✅ 운영 RUNBOOK: 35-RUNBOOK-PROD.md 작성 (Phase 36-02) — 사용자 검토 대기
  - ✅ Phase 36.1 회귀 hotfix(REG-1/REG-2) 코드 존재 (f3ade81)
  - ⏳ 남은 manual UAT (dev 실행 필요): U9/U10 cURL smoke (POST /stocks/movement 200/403) + U14 movBalance 브라우저 ⚠ 캡처
Resume: 1) RUNBOOK 사용자 검토/승인 (35-RUNBOOK-PROD.md)
        2) `./dev.sh` 후 U9/U10 cURL + U14 브라우저 manual 보충
        3) 운영 적용 (RUNBOOK Section 0~4, 각 단계 사용자 확인) → Phase 35/36 complete → Phase 37 배포 게이트 해제

Phase 34 (Client WhatsApp + CRM Routing — Phase 29 Wave C) — IMPLEMENTATION 완료 / verifying
Plan: 1/1 plan complete (12 tasks) — 모든 commit pushed (api-ventago 9 + ventago-app 3)
Status: ⚠ verifying — 정식 UAT 미수행, 운영 매장 실사용 검증 대기

Phase 32 (stocks-historial-drawer) — COMPLETE (2/2)
Last activity: 2026-05-17 (submodule auto-commit)

Progress: [████████░░] 82% (Phase 33/34 verifying 미산입, 운영 적용 + UAT 후 +4 plans 재계수 필요)

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
| Phase 26-gastos-categoria-tree-n-niveles P04 | ~28min | 4 tasks | 17 files |
| Phase 29 P01 | 8min | 3 tasks | 8 files |
| Phase 29-pos-mercadopago-qr-din-mico PP02 | 6min | 1 task tasks | 7 files files |
| Phase 29-pos-mercadopago-qr-din-mico P02b | 11min | 2 tasks | 11 files |
| Phase 29-pos-mercadopago-qr-din-mico P03 | 16min | 3 tasks | 12 files |
| Phase 29-pos-mercadopago-qr-din-mico P04 | 20min | 3 tasks tasks | 7 files files |
| Phase 29 P05 | 28min | 3 tasks | 10 files |
| Phase 29 P06 | 30min | 3 tasks | 13 files |
| Phase 29 P07 | 25 | 5 tasks | 8 files |
| Phase 29 P08 | 18min | 2 tasks | 9 files |
| Phase 29 P08b | 8min | 3 tasks | 7 files |
| Phase 29 P09 | 12min | 4 tasks | 11 files |
| Phase 25 P15 | 30min | 2 tasks | 8 files |
| Phase 25-clientes-globales-compartidos-entre-tiendas-historial-aislad P17 | 13min | 2 tasks | 4 files |
| Phase 25-clientes-globales-compartidos-entre-tiendas-historial-aislad P18 | ~25min | 3 tasks | 4 files |
| Phase 32 P01 | 25min | 2 tasks | 2 files |
| Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc P02 | 7min | 3 tasks | 5 files |

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
- Phase 29 added: POS Mercadopago — QR Dinámico (매장 내 QR 스캔 결제, store 단위 OAuth 계정, webhook + Socket.io 자동 Generar Venta, 3분 timeout/수동 취소, 환불은 phase 마지막 plan 에 포함)
- Phase 30 added: POS Mercadopago — Point 단말기 (물리 NFC/카드 단말기 결제, MP Point Smart SDK 연동. Phase 29 의 OAuth/webhook 인프라 재사용)
- Phase 31 added: Online Mercadopago — Phase 27 통합 (Checkout Pro/Bricks 로 온라인 채널 결제. Phase 27 ventas online 의 결제 레이어로 통합. Phase 29 OAuth 토큰/webhook 재사용)
- Phase 32 added: stocks-historial-drawer — Stocks 보고서 row 클릭 → 우측 380px drawer 슬라이드로 productBranch 의 movido/ingreso/fallado/corregido 전체 ledger 를 chronologically 표시 (Phase 12 cockpit drawer 패턴 재현). 2026-05-08 완료.
- **Phase 33 added (retroactive, 2026-05-17)**: Permissions v2 — RBAC + Branch Scope + Approval Threshold + Audit. 8 표준 role + user_branches 다지점 매핑 + approval_thresholds/approval_requests + user_permission_cache (5분 TTL). 운영 사용자 0명 zero-cost window 활용해 점진 마이그레이션 없이 한 번에 교체. 2026-05-14~15 .gsd/spec-permissions-v2.md 기반 49 파일 구현 (backend 4 마이그레이션 + 22 model/service/guard/controller + frontend 13 + docs 9). **현재 verifying**: api-ventago 30 파일 uncommitted + 운영 PG10 runbook 미실행.
- **Phase 34 added (retroactive, 2026-05-17)**: Customer WhatsApp + CRM Routing (Phase 29 Wave C) — clients/global_clients 에 whatsapp 컬럼 추가, Click-to-Chat 이 client.phone 대신 client.whatsapp 으로 라우팅 (strict mode, 422 fallback). "Igual que teléfono" 미러 체크박스 + ClienteVistaView/GlobalClientesView 컬럼+폼+WhatsAppSendDialog 게이팅. 2026-05-13~14 12-task TDD 구현 완료 (api 9 commits + app 3 commits, 모두 push). **현재 verifying**: 정식 UAT 미수행.
- **Phase 36 added (2026-05-23)**: 권한매핑보강+UAT감업 — Phase 35 manual UAT 에서 발견된 운영 적용 차단 사항 해결. (1) `stock.movement` 의 `role_function_actions` 매핑 누락 (Plan 02 마이그레이션 SQL 한계) — 모든 store 의 role × action 일괄 부여 SQL + admin UI 권한 매트릭스 검증. (2) 운영 PG10 RUNBOOK (`35-RUNBOOK-PROD.md`) 작성 — 마이그레이션 순서 / backfill dry-run·실행 / 5건 hotfix 배포 / 롤백 절차. (3) Phase 35 deferred 항목 (U14 movBalance 알람 staging 재검증, U18 MOV+ tooltip) 후속 결정. **현재 pending**: /gsd-spec-phase 36 (완료, 2026-05-23 commit 884c707) → /gsd-discuss-phase 36 / /gsd-plan-phase 36.
- **Phase 36.1 added (2026-05-23)**: Sale branch 필터 + dailyNumber 비-0 회귀 hotfix — (1) REG-1: sales.service.ts:364-369 의 branch 필터가 origin/target_branch_id 만 매칭하여 admin user(branch_id=NULL) 의 sale 행이 ventaVista branch chip 필터에서 누락. fix: sale 의 terminal → box → branch 경유 OR 절 추가. (2) REG-2: movido/fallado 가 INSERT 시점에 daily_number 비-0 부여 (U12b 1차 검증 0 → 후속 2/3/5/6/8). 근본 원인 미파악, 방어적 fix 로 stocks.service.ts 의 Sale.create() 에 `dailyNumber: 0` 명시 + 기존 DB 데이터 UPDATE 복원. **현재 in-progress**: 코드 fix 완료, 사용자 재검증 대기.
- **Phase 33.1 inserted (2026-05-24, URGENT)**: Permissions v2 D1/D2 Hotfix — 2026-05-24 자동 권한 점검(Scenario A/B/F)에서 발견한 P0 결함 2건. (D1) `user-structure.service.ts::ensureRoleFunctions` + `user-registration.service.ts::ensureRoleFunctions` 가 `/me` 호출 시점에 role 의 모든 function 에 대해 `RoleFunction.create(...)` 자동 실행 → bulk-actions 직후 1 row 였던 role_functions 가 /me 직후 11 row 로 복구. 사용자의 명시적 권한 토글과 DB 상태가 분리. (D2) `role-function.service.ts::bulkUpdateRoleFunctionActions` 끝에 `cacheService.invalidateUser` 호출 누락 → `user_permission_cache` 0 rows 로 Phase 33 spec "5분 TTL 캐시" 미작동. **현재 pending**: /gsd-plan-phase 33.1. 근거: `.planning/phases/33-permissions-v2/audit/2026-05-24-automated-verification.md`.

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
- [Phase 26 P04]: Spec under src/app/reports/ (jest rootDir=src) — not under api-ventago/test/ which is outside testRegex
- [Phase 26 P04]: ReportsGastoService constructor adds optional sequelize? param — preserves existing instantiation, NestJS DI auto-wires at runtime, jest mock injects directly
- [Phase 26 P04]: depth='all' = depthLimit=5 (leaf preserved). RECURSIVE CTE uses anc_parent_id chain + DISTINCT ON ORDER BY anc_depth DESC to pick deepest ancestor ≤ depthLimit
- [Phase 26 P04]: Cockpit top-N flat 8-row breakdown preserved unchanged (RESEARCH §6 Q6) — new rollup card is additive
- [Phase 26 P04]: ExpenseModal always sends expensesSubcategoryId=null; categoryId is the source of truth (Wave 5 drop prep)
- [Phase 26 P04]: DataConfig column renderer falls back legacy subcategory string when expenseCategory.path missing — preserves continuity for partial-state rows
- [Phase 29]: [Phase 29 P01]: Plan 01 (Wave 0) — qrcode.react@4.2.0 + 8 MP_* env vars + 3 fixtures + axios mock helper + 2 ops docs. Checkpoint pending (operator must provision real MP Apps + secrets).
- [Phase 29]: [Phase 29 P02]: 7 mp_* tables (PG10/15 compat). Two partial UNIQUE indexes on mp_accounts (PG10 alternative to COALESCE-in-UNIQUE). VARCHAR+CHECK over PG ENUM. Cross-table FKs split-add (mp_movements.refund_id/transfer_id added in 29-04/29-05). Verified clean apply + idempotent re-run + clean rollback on host PG18.
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 02b: DataType.DECIMAL(14,2) used for monetary fields (sequelize doesn't export NUMERIC; PG-side equivalent)
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 02b: AppModule lives at src/app.module.ts (NestJS standard), not src/app/app.module.ts as plan stated
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 02b: MercadopagoModule re-exports SequelizeModule so downstream plans can @InjectModel any of the 7 mp_* models without re-importing
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: @Public() decorator created (api-ventago/src/app/auth/decorators/public.decorator.ts) — no global JWT guard exists yet, but documents intent + future-proof
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: MpOAuthService spec uses positional constructor args (bypassing NestJS DI) — @InjectModel/@InjectConnection are metadata-only
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: MpStorePosService swallows 4xx errors from MP Store/POS POST — already-registered = idempotent success (no separate GET-check needed)
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: AuditOptions.getDescription is (result, body, user) 3-arg — plan example used (params) 1-arg form, fixed to match interface
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: createIntent uses status='failed' UPDATE on MP API failure (rollback path) — preserves audit; Plan 08 cron is backup cleanup, not primary mechanism
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: external_reference = String(intent.id), NOT pendingVentaId (RESEARCH §Architecture) — webhook resolves intent first then walks intent.pending_venta_id
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: notification_url contains ?accountId=N query (RESEARCH §A9) — webhook auth resolves account directly via query if MP preserves URL
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: Spec import order matters — mock-mp-api.ts must be imported BEFORE any axios consumer or jest.mock('axios') is bypassed (real network calls leak through)
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: JSON fixture loaded via require() (CommonJS path) — tsconfig has no resolveJsonModule and adding it project-wide is out of scope
- [Phase 29]: MercadopagoModule imports WebsocketModule (not @Global) — explicit dependency keeps the module graph readable
- [Phase 29]: Webhook controller always returns 200 + setImmediate background processing — MP retry storm avoided; internal failures flow to polling fallback (Plan 04 GET endpoint)
- [Phase 29]: Webhook handler RE-FETCHES MP /v1/payments/{id} as canonical truth (RESEARCH §Pitfall 1 — QR webhooks have NO x-signature; payload is wake-up signal only)
- [Phase 29]: Idempotency proven by SELECT FOR UPDATE intent inside TX + intent.paymentId guard + DB UNIQUE on payment_id (defense in depth — RESEARCH §Pitfall 5/9)
- [Phase 29]: [Phase 29 P06]: literal('branch_id ASC NULLS FIRST') for Sequelize order — typed Order array does not accept NULLS FIRST modifier; literal() bypasses parser
- [Phase 29]: [Phase 29 P06]: Defensive toResponse() helper despite attributes whitelist — defense in depth for T-29-02 token leak mitigation
- [Phase 29]: [Phase 29 P06]: Palette modification deferred (Rule 4 architectural) — existing materio template info/warning colors visually adequate; global change would cascade to 60+ screens, out of scope
- [Phase 29]: [Phase 29 P06]: MP frontend file location src/views/mercadopago/ (NOT src/views/configuracion/mercadopago/) — matches Phase 26 categorias-gastos pattern
- [Phase 29]: PaymentSummaryModal extended with MP QR side-panel + processedIntentRef double-trigger guard + auto-handleSubmit (Plan 07)
- [Phase 29]: Plan 08b: MP wallet rows rendered in adjacent MUI Table inside CashControlList CardFilter (above existing FullTable/DataGrid) — Variant A highlighted-row visual + role-gated buttons + chip don't map cleanly to DataGrid column-renderer model
- [Phase 29]: Plan 08b: Type re-exports from SWR hooks (McdpgWalletRow, McdpgMovementRow) — single-import ergonomics for downstream components (no need to import from both hook + types module)
- [Phase 29]: Plan 08b: useBranch returns plain any[] not paginated {data,total} — defensive shape handling Array.isArray(branches) || (branches as any).data ?? [] avoids future hook-shape regression
- [Phase 29]: Plan 09: refundForSale signature uses sale.id only (lookups mp_payment_intents via pendingVentaId) — SalePaymentMethod has no mpPaymentId column
- [Phase 29]: Plan 09: X-Idempotency-Key=refund-{saleId}-{attemptNo} — same key returns same MP refund record (T-29-06 mitigation), attemptNo increments per user-driven retry
- [Phase 29]: Plan 09: McdpgRefundFailureSection extracted as separate component — keeps SalesDetailView modification surgical (3-line addition + 1 import) and reusable
- [Phase 29]: Plan 09: nullifySale failure path NEVER throws (D-A4-03) — sale always nullified, MP failure surfaces via mpRefundResults/mpRefundFailed flags attached to reversalSale.dataValues
- [Phase 25]: [Phase 25 P15]: findAllScoped 분기 정책 — storeId 명시 시 ownerScope 미호출 (DB pool 절약), null 시 ownerGroup 매장 IN
- [Phase 25]: [Phase 25 P15]: resolveSaleClient — storeClient/globalClient eager 미적재 시 legacy clients 폴백 (호환성 우선)
- [Phase 25]: [Phase 25 P15]: 32 reports services 일괄 ownerGroup 변환 deferred — 운영 single-group 환경 즉시 leak 0, scope.helper.ts 만 추가
- [Phase 25]: [Phase 25 P15]: sales-create storeClientId 자동 추론 — clientId → document → store_clients (Plan 16 ClientsSync 매핑 활용)
- [Phase 25]: Plan 25-17: Backfill 스크립트 dev 검증 완료 (17 synced_new + 10 existing + 13 sales_remapped + 0 errors), idempotent 확인. 운영 적용은 사용자 승인 대기.
- [Phase 25]: Plan 25-17: standalone NestJS script — main.ts 진입점 아니므로 webcrypto polyfill + require.main === module 가드 + getModelToken(Class) 패턴 추가
- [Phase 32]: Phase 32-01: Stocks historial drawer backend — getHistorial service method + GET /reports/stocks-cockpit/historial endpoint with 7-way SQL classification, counterparty branch resolution from movido note pattern, audit_logs JOIN with 'Sistema' fallback. Plan SQL fix (talles/talle_id → sizes/size_id) per actual schema.
- [Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc]: Drawer state owned by StocksCockpitBody (single instance + cross-panel toggle close); same-target re-click closes via prev-target kind+ids comparison
- [Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc]: PanelC cell <td> converted to <Box component=td> sx :hover selector (idiomatic MUI hover-reveal) — fixed plan ambiguity around .MuiBox-root selector on native td
- [Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc]: useStocksHistorial accumulates rows via prevOffsetRef gate (offset==0 replaces, offset>prev appends); loadMore no-op unless data.hasMore=true

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260420-qet | useVariants 토글 — 신상품 등록 화면 단순화 (VariantsStock 조건부 숨김 + cantidad TextField) | 2026-04-20 | 89184d0 | [260420-qet-tienda-admin-usevariants-false-variantss](./quick/260420-qet-tienda-admin-usevariants-false-variantss/) |

## Session Continuity

Last session: 2026-05-07T16:14:34.746Z
Stopped at: Completed 32-02-PLAN.md
Resume file: None
Next: After 26-04-05 approved → Wave 5 (Migration & Cleanup): drop expenses_subcategory_id + expenses_categories/subcategories deprecated tables + verify regression-free run
