# PLAN: Phase B — Adelanto(가불) 요청·승인·급여차감
생성일: 2026-07-14 · SPEC: `.gsd/spec-attendance-hours-adelanto.md`

## 결정 (LOCKED)
- 승인권자 = **관리자(admin/superadmin) + 지점장(gerente)**.
- 금액 한도 = **없음** (승인 시 관리자 재량).
- 차감 월 = **승인 시 관리자가 payroll_period(YYYY-MM) 지정**.
- 급여 계산 안 함(D3): 시스템은 근무시간 + 승인 adelanto 합계 차감만 표시. 통화 = 매장 통화(별도 컬럼 없이 금액만).

## 데이터 모델 — 신규 테이블 `seller_adelantos`
| 컬럼 | 타입 | 비고 |
|---|---|---|
| id | serial PK | |
| seller_id | int FK Sellers | 요청 판매원 |
| store_id | int FK | 멀티테넌트 격리 |
| branch_id | int NULL | 참고용(요청 시점 지점) |
| amount | numeric(12,2) NOT NULL | 가불 금액 |
| status | varchar(12) default 'pending' | pending/approved/rejected |
| note | text NULL | 판매원 사유 |
| requested_by_user_id | int | 요청자(=seller linked user) |
| requested_at | timestamptz default now() | |
| decided_by_user_id | int NULL | 승인/거절자 |
| decided_at | timestamptz NULL | |
| decision_note | text NULL | 거절 사유 등 |
| payroll_period | varchar(7) NULL | YYYY-MM, 승인 시 지정 |
| created_at/updated_at | timestamptz | Sequelize timestamps |

- 인덱스: (store_id, status), (seller_id), (payroll_period).
- **마이그레이션**: 로컬 5432 + 운영 5434 동시. 끝에 owner+시퀀스 coolsistema 이전 DO블록 (CLAUDE.md 규칙). 파일 `api-ventago/migrations/<날짜>_seller_adelantos.sql`.

## API (api-ventago) — 신규 모듈 `adelanto/` (또는 attendance 확장)
판매원(모바일, AuthGuard jwt + seller 해석):
- `POST /mobile/adelanto` `{amount, note?}` → pending 생성(seller=linked_user_id, 미연결 NOT_A_SELLER).
- `GET /mobile/adelanto` → 본인 요청 목록(상태 포함).

관리자/지점장(@Auth admin, superadmin, gerente):
- `GET /adelanto?status=&payrollPeriod=&branchId=` → 목록(store_id 격리, gerente는 본인 지점만 옵션).
- `PATCH /adelanto/:id/approve` `{payrollPeriod: 'YYYY-MM'}` → status=approved, decided_by/at, payroll_period. store_id IDOR 가드.
- `PATCH /adelanto/:id/reject` `{note?}` → status=rejected.
- `GET /adelanto/summary?month=YYYY-MM&branchId=` → 판매원별 승인 adelanto 합계(payroll_period=month). 리포트 조인용.

## 리포트 연동
- `AttendanceReport` row에 `adelantoDeducted`(해당 payroll_period 승인 합계) 추가 — report 쿼리에 LEFT JOIN LATERAL 또는 별도 summary 호출 후 프론트 병합.
- Asistencia UI: 근무시간 열 옆에 "Adelanto (mes)" 열. 기간(Rango) 모드는 payroll_period가 월단위이므로 월 리포트에서만 차감 표시(기간모드는 근무시간만).

## 프론트 (ventago-app)
- Asistencia에 **Adelantos 탭** 추가: pending 목록 + [Aprobar](월 선택 다이얼로그) / [Rechazar]. 승인 시 payroll_period 지정.
- Horas 탭(월 모드): 판매원 행에 승인 adelanto 합계 표시.
- 훅: `useAdelantos(params)`, `useAdelantoSummary(month)`. apiConnector 사용.

## 앱 (mobile-sales-app)
- "Solicitar adelanto" 화면: 금액 입력 + 사유(note) → `POST /mobile/adelanto`. 성공 토스트.
- 본인 내역 리스트(pending/approved/rejected + payroll_period). 홈 메뉴/버튼에서 진입.

## 태스크
- [ ] B1 마이그레이션 seller_adelantos (로컬 5432 + 운영 5434, owner coolsistema)
- [ ] B2 API 모바일 POST/GET /mobile/adelanto (seller 생성/본인목록)
- [ ] B3 API 관리자 GET /adelanto + PATCH approve(payrollPeriod)/reject (guards admin/superadmin/gerente + IDOR)
- [ ] B4 API GET /adelanto/summary?month (판매원별 승인 합계) + report 연동
- [ ] B5 Front Asistencia Adelantos 탭(승인/거절/월지정) + Horas 차감 표시
- [ ] B6 App Solicitar adelanto 화면 + 본인 내역
- [ ] B7 검증: 모바일 요청 → 관리자 승인(월 지정) → 리포트 해당 월 차감 표시. tsc+jest+ESLint+analyze. 배포(Jenkins 수동).

## 완료 기준
판매원이 앱에서 가불 요청 → 관리자/지점장이 월 지정해 승인 → Asistencia 해당 월 리포트에 판매원별 "근무시간 + 가불 차감" 표시.

## 참고
- IDOR/store_id 격리 필수(멀티테넌트). gerente 지점 범위 확인.
- 배포는 수동 Jenkins([[project_deploy_manual_jenkins]]). 마이그레이션 운영 5434 수동 적용.
