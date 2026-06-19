---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: 개선
status: "🟡 ready-for-prod-deploy — 운영 적용 차단 blocker 2건 해소됨 (Phase 36):"
stopped_at: Completed 42-06-PLAN.md (code complete; browser UAT pending)
last_updated: "2026-06-19T16:30:23.818Z"
last_activity: 2026-05-17 (submodule auto-commit)
progress:
  total_phases: 43
  completed_phases: 18
  total_plans: 136
  completed_plans: 119
  percent: 88
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
| Phase 39-modo-restaurante-pos-mesas P01 | 20min | 2 tasks | 6 files |
| Phase 39 P03 | 5min | 1 tasks | 1 files |
| Phase 39 P02 | 4min | 2 tasks | 6 files |
| Phase 39 P04 | 7min | 1 tasks | 3 files |
| Phase 39 P05 | 6min | 3 tasks | 5 files |
| Phase 40 P04 | 9min | 2 tasks | 7 files |
| Phase 40 P05 | 5min | 2 tasks | 7 files |
| Phase 40 P06 | 5min | 2 tasks | 6 files |
| Phase 40 P07 | 5min | 3 tasks | 5 files |
| Phase 40 P08 | 5min | 3 tasks | 4 files |
| Phase 42 P03 | 6m | 3 tasks | 3 files |
| Phase 42 P04 | 12m | 4 tasks | 7 files |
| Phase 42 P05 | 10m | 3 tasks | 9 files |
| Phase 42 P06 | 1 session | 2 tasks | 2 files |

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
- **Phase 39 added (2026-06-13)**: Modo Restaurante — 식당 업종용 테이블 단위 POS 모드. configuración 식당모드 토글 → nueva-venta 가 테이블 배치도(salón) 뷰로 전환. 테이블(원형/긴원/정사각/직사각, 사용자 위치 지정) 클릭 → 웨이터 선택 → categoría·음식·수량 → 주방 전달(comanda) → 주문→음식나옴/음식나옴→소비완료 타이밍 테이블별 기록 → resumen de pago 감열 출력 → 현금/카드/MercadoPago 수금. 외상 없음, 메뉴 단순. **설계 방향(brainstorm 2026-06-13): 재구축 X, 기존 시스템 확장.** sales/sale_items/sale_payment_methods/sellers/print-agent/socket.io/mercadopago/멀티테넌트/CASL/배포 그대로 재사용. 신규 = restaurant_tables + sales 식당 컬럼(table_id+타이밍, nullable) + store_configs 플래그 + 전용 SalonView 프론트. MVP 우선(Slice 1 = 토글+배치도+주문/comanda+resumen 결제+기본 타이밍; KDS 화면·상세 타이밍 리포트는 후속 Phase 후보). **현재 not-planned**: /gsd-spec-phase 39 (미해결: 주방전달 방식 comandera vs KDS, 타이밍 트리거, 메뉴=products 재사용 여부, 배치도 충실도, open-ticket 상태모델) → /gsd-discuss-phase 39 → /gsd-plan-phase 39.
- **Phase 38 added (2026-06-11)**: CodigoMadre QR 감열 출력 — CodigoVista CodigoMadre View parent 행에 QR 출력 버튼 + price-type 선택 Popover → `POST /print/qr` → print-agent(감열) 가 QR(딥링크 URL: storeId+parentProductId) + 코드 + 제품명 + 가격 라벨 출력 (HTML→PNG→printImage, qrcode). 범위 = 데스크탑 QR 출력(Half A) 만. 모바일 스캔→`/m/stock`→크로스 지점 변형 재고 뷰(Half B)는 Phase 37 mobile 편입. 설계: docs/superpowers/specs/2026-06-11-codigomadre-qr-thermal-print-design.md. **현재 not-planned**: /gsd-spec-phase 38 또는 /gsd-plan-phase 38.
- **Phase 40 added (2026-06-16)**: Restaurante Delivery — 식당모드 매장 인터넷 배달 주문 접수·배차·수금 통제. 직원이 WhatsApp·전화·배달앱(PedidosYa/Rappi) 주문을 내부 콘솔로 접수 → 주방(comanda) → 라이더 배차 → 배달 → 수금 → 정산 마감. 핵심: *배달 완료 ≠ 주문 종료*, 현금 contra entrega 는 카하 정산까지 미수금 추적. **설계(brainstorm 2026-06-16): C안 — 신규 delivery 레이어 + 기존 Sale 백본 재사용.** 소매 online-orders 는 도메인 달라 재사용 X. 신규 엔티티 3개(Repartidor, RestaurantDelivery[Sale 1:1], RiderSettlement), 금전·재고·comanda·MP QR·caja·clients 재사용. 화면 4개(설정 Repartidores 카드, 주문 접수 모달, 배차 보드 칸반, 라이더 정산). 수금: MP QR=webhook 자동, 현금=라이더 교대 정산, 배달앱=L1 정산 CSV 대조. 범위밖: 고객 추적링크/배달앱 L2 API/라이더 모바일앱/GPS/외상. 설계: docs/superpowers/specs/2026-06-16-restaurant-delivery-design.md. **현재 not-planned**: /gsd-spec-phase 40 → /gsd-plan-phase 40.
- **Phase 41 added (2026-06-18)**: Soporte Remoto Embebido — 내장 원격 지원(보기 전용 MVP). 고객(매장 운영자)이 Ventago 웹에서 "지원 요청" → 서버가 세션 UUID 발급 → 고객이 UUID 를 지원팀 전달 → 지원팀이 인증 뷰어에서 그 UUID 로 고객 웹 화면(DOM)을 실시간·보기전용 재생. **rrweb DOM 미러링**(영상 코덱 없음, 대역폭 작고 저지연), 지원팀→고객 제어 채널 없음(의도된 보안 제약). **repo 스택 정식화(사용자 초안 조정)**: standalone `ws` 서버/별도 `pg` Pool → **기존 Socket.io 게이트웨이(`/support` 네임스페이스) + Sequelize 싱글턴 pool 재사용**(pool 낭비 0, `pool.connect()` 미사용). 신규 = support_sessions 테이블 + `/support` gateway + 고객 rrweb record 통합 + 지원팀 replay 뷰어(`pages/soporte/visor.tsx`). 보안(R-1..R-6): JWT+permission 게이트 뒤 뷰어 / 15분 만료 / 고객 진행배너+종료버튼 / maskAllInputs+결제·키화면 block / 동시뷰어 1 / store-scope. 범위밖: Flutter POS 화면, getDisplayMedia 픽셀영상, 역방향 입력. SPEC: .planning/phases/41-remote-support-viewonly/41-SPEC.md (Open Q: 뷰어 permission_slug 매핑 / rrweb 이벤트 DB 영속화 여부 / 운영 `/support` CORS). **현재 not-planned, 사용자 보안결정 승인 대기**: 승인 → /gsd-discuss-phase 41 또는 /gsd-plan-phase 41. **2026-06-19 ROADMAP `### Phase 41` 엔트리 소급 백필 완료** (그동안 STATE 진화로그에만 있던 갭 해소). 코드는 2026-06-19 main 통합(기능 플래그 OFF).
- **Phase 42 added (2026-06-19)**: Retail Delivery — Despacho / Cuentas por cobrar / Historial (의류 배송 통제). 식당 delivery 통제 UX(Phase 40)를 의류(비식당) 모드로 이식. **설계 방향(brainstorming 2026-06-19): A안 — 기존 online-orders(OnlineOrder) 백본 재사용 + 식당식 통제 UX 입히기.** 식당이 신규 RestaurantDelivery 를 만든 것과 달리, 의류 배송은 online-orders 가 만들어진 도메인(채널·운송장·택배사·결제상태)이라 데이터 재사용. 부족한 "직관적 통제 경험"만 신규. 신규 = Transporte 모델(CRUD, Correo Argentino/OCA/Andreani/Propia) + OnlineOrder 보강(transporteId·preparedAt/dispatchedAt/deliveredAt) + 외상은 기존 CreditLedger(sale_credit/payment_in/favor) 재사용. 화면 = Ventas Online 페이지 3탭 격상(Despacho 칸반 컬럼별누적+마스터디테일 보드75%/타임라인25% · Cuentas por cobrar 외상통제 · Historial) + 설정 Transporte 카드. 정산축 재해석: 라이더 현금 → 고객 외상(cuenta corriente). 완납후발송 게이트(잔액>0 외상발송 경고), 언제든 부분/split cobro(현금·이체·cheque·tarjeta·QR), 타임라인 Ticket/Recibo/Nota, 취소시 환불/favor. store_config `use_envios`(기본 OFF) 게이트. 범위밖: 반품(nueva-venta). 설계: docs/superpowers/specs/2026-06-19-retail-delivery-despacho-design.md. **2026-06-19 PLANNED — Ready to execute**: /gsd-plan-phase 42 완료 → CONTEXT(설계스펙 기반)+RESEARCH(HIGH conf, 5 pitfalls, Open Q 전부 RESOLVED)+PATTERNS(24파일/22 analog) 생성, **8 plans in 8 waves**(42-01 Transporte CRUD+use_envios 마이그레이션 · 42-02 OnlineOrder 보강+ship 완납게이트(shipSaldo)+cobro(FIFO+caja)+cancel favor · 42-03 [BLOCKING] 마이그레이션 로컬적용+deliver 결제귀속 재정렬(Pitfall1)+RD-12 회귀 · 42-04 /envios 게이트웨이+cuentas-por-cobrar/nota/auth-scoped GET:id(I-1 해소) · 42-05 프론트 foundation · 42-06 3탭+Despacho 칸반+실시간 · 42-07 타임라인+CobroModal+취소favor+NuevoEnvio · 42-08 Cuentas/Historial+검증). plan-checker VERIFICATION PASSED(revision 1회: 결제귀속 시점 정렬+백엔드 라우트 소유권+useEnviosHistory sibling). 다음: /gsd-execute-phase 42.

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
- [Phase 39-modo-restaurante-pos-mesas]: [Phase 39 P01]: use_restaurant_mode DEFAULT false (기존 use_* default true 와 차별 — 소매 무영향). restaurant_category_ids JSONB nullable.
- [Phase 39-modo-restaurante-pos-mesas]: [Phase 39 P01]: 순환 FK(sales.tableId ↔ restaurant_tables.currentSaleId)는 constraints:false BelongsTo + 마이그레이션 분리(39-01 current_sale_id, 39-02 table_id)로 회피. 신규 sales 컬럼 전부 nullable → 소매 회귀 0.
- [Phase 39-modo-restaurante-pos-mesas]: [Phase 39 P01]: last_comanda_at 신규 컬럼으로 comanda 증분 경계 확정 (39-RESEARCH Open Q2 해소). pos_x/pos_y REAL 정규화 0~1 (D-08).
- [Phase 39]: [Phase 39 P02]: findScoped() private 헬퍼로 update/updatePosition/remove 스코프 조회 통일 (IDOR 방지 단일 지점). syncTableStatus 는 39-03 이 이미 로드한 RestaurantTable row + options.transaction 재사용.
- [Phase 39]: [Phase 39 P02]: findByBranch 단일 SELECT(sales JOIN 금지) — pool 절약. DTO posX/posY @Min(0)@Max(1) + shape/status @IsEnum + DB CHECK 이중 방어. module exports 에 SequelizeModule 추가(Sellers 선례).
- [Phase 39]: [Phase 39 P04]: update() 도 findOrCreateByStoreId 경유로 보강 — 토글/설정 저장 경로(update-flag 포함)는 store_config 행 부재 시 자동 생성, GET(findByStoreId)은 NotFound 유지. useRestaurantMode 화이트리스트 @Patch+@Put 두 곳 모두 추가.
- [Phase 39]: [Phase 39 P05]: payMerge 배분 = 각 sale 자기 totalAmount 1행 결제(비율 배분 아님) — integer 정확 일치 + D-03 매출 귀속 보존. grand-total ΣtotalAmount 단일 검증.
- [Phase 39]: [Phase 39 P05]: 식당 결제 box-operation = recordBoxOperation(cashRegister closingTime=null findOne → addOperation(data,t) 위치 transaction). 미오픈 시 소매와 동일 스킵. RestaurantTable+CashRegister sales.module forFeature 등록.
- [Phase 39]: 39-07: placeOrder totalAmount 동기화(백엔드)로 결제 검증 통과 보장 + GET :id 조회 라우트 추가 (39-05 갭 해소)
- [Phase 40]: 40-04: qr 배달 주문 접수 시 MpPaymentIntent(pendingVentaId=sale.id)를 TX 커밋 후 생성 — plan 06 webhook가 intent.pendingVentaId로 delivery 자동 종료(REQ-8). Entregado는 Sale PAID이나 efectivo는 box-op 없이 por_cobrar 잔류(D-01/D-05, 정산은 plan 06).
- [Phase 40]: 40-06: QR 배달 자동 종료 hook은 intent.pendingVentaId(=delivery.saleId, plan04)로 delivery 조회 — 기존 intent-centric webhook은 saleId로 Sale을 안 찾으므로 linkage는 intent→delivery. post-commit + try/catch로 webhook 200 불변식+wallet-credit TX 무변경(additive).
- [Phase 40]: 40-06: L1 payout CSV = MinIO 원본 보관(D-07) + 고정 헤더(external_ref,amount) 검증 + sales.total_amount 정확 매칭(tolerance 없음, 센트반올림 정수비교). conciliacion 상태만 liquidado flip(T-40-22), storeId 스코프(T-40-21), 타입/크기/헤더 선검증(T-40-20).
- [Phase 40]: 40-07: RepartidoresCard는 use_restaurant_mode 이중 게이트(카드 내부 return null + RestauranteConfigView enabled 블록 내 렌더)로 소매 매장 노출 차단(T-40-25). NuevoPedidoModal은 OrderModal 메뉴 picker 재사용 + takeaway는 주소/라이더를 payload에서 제외(숨김 아님). useDeliveryBoard는 폴링 없이 Socket.io push 병합 대상.
- [Phase 40]: 40-08: DeliveryBoard는 base host + /restaurant 네임스페이스 Socket.io(auth.token=accessToken)로 delivery_updated 카드를 mutateRef 기반 functional updater로 SWR 캐시에 병합(폴링 없음). Por cobrar 컬럼 RED는 현금 미정산 통제 가시화. RestauranteShell이 Salón(기본)/Delivery/Liquidación을 next/dynamic ssr:false로 code-split하여 nueva-venta 식당모드 분기에 마운트(소매 VcontrolHome 무변경). 코드 완료, 블로킹 human-verify UAT 보류.
- [Phase 42]: 42-03 (executing, done 2026-06-19, feat/phase42-wave1) **[BLOCKING wave]**: 마이그레이션 로컬 적용 + deliver 결제귀속 재정렬(Pitfall 1) + RD-12 회귀 게이트. (1) **마이그레이션 3개 로컬 PG18 적용**(42-01 transportes + 42-03 use_envios 멱등 no-op + 42-02 online_orders prepared_at/dispatched_at/transporte_id 실적용 count 0→3) → BLOCKING 스키마검증 SCHEMA_OK(운영 PG10 미적용). (2) **deliverOrder**: 무조건 `paymentStatus=PAID` 제거 → `shipSaldo<=0 ? PAID : 유지`(부족분 외상 Cuentas por cobrar 노출). mirror.id 생성 직후 `shipSaldo>0 && isNewMirror(order.mirrorSaleId==null)` 일 때만 sale_credit 1건 누적(amount=shipSaldo, saleId=mirror.id, 동일 SERIALIZABLE deliver tx t — 새 pool 없음, 멱등 가드로 재-deliver 중복 차단). UPDATE/DELETE ledger 금지. (3) **createMirror**: optional `receivedAmount` 3번째 인자 → sale_payment_methods.amount=실수령액(total−shipSaldo), 미지정 시 totalAmount(완납 회귀-0). 불변식 SaleSource.ONLINE/SaleActivityType.SALE/online_order_id UNIQUE/dailyNumber 보존. (4) spec: 완납/부족분/멱등 deliver 3건 추가, online-orders jest 13/13 PASS(credit/box 독립 spec 부재 → online-orders 스위트가 mock 통합 커버). 커밋 9dda6e4(api-ventago submodule). (out-of-scope: no-unsafe-* eslint pre-existing 24건 baseline, 신규 0건 — nest build SWC 게이트 무관).
- [Phase 42]: 42-02 (executing, done 2026-06-19, feat/phase42-wave1): OnlineOrder 보강 + ship 완납게이트 + cobro + cancel favor. **ship 은 metadata.shipSaldo 에 외상 의도만 기록** — sale_credit ledger 행은 deliver(42-03)에서 mirrorSaleId 기준 누적(RESOLVED Pitfall-1 seam, ship 에서 appendMovement 호출 X). shipOrder(userId): transporte.name 미러(D-05) + dispatchedAt + saldo>0 시 익명 차단(Pitfall 2) + assertCreditEligible(positional sig, 동일 tx). prepareOrder→preparedAt(Listo 파생, D-03, 신규 enum 없음). registerCobro: split payments → registerPayment(credit_payment FIFO, 자체 tx 중첩 X/Pitfall 3) + 줄별 caja addOperation + 열린-caja 미오픈 차단(Pitfall 4). cancelOrder(refundAction): devolver=caja 역 movement / favor=appendMovement favor_in, 기존 reverseSale+nullifyMirror 보존(RD-12). computeReceivedSoFar: metadata.received 우선 / paymentStatus=paid→total / else 0. transportes.findScoped private→public. OnlineOrdersModule→CreditModule/BoxOperationModule/TransportesModule import(싱글턴 재사용). transporteId plain INTEGER(boot-hang guard). 마이그레이션 42-02 미적용(42-03 이 순서대로). online-orders.service jest 10/10 PASS. 커밋 6179da1/fcc6d74/9a0d143. (out-of-scope: mp-webhook spec TS2554 2건 pre-existing→deferred-items.md)
- [Phase 42]: 42-01 (executing, done 2026-06-19, feat/phase42-wave1): Transporte = Repartidor(Phase 40) 1:1 복제하되 phone 제외(D-04 스코프 {id,storeId,name,isActive}). store-scoped CRUD(findByStore activeOnly 단일 SELECT pool 절약 + findScoped NotFoundException IDOR 가드 + soft-toggle isActive, hard-delete 없음), 모든 라우트 @Auth() + storeId @GetUser 전용. use_envios = useRestaurantMode(39-03) 패턴 미러 default false → 기존 매장 자동 OFF(RD-12). 마이그레이션 2개(42-01-transportes.sql SERIAL/snake_case/IF NOT EXISTS, 42-03-store-config-use-envios.sql)는 **미적용** — 42-03 BLOCKING task 에서 42-02 online_orders FK 컬럼과 순서 맞춰 로컬 적용 후 운영 PG10 런북. TransportesModule exports [TransportesService] → 42-02 online-orders 가 ship 시 transporte.name 미러(D-05) 소비. jest 5/5 PASS. 백엔드 eslint 는 analog 동일 패턴(빌드 게이트 아님 — NestJS/SWC).
- [Phase 42]: 42-04: /envios Socket.io gateway (domain-separated from /restaurant, /print-agent) — JWT handshake + branch-room IDOR guard; post-commit envio_updated emits on all transitions+cobro (never inside tx)
- [Phase 42]: 42-04: GET /online-orders/:id replaced simple detail with auth-scoped merged-timeline (I-1 PII fix); read-side routes board/:branchId + cuentas-por-cobrar (RD-7 source) + :id/nota owned in backend
- [Phase 42]: 42-05 (done 2026-06-19, feat/phase42-wave1): 프론트 envíos foundation. useEnvios StoreConfig 플래그(default false, fetched+memoized)로 despacho 머신 전체 게이트. SWR 훅 3개(useTransportes 5분 dedup, useDespachoBoard branchId null-key+폴링없음 D-11, useCuentasPorCobrar 5분 dedup). envioLabels(canal/columnKey status/payment 라벨+hex 색, saldo>0 빨강). TransporteCard=RepartidoresCard clone(phone 제거)+useEnvios 게이트+soft toggle(put isActive, remove 없음)+이중 에러(Alert+toast). EnviosConfigView+/configuracion/envios 페이지(토글). **deviation: cuentas per-client 잔액 필드=clientBalance(42-04-SUMMARY 권위 계약), plan 본문의 balance 아님 — clientBalance 매핑.** **Rule3: storeConfig update-flag 화이트리스트에 useEnvios 추가(없으면 토글 400 → 카드 영구 도달불가).** 8 frontend 파일 eslint exit0, storeConfig.controller jest 5/5 PASS. 커밋 20ee42b/e054609/edc9ca9(ventago-app)+536521b(api-ventago).
- [Phase 42]: 42-06 (code complete 2026-06-19, browser UAT pending, feat/phase42-wave1): Ventas Online 3탭 격상 + Despacho 칸반 + 실시간 /envios 소켓 + master-detail 셸. **useEnvios 게이트(RD-12 #1 회귀-0)**: true→EnviosControlCenter(Despacho/Cuentas por cobrar/Historial), false→LegacyVentasOnline(Phase27 Pedidos/Envíos/Devoluciones 원본 verbatim 추출, 레거시 코드경로 일절 미변경). **DespachoBoard**(DeliveryBoard clone, 의류 매핑): 5컬럼(nuevo/preparando/listo/en_transito/entregado) columnKey 그룹핑+count 배지+세로스택. /envios Socket.io 구독(envio_updated → mutateRef 함수형 병합 id 교체, false revalidate 없음, 폴링 0 D-11, cleanup off+disconnect, deps=[branchId]만 — cards 변경마다 재연결 X). 카드: orderNumber/canalLabel/clientName/address/total/paymentStatus 칩(saldo>0 빨강)/transporte+tracking 칩/Saldo $X 빨강 배지. master-detail 75/25: 카드 선택→우측 패널, EnvioTimeline 자리는 inline placeholder(42-07). Despachar(listo): activeOnly transporte 드롭다운+tracking → PATCH /online-orders/:id/ship, saldo>0 외상발송 완납게이트 경고 Alert(despachar con saldo/외상으로 발송). 코드스플릿 next/dynamic ssr:false. **stub(plan 지시, 42-07/08 파일 충돌 회피)**: Cuentas/Historial 탭=inline 'Cargando…' placeholder(42-08), 타임라인=inline dashed container(42-07) — 신규 stub 파일 미생성. 2파일 eslint exit0 + tsc 무에러. 커밋 6034965(DespachoBoard)+81598f3(VentasOnlineView)(ventago-app submodule, fix/pos-precio-base-fallback 브랜치 — 42-05 frontend 와 동일 위치). **browser UAT PENDING**: 3탭 렌더/실시간 소켓 무새로고침/외상게이트/use_envios=false 레거시 무회귀(5 step).

### Pending Todos

None yet.

### Blockers/Concerns

- **[39-03 Task 2 — blocking human-action checkpoint]** print-agent `print_temp` 핸들러 코드는 머지됨(9f1339d). 운영 print-agent 가 신규 빌드를 받으려면 `push-both.sh` 로 CI 재빌드(GitHub Actions `build-print-agent.yml`) + 운영 PC 재설치 필요 (사용자 액션 — 실행자가 트리거하지 않음). 미완 시 운영 comanda/resumen 출력 무동작. dev(`npm run dev:print`)는 최신 코드 즉시 반영되므로 39-07 dev 검증은 가능.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260420-qet | useVariants 토글 — 신상품 등록 화면 단순화 (VariantsStock 조건부 숨김 + cantidad TextField) | 2026-04-20 | 89184d0 | [260420-qet-tienda-admin-usevariants-false-variantss](./quick/260420-qet-tienda-admin-usevariants-false-variantss/) |

## Session Continuity

Last session: 2026-06-19T16:30:23.806Z

**Phase 40 planned (2026-06-16):** gsd-plan-phase 40 — research 생략, pattern-mapper(40-PATTERNS.md) → gsd-planner 8개 PLAN.md(6 wave, 커밋 7d3da0e) → plan-checker 1차 ISSUES(blocker: 40-06 webhook 경로 오류, warning: QR intent 링크·CSV 템플릿) → 수정(40-04/40-06, 커밋 f2d2cbf) → plan-checker 2차 PASS. REQ-1~9 전부 커버. 다음=`/gsd-execute-phase 40`.

---
*(이전 세션)*

Stopped at: Completed 42-06-PLAN.md (code complete; browser UAT pending)
Resume file: None
Next: (Phase 39 잔여) Jenkins 배포완료 후 운영 /sellers vs /sellers?excludeAdmins=true 검증 + 운영 PC print-agent v1.0.8 재설치 + 브라우저 UAT(식당+소매 판매원 귀속). (다음 phase) `/gsd-plan-phase 40` — 식당 delivery 레이어(Repartidor/RestaurantDelivery/RiderSettlement + 화면 4개), 40-SPEC/40-CONTEXT 완료됨.
