# SPEC: Phase 57 — 메뉴 재구성 + Admin "Centro de Control" 대시보드
생성일: 2026-07-16
상태: PLAN (사용자 승인 대기)
근거 문서: ACE구조점검분석보고서/제안서(2026-07-15) + mockup 아티팩트 `ventago-menu-restructure-mockup`

## 목표
1. 사이드바 메뉴를 사용자 머릿속 모델("돈/조직/설정")과 일치시킨다 — Tesorería 신설, VentaVista 개명 복귀, Configuración 단일 허브, menuRegistry 단일 소스화.
2. admin Dashboard를 "환영 카드"에서 **예외 관제 센터(Centro de Control)**로 바꾼다 — 관리자가 아침에 1화면으로 "오늘 손대야 할 이상 징후"를 전부 본다.

## 설계 철학 (Dashboard)
- **관리는 예외로 한다(Management by Exception)**: 평균·합계 같은 vanity 지표가 아니라 "정상 범위를 벗어난 것"만 띄운다. 이상이 없으면 화면이 조용한 것이 정상.
- 모든 알림 카드는 **클릭 시 해당 업무 화면으로 딥링크** (알림 → 조치 동선 1클릭).
- 심각도 3단계: 🔴 즉시 조치 / 🟡 오늘 중 확인 / 🔵 참고.

## 배경 및 컨텍스트
- 현행 admin dashboard: `views/dashboards/admin/` — CardWelcome, CardStatistics, CardLastAudit 3장뿐 (사실상 빈 화면).
- 메뉴: `navigation/vertical/index.ts` 391줄 4겹 패치워크 (07-15 보고서 검증 완료).
- 운영 로그(2026-07-16): 신규 에러 없음. 기지 이슈 2건(ShopReadonlyDb pw — 별건, GoogleDrive env 미설정 — 의도됨).
- Phase 번호: 50~56 사용/예약 확인(.gsd 실측) → **57**.

## 기술 스택
- 백엔드: NestJS 11 + Sequelize (기존 pool min=10/max=80 공유 — **신규 pool 생성 절대 금지**)
- 프론트: Next.js 13 + MUI 5, SWR (`src/hooks/api/`), next/dynamic 코드 스플리팅
- DB: PostgreSQL 18 (로컬 5432 / 운영 5434) — 마이그레이션 **양쪽 동시 적용** + `OWNER TO coolsistema` (테이블+시퀀스)
- ESLint: ventago-app 루트 설정 (Warning=에러, newline-before-return / lines-around-comment 주의)

---

## Wave 57-A — menuRegistry 단일 소스화 (화면 무변경)
- [ ] TASK-A1: `src/navigation/menuRegistry.ts` 신설 — 항목·순서·아이콘·subject·role 조건을 선언적 배열 1개로. DB 시드는 접근 권한만 담당 — 파일: `ventago-app/src/navigation/menuRegistry.ts`
- [ ] TASK-A2: `vertical/index.ts`를 레지스트리 소비자로 교체 (hiddenModuleUrls/순서배열 4벌/아이콘맵 2벌 → 레지스트리로 흡수) — 파일: `ventago-app/src/navigation/vertical/index.ts`
- [ ] TASK-A3: 스냅샷 검증 — role별(superadmin/admin/gerente/vendedor/envio_manager) 현행 렌더 결과와 100% 동일함을 확인하는 테스트 스크립트
- [ ] TASK-A4: ESLint 검증 (`npx eslint src/navigation --fix`)

**게이트: A 완료 + 스냅샷 통과 전에는 B 시작 금지 (화면 변경과 구조 변경을 분리)**

## Wave 57-B — 메뉴 표시 변경 (한 번의 릴리스로 묶음)
- [ ] TASK-B1: Tesorería 그룹 신설 (Caja / Control de Caja / Cheques 이동) — 파일: `menuRegistry.ts`
- [ ] TASK-B2: VentaVista → "Historial de ventas" 개명 + Ventas 그룹 복귀 (hidden 해제) — 파일: `menuRegistry.ts` + 마이그레이션(modules.name UPDATE)
- [ ] TASK-B3: Configuración 단일 허브 — `/configuracion` 인덱스 페이지 신설, General(Preferencias·Integraciones·Permisos) / Operación(Ventas·Productos·Envíos·Inventario) / Avanzado(Generar Token·Importar Legacy) 3섹션 탭. 각 탭은 기존 페이지 컴포넌트 재사용 + next/dynamic lazy load. 구 URL → 허브 탭 리다이렉트 1~2주 유지 — 파일: `pages/configuracion/index.tsx`
- [ ] TASK-B4: CASL subject `facturacion` 신설 마이그레이션 (functions/role_function_actions 시드 — vendedor 제외) + 메뉴 subject 교체 — 파일: `api-ventago/migrations/20260716-phase57-facturacion-subject.sql`
- [ ] TASK-B5: 아이콘 시드 tabler 일괄 UPDATE 마이그레이션 → 오버라이드 맵 제거 — 파일: `api-ventago/migrations/20260716-phase57-menu-seed-cleanup.sql`
- [ ] TASK-B6: 직원 공지 1장 (스크린샷 + "메뉴가 이렇게 이동했습니다" ES) — 파일: `docs/aviso-menu-2026-07.md`

## Wave 57-C — Admin Alerts 집계 API (백엔드)
- [ ] TASK-C1: `AdminDashboardModule` 신설 — `GET /dashboard/admin/control-center` **단일 집계 엔드포인트**. 위젯별 개별 API 금지(프론트 10회 호출 → 1회). 내부는 `Promise.all()` + 각 쿼리 LIMIT/인덱스 필수 — 파일: `api-ventago/src/app/dashboard-admin/`
  - ★ 이 API는 **Phase 52(Store Manager Mobile App)의 관제 화면 데이터 소스로 재사용**된다 (실행 순서 57 → 52). 응답 스키마는 모바일 재사용을 전제로 설계: 위젯별 독립 키 + severity 필드 + 딥링크 경로 포함, 웹 전용 가정 금지. 관련: `.gsd/spec-phase52-manager-mobile.md`.
- [ ] TASK-C2: `MemoryCacheService` 30초 TTL 적용 (storeId 키) — 동시접속 500명이어도 DB 부하는 30초당 1회
- [ ] TASK-C3: 각 감지 쿼리 구현 (아래 「위젯 카탈로그」의 SQL 스케치 기준, 컬럼은 `.planning/intel/db-schema-tables.md` 재확인)
- [ ] TASK-C4: slow query 검증 — 각 쿼리 EXPLAIN, 100ms 초과 시 인덱스 추가(CONCURRENTLY + OWNER)
- [ ] TASK-C5: SessionGuard + CASL(admin) 적용, vendedor 접근 차단

## Wave 57-D — Centro de Control UI (프론트)
- [ ] TASK-D1: `useAdminControlCenter` SWR 훅 — refreshInterval 60s, `document.visibilityState !== 'visible'` 시 폴링 중단 (07-15 보고서 2-5 규약) — 파일: `src/hooks/api/useAdminControlCenter.ts`
- [ ] TASK-D2: 상단 KPI 스트립 (오늘 매출 / 열린 Caja 수 / 미수 총액 / 만기 임박 수표 합계 / 오프라인 프린터 수)
- [ ] TASK-D3: 알림 피드 (심각도 정렬, 카드 클릭 → 딥링크) + "이상 없음" 빈 상태 디자인
- [ ] TASK-D4: 도메인 위젯 6종 (위젯 카탈로그) — 각 위젯 next/dynamic + 스켈레톤
- [ ] TASK-D5: ESLint + 빌드 검증 (`docker compose build` 통과)

## Wave 57-E — REVIEW
- [ ] TASK-E1: 마이그레이션 로컬 5432 + 운영 5434 양쪽 적용·스키마 대조 (운영 적용은 사용자 승인 게이트)
- [ ] TASK-E2: 운영 배포 후 마지막 로그 확인 (combined-*.log 신규 에러 0)
- [ ] TASK-E3: pg_stat_statements에서 control-center 쿼리 mean < 100ms 확인
- [ ] TASK-E4: pool 점검 — 신규 pool 0개, 커넥션 점유 패턴 변화 없음

---

## 위젯 카탈로그 (관리자가 보고 싶은 것 — 근거 테이블 실측 완료)

### 🔴 W1. Caja 이상 감지 (→ /caja, /control-de-caja)
| 감지 | 로직 (테이블: boxes, box_operations, sales) |
|---|---|
| 미마감 Caja | `boxes.status` 열림 상태로 영업 종료 시각 경과 |
| 당일 차액 | box_operations 입출금 합계 vs 해당 지점 판매 결제 합계 불일치 (지점은 `user_id → users.branch_id` 경유 — sales에 branch_id 없음 주의) |
| 비정상 시간대 조작 | 영업시간 외 box_operations 발생 (type/execution_type별) |
| 큰 금액 출금 | 임계값 초과 EGRESO 1건 즉시 표시 |

### 🔴 W2. 외주(Talleres) 병목 (→ /talleres)
| 감지 | 로직 (테이블: talleres_envios, talleres_lotes) |
|---|---|
| 기한 초과 벤더 | `talleres_envios.due_date < now() AND pending_quantity > 0` — 벤더별 집계, 초과일수 정렬 |
| 정체 로트 | `talleres_lotes.status` 비종결 AND `updated_at` N일 무변동 (에타파에 갇힌 로트) |
| 미결 정산 | liquidaciones 미지급 합계 (벤더 신뢰 관리) |

### 🔴 W3. 자재 고갈 예측 (→ /materia-prima/inventario)
| 감지 | 로직 (테이블: mes_materials, mes_material_movements) |
|---|---|
| 최소재고 미달 | `current_stock < min_stock AND is_active` |
| 소진 D-day 예측 | 최근 30일 소비 속도(movements) ÷ current_stock → **D-7 이내 고갈 예상** 자재. 진행 중 work_orders의 BOM 소요량 반영 시 정확도↑ (2차 고도화) |
| 발주 리드타임 경고 | supplier 기본 리드타임보다 D-day가 짧으면 🔴 승격 |

### 🔴 W4. 미수금 연체 (→ /cuentas-corrientes)
| 감지 | 로직 (테이블: credit_ledger) |
|---|---|
| 연체 고객 Top N | `bucket_after > 0 AND due_date < now()` — store_client별 잔액·경과일 |
| 한도 근접 | 신용 한도 대비 잔액 비율 상위 |
| 부실 징후 | 최근 60일 입금(credit_payments) 0건 + 잔액 보유 고객 |

### 🟡 W5. 정체 Envío (→ /ventas-online)
| 감지 | 로직 (테이블: online_orders) |
|---|---|
| 미발송 정체 | `confirmed_at NOT NULL AND dispatched_at IS NULL AND confirmed_at < now()-interval '2 days'` |
| 재고 홀드 장기화 | `stock_held_at NOT NULL AND stock_released_at IS NULL` 장기 건 (재고 잠김) |
| 결제 대기 방치 | `payment_status` 미결 + 생성 N일 경과 |
| 배송중 무소식 | `dispatched_at` 후 N일간 `delivered_at` NULL (tracking_code 있음) |

### 🟡 W6. 수표(Cheques) — 보유 카르테라 + 리스크 (→ /cheques)
운영 실태: 수취 수표는 주로 **외상(gastos/공급처) 지불에 배서**로 사용 → 헤드라인은 "지금 보유 중인 수표 수량·금액 = 지불 여력".
| 감지 | 로직 (테이블: cheques) |
|---|---|
| **보유 현황 (헤드라인)** | `status='en_cartera'` COUNT + SUM(amount) — "N장 · $합계 = 배서 가능 지불 여력" |
| 만기 구간 분포 | en_cartera를 이번 주 / 다음 주 / 이후 3구간으로 due_date 분포 (배서 계획용 — 만기 가까운 것부터 배서 우선 후보 표시) |
| 이번 달 배서 실적 | endosado 상태 전환 건수·금액 (외상 지불에 쓰인 흐름 확인) |
| 부도 발생 | `rejected_at` 최근 발생 건 🔴 즉시 |
| 장기 정체 | 수취 후 N일 경과, 미예치·미배서 (카르테라에 잠든 수표) |

### 🟡 W7. 운영 인프라 (→ /sucursales/[id]/impresora, admin)
| 감지 | 로직 |
|---|---|
| 프린터 에이전트 오프라인 | `branch_agents.is_online = false` (thermal/zebra 구분) — 매장 영수증 출력 불능은 즉시 장애 |
| sync_outbox 적체 | `status='pending'` 건수 임계 초과 (2-3 부분 인덱스 활용) |
| 오래된 판매 보류 | `ventas_suspendidas.created_at < now()-interval '7 days'` — 잠긴 hold 재고 회수 후보 |
| 세션 보안 이벤트 | 신규 IP/디바이스 등록 대기, 최근 차단된 중복 로그인 (terminal_devices, branch_ip_registries) |

### 🔵 W8. 매출 맥박 (참고 지표 — 유일한 "정상 지표" 위젯)
- 오늘 지점별 매출 vs 최근 4주 같은 요일 평균 → ±30% 이탈 지점만 강조
- 시간대별 판매 스파크라인 (오늘 vs 평균)

**후순위(2차) 아이디어**: AFIP 발행 실패 건, 가격 미설정 신상품, 직원 출결 이상(attendance), 잘 팔리는데 완제품 재고 부족(판매속도 대비 stocks), 반품(online_returns) 급증 감지 — Phase 57 범위 밖, 카탈로그에만 기록.

---

## 완료 기준
- ESLint 오류 0개 + `docker compose build` 통과
- 스냅샷 테스트: Wave A 이후 role 5종 메뉴 렌더 결과 무변화
- control-center 응답 p95 < 300ms (캐시 히트 시 < 20ms), 각 쿼리 mean < 100ms
- 신규 pool 0개 / 위젯별 개별 API 0개 (단일 집계 엔드포인트만)
- 마이그레이션 로컬+운영 양쪽 적용 + 스키마 대조 통과 + OWNER coolsistema
- 메뉴 변경 릴리스에 직원 공지 1장 동봉

## 금지사항 / 주의사항
- **빅뱅 금지**: Wave A(구조)와 B(표시)를 한 커밋에 섞지 않는다. B는 한 번의 릴리스로만.
- **DB 시드 삭제 금지**: 숨김은 레지스트리에서 (FK/CASL 파손 방지 — hiddenModuleUrls 전례).
- **sales.branch_id 없음** — 지점 도달은 `user_id → users.branch_id` (CLAUDE.md 혼동 방지 규칙).
- 프론트 setInterval 신규 도입 금지 — SWR refreshInterval + 탭 비활성 중단만.
- 운영 DDL/DML은 사용자 승인 후 실행 (SQL + 예상 영향 행수 제시).
- restaurant 관련 설정은 허브에 넣지 않음 (실사용 테넌트 확인 전).
- 컬럼명은 추측 금지 — `.planning/intel/db-schema-tables.md` 참조 후 작성.
